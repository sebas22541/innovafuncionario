import "dotenv/config";
import { createHash, randomBytes, scryptSync } from "node:crypto";
import { PrismaPg } from "@prisma/adapter-pg";
import { Pool } from "pg";

import { PrismaClient, type Prisma } from "../src/generated/prisma/client.ts";
import { rol_usuario } from "../src/generated/prisma/enums.ts";

const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  throw new Error("DATABASE_URL no esta definido en backend/.env.");
}

const pool = new Pool({ connectionString: DATABASE_URL });
const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter });

const adminEmail = normalizeEmail(
  process.env.SEED_ADMIN_EMAIL ?? "admin@admin.com",
);
const adminPassword = process.env.SEED_ADMIN_PASSWORD ?? "admin123";
const adminNames = process.env.SEED_ADMIN_NAMES ?? "Administrador";
const adminFirstLastName = process.env.SEED_ADMIN_FIRST_LASTNAME ?? "Sistema";
const adminSecondLastName = process.env.SEED_ADMIN_SECOND_LASTNAME ?? "QR";
const adminCi = process.env.SEED_ADMIN_CI ?? "000000";

async function main() {
  const user = await prisma.usuarios.upsert({
    where: { email: adminEmail },
    update: {
      nombre_completo: buildDisplayName(),
      nombres: adminNames,
      primer_apellido: adminFirstLastName,
      segundo_apellido: adminSecondLastName,
      tercer_apellido: null,
      ci: adminCi,
      tipo_vinculo: "ITEM",
      unidad: "Administracion",
      oficina_id: null,
      cargo_codigo: null,
      cargo: "Administrador del sistema",
      numero_item: "0",
      foto_url: null,
      password_hash: hashPassword(adminPassword),
      rol: rol_usuario.ADMIN,
      activo: true,
      updated_at: new Date(),
    },
    create: {
      nombre_completo: buildDisplayName(),
      nombres: adminNames,
      primer_apellido: adminFirstLastName,
      segundo_apellido: adminSecondLastName,
      tercer_apellido: null,
      ci: adminCi,
      tipo_vinculo: "ITEM",
      unidad: "Administracion",
      oficina_id: null,
      cargo_codigo: null,
      cargo: "Administrador del sistema",
      numero_item: "0",
      foto_url: null,
      email: adminEmail,
      password_hash: hashPassword(adminPassword),
      rol: rol_usuario.ADMIN,
      activo: true,
    },
  });

  await ensurePersonIdentityForSeedUser(user);

  console.log("Usuario admin listo para login:");
  console.log(`  email: ${adminEmail}`);
  console.log(`  password: ${adminPassword}`);
}

function normalizeEmail(value: string) {
  return value.trim().toLowerCase();
}

function buildDisplayName() {
  return [adminNames, adminFirstLastName, adminSecondLastName]
    .map((value) => value.trim())
    .filter(Boolean)
    .join(" ");
}

function hashPassword(password: string) {
  const salt = randomBytes(16).toString("hex");
  const derivedKey = scryptSync(password, salt, 64).toString("hex");

  return `scrypt:${salt}:${derivedKey}`;
}

async function ensurePersonIdentityForSeedUser(user: {
  id: number;
  email: string;
  nombre_completo: string;
  nombres: string | null;
  primer_apellido: string | null;
  segundo_apellido: string | null;
  tercer_apellido: string | null;
  ci: string | null;
  tipo_vinculo: string | null;
  unidad: string | null;
  cargo: string | null;
  numero_item: string | null;
  foto_url: string | null;
  activo: boolean;
}) {
  const existingPerson = await prisma.personas.findUnique({
    where: { usuario_id: user.id },
  });
  const matchedPerson =
    existingPerson ??
    (user.ci == null
      ? null
      : await prisma.personas.findFirst({
          where: {
            usuario_id: null,
            ci: user.ci,
          },
          orderBy: [{ activo: "desc" }, { updated_at: "desc" }, { id: "desc" }],
        }));
  const qrCode = buildUserQrCode(user);
  const data = {
    nombre_completo: buildUserDisplayName(user),
    ci: user.ci,
    codigo_qr: qrCode,
    datos_qr: buildStoredUserQrMetadata(user, qrCode),
    activo: user.activo === true,
    updated_at: new Date(),
    usuario_id: user.id,
  };

  if (matchedPerson) {
    await prisma.personas.update({
      where: { id: matchedPerson.id },
      data,
    });
    return;
  }

  await prisma.personas.create({
    data,
  });
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

  return fullDisplayName.length > 0
    ? fullDisplayName
    : user.nombre_completo?.trim() ?? "";
}

function buildUserQrCode(user: {
  id: number;
  email?: string | null;
  ci?: string | null;
}) {
  const seed = `${user.id}:${user.email?.toLowerCase() ?? ""}:${user.ci ?? ""}:external-qr`;
  const digest = createHash("sha256").update(seed).digest("hex").slice(0, 20);

  return `QREXT-${digest.toUpperCase()}`;
}

function buildStoredUserQrMetadata(
  user: {
    id: number;
    email?: string | null;
    nombres?: string | null;
    nombre_completo?: string | null;
    primer_apellido?: string | null;
    segundo_apellido?: string | null;
    tercer_apellido?: string | null;
    ci?: string | null;
    tipo_vinculo?: string | null;
    unidad?: string | null;
    cargo?: string | null;
    numero_item?: string | null;
    foto_url?: string | null;
    activo?: boolean;
  },
  qrCode: string,
): Prisma.InputJsonObject {
  return {
    type: "qr-asistencia-user",
    version: 1,
    codigoQr: qrCode,
    usuarioId: user.id,
    ci: user.ci ?? "",
    email: user.email ?? "",
    nombreCompleto: user.nombres ?? user.nombre_completo ?? "",
    primerApellido: user.primer_apellido ?? "",
    segundoApellido: user.segundo_apellido ?? "",
    tercerApellido: user.tercer_apellido ?? "",
    nombreVisible: buildUserDisplayName(user),
    tipoVinculo: user.tipo_vinculo ?? "",
    unidad: user.unidad ?? "",
    cargo: user.cargo ?? "",
    numeroItem: user.numero_item ?? "",
    activo: user.activo === true,
    payloadPublico: qrCode,
    payloadTipo: "EXTERNAL_ID",
    origen: "usuario",
    fotoRegistrada: Boolean(user.foto_url),
    syncedAt: new Date().toISOString(),
  };
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
    await pool.end();
  });
