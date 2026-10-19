CREATE TABLE IF NOT EXISTS "inspeccion_falta_motivos" (
  "evento_id" INTEGER NOT NULL,
  "persona_id" INTEGER NOT NULL,
  "motivo" TEXT,
  "registrado_por_id" INTEGER,
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "inspeccion_falta_motivos_pkey" PRIMARY KEY ("evento_id", "persona_id"),
  CONSTRAINT "inspeccion_falta_motivos_evento_id_fkey"
    FOREIGN KEY ("evento_id") REFERENCES "eventos" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "inspeccion_falta_motivos_persona_id_fkey"
    FOREIGN KEY ("persona_id") REFERENCES "personas" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "inspeccion_falta_motivos_registrado_por_id_fkey"
    FOREIGN KEY ("registrado_por_id") REFERENCES "usuarios" ("id")
    ON DELETE SET NULL
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_inspeccion_falta_motivos_persona_id"
  ON "inspeccion_falta_motivos" ("persona_id");

CREATE INDEX IF NOT EXISTS "idx_inspeccion_falta_motivos_registrado_por_id"
  ON "inspeccion_falta_motivos" ("registrado_por_id");
