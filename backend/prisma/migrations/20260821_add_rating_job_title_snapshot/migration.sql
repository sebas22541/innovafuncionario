ALTER TABLE "calificaciones_funcionario"
  ADD COLUMN IF NOT EXISTS "funcionario_cargo_codigo" VARCHAR(50);

UPDATE "calificaciones_funcionario" c
SET "funcionario_cargo_codigo" = COALESCE(u."subcargo_codigo", u."cargo_codigo")
FROM "usuarios" u
WHERE c."funcionario_id" = u."id"
  AND c."funcionario_cargo_codigo" IS NULL;

CREATE INDEX IF NOT EXISTS "idx_calificaciones_funcionario_cargo_codigo"
  ON "calificaciones_funcionario" ("funcionario_cargo_codigo");
