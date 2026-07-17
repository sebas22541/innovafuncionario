ALTER TABLE "calificaciones_funcionario"
  ADD COLUMN IF NOT EXISTS "calificador_nombre" VARCHAR(120),
  ADD COLUMN IF NOT EXISTS "calificador_celular" VARCHAR(30);
