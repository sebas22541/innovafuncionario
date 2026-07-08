CREATE TABLE IF NOT EXISTS "calificaciones_funcionario" (
  "id" SERIAL PRIMARY KEY,
  "funcionario_id" INTEGER NOT NULL,
  "fecha" DATE NOT NULL,
  "calificacion" VARCHAR(20) NOT NULL,
  "comentario" TEXT,
  "device_id_hash" VARCHAR(64) NOT NULL,
  "device_label" VARCHAR(255),
  "user_agent" TEXT,
  "ip_hash" VARCHAR(64),
  "funcionario_nombre_completo" VARCHAR(220) NOT NULL,
  "funcionario_ci" VARCHAR(30),
  "funcionario_cargo" VARCHAR(120),
  "funcionario_oficina_id" INTEGER,
  "funcionario_oficina" VARCHAR(150),
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "calificaciones_funcionario_funcionario_id_fkey"
    FOREIGN KEY ("funcionario_id") REFERENCES "usuarios" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "calificaciones_funcionario_funcionario_fecha_device_key"
    UNIQUE ("funcionario_id", "fecha", "device_id_hash")
);

CREATE INDEX IF NOT EXISTS "idx_calificaciones_funcionario_fecha"
  ON "calificaciones_funcionario" ("fecha");

CREATE INDEX IF NOT EXISTS "idx_calificaciones_funcionario_funcionario_fecha"
  ON "calificaciones_funcionario" ("funcionario_id", "fecha");

CREATE INDEX IF NOT EXISTS "idx_calificaciones_funcionario_calificacion"
  ON "calificaciones_funcionario" ("calificacion");
