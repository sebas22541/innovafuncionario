CREATE TABLE IF NOT EXISTS "evento_controles" (
  "id" SERIAL NOT NULL,
  "evento_id" INTEGER NOT NULL,
  "nombre" VARCHAR(120) NOT NULL,
  "orden" INTEGER NOT NULL,
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "evento_controles_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "evento_controles_evento_id_fkey"
    FOREIGN KEY ("evento_id") REFERENCES "eventos" ("id")
    ON DELETE CASCADE ON UPDATE NO ACTION
);

CREATE UNIQUE INDEX IF NOT EXISTS "evento_controles_evento_id_orden_key"
  ON "evento_controles" ("evento_id", "orden");

CREATE INDEX IF NOT EXISTS "idx_evento_controles_evento_id"
  ON "evento_controles" ("evento_id");

CREATE TABLE IF NOT EXISTS "asistencia_controles" (
  "id" SERIAL NOT NULL,
  "asistencia_id" INTEGER NOT NULL,
  "control_id" INTEGER NOT NULL,
  "estado" "estado_asistencia" NOT NULL DEFAULT 'ASISTIO',
  "observacion" TEXT,
  "registrado_por_id" INTEGER,
  "registrado_en" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "asistencia_controles_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "asistencia_controles_asistencia_id_fkey"
    FOREIGN KEY ("asistencia_id") REFERENCES "asistencias" ("id")
    ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT "asistencia_controles_control_id_fkey"
    FOREIGN KEY ("control_id") REFERENCES "evento_controles" ("id")
    ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT "asistencia_controles_registrado_por_id_fkey"
    FOREIGN KEY ("registrado_por_id") REFERENCES "usuarios" ("id")
    ON DELETE SET NULL ON UPDATE NO ACTION
);

CREATE UNIQUE INDEX IF NOT EXISTS "asistencia_controles_asistencia_id_control_id_key"
  ON "asistencia_controles" ("asistencia_id", "control_id");

CREATE INDEX IF NOT EXISTS "idx_asistencia_controles_control_id"
  ON "asistencia_controles" ("control_id");

CREATE INDEX IF NOT EXISTS "idx_asistencia_controles_registrado_por_id"
  ON "asistencia_controles" ("registrado_por_id");

INSERT INTO "evento_controles" ("evento_id", "nombre", "orden")
SELECT e."id", 'Primer control', 1
FROM "eventos" e
WHERE NOT EXISTS (
  SELECT 1
  FROM "evento_controles" c
  WHERE c."evento_id" = e."id"
);

INSERT INTO "asistencia_controles" (
  "asistencia_id",
  "control_id",
  "estado",
  "observacion",
  "registrado_por_id",
  "registrado_en"
)
SELECT
  a."id",
  c."id",
  a."estado",
  a."observacion",
  a."registrado_por_id",
  a."registrado_en"
FROM "asistencias" a
INNER JOIN "evento_controles" c
  ON c."evento_id" = a."evento_id"
 AND c."orden" = 1
WHERE NOT EXISTS (
  SELECT 1
  FROM "asistencia_controles" ac
  WHERE ac."asistencia_id" = a."id"
    AND ac."control_id" = c."id"
);
