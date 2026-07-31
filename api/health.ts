import { Pool } from "pg";

export default async function handler(request: any, response: any) {
  if (request.method !== "GET") {
    response.status(405).json({ error: "Metodo no permitido." });
    return;
  }

  const databaseUrl = process.env.DATABASE_URL;

  if (!databaseUrl) {
    response.status(500).json({
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
    response.status(200).json({ status: "ok" });
  } catch (error) {
    response.status(500).json({
      status: "error",
      error: error instanceof Error ? error.message : "Error desconocido.",
    });
  } finally {
    await pool.end();
  }
}
