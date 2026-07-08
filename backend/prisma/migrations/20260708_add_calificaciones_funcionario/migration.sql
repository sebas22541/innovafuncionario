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

CREATE TABLE IF NOT EXISTS "calificacion_funcionario_qrs" (
  "id" SERIAL PRIMARY KEY,
  "funcionario_id" INTEGER NOT NULL UNIQUE,
  "token_hash" VARCHAR(64) NOT NULL,
  "activo" BOOLEAN NOT NULL DEFAULT TRUE,
  "generado_por_id" INTEGER,
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "calificacion_funcionario_qrs_funcionario_id_fkey"
    FOREIGN KEY ("funcionario_id") REFERENCES "usuarios" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "calificacion_funcionario_qrs_generado_por_id_fkey"
    FOREIGN KEY ("generado_por_id") REFERENCES "usuarios" ("id")
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_calificacion_funcionario_qrs_activo"
  ON "calificacion_funcionario_qrs" ("activo");

CREATE INDEX IF NOT EXISTS "idx_calificacion_funcionario_qrs_updated"
  ON "calificacion_funcionario_qrs" ("updated_at" DESC);
