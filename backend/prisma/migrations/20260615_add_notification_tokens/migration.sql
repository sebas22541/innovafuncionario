CREATE TABLE IF NOT EXISTS "notificacion_tokens" (
  "id" SERIAL PRIMARY KEY,
  "usuario_id" INTEGER NOT NULL,
  "token" TEXT NOT NULL UNIQUE,
  "platform" VARCHAR(20) NOT NULL,
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "notificacion_tokens_usuario_id_fkey"
    FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_notificacion_tokens_usuario_id"
  ON "notificacion_tokens" ("usuario_id");
