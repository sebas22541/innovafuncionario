import { cert, getApps, initializeApp } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import type { Pool } from "pg";

import { uploadBufferToCloudinary } from "../../../cloudinary/upload.ts";
import { HttpError } from "../../../http-error.ts";

const USER_LINK_TYPES = ["ITEM", "EVENTUAL", "CONSULTOR", "SERVICIOS"] as const;
const SENT_NOTIFICATION_HISTORY_PAGE_SIZE = 20;
const EXTERNAL_NOTIFICATIONS_BASE_URL = (
  process.env.EXTERNAL_NOTIFICATIONS_BASE_URL ??
  (process.env.NODE_ENV === "production"
    ? "https://notificacionesapi.cochabamba.bo"
    : "https://notificacionesapidev.cochabamba.bo")
).replace(/\/+$/, "");
const ANDROID_NOTIFICATION_CHANNEL_ID = "innova_funcionario_push_v2";

type NotificationServiceConfig = {
  pool: Pool;
  firebaseServiceAccountJson: string | null;
};

type RegisterNotificationTokenInput = {
  token: string;
  platform: string;
};

type SendNotificationInput = {
  title: string;
  body: string;
  imageUrl: string | null;
  cargoCodigos: string[];
  oficinaIds: number[];
  cis: string[];
  tiposVinculo: string[];
  unidades: string[];
  sendToAll: boolean;
  imageData: string | null;
};

type ReceivedNotificationRecord = {
  id: number;
  usuario_id: number;
  tipo: string;
  titulo: string;
  cuerpo: string;
  destino_seccion: string | null;
  salida_id: number | null;
  leida_en: Date | null;
  created_at: Date;
};

type SentNotificationRecord = {
  id: number;
  enviado_por_id: number;
  titulo: string;
  cuerpo: string;
  filtros: any;
  destinatarios_solicitados: number;
  enviados: number;
  fallidos: number;
  tokens_invalidos_removidos: number;
  mensaje_resultado: string | null;
  created_at: Date;
};

type NotificationTargetToken = {
  userId: number;
  token: string;
};

type NotificationTargetUser = {
  userId: number;
  ci: string;
  nombreCompleto: string;
  oficina: string;
};

type FailedNotificationRecipient = {
  ci: string;
  nombreCompleto: string;
  oficina: string;
};

type NotificationSendSummary = {
  requested: number;
  sent: number;
  failed: number;
  removedInvalidTokens?: number;
  message?: string;
  failedRecipients?: FailedNotificationRecipient[];
};

let notificationServiceConfig: NotificationServiceConfig | null = null;

export function configureNotificationService(
  config: NotificationServiceConfig,
) {
  notificationServiceConfig = config;
}

export function parseRegisterNotificationTokenInput(
  payload: unknown,
): RegisterNotificationTokenInput {
  const body = expectRecord(payload);

  return {
    token: readRequiredString(body, "token", 20, 4096),
    platform: readRequiredUppercaseChoice(body, "platform", ["ANDROID", "IOS"]),
  };
}

export function parseSendNotificationInput(
  payload: unknown,
): SendNotificationInput {
  const body = expectRecord(payload);
  const sendToAll = readOptionalBoolean(body, "sendToAll") ?? false;
  const cargoCodigos = readOptionalStringList(body, "cargoCodigos", "cargo");
  const oficinaIds = readOptionalIntList(body, "oficinaIds");
  const unidades = readOptionalStringList(body, "unidades", "unidad");
  const cis = readOptionalStringList(body, "cis", "CI").map(
    normalizeCiLookupValue,
  );
  const tiposVinculo = readOptionalUppercaseChoiceList(body, "tiposVinculo", [
    ...USER_LINK_TYPES,
  ]);
  const hasFilters =
    cargoCodigos.length > 0 ||
    oficinaIds.length > 0 ||
    cis.length > 0 ||
    tiposVinculo.length > 0 ||
    unidades.length > 0;

  if (!sendToAll && !hasFilters) {
    throw new HttpError(
      400,
      "Selecciona todos o al menos un filtro de destinatarios.",
    );
  }

  return {
    title: readRequiredString(body, "title", 3, 120),
    body: readRequiredString(body, "body", 3, 500),
    imageUrl: readOptionalUrlString(body, "imageUrl"),
    imageData: readOptionalImageData(body, "imageData"),
    cargoCodigos,
    oficinaIds,
    cis,
    tiposVinculo,
    unidades,
    sendToAll,
  };
}

