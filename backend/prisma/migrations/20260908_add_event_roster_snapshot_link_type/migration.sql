ALTER TABLE "evento_personas_snapshot"
  ADD COLUMN IF NOT EXISTS "tipo_vinculo_snapshot" VARCHAR(30);

UPDATE "evento_personas_snapshot" eps
SET "tipo_vinculo_snapshot" = COALESCE(eps."tipo_vinculo_snapshot", u."tipo_vinculo")
FROM "personas" p, "usuarios" u
WHERE p."id" = eps."persona_id"
  AND u."id" = COALESCE(eps."usuario_id", p."usuario_id")
  AND eps."tipo_vinculo_snapshot" IS NULL
  AND u."tipo_vinculo" IS NOT NULL;
