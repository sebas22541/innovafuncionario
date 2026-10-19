import { HttpError } from "../../../http-error.ts";
import type { LunchReportQuery, LunchScanInput } from "../types/lunch-types.ts";

export function parseLunchScanInput(payload: unknown): LunchScanInput {
  const body = expectRecord(payload);

  return {
    qrValue: readRequiredString(body, "qrValue", 5, 2000),
    latitud: readOptionalFloat(body, "latitud", -90, 90),
    longitud: readOptionalFloat(body, "longitud", -180, 180),
    accuracy: readOptionalFloat(body, "accuracy", 0, 10_000),
  };
}

export function parseLunchReportQuery(
  url: URL,
  options: {
    readOptionalQueryInt: (url: URL, key: string) => number | null;
    readDateOnlyString: (value: string, key: string) => Date;
    formatDateInAppTimeZone: (date: Date) => string;
  },
): LunchReportQuery {
  const rawStatus =
    url.searchParams.get("estado")?.trim().toUpperCase() ?? null;
  let status: LunchReportQuery["status"] = null;

  if (rawStatus != null && rawStatus.length > 0) {
    if (rawStatus !== "ABIERTOS" && rawStatus !== "CERRADOS") {
      throw new HttpError(400, "El estado de almuerzo no es valido.");
    }

    status = rawStatus;
  }

  return {
    ...readLunchQueryDateRange(url, options),
    search: readLunchQuerySearch(url),
    status,
    scannerId: options.readOptionalQueryInt(url, "scannerId"),
    userId: null,
    officeId: options.readOptionalQueryInt(url, "oficinaId"),
    placeId: options.readOptionalQueryInt(url, "lugarId"),
    jobTitle: readLunchQueryJobTitle(url),
    linkType: readLunchQueryLinkType(url),
  };
}

function readLunchQueryDateRange(
  url: URL,
  options: {
    readDateOnlyString: (value: string, key: string) => Date;
    formatDateInAppTimeZone: (date: Date) => string;
  },
) {
  const todayText = options.formatDateInAppTimeZone(new Date());
  const rawDate = url.searchParams.get("fecha")?.trim();
  const rawStart = url.searchParams.get("desde")?.trim() ?? rawDate;
  const rawEnd = url.searchParams.get("hasta")?.trim() ?? rawDate;
  const fechaDesde =
    rawStart == null || rawStart.length === 0
      ? options.readDateOnlyString(todayText, "desde")
      : options.readDateOnlyString(rawStart, "desde");
  const fechaHasta =
    rawEnd == null || rawEnd.length === 0
      ? fechaDesde
      : options.readDateOnlyString(rawEnd, "hasta");

  if (fechaDesde.getTime() > fechaHasta.getTime()) {
    throw new HttpError(
      400,
      "La fecha inicial no puede ser mayor a la fecha final.",
    );
  }

  const rangeDays =
    Math.floor(
      (fechaHasta.getTime() - fechaDesde.getTime()) / (24 * 60 * 60 * 1000),
    ) + 1;

  if (rangeDays > 366) {
    throw new HttpError(400, "El rango de fechas no puede superar 366 dias.");
  }

  return { fechaDesde, fechaHasta };
}

function readLunchQuerySearch(url: URL) {
  const rawValue =
    url.searchParams.get("q")?.trim() ?? url.searchParams.get("ci")?.trim();

  if (rawValue == null || rawValue.length === 0) {
    return null;
  }

  if (rawValue.length > 80) {
    throw new HttpError(400, "La busqueda no puede superar 80 caracteres.");
  }

  return rawValue;
}

function readLunchQueryJobTitle(url: URL) {
  const rawValue =
    url.searchParams.get("cargo")?.trim() ??
    url.searchParams.get("cargoNombre")?.trim();

  if (rawValue == null || rawValue.length === 0) {
    return null;
  }

  if (rawValue.length > 120) {
    throw new HttpError(400, "El cargo no puede superar 120 caracteres.");
  }

  return rawValue;
}

function readLunchQueryLinkType(url: URL) {
  const rawValue =
    url.searchParams.get("tipoVinculo")?.trim().toUpperCase() ??
    url.searchParams.get("tipo")?.trim().toUpperCase();

  if (rawValue == null || rawValue.length === 0) {
    return null;
  }

  if (
    rawValue !== "ITEM" &&
    rawValue !== "EVENTUAL" &&
    rawValue !== "CONSULTOR" &&
    rawValue !== "SERVICIOS"
  ) {
    throw new HttpError(400, "El tipo de vinculo no es valido.");
  }

  return rawValue;
}

function expectRecord(payload: unknown) {
  if (
    typeof payload !== "object" ||
    payload == null ||
    Array.isArray(payload)
  ) {
    throw new HttpError(
      400,
      "El cuerpo de la solicitud no tiene un formato valido.",
    );
  }

  return payload as Record<string, unknown>;
}

function readRequiredString(
  source: Record<string, unknown>,
  key: string,
  minLength: number,
  maxLength: number,
) {
  const value = source[key];

  if (typeof value !== "string") {
    throw new HttpError(400, `Debes enviar el campo ${key}.`);
  }

  const trimmed = value.trim();

  if (trimmed.length < minLength || trimmed.length > maxLength) {
    throw new HttpError(
      400,
      `El campo ${key} debe tener entre ${minLength} y ${maxLength} caracteres.`,
    );
  }

  return trimmed;
}

function readOptionalFloat(
  source: Record<string, unknown>,
  key: string,
  min: number,
  max: number,
) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  const numericValue =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number.parseFloat(value)
        : Number.NaN;

  if (
    !Number.isFinite(numericValue) ||
    numericValue < min ||
    numericValue > max
  ) {
    throw new HttpError(400, `El campo ${key} no tiene un valor valido.`);
  }

  return numericValue;
}