export async function registerNotificationToken(
  userId: number,
  input: RegisterNotificationTokenInput,
) {
  await getPool().query(
    `
      INSERT INTO "notificacion_tokens" ("usuario_id", "token", "platform")
      VALUES ($1, $2, $3)
      ON CONFLICT ("token") DO UPDATE SET
        "usuario_id" = EXCLUDED."usuario_id",
        "platform" = EXCLUDED."platform",
        "updated_at" = CURRENT_TIMESTAMP
    `,
    [userId, input.token, input.platform],
  );
}

export async function deleteNotificationToken(userId: number, token: string) {
  await getPool().query(
    `
      DELETE FROM "notificacion_tokens"
      WHERE "usuario_id" = $1 AND "token" = $2
    `,
    [userId, token],
  );
}

export async function loadReceivedNotifications(userId: number) {
  const result = await getPool().query<ReceivedNotificationRecord>(
    `
      SELECT
        "id",
        "usuario_id",
        "tipo",
        "titulo",
        "cuerpo",
        "destino_seccion",
        "salida_id",
        "leida_en",
        "created_at"
      FROM "notificaciones"
      WHERE "usuario_id" = $1
      ORDER BY "created_at" DESC, "id" DESC
      LIMIT 80
    `,
    [userId],
  );

  return result.rows;
}

export async function markReceivedNotificationRead(
  userId: number,
  notificationId: number,
) {
  await getPool().query(
    `
      UPDATE "notificaciones"
      SET "leida_en" = COALESCE("leida_en", CURRENT_TIMESTAMP)
      WHERE "id" = $1 AND "usuario_id" = $2
    `,
    [notificationId, userId],
  );
}

export function serializeReceivedNotification(
  notification: ReceivedNotificationRecord,
) {
  return {
    id: notification.id,
    usuarioId: notification.usuario_id,
    tipo: notification.tipo,
    titulo: notification.titulo,
    cuerpo: notification.cuerpo,
    destinoSeccion: notification.destino_seccion,
    salidaId: notification.salida_id,
    leidaEn: notification.leida_en?.toISOString() ?? null,
    createdAt: notification.created_at.toISOString(),
  };
}

export async function loadSentNotificationHistory(page: number) {
  const offset = (page - 1) * SENT_NOTIFICATION_HISTORY_PAGE_SIZE;
  const [itemsResult, countResult] = await Promise.all([
    getPool().query<SentNotificationRecord>(
      `
        SELECT
          "id",
          "enviado_por_id",
          "titulo",
          "cuerpo",
          "filtros",
          "destinatarios_solicitados",
          "enviados",
          "fallidos",
          "tokens_invalidos_removidos",
          "mensaje_resultado",
          "created_at"
        FROM "notificacion_envios"
        ORDER BY "created_at" DESC, "id" DESC
        LIMIT $1 OFFSET $2
      `,
      [SENT_NOTIFICATION_HISTORY_PAGE_SIZE, offset],
    ),
    getPool().query<{ total: string }>(
      `SELECT COUNT(*)::text AS "total" FROM "notificacion_envios"`,
    ),
  ]);
  const total = Number.parseInt(countResult.rows[0]?.total ?? "0", 10);

  return {
    page,
    pageSize: SENT_NOTIFICATION_HISTORY_PAGE_SIZE,
    total,
    totalPages: Math.max(
      1,
      Math.ceil(total / SENT_NOTIFICATION_HISTORY_PAGE_SIZE),
    ),
    items: itemsResult.rows.map(serializeSentNotification),
  };
}

