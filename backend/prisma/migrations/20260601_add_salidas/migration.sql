DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'motivo_salida') THEN
    CREATE TYPE "motivo_salida" AS ENUM ('TRABAJO', 'PARTICULAR');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS "salidas" (
  "id" SERIAL PRIMARY KEY,
  "usuario_id" INTEGER NOT NULL,
  "motivo" "motivo_salida" NOT NULL,
  "lugar_destino" VARCHAR(255) NOT NULL,
  "descripcion" TEXT,
  "fecha_permiso" DATE NOT NULL,
  "hora_inicio" VARCHAR(5) NOT NULL,
  "hora_final" VARCHAR(5),
  "solicitante_nombre_completo" VARCHAR(220) NOT NULL,
  "solicitante_ci" VARCHAR(30),
  "solicitante_numero_item" VARCHAR(50),
  "solicitante_cargo" VARCHAR(120),
  "solicitante_oficina" VARCHAR(150),
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "salidas_usuario_id_fkey"
    FOREIGN KEY ("usuario_id")
    REFERENCES "usuarios" ("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION
);

CREATE INDEX IF NOT EXISTS "idx_salidas_fecha_permiso" ON "salidas" ("fecha_permiso");
CREATE INDEX IF NOT EXISTS "idx_salidas_usuario_id" ON "salidas" ("usuario_id");
