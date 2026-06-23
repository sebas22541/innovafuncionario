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
