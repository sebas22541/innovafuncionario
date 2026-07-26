import { HttpError } from "../../../http-error.ts";
import type { DeviceHeartbeatInput } from "../types/device-types.ts";

export function parseDeviceHeartbeatInput(
  payload: unknown,
): DeviceHeartbeatInput {
  const body = expectRecord(payload);

  return {
    deviceId: readRequiredString(body, "deviceId", 8, 120),
    platform:
      readOptionalString(body, "platform", 1, 30)?.toUpperCase() ?? "UNKNOWN",
    manufacturer: readOptionalString(body, "manufacturer", 0, 120),
    model: readOptionalString(body, "model", 0, 160),
    androidSdk: readOptionalIntInRange(body, "androidSdk", 1, 10_000),
    batteryLevel: readOptionalIntInRange(body, "batteryLevel", 0, 100),
    isCharging: readOptionalBoolean(body, "isCharging"),
    brightness: readOptionalIntInRange(body, "brightness", 0, 100),
    kioskEnabled: readOptionalBoolean(body, "kioskEnabled") ?? false,
  };
}

export function readDeviceIdParam(value: string) {
  const deviceId = decodeURIComponent(value).trim();

  if (deviceId.length < 8 || deviceId.length > 120) {
    throw new HttpError(400, "El celular seleccionado no es valido.");
  }

  return deviceId;
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

function readOptionalIntInRange(
  source: Record<string, unknown>,
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

function readOptionalBoolean(source: Record<string, unknown>, key: string) {
  const value = source[key];

  if (value == null) {
    return null;
  }

  if (typeof value !== "boolean") {
    throw new HttpError(400, `El campo ${key} debe ser booleano.`);
  }

  return value;
}
