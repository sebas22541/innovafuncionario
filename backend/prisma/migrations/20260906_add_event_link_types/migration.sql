ALTER TABLE "eventos"
  ADD COLUMN IF NOT EXISTS "tipos_vinculo" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

CREATE INDEX IF NOT EXISTS "idx_eventos_tipos_vinculo"
  ON "eventos" USING GIN ("tipos_vinculo");
