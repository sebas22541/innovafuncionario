ALTER TABLE "asistencia_controles"
  ADD COLUMN IF NOT EXISTS "retrasado" BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS "idx_asistencia_controles_retrasado"
  ON "asistencia_controles" ("retrasado");
