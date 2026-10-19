import assert from 'node:assert/strict';
import { test, before, after } from 'node:test';
import { createHmac } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { Pool } from 'pg';
import { issueRefreshSession, rotateRefreshSession, refreshSessionSchemaSql, type RefreshIdentity } from '../src/refresh-sessions.ts';
import { verifySessionJwt } from '../src/session-jwt.ts';

// Isolated database; never loads application credentials or .env files.
const folder = mkdtempSync(join(tmpdir(), 'innova-refresh-test-'));
const bin = process.env.PG_TEST_BIN ?? 'C:/Program Files/PostgreSQL/17/bin';
const pool = new Pool({ host: '127.0.0.1', port: 55494, user: 'postgres', database: 'postgres' });
let started = false;
function pg(command: string, args: string[]) {
  const result = spawnSync(join(bin, command + (process.platform === 'win32' ? '.exe' : '')), args,
    { windowsHide: true, stdio: 'ignore', timeout: 120000 });
  if (result.status !== 0) throw new Error(`Postgres test command failed: ${command}`);
}
before(async () => {
  pg('initdb', ['-D', folder, '-U', 'postgres', '-A', 'trust', '--no-locale', '-E', 'UTF8']);
  pg('pg_ctl', ['-D', folder, '-l', join(folder, 'server.log'), '-o', '-h 127.0.0.1 -p 55494', '-w', 'start']);
  started = true;
  await pool.query(`CREATE TABLE usuarios(id INTEGER PRIMARY KEY, activo BOOLEAN DEFAULT TRUE, session_version INTEGER DEFAULT 0);
    INSERT INTO usuarios(id) VALUES (1); ${refreshSessionSchemaSql}`);
});
after(async () => {
  await pool.end();
  if (started) pg('pg_ctl', ['-D', folder, '-m', 'immediate', '-w', 'stop']);
  if (dirname(resolve(folder)) === resolve(tmpdir()) && folder.startsWith(join(tmpdir(), 'innova-refresh-test-'))) {
    rmSync(folder, { recursive: true, force: true });
  }
});
const identity = { user_id: 1, device_id: 'device_123', session_version: 0 };
async function authorize(session: RefreshIdentity) {
  const { rows: [user] } = await pool.query('SELECT * FROM usuarios WHERE id=$1', [session.user_id]);
  assert.ok(user?.activo && user.session_version === session.session_version, 'revoked identity');
}
const rotate = (token: string, device = identity.device_id) => rotateRefreshSession(pool, token, device, 'test-secret', authorize);

test('permanent session, concurrent rotation, lost response recovery and retired tokens', async () => {
  const original = await issueRefreshSession(pool, identity);
  await pool.query("UPDATE auth_refresh_sessions SET created_at='2000-01-01'");
  const results = await Promise.all(Array.from({ length: 15 }, () => rotate(original)));
  const next = results[0].refreshToken;
  assert.notEqual(original, next);
  assert.ok(results.every(result => result.refreshToken === next));
  const { rows: [stored] } = await pool.query('SELECT * FROM auth_refresh_sessions');
  assert.ok(!JSON.stringify(stored).includes(original));
  assert.ok(!JSON.stringify(stored).includes(next));
  await pool.query("UPDATE auth_refresh_sessions SET grace_until=NOW()-INTERVAL '10 years'");
  assert.equal((await rotate(original)).refreshToken, next, 'lost response can be recovered after a long outage');
  const latest = (await rotate(next)).refreshToken;
  assert.notEqual(latest, next);
  await assert.rejects(rotate(original));
  await assert.rejects(rotate(latest, 'another_device'));
  await pool.query('UPDATE usuarios SET activo=FALSE WHERE id=1');
  await assert.rejects(rotate(latest));
  await pool.query('UPDATE usuarios SET activo=TRUE,session_version=1 WHERE id=1');
  await assert.rejects(rotate(latest));
  await pool.query('UPDATE usuarios SET session_version=0 WHERE id=1');
  await pool.query('DELETE FROM auth_refresh_sessions WHERE user_id=1');
  await assert.rejects(rotate(latest), 'logout deletes the refresh session');
});

function sign(claims: object, secret = 'test-secret') {
  const data = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url') + '.' +
    Buffer.from(JSON.stringify(claims)).toString('base64url');
  return data + '.' + createHmac('sha256', secret).update(data).digest('base64url');
}
test('access expiry is enforced; only signed legacy sessions can be upgraded after expiry', () => {
  const claims = { sub: 1, email: 'test@example.test', sv: 0, did: 'device_123', iat: 100, exp: 200 };
  const access = sign({ ...claims, token_use: 'access' });
  assert.equal(verifySessionJwt(access, 'test-secret', 199).sub, 1);
  assert.throws(() => verifySessionJwt(access, 'test-secret', 200));
  assert.throws(() => verifySessionJwt(access, 'test-secret', 200, false, true));
  assert.equal(verifySessionJwt(sign(claims), 'test-secret', 200, false, true).legacy, true);
  assert.throws(() => verifySessionJwt(sign(claims, 'wrong-key'), 'test-secret', 200, false, true));
  assert.throws(() => verifySessionJwt(sign({ ...claims, token_use: 'refresh' }), 'test-secret', 150));
});
