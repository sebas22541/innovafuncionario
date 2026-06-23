CREATE TABLE IF NOT EXISTS "almuerzos" (
  "id" SERIAL NOT NULL,
  "usuario_id" INTEGER NOT NULL,
  "fecha" DATE NOT NULL,
  "hora_salida" VARCHAR(5) NOT NULL,
  "salida_en" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "hora_retorno" VARCHAR(5),
  "retorno_en" TIMESTAMPTZ(6),
  "registrado_salida_por_id" INTEGER,
  "registrado_retorno_por_id" INTEGER,
  "qr_leido" TEXT,
  "datos_qr_snapshot" JSONB,
  "funcionario_nombre_completo" VARCHAR(220) NOT NULL,
  "funcionario_ci" VARCHAR(30),
  "funcionario_numero_item" VARCHAR(50),
  "funcionario_cargo" VARCHAR(120),
  "funcionario_oficina_id" INTEGER,
  "funcionario_oficina" VARCHAR(150),
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "almuerzos_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "idx_almuerzos_fecha"
  ON "almuerzos" ("fecha");

CREATE INDEX IF NOT EXISTS "idx_almuerzos_usuario_id"
  ON "almuerzos" ("usuario_id");

CREATE INDEX IF NOT EXISTS "idx_almuerzos_funcionario_ci"
  ON "almuerzos" ("funcionario_ci");

CREATE INDEX IF NOT EXISTS "idx_almuerzos_funcionario_oficina_id"
  ON "almuerzos" ("funcionario_oficina_id");

CREATE INDEX IF NOT EXISTS "idx_almuerzos_registrado_salida_por_id"
  ON "almuerzos" ("registrado_salida_por_id");

CREATE INDEX IF NOT EXISTS "idx_almuerzos_registrado_retorno_por_id"
  ON "almuerzos" ("registrado_retorno_por_id");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'almuerzos_usuario_id_fkey'
  ) THEN
    ALTER TABLE "almuerzos"
      ADD CONSTRAINT "almuerzos_usuario_id_fkey"
      FOREIGN KEY ("usuario_id") REFERENCES "usuarios" ("id")
      ON DELETE CASCADE ON UPDATE NO ACTION;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'almuerzos_registrado_salida_por_id_fkey'
  ) THEN
    ALTER TABLE "almuerzos"
      ADD CONSTRAINT "almuerzos_registrado_salida_por_id_fkey"
      FOREIGN KEY ("registrado_salida_por_id") REFERENCES "usuarios" ("id")
      ON UPDATE NO ACTION;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'almuerzos_registrado_retorno_por_id_fkey'
  ) THEN
    ALTER TABLE "almuerzos"
      ADD CONSTRAINT "almuerzos_registrado_retorno_por_id_fkey"
      FOREIGN KEY ("registrado_retorno_por_id") REFERENCES "usuarios" ("id")
      ON UPDATE NO ACTION;
  END IF;
END $$;

