import type { Pool } from "pg";

import { HttpError } from "../../../http-error.ts";
import type { PlaceInput } from "../types/place-types.ts";

type PlaceServiceConfig = {
  pool: Pool;
  referenceCacheTtlMs: number;
};

type CacheEntry<T> = {
  value: T;
  expiresAt: number;
};

let placeServiceConfig: PlaceServiceConfig | null = null;
let placesCache: CacheEntry<any[]> | null = null;

export function configurePlaceService(config: PlaceServiceConfig) {
  placeServiceConfig = config;
}

export async function loadSerializedPlaces() {
  const cachedPlaces = readCacheValue(placesCache);

  if (cachedPlaces != null) {
    return cachedPlaces;
  }

  const config = getPlaceServiceConfig();
  const result = await config.pool.query(
    `
      SELECT
        l."id",
        l."oficina_id",
        l."nombre",
        l."latitud",
        l."longitud",
        l."radio_metros",
        l."activo",
        l."created_at",
        l."updated_at",
        COALESCE(
          jsonb_agg(
            jsonb_build_object(
              'id', o."id",
              'nombre', o."oficina",
              'codigo', o."cod",
              'nivel', o."nivel"
            )
            ORDER BY o."cod", o."oficina"
          ) FILTER (WHERE o."id" IS NOT NULL),
          '[]'::jsonb
        ) AS "oficinas"
        ,COALESCE(
          jsonb_agg(DISTINCT lue."usuario_id")
          FILTER (WHERE lue."usuario_id" IS NOT NULL),
          '[]'::jsonb
        ) AS "usuario_ids_excluidos",
        COALESCE(
          (
            SELECT jsonb_agg(
              jsonb_build_object(
                'id', lp."id",
                'nombre', lp."nombre"
              )
              ORDER BY lp."orden", lp."id"
            )
            FROM "lugar_pisos" lp
            WHERE lp."lugar_id" = l."id"
          ),
          '[]'::jsonb
        ) AS "pisos"
      FROM "lugares" l
      LEFT JOIN "lugar_oficinas" lo ON lo."lugar_id" = l."id"
      LEFT JOIN "oficinas" o ON o."id" = lo."oficina_id"
      LEFT JOIN "lugar_usuario_exclusiones" lue ON lue."lugar_id" = l."id"
      GROUP BY l."id"
      ORDER BY l."activo" DESC, l."nombre" ASC, l."id" ASC
    `,
  );
  const places = result.rows.map(serializePlaceRow);

  placesCache = createCacheEntry(places, config.referenceCacheTtlMs);

  return places;
}

export async function createPlace(input: PlaceInput) {
  const config = getPlaceServiceConfig();

  await assertPlaceOfficesExist(input.oficinaIds);
  await assertExcludedUsersExist(input.usuarioIdsExcluidos);
  const result = await config.pool.query(
    `
      INSERT INTO "lugares" (
        "oficina_id",
        "nombre",
        "latitud",
        "longitud",
        "radio_metros",
        "activo"
      )
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING "id"
    `,
    [
      input.oficinaId,
      input.nombre,
      input.latitud,
      input.longitud,
      input.radioMetros,
      input.activo,
    ],
  );

  const placeId = result.rows[0]?.id;

  await replacePlaceOffices(placeId, input.oficinaIds);
  await replacePlaceUserExclusions(placeId, input.usuarioIdsExcluidos);
  await replacePlaceFloors(placeId, input.pisos);
  placesCache = null;

  return loadSerializedPlaceById(placeId);
}

