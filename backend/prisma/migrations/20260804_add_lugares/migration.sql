CREATE TABLE IF NOT EXISTS "lugares" (
  "id" SERIAL PRIMARY KEY,
  "oficina_id" INTEGER NOT NULL UNIQUE,
  "nombre" VARCHAR(150) NOT NULL,
  "latitud" DOUBLE PRECISION NOT NULL,
  "longitud" DOUBLE PRECISION NOT NULL,
  "radio_metros" INTEGER NOT NULL,
  "activo" BOOLEAN NOT NULL DEFAULT TRUE,
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "lugares_oficina_id_fkey"
    FOREIGN KEY ("oficina_id") REFERENCES "oficinas" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_lugares_activo"
  ON "lugares" ("activo");

CREATE INDEX IF NOT EXISTS "idx_lugares_oficina_id"
  ON "lugares" ("oficina_id");

CREATE TABLE IF NOT EXISTS "lugar_oficinas" (
  "lugar_id" INTEGER NOT NULL,
  "oficina_id" INTEGER NOT NULL,
  CONSTRAINT "lugar_oficinas_pkey" PRIMARY KEY ("lugar_id", "oficina_id"),
  CONSTRAINT "lugar_oficinas_lugar_id_fkey"
    FOREIGN KEY ("lugar_id") REFERENCES "lugares" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "lugar_oficinas_oficina_id_fkey"
    FOREIGN KEY ("oficina_id") REFERENCES "oficinas" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_lugar_oficinas_oficina_id"
  ON "lugar_oficinas" ("oficina_id");
