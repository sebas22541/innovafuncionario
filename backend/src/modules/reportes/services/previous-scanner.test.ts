import { test } from "node:test";
import { strict as assert } from "node:assert";
import { previousScannerReferences, scannerDisplayName } from "./previous-scanner.ts";

test("scanner label uses the first given name and the first surname", () => {
  assert.equal(scannerDisplayName({nombres: " Maria Elena ", primer_apellido: "Perez"}), "Maria Perez");
  assert.equal(scannerDisplayName({nombre_completo: "Juan Carlos", primer_apellido: "De la Cruz"}), "Juan De la Cruz");
  assert.equal(scannerDisplayName({nombres: "Luis", primer_apellido: null}), "Luis");
});

test("uses the preceding real scanner on the same Bolivia date", () => {
  const scan = (id: number, time: string, name = "", email = "admin@admin.com") => ({
    id, registradoEn: time, registradoPorNombre: name, registradoPorEmail: email,
  });
  const records = [
    scan(1, "2026-09-17T03:59:00Z", "Yesterday", "y@example.com"),
    scan(2, "2026-09-17T04:00:00Z"),
    scan(3, "2026-09-17T12:00:00Z", "Ana", "ana@example.com"),
    scan(4, "2026-09-17T12:01:00Z"),
    scan(5, "2026-09-17T12:02:00Z"),
    scan(6, "2026-09-17T12:03:00Z", "Luis", "luis@example.com"),
    scan(7, "2026-09-17T12:04:00Z"),
    scan(8, "2026-09-18T04:00:00Z"),
  ];
  const references = previousScannerReferences([...records].reverse());
  assert.deepEqual([...references], [[4, "Ana"], [5, "Ana"], [7, "Luis"]]);
  assert.equal(records[3].registradoPorEmail, "admin@admin.com");
  assert.equal(previousScannerReferences([records[3]]).size, 0);
});

test("does not infer an order from simultaneous scans", () => {
  assert.equal(previousScannerReferences([
    {id: 1, registradoEn: "2026-09-17T12:00:00Z", registradoPorEmail: "a@a.com", registradoPorNombre: "Ana"},
    {id: 2, registradoEn: "2026-09-17T12:00:00Z", registradoPorEmail: "admin@admin.com"},
  ]).size, 0);
});
