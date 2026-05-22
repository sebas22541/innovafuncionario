CREATE TABLE IF NOT EXISTS "cargos" (
  "codigo" VARCHAR(50) NOT NULL,
  "cargo" VARCHAR(150) NOT NULL,

  CONSTRAINT "cargos_pkey" PRIMARY KEY ("codigo")
);

CREATE INDEX IF NOT EXISTS "idx_cargos_cargo"
  ON "cargos" ("cargo");

ALTER TABLE "usuarios"
  ADD COLUMN IF NOT EXISTS "cargo_codigo" VARCHAR(50);

CREATE INDEX IF NOT EXISTS "idx_usuarios_cargo_codigo"
  ON "usuarios" ("cargo_codigo");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'usuarios_cargo_codigo_fkey'
  ) THEN
    ALTER TABLE "usuarios"
      ADD CONSTRAINT "usuarios_cargo_codigo_fkey"
      FOREIGN KEY ("cargo_codigo")
      REFERENCES "cargos" ("codigo")
      ON DELETE SET NULL
      ON UPDATE NO ACTION;
  END IF;
END $$;
