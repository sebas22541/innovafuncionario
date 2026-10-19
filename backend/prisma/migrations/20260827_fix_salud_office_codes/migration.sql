UPDATE "oficinas"
SET "cod" = CASE "id"
  WHEN 2174 THEN '11'
  WHEN 2202 THEN '11.0'
  WHEN 2317 THEN '11.2.3'
  ELSE "cod"
END
WHERE "id" IN (2174, 2202, 2317)
  AND "cod" IN ('11.0.0.0', '11', '11.0.01');
