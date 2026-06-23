CREATE TABLE IF NOT EXISTS "celulares_asistencia" (
  "id" SERIAL PRIMARY KEY,
  "device_id" VARCHAR(120) NOT NULL UNIQUE,
  "usuario_id" INTEGER NOT NULL,
  "platform" VARCHAR(30) NOT NULL,
  "manufacturer" VARCHAR(120),
  "model" VARCHAR(160),
  "android_sdk" INTEGER,
  "battery_level" INTEGER,
  "is_charging" BOOLEAN,
  "brightness" INTEGER,
  "kiosk_enabled" BOOLEAN NOT NULL DEFAULT FALSE,
  "last_seen_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "logout_requested_at" TIMESTAMPTZ(6),
  "logout_requested_by_id" INTEGER,
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "celulares_asistencia_usuario_id_fkey"
    FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "celulares_asistencia_logout_requested_by_id_fkey"
    FOREIGN KEY ("logout_requested_by_id") REFERENCES "usuarios" ("id")
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_celulares_asistencia_usuario_id"
  ON "celulares_asistencia" ("usuario_id");

CREATE INDEX IF NOT EXISTS "idx_celulares_asistencia_last_seen"
  ON "celulares_asistencia" ("last_seen_at" DESC);