export async function sendFirebaseNotification(
  input: SendNotificationInput,
  senderUserId: number,
) {
  const notificationImageUrl = await resolveNotificationImageUrl(
    input,
    senderUserId,
  );
  input.imageUrl = notificationImageUrl;
  const targets = await loadNotificationTargets(input);
  await createReceivedNotifications(targets.userIds, {
    type: "general",
    title: input.title,
    body: JSON.stringify({
      message: input.body,
      body: input.body,
      tipo: "general",
      type: "general",
      screen: "notifications",
      route: "",
      imageUrl: notificationImageUrl ?? "",
    }),
    targetSection: "notifications",
    salidaId: null,
  });

  let result: NotificationSendSummary;

  if (targets.tokens.length > 0) {
    try {
      const targetTokens = targets.tokens.map((target) => target.token);
      const localResult = await sendFirebaseMulticastNotification(
        targetTokens,
        {
          title: input.title,
          body: input.body,
          imageUrl: input.imageUrl,
          data: {
            screen: "notifications",
            route: "",
            tipo: "general",
            type: "general",
            recipientCis: JSON.stringify(targets.cis),
            funcionariosCis: JSON.stringify(targets.cis),
            imageUrl: notificationImageUrl ?? "",
          },
        },
      );
      const personResult = summarizeFirebaseResultByUser(
        targets.users,
        targets.tokens,
        localResult.successfulTokens ?? [],
      );

      result = {
        ...localResult,
        sent: personResult.sent,
        failed: personResult.failed,
        requested: targets.cis.length,
        failedRecipients: personResult.failedRecipients,
        message: `Enviadas: ${personResult.sent}. No enviadas: ${personResult.failed}. Destinatarios: ${targets.cis.length}.`,
      };
    } catch (error) {
      result = await sendExternalNotificationFallback(input, targets, error);
    }
  } else {
    result = await sendExternalNotificationFallback(input, targets);

    if (result.sent === 0 && targets.cis.length > 0) {
      result = {
        ...result,
        failedRecipients: targets.users.map(toFailedNotificationRecipient),
        message: `${
          result.message ?? "El servicio externo no reporto envios exitosos."
        } No se envio a usuarios con esos filtros.`,
      };
    }
  }

  await saveSentNotification(input, senderUserId, result);

  return result;
}

export async function sendFirebaseMulticastNotification(
  tokens: string[],
  input: {
    title: string;
    body: string;
    imageUrl?: string | null;
    data?: Record<string, string>;
  },
) {
  if (tokens.length === 0) {
    return {
      requested: 0,
      sent: 0,
      failed: 0,
      message: "No hay dispositivos registrados para esos filtros.",
    };
  }

  const messaging = getFirebaseMessagingClient();
  let sent = 0;
  let failed = 0;
  const invalidTokens: string[] = [];
  const successfulTokens: string[] = [];

  try {
    for (const tokenChunk of chunkArray(tokens, 500)) {
      const batchResult = await messaging.sendEachForMulticast({
        tokens: tokenChunk,
        notification: {
          title: input.title,
          body: input.body,
          ...(input.imageUrl == null ? {} : { imageUrl: input.imageUrl }),
        },
        android: {
          priority: "high",
          notification: {
            title: input.title,
            body: input.body,
            channelId: ANDROID_NOTIFICATION_CHANNEL_ID,
            priority: "max",
            visibility: "public",
            defaultSound: true,
            defaultVibrateTimings: true,
            ...(input.imageUrl == null ? {} : { imageUrl: input.imageUrl }),
          },
        },
        apns: {
          fcmOptions:
            input.imageUrl == null ? undefined : { imageUrl: input.imageUrl },
          payload: {
            aps: {
              alert: {
                title: input.title,
                body: input.body,
              },
              sound: "default",
            },
          },
        },
        data: {
          source: "innovafuncionario",
          title: input.title,
          body: input.body,
          message: input.body,
          titulo: input.title,
          mensaje: input.body,
          ...(input.data ?? {}),
        },
      });

      sent += batchResult.successCount;
      failed += batchResult.failureCount;
      batchResult.responses.forEach((item, index) => {
        if (item.success) {
          successfulTokens.push(tokenChunk[index]);
        }

        const code = item.error?.code;

        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          invalidTokens.push(tokenChunk[index]);
        }
      });
    }
  } catch (error) {
    throw mapFirebaseMessagingError(error);
  }

  if (invalidTokens.length > 0) {
    await removeNotificationTokens(invalidTokens);
  }

  return {
    requested: tokens.length,
    sent,
    failed,
    removedInvalidTokens: invalidTokens.length,
    successfulTokens,
  };
}

export async function loadNotificationTokensForUser(userId: number) {
  const result = await getPool().query<{ token: string }>(
    `
      SELECT DISTINCT "token"
      FROM "notificacion_tokens"
      WHERE "usuario_id" = $1
        AND "platform" = 'ANDROID'
    `,
    [userId],
  );

  return result.rows.map((row) => row.token);
}

