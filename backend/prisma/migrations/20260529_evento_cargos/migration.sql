CREATE TABLE IF NOT EXISTS "evento_cargos" (
  "evento_id" INTEGER NOT NULL,
  "cargo_codigo" VARCHAR(50) NOT NULL,
  CONSTRAINT "evento_cargos_pkey" PRIMARY KEY ("evento_id", "cargo_codigo"),
  CONSTRAINT "evento_cargos_evento_id_fkey"
    FOREIGN KEY ("evento_id") REFERENCES "eventos" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "evento_cargos_cargo_codigo_fkey"
    FOREIGN KEY ("cargo_codigo") REFERENCES "cargos" ("codigo")
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_evento_cargos_cargo_codigo"
  ON "evento_cargos" ("cargo_codigo");
