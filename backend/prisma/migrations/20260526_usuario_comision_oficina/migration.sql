ALTER TABLE "usuarios"
  ADD COLUMN IF NOT EXISTS "oficina_comision_id" INTEGER;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'usuarios_oficina_comision_id_fkey'
  ) THEN
    ALTER TABLE "usuarios"
      ADD CONSTRAINT "usuarios_oficina_comision_id_fkey"
      FOREIGN KEY ("oficina_comision_id")
      REFERENCES "oficinas" ("id")
      ON DELETE SET NULL
      ON UPDATE NO ACTION;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "idx_usuarios_oficina_comision_id"
  ON "usuarios" ("oficina_comision_id");