export async function sendFirebaseDataMulticastMessage(
  tokens: string[],
  data: Record<string, string>,
) {
  if (tokens.length === 0) {
    return {
      requested: 0,
      sent: 0,
      failed: 0,
      message: "No hay token push registrado para este celular.",
    };
  }

  const messaging = getFirebaseMessagingClient();
  let sent = 0;
  let failed = 0;
  const invalidTokens: string[] = [];

  try {
    for (const tokenChunk of chunkArray(tokens, 500)) {
      const batchResult = await messaging.sendEachForMulticast({
        tokens: tokenChunk,
        android: {
          priority: "high",
        },
        data,
      });

      sent += batchResult.successCount;
      failed += batchResult.failureCount;
      batchResult.responses.forEach((item, index) => {
        const code = item.error?.code;

        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          invalidTokens.push(tokenChunk[index]);
        }
      });
    }
  } catch (error) {
    throw mapFirebaseMessagingError(error);
  }

  if (invalidTokens.length > 0) {
    await removeNotificationTokens(invalidTokens);
  }

  return {
    requested: tokens.length,
    sent,
    failed,
    removedInvalidTokens: invalidTokens.length,
  };
}

export async function createReceivedNotifications(
  userIds: number[],
  input: {
    type: string;
    title: string;
    body: string;
    targetSection: string;
    salidaId: number | null;
  },
) {
  const uniqueUserIds = [...new Set(userIds.filter((userId) => userId > 0))];

  if (uniqueUserIds.length === 0) {
    return;
  }

  await getPool().query(
    `
      INSERT INTO "notificaciones" (
        "usuario_id",
        "tipo",
        "titulo",
        "cuerpo",
        "destino_seccion",
        "salida_id"
      )
      SELECT
        unnest($1::int[]),
        $2,
        $3,
        $4,
        $5,
        $6
    `,
    [
      uniqueUserIds,
      input.type,
      input.title,
      input.body,
      input.targetSection,
      input.salidaId,
    ],
  );
}

async function saveSentNotification(
  input: SendNotificationInput,
  senderUserId: number,
  result: NotificationSendSummary,
) {
  await getPool().query(
    `
      INSERT INTO "notificacion_envios" (
        "enviado_por_id",
        "titulo",
        "cuerpo",
        "filtros",
        "destinatarios_solicitados",
        "enviados",
        "fallidos",
        "tokens_invalidos_removidos",
        "mensaje_resultado"
      )
      VALUES ($1, $2, $3, $4::jsonb, $5, $6, $7, $8, $9)
    `,
    [
      senderUserId,
      input.title,
      input.body,
      JSON.stringify({
        sendToAll: input.sendToAll,
        cargoCodigos: input.cargoCodigos,
        oficinaIds: input.oficinaIds,
        cis: input.cis,
        tiposVinculo: input.tiposVinculo,
        unidades: input.unidades,
        imageUrl: input.imageUrl,
        usuariosFallidos: result.failedRecipients ?? [],
      }),
      result.requested,
      result.sent,
      result.failed,
      result.removedInvalidTokens ?? 0,
      result.message ?? null,
    ],
  );
}

