import type { Pool } from "pg";
import { HttpError } from "../../../http-error.ts";

type SwornDeclarationServiceConfig = {
  pool: Pool;
  isAdminUser: (user: any) => boolean;
};

let swornDeclarationServiceConfig: SwornDeclarationServiceConfig | null = null;

export function configureSwornDeclarationService(
  config: SwornDeclarationServiceConfig,
) {
  swornDeclarationServiceConfig = config;
}

export async function listSwornDeclarations(input: {
  userId: number;
  onlyMine: boolean;
  query: string | null;
}) {
  const conditions: string[] = [];
  const values: unknown[] = [];

  if (input.onlyMine) {
    values.push(input.userId);
    conditions.push(`"usuario_id" = $${values.length}`);
  }

  if (!input.onlyMine && input.query != null) {
    values.push(`%${input.query}%`);
    const parameter = `$${values.length}`;
    conditions.push(
      `(
        "funcionario_nombre_completo" ILIKE ${parameter}
        OR COALESCE("funcionario_ci", '') ILIKE ${parameter}
        OR COALESCE("funcionario_numero_item", '') ILIKE ${parameter}
        OR COALESCE("funcionario_oficina", '') ILIKE ${parameter}
      )`,
    );
  }

  const whereClause =
    conditions.length === 0 ? "" : `WHERE ${conditions.join(" AND ")}`;
  const result = await getConfig().pool.query(
    `
      SELECT *
      FROM "declaraciones_juradas"
      ${whereClause}
      ORDER BY "created_at" DESC, "id" DESC
      LIMIT 500
    `,
    values,
  );

  return result.rows;
}

export function serializeSwornDeclaration(record: any) {
  return {
    id: record.id,
    usuarioId: record.usuario_id,
    gestion: record.gestion,
    estado: record.estado,
    funcionarioNombreCompleto: record.funcionario_nombre_completo,
    funcionarioCi: record.funcionario_ci ?? "",
    funcionarioNumeroItem: record.funcionario_numero_item ?? "",
    funcionarioCargo: record.funcionario_cargo ?? "",
    funcionarioOficinaId: record.funcionario_oficina_id ?? null,
    funcionarioOficina: record.funcionario_oficina ?? "",
    payload: record.payload ?? {},
    observacionRevision: record.observacion_revision ?? "",
    revisadoPorId: record.revisado_por_id ?? null,
    revisadoPorNombre: record.revisado_por_nombre ?? "",
    revisadoEn: record.revisado_en?.toISOString() ?? null,
    createdAt: record.created_at.toISOString(),
    updatedAt: record.updated_at.toISOString(),
  };
}

export async function loadSwornDeclarationForPdf(
  declarationId: number,
  authenticatedUser: any,
) {
  if (!Number.isInteger(declarationId) || declarationId <= 0) {
    throw new HttpError(400, "Debes enviar una declaracion valida.");
  }

  const config = getConfig();
  const conditions = [`"id" = $1`];
  const values: unknown[] = [declarationId];

  if (!config.isAdminUser(authenticatedUser)) {
    values.push(authenticatedUser.id);
    conditions.push(`"usuario_id" = $${values.length}`);
  }

  const result = await config.pool.query(
    `
      SELECT *
      FROM "declaraciones_juradas"
      WHERE ${conditions.join(" AND ")}
      LIMIT 1
    `,
    values,
  );

  if (result.rowCount === 0) {
    throw new HttpError(404, "No se encontro la declaracion jurada.");
  }

  return result.rows[0];
}

function getConfig() {
  if (swornDeclarationServiceConfig == null) {
    throw new Error(
      "El servicio de declaraciones juradas no esta configurado.",
    );
  }

  return swornDeclarationServiceConfig;
}
