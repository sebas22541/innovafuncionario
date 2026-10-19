import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "../src/generated/prisma/client.ts";
import { controlPeriodUtcSchemaSql } from "../src/control-period-schema.ts";
import { createDatabasePool } from "../src/database-pool.ts";

const connectionString = process.env.CONTROL_ROLE_TEST_DATABASE_URL;
const userId = Number(process.env.CONTROL_ROLE_TEST_USER_ID);

test("Prisma stores control boundaries as real UTC instants and preserves the previous role", {
  skip: !connectionString || !userId,
}, async () => {
  const pool = createDatabasePool({ connectionString, connectionTimeoutMillis: 8000 });
  const prisma = new PrismaClient({ adapter: new PrismaPg(pool) });
  const rollback = new Error("Intentional rollback: do not change the test user");
  try {
    await assert.rejects(prisma.$transaction(async tx => {
      const before = await tx.$queryRaw<Array<{ timezone: string }>>`SELECT current_setting('TimeZone') AS timezone`;
      await tx.$executeRawUnsafe(controlPeriodUtcSchemaSql);
      const start = new Date("2026-09-12T21:08:00-04:00");
      const end = new Date("2026-09-12T21:15:00-04:00");
      await tx.usuarios.update({ where: { id: userId }, data: {
        rol: "ADMIN_EVENTUALES", control_rol_anterior: "ADMIN_EVENTUALES",
        control_inicio: start, control_fin: end,
      } });
      // Do not verify only Prisma DateTime reads: the old adapter conversion
      // masked the write offset. Read database epoch values independently.
      const rows = await tx.$queryRaw<Array<{ start_ms: number; end_ms: number; timezone: string }>>`
        SELECT EXTRACT(EPOCH FROM control_inicio)::double precision * 1000 AS start_ms,
          EXTRACT(EPOCH FROM control_fin)::double precision * 1000 AS end_ms,
          current_setting('TimeZone') AS timezone FROM usuarios WHERE id=${userId}`;
      assert.equal(rows[0]!.timezone, before[0]!.timezone);
      assert.equal(rows[0]!.start_ms, start.getTime());
      assert.equal(rows[0]!.end_ms, end.getTime());
      const user = await tx.usuarios.findUniqueOrThrow({ where: { id: userId } });
      assert.equal(user.control_inicio!.toISOString(), start.toISOString());
      assert.equal(user.control_fin!.toISOString(), end.toISOString());
      assert.equal(user.control_rol_anterior, "ADMIN_EVENTUALES");
      const source = readFileSync(new URL("../src/index.ts", import.meta.url), "utf8");
      const scheduler = source.slice(source.indexOf("async function refreshTemporaryControlRoles()"));
      const updateSql = scheduler.split("await pool.query(`")[1]!.split("`);")[0]!;
      for (const [instant, expected] of [
        ["2026-09-13T01:07:59Z", "ADMIN_EVENTUALES"],
        ["2026-09-13T01:08:00Z", "CONTROL"],
        ["2026-09-13T01:14:59Z", "CONTROL"],
        ["2026-09-13T01:15:00Z", "ADMIN_EVENTUALES"],
      ]) {
        const sql = updateSql.replaceAll("CURRENT_TIMESTAMP", `TIMESTAMPTZ '${instant}'`);
        await tx.$executeRawUnsafe(`${sql} AND "id" = $1`, userId);
        const current = await tx.usuarios.findUniqueOrThrow({ where: { id: userId } });
        assert.equal(current.rol, expected, instant);
      }
      throw rollback;
    }), error => error === rollback);
  } finally {
    await prisma.$disconnect();
    await pool.end();
  }
});