export async function updatePlace(placeId: number, input: PlaceInput) {
  const config = getPlaceServiceConfig();

  await assertPlaceOfficesExist(input.oficinaIds);
  await assertExcludedUsersExist(input.usuarioIdsExcluidos);
  const result = await config.pool.query(
    `
      UPDATE "lugares"
          SET "oficina_id" = $2,
          "nombre" = $3,
          "latitud" = $4,
          "longitud" = $5,
          "radio_metros" = $6,
          "activo" = $7,
          "updated_at" = CURRENT_TIMESTAMP
      WHERE "lugares"."id" = $1
      RETURNING "lugares"."id"
    `,
    [
      placeId,
      input.oficinaId,
      input.nombre,
      input.latitud,
      input.longitud,
      input.radioMetros,
      input.activo,
    ],
  );

  if (result.rowCount === 0) {
    throw new HttpError(404, "No se encontro el lugar seleccionado.");
  }

  await replacePlaceOffices(placeId, input.oficinaIds);
  await replacePlaceUserExclusions(placeId, input.usuarioIdsExcluidos);
  await replacePlaceFloors(placeId, input.pisos);
  placesCache = null;

  return loadSerializedPlaceById(placeId);
}

export async function setPlaceActive(placeId: number, active: boolean) {
  const config = getPlaceServiceConfig();
  const result = await config.pool.query(
    `
      UPDATE "lugares"
      SET "activo" = $2,
          "updated_at" = CURRENT_TIMESTAMP
      WHERE "id" = $1
      RETURNING "id"
    `,
    [placeId, active],
  );

  if (result.rowCount === 0) {
    throw new HttpError(404, "No se encontro el lugar seleccionado.");
  }

  placesCache = null;

  return loadSerializedPlaceById(placeId);
}

export async function deletePlace(placeId: number) {
  const place = await loadSerializedPlaceById(placeId);
  const config = getPlaceServiceConfig();
  const result = await config.pool.query(
    `DELETE FROM "lugares" WHERE "id" = $1`,
    [placeId],
  );

  if (result.rowCount === 0) {
    throw new HttpError(404, "No se encontro el lugar seleccionado.");
  }

  placesCache = null;

  return place;
}

export async function loadPlaceName(placeId: number) {
  const config = getPlaceServiceConfig();
  const result = await config.pool.query(
    `SELECT "nombre" FROM "lugares" WHERE "id" = $1 LIMIT 1`,
    [placeId],
  );

  return normalizeOptionalText(result.rows[0]?.nombre) ?? null;
}

export async function loadPlaceFloorName(placeId: number, floorId: number) {
  const config = getPlaceServiceConfig();
  const result = await config.pool.query(
    `
      SELECT "nombre"
      FROM "lugar_pisos"
      WHERE "id" = $1
        AND "lugar_id" = $2
      LIMIT 1
    `,
    [floorId, placeId],
  );

  return normalizeOptionalText(result.rows[0]?.nombre) ?? null;
}

export async function assertOfficeBelongsToPlace(
  officeId: number | null,
  placeId: number | null,
  floorId?: number | null,
  userId?: number | null,
) {
  if (placeId == null) {
    return;
  }

  if (officeId == null) {
    throw new HttpError(
      403,
      "Este funcionario no tiene una oficina asignada para validar el lugar.",
    );
  }

  const config = getPlaceServiceConfig();
  const result = await config.pool.query(
    `
      SELECT l."nombre"
      FROM "lugares" l
      INNER JOIN "lugar_oficinas" lo ON lo."lugar_id" = l."id"
      WHERE l."id" = $1
        AND l."activo" = TRUE
        AND lo."oficina_id" = $2
        AND NOT EXISTS (
          SELECT 1
          FROM "lugar_usuario_exclusiones" lue
          WHERE lue."lugar_id" = l."id"
            AND lue."usuario_id" = $3
        )
      LIMIT 1
    `,
    [placeId, officeId, userId ?? 0],
  );

  if (result.rowCount === 0) {
    throw new HttpError(
      403,
      "Usted no pertenece a ese lugar para escanear este QR.",
    );
  }
}

