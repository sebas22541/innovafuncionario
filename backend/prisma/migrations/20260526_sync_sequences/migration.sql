DO $$
DECLARE
  sequence_name text;
BEGIN
  SELECT pg_get_serial_sequence('"usuarios"', 'id') INTO sequence_name;
  IF sequence_name IS NOT NULL THEN
    EXECUTE format(
      'SELECT setval(%L, COALESCE((SELECT MAX(id) FROM "usuarios"), 0) + 1, false)',
      sequence_name
    );
  END IF;

  SELECT pg_get_serial_sequence('"personas"', 'id') INTO sequence_name;
  IF sequence_name IS NOT NULL THEN
    EXECUTE format(
      'SELECT setval(%L, COALESCE((SELECT MAX(id) FROM "personas"), 0) + 1, false)',
      sequence_name
    );
  END IF;

  SELECT pg_get_serial_sequence('"eventos"', 'id') INTO sequence_name;
  IF sequence_name IS NOT NULL THEN
    EXECUTE format(
      'SELECT setval(%L, COALESCE((SELECT MAX(id) FROM "eventos"), 0) + 1, false)',
      sequence_name
    );
  END IF;

  SELECT pg_get_serial_sequence('"asistencias"', 'id') INTO sequence_name;
  IF sequence_name IS NOT NULL THEN
    EXECUTE format(
      'SELECT setval(%L, COALESCE((SELECT MAX(id) FROM "asistencias"), 0) + 1, false)',
      sequence_name
    );
  END IF;

  SELECT pg_get_serial_sequence('"departamentos"', 'id') INTO sequence_name;
  IF sequence_name IS NOT NULL THEN
    EXECUTE format(
      'SELECT setval(%L, COALESCE((SELECT MAX(id) FROM "departamentos"), 0) + 1, false)',
      sequence_name
    );
  END IF;

  SELECT pg_get_serial_sequence('"evento_controles"', 'id') INTO sequence_name;
  IF sequence_name IS NOT NULL THEN
    EXECUTE format(
      'SELECT setval(%L, COALESCE((SELECT MAX(id) FROM "evento_controles"), 0) + 1, false)',
      sequence_name
    );
  END IF;

  SELECT pg_get_serial_sequence('"asistencia_controles"', 'id') INTO sequence_name;
  IF sequence_name IS NOT NULL THEN
    EXECUTE format(
      'SELECT setval(%L, COALESCE((SELECT MAX(id) FROM "asistencia_controles"), 0) + 1, false)',
      sequence_name
    );
  END IF;
END $$;
