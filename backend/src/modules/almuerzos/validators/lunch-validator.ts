import { HttpError } from "../../../http-error.ts";
import type { LunchReportQuery, LunchScanInput } from "../types/lunch-types.ts";

export function parseLunchScanInput(payload: unknown): LunchScanInput {
  const body = expectRecord(payload);

  return {
    qrValue: readRequiredString(body, "qrValue", 5, 2000),
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
    fecha: readLunchQueryDate(url, options),
    search: readLunchQuerySearch(url),
    status,
    scannerId: options.readOptionalQueryInt(url, "scannerId"),
    officeId: options.readOptionalQueryInt(url, "oficinaId"),
  };
}

function readLunchQueryDate(
  url: URL,
  options: {
    readDateOnlyString: (value: string, key: string) => Date;
    formatDateInAppTimeZone: (date: Date) => string;
  },
) {
  const rawValue = url.searchParams.get("fecha")?.trim();

  if (rawValue == null || rawValue.length === 0) {
    return options.readDateOnlyString(
      options.formatDateInAppTimeZone(new Date()),
      "fecha",
    );
  }

  return options.readDateOnlyString(rawValue, "fecha");
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
