ALTER TABLE "lugares"
  ALTER COLUMN "oficina_id" DROP NOT NULL;

DROP INDEX IF EXISTS "lugares_oficina_id_key";

CREATE TABLE IF NOT EXISTS "lugar_usuario_exclusiones" (
  "lugar_id" INTEGER NOT NULL,
  "usuario_id" INTEGER NOT NULL,
  CONSTRAINT "lugar_usuario_exclusiones_pkey" PRIMARY KEY ("lugar_id", "usuario_id"),
  CONSTRAINT "lugar_usuario_exclusiones_lugar_id_fkey"
    FOREIGN KEY ("lugar_id") REFERENCES "lugares" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT "lugar_usuario_exclusiones_usuario_id_fkey"
    FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_lugar_usuario_exclusiones_usuario_id"
  ON "lugar_usuario_exclusiones" ("usuario_id");
