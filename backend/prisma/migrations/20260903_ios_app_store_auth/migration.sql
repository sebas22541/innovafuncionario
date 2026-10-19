ALTER TABLE "usuarios"
  ADD COLUMN IF NOT EXISTS "apple_sub" VARCHAR(255),
  ADD COLUMN IF NOT EXISTS "apple_refresh_token" TEXT,
  ADD COLUMN IF NOT EXISTS "account_deleted_at" TIMESTAMPTZ(6);

CREATE UNIQUE INDEX IF NOT EXISTS "usuarios_apple_sub_key"
  ON "usuarios"("apple_sub")
  WHERE "apple_sub" IS NOT NULL;
