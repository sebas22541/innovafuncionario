DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'estado_salida') THEN
    CREATE TYPE "estado_salida" AS ENUM ('PENDIENTE', 'APROBADO', 'RECHAZADO');
  END IF;
END $$;

ALTER TABLE "salidas"
  ADD COLUMN IF NOT EXISTS "estado" "estado_salida" NOT NULL DEFAULT 'PENDIENTE',
  ADD COLUMN IF NOT EXISTS "solicitante_oficina_id" INTEGER,
  ADD COLUMN IF NOT EXISTS "aprobado_por_id" INTEGER,
  ADD COLUMN IF NOT EXISTS "aprobado_por_nombre" VARCHAR(220),
  ADD COLUMN IF NOT EXISTS "aprobado_en" TIMESTAMPTZ(6);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'salidas_aprobado_por_id_fkey'
  ) THEN
    ALTER TABLE "salidas"
      ADD CONSTRAINT "salidas_aprobado_por_id_fkey"
      FOREIGN KEY ("aprobado_por_id")
      REFERENCES "usuarios" ("id")
      ON UPDATE NO ACTION;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "idx_salidas_estado" ON "salidas" ("estado");
CREATE INDEX IF NOT EXISTS "idx_salidas_solicitante_oficina_id" ON "salidas" ("solicitante_oficina_id");
CREATE INDEX IF NOT EXISTS "idx_salidas_aprobado_por_id" ON "salidas" ("aprobado_por_id");
