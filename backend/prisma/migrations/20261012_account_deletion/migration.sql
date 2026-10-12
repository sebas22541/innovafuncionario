ALTER TABLE "usuarios" ADD COLUMN "default_ci_login_enabled" BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE "eventos" ALTER COLUMN "creado_por_id" DROP NOT NULL;
ALTER TABLE "eventos" DROP CONSTRAINT "eventos_creado_por_id_fkey";
ALTER TABLE "eventos" ADD CONSTRAINT "eventos_creado_por_id_fkey"
  FOREIGN KEY ("creado_por_id") REFERENCES "usuarios"("id") ON DELETE SET NULL ON UPDATE NO ACTION;
