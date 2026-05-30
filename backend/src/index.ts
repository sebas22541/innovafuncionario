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
import { URL } from "node:url";
import { PrismaPg } from "@prisma/adapter-pg";
import { Pool } from "pg";

import {
  generateAndStoreUserCredential,
  generateUserCredentialPdf,
  storeUserProfilePhoto,
} from "./cloudinary/index.ts";
import { PrismaClient, type Prisma } from "./generated/prisma/client.ts";
import { estado_asistencia, rol_usuario } from "./generated/prisma/enums.ts";
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
  300,
  30,
  3600,
);
const DYNAMIC_QR_MIN_REUSE_SECONDS = 15;
const DYNAMIC_QR_HISTORY_LIMIT = clampInt(
  process.env.QR_DYNAMIC_HISTORY_LIMIT ?? null,
  20,
  1,
  100,
);
const DYNAMIC_QR_VERSION = "DQR1";
const DYNAMIC_QR_SIGNATURE_LENGTH = 16;
const JWT_TTL_SECONDS = clampInt(
  process.env.JWT_TTL_SECONDS ?? null,
  2_592_000,
  3_600,
  31_536_000,
);
const JWT_SECRET =
  process.env.JWT_SECRET ??
  createHash("sha256").update(`${DATABASE_URL}:jwt`).digest("hex");
const RATE_LIMIT_MAX_REQUESTS = clampInt(
  process.env.RATE_LIMIT_MAX_REQUESTS ?? null,
  100,
  1,
  100,
);
const IP_RATE_LIMIT_MAX_REQUESTS = clampInt(
  process.env.IP_RATE_LIMIT_MAX_REQUESTS ?? null,
  60,
  1,
  100,
);
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_BAN_MS = clampInt(
  process.env.RATE_LIMIT_BAN_SECONDS ?? null,
  300,
  60,
  3600,
) * 1000;
const ALLOWED_CORS_ORIGINS = parseAllowedCorsOrigins(
  process.env.CORS_ALLOWED_ORIGINS,
);
const PAYLOAD_ENCRYPTION_KEY = normalizeOptionalEnvValue(
  process.env.PAYLOAD_ENCRYPTION_KEY,
);
const PAYLOAD_ENCRYPTION_KEY_BYTES =
  PAYLOAD_ENCRYPTION_KEY == null
    ? null
    : createHash("sha256").update(PAYLOAD_ENCRYPTION_KEY).digest();
const PAYLOAD_RESPONSE_ENCRYPTION_ENABLED =
  process.env.PAYLOAD_RESPONSE_ENCRYPTION === "true";
const REFERENCE_CACHE_TTL_MS = 5 * 60 * 1000;
const DASHBOARD_CACHE_TTL_MS = 30 * 1000;
const EVENT_SUMMARY_CACHE_TTL_MS = 15 * 1000;
const SEED_ADMIN_EMAIL = normalizeEmailValue(
  process.env.SEED_ADMIN_EMAIL ?? "admin@admin.com",
);
const DYNAMIC_QR_SIGNING_SECRET =
  process.env.QR_DYNAMIC_SECRET ??
  createHash("sha256").update(`${DATABASE_URL}:dynamic-qr`).digest("hex");

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

type AuthenticatedUser = {
  id: number;
  email: string;
  ci: string | null;
  rol: (typeof rol_usuario)[keyof typeof rol_usuario];
  activo: boolean;
};

