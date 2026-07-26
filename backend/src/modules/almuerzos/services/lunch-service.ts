import type { Prisma } from "../../../generated/prisma/client.ts";
import type { LunchReportQuery } from "../types/lunch-types.ts";

type LunchServiceConfig = {
  buildUserDisplayName: (user: any) => string;
  toDateOnlyText: (date: Date) => string;
};

let lunchServiceConfig: LunchServiceConfig | null = null;

export function configureLunchService(config: LunchServiceConfig) {
  lunchServiceConfig = config;
}

export function buildLunchReportWhere(
  query: LunchReportQuery,
): Prisma.almuerzosWhereInput {
  const search = query.search?.trim();
  const conditions: Prisma.almuerzosWhereInput[] = [
    {
      fecha: query.fecha,
    },
  ];

  if (search != null && search.length > 0) {
    conditions.push({
      OR: [
        {
          funcionario_nombre_completo: {
            contains: search,
            mode: "insensitive",
          },
        },
        { funcionario_ci: { contains: search, mode: "insensitive" } },
        { funcionario_numero_item: { contains: search, mode: "insensitive" } },
        { funcionario_cargo: { contains: search, mode: "insensitive" } },
        { funcionario_oficina: { contains: search, mode: "insensitive" } },
      ],
    });
  }

  if (query.status === "ABIERTOS") {
    conditions.push({ hora_retorno: null });
  } else if (query.status === "CERRADOS") {
    conditions.push({ hora_retorno: { not: null } });
  }

  if (query.scannerId != null) {
    conditions.push({
      OR: [
        { registrado_salida_por_id: query.scannerId },
        { registrado_retorno_por_id: query.scannerId },
      ],
    });
  }

  if (query.officeId != null) {
    conditions.push({ funcionario_oficina_id: query.officeId });
  }

  return { AND: conditions };
}

export function serializeLunchRecord(record: any) {
  const config = getLunchServiceConfig();
  const salidaRegistrador = record.registrador_salida ?? null;
  const retornoRegistrador = record.registrador_retorno ?? null;

  return {
    id: record.id,
    usuarioId: record.usuario_id,
    fecha: config.toDateOnlyText(record.fecha),
    horaSalida: record.hora_salida,
    salidaEn: record.salida_en.toISOString(),
    horaRetorno: record.hora_retorno ?? "",
    retornoEn: record.retorno_en?.toISOString() ?? null,
    estado: record.hora_retorno == null ? "ABIERTO" : "CERRADO",
    funcionarioNombreCompleto: record.funcionario_nombre_completo,
    funcionarioCi: record.funcionario_ci ?? "",
    funcionarioNumeroItem: record.funcionario_numero_item ?? "",
    funcionarioCargo: record.funcionario_cargo ?? "",
    funcionarioOficinaId: record.funcionario_oficina_id ?? null,
    funcionarioOficina: record.funcionario_oficina ?? "",
    registradoSalidaPorId: record.registrado_salida_por_id ?? null,
    registradoSalidaPorNombre:
      salidaRegistrador == null
        ? ""
        : config.buildUserDisplayName(salidaRegistrador),
    registradoRetornoPorId: record.registrado_retorno_por_id ?? null,
    registradoRetornoPorNombre:
      retornoRegistrador == null
        ? ""
        : config.buildUserDisplayName(retornoRegistrador),
    createdAt: record.created_at.toISOString(),
    updatedAt: record.updated_at.toISOString(),
  };
}

function getLunchServiceConfig() {
  if (lunchServiceConfig == null) {
    throw new Error("El servicio de almuerzos no esta configurado.");
  }

  return lunchServiceConfig;
}
