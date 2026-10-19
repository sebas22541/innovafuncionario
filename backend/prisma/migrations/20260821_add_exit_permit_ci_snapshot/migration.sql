ALTER TABLE "salidas"
  ADD COLUMN IF NOT EXISTS "solicitante_ci" VARCHAR(30);

UPDATE "salidas" s
SET "solicitante_ci" = u."ci"
FROM "usuarios" u
WHERE s."usuario_id" = u."id"
  AND s."solicitante_ci" IS NULL;

CREATE INDEX IF NOT EXISTS "idx_salidas_solicitante_ci"
  ON "salidas" ("solicitante_ci");
