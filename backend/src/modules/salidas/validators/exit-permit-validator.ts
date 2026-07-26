import { HttpError } from "../../../http-error.ts";
import {
  estado_salida,
  motivo_salida,
} from "../../../generated/prisma/enums.ts";
import type {
  CreateExitPermitInput,
  UpdateExitPermitArrivalInput,
  UpdateExitPermitStatusInput,
} from "../types/exit-permit-types.ts";

export function parseCreateExitPermitInput(
  payload: unknown,
): CreateExitPermitInput {
  const body = expectRecord(payload);

  return {
    motivo: readRequiredUppercaseChoice(body, "motivo", [
      motivo_salida.TRABAJO,
      motivo_salida.PARTICULAR,
    ]) as (typeof motivo_salida)[keyof typeof motivo_salida],
    lugarDestino: readRequiredString(body, "lugarDestino", 2, 255),
    descripcion: readOptionalString(body, "descripcion", 0, 1000),
    fechaPermiso: readRequiredDateOnly(body, "fechaPermiso"),
  };
}

export function parseUpdateExitPermitStatusInput(
  payload: unknown,
): UpdateExitPermitStatusInput {
  const body = expectRecord(payload);
  const estado = readRequiredUppercaseChoice(body, "estado", [
    estado_salida.APROBADO,
    estado_salida.RECHAZADO,
  ]);

  return {
    estado: estado as
      typeof estado_salida.APROBADO | typeof estado_salida.RECHAZADO,
  };
}

export function parseUpdateExitPermitArrivalInput(
  payload: unknown,
): UpdateExitPermitArrivalInput {
  const body = expectRecord(payload);

  return {
    horaLlegada: readRequiredTimeText(body, "horaLlegada"),
  };
}

export function readExitPermitQueryDate(
  url: URL,
  readDateOnlyString: (value: string, key: string) => Date,
  toDateOnlyText: (date: Date) => string,
) {
  const rawValue = url.searchParams.get("fecha")?.trim();

  if (rawValue == null || rawValue.length === 0) {
    return readDateOnlyString(toDateOnlyText(new Date()), "fecha");
  }

  return readDateOnlyString(rawValue, "fecha");
}

export function readExitPermitQuerySearch(url: URL) {
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

export function readExitPermitOnlyMineQuery(url: URL) {
  const rawValue =
    url.searchParams.get("propias")?.trim().toLowerCase() ??
    url.searchParams.get("mine")?.trim().toLowerCase();

  return rawValue === "true" || rawValue === "1";
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

function readOptionalString(
  source: Record<string, unknown>,
  key: string,
  minLength: number,
  maxLength: number,
) {
  const value = source[key];

  if (value == null || value === "") {
    return null;
  }

  if (typeof value !== "string") {
    throw new HttpError(400, `El campo ${key} debe ser texto.`);
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

function readRequiredUppercaseChoice(
  source: Record<string, unknown>,
  key: string,
  choices: readonly string[],
) {
  const value = readRequiredString(source, key, 1, 40).toUpperCase();

  if (!choices.includes(value)) {
    throw new HttpError(400, `El campo ${key} no tiene un valor valido.`);
  }

  return value;
}

function readRequiredDateOnly(source: Record<string, unknown>, key: string) {
  const value = readRequiredString(source, key, 10, 10);

  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new HttpError(400, `El campo ${key} debe tener formato YYYY-MM-DD.`);
  }

  const date = new Date(`${value}T00:00:00.000Z`);

  if (Number.isNaN(date.getTime())) {
    throw new HttpError(400, `El campo ${key} no es una fecha valida.`);
  }

  return date;
}

function readRequiredTimeText(source: Record<string, unknown>, key: string) {
  const value = readRequiredString(source, key, 5, 5);

  if (!/^\d{2}:\d{2}$/.test(value)) {
    throw new HttpError(400, `El campo ${key} debe tener formato HH:mm.`);
  }

  return value;
}
