UPDATE "almuerzos"
SET
  "hora_retorno" = NULL,
  "retorno_en" = NULL,
  "registrado_retorno_por_id" = NULL,
  "updated_at" = CURRENT_TIMESTAMP
WHERE
  "retorno_en" IS NOT NULL
  AND "salida_en" IS NOT NULL
  AND "retorno_en" < "salida_en" + INTERVAL '15 minutes';