async function loadNotificationTargets(input: SendNotificationInput) {
  const baseClauses = [
    `u."activo" = TRUE`,
    `NULLIF(TRIM(COALESCE(u."ci", '')), '') IS NOT NULL`,
  ];
  const filterClauses: string[] = [];
  const params: unknown[] = [];

  if (!input.sendToAll) {
    if (input.cargoCodigos.length > 0) {
      params.push(input.cargoCodigos);
      filterClauses.push(
        `COALESCE(u."subcargo_codigo", u."cargo_codigo") = ANY($${params.length}::text[])`,
      );
    }

    if (input.oficinaIds.length > 0) {
      params.push(input.oficinaIds);
      filterClauses.push(
        `COALESCE(u."oficina_comision_id", u."oficina_id") = ANY($${params.length}::int[])`,
      );
    }

    if (input.cis.length > 0) {
      params.push(input.cis);
      filterClauses.push(
        `REGEXP_REPLACE(UPPER(COALESCE(u."ci", '')), '[^A-Z0-9]', '', 'g') = ANY($${params.length}::text[])`,
      );
    }

    if (input.tiposVinculo.length > 0) {
      params.push(input.tiposVinculo);
      filterClauses.push(
        `UPPER(COALESCE(u."tipo_vinculo", '')) = ANY($${params.length}::text[])`,
      );
    }

    if (input.unidades.length > 0) {
      params.push(input.unidades.map((value) => value.trim().toUpperCase()));
      filterClauses.push(
        `UPPER(TRIM(COALESCE(u."unidad", ''))) = ANY($${params.length}::text[])`,
      );
    }
  }

  const clauses =
    input.sendToAll || filterClauses.length === 0
      ? baseClauses
      : [...baseClauses, `(${filterClauses.join(" OR ")})`];

  const result = await getPool().query<{
    usuario_id: number;
    ci: string;
    nombre_completo: string;
    oficina: string;
  }>(
    `
      SELECT DISTINCT
        u."id" AS "usuario_id",
        TRIM(u."ci") AS "ci",
        TRIM(COALESCE(u."nombre_completo", '')) AS "nombre_completo",
        TRIM(COALESCE(oc."oficina", op."oficina", u."unidad", '')) AS "oficina"
      FROM "usuarios" u
      LEFT JOIN "oficinas" op ON op."id" = u."oficina_id"
      LEFT JOIN "oficinas" oc ON oc."id" = u."oficina_comision_id"
      WHERE ${clauses.join(" AND ")}
    `,
    params,
  );
  const userIds = [...new Set(result.rows.map((row) => row.usuario_id))];
  const cis = [
    ...new Set(
      result.rows
        .map((row) => row.ci.trim())
        .filter((ci) => ci.length > 0),
    ),
  ];
  const users = result.rows.map((row) => ({
    userId: row.usuario_id,
    ci: row.ci.trim(),
    nombreCompleto: row.nombre_completo.trim(),
    oficina: row.oficina.trim(),
  }));

  return {
    users,
    userIds,
    cis,
    tokens: await loadNotificationTokensForUsers(userIds),
  };
}

async function loadNotificationTokensForUsers(
  userIds: number[],
): Promise<NotificationTargetToken[]> {
  const uniqueUserIds = [...new Set(userIds.filter((userId) => userId > 0))];

  if (uniqueUserIds.length === 0) {
    return [];
  }

  const result = await getPool().query<{ usuario_id: number; token: string }>(
    `
      SELECT DISTINCT "usuario_id", "token"
      FROM "notificacion_tokens"
      WHERE "usuario_id" = ANY($1::int[])
        AND "platform" IN ('ANDROID', 'IOS')
    `,
    [uniqueUserIds],
  );

  return result.rows.map((row) => ({
    userId: row.usuario_id,
    token: row.token,
  }));
}

function summarizeFirebaseResultByUser(
  users: NotificationTargetUser[],
  targetTokens: NotificationTargetToken[],
  successfulTokens: string[],
) {
  const successSet = new Set(successfulTokens);
  const tokensByUser = new Map<number, string[]>();

  for (const target of targetTokens) {
    const tokens = tokensByUser.get(target.userId) ?? [];
    tokens.push(target.token);
    tokensByUser.set(target.userId, tokens);
  }

  let sent = 0;
  let failed = 0;
  const failedRecipients: FailedNotificationRecipient[] = [];

  const uniqueUsers = new Map<number, NotificationTargetUser>();
  for (const user of users) {
    uniqueUsers.set(user.userId, user);
  }

  for (const user of uniqueUsers.values()) {
    const userId = user.userId;
    const tokens = tokensByUser.get(userId) ?? [];

    if (tokens.some((token) => successSet.has(token))) {
      sent++;
    } else {
      failed++;
      failedRecipients.push(toFailedNotificationRecipient(user));
    }
  }

  return { sent, failed, failedRecipients };
}

async function sendExternalNotificationFallback(
  input: SendNotificationInput,
  targets: {
    cis: string[];
    users: NotificationTargetUser[];
  },
  originalError?: unknown,
): Promise<NotificationSendSummary> {
  try {
    const result = await sendExternalFuncionarioNotification(input, targets.cis);
    return {
      ...result,
      failedRecipients:
        result.failed >= targets.users.length
          ? targets.users.map(toFailedNotificationRecipient)
          : [],
    };
  } catch (error) {
    return {
      requested: targets.cis.length,
      sent: 0,
      failed: targets.cis.length,
      failedRecipients: targets.users.map(toFailedNotificationRecipient),
      message:
        originalError == null
          ? error instanceof HttpError
            ? error.message
            : getErrorMessage(error)
          : `Firebase local: ${getErrorMessage(originalError)}. Servicio externo: ${
              error instanceof HttpError ? error.message : getErrorMessage(error)
            }`,
    };
  }
}

