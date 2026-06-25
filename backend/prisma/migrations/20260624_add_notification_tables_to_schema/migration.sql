CREATE TABLE IF NOT EXISTS "notificaciones" (
  "id" SERIAL PRIMARY KEY,
  "usuario_id" INTEGER NOT NULL,
  "tipo" VARCHAR(60) NOT NULL,
  "titulo" VARCHAR(180) NOT NULL,
  "cuerpo" TEXT NOT NULL,
  "destino_seccion" VARCHAR(80),
  "salida_id" INTEGER,
  "leida_en" TIMESTAMPTZ(6),
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "notificaciones_usuario_id_fkey"
    FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_notificaciones_usuario_created"
  ON "notificaciones" ("usuario_id", "created_at" DESC);

CREATE INDEX IF NOT EXISTS "idx_notificaciones_usuario_leida"
  ON "notificaciones" ("usuario_id", "leida_en");
