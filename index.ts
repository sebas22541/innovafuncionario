import { Pool } from "pg";

export default async function handler(request: any, response: any) {
  const url = new URL(
    request.url ?? "/",
    `https://${request.headers.host ?? "localhost"}`,
  );

  if (url.pathname === "/api/ping") {
    sendJson(response, 200, { status: "ok", service: "api" });
    return;
  }

  if (url.pathname === "/api/health") {
    await handleHealth(response);
    return;
  }

  sendJson(response, 404, {
    error: "Usa las rutas /api, por ejemplo /api/health.",
  });
}

async function handleHealth(response: any) {
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
