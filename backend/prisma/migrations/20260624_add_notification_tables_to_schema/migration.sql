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

CREATE TABLE IF NOT EXISTS "notificacion_envios" (
  "id" SERIAL PRIMARY KEY,
  "enviado_por_id" INTEGER NOT NULL,
  "titulo" VARCHAR(120) NOT NULL,
  "cuerpo" TEXT NOT NULL,
  "filtros" JSONB NOT NULL DEFAULT '{}'::jsonb,
  "destinatarios_solicitados" INTEGER NOT NULL DEFAULT 0,
  "enviados" INTEGER NOT NULL DEFAULT 0,
  "fallidos" INTEGER NOT NULL DEFAULT 0,
  "tokens_invalidos_removidos" INTEGER NOT NULL DEFAULT 0,
  "mensaje_resultado" TEXT,
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "notificacion_envios_enviado_por_id_fkey"
    FOREIGN KEY ("enviado_por_id") REFERENCES "usuarios" ("id")
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_notificacion_envios_created"
  ON "notificacion_envios" ("created_at" DESC, "id" DESC);
