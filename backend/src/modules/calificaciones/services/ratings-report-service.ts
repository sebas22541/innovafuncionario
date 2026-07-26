import type { Pool } from "pg";

import { HttpError } from "../../../http-error.ts";

type RatingsReportRequester = {
  rol?: string | null;
  oficinas?: { nivel?: number | null } | null;
  oficina_comision?: { nivel?: number | null } | null;
};

type LoadFuncionarioRatingsSummaryParams = {
  pool: Pool;
  requester: RatingsReportRequester | null | undefined;
  fechaInicio: string | null;
  fechaFin: string | null;
  cargoCodigo: string | null;
  oficinaId: number | null;
  search: string | null;
  healthOfficeLevel: number;
  seedAdminEmail: string;
};

export async function loadFuncionarioRatingsSummary({
  pool,
  requester,
  fechaInicio,
  fechaFin,
  cargoCodigo,
  oficinaId,
  search,
  healthOfficeLevel,
  seedAdminEmail,
}: LoadFuncionarioRatingsSummaryParams) {
  const hasDateFilter = fechaInicio != null || fechaFin != null;
  const start =
    fechaInicio == null ? null : readDateOnlyString(fechaInicio, "fechaInicio");
  const end =
    fechaFin == null ? start : readDateOnlyString(fechaFin, "fechaFin");

  if (start != null && end != null && start.getTime() > end.getTime()) {
    throw new HttpError(
      400,
      "La fecha inicio no puede ser mayor a la fecha fin.",
    );
  }

  const params: unknown[] = [];
  const healthFilter = isHealthAdminUser(requester, healthOfficeLevel)
    ? `AND (
        principal.nivel = ${healthOfficeLevel}
        OR comision.nivel = ${healthOfficeLevel}
      )`
    : "";
  const filters: string[] = [];
  const joinFilters: string[] = [];

  if (hasDateFilter && fechaInicio != null && fechaFin != null) {
    params.push(fechaInicio, fechaFin);
    joinFilters.push(
      `AND c."fecha" BETWEEN $${params.length - 1}::date AND $${params.length}::date`,
    );
  }

  if (cargoCodigo != null) {
    params.push(cargoCodigo);
    filters.push(
      `AND (u."cargo_codigo" = $${params.length} OR u."subcargo_codigo" = $${params.length})`,
    );
  }

  if (oficinaId != null) {
    params.push(oficinaId);
    filters.push(
      `AND COALESCE(u."oficina_comision_id", u."oficina_id") = $${params.length}`,
    );
  }

  if (search != null) {
    const normalizedSearch = search.trim();
    if (/^\d+$/.test(normalizedSearch)) {
      params.push(normalizedSearch);
      filters.push(`AND COALESCE(u."ci", '') = $${params.length}`);
    } else {
      params.push(`%${normalizedSearch}%`);
      filters.push(`AND u."nombre_completo" ILIKE $${params.length}`);
    }
  }

  const result = await pool.query(
    `
      SELECT
        u."id" AS "funcionarioId",
        u."nombre_completo" AS "nombreCompleto",
        COALESCE(u."ci", '') AS "ci",
        COALESCE(u."subcargo", u."cargo", '') AS "cargo",
        COALESCE(comision."oficina", principal."oficina", u."unidad", '') AS "oficina",
        COUNT(c."id")::int AS "total",
        COUNT(c."id") FILTER (WHERE c."calificacion" = 'muy_malo')::int AS "muyMalo",
        COUNT(c."id") FILTER (WHERE c."calificacion" IN ('malo', 'enojada'))::int AS "malo",
        COUNT(c."id") FILTER (WHERE c."calificacion" IN ('regular', 'neutral'))::int AS "regular",
        COUNT(c."id") FILTER (WHERE c."calificacion" IN ('bueno', 'feliz'))::int AS "bueno",
        COUNT(c."id") FILTER (WHERE c."calificacion" = 'muy_bueno')::int AS "muyBueno",
        COALESCE(
          json_agg(
            json_build_object(
              'id', c."id",
              'calificacion', c."calificacion",
              'comentario', COALESCE(c."comentario", ''),
              'calificadorNombre', COALESCE(c."calificador_nombre", ''),
              'calificadorCelular', COALESCE(c."calificador_celular", ''),
              'createdAt', c."created_at"
            )
            ORDER BY c."created_at" DESC
          ) FILTER (WHERE c."id" IS NOT NULL),
          '[]'::json
        ) AS "comentarios"
      FROM "usuarios" u
      LEFT JOIN "oficinas" principal ON principal."id" = u."oficina_id"
      LEFT JOIN "oficinas" comision ON comision."id" = u."oficina_comision_id"
      INNER JOIN "calificacion_funcionario_qrs" q
        ON q."funcionario_id" = u."id"
        AND q."activo" = TRUE
      LEFT JOIN "calificaciones_funcionario" c
        ON c."funcionario_id" = u."id"
        ${joinFilters.join("\n")}
      WHERE u."activo" = TRUE
        AND u."email" <> '${seedAdminEmail.replace(/'/g, "''")}'
        ${healthFilter}
        ${filters.join("\n")}
      GROUP BY
        u."id",
        u."nombre_completo",
        u."ci",
        u."subcargo",
        u."cargo",
        u."unidad",
        comision."oficina",
        principal."oficina"
      ORDER BY u."nombre_completo" ASC
    `,
    params,
  );

  return result.rows;
}

function readDateOnlyString(value: string, key: string) {
  const trimmed = value.trim();

  if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    throw new HttpError(400, `El campo ${key} debe tener formato YYYY-MM-DD.`);
  }

  const date = new Date(`${trimmed}T00:00:00.000Z`);

  if (Number.isNaN(date.getTime())) {
    throw new HttpError(400, `El campo ${key} no es una fecha valida.`);
  }

  return date;
}

function isHealthAdminUser(
  user: RatingsReportRequester | null | undefined,
  healthOfficeLevel: number,
) {
  if (user?.rol !== "ADMIN_SALUD") {
    return false;
  }

  const office = user.oficina_comision ?? user.oficinas;
  return office?.nivel === healthOfficeLevel;
}
