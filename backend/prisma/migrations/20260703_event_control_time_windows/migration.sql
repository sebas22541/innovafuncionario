ALTER TABLE "evento_controles"
  ADD COLUMN IF NOT EXISTS "hora_inicio" VARCHAR(5),
  ADD COLUMN IF NOT EXISTS "hora_fin" VARCHAR(5);

ALTER TABLE "evento_controles"
  ADD CONSTRAINT "evento_controles_horas_validas_check"
  CHECK (
    ("hora_inicio" IS NULL AND "hora_fin" IS NULL)
    OR (
      "hora_inicio" ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      AND "hora_fin" ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      AND "hora_inicio" < "hora_fin"
    )
  );
