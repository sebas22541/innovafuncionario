DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'personas' AND column_name = 'usuario_id'
  ) THEN
    ALTER TABLE "personas"
    ADD COLUMN "usuario_id" INTEGER;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = current_schema()
      AND indexname = 'personas_usuario_id_key'
  ) THEN
    CREATE UNIQUE INDEX "personas_usuario_id_key"
    ON "personas"("usuario_id");
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'personas_usuario_id_fkey'
  ) THEN
    ALTER TABLE "personas"
    ADD CONSTRAINT "personas_usuario_id_fkey"
    FOREIGN KEY ("usuario_id")
    REFERENCES "usuarios"("id")
    ON DELETE SET NULL
    ON UPDATE NO ACTION;
  END IF;
END $$;
