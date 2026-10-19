ALTER TABLE "asistencias"
  ADD COLUMN IF NOT EXISTS "ci_snapshot" VARCHAR(30),
  ADD COLUMN IF NOT EXISTS "cargo_snapshot" VARCHAR(150),
  ADD COLUMN IF NOT EXISTS "oficina_id_snapshot" INTEGER,
  ADD COLUMN IF NOT EXISTS "oficina_snapshot" VARCHAR(180),
  ADD COLUMN IF NOT EXISTS "oficina_cod_snapshot" VARCHAR(50);

UPDATE "asistencias" a
SET
  "ci_snapshot" = COALESCE(a."ci_snapshot", u."ci", p."ci"),
  "cargo_snapshot" = COALESCE(
    a."cargo_snapshot",
    NULLIF(TRIM(COALESCE(u."subcargo", '')), ''),
    NULLIF(TRIM(COALESCE(u."cargo", '')), '')
  ),
  "oficina_id_snapshot" = COALESCE(
    a."oficina_id_snapshot",
    u."oficina_comision_id",
    u."oficina_id"
  ),
  "oficina_snapshot" = COALESCE(
    a."oficina_snapshot",
    oc."oficina",
    op."oficina",
    u."unidad"
  ),
  "oficina_cod_snapshot" = COALESCE(
    a."oficina_cod_snapshot",
    oc."cod",
    op."cod"
  )
FROM "personas" p
LEFT JOIN "usuarios" u ON u."id" = p."usuario_id"
LEFT JOIN "oficinas" op ON op."id" = u."oficina_id"
LEFT JOIN "oficinas" oc ON oc."id" = u."oficina_comision_id"
WHERE a."persona_id" = p."id";
