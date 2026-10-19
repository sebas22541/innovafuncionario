// Only the temporary CONTROL period uses UTC timestamp values. Do not change
// the connection timezone or the types/values of any other date columns.
export const controlPeriodUtcSchemaSql = `DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema = current_schema() AND table_name = 'usuarios'
      AND column_name = 'control_inicio' AND data_type = 'timestamp with time zone') THEN
    ALTER TABLE "usuarios" ALTER COLUMN "control_inicio" TYPE TIMESTAMP(6)
      USING "control_inicio" AT TIME ZONE 'UTC';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema = current_schema() AND table_name = 'usuarios'
      AND column_name = 'control_fin' AND data_type = 'timestamp with time zone') THEN
    ALTER TABLE "usuarios" ALTER COLUMN "control_fin" TYPE TIMESTAMP(6)
      USING "control_fin" AT TIME ZONE 'UTC';
  END IF;
END $$`;
