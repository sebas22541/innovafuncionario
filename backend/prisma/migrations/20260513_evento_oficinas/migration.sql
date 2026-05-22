CREATE TABLE IF NOT EXISTS "evento_oficinas" (
  "evento_id" INTEGER NOT NULL,
  "oficina_id" INTEGER NOT NULL,
  "seleccion_directa" BOOLEAN NOT NULL DEFAULT false,

  CONSTRAINT "evento_oficinas_pkey" PRIMARY KEY ("evento_id", "oficina_id"),
  CONSTRAINT "evento_oficinas_evento_id_fkey"
    FOREIGN KEY ("evento_id")
    REFERENCES "eventos" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "evento_oficinas_oficina_id_fkey"
    FOREIGN KEY ("oficina_id")
    REFERENCES "oficinas" ("id")
    ON DELETE RESTRICT
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_evento_oficinas_oficina_id"
  ON "evento_oficinas" ("oficina_id");