function toFailedNotificationRecipient(
  user: NotificationTargetUser,
): FailedNotificationRecipient {
  return {
    ci: user.ci,
    nombreCompleto: user.nombreCompleto || `CI ${user.ci}`,
    oficina: user.oficina,
  };
}

async function sendExternalFuncionarioNotification(
  input: SendNotificationInput,
  cis: string[],
) {
  if (cis.length === 0) {
    return {
      requested: 0,
      sent: 0,
      failed: 0,
      message: "No hay funcionarios para esos filtros.",
    };
  }

  const response = await fetch(
    `${EXTERNAL_NOTIFICATIONS_BASE_URL}/api/funcionarios/enviar-alerta`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        funcionariosCis: cis,
        titulo: input.title,
        mensaje: input.body,
        imagen: input.imageUrl,
        imagenUrl: input.imageUrl,
        imageUrl: input.imageUrl,
        data: {
          source: "innovafuncionario",
          screen: "notifications",
          route: "",
          tipo: "general",
        imageUrl: input.imageUrl ?? "",
        },
      }),
    },
  );
  const payload = await readExternalJsonResponse(response);

  if (!response.ok) {
    throw new HttpError(
      response.status,
      readExternalMessage(payload) ??
        "No pudimos enviar la notificacion con el servicio externo.",
    );
  }

  const summary = readExternalRecord(payload.resumen) ?? payload;
  const sent =
    readOptionalNumber(summary.sent) ??
    readOptionalNumber(summary.pushesExitosos) ??
    readOptionalNumber(summary.enviadas) ??
    readOptionalNumber(summary.enviados) ??
    cis.length;
  const failed =
    readOptionalNumber(summary.failed) ??
    readOptionalNumber(summary.pushesFallidos) ??
    readOptionalNumber(summary.fallidas) ??
    Math.max(cis.length - sent, 0);

  return {
    requested:
      readOptionalNumber(summary.requested) ??
      readOptionalNumber(summary.totalCisEnviados) ??
      cis.length,
    sent,
    failed,
    removedInvalidTokens: 0,
    message:
      readExternalMessage(payload) ??
      `Enviadas: ${sent}. Fallidas: ${failed}. Destinatarios: ${cis.length}.`,
  };
}

async function resolveNotificationImageUrl(
  input: SendNotificationInput,
  senderUserId: number,
) {
  if (input.imageData == null) {
    return input.imageUrl;
  }

  const decodedImage = decodeNotificationImage(input.imageData);
  const publicId = `notificacion-${senderUserId}-${Date.now()}`;

  try {
    return await uploadBufferToCloudinary({
      buffer: decodedImage.buffer,
      folder: "imagenes/notificaciones",
      publicId,
      resourceType: "image",
      filename: `${publicId}.${decodedImage.extension}`,
      mimetype: decodedImage.mimeType,
    });
  } catch {
    throw new HttpError(500, "No pudimos subir la imagen de la notificacion.");
  }
}

async function removeNotificationTokens(tokens: string[]) {
  if (tokens.length === 0) {
    return;
  }

  await getPool().query(
    `
      DELETE FROM "notificacion_tokens"
      WHERE "token" = ANY($1::text[])
    `,
    [tokens],
  );
}

function serializeSentNotification(notification: SentNotificationRecord) {
  return {
    id: notification.id,
    enviadoPorId: notification.enviado_por_id,
    titulo: notification.titulo,
    cuerpo: notification.cuerpo,
    filtros: notification.filtros ?? {},
    usuariosFallidos: readFailedNotificationRecipients(
      notification.filtros?.usuariosFallidos,
    ),
    requested: notification.destinatarios_solicitados,
    sent: notification.enviados,
    failed: notification.fallidos,
    removedInvalidTokens: notification.tokens_invalidos_removidos,
    message: notification.mensaje_resultado,
    createdAt: notification.created_at.toISOString(),
  };
}

