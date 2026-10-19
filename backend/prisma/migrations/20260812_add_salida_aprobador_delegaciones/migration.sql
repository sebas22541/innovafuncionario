CREATE TABLE IF NOT EXISTS "salida_aprobador_delegaciones" (
  "id" SERIAL PRIMARY KEY,
  "otorgante_id" INTEGER NOT NULL,
  "delegado_id" INTEGER NOT NULL,
  "creado_por_id" INTEGER NOT NULL,
  "activo" BOOLEAN NOT NULL DEFAULT TRUE,
  "revocado_por_id" INTEGER,
  "revocado_en" TIMESTAMPTZ(6),
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "salida_aprobador_delegaciones_otorgante_id_fkey"
    FOREIGN KEY ("otorgante_id") REFERENCES "usuarios" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "salida_aprobador_delegaciones_delegado_id_fkey"
    FOREIGN KEY ("delegado_id") REFERENCES "usuarios" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "salida_aprobador_delegaciones_creado_por_id_fkey"
    FOREIGN KEY ("creado_por_id") REFERENCES "usuarios" ("id")
    ON UPDATE NO ACTION,
  CONSTRAINT "salida_aprobador_delegaciones_otorgante_delegado_key"
    UNIQUE ("otorgante_id", "delegado_id")
);

CREATE INDEX IF NOT EXISTS "idx_salida_aprobador_delegaciones_delegado"
  ON "salida_aprobador_delegaciones" ("delegado_id", "activo");

CREATE INDEX IF NOT EXISTS "idx_salida_aprobador_delegaciones_otorgante"
  ON "salida_aprobador_delegaciones" ("otorgante_id", "activo");
