import { createHash, createHmac, randomBytes } from 'node:crypto';
import type { Pool } from 'pg';
import { HttpError } from './http-error.ts';

// No time limit: these sessions end through explicit revocation, not inactivity.
export const refreshSessionSchemaSql = `
  CREATE TABLE IF NOT EXISTS auth_refresh_sessions (
    id BIGSERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    device_id TEXT,
    session_version INTEGER NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    previous_hash TEXT,
    grace_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS auth_refresh_user_idx ON auth_refresh_sessions(user_id);
  CREATE INDEX IF NOT EXISTS auth_refresh_previous_idx ON auth_refresh_sessions(previous_hash);
`;

export type RefreshIdentity = { user_id: number; device_id: string | null; session_version: number };
type RefreshRow = RefreshIdentity & {
  id: string; token_hash: string; previous_hash: string | null; grace_until: Date | null;
};
const hash = (token: string) => createHash('sha256').update(token).digest('hex');
const invalid = () => new HttpError(401, 'La sesion fue revocada o no es valida. Inicia sesion nuevamente.');

export async function issueRefreshSession(pool: Pool, identity: RefreshIdentity) {
  const token = randomBytes(32).toString('hex');
  await pool.query(`INSERT INTO auth_refresh_sessions
    (user_id, device_id, session_version, token_hash) VALUES ($1,$2,$3,$4)`,
  [identity.user_id, identity.device_id, identity.session_version, hash(token)]);
  return token;
}

// Retries after a lost response and concurrent requests share the same successor
// until the successor is used and rotated. A lost response never expires the
// session. Neither secret is stored as plaintext.
export async function rotateRefreshSession(
  pool: Pool, token: unknown, deviceId: string | null, secret: string,
  authorize: (identity: RefreshIdentity) => Promise<unknown>,
) {
  if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token)) throw invalid();
  const digest = hash(token);
  const { rows: [candidate] } = await pool.query<RefreshRow>(
    'SELECT * FROM auth_refresh_sessions WHERE token_hash=$1 OR previous_hash=$1', [digest]);
  if (!candidate || (candidate.device_id !== null && candidate.device_id !== deviceId)) throw invalid();
  // Do not hold a pool connection while authorization queries need that pool.
  await authorize(candidate);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows: [row] } = await client.query<RefreshRow>(
      'SELECT * FROM auth_refresh_sessions WHERE token_hash=$1 OR previous_hash=$1 FOR UPDATE', [digest]);
    if (!row || (row.device_id !== null && row.device_id !== deviceId)) throw invalid();
    const now = Date.now();
    const grace = row.grace_until != null && row.grace_until.getTime() > now;
    let nextToken = token;
    if (row.token_hash !== digest) {
      nextToken = createHmac('sha256', secret).update(`refresh:${token}`).digest('hex');
      if (hash(nextToken) !== row.token_hash) throw invalid();
    } else if (!grace) {
      nextToken = createHmac('sha256', secret).update(`refresh:${token}`).digest('hex');
      await client.query(`UPDATE auth_refresh_sessions SET token_hash=$2,
        previous_hash=$3, grace_until=$4 WHERE id=$1`,
      [row.id, hash(nextToken), digest, new Date(now + 60000)]);
    }
    await client.query('COMMIT');
    return { identity: row as RefreshIdentity, refreshToken: nextToken };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
}
