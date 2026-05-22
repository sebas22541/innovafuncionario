-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "estado_asistencia" AS ENUM ('ASISTIO', 'OBSERVADO');

-- CreateEnum
CREATE TYPE "estado_evento" AS ENUM ('ACTIVO', 'CERRADO', 'CANCELADO');

-- CreateEnum
CREATE TYPE "rol_usuario" AS ENUM ('ADMIN', 'CONTROL', 'OPERADOR');

-- CreateTable
CREATE TABLE "asistencias" (
    "id" SERIAL NOT NULL,
    "evento_id" INTEGER NOT NULL,
    "persona_id" INTEGER NOT NULL,
    "nombre_snapshot" VARCHAR(150) NOT NULL,
    "estado" "estado_asistencia" NOT NULL DEFAULT 'ASISTIO',
    "qr_leido" TEXT,
    "datos_qr_snapshot" JSONB,
    "observacion" TEXT,
    "registrado_por_id" INTEGER,
    "registrado_en" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "asistencias_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "departamentos" (
    "id" SERIAL NOT NULL,
    "nombre" VARCHAR(120) NOT NULL,
    "descripcion" TEXT,
    "activo" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "departamentos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "evento_departamentos" (
    "evento_id" INTEGER NOT NULL,
    "departamento_id" INTEGER NOT NULL,
    CONSTRAINT "evento_departamentos_pkey" PRIMARY KEY ("evento_id","departamento_id")
);

