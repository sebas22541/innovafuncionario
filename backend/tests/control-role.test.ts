import assert from "node:assert/strict";
import test from "node:test";
import { buildControlRoleAssignment, normalizeControlPeriod } from "../src/control-role.ts";

const start = new Date("2026-09-12T12:00:00Z");
const end = new Date("2026-09-12T20:00:00Z");
const temporary = { rol: "CONTROL" as const, controlTemporal: true, controlInicio: start, controlFin: end };

test("both boundaries use the selected minute at :00 in Bolivia time", () => {
  const period = normalizeControlPeriod(new Date('2026-09-12T14:00:45-04:00'), new Date('2026-09-12T15:00:00-04:00'));
  assert.equal(period.controlInicio.toISOString(), '2026-09-12T18:00:00.000Z');
  assert.equal(period.controlFin.toISOString(), '2026-09-12T19:00:00.000Z');
});

test("the same selected minute is not expanded into a valid range", () => {
  const period = normalizeControlPeriod(start, start);
  assert.equal(period.controlFin.getTime(), period.controlInicio.getTime());
});

test("an existing permanent CONTROL returns to OPERADOR outside its new range", () => {
  const result = buildControlRoleAssignment(temporary, { rol: "CONTROL" }, start.getTime() - 1);
  assert.equal(result.rol, "OPERADOR");
  assert.equal(result.control_rol_anterior, "OPERADOR");
});

test("a previously broken CONTROL restoration is repaired when editing the range", () => {
  const result = buildControlRoleAssignment(temporary, { rol: "CONTROL", control_rol_anterior: "CONTROL" }, start.getTime());
  assert.equal(result.control_rol_anterior, "OPERADOR");
});

test("control is active just before the end and restores the original role at the end", () => {
  const existing = { rol: "CONTROL" as const, control_rol_anterior: "CREDENCIALES" as const };
  assert.equal(buildControlRoleAssignment(temporary, existing, end.getTime() - 1).rol, "CONTROL");
  assert.deepEqual(buildControlRoleAssignment(temporary, existing, end.getTime()), {
    rol: "CREDENCIALES", control_rol_anterior: null, control_inicio: null, control_fin: null,
  });
  assert.equal(buildControlRoleAssignment(temporary, existing, end.getTime() + 120000).rol, "CREDENCIALES");
});

test("scheduled control keeps the original role until the start", () => {
  const result = buildControlRoleAssignment(temporary, { rol: "ADMIN_EVENTUALES" }, start.getTime() - 1);
  assert.equal(result.rol, "ADMIN_EVENTUALES");
  assert.equal(result.control_rol_anterior, "ADMIN_EVENTUALES");
  assert.equal(result.control_fin, end);
});

test("control starts at the selected instant and preserves the restoration role", () => {
  const result = buildControlRoleAssignment(temporary, { rol: "CREDENCIALES" }, start.getTime());
  assert.equal(result.rol, "CONTROL");
  assert.equal(result.control_rol_anterior, "CREDENCIALES");
});

test("extending a temporary control retains the original role", () => {
  const result = buildControlRoleAssignment(temporary, { rol: "CONTROL", control_rol_anterior: "OPERADOR" }, start.getTime());
  assert.equal(result.control_rol_anterior, "OPERADOR");
});

test("indefinite control clears its previous schedule", () => {
  const result = buildControlRoleAssignment({ ...temporary, controlTemporal: false }, { rol: "CONTROL", control_rol_anterior: "OPERADOR" });
  assert.deepEqual(result, { rol: "CONTROL", control_rol_anterior: null, control_inicio: null, control_fin: null });
});

test("a manual role change cancels the scheduled restoration", () => {
  const result = buildControlRoleAssignment({ ...temporary, rol: "KARDEX", controlTemporal: false }, { rol: "CONTROL", control_rol_anterior: "OPERADOR" });
  assert.equal(result.rol, "KARDEX");
  assert.equal(result.control_fin, null);
});

test("older clients editing other fields do not erase the schedule", () => {
  assert.deepEqual(buildControlRoleAssignment({ ...temporary, controlTemporal: null }, { rol: "CONTROL", control_rol_anterior: "OPERADOR" }), { rol: "CONTROL" });
});
