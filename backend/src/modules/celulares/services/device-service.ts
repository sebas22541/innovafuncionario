import type { Pool } from "pg";
import { HttpError } from "../../../http-error.ts";
import type { DeviceHeartbeatInput } from "../types/device-types.ts";

type DeviceServiceConfig = {
  pool: Pool;
  onlineThresholdMs: number;
  buildUserDisplayName: (user: any) => string;
};

let deviceServiceConfig: DeviceServiceConfig | null = null;

export function configureDeviceService(config: DeviceServiceConfig) {
  deviceServiceConfig = config;
}

export async function registerDeviceHeartbeat(
  userId: number,
  input: DeviceHeartbeatInput,
) {
  const config = getConfig();
  const client = await config.pool.connect();

  try {
    await client.query("BEGIN");

    const result = await client.query<{ force_logout: boolean }>(
      `
        INSERT INTO "celulares_asistencia" (
          "device_id",
          "usuario_id",
          "platform",
          "manufacturer",
          "model",
          "android_sdk",
          "battery_level",
          "is_charging",
          "brightness",
          "kiosk_enabled",
          "last_seen_at",
          "updated_at"
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT ("device_id") DO UPDATE SET
          "usuario_id" = EXCLUDED."usuario_id",
          "platform" = EXCLUDED."platform",
          "manufacturer" = EXCLUDED."manufacturer",
          "model" = EXCLUDED."model",
          "android_sdk" = EXCLUDED."android_sdk",
          "battery_level" = EXCLUDED."battery_level",
          "is_charging" = EXCLUDED."is_charging",
          "brightness" = EXCLUDED."brightness",
          "kiosk_enabled" = EXCLUDED."kiosk_enabled",
          "last_seen_at" = CURRENT_TIMESTAMP,
          "updated_at" = CURRENT_TIMESTAMP
        RETURNING "logout_requested_at" IS NOT NULL AS "force_logout"
      `,
      [
        input.deviceId,
        userId,
        input.platform,
        input.manufacturer,
        input.model,
        input.androidSdk,
        input.batteryLevel,
        input.isCharging,
        input.brightness,
        input.kioskEnabled,
      ],
    );
    const forceLogout = result.rows[0]?.force_logout === true;

    await client.query(
      `
        DELETE FROM "celulares_asistencia"
        WHERE "usuario_id" = $1
          AND "device_id" <> $2
      `,
      [userId, input.deviceId],
    );

    if (forceLogout) {
      await client.query(
        `
          UPDATE "celulares_asistencia"
          SET "logout_requested_at" = NULL,
              "logout_requested_by_id" = NULL,
              "kiosk_enabled" = FALSE,
              "last_seen_at" = CURRENT_TIMESTAMP - ($2::int * INTERVAL '1 millisecond'),
              "updated_at" = CURRENT_TIMESTAMP
          WHERE "device_id" = $1
        `,
        [input.deviceId, config.onlineThresholdMs + 1000],
      );
    }

    await client.query("COMMIT");

    return {
      forceLogout,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function loadManagedDevices() {
  const config = getConfig();
  const result = await config.pool.query(
    `
      SELECT DISTINCT ON (c."usuario_id")
        c."device_id",
        c."usuario_id",
        c."platform",
        c."manufacturer",
        c."model",
        c."android_sdk",
        c."battery_level",
        c."is_charging",
        c."brightness",
        c."kiosk_enabled",
        c."last_seen_at",
        c."logout_requested_at",
        u."nombre_completo",
        u."nombres",
        u."primer_apellido",
        u."segundo_apellido",
        u."tercer_apellido",
        u."ci"
      FROM "celulares_asistencia" c
      INNER JOIN "usuarios" u ON u."id" = c."usuario_id"
      WHERE u."rol" = 'ALMUERZO'
      ORDER BY c."usuario_id", c."last_seen_at" DESC, c."id" DESC
    `,
  );

  return result.rows.map(serializeManagedDevice).sort((left, right) => {
    if (left.isOnline !== right.isOnline) {
      return left.isOnline ? -1 : 1;
    }

    return right.lastSeenAt.localeCompare(left.lastSeenAt);
  });
}

export async function requestDeviceLogout(
  deviceId: string,
  requesterUserId: number,
) {
  const config = getConfig();
  const result = await config.pool.query(
    `
      UPDATE "celulares_asistencia"
      SET "logout_requested_at" = CURRENT_TIMESTAMP,
          "logout_requested_by_id" = $2,
          "kiosk_enabled" = FALSE,
          "last_seen_at" = CURRENT_TIMESTAMP - ($3::int * INTERVAL '1 millisecond'),
          "updated_at" = CURRENT_TIMESTAMP
      WHERE "device_id" = $1
      RETURNING "device_id"
    `,
    [deviceId, requesterUserId, config.onlineThresholdMs + 1000],
  );

  if (result.rowCount === 0) {
    throw new HttpError(404, "No se encontro el celular seleccionado.");
  }
}

export async function requestDeviceLogin(deviceId: string) {
  const result = await getConfig().pool.query<{ usuario_id: number }>(
    `
      UPDATE "celulares_asistencia"
      SET "logout_requested_at" = NULL,
          "logout_requested_by_id" = NULL,
          "updated_at" = CURRENT_TIMESTAMP
      WHERE "device_id" = $1
      RETURNING "usuario_id"
    `,
    [deviceId],
  );

  const row = result.rows[0];

  if (row == null) {
    throw new HttpError(404, "No se encontro el celular seleccionado.");
  }

  return {
    userId: Number(row.usuario_id),
  };
}

export async function markUserDevicesOffline(userId: number) {
  const config = getConfig();
  await config.pool.query(
    `
      UPDATE "celulares_asistencia"
      SET "logout_requested_at" = NULL,
          "logout_requested_by_id" = NULL,
          "kiosk_enabled" = FALSE,
          "last_seen_at" = CURRENT_TIMESTAMP - ($2::int * INTERVAL '1 millisecond'),
          "updated_at" = CURRENT_TIMESTAMP
      WHERE "usuario_id" = $1
    `,
    [userId, config.onlineThresholdMs + 1000],
  );
}

function serializeManagedDevice(device: any) {
  const config = getConfig();
  const lastSeenAt =
    device.last_seen_at instanceof Date
      ? device.last_seen_at
      : new Date(device.last_seen_at);
  const logoutRequestedAt =
    device.logout_requested_at instanceof Date
      ? device.logout_requested_at
      : device.logout_requested_at == null
        ? null
        : new Date(device.logout_requested_at);
  const userName = config.buildUserDisplayName({
    nombre_completo: device.nombre_completo,
    nombres: device.nombres,
    primer_apellido: device.primer_apellido,
    segundo_apellido: device.segundo_apellido,
    tercer_apellido: device.tercer_apellido,
  });

  return {
    deviceId: device.device_id ?? "",
    userId: Number(device.usuario_id ?? 0),
    userName,
    userCi: device.ci ?? "",
    platform: device.platform ?? "",
    manufacturer: device.manufacturer ?? "",
    model: device.model ?? "",
    androidSdk: nullableNumber(device.android_sdk),
    batteryLevel: nullableNumber(device.battery_level),
    isCharging:
      typeof device.is_charging === "boolean" ? device.is_charging : null,
    brightness: nullableNumber(device.brightness),
    kioskEnabled: device.kiosk_enabled === true,
    isOnline:
      device.kiosk_enabled === true &&
      logoutRequestedAt == null &&
      Date.now() - lastSeenAt.getTime() <= config.onlineThresholdMs,
    lastSeenAt: lastSeenAt.toISOString(),
    logoutRequestedAt: logoutRequestedAt?.toISOString() ?? null,
  };
}

function nullableNumber(value: unknown) {
  if (typeof value === "number") {
    return value;
  }

  if (typeof value === "string" && value.trim().length > 0) {
    const parsedValue = Number(value);
    return Number.isFinite(parsedValue) ? parsedValue : null;
  }

  return null;
}

function getConfig() {
  if (deviceServiceConfig == null) {
    throw new Error("El servicio de celulares no esta configurado.");
  }

  return deviceServiceConfig;
}