const userWithOfficeInclude = {
  oficinas: true,
  oficina_comision: true,
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

type RateLimitBucket = {
  count: number;
  resetAt: number;
  bannedUntil?: number;
};

let officesCache: CacheEntry<any[]> | null = null;
let cargosCache: CacheEntry<any[]> | null = null;
let dashboardSummaryCache: CacheEntry<{
  usuariosRegistrados: number;
  oficinas: number;
  eventos: number;
}> | null = null;
let eventSummaryCache: CacheEntry<any[]> | null = null;
const rateLimitBuckets = new Map<string, RateLimitBucket>();

await ensureRuntimeSchema();

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

  if (!applyCors(request, response)) {
    logWarning("Origen no permitido.", buildRequestLogFields(request, requestId, {
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

  if (!request.url || !request.method) {
    sendJson(response, 400, { error: "Solicitud invalida." });
    return;
  }

  const url = new URL(
    request.url,
    `http://${request.headers.host ?? "localhost"}`,
  );
  requestPath = buildSafeRequestPath(url);

  try {
    const shouldRateLimitIpBeforeAuth =
      isPublicRoute(request, url) || readOptionalBearerToken(request) == null;

    if (shouldRateLimitIpBeforeAuth) {
      enforceRateLimit(request, response, null);
    }

    let authenticatedUser: AuthenticatedUser;

    try {
      authenticatedUser = await authenticateRequestIfRequired(request, url);
    } catch (error) {
      if (!shouldRateLimitIpBeforeAuth) {
        enforceRateLimit(request, response, null);
      }

      throw error;
    }

    authenticatedUserForLog = authenticatedUser;
    if (authenticatedUser.id > 0) {
      enforceRateLimit(request, response, authenticatedUser);
    }

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

    if (request.method === "POST" && url.pathname === "/api/auth/register") {
      await assertAdminRequester(
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

      const selectedCommissionOffice =
        input.oficinaComisionId == null
          ? null
          : await prisma.oficinas.findUnique({
              where: { id: input.oficinaComisionId },
            });

      if (input.oficinaComisionId != null && !selectedCommissionOffice) {
        throw new HttpError(400, "La oficina de comision seleccionada no existe.");
      }

      const selectedCargo =
        input.cargoCodigo == null
          ? null
          : await prisma.cargos.findUnique({
              where: { codigo: input.cargoCodigo },
            });

      if (input.cargoCodigo != null && !selectedCargo) {
        throw new HttpError(400, "El cargo seleccionado no existe.");
      }

      const resolvedUnit = selectedOffice?.oficina ?? input.unidad ?? "";
      const resolvedOfficeId = selectedOffice?.id ?? null;
      const resolvedCommissionOfficeId = selectedCommissionOffice?.id ?? null;
      const resolvedCargo = selectedCargo?.cargo ?? input.cargo;
      const resolvedCargoCode = selectedCargo?.codigo ?? null;
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
          tipo_vinculo: input.tipoVinculo,
          unidad: resolvedUnit,
          oficina_id: resolvedOfficeId,
          oficina_comision_id: resolvedCommissionOfficeId,
          cargo_codigo: resolvedCargoCode,
          cargo: resolvedCargo,
          numero_item: input.numeroItem,
          foto_url: storedProfilePhoto,
          email: input.email,
          password_hash: passwordHash,
          rol: rol_usuario.OPERADOR,
          activo: input.activo,
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
      const authToken = await createAuthToken(user);

      sendJson(response, 200, {
        data: serializeAppUser(user, person, authToken),
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/auth/logout") {
      await revokeUserSessions(authenticatedUser.id);

      sendJson(response, 200, {
        data: { revoked: true },
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
      const authToken = await createAuthToken(user);

      sendJson(response, 200, {
        data: serializeAppUser(user, person, authToken),
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

      if (existingUser.rol !== rol_usuario.ADMIN) {
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
      const authToken = await createAuthToken(updatedUser);

      sendJson(response, 200, {
        data: serializeAppUser(updatedUser, person, authToken),
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
      const user = await resolveCredentialTargetUser(
        authenticatedUser,
        await readJsonBody(request),
      );
      const person = await ensurePersonIdentityForUser(prisma, user);
      const pdfBytes = await generateUserCredentialPdf(user, person);

      sendPdf(
        response,
        200,
        Buffer.from(pdfBytes),
        buildCredentialPdfFilename(user),
      );
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
        data: await loadSerializedOffices(),
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

    if (request.method === "GET" && url.pathname === "/api/usuarios") {
      await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede gestionar usuarios.",
      );
      const usuarios = await prisma.usuarios.findMany({
        where: {
          email: {
            not: SEED_ADMIN_EMAIL,
          },
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

    if (request.method === "POST" && url.pathname === "/api/usuarios") {
      await assertAdminRequester(
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

      const selectedCommissionOffice =
        input.oficinaComisionId == null
          ? null
          : await prisma.oficinas.findUnique({
              where: { id: input.oficinaComisionId },
            });

      if (input.oficinaComisionId != null && !selectedCommissionOffice) {
        throw new HttpError(400, "La oficina de comision seleccionada no existe.");
      }

      const selectedCargo =
        input.cargoCodigo == null
          ? null
          : await prisma.cargos.findUnique({
              where: { codigo: input.cargoCodigo },
            });

      if (input.cargoCodigo != null && !selectedCargo) {
        throw new HttpError(400, "El cargo seleccionado no existe.");
      }

      const resolvedUnit = selectedOffice?.oficina ?? input.unidad ?? "";
      const resolvedOfficeId = selectedOffice?.id ?? null;
      const resolvedCommissionOfficeId = selectedCommissionOffice?.id ?? null;
      const resolvedCargo = selectedCargo?.cargo ?? input.cargo;
      const resolvedCargoCode = selectedCargo?.codigo ?? null;
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
          tipo_vinculo: input.tipoVinculo,
          unidad: resolvedUnit,
          oficina_id: resolvedOfficeId,
          oficina_comision_id: resolvedCommissionOfficeId,
          cargo_codigo: resolvedCargoCode,
          cargo: resolvedCargo,
          numero_item: input.numeroItem,
          foto_url: storedProfilePhoto,
          email: input.email,
          password_hash: passwordHash,
          rol: input.rol,
          activo: input.activo,
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
      await assertAdminRequester(
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

          const selectedCargo =
            managedInput.cargoCodigo == null
              ? null
              : await tx.cargos.findUnique({
                  where: { codigo: managedInput.cargoCodigo },
                });

          if (managedInput.cargoCodigo != null && !selectedCargo) {
            throw new HttpError(400, "El cargo seleccionado no existe.");
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
              tipo_vinculo: managedInput.tipoVinculo,
              unidad: resolvedUnit,
              oficina_id: resolvedOfficeId,
              oficina_comision_id: resolvedCommissionOfficeId,
              cargo_codigo: resolvedCargoCode,
              cargo: resolvedCargo,
              numero_item: managedInput.numeroItem,
              foto_url: nextPhotoSource,
              email: managedInput.email,
              password_hash: nextPasswordHash,
              rol: managedInput.rol,
              activo: managedInput.activo,
              updated_at: new Date(),
            },
            include: userWithOfficeInclude,
          });

          await tx.personas.updateMany({
            where: { usuario_id: userId },
            data: {
              nombre_completo: buildUserDisplayName(nextUser),
              ci: normalizeOptionalText(nextUser.ci),
              activo: managedInput.activo,
              updated_at: new Date(),
            },
          });

          return nextUser;
        }

        const nextUser = await tx.usuarios.update({
          where: { id: userId },
          data: {
            activo: input.activo,
            updated_at: new Date(),
          },
          include: userWithOfficeInclude,
        });

        await tx.personas.updateMany({
          where: { usuario_id: userId },
          data: {
            activo: input.activo,
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
        data: await loadDashboardSummary(),
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/eventos") {
      const view = parseEventListView(url);

      sendJson(response, 200, {
        data:
          view === "summary"
            ? await loadSerializedEventSummaries()
            : (await prisma.eventos.findMany({
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
        );

        await tx.evento_oficinas.createMany({
          data: resolvedOfficeSelection.expandedOffices.map((office) => ({
            evento_id: createdEvent.id,
            oficina_id: office.id,
            seleccion_directa: office.isDirectSelection,
          })),
        });

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

      sendJson(response, 200, {
        data: serializeEvent(evento),
      });
      return;
    }

    if (request.method === "PUT" && eventId != null) {
      const input = parseUpdateEventInput(await readJsonBody(request));
      await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede editar eventos.",
      );

      const evento = await prisma.$transaction(async (tx) => {
        const existingEvent = await tx.eventos.findUnique({
          where: { id: eventId },
        });

        if (!existingEvent) {
          throw new HttpError(404, "No se encontro el evento seleccionado.");
        }

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
        );

        await tx.evento_oficinas.createMany({
          data: resolvedOfficeSelection.expandedOffices.map((office) => ({
            evento_id: eventId,
            oficina_id: office.id,
            seleccion_directa: office.isDirectSelection,
          })),
        });

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

      sendJson(response, 200, {
        data: serializeEvent(evento),
      });
      return;
    }

    if (request.method === "DELETE" && eventId != null) {
      await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede borrar eventos.",
      );

      const existingEvent = await prisma.eventos.findUnique({
        where: { id: eventId },
      });

      if (!existingEvent) {
        throw new HttpError(404, "No se encontro el evento seleccionado.");
      }

      await prisma.eventos.delete({
        where: { id: eventId },
      });
      invalidateEventSummaryCache();
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
      await assertAdminRequester(
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
                usuario_id: {
                  not: null,
                },
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
        assertScannedQrIsUsable(scannedValue);
      }

      if (!lookupCode) {
        throw new HttpError(
          400,
          isCiRegistration
            ? "Debes enviar un CI valido."
            : "Debes enviar un codigo QR valido.",
        );
      }

      const evento = await prisma.eventos.findUnique({
        where: { id: input.eventId },
        include: {
          evento_oficinas: {
            select: {
              oficina_id: true,
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
            },
            orderBy: {
              orden: "asc",
            },
          },
        },
      });

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

      const persona = isCiRegistration
        ? await findPersonByCi(input.ci!)
        : await resolvePersonByQrValue(scannedValue, lookupCode);

      if (!persona) {
        throw new HttpError(404, "No se encontro una persona con ese CI.");
      }

      if (input.estado === estado_asistencia.ASISTIO) {
        await assertPersonCanAttendEvent(persona, evento);
      }

      const operador = await assertEventOperator(authenticatedUser.id);
      const registeredAt = new Date();
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

        await tx.asistencia_controles.upsert({
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
            observacion: resolvedObservation,
            registrado_por_id: operador.id,
            registrado_en: registeredAt,
            latitud_registro: input.latitud,
            longitud_registro: input.longitud,
            accuracy_registro: input.accuracy,
          },
          update: {
            estado: input.estado,
            observacion: resolvedObservation,
            registrado_por_id: operador.id,
            registrado_en: registeredAt,
            latitud_registro: input.latitud,
            longitud_registro: input.longitud,
            accuracy_registro: input.accuracy,
          },
        });

        const controlAttendances = await tx.asistencia_controles.findMany({
          where: {
            asistencia_id: baseAttendance.id,
          },
          select: {
            estado: true,
          },
        });
        const resolvedAttendanceState = controlAttendances.some(
          (item: { estado: estado_asistencia }) =>
            item.estado === estado_asistencia.ASISTIO,
        )
          ? estado_asistencia.ASISTIO
          : estado_asistencia.OBSERVADO;

        await tx.asistencias.update({
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
        });

        return tx.asistencias.findUniqueOrThrow({
          where: {
            id: baseAttendance.id,
          },
          include: {
            personas: {
              include: {
                departamentos: true,
                usuario: {
                  include: userWithOfficeInclude,
                },
              },
            },
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
        });
      });
      invalidateEventSummaryCache();

      sendJson(response, 200, {
        data: serializeAttendanceRecord(asistencia),
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/personas") {
      await assertAdminRequester(
        authenticatedUser.email,
        "Solo un administrador puede listar personas.",
      );
      const limit = clampInt(url.searchParams.get("limit"), 20, 1, 100);
      const personas = await prisma.personas.findMany({
        take: limit,
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

      if (eventId != null) {
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
        data: serializeQrPersonDetail(persona, { eventAttendance }),
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

      assertScannedQrIsUsable(codigoQr);

      const persona = await findPersonByScannedValue(codigoQr);
      const eventId = readOptionalQueryInt(url, "eventId");

      if (!persona) {
        sendJson(response, 404, {
          error: "No se encontro una persona con ese codigo QR.",
        });
        return;
      }

      let eventAttendance = null;

      if (eventId != null) {
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
        data: serializeQrPersonDetail(persona, { eventAttendance }),
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
      sendJson(response, error.statusCode, { error: error.message });
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
  segundoApellido: string;
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

type RegisterUserInput = {
  email: string;
  password: string;
  nombreCompleto: string;
  primerApellido: string;
  segundoApellido: string;
  tercerApellido: string | null;
  ci: string;
  tipoVinculo: string;
  unidad: string | null;
  oficinaId: number | null;
  oficinaComisionId: number | null;
  cargoCodigo: string | null;
  cargo: string;
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
  const isTrustedUnsafeRequest =
    !isUnsafeHttpMethod(request.method) ||
    (origin != null && isAllowedRequestOrigin(origin)) ||
    (origin == null &&
      referrerOrigin != null &&
      isAllowedRequestOrigin(referrerOrigin));

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
    "Content-Type, Authorization",
  );
  response.setHeader("Access-Control-Max-Age", "86400");
  response.setHeader("Content-Type", "application/json; charset=utf-8");

  return isAllowedOrigin;
}

function isUnsafeHttpMethod(method: string | undefined) {
  return method !== "GET" && method !== "HEAD" && method !== "OPTIONS";
}

function isAllowedRequestOrigin(origin: string) {
  return ALLOWED_CORS_ORIGINS.has(origin);
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
  const forwardedFor = readSingleHeader(request.headers["x-forwarded-for"]);

  if (forwardedFor != null && forwardedFor.trim().length > 0) {
    return forwardedFor.split(",")[0]?.trim();
  }

  return request.socket.remoteAddress;
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
    response.setHeader("X-Payload-Encrypted", "AES-256-GCM");
    payload = encryptedPayload;
  }

  response.setHeader("Cache-Control", "no-store");
  response.setHeader("Pragma", "no-cache");
  response.writeHead(statusCode);
  response.end(JSON.stringify(payload, null, 2));
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

function enforceRateLimit(
  request: IncomingMessage,
  response: ServerResponse,
  authenticatedUser: AuthenticatedUser | null,
) {
  const key = readRateLimitKey(request, authenticatedUser);
  const scope = authenticatedUser == null ? "ip" : "user";
  const maxRequests =
    scope === "ip" ? IP_RATE_LIMIT_MAX_REQUESTS : RATE_LIMIT_MAX_REQUESTS;
  const now = Date.now();
  pruneExpiredRateLimitBuckets(now);
  const bucket = rateLimitBuckets.get(key);

  if (bucket?.bannedUntil != null && bucket.bannedUntil > now) {
    setRateLimitHeaders(response, bucket, scope, maxRequests);
    response.setHeader(
      "Retry-After",
      Math.max(1, Math.ceil((bucket.bannedUntil - now) / 1000)).toString(),
    );
    throw new HttpError(
      429,
      "Demasiadas solicitudes. Intenta nuevamente mas tarde.",
    );
  }

  if (bucket == null || bucket.resetAt <= now) {
    const nextBucket = {
      count: 1,
      resetAt: now + RATE_LIMIT_WINDOW_MS,
    };
    rateLimitBuckets.set(key, nextBucket);
    setRateLimitHeaders(response, nextBucket, scope, maxRequests);
    return;
  }

  bucket.count += 1;
  setRateLimitHeaders(response, bucket, scope, maxRequests);

  if (bucket.count > maxRequests) {
    bucket.bannedUntil = now + RATE_LIMIT_BAN_MS;
    response.setHeader(
      "Retry-After",
      Math.max(1, Math.ceil(RATE_LIMIT_BAN_MS / 1000)).toString(),
    );
    throw new HttpError(
      429,
      "Demasiadas solicitudes. Intenta nuevamente mas tarde.",
    );
  }
}

function readRateLimitKey(
  request: IncomingMessage,
  authenticatedUser: AuthenticatedUser | null,
) {
  if (authenticatedUser != null && authenticatedUser.id > 0) {
    return `user:${authenticatedUser.id}`;
  }

  return `ip:${readClientIp(request)}`;
}

function pruneExpiredRateLimitBuckets(now: number) {
  for (const [key, bucket] of rateLimitBuckets) {
    if (bucket.resetAt <= now && (bucket.bannedUntil == null || bucket.bannedUntil <= now)) {
      rateLimitBuckets.delete(key);
    }
  }
}

function setRateLimitHeaders(
  response: ServerResponse,
  bucket: RateLimitBucket,
  scope: "ip" | "user",
  maxRequests: number,
) {
  response.setHeader("X-RateLimit-Limit", maxRequests.toString());
  response.setHeader("X-RateLimit-Scope", scope);
  response.setHeader(
    "X-RateLimit-Remaining",
    Math.max(0, maxRequests - bucket.count).toString(),
  );
  response.setHeader(
    "X-RateLimit-Reset",
    Math.ceil(bucket.resetAt / 1000).toString(),
  );
}

function readClientIp(request: IncomingMessage) {
  const forwardedFor = request.headers["x-forwarded-for"];
  const firstForwardedIp = Array.isArray(forwardedFor)
    ? forwardedFor[0]
    : forwardedFor?.split(",")[0];

  return (
    firstForwardedIp?.trim() ??
    request.socket.remoteAddress ??
    "unknown"
  );
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

  if (
    request.method === "POST" &&
    url.pathname === "/api/auth/login"
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
    ALTER TABLE "usuarios"
    ADD COLUMN IF NOT EXISTS "oficina_comision_id" INTEGER
  `);

  await pool.query(`
    ALTER TABLE "usuarios"
      ADD COLUMN IF NOT EXISTS "session_version" INTEGER NOT NULL DEFAULT 0
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
    END $$
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "idx_usuarios_oficina_comision_id"
      ON "usuarios" ("oficina_comision_id")
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
    encrypted: true,
    alg: "AES-256-GCM",
    iv: iv.toString("base64"),
    payload: encrypted.toString("base64"),
    tag: tag.toString("base64"),
  };
}

function decryptJsonPayload(payload: unknown) {
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
  } catch {
    throw new HttpError(400, "No fue posible descifrar el cuerpo JSON.");
  }
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
  const oficinaIds = readRequiredIntList(body, "oficinaIds", "oficinaId");
  const oficinaIdsExcluidos = readOptionalIntList(
    body,
    "oficinaIdsExcluidos",
  );
  const cargoCodigos = readOptionalStringList(body, "cargoCodigos", "cargoCodigo");
  const cargoCodigosPorOficina = parseOfficeJobTitleInput(body);
  const controles = parseEventControlsInput(body);

  return {
    nombre,
    fechaEvento,
    direccion,
    latitud,
    longitud,
    oficinaIds,
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

    return {
      id: readOptionalInt(control, "id"),
      nombre: readRequiredString(control, "nombre", 2, 120),
      orden: index + 1,
    };
  });
}

async function resolveExpandedEventOffices(
  tx: any,
  officeIds: number[],
  excludedOfficeIds: number[] = [],
): Promise<ResolvedEventOfficeSelection> {
  const uniqueOfficeIds = [...new Set(officeIds)];
  const allOffices = (await tx.oficinas.findMany()) as EventOfficeNode[];
  const officesById = new Map(allOffices.map((office) => [office.id, office]));
  const directOffices = uniqueOfficeIds.map((officeId) => officesById.get(officeId));

  if (directOffices.some((office) => office == null)) {
    throw new HttpError(400, "Debes seleccionar una o mas oficinas validas.");
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
        (selectedCode) =>
          officeCode === selectedCode || officeCode.startsWith(`${selectedCode}.`),
      );
    });
  const excludedCodes = normalizedExcludedOffices
    .map((office) => normalizeOfficeCode(office.cod))
    .filter((code) => code.length > 0);

  const expandedOffices = allOffices
    .filter((office: EventOfficeNode) => {
      const officeCode = normalizeOfficeCode(office.cod);

      const isIncluded = directCodes.some(
        (selectedCode) =>
          officeCode === selectedCode || officeCode.startsWith(`${selectedCode}.`),
      );
      const isExcluded = excludedCodes.some(
        (excludedCode) =>
          officeCode === excludedCode || officeCode.startsWith(`${excludedCode}.`),
      );

      return isIncluded && !isExcluded;
    })
    .map((office: EventOfficeNode) => ({
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
    })),
  });
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

function isOfficeCoveredByBranch(officeCode: string, branchCode: string) {
  const normalizedOfficeCode = normalizeOfficeCode(officeCode);
  const normalizedBranchCode = normalizeOfficeCode(branchCode);

  return normalizedOfficeCode === normalizedBranchCode ||
    normalizedOfficeCode.startsWith(`${normalizedBranchCode}.`);
}

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
    await assertAdminRequester(
      authenticatedUser.email,
      "Solo un administrador puede descargar credenciales de otros usuarios.",
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

  return user;
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
    segundoApellido: readRequiredString(body, "segundoApellido", 2, 80),
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

function parseRegisterUserInput(payload: unknown): RegisterUserInput {
  const body = expectRecord(payload);
  const tipoVinculo = readRequiredUppercaseChoice(
    body,
    "tipoVinculo",
    ["ITEM", "EVENTUAL", "CONSULTOR"],
  );
  const oficinaId = readOptionalInt(body, "oficinaId");
  const oficinaComisionId = readOptionalInt(body, "oficinaComisionId");
  const unidad = readOptionalString(body, "unidad", 0, 120);
  const cargoCodigo = readOptionalString(body, "cargoCodigo", 1, 50);
  const cargo = readOptionalString(body, "cargo", 2, 120);
  const ci = readRequiredString(body, "ci", 3, 30);
  const primerApellido = readRequiredString(body, "primerApellido", 2, 80);
  const loginIdentifier = normalizeEmailValue(normalizeCiValue(ci));

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
    segundoApellido: readRequiredString(body, "segundoApellido", 2, 80),
    tercerApellido: readOptionalString(body, "tercerApellido", 0, 80),
    ci: readRequiredString(body, "ci", 3, 30),
    tipoVinculo,
    unidad,
    oficinaId,
    oficinaComisionId,
    cargoCodigo,
    cargo: cargo ?? "",
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
    rol_usuario.CONTROL,
    rol_usuario.OPERADOR,
  ]) as (typeof rol_usuario)[keyof typeof rol_usuario];
  const requesterEmail = readRequiredLoginIdentifier(body, "requesterEmail");

  return {
    ...baseInput,
    rol: requestedRole,
    requesterEmail,
  };
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
    ["ITEM", "EVENTUAL", "CONSULTOR"],
  );
  const oficinaId = readOptionalInt(body, "oficinaId");
  const oficinaComisionId = readOptionalInt(body, "oficinaComisionId");
  const unidad = readOptionalString(body, "unidad", 0, 120);
  const cargoCodigo = readOptionalString(body, "cargoCodigo", 1, 50);
  const cargo = readOptionalString(body, "cargo", 2, 120);
  const requestedRole = readRequiredUppercaseChoice(body, "rol", [
    rol_usuario.ADMIN,
    rol_usuario.CONTROL,
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
    segundoApellido: readRequiredString(body, "segundoApellido", 2, 80),
    tercerApellido: readOptionalString(body, "tercerApellido", 0, 80),
    ci,
    tipoVinculo,
    unidad,
    oficinaId,
    oficinaComisionId,
    cargoCodigo,
    cargo: cargo ?? "",
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

  if (view === "summary" || view === "detail") {
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

function readRequiredBoolean(source: JsonRecord, key: string) {
  const value = source[key];

  if (typeof value !== "boolean") {
    throw new HttpError(400, `El campo ${key} es obligatorio.`);
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

async function assertAdminRequester(
  email: string,
  message = "Solo un administrador puede realizar esta accion.",
) {
  const user = await prisma.usuarios.findUnique({
    where: { email: email.toLowerCase() },
  });

  if (!user || user.rol !== rol_usuario.ADMIN || user.activo !== true) {
    throw new HttpError(403, message);
  }

  return user;
}

function isAdminUser(user: AuthenticatedUser) {
  return user.rol === rol_usuario.ADMIN;
}

function assertAuthenticatedRequester(user: AuthenticatedUser) {
  if (user.id <= 0 || user.activo !== true) {
    throw new HttpError(401, "Debes iniciar sesion para continuar.");
  }
}

function assertPersonLookupRequester(user: AuthenticatedUser) {
  if (!isAdminUser(user)) {
    throw new HttpError(
      403,
      "Solo un administrador puede consultar datos por QR o CI.",
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
    (user.rol !== rol_usuario.ADMIN && user.rol !== rol_usuario.CONTROL)
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
  input: GenerateDynamicQrInput,
) {
  const activeDynamicQr = readActiveDynamicQrSession(person, user);

  if (isReusableDynamicQrSession(activeDynamicQr)) {
    return activeDynamicQr;
  }

  const qrCode = person.codigo_qr ?? buildUserQrCode(user);
  const issuedAt = new Date();
  const expiresAt = new Date(
    issuedAt.getTime() + (DYNAMIC_QR_TTL_SECONDS * 1000),
  );
  const qrPayload = buildDynamicQrPayload(qrCode, expiresAt);
  const nextMetadata = buildStoredUserQrMetadata(
    user,
    qrCode,
    person.datos_qr ?? null,
    {
      qrPayload,
      issuedAt,
      expiresAt,
      latitud: input.latitud,
      longitud: input.longitud,
      accuracy: input.accuracy,
    },
  );

  await tx.personas.update({
    where: { id: person.id },
    data: {
      codigo_qr: qrCode,
      datos_qr: nextMetadata,
      updated_at: new Date(),
    },
  });

  return {
    qrCode,
    qrPayload,
    generatedAt: issuedAt.toISOString(),
    expiresAt: expiresAt.toISOString(),
    ttlSeconds: DYNAMIC_QR_TTL_SECONDS,
    location: {
      latitud: input.latitud,
      longitud: input.longitud,
      accuracy: input.accuracy,
    },
  };
}

function isReusableDynamicQrSession(
  session: ReturnType<typeof readActiveDynamicQrSession>,
) {
  return (
    session != null &&
    new Date(session.expiresAt).getTime() - Date.now() >
      DYNAMIC_QR_MIN_REUSE_SECONDS * 1000
  );
}

function readActiveDynamicQrSession(person: any, user: any) {
  const qrCode = person.codigo_qr ?? buildUserQrCode(user);
  const dynamicQr = readDynamicQrMetadata(person.datos_qr);
  const generatedAt = readIsoDate(dynamicQr?.lastGeneratedAt);
  const expiresAt = readIsoDate(dynamicQr?.lastExpiresAt);
  const location = readLooseJsonRecord(dynamicQr?.lastLocation);
  const latitud = readFiniteNumber(location?.latitud);
  const longitud = readFiniteNumber(location?.longitud);
  const accuracy = readFiniteNumber(location?.accuracy);

  if (
    !generatedAt ||
    !expiresAt ||
    expiresAt.getTime() <= Date.now() ||
    latitud == null ||
    longitud == null
  ) {
    return null;
  }

  return {
    qrCode,
    qrPayload: buildDynamicQrPayload(qrCode, expiresAt),
    generatedAt: generatedAt.toISOString(),
    expiresAt: expiresAt.toISOString(),
    ttlSeconds: DYNAMIC_QR_TTL_SECONDS,
    location: {
      latitud,
      longitud,
      accuracy,
    },
  };
}

function hashPassword(password: string) {
  const salt = randomBytes(16).toString("hex");
  const derivedKey = scryptSync(password, salt, 64).toString("hex");

  return `scrypt:${salt}:${derivedKey}`;
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

function buildQrLookupCandidates(scannedValue: string, providedLookupCode?: string) {
  // Orden de candidatos:
  // 1. lookupCode extraido del payload/URL/texto.
  // 2. valor exacto leido, por compatibilidad con QRs antiguos.
  // 3. AUTOQR:{sha256(raw)}, para placeholders creados desde escaneos previos.
  const trimmedValue = scannedValue.trim();

  if (!trimmedValue) {
    return [];
  }

  const lookupCode = providedLookupCode ?? extractLookupCode(trimmedValue);
  const exactValue = trimmedValue.length <= 255 ? trimmedValue : null;
  const placeholderCode = buildPlaceholderQrCode(trimmedValue);

  return [...new Set([lookupCode, exactValue, placeholderCode].filter(isValidQrCode))];
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

function assertScannedQrIsUsable(scannedValue: string) {
  const dynamicQr = tryParseDynamicQrPayload(scannedValue);

  if (dynamicQr != null && isDynamicQrExpired(dynamicQr)) {
    throw new HttpError(
      410,
      "No se puede realizar el escaneo porque el QR esta caduco. Genera o refresca un nuevo QR e intentalo otra vez.",
    );
  }
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
    cargo: normalizeOptionalText(user.cargo) ?? "",
    numeroItem: normalizeOptionalText(user.numero_item) ?? "",
    activo: user.activo === true,
  };
}

function buildUserQrPayload(_: any, qrCode: string) {
  // El QR visible y exportable contiene solo el ID externo.
  // La app consulta al backend con ese ID para obtener los datos completos.
  return qrCode;
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
    cargo: linkedUser?.cargo ?? null,
    tipoVinculo: linkedUser?.tipo_vinculo ?? null,
    numeroItem: linkedUser?.numero_item ?? null,
    fotoRegistrada: normalizeOptionalText(linkedUser?.foto_url) != null,
    origen: linkedUser == null ? "persona" : "usuario",
    registrationSource: options?.registrationSource ?? "QR",
    registrationCi: normalizeOptionalText(options?.registrationCi) ?? null,
    scannedAt: options?.scannedAt?.toISOString() ?? null,
    registrationLocation: options?.registrationLocation ?? null,
  };
}

async function loadSerializedOffices() {
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

async function loadDashboardSummary() {
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

async function loadSerializedEventSummaries() {
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
}) {
  return {
    id: control.id,
    nombre: control.nombre,
    orden: control.orden,
  };
}

function serializeAttendanceControlRecord(controlAttendance: any) {
  return {
    id: controlAttendance.id,
    controlId: controlAttendance.control_id,
    controlNombre: controlAttendance.evento_controles.nombre,
    controlOrden: controlAttendance.evento_controles.orden,
    estado: controlAttendance.estado,
    observacion: controlAttendance.observacion,
    registradoEn: controlAttendance.registrado_en.toISOString(),
  };
}

function serializeEventAttendanceLookup(attendance: any) {
  const serializedControls = (attendance.asistencia_controles ?? []).map(
    serializeAttendanceControlRecord,
  );
  const controlSummary = buildSerializedControlSummary(serializedControls);

  return {
    estado: controlSummary.state,
    controles: controlSummary.controls,
    controlesRegistrados: controlSummary.registeredCount,
    controlesAsistidos: controlSummary.attendedCount,
    controlesObservados: controlSummary.observedCount,
    registradoEn: attendance.registrado_en.toISOString(),
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

  return {
    controls: sortedControls,
    registeredCount: sortedControls.length,
    attendedCount: attendedControls.length,
    observedCount: observedControls.length,
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
    asistieronCount: resolvedCounts.attended,
    observaronCount: resolvedCounts.observed,
    personasListadasCount: resolvedCounts.total,
    detalleCompleto: false,
  };
}

function serializeEvent(event: any) {
  const attended = (event.asistencias ?? [])
    .filter((item: any) => item.estado === estado_asistencia.ASISTIO)
    .map(serializeAttendanceRecord);
  const observed = (event.asistencias ?? [])
    .filter((item: any) => item.estado === estado_asistencia.OBSERVADO)
    .map(serializeAttendanceRecord);

  return {
    ...buildSerializedEventBase(event),
    asistieron: attended,
    observaron: observed,
    asistieronCount: attended.length,
    observaronCount: observed.length,
    personasListadasCount: attended.length + observed.length,
    detalleCompleto: true,
  };
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

function serializeAppUser(user: any, person?: any | null, authToken?: string) {
  // El frontend recibe dos piezas equivalentes:
  // 1. `qrCode` para mostrar el ID externo en texto.
  // 2. `qrPayload` para renderizar ese mismo ID externo como imagen QR.
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
    tipoVinculo: user.tipo_vinculo ?? "ITEM",
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
    numeroItem: user.numero_item ?? "",
    activo: user.activo,
    fotoUrl: user.foto_url,
    qrCode,
    qrPayload: buildUserQrPayload(user, qrCode),
    personaId: linkedPerson?.id ?? null,
    authToken,
  };
}

function serializeAttendanceRecord(attendance: any) {
  const linkedUser = attendance.personas.usuario ?? null;
  const officeName = resolveLinkedOfficeName(linkedUser);
  const serializedControls = (attendance.asistencia_controles ?? []).map(
    serializeAttendanceControlRecord,
  );
  const controlSummary = buildSerializedControlSummary(serializedControls);
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
    tipoVinculo: linkedUser?.tipo_vinculo ?? null,
    unidad: officeName,
    cargo: linkedUser?.cargo ?? null,
    fotoUrl: linkedUser?.foto_url ?? null,
    email: linkedUser?.email ?? null,
    registradoEn: attendance.registrado_en.toISOString(),
    controles: controlSummary.controls,
    controlesRegistrados: controlSummary.registeredCount,
    controlesAsistidos: controlSummary.attendedCount,
    controlesObservados: controlSummary.observedCount,
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
    cargo: linkedUser?.cargo ?? null,
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
    cargoCodigo: linkedUser?.cargo_codigo ?? null,
    cargo: linkedUser?.cargo ?? null,
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
  };
}

async function assertPersonCanAttendEvent(person: any, event: any) {
  const linkedUser = person.usuario ?? null;
  const userOfficeId =
    resolveLinkedOfficeId(linkedUser) ??
    (await resolveOfficeForUser(prisma, linkedUser))?.id ??
    null;
  const allowedOfficeIds = new Set<number>(
    (event.evento_oficinas ?? []).map((item: { oficina_id: number }) => item.oficina_id),
  );
  const allowedCargoCodigos = new Set<string>(
    (event.evento_cargos ?? [])
      .map((item: { cargo_codigo: string }) => item.cargo_codigo)
      .filter((cargoCodigo: string | null) => cargoCodigo != null),
  );
  const allowedCargoNames = new Set<string>(
    (event.evento_cargos ?? [])
      .map((item: { cargos?: { cargo?: string | null } }) =>
        normalizeOfficeMatchText(item.cargos?.cargo),
      )
      .filter((cargoName: string | null) => cargoName != null),
  );
  const userCargoCodigo = normalizeOptionalText(linkedUser?.cargo_codigo);
  const userCargoName = normalizeOfficeMatchText(linkedUser?.cargo);
  const matchesOffice = userOfficeId != null && allowedOfficeIds.has(userOfficeId);
  const officeCargoRows = event.evento_oficina_cargos ?? [];
  const hasOfficeCargoRules = officeCargoRows.length > 0;
  const officeCargoRules = officeCargoRows.filter(
    (item: { oficina_id: number }) => item.oficina_id === userOfficeId,
  );
  const officeCargoCodes = new Set<string>(
    officeCargoRules
      .map((item: { cargo_codigo: string }) => item.cargo_codigo)
      .filter((cargoCodigo: string | null) => cargoCodigo != null),
  );
  const officeCargoNames = new Set<string>(
    officeCargoRules
      .map((item: { cargos?: { cargo?: string | null } }) =>
        normalizeOfficeMatchText(item.cargos?.cargo),
      )
      .filter((cargoName: string | null) => cargoName != null),
  );
  const matchesOfficeCargo =
    !hasOfficeCargoRules ||
    officeCargoRules.length === 0 ||
    (userCargoCodigo != null && officeCargoCodes.has(userCargoCodigo)) ||
    (userCargoName != null && officeCargoNames.has(userCargoName));
  const matchesCargo =
    allowedCargoCodigos.size > 0 &&
    ((userCargoCodigo != null && allowedCargoCodigos.has(userCargoCodigo)) ||
      (userCargoName != null && allowedCargoNames.has(userCargoName)));

  if (hasOfficeCargoRules) {
    if (!matchesOffice || !matchesOfficeCargo) {
      throw new HttpError(
        403,
        "Este usuario no esta permitido asistir a este evento.",
      );
    }

    return;
  }

  if (!matchesOffice && !matchesCargo) {
    throw new HttpError(
      403,
      "Este usuario no esta permitido asistir a este evento.",
    );
  }
}

function buildUserDisplayNameFromParts(user: {
  nombreCompleto: string;
  primerApellido: string;
  segundoApellido: string;
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
