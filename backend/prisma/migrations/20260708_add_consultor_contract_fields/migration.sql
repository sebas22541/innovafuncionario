ALTER TABLE "usuarios"
  ADD COLUMN IF NOT EXISTS "contrato_numero" VARCHAR(80),
  ADD COLUMN IF NOT EXISTS "contrato_inicio" DATE,
  ADD COLUMN IF NOT EXISTS "contrato_fin" DATE;

CREATE INDEX IF NOT EXISTS "idx_usuarios_contrato_fin"
  ON "usuarios" ("contrato_fin");
