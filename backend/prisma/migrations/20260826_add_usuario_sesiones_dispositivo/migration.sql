CREATE TABLE IF NOT EXISTS "usuario_sesiones_dispositivo" (
  "id" SERIAL PRIMARY KEY,
  "usuario_id" INTEGER NOT NULL,
  "device_id" VARCHAR(120) NOT NULL,
  "last_login_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "revoked_at" TIMESTAMPTZ(6),
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "usuario_sesiones_dispositivo_usuario_id_fkey"
    FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "usuario_sesiones_dispositivo_usuario_device_key"
    UNIQUE ("usuario_id", "device_id")
);

CREATE INDEX IF NOT EXISTS "idx_usuario_sesiones_dispositivo_usuario"
  ON "usuario_sesiones_dispositivo" ("usuario_id", "last_login_at" DESC);

CREATE INDEX IF NOT EXISTS "idx_usuario_sesiones_dispositivo_device"
  ON "usuario_sesiones_dispositivo" ("usuario_id", "device_id");
