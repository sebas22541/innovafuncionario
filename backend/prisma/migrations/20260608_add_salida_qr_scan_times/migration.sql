ALTER TABLE "salidas"
  ALTER COLUMN "hora_inicio" DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS "salida_en" TIMESTAMPTZ(6),
  ADD COLUMN IF NOT EXISTS "llegada_en" TIMESTAMPTZ(6),
  ADD COLUMN IF NOT EXISTS "registrado_salida_por_id" INTEGER,
  ADD COLUMN IF NOT EXISTS "registrado_llegada_por_id" INTEGER,
  ADD COLUMN IF NOT EXISTS "qr_leido" TEXT,
  ADD COLUMN IF NOT EXISTS "datos_qr_snapshot" JSONB;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'salidas_registrado_salida_por_id_fkey'
  ) THEN
    ALTER TABLE "salidas"
      ADD CONSTRAINT "salidas_registrado_salida_por_id_fkey"
      FOREIGN KEY ("registrado_salida_por_id")
      REFERENCES "usuarios" ("id")
      ON UPDATE NO ACTION;
  END IF;
END $$
;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'salidas_registrado_llegada_por_id_fkey'
  ) THEN
    ALTER TABLE "salidas"
      ADD CONSTRAINT "salidas_registrado_llegada_por_id_fkey"
      FOREIGN KEY ("registrado_llegada_por_id")
      REFERENCES "usuarios" ("id")
      ON UPDATE NO ACTION;
  END IF;
END $$
;

CREATE INDEX IF NOT EXISTS "idx_salidas_registrado_salida_por_id"
  ON "salidas" ("registrado_salida_por_id");

CREATE INDEX IF NOT EXISTS "idx_salidas_registrado_llegada_por_id"
  ON "salidas" ("registrado_llegada_por_id");