async function replacePlaceUserExclusions(placeId: number, userIds: number[]) {
  const config = getPlaceServiceConfig();
  const client = await config.pool.connect();

  try {
    await client.query("BEGIN");
    await client.query(
      `DELETE FROM "lugar_usuario_exclusiones" WHERE "lugar_id" = $1`,
      [placeId],
    );

    if (userIds.length > 0) {
      await client.query(
        `
          INSERT INTO "lugar_usuario_exclusiones" ("lugar_id", "usuario_id")
          SELECT $1, unnest($2::int[])
          ON CONFLICT DO NOTHING
        `,
        [placeId, userIds],
      );
    }

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function assertRegistrationLocationInsidePlace(input: {
  placeId: number | null;
  latitud: number | null;
  longitud: number | null;
  accuracy: number | null;
}) {
  if (input.placeId == null) {
    return;
  }

  if (input.latitud == null || input.longitud == null) {
    throw new HttpError(
      403,
      "No se puede registrar porque no se recibio tu ubicacion actual.",
    );
  }

  const config = getPlaceServiceConfig();
  const result = await config.pool.query(
    `
      SELECT "latitud", "longitud", "radio_metros", "nombre"
      FROM "lugares"
      WHERE "id" = $1
        AND "activo" = TRUE
      LIMIT 1
    `,
    [input.placeId],
  );
  const place = result.rows[0];

  if (place == null) {
    throw new HttpError(404, "No se encontro el lugar del QR.");
  }

  const distance = calculateDistanceMeters(
    input.latitud,
    input.longitud,
    Number(place.latitud),
    Number(place.longitud),
  );
  const allowedRadius = Number(place.radio_metros);
  const effectiveDistance = Math.max(0, distance - (input.accuracy ?? 0));

  if (!Number.isFinite(allowedRadius) || effectiveDistance > allowedRadius) {
    throw new HttpError(
      403,
      `No se puede registrar porque no estas dentro del rango de ${place.nombre}.`,
    );
  }
}

async function assertExcludedUsersExist(userIds: number[]) {
  if (userIds.length === 0) {
    return;
  }

  const config = getPlaceServiceConfig();
  const result = await config.pool.query(
    `SELECT "id" FROM "usuarios" WHERE "id" = ANY($1::int[])`,
    [userIds],
  );

  if (result.rowCount !== userIds.length) {
    throw new HttpError(400, "Uno o mas funcionarios excluidos no existen.");
  }
}

async function loadSerializedPlaceById(placeId: number) {
  const places = await loadSerializedPlaces();
  const place = places.find((item: any) => item.id === placeId);

  if (place == null) {
    throw new HttpError(404, "No se encontro el lugar seleccionado.");
  }

  return place;
}

async function replacePlaceOffices(placeId: number, officeIds: number[]) {
  const config = getPlaceServiceConfig();
  const client = await config.pool.connect();

  try {
    await client.query("BEGIN");
    await client.query(
      `DELETE FROM "lugar_oficinas" WHERE "lugar_id" = $1`,
      [placeId],
    );

    if (officeIds.length > 0) {
      await client.query(
        `
          INSERT INTO "lugar_oficinas" ("lugar_id", "oficina_id")
          SELECT $1, unnest($2::int[])
          ON CONFLICT DO NOTHING
        `,
        [placeId, officeIds],
      );
    }

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function replacePlaceFloors(
  placeId: number,
  floors: PlaceInput["pisos"],
) {
  const config = getPlaceServiceConfig();
  const client = await config.pool.connect();

  try {
    await client.query("BEGIN");
    const requestedExistingIds = floors
      .map((floor) => floor.id)
      .filter((id): id is number => id != null);

    if (requestedExistingIds.length > 0) {
      const existingResult = await client.query(
        `
          SELECT "id"
          FROM "lugar_pisos"
          WHERE "lugar_id" = $1
            AND "id" = ANY($2::int[])
        `,
        [placeId, requestedExistingIds],
      );

      if (existingResult.rowCount !== requestedExistingIds.length) {
        throw new HttpError(400, "Uno o mas pisos no pertenecen al lugar.");
      }
    }

    await client.query(
      `
        DELETE FROM "lugar_pisos"
        WHERE "lugar_id" = $1
          AND NOT ("id" = ANY($2::int[]))
      `,
      [placeId, requestedExistingIds],
    );

    for (const [index, floor] of floors.entries()) {
      let floorId = floor.id;

      if (floorId == null) {
        const result = await client.query(
          `
            INSERT INTO "lugar_pisos" ("lugar_id", "nombre", "orden")
            VALUES ($1, $2, $3)
            RETURNING "id"
          `,
          [placeId, floor.nombre, index],
        );
        floorId = result.rows[0]?.id;
      } else {
        await client.query(
          `
            UPDATE "lugar_pisos"
            SET "nombre" = $3,
                "orden" = $4,
                "updated_at" = CURRENT_TIMESTAMP
            WHERE "id" = $1
              AND "lugar_id" = $2
          `,
          [floorId, placeId, floor.nombre, index],
        );
      }
    }

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function assertPlaceOfficesExist(officeIds: number[]) {
  if (officeIds.length === 0) {
    throw new HttpError(400, "Selecciona una o mas oficinas para el lugar.");
  }

  const config = getPlaceServiceConfig();
  const result = await config.pool.query(
    `SELECT "id" FROM "oficinas" WHERE "id" = ANY($1::int[])`,
    [officeIds],
  );

  if (result.rowCount !== officeIds.length) {
    throw new HttpError(400, "Una o mas oficinas seleccionadas no existen.");
  }
}

function getPlaceServiceConfig() {
  if (placeServiceConfig == null) {
    throw new Error("El servicio de lugares no esta configurado.");
  }

  return placeServiceConfig;
}

function serializePlaceRow(row: any) {
  return {
    id: Number(row.id),
    oficinaId: row.oficina_id == null ? null : Number(row.oficina_id),
    nombre: row.nombre ?? "",
    latitud: Number(row.latitud),
    longitud: Number(row.longitud),
    radioMetros: Number(row.radio_metros),
    activo: row.activo === true,
    oficinas: Array.isArray(row.oficinas) ? row.oficinas : [],
    pisos: Array.isArray(row.pisos) ? row.pisos : [],
    usuarioIdsExcluidos: Array.isArray(row.usuario_ids_excluidos)
      ? row.usuario_ids_excluidos.map((id: unknown) => Number(id))
      : [],
    createdAt: row.created_at?.toISOString?.() ?? String(row.created_at),
    updatedAt: row.updated_at?.toISOString?.() ?? String(row.updated_at),
  };
}

function calculateDistanceMeters(
  startLat: number,
  startLng: number,
  endLat: number,
  endLng: number,
) {
  const earthRadiusMeters = 6_371_000;
  const startLatRad = toRadians(startLat);
  const endLatRad = toRadians(endLat);
  const deltaLat = toRadians(endLat - startLat);
  const deltaLng = toRadians(endLng - startLng);
  const haversine =
    Math.sin(deltaLat / 2) * Math.sin(deltaLat / 2) +
    Math.cos(startLatRad) *
      Math.cos(endLatRad) *
      Math.sin(deltaLng / 2) *
      Math.sin(deltaLng / 2);

  return (
    earthRadiusMeters *
    2 *
    Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine))
  );
}

function toRadians(value: number) {
  return (value * Math.PI) / 180;
}

function normalizeOptionalText(value: unknown) {
  if (typeof value !== "string") {
    return null;
  }

  const text = value.trim();

  return text.length > 0 ? text : null;
}

function readCacheValue<T>(entry: CacheEntry<T> | null) {
  if (entry == null || entry.expiresAt <= Date.now()) {
    return null;
  }

  return entry.value;
}

function createCacheEntry<T>(value: T, ttlMs: number): CacheEntry<T> {
  return {
    value,
    expiresAt: Date.now() + ttlMs,
  };
}
