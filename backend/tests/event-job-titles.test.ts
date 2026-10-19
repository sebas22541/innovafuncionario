import assert from "node:assert/strict";
import test from "node:test";
import { matchesCargoSelection } from "../src/event-job-titles.ts";

const codes = new Set(["DEPTO"]);
const names = new Set(["JEFE DE DEPARTAMENTO"]);

test("department-only events exclude division chiefs in live and saved rosters", () => {
  for (const code of ["DIVISION", null]) {
    assert.equal(matchesCargoSelection([
      { code, name: "JEFE DE DIVISION" },
    ], codes, names), false);
  }
  assert.equal(matchesCargoSelection([
    { code: "DEPTO", name: "JEFE DE DEPARTAMENTO" },
  ], codes, names), true);
  // Historical rosters store the name without a job code.
  assert.equal(matchesCargoSelection([
    { code: null, name: "JEFE DE DEPARTAMENTO" },
  ], codes, names), true);
});

test("job groups and partial names cannot broaden the selected jobs", () => {
  for (const name of ["JEFE", "JEFE DE DEPARTAMENTO ADJUNTO", "DIRECTOR", "TECNICO"]) {
    assert.equal(matchesCargoSelection([{ code: null, name }], codes, names), false);
  }
  assert.equal(matchesCargoSelection([{ code: null, name: "ADMINISTRATIVO" }],
    new Set(), new Set(["TECNICO"])), false);
});

test("exact codes, multiple selections and empty selections", () => {
  assert.equal(matchesCargoSelection([{ code: "DEPTO", name: null }], codes, names), true);
  assert.equal(matchesCargoSelection([{ code: "DIVISION", name: "JEFE DE DIVISION" }],
    new Set(["DEPTO", "DIVISION"]), names), true);
  assert.equal(matchesCargoSelection([{ code: "DEPTO", name: "JEFE DE DEPARTAMENTO" }],
    new Set(), new Set()), false);
  assert.equal(matchesCargoSelection([], codes, names), false);
});
