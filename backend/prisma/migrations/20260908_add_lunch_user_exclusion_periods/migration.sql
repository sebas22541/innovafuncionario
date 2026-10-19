CREATE TABLE IF NOT EXISTS "almuerzo_usuario_exclusiones" (
  "id" SERIAL PRIMARY KEY,
  "usuario_id" INTEGER NOT NULL,
  "activo_desde" DATE NOT NULL,
  "activo_hasta" DATE,
  "creado_por_id" INTEGER,
  "cerrado_por_id" INTEGER,
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "almuerzo_usuario_exclusiones_usuario_id_fkey"
    FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "almuerzo_usuario_exclusiones_creado_por_id_fkey"
    FOREIGN KEY ("creado_por_id") REFERENCES "usuarios" ("id")
    ON DELETE SET NULL
    ON UPDATE NO ACTION,
  CONSTRAINT "almuerzo_usuario_exclusiones_cerrado_por_id_fkey"
    FOREIGN KEY ("cerrado_por_id") REFERENCES "usuarios" ("id")
    ON DELETE SET NULL
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_almuerzo_usuario_exclusiones_usuario_fecha"
  ON "almuerzo_usuario_exclusiones" ("usuario_id", "activo_desde", "activo_hasta");

CREATE INDEX IF NOT EXISTS "idx_almuerzo_usuario_exclusiones_activo_hasta"
  ON "almuerzo_usuario_exclusiones" ("activo_hasta");
