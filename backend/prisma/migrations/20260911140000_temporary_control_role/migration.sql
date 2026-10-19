ALTER TABLE "usuarios"
  ADD COLUMN IF NOT EXISTS "control_rol_anterior" "rol_usuario",
  ADD COLUMN IF NOT EXISTS "control_inicio" TIMESTAMPTZ(6),
  ADD COLUMN IF NOT EXISTS "control_fin" TIMESTAMPTZ(6);
