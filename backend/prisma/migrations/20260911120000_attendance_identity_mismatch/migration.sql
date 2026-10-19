ALTER TABLE "asistencia_controles"
ADD COLUMN IF NOT EXISTS "no_es_persona" BOOLEAN NOT NULL DEFAULT false;
