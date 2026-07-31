import { Pool } from "pg";

export default async function handler(request: any, response: any) {
  if (request.method !== "GET") {
    sendJson(response, 405, { error: "Metodo no permitido." });
    return;
  }

  const databaseUrl = process.env.DATABASE_URL;

  if (!databaseUrl) {
    sendJson(response, 500, {
      status: "error",
      error: "DATABASE_URL no esta definido en Vercel.",
    });
    return;
  }

  const pool = new Pool({
    connectionString: databaseUrl,
    max: 1,
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 1000,
  });

  try {
    await pool.query("SELECT 1");
    sendJson(response, 200, { status: "ok" });
  } catch (error) {
    sendJson(response, 500, {
      status: "error",
      error: error instanceof Error ? error.message : "Error desconocido.",
    });
  } finally {
    await pool.end();
  }
}

function sendJson(response: any, statusCode: number, payload: unknown) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
  });
  response.end(JSON.stringify(payload));
}
