import type { Prisma } from "../../../generated/prisma/client.ts";
import { formatInTimeZone } from "date-fns-tz";
import type { LunchReportQuery } from "../types/lunch-types.ts";

const LUNCH_TIME_ZONE = "America/La_Paz";

type LunchServiceConfig = {
  buildUserDisplayName: (user: any) => string;
  toDateOnlyText: (date: Date) => string;
  isUserExcludedFromLunchOnDate: (userId: number, date: Date) => Promise<boolean>;
};

let lunchServiceConfig: LunchServiceConfig | null = null;

export function configureLunchService(config: LunchServiceConfig) {
  lunchServiceConfig = config;
}

export function buildLunchReportWhere(
  query: LunchReportQuery,
): Prisma.almuerzosWhereInput {
  const searchTokens = buildLunchSearchTokens(query.search);
  const conditions: Prisma.almuerzosWhereInput[] = [
    {
      fecha: {
        gte: query.fechaDesde,
        lte: query.fechaHasta,
      },
    },
  ];

  for (const token of searchTokens) {
    conditions.push({
      OR: [
        {
          funcionario_nombre_completo: {
            contains: token,
            mode: "insensitive",
          },
        },
        { funcionario_ci: { contains: token, mode: "insensitive" } },
        { funcionario_numero_item: { contains: token, mode: "insensitive" } },
        { funcionario_cargo: { contains: token, mode: "insensitive" } },
        { funcionario_oficina: { contains: token, mode: "insensitive" } },
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

  if (query.userId != null) {
    conditions.push({ usuario_id: query.userId });
  }

  if (query.officeId != null) {
    conditions.push({ funcionario_oficina_id: query.officeId });
  }

  if (query.placeId != null) {
    conditions.push({
      OR: [
        {
          datos_qr_snapshot: {
            path: ["salida", "lugarId"],
            equals: query.placeId,
          },
        },
        {
          datos_qr_snapshot: {
            path: ["retorno", "lugarId"],
            equals: query.placeId,
          },
        },
        {
          datos_qr_snapshot: {
            path: ["lugarId"],
            equals: query.placeId,
          },
        },
        {
          datos_qr_snapshot: {
            path: ["salida", "lookupCode"],
            equals: `QR_ALMUERZO_LUGAR_${query.placeId}`,
          },
        },
        {
          datos_qr_snapshot: {
            path: ["retorno", "lookupCode"],
            equals: `QR_ALMUERZO_LUGAR_${query.placeId}`,
          },
        },
        {
          datos_qr_snapshot: {
            path: ["lookupCode"],
            equals: `QR_ALMUERZO_LUGAR_${query.placeId}`,
          },
        },
      ],
    });
  }

  if (query.jobTitle != null && query.jobTitle.trim().length > 0) {
    conditions.push({
      funcionario_cargo: {
        contains: query.jobTitle.trim(),
        mode: "insensitive",
      },
    });
  }

  if (query.linkType != null) {
    conditions.push({
      funcionario: {
        tipo_vinculo: query.linkType,
      },
    });
  }

  return { AND: conditions };
}

export async function filterLunchRecordsByExclusionHistory(records: any[]) {
  const config = getLunchServiceConfig();
  const filteredRecords: any[] = [];
  const excludedByUserDate = new Map<string, boolean>();

  for (const record of records) {
    const userId = Number(record.usuario_id);
    const recordDate = record.fecha;
    const cacheKey = `${userId}:${config.toDateOnlyText(recordDate)}`;
    let excluded = excludedByUserDate.get(cacheKey);

    if (excluded == null) {
      excluded = await config.isUserExcludedFromLunchOnDate(userId, recordDate);
      excludedByUserDate.set(cacheKey, excluded);
    }

    if (!excluded) {
      filteredRecords.push(record);
    }
  }

  return filteredRecords;
}

function buildLunchSearchTokens(search: string | null | undefined): string[] {
  return (search ?? "")
    .trim()
    .split(/[\s,.;:/\\|()-]+/u)
    .map((token) => token.trim())
    .filter((token) => token.length >= 2)
    .slice(0, 8);
}

export function serializeLunchRecord(record: any) {
  const config = getLunchServiceConfig();
  const salidaRegistrador = record.registrador_salida ?? null;
  const retornoRegistrador = record.registrador_retorno ?? null;
  const qrSnapshot = readRecordJson(record.datos_qr_snapshot);
  const legacyPlace = readRegistrationPlace(qrSnapshot);
  const departurePlace =
    readRegistrationPlace(readRecordJson(qrSnapshot?.salida)) ?? legacyPlace;
  const returnPlace =
    readRegistrationPlace(readRecordJson(qrSnapshot?.retorno)) ??
    (record.hora_retorno == null ? null : legacyPlace);

  return {
    id: record.id,
    usuarioId: record.usuario_id,
    fecha: config.toDateOnlyText(record.fecha),
    horaSalida:
      formatLunchTimeInBoliviaTimeZone(record.salida_en) ?? record.hora_salida,
    salidaEn: record.salida_en.toISOString(),
    horaRetorno:
      record.retorno_en == null
        ? ""
        : (formatLunchTimeInBoliviaTimeZone(record.retorno_en) ??
          record.hora_retorno ??
          ""),
    retornoEn: record.retorno_en?.toISOString() ?? null,
    estado: record.hora_retorno == null ? "ABIERTO" : "CERRADO",
    funcionarioNombreCompleto: record.funcionario_nombre_completo,
    funcionarioCi: record.funcionario_ci ?? "",
    funcionarioNumeroItem: record.funcionario_numero_item ?? "",
    funcionarioCargo: record.funcionario_cargo ?? "",
    funcionarioOficinaId: record.funcionario_oficina_id ?? null,
    funcionarioOficina: record.funcionario_oficina ?? "",
    lugarRegistroId: returnPlace?.id ?? departurePlace?.id ?? null,
    lugarRegistroNombre: returnPlace?.name ?? departurePlace?.name ?? "",
    lugarSalidaId: departurePlace?.id ?? null,
    lugarSalidaNombre: departurePlace?.name ?? "",
    lugarRetornoId: returnPlace?.id ?? null,
    lugarRetornoNombre: returnPlace?.name ?? "",
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

function formatLunchTimeInBoliviaTimeZone(value: unknown) {
  if (!(value instanceof Date)) {
    return null;
  }

  return formatInTimeZone(value, LUNCH_TIME_ZONE, "HH:mm");
}

function readRegistrationPlace(snapshot: Record<string, unknown> | null) {
  if (snapshot == null) {
    return null;
  }

  const id = readOptionalNumber(snapshot.lugarId);
  const floorName = readOptionalString(snapshot.pisoNombre);
  const name =
    readOptionalString(snapshot.lugarNombre) ??
    readRegistrationPlaceNameFromLookupCode(snapshot.lookupCode) ??
    "";
  const displayName =
    name.length > 0 && floorName != null ? `${name} - ${floorName}` : name;

  if (id == null && displayName.length === 0) {
    return null;
  }

  return { id, name: displayName };
}

function readRecordJson(value: unknown) {
  if (typeof value !== "object" || value == null || Array.isArray(value)) {
    return null;
  }

  return value as Record<string, unknown>;
}

function readOptionalString(value: unknown) {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function readOptionalNumber(value: unknown) {
  const numericValue =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number.parseInt(value, 10)
        : Number.NaN;

  return Number.isInteger(numericValue) ? numericValue : null;
}

function readRegistrationPlaceNameFromLookupCode(value: unknown) {
  const lookupCode = readOptionalString(value);

  if (lookupCode == null || lookupCode === "QR_ALMUERZO_FIJO") {
    return null;
  }

  const match = lookupCode.match(/^QR_ALMUERZO_LUGAR_(\d+)(?:_PISO_\d+)?$/);

  return match == null ? null : `Lugar ${match[1]}`;
}

function getLunchServiceConfig() {
  if (lunchServiceConfig == null) {
    throw new Error("El servicio de almuerzos no esta configurado.");
  }

  return lunchServiceConfig;
}
