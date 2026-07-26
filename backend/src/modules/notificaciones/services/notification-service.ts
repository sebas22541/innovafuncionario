import { cert, getApps, initializeApp } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import type { Pool } from "pg";

import { HttpError } from "../../../http-error.ts";

const USER_LINK_TYPES = ["ITEM", "EVENTUAL", "CONSULTOR", "SERVICIOS"] as const;
const SENT_NOTIFICATION_HISTORY_PAGE_SIZE = 20;

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
  cargoCodigos: string[];
  oficinaIds: number[];
  cis: string[];
  tiposVinculo: string[];
  sendToAll: boolean;
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
    tiposVinculo.length > 0;

  if (!sendToAll && !hasFilters) {
    throw new HttpError(
      400,
      "Selecciona todos o al menos un filtro de destinatarios.",
    );
  }

  return {
    title: readRequiredString(body, "title", 3, 120),
    body: readRequiredString(body, "body", 3, 500),
    cargoCodigos,
    oficinaIds,
    cis,
    tiposVinculo,
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
  const targets = await loadNotificationTargets(input);
  await createReceivedNotifications(targets.userIds, {
    type: "general",
    title: input.title,
    body: input.body,
    targetSection: "notifications",
    salidaId: null,
  });
  let result: {
    requested: number;
    sent: number;
    failed: number;
    removedInvalidTokens?: number;
    message?: string;
  };

  try {
    result = await sendFirebaseMulticastNotification(targets.tokens, {
      title: input.title,
      body: input.body,
      data: {
        source: "innovafuncionario",
        type: "general",
        targetSection: "notifications",
      },
    });
  } catch (error) {
    const mappedError =
      error instanceof HttpError ? error : mapFirebaseMessagingError(error);
    result = {
      requested: targets.tokens.length,
      sent: 0,
      failed: targets.tokens.length,
      message:
        mappedError instanceof HttpError
          ? mappedError.message
          : getErrorMessage(mappedError),
    };
  }

  await saveSentNotification(input, senderUserId, result);

  return result;
}

export async function sendFirebaseMulticastNotification(
  tokens: string[],
  input: {
    title: string;
    body: string;
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

  try {
    for (const tokenChunk of chunkArray(tokens, 500)) {
      const batchResult = await messaging.sendEachForMulticast({
        tokens: tokenChunk,
        notification: {
          title: input.title,
          body: input.body,
        },
        android: {
          priority: "high",
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
        data: {
          source: "innovafuncionario",
          ...(input.data ?? {}),
        },
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
  result: {
    requested: number;
    sent: number;
    failed: number;
    removedInvalidTokens?: number;
    message?: string;
  },
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
  const clauses = [`u."activo" = TRUE`, `nt."platform" IN ('ANDROID', 'IOS')`];
  const params: unknown[] = [];

  if (!input.sendToAll) {
    if (input.cargoCodigos.length > 0) {
      params.push(input.cargoCodigos);
      clauses.push(
        `COALESCE(u."subcargo_codigo", u."cargo_codigo") = ANY($${params.length}::text[])`,
      );
    }

    if (input.oficinaIds.length > 0) {
      params.push(input.oficinaIds);
      clauses.push(
        `COALESCE(u."oficina_comision_id", u."oficina_id") = ANY($${params.length}::int[])`,
      );
    }

    if (input.cis.length > 0) {
      params.push(input.cis);
      clauses.push(
        `UPPER(REPLACE(COALESCE(u."ci", ''), '-', '')) = ANY($${params.length}::text[])`,
      );
    }

    if (input.tiposVinculo.length > 0) {
      params.push(input.tiposVinculo);
      clauses.push(
        `UPPER(COALESCE(u."tipo_vinculo", '')) = ANY($${params.length}::text[])`,
      );
    }
  }

  const result = await getPool().query<{ usuario_id: number; token: string }>(
    `
      SELECT DISTINCT nt."usuario_id", nt."token"
      FROM "notificacion_tokens" nt
      INNER JOIN "usuarios" u ON u."id" = nt."usuario_id"
      WHERE ${clauses.join(" AND ")}
    `,
    params,
  );

  return {
    userIds: [...new Set(result.rows.map((row) => row.usuario_id))],
    tokens: result.rows.map((row) => row.token),
  };
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
    requested: notification.destinatarios_solicitados,
    sent: notification.enviados,
    failed: notification.fallidos,
    removedInvalidTokens: notification.tokens_invalidos_removidos,
    message: notification.mensaje_resultado,
    createdAt: notification.created_at.toISOString(),
  };
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
  return (value ?? "").trim().replace(/-/g, "").toUpperCase();
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