INSERT INTO "usuarios" (
  "nombre_completo",
  "nombres",
  "primer_apellido",
  "segundo_apellido",
  "tercer_apellido",
  "ci",
  "celular",
  "tipo_vinculo",
  "unidad",
  "oficina_id",
  "oficina_comision_id",
  "cargo_codigo",
  "cargo",
  "lugar",
  "numero_item",
  "foto_url",
  "email",
  "password_hash",
  "rol",
  "activo"
)
VALUES
  (
    'Control Almuerzo 1',
    'Control Almuerzo',
    'Punto 1',
    'Tecnico',
    NULL,
    'ALM001',
    '00000001',
    'ITEM',
    'Control de almuerzo',
    NULL,
    NULL,
    NULL,
    'Control de almuerzo',
    'Punto 1',
    'ALM001',
    NULL,
    'alm001',
    'scrypt:458d43c75cc7e00691c1d68c164c0892:2f0bdca98a402901b7cc988c5822cc9c2d12f869be5c746e8c1e0dbf8e5bcda4b1c110c08bfe05bc3ed6c1cf5bf307b0f340d47043f87c332eca4057bd0c8e98',
    'ALMUERZO',
    TRUE
  ),
  (
    'Control Almuerzo 2',
    'Control Almuerzo',
    'Punto 2',
    'Tecnico',
    NULL,
    'ALM002',
    '00000002',
    'ITEM',
    'Control de almuerzo',
    NULL,
    NULL,
    NULL,
    'Control de almuerzo',
    'Punto 2',
    'ALM002',
    NULL,
    'alm002',
    'scrypt:def0104b3169de0e1f671308b85db8ac:664502a39f53ac84e9c0cff7170634dbbdf2d0e6b88efcba65f82818c446cdd093118ba711d983dee3db5387fbaa0e7414d0f7da649ea1b4cb5d5e3a272756f2',
    'ALMUERZO',
    TRUE
  ),
  (
    'Control Almuerzo 3',
    'Control Almuerzo',
    'Punto 3',
    'Tecnico',
    NULL,
    'ALM003',
    '00000003',
    'ITEM',
    'Control de almuerzo',
    NULL,
    NULL,
    NULL,
    'Control de almuerzo',
    'Punto 3',
    'ALM003',
    NULL,
    'alm003',
    'scrypt:51cf81e7bc46340d3b84f25d3e3fbe42:0361d882bbd0069e5fec26096a4fab6f69e5d8be14208deaa33f329eab7ed6b4603c47b5a141137fb78f0aed1077adfee62f58d7daab96d9038307d75432e1bd',
    'ALMUERZO',
    TRUE
  ),
  (
    'Control Almuerzo 4',
    'Control Almuerzo',
    'Punto 4',
    'Tecnico',
    NULL,
    'ALM004',
    '00000004',
    'ITEM',
    'Control de almuerzo',
    NULL,
    NULL,
    NULL,
    'Control de almuerzo',
    'Punto 4',
    'ALM004',
    NULL,
    'alm004',
    'scrypt:96b466eae4d73a22929c9b6ebb216b02:f9f7c0f4027bdd3d8073dcb9d00021c251e16f9ab080d236764cb163c01ddb3406b50c711084c5fda9515ce602a3235164b0ae95642f3d940dcf98a083179e19',
    'ALMUERZO',
    TRUE
  ),
  (
    'Control Almuerzo 5',
    'Control Almuerzo',
    'Punto 5',
    'Tecnico',
    NULL,
    'ALM005',
    '00000005',
    'ITEM',
    'Control de almuerzo',
    NULL,
    NULL,
    NULL,
    'Control de almuerzo',
    'Punto 5',
    'ALM005',
    NULL,
    'alm005',
    'scrypt:ca2b0635a4c8f9e7d2ec736d4a13bee0:769d4b9c33b3343fd0e3a3c808a275ca39f1f36bd3f6b905f54f1acdc35e3a146083f67b1c28adb0429f07085846c69e06abcc7efa1c8c0d7c85b016b10b4c8e',
    'ALMUERZO',
    TRUE
  )
ON CONFLICT ("email") DO UPDATE SET
  "nombre_completo" = EXCLUDED."nombre_completo",
  "nombres" = EXCLUDED."nombres",
  "primer_apellido" = EXCLUDED."primer_apellido",
  "segundo_apellido" = EXCLUDED."segundo_apellido",
  "ci" = EXCLUDED."ci",
  "celular" = EXCLUDED."celular",
  "tipo_vinculo" = EXCLUDED."tipo_vinculo",
  "unidad" = EXCLUDED."unidad",
  "cargo" = EXCLUDED."cargo",
  "lugar" = EXCLUDED."lugar",
  "numero_item" = EXCLUDED."numero_item",
  "rol" = EXCLUDED."rol",
  "activo" = TRUE,
  "updated_at" = CURRENT_TIMESTAMP;