function readFailedNotificationRecipients(
  value: unknown,
): FailedNotificationRecipient[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((item) => {
      if (typeof item !== "object" || item == null || Array.isArray(item)) {
        return null;
      }

      const record = item as Record<string, unknown>;
      const ci =
        typeof record.ci === "string" ? record.ci.trim() : "";

      if (ci.length === 0) {
        return null;
      }

      return {
        ci,
        nombreCompleto:
          typeof record.nombreCompleto === "string"
            ? record.nombreCompleto.trim()
            : `CI ${ci}`,
        oficina:
          typeof record.oficina === "string" ? record.oficina.trim() : "",
      };
    })
    .filter(
      (item): item is FailedNotificationRecipient => item != null,
    );
}

function getFirebaseMessagingClient() {
  if (getApps().length === 0) {
    const credential = readFirebaseServiceAccountCredential();

    if (credential == null) {
      initializeApp();
    } else {
      initializeApp({ credential });
    }
  }

  return getMessaging();
}

function mapFirebaseMessagingError(error: unknown) {
  const code = readErrorCode(error);

  if (
    code === "app/invalid-credential" ||
    code === "app/invalid-app-options" ||
    code === "messaging/authentication-error" ||
    code === "messaging/invalid-credential" ||
    getErrorMessage(error).includes("Could not load the default credentials")
  ) {
    return new HttpError(
      503,
      "Firebase no esta configurado correctamente en el servidor dev.",
    );
  }

  return error;
}

function readFirebaseServiceAccountCredential() {
  const serviceAccountJson =
    notificationServiceConfig?.firebaseServiceAccountJson;

  if (serviceAccountJson == null) {
    return null;
  }

  try {
    const jsonText = serviceAccountJson.trim().startsWith("{")
      ? serviceAccountJson
      : Buffer.from(serviceAccountJson, "base64").toString("utf8");

    return cert(JSON.parse(jsonText));
  } catch {
    throw new HttpError(
      500,
      "FIREBASE_SERVICE_ACCOUNT_JSON no tiene un formato valido.",
    );
  }
}

function getPool() {
  if (notificationServiceConfig == null) {
    throw new HttpError(
      500,
      "El servicio de notificaciones no esta configurado.",
    );
  }

  return notificationServiceConfig.pool;
}

function expectRecord(payload: unknown) {
  if (
    typeof payload !== "object" ||
    payload == null ||
    Array.isArray(payload)
  ) {
    throw new HttpError(
      400,
      "El cuerpo de la solicitud no tiene un formato valido.",
    );
  }

  return payload as Record<string, unknown>;
}

function readRequiredString(
  source: Record<string, unknown>,
  key: string,
  minLength: number,
  maxLength: number,
) {
  const value = source[key];

  if (typeof value !== "string") {
    throw new HttpError(400, `Debes enviar el campo ${key}.`);
  }

  const trimmed = value.trim();

  if (trimmed.length < minLength || trimmed.length > maxLength) {
    throw new HttpError(
      400,
      `El campo ${key} debe tener entre ${minLength} y ${maxLength} caracteres.`,
    );
  }

  return trimmed;
}

function readOptionalBoolean(source: Record<string, unknown>, key: string) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  if (typeof value !== "boolean") {
    throw new HttpError(400, `El campo ${key} debe ser booleano.`);
  }

  return value;
}

function readOptionalUrlString(source: Record<string, unknown>, key: string) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  if (typeof value !== "string") {
    throw new HttpError(400, `El campo ${key} debe ser texto.`);
  }

  const trimmed = value.trim();

  if (trimmed.length === 0) {
    return null;
  }

  if (trimmed.length > 1000) {
    throw new HttpError(400, `El campo ${key} no puede superar 1000 caracteres.`);
  }

  let parsedUrl: URL;

  try {
    parsedUrl = new URL(trimmed);
  } catch {
    throw new HttpError(400, "La URL de imagen no es valida.");
  }

  if (parsedUrl.protocol !== "https:") {
    throw new HttpError(400, "La imagen debe usar una URL HTTPS.");
  }

  return trimmed;
}

function readOptionalImageData(source: Record<string, unknown>, key: string) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  if (typeof value !== "string") {
    throw new HttpError(400, `El campo ${key} debe ser texto.`);
  }

  const trimmed = value.trim();

  if (trimmed.length === 0) {
    return null;
  }

  if (trimmed.length > 5_000_000) {
    throw new HttpError(400, "La imagen no puede superar 5 MB.");
  }

  return trimmed;
}

