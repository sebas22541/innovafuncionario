ALTER TABLE "usuarios"
  ADD COLUMN IF NOT EXISTS "subcargo_codigo" VARCHAR(50),
  ADD COLUMN IF NOT EXISTS "subcargo" VARCHAR(120);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'usuarios_subcargo_codigo_fkey'
  ) THEN
    ALTER TABLE "usuarios"
      ADD CONSTRAINT "usuarios_subcargo_codigo_fkey"
      FOREIGN KEY ("subcargo_codigo") REFERENCES "cargos" ("codigo")
      ON UPDATE NO ACTION;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "idx_usuarios_subcargo_codigo"
  ON "usuarios" ("subcargo_codigo");
