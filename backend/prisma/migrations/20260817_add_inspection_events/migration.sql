ALTER TABLE "eventos"
  ADD COLUMN IF NOT EXISTS "tipo" VARCHAR(20) NOT NULL DEFAULT 'EVENTO',
  ADD COLUMN IF NOT EXISTS "inspeccion_activa" BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE "eventos"
SET "tipo" = 'EVENTO'
WHERE "tipo" IS NULL OR TRIM("tipo") = '';

CREATE INDEX IF NOT EXISTS "idx_eventos_tipo_inspeccion_activa"
  ON "eventos" ("tipo", "inspeccion_activa");
