import { HttpError } from "../../../http-error.ts";
import type { PlaceInput } from "../types/place-types.ts";

export function parsePlaceInput(payload: unknown): PlaceInput {
  const body = expectRecord(payload);
  const oficinaIds = readRequiredIntList(body, "oficinaIds", "oficinaId");
  const oficinaId = readOptionalInt(body, "oficinaId");
  const nombre = readRequiredString(body, "nombre", 2, 150);

  return {
    nombre,
    oficinaId,
    oficinaIds: [...new Set([...(oficinaId == null ? [] : [oficinaId]), ...oficinaIds])],
    usuarioIdsExcluidos: readOptionalIntList(body, "usuarioIdsExcluidos"),
    pisos: readOptionalFloors(body, "pisos"),
    latitud: readRequiredFloatInRange(body, "latitud", -90, 90),
    longitud: readRequiredFloatInRange(body, "longitud", -180, 180),
    radioMetros: readRequiredIntInRange(body, "radioMetros", 5, 10_000),
    activo: readOptionalBoolean(body, "activo") ?? true,
  };
}

export function parsePlaceActiveInput(payload: unknown) {
  const body = expectRecord(payload);
  const activo = readOptionalBoolean(body, "activo");

  if (activo == null) {
    throw new HttpError(400, "Debes enviar el estado activo del lugar.");
  }

  return { activo };
}

function readRequiredString(
  source: Record<string, unknown>,
  key: string,
  minLength: number,
  maxLength: number,
) {
  const value = source[key];

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

export function readPlaceIdFromPathMatch(match: RegExpExecArray) {
  const placeId = Number.parseInt(match[1] ?? "", 10);

  if (!Number.isInteger(placeId) || placeId <= 0) {
    throw new HttpError(400, "Debes enviar un lugar valido.");
  }

  return placeId;
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

function readRequiredFloat(
  source: Record<string, unknown>,
  key: string,
) {
  const value = source[key];
  const numericValue =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number.parseFloat(value)
        : Number.NaN;

  if (!Number.isFinite(numericValue)) {
    throw new HttpError(400, `El campo ${key} debe ser un numero valido.`);
  }

  return numericValue;
}

function readRequiredFloatInRange(
  source: Record<string, unknown>,
  key: string,
  min: number,
  max: number,
) {
  const numericValue = readRequiredFloat(source, key);

  if (numericValue < min || numericValue > max) {
    throw new HttpError(
      400,
      `El campo ${key} debe estar entre ${min} y ${max}.`,
    );
  }

  return numericValue;
}

function readRequiredIntInRange(
  source: Record<string, unknown>,
  key: string,
  min: number,
  max: number,
) {
  const numericValue = readRequiredInt(source, key);

  if (numericValue < min || numericValue > max) {
    throw new HttpError(
      400,
      `El campo ${key} debe estar entre ${min} y ${max}.`,
    );
  }

  return numericValue;
}

function readOptionalBoolean(source: Record<string, unknown>, key: string) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  if (typeof value !== "boolean") {
    throw new HttpError(400, `El campo ${key} debe ser verdadero o falso.`);
  }

  return value;
}

function readRequiredIntList(
  source: Record<string, unknown>,
  pluralKey: string,
  singularFallbackKey: string,
) {
  const pluralValue = source[pluralKey];

  if (Array.isArray(pluralValue)) {
    if (pluralValue.length === 0) {
      throw new HttpError(
        400,
        `El campo ${pluralKey} debe incluir al menos un valor.`,
      );
    }

    return pluralValue.map((value, index) => {
      const numericValue =
        typeof value === "number"
          ? value
          : typeof value === "string"
            ? Number.parseInt(value, 10)
            : Number.NaN;

      if (!Number.isInteger(numericValue) || numericValue <= 0) {
        throw new HttpError(
          400,
          `El valor ${index + 1} de ${pluralKey} no es valido.`,
        );
      }

      return numericValue;
    });
  }

  return [readRequiredInt(source, singularFallbackKey)];
}

function readRequiredInt(source: Record<string, unknown>, key: string) {
  const value = source[key];
  const numericValue =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number.parseInt(value, 10)
        : Number.NaN;

  if (!Number.isInteger(numericValue) || numericValue <= 0) {
    throw new HttpError(400, `El campo ${key} debe ser un numero valido.`);
  }

  return numericValue;
}

function readOptionalInt(source: Record<string, unknown>, key: string) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  const numericValue =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number.parseInt(value, 10)
        : Number.NaN;

  if (!Number.isInteger(numericValue) || numericValue <= 0) {
    throw new HttpError(400, `El campo ${key} debe ser un numero valido.`);
  }

  return numericValue;
}

function readOptionalIntList(source: Record<string, unknown>, key: string) {
  const value = source[key];

  if (value == null) {
    return [];
  }

  if (!Array.isArray(value)) {
    throw new HttpError(400, `El campo ${key} debe ser una lista.`);
  }

  return [
    ...new Set(
      value.map((item, index) => {
        const numericValue =
          typeof item === "number"
            ? item
            : typeof item === "string"
              ? Number.parseInt(item, 10)
              : Number.NaN;

        if (!Number.isInteger(numericValue) || numericValue <= 0) {
          throw new HttpError(
            400,
            `El valor ${index + 1} de ${key} no es valido.`,
          );
        }

        return numericValue;
      }),
    ),
  ];
}

function readOptionalFloors(source: Record<string, unknown>, key: string) {
  const value = source[key];

  if (value == null) {
    return [];
  }

  if (!Array.isArray(value)) {
    throw new HttpError(400, `El campo ${key} debe ser una lista.`);
  }

  return value.map((item, index) => {
    const record = expectRecord(item);
    const id = readNullablePositiveInt(record, "id");
    const nombre = readRequiredString(record, "nombre", 1, 120);

    return {
      id,
      nombre,
      orden: index,
    };
  });
}

function readNullablePositiveInt(source: Record<string, unknown>, key: string) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  const numericValue =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number.parseInt(value, 10)
        : Number.NaN;

  if (!Number.isInteger(numericValue) || numericValue <= 0) {
    throw new HttpError(400, `El campo ${key} debe ser un numero valido.`);
  }

  return numericValue;
}