function decodeNotificationImage(imageData: string) {
  const dataUriMatch = imageData.match(
    /^data:(image\/[a-z0-9.+-]+);base64,(.+)$/i,
  );
  const encodedPayload = dataUriMatch?.[2] ?? imageData;
  const buffer = Buffer.from(encodedPayload, "base64");

  if (buffer.length === 0) {
    throw new HttpError(400, "La imagen no contiene datos validos.");
  }

  const mimeType = (
    dataUriMatch?.[1] ?? inferNotificationImageMimeType(buffer)
  ).toLowerCase();

  if (!["image/jpeg", "image/png"].includes(mimeType)) {
    throw new HttpError(400, "La imagen debe ser JPG o PNG.");
  }

  return {
    buffer,
    mimeType,
    extension: notificationImageMimeTypeToExtension(mimeType),
  };
}

function inferNotificationImageMimeType(buffer: Buffer) {
  if (
    buffer.length >= 8 &&
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47
  ) {
    return "image/png";
  }

  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8) {
    return "image/jpeg";
  }

  return "image/jpeg";
}

function notificationImageMimeTypeToExtension(mimeType: string) {
  switch (mimeType) {
    case "image/png":
      return "png";
    case "image/jpeg":
    default:
      return "jpg";
  }
}

async function readExternalJsonResponse(response: Response) {
  const text = await response.text();

  if (text.trim().length === 0) {
    return {};
  }

  try {
    const parsed = JSON.parse(text);
    return typeof parsed === "object" && parsed != null
      ? (parsed as Record<string, unknown>)
      : {};
  } catch {
    return { message: text };
  }
}

function readExternalRecord(value: unknown) {
  return typeof value === "object" && value != null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function readOptionalNumber(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number.parseInt(value, 10);
    return Number.isInteger(parsed) ? parsed : null;
  }

  return null;
}

function readExternalMessage(payload: Record<string, unknown>) {
  const value = payload.message ?? payload.mensaje ?? payload.error;
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function readOptionalStringList(
  source: Record<string, unknown>,
  key: string,
  label: string,
) {
  const rawValue = source[key];

  if (rawValue == null) {
    return [];
  }

  if (!Array.isArray(rawValue)) {
    throw new HttpError(400, `El campo ${key} debe ser una lista.`);
  }

  return rawValue
    .map((item) => {
      if (typeof item !== "string") {
        throw new HttpError(400, `Cada ${label} debe ser texto.`);
      }

      return item.trim();
    })
    .filter((item) => item.length > 0);
}

function readOptionalIntList(source: Record<string, unknown>, key: string) {
  const rawValue = source[key];

  if (rawValue == null) {
    return [];
  }

  if (!Array.isArray(rawValue)) {
    throw new HttpError(400, `El campo ${key} debe ser una lista.`);
  }

  return rawValue.map((item) => {
    const value =
      typeof item === "number" ? item : Number.parseInt(`${item}`, 10);

    if (!Number.isInteger(value) || value <= 0) {
      throw new HttpError(400, `El campo ${key} contiene un id no valido.`);
    }

    return value;
  });
}

function readRequiredUppercaseChoice(
  source: Record<string, unknown>,
  key: string,
  choices: readonly string[],
) {
  const value = readRequiredString(source, key, 1, 40).toUpperCase();

  if (!choices.includes(value)) {
    throw new HttpError(400, `El campo ${key} no tiene un valor valido.`);
  }

  return value;
}

function readOptionalUppercaseChoiceList(
  source: Record<string, unknown>,
  key: string,
  choices: readonly string[],
) {
  return readOptionalStringList(source, key, key).map((item) => {
    const value = item.toUpperCase();

    if (!choices.includes(value)) {
      throw new HttpError(400, `El campo ${key} contiene un valor no valido.`);
    }

    return value;
  });
}

function normalizeCiLookupValue(value: string | null) {
  return (value ?? "").trim().replace(/[^a-zA-Z0-9]/g, "").toUpperCase();
}

function getErrorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  return "Error desconocido.";
}

function readErrorCode(error: unknown) {
  if (typeof error !== "object" || error == null || !("code" in error)) {
    return null;
  }

  const code = (error as { code?: unknown }).code;

  return typeof code === "string" ? code : null;
}

function chunkArray<T>(values: T[], size: number) {
  const chunks: T[][] = [];

  for (let index = 0; index < values.length; index += size) {
    chunks.push(values.slice(index, index + size));
  }

  return chunks;
}
