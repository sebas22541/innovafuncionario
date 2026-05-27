import "dotenv/config";
import { randomBytes, scryptSync } from "node:crypto";
import { PrismaPg } from "@prisma/adapter-pg";
import { Pool } from "pg";

import { PrismaClient } from "../src/generated/prisma/client.ts";
import { rol_usuario } from "../src/generated/prisma/enums.ts";

const DATABASE_URL = process.env.DATABASE_URL;
const APPLY_CHANGES = process.argv.includes("--apply");
const INCLUDE_ADMINS = process.argv.includes("--include-admins");

if (!DATABASE_URL) {
  throw new Error("DATABASE_URL no esta definido en backend/.env.");
}

const pool = new Pool({ connectionString: DATABASE_URL });
const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter });

type UserLoginUpdate = {
  id: number;
  currentEmail: string;
  nextEmail: string;
  nextPassword: string;
};

async function main() {
  const users = await prisma.usuarios.findMany({
    orderBy: { id: "asc" },
    select: {
      id: true,
      email: true,
      ci: true,
      primer_apellido: true,
      rol: true,
    },
  });
  const errors: string[] = [];
  const updates: UserLoginUpdate[] = [];
  const ciCounts = new Map<string, number>();

  for (const user of users) {
    const ci = normalizeCi(user.ci);

    if (!ci) {
      errors.push(`Usuario ${user.id} (${user.email}) no tiene CI.`);
      continue;
    }

    ciCounts.set(ci, (ciCounts.get(ci) ?? 0) + 1);
  }

  for (const user of users) {
    if (user.rol === rol_usuario.ADMIN && !INCLUDE_ADMINS) {
      continue;
    }

    const ci = normalizeCi(user.ci);
    const lastNamePrefix = buildLastNamePrefix(user.primer_apellido);

    if (!ci) {
      continue;
    }

    if ((ciCounts.get(ci) ?? 0) > 1) {
      errors.push(`CI duplicado ${ci}; no se puede usar como email unico.`);
      continue;
    }

    if (!lastNamePrefix) {
      errors.push(`Usuario ${user.id} (${user.email}) no tiene primer apellido.`);
      continue;
    }

    updates.push({
      id: user.id,
      currentEmail: user.email,
      nextEmail: ci,
      nextPassword: `${lastNamePrefix}${ci}`,
    });
  }

  if (errors.length > 0) {
    console.error("No se puede migrar hasta corregir estos datos:");
    for (const error of [...new Set(errors)]) {
      console.error(`- ${error}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log(
    APPLY_CHANGES
      ? "Aplicando cambios de login..."
      : "Simulacion: no se escribira nada. Usa --apply para aplicar.",
  );
  console.log(
    INCLUDE_ADMINS
      ? "Incluye usuarios ADMIN."
      : "Usuarios ADMIN omitidos. Usa --include-admins para incluirlos.",
  );
  console.table(
    updates.map((update) => ({
      id: update.id,
      email_actual: update.currentEmail,
      email_nuevo: update.nextEmail,
      password_nuevo: update.nextPassword,
    })),
  );

  if (!APPLY_CHANGES) {
    return;
  }

  await prisma.$transaction(
    updates.map((update) =>
      prisma.usuarios.update({
        where: { id: update.id },
        data: {
          email: update.nextEmail,
          password_hash: hashPassword(update.nextPassword),
          updated_at: new Date(),
        },
      }),
    ),
  );

  console.log(`Usuarios actualizados: ${updates.length}`);
}

function normalizeCi(value: string | null) {
  return value?.trim().replace(/\s+/g, "") ?? "";
}

function buildLastNamePrefix(value: string | null) {
  const normalized = value
    ?.trim()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z]/g, "")
    .toLowerCase() ?? "";

  return normalized.length >= 3 ? normalized.slice(0, 3) : normalized;
}

function hashPassword(password: string) {
  const salt = randomBytes(16).toString("hex");
  const derivedKey = scryptSync(password, salt, 64).toString("hex");

  return `scrypt:${salt}:${derivedKey}`;
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
