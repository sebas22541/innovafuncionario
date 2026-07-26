import { HttpError } from "../../../http-error.ts";
import type {
  CreateSwornDeclarationInput,
  JsonRecord,
  ReviewSwornDeclarationInput,
} from "../types/sworn-declaration-types.ts";

export function parseCreateSwornDeclarationInput(
  payload: unknown,
): CreateSwornDeclarationInput {
  const body = expectRecord(payload);
  const now = new Date();
  const gestion =
    readOptionalIntInRange(body, "gestion", 2000, now.getFullYear() + 1) ??
    now.getFullYear();
  const declarationPayload = readSwornDeclarationPayload(body);

  validateSwornDeclarationPayload(declarationPayload);

  return {
    gestion,
    payload: declarationPayload,
  };
}

export function parseReviewSwornDeclarationInput(
  payload: unknown,
): ReviewSwornDeclarationInput {
  const body = expectRecord(payload);
  const rawEstado = readRequiredString(body, "estado", 7, 9).toUpperCase();

  if (rawEstado !== "APROBADO" && rawEstado !== "RECHAZADO") {
    throw new HttpError(400, "El estado de revision no es valido.");
  }

  return {
    estado: rawEstado,
    observacion: readOptionalString(body, "observacion", 1, 1000),
  };
}

export function readSwornDeclarationPayload(source: JsonRecord): JsonRecord {
  const value = source["payload"];

  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(
      400,
      "La declaracion jurada no tiene un formato valido.",
    );
  }

  return value as JsonRecord;
}

function validateSwornDeclarationPayload(payload: JsonRecord) {
  const relatives = readJsonArray(payload, "consanguinidadAfinidad");
  const doublePerception = readJsonRecord(payload, "doblePercepcion");
  const sentences = readJsonRecord(payload, "sentenciasProcesos");
  const incompatibilities = readJsonRecord(payload, "otrasIncompatibilidades");
  const address = readJsonRecord(payload, "datosDomiciliarios");
  const cityHallRelatives = readJsonRecord(payload, "familiaresAlcaldia");

  if (relatives.length === 0) {
    throw new HttpError(
      400,
      "Debes registrar al menos un familiar en consanguinidad y afinidad.",
    );
  }

  for (const relative of relatives) {
    const record = expectRecord(relative);
    readRequiredString(record, "parentesco", 2, 80);
    readRequiredString(record, "nombres", 2, 150);
    readRequiredString(record, "documentoIdentidad", 2, 40);
  }

  const perceivesDoubleIncome = readRequiredBoolean(
    doublePerception,
    "percibeDoblePercepcion",
  );

  if (perceivesDoubleIncome) {
    readRequiredString(doublePerception, "institucion", 2, 180);
    readRequiredString(doublePerception, "funcion", 2, 180);
    readRequiredString(doublePerception, "montoPercibe", 1, 40);
    readRequiredString(doublePerception, "remuneracionCargoActual", 1, 40);
    readRequiredString(doublePerception, "montoTotalRemuneracion", 1, 40);
  }

  validateConditionalDescription(
    sentences,
    "tieneSentencias",
    "detalleSentencias",
    "Debes describir las sentencias declaradas.",
  );
  validateConditionalDescription(
    sentences,
    "tieneProcesos",
    "detalleProcesos",
    "Debes describir el estado del proceso declarado.",
  );
  validateConditionalDescription(
    sentences,
    "fueDestituido",
    "detalleDestitucion",
    "Debes indicar el motivo y anio de destitucion.",
  );

  validateConditionalDescription(
    incompatibilities,
    "recibeRenta",
    "detalleRenta",
    "Debes detallar la suspension temporal del beneficio.",
  );
  validateConditionalDescription(
    incompatibilities,
    "representaEmpresas",
    "nombreEmpresa",
    "Debes indicar el nombre de la empresa.",
  );
  readRequiredBoolean(incompatibilities, "compromisoMatrimonio");

  readRequiredString(address, "calleAvenida", 2, 180);
  readRequiredString(address, "barrioZona", 2, 120);
  readRequiredString(address, "numeroDomicilio", 1, 40);
  readRequiredString(address, "tipoVivienda", 2, 80);
  readRequiredString(address, "telefonoCelular", 5, 40);
  readRequiredString(address, "telefonoReferencia", 5, 40);
  readRequiredFloat(address, "latitud", -90, 90);
  readRequiredFloat(address, "longitud", -180, 180);

  const hasCityHallRelatives = readRequiredBoolean(
    cityHallRelatives,
    "tieneFamiliares",
  );
  const cityHallRelativeRows = readJsonArray(cityHallRelatives, "familiares");

  if (hasCityHallRelatives && cityHallRelativeRows.length === 0) {
    throw new HttpError(
      400,
      "Debes registrar los datos de familiares que trabajan en la alcaldia.",
    );
  }

  for (const relative of cityHallRelativeRows) {
    const record = expectRecord(relative);
    readRequiredString(record, "parentesco", 2, 80);
    readRequiredString(record, "nombreCompleto", 2, 180);
    readRequiredString(record, "cargo", 2, 150);
    readRequiredString(record, "unidad", 2, 180);
  }
}

function readJsonRecord(source: JsonRecord, key: string): JsonRecord {
  const value = source[key];

  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, `La seccion ${key} es obligatoria.`);
  }

  return value as JsonRecord;
}

function readJsonArray(source: JsonRecord, key: string): unknown[] {
  const value = source[key];

  if (!Array.isArray(value)) {
    throw new HttpError(400, `La seccion ${key} no tiene un formato valido.`);
  }

  return value;
}

function validateConditionalDescription(
  source: JsonRecord,
  conditionKey: string,
  descriptionKey: string,
  message: string,
) {
  const enabled = readRequiredBoolean(source, conditionKey);
  const description = readRequiredString(source, descriptionKey, 2, 1000);

  if (enabled && description.toUpperCase() === "NO APLICA") {
    throw new HttpError(400, message);
  }
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

  return payload as JsonRecord;
}

function readRequiredString(
  source: JsonRecord,
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
  source: JsonRecord,
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

function readRequiredBoolean(source: JsonRecord, key: string) {
  const value = source[key];

  if (typeof value !== "boolean") {
    throw new HttpError(400, `Debes enviar el campo ${key}.`);
  }

  return value;
}

function readRequiredFloat(
  source: JsonRecord,
  key: string,
  min: number,
  max: number,
) {
  const value = source[key];
  const parsedValue = typeof value === "number" ? value : Number(value);

  if (!Number.isFinite(parsedValue) || parsedValue < min || parsedValue > max) {
    throw new HttpError(400, `El campo ${key} no es valido.`);
  }

  return parsedValue;
}

function readOptionalIntInRange(
  source: JsonRecord,
  key: string,
  min: number,
  max: number,
) {
  const value = source[key];

  if (value == null || value === "") {
    return null;
  }

  const parsedValue =
    typeof value === "number" ? value : Number.parseInt(`${value}`, 10);

  if (
    !Number.isInteger(parsedValue) ||
    parsedValue < min ||
    parsedValue > max
  ) {
    throw new HttpError(400, `El campo ${key} no es valido.`);
  }

  return parsedValue;
}
