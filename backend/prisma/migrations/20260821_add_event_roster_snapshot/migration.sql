CREATE TABLE IF NOT EXISTS "evento_personas_snapshot" (
  "evento_id" INTEGER NOT NULL,
  "persona_id" INTEGER NOT NULL,
  "usuario_id" INTEGER,
  "nombre_snapshot" VARCHAR(150) NOT NULL,
  "ci_snapshot" VARCHAR(30),
  "cargo_snapshot" VARCHAR(150),
  "oficina_id_snapshot" INTEGER,
  "oficina_snapshot" VARCHAR(180),
  "oficina_cod_snapshot" VARCHAR(50),
  "motivo_registro" VARCHAR(80),
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "evento_personas_snapshot_pkey" PRIMARY KEY ("evento_id", "persona_id"),
  CONSTRAINT "evento_personas_snapshot_evento_id_fkey"
    FOREIGN KEY ("evento_id") REFERENCES "eventos" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "evento_personas_snapshot_persona_id_fkey"
    FOREIGN KEY ("persona_id") REFERENCES "personas" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_evento_personas_snapshot_evento_id"
  ON "evento_personas_snapshot" ("evento_id");

CREATE INDEX IF NOT EXISTS "idx_evento_personas_snapshot_persona_id"
  ON "evento_personas_snapshot" ("persona_id");
