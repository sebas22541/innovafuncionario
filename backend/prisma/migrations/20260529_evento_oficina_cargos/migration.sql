CREATE TABLE IF NOT EXISTS "evento_oficina_cargos" (
  "evento_id" INTEGER NOT NULL,
  "oficina_id" INTEGER NOT NULL,
  "cargo_codigo" VARCHAR(50) NOT NULL,
  CONSTRAINT "evento_oficina_cargos_pkey"
    PRIMARY KEY ("evento_id", "oficina_id", "cargo_codigo"),
  CONSTRAINT "evento_oficina_cargos_evento_id_fkey"
    FOREIGN KEY ("evento_id") REFERENCES "eventos" ("id")
    ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT "evento_oficina_cargos_oficina_id_fkey"
    FOREIGN KEY ("oficina_id") REFERENCES "oficinas" ("id")
    ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT "evento_oficina_cargos_cargo_codigo_fkey"
    FOREIGN KEY ("cargo_codigo") REFERENCES "cargos" ("codigo")
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_evento_oficina_cargos_oficina_id"
  ON "evento_oficina_cargos" ("oficina_id");

CREATE INDEX IF NOT EXISTS "idx_evento_oficina_cargos_cargo_codigo"
  ON "evento_oficina_cargos" ("cargo_codigo");
