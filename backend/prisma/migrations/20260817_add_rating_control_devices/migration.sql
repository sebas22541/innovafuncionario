ALTER TABLE "calificaciones_funcionario"
  ADD COLUMN IF NOT EXISTS "device_id_public" VARCHAR(220);

CREATE TABLE IF NOT EXISTS "calificacion_device_bloqueos" (
  "id" SERIAL PRIMARY KEY,
  "device_id_hash" VARCHAR(64) NOT NULL UNIQUE,
  "device_id_public" VARCHAR(220),
  "motivo" TEXT,
  "bloqueado_por_id" INTEGER,
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "calificacion_device_bloqueos_bloqueado_por_id_fkey"
    FOREIGN KEY ("bloqueado_por_id") REFERENCES "usuarios" ("id")
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_calificacion_device_bloqueos_created"
  ON "calificacion_device_bloqueos" ("created_at" DESC);

CREATE INDEX IF NOT EXISTS "idx_calificaciones_funcionario_device_funcionario"
  ON "calificaciones_funcionario" ("device_id_hash", "funcionario_id");
