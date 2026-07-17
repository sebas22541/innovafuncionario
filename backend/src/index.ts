import "dotenv/config";
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  randomBytes,
  scryptSync,
  timingSafeEqual,
} from "node:crypto";
import http, {
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { cert, getApps, initializeApp } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import { PrismaPg } from "@prisma/adapter-pg";
import { Pool } from "pg";
import { PDFDocument, StandardFonts, rgb } from "pdf-lib";

import {
  generateAndStoreUserCredential,
  generateUserCredentialPdf,
  storeUserProfilePhoto,
} from "./cloudinary/index.ts";
import { PrismaClient, type Prisma } from "./generated/prisma/client.ts";
import {
  estado_asistencia,
  estado_salida,
  motivo_salida,
  rol_usuario,
} from "./generated/prisma/enums.ts";
import { HttpError } from "./http-error.ts";
import {
  logAccess,
  logError,
  logFatal,
  logInfo,
  logWarning,
} from "./logger.ts";

const DEFAULT_PORT = 3000;
const DATABASE_URL = process.env.DATABASE_URL;
const PORT = parsePort(process.env.PORT);
const DB_POOL_MAX = clampInt(process.env.DB_POOL_MAX ?? null, 25, 5, 100);
const DB_POOL_IDLE_TIMEOUT_MS = clampInt(
  process.env.DB_POOL_IDLE_TIMEOUT_MS ?? null,
  30_000,
  1_000,
  120_000,
);
const DB_POOL_CONNECTION_TIMEOUT_MS = clampInt(
  process.env.DB_POOL_CONNECTION_TIMEOUT_MS ?? null,
  5_000,
  500,
  30_000,
);
const DYNAMIC_QR_TTL_SECONDS = clampInt(
  process.env.QR_DYNAMIC_TTL_SECONDS ?? null,
  1800,
  30,
  3600,
);
const DYNAMIC_QR_HISTORY_LIMIT = clampInt(
  process.env.QR_DYNAMIC_HISTORY_LIMIT ?? null,
  20,
  1,
  100,
);
const DYNAMIC_QR_VERSION = "DQR1";
const DYNAMIC_QR_SIGNATURE_LENGTH = 16;
const STATIC_DYNAMIC_QR_EXPIRES_AT = new Date("2099-12-31T23:59:59.000Z");
const APP_TIME_ZONE = process.env.APP_TIME_ZONE ?? "America/La_Paz";
const JWT_TTL_SECONDS = clampInt(
  process.env.JWT_TTL_SECONDS ?? null,
  31_536_000,
  2_592_000,
  31_536_000,
);
const JWT_SECRET =
  process.env.JWT_SECRET ??
  createHash("sha256").update(`${DATABASE_URL}:jwt`).digest("hex");
const ALLOWED_CORS_ORIGINS = parseAllowedCorsOrigins(
  process.env.CORS_ALLOWED_ORIGINS,
);
const ALLOW_LOCALHOST_CORS = process.env.ALLOW_LOCALHOST_CORS === "true";
const PAYLOAD_ENCRYPTION_KEY = normalizeOptionalEnvValue(
  process.env.PAYLOAD_ENCRYPTION_KEY,
);
const PAYLOAD_ENCRYPTION_KEY_BYTES =
  PAYLOAD_ENCRYPTION_KEY == null
    ? null
    : createHash("sha256").update(PAYLOAD_ENCRYPTION_KEY).digest();
const PAYLOAD_RESPONSE_ENCRYPTION_ENABLED =
  PAYLOAD_ENCRYPTION_KEY_BYTES != null &&
  process.env.PAYLOAD_RESPONSE_ENCRYPTION !== "false";
const REFERENCE_CACHE_TTL_MS = 5 * 60 * 1000;
const DASHBOARD_CACHE_TTL_MS = 30 * 1000;
const EVENT_SUMMARY_CACHE_TTL_MS = 15 * 1000;
const EVENT_ATTENDANCE_CONTEXT_CACHE_TTL_MS = 60 * 1000;
const SEED_ADMIN_EMAIL = normalizeEmailValue(
  process.env.SEED_ADMIN_EMAIL ?? "admin@admin.com",
);
const HIDDEN_USER_READER_LOGIN = normalizeEmailValue(
  process.env.USER_READER_LOGIN ?? "lectorusuarios",
);
const HIDDEN_USER_READER_PASSWORD =
  normalizeOptionalEnvValue(process.env.USER_READER_PASSWORD) ??
  "LectorUsuarios2026*";
const DYNAMIC_QR_SIGNING_SECRET =
  process.env.QR_DYNAMIC_SECRET ??
  createHash("sha256").update(`${DATABASE_URL}:dynamic-qr`).digest("hex");
const FIREBASE_SERVICE_ACCOUNT_JSON = normalizeOptionalEnvValue(
  process.env.FIREBASE_SERVICE_ACCOUNT_JSON,
);
const PUBLIC_RATING_BASE_URL = (
  normalizeOptionalEnvValue(process.env.PUBLIC_RATING_BASE_URL) ??
  "https://innovafuncionario.cochabamba.bo/calificar"
).replace(/\/+$/, "");
const CALIFICACION_QR_SECRET =
  process.env.CALIFICACION_QR_SECRET ??
  createHash("sha256").update(`${DATABASE_URL}:calificaciones`).digest("hex");
const CALIFICACION_QR_VERSION = "CAL1";
const PUBLIC_RATING_LOGO_SRC = readAssetDataUri(
  [
    "assets/images/escuBla.png",
    new URL("../../frontend/assets/images/escuBla.png", import.meta.url),
  ],
  "image/png",
);

// INICIO SERVICIO EXTERNO VERIFICACION FUNCIONARIO POR CI
const FUNCIONARIO_CI_SERVICE_TOKEN_SHA256 = normalizeOptionalEnvValue(
  process.env.FUNCIONARIO_CI_SERVICE_TOKEN_SHA256,
);
const FUNCIONARIO_CI_SERVICE_PATH = "/api/integraciones/funcionarios/verificar-ci";
// FIN SERVICIO EXTERNO VERIFICACION FUNCIONARIO POR CI

if (!DATABASE_URL) {
  logFatal(
    "DATABASE_URL no esta definido en backend/.env.",
    new Error("DATABASE_URL no esta definido en backend/.env."),
  );
  process.exit(1);
}

const pool = new Pool({
  connectionString: DATABASE_URL,
  max: DB_POOL_MAX,
  idleTimeoutMillis: DB_POOL_IDLE_TIMEOUT_MS,
  connectionTimeoutMillis: DB_POOL_CONNECTION_TIMEOUT_MS,
});
const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter });
const requestIdHeader = "X-Request-Id";
const HEALTH_OFFICE_LEVEL = 11;
const HIDDEN_EVENT_ABSENTEE_CI = "2352217";
const HIDDEN_EVENT_ABSENTEE_ITEM = "1";
const CONSULTANT_LINK_TYPE = "CONSULTOR";
const SERVICES_LINK_TYPE = "SERVICIOS";
const TEMPORARY_LINK_TYPE = "EVENTUAL";
const CONTRACT_LINK_TYPES = new Set([CONSULTANT_LINK_TYPE, SERVICES_LINK_TYPE]);
const USER_LINK_TYPES = ["ITEM", TEMPORARY_LINK_TYPE, CONSULTANT_LINK_TYPE, SERVICES_LINK_TYPE] as const;
const DEVICE_ONLINE_THRESHOLD_MS = clampInt(
  process.env.DEVICE_ONLINE_THRESHOLD_MS ?? null,
  30_000,
  10_000,
  120_000,
);

type AuthenticatedUser = {
  id: number;
  email: string;
  ci: string | null;
  rol: (typeof rol_usuario)[keyof typeof rol_usuario];
  activo: boolean;
};

type EventAttendanceRequirement = {
  obligatorio: boolean;
  motivo: string | null;
};

const userWithOfficeInclude = {
  oficinas: true,
  oficina_comision: true,
} as const;

const exitPermitApplicantInclude = {
  usuarios: {
    include: userWithOfficeInclude,
  },
} as const;

const exitPermitRecordInclude = {
  ...exitPermitApplicantInclude,
  registrador_salida: true,
  registrador_llegada: true,
} as const;

const lunchRecordInclude = {
  funcionario: {
    include: userWithOfficeInclude,
  },
  registrador_salida: true,
  registrador_retorno: true,
} as const;

const personIdentityInclude = {
  departamentos: true,
  usuario: {
    include: userWithOfficeInclude,
  },
} as const;

const eventInclude = {
  usuarios: true,
  evento_departamentos: {
    include: {
      departamentos: true,
    },
  },
  evento_controles: {
    orderBy: {
      orden: "asc",
    },
  },
  evento_oficinas: {
    include: {
      oficinas: true,
    },
  },
  evento_cargos: {
    include: {
      cargos: true,
    },
  },
  evento_oficina_cargos: {
    include: {
      cargos: true,
    },
  },
  asistencias: {
    include: {
      personas: {
        include: {
          departamentos: true,
          usuario: {
            include: userWithOfficeInclude,
          },
        },
      },
      asistencia_controles: {
        include: {
          evento_controles: true,
        },
        orderBy: {
          control_id: "asc",
        },
      },
    },
    orderBy: {
      registrado_en: "desc",
    },
  },
} as const;

const eventSummaryInclude = {
  usuarios: true,
  evento_controles: {
    orderBy: {
      orden: "asc",
    },
  },
  evento_oficinas: {
    select: {
      oficina_id: true,
      seleccion_directa: true,
    },
  },
  evento_cargos: {
    select: {
      cargo_codigo: true,
    },
  },
  evento_oficina_cargos: {
    select: {
      oficina_id: true,
      cargo_codigo: true,
    },
  },
} as const;

type CacheEntry<T> = {
  value: T;
  expiresAt: number;
};

let officesCache: CacheEntry<any[]> | null = null;
let cargosCache: CacheEntry<any[]> | null = null;
let dashboardSummaryCache: CacheEntry<{
  usuariosRegistrados: number;
  oficinas: number;
  eventos: number;
}> | null = null;
let eventSummaryCache: CacheEntry<any[]> | null = null;
const eventAttendanceContextCache = new Map<number, CacheEntry<any>>();

await ensureRuntimeSchema();
await ensureHiddenUserReaderAccount();
await deactivateExpiredConsultantContracts();

const server = http.createServer(async (request, response) => {
  const requestStartedAt = process.hrtime.bigint();
  const requestId = createRequestId();
  let requestPath = request.url ?? null;
  let authenticatedUserForLog: AuthenticatedUser | null = null;

  response.setHeader(requestIdHeader, requestId);
  response.on("finish", () => {
    logAccess({
      requestId,
      method: request.method,
      path: requestPath,
      statusCode: response.statusCode,
      durationMs: calculateDurationMs(requestStartedAt),
      ip: getClientIp(request),
      userAgent: readSingleHeader(request.headers["user-agent"]),
      userId: authenticatedUserForLog?.id,
      userEmail: authenticatedUserForLog?.email,
    });
  });

  if (!request.url || !request.method) {
    sendJson(response, 400, { error: "Solicitud invalida." });
    return;
  }

  const url = new URL(
    request.url,
    `http://${request.headers.host ?? "localhost"}`,
  );
  requestPath = buildSafeRequestPath(url);

  if (!applyCors(request, response)) {
    logWarning("Origen no permitido.", buildRequestLogFields(request, requestId, {
      origin: normalizeRequestOrigin(readSingleHeader(request.headers.origin)),
      referrerOrigin: readReferrerOrigin(request),
      statusCode: 403,
    }));
    sendJson(response, 403, { error: "Origen no permitido." });
    return;
  }

  if (request.method === "OPTIONS") {
    response.writeHead(204);
    response.end();
    return;
  }

  try {
    const authenticatedUser = await authenticateRequestIfRequired(request, url);

    authenticatedUserForLog = authenticatedUser;

    if (request.method === "GET" && url.pathname === "/") {
      sendJson(response, 404, { error: "No encontrado." });
      return;
    }

    if (request.method === "GET" && url.pathname === "/health") {
      await prisma.$queryRaw`SELECT 1`;
      sendJson(response, 200, {
        status: "ok",
      });
      return;
    }

    const publicRatingPageMatch = /^\/calificar\/([^/]+)$/.exec(url.pathname);
    if (request.method === "GET" && publicRatingPageMatch) {
      const token = decodeURIComponent(publicRatingPageMatch[1] ?? "");
      const funcionario = await resolveRatingTokenFuncionario(token);

      sendHtml(response, 200, await buildPublicRatingPage(token, funcionario));
      return;
    }

    // INICIO SERVICIO EXTERNO VERIFICACION FUNCIONARIO POR CI
    if (request.method === "POST" && url.pathname === FUNCIONARIO_CI_SERVICE_PATH) {
      assertFuncionarioCiServiceToken(request);
      const input = parseFuncionarioCiLookupInput(await readJsonBody(request));
      const funcionario = await prisma.usuarios.findFirst({
        where: { ci: input.ci },
        select: { id: true },
      });

      sendPlainJson(response, 200, {
        data: {
          ci: input.ci,
          esFuncionario: funcionario != null,
        },
      });
      return;
    }
    // FIN SERVICIO EXTERNO VERIFICACION FUNCIONARIO POR CI

    const publicRatingMatch = /^\/api\/calificaciones\/publica\/([^/]+)$/.exec(
      url.pathname,
    );
    if (request.method === "GET" && publicRatingMatch) {
      const token = decodeURIComponent(publicRatingMatch[1] ?? "");
      const funcionario = await resolveRatingTokenFuncionario(token);

      sendJson(response, 200, {
        data: {
          funcionario: serializeRatingFuncionario(funcionario),
        },
      });
      return;
    }

    if (request.method === "POST" && publicRatingMatch) {
      const token = decodeURIComponent(publicRatingMatch[1] ?? "");
      const funcionario = await resolveRatingTokenFuncionario(token);
      const input = parseSubmitFuncionarioRatingInput(await readJsonBody(request));
      const result = await submitFuncionarioRating({
        funcionario,
        input,
        request,
      });

      sendJson(response, 201, {
        data: result,
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/auth/register") {
      const requester = await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede crear usuarios.",
      );
      const input = parseRegisterUserInput(await readJsonBody(request));

      if (isAdminEmail(input.email)) {
        throw new HttpError(
          403,
          "Solo un administrador puede crear cuentas con @admin.",
        );
      }

      const passwordHash = hashPassword(input.password);
      const selectedOffice =
        input.oficinaId == null
          ? null
          : await prisma.oficinas.findUnique({
              where: { id: input.oficinaId },
            });

      if (input.oficinaId != null && !selectedOffice) {
        throw new HttpError(400, "La unidad seleccionada no existe.");
      }
      assertHealthAdminCanUseOffice(requester, selectedOffice);

      const selectedCommissionOffice =
        input.oficinaComisionId == null
          ? null
          : await prisma.oficinas.findUnique({
              where: { id: input.oficinaComisionId },
            });

      if (input.oficinaComisionId != null && !selectedCommissionOffice) {
        throw new HttpError(400, "La oficina de comision seleccionada no existe.");
      }
      assertHealthAdminCanUseOffice(requester, selectedCommissionOffice);

      const selectedCargo =
        input.cargoCodigo == null
          ? null
          : await prisma.cargos.findUnique({
              where: { codigo: input.cargoCodigo },
            });

      if (input.cargoCodigo != null && !selectedCargo) {
        throw new HttpError(400, "El cargo seleccionado no existe.");
      }

      const selectedSubcargo =
        input.subcargoCodigo == null
          ? null
          : await prisma.cargos.findUnique({
              where: { codigo: input.subcargoCodigo },
            });

      if (input.subcargoCodigo != null && !selectedSubcargo) {
        throw new HttpError(400, "El subcargo seleccionado no existe.");
      }

      const resolvedUnit = selectedOffice?.oficina ?? input.unidad ?? "";
      const resolvedOfficeId = selectedOffice?.id ?? null;
      const resolvedCommissionOfficeId = selectedCommissionOffice?.id ?? null;
      const resolvedCargo = selectedCargo?.cargo ?? input.cargo;
      const resolvedCargoCode = selectedCargo?.codigo ?? null;
      const resolvedSubcargo = selectedSubcargo?.cargo ?? input.subcargo;
      const resolvedSubcargoCode = selectedSubcargo?.codigo ?? null;
      const resolvedLugar = resolvePorteroLugar(
        resolvedCargo,
        resolvedCargoCode,
        input.lugar,
      );
      const duplicatedUser = await findUserByLoginOrCi(prisma, {
        login: input.email,
        ci: input.ci,
      });

      if (duplicatedUser) {
        throw new HttpError(
          409,
          sameCiValue(duplicatedUser.ci, input.ci)
            ? "Ya existe un usuario con ese CI."
            : "Ya existe un usuario con ese usuario de acceso.",
        );
      }

      const storedProfilePhoto = await storeUserProfilePhoto({
        photoSource: input.fotoData,
        email: input.email,
        ci: input.ci,
      });

      const user = await prisma.usuarios.create({
        data: {
          nombre_completo: buildUserDisplayNameFromParts(input),
          nombres: input.nombreCompleto,
          primer_apellido: input.primerApellido,
          segundo_apellido: input.segundoApellido,
          tercer_apellido: input.tercerApellido,
          ci: input.ci,
          celular: input.celular,
          tipo_vinculo: input.tipoVinculo,
          contrato_numero: input.contratoNumero,
          contrato_inicio: input.contratoInicio,
          contrato_fin: input.contratoFin,
          contrato_adenda: input.contratoAdenda,
          unidad: resolvedUnit,
          oficina_id: resolvedOfficeId,
          oficina_comision_id: resolvedCommissionOfficeId,
          cargo_codigo: resolvedCargoCode,
          cargo: resolvedCargo,
          subcargo_codigo: resolvedSubcargoCode,
          subcargo: resolvedSubcargo,
          lugar: resolvedLugar,
          numero_item: input.numeroItem,
          foto_url: storedProfilePhoto,
          email: input.email,
          password_hash: passwordHash,
          rol: rol_usuario.OPERADOR,
          activo: resolveActiveForContract(input),
        },
        include: userWithOfficeInclude,
      });
      const person = await ensurePersonIdentityForUser(prisma, user);
      const authToken = await createAuthToken(user);
      invalidateDashboardSummaryCache();

      sendJson(response, 201, {
        data: serializeAppUser(user, person, authToken),
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/auth/login") {
      await deactivateExpiredConsultantContracts();
      const input = parseLoginInput(await readJsonBody(request));
      const user = await findUserForLogin(input.email);
      const hasStoredPassword =
        user != null && verifyPassword(input.password, user.password_hash);
      const hasDefaultCiPassword =
        user != null && verifyDefaultCiPassword(input.password, user);

      if (!user || (!hasStoredPassword && !hasDefaultCiPassword)) {
        throw new HttpError(401, "Usuario o contrasena incorrectos.");
      }

      if (user.activo !== true) {
        throw new HttpError(
          403,
          "Tu usuario se encuentra inactivo. Solicita su activacion.",
        );
      }

      if (!hasStoredPassword && hasDefaultCiPassword) {
        await prisma.usuarios.update({
          where: { id: user.id },
          data: {
            password_hash: hashPassword(input.password),
            updated_at: new Date(),
          },
        });
      }

      const person = await ensurePersonIdentityForUser(prisma, user);
      if (user.rol === rol_usuario.ALMUERZO) {
        await revokeUserSessions(user.id);
      }
      const authToken = await createAuthToken(user);

      sendJson(response, 200, {
        data: serializeAppUser(user, person, authToken),
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/auth/logout") {
      await markUserDevicesOffline(authenticatedUser.id);
      await revokeUserSessions(authenticatedUser.id);

      sendJson(response, 200, {
        data: { revoked: true },
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/celulares/heartbeat") {
      assertAuthenticatedRequester(authenticatedUser);
      const input = parseDeviceHeartbeatInput(await readJsonBody(request));
      const result = await registerDeviceHeartbeat(authenticatedUser.id, input);

      sendJson(response, 200, {
        data: result,
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/celulares") {
      await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede consultar celulares.",
      );

      sendJson(response, 200, {
        data: await loadManagedDevices(),
      });
      return;
    }

    const deviceLogoutMatch = /^\/api\/celulares\/([^/]+)\/cerrar-sesion$/.exec(
      url.pathname,
    );
    if (request.method === "POST" && deviceLogoutMatch) {
      await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede cerrar sesiones de celulares.",
      );
      const deviceId = decodeURIComponent(deviceLogoutMatch[1] ?? "").trim();

      if (deviceId.length < 8 || deviceId.length > 120) {
        throw new HttpError(400, "El celular seleccionado no es valido.");
      }

      await requestDeviceLogout(deviceId, authenticatedUser.id);

      sendJson(response, 200, {
        data: { requested: true },
      });
      return;
    }

    const deviceLoginMatch = /^\/api\/celulares\/([^/]+)\/iniciar-sesion$/.exec(
      url.pathname,
    );
    if (request.method === "POST" && deviceLoginMatch) {
      await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede iniciar sesiones de celulares.",
      );
      const deviceId = decodeURIComponent(deviceLoginMatch[1] ?? "").trim();

      if (deviceId.length < 8 || deviceId.length > 120) {
        throw new HttpError(400, "El celular seleccionado no es valido.");
      }

      const loginRequest = await requestDeviceLogin(deviceId);
      const wakeResult = await sendDeviceLoginCommand(
        loginRequest.userId,
        deviceId,
      );

      sendJson(response, 200, {
        data: { requested: true, wake: wakeResult },
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/auth/me") {
      const user = await prisma.usuarios.findUnique({
        where: { id: authenticatedUser.id },
        include: userWithOfficeInclude,
      });

      if (!user || user.activo !== true) {
        throw new HttpError(401, "Sesion invalida o expirada.");
      }

      const person = await ensurePersonIdentityForUser(prisma, user);

      sendJson(response, 200, {
        data: serializeAppUser(user, person),
      });
      return;
    }

    if (request.method === "PUT" && url.pathname === "/api/auth/profile") {
      const input = parseUpdateProfileInput(await readJsonBody(request));
      const existingUser = await prisma.usuarios.findUnique({
        where: { email: authenticatedUser.email },
        include: userWithOfficeInclude,
      });

      if (!existingUser) {
        throw new HttpError(404, "No se encontro el usuario seleccionado.");
      }

      if (!isAdminRole(existingUser.rol)) {
        throw new HttpError(
          403,
          "Solo un administrador puede editar su perfil.",
        );
      }

      const nextPhotoSource = input.fotoData == null
        ? existingUser.foto_url
        : await storeUserProfilePhoto({
            photoSource: input.fotoData,
            email: existingUser.email,
            ci: existingUser.ci,
            userId: existingUser.id,
          });

      const updatedUser = await prisma.usuarios.update({
        where: { email: authenticatedUser.email },
        data: {
          nombre_completo: buildUserDisplayNameFromParts(input),
          nombres: input.nombreCompleto,
          primer_apellido: input.primerApellido,
          segundo_apellido: input.segundoApellido,
          tercer_apellido: input.tercerApellido,
          foto_url: nextPhotoSource,
          updated_at: new Date(),
        },
        include: userWithOfficeInclude,
      });
      const person = await ensurePersonIdentityForUser(prisma, updatedUser);

      sendJson(response, 200, {
        data: serializeAppUser(updatedUser, person),
      });
      return;
    }

    if (request.method === "PUT" && url.pathname === "/api/auth/password") {
      const input = parseUpdatePasswordInput(await readJsonBody(request));
      const existingUser = await prisma.usuarios.findUnique({
        where: { email: authenticatedUser.email },
      });

      if (!existingUser) {
        throw new HttpError(404, "No se encontro el usuario seleccionado.");
      }

      if (!verifyPassword(input.currentPassword, existingUser.password_hash)) {
        throw new HttpError(401, "La contrasena actual no es correcta.");
      }

      await prisma.usuarios.update({
        where: { email: authenticatedUser.email },
        data: {
          password_hash: hashPassword(input.newPassword),
          updated_at: new Date(),
        },
      });

      sendJson(response, 200, {
        data: { updated: true },
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/auth/qr/dynamic") {
      const input = parseGenerateDynamicQrInput(await readJsonBody(request));
      const user = await prisma.usuarios.findUnique({
        where: { id: authenticatedUser.id },
        include: userWithOfficeInclude,
      });

      if (!user) {
        throw new HttpError(404, "No se encontro el usuario seleccionado.");
      }

      if (user.activo !== true) {
        throw new HttpError(
          403,
          "Tu usuario se encuentra inactivo. Solicita su activacion.",
        );
      }

      const person = await ensurePersonIdentityForUser(prisma, user);
      const dynamicQr = await issueDynamicQrForUser(prisma, person, user, input);

      sendJson(response, 200, {
        data: dynamicQr,
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/auth/qr/dynamic") {
      const user = await prisma.usuarios.findUnique({
        where: { id: authenticatedUser.id },
        include: userWithOfficeInclude,
      });

      if (!user) {
        throw new HttpError(404, "No se encontro el usuario seleccionado.");
      }

      if (user.activo !== true) {
        throw new HttpError(
          403,
          "Tu usuario se encuentra inactivo. Solicita su activacion.",
        );
      }

      const person = await ensurePersonIdentityForUser(prisma, user);
      const activeDynamicQr = readActiveDynamicQrSession(person, user);

      sendJson(response, 200, {
        data: activeDynamicQr,
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/auth/credential") {
      const user = await resolveCredentialTargetUser(
        authenticatedUser,
        await readJsonBody(request),
      );
      const person = await ensurePersonIdentityForUser(prisma, user);
      const credential = await generateAndStoreUserCredential(user, person);

      sendJson(response, 200, {
        data: credential,
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/auth/credential/pdf") {
      const payload = await readJsonBody(request);
      const user = await resolveCredentialTargetUser(authenticatedUser, payload);
      const pdfUser = applyCredentialPdfOverrides(user, payload);
      const person = await ensurePersonIdentityForUser(prisma, user);
      const pdfBytes = await generateUserCredentialPdf(pdfUser, person);

      sendPdf(
        response,
        200,
        Buffer.from(pdfBytes),
        buildCredentialPdfFilename(user),
      );
      return;
    }

    if (request.method === "PUT" && url.pathname === "/api/auth/credential/photo") {
      const payload = await readJsonBody(request);
      await assertCredentialsRequester(
        authenticatedUser.email,
        "Solo un administrador o usuario de credenciales puede actualizar fotos de credenciales.",
      );
      const user = await resolveCredentialTargetUser(authenticatedUser, payload);
      const body = expectRecord(payload);
      const fotoData = readRequiredString(body, "fotoData", 20, 5_000_000);
      const nextPhotoSource = await storeUserProfilePhoto({
        photoSource: fotoData,
        email: user.email,
        ci: user.ci,
        userId: user.id,
      });
      const updatedUser = await prisma.usuarios.update({
        where: { id: user.id },
        data: {
          foto_url: nextPhotoSource,
          updated_at: new Date(),
        },
        include: userWithOfficeInclude,
      });
      const person = await ensurePersonIdentityForUser(prisma, updatedUser);

      sendJson(response, 200, {
        data: serializeAppUser(updatedUser, person),
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/almuerzos") {
      assertLunchReportRequester(authenticatedUser);
      const query = parseLunchReportQuery(url);
      const records = await prisma.almuerzos.findMany({
        where: buildLunchReportWhere(query),
        include: lunchRecordInclude,
        orderBy: [
          { fecha: "desc" },
          { salida_en: "desc" },
          { id: "desc" },
        ],
        take: 500,
      });

      sendJson(response, 200, {
        data: records.map(serializeLunchRecord),
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/almuerzos/scan") {
      assertLunchScannerRequester(authenticatedUser);
      const input = parseLunchScanInput(await readJsonBody(request));
      const result = await registerLunchScan(input.qrValue, authenticatedUser.id);

      sendJson(response, 201, {
        data: result,
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/salidas/scan") {
      assertExitPermitScannerRequester(authenticatedUser);
      const input = parseLunchScanInput(await readJsonBody(request));
      const result = await registerExitPermitScan(input.qrValue, authenticatedUser.id);

      sendJson(response, 201, {
        data: result,
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/salidas") {
      const input = parseCreateExitPermitInput(await readJsonBody(request));
      const user = await prisma.usuarios.findUnique({
        where: { id: authenticatedUser.id },
        include: userWithOfficeInclude,
      });

      if (!user || user.activo !== true) {
        throw new HttpError(401, "Sesion invalida o expirada.");
      }

      if (user.rol !== rol_usuario.OPERADOR) {
        throw new HttpError(
          403,
          "Solo un funcionario puede registrar formularios de salida.",
        );
      }

      if (isDirectorExitPermitApprover(user)) {
        throw new HttpError(
          403,
          "Los directores solo pueden revisar solicitudes de salida.",
        );
      }

      const salida = await prisma.salidas.create({
        data: {
          usuario_id: user.id,
          motivo: input.motivo,
          lugar_destino: input.lugarDestino,
          descripcion: input.descripcion,
          fecha_permiso: input.fechaPermiso,
          solicitante_nombre_completo: buildUserDisplayName(user),
          solicitante_numero_item: normalizeOptionalText(user.numero_item),
          solicitante_cargo: resolveEffectiveJobTitleName(user),
          solicitante_oficina_id: resolveLinkedOfficeId(user),
          solicitante_oficina: resolveLinkedOfficeName(user),
        },
      });

      notifyExitPermitApprovers(salida.id).catch((error) => {
        logError("No se pudo enviar la notificacion de solicitud de salida.", error, {
          salidaId: salida.id,
        });
      });

      sendJson(response, 201, {
        data: serializeExitPermit(salida),
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/salidas/pendientes") {
      const approver = await prisma.usuarios.findUnique({
        where: { id: authenticatedUser.id },
        include: userWithOfficeInclude,
      });

      if (!approver) {
        throw new HttpError(403, "Solo un jefe puede revisar salidas.");
      }

      assertExitPermitApprover(approver);
      const salidas = await prisma.salidas.findMany({
        where: {
          estado: estado_salida.PENDIENTE,
          usuario_id: { not: approver.id },
        },
        include: exitPermitApplicantInclude,
        orderBy: [
          { fecha_permiso: "asc" },
          { hora_inicio: "asc" },
          { created_at: "asc" },
          { id: "asc" },
        ],
      });
      const reviewableSalidas = await filterReviewableExitPermits(
        approver,
        salidas,
      );

      sendJson(response, 200, {
        data: reviewableSalidas.map(serializeExitPermit),
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/salidas") {
      assertAuthenticatedRequester(authenticatedUser);
      const searchText = readExitPermitQuerySearch(url);
      const onlyOwnExitPermits = readExitPermitOnlyMineQuery(url);
      const requester = await prisma.usuarios.findUnique({
        where: { id: authenticatedUser.id },
        include: userWithOfficeInclude,
      });
      const fechaPermiso =
        !onlyOwnExitPermits &&
        ((isAdminUser(authenticatedUser) && searchText != null) ||
          (requester != null &&
            isExitPermitApproverUser(requester) &&
            !url.searchParams.has("fecha")))
          ? null
          : readExitPermitQueryDate(url);
      const where = buildExitPermitListWhere(
        authenticatedUser,
        requester,
        fechaPermiso,
        searchText,
        onlyOwnExitPermits,
      );
      const salidas = await prisma.salidas.findMany({
        where,
        include: {
          ...exitPermitRecordInclude,
        },
        orderBy: [
          { fecha_permiso: "desc" },
          { hora_inicio: "asc" },
          { created_at: "asc" },
          { id: "asc" },
        ],
      });
      const visibleSalidas =
        requester != null &&
        isExitPermitApproverUser(requester) &&
        !isAdminUser(authenticatedUser) &&
        !onlyOwnExitPermits
          ? await filterReviewableExitPermits(requester, salidas)
          : salidas;

      sendJson(response, 200, {
        data: visibleSalidas.map(serializeExitPermit),
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/declaraciones-juradas") {
      assertAuthenticatedRequester(authenticatedUser);
      const query = normalizeOptionalText(url.searchParams.get("q"));
      const onlyMine =
        !isAdminUser(authenticatedUser) ||
        url.searchParams.get("propias")?.trim().toLowerCase() === "true";
      const records = await listSwornDeclarations({
        userId: authenticatedUser.id,
        onlyMine,
        query,
      });

      sendJson(response, 200, {
        data: records.map(serializeSwornDeclaration),
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/declaraciones-juradas") {
      const user = await prisma.usuarios.findUnique({
        where: { id: authenticatedUser.id },
        include: userWithOfficeInclude,
      });

      if (!user || user.activo !== true) {
        throw new HttpError(401, "Sesion invalida o expirada.");
      }

      if (user.rol !== rol_usuario.OPERADOR) {
        throw new HttpError(
          403,
          "Solo un funcionario puede registrar declaraciones juradas.",
        );
      }

      const input = parseCreateSwornDeclarationInput(await readJsonBody(request));
      const result = await pool.query(
        `
          INSERT INTO "declaraciones_juradas" (
            "usuario_id",
            "gestion",
            "estado",
            "funcionario_nombre_completo",
            "funcionario_ci",
            "funcionario_numero_item",
            "funcionario_cargo",
            "funcionario_oficina_id",
            "funcionario_oficina",
            "payload"
          )
          VALUES ($1, $2, 'PENDIENTE', $3, $4, $5, $6, $7, $8, $9::jsonb)
          RETURNING *
        `,
        [
          user.id,
          input.gestion,
          buildUserDisplayName(user),
          normalizeOptionalText(user.ci),
          normalizeOptionalText(user.numero_item),
          resolveEffectiveJobTitleName(user),
          resolveLinkedOfficeId(user),
          resolveLinkedOfficeName(user),
          JSON.stringify(input.payload),
        ],
      );

      sendJson(response, 201, {
        data: serializeSwornDeclaration(result.rows[0]),
      });
      return;
    }

    const swornDeclarationUpdateMatch =
      /^\/api\/declaraciones-juradas\/(\d+)$/.exec(url.pathname);

    if (request.method === "PUT" && swornDeclarationUpdateMatch != null) {
      const user = await prisma.usuarios.findUnique({
        where: { id: authenticatedUser.id },
      });

      if (!user || user.activo !== true) {
        throw new HttpError(401, "Sesion invalida o expirada.");
      }

      if (user.rol !== rol_usuario.OPERADOR) {
        throw new HttpError(
          403,
          "Solo un funcionario puede corregir declaraciones juradas.",
        );
      }

      const declarationId = Number.parseInt(
        swornDeclarationUpdateMatch[1] ?? "",
        10,
      );
      const input = parseCreateSwornDeclarationInput(await readJsonBody(request));
      const result = await pool.query(
        `
          UPDATE "declaraciones_juradas"
          SET
            "gestion" = $3,
            "estado" = 'PENDIENTE',
            "payload" = $4::jsonb,
            "observacion_revision" = NULL,
            "revisado_por_id" = NULL,
            "revisado_por_nombre" = NULL,
            "revisado_en" = NULL,
            "updated_at" = CURRENT_TIMESTAMP
          WHERE "id" = $1
            AND "usuario_id" = $2
            AND "estado" = 'RECHAZADO'
          RETURNING *
        `,
        [
          declarationId,
          authenticatedUser.id,
          input.gestion,
          JSON.stringify(input.payload),
        ],
      );

      if (result.rowCount === 0) {
        throw new HttpError(
          409,
          "Solo puedes corregir declaraciones rechazadas propias.",
        );
      }

      sendJson(response, 200, {
        data: serializeSwornDeclaration(result.rows[0]),
      });
      return;
    }

    const swornDeclarationPdfMatch =
      /^\/api\/declaraciones-juradas\/(\d+)\/pdf$/.exec(url.pathname);

    if (request.method === "POST" && swornDeclarationPdfMatch != null) {
      assertAuthenticatedRequester(authenticatedUser);
      const declarationId = Number.parseInt(swornDeclarationPdfMatch[1] ?? "", 10);
      const record = await loadSwornDeclarationForPdf(
        declarationId,
        authenticatedUser,
      );
      const pdfBytes = await buildSwornDeclarationPdf(record);

      sendPdf(
        response,
        200,
        Buffer.from(pdfBytes),
        buildSwornDeclarationPdfFilename(record),
      );
      return;
    }

    const swornDeclarationStatusMatch =
      /^\/api\/declaraciones-juradas\/(\d+)\/estado$/.exec(url.pathname);

    if (request.method === "PUT" && swornDeclarationStatusMatch != null) {
      if (!isAdminUser(authenticatedUser)) {
        throw new HttpError(
          403,
          "Solo un administrador puede revisar declaraciones juradas.",
        );
      }

      const declarationId = Number.parseInt(
        swornDeclarationStatusMatch[1] ?? "",
        10,
      );
      const input = parseReviewSwornDeclarationInput(await readJsonBody(request));
      const reviewer = await prisma.usuarios.findUnique({
        where: { id: authenticatedUser.id },
      });
      const result = await pool.query(
        `
          UPDATE "declaraciones_juradas"
          SET
            "estado" = $2,
            "observacion_revision" = $3,
            "revisado_por_id" = $4,
            "revisado_por_nombre" = $5,
            "revisado_en" = CURRENT_TIMESTAMP,
            "updated_at" = CURRENT_TIMESTAMP
          WHERE "id" = $1
          RETURNING *
        `,
        [
          declarationId,
          input.estado,
          input.observacion,
          authenticatedUser.id,
          reviewer == null ? authenticatedUser.email : buildUserDisplayName(reviewer),
        ],
      );

      if (result.rowCount === 0) {
        throw new HttpError(404, "No se encontro la declaracion jurada.");
      }

      sendJson(response, 200, {
        data: serializeSwornDeclaration(result.rows[0]),
      });
      return;
    }

    const salidaLlegadaMatch = /^\/api\/salidas\/(\d+)\/llegada$/.exec(
      url.pathname,
    );

    if (request.method === "PUT" && salidaLlegadaMatch != null) {
      const salidaId = Number.parseInt(salidaLlegadaMatch[1] ?? "", 10);
      const input = parseUpdateExitPermitArrivalInput(await readJsonBody(request));

      const salida = await prisma.salidas.findUnique({
        where: { id: salidaId },
        include: exitPermitRecordInclude,
      });

      if (!salida) {
        throw new HttpError(404, "No se encontro la salida seleccionada.");
      }

      if (salida.usuario_id !== authenticatedUser.id) {
        throw new HttpError(403, "Solo el solicitante puede registrar su llegada.");
      }

      if (salida.estado !== estado_salida.APROBADO) {
        throw new HttpError(409, "Solo puedes registrar llegada de una salida aprobada.");
      }

      const updatedSalida = await prisma.salidas.update({
        where: { id: salida.id },
        data: {
          hora_llegada: input.horaLlegada,
          updated_at: new Date(),
        },
        include: exitPermitRecordInclude,
      });

      sendJson(response, 200, {
        data: serializeExitPermit(updatedSalida),
      });
      return;
    }

    const salidaEstadoMatch = /^\/api\/salidas\/(\d+)\/estado$/.exec(
      url.pathname,
    );

    if (request.method === "PUT" && salidaEstadoMatch != null) {
      const salidaId = Number.parseInt(salidaEstadoMatch[1] ?? "", 10);
      const input = parseUpdateExitPermitStatusInput(await readJsonBody(request));
      const approver = await prisma.usuarios.findUnique({
        where: { id: authenticatedUser.id },
        include: userWithOfficeInclude,
      });

      if (!approver) {
        throw new HttpError(403, "Solo un jefe puede revisar salidas.");
      }

      assertExitPermitApprover(approver);

      const salida = await prisma.salidas.findUnique({
        where: { id: salidaId },
        include: exitPermitRecordInclude,
      });

      if (!salida) {
        throw new HttpError(404, "No se encontro la salida seleccionada.");
      }

      await assertCanReviewExitPermit(approver, salida);

      if (salida.estado !== estado_salida.PENDIENTE) {
        throw new HttpError(409, "Esta salida ya fue revisada.");
      }

      const updatedSalida = await prisma.salidas.update({
        where: { id: salida.id },
        data: {
          estado: input.estado,
          aprobado_por_id: approver.id,
          aprobado_por_nombre: buildUserDisplayName(approver),
          aprobado_en: new Date(),
          updated_at: new Date(),
        },
        include: exitPermitRecordInclude,
      });

      sendJson(response, 200, {
        data: serializeExitPermit(updatedSalida),
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/departamentos") {
      const departamentos = await prisma.departamentos.findMany({
        where: { activo: true },
        orderBy: { nombre: "asc" },
      });

      sendJson(response, 200, {
        data: departamentos.map(serializeDepartment),
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/oficinas") {
      assertAuthenticatedRequester(authenticatedUser);

      sendJson(response, 200, {
        data: await loadSerializedOffices(authenticatedUser),
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/cargos") {
      assertAuthenticatedRequester(authenticatedUser);

      sendJson(response, 200, {
        data: await loadSerializedJobTitles(),
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/notificaciones/token") {
      assertAuthenticatedRequester(authenticatedUser);
      const input = parseRegisterNotificationTokenInput(await readJsonBody(request));

      await registerNotificationToken(authenticatedUser.id, input);

      sendJson(response, 200, {
        data: { registered: true },
      });
      return;
    }

    if (request.method === "DELETE" && url.pathname === "/api/notificaciones/token") {
      assertAuthenticatedRequester(authenticatedUser);
      const input = parseRegisterNotificationTokenInput(await readJsonBody(request));

      await deleteNotificationToken(authenticatedUser.id, input.token);

      sendJson(response, 200, {
        data: { deleted: true },
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/notificaciones/recibidas") {
      assertAuthenticatedRequester(authenticatedUser);
      const notifications = await loadReceivedNotifications(authenticatedUser.id);

      sendJson(response, 200, {
        data: notifications.map(serializeReceivedNotification),
      });
      return;
    }

    const notificationReadMatch = /^\/api\/notificaciones\/(\d+)\/leida$/.exec(
      url.pathname,
    );

    if (request.method === "PUT" && notificationReadMatch != null) {
      assertAuthenticatedRequester(authenticatedUser);
      const notificationId = Number.parseInt(notificationReadMatch[1] ?? "", 10);

      if (!Number.isInteger(notificationId) || notificationId <= 0) {
        throw new HttpError(400, "La notificacion seleccionada no es valida.");
      }

      await markReceivedNotificationRead(authenticatedUser.id, notificationId);

      sendJson(response, 200, {
        data: { updated: true },
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/notificaciones/enviadas") {
      await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede consultar notificaciones enviadas.",
      );
      const page = readOptionalQueryInt(url, "page") ?? 1;
      const history = await loadSentNotificationHistory(page);

      sendJson(response, 200, {
        data: history,
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/notificaciones/enviar") {
      await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede enviar notificaciones.",
      );
      const input = parseSendNotificationInput(await readJsonBody(request));
      const result = await sendFirebaseNotification(input, authenticatedUser.id);

      sendJson(response, 200, {
        data: result,
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/usuarios") {
      await deactivateExpiredConsultantContracts();
      const requester = await assertUserDirectoryRequester(
        authenticatedUser.email,
        "Solo un administrador o usuario de credenciales puede consultar credenciales.",
      );
      const usuarios = await prisma.usuarios.findMany({
        where: {
          AND: [
            {
              email: {
                not: SEED_ADMIN_EMAIL,
              },
            },
            {
              rol: {
                not: rol_usuario.LECTOR_USUARIOS,
              },
            },
            ...healthWhereArray(userDirectoryWhereForRequester(requester)),
          ],
        },
        orderBy: [
          { rol: "asc" },
          { activo: "desc" },
          { updated_at: "desc" },
          { id: "desc" },
        ],
        include: userWithOfficeInclude,
      });

      sendJson(response, 200, {
        data: usuarios.map((user) => serializeAppUser(user)),
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/calificaciones") {
      const requester = await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede consultar calificaciones.",
      );
      const fechaInicio = readOptionalQueryDateOnly(url, "fechaInicio") ??
        readOptionalQueryDateOnly(url, "fecha");
      const fechaFin = readOptionalQueryDateOnly(url, "fechaFin") ?? fechaInicio;
      const cargoCodigo = normalizeOptionalText(url.searchParams.get("cargoCodigo"));
      const oficinaId = readOptionalQueryInt(url, "oficinaId");
      const search = normalizeOptionalText(
        url.searchParams.get("q") ?? url.searchParams.get("ci"),
      );
      const rows = await loadFuncionarioRatingsSummary(
        requester,
        fechaInicio,
        fechaFin,
        cargoCodigo,
        oficinaId,
        search,
      );

      sendJson(response, 200, {
        data: {
          fecha: fechaInicio ?? "",
          fechaInicio,
          fechaFin: fechaFin ?? null,
          cargoCodigo,
          oficinaId,
          q: search,
          funcionarios: rows,
        },
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/calificaciones/qrs") {
      const requester = await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede consultar QR activos de calificaciones.",
      );
      const rows = await loadActiveFuncionarioRatingQrs(requester);

      sendJson(response, 200, {
        data: {
          qrs: rows,
        },
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/calificaciones/qr") {
      const requester = await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede generar QR de calificaciones.",
      );
      const input = parseGenerateFuncionarioRatingQrInput(await readJsonBody(request));
      const funcionario = await loadFuncionarioForRatingAdmin(
        input.funcionarioId,
        requester,
      );
      const token = buildFuncionarioRatingToken(funcionario.id);
      const urlCalificacion = buildFuncionarioRatingUrl(token);
      await activateFuncionarioRatingQr({
        funcionarioId: funcionario.id,
        token,
        generatedById: authenticatedUser.id,
      });

      sendJson(response, 200, {
        data: {
          funcionario: serializeRatingFuncionario(funcionario),
          token,
          url: urlCalificacion,
        },
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/usuarios") {
      await deactivateExpiredConsultantContracts();
      const requester = await assertUserManagerRequester(
        authenticatedUser.email,
        "Solo un administrador puede gestionar usuarios.",
      );
      const input = parseManagedUserInput(await readJsonBody(request));
      const passwordHash = hashPassword(input.password);
      const selectedOffice =
        input.oficinaId == null
          ? null
          : await prisma.oficinas.findUnique({
              where: { id: input.oficinaId },
            });

      if (input.oficinaId != null && !selectedOffice) {
        throw new HttpError(400, "La unidad seleccionada no existe.");
      }
      assertManagedUserRoleAllowedForRequester(requester, input.rol);
      assertScopedUserAdminCanManageUserInput(requester, input);
      assertManagedUserRoleOffice(input.rol, selectedOffice);
      assertHealthAdminCanUseOffice(requester, selectedOffice);

      const selectedCommissionOffice =
        input.oficinaComisionId == null
          ? null
          : await prisma.oficinas.findUnique({
              where: { id: input.oficinaComisionId },
            });

      if (input.oficinaComisionId != null && !selectedCommissionOffice) {
        throw new HttpError(400, "La oficina de comision seleccionada no existe.");
      }
      assertHealthAdminCanUseOffice(requester, selectedCommissionOffice);

      const selectedCargo =
        input.cargoCodigo == null
          ? null
          : await prisma.cargos.findUnique({
              where: { codigo: input.cargoCodigo },
            });

      if (input.cargoCodigo != null && !selectedCargo) {
        throw new HttpError(400, "El cargo seleccionado no existe.");
      }

      const selectedSubcargo =
        input.subcargoCodigo == null
          ? null
          : await prisma.cargos.findUnique({
              where: { codigo: input.subcargoCodigo },
            });

      if (input.subcargoCodigo != null && !selectedSubcargo) {
        throw new HttpError(400, "El subcargo seleccionado no existe.");
      }

      const resolvedUnit = selectedOffice?.oficina ?? input.unidad ?? "";
      const resolvedOfficeId = selectedOffice?.id ?? null;
      const resolvedCommissionOfficeId = selectedCommissionOffice?.id ?? null;
      const resolvedCargo = selectedCargo?.cargo ?? input.cargo;
      const resolvedCargoCode = selectedCargo?.codigo ?? null;
      const resolvedSubcargo = selectedSubcargo?.cargo ?? input.subcargo;
      const resolvedSubcargoCode = selectedSubcargo?.codigo ?? null;
      const resolvedLugar = resolvePorteroLugar(
        resolvedCargo,
        resolvedCargoCode,
        input.lugar,
      );
      const existingUser = await prisma.usuarios.findUnique({
        where: { email: input.email },
      });
      const duplicatedUser = await findUserByLoginOrCi(prisma, {
        login: input.email,
        ci: input.ci,
      });

      if (existingUser) {
        throw new HttpError(409, "Ya existe un usuario con ese usuario de acceso.");
      }

      if (duplicatedUser) {
        throw new HttpError(
          409,
          sameCiValue(duplicatedUser.ci, input.ci)
            ? "Ya existe un usuario con ese CI."
            : "Ya existe un usuario con ese usuario de acceso.",
        );
      }

      const storedProfilePhoto = await storeUserProfilePhoto({
        photoSource: input.fotoData,
        email: input.email,
        ci: input.ci,
      });

      const user = await prisma.usuarios.create({
        data: {
          nombre_completo: buildUserDisplayNameFromParts(input),
          nombres: input.nombreCompleto,
          primer_apellido: input.primerApellido,
          segundo_apellido: input.segundoApellido,
          tercer_apellido: input.tercerApellido,
          ci: input.ci,
          celular: input.celular,
          tipo_vinculo: input.tipoVinculo,
          contrato_numero: input.contratoNumero,
          contrato_inicio: input.contratoInicio,
          contrato_fin: input.contratoFin,
          contrato_adenda: input.contratoAdenda,
          unidad: resolvedUnit,
          oficina_id: resolvedOfficeId,
          oficina_comision_id: resolvedCommissionOfficeId,
          cargo_codigo: resolvedCargoCode,
          cargo: resolvedCargo,
          subcargo_codigo: resolvedSubcargoCode,
          subcargo: resolvedSubcargo,
          lugar: resolvedLugar,
          numero_item: input.numeroItem,
          foto_url: storedProfilePhoto,
          email: input.email,
          password_hash: passwordHash,
          rol: input.rol,
          activo: resolveActiveForContract(input),
        },
        include: userWithOfficeInclude,
      });
      const person = await ensurePersonIdentityForUser(prisma, user);
      invalidateDashboardSummaryCache();

      sendJson(response, 201, {
        data: serializeAppUser(user, person),
      });
      return;
    }

    const userId = readResourceId(url.pathname, "/api/usuarios/");

    if (request.method === "PUT" && userId != null) {
      const requester = await assertUserManagerRequester(
        authenticatedUser.email,
        "Solo un administrador puede gestionar usuarios.",
      );
      const payload = await readJsonBody(request);
      const input = isUpdateUserStatusPayload(payload)
        ? parseUpdateUserStatusInput(payload)
        : parseUpdateManagedUserInput(payload);

      const updatedUser = await prisma.$transaction(async (tx) => {
        const existingUser = await tx.usuarios.findUnique({
          where: { id: userId },
          include: userWithOfficeInclude,
        });

        if (!existingUser) {
          throw new HttpError(404, "No se encontro el usuario seleccionado.");
        }
        assertHealthAdminCanManageUser(requester, existingUser);
        assertScopedUserAdminCanManageUser(requester, existingUser);

        if ("email" in input) {
          const managedInput = input as UpdateManagedUserInput;
          const selectedOffice =
            managedInput.oficinaId == null
              ? null
              : await tx.oficinas.findUnique({
                  where: { id: managedInput.oficinaId },
                });

          if (managedInput.oficinaId != null && !selectedOffice) {
            throw new HttpError(400, "La unidad seleccionada no existe.");
          }
          assertManagedUserRoleAllowedForRequester(requester, managedInput.rol);
          assertScopedUserAdminCanManageUserInput(requester, managedInput);
          assertManagedUserRoleOffice(managedInput.rol, selectedOffice);
          assertHealthAdminCanUseOffice(requester, selectedOffice);

          const selectedCommissionOffice =
            managedInput.oficinaComisionId == null
              ? null
              : await tx.oficinas.findUnique({
                  where: { id: managedInput.oficinaComisionId },
                });

          if (
            managedInput.oficinaComisionId != null &&
            !selectedCommissionOffice
          ) {
            throw new HttpError(
              400,
              "La oficina de comision seleccionada no existe.",
            );
          }
          assertHealthAdminCanUseOffice(requester, selectedCommissionOffice);

          const selectedCargo =
            managedInput.cargoCodigo == null
              ? null
              : await tx.cargos.findUnique({
                  where: { codigo: managedInput.cargoCodigo },
                });

          if (managedInput.cargoCodigo != null && !selectedCargo) {
            throw new HttpError(400, "El cargo seleccionado no existe.");
          }

          const selectedSubcargo =
            managedInput.subcargoCodigo == null
              ? null
              : await tx.cargos.findUnique({
                  where: { codigo: managedInput.subcargoCodigo },
                });

          if (managedInput.subcargoCodigo != null && !selectedSubcargo) {
            throw new HttpError(400, "El subcargo seleccionado no existe.");
          }

          const duplicatedUser = await findUserByLoginOrCi(tx, {
            login: managedInput.email,
            ci: managedInput.ci,
            excludeUserId: userId,
          });

          if (duplicatedUser) {
            throw new HttpError(
              409,
              sameCiValue(duplicatedUser.ci, managedInput.ci)
                ? "Ya existe un usuario con ese CI."
                : "Ya existe un usuario con ese usuario de acceso.",
            );
          }

          const resolvedUnit = selectedOffice?.oficina ?? managedInput.unidad ?? "";
          const resolvedOfficeId = selectedOffice?.id ?? null;
          const resolvedCommissionOfficeId = selectedCommissionOffice?.id ?? null;
          const resolvedCargo = selectedCargo?.cargo ?? managedInput.cargo;
          const resolvedCargoCode = selectedCargo?.codigo ?? null;
          const resolvedSubcargo = selectedSubcargo?.cargo ?? managedInput.subcargo;
          const resolvedSubcargoCode = selectedSubcargo?.codigo ?? null;
          const resolvedLugar = resolvePorteroLugar(
            resolvedCargo,
            resolvedCargoCode,
            managedInput.lugar,
          );
          const nextPhotoSource = managedInput.fotoData == null
            ? existingUser.foto_url
            : await storeUserProfilePhoto({
                photoSource: managedInput.fotoData,
                email: managedInput.email,
                ci: managedInput.ci,
                userId,
              });
          const nextPasswordHash = managedInput.password == null
            ? existingUser.password_hash
            : hashPassword(managedInput.password);

          const nextUser = await tx.usuarios.update({
            where: { id: userId },
            data: {
              nombre_completo: buildUserDisplayNameFromParts(managedInput),
              nombres: managedInput.nombreCompleto,
              primer_apellido: managedInput.primerApellido,
              segundo_apellido: managedInput.segundoApellido,
              tercer_apellido: managedInput.tercerApellido,
              ci: managedInput.ci,
              celular: managedInput.celular,
              tipo_vinculo: managedInput.tipoVinculo,
              contrato_numero: managedInput.contratoNumero,
              contrato_inicio: managedInput.contratoInicio,
              contrato_fin: managedInput.contratoFin,
              contrato_adenda: managedInput.contratoAdenda,
              unidad: resolvedUnit,
              oficina_id: resolvedOfficeId,
              oficina_comision_id: resolvedCommissionOfficeId,
              cargo_codigo: resolvedCargoCode,
              cargo: resolvedCargo,
              subcargo_codigo: resolvedSubcargoCode,
              subcargo: resolvedSubcargo,
              lugar: resolvedLugar,
              numero_item: managedInput.numeroItem,
              foto_url: nextPhotoSource,
              email: managedInput.email,
              password_hash: nextPasswordHash,
              rol: managedInput.rol,
              activo: resolveActiveForContract(managedInput),
              updated_at: new Date(),
            },
            include: userWithOfficeInclude,
          });

          await tx.personas.updateMany({
            where: { usuario_id: userId },
            data: {
              nombre_completo: buildUserDisplayName(nextUser),
              ci: normalizeOptionalText(nextUser.ci),
              activo: nextUser.activo,
              updated_at: new Date(),
            },
          });

          return nextUser;
        }

        const nextUser = await tx.usuarios.update({
          where: { id: userId },
          data: {
            activo: resolveActiveForExistingContract(existingUser, input.activo),
            updated_at: new Date(),
          },
          include: userWithOfficeInclude,
        });

        await tx.personas.updateMany({
          where: { usuario_id: userId },
          data: {
            activo: nextUser.activo,
            updated_at: new Date(),
          },
        });

        return nextUser;
      });
      const person = await ensurePersonIdentityForUser(prisma, updatedUser);

      sendJson(response, 200, {
        data: serializeAppUser(updatedUser, person),
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/inicio/resumen") {
      sendJson(response, 200, {
        data: await loadDashboardSummary(authenticatedUser),
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/eventos") {
      const view = parseEventListView(url);

      sendJson(response, 200, {
        data:
          view === "summary"
            ? await loadSerializedEventSummaries(authenticatedUser)
            : view === "assigned"
              ? await loadSerializedAssignedEventSummaries(authenticatedUser)
            : (await prisma.eventos.findMany({
                where: healthEventWhereForRequester(authenticatedUser),
                orderBy: [{ fecha_evento: "desc" }, { id: "desc" }],
                include: eventInclude,
              })).map(serializeEvent),
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/eventos") {
      const input = parseCreateEventInput(await readJsonBody(request));

      const operador = await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede crear eventos.",
      );

      const evento = await prisma.$transaction(async (tx) => {
        const createdEvent = await tx.eventos.create({
          data: {
            nombre: input.nombre,
            fecha_evento: input.fechaEvento,
            descripcion: input.direccion,
            direccion: input.direccion,
            latitud: input.latitud,
            longitud: input.longitud,
            creado_por_id: operador.id,
          },
        });

        const resolvedOfficeSelection = await resolveExpandedEventOffices(
          tx,
          input.oficinaIds,
          input.oficinaIdsExcluidos,
          input.oficinaIdsFinales,
        );
        assertHealthAdminCanUseEventOffices(
          operador,
          resolvedOfficeSelection.expandedOffices,
        );

        if (resolvedOfficeSelection.expandedOffices.length > 0) {
          await tx.evento_oficinas.createMany({
            data: resolvedOfficeSelection.expandedOffices.map((office) => ({
              evento_id: createdEvent.id,
              oficina_id: office.id,
              seleccion_directa: office.isDirectSelection,
            })),
          });
        }

        await syncEventJobTitles(tx, createdEvent.id, input.cargoCodigos);
        await syncEventOfficeJobTitles(
          tx,
          createdEvent.id,
          input.cargoCodigosPorOficina,
          resolvedOfficeSelection.expandedOffices.map((office) => office.id),
        );

        await tx.eventos.update({
          where: { id: createdEvent.id },
          data: {
            oficina_ids_excluidos: resolvedOfficeSelection.excludedOfficeIds,
          },
        });

        await createEventControls(tx, createdEvent.id, input.controles);

        return tx.eventos.findUniqueOrThrow({
          where: { id: createdEvent.id },
          include: eventInclude,
        });
      });
      invalidateEventSummaryCache();
      invalidateEventAttendanceContextCache(evento.id);
      invalidateDashboardSummaryCache();

      sendJson(response, 201, {
        data: serializeEvent(evento),
      });
      return;
    }

    const eventId = readResourceId(url.pathname, "/api/eventos/");

    if (request.method === "GET" && eventId != null) {
      const evento = await prisma.eventos.findUnique({
        where: { id: eventId },
        include: eventInclude,
      });

      if (!evento) {
        throw new HttpError(404, "No se encontro el evento seleccionado.");
      }
      assertHealthAdminCanManageEvent(authenticatedUser, evento);

      sendJson(response, 200, {
        data: await serializeEventWithAbsentees(evento),
      });
      return;
    }

    if (request.method === "PUT" && eventId != null) {
      const input = parseUpdateEventInput(await readJsonBody(request));
      const operador = await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede editar eventos.",
      );

      const evento = await prisma.$transaction(async (tx) => {
        const existingEvent = await tx.eventos.findUnique({
          where: { id: eventId },
          include: {
            evento_oficinas: {
              include: { oficinas: true },
            },
          },
        });

        if (!existingEvent) {
          throw new HttpError(404, "No se encontro el evento seleccionado.");
        }
        assertHealthAdminCanManageEvent(operador, existingEvent);

        await tx.eventos.update({
          where: { id: eventId },
          data: {
            nombre: input.nombre,
            fecha_evento: input.fechaEvento,
            descripcion: input.direccion,
            direccion: input.direccion,
            latitud: input.latitud,
            longitud: input.longitud,
            updated_at: new Date(),
          },
        });

        await tx.evento_departamentos.deleteMany({
          where: { evento_id: eventId },
        });

        await tx.evento_oficinas.deleteMany({
          where: { evento_id: eventId },
        });

        const resolvedOfficeSelection = await resolveExpandedEventOffices(
          tx,
          input.oficinaIds,
          input.oficinaIdsExcluidos,
          input.oficinaIdsFinales,
        );
        assertHealthAdminCanUseEventOffices(
          operador,
          resolvedOfficeSelection.expandedOffices,
        );

        if (resolvedOfficeSelection.expandedOffices.length > 0) {
          await tx.evento_oficinas.createMany({
            data: resolvedOfficeSelection.expandedOffices.map((office) => ({
              evento_id: eventId,
              oficina_id: office.id,
              seleccion_directa: office.isDirectSelection,
            })),
          });
        }

        await syncEventJobTitles(tx, eventId, input.cargoCodigos);
        await syncEventOfficeJobTitles(
          tx,
          eventId,
          input.cargoCodigosPorOficina,
          resolvedOfficeSelection.expandedOffices.map((office) => office.id),
        );

        await tx.eventos.update({
          where: { id: eventId },
          data: {
            oficina_ids_excluidos: resolvedOfficeSelection.excludedOfficeIds,
          },
        });

        await syncEventControls(tx, eventId, input.controles);

        return tx.eventos.findUniqueOrThrow({
          where: { id: eventId },
          include: eventInclude,
        });
      });
      invalidateEventSummaryCache();
      invalidateEventAttendanceContextCache(eventId);

      sendJson(response, 200, {
        data: serializeEvent(evento),
      });
      return;
    }

    if (request.method === "DELETE" && eventId != null) {
      const operador = await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede borrar eventos.",
      );

      const existingEvent = await prisma.eventos.findUnique({
        where: { id: eventId },
        include: {
          evento_oficinas: {
            include: { oficinas: true },
          },
        },
      });

      if (!existingEvent) {
        throw new HttpError(404, "No se encontro el evento seleccionado.");
      }
      assertHealthAdminCanManageEvent(operador, existingEvent);

      await prisma.eventos.delete({
        where: { id: eventId },
      });
      invalidateEventSummaryCache();
      invalidateEventAttendanceContextCache(eventId);
      invalidateDashboardSummaryCache();

      sendJson(response, 200, {
        data: {
          id: eventId,
        },
      });
      return;
    }

    if (
      request.method === "GET" &&
      url.pathname === "/api/reportes/asistencias"
    ) {
      const reportQuery = parseAttendanceReportQuery(url);
      assertAttendanceReportRequester(authenticatedUser, reportQuery.ci);
      const user = await prisma.usuarios.findFirst({
        where: {
          ci: reportQuery.ci,
        },
        include: userWithOfficeInclude,
      });
      const people = await prisma.personas.findMany({
        where: {
          ci: reportQuery.ci,
        },
        include: {
          ...personIdentityInclude,
          asistencias: {
            where:
              reportQuery.estado == null
                ? undefined
                : {
                    estado: reportQuery.estado,
                  },
            include: {
              eventos: true,
              asistencia_controles: {
                include: {
                  evento_controles: true,
                },
                orderBy: {
                  control_id: "asc",
                },
              },
            },
            orderBy: [{ registrado_en: "desc" }, { id: "desc" }],
          },
        },
        orderBy: [{ activo: "desc" }, { id: "desc" }],
      });

      if (!user && people.length === 0) {
        throw new HttpError(404, "No se encontro una persona con ese CI.");
      }

      if (isHealthAdminUser(authenticatedUser)) {
        const hasHealthMatch =
          (user != null && isUserInHealthScope(user)) ||
          people.some((person) => isUserInHealthScope(person.usuario));

        if (!hasHealthMatch) {
          throw new HttpError(
            403,
            "El administrador de salud solo puede consultar reportes de oficinas nivel 11.",
          );
        }
      }

      const primaryPerson = people[0] ?? null;
      const records = people
        .flatMap((person) =>
          person.asistencias.map((attendance) =>
            serializeAttendanceReportRecord(attendance, person),
          ),
        )
        .sort((left, right) =>
          right.registradoEn.localeCompare(left.registradoEn),
        );

      sendJson(response, 200, {
        data: {
          person: serializeReportPerson({
            user,
            person: primaryPerson,
          }),
          filters: {
            ci: reportQuery.ci,
            estado: reportQuery.estado ?? "TODOS",
          },
          records,
        },
      });
      return;
    }

    if (
      request.method === "GET" &&
      url.pathname === "/api/reportes/qr-generaciones"
    ) {
      const requester = await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede consultar el mapa de QR.",
      );

      const filterBy = parseQrGenerationFilterBy(url);
      const scope = parseQrMapScope(url);
      const query = (url.searchParams.get("query") ?? "").trim().toLowerCase();
      const eventId = readOptionalQueryInt(url, "eventId");
      const controlId = readOptionalQueryInt(url, "controlId");
      const generatedFrom = readOptionalQueryIsoDate(url, "generatedFrom");
      const generatedTo = readOptionalQueryIsoDate(url, "generatedTo");
      const hasDateFilter = generatedFrom != null || generatedTo != null;
      const healthPersonWhere = healthPersonWhereForRequester(requester);

      if (
        generatedFrom != null &&
        generatedTo != null &&
        generatedFrom.getTime() > generatedTo.getTime()
      ) {
        throw new HttpError(
          400,
          "La fecha inicial no puede ser mayor que la fecha final.",
        );
      }

      if (
        !query &&
        !(scope === "eventos" && eventId != null) &&
        !(scope === "generaciones" && hasDateFilter)
      ) {
        sendJson(response, 200, {
          data: {
            records: [],
            filterBy,
            scope,
            eventId,
            controlId,
            query,
            generatedFrom: generatedFrom?.toISOString() ?? null,
            generatedTo: generatedTo?.toISOString() ?? null,
          },
        });
        return;
      }

      const records =
        scope === "eventos"
          ? (await prisma.asistencia_controles.findMany({
              where: {
                latitud_registro: {
                  not: null,
                },
                longitud_registro: {
                  not: null,
                },
                ...(controlId == null
                    ? {}
                    : {
                        control_id: controlId,
                      }),
                asistencias: {
                  ...(eventId == null
                      ? {}
                      : {
                          evento_id: eventId,
                        }),
                  personas: {
                    ...healthPersonWhere,
                    ...(query.length === 0
                        ? {}
                        : {
                            OR: [
                              {
                                ci: {
                                  contains: query,
                                  mode: "insensitive",
                                },
                              },
                              {
                                usuario: {
                                  is: {
                                    ci: {
                                      contains: query,
                                      mode: "insensitive",
                                    },
                                  },
                                },
                              },
                            ],
                          }),
                  },
                },
                ...(generatedFrom == null && generatedTo == null
                    ? {}
                    : {
                        registrado_en: {
                          ...(generatedFrom == null
                              ? {}
                              : {
                                  gte: generatedFrom,
                                }),
                          ...(generatedTo == null
                              ? {}
                              : {
                                  lte: generatedTo,
                                }),
                        },
                      }),
              },
              include: {
                evento_controles: true,
                asistencias: {
                  include: {
                    eventos: true,
                    personas: {
                      include: personIdentityInclude,
                    },
                  },
                },
              },
              orderBy: [{ registrado_en: "desc" }, { id: "desc" }],
            }))
              .map(serializeEventScanMapRecord)
              .filter(isQrMapRecord)
              .filter((record) => matchesQrMapFilter(record, query, filterBy))
              .filter((record) =>
                matchesQrMapDateRange(record, generatedFrom, generatedTo),
              )
              .sort(
                (left, right) =>
                  new Date(right.generatedAt).getTime() -
                  new Date(left.generatedAt).getTime(),
              )
          : (await prisma.personas.findMany({
              where: {
                AND: [
                  {
                    usuario_id: {
                      not: null,
                    },
                  },
                  ...healthWhereArray(healthPersonWhere),
                ],
              },
              include: personIdentityInclude,
              orderBy: [{ updated_at: "desc" }, { id: "desc" }],
            }))
              .flatMap((person) => serializeQrGenerationHistoryRecords(person))
              .filter(isQrMapRecord)
              .filter((record) => matchesQrMapFilter(record, query, filterBy))
              .filter((record) =>
                matchesQrMapDateRange(record, generatedFrom, generatedTo),
              )
              .sort(
                (left, right) =>
                  new Date(right.generatedAt).getTime() -
                  new Date(left.generatedAt).getTime(),
              );

      sendJson(response, 200, {
        data: {
          records,
          filterBy,
          scope,
          eventId,
          controlId,
          query,
          generatedFrom: generatedFrom?.toISOString() ?? null,
          generatedTo: generatedTo?.toISOString() ?? null,
        },
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/asistencias") {
      // Flujo de registro por QR o por CI:
      // 1. Normaliza el valor leido o el CI manual para obtener una identidad estable.
      // 2. Valida que el evento y el control existan.
      // 3. Resuelve la persona real asociada al QR o crea un placeholder.
      // 4. Guarda un snapshot del QR leido para auditoria.
      // 5. Hace upsert de la asistencia general y del control puntual.
      const input = parseRegisterAttendanceInput(await readJsonBody(request));
      const isCiRegistration = input.registrationSource === "CI";
      const scannedValue = isCiRegistration
        ? buildCiAttendanceRawValue(input.ci!)
        : input.qrValue!;
      const lookupCode = isCiRegistration
        ? input.ci!.trim().toUpperCase()
        : extractLookupCode(scannedValue);

      if (!isCiRegistration) {
        assertScannedQrCanRegisterAttendance(scannedValue);
      }

      if (!lookupCode) {
        throw new HttpError(
          400,
          isCiRegistration
            ? "Debes enviar un CI valido."
            : "Debes enviar un codigo QR valido.",
        );
      }

      const evento = await getEventAttendanceContext(input.eventId);

      if (!evento) {
        throw new HttpError(404, "No se encontro el evento seleccionado.");
      }

      const selectedControl = (evento.evento_controles ?? []).find(
        (control: { id: number }) => control.id === input.controlId,
      );

      if (!selectedControl) {
        throw new HttpError(
          400,
          "El control seleccionado no pertenece al evento.",
        );
      }

      const registeredAt = new Date();
      const registrationTiming = resolveControlRegistrationTiming(
        evento,
        selectedControl,
        registeredAt,
      );

      const persona = isCiRegistration
        ? await findPersonByCi(input.ci!)
        : await resolvePersonByQrValue(scannedValue, lookupCode);

      if (!persona) {
        throw new HttpError(404, "No se encontro una persona con ese CI.");
      }

      const eventRequirement = await resolvePersonEventRequirement(
        persona,
        evento,
      );

      const operador = await assertEventOperator(authenticatedUser.id);
      const resolvedObservation = buildAttendanceObservation(input);
      const qrSnapshot = buildAttendanceQrSnapshot(
        persona,
        scannedValue,
        lookupCode,
        input.payloadFields,
        {
          registrationSource: input.registrationSource,
          registrationCi: input.ci,
          scannedAt: input.scannedAt,
          registrationLocation: buildAttendanceRegistrationLocation(input),
          eventRequirement,
        },
      );
      const asistencia = await prisma.$transaction(async (tx) => {
        const baseAttendance = await tx.asistencias.upsert({
          where: {
            evento_id_persona_id: {
              evento_id: evento.id,
              persona_id: persona.id,
            },
          },
          create: {
            evento_id: evento.id,
            persona_id: persona.id,
            nombre_snapshot: buildResolvedPersonDisplayName(persona),
            estado: input.estado,
            qr_leido: scannedValue,
            datos_qr_snapshot: qrSnapshot,
            observacion: resolvedObservation,
            registrado_por_id: operador.id,
            registrado_en: registeredAt,
          },
          update: {
            nombre_snapshot: buildResolvedPersonDisplayName(persona),
            qr_leido: scannedValue,
            datos_qr_snapshot: qrSnapshot,
            observacion: resolvedObservation,
            registrado_por_id: operador.id,
            registrado_en: registeredAt,
          },
        });

        const controlAttendance = await tx.asistencia_controles.upsert({
          where: {
            asistencia_id_control_id: {
              asistencia_id: baseAttendance.id,
              control_id: input.controlId,
            },
          },
          create: {
            asistencia_id: baseAttendance.id,
            control_id: input.controlId,
            estado: input.estado,
            retrasado: registrationTiming.isLate,
            observacion: resolvedObservation,
            registrado_por_id: operador.id,
            registrado_en: registeredAt,
            latitud_registro: input.latitud,
            longitud_registro: input.longitud,
            accuracy_registro: input.accuracy,
          },
          update: {
            estado: input.estado,
            retrasado: registrationTiming.isLate,
            observacion: resolvedObservation,
            registrado_por_id: operador.id,
            registrado_en: registeredAt,
            latitud_registro: input.latitud,
            longitud_registro: input.longitud,
            accuracy_registro: input.accuracy,
          },
        });

        const attendedControl = input.estado === estado_asistencia.ASISTIO
          ? { id: controlAttendance.id }
          : await tx.asistencia_controles.findFirst({
              where: {
                asistencia_id: baseAttendance.id,
                estado: estado_asistencia.ASISTIO,
              },
              select: {
                id: true,
              },
            });
        const resolvedAttendanceState = attendedControl != null
          ? estado_asistencia.ASISTIO
          : estado_asistencia.OBSERVADO;

        const updatedAttendance = await tx.asistencias.update({
          where: { id: baseAttendance.id },
          data: {
            nombre_snapshot: buildResolvedPersonDisplayName(persona),
            estado: resolvedAttendanceState,
            qr_leido: scannedValue,
            datos_qr_snapshot: qrSnapshot,
            observacion: resolvedObservation,
            registrado_por_id: operador.id,
            registrado_en: registeredAt,
          },
          select: {
            id: true,
            persona_id: true,
            evento_id: true,
            estado: true,
            registrado_en: true,
          },
        });

        return {
          id: updatedAttendance.id,
          personaId: updatedAttendance.persona_id,
          eventoId: updatedAttendance.evento_id,
          estado: updatedAttendance.estado,
          registradoEn: updatedAttendance.registrado_en.toISOString(),
          control: {
            id: controlAttendance.id,
            controlId: controlAttendance.control_id,
            controlNombre: selectedControl.nombre,
            controlOrden: selectedControl.orden,
            estado: controlAttendance.estado,
            retrasado: controlAttendance.retrasado,
            observacion: controlAttendance.observacion,
            registradoEn: controlAttendance.registrado_en.toISOString(),
          },
        };
      });
      invalidateEventSummaryCache();

      sendJson(response, 200, {
        data: asistencia,
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/personas") {
      const requester = await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede listar personas.",
      );
      const limit = clampInt(url.searchParams.get("limit"), 20, 1, 100);
      const personas = await prisma.personas.findMany({
        take: limit,
        where: healthPersonWhereForRequester(requester),
        orderBy: { id: "desc" },
        include: personIdentityInclude,
      });

      sendJson(response, 200, {
        data: personas.map((person) => serializeQrPersonDetail(person)),
      });
      return;
    }

    if (
      request.method === "GET" &&
      url.pathname.startsWith("/api/personas/ci/")
    ) {
      // Fallback manual para usuarios ADMIN:
      // busca CI -> backend resuelve persona real -> frontend permite registrar
      // solo como observado sin depender del QR leido.
      assertPersonLookupRequester(authenticatedUser);
      const ci = decodeURIComponent(url.pathname.replace("/api/personas/ci/", ""))
        .trim();

      if (!ci) {
        sendJson(response, 400, { error: "Debes enviar un CI valido." });
        return;
      }

      const persona = await findPersonByCi(ci);
      const eventId = readOptionalQueryInt(url, "eventId");

      if (!persona) {
        sendJson(response, 404, {
          error: "No se encontro una persona con ese CI.",
        });
        return;
      }

      let eventAttendance = null;
      let eventPermission = null;

      if (eventId != null) {
        eventPermission = await resolvePersonEventPermission(persona, eventId);

        const attendance = await prisma.asistencias.findUnique({
          where: {
            evento_id_persona_id: {
              evento_id: eventId,
              persona_id: persona.id,
            },
          },
          include: {
            asistencia_controles: {
              include: {
                evento_controles: true,
              },
              orderBy: {
                control_id: "asc",
              },
            },
          },
        });

        if (attendance) {
          eventAttendance = serializeEventAttendanceLookup(attendance);
        }
      }

      sendJson(response, 200, {
        data: serializeQrPersonDetail(persona, {
          eventAttendance,
          eventPermission,
        }),
      });
      return;
    }

    if (
      request.method === "GET" &&
      url.pathname.startsWith("/api/personas/qr/")
    ) {
      // Flujo de consulta al escanear:
      // frontend -> lookupCode -> /api/personas/qr/:codigo -> persona -> UI detalle.
      // Aqui no se registra asistencia; solo se resuelve la identidad del QR.
      assertPersonLookupRequester(authenticatedUser);
      const codigoQr = decodeURIComponent(
        url.pathname.replace("/api/personas/qr/", ""),
      ).trim();

      if (!codigoQr) {
        sendJson(response, 400, { error: "Debes enviar un codigo QR valido." });
        return;
      }

      assertScannedQrCanRegisterAttendance(codigoQr);

      const persona = await findPersonByScannedValue(codigoQr);
      const eventId = readOptionalQueryInt(url, "eventId");

      if (!persona) {
        sendJson(response, 404, {
          error: "No se encontro una persona con ese codigo QR.",
        });
        return;
      }

      let eventAttendance = null;
      let eventPermission = null;

      if (eventId != null) {
        eventPermission = await resolvePersonEventPermission(persona, eventId);

        const attendance = await prisma.asistencias.findUnique({
          where: {
            evento_id_persona_id: {
              evento_id: eventId,
              persona_id: persona.id,
            },
          },
          include: {
            asistencia_controles: {
              include: {
                evento_controles: true,
              },
              orderBy: {
                control_id: "asc",
              },
            },
          },
        });

        if (attendance) {
          eventAttendance = serializeEventAttendanceLookup(attendance);
        }
      }

      sendJson(response, 200, {
        data: serializeQrPersonDetail(persona, {
          eventAttendance,
          eventPermission,
        }),
      });
      return;
    }

    sendJson(response, 404, { error: "Ruta no encontrada." });
  } catch (error) {
    if (error instanceof HttpError) {
      logWarning(error.message, buildRequestLogFields(request, requestId, {
        path: requestPath,
        statusCode: error.statusCode,
        userId: authenticatedUserForLog?.id,
        userEmail: authenticatedUserForLog?.email,
      }));
      if (requestPath === FUNCIONARIO_CI_SERVICE_PATH) {
        sendPlainJson(response, error.statusCode, {
          status: error.statusCode,
          message: error.message,
          error: error.message,
        });
        return;
      }

      sendErrorJson(response, error.statusCode, error.message);
      return;
    }

    logError("Error no controlado procesando request.", error, buildRequestLogFields(
      request,
      requestId,
      {
        path: requestPath,
        statusCode: 500,
        userId: authenticatedUserForLog?.id,
        userEmail: authenticatedUserForLog?.email,
      },
    ));
    sendJson(response, 500, {
      error: "Error interno del servidor.",
      details: getErrorMessage(error),
    });
  }
});

server.keepAliveTimeout = 65_000;
server.headersTimeout = 66_000;

server.on("error", (error: NodeJS.ErrnoException) => {
  if (error.code === "EADDRINUSE") {
    logFatal(`No se puede iniciar el backend: el puerto ${PORT} ya esta en uso.`, error);
    logFatal("Cierra el proceso anterior o define otro puerto con la variable PORT.", error);
    process.exit(1);
  }

  logFatal("No se pudo iniciar el backend.", error);
  process.exit(1);
});

server.listen(PORT, () => {
  logInfo(`Backend escuchando en http://localhost:${PORT}`, {
    port: PORT,
    nodeEnv: process.env.NODE_ENV ?? "development",
  });
});

process.on("uncaughtException", (error) => {
  logFatal("Excepcion no capturada. El proceso se cerrara.", error);
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  logFatal("Promesa rechazada sin manejo. El proceso se cerrara.", reason);
  process.exit(1);
});

process.on("SIGINT", () => {
  void shutdown("SIGINT");
});

process.on("SIGTERM", () => {
  void shutdown("SIGTERM");
});

async function shutdown(signal: string) {
  logInfo(`Cerrando backend por ${signal}...`, { signal });
  server.close();
  await prisma.$disconnect();
  await pool.end();
  process.exit(0);
}

type JsonRecord = Prisma.InputJsonObject;

type CreateEventInput = {
  nombre: string;
  fechaEvento: Date;
  direccion: string;
  latitud: number;
  longitud: number;
  oficinaIds: number[];
  oficinaIdsFinales: number[];
  oficinaIdsExcluidos: number[];
  cargoCodigos: string[];
  cargoCodigosPorOficina: EventOfficeJobTitleInput[];
  controles: EventControlInput[];
  creatorEmail: string;
  creatorFullName: string;
};

type UpdateEventInput = {
  nombre: string;
  fechaEvento: Date;
  direccion: string;
  latitud: number;
  longitud: number;
  oficinaIds: number[];
  oficinaIdsFinales: number[];
  oficinaIdsExcluidos: number[];
  cargoCodigos: string[];
  cargoCodigosPorOficina: EventOfficeJobTitleInput[];
  controles: EventControlInput[];
  requesterEmail: string;
};

type RegisterAttendanceInput = {
  eventId: number;
  controlId: number;
  qrValue: string | null;
  ci: string | null;
  registrationSource: "QR" | "CI";
  estado: (typeof estado_asistencia)[keyof typeof estado_asistencia];
  observacion: string | null;
  payloadFields: JsonRecord | null;
  scannedAt: Date | null;
  latitud: number | null;
  longitud: number | null;
  accuracy: number | null;
};

type EventControlInput = {
  id: number | null;
  nombre: string;
  orden: number;
  horaInicio: string;
  horaFin: string;
};

type ExpandedEventOffice = {
  id: number;
  oficina: string;
  cod: string;
  nivel: number;
  isDirectSelection: boolean;
};

type ResolvedEventOfficeSelection = {
  expandedOffices: ExpandedEventOffice[];
  excludedOfficeIds: number[];
};

type EventOfficeNode = {
  id: number;
  oficina: string;
  cod: string;
  nivel: number;
};

type LoginInput = {
  email: string;
  password: string;
};

type UpdateProfileInput = {
  email: string;
  nombreCompleto: string;
  primerApellido: string;
  segundoApellido: string | null;
  tercerApellido: string | null;
  fotoData: string | null;
};

type EventOfficeJobTitleInput = {
  oficinaId: number;
  cargoCodigos: string[];
};

type UpdatePasswordInput = {
  currentPassword: string;
  newPassword: string;
};

type GenerateDynamicQrInput = {
  latitud: number;
  longitud: number;
  accuracy: number | null;
};

type CreateExitPermitInput = {
  motivo: (typeof motivo_salida)[keyof typeof motivo_salida];
  lugarDestino: string;
  descripcion: string | null;
  fechaPermiso: Date;
};

type UpdateExitPermitStatusInput = {
  estado: typeof estado_salida.APROBADO | typeof estado_salida.RECHAZADO;
};

type UpdateExitPermitArrivalInput = {
  horaLlegada: string;
};

type LunchScanInput = {
  qrValue: string;
};

type LunchReportQuery = {
  fecha: Date;
  search: string | null;
  status: "ABIERTOS" | "CERRADOS" | null;
  scannerId: number | null;
  officeId: number | null;
};

type RegisterNotificationTokenInput = {
  token: string;
  platform: string;
};

type DeviceHeartbeatInput = {
  deviceId: string;
  platform: string;
  manufacturer: string | null;
  model: string | null;
  androidSdk: number | null;
  batteryLevel: number | null;
  isCharging: boolean | null;
  brightness: number | null;
  kioskEnabled: boolean;
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

type RegisterUserInput = {
  email: string;
  password: string;
  nombreCompleto: string;
  primerApellido: string;
  segundoApellido: string | null;
  tercerApellido: string | null;
  ci: string;
  celular: string | null;
  tipoVinculo: string;
  contratoNumero: string | null;
  contratoInicio: Date | null;
  contratoFin: Date | null;
  contratoAdenda: Date | null;
  unidad: string | null;
  oficinaId: number | null;
  oficinaComisionId: number | null;
  cargoCodigo: string | null;
  cargo: string;
  subcargoCodigo: string | null;
  subcargo: string | null;
  lugar: string | null;
  numeroItem: string | null;
  activo: boolean;
  fotoData: string;
};

type ManagedUserInput = RegisterUserInput & {
  rol: (typeof rol_usuario)[keyof typeof rol_usuario];
  requesterEmail: string;
};

type UpdateUserStatusInput = {
  requesterEmail: string;
  activo: boolean;
};

type UpdateManagedUserInput = Omit<RegisterUserInput, "password" | "fotoData"> & {
  requesterEmail: string;
  rol: (typeof rol_usuario)[keyof typeof rol_usuario];
  password: string | null;
  fotoData: string | null;
};

type AttendanceReportQuery = {
  ci: string;
  estado:
    | (typeof estado_asistencia)[keyof typeof estado_asistencia]
    | null;
};

type EventAttendanceCounts = {
  attended: number;
  observed: number;
  total: number;
};

type QrMapRecord = {
  id: string;
  source: "GENERACION" | "EVENTO";
  personaId: number;
  usuarioId: number | null;
  nombreCompleto: string;
  ci: string;
  email: string | null;
  oficina: string | null;
  codigoQr: string | null;
  latitud: number;
  longitud: number;
  accuracy: number | null;
  generatedAt: string;
  expiresAt: string | null;
  eventoId: number | null;
  eventoNombre: string | null;
  controlId: number | null;
  controlNombre: string | null;
  estado: (typeof estado_asistencia)[keyof typeof estado_asistencia] | null;
  observacion: string | null;
  registrationSource: "QR" | "CI" | null;
};

function applyCors(request: IncomingMessage, response: ServerResponse) {
  const origin = normalizeRequestOrigin(readSingleHeader(request.headers.origin));
  const referrerOrigin = readReferrerOrigin(request);
  const isAllowedOrigin = origin == null || isAllowedRequestOrigin(origin);
  const isAllowedReferrer =
    referrerOrigin == null || isAllowedRequestOrigin(referrerOrigin);
  const isTrustedUnsafeRequest =
    !isUnsafeHttpMethod(request.method) ||
    (origin != null && isAllowedRequestOrigin(origin)) ||
    (origin == null && isAllowedReferrer);

  if (!isAllowedOrigin || !isTrustedUnsafeRequest) {
    return false;
  }

  if (origin != null && isAllowedOrigin) {
    response.setHeader("Access-Control-Allow-Origin", origin);
    response.setHeader("Vary", "Origin");
  }

  response.setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS");
  response.setHeader(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, x-service",
  );
  response.setHeader("Access-Control-Max-Age", "86400");
  response.setHeader("Content-Type", "application/json; charset=utf-8");

  return isAllowedOrigin;
}

function isUnsafeHttpMethod(method: string | undefined) {
  return method !== "GET" && method !== "HEAD" && method !== "OPTIONS";
}

function isAllowedRequestOrigin(origin: string) {
  return (
    ALLOWED_CORS_ORIGINS.has(origin) ||
    (ALLOW_LOCALHOST_CORS && isLocalhostOrigin(origin))
  );
}

function isLocalhostOrigin(origin: string) {
  try {
    const url = new URL(origin);

    return (
      (url.protocol === "http:" || url.protocol === "https:") &&
      (url.hostname === "localhost" || url.hostname === "127.0.0.1")
    );
  } catch {
    return false;
  }
}

function readSingleHeader(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function createRequestId() {
  return randomBytes(8).toString("hex");
}

function calculateDurationMs(startedAt: bigint) {
  return Number((process.hrtime.bigint() - startedAt) / 1_000_000n);
}

function buildSafeRequestPath(url: URL) {
  const queryKeys = [...url.searchParams.keys()];

  if (queryKeys.length === 0) {
    return url.pathname;
  }

  return `${url.pathname}?${queryKeys.map((key) => `${key}=[redacted]`).join("&")}`;
}

function getClientIp(request: IncomingMessage) {
  return readClientIp(request);
}

function buildRequestLogFields(
  request: IncomingMessage,
  requestId: string,
  fields: Record<string, unknown> = {},
) {
  return {
    requestId,
    method: request.method,
    path: request.url,
    ip: getClientIp(request),
    userAgent: readSingleHeader(request.headers["user-agent"]),
    ...fields,
  };
}

function normalizeRequestOrigin(value: string | undefined) {
  return value?.trim().replace(/\/+$/, "") || null;
}

function readReferrerOrigin(request: IncomingMessage) {
  const referrer = readSingleHeader(request.headers.referer);

  if (referrer == null || referrer.trim().length === 0) {
    return null;
  }

  try {
    return normalizeRequestOrigin(new URL(referrer).origin);
  } catch {
    return null;
  }
}

function sendJson(
  response: ServerResponse,
  statusCode: number,
  payload: unknown,
) {
  const encryptedPayload = encryptJsonPayload(payload);

  if (encryptedPayload != null) {
    payload = encryptedPayload;
  }

  response.setHeader("Cache-Control", "no-store");
  response.setHeader("Pragma", "no-cache");
  response.writeHead(statusCode);
  response.end(JSON.stringify(payload, null, 2));
}

function sendPlainJson(
  response: ServerResponse,
  statusCode: number,
  payload: unknown,
) {
  response.setHeader("Cache-Control", "no-store");
  response.setHeader("Pragma", "no-cache");
  response.writeHead(statusCode);
  response.end(JSON.stringify(payload, null, 2));
}

function sendHtml(
  response: ServerResponse,
  statusCode: number,
  html: string,
) {
  response.setHeader("Content-Type", "text/html; charset=utf-8");
  response.setHeader("Cache-Control", "no-store");
  response.setHeader("Pragma", "no-cache");
  response.setHeader("X-Frame-Options", "DENY");
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("Referrer-Policy", "no-referrer");
  response.setHeader(
    "Content-Security-Policy",
    "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
  );
  response.writeHead(statusCode);
  response.end(html);
}

function sendErrorJson(
  response: ServerResponse,
  statusCode: number,
  message: string,
) {
  sendJson(response, statusCode, {
    status: statusCode,
    message,
    error: message,
  });
}

function sendPdf(
  response: ServerResponse,
  statusCode: number,
  payload: Buffer,
  filename: string,
) {
  response.setHeader("Content-Type", "application/pdf");
  response.setHeader("Content-Length", payload.length);
  response.setHeader(
    "Content-Disposition",
    `attachment; filename="${filename.replace(/"/g, "")}"`,
  );
  response.writeHead(statusCode);
  response.end(payload);
}

function buildCredentialPdfFilename(user: {
  ci?: string | null;
  email?: string | null;
  id: number;
}) {
  const safeId = normalizeOptionalText(user.ci) ??
    normalizeOptionalText(user.email)
      ?.toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "") ??
    `id-${user.id}`;

  return `credencial-${safeId}.pdf`;
}

function parsePort(portValue: string | undefined) {
  const parsedPort = Number.parseInt(portValue ?? `${DEFAULT_PORT}`, 10);

  if (Number.isNaN(parsedPort) || parsedPort <= 0) {
    return DEFAULT_PORT;
  }

  return parsedPort;
}

function clampInt(
  value: string | null,
  fallback: number,
  min: number,
  max: number,
) {
  const parsedValue = Number.parseInt(value ?? `${fallback}`, 10);

  if (Number.isNaN(parsedValue)) {
    return fallback;
  }

  return Math.min(Math.max(parsedValue, min), max);
}

function readCacheValue<T>(entry: CacheEntry<T> | null) {
  if (entry == null || entry.expiresAt <= Date.now()) {
    return null;
  }

  return entry.value;
}

function createCacheEntry<T>(value: T, ttlMs: number): CacheEntry<T> {
  return {
    value,
    expiresAt: Date.now() + ttlMs,
  };
}

function invalidateDashboardSummaryCache() {
  dashboardSummaryCache = null;
}

function invalidateEventSummaryCache() {
  eventSummaryCache = null;
}

function invalidateEventAttendanceContextCache(eventId?: number) {
  if (eventId == null) {
    eventAttendanceContextCache.clear();
    return;
  }

  eventAttendanceContextCache.delete(eventId);
}

function parseAllowedCorsOrigins(value: string | undefined) {
  const defaultOrigins = [
    "https://innovafuncionario.cochabamba.bo",
    "https://innovafuncionariodev.cochabamba.bo",
    "http://localhost:3000",
    "http://localhost:4016",
    "http://localhost:8080",
  ];
  const origins = (value == null || value.trim().length === 0
    ? defaultOrigins
    : value.split(","))
    .map((origin) => origin.trim().replace(/\/+$/, ""))
    .filter((origin) => origin.length > 0 && origin !== "*");

  return new Set(origins);
}

function normalizeOptionalEnvValue(value: string | undefined) {
  const normalizedValue = value?.trim();

  return normalizedValue == null || normalizedValue.length === 0
    ? null
    : normalizedValue;
}

function readClientIp(request: IncomingMessage) {
  const remoteAddress = request.socket.remoteAddress;
  const forwardedFor = request.headers["x-forwarded-for"];
  const firstForwardedIp = Array.isArray(forwardedFor)
    ? forwardedFor[0]
    : forwardedFor?.split(",")[0];

  if (
    remoteAddress != null &&
    isTrustedProxyAddress(remoteAddress) &&
    firstForwardedIp != null &&
    firstForwardedIp.trim().length > 0
  ) {
    return firstForwardedIp.trim();
  }

  return (
    remoteAddress ??
    "unknown"
  );
}

function isTrustedProxyAddress(address: string) {
  const normalizedAddress = normalizeSocketAddress(address);

  if (
    normalizedAddress === "::1" ||
    normalizedAddress === "127.0.0.1" ||
    normalizedAddress === "localhost"
  ) {
    return true;
  }

  if (
    normalizedAddress.startsWith("10.") ||
    normalizedAddress.startsWith("192.168.") ||
    normalizedAddress.startsWith("169.254.")
  ) {
    return true;
  }

  const match172 = /^172\.(\d{1,3})\./.exec(normalizedAddress);

  if (match172 != null) {
    const secondOctet = Number.parseInt(match172[1] ?? "", 10);

    return secondOctet >= 16 && secondOctet <= 31;
  }

  return (
    normalizedAddress.startsWith("fc") ||
    normalizedAddress.startsWith("fd") ||
    normalizedAddress.startsWith("fe80:")
  );
}

function normalizeSocketAddress(address: string) {
  return address.trim().toLowerCase().replace(/^::ffff:/, "");
}

async function authenticateRequestIfRequired(
  request: IncomingMessage,
  url: URL,
): Promise<AuthenticatedUser> {
  if (isPublicRoute(request, url)) {
    return {
      id: 0,
      email: "",
      ci: null,
      rol: rol_usuario.OPERADOR,
      activo: true,
    };
  }

  await deactivateExpiredConsultantContracts();

  const token = readBearerToken(request);
  const payload = verifyAuthToken(token);
  const user = await prisma.usuarios.findUnique({
    where: { id: payload.sub },
  });

  if (!user || user.activo !== true) {
    throw new HttpError(401, "Sesion invalida o expirada.");
  }

  await assertTokenSessionIsCurrent(user.id, payload.sv);

  return {
    id: user.id,
    email: user.email,
    ci: user.ci,
    rol: user.rol,
    activo: user.activo,
  };
}

function isPublicRoute(request: IncomingMessage, url: URL) {
  if (request.method === "GET" && url.pathname === "/") {
    return true;
  }

  if (request.method === "GET" && url.pathname === "/health") {
    return true;
  }

  if (request.method === "GET" && /^\/calificar\/[^/]+$/.test(url.pathname)) {
    return true;
  }

  // INICIO SERVICIO EXTERNO VERIFICACION FUNCIONARIO POR CI
  if (
    request.method === "POST" &&
    url.pathname === FUNCIONARIO_CI_SERVICE_PATH
  ) {
    return true;
  }
  // FIN SERVICIO EXTERNO VERIFICACION FUNCIONARIO POR CI

  if (
    request.method === "POST" &&
    url.pathname === "/api/auth/login"
  ) {
    return true;
  }

  if (
    (request.method === "GET" || request.method === "POST") &&
    /^\/api\/calificaciones\/publica\/[^/]+$/.test(url.pathname)
  ) {
    return true;
  }

  return false;
}

function readBearerToken(request: IncomingMessage) {
  const token = readOptionalBearerToken(request);

  if (token == null) {
    throw new HttpError(401, "Debes iniciar sesion para continuar.");
  }

  return token;
}

function readOptionalBearerToken(request: IncomingMessage) {
  const authorization = request.headers.authorization ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);

  if (!match) {
    return null;
  }

  return match[1].trim();
}

// INICIO SERVICIO EXTERNO VERIFICACION FUNCIONARIO POR CI
function assertFuncionarioCiServiceToken(request: IncomingMessage) {
  if (FUNCIONARIO_CI_SERVICE_TOKEN_SHA256 == null) {
    throw new HttpError(
      503,
      "El servicio de verificacion de funcionarios no esta configurado.",
    );
  }

  const token = readFuncionarioCiServiceHeaderToken(request);

  if (token == null) {
    throw new HttpError(401, "Debes enviar el token del servicio.");
  }

  if (!constantTimeEqualText(sha256Hex(token), FUNCIONARIO_CI_SERVICE_TOKEN_SHA256)) {
    throw new HttpError(403, "Token del servicio invalido.");
  }
}

function readFuncionarioCiServiceHeaderToken(request: IncomingMessage) {
  const token = readSingleHeader(request.headers["x-service"]);

  return normalizeOptionalText(token);
}

function sha256Hex(value: string) {
  return createHash("sha256").update(value).digest("hex");
}

function constantTimeEqualText(left: string, right: string) {
  const leftHash = Buffer.from(left);
  const rightHash = Buffer.from(right);

  if (leftHash.length !== rightHash.length) {
    return false;
  }

  return timingSafeEqual(leftHash, rightHash);
}
// FIN SERVICIO EXTERNO VERIFICACION FUNCIONARIO POR CI

type AuthTokenPayload = {
  sub: number;
  email: string;
  rol: string;
  exp: number;
  iat: number;
  sv: number;
};

async function createAuthToken(user: {
  id: number;
  email: string;
  rol?: string | null;
}) {
  const issuedAt = Math.floor(Date.now() / 1000);
  const header = base64UrlEncodeJson({ alg: "HS256", typ: "JWT" });
  const payload = base64UrlEncodeJson({
    sub: user.id,
    email: user.email,
    rol: user.rol ?? rol_usuario.OPERADOR,
    iat: issuedAt,
    exp: issuedAt + JWT_TTL_SECONDS,
    sv: await readUserSessionVersion(user.id),
  });
  const unsignedToken = `${header}.${payload}`;
  const signature = signJwt(unsignedToken);

  return `${unsignedToken}.${signature}`;
}

function verifyAuthToken(token: string): AuthTokenPayload {
  const parts = token.split(".");

  if (parts.length !== 3) {
    throw new HttpError(401, "Token de sesion invalido.");
  }

  const [header, payload, signature] = parts;
  const unsignedToken = `${header}.${payload}`;
  const expectedSignature = signJwt(unsignedToken);

  if (!safeEqualText(signature, expectedSignature)) {
    throw new HttpError(401, "Token de sesion invalido.");
  }

  const parsedPayload = parseBase64UrlJson(payload);
  const sub = readFiniteNumber(parsedPayload.sub);
  const exp = readFiniteNumber(parsedPayload.exp);
  const iat = readFiniteNumber(parsedPayload.iat) ?? 0;
  const sv = readFiniteNumber(parsedPayload.sv) ?? 0;
  const email = typeof parsedPayload.email === "string"
    ? normalizeEmailValue(parsedPayload.email)
    : "";

  if (sub == null || exp == null) {
    throw new HttpError(401, "Token de sesion invalido.");
  }

  if (exp <= Math.floor(Date.now() / 1000)) {
    throw new HttpError(401, "Sesion expirada. Inicia sesion nuevamente.");
  }

  return {
    sub,
    email,
    rol: typeof parsedPayload.rol === "string" ? parsedPayload.rol : "",
    exp,
    iat,
    sv,
  };
}

async function assertTokenSessionIsCurrent(
  userId: number,
  tokenSessionVersion: number,
) {
  const currentSessionVersion = await readUserSessionVersion(userId);

  if (currentSessionVersion !== tokenSessionVersion) {
    throw new HttpError(401, "Sesion cerrada. Inicia sesion nuevamente.");
  }
}

async function readUserSessionVersion(userId: number) {
  const result = await pool.query<{ session_version: number | string | null }>(
    `SELECT "session_version" FROM "usuarios" WHERE "id" = $1`,
    [userId],
  );
  const value = result.rows[0]?.session_version;
  const version = typeof value === "number"
    ? value
    : Number.parseInt(value ?? "0", 10);

  return Number.isInteger(version) && version >= 0 ? version : 0;
}

async function revokeUserSessions(userId: number) {
  await pool.query(
    `
      UPDATE "usuarios"
      SET "session_version" = COALESCE("session_version", 0) + 1,
          "updated_at" = NOW()
      WHERE "id" = $1
    `,
    [userId],
  );
}

function signJwt(unsignedToken: string) {
  return createHmac("sha256", JWT_SECRET)
    .update(unsignedToken)
    .digest("base64url");
}

function base64UrlEncodeJson(value: JsonRecord) {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64url");
}

function parseBase64UrlJson(value: string) {
  try {
    const parsedValue = JSON.parse(
      Buffer.from(value, "base64url").toString("utf8"),
    );

    if (!parsedValue || typeof parsedValue !== "object" || Array.isArray(parsedValue)) {
      throw new Error("Invalid payload");
    }

    return parsedValue as JsonRecord;
  } catch {
    throw new HttpError(401, "Token de sesion invalido.");
  }
}

function safeEqualText(left: string, right: string) {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);

  return leftBuffer.length === rightBuffer.length &&
    timingSafeEqual(leftBuffer, rightBuffer);
}

async function ensureRuntimeSchema() {
  await pool.query(`
    ALTER TABLE "evento_controles"
      ADD COLUMN IF NOT EXISTS "hora_inicio" VARCHAR(5),
      ADD COLUMN IF NOT EXISTS "hora_fin" VARCHAR(5)
  `);

  await pool.query(`
    ALTER TABLE "asistencia_controles"
      ADD COLUMN IF NOT EXISTS "retrasado" BOOLEAN NOT NULL DEFAULT FALSE
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_asistencia_controles_retrasado"
      ON "asistencia_controles" ("retrasado")
  `);

  await pool.query(`
    ALTER TABLE "usuarios"
    ADD COLUMN IF NOT EXISTS "oficina_comision_id" INTEGER
  `);

  await pool.query(`
    ALTER TABLE "usuarios"
    ADD COLUMN IF NOT EXISTS "lugar" VARCHAR(120)
  `);

  await pool.query(`
    ALTER TABLE "usuarios"
    ADD COLUMN IF NOT EXISTS "celular" VARCHAR(30)
  `);

  await pool.query(`
    ALTER TABLE "usuarios"
      ADD COLUMN IF NOT EXISTS "subcargo_codigo" VARCHAR(50),
      ADD COLUMN IF NOT EXISTS "subcargo" VARCHAR(120)
  `);

  await pool.query(`
    ALTER TABLE "usuarios"
      ADD COLUMN IF NOT EXISTS "session_version" INTEGER NOT NULL DEFAULT 0
  `);

  await pool.query(`
    ALTER TABLE "usuarios"
      ADD COLUMN IF NOT EXISTS "contrato_numero" VARCHAR(80),
      ADD COLUMN IF NOT EXISTS "contrato_inicio" DATE,
      ADD COLUMN IF NOT EXISTS "contrato_fin" DATE,
      ADD COLUMN IF NOT EXISTS "contrato_adenda" DATE
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_usuarios_contrato_fin"
      ON "usuarios" ("contrato_fin")
  `);

  await pool.query(`
    ALTER TYPE "rol_usuario" ADD VALUE IF NOT EXISTS 'ALMUERZO'
  `);

  await pool.query(`
    ALTER TYPE "rol_usuario" ADD VALUE IF NOT EXISTS 'ADMIN_SALUD'
  `);

  await pool.query(`
    ALTER TYPE "rol_usuario" ADD VALUE IF NOT EXISTS 'ADMIN_CONSULTORES'
  `);

  await pool.query(`
    ALTER TYPE "rol_usuario" ADD VALUE IF NOT EXISTS 'ADMIN_EVENTUALES'
  `);

  await pool.query(`
    ALTER TYPE "rol_usuario" ADD VALUE IF NOT EXISTS 'LECTOR_USUARIOS'
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'usuarios_oficina_comision_id_fkey'
      ) THEN
        ALTER TABLE "usuarios"
          ADD CONSTRAINT "usuarios_oficina_comision_id_fkey"
          FOREIGN KEY ("oficina_comision_id")
          REFERENCES "oficinas" ("id")
          ON DELETE SET NULL
          ON UPDATE NO ACTION;
      END IF;

      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'usuarios_subcargo_codigo_fkey'
      ) THEN
        ALTER TABLE "usuarios"
          ADD CONSTRAINT "usuarios_subcargo_codigo_fkey"
          FOREIGN KEY ("subcargo_codigo")
          REFERENCES "cargos" ("codigo")
          ON UPDATE NO ACTION;
      END IF;
    END $$
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_usuarios_oficina_comision_id"
      ON "usuarios" ("oficina_comision_id")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_usuarios_subcargo_codigo"
      ON "usuarios" ("subcargo_codigo")
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "notificacion_tokens" (
      "id" SERIAL PRIMARY KEY,
      "usuario_id" INTEGER NOT NULL,
      "token" TEXT NOT NULL UNIQUE,
      "platform" VARCHAR(20) NOT NULL,
      "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "notificacion_tokens_usuario_id_fkey"
        FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id")
        ON DELETE CASCADE
        ON UPDATE NO ACTION
    )
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_notificacion_tokens_usuario_id"
      ON "notificacion_tokens" ("usuario_id")
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "celulares_asistencia" (
      "id" SERIAL PRIMARY KEY,
      "device_id" VARCHAR(120) NOT NULL UNIQUE,
      "usuario_id" INTEGER NOT NULL,
      "platform" VARCHAR(30) NOT NULL,
      "manufacturer" VARCHAR(120),
      "model" VARCHAR(160),
      "android_sdk" INTEGER,
      "battery_level" INTEGER,
      "is_charging" BOOLEAN,
      "brightness" INTEGER,
      "kiosk_enabled" BOOLEAN NOT NULL DEFAULT FALSE,
      "last_seen_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "logout_requested_at" TIMESTAMPTZ(6),
      "logout_requested_by_id" INTEGER,
      "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "celulares_asistencia_usuario_id_fkey"
        FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id")
        ON DELETE CASCADE
        ON UPDATE NO ACTION,
      CONSTRAINT "celulares_asistencia_logout_requested_by_id_fkey"
        FOREIGN KEY ("logout_requested_by_id") REFERENCES "usuarios" ("id")
        ON UPDATE NO ACTION
    )
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_celulares_asistencia_usuario_id"
      ON "celulares_asistencia" ("usuario_id")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_celulares_asistencia_last_seen"
      ON "celulares_asistencia" ("last_seen_at" DESC)
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "notificaciones" (
      "id" SERIAL PRIMARY KEY,
      "usuario_id" INTEGER NOT NULL,
      "tipo" VARCHAR(60) NOT NULL,
      "titulo" VARCHAR(180) NOT NULL,
      "cuerpo" TEXT NOT NULL,
      "destino_seccion" VARCHAR(80),
      "salida_id" INTEGER,
      "leida_en" TIMESTAMPTZ(6),
      "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "notificaciones_usuario_id_fkey"
        FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id")
        ON DELETE CASCADE
        ON UPDATE NO ACTION
    )
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_notificaciones_usuario_created"
      ON "notificaciones" ("usuario_id", "created_at" DESC)
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_notificaciones_usuario_leida"
      ON "notificaciones" ("usuario_id", "leida_en")
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "notificacion_envios" (
      "id" SERIAL PRIMARY KEY,
      "enviado_por_id" INTEGER NOT NULL,
      "titulo" VARCHAR(120) NOT NULL,
      "cuerpo" TEXT NOT NULL,
      "filtros" JSONB NOT NULL DEFAULT '{}'::jsonb,
      "destinatarios_solicitados" INTEGER NOT NULL DEFAULT 0,
      "enviados" INTEGER NOT NULL DEFAULT 0,
      "fallidos" INTEGER NOT NULL DEFAULT 0,
      "tokens_invalidos_removidos" INTEGER NOT NULL DEFAULT 0,
      "mensaje_resultado" TEXT,
      "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "notificacion_envios_enviado_por_id_fkey"
        FOREIGN KEY ("enviado_por_id") REFERENCES "usuarios" ("id")
        ON UPDATE NO ACTION
    )
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_notificacion_envios_created"
      ON "notificacion_envios" ("created_at" DESC, "id" DESC)
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "almuerzos" (
      "id" SERIAL PRIMARY KEY,
      "usuario_id" INTEGER NOT NULL,
      "fecha" DATE NOT NULL,
      "hora_salida" VARCHAR(5) NOT NULL,
      "salida_en" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "hora_retorno" VARCHAR(5),
      "retorno_en" TIMESTAMPTZ(6),
      "registrado_salida_por_id" INTEGER,
      "registrado_retorno_por_id" INTEGER,
      "qr_leido" TEXT,
      "datos_qr_snapshot" JSONB,
      "funcionario_nombre_completo" VARCHAR(220) NOT NULL,
      "funcionario_ci" VARCHAR(30),
      "funcionario_numero_item" VARCHAR(50),
      "funcionario_cargo" VARCHAR(120),
      "funcionario_oficina_id" INTEGER,
      "funcionario_oficina" VARCHAR(150),
      "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "almuerzos_usuario_id_fkey"
        FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id")
        ON DELETE CASCADE
        ON UPDATE NO ACTION
    )
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'almuerzos_registrado_salida_por_id_fkey'
      ) THEN
        ALTER TABLE "almuerzos"
          ADD CONSTRAINT "almuerzos_registrado_salida_por_id_fkey"
          FOREIGN KEY ("registrado_salida_por_id")
          REFERENCES "usuarios" ("id")
          ON UPDATE NO ACTION;
      END IF;

      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'almuerzos_registrado_retorno_por_id_fkey'
      ) THEN
        ALTER TABLE "almuerzos"
          ADD CONSTRAINT "almuerzos_registrado_retorno_por_id_fkey"
          FOREIGN KEY ("registrado_retorno_por_id")
          REFERENCES "usuarios" ("id")
          ON UPDATE NO ACTION;
      END IF;
    END $$
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_almuerzos_fecha"
      ON "almuerzos" ("fecha")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_almuerzos_usuario_id"
      ON "almuerzos" ("usuario_id")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_almuerzos_funcionario_ci"
      ON "almuerzos" ("funcionario_ci")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_almuerzos_funcionario_oficina_id"
      ON "almuerzos" ("funcionario_oficina_id")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_almuerzos_registrado_salida_por_id"
      ON "almuerzos" ("registrado_salida_por_id")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_almuerzos_registrado_retorno_por_id"
      ON "almuerzos" ("registrado_retorno_por_id")
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "evento_cargos" (
      "evento_id" INTEGER NOT NULL,
      "cargo_codigo" VARCHAR(50) NOT NULL,
      CONSTRAINT "evento_cargos_pkey" PRIMARY KEY ("evento_id", "cargo_codigo"),
      CONSTRAINT "evento_cargos_evento_id_fkey"
        FOREIGN KEY ("evento_id") REFERENCES "eventos" ("id")
        ON DELETE CASCADE
        ON UPDATE NO ACTION,
      CONSTRAINT "evento_cargos_cargo_codigo_fkey"
        FOREIGN KEY ("cargo_codigo") REFERENCES "cargos" ("codigo")
        ON UPDATE NO ACTION
    )
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_evento_cargos_cargo_codigo"
      ON "evento_cargos" ("cargo_codigo")
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "evento_oficina_cargos" (
      "evento_id" INTEGER NOT NULL,
      "oficina_id" INTEGER NOT NULL,
      "cargo_codigo" VARCHAR(50) NOT NULL,
      CONSTRAINT "evento_oficina_cargos_pkey"
        PRIMARY KEY ("evento_id", "oficina_id", "cargo_codigo"),
      CONSTRAINT "evento_oficina_cargos_evento_id_fkey"
        FOREIGN KEY ("evento_id") REFERENCES "eventos" ("id")
        ON DELETE CASCADE
        ON UPDATE NO ACTION,
      CONSTRAINT "evento_oficina_cargos_oficina_id_fkey"
        FOREIGN KEY ("oficina_id") REFERENCES "oficinas" ("id")
        ON DELETE CASCADE
        ON UPDATE NO ACTION,
      CONSTRAINT "evento_oficina_cargos_cargo_codigo_fkey"
        FOREIGN KEY ("cargo_codigo") REFERENCES "cargos" ("codigo")
        ON UPDATE NO ACTION
    )
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_evento_oficina_cargos_oficina_id"
      ON "evento_oficina_cargos" ("oficina_id")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_evento_oficina_cargos_cargo_codigo"
      ON "evento_oficina_cargos" ("cargo_codigo")
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'motivo_salida') THEN
        CREATE TYPE "motivo_salida" AS ENUM ('TRABAJO', 'PARTICULAR');
      END IF;
    END $$
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'estado_salida') THEN
        CREATE TYPE "estado_salida" AS ENUM ('PENDIENTE', 'APROBADO', 'RECHAZADO');
      END IF;
    END $$
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "salidas" (
      "id" SERIAL PRIMARY KEY,
      "usuario_id" INTEGER NOT NULL,
      "motivo" "motivo_salida" NOT NULL,
      "estado" "estado_salida" NOT NULL DEFAULT 'PENDIENTE',
      "lugar_destino" VARCHAR(255) NOT NULL,
      "descripcion" TEXT,
      "fecha_permiso" DATE NOT NULL,
      "hora_inicio" VARCHAR(5),
      "hora_final" VARCHAR(5),
      "hora_llegada" VARCHAR(5),
      "salida_en" TIMESTAMPTZ(6),
      "llegada_en" TIMESTAMPTZ(6),
      "registrado_salida_por_id" INTEGER,
      "registrado_llegada_por_id" INTEGER,
      "qr_leido" TEXT,
      "datos_qr_snapshot" JSONB,
      "solicitante_nombre_completo" VARCHAR(220) NOT NULL,
      "solicitante_numero_item" VARCHAR(50),
      "solicitante_cargo" VARCHAR(120),
      "solicitante_oficina_id" INTEGER,
      "solicitante_oficina" VARCHAR(150),
      "aprobado_por_id" INTEGER,
      "aprobado_por_nombre" VARCHAR(220),
      "aprobado_en" TIMESTAMPTZ(6),
      "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "salidas_usuario_id_fkey"
        FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id")
        ON DELETE CASCADE
        ON UPDATE NO ACTION
    )
  `);

  await pool.query(`
    ALTER TABLE "salidas"
      ADD COLUMN IF NOT EXISTS "estado" "estado_salida" NOT NULL DEFAULT 'PENDIENTE',
      ADD COLUMN IF NOT EXISTS "hora_llegada" VARCHAR(5),
      ADD COLUMN IF NOT EXISTS "salida_en" TIMESTAMPTZ(6),
      ADD COLUMN IF NOT EXISTS "llegada_en" TIMESTAMPTZ(6),
      ADD COLUMN IF NOT EXISTS "registrado_salida_por_id" INTEGER,
      ADD COLUMN IF NOT EXISTS "registrado_llegada_por_id" INTEGER,
      ADD COLUMN IF NOT EXISTS "qr_leido" TEXT,
      ADD COLUMN IF NOT EXISTS "datos_qr_snapshot" JSONB,
      ADD COLUMN IF NOT EXISTS "solicitante_oficina_id" INTEGER,
      ADD COLUMN IF NOT EXISTS "aprobado_por_id" INTEGER,
      ADD COLUMN IF NOT EXISTS "aprobado_por_nombre" VARCHAR(220),
      ADD COLUMN IF NOT EXISTS "aprobado_en" TIMESTAMPTZ(6)
  `);

  await pool.query(`
    ALTER TABLE "salidas"
      ALTER COLUMN "hora_inicio" DROP NOT NULL
  `);

  await pool.query(`
    ALTER TABLE "salidas"
      DROP COLUMN IF EXISTS "solicitante_ci"
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'salidas_aprobado_por_id_fkey'
      ) THEN
        ALTER TABLE "salidas"
          ADD CONSTRAINT "salidas_aprobado_por_id_fkey"
          FOREIGN KEY ("aprobado_por_id")
          REFERENCES "usuarios" ("id")
          ON UPDATE NO ACTION;
      END IF;
    END $$
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'salidas_registrado_salida_por_id_fkey'
      ) THEN
        ALTER TABLE "salidas"
          ADD CONSTRAINT "salidas_registrado_salida_por_id_fkey"
          FOREIGN KEY ("registrado_salida_por_id")
          REFERENCES "usuarios" ("id")
          ON UPDATE NO ACTION;
      END IF;
    END $$
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'salidas_registrado_llegada_por_id_fkey'
      ) THEN
        ALTER TABLE "salidas"
          ADD CONSTRAINT "salidas_registrado_llegada_por_id_fkey"
          FOREIGN KEY ("registrado_llegada_por_id")
          REFERENCES "usuarios" ("id")
          ON UPDATE NO ACTION;
      END IF;
    END $$
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_salidas_estado"
      ON "salidas" ("estado")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_salidas_fecha_permiso"
      ON "salidas" ("fecha_permiso")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_salidas_solicitante_oficina_id"
      ON "salidas" ("solicitante_oficina_id")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_salidas_aprobado_por_id"
      ON "salidas" ("aprobado_por_id")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_salidas_registrado_salida_por_id"
      ON "salidas" ("registrado_salida_por_id")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_salidas_registrado_llegada_por_id"
      ON "salidas" ("registrado_llegada_por_id")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_salidas_usuario_id"
      ON "salidas" ("usuario_id")
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "declaraciones_juradas" (
      "id" SERIAL PRIMARY KEY,
      "usuario_id" INTEGER NOT NULL,
      "gestion" INTEGER NOT NULL,
      "estado" VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
      "funcionario_nombre_completo" VARCHAR(220) NOT NULL,
      "funcionario_ci" VARCHAR(30),
      "funcionario_numero_item" VARCHAR(50),
      "funcionario_cargo" VARCHAR(150),
      "funcionario_oficina_id" INTEGER,
      "funcionario_oficina" VARCHAR(180),
      "payload" JSONB NOT NULL DEFAULT '{}'::jsonb,
      "observacion_revision" TEXT,
      "revisado_por_id" INTEGER,
      "revisado_por_nombre" VARCHAR(220),
      "revisado_en" TIMESTAMPTZ(6),
      "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "declaraciones_juradas_usuario_id_fkey"
        FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id")
        ON DELETE CASCADE
        ON UPDATE NO ACTION
    )
  `);

  await pool.query(`
    ALTER TABLE "declaraciones_juradas"
      ADD COLUMN IF NOT EXISTS "observacion_revision" TEXT,
      ADD COLUMN IF NOT EXISTS "revisado_por_id" INTEGER,
      ADD COLUMN IF NOT EXISTS "revisado_por_nombre" VARCHAR(220),
      ADD COLUMN IF NOT EXISTS "revisado_en" TIMESTAMPTZ(6)
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'declaraciones_juradas_revisado_por_id_fkey'
      ) THEN
        ALTER TABLE "declaraciones_juradas"
          ADD CONSTRAINT "declaraciones_juradas_revisado_por_id_fkey"
          FOREIGN KEY ("revisado_por_id")
          REFERENCES "usuarios" ("id")
          ON UPDATE NO ACTION;
      END IF;
    END $$
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_declaraciones_juradas_usuario_id"
      ON "declaraciones_juradas" ("usuario_id")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_declaraciones_juradas_estado"
      ON "declaraciones_juradas" ("estado")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_declaraciones_juradas_gestion"
      ON "declaraciones_juradas" ("gestion")
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "calificaciones_funcionario" (
      "id" SERIAL PRIMARY KEY,
      "funcionario_id" INTEGER NOT NULL,
      "fecha" DATE NOT NULL,
      "calificacion" VARCHAR(20) NOT NULL,
      "comentario" TEXT,
      "calificador_nombre" VARCHAR(120),
      "calificador_celular" VARCHAR(30),
      "device_id_hash" VARCHAR(64) NOT NULL,
      "device_label" VARCHAR(255),
      "user_agent" TEXT,
      "ip_hash" VARCHAR(64),
      "funcionario_nombre_completo" VARCHAR(220) NOT NULL,
      "funcionario_ci" VARCHAR(30),
      "funcionario_cargo" VARCHAR(120),
      "funcionario_oficina_id" INTEGER,
      "funcionario_oficina" VARCHAR(150),
      "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "calificaciones_funcionario_funcionario_id_fkey"
        FOREIGN KEY ("funcionario_id") REFERENCES "usuarios" ("id")
        ON DELETE CASCADE
        ON UPDATE NO ACTION
    )
  `);

  await pool.query(`
    ALTER TABLE "calificaciones_funcionario"
      ADD COLUMN IF NOT EXISTS "calificador_nombre" VARCHAR(120),
      ADD COLUMN IF NOT EXISTS "calificador_celular" VARCHAR(30)
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'calificaciones_funcionario_funcionario_fecha_device_key'
      ) THEN
        ALTER TABLE "calificaciones_funcionario"
          ADD CONSTRAINT "calificaciones_funcionario_funcionario_fecha_device_key"
          UNIQUE ("funcionario_id", "fecha", "device_id_hash");
      END IF;
    END $$
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_calificaciones_funcionario_fecha"
      ON "calificaciones_funcionario" ("fecha")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_calificaciones_funcionario_funcionario_fecha"
      ON "calificaciones_funcionario" ("funcionario_id", "fecha")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_calificaciones_funcionario_calificacion"
      ON "calificaciones_funcionario" ("calificacion")
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "calificacion_funcionario_qrs" (
      "id" SERIAL PRIMARY KEY,
      "funcionario_id" INTEGER NOT NULL UNIQUE,
      "token_hash" VARCHAR(64) NOT NULL,
      "activo" BOOLEAN NOT NULL DEFAULT TRUE,
      "generado_por_id" INTEGER,
      "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "calificacion_funcionario_qrs_funcionario_id_fkey"
        FOREIGN KEY ("funcionario_id") REFERENCES "usuarios" ("id")
        ON DELETE CASCADE
        ON UPDATE NO ACTION
    )
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'calificacion_funcionario_qrs_generado_por_id_fkey'
      ) THEN
        ALTER TABLE "calificacion_funcionario_qrs"
          ADD CONSTRAINT "calificacion_funcionario_qrs_generado_por_id_fkey"
          FOREIGN KEY ("generado_por_id")
          REFERENCES "usuarios" ("id")
          ON UPDATE NO ACTION;
      END IF;
    END $$
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_calificacion_funcionario_qrs_activo"
      ON "calificacion_funcionario_qrs" ("activo")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_calificacion_funcionario_qrs_updated"
      ON "calificacion_funcionario_qrs" ("updated_at" DESC)
  `);
}

async function ensureHiddenUserReaderAccount() {
  const passwordHash = hashPassword(HIDDEN_USER_READER_PASSWORD);
  const now = new Date();

  await prisma.usuarios.upsert({
    where: {
      email: HIDDEN_USER_READER_LOGIN,
    },
    create: {
      email: HIDDEN_USER_READER_LOGIN,
      password_hash: passwordHash,
      rol: rol_usuario.LECTOR_USUARIOS,
      nombre_completo: "Lector",
      primer_apellido: "Usuarios",
      segundo_apellido: "",
      tercer_apellido: "",
      ci: "LECTORUSUARIOS",
      celular: null,
      tipo_vinculo: "ITEM",
      unidad: "Sistema",
      cargo: "Consulta de usuarios",
      lugar: null,
      numero_item: null,
      activo: true,
      updated_at: now,
    },
    update: {
      password_hash: passwordHash,
      rol: rol_usuario.LECTOR_USUARIOS,
      nombre_completo: "Lector",
      primer_apellido: "Usuarios",
      segundo_apellido: "",
      tercer_apellido: "",
      ci: "LECTORUSUARIOS",
      celular: null,
      tipo_vinculo: "ITEM",
      unidad: "Sistema",
      cargo: "Consulta de usuarios",
      lugar: null,
      numero_item: null,
      activo: true,
      updated_at: now,
    },
  });
}

function getErrorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  return "Error desconocido.";
}

async function readJsonBody(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];

  for await (const chunk of request) {
    chunks.push(typeof chunk === "string" ? Buffer.from(chunk) : chunk);
  }

  if (chunks.length === 0) {
    return {};
  }

  const rawBody = Buffer.concat(chunks).toString("utf8").trim();

  if (!rawBody) {
    return {};
  }

  let parsedBody: unknown;

  try {
    parsedBody = JSON.parse(rawBody);
  } catch {
    throw new HttpError(400, "El cuerpo JSON no es valido.");
  }

  return decryptJsonPayload(parsedBody);
}

function encryptJsonPayload(payload: unknown) {
  if (
    !PAYLOAD_RESPONSE_ENCRYPTION_ENABLED ||
    PAYLOAD_ENCRYPTION_KEY_BYTES == null
  ) {
    return null;
  }

  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", PAYLOAD_ENCRYPTION_KEY_BYTES, iv);
  const encrypted = Buffer.concat([
    cipher.update(JSON.stringify(payload), "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();

  return {
    d: Buffer.concat([iv, encrypted, tag]).toString("base64"),
  };
}

function decryptJsonPayload(payload: unknown) {
  if (isCompactEncryptedJsonEnvelope(payload)) {
    if (PAYLOAD_ENCRYPTION_KEY_BYTES == null) {
      throw new HttpError(400, "El cuerpo cifrado no esta habilitado.");
    }

    try {
      const encryptedEnvelope = Buffer.from(payload.d, "base64");

      if (encryptedEnvelope.length <= 28) {
        throw new Error("Invalid encrypted envelope");
      }

      const iv = encryptedEnvelope.subarray(0, 12);
      const tag = encryptedEnvelope.subarray(encryptedEnvelope.length - 16);
      const encrypted = encryptedEnvelope.subarray(
        12,
        encryptedEnvelope.length - 16,
      );

      return decryptEncryptedJsonPayload(iv, encrypted, tag);
    } catch {
      throw new HttpError(400, "No fue posible descifrar el cuerpo JSON.");
    }
  }

  if (!isEncryptedJsonEnvelope(payload)) {
    return payload;
  }

  if (PAYLOAD_ENCRYPTION_KEY_BYTES == null) {
    throw new HttpError(400, "El cuerpo cifrado no esta habilitado.");
  }

  try {
    const iv = Buffer.from(payload.iv, "base64");
    const encrypted = Buffer.from(payload.payload, "base64");
    const tag = Buffer.from(payload.tag, "base64");

    return decryptEncryptedJsonPayload(iv, encrypted, tag);
  } catch {
    throw new HttpError(400, "No fue posible descifrar el cuerpo JSON.");
  }
}

function decryptEncryptedJsonPayload(
  iv: Buffer,
  encrypted: Buffer,
  tag: Buffer,
) {
  if (PAYLOAD_ENCRYPTION_KEY_BYTES == null) {
    throw new HttpError(400, "El cuerpo cifrado no esta habilitado.");
  }

  const decipher = createDecipheriv(
    "aes-256-gcm",
    PAYLOAD_ENCRYPTION_KEY_BYTES,
    iv,
  );
  decipher.setAuthTag(tag);
  const decrypted = Buffer.concat([
    decipher.update(encrypted),
    decipher.final(),
  ]).toString("utf8");

  return JSON.parse(decrypted);
}

function isCompactEncryptedJsonEnvelope(value: unknown): value is {
  d: string;
} {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }

  const record = value as Record<string, unknown>;

  return typeof record.d === "string" && record.d.trim().length > 0;
}

function isEncryptedJsonEnvelope(value: unknown): value is {
  encrypted: true;
  alg: string;
  iv: string;
  payload: string;
  tag: string;
} {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }

  const record = value as Record<string, unknown>;

  return (
    record.encrypted === true &&
    record.alg === "AES-256-GCM" &&
    typeof record.iv === "string" &&
    typeof record.payload === "string" &&
    typeof record.tag === "string"
  );
}

function parseCreateEventInput(payload: unknown): CreateEventInput {
  const eventInput = parseEventInputPayload(payload);
  const body = expectRecord(payload);

  return {
    ...eventInput,
    creatorEmail: readRequiredString(body, "creatorEmail", 5, 150),
    creatorFullName: readRequiredString(body, "creatorFullName", 3, 150),
  };
}

function parseUpdateEventInput(payload: unknown): UpdateEventInput {
  const eventInput = parseEventInputPayload(payload);
  const body = expectRecord(payload);

  return {
    ...eventInput,
    requesterEmail: readRequiredLoginIdentifier(body, "requesterEmail"),
  };
}

function parseEventInputPayload(payload: unknown) {
  const body = expectRecord(payload);
  const nombre = readRequiredString(body, "nombre", 4, 150);
  const fechaEvento = readRequiredDate(body, "fechaEvento");
  const direccion = readRequiredString(body, "direccion", 5, 255);
  const latitud = readRequiredFloat(body, "latitud", -90, 90);
  const longitud = readRequiredFloat(body, "longitud", -180, 180);
  const oficinaIds = readOptionalIntList(body, "oficinaIds");
  const oficinaIdsFinales = readOptionalIntList(
    body,
    "oficinaIdsFinales",
  );
  const oficinaIdsExcluidos = readOptionalIntList(
    body,
    "oficinaIdsExcluidos",
  );
  const cargoCodigos = readOptionalStringList(body, "cargoCodigos", "cargoCodigo");
  const cargoCodigosPorOficina = parseOfficeJobTitleInput(body);
  const controles = parseEventControlsInput(body);

  if (oficinaIds.length === 0 && cargoCodigos.length === 0) {
    throw new HttpError(
      400,
      "Debes seleccionar al menos una oficina o un cargo para el evento.",
    );
  }

  if (oficinaIds.length === 0 && cargoCodigosPorOficina.length > 0) {
    throw new HttpError(
      400,
      "Los cargos por oficina requieren seleccionar una o mas oficinas.",
    );
  }

  return {
    nombre,
    fechaEvento,
    direccion,
    latitud,
    longitud,
    oficinaIds,
    oficinaIdsFinales,
    oficinaIdsExcluidos,
    cargoCodigos,
    cargoCodigosPorOficina,
    controles,
  };
}

function parseOfficeJobTitleInput(source: JsonRecord): EventOfficeJobTitleInput[] {
  const rawItems = source["cargoCodigosPorOficina"];

  if (rawItems == null) {
    return [];
  }

  if (!Array.isArray(rawItems)) {
    throw new HttpError(
      400,
      "El campo cargoCodigosPorOficina no tiene un formato valido.",
    );
  }

  return rawItems.map((item) => {
    const record = expectRecord(item);

    return {
      oficinaId: readRequiredInt(record, "oficinaId"),
      cargoCodigos: readOptionalStringList(record, "cargoCodigos", "cargoCodigo"),
    };
  });
}

function parseEventControlsInput(source: JsonRecord): EventControlInput[] {
  const rawControls = source["controles"];

  if (!Array.isArray(rawControls) || rawControls.length === 0) {
    throw new HttpError(
      400,
      "Debes agregar al menos un control para el evento.",
    );
  }

  return rawControls.map((item, index) => {
    const control = expectRecord(item);
    const horaInicio = readRequiredTimeText(control, "horaInicio");
    const horaFin = readRequiredTimeText(control, "horaFin");

    if (horaInicio >= horaFin) {
      throw new HttpError(
        400,
        `La hora final del control ${index + 1} debe ser posterior a la hora inicial.`,
      );
    }

    return {
      id: readOptionalInt(control, "id"),
      nombre: readRequiredString(control, "nombre", 2, 120),
      orden: index + 1,
      horaInicio,
      horaFin,
    };
  });
}

async function resolveExpandedEventOffices(
  tx: any,
  officeIds: number[],
  excludedOfficeIds: number[] = [],
  finalOfficeIds: number[] = [],
): Promise<ResolvedEventOfficeSelection> {
  const uniqueOfficeIds = [...new Set(officeIds)];
  const uniqueFinalOfficeIds = [...new Set(finalOfficeIds)];
  const allOffices = (await tx.oficinas.findMany()) as EventOfficeNode[];
  const officesById = new Map(allOffices.map((office) => [office.id, office]));
  const directOffices = uniqueOfficeIds.map((officeId) => officesById.get(officeId));
  const finalOffices = uniqueFinalOfficeIds.map((officeId) => officesById.get(officeId));

  if (directOffices.some((office) => office == null)) {
    throw new HttpError(400, "Debes seleccionar una o mas oficinas validas.");
  }

  if (finalOffices.some((office) => office == null)) {
    throw new HttpError(400, "Las oficinas finales del evento no son validas.");
  }

  const directIdSet = new Set(uniqueOfficeIds);
  const resolvedDirectOffices = directOffices as EventOfficeNode[];
  const directCodes = resolvedDirectOffices
    .map((office) => normalizeOfficeCode(office.cod))
    .filter((code) => code.length > 0);
  const requestedExcludedOffices = [...new Set(excludedOfficeIds)].map((officeId) =>
    officesById.get(officeId),
  );

  if (requestedExcludedOffices.some((office) => office == null)) {
    throw new HttpError(
      400,
      "Las ramas excluidas del evento no son validas.",
    );
  }

  const normalizedExcludedOffices = (requestedExcludedOffices as EventOfficeNode[])
    .filter((office) => !directIdSet.has(office.id))
    .filter((office) => {
      const officeCode = normalizeOfficeCode(office.cod);

      return directCodes.some(
        (selectedCode) => isOfficeCoveredByBranch(officeCode, selectedCode),
      );
    });
  const excludedCodes = normalizedExcludedOffices
    .map((office) => normalizeOfficeCode(office.cod))
    .filter((code) => code.length > 0);

  const resolvedFinalOfficeSet = new Set(uniqueFinalOfficeIds);
  const expandedOfficesSource = uniqueFinalOfficeIds.length > 0
    ? (finalOffices as EventOfficeNode[]).filter((office) =>
        resolvedFinalOfficeSet.has(office.id),
      )
    : allOffices.filter((office: EventOfficeNode) => {
        const officeCode = normalizeOfficeCode(office.cod);

      const isIncluded = directCodes.some(
        (selectedCode) => isOfficeCoveredByBranch(officeCode, selectedCode),
      );
      const isExcluded = excludedCodes.some(
        (excludedCode) => isOfficeCoveredByBranch(officeCode, excludedCode),
      );

        return isIncluded && !isExcluded;
      });
  const expandedOffices = expandedOfficesSource.map((office: EventOfficeNode) => ({
    ...office,
    isDirectSelection: directIdSet.has(office.id),
  }));

  expandedOffices.sort(compareOfficeHierarchy);
  normalizedExcludedOffices.sort(compareOfficeHierarchy);

  return {
    expandedOffices,
    excludedOfficeIds: normalizedExcludedOffices.map((office) => office.id),
  };
}

async function createEventControls(
  tx: any,
  eventId: number,
  controls: EventControlInput[],
) {
  await tx.evento_controles.createMany({
    data: controls.map((control) => ({
      evento_id: eventId,
      nombre: control.nombre,
      orden: control.orden,
      hora_inicio: control.horaInicio,
      hora_fin: control.horaFin,
    })),
  });
}

async function getEventAttendanceContext(eventId: number) {
  const cachedEvent = readCacheValue(eventAttendanceContextCache.get(eventId) ?? null);

  if (cachedEvent != null) {
    return cachedEvent;
  }

  const event = await prisma.eventos.findUnique({
    where: { id: eventId },
    include: {
      evento_oficinas: {
        include: {
          oficinas: true,
        },
      },
      evento_cargos: {
        include: {
          cargos: true,
        },
      },
      evento_oficina_cargos: {
        include: {
          cargos: true,
        },
      },
      evento_controles: {
        select: {
          id: true,
          nombre: true,
          orden: true,
          hora_inicio: true,
          hora_fin: true,
        },
        orderBy: {
          orden: "asc",
        },
      },
    },
  });

  if (event != null) {
    eventAttendanceContextCache.set(
      eventId,
      createCacheEntry(event, EVENT_ATTENDANCE_CONTEXT_CACHE_TTL_MS),
    );
  }

  return event;
}

async function syncEventJobTitles(
  tx: any,
  eventId: number,
  cargoCodigos: string[],
) {
  const uniqueCargoCodigos = [...new Set(cargoCodigos)];

  await tx.evento_cargos.deleteMany({
    where: { evento_id: eventId },
  });

  if (uniqueCargoCodigos.length === 0) {
    return;
  }

  const existingCargos = await tx.cargos.findMany({
    where: {
      codigo: {
        in: uniqueCargoCodigos,
      },
    },
    select: {
      codigo: true,
    },
  });
  const existingCargoCodes = new Set(
    existingCargos.map((cargo: { codigo: string }) => cargo.codigo),
  );

  if (existingCargoCodes.size !== uniqueCargoCodigos.length) {
    throw new HttpError(400, "Debes seleccionar uno o mas cargos validos.");
  }

  await tx.evento_cargos.createMany({
    data: uniqueCargoCodigos.map((cargoCodigo) => ({
      evento_id: eventId,
      cargo_codigo: cargoCodigo,
    })),
  });
}

async function syncEventOfficeJobTitles(
  tx: any,
  eventId: number,
  selections: EventOfficeJobTitleInput[],
  allowedOfficeIds: number[],
) {
  await tx.evento_oficina_cargos.deleteMany({
    where: { evento_id: eventId },
  });

  if (selections.length === 0) {
    return;
  }

  const allowedOfficeIdSet = new Set(allowedOfficeIds);
  const rows = selections.flatMap((selection) => {
    if (!allowedOfficeIdSet.has(selection.oficinaId)) {
      throw new HttpError(
        400,
        "Los cargos por oficina deben pertenecer a oficinas del evento.",
      );
    }

    return [...new Set(selection.cargoCodigos)].map((cargoCodigo) => ({
      evento_id: eventId,
      oficina_id: selection.oficinaId,
      cargo_codigo: cargoCodigo,
    }));
  });

  if (rows.length === 0) {
    return;
  }

  const uniqueCargoCodigos = [...new Set(rows.map((row) => row.cargo_codigo))];
  const existingCargos = await tx.cargos.findMany({
    where: {
      codigo: {
        in: uniqueCargoCodigos,
      },
    },
    select: {
      codigo: true,
    },
  });
  const existingCargoCodes = new Set(
    existingCargos.map((cargo: { codigo: string }) => cargo.codigo),
  );

  if (existingCargoCodes.size !== uniqueCargoCodigos.length) {
    throw new HttpError(400, "Debes seleccionar cargos validos por oficina.");
  }

  await tx.evento_oficina_cargos.createMany({
    data: rows,
    skipDuplicates: true,
  });
}

async function syncEventControls(
  tx: any,
  eventId: number,
  controls: EventControlInput[],
) {
  const existingControls = await tx.evento_controles.findMany({
    where: { evento_id: eventId },
    select: { id: true },
  });
  const existingControlIds = new Set<number>(
    existingControls.map((control: { id: number }) => control.id),
  );

  for (const control of controls) {
    if (control.id != null && !existingControlIds.has(control.id)) {
      throw new HttpError(
        400,
        "Uno de los controles enviados no pertenece al evento.",
      );
    }
  }

  if (existingControls.length > 0) {
    await tx.evento_controles.updateMany({
      where: { evento_id: eventId },
      data: {
        orden: {
          increment: 1000,
        },
        updated_at: new Date(),
      },
    });
  }

  for (const control of controls) {
    if (control.id != null) {
      await tx.evento_controles.update({
        where: { id: control.id },
        data: {
          nombre: control.nombre,
          orden: control.orden,
          hora_inicio: control.horaInicio,
          hora_fin: control.horaFin,
          updated_at: new Date(),
        },
      });
      continue;
    }

    await tx.evento_controles.create({
      data: {
        evento_id: eventId,
        nombre: control.nombre,
        orden: control.orden,
        hora_inicio: control.horaInicio,
        hora_fin: control.horaFin,
      },
    });
  }

  await tx.evento_controles.deleteMany({
    where: {
      evento_id: eventId,
      orden: {
        gt: 1000,
      },
    },
  });
}

function normalizeOfficeCode(code: string) {
  return code.trim().replace(/\.+$/, "");
}

function normalizeOfficeMatchText(value: unknown) {
  const text = normalizeOptionalText(value);

  if (text == null) {
    return null;
  }

  return text
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .toUpperCase();
}

function normalizeLooseMatchText(value: unknown) {
  const text = normalizeOfficeMatchText(value);

  if (text == null) {
    return null;
  }

  return text
    .replace(/\bCOMISION\b/g, " ")
    .replace(/[^A-Z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function requiresLugarForCargo(
  cargo: string | null | undefined,
  cargoCodigo: string | null | undefined,
) {
  const locationRequiredCargoCodes = new Set([
    "CA116",
    "CA082",
    "CA096",
    "CA087",
  ]);
  const normalizedCode = normalizeOptionalText(cargoCodigo)?.toUpperCase();
  const normalizedCargo = normalizeLooseMatchText(cargo);

  return (
    (normalizedCode != null && locationRequiredCargoCodes.has(normalizedCode)) ||
    normalizedCargo?.startsWith("PORTERO") === true ||
    normalizedCargo?.startsWith("GUARDIA MUNICIPAL") === true
  );
}

function resolvePorteroLugar(
  cargo: string | null | undefined,
  cargoCodigo: string | null | undefined,
  lugar: string | null,
) {
  if (!requiresLugarForCargo(cargo, cargoCodigo)) {
    return null;
  }

  return normalizeOptionalText(lugar);
}

type EventJobTitleCandidate = {
  code: string | null;
  name: string | null;
};

type EventJobTitleGroup =
  | "CHIEF"
  | "DIRECTOR"
  | "MUNICIPAL_SECRETARY"
  | "SUBMAYOR"
  | "TECHNICAL";

function resolveUserEventJobTitles(user: any): EventJobTitleCandidate[] {
  const candidates = [
    {
      code: normalizeOptionalText(user?.cargo_codigo),
      name: normalizeLooseMatchText(user?.cargo),
    },
    {
      code: normalizeOptionalText(user?.subcargo_codigo),
      name: normalizeLooseMatchText(user?.subcargo),
    },
  ];
  const seen = new Set<string>();

  return candidates.filter((candidate) => {
    if (candidate.code == null && candidate.name == null) {
      return false;
    }

    const key = `${candidate.code ?? ""}|${candidate.name ?? ""}`;

    if (seen.has(key)) {
      return false;
    }

    seen.add(key);
    return true;
  });
}

function resolveEventJobTitleGroup(
  normalizedJobTitle: string | null,
): EventJobTitleGroup | null {
  if (normalizedJobTitle == null) {
    return null;
  }

  if (/\bJEF[EA]\b/.test(normalizedJobTitle)) {
    return "CHIEF";
  }

  if (
    normalizedJobTitle.includes("DIRECTOR") ||
    normalizedJobTitle.includes("DIRECCTOR")
  ) {
    return "DIRECTOR";
  }

  if (
    /\bSECRETARI[OA]\b/.test(normalizedJobTitle) &&
    normalizedJobTitle.includes("MUNICIPAL")
  ) {
    return "MUNICIPAL_SECRETARY";
  }

  if (normalizedJobTitle.includes("SUBALCALD")) {
    return "SUBMAYOR";
  }

  if (normalizedJobTitle.includes("TECNIC")) {
    return "TECHNICAL";
  }

  return null;
}

function isEventLeadershipJobTitle(normalizedJobTitle: string | null) {
  const group = resolveEventJobTitleGroup(normalizedJobTitle);

  return (
    group === "CHIEF" ||
    group === "DIRECTOR" ||
    group === "MUNICIPAL_SECRETARY" ||
    group === "SUBMAYOR"
  );
}

function matchesCargoSelection(
  userJobTitles: EventJobTitleCandidate[],
  allowedCargoCodigos: Set<string>,
  allowedCargoNames: Set<string>,
) {
  const onlyTechnicalSelection =
    allowedCargoNames.size > 0 &&
    [...allowedCargoNames].every(
      (jobTitle) => resolveEventJobTitleGroup(jobTitle) === "TECHNICAL",
    );

  if (
    onlyTechnicalSelection &&
    userJobTitles.some((jobTitle) =>
      isEventLeadershipJobTitle(jobTitle.name),
    )
  ) {
    return false;
  }

  if (
    userJobTitles.some(
      (jobTitle) =>
        jobTitle.code != null && allowedCargoCodigos.has(jobTitle.code),
    )
  ) {
    return true;
  }

  if (
    userJobTitles.some(
      (jobTitle) =>
        jobTitle.name != null && allowedCargoNames.has(jobTitle.name),
    )
  ) {
    return true;
  }

  for (const allowedCargoName of allowedCargoNames) {
    const allowedGroup = resolveEventJobTitleGroup(allowedCargoName);

    if (allowedGroup === "TECHNICAL") {
      if (
        userJobTitles.length > 0 &&
        !userJobTitles.some((jobTitle) =>
          isEventLeadershipJobTitle(jobTitle.name),
        )
      ) {
        return true;
      }

      continue;
    }

    if (
      allowedGroup != null &&
      userJobTitles.some(
        (jobTitle) =>
          resolveEventJobTitleGroup(jobTitle.name) === allowedGroup,
      )
    ) {
      return true;
    }

    for (const jobTitle of userJobTitles) {
      if (
        jobTitle.name != null &&
        allowedCargoName.length >= 4 &&
        jobTitle.name.length >= 4 &&
        (allowedCargoName.includes(jobTitle.name) ||
          jobTitle.name.includes(allowedCargoName))
      ) {
        return true;
      }
    }
  }

  return false;
}

function isOfficeCoveredByBranch(officeCode: string, branchCode: string) {
  const normalizedOfficeCode = normalizeOfficeCode(officeCode);
  const normalizedBranchCode = normalizeOfficeCode(branchCode);
  const explicitBranchCodes =
    submayoraltyEventBranchCodes[normalizedBranchCode];

  if (explicitBranchCodes != null) {
    return normalizedOfficeCode === normalizedBranchCode ||
      explicitBranchCodes.has(normalizedOfficeCode);
  }

  return normalizedOfficeCode === normalizedBranchCode ||
    normalizedOfficeCode.startsWith(`${normalizedBranchCode}.`);
}

const submayoraltyEventBranchCodes: Record<string, Set<string>> = {
  "10.2.2": new Set(["10.4.3.1", "10.4.3.2", "10.4.3.3", "10.4.3.4"]),
  "10.2.3": new Set(["10.4.4.1", "10.4.4.2", "10.4.4.3", "10.4.4.4"]),
  "10.2.4": new Set(["10.4.5.1", "10.4.5.2", "10.4.5.3", "10.4.5.4"]),
  "10.2.5": new Set(["10.4.7.1", "10.4.7.2", "10.4.7.3", "10.4.7.4"]),
  "10.2.6": new Set(["10.4.6.1", "10.4.6.2", "10.4.6.3", "10.4.6.4"]),
  "10.2.7": new Set(["10.4.8.1", "10.4.8.2", "10.4.8.3", "10.4.8.4"]),
};

function compareOfficeHierarchy(
  left: { cod: string; oficina: string },
  right: { cod: string; oficina: string },
) {
  const leftSegments = splitOfficeCode(left.cod);
  const rightSegments = splitOfficeCode(right.cod);
  const limit = Math.max(leftSegments.length, rightSegments.length);

  for (let index = 0; index < limit; index += 1) {
    const leftSegment = leftSegments[index];
    const rightSegment = rightSegments[index];

    if (leftSegment == null) {
      return -1;
    }

    if (rightSegment == null) {
      return 1;
    }

    if (leftSegment.numeric != null && rightSegment.numeric != null) {
      if (leftSegment.numeric !== rightSegment.numeric) {
        return leftSegment.numeric - rightSegment.numeric;
      }
      continue;
    }

    const segmentComparison = leftSegment.raw.localeCompare(rightSegment.raw);

    if (segmentComparison !== 0) {
      return segmentComparison;
    }
  }

  return left.oficina.localeCompare(right.oficina);
}

function splitOfficeCode(code: string) {
  return normalizeOfficeCode(code)
    .split(".")
    .filter((segment) => segment.length > 0)
    .map((segment) => {
      const numeric = Number.parseInt(segment, 10);

      return {
        raw: segment,
        numeric: Number.isNaN(numeric) ? null : numeric,
      };
    });
}

function parseRegisterAttendanceInput(
  payload: unknown,
): RegisterAttendanceInput {
  const body = expectRecord(payload);
  const eventId = readRequiredInt(body, "eventId");
  const controlId = readRequiredInt(body, "controlId");
  const qrValue = readOptionalString(body, "qrValue", 1, 500);
  const ci = readOptionalString(body, "ci", 3, 30);
  const registrationSource = readRequiredUppercaseChoice(body, "registrationSource", [
    "QR",
    "CI",
  ]) as "QR" | "CI";
  const observacion = readOptionalString(body, "observacion", 0, 500);
  const payloadFields = readOptionalRecord(body, "payloadFields");
  const scannedAt = readOptionalDate(body, "scannedAt");
  const latitud = readOptionalFloat(body, "latitud", -90, 90);
  const longitud = readOptionalFloat(body, "longitud", -180, 180);
  const accuracy = readOptionalFloat(body, "accuracy", 0, 10_000);
  const estadoValue = readRequiredString(body, "estado", 6, 20).toUpperCase();

  if (
    estadoValue !== estado_asistencia.ASISTIO &&
    estadoValue !== estado_asistencia.OBSERVADO
  ) {
    throw new HttpError(
      400,
      "El estado debe ser ASISTIO u OBSERVADO.",
    );
  }

  if (registrationSource === "QR" && qrValue == null) {
    throw new HttpError(400, "Debes enviar un codigo QR valido.");
  }

  if (registrationSource === "CI" && ci == null) {
    throw new HttpError(400, "Debes enviar un CI valido.");
  }

  if (
    estadoValue === estado_asistencia.OBSERVADO &&
    normalizeOptionalText(observacion) == null
  ) {
    throw new HttpError(
      400,
      "Debes indicar el motivo de la observacion.",
    );
  }

  if (
    registrationSource === "CI" &&
    estadoValue !== estado_asistencia.OBSERVADO
  ) {
    throw new HttpError(
      400,
      "El registro por CI solo puede guardarse como OBSERVADO.",
    );
  }

  if ((latitud == null) !== (longitud == null)) {
    throw new HttpError(
      400,
      "Debes enviar una ubicacion completa para registrar la asistencia.",
    );
  }

  return {
    eventId,
    controlId,
    qrValue,
    ci,
    registrationSource,
    estado: estadoValue,
    observacion,
    payloadFields,
    scannedAt,
    latitud,
    longitud,
    accuracy,
  };
}

function parseLoginInput(payload: unknown): LoginInput {
  const body = expectRecord(payload);

  return {
    email: readRequiredString(body, "email", 3, 150).trim(),
    password: readRequiredString(body, "password", 6, 200),
  };
}

// INICIO SERVICIO EXTERNO VERIFICACION FUNCIONARIO POR CI
function parseFuncionarioCiLookupInput(payload: unknown) {
  const body = expectRecord(payload);

  return {
    ci: readRequiredString(body, "ci", 1, 30),
  };
}
// FIN SERVICIO EXTERNO VERIFICACION FUNCIONARIO POR CI

function readOptionalLoginIdentifier(source: JsonRecord, key: string) {
  const rawValue = readOptionalString(source, key, 3, 150);

  if (rawValue == null) {
    return null;
  }

  return normalizeEmailValue(rawValue);
}

function readRequiredLoginIdentifier(source: JsonRecord, key: string) {
  return normalizeEmailValue(readRequiredString(source, key, 3, 150));
}

async function resolveCredentialTargetUser(
  authenticatedUser: AuthenticatedUser,
  payload: unknown,
) {
  const body = expectRecord(payload);
  const requestedLogin = readOptionalLoginIdentifier(body, "email");
  const targetLogin = requestedLogin ?? authenticatedUser.email;

  if (requestedLogin != null && requestedLogin !== authenticatedUser.email) {
    await assertCredentialsRequester(
      authenticatedUser.email,
      "Solo un administrador o usuario de credenciales puede descargar credenciales de otros usuarios.",
    );
  }

  const user = await prisma.usuarios.findUnique({
    where: { email: targetLogin },
    include: userWithOfficeInclude,
  });

  if (!user) {
    throw new HttpError(404, "No se encontro el usuario seleccionado.");
  }

  if (user.activo !== true) {
    throw new HttpError(
      403,
      "El usuario seleccionado se encuentra inactivo.",
    );
  }

  if (isHealthAdminUser(authenticatedUser) && !isUserInHealthScope(user)) {
    throw new HttpError(
      403,
      "El administrador de salud solo puede gestionar credenciales de oficinas nivel 11.",
    );
  }

  return user;
}

function applyCredentialPdfOverrides(user: any, payload: unknown) {
  const body = expectRecord(payload);
  const nombres = normalizeOptionalText(body["nombreCompleto"]);
  const primerApellido = normalizeOptionalText(body["primerApellido"]);
  const segundoApellido = normalizeOptionalText(body["segundoApellido"]);
  const tercerApellido = normalizeOptionalText(body["tercerApellido"]);

  if (
    nombres == null &&
    primerApellido == null &&
    segundoApellido == null &&
    tercerApellido == null
  ) {
    return user;
  }

  const pdfUser = {
    ...user,
    nombres: nombres ?? user.nombres,
    primer_apellido: primerApellido ?? user.primer_apellido,
    segundo_apellido: segundoApellido ?? user.segundo_apellido,
    tercer_apellido: tercerApellido ?? user.tercer_apellido,
  };

  return {
    ...pdfUser,
    nombre_completo: buildUserDisplayName(pdfUser),
  };
}

function readQueryEmailFromBody(payload: unknown) {
  const body = expectRecord(payload);
  return readRequiredLoginIdentifier(body, "email");
}

function readOptionalPhotoData(body: JsonRecord): string | null {
  if (body.fotoData != null) {
    return readOptionalString(body, "fotoData", 20, 5_000_000);
  }

  return readOptionalString(body, "fotoBase64", 20, 5_000_000);
}

function readRequiredPhotoData(body: JsonRecord): string {
  if (body.fotoData != null) {
    return readRequiredString(body, "fotoData", 20, 5_000_000);
  }

  return readRequiredString(body, "fotoBase64", 20, 5_000_000);
}

function parseUpdateProfileInput(payload: unknown): UpdateProfileInput {
  const body = expectRecord(payload);

  return {
    email: readRequiredLoginIdentifier(body, "email"),
    nombreCompleto: readRequiredString(body, "nombreCompleto", 2, 150),
    primerApellido: readRequiredString(body, "primerApellido", 2, 80),
    segundoApellido: readOptionalString(body, "segundoApellido", 0, 80),
    tercerApellido: readOptionalString(body, "tercerApellido", 0, 80),
    fotoData: readOptionalPhotoData(body),
  };
}

function parseUpdatePasswordInput(payload: unknown): UpdatePasswordInput {
  const body = expectRecord(payload);
  const currentPassword = readRequiredString(body, "currentPassword", 6, 200);
  const newPassword = readRequiredString(body, "newPassword", 6, 200);
  const confirmPassword = readRequiredString(body, "confirmPassword", 6, 200);

  if (newPassword !== confirmPassword) {
    throw new HttpError(400, "Las contrasenas no coinciden.");
  }

  if (newPassword === currentPassword) {
    throw new HttpError(
      400,
      "La nueva contrasena debe ser diferente a la actual.",
    );
  }

  return {
    currentPassword,
    newPassword,
  };
}

function parseGenerateDynamicQrInput(payload: unknown): GenerateDynamicQrInput {
  const body = expectRecord(payload);

  return {
    latitud: readRequiredFloat(body, "latitud", -90, 90),
    longitud: readRequiredFloat(body, "longitud", -180, 180),
    accuracy: readOptionalFloatOrNull(body, "accuracy", 0, 10_000),
  };
}

function parseCreateExitPermitInput(payload: unknown): CreateExitPermitInput {
  const body = expectRecord(payload);

  return {
    motivo: readRequiredUppercaseChoice(body, "motivo", [
      motivo_salida.TRABAJO,
      motivo_salida.PARTICULAR,
    ]) as (typeof motivo_salida)[keyof typeof motivo_salida],
    lugarDestino: readRequiredString(body, "lugarDestino", 2, 255),
    descripcion: readOptionalString(body, "descripcion", 0, 1000),
    fechaPermiso: readRequiredDateOnly(body, "fechaPermiso"),
  };
}

function parseUpdateExitPermitStatusInput(
  payload: unknown,
): UpdateExitPermitStatusInput {
  const body = expectRecord(payload);
  const estado = readRequiredUppercaseChoice(body, "estado", [
    estado_salida.APROBADO,
    estado_salida.RECHAZADO,
  ]);

  return {
    estado: estado as typeof estado_salida.APROBADO | typeof estado_salida.RECHAZADO,
  };
}

function parseUpdateExitPermitArrivalInput(
  payload: unknown,
): UpdateExitPermitArrivalInput {
  const body = expectRecord(payload);

  return {
    horaLlegada: readRequiredTimeText(body, "horaLlegada"),
  };
}

function parseLunchScanInput(payload: unknown): LunchScanInput {
  const body = expectRecord(payload);

  return {
    qrValue: readRequiredString(body, "qrValue", 5, 2000),
  };
}

function parseDeviceHeartbeatInput(payload: unknown): DeviceHeartbeatInput {
  const body = expectRecord(payload);

  return {
    deviceId: readRequiredString(body, "deviceId", 8, 120),
    platform:
      readOptionalString(body, "platform", 1, 30)?.toUpperCase() ?? "UNKNOWN",
    manufacturer: readOptionalString(body, "manufacturer", 0, 120),
    model: readOptionalString(body, "model", 0, 160),
    androidSdk: readOptionalIntInRange(body, "androidSdk", 1, 10_000),
    batteryLevel: readOptionalIntInRange(body, "batteryLevel", 0, 100),
    isCharging: readOptionalBoolean(body, "isCharging"),
    brightness: readOptionalIntInRange(body, "brightness", 0, 100),
    kioskEnabled: readOptionalBoolean(body, "kioskEnabled") ?? false,
  };
}

function parseLunchReportQuery(url: URL): LunchReportQuery {
  const rawStatus = url.searchParams.get("estado")?.trim().toUpperCase() ?? null;
  let status: LunchReportQuery["status"] = null;

  if (rawStatus != null && rawStatus.length > 0) {
    if (rawStatus !== "ABIERTOS" && rawStatus !== "CERRADOS") {
      throw new HttpError(400, "El estado de almuerzo no es valido.");
    }

    status = rawStatus;
  }

  return {
    fecha: readLunchQueryDate(url),
    search: readLunchQuerySearch(url),
    status,
    scannerId: readOptionalQueryInt(url, "scannerId"),
    officeId: readOptionalQueryInt(url, "oficinaId"),
  };
}

function parseRegisterNotificationTokenInput(
  payload: unknown,
): RegisterNotificationTokenInput {
  const body = expectRecord(payload);

  return {
    token: readRequiredString(body, "token", 20, 4096),
    platform: readRequiredUppercaseChoice(body, "platform", [
      "ANDROID",
      "IOS",
    ]),
  };
}

function parseSendNotificationInput(payload: unknown): SendNotificationInput {
  const body = expectRecord(payload);
  const sendToAll = readOptionalBoolean(body, "sendToAll") ?? false;
  const cargoCodigos = readOptionalStringList(body, "cargoCodigos", "cargo");
  const oficinaIds = readOptionalIntList(body, "oficinaIds");
  const cis = readOptionalStringList(body, "cis", "CI").map(normalizeCiLookupValue);
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

function readLunchQueryDate(url: URL) {
  const rawValue = url.searchParams.get("fecha")?.trim();

  if (rawValue == null || rawValue.length === 0) {
    return readDateOnlyString(formatDateInAppTimeZone(new Date()), "fecha");
  }

  return readDateOnlyString(rawValue, "fecha");
}

function readLunchQuerySearch(url: URL) {
  const rawValue =
    url.searchParams.get("q")?.trim() ?? url.searchParams.get("ci")?.trim();

  if (rawValue == null || rawValue.length === 0) {
    return null;
  }

  if (rawValue.length > 80) {
    throw new HttpError(400, "La busqueda no puede superar 80 caracteres.");
  }

  return rawValue;
}

function readExitPermitQueryDate(url: URL) {
  const rawValue = url.searchParams.get("fecha")?.trim();

  if (rawValue == null || rawValue.length === 0) {
    return readDateOnlyString(toDateOnlyText(new Date()), "fecha");
  }

  return readDateOnlyString(rawValue, "fecha");
}

function readExitPermitQuerySearch(url: URL) {
  const rawValue =
    url.searchParams.get("q")?.trim() ?? url.searchParams.get("ci")?.trim();

  if (rawValue == null || rawValue.length === 0) {
    return null;
  }

  if (rawValue.length > 80) {
    throw new HttpError(400, "La busqueda no puede superar 80 caracteres.");
  }

  return rawValue;
}

function readExitPermitOnlyMineQuery(url: URL) {
  const rawValue =
    url.searchParams.get("propias")?.trim().toLowerCase() ??
    url.searchParams.get("mine")?.trim().toLowerCase();

  return rawValue === "true" || rawValue === "1";
}

function parseRegisterUserInput(payload: unknown): RegisterUserInput {
  const body = expectRecord(payload);
  const tipoVinculo = readRequiredUppercaseChoice(
    body,
    "tipoVinculo",
    [...USER_LINK_TYPES],
  );
  const oficinaId = readOptionalInt(body, "oficinaId");
  const oficinaComisionId = readOptionalInt(body, "oficinaComisionId");
  const unidad = readOptionalString(body, "unidad", 0, 120);
  const cargoCodigo = readOptionalString(body, "cargoCodigo", 1, 50);
  const cargo = readOptionalString(body, "cargo", 2, 120);
  const subcargoCodigo = readOptionalString(body, "subcargoCodigo", 1, 50);
  const subcargo = readOptionalString(body, "subcargo", 0, 120);
  const lugar = readOptionalString(body, "lugar", 0, 120);
  const ci = readRequiredString(body, "ci", 3, 30);
  const primerApellido = readRequiredString(body, "primerApellido", 2, 80);
  const loginIdentifier = normalizeEmailValue(normalizeCiValue(ci));
  const contractInput = parseConsultantContractInput(body, tipoVinculo);

  if (oficinaId == null && !unidad) {
    throw new HttpError(400, "Debes seleccionar una unidad valida.");
  }

  if (cargoCodigo == null && !cargo) {
    throw new HttpError(400, "Debes seleccionar un cargo valido.");
  }

  return {
    email: loginIdentifier,
    password:
      readOptionalString(body, "password", 6, 200) ??
      buildDefaultUserPassword({
        primerApellido,
        ci,
      }),
    nombreCompleto: readRequiredString(body, "nombreCompleto", 2, 150),
    primerApellido,
    segundoApellido: readOptionalString(body, "segundoApellido", 0, 80),
    tercerApellido: readOptionalString(body, "tercerApellido", 0, 80),
    ci: readRequiredString(body, "ci", 3, 30),
    celular: readOptionalString(body, "celular", 5, 30),
    tipoVinculo,
    ...contractInput,
    unidad,
    oficinaId,
    oficinaComisionId,
    cargoCodigo,
    cargo: cargo ?? "",
    subcargoCodigo,
    subcargo,
    lugar,
    numeroItem:
      tipoVinculo === "ITEM"
        ? readRequiredString(body, "numeroItem", 1, 50)
        : readOptionalString(body, "numeroItem", 0, 50),
    activo: readRequiredBoolean(body, "activo"),
    fotoData: readRequiredPhotoData(body),
  };
}

function parseManagedUserInput(payload: unknown): ManagedUserInput {
  const body = expectRecord(payload);
  const baseInput = parseRegisterUserInput(payload);
  const requestedRole = readRequiredUppercaseChoice(body, "rol", [
    rol_usuario.ADMIN,
    rol_usuario.ADMIN_SALUD,
    rol_usuario.ADMIN_CONSULTORES,
    rol_usuario.ADMIN_EVENTUALES,
    rol_usuario.CONTROL,
    rol_usuario.CREDENCIALES,
    rol_usuario.ALMUERZO,
    rol_usuario.OPERADOR,
  ]) as (typeof rol_usuario)[keyof typeof rol_usuario];
  const requesterEmail = readRequiredLoginIdentifier(body, "requesterEmail");

  return {
    ...baseInput,
    rol: requestedRole,
    requesterEmail,
  };
}

function parseConsultantContractInput(body: JsonRecord, tipoVinculo: string) {
  if (!CONTRACT_LINK_TYPES.has(tipoVinculo)) {
    return {
      contratoNumero: null,
      contratoInicio: null,
      contratoFin: null,
      contratoAdenda: null,
    };
  }

  const contratoNumero = readRequiredString(body, "contratoNumero", 1, 80);
  const contratoInicio = readRequiredDateOnly(body, "contratoInicio");
  const contratoFin = readRequiredDateOnly(body, "contratoFin");
  const contratoAdenda = readOptionalDateOnly(body, "contratoAdenda");

  if (contratoInicio.getTime() > contratoFin.getTime()) {
    throw new HttpError(
      400,
      "La fecha de inicio de contrato no puede ser mayor a la fecha fin.",
    );
  }

  if (contratoAdenda != null && contratoFin.getTime() > contratoAdenda.getTime()) {
    throw new HttpError(
      400,
      "La fecha de adenda no puede ser menor a la fecha fin de contrato.",
    );
  }

  return {
    contratoNumero,
    contratoInicio,
    contratoFin,
    contratoAdenda,
  };
}

function resolveActiveForContract(input: {
  tipoVinculo: string;
  contratoFin: Date | null;
  contratoAdenda: Date | null;
  activo: boolean;
}) {
  if (!input.activo) {
    return false;
  }

  const contractEnd = input.contratoAdenda ?? input.contratoFin;

  if (!CONTRACT_LINK_TYPES.has(input.tipoVinculo) || contractEnd == null) {
    return input.activo;
  }

  return !isContractEndExpired(contractEnd);
}

function resolveActiveForExistingContract(
  user: {
    tipo_vinculo?: string | null;
    contrato_fin?: Date | null;
    contrato_adenda?: Date | null;
  },
  requestedActive: boolean,
) {
  if (!requestedActive) {
    return false;
  }

  const contractEnd = user.contrato_adenda ?? user.contrato_fin;

  if (!CONTRACT_LINK_TYPES.has(user.tipo_vinculo ?? "") || contractEnd == null) {
    return requestedActive;
  }

  return !isContractEndExpired(contractEnd);
}

function isContractEndExpired(contractEnd: Date) {
  return toDateOnlyText(contractEnd) <= getAppDateOnlyText();
}

function parseUpdateUserStatusInput(payload: unknown): UpdateUserStatusInput {
  const body = expectRecord(payload);

  return {
    requesterEmail: readRequiredLoginIdentifier(body, "requesterEmail"),
    activo: readRequiredBoolean(body, "activo"),
  };
}

function parseUpdateManagedUserInput(payload: unknown): UpdateManagedUserInput {
  const body = expectRecord(payload);
  const tipoVinculo = readRequiredUppercaseChoice(
    body,
    "tipoVinculo",
    [...USER_LINK_TYPES],
  );
  const oficinaId = readOptionalInt(body, "oficinaId");
  const oficinaComisionId = readOptionalInt(body, "oficinaComisionId");
  const unidad = readOptionalString(body, "unidad", 0, 120);
  const cargoCodigo = readOptionalString(body, "cargoCodigo", 1, 50);
  const cargo = readOptionalString(body, "cargo", 2, 120);
  const subcargoCodigo = readOptionalString(body, "subcargoCodigo", 1, 50);
  const subcargo = readOptionalString(body, "subcargo", 0, 120);
  const lugar = readOptionalString(body, "lugar", 0, 120);
  const contractInput = parseConsultantContractInput(body, tipoVinculo);
  const requestedRole = readRequiredUppercaseChoice(body, "rol", [
    rol_usuario.ADMIN,
    rol_usuario.ADMIN_SALUD,
    rol_usuario.ADMIN_CONSULTORES,
    rol_usuario.ADMIN_EVENTUALES,
    rol_usuario.CONTROL,
    rol_usuario.CREDENCIALES,
    rol_usuario.ALMUERZO,
    rol_usuario.OPERADOR,
  ]) as (typeof rol_usuario)[keyof typeof rol_usuario];
  const ci = readRequiredString(body, "ci", 3, 30);
  const email = normalizeEmailValue(normalizeCiValue(ci));

  if (oficinaId == null && !unidad) {
    throw new HttpError(400, "Debes seleccionar una unidad valida.");
  }

  if (cargoCodigo == null && !cargo) {
    throw new HttpError(400, "Debes seleccionar un cargo valido.");
  }

  return {
    requesterEmail: readRequiredLoginIdentifier(body, "requesterEmail"),
    rol: requestedRole,
    email,
    password: readOptionalString(body, "password", 6, 200),
    nombreCompleto: readRequiredString(body, "nombreCompleto", 2, 150),
    primerApellido: readRequiredString(body, "primerApellido", 2, 80),
    segundoApellido: readOptionalString(body, "segundoApellido", 0, 80),
    tercerApellido: readOptionalString(body, "tercerApellido", 0, 80),
    ci,
    celular: readOptionalString(body, "celular", 5, 30),
    tipoVinculo,
    ...contractInput,
    unidad,
    oficinaId,
    oficinaComisionId,
    cargoCodigo,
    cargo: cargo ?? "",
    subcargoCodigo,
    subcargo,
    lugar,
    numeroItem:
      tipoVinculo === "ITEM"
        ? readRequiredString(body, "numeroItem", 1, 50)
        : readOptionalString(body, "numeroItem", 0, 50),
    activo: readRequiredBoolean(body, "activo"),
    fotoData: readOptionalPhotoData(body),
  };
}

function isUpdateUserStatusPayload(payload: unknown) {
  const body = expectRecord(payload);

  return !("email" in body) && !("rol" in body);
}

function parseAttendanceReportQuery(url: URL): AttendanceReportQuery {
  const ci = url.searchParams.get("ci")?.trim() ?? "";
  const estadoRaw = url.searchParams.get("estado")?.trim().toUpperCase() ?? "";

  if (ci.length < 3) {
    throw new HttpError(400, "Debes enviar un CI valido para el reporte.");
  }

  if (!estadoRaw || estadoRaw === "TODOS") {
    return {
      ci,
      estado: null,
    };
  }

  if (
    estadoRaw !== estado_asistencia.ASISTIO &&
    estadoRaw !== estado_asistencia.OBSERVADO
  ) {
    throw new HttpError(400, "El filtro de estado no es valido.");
  }

  return {
    ci,
    estado: estadoRaw,
  };
}

function parseEventListView(url: URL) {
  const view = (url.searchParams.get("view") ?? "summary").trim().toLowerCase();

  if (view === "summary" || view === "detail" || view === "assigned") {
    return view;
  }

  throw new HttpError(400, "La vista de eventos no es valida.");
}

function expectRecord(value: unknown): JsonRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, "El cuerpo de la solicitud no es valido.");
  }

  return value as JsonRecord;
}

function readRequiredString(
  source: JsonRecord,
  key: string,
  minLength: number,
  maxLength: number,
) {
  const value = source[key];

  if (typeof value !== "string") {
    throw new HttpError(400, `El campo ${key} es obligatorio.`);
  }

  const normalizedValue = value.trim();

  if (
    normalizedValue.length < minLength ||
    normalizedValue.length > maxLength
  ) {
    throw new HttpError(400, `El campo ${key} no tiene un formato valido.`);
  }

  return normalizedValue;
}

function readOptionalString(
  source: JsonRecord,
  key: string,
  minLength: number,
  maxLength: number,
) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  if (typeof value !== "string") {
    throw new HttpError(400, `El campo ${key} no tiene un formato valido.`);
  }

  const normalizedValue = value.trim();

  if (!normalizedValue) {
    return null;
  }

  if (
    normalizedValue.length < minLength ||
    normalizedValue.length > maxLength
  ) {
    throw new HttpError(400, `El campo ${key} no tiene un formato valido.`);
  }

  return normalizedValue;
}

function readRequiredEmail(source: JsonRecord, key: string) {
  const value = normalizeEmailValue(readRequiredString(source, key, 5, 150));

  if (!value.includes("@")) {
    throw new HttpError(400, `El campo ${key} no tiene un correo valido.`);
  }

  return value;
}

function readQueryEmail(url: URL, key: string) {
  const value = url.searchParams.get(key)?.trim().toLowerCase() ?? "";

  if (!value || !value.includes("@")) {
    throw new HttpError(400, `Debes enviar un correo valido en ${key}.`);
  }

  return value;
}

function normalizeEmailValue(value: string) {
  return value.trim().toLowerCase();
}

function normalizeCiValue(value: string | null) {
  return (value ?? "").trim().replace(/\s+/g, "").toUpperCase();
}

function normalizeCiLookupValue(value: string | null) {
  return normalizeCiValue(value).replace(/-/g, "");
}

function readOptionalQueryInt(url: URL, key: string) {
  const rawValue = url.searchParams.get(key)?.trim();

  if (rawValue == null || rawValue.length === 0) {
    return null;
  }

  const numericValue = Number.parseInt(rawValue, 10);

  if (!Number.isInteger(numericValue) || numericValue <= 0) {
    throw new HttpError(400, `Debes enviar un valor valido en ${key}.`);
  }

  return numericValue;
}

function readOptionalQueryIsoDate(url: URL, key: string) {
  const rawValue = url.searchParams.get(key)?.trim();

  if (rawValue == null || rawValue.length === 0) {
    return null;
  }

  const parsedDate = readIsoDate(rawValue);

  if (!parsedDate) {
    throw new HttpError(400, `Debes enviar una fecha valida en ${key}.`);
  }

  return parsedDate;
}

function readOptionalQueryDateOnly(url: URL, key: string) {
  const rawValue = url.searchParams.get(key)?.trim();

  if (rawValue == null || rawValue.length === 0) {
    return null;
  }

  readDateOnlyString(rawValue, key);
  return rawValue;
}

function readRequiredInt(source: JsonRecord, key: string) {
  const value = source[key];
  const numericValue =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number.parseInt(value, 10)
        : Number.NaN;

  if (!Number.isInteger(numericValue) || numericValue <= 0) {
    throw new HttpError(400, `El campo ${key} debe ser un numero valido.`);
  }

  return numericValue;
}

function readOptionalInt(source: JsonRecord, key: string) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  const numericValue =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number.parseInt(value, 10)
        : Number.NaN;

  if (!Number.isInteger(numericValue) || numericValue <= 0) {
    throw new HttpError(400, `El campo ${key} debe ser un numero valido.`);
  }

  return numericValue;
}

function readOptionalIntInRange(
  source: JsonRecord,
  key: string,
  min: number,
  max: number,
) {
  const value = source[key];

  if (value == null || value === "") {
    return null;
  }

  const numericValue =
    typeof value === "number"
      ? Math.round(value)
      : typeof value === "string"
        ? Number.parseInt(value, 10)
        : Number.NaN;

  if (!Number.isInteger(numericValue) || numericValue < min || numericValue > max) {
    return null;
  }

  return numericValue;
}

function readRequiredIntList(
  source: JsonRecord,
  pluralKey: string,
  singularFallbackKey: string,
) {
  const pluralValue = source[pluralKey];

  if (Array.isArray(pluralValue)) {
    if (pluralValue.length === 0) {
      throw new HttpError(
        400,
        `El campo ${pluralKey} debe incluir al menos un valor.`,
      );
    }

    const parsedValues = pluralValue.map((value, index) => {
      const numericValue =
        typeof value === "number"
          ? value
          : typeof value === "string"
            ? Number.parseInt(value, 10)
            : Number.NaN;

      if (!Number.isInteger(numericValue) || numericValue <= 0) {
        throw new HttpError(
          400,
          `El valor ${index + 1} de ${pluralKey} no es valido.`,
        );
      }

      return numericValue;
    });

    return [...new Set(parsedValues)];
  }

  return [readRequiredInt(source, singularFallbackKey)];
}

function readOptionalIntList(
  source: JsonRecord,
  key: string,
) {
  const rawValue = source[key];

  if (rawValue == null) {
    return [] as number[];
  }

  if (!Array.isArray(rawValue)) {
    throw new HttpError(400, `El campo ${key} debe ser una lista valida.`);
  }

  const parsedValues = rawValue.map((value, index) => {
    const numericValue =
      typeof value === "number"
        ? value
        : typeof value === "string"
          ? Number.parseInt(value, 10)
          : Number.NaN;

    if (!Number.isInteger(numericValue) || numericValue <= 0) {
      throw new HttpError(
        400,
        `El valor ${index + 1} de ${key} no es valido.`,
      );
    }

    return numericValue;
  });

  return [...new Set(parsedValues)];
}

function readOptionalStringList(
  source: JsonRecord,
  key: string,
  itemName: string,
) {
  const rawValue = source[key];

  if (rawValue == null) {
    return [] as string[];
  }

  if (!Array.isArray(rawValue)) {
    throw new HttpError(400, `El campo ${key} debe ser una lista valida.`);
  }

  const parsedValues = rawValue.map((value, index) => {
    if (typeof value !== "string") {
      throw new HttpError(
        400,
        `El valor ${index + 1} de ${key} no es valido.`,
      );
    }

    const normalizedValue = value.trim();

    if (normalizedValue.length < 1 || normalizedValue.length > 50) {
      throw new HttpError(
        400,
        `El ${itemName} ${index + 1} no es valido.`,
      );
    }

    return normalizedValue;
  });

  return [...new Set(parsedValues)];
}

function readRequiredDate(source: JsonRecord, key: string) {
  const value = source[key];

  if (typeof value !== "string") {
    throw new HttpError(400, `El campo ${key} es obligatorio.`);
  }

  const parsedDate = new Date(value);

  if (Number.isNaN(parsedDate.getTime())) {
    throw new HttpError(400, `El campo ${key} no tiene una fecha valida.`);
  }

  return parsedDate;
}

function readOptionalDate(source: JsonRecord, key: string) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  if (typeof value !== "string") {
    throw new HttpError(400, `El campo ${key} no tiene una fecha valida.`);
  }

  const parsedDate = new Date(value);

  if (Number.isNaN(parsedDate.getTime())) {
    throw new HttpError(400, `El campo ${key} no tiene una fecha valida.`);
  }

  return parsedDate;
}

function readRequiredDateOnly(source: JsonRecord, key: string) {
  const value = source[key];

  if (typeof value !== "string") {
    throw new HttpError(400, `El campo ${key} es obligatorio.`);
  }

  return readDateOnlyString(value, key);
}

function readOptionalDateOnly(source: JsonRecord, key: string) {
  const value = source[key];

  if (value == null || (typeof value === "string" && value.trim() === "")) {
    return null;
  }

  if (typeof value !== "string") {
    throw new HttpError(400, `El campo ${key} no tiene una fecha valida.`);
  }

  return readDateOnlyString(value, key);
}

function readDateOnlyString(value: string, key: string) {
  const normalizedValue = value.trim();

  if (!/^\d{4}-\d{2}-\d{2}$/.test(normalizedValue)) {
    throw new HttpError(400, `El campo ${key} debe tener formato YYYY-MM-DD.`);
  }

  const parsedDate = new Date(`${normalizedValue}T00:00:00.000Z`);

  if (
    Number.isNaN(parsedDate.getTime()) ||
    toDateOnlyText(parsedDate) !== normalizedValue
  ) {
    throw new HttpError(400, `El campo ${key} no tiene una fecha valida.`);
  }

  return parsedDate;
}

function readRequiredTimeText(source: JsonRecord, key: string) {
  const value = readRequiredString(source, key, 5, 5);

  if (!isValidTimeText(value)) {
    throw new HttpError(400, `El campo ${key} debe tener formato HH:mm.`);
  }

  return value;
}

function readOptionalTimeText(source: JsonRecord, key: string) {
  const value = readOptionalString(source, key, 5, 5);

  if (value == null) {
    return null;
  }

  if (!isValidTimeText(value)) {
    throw new HttpError(400, `El campo ${key} debe tener formato HH:mm.`);
  }

  return value;
}

function isValidTimeText(value: string) {
  const match = /^(\d{2}):(\d{2})$/.exec(value);

  if (!match) {
    return false;
  }

  const hours = Number.parseInt(match[1] ?? "", 10);
  const minutes = Number.parseInt(match[2] ?? "", 10);

  return hours >= 0 && hours <= 23 && minutes >= 0 && minutes <= 59;
}

function toDateOnlyText(date: Date) {
  return date.toISOString().slice(0, 10);
}

function readRequiredBoolean(source: JsonRecord, key: string) {
  const value = source[key];

  if (typeof value !== "boolean") {
    throw new HttpError(400, `El campo ${key} es obligatorio.`);
  }

  return value;
}

function readOptionalBoolean(source: JsonRecord, key: string) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  if (typeof value !== "boolean") {
    throw new HttpError(400, `El campo ${key} debe ser verdadero o falso.`);
  }

  return value;
}

function readRequiredFloat(
  source: JsonRecord,
  key: string,
  min: number,
  max: number,
) {
  const value = source[key];
  const numericValue =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number.parseFloat(value)
        : Number.NaN;

  if (!Number.isFinite(numericValue) || numericValue < min || numericValue > max) {
    throw new HttpError(400, `El campo ${key} no tiene un valor valido.`);
  }

  return numericValue;
}

function readOptionalFloat(
  source: JsonRecord,
  key: string,
  min: number,
  max: number,
) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  const numericValue =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number.parseFloat(value)
        : Number.NaN;

  if (!Number.isFinite(numericValue) || numericValue < min || numericValue > max) {
    throw new HttpError(400, `El campo ${key} no tiene un valor valido.`);
  }

  return numericValue;
}

function readOptionalFloatOrNull(
  source: JsonRecord,
  key: string,
  min: number,
  max: number,
) {
  const value = source[key];

  if (value == null || value === "") {
    return null;
  }

  const numericValue =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number.parseFloat(value)
        : Number.NaN;

  if (!Number.isFinite(numericValue) || numericValue < min || numericValue > max) {
    return null;
  }

  return numericValue;
}

function readRequiredUppercaseChoice(
  source: JsonRecord,
  key: string,
  allowedValues: string[],
) {
  const value = readRequiredString(source, key, 2, 40).toUpperCase();

  if (!allowedValues.includes(value)) {
    throw new HttpError(400, `El campo ${key} no tiene un valor permitido.`);
  }

  return value;
}

function readOptionalUppercaseChoiceList(
  source: JsonRecord,
  key: string,
  allowedValues: string[],
) {
  const values = readOptionalStringList(source, key, key);

  return [
    ...new Set(
      values.map((value) => {
        const normalizedValue = value.toUpperCase();

        if (!allowedValues.includes(normalizedValue)) {
          throw new HttpError(
            400,
            `El campo ${key} contiene un valor no permitido.`,
          );
        }

        return normalizedValue;
      }),
    ),
  ];
}

function readResourceId(pathname: string, prefix: string) {
  if (!pathname.startsWith(prefix)) {
    return null;
  }

  const rawId = pathname.slice(prefix.length).trim();

  if (!rawId || rawId.includes("/")) {
    return null;
  }

  const parsedId = Number.parseInt(rawId, 10);

  if (!Number.isInteger(parsedId) || parsedId <= 0) {
    throw new HttpError(400, "El identificador enviado no es valido.");
  }

  return parsedId;
}

function readOptionalRecord(source: JsonRecord, key: string) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  if (typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, `El campo ${key} no tiene un formato valido.`);
  }

  return value as JsonRecord;
}

function isAdminEmail(email: string) {
  return email.trim().toLowerCase().includes("@admin");
}

function isAdminRole(role: (typeof rol_usuario)[keyof typeof rol_usuario]) {
  return role === rol_usuario.ADMIN || role === rol_usuario.ADMIN_SALUD;
}

function isScopedUserAdminRole(
  role: (typeof rol_usuario)[keyof typeof rol_usuario],
) {
  return (
    role === rol_usuario.ADMIN_CONSULTORES ||
    role === rol_usuario.ADMIN_EVENTUALES
  );
}

function isUserManagerRole(role: (typeof rol_usuario)[keyof typeof rol_usuario]) {
  return isAdminRole(role) || isScopedUserAdminRole(role);
}

function isUserReaderRole(role: (typeof rol_usuario)[keyof typeof rol_usuario]) {
  return role === rol_usuario.LECTOR_USUARIOS;
}

function scopedUserAdminTipoVinculosForRole(
  role: (typeof rol_usuario)[keyof typeof rol_usuario],
) {
  if (role === rol_usuario.ADMIN_CONSULTORES) {
    return [CONSULTANT_LINK_TYPE, SERVICES_LINK_TYPE];
  }

  if (role === rol_usuario.ADMIN_EVENTUALES) {
    return [TEMPORARY_LINK_TYPE];
  }

  return null;
}

function isHealthAdminUser(user: { rol?: string | null } | null | undefined) {
  return user?.rol === rol_usuario.ADMIN_SALUD;
}

function isHealthOffice(office: { nivel?: number | null } | null | undefined) {
  return office?.nivel === HEALTH_OFFICE_LEVEL;
}

function isUserInHealthScope(user: any) {
  return isHealthOffice(user?.oficinas) || isHealthOffice(user?.oficina_comision);
}

function healthUserWhereForRequester(requester: any) {
  if (!isHealthAdminUser(requester)) {
    return undefined;
  }

  return {
    OR: [
      { oficinas: { is: { nivel: HEALTH_OFFICE_LEVEL } } },
      { oficina_comision: { is: { nivel: HEALTH_OFFICE_LEVEL } } },
    ],
  };
}

function userDirectoryWhereForRequester(requester: any) {
  const scopedTipoVinculos = scopedUserAdminTipoVinculosForRole(requester?.rol);

  if (scopedTipoVinculos != null) {
    return {
      rol: rol_usuario.OPERADOR,
      tipo_vinculo: { in: scopedTipoVinculos },
    };
  }

  const healthWhere = healthUserWhereForRequester(requester);

  if (healthWhere != null) {
    return healthWhere;
  }

  if (requester?.rol === rol_usuario.ADMIN) {
    return undefined;
  }

  if (isUserReaderRole(requester?.rol)) {
    return undefined;
  }

  return {
    NOT: {
      OR: [
        { oficinas: { is: { nivel: HEALTH_OFFICE_LEVEL } } },
        { oficina_comision: { is: { nivel: HEALTH_OFFICE_LEVEL } } },
      ],
    },
  };
}

function healthPersonWhereForRequester(requester: any) {
  const userWhere = healthUserWhereForRequester(requester);

  if (userWhere == null) {
    return undefined;
  }

  return {
    usuario: {
      is: userWhere,
    },
  };
}

function healthExitPermitWhereForRequester(requester: any) {
  const userWhere = healthUserWhereForRequester(requester);

  if (userWhere == null) {
    return undefined;
  }

  return {
    usuarios: {
      is: userWhere,
    },
  };
}

function healthEventWhereForRequester(requester: any) {
  if (!isHealthAdminUser(requester)) {
    return undefined;
  }

  return {
    AND: [
      {
        evento_oficinas: {
          some: {
            oficinas: {
              nivel: HEALTH_OFFICE_LEVEL,
            },
          },
        },
      },
      {
        evento_oficinas: {
          every: {
            oficinas: {
              nivel: HEALTH_OFFICE_LEVEL,
            },
          },
        },
      },
    ],
  };
}

function healthWhereArray(where: any) {
  return where == null ? [] : [where];
}

function assertHealthAdminCanUseOffice(
  requester: any,
  office: { nivel?: number | null } | null | undefined,
) {
  if (!isHealthAdminUser(requester) || office == null) {
    return;
  }

  if (!isHealthOffice(office)) {
    throw new HttpError(
      403,
      "El administrador de salud solo puede gestionar oficinas de nivel 11.",
    );
  }
}

function assertHealthAdminCanManageUser(requester: any, user: any) {
  if (!isHealthAdminUser(requester)) {
    return;
  }

  if (!isUserInHealthScope(user)) {
    throw new HttpError(
      403,
      "El administrador de salud solo puede gestionar usuarios de oficinas nivel 11.",
    );
  }
}

function assertManagedUserRoleAllowedForRequester(
  requester: any,
  role: (typeof rol_usuario)[keyof typeof rol_usuario],
) {
  if (isScopedUserAdminRole(requester?.rol)) {
    if (role !== rol_usuario.OPERADOR) {
      throw new HttpError(
        403,
        "Este administrador solo puede gestionar usuarios funcionarios.",
      );
    }

    return;
  }

  if (!isHealthAdminUser(requester)) {
    return;
  }

  if (role === rol_usuario.ADMIN) {
    throw new HttpError(
      403,
      "El administrador de salud no puede crear administradores generales.",
    );
  }
}

function assertScopedUserAdminCanManageUserInput(
  requester: any,
  input: Pick<ManagedUserInput | UpdateManagedUserInput, "rol" | "tipoVinculo">,
) {
  const scopedTipoVinculos = scopedUserAdminTipoVinculosForRole(requester?.rol);

  if (scopedTipoVinculos == null) {
    return;
  }

  if (
    input.rol !== rol_usuario.OPERADOR ||
    !scopedTipoVinculos.includes(input.tipoVinculo)
  ) {
    throw new HttpError(
      403,
      `Este administrador solo puede gestionar funcionarios de tipo ${formatScopedTipoVinculos(scopedTipoVinculos)}.`,
    );
  }
}

function assertScopedUserAdminCanManageUser(requester: any, user: any) {
  const scopedTipoVinculos = scopedUserAdminTipoVinculosForRole(requester?.rol);

  if (scopedTipoVinculos == null) {
    return;
  }

  if (
    user?.rol !== rol_usuario.OPERADOR ||
    !scopedTipoVinculos.includes(user?.tipo_vinculo)
  ) {
    throw new HttpError(
      403,
      `Este administrador solo puede gestionar funcionarios de tipo ${formatScopedTipoVinculos(scopedTipoVinculos)}.`,
    );
  }
}

function formatScopedTipoVinculos(tiposVinculo: string[]) {
  return tiposVinculo.map((value) => value.toLowerCase()).join(" o ");
}

function assertManagedUserRoleOffice(
  role: (typeof rol_usuario)[keyof typeof rol_usuario],
  office: { nivel?: number | null } | null | undefined,
) {
  if (role !== rol_usuario.ADMIN_SALUD) {
    return;
  }

  if (!isHealthOffice(office)) {
    throw new HttpError(
      400,
      "El rol admin (salud) debe estar asociado a una oficina de nivel 11.",
    );
  }
}

function assertHealthAdminCanUseEventOffices(requester: any, offices: any[]) {
  if (!isHealthAdminUser(requester)) {
    return;
  }

  if (offices.length === 0 || offices.some((office) => !isHealthOffice(office))) {
    throw new HttpError(
      403,
      "El administrador de salud solo puede crear eventos para oficinas nivel 11.",
    );
  }
}

function assertHealthAdminCanManageEvent(requester: any, event: any) {
  if (!isHealthAdminUser(requester)) {
    return;
  }

  const offices = event?.evento_oficinas?.map((item: any) => item.oficinas) ?? [];

  if (offices.length === 0 || offices.some((office: any) => !isHealthOffice(office))) {
    throw new HttpError(
      403,
      "El administrador de salud solo puede gestionar eventos de oficinas nivel 11.",
    );
  }
}

async function assertAdminRequester(
  email: string,
  message = "Solo un administrador puede realizar esta accion.",
) {
  const user = await prisma.usuarios.findUnique({
    where: { email: email.toLowerCase() },
  });

  if (!user || !isAdminRole(user.rol) || user.activo !== true) {
    throw new HttpError(403, message);
  }

  return user;
}

async function assertUserManagerRequester(
  email: string,
  message = "Solo un administrador puede gestionar usuarios.",
) {
  const user = await prisma.usuarios.findUnique({
    where: { email: email.toLowerCase() },
  });

  if (!user || !isUserManagerRole(user.rol) || user.activo !== true) {
    throw new HttpError(403, message);
  }

  return user;
}

async function assertUserDirectoryRequester(
  email: string,
  message = "Solo un administrador o usuario de credenciales puede consultar credenciales.",
) {
  const user = await prisma.usuarios.findUnique({
    where: { email: email.toLowerCase() },
  });

  if (
    !user ||
    (!isUserManagerRole(user.rol) &&
      user.rol !== rol_usuario.CREDENCIALES &&
      !isUserReaderRole(user.rol)) ||
    user.activo !== true
  ) {
    throw new HttpError(403, message);
  }

  return user;
}

async function assertCredentialsRequester(
  email: string,
  message = "Solo un administrador o usuario de credenciales puede realizar esta accion.",
) {
  const user = await prisma.usuarios.findUnique({
    where: { email: email.toLowerCase() },
  });

  if (
    !user ||
    (!isUserManagerRole(user.rol) && user.rol !== rol_usuario.CREDENCIALES) ||
    user.activo !== true
  ) {
    throw new HttpError(403, message);
  }

  return user;
}

function isAdminUser(user: AuthenticatedUser) {
  return isAdminRole(user.rol);
}

function canScanQrData(user: AuthenticatedUser) {
  return isAdminRole(user.rol) || user.rol === rol_usuario.CONTROL;
}

function assertLunchScannerRequester(user: AuthenticatedUser) {
  if (user.id <= 0 || user.activo !== true || user.rol !== rol_usuario.ALMUERZO) {
    throw new HttpError(403, "Solo una cuenta de almuerzo puede registrar almuerzos.");
  }
}

function assertExitPermitScannerRequester(user: AuthenticatedUser) {
  if (user.id <= 0 || user.activo !== true || user.rol !== rol_usuario.ALMUERZO) {
    throw new HttpError(
      403,
      "Solo una cuenta de almuerzo puede registrar salidas por QR.",
    );
  }
}

function assertLunchReportRequester(user: AuthenticatedUser) {
  if (user.id <= 0 || user.activo !== true || !isAdminRole(user.rol)) {
    throw new HttpError(403, "Solo un administrador puede consultar almuerzos.");
  }
}

function assertAuthenticatedRequester(user: AuthenticatedUser) {
  if (user.id <= 0 || user.activo !== true) {
    throw new HttpError(401, "Debes iniciar sesion para continuar.");
  }
}

function assertExitPermitApprover(user: any) {
  if (!user || user.activo !== true || user.rol !== rol_usuario.OPERADOR) {
    throw new HttpError(403, "Solo un jefe o director puede revisar salidas.");
  }

  if (!isExitPermitApproverUser(user)) {
    throw new HttpError(
      403,
      "Solo usuarios con cargo de jefe o director pueden revisar salidas.",
    );
  }

  if (resolveLinkedOfficeId(user) == null) {
    throw new HttpError(403, "Tu usuario no tiene oficina asignada para revisar salidas.");
  }
}

async function assertCanReviewExitPermit(approver: any, salida: any) {
  if (salida.usuario_id === approver.id) {
    throw new HttpError(403, "No puedes revisar tu propia salida.");
  }

  if (await canReviewExitPermit(approver, salida, salida.usuarios)) {
    return;
  }

  throw new HttpError(
    403,
    "Solo puedes revisar salidas asignadas a tu nivel jerarquico.",
  );
}

function buildExitPermitReviewWhere(
  approver: any,
  options: { onlyPending?: boolean } = {},
): Prisma.salidasWhereInput {
  const baseWhere = {
    ...(options.onlyPending == true ? { estado: estado_salida.PENDIENTE } : {}),
    usuario_id: { not: approver.id },
  };

  if (isDirectorExitPermitApprover(approver)) {
    const directionCode = resolveDirectorOfficeCode(approver);

    return {
      ...baseWhere,
      usuarios: {
        OR: buildOfficeCodeScopeUserFilters(directionCode),
      },
    };
  }

  if (isSeniorExitPermitApprover(approver)) {
    return {
      ...baseWhere,
      usuarios: {
        OR: buildOfficeCodeScopeUserFilters(resolveLinkedOfficeCode(approver)),
      },
    };
  }

  return {
    ...baseWhere,
    solicitante_oficina_id: resolveLinkedOfficeId(approver),
    usuarios: {
      AND: [
        { NOT: buildEffectiveChiefJobTitleUserWhere() },
        { NOT: buildEffectiveDirectorJobTitleUserWhere() },
      ],
    },
  };
}

function buildExitPermitListWhere(
  authenticatedUser: AuthenticatedUser,
  requester: any,
  fechaPermiso: Date | null,
  searchText: string | null,
  onlyOwnExitPermits = false,
) {
  if (onlyOwnExitPermits) {
    if (fechaPermiso == null) {
      throw new HttpError(400, "La fecha es obligatoria para consultar salidas.");
    }

    return {
      fecha_permiso: fechaPermiso,
      usuario_id: authenticatedUser.id,
    };
  }

  if (isAdminUser(authenticatedUser)) {
    return {
      AND: [
        ...(fechaPermiso == null ? [] : [{ fecha_permiso: fechaPermiso }]),
        ...(searchText == null ? [] : [buildExitPermitSearchWhere(searchText)]),
        ...healthWhereArray(healthExitPermitWhereForRequester(authenticatedUser)),
      ],
    };
  }

  if (requester != null && isExitPermitApproverUser(requester)) {
    return {
      usuario_id: { not: requester.id },
      ...(fechaPermiso == null ? {} : { fecha_permiso: fechaPermiso }),
    };
  }

  if (fechaPermiso == null) {
    throw new HttpError(400, "La fecha es obligatoria para consultar salidas.");
  }

  return {
    fecha_permiso: fechaPermiso,
    usuario_id: authenticatedUser.id,
  };
}

function buildExitPermitSearchWhere(searchText: string) {
  const tokens = searchText
    .trim()
    .split(/\s+/)
    .filter((token) => token.length > 0);

  return {
    OR: [
      ...buildExitPermitSearchTokenFilters(searchText),
      ...(tokens.length <= 1
        ? []
        : [
            {
              AND: tokens.map((token) => ({
                OR: buildExitPermitSearchTokenFilters(token),
              })),
            },
          ]),
    ],
  };
}

function buildExitPermitSearchTokenFilters(token: string) {
  return [
    {
      solicitante_nombre_completo: {
        contains: token,
        mode: "insensitive" as const,
      },
    },
    {
      usuarios: {
        ci: {
          contains: token,
          mode: "insensitive" as const,
        },
      },
    },
    {
      usuarios: {
        nombre_completo: {
          contains: token,
          mode: "insensitive" as const,
        },
      },
    },
    {
      usuarios: {
        nombres: {
          contains: token,
          mode: "insensitive" as const,
        },
      },
    },
    {
      usuarios: {
        primer_apellido: {
          contains: token,
          mode: "insensitive" as const,
        },
      },
    },
    {
      usuarios: {
        segundo_apellido: {
          contains: token,
          mode: "insensitive" as const,
        },
      },
    },
  ];
}

const EXIT_PERMIT_CHIEF_CARGO_CODES = new Set([
  "CA018",
  "CA015",
  "CA014",
  "CA013",
  "CA012",
  "CA011",
]);

const EXIT_PERMIT_APPROVER_CARGO_CODES = new Set([
  ...EXIT_PERMIT_CHIEF_CARGO_CODES,
  "CA010",
]);

const EXIT_PERMIT_DIRECTOR_OFFICE_CODES = new Set([
  "0.1",
  "0.2",
  "0.5",
  "1.1",
  "1.3",
  "2.1",
  "2.2",
  "3.3",
  "3.4",
  "4.1",
  "4.2",
  "5.1",
  "5.2",
  "5.3",
  "5.5",
  "6.1",
  "6.2",
  "6.3",
  "6.4",
  "7.2",
  "7.3",
  "8.1",
  "8.2",
  "8.3",
  "9.1",
  "9.2",
  "10.1",
  "10.2",
  "10.3",
  "10.4",
  "11.1",
  "11.2",
  "11.4",
  "12.1",
  "12.2",
]);

function isExitPermitApproverUser(user: any) {
  return (
    user != null &&
    user.activo === true &&
    user.rol === rol_usuario.OPERADOR &&
    (isBossJobTitle(
      resolveEffectiveJobTitleName(user),
      resolveEffectiveJobTitleCode(user),
    ) ||
      isDirectorExitPermitApprover(user) ||
      isSeniorExitPermitApprover(user)) &&
    resolveLinkedOfficeId(user) != null
  );
}

function isChiefExitPermitApplicant(user: any) {
  const normalizedCode = resolveEffectiveJobTitleCode(user)?.toUpperCase();

  return (
    (normalizedCode != null &&
      EXIT_PERMIT_CHIEF_CARGO_CODES.has(normalizedCode)) ||
    normalizeTextForComparison(resolveEffectiveJobTitleName(user)).includes("jefe")
  );
}

function isDirectorExitPermitApprover(user: any) {
  return (
    isDirectorJobTitle(resolveEffectiveJobTitleName(user)) &&
    resolveDirectorOfficeCode(user) != null
  );
}

function isDirectorJobTitle(value: string | null | undefined) {
  const normalized = normalizeTextForComparison(value);

  return normalized.includes("director") || normalized.includes("direcctor");
}

function isSeniorExitPermitApprover(user: any) {
  return (
    isSeniorJobTitle(resolveEffectiveJobTitleName(user)) &&
    normalizeOptionalText(resolveLinkedOfficeCode(user)) != null
  );
}

function isSeniorJobTitle(value: string | null | undefined) {
  const normalized = normalizeTextForComparison(value);
  const compact = normalized.replace(/[^a-z0-9]+/g, "");

  return normalized.includes("secretar") || compact.includes("subalcald");
}

function resolveDirectorOfficeCode(user: any) {
  const officeCode = normalizeOptionalText(resolveLinkedOfficeCode(user));

  if (officeCode == null || !EXIT_PERMIT_DIRECTOR_OFFICE_CODES.has(officeCode)) {
    return null;
  }

  return officeCode;
}

function buildOfficeCodeScopeUserFilters(officeCode: string | null | undefined) {
  const normalizedCode = normalizeOptionalText(officeCode);

  if (normalizedCode == null) {
    return [];
  }

  return [
    {
      oficinas: {
        cod: {
          startsWith: `${normalizedCode}.`,
        },
      },
    },
    {
      oficina_comision: {
        cod: {
          startsWith: `${normalizedCode}.`,
        },
      },
    },
  ];
}

const buildDirectorOfficeScopeUserFilters = buildOfficeCodeScopeUserFilters;

function buildEffectiveChiefJobTitleUserWhere(): Prisma.usuariosWhereInput {
  return {
    OR: [
      {
        subcargo_codigo: {
          in: Array.from(EXIT_PERMIT_CHIEF_CARGO_CODES),
        },
      },
      {
        AND: [
          { subcargo_codigo: null },
          { subcargo: null },
          {
            cargo_codigo: {
              in: Array.from(EXIT_PERMIT_CHIEF_CARGO_CODES),
            },
          },
        ],
      },
      {
        subcargo: {
          contains: "jefe",
          mode: "insensitive" as const,
        },
      },
      {
        AND: [
          { subcargo_codigo: null },
          { subcargo: null },
          {
            cargo: {
              contains: "jefe",
              mode: "insensitive" as const,
            },
          },
        ],
      },
    ],
  };
}

function buildEffectiveDirectorJobTitleUserWhere(): Prisma.usuariosWhereInput {
  return {
    OR: [
      {
        subcargo: {
          contains: "director",
          mode: "insensitive" as const,
        },
      },
      {
        subcargo: {
          contains: "direcctor",
          mode: "insensitive" as const,
        },
      },
      {
        AND: [
          { subcargo_codigo: null },
          { subcargo: null },
          {
            OR: [
              {
                cargo: {
                  contains: "director",
                  mode: "insensitive" as const,
                },
              },
              {
                cargo: {
                  contains: "direcctor",
                  mode: "insensitive" as const,
                },
              },
            ],
          },
        ],
      },
    ],
  };
}

function isApplicantInDirectorScope(director: any, applicant: any) {
  const directionCode = resolveDirectorOfficeCode(director);
  const applicantOfficeCode = normalizeOptionalText(
    resolveLinkedOfficeCode(applicant),
  );

  if (directionCode == null || applicantOfficeCode == null) {
    return false;
  }

  return applicantOfficeCode.startsWith(`${directionCode}.`);
}

function isBossJobTitle(
  value: string | null | undefined,
  cargoCodigo?: string | null,
) {
  const normalizedCode = normalizeOptionalText(cargoCodigo)?.toUpperCase();

  return (
    (normalizedCode != null &&
      EXIT_PERMIT_APPROVER_CARGO_CODES.has(normalizedCode)) ||
    normalizeTextForComparison(value).includes("jefe")
  );
}

function assertPersonLookupRequester(user: AuthenticatedUser) {
  if (!canScanQrData(user)) {
    throw new HttpError(
      403,
      "Solo un administrador o usuario de control puede consultar datos por QR o CI.",
    );
  }
}

function assertAttendanceReportRequester(
  user: AuthenticatedUser,
  requestedCi: string,
) {
  if (isAdminUser(user)) {
    return;
  }

  if (user.ci != null && sameCiValue(user.ci, requestedCi)) {
    return;
  }

  throw new HttpError(
    403,
    "No tienes permiso para consultar datos de otro usuario.",
  );
}

async function assertEventOperator(userId: number) {
  const user = await prisma.usuarios.findUnique({
    where: { id: userId },
  });

  if (
    !user ||
    user.activo !== true ||
    (!isAdminRole(user.rol) && user.rol !== rol_usuario.CONTROL)
  ) {
    throw new HttpError(
      403,
      "Solo un administrador o usuario de control puede registrar asistencias.",
    );
  }

  return user;
}

async function ensurePersonIdentityForUser(tx: any, user: any) {
  // Generacion y sincronizacion del QR del usuario:
  // usuario autenticado -> persona vinculada -> codigo_qr estable -> datos_qr.
  // Esto mantiene en la tabla `personas` la identidad que luego resuelve el escaner.
  const linkedUser = await ensureUserOfficeLink(tx, user);
  const normalizedCi = normalizeOptionalText(linkedUser.ci);
  const existingPerson = await tx.personas.findUnique({
    where: { usuario_id: linkedUser.id },
    include: personIdentityInclude,
  });
  const matchedPerson =
    existingPerson ??
    (normalizedCi == null
      ? null
      : await tx.personas.findFirst({
          where: {
            usuario_id: null,
            ci: normalizedCi,
          },
          include: personIdentityInclude,
          orderBy: [{ activo: "desc" }, { updated_at: "desc" }, { id: "desc" }],
        }));
  const qrCode = resolveUserQrCode(linkedUser, matchedPerson?.codigo_qr ?? null);
  const data = {
    nombre_completo: buildUserDisplayName(linkedUser),
    ci: normalizedCi,
    codigo_qr: qrCode,
    datos_qr: buildStoredUserQrMetadata(
      linkedUser,
      qrCode,
      matchedPerson?.datos_qr ?? null,
    ),
    activo: linkedUser.activo === true,
    updated_at: new Date(),
    usuario_id: linkedUser.id,
  };

  if (matchedPerson) {
    const isAlreadySynced =
      matchedPerson.nombre_completo === data.nombre_completo &&
      matchedPerson.ci === data.ci &&
      matchedPerson.codigo_qr === data.codigo_qr &&
      matchedPerson.activo === data.activo &&
      matchedPerson.usuario_id === data.usuario_id;

    if (isAlreadySynced) {
      return matchedPerson;
    }

    return tx.personas.update({
      where: { id: matchedPerson.id },
      data,
      include: personIdentityInclude,
    });
  }

  return tx.personas.create({
    data,
    include: personIdentityInclude,
  });
}

async function ensureUserOfficeLink(tx: any, user: any) {
  if (!user) {
    return user;
  }

  const currentOfficeId = resolveLinkedOfficeId(user);

  if (currentOfficeId != null && resolveLinkedOffice(user) != null) {
    return user;
  }

  if (currentOfficeId != null) {
    return tx.usuarios.findUnique({
      where: { id: user.id },
      include: userWithOfficeInclude,
    });
  }

  const resolvedOffice = await resolveOfficeForUser(tx, user);

  if (resolvedOffice == null) {
    return user;
  }

  if (user.oficina_id === resolvedOffice.id && user.oficinas == null) {
    return tx.usuarios.findUnique({
      where: { id: user.id },
      include: userWithOfficeInclude,
    });
  }

  return tx.usuarios.update({
    where: { id: user.id },
    data: {
      oficina_id: resolvedOffice.id,
    },
    include: userWithOfficeInclude,
  });
}

async function resolveOfficeForUser(tx: any, user: any) {
  if (!user) {
    return null;
  }

  const officeId =
    user.oficina_comision?.id ??
    user.oficina_comision_id ??
    user.oficinas?.id ??
    user.oficina_id ??
    null;

  if (officeId != null) {
    return tx.oficinas.findUnique({
      where: { id: officeId },
    });
  }

  const normalizedUnit = normalizeOfficeMatchText(user.unidad);

  if (normalizedUnit == null) {
    return null;
  }

  const offices = (await tx.oficinas.findMany()) as EventOfficeNode[];
  return (
    offices.find(
      (office) => normalizeOfficeMatchText(office.oficina) === normalizedUnit,
    ) ?? null
  );
}

async function ensurePersonLinkedOffice(person: any) {
  const linkedUser = person?.usuario ?? null;

  if (!linkedUser) {
    return person;
  }

  const originalOfficeId = resolveLinkedOfficeId(linkedUser);
  const resolvedUser = await ensureUserOfficeLink(prisma, linkedUser);
  const resolvedOfficeId = resolveLinkedOfficeId(resolvedUser);

  if (originalOfficeId === resolvedOfficeId && linkedUser.oficinas != null) {
    return person;
  }

  return {
    ...person,
    usuario: resolvedUser,
  };
}

async function issueDynamicQrForUser(
  tx: any,
  person: any,
  user: any,
  _input: GenerateDynamicQrInput,
) {
  const qrCode = person.codigo_qr ?? buildUserQrCode(user);
  const staticQr = buildStaticDynamicQrSession(person, user);
  const nextMetadata = buildStoredUserQrMetadata(
    user,
    qrCode,
    person.datos_qr ?? null,
  );

  await tx.personas.update({
    where: { id: person.id },
    data: {
      codigo_qr: qrCode,
      datos_qr: nextMetadata,
      updated_at: new Date(),
    },
  });

  return staticQr;
}

function readActiveDynamicQrSession(person: any, user: any) {
  return buildStaticDynamicQrSession(person, user);
}

function buildStaticDynamicQrSession(person: any, user: any) {
  const qrCode = person.codigo_qr ?? buildUserQrCode(user);
  const generatedAt =
    person.created_at instanceof Date
      ? person.created_at
      : user.created_at instanceof Date
        ? user.created_at
        : new Date();

  return {
    qrCode,
    qrPayload: buildDynamicQrPayload(qrCode, STATIC_DYNAMIC_QR_EXPIRES_AT),
    generatedAt: generatedAt.toISOString(),
    expiresAt: STATIC_DYNAMIC_QR_EXPIRES_AT.toISOString(),
    ttlSeconds: 0,
    location: {
      latitud: 0,
      longitud: 0,
      accuracy: null,
    },
  };
}

function hashPassword(password: string) {
  const salt = randomBytes(16).toString("hex");
  const derivedKey = scryptSync(password, salt, 64).toString("hex");

  return `scrypt:${salt}:${derivedKey}`;
}

function readAssetDataUri(fileLocations: Array<string | URL>, mimeType: string) {
  for (const location of fileLocations) {
    try {
      return `data:${mimeType};base64,${readFileSync(location).toString("base64")}`;
    } catch {
      // Intenta la siguiente ubicacion. En Docker el asset vive en /app/assets.
    }
  }

  logWarning("No se pudo cargar el logo publico de calificaciones.");
  return null;
}

function buildDefaultUserPassword(input: {
  primerApellido: string;
  ci: string;
}) {
  const lastNamePrefix = input.primerApellido
    .trim()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z]/g, "")
    .toLowerCase()
    .slice(0, 3);
  const ci = input.ci.trim().replace(/\s+/g, "");
  const password = `${lastNamePrefix}${ci}`;

  if (password.length < 6) {
    throw new HttpError(
      400,
      "La contrasena inicial generada debe tener al menos 6 caracteres. Verifica el primer apellido y CI.",
    );
  }

  return password;
}

async function findUserForLogin(login: string) {
  const normalizedLogin = normalizeEmailValue(login);
  const normalizedCi = normalizeCiLookupValue(login);

  const userByEmail = await prisma.usuarios.findUnique({
    where: { email: normalizedLogin },
    include: userWithOfficeInclude,
  });

  if (userByEmail != null) {
    return userByEmail;
  }

  const users = await prisma.usuarios.findMany({
    where: {
      ci: {
        not: null,
      },
    },
    include: userWithOfficeInclude,
    orderBy: [{ activo: "desc" }, { updated_at: "desc" }, { id: "desc" }],
  });

  return users.find((user) => normalizeCiLookupValue(user.ci) === normalizedCi) ?? null;
}

function verifyDefaultCiPassword(
  password: string,
  user: {
    ci?: string | null;
    primer_apellido?: string | null;
  },
) {
  const defaultPassword = buildDefaultCiPasswordOrNull(user);

  if (defaultPassword == null || defaultPassword.length !== password.length) {
    return false;
  }

  return timingSafeEqual(
    Buffer.from(password, "utf8"),
    Buffer.from(defaultPassword, "utf8"),
  );
}

function buildDefaultCiPasswordOrNull(input: {
  ci?: string | null;
  primer_apellido?: string | null;
}) {
  const ci = normalizeCiValue(input.ci ?? null);
  const lastNamePrefix = input.primer_apellido
    ?.trim()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z]/g, "")
    .toLowerCase()
    .slice(0, 3) ?? "";
  const password = `${lastNamePrefix}${ci}`;

  return ci.length >= 3 && lastNamePrefix.length > 0 && password.length >= 6
    ? password
    : null;
}

async function findUserByLoginOrCi(
  tx: any,
  input: {
    login: string;
    ci: string;
    excludeUserId?: number;
  },
) {
  const normalizedLogin = normalizeEmailValue(input.login);
  const normalizedCi = normalizeCiLookupValue(input.ci);
  const users = await tx.usuarios.findMany({
    where:
      input.excludeUserId == null
        ? undefined
        : {
            id: {
              not: input.excludeUserId,
            },
          },
    select: {
      id: true,
      email: true,
      ci: true,
    },
  });

  return users.find((user: { email: string; ci: string | null }) => {
    return (
      normalizeEmailValue(user.email) === normalizedLogin ||
      normalizeCiLookupValue(user.ci) === normalizedCi
    );
  }) ?? null;
}

function sameCiValue(left: string | null, right: string) {
  return normalizeCiLookupValue(left) === normalizeCiLookupValue(right);
}

function verifyPassword(password: string, storedHash: string) {
  if (!storedHash.startsWith("scrypt:")) {
    return false;
  }

  const parts = storedHash.split(":");

  if (parts.length !== 3) {
    return false;
  }

  const [, salt, originalHash] = parts;
  const derivedKey = scryptSync(password, salt, 64).toString("hex");
  const originalBuffer = Buffer.from(originalHash, "hex");
  const currentBuffer = Buffer.from(derivedKey, "hex");

  if (originalBuffer.length !== currentBuffer.length) {
    return false;
  }

  return timingSafeEqual(originalBuffer, currentBuffer);
}

async function findPersonByScannedValue(
  scannedValue: string,
  lookupCode?: string,
) {
  // Al escanear se prueban varios candidatos porque el lector puede devolver
  // el JSON completo, una URL o solo el codigo QR ya normalizado.
  const candidates = buildQrLookupCandidates(scannedValue, lookupCode);

  for (const candidate of candidates) {
    const person = await prisma.personas.findUnique({
      where: { codigo_qr: candidate },
      include: personIdentityInclude,
    });

    if (person) {
      return ensurePersonLinkedOffice(person);
    }
  }

  // Compatibilidad con QRs historicos:
  // aunque el usuario ya haya migrado a un ID externo nuevo, seguimos aceptando
  // el codigo legado `USR-*` si coincide con la identidad real del usuario.
  for (const candidate of candidates) {
    const legacyPerson = await findPersonByLegacyUserQrCode(candidate);

    if (legacyPerson) {
      return ensurePersonLinkedOffice(legacyPerson);
    }
  }

  for (const candidate of candidates) {
    const personByCi = await findPersonByCi(candidate);

    if (personByCi) {
      return ensurePersonLinkedOffice(personByCi);
    }
  }

  const credentialUserId = readCredentialUserIdFromScannedValue(scannedValue);

  if (credentialUserId != null) {
    const linkedUser = await prisma.usuarios.findUnique({
      where: { id: credentialUserId },
      include: userWithOfficeInclude,
    });

    if (linkedUser) {
      return ensurePersonIdentityForUser(prisma, linkedUser);
    }
  }

  const dynamicQr = tryParseDynamicQrPayload(scannedValue);

  if (dynamicQr != null && !isDynamicQrExpired(dynamicQr)) {
    const dynamicPerson = await prisma.personas.findUnique({
      where: { codigo_qr: dynamicQr.qrCode },
      include: personIdentityInclude,
    });

    if (dynamicPerson) {
      return ensurePersonLinkedOffice(dynamicPerson);
    }
  }

  return null;
}

async function resolvePersonByQrValue(scannedValue: string, lookupCode: string) {
  // Si el QR ya pertenece a una persona existente la reutilizamos.
  // Si no existe, se crea una persona placeholder para no perder la lectura
  // y dejar trazabilidad del valor exacto que llego desde la camara.
  const existingPerson = await findPersonByScannedValue(scannedValue, lookupCode);

  if (existingPerson) {
    return existingPerson;
  }

  const placeholderCode = buildPlaceholderQrCode(scannedValue);

  try {
    return await prisma.personas.create({
      data: {
        nombre_completo: buildPlaceholderName(scannedValue),
        codigo_qr: placeholderCode,
        datos_qr: {
          rawValue: scannedValue.trim(),
          lookupCode,
          autoGenerated: true,
        },
        activo: true,
      },
      include: personIdentityInclude,
    });
  } catch (error) {
    const concurrentPerson = await prisma.personas.findUnique({
      where: { codigo_qr: placeholderCode },
      include: personIdentityInclude,
    });

    if (concurrentPerson) {
      return concurrentPerson;
    }

    throw error;
  }
}

async function findPersonByCi(ci: string) {
  const normalizedCi = normalizeOptionalText(ci);

  if (normalizedCi == null) {
    return null;
  }

  const linkedUser = await prisma.usuarios.findFirst({
    where: {
      ci: normalizedCi,
    },
    include: userWithOfficeInclude,
    orderBy: [{ activo: "desc" }, { updated_at: "desc" }, { id: "desc" }],
  });

  if (linkedUser) {
    return ensurePersonIdentityForUser(prisma, linkedUser);
  }

  const person = await prisma.personas.findFirst({
    where: {
      ci: normalizedCi,
    },
    include: personIdentityInclude,
    orderBy: [{ activo: "desc" }, { updated_at: "desc" }, { id: "desc" }],
  });

  return person == null ? null : ensurePersonLinkedOffice(person);
}

function buildCiAttendanceRawValue(ci: string) {
  return `CI:${ci.trim().toUpperCase()}`;
}

function buildAttendanceObservation(input: RegisterAttendanceInput) {
  if (input.registrationSource !== "CI") {
    return input.observacion;
  }

  const fallbackMessage = `Registrado manualmente por CI ${input.ci!.trim()}.`;
  const customObservation = normalizeOptionalText(input.observacion);

  if (customObservation == null) {
    return fallbackMessage;
  }

  if (customObservation.toLowerCase() === fallbackMessage.toLowerCase()) {
    return fallbackMessage;
  }

  return `${fallbackMessage} ${customObservation}`;
}

function buildAttendanceRegistrationLocation(input: RegisterAttendanceInput) {
  if (input.latitud == null || input.longitud == null) {
    return null;
  }

  return {
    latitud: input.latitud,
    longitud: input.longitud,
    accuracy: input.accuracy,
  };
}

async function registerLunchScan(qrValue: string, scannerUserId: number) {
  const scannedValue = qrValue.trim();
  const lookupCode = extractLookupCode(scannedValue);

  if (!lookupCode) {
    throw new HttpError(400, "Debes enviar un codigo QR valido.");
  }

  const person = await findPersonByScannedValue(scannedValue, lookupCode);
  const funcionario = person?.usuario ?? null;

  if (!person || !funcionario) {
    throw new HttpError(404, "No se encontro un funcionario con ese codigo QR.");
  }

  if (funcionario.activo !== true || funcionario.rol !== rol_usuario.OPERADOR) {
    throw new HttpError(
      400,
      "El QR escaneado no pertenece a un funcionario activo.",
    );
  }

  const scannedAt = new Date();
  const lunchDateText = formatDateInAppTimeZone(scannedAt);
  const lunchDate = readDateOnlyString(lunchDateText, "fecha");
  const lunchTime = formatTimeInAppTimeZone(scannedAt);

  assertLunchScanWithinAllowedTime(lunchTime);

  const qrSnapshot = {
    rawValue: scannedValue,
    lookupCode,
    scannedAt: scannedAt.toISOString(),
    personaId: person.id,
    usuarioId: funcionario.id,
  };

  const record = await prisma.$transaction(async (tx) => {
    const openLunch = await tx.almuerzos.findFirst({
      where: {
        usuario_id: funcionario.id,
        fecha: lunchDate,
        hora_retorno: null,
      },
      orderBy: [{ salida_en: "desc" }, { id: "desc" }],
    });

    if (openLunch) {
      return tx.almuerzos.update({
        where: { id: openLunch.id },
        data: {
          hora_retorno: lunchTime,
          retorno_en: scannedAt,
          registrado_retorno_por_id: scannerUserId,
          qr_leido: scannedValue,
          datos_qr_snapshot: qrSnapshot,
          updated_at: scannedAt,
        },
        include: lunchRecordInclude,
      });
    }

    const closedLunch = await tx.almuerzos.findFirst({
      where: {
        usuario_id: funcionario.id,
        fecha: lunchDate,
        hora_retorno: {
          not: null,
        },
      },
      orderBy: [{ retorno_en: "desc" }, { id: "desc" }],
    });

    if (closedLunch) {
      throw new HttpError(
        409,
        "Este funcionario ya registro salida y retorno de almuerzo hoy. Podra registrar nuevamente al dia siguiente.",
      );
    }

    return tx.almuerzos.create({
      data: {
        usuario_id: funcionario.id,
        fecha: lunchDate,
        hora_salida: lunchTime,
        salida_en: scannedAt,
        registrado_salida_por_id: scannerUserId,
        qr_leido: scannedValue,
        datos_qr_snapshot: qrSnapshot,
        funcionario_nombre_completo: buildUserDisplayName(funcionario),
        funcionario_ci: normalizeOptionalText(funcionario.ci),
        funcionario_numero_item: normalizeOptionalText(funcionario.numero_item),
        funcionario_cargo: resolveEffectiveJobTitleName(funcionario),
        funcionario_oficina_id: resolveLinkedOfficeId(funcionario),
        funcionario_oficina: resolveLinkedOfficeName(funcionario),
      },
      include: lunchRecordInclude,
    });
  });

  const action = record.hora_retorno == null ? "SALIDA" : "RETORNO";
  const actionLabel = action === "SALIDA" ? "Salida" : "Retorno";

  return {
    accion: action,
    mensaje: `${actionLabel} de almuerzo registrada para ${record.funcionario_nombre_completo}.`,
    registro: serializeLunchRecord(record),
  };
}

function assertLunchScanWithinAllowedTime(lunchTime: string) {
  const minutes = parseTimeTextToMinutes(lunchTime);
  const startMinutes = 12 * 60;
  const endMinutes = 15 * 60;

  if (minutes < startMinutes || minutes >= endMinutes) {
    throw new HttpError(
      403,
      "No cumple el horario de almuerzo. El escaneo solo esta permitido de 12:00 a 15:00.",
    );
  }
}

function parseTimeTextToMinutes(value: string) {
  const [hourText, minuteText] = value.split(":");
  const hour = Number.parseInt(hourText ?? "", 10);
  const minute = Number.parseInt(minuteText ?? "", 10);

  if (
    !Number.isInteger(hour) ||
    !Number.isInteger(minute) ||
    hour < 0 ||
    hour > 23 ||
    minute < 0 ||
    minute > 59
  ) {
    throw new HttpError(500, "No fue posible validar el horario de almuerzo.");
  }

  return hour * 60 + minute;
}

async function registerExitPermitScan(qrValue: string, scannerUserId: number) {
  const scannedValue = qrValue.trim();
  const lookupCode = extractLookupCode(scannedValue);

  if (!lookupCode) {
    throw new HttpError(400, "Debes enviar un codigo QR valido.");
  }

  const person = await findPersonByScannedValue(scannedValue, lookupCode);
  const funcionario = person?.usuario ?? null;

  if (!person || !funcionario) {
    throw new HttpError(404, "No se encontro un funcionario con ese codigo QR.");
  }

  if (funcionario.activo !== true || funcionario.rol !== rol_usuario.OPERADOR) {
    throw new HttpError(
      400,
      "El QR escaneado no pertenece a un funcionario activo.",
    );
  }

  const scannedAt = new Date();
  const permitDateText = formatDateInAppTimeZone(scannedAt);
  const permitDate = readDateOnlyString(permitDateText, "fecha");
  const scanTime = formatTimeInAppTimeZone(scannedAt);
  const qrSnapshot = {
    rawValue: scannedValue,
    lookupCode,
    scannedAt: scannedAt.toISOString(),
    personaId: person.id,
    usuarioId: funcionario.id,
  };

  const record = await prisma.$transaction(async (tx) => {
    const openExitPermit = await tx.salidas.findFirst({
      where: {
        usuario_id: funcionario.id,
        fecha_permiso: permitDate,
        estado: estado_salida.APROBADO,
        hora_inicio: {
          not: null,
        },
        hora_llegada: null,
      },
      orderBy: [
        { salida_en: "desc" },
        { aprobado_en: "desc" },
        { id: "desc" },
      ],
    });

    if (openExitPermit) {
      return tx.salidas.update({
        where: { id: openExitPermit.id },
        data: {
          hora_llegada: scanTime,
          llegada_en: scannedAt,
          registrado_llegada_por_id: scannerUserId,
          qr_leido: scannedValue,
          datos_qr_snapshot: qrSnapshot,
          updated_at: scannedAt,
        },
        include: exitPermitRecordInclude,
      });
    }

    const pendingDeparturePermit = await tx.salidas.findFirst({
      where: {
        usuario_id: funcionario.id,
        fecha_permiso: permitDate,
        estado: estado_salida.APROBADO,
        hora_inicio: null,
      },
      orderBy: [
        { aprobado_en: "asc" },
        { created_at: "asc" },
        { id: "asc" },
      ],
    });

    if (pendingDeparturePermit) {
      return tx.salidas.update({
        where: { id: pendingDeparturePermit.id },
        data: {
          hora_inicio: scanTime,
          salida_en: scannedAt,
          registrado_salida_por_id: scannerUserId,
          qr_leido: scannedValue,
          datos_qr_snapshot: qrSnapshot,
          updated_at: scannedAt,
        },
        include: exitPermitRecordInclude,
      });
    }

    const completedPermit = await tx.salidas.findFirst({
      where: {
        usuario_id: funcionario.id,
        fecha_permiso: permitDate,
        estado: estado_salida.APROBADO,
        hora_inicio: {
          not: null,
        },
        hora_llegada: {
          not: null,
        },
      },
      orderBy: [{ llegada_en: "desc" }, { updated_at: "desc" }, { id: "desc" }],
    });

    if (completedPermit) {
      throw new HttpError(
        409,
        "Este funcionario ya registro salida y llegada de su permiso aprobado de hoy.",
      );
    }

    throw new HttpError(
      404,
      "Este funcionario no tiene un permiso de salida aprobado para hoy.",
    );
  });

  const action = record.hora_llegada == null ? "SALIDA" : "LLEGADA";
  const actionLabel = action === "SALIDA" ? "Salida" : "Llegada";

  return {
    accion: action,
    mensaje: `${actionLabel} de permiso registrada para ${record.solicitante_nombre_completo}.`,
    registro: serializeExitPermit(record),
  };
}

function buildLunchReportWhere(query: LunchReportQuery): Prisma.almuerzosWhereInput {
  const search = query.search;
  const insensitive = "insensitive" as const;
  const conditions: Prisma.almuerzosWhereInput[] = [
    { fecha: query.fecha },
    ...(query.status === "ABIERTOS" ? [{ hora_retorno: null }] : []),
    ...(query.status === "CERRADOS" ? [{ hora_retorno: { not: null } }] : []),
    ...(query.officeId == null
      ? []
      : [{ funcionario_oficina_id: query.officeId }]),
    ...(query.scannerId == null
      ? []
      : [
          {
            OR: [
              { registrado_salida_por_id: query.scannerId },
              { registrado_retorno_por_id: query.scannerId },
            ],
          },
        ]),
    ...(search == null
      ? []
      : [
          {
            OR: [
              { funcionario_nombre_completo: { contains: search, mode: insensitive } },
              { funcionario_ci: { contains: search, mode: insensitive } },
              { funcionario_numero_item: { contains: search, mode: insensitive } },
              { funcionario_cargo: { contains: search, mode: insensitive } },
              { funcionario_oficina: { contains: search, mode: insensitive } },
            ],
          },
        ]),
  ];

  return {
    AND: conditions,
  };
}

function formatDateInAppTimeZone(date: Date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: APP_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function formatTimeInAppTimeZone(date: Date) {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: APP_TIME_ZONE,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
}

function resolveControlRegistrationTiming(
  event: { fecha_evento: Date },
  control: {
    nombre: string;
    hora_inicio?: string | null;
    hora_fin?: string | null;
  },
  registeredAt: Date,
) {
  const startTime = control.hora_inicio ?? null;
  const endTime = control.hora_fin ?? null;

  // Los controles creados antes de esta funcionalidad no tienen rango.
  if (startTime == null && endTime == null) {
    return { isLate: false };
  }

  if (
    startTime == null ||
    endTime == null ||
    !isValidTimeText(startTime) ||
    !isValidTimeText(endTime)
  ) {
    throw new HttpError(
      409,
      `El control "${control.nombre}" no tiene un rango horario valido.`,
    );
  }

  const eventDate = formatDateInAppTimeZone(event.fecha_evento);
  const currentDate = formatDateInAppTimeZone(registeredAt);
  const currentTime = formatTimeInAppTimeZone(registeredAt);

  if (currentDate !== eventDate) {
    throw new HttpError(
      409,
      `El control "${control.nombre}" solo permite registrar en la fecha del evento.`,
    );
  }

  if (currentTime < startTime) {
    throw new HttpError(
      409,
      `El control "${control.nombre}" comenzara a registrar asistencia a las ${startTime}.`,
    );
  }

  return { isLate: currentTime > endTime };
}

function buildQrLookupCandidates(scannedValue: string, providedLookupCode?: string) {
  // Orden de candidatos:
  // 1. lookupCode extraido del payload/URL/texto.
  // 2. token de URL de credencial antigua.
  // 3. valor exacto leido, por compatibilidad con QRs antiguos.
  // 4. AUTOQR:{sha256(raw)}, para placeholders creados desde escaneos previos.
  const trimmedValue = scannedValue.trim();

  if (!trimmedValue) {
    return [];
  }

  const lookupCode = providedLookupCode ?? extractLookupCode(trimmedValue);
  const exactValue = trimmedValue.length <= 255 ? trimmedValue : null;
  const placeholderCode = buildPlaceholderQrCode(trimmedValue);
  const credentialTokenCandidates = extractCredentialQrLookupCandidates(trimmedValue);

  return [
    ...new Set([
      lookupCode,
      ...credentialTokenCandidates,
      exactValue,
      placeholderCode,
    ].filter(isValidQrCode)),
  ];
}

function extractCredentialQrLookupCandidates(scannedValue: string) {
  const uri = UriTryParse(scannedValue);

  if (uri == null) {
    return [];
  }

  const decodedPath = safeDecodeUriComponent(uri.pathname);
  const match = decodedPath.match(/credencial-frente-pdf-([^/.]+)/i);
  const token = match?.[1]?.trim();

  if (!token) {
    return [];
  }

  return [token, token.toUpperCase()];
}

function readCredentialUserIdFromScannedValue(scannedValue: string) {
  const uri = UriTryParse(scannedValue);

  if (uri == null) {
    return null;
  }

  const decodedPath = safeDecodeUriComponent(uri.pathname);
  const match = decodedPath.match(/credencial-frente-pdf-id-(\d+)/i);
  const userId = Number.parseInt(match?.[1] ?? "", 10);

  return Number.isInteger(userId) && userId > 0 ? userId : null;
}

function safeDecodeUriComponent(value: string) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function buildPlaceholderQrCode(scannedValue: string) {
  const normalizedValue = scannedValue.trim();
  const digest = createHash("sha256").update(normalizedValue).digest("hex");

  return `AUTOQR:${digest}`;
}

function buildPlaceholderName(scannedValue: string) {
  return truncateText(scannedValue.trim(), 150);
}

function truncateText(value: string, maxLength: number) {
  if (value.length <= maxLength) {
    return value;
  }

  if (maxLength <= 3) {
    return value.slice(0, maxLength);
  }

  return `${value.slice(0, maxLength - 3)}...`;
}

function isValidQrCode(value: string | null): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= 255;
}

function isPlaceholderQrCode(value: string | null) {
  return typeof value === "string" && value.startsWith("AUTOQR:");
}

function isLegacyUserQrCode(value: string | null) {
  return typeof value === "string" && /^USR-\d+-[A-F0-9]{12}$/i.test(value);
}

function extractLookupCode(scannedValue: string) {
  // Estrategia de normalizacion del QR:
  // JSON emitido por la app -> URL con query/path -> texto crudo en mayusculas.
  // La idea es obtener un identificador corto y estable para buscar en `codigo_qr`.
  const trimmedValue = scannedValue.trim();

  if (!trimmedValue) {
    return null;
  }

  const dynamicQr = tryParseDynamicQrPayload(trimmedValue);

  if (dynamicQr != null) {
    return isDynamicQrExpired(dynamicQr) ? null : dynamicQr.qrCode;
  }

  const qrPayload = tryParseQrPayloadRecord(trimmedValue);

  if (qrPayload != null) {
    const payloadLookupCode = readLookupCodeFromQrPayload(qrPayload);

    if (payloadLookupCode != null) {
      return payloadLookupCode;
    }
  }

  const uri = UriTryParse(trimmedValue);

  if (uri == null) {
    return trimmedValue.toUpperCase();
  }

  const lookupKeys = ["qr", "codigoQr", "codigo_qr", "code", "id", "slug", "token", "ci"];

  for (const key of lookupKeys) {
    const value = uri.searchParams.get(key)?.trim();

    if (value) {
      return value.toUpperCase();
    }
  }

  const pathSegments = uri.pathname
    .split("/")
    .map((segment) => segment.trim())
    .filter(Boolean);
  const lastSegment = pathSegments.at(-1);

  if (lastSegment) {
    return lastSegment.toUpperCase();
  }

  return trimmedValue.toUpperCase();
}

type DynamicQrPayload = {
  qrCode: string;
  expiresAt: Date;
  expiresAtKey: string;
  signature: string;
};

function buildDynamicQrSignature(qrCode: string, expiresAtKey: string) {
  return createHmac("sha256", DYNAMIC_QR_SIGNING_SECRET)
    .update(`${DYNAMIC_QR_VERSION}|${qrCode}|${expiresAtKey}`)
    .digest("hex")
    .slice(0, DYNAMIC_QR_SIGNATURE_LENGTH)
    .toUpperCase();
}

function buildDynamicQrPayload(qrCode: string, expiresAt: Date) {
  const expiresAtKey = Math.floor(expiresAt.getTime() / 1000)
    .toString(36)
    .toUpperCase();
  const signature = buildDynamicQrSignature(qrCode, expiresAtKey);

  return `${DYNAMIC_QR_VERSION}.${qrCode}.${expiresAtKey}.${signature}`;
}

function tryParseDynamicQrPayload(scannedValue: string): DynamicQrPayload | null {
  const normalizedValue = scannedValue.trim().toUpperCase();
  const match = normalizedValue.match(
    /^DQR1\.(QREXT-[A-F0-9]{20})\.([0-9A-Z]+)\.([A-F0-9]{16})$/,
  );

  if (!match) {
    return null;
  }

  const [, qrCode, expiresAtKey, signature] = match;
  const expectedSignature = buildDynamicQrSignature(qrCode, expiresAtKey);

  if (expectedSignature !== signature) {
    return null;
  }

  const expiresAtUnix = Number.parseInt(expiresAtKey, 36);

  if (!Number.isInteger(expiresAtUnix) || expiresAtUnix <= 0) {
    return null;
  }

  return {
    qrCode,
    expiresAt: new Date(expiresAtUnix * 1000),
    expiresAtKey,
    signature,
  };
}

function isDynamicQrExpired(payload: DynamicQrPayload) {
  return payload.expiresAt.getTime() <= Date.now();
}

function assertScannedQrCanRegisterAttendance(scannedValue: string) {
  const dynamicQr = tryParseDynamicQrPayload(scannedValue);

  if (dynamicQr != null) {
    if (isDynamicQrExpired(dynamicQr)) {
      throw new HttpError(
        410,
        "No se puede realizar el escaneo porque el QR esta caduco. Vuelve a cargar tu QR e intentalo otra vez.",
      );
    }

    return;
  }

  if (isPrintedCredentialQr(scannedValue)) {
    return;
  }

  throw new HttpError(
    400,
    "Solo se puede registrar asistencia con el QR del funcionario o el QR impreso en su credencial.",
  );
}

function isPrintedCredentialQr(scannedValue: string) {
  const uri = UriTryParse(scannedValue.trim());

  if (
    uri == null ||
    uri.protocol !== "https:" ||
    uri.hostname.toLowerCase() !== "res.cloudinary.com"
  ) {
    return false;
  }

  const decodedPath = safeDecodeUriComponent(uri.pathname);
  return /\/imagenes\/credenciales\/credencial-frente-pdf-[^/]+(?:\.jpg)?$/i
    .test(decodedPath);
}

function tryParseQrPayloadRecord(scannedValue: string) {
  try {
    const parsedValue = JSON.parse(scannedValue);

    if (
      !parsedValue ||
      typeof parsedValue !== "object" ||
      Array.isArray(parsedValue)
    ) {
      return null;
    }

    return parsedValue as JsonRecord;
  } catch {
    return null;
  }
}

function readLookupCodeFromQrPayload(payload: JsonRecord) {
  // Acepta varias claves para soportar payloads historicos o integraciones externas.
  const lookupKeys = [
    "codigoQr",
    "qrCode",
    "codigo_qr",
    "code",
    "id",
    "qr",
    "slug",
    "token",
  ];

  for (const key of lookupKeys) {
    const value = payload[key];

    if (typeof value === "string" && value.trim().length > 0) {
      return value.trim().toUpperCase();
    }
  }

  return null;
}

function UriTryParse(value: string) {
  try {
    return new URL(value);
  } catch {
    return null;
  }
}

function normalizeOptionalText(value: unknown) {
  if (typeof value !== "string") {
    return null;
  }

  const normalizedValue = value.trim();
  return normalizedValue.length > 0 ? normalizedValue : null;
}

function normalizeTextForComparison(value: unknown) {
  return (normalizeOptionalText(value) ?? "")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase();
}

function buildLegacyUserQrCode(user: {
  id: number;
  email?: string | null;
  ci?: string | null;
}) {
  const seed = `${user.id}:${user.email?.toLowerCase() ?? ""}:${user.ci ?? ""}`;
  const digest = createHash("sha256").update(seed).digest("hex").slice(0, 12);

  return `USR-${user.id}-${digest.toUpperCase()}`;
}

function buildUserQrCode(user: {
  id: number;
  email?: string | null;
  ci?: string | null;
}) {
  // El QR publico solo expone un identificador externo opaco.
  // Ya no incluye JSON ni el id secuencial interno del usuario.
  const seed = `${user.id}:${user.email?.toLowerCase() ?? ""}:${user.ci ?? ""}:external-qr`;
  const digest = createHash("sha256").update(seed).digest("hex").slice(0, 20);

  return `QREXT-${digest.toUpperCase()}`;
}

function resolveUserQrCode(
  user: {
    id: number;
    email?: string | null;
    ci?: string | null;
  },
  existingCode: string | null,
) {
  // Conserva el codigo_qr ya asignado si es valido y no es placeholder.
  // Los codigos legacy `USR-*` se migran a un ID externo opaco en el siguiente sync.
  if (
    isValidQrCode(existingCode) &&
    !isPlaceholderQrCode(existingCode) &&
    !isLegacyUserQrCode(existingCode)
  ) {
    return existingCode;
  }

  return buildUserQrCode(user);
}

function buildUserQrPayloadObject(user: any, qrCode: string) {
  // Este objeto queda solo como metadata interna.
  // El contenido real del QR publico ya no es este JSON, sino solo el ID externo.
  return {
    type: "qr-asistencia-user",
    version: 1,
    codigoQr: qrCode,
    usuarioId: user.id,
    ci: normalizeOptionalText(user.ci) ?? "",
    email: normalizeOptionalText(user.email) ?? "",
    nombreCompleto: normalizeOptionalText(user.nombres) ??
      normalizeOptionalText(user.nombre_completo) ??
      "",
    primerApellido: normalizeOptionalText(user.primer_apellido) ?? "",
    segundoApellido: normalizeOptionalText(user.segundo_apellido) ?? "",
    tercerApellido: normalizeOptionalText(user.tercer_apellido) ?? "",
    nombreVisible: buildUserDisplayName(user),
    tipoVinculo: normalizeOptionalText(user.tipo_vinculo) ?? "",
    unidad: normalizeOptionalText(user.unidad) ?? "",
    cargo: resolveEffectiveJobTitleName(user) ?? "",
    lugar: normalizeOptionalText(user.lugar) ?? "",
    numeroItem: normalizeOptionalText(user.numero_item) ?? "",
    activo: user.activo === true,
  };
}

function buildUserQrPayload(_: any, qrCode: string) {
  // El QR visible del perfil usa un token firmado y estable.
  // No depende de ubicacion, no rota y queda valido para el escaner del evento.
  return buildDynamicQrPayload(qrCode, STATIC_DYNAMIC_QR_EXPIRES_AT);
}

function buildStoredUserQrMetadata(
  user: any,
  qrCode: string,
  previousData?: unknown,
  dynamicIssue?: {
    qrPayload: string;
    issuedAt: Date;
    expiresAt: Date;
    latitud: number;
    longitud: number;
    accuracy: number | null;
  },
) {
  // `datos_qr` conserva metadata completa para auditoria y soporte.
  // Esa metadata no se expone en el QR renderizado al usuario final.
  const baseMetadata = {
    ...buildUserQrPayloadObject(user, qrCode),
    payloadPublico: qrCode,
    payloadTipo: "EXTERNAL_ID",
    origen: "usuario",
    fotoRegistrada: normalizeOptionalText(user.foto_url) != null,
    syncedAt: new Date().toISOString(),
  };

  const preservedDynamicQr = readDynamicQrMetadata(previousData);

  if (dynamicIssue == null && preservedDynamicQr == null) {
    return baseMetadata;
  }

  return {
    ...baseMetadata,
    dynamicQr:
      dynamicIssue == null
        ? preservedDynamicQr
        : buildNextDynamicQrMetadata(preservedDynamicQr, dynamicIssue),
  };
}

function readDynamicQrMetadata(source: unknown) {
  const record = readLooseJsonRecord(source);
  const dynamicQr = readLooseJsonRecord(record?.dynamicQr);

  return dynamicQr;
}

function readDynamicQrHistoryEntries(source: unknown) {
  const dynamicQr = readDynamicQrMetadata(source);
  const history = dynamicQr?.history;

  if (!Array.isArray(history)) {
    return [];
  }

  return history.filter(
    (item) => item != null && typeof item === "object" && !Array.isArray(item),
  ) as Record<string, unknown>[];
}

function readLooseJsonRecord(value: unknown) {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  return value as Record<string, unknown>;
}

function readIsoDate(value: unknown) {
  if (typeof value !== "string") {
    return null;
  }

  const parsedDate = new Date(value);

  if (Number.isNaN(parsedDate.getTime())) {
    return null;
  }

  return parsedDate;
}

function buildNextDynamicQrMetadata(
  previousDynamicQr: Record<string, unknown> | null,
  dynamicIssue: {
    qrPayload: string;
    issuedAt: Date;
    expiresAt: Date;
    latitud: number;
    longitud: number;
    accuracy: number | null;
  },
) {
  const previousHistory = Array.isArray(previousDynamicQr?.history)
    ? previousDynamicQr!.history.filter(
        (item) =>
          item != null &&
          typeof item === "object" &&
          !Array.isArray(item),
      )
    : [];
  const historyEntry = {
    generatedAt: dynamicIssue.issuedAt.toISOString(),
    expiresAt: dynamicIssue.expiresAt.toISOString(),
    tokenHash: createHash("sha256").update(dynamicIssue.qrPayload).digest("hex"),
    location: {
      latitud: dynamicIssue.latitud,
      longitud: dynamicIssue.longitud,
      accuracy: dynamicIssue.accuracy,
    },
  };

  return {
    ttlSeconds: DYNAMIC_QR_TTL_SECONDS,
    lastGeneratedAt: dynamicIssue.issuedAt.toISOString(),
    lastExpiresAt: dynamicIssue.expiresAt.toISOString(),
    lastTokenHash: historyEntry.tokenHash,
    lastLocation: historyEntry.location,
    history: [historyEntry, ...previousHistory].slice(0, DYNAMIC_QR_HISTORY_LIMIT),
  };
}

function parseQrGenerationFilterBy(url: URL) {
  const filterBy = (url.searchParams.get("filterBy") ?? "usuario")
    .trim()
    .toLowerCase();

  if (filterBy === "usuario" || filterBy === "ci") {
    return filterBy;
  }

  throw new HttpError(400, "El filtro del mapa QR no es valido.");
}

function parseQrMapScope(url: URL) {
  const scope = (url.searchParams.get("scope") ?? "eventos").trim().toLowerCase();

  if (scope === "generaciones" || scope === "eventos") {
    return scope;
  }

  throw new HttpError(400, "El alcance del mapa QR no es valido.");
}

function serializeQrGenerationHistoryRecords(person: any): QrMapRecord[] {
  const linkedUser = person.usuario ?? null;
  const officeName = resolveLinkedOfficeName(linkedUser);
  const fullName = buildResolvedPersonDisplayName(person);
  const ci = normalizeOptionalText(linkedUser?.ci ?? person.ci) ?? "";
  const history = readDynamicQrHistoryEntries(person.datos_qr);
  const records: QrMapRecord[] = [];

  history.forEach((entry, index) => {
    const generatedAt = normalizeOptionalText(entry.generatedAt);
    const expiresAt = normalizeOptionalText(entry.expiresAt);
    const location = readLooseJsonRecord(entry.location);
    const latitud = readFiniteNumber(location?.latitud);
    const longitud = readFiniteNumber(location?.longitud);
    const accuracy = readFiniteNumber(location?.accuracy);

    if (!generatedAt || latitud == null || longitud == null) {
      return;
    }

    records.push({
        id: `${person.id}-${generatedAt}-${index}`,
        source: "GENERACION" as const,
        personaId: person.id,
        usuarioId: linkedUser?.id ?? null,
        nombreCompleto: fullName,
        ci,
        email: linkedUser?.email ?? null,
        oficina: officeName,
        codigoQr: person.codigo_qr ?? null,
        latitud,
        longitud,
        accuracy,
        generatedAt,
        expiresAt,
        eventoId: null,
        eventoNombre: null,
        controlId: null,
        controlNombre: null,
        estado: null,
        observacion: null,
        registrationSource: "QR" as const,
    });
  });

  return records;
}

function serializeEventScanMapRecord(controlAttendance: any): QrMapRecord | null {
  const attendance = controlAttendance.asistencias;
  const person = attendance.personas;
  const linkedUser = person.usuario ?? null;
  const officeName = resolveLinkedOfficeName(linkedUser);
  const fullName = buildResolvedPersonDisplayName(person);
  const ci = normalizeOptionalText(linkedUser?.ci ?? person.ci) ?? "";
  const latitud = controlAttendance.latitud_registro;
  const longitud = controlAttendance.longitud_registro;

  if (
    typeof latitud !== "number" ||
    !Number.isFinite(latitud) ||
    typeof longitud !== "number" ||
    !Number.isFinite(longitud)
  ) {
    return null;
  }

  return {
    id: `EVT-${controlAttendance.id}`,
    source: "EVENTO" as const,
    personaId: person.id,
    usuarioId: linkedUser?.id ?? null,
    nombreCompleto: fullName,
    ci,
    email: linkedUser?.email ?? null,
    oficina: officeName,
    codigoQr: person.codigo_qr ?? null,
    latitud,
    longitud,
    accuracy:
      typeof controlAttendance.accuracy_registro === "number" &&
        Number.isFinite(controlAttendance.accuracy_registro)
      ? controlAttendance.accuracy_registro
      : null,
    generatedAt: controlAttendance.registrado_en.toISOString(),
    expiresAt: null,
    eventoId: attendance.eventos.id,
    eventoNombre: attendance.eventos.nombre,
    controlId: controlAttendance.control_id,
    controlNombre: controlAttendance.evento_controles.nombre,
    estado: controlAttendance.estado,
    observacion:
      normalizeOptionalText(controlAttendance.observacion) ??
      normalizeOptionalText(attendance.observacion),
    registrationSource: readAttendanceRegistrationSource(
      attendance.datos_qr_snapshot,
    ),
  };
}

function matchesQrMapFilter(
  record: QrMapRecord,
  query: string,
  filterBy: "usuario" | "ci",
) {
  if (!query) {
    return true;
  }

  if (filterBy === "ci") {
    return record.ci.toLowerCase().includes(query);
  }

  return [
    record.nombreCompleto,
    record.email ?? "",
  ].some((value) => value.toLowerCase().includes(query));
}

function matchesQrMapDateRange(
  record: QrMapRecord,
  generatedFrom: Date | null,
  generatedTo: Date | null,
) {
  if (generatedFrom == null && generatedTo == null) {
    return true;
  }

  const generatedAt = new Date(record.generatedAt);

  if (Number.isNaN(generatedAt.getTime())) {
    return false;
  }

  if (generatedFrom != null && generatedAt.getTime() < generatedFrom.getTime()) {
    return false;
  }

  if (generatedTo != null && generatedAt.getTime() > generatedTo.getTime()) {
    return false;
  }

  return true;
}

function readFiniteNumber(value: unknown) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }

  return value;
}

function readAttendanceRegistrationSource(
  snapshot: unknown,
): "QR" | "CI" | null {
  const record = readLooseJsonRecord(snapshot);
  const source = normalizeOptionalText(record?.registrationSource);

  return source === "CI" ? "CI" : source === "QR" ? "QR" : null;
}

function isQrMapRecord(
  value: QrMapRecord | null,
): value is QrMapRecord {
  return value != null;
}

async function findPersonByLegacyUserQrCode(scannedCode: string) {
  const match = scannedCode.trim().toUpperCase().match(/^USR-(\d+)-([A-F0-9]{12})$/);

  if (!match) {
    return null;
  }

  const userId = Number(match[1]);

  if (!Number.isInteger(userId) || userId <= 0) {
    return null;
  }

  const person = await prisma.personas.findUnique({
    where: { usuario_id: userId },
    include: personIdentityInclude,
  });

  if (!person?.usuario) {
    return null;
  }

  const expectedCode = buildLegacyUserQrCode(person.usuario);

  return expectedCode === scannedCode.trim().toUpperCase() ? person : null;
}

function buildResolvedPersonDisplayName(person: any) {
  if (person.usuario) {
    return buildUserDisplayName(person.usuario);
  }

  return normalizeOptionalText(person.nombre_completo) ?? "";
}

function buildAttendanceQrSnapshot(
  person: any,
  scannedValue: string,
  lookupCode: string,
  payloadFields: JsonRecord | null,
  options?: {
    registrationSource?: "QR" | "CI";
    registrationCi?: string | null;
    scannedAt?: Date | null;
    registrationLocation?: {
      latitud: number;
      longitud: number;
      accuracy: number | null;
    } | null;
    eventRequirement?: EventAttendanceRequirement | null;
  },
) {
  // Snapshot tecnico del registro:
  // qr crudo leido o CI manual -> codigo normalizado -> persona resuelta.
  // Esto deja evidencia de como se consolido la identidad del registro.
  const linkedUser = person.usuario ?? null;

  return {
    rawValue: scannedValue.trim(),
    lookupCode,
    payloadFields,
    personaId: person.id,
    usuarioId: linkedUser?.id ?? null,
    codigoQr: person.codigo_qr ?? null,
    nombreCompleto: buildResolvedPersonDisplayName(person),
    ci: linkedUser?.ci ?? person.ci ?? null,
    email: linkedUser?.email ?? null,
    unidad: linkedUser?.unidad ?? null,
    cargo: resolveEffectiveJobTitleName(linkedUser),
    tipoVinculo: linkedUser?.tipo_vinculo ?? null,
    numeroItem: linkedUser?.numero_item ?? null,
    fotoRegistrada: normalizeOptionalText(linkedUser?.foto_url) != null,
    origen: linkedUser == null ? "persona" : "usuario",
    registrationSource: options?.registrationSource ?? "QR",
    registrationCi: normalizeOptionalText(options?.registrationCi) ?? null,
    scannedAt: options?.scannedAt?.toISOString() ?? null,
    registrationLocation: options?.registrationLocation ?? null,
    eventRequirement: options?.eventRequirement ?? null,
  };
}

async function loadSerializedOffices(requester?: AuthenticatedUser) {
  if (requester != null && isHealthAdminUser(requester)) {
    const oficinas = await prisma.oficinas.findMany({
      where: { nivel: HEALTH_OFFICE_LEVEL },
    });
    oficinas.sort(compareOfficeHierarchy);

    return oficinas.map(serializeOffice);
  }

  const cachedOffices = readCacheValue(officesCache);

  if (cachedOffices != null) {
    return cachedOffices;
  }

  const oficinas = await prisma.oficinas.findMany();
  oficinas.sort(compareOfficeHierarchy);
  const serializedOffices = oficinas.map(serializeOffice);
  officesCache = createCacheEntry(serializedOffices, REFERENCE_CACHE_TTL_MS);

  return serializedOffices;
}

async function loadSerializedJobTitles() {
  const cachedJobTitles = readCacheValue(cargosCache);

  if (cachedJobTitles != null) {
    return cachedJobTitles;
  }

  const cargos = await prisma.cargos.findMany({
    orderBy: [{ cargo: "asc" }, { codigo: "asc" }],
  });
  const serializedJobTitles = cargos.map(serializeJobTitle);
  cargosCache = createCacheEntry(serializedJobTitles, REFERENCE_CACHE_TTL_MS);

  return serializedJobTitles;
}

async function loadDashboardSummary(requester?: AuthenticatedUser) {
  if (requester != null && isHealthAdminUser(requester)) {
    const [usuariosRegistrados, oficinas, eventos] = await Promise.all([
      prisma.usuarios.count({
        where: healthUserWhereForRequester(requester),
      }),
      prisma.oficinas.count({
        where: { nivel: HEALTH_OFFICE_LEVEL },
      }),
      prisma.eventos.count({
        where: healthEventWhereForRequester(requester),
      }),
    ]);

    return {
      usuariosRegistrados,
      oficinas,
      eventos,
    };
  }

  const cachedSummary = readCacheValue(dashboardSummaryCache);

  if (cachedSummary != null) {
    return cachedSummary;
  }

  const [usuariosRegistrados, oficinas, eventos] = await Promise.all([
    prisma.usuarios.count(),
    prisma.oficinas.count(),
    prisma.eventos.count(),
  ]);
  const summary = {
    usuariosRegistrados,
    oficinas,
    eventos,
  };
  dashboardSummaryCache = createCacheEntry(summary, DASHBOARD_CACHE_TTL_MS);

  return summary;
}

async function registerDeviceHeartbeat(
  userId: number,
  input: DeviceHeartbeatInput,
) {
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const result = await client.query<{ force_logout: boolean }>(
      `
        INSERT INTO "celulares_asistencia" (
          "device_id",
          "usuario_id",
          "platform",
          "manufacturer",
          "model",
          "android_sdk",
          "battery_level",
          "is_charging",
          "brightness",
          "kiosk_enabled",
          "last_seen_at",
          "updated_at"
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT ("device_id") DO UPDATE SET
          "usuario_id" = EXCLUDED."usuario_id",
          "platform" = EXCLUDED."platform",
          "manufacturer" = EXCLUDED."manufacturer",
          "model" = EXCLUDED."model",
          "android_sdk" = EXCLUDED."android_sdk",
          "battery_level" = EXCLUDED."battery_level",
          "is_charging" = EXCLUDED."is_charging",
          "brightness" = EXCLUDED."brightness",
          "kiosk_enabled" = EXCLUDED."kiosk_enabled",
          "last_seen_at" = CURRENT_TIMESTAMP,
          "updated_at" = CURRENT_TIMESTAMP
        RETURNING "logout_requested_at" IS NOT NULL AS "force_logout"
      `,
      [
        input.deviceId,
        userId,
        input.platform,
        input.manufacturer,
        input.model,
        input.androidSdk,
        input.batteryLevel,
        input.isCharging,
        input.brightness,
        input.kioskEnabled,
      ],
    );
    const forceLogout = result.rows[0]?.force_logout === true;

    await client.query(
      `
        DELETE FROM "celulares_asistencia"
        WHERE "usuario_id" = $1
          AND "device_id" <> $2
      `,
      [userId, input.deviceId],
    );

    if (forceLogout) {
      await client.query(
        `
          UPDATE "celulares_asistencia"
          SET "logout_requested_at" = NULL,
              "logout_requested_by_id" = NULL,
              "kiosk_enabled" = FALSE,
              "last_seen_at" = CURRENT_TIMESTAMP - ($2::int * INTERVAL '1 millisecond'),
              "updated_at" = CURRENT_TIMESTAMP
          WHERE "device_id" = $1
        `,
        [input.deviceId, DEVICE_ONLINE_THRESHOLD_MS + 1000],
      );
    }

    await client.query("COMMIT");

    return {
      forceLogout,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function loadManagedDevices() {
  const result = await pool.query(
    `
      SELECT DISTINCT ON (c."usuario_id")
        c."device_id",
        c."usuario_id",
        c."platform",
        c."manufacturer",
        c."model",
        c."android_sdk",
        c."battery_level",
        c."is_charging",
        c."brightness",
        c."kiosk_enabled",
        c."last_seen_at",
        c."logout_requested_at",
        u."nombre_completo",
        u."nombres",
        u."primer_apellido",
        u."segundo_apellido",
        u."tercer_apellido",
        u."ci"
      FROM "celulares_asistencia" c
      INNER JOIN "usuarios" u ON u."id" = c."usuario_id"
      WHERE u."rol" = 'ALMUERZO'
      ORDER BY c."usuario_id", c."last_seen_at" DESC, c."id" DESC
    `,
  );

  return result.rows
    .map(serializeManagedDevice)
    .sort((left, right) => {
      if (left.isOnline !== right.isOnline) {
        return left.isOnline ? -1 : 1;
      }

      return right.lastSeenAt.localeCompare(left.lastSeenAt);
    });
}

async function requestDeviceLogout(deviceId: string, requesterUserId: number) {
  const result = await pool.query(
    `
      UPDATE "celulares_asistencia"
      SET "logout_requested_at" = CURRENT_TIMESTAMP,
          "logout_requested_by_id" = $2,
          "kiosk_enabled" = FALSE,
          "last_seen_at" = CURRENT_TIMESTAMP - ($3::int * INTERVAL '1 millisecond'),
          "updated_at" = CURRENT_TIMESTAMP
      WHERE "device_id" = $1
      RETURNING "device_id"
    `,
    [deviceId, requesterUserId, DEVICE_ONLINE_THRESHOLD_MS + 1000],
  );

  if (result.rowCount === 0) {
    throw new HttpError(404, "No se encontro el celular seleccionado.");
  }
}

async function requestDeviceLogin(deviceId: string) {
  const result = await pool.query<{ usuario_id: number }>(
    `
      UPDATE "celulares_asistencia"
      SET "logout_requested_at" = NULL,
          "logout_requested_by_id" = NULL,
          "updated_at" = CURRENT_TIMESTAMP
      WHERE "device_id" = $1
      RETURNING "usuario_id"
    `,
    [deviceId],
  );

  const row = result.rows[0];

  if (row == null) {
    throw new HttpError(404, "No se encontro el celular seleccionado.");
  }

  return {
    userId: Number(row.usuario_id),
  };
}

async function markUserDevicesOffline(userId: number) {
  await pool.query(
    `
      UPDATE "celulares_asistencia"
      SET "logout_requested_at" = NULL,
          "logout_requested_by_id" = NULL,
          "kiosk_enabled" = FALSE,
          "last_seen_at" = CURRENT_TIMESTAMP - ($2::int * INTERVAL '1 millisecond'),
          "updated_at" = CURRENT_TIMESTAMP
      WHERE "usuario_id" = $1
    `,
    [userId, DEVICE_ONLINE_THRESHOLD_MS + 1000],
  );
}

function serializeManagedDevice(device: any) {
  const lastSeenAt = device.last_seen_at instanceof Date
    ? device.last_seen_at
    : new Date(device.last_seen_at);
  const logoutRequestedAt = device.logout_requested_at instanceof Date
    ? device.logout_requested_at
    : device.logout_requested_at == null
      ? null
      : new Date(device.logout_requested_at);
  const userName = buildUserDisplayName({
    nombre_completo: device.nombre_completo,
    nombres: device.nombres,
    primer_apellido: device.primer_apellido,
    segundo_apellido: device.segundo_apellido,
    tercer_apellido: device.tercer_apellido,
  });

  return {
    deviceId: device.device_id ?? "",
    userId: Number(device.usuario_id ?? 0),
    userName,
    userCi: device.ci ?? "",
    platform: device.platform ?? "",
    manufacturer: device.manufacturer ?? "",
    model: device.model ?? "",
    androidSdk: nullableNumber(device.android_sdk),
    batteryLevel: nullableNumber(device.battery_level),
    isCharging: typeof device.is_charging === "boolean" ? device.is_charging : null,
    brightness: nullableNumber(device.brightness),
    kioskEnabled: device.kiosk_enabled === true,
    isOnline:
      device.kiosk_enabled === true &&
      logoutRequestedAt == null &&
      Date.now() - lastSeenAt.getTime() <= DEVICE_ONLINE_THRESHOLD_MS,
    lastSeenAt: lastSeenAt.toISOString(),
    logoutRequestedAt: logoutRequestedAt?.toISOString() ?? null,
  };
}

function nullableNumber(value: unknown) {
  if (typeof value === "number") {
    return value;
  }

  if (typeof value === "string" && value.trim().length > 0) {
    const parsedValue = Number(value);
    return Number.isFinite(parsedValue) ? parsedValue : null;
  }

  return null;
}

async function registerNotificationToken(
  userId: number,
  input: RegisterNotificationTokenInput,
) {
  await pool.query(
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

async function deleteNotificationToken(userId: number, token: string) {
  await pool.query(
    `
      DELETE FROM "notificacion_tokens"
      WHERE "usuario_id" = $1 AND "token" = $2
    `,
    [userId, token],
  );
}

async function loadReceivedNotifications(userId: number) {
  const result = await pool.query<ReceivedNotificationRecord>(
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

async function markReceivedNotificationRead(userId: number, notificationId: number) {
  await pool.query(
    `
      UPDATE "notificaciones"
      SET "leida_en" = COALESCE("leida_en", CURRENT_TIMESTAMP)
      WHERE "id" = $1 AND "usuario_id" = $2
    `,
    [notificationId, userId],
  );
}

function serializeReceivedNotification(notification: ReceivedNotificationRecord) {
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

const SENT_NOTIFICATION_HISTORY_PAGE_SIZE = 20;

async function loadSentNotificationHistory(page: number) {
  const offset = (page - 1) * SENT_NOTIFICATION_HISTORY_PAGE_SIZE;
  const [itemsResult, countResult] = await Promise.all([
    pool.query<SentNotificationRecord>(
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
    pool.query<{ total: string }>(
      `SELECT COUNT(*)::text AS "total" FROM "notificacion_envios"`,
    ),
  ]);
  const total = Number.parseInt(countResult.rows[0]?.total ?? "0", 10);

  return {
    page,
    pageSize: SENT_NOTIFICATION_HISTORY_PAGE_SIZE,
    total,
    totalPages: Math.max(1, Math.ceil(total / SENT_NOTIFICATION_HISTORY_PAGE_SIZE)),
    items: itemsResult.rows.map(serializeSentNotification),
  };
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

async function sendFirebaseNotification(input: SendNotificationInput, senderUserId: number) {
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
    const mappedError = error instanceof HttpError ? error : mapFirebaseMessagingError(error);
    result = {
      requested: targets.tokens.length,
      sent: 0,
      failed: targets.tokens.length,
      message: mappedError instanceof HttpError
        ? mappedError.message
        : getErrorMessage(mappedError),
    };
  }

  await saveSentNotification(input, senderUserId, result);

  return result;
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
  await pool.query(
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

async function sendFirebaseMulticastNotification(
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

async function sendDeviceLoginCommand(userId: number, deviceId: string) {
  const targets = await loadNotificationTokensForUser(userId);

  return sendFirebaseDataMulticastMessage(targets, {
    source: "innovafuncionario",
    type: "device_login",
    action: "open_app",
    deviceId,
  });
}

async function loadNotificationTokensForUser(userId: number) {
  const result = await pool.query<{ token: string }>(
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

async function sendFirebaseDataMulticastMessage(
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

async function notifyExitPermitApprovers(salidaId: number) {
  const salida = await prisma.salidas.findUnique({
    where: { id: salidaId },
    include: exitPermitRecordInclude,
  });

  if (salida == null || salida.estado !== estado_salida.PENDIENTE) {
    return;
  }

  const targets = await loadExitPermitApproverNotificationTargets(salida);
  const title = "Solicitud de salida pendiente";
  const body = `${salida.solicitante_nombre_completo} envio una solicitud de salida.`;

  await createReceivedNotifications(targets.userIds, {
    type: "exit_permit_request",
    title,
    body,
    targetSection: "exitPermitRequests",
    salidaId: salida.id,
  });

  await sendFirebaseMulticastNotification(targets.tokens, {
    title,
    body,
    data: {
      source: "innovafuncionario",
      type: "exit_permit_request",
      targetSection: "exitPermitRequests",
      salidaId: String(salida.id),
    },
  });
}

async function loadExitPermitApproverNotificationTargets(salida: any) {
  const applicant = salida.usuarios;
  const candidateWhere = buildExitPermitNotificationCandidateWhere(salida);

  if (candidateWhere == null) {
    return { userIds: [] as number[], tokens: [] as string[] };
  }

  const candidates = await prisma.usuarios.findMany({
    where: candidateWhere,
    include: userWithOfficeInclude,
  });
  const approverIds: number[] = [];

  for (const approver of candidates) {
    if (await canReviewExitPermit(approver, salida, applicant)) {
      approverIds.push(approver.id);
    }
  }

  if (approverIds.length === 0) {
    return { userIds: [] as number[], tokens: [] as string[] };
  }

  const result = await pool.query<{ token: string }>(
    `
      SELECT DISTINCT "token"
      FROM "notificacion_tokens"
      WHERE "usuario_id" = ANY($1::int[])
        AND "platform" IN ('ANDROID', 'IOS')
    `,
    [approverIds],
  );

  return {
    userIds: approverIds,
    tokens: result.rows.map((row) => row.token),
  };
}

async function createReceivedNotifications(
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

  await pool.query(
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

function buildExitPermitNotificationCandidateWhere(salida: any) {
  return {
    id: { not: salida.usuario_id },
    activo: true,
    rol: rol_usuario.OPERADOR,
  };
}

async function canReviewExitPermit(approver: any, salida: any, applicant: any) {
  const approverOfficeId = resolveLinkedOfficeId(approver);
  const applicantIsChief = isChiefExitPermitApplicant(applicant);
  const applicantIsDirector = isDirectorExitPermitApprover(applicant);

  if (!isExitPermitApproverUser(approver) || salida.usuario_id === approver.id) {
    return false;
  }

  if (isDirectorExitPermitApprover(approver)) {
    if (!isApplicantInDirectorScope(approver, applicant)) {
      return false;
    }

    if (applicantIsChief) {
      return true;
    }

    if (applicantIsDirector || isSeniorExitPermitApprover(applicant)) {
      return false;
    }

    return !(await hasActiveChiefInEffectiveOffice(
      salida.solicitante_oficina_id,
    ));
  }

  if (isSeniorExitPermitApprover(approver)) {
    return canSeniorReviewExitPermit(approver, salida, applicant);
  }

  return (
    approverOfficeId != null &&
    salida.solicitante_oficina_id != null &&
    approverOfficeId === salida.solicitante_oficina_id &&
    !applicantIsChief &&
    !applicantIsDirector
  );
}

async function filterReviewableExitPermits(approver: any, salidas: any[]) {
  const result: any[] = [];

  for (const salida of salidas) {
    if (await canReviewExitPermit(approver, salida, salida.usuarios)) {
      result.push(salida);
    }
  }

  return result;
}

async function canSeniorReviewExitPermit(
  approver: any,
  salida: any,
  applicant: any,
) {
  const seniorOfficeCode = normalizeOptionalText(resolveLinkedOfficeCode(approver));
  const applicantOfficeCode = normalizeOptionalText(resolveLinkedOfficeCode(applicant));

  if (
    seniorOfficeCode == null ||
    applicantOfficeCode == null ||
    !applicantOfficeCode.startsWith(`${seniorOfficeCode}.`)
  ) {
    return false;
  }

  const directionCode = resolveChildOfficeCodeUnderParent(
    applicantOfficeCode,
    seniorOfficeCode,
  );

  if (directionCode == null) {
    return false;
  }

  if (await hasActiveDirectorInEffectiveOfficeCode(directionCode)) {
    return false;
  }

  if (isDirectorExitPermitApprover(applicant) || isSeniorExitPermitApprover(applicant)) {
    return false;
  }

  if (isChiefExitPermitApplicant(applicant)) {
    return true;
  }

  return !(await hasActiveChiefInEffectiveOffice(salida.solicitante_oficina_id));
}

function resolveChildOfficeCodeUnderParent(
  officeCode: string,
  parentCode: string,
) {
  if (!officeCode.startsWith(`${parentCode}.`)) {
    return null;
  }

  const remainingParts = officeCode
    .slice(parentCode.length + 1)
    .split(".")
    .filter((part) => part.length > 0);

  if (remainingParts.length === 0) {
    return null;
  }

  return `${parentCode}.${remainingParts[0]}`;
}

async function hasActiveChiefInEffectiveOffice(officeId: number | null | undefined) {
  if (officeId == null) {
    return false;
  }

  const result = await pool.query<{ exists: number }>(
    `
      SELECT 1 AS "exists"
      FROM "usuarios" u
      WHERE u."activo" = TRUE
        AND u."rol" = $2
        AND COALESCE(u."oficina_comision_id", u."oficina_id") = $1
        AND (
          CASE
            WHEN NULLIF(TRIM(u."subcargo_codigo"), '') IS NOT NULL THEN NULLIF(TRIM(u."subcargo_codigo"), '')
            WHEN NULLIF(TRIM(u."subcargo"), '') IS NOT NULL THEN NULL
            ELSE NULLIF(TRIM(u."cargo_codigo"), '')
          END = ANY($3::text[])
          OR LOWER(COALESCE(NULLIF(TRIM(u."subcargo"), ''), u."cargo", '')) LIKE '%jefe%'
        )
      LIMIT 1
    `,
    [officeId, rol_usuario.OPERADOR, Array.from(EXIT_PERMIT_CHIEF_CARGO_CODES)],
  );

  return result.rows.length > 0;
}

async function hasActiveDirectorInEffectiveOfficeCode(
  officeCode: string | null | undefined,
) {
  const normalizedCode = normalizeOptionalText(officeCode);

  if (normalizedCode == null) {
    return false;
  }

  const result = await pool.query<{ exists: number }>(
    `
      SELECT 1 AS "exists"
      FROM "usuarios" u
      JOIN "oficinas" o
        ON o."id" = COALESCE(u."oficina_comision_id", u."oficina_id")
      WHERE u."activo" = TRUE
        AND u."rol" = $2
        AND o."cod" = $1
        AND (
          LOWER(COALESCE(NULLIF(TRIM(u."subcargo"), ''), u."cargo", '')) LIKE '%director%'
          OR LOWER(COALESCE(NULLIF(TRIM(u."subcargo"), ''), u."cargo", '')) LIKE '%direcctor%'
        )
      LIMIT 1
    `,
    [normalizedCode, rol_usuario.OPERADOR],
  );

  return result.rows.length > 0;
}

async function loadNotificationTargets(input: SendNotificationInput) {
  const clauses = [
    `u."activo" = TRUE`,
    `nt."platform" IN ('ANDROID', 'IOS')`,
  ];
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

  const result = await pool.query<{ usuario_id: number; token: string }>(
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

  await pool.query(
    `
      DELETE FROM "notificacion_tokens"
      WHERE "token" = ANY($1::text[])
    `,
    [tokens],
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

function readErrorCode(error: unknown) {
  if (typeof error !== "object" || error == null || !("code" in error)) {
    return null;
  }

  const code = (error as { code?: unknown }).code;

  return typeof code === "string" ? code : null;
}

function readFirebaseServiceAccountCredential() {
  if (FIREBASE_SERVICE_ACCOUNT_JSON == null) {
    return null;
  }

  try {
    const jsonText = FIREBASE_SERVICE_ACCOUNT_JSON.trim().startsWith("{")
      ? FIREBASE_SERVICE_ACCOUNT_JSON
      : Buffer.from(FIREBASE_SERVICE_ACCOUNT_JSON, "base64").toString("utf8");

    return cert(JSON.parse(jsonText));
  } catch {
    throw new HttpError(
      500,
      "FIREBASE_SERVICE_ACCOUNT_JSON no tiene un formato valido.",
    );
  }
}

function chunkArray<T>(values: T[], size: number) {
  const chunks: T[][] = [];

  for (let index = 0; index < values.length; index += size) {
    chunks.push(values.slice(index, index + size));
  }

  return chunks;
}

async function loadSerializedEventSummaries(requester?: AuthenticatedUser) {
  const eventWhere = healthEventWhereForRequester(requester);

  if (eventWhere != null) {
    const events = await prisma.eventos.findMany({
      where: eventWhere,
      orderBy: [{ fecha_evento: "desc" }, { id: "desc" }],
      include: eventSummaryInclude,
    });
    const attendanceCountMap = await loadEventAttendanceCountMap(
      events.map((event) => event.id),
    );

    return events.map((event) =>
      serializeEventSummary(event, attendanceCountMap.get(event.id)),
    );
  }

  const cachedEvents = readCacheValue(eventSummaryCache);

  if (cachedEvents != null) {
    return cachedEvents;
  }

  const events = await prisma.eventos.findMany({
    orderBy: [{ fecha_evento: "desc" }, { id: "desc" }],
    include: eventSummaryInclude,
  });
  const attendanceCountMap = await loadEventAttendanceCountMap(
    events.map((event) => event.id),
  );
  const serializedEvents = events.map((event) =>
    serializeEventSummary(event, attendanceCountMap.get(event.id)),
  );
  eventSummaryCache = createCacheEntry(
    serializedEvents,
    EVENT_SUMMARY_CACHE_TTL_MS,
  );

  return serializedEvents;
}

async function loadSerializedAssignedEventSummaries(requester: AuthenticatedUser) {
  const linkedPerson = await prisma.personas.findFirst({
    where: {
      OR: [
        { usuario_id: requester.id },
        ...(requester.ci != null && requester.ci.trim().length >= 3
          ? [{ ci: requester.ci.trim() }]
          : []),
      ],
    },
    select: {
      id: true,
    },
  });
  const whereParts: Prisma.eventosWhereInput[] = [
    {
      fecha_evento: {
        gte: new Date(),
      },
    },
  ];
  const scopedEventWhere = healthEventWhereForRequester(requester);

  if (scopedEventWhere != null) {
    whereParts.push(scopedEventWhere);
  }

  if (linkedPerson != null) {
    whereParts.push({
      NOT: {
        asistencias: {
          some: {
            persona_id: linkedPerson.id,
            estado: estado_asistencia.ASISTIO,
          },
        },
      },
    });
  }

  const events = await prisma.eventos.findMany({
    where: {
      AND: whereParts,
    },
    orderBy: [{ fecha_evento: "asc" }, { id: "asc" }],
    include: eventSummaryInclude,
  });
  const attendanceCountMap = await loadEventAttendanceCountMap(
    events.map((event) => event.id),
  );

  return events.map((event) =>
    serializeEventSummary(event, attendanceCountMap.get(event.id)),
  );
}

async function loadEventAttendanceCountMap(eventIds: number[]) {
  const uniqueEventIds = [...new Set(eventIds.filter((eventId) => eventId > 0))];
  const countMap = new Map<number, EventAttendanceCounts>();

  if (uniqueEventIds.length === 0) {
    return countMap;
  }

  const groupedAttendances = await prisma.asistencias.groupBy({
    by: ["evento_id", "estado"],
    where: {
      evento_id: {
        in: uniqueEventIds,
      },
    },
    _count: {
      _all: true,
    },
  });

  for (const eventId of uniqueEventIds) {
    countMap.set(eventId, {
      attended: 0,
      observed: 0,
      total: 0,
    });
  }

  for (const groupedAttendance of groupedAttendances) {
    const currentCounts = countMap.get(groupedAttendance.evento_id) ?? {
      attended: 0,
      observed: 0,
      total: 0,
    };
    const nextCount = groupedAttendance._count._all;

    if (groupedAttendance.estado === estado_asistencia.ASISTIO) {
      currentCounts.attended = nextCount;
    } else if (groupedAttendance.estado === estado_asistencia.OBSERVADO) {
      currentCounts.observed = nextCount;
    }

    currentCounts.total = currentCounts.attended + currentCounts.observed;
    countMap.set(groupedAttendance.evento_id, currentCounts);
  }

  return countMap;
}

function serializeDepartment(departamento: {
  id: number;
  nombre: string;
  descripcion: string | null;
}) {
  return {
    id: departamento.id,
    nombre: departamento.nombre,
    descripcion: departamento.descripcion,
  };
}

function serializeOffice(oficina: {
  id: number;
  oficina: string;
  cod: string;
  nivel: number;
}) {
  return {
    id: oficina.id,
    nombre: oficina.oficina,
    codigo: oficina.cod,
    nivel: oficina.nivel,
  };
}

function serializeJobTitle(cargo: { codigo: string; cargo: string }) {
  return {
    codigo: cargo.codigo,
    cargo: cargo.cargo,
  };
}

function serializeEventControl(control: {
  id: number;
  nombre: string;
  orden: number;
  hora_inicio?: string | null;
  hora_fin?: string | null;
}) {
  return {
    id: control.id,
    nombre: control.nombre,
    orden: control.orden,
    horaInicio: control.hora_inicio ?? null,
    horaFin: control.hora_fin ?? null,
  };
}

function serializeAttendanceControlRecord(controlAttendance: any) {
  return {
    id: controlAttendance.id,
    controlId: controlAttendance.control_id,
    controlNombre: controlAttendance.evento_controles.nombre,
    controlOrden: controlAttendance.evento_controles.orden,
    estado: controlAttendance.estado,
    retrasado: controlAttendance.retrasado === true,
    observacion: controlAttendance.observacion,
    registradoEn: controlAttendance.registrado_en.toISOString(),
  };
}

function serializeEventAttendanceLookup(attendance: any) {
  const serializedControls = (attendance.asistencia_controles ?? []).map(
    serializeAttendanceControlRecord,
  );
  const controlSummary = buildSerializedControlSummary(serializedControls);
  const lateRegisteredAt = serializedControls
    .filter((control: any) => control.retrasado === true)
    .map((control: any) => control.registradoEn as string)
    .sort()
    .at(-1) ?? null;

  return {
    estado: controlSummary.state,
    controles: controlSummary.controls,
    controlesRegistrados: controlSummary.registeredCount,
    controlesAsistidos: controlSummary.attendedCount,
    controlesObservados: controlSummary.observedCount,
    controlesRetrasados: controlSummary.lateCount,
    registradoEn: attendance.registrado_en.toISOString(),
    retrasado: lateRegisteredAt != null,
    retrasadoEn: lateRegisteredAt,
  };
}

function buildSerializedControlSummary(controlRecords: any[]) {
  const sortedControls = [...controlRecords].sort(
    (left, right) =>
      left.controlOrden - right.controlOrden ||
      left.registradoEn.localeCompare(right.registradoEn),
  );
  const attendedControls = sortedControls.filter(
    (control) => control.estado === estado_asistencia.ASISTIO,
  );
  const observedControls = sortedControls.filter(
    (control) => control.estado === estado_asistencia.OBSERVADO,
  );
  const lateControls = sortedControls.filter(
    (control) => control.retrasado === true,
  );

  return {
    controls: sortedControls,
    registeredCount: sortedControls.length,
    attendedCount: attendedControls.length,
    observedCount: observedControls.length,
    lateCount: lateControls.length,
    state:
      attendedControls.length > 0
        ? estado_asistencia.ASISTIO
        : estado_asistencia.OBSERVADO,
  };
}

function buildSerializedEventBase(event: any) {
  const departments = (event.evento_departamentos ?? []).map((item: any) => ({
    id: item.departamentos.id,
    nombre: item.departamentos.nombre,
    descripcion: item.departamentos.descripcion,
  }));
  const offices = (event.evento_oficinas ?? [])
    .map((item: any) => ({
      id: item.oficinas.id,
      nombre: item.oficinas.oficina,
      codigo: item.oficinas.cod,
      nivel: item.oficinas.nivel,
      seleccionDirecta: item.seleccion_directa === true,
    }))
    .sort((left: any, right: any) =>
      compareOfficeHierarchy(
        { cod: left.codigo, oficina: left.nombre },
        { cod: right.codigo, oficina: right.nombre },
      ),
    );
  const directOfficeIds = offices
    .filter((office: any) => office.seleccionDirecta === true)
    .map((office: any) => office.id);
  const cargos = (event.evento_cargos ?? [])
    .map((item: any) => ({
      codigo: item.cargos.codigo,
      cargo: item.cargos.cargo,
    }))
    .sort((left: any, right: any) => left.cargo.localeCompare(right.cargo));
  const cargoCodigosPorOficina = buildSerializedOfficeJobTitleSelections(event);
  const controls = (event.evento_controles ?? [])
    .map(serializeEventControl)
    .sort((left: any, right: any) => left.orden - right.orden);

  return {
    id: event.id,
    nombre: event.nombre,
    fechaEvento: serializeLocalEventDate(event.fecha_evento),
    descripcion: event.descripcion,
    direccion: event.direccion ?? event.descripcion,
    latitud: event.latitud,
    longitud: event.longitud,
    estado: event.estado,
    createdAt: event.created_at.toISOString(),
    updatedAt: event.updated_at.toISOString(),
    creadoPor: {
      id: event.usuarios.id,
      nombreCompleto: buildUserDisplayName(event.usuarios),
      email: event.usuarios.email,
    },
    controles: controls,
    departamentos: departments,
    oficinas: offices,
    cargos,
    cargoCodigosSeleccionados: cargos.map((cargo: any) => cargo.codigo),
    cargoCodigosPorOficina,
    oficinaIdsSeleccionados: directOfficeIds,
    oficinaIdsExcluidos: event.oficina_ids_excluidos ?? [],
  };
}

function buildSerializedOfficeJobTitleSelections(event: any) {
  const rows = event.evento_oficina_cargos ?? [];
  const byOfficeId = new Map<number, Set<string>>();

  for (const row of rows) {
    const officeId = row.oficina_id;
    const cargoCodigo = row.cargo_codigo;

    if (typeof officeId !== "number" || typeof cargoCodigo !== "string") {
      continue;
    }

    const codes = byOfficeId.get(officeId) ?? new Set<string>();
    codes.add(cargoCodigo);
    byOfficeId.set(officeId, codes);
  }

  return [...byOfficeId.entries()]
    .map(([oficinaId, cargoCodigos]) => ({
      oficinaId,
      cargoCodigos: [...cargoCodigos].sort(),
    }))
    .sort((left, right) => left.oficinaId - right.oficinaId);
}

function serializeEventSummary(
  event: any,
  attendanceCounts?: EventAttendanceCounts,
) {
  const resolvedCounts = attendanceCounts ?? {
    attended: 0,
    observed: 0,
    total: 0,
  };
  const controls = (event.evento_controles ?? [])
    .map(serializeEventControl)
    .sort((left: any, right: any) => left.orden - right.orden);
  const directOfficeIds = (event.evento_oficinas ?? [])
    .filter((item: any) => item.seleccion_directa === true)
    .map((item: any) => item.oficina_id);
  const selectedCargoCodes = (event.evento_cargos ?? [])
    .map((item: any) => item.cargo_codigo)
    .filter((value: unknown) => typeof value === "string")
    .sort();

  return {
    id: event.id,
    nombre: event.nombre,
    fechaEvento: serializeLocalEventDate(event.fecha_evento),
    descripcion: event.descripcion,
    direccion: event.direccion ?? event.descripcion,
    latitud: event.latitud,
    longitud: event.longitud,
    estado: event.estado,
    createdAt: event.created_at.toISOString(),
    updatedAt: event.updated_at.toISOString(),
    creadoPor: {
      id: event.usuarios.id,
      nombreCompleto: buildUserDisplayName(event.usuarios),
      email: event.usuarios.email,
    },
    controles: controls,
    departamentos: [],
    oficinas: [],
    cargos: [],
    cargoCodigosSeleccionados: selectedCargoCodes,
    cargoCodigosPorOficina: buildSerializedOfficeJobTitleSelections(event),
    oficinaIdsSeleccionados: directOfficeIds,
    oficinaIdsExcluidos: event.oficina_ids_excluidos ?? [],
    oficinasCount: event.evento_oficinas?.length ?? 0,
    cargosCount: selectedCargoCodes.length,
    asistieron: [],
    observaron: [],
    retrasados: [],
    noObligados: [],
    asistieronCount: resolvedCounts.attended,
    observaronCount: resolvedCounts.observed,
    retrasadosCount: 0,
    noObligadosCount: 0,
    personasListadasCount: resolvedCounts.total,
    detalleCompleto: false,
  };
}

function serializeEvent(event: any) {
  const requiredAttendances = (event.asistencias ?? []).filter(
    (item: any) => !isNonRequiredEventAttendance(item),
  );
  const nonRequired = (event.asistencias ?? [])
    .filter(isNonRequiredEventAttendance)
    .map(serializeAttendanceRecord);
  const attended = requiredAttendances
    .filter((item: any) => item.estado === estado_asistencia.ASISTIO)
    .map(serializeAttendanceRecord);
  const observed = requiredAttendances
    .filter((item: any) => item.estado === estado_asistencia.OBSERVADO)
    .map(serializeAttendanceRecord);
  const late = requiredAttendances
    .filter((item: any) =>
      (item.asistencia_controles ?? []).some(
        (control: any) => control.retrasado === true,
      ),
    )
    .map(serializeAttendanceRecord);

  return {
    ...buildSerializedEventBase(event),
    asistieron: attended,
    observaron: observed,
    retrasados: late,
    noObligados: nonRequired,
    asistieronCount: attended.length,
    observaronCount: observed.length,
    retrasadosCount: late.length,
    noObligadosCount: nonRequired.length,
    personasListadasCount: attended.length + observed.length,
    detalleCompleto: true,
  };
}

async function serializeEventWithAbsentees(event: any) {
  const serializedEvent = serializeEvent(event);
  const absentees = await loadEventAbsentees(event);

  return {
    ...serializedEvent,
    faltaron: absentees,
    faltaronCount: absentees.length,
    personasListadasCount:
      serializedEvent.asistieronCount +
      serializedEvent.observaronCount +
      absentees.length,
  };
}

async function loadEventAbsentees(event: any) {
  const registeredPersonIds = new Set<number>(
    (event.asistencias ?? [])
      .map((attendance: any) => attendance.persona_id)
      .filter((personId: unknown): personId is number => typeof personId === "number"),
  );
  const candidates = await prisma.personas.findMany({
    where: {
      activo: true,
      usuario_id: {
        not: null,
      },
      id: {
        notIn: [...registeredPersonIds],
      },
      usuario: {
        is: {
          activo: true,
          rol: rol_usuario.OPERADOR,
        },
      },
    },
    include: personIdentityInclude,
    orderBy: [{ nombre_completo: "asc" }, { id: "asc" }],
  });
  const absentees = [];

  for (const person of candidates) {
    if (isHiddenEventAbsenteePerson(person)) {
      continue;
    }

    const requirementReason = await buildEventReportRequirementReason(person, event);

    if (requirementReason != null) {
      absentees.push(serializeEventAbsenteeRecord(person, requirementReason));
    }
  }

  return absentees;
}

function isHiddenEventAbsenteePerson(person: any) {
  const linkedUser = person.usuario ?? null;
  const ci = normalizeCiLookupValue(linkedUser?.ci ?? person.ci ?? "");
  const numeroItem = normalizeOptionalText(linkedUser?.numero_item)?.trim();

  return (
    ci === HIDDEN_EVENT_ABSENTEE_CI &&
    numeroItem === HIDDEN_EVENT_ABSENTEE_ITEM
  );
}

function serializeEventAbsenteeRecord(person: any, requirementReason: string) {
  const linkedUser = person.usuario ?? null;
  const officeName = resolveLinkedOfficeName(linkedUser);

  return {
    personaId: person.id,
    nombreCompleto: buildResolvedPersonDisplayName(person),
    oficina: officeName,
    oficinaId: resolveLinkedOfficeId(linkedUser),
    oficinaCodigo: resolveLinkedOfficeCode(linkedUser),
    ci: linkedUser?.ci ?? person.ci ?? null,
    numeroItem: linkedUser?.numero_item ?? null,
    tipoVinculo: linkedUser?.tipo_vinculo ?? null,
    unidad: officeName,
    cargo: resolveEffectiveJobTitleName(linkedUser),
    email: linkedUser?.email ?? null,
    motivoFalta: requirementReason,
  };
}

async function buildEventReportRequirementReason(person: any, event: any) {
  const linkedUser = person.usuario ?? null;
  const userOfficeId =
    resolveLinkedOfficeId(linkedUser) ??
    (await resolveOfficeForUser(prisma, linkedUser))?.id ??
    null;
  const userJobTitles = resolveUserEventJobTitles(linkedUser);
  const eventCargoCodes = new Set<string>(
    (event.evento_cargos ?? []).map(
      (item: { cargo_codigo: string }) => item.cargo_codigo,
    ),
  );
  const eventCargoNames = new Set<string>(
    (event.evento_cargos ?? [])
      .map((item: { cargos?: { cargo?: string | null } }) =>
        normalizeLooseMatchText(item.cargos?.cargo),
      )
      .filter((name: string | null): name is string => name != null),
  );
  const officeCargoRows = (event.evento_oficina_cargos ?? []).filter(
    (item: { oficina_id: number }) => item.oficina_id === userOfficeId,
  );
  const officeCargoCodes = new Set<string>(
    officeCargoRows.map(
      (item: { cargo_codigo: string }) => item.cargo_codigo,
    ),
  );
  const officeCargoNames = new Set<string>(
    officeCargoRows
      .map((item: { cargos?: { cargo?: string | null } }) =>
        normalizeLooseMatchText(item.cargos?.cargo),
      )
      .filter((name: string | null): name is string => name != null),
  );
  const matchesOffice =
    userOfficeId != null &&
    (event.evento_oficinas ?? []).some(
      (item: { oficina_id: number }) => item.oficina_id === userOfficeId,
    );
  const matchesCargo =
    eventCargoCodes.size > 0 &&
    matchesCargoSelection(userJobTitles, eventCargoCodes, eventCargoNames);
  const matchesOfficeCargo =
    matchesOffice &&
    officeCargoRows.length > 0 &&
    matchesCargoSelection(
      userJobTitles,
      officeCargoCodes,
      officeCargoNames,
    );
  const officeAllowsAllJobTitles =
    matchesOffice && officeCargoRows.length === 0;

  if (matchesOfficeCargo) {
    return "Oficina y cargo";
  }

  if (matchesOffice && matchesCargo) {
    return "Oficina y cargo";
  }

  if (officeAllowsAllJobTitles) {
    return "Oficina";
  }

  if (matchesCargo) {
    return "Cargo";
  }

  return null;
}

function resolveLinkedOffice(linkedUser: any) {
  return linkedUser?.oficina_comision ?? linkedUser?.oficinas ?? null;
}

function resolveLinkedOfficeId(linkedUser: any) {
  const linkedOffice = resolveLinkedOffice(linkedUser);
  return linkedOffice?.id ??
    linkedUser?.oficina_comision_id ??
    linkedUser?.oficina_id ??
    null;
}

function resolveLinkedOfficeName(linkedUser: any) {
  const commissionOfficeName = resolveCommissionOfficeName(linkedUser);

  if (commissionOfficeName != null) {
    return `Comision: ${commissionOfficeName}`;
  }

  if (linkedUser?.oficina_comision_id != null) {
    return "Comision";
  }

  const linkedOffice = resolveLinkedOffice(linkedUser);

  return (
    normalizeOptionalText(linkedOffice?.oficina) ??
    normalizeOptionalText(linkedUser?.unidad) ??
    null
  );
}

function resolveLinkedOfficeCode(linkedUser: any) {
  const linkedOffice = resolveLinkedOffice(linkedUser);
  return normalizeOptionalText(linkedOffice?.cod) ?? null;
}

function resolvePrimaryOfficeName(linkedUser: any) {
  return (
    normalizeOptionalText(linkedUser?.oficinas?.oficina) ??
    normalizeOptionalText(linkedUser?.unidad) ??
    null
  );
}

function resolveCommissionOfficeName(linkedUser: any) {
  return normalizeOptionalText(linkedUser?.oficina_comision?.oficina) ?? null;
}

function resolveEffectiveJobTitleCode(user: any) {
  const subcargoCode = normalizeOptionalText(user?.subcargo_codigo);

  if (subcargoCode != null) {
    return subcargoCode;
  }

  if (normalizeOptionalText(user?.subcargo) != null) {
    return null;
  }

  return normalizeOptionalText(user?.cargo_codigo) ?? null;
}

function resolveEffectiveJobTitleName(user: any) {
  return (
    normalizeOptionalText(user?.subcargo) ??
    normalizeOptionalText(user?.cargo) ??
    null
  );
}

type SubmitFuncionarioRatingInput = {
  calificacion: "feliz" | "neutral" | "enojada";
  comentario: string | null;
  calificadorNombre: string | null;
  calificadorCelular: string | null;
  deviceId: string;
  deviceLabel: string | null;
};

function parseGenerateFuncionarioRatingQrInput(payload: unknown) {
  const body = expectRecord(payload);

  return {
    funcionarioId: readRequiredInt(body, "funcionarioId"),
  };
}

function parseSubmitFuncionarioRatingInput(
  payload: unknown,
): SubmitFuncionarioRatingInput {
  const body = expectRecord(payload);
  const calificacion = readRequiredString(body, "calificacion", 5, 20)
    .toLowerCase();

  if (
    calificacion !== "feliz" &&
    calificacion !== "neutral" &&
    calificacion !== "enojada"
  ) {
    throw new HttpError(400, "La calificacion enviada no es valida.");
  }

  return {
    calificacion,
    comentario: readOptionalString(body, "comentario", 0, 500),
    calificadorNombre: readOptionalString(body, "calificadorNombre", 0, 120),
    calificadorCelular: readOptionalString(body, "calificadorCelular", 0, 30),
    deviceId: readRequiredString(body, "deviceId", 8, 200),
    deviceLabel: readOptionalString(body, "deviceLabel", 0, 255),
  };
}

function buildFuncionarioRatingToken(funcionarioId: number) {
  const payload = Buffer.from(
    JSON.stringify({
      v: CALIFICACION_QR_VERSION,
      funcionarioId,
    }),
  ).toString("base64url");
  const signature = createHmac("sha256", CALIFICACION_QR_SECRET)
    .update(payload)
    .digest("base64url")
    .slice(0, 32);

  return `${payload}.${signature}`;
}

function readFuncionarioIdFromRatingToken(token: string) {
  const normalizedToken = token.trim();
  const [payload, signature, extra] = normalizedToken.split(".");

  if (!payload || !signature || extra != null) {
    throw new HttpError(400, "El QR de calificacion no es valido.");
  }

  const expectedSignature = createHmac("sha256", CALIFICACION_QR_SECRET)
    .update(payload)
    .digest("base64url")
    .slice(0, 32);

  if (!constantTimeEqualText(signature, expectedSignature)) {
    throw new HttpError(400, "El QR de calificacion no es valido.");
  }

  let decodedPayload: unknown;

  try {
    decodedPayload = JSON.parse(Buffer.from(payload, "base64url").toString());
  } catch {
    throw new HttpError(400, "El QR de calificacion no es valido.");
  }

  const body = expectRecord(decodedPayload);

  if (body.v !== CALIFICACION_QR_VERSION) {
    throw new HttpError(400, "El QR de calificacion no es valido.");
  }

  return readRequiredInt(body, "funcionarioId");
}

function buildFuncionarioRatingUrl(token: string) {
  return `${PUBLIC_RATING_BASE_URL}/${encodeURIComponent(token)}`;
}

async function resolveRatingTokenFuncionario(token: string) {
  const funcionarioId = readFuncionarioIdFromRatingToken(token);
  const activeQr = await pool.query(
    `
      SELECT "id"
      FROM "calificacion_funcionario_qrs"
      WHERE "funcionario_id" = $1
        AND "token_hash" = $2
        AND "activo" = TRUE
      LIMIT 1
    `,
    [funcionarioId, sha256Hex(token)],
  );

  if (activeQr.rowCount === 0) {
    throw new HttpError(404, "El QR de calificacion no esta activo.");
  }

  const funcionario = await prisma.usuarios.findUnique({
    where: { id: funcionarioId },
    include: userWithOfficeInclude,
  });

  if (!funcionario || funcionario.activo !== true) {
    throw new HttpError(404, "No se encontro el funcionario a calificar.");
  }

  return funcionario;
}

async function activateFuncionarioRatingQr({
  funcionarioId,
  token,
  generatedById,
}: {
  funcionarioId: number;
  token: string;
  generatedById: number;
}) {
  await pool.query(
    `
      INSERT INTO "calificacion_funcionario_qrs" (
        "funcionario_id",
        "token_hash",
        "activo",
        "generado_por_id",
        "created_at",
        "updated_at"
      )
      VALUES ($1, $2, TRUE, $3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT ("funcionario_id")
      DO UPDATE SET
        "token_hash" = EXCLUDED."token_hash",
        "activo" = TRUE,
        "generado_por_id" = EXCLUDED."generado_por_id",
        "updated_at" = CURRENT_TIMESTAMP
    `,
    [funcionarioId, sha256Hex(token), generatedById],
  );
}

async function loadFuncionarioForRatingAdmin(funcionarioId: number, requester: any) {
  const funcionario = await prisma.usuarios.findUnique({
    where: { id: funcionarioId },
    include: userWithOfficeInclude,
  });

  if (!funcionario || funcionario.activo !== true) {
    throw new HttpError(404, "No se encontro el funcionario seleccionado.");
  }

  assertHealthAdminCanManageUser(requester, funcionario);
  return funcionario;
}

function serializeRatingFuncionario(user: any) {
  return {
    id: user.id,
    nombreCompleto: buildUserDisplayName(user),
    ci: user.ci ?? "",
    cargo: resolveEffectiveJobTitleName(user) ?? "",
    oficinaId: resolveLinkedOfficeId(user),
    oficina: resolveLinkedOfficeName(user) ?? user.unidad ?? "",
    fotoUrl: user.foto_url ?? "",
  };
}

async function normalizePublicPhotoSource(photoSource: string | null | undefined) {
  const normalized = normalizeOptionalText(photoSource);

  if (normalized == null) {
    return null;
  }

  if (/^data:image\/[a-z0-9.+-]+;base64,/i.test(normalized)) {
    return normalized;
  }

  if (/^https?:\/\//i.test(normalized)) {
    return await inlineRemotePublicPhoto(normalized) ?? normalized;
  }

  if (normalized.startsWith("/")) {
    return normalized;
  }

  return `data:image/jpeg;base64,${normalized}`;
}

async function inlineRemotePublicPhoto(url: string) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3000);

  try {
    const response = await fetch(url, { signal: controller.signal });

    if (!response.ok) {
      return null;
    }

    const contentType = response.headers.get("content-type") ?? "image/jpeg";

    if (!contentType.toLowerCase().startsWith("image/")) {
      return null;
    }

    const imageBytes = Buffer.from(await response.arrayBuffer());

    if (imageBytes.length === 0) {
      return null;
    }

    return `data:${contentType};base64,${imageBytes.toString("base64")}`;
  } catch (_) {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

async function buildPublicRatingPage(token: string, funcionario: any) {
  const funcionarioData = serializeRatingFuncionario(funcionario);
  const safeToken = escapeHtml(token);
  const safeName = escapeHtml(funcionarioData.nombreCompleto);
  const safeCargo = escapeHtml(funcionarioData.cargo);
  const safeOffice = escapeHtml(funcionarioData.oficina);
  const safeInitial = escapeHtml(
    funcionarioData.nombreCompleto.trim().slice(0, 1).toUpperCase() || "F",
  );
  const safePhoto = await normalizePublicPhotoSource(funcionarioData.fotoUrl);
  const photoMarkup = safePhoto == null
    ? `<div class="person-photo fallback">${safeInitial}</div>`
    : `<img class="person-photo" src="${escapeHtml(safePhoto)}" alt="${safeName}">`;
  const logoMarkup = PUBLIC_RATING_LOGO_SRC == null
    ? ``
    : `<img class="brand-logo" src="${PUBLIC_RATING_LOGO_SRC}" alt="Innova Funcionario">`;

  return `<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex,nofollow">
  <title>Calificar atenci&oacute;n</title>
  <style>
    @import url("https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700;800&display=swap");
    * { box-sizing: border-box; }
    :root {
      --night: #6d56a0;
      --night-deep: #54407e;
      --accent: #7d67b1;
      --surface: #ffffff;
      --surface-soft: #fbfaff;
      --line: #e7e7ec;
      --ink: #4a396f;
      --muted: #7c6e9e;
      --danger: #d94841;
      --success: #16a34a;
    }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: "Poppins", Arial, Helvetica, sans-serif;
      background:
        linear-gradient(180deg, rgba(109, 86, 160, 0.08), rgba(255, 255, 255, 0) 42%),
        var(--surface);
      color: var(--ink);
      display: grid;
      place-items: center;
      padding: 24px 16px;
    }
    main {
      width: min(100%, 560px);
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 30px;
      box-shadow: 0 24px 70px rgba(84, 64, 126, 0.14);
      overflow: hidden;
    }
    .content {
      padding: clamp(22px, 6vw, 34px);
    }
    h1 {
      margin: 0 0 10px;
      color: var(--ink);
      font-size: clamp(30px, 8vw, 42px);
      line-height: 1.08;
      font-weight: 800;
      letter-spacing: 0;
      text-align: center;
    }
    .brand {
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 96px;
      padding: 20px 24px;
      background: linear-gradient(135deg, var(--night-deep), var(--night));
      border-bottom: 1px solid rgba(255, 255, 255, .18);
    }
    .brand-logo {
      display: block;
      width: min(72%, 280px);
      max-height: 62px;
      object-fit: contain;
    }
    .brand-fallback {
      color: #fff;
      font-size: 22px;
      font-weight: 800;
      text-align: center;
    }
    .person {
      text-align: center;
      margin-bottom: 26px;
      line-height: 1.4;
    }
    .person-photo {
      width: 190px;
      height: 190px;
      display: grid;
      place-items: center;
      margin: 0 auto 18px;
      border-radius: 34px;
      object-fit: cover;
      border: 4px solid #fff;
      box-shadow: 0 18px 42px rgba(84, 64, 126, .18);
      background: var(--surface-soft);
    }
    .person-photo.fallback {
      color: var(--night-deep);
      background: rgba(109, 86, 160, .12);
      font-size: 52px;
      font-weight: 800;
    }
    .person strong {
      display: block;
      color: var(--ink);
      font-size: clamp(20px, 5vw, 28px);
      font-weight: 700;
    }
    .muted {
      color: var(--muted);
      font-size: clamp(15px, 4vw, 20px);
      font-weight: 500;
      text-transform: uppercase;
    }
    .ratings {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 12px;
    }
    button.rating {
      min-height: 122px;
      border: 1.5px solid var(--line);
      border-radius: 22px;
      background: var(--surface-soft);
      cursor: pointer;
      font-family: inherit;
      font-size: 15px;
      font-weight: 700;
      color: var(--ink);
      transition: border-color .16s ease, background .16s ease, color .16s ease, transform .16s ease, box-shadow .16s ease;
    }
    button.rating:hover {
      border-color: rgba(109, 86, 160, .42);
      transform: translateY(-1px);
    }
    button.rating span {
      display: block;
      font-size: 46px;
      line-height: 1;
      margin-bottom: 12px;
    }
    button.rating.selected {
      border-color: var(--night);
      background: rgba(109, 86, 160, .10);
      box-shadow: 0 14px 34px rgba(84, 64, 126, .14);
      color: var(--night-deep);
    }
    label {
      display: block;
      margin-top: 26px;
      color: var(--ink);
      font-size: 18px;
      font-weight: 700;
    }
    input,
    textarea {
      width: 100%;
      margin-top: 12px;
      border: 1.5px solid var(--line);
      border-radius: 18px;
      background: var(--surface);
      color: var(--ink);
      padding: 16px 18px;
      font: inherit;
      outline: none;
      transition: border-color .16s ease, box-shadow .16s ease;
    }
    input::placeholder,
    textarea::placeholder {
      color: var(--muted);
    }
    input {
      min-height: 56px;
    }
    textarea {
      min-height: 132px;
      resize: vertical;
    }
    input:focus,
    textarea:focus {
      border-color: var(--night);
      box-shadow: 0 0 0 4px rgba(109, 86, 160, .10);
    }
    .optional-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 12px;
      margin-top: 20px;
    }
    .optional-grid label {
      margin-top: 0;
    }
    .submit {
      width: 100%;
      margin-top: 26px;
      border: 0;
      border-radius: 18px;
      background: var(--night-deep);
      color: #fff;
      padding: 18px 20px;
      font-family: inherit;
      font-size: 16px;
      font-weight: 700;
      cursor: pointer;
      box-shadow: 0 16px 32px rgba(84, 64, 126, .22);
      transition: background .16s ease, transform .16s ease, box-shadow .16s ease;
    }
    .submit:hover {
      background: var(--night);
      transform: translateY(-1px);
    }
    .submit:disabled {
      opacity: .65;
      cursor: default;
      transform: none;
      box-shadow: none;
    }
    .message {
      margin-top: 16px;
      padding: 14px 16px;
      border-radius: 18px;
      display: none;
      text-align: center;
      font-weight: 700;
    }
    .message.ok {
      display: block;
      color: var(--success);
      background: #eaf8ef;
    }
    .message.error {
      display: block;
      color: var(--danger);
      background: #fff0f0;
    }
    .done {
      display: none;
      text-align: center;
      padding: 32px 4px;
    }
    .done.visible {
      display: block;
    }
    .done .icon {
      width: 74px;
      height: 74px;
      display: grid;
      place-items: center;
      margin: 0 auto 18px;
      border-radius: 24px;
      background: rgba(22, 163, 74, .10);
      color: var(--success);
      font-size: 42px;
      font-weight: 800;
    }
    .hidden {
      display: none;
    }
    @media (max-width: 430px) {
      body {
        align-items: center;
        padding: 20px 12px;
      }
      main {
        border-radius: 26px;
      }
      .ratings {
        gap: 10px;
      }
      button.rating {
        min-height: 112px;
        border-radius: 20px;
        font-size: 14px;
      }
      button.rating span {
        font-size: 36px;
      }
      .person-photo {
        width: 150px;
        height: 150px;
        border-radius: 30px;
      }
      .optional-grid {
        grid-template-columns: 1fr;
      }
    }
  </style>
</head>
<body>
  <main>
    <section id="form">
      <div class="brand">${logoMarkup}</div>
      <div class="content">
        <h1>Califica la atenci&oacute;n</h1>
        <div class="person">
          ${photoMarkup}
          <strong>${safeName}</strong>
          <div class="muted">${safeCargo}</div>
          <div class="muted">${safeOffice}</div>
        </div>
        <div class="ratings" role="group" aria-label="Calificaci&oacute;n">
          <button class="rating" type="button" data-rating="feliz"><span>&#128578;</span>Feliz</button>
          <button class="rating" type="button" data-rating="neutral"><span>&#128528;</span>Neutral</button>
          <button class="rating" type="button" data-rating="enojada"><span>&#128577;</span>Enojada</button>
        </div>
        <div class="optional-grid">
          <label for="calificadorNombre">Tu nombre opcional
            <input id="calificadorNombre" maxlength="120" autocomplete="name" placeholder="Nombre">
          </label>
          <label for="calificadorCelular">Tu celular opcional
            <input id="calificadorCelular" maxlength="30" inputmode="tel" autocomplete="tel" placeholder="Celular">
          </label>
        </div>
        <label for="comentario">Comentario opcional</label>
        <textarea id="comentario" maxlength="500" placeholder="Escribe un comentario si lo deseas"></textarea>
        <button id="send" class="submit" type="button">Enviar calificaci&oacute;n</button>
        <div id="message" class="message"></div>
      </div>
    </section>
    <section id="done" class="done" aria-live="polite">
      <div class="icon">&#10003;</div>
      <h1>Gracias</h1>
      <p>Tu calificaci&oacute;n fue registrada.</p>
    </section>
  </main>
  <script>
    const token = "${safeToken}";
    const buttons = Array.from(document.querySelectorAll("[data-rating]"));
    const sendButton = document.getElementById("send");
    const message = document.getElementById("message");
    let selectedRating = "";

    buttons.forEach((button) => {
      button.addEventListener("click", () => {
        selectedRating = button.dataset.rating || "";
        buttons.forEach((item) => item.classList.toggle("selected", item === button));
        showMessage("", "");
      });
    });

    sendButton.addEventListener("click", async () => {
      if (!selectedRating) {
        showMessage("Selecciona una calificaci\u00f3n.", "error");
        return;
      }

      sendButton.disabled = true;
      sendButton.textContent = "Enviando...";

      try {
        const response = await fetch("/api/calificaciones/publica/" + encodeURIComponent(token), {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            calificacion: selectedRating,
            comentario: document.getElementById("comentario").value.trim(),
            calificadorNombre: document.getElementById("calificadorNombre").value.trim(),
            calificadorCelular: document.getElementById("calificadorCelular").value.trim(),
            deviceId: readOrCreateDeviceId(),
            deviceLabel: navigator.userAgent || "Navegador"
          })
        });
        const payload = await response.json().catch(() => ({}));

        if (!response.ok) {
          throw new Error(payload.error || "No fue posible enviar la calificaci\u00f3n.");
        }

        document.getElementById("form").classList.add("hidden");
        document.getElementById("done").classList.add("visible");
      } catch (error) {
        showMessage(error.message || "No fue posible enviar la calificaci\u00f3n.", "error");
      } finally {
        sendButton.disabled = false;
        sendButton.textContent = "Enviar calificaci\u00f3n";
      }
    });

    function showMessage(text, type) {
      message.textContent = text;
      message.className = type ? "message " + type : "message";
    }

    function readOrCreateDeviceId() {
      const key = "rating_device_id";
      const existing = localStorage.getItem(key);

      if (existing && existing.length >= 8) {
        return existing;
      }

      const bytes = new Uint8Array(16);
      crypto.getRandomValues(bytes);
      const value = Date.now() + "-" + Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
      localStorage.setItem(key, value);
      return value;
    }
  </script>
</body>
</html>`;
}

function escapeHtml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

async function submitFuncionarioRating({
  funcionario,
  input,
  request,
}: {
  funcionario: any;
  input: SubmitFuncionarioRatingInput;
  request: IncomingMessage;
}) {
  const fecha = getAppDateOnlyText();
  const deviceHash = sha256Hex(input.deviceId);
  const ipHash = sha256Hex(readClientIp(request));
  const funcionarioOficinaId = resolveLinkedOfficeId(funcionario);
  const funcionarioOficina = resolveLinkedOfficeName(funcionario) ??
    funcionario.unidad ??
    null;

  try {
    const result = await pool.query(
      `
        INSERT INTO "calificaciones_funcionario" (
          "funcionario_id",
          "fecha",
          "calificacion",
          "comentario",
          "calificador_nombre",
          "calificador_celular",
          "device_id_hash",
          "device_label",
          "user_agent",
          "ip_hash",
          "funcionario_nombre_completo",
          "funcionario_ci",
          "funcionario_cargo",
          "funcionario_oficina_id",
          "funcionario_oficina"
        )
        VALUES ($1, $2::date, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
        RETURNING "id", "fecha", "calificacion", "created_at"
      `,
      [
        funcionario.id,
        fecha,
        input.calificacion,
        input.comentario,
        input.calificadorNombre,
        input.calificadorCelular,
        deviceHash,
        input.deviceLabel,
        readSingleHeader(request.headers["user-agent"]) ?? null,
        ipHash,
        buildUserDisplayName(funcionario),
        funcionario.ci ?? null,
        resolveEffectiveJobTitleName(funcionario),
        funcionarioOficinaId,
        funcionarioOficina,
      ],
    );

    return {
      registrado: true,
      calificacion: result.rows[0],
    };
  } catch (error: any) {
    if (error?.code === "23505") {
      throw new HttpError(
        409,
        "Este celular ya califico a este funcionario hoy.",
      );
    }

    throw error;
  }
}

async function loadFuncionarioRatingsSummary(
  requester: any,
  fechaInicio: string | null,
  fechaFin: string | null,
  cargoCodigo: string | null,
  oficinaId: number | null,
  search: string | null,
) {
  const hasDateFilter = fechaInicio != null || fechaFin != null;
  const start = fechaInicio == null
    ? null
    : readDateOnlyString(fechaInicio, "fechaInicio");
  const end = fechaFin == null ? start : readDateOnlyString(fechaFin, "fechaFin");

  if (start != null && end != null && start.getTime() > end.getTime()) {
    throw new HttpError(400, "La fecha inicio no puede ser mayor a la fecha fin.");
  }

  const params: unknown[] = [];
  const healthFilter = isHealthAdminUser(requester)
    ? `AND (
        principal.nivel = ${HEALTH_OFFICE_LEVEL}
        OR comision.nivel = ${HEALTH_OFFICE_LEVEL}
      )`
    : "";
  const filters: string[] = [];
  const joinFilters: string[] = [];

  if (hasDateFilter && fechaInicio != null && fechaFin != null) {
    params.push(fechaInicio, fechaFin);
    joinFilters.push(`AND c."fecha" BETWEEN $${params.length - 1}::date AND $${params.length}::date`);
  }

  if (cargoCodigo != null) {
    params.push(cargoCodigo);
    filters.push(
      `AND (u."cargo_codigo" = $${params.length} OR u."subcargo_codigo" = $${params.length})`,
    );
  }

  if (oficinaId != null) {
    params.push(oficinaId);
    filters.push(
      `AND COALESCE(u."oficina_comision_id", u."oficina_id") = $${params.length}`,
    );
  }

  if (search != null) {
    const normalizedSearch = search.trim();
    if (/^\d+$/.test(normalizedSearch)) {
      params.push(normalizedSearch);
      filters.push(`AND COALESCE(u."ci", '') = $${params.length}`);
    } else {
      params.push(`%${normalizedSearch}%`);
      filters.push(`AND u."nombre_completo" ILIKE $${params.length}`);
    }
  }

  const result = await pool.query(
    `
      SELECT
        u."id" AS "funcionarioId",
        u."nombre_completo" AS "nombreCompleto",
        COALESCE(u."ci", '') AS "ci",
        COALESCE(u."subcargo", u."cargo", '') AS "cargo",
        COALESCE(comision."oficina", principal."oficina", u."unidad", '') AS "oficina",
        COUNT(c."id")::int AS "total",
        COUNT(c."id") FILTER (WHERE c."calificacion" = 'feliz')::int AS "feliz",
        COUNT(c."id") FILTER (WHERE c."calificacion" = 'neutral')::int AS "neutral",
        COUNT(c."id") FILTER (WHERE c."calificacion" = 'enojada')::int AS "enojada",
        COALESCE(
          json_agg(
            json_build_object(
              'id', c."id",
              'calificacion', c."calificacion",
              'comentario', COALESCE(c."comentario", ''),
              'calificadorNombre', COALESCE(c."calificador_nombre", ''),
              'calificadorCelular', COALESCE(c."calificador_celular", ''),
              'createdAt', c."created_at"
            )
            ORDER BY c."created_at" DESC
          ) FILTER (WHERE c."id" IS NOT NULL),
          '[]'::json
        ) AS "comentarios"
      FROM "usuarios" u
      LEFT JOIN "oficinas" principal ON principal."id" = u."oficina_id"
      LEFT JOIN "oficinas" comision ON comision."id" = u."oficina_comision_id"
      INNER JOIN "calificacion_funcionario_qrs" q
        ON q."funcionario_id" = u."id"
        AND q."activo" = TRUE
      LEFT JOIN "calificaciones_funcionario" c
        ON c."funcionario_id" = u."id"
        ${joinFilters.join("\n")}
      WHERE u."activo" = TRUE
        AND u."email" <> '${SEED_ADMIN_EMAIL.replace(/'/g, "''")}'
        ${healthFilter}
        ${filters.join("\n")}
      GROUP BY
        u."id",
        u."nombre_completo",
        u."ci",
        u."subcargo",
        u."cargo",
        u."unidad",
        comision."oficina",
        principal."oficina"
      ORDER BY u."nombre_completo" ASC
    `,
    params,
  );

  return result.rows;
}

async function loadActiveFuncionarioRatingQrs(requester: any) {
  const healthFilter = isHealthAdminUser(requester)
    ? `AND (
        principal.nivel = ${HEALTH_OFFICE_LEVEL}
        OR comision.nivel = ${HEALTH_OFFICE_LEVEL}
      )`
    : "";
  const result = await pool.query(
    `
      SELECT
        u."id" AS "funcionarioId",
        u."nombre_completo" AS "nombreCompleto",
        COALESCE(u."ci", '') AS "ci",
        COALESCE(u."subcargo", u."cargo", '') AS "cargo",
        COALESCE(comision."oficina", principal."oficina", u."unidad", '') AS "oficina",
        q."updated_at" AS "updatedAt"
      FROM "calificacion_funcionario_qrs" q
      INNER JOIN "usuarios" u ON u."id" = q."funcionario_id"
      LEFT JOIN "oficinas" principal ON principal."id" = u."oficina_id"
      LEFT JOIN "oficinas" comision ON comision."id" = u."oficina_comision_id"
      WHERE q."activo" = TRUE
        AND u."activo" = TRUE
        AND u."email" <> '${SEED_ADMIN_EMAIL.replace(/'/g, "''")}'
        ${healthFilter}
      ORDER BY q."updated_at" DESC, u."nombre_completo" ASC
    `,
  );

  return result.rows.map((row) => {
    const token = buildFuncionarioRatingToken(row.funcionarioId);

    return {
      ...row,
      token,
      url: buildFuncionarioRatingUrl(token),
    };
  });
}

function getAppDateOnlyText(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: APP_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const year = parts.find((part) => part.type === "year")?.value;
  const month = parts.find((part) => part.type === "month")?.value;
  const day = parts.find((part) => part.type === "day")?.value;

  return `${year}-${month}-${day}`;
}

async function deactivateExpiredConsultantContracts() {
  const today = getAppDateOnlyText();
  const result = await pool.query(
    `
      UPDATE "usuarios"
      SET "activo" = FALSE,
          "updated_at" = CURRENT_TIMESTAMP
      WHERE "activo" = TRUE
        AND "tipo_vinculo" = ANY($1::text[])
        AND "contrato_fin" IS NOT NULL
        AND COALESCE("contrato_adenda", "contrato_fin") <= $2::date
      RETURNING "id"
    `,
    [Array.from(CONTRACT_LINK_TYPES), today],
  );

  if ((result.rowCount ?? 0) > 0) {
    await pool.query(
      `
        UPDATE "personas"
        SET "activo" = FALSE,
            "updated_at" = CURRENT_TIMESTAMP
        WHERE "usuario_id" = ANY($1::int[])
      `,
      [result.rows.map((row) => row.id)],
    );
    invalidateDashboardSummaryCache();
  }
}

function serializeAppUser(user: any, person?: any | null, authToken?: string) {
  // El frontend recibe dos piezas equivalentes:
  // 1. `qrCode` para mostrar el ID externo en texto.
  // 2. `qrPayload` para renderizar el QR firmado y permanente del perfil.
  const linkedPerson = person ?? user.persona ?? null;
  const qrCode = linkedPerson?.codigo_qr ?? buildUserQrCode(user);
  const officeName = resolveLinkedOfficeName(user);
  const primaryOfficeName = resolvePrimaryOfficeName(user);
  const commissionOfficeName = resolveCommissionOfficeName(user);

  return {
    id: user.id,
    email: user.email,
    rol: user.rol ?? rol_usuario.OPERADOR,
    nombreCompleto: user.nombres ?? user.nombre_completo,
    primerApellido: user.primer_apellido ?? "",
    segundoApellido: user.segundo_apellido ?? "",
    tercerApellido: user.tercer_apellido ?? "",
    nombreVisible: buildUserDisplayName(user),
    ci: user.ci ?? "",
    celular: user.celular ?? "",
    tipoVinculo: user.tipo_vinculo ?? "ITEM",
    contratoNumero: user.contrato_numero ?? "",
    contratoInicio: user.contrato_inicio == null
      ? null
      : toDateOnlyText(user.contrato_inicio),
    contratoFin: user.contrato_fin == null ? null : toDateOnlyText(user.contrato_fin),
    contratoAdenda: user.contrato_adenda == null
      ? null
      : toDateOnlyText(user.contrato_adenda),
    unidad: officeName ?? user.unidad ?? "",
    oficinaId: resolveLinkedOfficeId(user),
    oficinaNombre: officeName,
    oficinaCodigo: resolveLinkedOfficeCode(user),
    oficinaPrincipalId: user.oficina_id ?? user.oficinas?.id ?? null,
    oficinaPrincipalNombre: primaryOfficeName,
    oficinaComisionId: user.oficina_comision_id ?? user.oficina_comision?.id ?? null,
    oficinaComisionNombre: commissionOfficeName,
    tieneComision: commissionOfficeName != null || user.oficina_comision_id != null,
    cargoCodigo: user.cargo_codigo ?? null,
    cargo: user.cargo ?? "",
    subcargoCodigo: user.subcargo_codigo ?? null,
    subcargo: user.subcargo ?? "",
    cargoEfectivoCodigo: resolveEffectiveJobTitleCode(user),
    cargoEfectivo: resolveEffectiveJobTitleName(user) ?? "",
    lugar: user.lugar ?? "",
    numeroItem: user.numero_item ?? "",
    activo: user.activo,
    fotoUrl: user.foto_url,
    qrCode,
    qrPayload: buildUserQrPayload(user, qrCode),
    personaId: linkedPerson?.id ?? null,
    authToken,
  };
}

function serializeExitPermit(salida: any) {
  const salidaRegistrador = salida.registrador_salida ?? null;
  const llegadaRegistrador = salida.registrador_llegada ?? null;

  return {
    id: salida.id,
    usuarioId: salida.usuario_id,
    motivo: salida.motivo,
    estado: salida.estado ?? estado_salida.PENDIENTE,
    lugarDestino: salida.lugar_destino,
    descripcion: salida.descripcion ?? "",
    fechaPermiso: toDateOnlyText(salida.fecha_permiso),
    horaInicio: salida.hora_inicio ?? "",
    horaFinal: salida.hora_final ?? "",
    horaLlegada: salida.hora_llegada ?? "",
    salidaEn: salida.salida_en?.toISOString() ?? null,
    llegadaEn: salida.llegada_en?.toISOString() ?? null,
    registradoSalidaPorId: salida.registrado_salida_por_id ?? null,
    registradoSalidaPorNombre:
      salidaRegistrador == null ? "" : buildUserDisplayName(salidaRegistrador),
    registradoLlegadaPorId: salida.registrado_llegada_por_id ?? null,
    registradoLlegadaPorNombre:
      llegadaRegistrador == null ? "" : buildUserDisplayName(llegadaRegistrador),
    solicitanteNombreCompleto: salida.solicitante_nombre_completo,
    solicitanteCi: salida.usuarios?.ci ?? "",
    solicitanteNumeroItem: salida.solicitante_numero_item ?? "",
    solicitanteCargo: salida.solicitante_cargo ?? "",
    solicitanteOficinaId: salida.solicitante_oficina_id ?? null,
    solicitanteOficina: salida.solicitante_oficina ?? "",
    aprobadoPorId: salida.aprobado_por_id ?? null,
    aprobadoPorNombre: salida.aprobado_por_nombre ?? "",
    aprobadoEn: salida.aprobado_en?.toISOString() ?? null,
    createdAt: salida.created_at.toISOString(),
    updatedAt: salida.updated_at.toISOString(),
  };
}

type CreateSwornDeclarationInput = {
  gestion: number;
  payload: JsonRecord;
};

type ReviewSwornDeclarationInput = {
  estado: "APROBADO" | "RECHAZADO";
  observacion: string | null;
};

async function listSwornDeclarations(input: {
  userId: number;
  onlyMine: boolean;
  query: string | null;
}) {
  const conditions: string[] = [];
  const values: unknown[] = [];

  if (input.onlyMine) {
    values.push(input.userId);
    conditions.push(`"usuario_id" = $${values.length}`);
  }

  if (!input.onlyMine && input.query != null) {
    values.push(`%${input.query}%`);
    const parameter = `$${values.length}`;
    conditions.push(
      `(
        "funcionario_nombre_completo" ILIKE ${parameter}
        OR COALESCE("funcionario_ci", '') ILIKE ${parameter}
        OR COALESCE("funcionario_numero_item", '') ILIKE ${parameter}
        OR COALESCE("funcionario_oficina", '') ILIKE ${parameter}
      )`,
    );
  }

  const whereClause =
    conditions.length === 0 ? "" : `WHERE ${conditions.join(" AND ")}`;
  const result = await pool.query(
    `
      SELECT *
      FROM "declaraciones_juradas"
      ${whereClause}
      ORDER BY "created_at" DESC, "id" DESC
      LIMIT 500
    `,
    values,
  );

  return result.rows;
}

function parseCreateSwornDeclarationInput(
  payload: unknown,
): CreateSwornDeclarationInput {
  const body = expectRecord(payload);
  const now = new Date();
  const gestion = readOptionalIntInRange(body, "gestion", 2000, now.getFullYear() + 1)
    ?? now.getFullYear();
  const declarationPayload = readSwornDeclarationPayload(body);

  validateSwornDeclarationPayload(declarationPayload);

  return {
    gestion,
    payload: declarationPayload,
  };
}

function parseReviewSwornDeclarationInput(
  payload: unknown,
): ReviewSwornDeclarationInput {
  const body = expectRecord(payload);
  const rawEstado = readRequiredString(body, "estado", 7, 9).toUpperCase();

  if (rawEstado !== "APROBADO" && rawEstado !== "RECHAZADO") {
    throw new HttpError(400, "El estado de revision no es valido.");
  }

  return {
    estado: rawEstado,
    observacion: readOptionalString(body, "observacion", 1, 1000),
  };
}

function readSwornDeclarationPayload(source: JsonRecord): JsonRecord {
  const value = source["payload"];

  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, "La declaracion jurada no tiene un formato valido.");
  }

  return value as JsonRecord;
}

function validateSwornDeclarationPayload(payload: JsonRecord) {
  const relatives = readJsonArray(payload, "consanguinidadAfinidad");
  const doublePerception = readJsonRecord(payload, "doblePercepcion");
  const sentences = readJsonRecord(payload, "sentenciasProcesos");
  const incompatibilities = readJsonRecord(payload, "otrasIncompatibilidades");
  const address = readJsonRecord(payload, "datosDomiciliarios");
  const cityHallRelatives = readJsonRecord(payload, "familiaresAlcaldia");

  if (relatives.length === 0) {
    throw new HttpError(
      400,
      "Debes registrar al menos un familiar en consanguinidad y afinidad.",
    );
  }

  for (const relative of relatives) {
    const record = expectRecord(relative);
    readRequiredString(record, "parentesco", 2, 80);
    readRequiredString(record, "nombres", 2, 150);
    readRequiredString(record, "documentoIdentidad", 2, 40);
  }

  const perceivesDoubleIncome = readRequiredBoolean(
    doublePerception,
    "percibeDoblePercepcion",
  );

  if (perceivesDoubleIncome) {
    readRequiredString(doublePerception, "institucion", 2, 180);
    readRequiredString(doublePerception, "funcion", 2, 180);
    readRequiredString(doublePerception, "montoPercibe", 1, 40);
    readRequiredString(doublePerception, "remuneracionCargoActual", 1, 40);
    readRequiredString(doublePerception, "montoTotalRemuneracion", 1, 40);
  }

  validateConditionalDescription(
    sentences,
    "tieneSentencias",
    "detalleSentencias",
    "Debes describir las sentencias declaradas.",
  );
  validateConditionalDescription(
    sentences,
    "tieneProcesos",
    "detalleProcesos",
    "Debes describir el estado del proceso declarado.",
  );
  validateConditionalDescription(
    sentences,
    "fueDestituido",
    "detalleDestitucion",
    "Debes indicar el motivo y anio de destitucion.",
  );

  validateConditionalDescription(
    incompatibilities,
    "recibeRenta",
    "detalleRenta",
    "Debes detallar la suspension temporal del beneficio.",
  );
  validateConditionalDescription(
    incompatibilities,
    "representaEmpresas",
    "nombreEmpresa",
    "Debes indicar el nombre de la empresa.",
  );
  readRequiredBoolean(incompatibilities, "compromisoMatrimonio");

  readRequiredString(address, "calleAvenida", 2, 180);
  readRequiredString(address, "barrioZona", 2, 120);
  readRequiredString(address, "numeroDomicilio", 1, 40);
  readRequiredString(address, "tipoVivienda", 2, 80);
  readRequiredString(address, "telefonoCelular", 5, 40);
  readRequiredString(address, "telefonoReferencia", 5, 40);
  readRequiredFloat(address, "latitud", -90, 90);
  readRequiredFloat(address, "longitud", -180, 180);

  const hasCityHallRelatives = readRequiredBoolean(
    cityHallRelatives,
    "tieneFamiliares",
  );
  const cityHallRelativeRows = readJsonArray(cityHallRelatives, "familiares");

  if (hasCityHallRelatives && cityHallRelativeRows.length === 0) {
    throw new HttpError(
      400,
      "Debes registrar los datos de familiares que trabajan en la alcaldia.",
    );
  }

  for (const relative of cityHallRelativeRows) {
    const record = expectRecord(relative);
    readRequiredString(record, "parentesco", 2, 80);
    readRequiredString(record, "nombreCompleto", 2, 180);
    readRequiredString(record, "cargo", 2, 150);
    readRequiredString(record, "unidad", 2, 180);
  }
}

function readJsonRecord(source: JsonRecord, key: string): JsonRecord {
  const value = source[key];

  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, `La seccion ${key} es obligatoria.`);
  }

  return value as JsonRecord;
}

function readJsonArray(source: JsonRecord, key: string): unknown[] {
  const value = source[key];

  if (!Array.isArray(value)) {
    throw new HttpError(400, `La seccion ${key} no tiene un formato valido.`);
  }

  return value;
}

function validateConditionalDescription(
  source: JsonRecord,
  conditionKey: string,
  descriptionKey: string,
  message: string,
) {
  const enabled = readRequiredBoolean(source, conditionKey);
  const description = readRequiredString(source, descriptionKey, 2, 1000);

  if (enabled && description.toUpperCase() === "NO APLICA") {
    throw new HttpError(400, message);
  }
}

function serializeSwornDeclaration(record: any) {
  return {
    id: record.id,
    usuarioId: record.usuario_id,
    gestion: record.gestion,
    estado: record.estado,
    funcionarioNombreCompleto: record.funcionario_nombre_completo,
    funcionarioCi: record.funcionario_ci ?? "",
    funcionarioNumeroItem: record.funcionario_numero_item ?? "",
    funcionarioCargo: record.funcionario_cargo ?? "",
    funcionarioOficinaId: record.funcionario_oficina_id ?? null,
    funcionarioOficina: record.funcionario_oficina ?? "",
    payload: record.payload ?? {},
    observacionRevision: record.observacion_revision ?? "",
    revisadoPorId: record.revisado_por_id ?? null,
    revisadoPorNombre: record.revisado_por_nombre ?? "",
    revisadoEn: record.revisado_en?.toISOString() ?? null,
    createdAt: record.created_at.toISOString(),
    updatedAt: record.updated_at.toISOString(),
  };
}

async function loadSwornDeclarationForPdf(
  declarationId: number,
  authenticatedUser: AuthenticatedUser,
) {
  if (!Number.isInteger(declarationId) || declarationId <= 0) {
    throw new HttpError(400, "Debes enviar una declaracion valida.");
  }

  const conditions = [`"id" = $1`];
  const values: unknown[] = [declarationId];

  if (!isAdminUser(authenticatedUser)) {
    values.push(authenticatedUser.id);
    conditions.push(`"usuario_id" = $${values.length}`);
  }

  const result = await pool.query(
    `
      SELECT *
      FROM "declaraciones_juradas"
      WHERE ${conditions.join(" AND ")}
      LIMIT 1
    `,
    values,
  );

  if (result.rowCount === 0) {
    throw new HttpError(404, "No se encontro la declaracion jurada.");
  }

  return result.rows[0];
}

async function buildSwornDeclarationPdf(record: any) {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const boldFont = await pdf.embedFont(StandardFonts.HelveticaBold);
  const context: SwornDeclarationPdfContext = {
    pdf,
    font,
    boldFont,
    record,
    pageNumber: 0,
  };
  const payload = readSwornDeclarationPayloadRecord(record);
  const doublePerception = readPayloadRecord(payload.doblePercepcion);
  const sentences = readPayloadRecord(payload.sentenciasProcesos);
  const incompatibilities = readPayloadRecord(payload.otrasIncompatibilidades);
  const address = readPayloadRecord(payload.datosDomiciliarios);
  const cityHall = readPayloadRecord(payload.familiaresAlcaldia);
  const relatives = buildSwornDeclarationRelatives(record);
  const cityHallRelatives = Array.isArray(cityHall.familiares)
    ? cityHall.familiares.map((item: any) => readPayloadRecord(item))
    : [];

  let { page, y } = addSwornDeclarationPage(context);

  y = drawSwornSectionTitle(context, page, "Datos del funcionario", y);
  y = drawSwornInfoGrid(
    context,
    page,
    [
      ["Nombre completo", record.funcionario_nombre_completo],
      ["Cedula de identidad", record.funcionario_ci],
      ["Numero de item", record.funcionario_numero_item],
      ["Cargo", record.funcionario_cargo],
      ["Unidad / Oficina", record.funcionario_oficina],
      ["Gestion", String(record.gestion ?? "")],
      ["Fecha de registro", formatSwornDeclarationDate(record.created_at)],
      ["Codigo", buildSwornDeclarationCode(record)],
    ],
    y,
  );

  y = drawSwornSectionTitle(context, page, "Resumen de declaracion", y - 8);
  y = drawSwornChecklist(
    context,
    page,
    [
      [
        "Doble percepcion",
        doublePerception.percibeDoblePercepcion === true
          ? "Declara percibir doble percepcion"
          : "No declara doble percepcion",
      ],
      [
        "Sentencias ejecutoriadas",
        sentences.tieneSentencias === true ? "Si registra" : "No registra",
      ],
      [
        "Procesos administrativos o judiciales",
        sentences.tieneProcesos === true ? "Si registra" : "No registra",
      ],
      [
        "Destitucion previa",
        sentences.fueDestituido === true ? "Si registra" : "No registra",
      ],
      [
        "Renta o pension",
        incompatibilities.recibeRenta === true ? "Si registra" : "No registra",
      ],
      [
        "Compromiso de matrimonio",
        incompatibilities.compromisoMatrimonio === true ? "Declara compromiso" : "No declara",
      ],
      [
        "Representacion de empresas",
        incompatibilities.representaEmpresas === true ? "Si representa" : "No representa",
      ],
      [
        "Familiares en la Alcaldia",
        cityHall.tieneFamiliares === true ? "Si registra" : "No registra",
      ],
    ],
    y,
  );

  ({ page, y } = addSwornDeclarationPage(context));
  y = drawSwornSectionTitle(context, page, "Consanguinidad y afinidad", y);
  y = drawSwornParagraph(
    context,
    page,
    "Detalle de familiares declarados por el funcionario. Los campos sin informacion fueron dejados en blanco por el declarante.",
    y,
    10,
  );
  ({ page, y } = drawSwornRelativesTable(context, page, relatives, y - 6));

  ({ page, y } = addSwornDeclarationPage(context));
  y = drawSwornSectionTitle(context, page, "Doble percepcion", y);
  y = drawSwornInfoGrid(
    context,
    page,
    [
      ["Percibe doble percepcion", doublePerception.percibeDoblePercepcion === true ? "SI" : "NO"],
      ["Institucion", doublePerception.institucion],
      ["Funcion", doublePerception.funcion],
      ["Monto percibido", doublePerception.montoPercibe],
      ["Remuneracion cargo actual", doublePerception.remuneracionCargoActual],
      ["Monto total remuneracion", doublePerception.montoTotalRemuneracion],
    ],
    y,
  );

  y = drawSwornSectionTitle(context, page, "Sentencias y procesos", y - 8);
  y = drawSwornInfoGrid(
    context,
    page,
    [
      ["Tiene sentencias", sentences.tieneSentencias === true ? "SI" : "NO"],
      ["Detalle sentencias", sentences.detalleSentencias],
      ["Tiene procesos", sentences.tieneProcesos === true ? "SI" : "NO"],
      ["Detalle procesos", sentences.detalleProcesos],
      ["Fue destituido", sentences.fueDestituido === true ? "SI" : "NO"],
      ["Detalle destitucion", sentences.detalleDestitucion],
    ],
    y,
  );

  y = drawSwornSectionTitle(context, page, "Otras incompatibilidades", y - 8);
  y = drawSwornInfoGrid(
    context,
    page,
    [
      ["Recibe renta o pension", incompatibilities.recibeRenta === true ? "SI" : "NO"],
      ["Detalle renta", incompatibilities.detalleRenta],
      ["Compromiso matrimonio", incompatibilities.compromisoMatrimonio === true ? "SI" : "NO"],
      ["Representa empresas", incompatibilities.representaEmpresas === true ? "SI" : "NO"],
      ["Nombre de empresa", incompatibilities.nombreEmpresa],
    ],
    y,
  );

  ({ page, y } = addSwornDeclarationPage(context));
  y = drawSwornSectionTitle(context, page, "Datos domiciliarios", y);
  y = drawSwornInfoGrid(
    context,
    page,
    [
      ["Barrio / Zona", address.barrioZona],
      ["Calle / Avenida", address.calleAvenida],
      ["Numero de domicilio", address.numeroDomicilio],
      ["Tipo de vivienda", address.tipoVivienda],
      ["Edificio", address.edificio],
      ["Piso", address.piso],
      ["Departamento", address.departamento],
      ["Telefono celular", address.telefonoCelular],
      ["Telefono referencia", address.telefonoReferencia],
      ["Referencias", address.referencias],
    ],
    y,
  );

  const mapImage = await embedSwornDeclarationMapImage(pdf, address.mapaImagenPngBase64);
  if (mapImage != null) {
    y = drawSwornSectionTitle(context, page, "Ubicacion declarada", y - 8);
    const mapBoxWidth = 500;
    const mapBoxHeight = 210;
    const { width: mapWidth, height: mapHeight } = fitImageInsideBox(
      mapImage.width,
      mapImage.height,
      mapBoxWidth - 2,
      mapBoxHeight - 2,
    );
    const mapX = 48 + (mapBoxWidth - 2 - mapWidth) / 2;
    const mapY = y - mapBoxHeight - 7 + (mapBoxHeight - 2 - mapHeight) / 2;

    page.drawRectangle({
      x: 47,
      y: y - mapBoxHeight - 8,
      width: mapBoxWidth,
      height: mapBoxHeight,
      borderColor: swornPdfColors.line,
      borderWidth: 1,
    });
    page.drawImage(mapImage, {
      x: mapX,
      y: mapY,
      width: mapWidth,
      height: mapHeight,
    });
    y -= mapBoxHeight + 28;
  }

  if (cityHall.tieneFamiliares === true) {
    if (y < 260) {
      ({ page, y } = addSwornDeclarationPage(context));
    }
    y = drawSwornSectionTitle(context, page, "Familiares en la Alcaldia", y);
    ({ page, y } = drawSwornCityHallRelativesTable(context, page, cityHallRelatives, y));
  }

  if (y < 260) {
    ({ page, y } = addSwornDeclarationPage(context));
  }
  y = drawSwornSectionTitle(context, page, "Declaracion y firma", y - 4);
  y = drawSwornParagraph(
    context,
    page,
    "Declaro bajo juramento que la informacion consignada en el presente documento es veraz, completa y fidedigna. Tengo conocimiento de que la falsedad u omision de datos puede generar responsabilidad administrativa, civil y penal conforme a normativa vigente.",
    y,
    10.5,
  );
  drawSwornSignatureBlock(context, page, y - 46);

  pdf.setTitle(buildSwornDeclarationPdfFilename(record));
  pdf.setAuthor("Gobierno Autonomo Municipal de Cochabamba");
  pdf.setSubject("Declaracion jurada de incompatibilidades");
  pdf.setCreator("Innova Funcionario");
  pdf.setProducer("Innova Funcionario");

  return pdf.save();
}

type SwornDeclarationPdfContext = {
  pdf: any;
  font: any;
  boldFont: any;
  record: any;
  pageNumber: number;
};

const swornPdfSize = { width: 595.28, height: 841.89 };
const swornPdfMargin = 44;
const swornPdfColors = {
  black: rgb(0.08, 0.08, 0.1),
  ink: rgb(0.14, 0.15, 0.18),
  muted: rgb(0.36, 0.34, 0.42),
  line: rgb(0.72, 0.7, 0.68),
  soft: rgb(0.95, 0.95, 0.95),
  olive: rgb(0.55, 0.6, 0.46),
  taupe: rgb(0.7, 0.61, 0.52),
  taupeDark: rgb(0.46, 0.36, 0.27),
  paleLine: rgb(0.86, 0.84, 0.81),
  white: rgb(1, 1, 1),
};

function addSwornDeclarationPage(context: SwornDeclarationPdfContext) {
  context.pageNumber += 1;
  const page = context.pdf.addPage([swornPdfSize.width, swornPdfSize.height]);

  drawSwornPageFrame(context, page);

  return { page, y: swornPdfSize.height - 220 };
}

function drawSwornPageFrame(context: SwornDeclarationPdfContext, page: any) {
  const { font, boldFont, record, pageNumber } = context;
  const code = buildSwornDeclarationCode(record);

  page.drawRectangle({
    x: 0,
    y: swornPdfSize.height - 118,
    width: 370,
    height: 74,
    color: swornPdfColors.olive,
  });
  page.drawRectangle({
    x: swornPdfSize.width - 174,
    y: swornPdfSize.height - 118,
    width: 174,
    height: 118,
    color: swornPdfColors.taupe,
  });
  page.drawSvgPath(
    `M ${swornPdfSize.width - 206} ${swornPdfSize.height} L ${swornPdfSize.width - 174} ${swornPdfSize.height} L ${swornPdfSize.width - 64} ${swornPdfSize.height - 118} L ${swornPdfSize.width - 96} ${swornPdfSize.height - 118} Z`,
    { color: swornPdfColors.white },
  );
  page.drawSvgPath(
    `M ${swornPdfSize.width - 82} ${swornPdfSize.height - 118} L ${swornPdfSize.width} ${swornPdfSize.height - 118} L ${swornPdfSize.width} ${swornPdfSize.height - 36} Z`,
    { color: swornPdfColors.taupeDark },
  );
  page.drawLine({
    start: { x: swornPdfMargin, y: swornPdfSize.height - 85 },
    end: { x: 305, y: swornPdfSize.height - 85 },
    thickness: 1,
    color: swornPdfColors.white,
  });
  page.drawText("GOBIERNO AUTONOMO MUNICIPAL DE COCHABAMBA", {
    x: swornPdfMargin,
    y: swornPdfSize.height - 75,
    size: 9,
    font: boldFont,
    color: swornPdfColors.white,
  });
  page.drawText("Innova Funcionario", {
    x: swornPdfSize.width - 154,
    y: swornPdfSize.height - 94,
    size: 14,
    font: boldFont,
    color: swornPdfColors.white,
  });
  page.drawText("DECLARACION", {
    x: swornPdfMargin,
    y: swornPdfSize.height - 178,
    size: 28,
    font: boldFont,
    color: swornPdfColors.black,
  });
  page.drawText("JURADA", {
    x: swornPdfMargin,
    y: swornPdfSize.height - 208,
    size: 28,
    font: boldFont,
    color: swornPdfColors.black,
  });
  drawSwornBadge(page, code, swornPdfSize.width - 206, swornPdfSize.height - 196, 162, boldFont);

  page.drawLine({
    start: { x: swornPdfMargin, y: 54 },
    end: { x: swornPdfSize.width - swornPdfMargin, y: 54 },
    thickness: 0.5,
    color: swornPdfColors.line,
  });
  page.drawRectangle({
    x: 82,
    y: 0,
    width: swornPdfSize.width - 82,
    height: 34,
    color: swornPdfColors.olive,
  });
  page.drawSvgPath(
    `M 0 0 L 56 0 L 28 34 L 0 34 Z`,
    { color: swornPdfColors.taupe },
  );
  page.drawSvgPath(
    `M 58 0 L 76 0 L 48 34 L 30 34 Z`,
    { color: swornPdfColors.white },
  );
  page.drawText(`Pagina ${pageNumber}`, {
    x: swornPdfSize.width - swornPdfMargin - 52,
    y: 42,
    size: 8,
    font,
    color: swornPdfColors.muted,
  });
  page.drawText("Documento generado digitalmente", {
    x: swornPdfMargin,
    y: 42,
    size: 8,
    font,
    color: swornPdfColors.muted,
  });
}

function drawSwornBadge(
  page: any,
  text: string,
  x: number,
  y: number,
  width: number,
  font: any,
) {
  page.drawRectangle({
    x,
    y,
    width,
    height: 28,
    color: swornPdfColors.white,
    borderColor: swornPdfColors.line,
    borderWidth: 0.8,
  });
  page.drawText(fitPdfCellText(text, width - 18, 8.5), {
    x: x + 9,
    y: y + 10,
    size: 8.5,
    font,
    color: swornPdfColors.black,
  });
}

function drawSwornSectionTitle(
  context: SwornDeclarationPdfContext,
  page: any,
  title: string,
  y: number,
) {
  const titleWidth = Math.min(
    300,
    Math.max(150, context.boldFont.widthOfTextAtSize(title.toUpperCase(), 11) + 24),
  );
  page.drawRectangle({
    x: swornPdfMargin,
    y: y - 28,
    width: titleWidth,
    height: 28,
    color: swornPdfColors.taupe,
  });
  page.drawLine({
    start: { x: swornPdfMargin + titleWidth + 6, y: y - 14 },
    end: { x: swornPdfSize.width - swornPdfMargin, y: y - 14 },
    thickness: 0.7,
    color: swornPdfColors.line,
  });
  page.drawText(title.toUpperCase(), {
    x: swornPdfMargin + 12,
    y: y - 19,
    size: 11,
    font: context.boldFont,
    color: swornPdfColors.white,
  });

  return y - 42;
}

function drawSwornInfoGrid(
  context: SwornDeclarationPdfContext,
  page: any,
  rows: Array<[string, unknown]>,
  y: number,
) {
  const columnGap = 12;
  const cellWidth = (swornPdfSize.width - swornPdfMargin * 2 - columnGap) / 2;
  const cellHeight = 46;
  let cursorY = y;

  rows.forEach((row, index) => {
    const column = index % 2;
    const x = swornPdfMargin + column * (cellWidth + columnGap);

    if (column === 0 && index > 0) {
      cursorY -= cellHeight + 8;
    }

    drawSwornInfoCell(context, page, x, cursorY, cellWidth, cellHeight, row[0], row[1]);
  });

  return cursorY - cellHeight - 10;
}

function drawSwornInfoCell(
  context: SwornDeclarationPdfContext,
  page: any,
  x: number,
  y: number,
  width: number,
  height: number,
  label: string,
  value: unknown,
) {
  page.drawRectangle({
    x,
    y: y - height,
    width,
    height,
    color: swornPdfColors.soft,
    borderColor: swornPdfColors.line,
    borderWidth: 0.7,
  });
  page.drawText(label.toUpperCase(), {
    x: x + 10,
    y: y - 15,
    size: 7,
    font: context.boldFont,
    color: swornPdfColors.muted,
  });
  drawSwornWrappedText(
    page,
    normalizePdfValue(value) || "Sin dato",
    x + 10,
    y - 30,
    width - 20,
    9,
    context.font,
    swornPdfColors.ink,
    2,
  );
}

function drawSwornChecklist(
  context: SwornDeclarationPdfContext,
  page: any,
  rows: Array<[string, string]>,
  y: number,
) {
  let cursorY = y;

  rows.forEach(([label, value]) => {
    page.drawCircle({
      x: swornPdfMargin + 8,
      y: cursorY - 8,
      size: 4,
      color: swornPdfColors.black,
    });
    page.drawText(label, {
      x: swornPdfMargin + 20,
      y: cursorY - 12,
      size: 9,
      font: context.boldFont,
      color: swornPdfColors.black,
    });
    drawSwornWrappedText(
      page,
      value,
      swornPdfMargin + 190,
      cursorY - 12,
      330,
      9,
      context.font,
      swornPdfColors.muted,
      1,
    );
    cursorY -= 24;
  });

  return cursorY - 4;
}

function drawSwornParagraph(
  context: SwornDeclarationPdfContext,
  page: any,
  text: string,
  y: number,
  size: number,
) {
  return drawSwornWrappedText(
    page,
    text,
    swornPdfMargin,
    y,
    swornPdfSize.width - swornPdfMargin * 2,
    size,
    context.font,
    swornPdfColors.ink,
  ) - 12;
}

function drawSwornRelativesTable(
  context: SwornDeclarationPdfContext,
  page: any,
  rows: any[],
  y: number,
) {
  const columns = [
    ["Parentesco", 70],
    ["Nombre completo", 145],
    ["Ocupacion", 85],
    ["Lugar trabajo", 95],
    ["CI", 52],
    ["Fallecido", 60],
  ] as Array<[string, number]>;

  if (rows.length === 0) {
    y = drawSwornParagraph(context, page, "No se registraron familiares en esta seccion.", y, 10);
    return { page, y };
  }

  return drawSwornTable(
    context,
    page,
    columns,
    rows.map((row) => [
      row.relationship,
      row.fullName,
      row.occupation,
      row.workplace,
      row.document,
      row.deceased ?? "NO",
    ]),
    y,
  );
}

function drawSwornCityHallRelativesTable(
  context: SwornDeclarationPdfContext,
  page: any,
  rows: Array<Record<string, any>>,
  y: number,
) {
  const columns = [
    ["Parentesco", 90],
    ["Nombre completo", 180],
    ["Cargo", 112],
    ["Unidad", 125],
  ] as Array<[string, number]>;

  if (rows.length === 0) {
    y = drawSwornParagraph(context, page, "El funcionario marco que tiene familiares en la Alcaldia, pero no registro filas de detalle.", y, 10);
    return { page, y };
  }

  return drawSwornTable(
    context,
    page,
    columns,
    rows.map((row) => [
      row.parentesco,
      row.nombreCompleto,
      row.cargo,
      row.unidad,
    ]),
    y,
  );
}

function drawSwornTable(
  context: SwornDeclarationPdfContext,
  currentPage: any,
  columns: Array<[string, number]>,
  rows: unknown[][],
  startY: number,
) {
  let page = currentPage;
  let y = startY;
  const rowHeight = 34;
  const tableWidth = columns.reduce((sum, [, width]) => sum + width, 0);

  const drawHeader = () => {
    let x = swornPdfMargin;
    page.drawRectangle({
      x,
      y: y - 24,
      width: tableWidth,
      height: 24,
      color: swornPdfColors.taupe,
    });
    columns.forEach(([label, width]) => {
      page.drawText(label.toUpperCase(), {
        x: x + 6,
        y: y - 16,
        size: 7,
        font: context.boldFont,
        color: swornPdfColors.white,
      });
      x += width;
    });
    y -= 24;
  };

  drawHeader();

  rows.forEach((row, rowIndex) => {
    if (y < 96) {
      ({ page, y } = addSwornDeclarationPage(context));
      y = drawSwornSectionTitle(context, page, "Continuacion", y);
      drawHeader();
    }

    let x = swornPdfMargin;
    page.drawRectangle({
      x,
      y: y - rowHeight,
      width: tableWidth,
      height: rowHeight,
      color: swornPdfColors.white,
      borderColor: swornPdfColors.line,
      borderWidth: 0.4,
    });
    columns.forEach(([, width], columnIndex) => {
      drawSwornWrappedText(
        page,
        normalizePdfValue(row[columnIndex]) || "-",
        x + 6,
        y - 11,
        width - 10,
        7,
        context.font,
        swornPdfColors.ink,
        2,
      );
      x += width;
    });
    y -= rowHeight;
  });

  return { page, y: y - 14 };
}

function drawSwornSignatureBlock(
  context: SwornDeclarationPdfContext,
  page: any,
  y: number,
) {
  const lineWidth = 220;
  const gap = 70;
  const totalWidth = lineWidth * 2 + gap;
  const leftX = (swornPdfSize.width - totalWidth) / 2;
  const rightX = leftX + lineWidth + gap;

  drawSwornSignature(page, leftX, y, lineWidth, "FIRMA DEL DECLARANTE", context.boldFont);
  drawSwornSignature(page, rightX, y, lineWidth, "ACLARACION DE FIRMA", context.boldFont);
  page.drawText(`CI: ${normalizePdfValue(context.record.funcionario_ci) || "________________"}`, {
    x: leftX,
    y: y - 42,
    size: 9,
    font: context.font,
    color: swornPdfColors.black,
  });
}

function drawSwornSignature(
  page: any,
  x: number,
  y: number,
  width: number,
  label: string,
  font: any,
) {
  page.drawLine({
    start: { x, y },
    end: { x: x + width, y },
    thickness: 0.8,
    color: swornPdfColors.black,
  });
  const labelWidth = font.widthOfTextAtSize(label, 8);
  page.drawText(label.toUpperCase(), {
    x: x + (width - labelWidth) / 2,
    y: y - 18,
    size: 8,
    font,
    color: swornPdfColors.black,
  });
}

function drawSwornWrappedText(
  page: any,
  text: string,
  x: number,
  y: number,
  maxWidth: number,
  size: number,
  font: any,
  color: any,
  maxLines = Number.POSITIVE_INFINITY,
) {
  const lines = wrapSwornPdfText(text, font, size, maxWidth).slice(0, maxLines);
  const lineHeight = size + 3;
  let cursorY = y;

  lines.forEach((line) => {
    page.drawText(line, {
      x,
      y: cursorY,
      size,
      font,
      color,
    });
    cursorY -= lineHeight;
  });

  return cursorY;
}

function wrapSwornPdfText(
  text: string,
  font: any,
  size: number,
  maxWidth: number,
) {
  const cleanText = text
    .replace(/\r\n/g, "\n")
    .replace(/\s+/g, " ")
    .trim();

  if (cleanText.length === 0) {
    return [""];
  }

  const words = cleanText.split(" ");
  const lines: string[] = [];
  let line = "";

  words.forEach((word) => {
    const candidate = line.length === 0 ? word : `${line} ${word}`;

    if (font.widthOfTextAtSize(candidate, size) <= maxWidth) {
      line = candidate;
      return;
    }

    if (line.length > 0) {
      lines.push(line);
    }

    line = word;
  });

  if (line.length > 0) {
    lines.push(line);
  }

  return lines;
}

function fitImageInsideBox(
  imageWidth: number,
  imageHeight: number,
  boxWidth: number,
  boxHeight: number,
) {
  const scale = Math.min(boxWidth / imageWidth, boxHeight / imageHeight);

  return {
    width: imageWidth * scale,
    height: imageHeight * scale,
  };
}

function drawSwornDeclarationHeader(
  page: any,
  record: any,
  _pageNumber: number,
  _totalPages: number,
  font: any,
) {
  const dateText = formatSwornDeclarationDate(record.created_at);
  const code = buildSwornDeclarationCode(record);

  drawPdfText(page, 148, 126, dateText, { font, size: 8, maxWidth: 126 });
  drawPdfText(page, 334, 126, code, { font, size: 8, maxWidth: 122 });
}

function drawSwornDeclarationPageOne(page: any, record: any, font: any) {
  const relatives = buildSwornDeclarationRelatives(record);

  drawCellText(page, 91, 229, record.funcionario_nombre_completo, 216, font);
  drawCellText(page, 316, 229, record.funcionario_ci, 54, font);
  drawCellText(page, 386, 229, null, 84, font);
  drawCellText(page, 145, 252, null, 130, font);
  drawCellText(page, 319, 252, null, 80, font);
  drawCellText(page, 205, 275, record.funcionario_oficina, 325, font);
  drawCellText(page, 88, 297, record.funcionario_cargo, 112, font);
  drawCellText(page, 228, 297, record.funcionario_numero_item, 104, font);
  drawCellText(page, 386, 297, null, 132, font);
  drawRelativeRows(page, relatives, ["ESPOSO(A)"], [371], font);
  drawRelativeRows(page, relatives, ["UNION LIBRE"], [441], font);
  drawRelativeRows(page, relatives, ["DIVORCIADO(A)"], [510], font);
  drawRelativeRows(page, relatives, ["SEPARADO(A)"], [579], font);
  drawRelativeRows(page, relatives, ["PADRE O MADRE DE LOS HIJOS"], [649], font);
  drawRelativeRows(page, relatives, ["PADRES"], [719, 741], font);
}

function drawSwornDeclarationPageTwo(page: any, record: any, font: any) {
  const relatives = buildSwornDeclarationRelatives(record);

  drawRelativeRows(page, relatives, ["HERMANOS"], [194], font);
  drawRelativeRows(page, relatives, ["HIJOS"], [252], font);
  drawRelativeRows(page, relatives, ["TIOS"], [323, 344, 365, 386], font);
  drawRelativeRows(page, relatives, ["PRIMOS"], [470, 491], font);
  drawRelativeRows(page, relatives, ["SOBRINOS"], [555, 576], font);
  drawRelativeRows(page, relatives, ["SUEGROS"], [650], font);
  drawRelativeRows(page, relatives, ["YERNOS - NUERAS", "YERNOS", "NUERAS"], [719], font);
  drawRelativeRows(page, relatives, ["CUNADOS", "CUÑADOS"], [792], font);
}

function drawSwornDeclarationPageFour(page: any, record: any, font: any, boldFont: any) {
  const payload = readSwornDeclarationPayloadRecord(record);
  const doublePerception = readPayloadRecord(payload.doblePercepcion);
  const sentences = readPayloadRecord(payload.sentenciasProcesos);
  const perceives = doublePerception.percibeDoblePercepcion === true;
  const hasSentences = sentences.tieneSentencias === true;
  const hasProcesses = sentences.tieneProcesos === true;
  const wasDismissed = sentences.fueDestituido === true;

  drawCenteredPdfText(
    page,
    296,
    250,
    perceives ? "SI PERCIBO DOBLE PERCEPCION" : "NO PERCIBO DOBLE PERCEPCION",
    { font: boldFont, size: 7.2, width: 240 },
  );
  drawCellText(page, 303, 337, doublePerception.institucion, 130, font);
  drawCellText(page, 303, 360, doublePerception.funcion ?? "NINGUNA", 130, font);
  drawCellText(page, 303, 383, doublePerception.montoPercibe, 130, font);
  drawCenteredPdfText(page, 296, 480, hasSentences ? "SI" : "NO", {
    font: boldFont,
    size: 7.2,
    width: 160,
  });
  if (hasSentences) {
    drawCellText(page, 55, 493, sentences.detalleSentencias, 485, font, 5.8);
  }
  drawCenteredPdfText(page, 296, 528, hasProcesses ? "SI" : "NINGUNO", {
    font: boldFont,
    size: 7.2,
    width: 160,
  });
  if (hasProcesses) {
    drawCellText(page, 55, 541, sentences.detalleProcesos, 485, font, 5.8);
  }
  drawCenteredPdfText(page, 296, 574, wasDismissed ? "SI" : "NO", {
    font: boldFont,
    size: 7.2,
    width: 160,
  });
  if (wasDismissed) {
    drawCellText(page, 55, 587, sentences.detalleDestitucion, 485, font, 5.8);
  }
}

function drawSwornDeclarationPageFive(page: any, record: any, font: any, boldFont: any) {
  const payload = readSwornDeclarationPayloadRecord(record);
  const incompatibilities = readPayloadRecord(payload.otrasIncompatibilidades);
  const receivesPension = incompatibilities.recibeRenta === true;
  const marriageCommitment = incompatibilities.compromisoMatrimonio === true;
  const representsCompanies = incompatibilities.representaEmpresas === true;

  drawCenteredPdfText(page, 296, 224, receivesPension ? "SI" : "NO", {
    font: boldFont,
    size: 7.2,
    width: 160,
  });
  if (receivesPension) {
    drawCellText(page, 55, 237, incompatibilities.detalleRenta, 485, font, 5.8);
  }
  drawCenteredPdfText(page, 296, 294, marriageCommitment ? "SI" : "NO", {
    font: boldFont,
    size: 7.2,
    width: 160,
  });
  drawCenteredPdfText(page, 296, 364, representsCompanies ? "SI" : "NO", {
    font: boldFont,
    size: 7.2,
    width: 160,
  });
  if (representsCompanies) {
    drawCellText(page, 55, 377, incompatibilities.nombreEmpresa, 485, font, 5.8);
  }
}

async function drawSwornDeclarationPageSix(
  pdf: any,
  page: any,
  record: any,
  font: any,
  boldFont: any,
) {
  const payload = readSwornDeclarationPayloadRecord(record);
  const address = readPayloadRecord(payload.datosDomiciliarios);
  const mapImage = await embedSwornDeclarationMapImage(pdf, address.mapaImagenPngBase64);

  drawCellText(page, 170, 236, record.funcionario_nombre_completo, 360, font);
  drawCellText(page, 170, 259, record.funcionario_ci, 94, font);
  drawCellText(page, 316, 259, address.barrioZona, 210, font);
  drawCellText(page, 170, 282, address.calleAvenida, 176, font);
  drawCellText(page, 371, 282, address.numeroDomicilio, 46, font);
  drawCellText(page, 485, 282, address.tipoVivienda, 70, font);
  drawCellText(page, 130, 305, address.telefonoFijo ?? "S/N", 84, font);
  drawCellText(page, 285, 305, address.telefonoCelular, 122, font);
  drawCellText(page, 486, 305, address.telefonoReferencia, 82, font);

  if (mapImage != null) {
    page.drawImage(mapImage, {
      x: 45,
      y: topToPdfY(page, 573),
      width: 482,
      height: 217,
    });
  } else {
    drawCellText(page, 55, 420, "------------------------", 240, font, 7);
  }

  drawPdfText(
    page,
    55,
    606,
    "Tengo conocimiento que de existir falsedad en los datos consignados en el presente formulario, la misma constituye un delito tipificado en el parrafo II del articulo 345 Bis del Codigo Penal Boliviano, declaro que la informacion que detallo es fidedigna, caso contrario sere sujeto a responsabilidad penal y administrativa.",
    { font: boldFont, size: 5.7, maxWidth: 490 },
  );
  drawSignatureLine(page, 45, 732, "FIRMA", boldFont);
  drawSignatureLine(page, 357, 732, "ACLARACION DE FIRMA", boldFont);
}

function buildSwornDeclarationRelatives(record: any) {
  const payload = readSwornDeclarationPayloadRecord(record);
  const rows = Array.isArray(payload.consanguinidadAfinidad)
    ? payload.consanguinidadAfinidad
    : [];

  return rows.map((item: any) => {
    const row = readPayloadRecord(item);

    return {
      relationship: normalizeOptionalText(row.parentesco)?.toUpperCase() ?? "",
      fullName: [
        normalizeOptionalText(row.apellidoPaterno),
        normalizeOptionalText(row.apellidoMaterno),
        normalizeOptionalText(row.nombres),
      ].filter(Boolean).join(" "),
      occupation: normalizeOptionalText(row.ocupacion),
      workplace: normalizeOptionalText(row.lugarTrabajo),
      document: normalizeOptionalText(row.documentoIdentidad),
      deceased: row.fallecido === true ? "SI" : null,
    };
  });
}

function drawRelativeRows(
  page: any,
  rows: any[],
  relationships: string[],
  topYs: number[],
  font: any,
) {
  const allowed = new Set(relationships.map((value) => value.toUpperCase()));
  const matches = rows
    .filter((row) => allowed.has(row.relationship))
    .slice(0, topYs.length);

  for (let index = 0; index < topYs.length; index++) {
    const row = matches[index] ?? {};
    const topY = topYs[index];

    drawCellText(page, 52, topY, row.fullName, 142, font, 5.5);
    drawCellText(page, 201, topY, row.occupation, 140, font, 5.5);
    drawCellText(page, 352, topY, row.workplace, 95, font, 5.5);
    drawCellText(page, 456, topY, row.document, 35, font, 5.5);
    drawCellText(page, 502, topY, row.deceased, 35, font, 5.5);
  }
}

function drawCellText(
  page: any,
  x: number,
  topY: number,
  value: unknown,
  width: number,
  font: any,
  size = 8,
) {
  const effectiveSize = Math.max(size, 7.8);
  const text = fitPdfCellText(value, width - 10, effectiveSize);

  drawPdfText(page, x + 7, topY - 5, text, {
    font,
    size: effectiveSize,
    maxWidth: width - 10,
  });
}

function drawPdfText(
  page: any,
  x: number,
  topY: number,
  text: string,
  options: { font: any; size: number; maxWidth: number },
) {
  page.drawText(text, {
    x,
    y: topToPdfY(page, topY + options.size),
    size: options.size,
    font: options.font,
    maxWidth: options.maxWidth,
    lineHeight: options.size + 1,
  });
}

function drawCenteredPdfText(
  page: any,
  centerX: number,
  topY: number,
  text: string,
  options: { font: any; size: number; width: number },
) {
  const fitted = fitPdfCellText(text, options.width, options.size);
  const textWidth = options.font.widthOfTextAtSize(fitted, options.size);

  page.drawText(fitted, {
    x: centerX - textWidth / 2,
    y: topToPdfY(page, topY + options.size - 6),
    size: options.size,
    font: options.font,
  });
}

function drawSignatureLine(page: any, x: number, topY: number, label: string, font: any) {
  const y = topToPdfY(page, topY);

  page.drawLine({
    start: { x, y },
    end: { x: x + 160, y },
    thickness: 0.6,
  });
  drawCenteredPdfText(page, x + 80, topY + 10, label, {
    font,
    size: 7,
    width: 160,
  });
}

function fitPdfCellText(value: unknown, width: number, size: number) {
  const raw = normalizePdfValue(value);
  const maxChars = Math.max(4, Math.floor(width / (size * 0.58)));
  const text = raw.length === 0 ? "-".repeat(maxChars) : raw;

  if (text.length <= maxChars) {
    return text;
  }

  return text.slice(0, Math.max(1, maxChars - 1)).trimEnd();
}

function normalizePdfValue(value: unknown) {
  const text = normalizeOptionalText(value);

  if (text == null || text.toUpperCase() === "NO APLICA") {
    return "";
  }

  return text;
}

function topToPdfY(page: any, topY: number) {
  return page.getSize().height - topY;
}

function readSwornDeclarationPayloadRecord(record: any) {
  return readPayloadRecord(record.payload);
}

function readPayloadRecord(value: unknown): Record<string, any> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }

  return value as Record<string, any>;
}

async function embedSwornDeclarationMapImage(pdf: any, value: unknown) {
  const imageBase64 = normalizeOptionalText(value);

  if (imageBase64 == null) {
    return null;
  }

  try {
    return await pdf.embedPng(Buffer.from(imageBase64, "base64"));
  } catch (_) {
    return null;
  }
}

function buildSwornDeclarationCode(record: any) {
  return `DJ-${record.id}-${record.funcionario_ci ?? ""}`.replace(/\s+/g, "");
}

function buildSwornDeclarationPdfFilename(record: any) {
  const safeCi =
    normalizeOptionalText(record.funcionario_ci)
      ?.replace(/[^A-Za-z0-9_-]+/g, "_") ?? String(record.id);

  return `DJ-${record.id}-${safeCi}.pdf`;
}

function formatSwornDeclarationDate(value: unknown) {
  const date = value instanceof Date ? value : new Date(String(value));
  const months = [
    "ENERO",
    "FEBRERO",
    "MARZO",
    "ABRIL",
    "MAYO",
    "JUNIO",
    "JULIO",
    "AGOSTO",
    "SEPTIEMBRE",
    "OCTUBRE",
    "NOVIEMBRE",
    "DICIEMBRE",
  ];

  if (Number.isNaN(date.getTime())) {
    return "";
  }

  return `${String(date.getDate()).padStart(2, "0")} ${months[date.getMonth()]} DE ${date.getFullYear()}`;
}

function serializeLunchRecord(record: any) {
  const salidaRegistrador = record.registrador_salida ?? null;
  const retornoRegistrador = record.registrador_retorno ?? null;

  return {
    id: record.id,
    usuarioId: record.usuario_id,
    fecha: toDateOnlyText(record.fecha),
    horaSalida: record.hora_salida,
    salidaEn: record.salida_en.toISOString(),
    horaRetorno: record.hora_retorno ?? "",
    retornoEn: record.retorno_en?.toISOString() ?? null,
    estado: record.hora_retorno == null ? "ABIERTO" : "CERRADO",
    funcionarioNombreCompleto: record.funcionario_nombre_completo,
    funcionarioCi: record.funcionario_ci ?? "",
    funcionarioNumeroItem: record.funcionario_numero_item ?? "",
    funcionarioCargo: record.funcionario_cargo ?? "",
    funcionarioOficinaId: record.funcionario_oficina_id ?? null,
    funcionarioOficina: record.funcionario_oficina ?? "",
    registradoSalidaPorId: record.registrado_salida_por_id ?? null,
    registradoSalidaPorNombre:
      salidaRegistrador == null ? "" : buildUserDisplayName(salidaRegistrador),
    registradoRetornoPorId: record.registrado_retorno_por_id ?? null,
    registradoRetornoPorNombre:
      retornoRegistrador == null ? "" : buildUserDisplayName(retornoRegistrador),
    createdAt: record.created_at.toISOString(),
    updatedAt: record.updated_at.toISOString(),
  };
}

function isNonRequiredEventAttendance(attendance: any) {
  const snapshot = attendance?.datos_qr_snapshot;

  if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot)) {
    return false;
  }

  const eventRequirement = (snapshot as JsonRecord).eventRequirement;

  return (
    eventRequirement != null &&
    typeof eventRequirement === "object" &&
    !Array.isArray(eventRequirement) &&
    (eventRequirement as JsonRecord).obligatorio === false
  );
}

function readEventAttendanceRequirementReason(attendance: any) {
  const snapshot = attendance?.datos_qr_snapshot;

  if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot)) {
    return null;
  }

  const eventRequirement = (snapshot as JsonRecord).eventRequirement;

  if (
    eventRequirement == null ||
    typeof eventRequirement !== "object" ||
    Array.isArray(eventRequirement)
  ) {
    return null;
  }

  return normalizeOptionalText((eventRequirement as JsonRecord).motivo);
}

function serializeAttendanceRecord(attendance: any) {
  const linkedUser = attendance.personas.usuario ?? null;
  const officeName = resolveLinkedOfficeName(linkedUser);
  const serializedControls = (attendance.asistencia_controles ?? []).map(
    serializeAttendanceControlRecord,
  );
  const controlSummary = buildSerializedControlSummary(serializedControls);
  const lateRegisteredAt = serializedControls
    .filter((control: any) => control.retrasado === true)
    .map((control: any) => control.registradoEn as string)
    .sort()
    .at(-1) ?? null;
  const resolvedState = serializedControls.length > 0
    ? controlSummary.state
    : attendance.estado;
  const defaultNote =
    resolvedState === estado_asistencia.ASISTIO
      ? "Registro de asistencia confirmado."
      : "Registro marcado como observado.";

  return {
    id: attendance.id,
    personaId: attendance.persona_id,
    nombreCompleto:
      attendance.nombre_snapshot ?? buildResolvedPersonDisplayName(attendance.personas),
    estado: resolvedState,
    observacion: attendance.observacion ?? defaultNote,
    qrLeido: attendance.qr_leido,
    oficina: officeName,
    oficinaId: resolveLinkedOfficeId(linkedUser),
    oficinaCodigo: resolveLinkedOfficeCode(linkedUser),
    ci: linkedUser?.ci ?? attendance.personas.ci ?? null,
    numeroItem: linkedUser?.numero_item ?? null,
    tipoVinculo: linkedUser?.tipo_vinculo ?? null,
    unidad: officeName,
    cargo: resolveEffectiveJobTitleName(linkedUser),
    fotoUrl: linkedUser?.foto_url ?? null,
    email: linkedUser?.email ?? null,
    registradoEn: attendance.registrado_en.toISOString(),
    retrasado: lateRegisteredAt != null,
    retrasadoEn: lateRegisteredAt,
    controles: controlSummary.controls,
    controlesRegistrados: controlSummary.registeredCount,
    controlesAsistidos: controlSummary.attendedCount,
    controlesObservados: controlSummary.observedCount,
    controlesRetrasados: controlSummary.lateCount,
    obligatorio: !isNonRequiredEventAttendance(attendance),
    motivoRegistroEvento: readEventAttendanceRequirementReason(attendance),
    eventoId: attendance.evento_id,
    eventoNombre:
      "eventos" in attendance ? attendance.eventos.nombre : undefined,
  };
}

function serializeAttendanceReportRecord(attendance: any, person: any) {
  const linkedUser = person.usuario ?? null;
  const officeName = resolveLinkedOfficeName(linkedUser);
  const serializedControls = (attendance.asistencia_controles ?? []).map(
    serializeAttendanceControlRecord,
  );
  const controlSummary = buildSerializedControlSummary(serializedControls);
  const resolvedState = serializedControls.length > 0
    ? controlSummary.state
    : attendance.estado;

  return {
    id: attendance.id,
    personaId: person.id,
    ci: linkedUser?.ci ?? person.ci,
    nombreCompleto: buildResolvedPersonDisplayName(person),
    oficina: officeName,
    oficinaId: resolveLinkedOfficeId(linkedUser),
    oficinaCodigo: resolveLinkedOfficeCode(linkedUser),
    estado: resolvedState,
    observacion: attendance.observacion,
    eventoId: attendance.eventos.id,
    eventoNombre: attendance.eventos.nombre,
    eventoFecha: serializeLocalEventDate(attendance.eventos.fecha_evento),
    eventoDireccion: attendance.eventos.direccion ?? attendance.eventos.descripcion,
    registradoEn: attendance.registrado_en.toISOString(),
    controles: controlSummary.controls,
    controlesRegistrados: controlSummary.registeredCount,
    controlesAsistidos: controlSummary.attendedCount,
    controlesObservados: controlSummary.observedCount,
    controlesRetrasados: controlSummary.lateCount,
  };
}

function serializeReportPerson(source: {
  user: any | null;
  person: any | null;
}) {
  const linkedUser = source.user ?? source.person?.usuario ?? null;
  const linkedPerson = source.person ?? linkedUser?.persona ?? null;
  const officeName = resolveLinkedOfficeName(linkedUser);

  return {
    id: linkedUser?.id ?? linkedPerson?.id ?? 0,
    personaId: linkedPerson?.id ?? null,
    usuarioId: linkedUser?.id ?? null,
    ci: linkedUser?.ci ?? linkedPerson?.ci ?? "",
    nombreCompleto: linkedUser
      ? buildUserDisplayName(linkedUser)
      : linkedPerson?.nombre_completo ?? "",
    oficina: officeName,
    oficinaId: resolveLinkedOfficeId(linkedUser),
    oficinaCodigo: resolveLinkedOfficeCode(linkedUser),
    unidad: officeName,
    cargo: resolveEffectiveJobTitleName(linkedUser),
    tipoVinculo: linkedUser?.tipo_vinculo ?? null,
    numeroItem: linkedUser?.numero_item ?? null,
    email: linkedUser?.email ?? null,
    activo: linkedUser?.activo ?? linkedPerson?.activo ?? true,
    fotoUrl: linkedUser?.foto_url ?? null,
    codigoQr:
      linkedPerson?.codigo_qr ?? (linkedUser ? buildUserQrCode(linkedUser) : null),
  };
}

function serializeQrPersonDetail(
  person: any,
  options?: {
    eventAttendance?: ReturnType<typeof serializeEventAttendanceLookup> | null;
    eventPermission?: { permitido: boolean; mensaje: string | null } | null;
  },
) {
  const linkedUser = person.usuario ?? null;
  const officeName = resolveLinkedOfficeName(linkedUser);

  return {
    id: person.id,
    usuarioId: linkedUser?.id ?? null,
    codigoQr:
      person.codigo_qr ?? (linkedUser ? buildUserQrCode(linkedUser) : null),
    nombreCompleto: buildResolvedPersonDisplayName(person),
    descripcion: null,
    nombres:
      normalizeOptionalText(linkedUser?.nombres) ??
      normalizeOptionalText(person.nombre_completo),
    primerApellido: normalizeOptionalText(linkedUser?.primer_apellido),
    segundoApellido: normalizeOptionalText(linkedUser?.segundo_apellido),
    tercerApellido: normalizeOptionalText(linkedUser?.tercer_apellido),
    ci: linkedUser?.ci ?? person.ci ?? null,
    email: linkedUser?.email ?? null,
    unidad: officeName,
    oficinaId: resolveLinkedOfficeId(linkedUser),
    oficinaNombre: officeName,
    oficinaCodigo: resolveLinkedOfficeCode(linkedUser),
    cargoCodigo: resolveEffectiveJobTitleCode(linkedUser),
    cargo: resolveEffectiveJobTitleName(linkedUser),
    tipoVinculo: linkedUser?.tipo_vinculo ?? null,
    numeroItem: linkedUser?.numero_item ?? null,
    activo: linkedUser?.activo ?? person.activo,
    fotoUrl: linkedUser?.foto_url ?? null,
    updatedAt: (
      linkedUser?.updated_at ??
      person.updated_at ??
      person.created_at ??
      new Date()
    ).toISOString(),
    eventoRegistro: options?.eventAttendance ?? null,
    eventoPermiso: options?.eventPermission ?? null,
  };
}

async function resolvePersonEventPermission(person: any, eventId: number) {
  const event = await getEventAttendanceContext(eventId);

  if (!event) {
    throw new HttpError(404, "No se encontro el evento seleccionado.");
  }

  const requirement = await resolvePersonEventRequirement(person, event);

  return {
    permitido: true,
    obligatorio: requirement.obligatorio,
    mensaje: requirement.obligatorio
      ? null
      : "Este funcionario no esta obligado a este evento; se registrara como no obligado.",
  };
}

async function assertPersonCanAttendEvent(person: any, event: any) {
  const requirement = await resolvePersonEventRequirement(person, event);

  if (!requirement.obligatorio) {
    throw new HttpError(
      403,
      "Este usuario no esta permitido asistir a este evento.",
    );
  }
}

async function resolvePersonEventRequirement(
  person: any,
  event: any,
): Promise<EventAttendanceRequirement> {
  const linkedUser = person.usuario ?? null;
  const userOfficeId =
    resolveLinkedOfficeId(linkedUser) ??
    (await resolveOfficeForUser(prisma, linkedUser))?.id ??
    null;
  const allowedOfficeIds = new Set<number>(
    (event.evento_oficinas ?? []).map((item: { oficina_id: number }) => item.oficina_id),
  );
  const allowedOfficeCodes = new Set<string>(
    (event.evento_oficinas ?? [])
      .map((item: { oficinas?: { cod?: string | null } }) =>
        normalizeOfficeCode(item.oficinas?.cod ?? ""),
      )
      .filter((officeCode: string) => officeCode.length > 0),
  );
  const allowedOfficeNames = new Set<string>(
    (event.evento_oficinas ?? [])
      .map((item: { oficinas?: { oficina?: string | null } }) =>
        normalizeLooseMatchText(item.oficinas?.oficina),
      )
      .filter((officeName: string | null) => officeName != null),
  );
  const allowedCargoCodigos = new Set<string>(
    (event.evento_cargos ?? [])
      .map((item: { cargo_codigo: string }) => item.cargo_codigo)
      .filter((cargoCodigo: string | null) => cargoCodigo != null),
  );
  const allowedCargoNames = new Set<string>(
    (event.evento_cargos ?? [])
      .map((item: { cargos?: { cargo?: string | null } }) =>
        normalizeLooseMatchText(item.cargos?.cargo),
      )
      .filter((cargoName: string | null) => cargoName != null),
  );
  const userJobTitles = resolveUserEventJobTitles(linkedUser);
  const userOfficeCode = normalizeOfficeCode(resolveLinkedOfficeCode(linkedUser) ?? "");
  const userOfficeName = normalizeLooseMatchText(resolveLinkedOfficeName(linkedUser));
  const matchingOfficeIds = new Set<number>(
    (event.evento_oficinas ?? [])
      .filter((item: { oficina_id: number; oficinas?: { cod?: string | null; oficina?: string | null } }) => {
        const eventOfficeCode = normalizeOfficeCode(item.oficinas?.cod ?? "");
        const eventOfficeName = normalizeLooseMatchText(item.oficinas?.oficina);

        return (
          (userOfficeId != null && item.oficina_id === userOfficeId) ||
          (userOfficeCode.length > 0 && allowedOfficeCodes.has(userOfficeCode) && eventOfficeCode === userOfficeCode) ||
          (userOfficeName != null && allowedOfficeNames.has(userOfficeName) && eventOfficeName === userOfficeName)
        );
      })
      .map((item: { oficina_id: number }) => item.oficina_id),
  );
  const matchesOffice =
    (userOfficeId != null && allowedOfficeIds.has(userOfficeId)) ||
    (userOfficeCode.length > 0 && allowedOfficeCodes.has(userOfficeCode)) ||
    (userOfficeName != null && allowedOfficeNames.has(userOfficeName));
  const officeCargoRows = event.evento_oficina_cargos ?? [];
  const hasOfficeCargoRules = officeCargoRows.length > 0;
  const officeCargoRules = officeCargoRows.filter(
    (item: { oficina_id: number }) => matchingOfficeIds.has(item.oficina_id),
  );
  const officeCargoCodes = new Set<string>(
    officeCargoRules
      .map((item: { cargo_codigo: string }) => item.cargo_codigo)
      .filter((cargoCodigo: string | null) => cargoCodigo != null),
  );
  const officeCargoNames = new Set<string>(
    officeCargoRules
      .map((item: { cargos?: { cargo?: string | null } }) =>
        normalizeLooseMatchText(item.cargos?.cargo),
      )
      .filter((cargoName: string | null) => cargoName != null),
  );
  const matchesOfficeCargo =
    !hasOfficeCargoRules ||
    officeCargoRules.length === 0 ||
    matchesCargoSelection(userJobTitles, officeCargoCodes, officeCargoNames);
  const matchesCargo =
    allowedCargoCodigos.size > 0 &&
    matchesCargoSelection(
      userJobTitles,
      allowedCargoCodigos,
      allowedCargoNames,
    );

  const matchesOfficeRule = matchesOffice && matchesOfficeCargo;

  if (matchesOfficeRule && matchesCargo) {
    return {
      obligatorio: true,
      motivo: "Oficina y cargo",
    };
  }

  if (matchesOfficeRule) {
    return {
      obligatorio: true,
      motivo: "Oficina",
    };
  }

  if (matchesCargo) {
    return {
      obligatorio: true,
      motivo: "Cargo",
    };
  }

  return {
    obligatorio: false,
    motivo: "No asignado por oficina o cargo",
  };
}

function buildUserDisplayNameFromParts(user: {
  nombreCompleto: string;
  primerApellido: string;
  segundoApellido: string | null;
  tercerApellido: string | null;
}) {
  return [
    user.nombreCompleto,
    user.primerApellido,
    user.segundoApellido,
    user.tercerApellido,
  ]
    .map((value) => value?.trim() ?? "")
    .filter((value) => value.length > 0)
    .join(" ");
}

function buildUserDisplayName(user: {
  nombre_completo?: string | null;
  nombres?: string | null;
  primer_apellido?: string | null;
  segundo_apellido?: string | null;
  tercer_apellido?: string | null;
}) {
  const fullDisplayName = [
    user.nombres,
    user.primer_apellido,
    user.segundo_apellido,
    user.tercer_apellido,
  ]
    .map((value) => value?.trim() ?? "")
    .filter((value) => value.length > 0)
    .join(" ");

  if (fullDisplayName.length > 0) {
    return fullDisplayName;
  }

  return user.nombre_completo?.trim() ?? "";
}

function serializeLocalEventDate(date: Date) {
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  const hour = `${date.getHours()}`.padStart(2, "0");
  const minute = `${date.getMinutes()}`.padStart(2, "0");
  const second = `${date.getSeconds()}`.padStart(2, "0");

  return `${year}-${month}-${day}T${hour}:${minute}:${second}`;
}