-- CreateTable
CREATE TABLE "eventos" (
    "id" SERIAL NOT NULL,
    "nombre" VARCHAR(150) NOT NULL,
    "fecha_evento" TIMESTAMPTZ(6) NOT NULL,
    "descripcion" TEXT,
    "direccion" VARCHAR(255),
    "latitud" DOUBLE PRECISION,
    "longitud" DOUBLE PRECISION,
    "oficina_ids_excluidos" INTEGER[] DEFAULT ARRAY[]::INTEGER[],
    "estado" "estado_evento" NOT NULL DEFAULT 'ACTIVO',
    "creado_por_id" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "eventos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oficinas" (
    "id" INTEGER NOT NULL,
    "oficina" VARCHAR(150) NOT NULL,
    "cod" VARCHAR(50) NOT NULL,
    "nivel" INTEGER NOT NULL,
    CONSTRAINT "oficinas_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cargos" (
    "codigo" VARCHAR(50) NOT NULL,
    "cargo" VARCHAR(150) NOT NULL,
    CONSTRAINT "cargos_pkey" PRIMARY KEY ("codigo")
);

-- CreateTable
CREATE TABLE "evento_oficinas" (
    "evento_id" INTEGER NOT NULL,
    "oficina_id" INTEGER NOT NULL,
    "seleccion_directa" BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT "evento_oficinas_pkey" PRIMARY KEY ("evento_id","oficina_id")
);

-- CreateTable
CREATE TABLE "evento_controles" (
    "id" SERIAL NOT NULL,
    "evento_id" INTEGER NOT NULL,
    "nombre" VARCHAR(120) NOT NULL,
    "orden" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "evento_controles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "asistencia_controles" (
    "id" SERIAL NOT NULL,
    "asistencia_id" INTEGER NOT NULL,
    "control_id" INTEGER NOT NULL,
    "estado" "estado_asistencia" NOT NULL DEFAULT 'ASISTIO',
    "observacion" TEXT,
    "registrado_por_id" INTEGER,
    "registrado_en" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "latitud_registro" DOUBLE PRECISION,
    "longitud_registro" DOUBLE PRECISION,
    "accuracy_registro" DOUBLE PRECISION,
    CONSTRAINT "asistencia_controles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "personas" (
    "id" SERIAL NOT NULL,
    "nombre_completo" VARCHAR(150) NOT NULL,
    "ci" VARCHAR(30),
    "codigo_qr" VARCHAR(255),
    "datos_qr" JSONB,
    "departamento_id" INTEGER,
    "usuario_id" INTEGER,
    "activo" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "personas_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "usuarios" (
    "id" SERIAL NOT NULL,
    "nombre_completo" VARCHAR(150) NOT NULL,
    "nombres" VARCHAR(150),
    "primer_apellido" VARCHAR(80),
    "segundo_apellido" VARCHAR(80),
    "tercer_apellido" VARCHAR(80),
    "ci" VARCHAR(30),
    "tipo_vinculo" VARCHAR(30),
    "unidad" VARCHAR(120),
    "oficina_id" INTEGER,
    "cargo_codigo" VARCHAR(50),
    "cargo" VARCHAR(120),
    "numero_item" VARCHAR(50),
    "foto_url" TEXT,
    "email" VARCHAR(150) NOT NULL,
    "password_hash" TEXT NOT NULL,
    "rol" "rol_usuario" NOT NULL DEFAULT 'OPERADOR',
    "activo" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "usuarios_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "idx_asistencias_datos_qr_snapshot" ON "asistencias" USING GIN ("datos_qr_snapshot");
CREATE INDEX "idx_asistencias_estado" ON "asistencias"("estado");
CREATE INDEX "idx_asistencias_evento_id" ON "asistencias"("evento_id");
CREATE INDEX "idx_asistencias_persona_id" ON "asistencias"("persona_id");
CREATE UNIQUE INDEX "asistencias_evento_id_persona_id_key" ON "asistencias"("evento_id", "persona_id");
CREATE UNIQUE INDEX "departamentos_nombre_key" ON "departamentos"("nombre");
CREATE INDEX "idx_evento_departamentos_departamento_id" ON "evento_departamentos"("departamento_id");
CREATE INDEX "idx_eventos_fecha_evento" ON "eventos"("fecha_evento");
CREATE INDEX "idx_oficinas_cod" ON "oficinas"("cod");
CREATE INDEX "idx_oficinas_nivel" ON "oficinas"("nivel");
CREATE INDEX "idx_cargos_cargo" ON "cargos"("cargo");
CREATE INDEX "idx_evento_oficinas_oficina_id" ON "evento_oficinas"("oficina_id");
CREATE INDEX "idx_evento_controles_evento_id" ON "evento_controles"("evento_id");
CREATE UNIQUE INDEX "evento_controles_evento_id_orden_key" ON "evento_controles"("evento_id", "orden");
CREATE INDEX "idx_asistencia_controles_control_id" ON "asistencia_controles"("control_id");
CREATE INDEX "idx_asistencia_controles_registrado_por_id" ON "asistencia_controles"("registrado_por_id");
CREATE UNIQUE INDEX "asistencia_controles_asistencia_id_control_id_key" ON "asistencia_controles"("asistencia_id", "control_id");
CREATE UNIQUE INDEX "personas_codigo_qr_key" ON "personas"("codigo_qr");
CREATE UNIQUE INDEX "personas_usuario_id_key" ON "personas"("usuario_id");
CREATE INDEX "idx_personas_datos_qr" ON "personas" USING GIN ("datos_qr");
CREATE INDEX "idx_personas_departamento_id" ON "personas"("departamento_id");
CREATE UNIQUE INDEX "usuarios_email_key" ON "usuarios"("email");
CREATE INDEX "idx_usuarios_cargo_codigo" ON "usuarios"("cargo_codigo");
CREATE INDEX "idx_usuarios_oficina_id" ON "usuarios"("oficina_id");

ALTER TABLE "asistencias" ADD CONSTRAINT "asistencias_evento_id_fkey" FOREIGN KEY ("evento_id") REFERENCES "eventos"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE "asistencias" ADD CONSTRAINT "asistencias_persona_id_fkey" FOREIGN KEY ("persona_id") REFERENCES "personas"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE "asistencias" ADD CONSTRAINT "asistencias_registrado_por_id_fkey" FOREIGN KEY ("registrado_por_id") REFERENCES "usuarios"("id") ON DELETE SET NULL ON UPDATE NO ACTION;
ALTER TABLE "evento_departamentos" ADD CONSTRAINT "evento_departamentos_departamento_id_fkey" FOREIGN KEY ("departamento_id") REFERENCES "departamentos"("id") ON DELETE RESTRICT ON UPDATE NO ACTION;
ALTER TABLE "evento_departamentos" ADD CONSTRAINT "evento_departamentos_evento_id_fkey" FOREIGN KEY ("evento_id") REFERENCES "eventos"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE "eventos" ADD CONSTRAINT "eventos_creado_por_id_fkey" FOREIGN KEY ("creado_por_id") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE NO ACTION;
ALTER TABLE "evento_oficinas" ADD CONSTRAINT "evento_oficinas_evento_id_fkey" FOREIGN KEY ("evento_id") REFERENCES "eventos"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE "evento_oficinas" ADD CONSTRAINT "evento_oficinas_oficina_id_fkey" FOREIGN KEY ("oficina_id") REFERENCES "oficinas"("id") ON DELETE RESTRICT ON UPDATE NO ACTION;
ALTER TABLE "evento_controles" ADD CONSTRAINT "evento_controles_evento_id_fkey" FOREIGN KEY ("evento_id") REFERENCES "eventos"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE "asistencia_controles" ADD CONSTRAINT "asistencia_controles_asistencia_id_fkey" FOREIGN KEY ("asistencia_id") REFERENCES "asistencias"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE "asistencia_controles" ADD CONSTRAINT "asistencia_controles_control_id_fkey" FOREIGN KEY ("control_id") REFERENCES "evento_controles"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE "asistencia_controles" ADD CONSTRAINT "asistencia_controles_registrado_por_id_fkey" FOREIGN KEY ("registrado_por_id") REFERENCES "usuarios"("id") ON DELETE SET NULL ON UPDATE NO ACTION;
ALTER TABLE "personas" ADD CONSTRAINT "personas_departamento_id_fkey" FOREIGN KEY ("departamento_id") REFERENCES "departamentos"("id") ON DELETE SET NULL ON UPDATE NO ACTION;
ALTER TABLE "personas" ADD CONSTRAINT "personas_usuario_id_fkey" FOREIGN KEY ("usuario_id") REFERENCES "usuarios"("id") ON DELETE SET NULL ON UPDATE NO ACTION;
ALTER TABLE "usuarios" ADD CONSTRAINT "usuarios_cargo_codigo_fkey" FOREIGN KEY ("cargo_codigo") REFERENCES "cargos"("codigo") ON DELETE SET NULL ON UPDATE NO ACTION;
ALTER TABLE "usuarios" ADD CONSTRAINT "usuarios_oficina_id_fkey" FOREIGN KEY ("oficina_id") REFERENCES "oficinas"("id") ON DELETE SET NULL ON UPDATE NO ACTION;
