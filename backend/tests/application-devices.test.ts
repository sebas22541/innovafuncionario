import assert from 'node:assert/strict';
import { test, before, after } from 'node:test';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHmac } from 'node:crypto';
import type { IncomingMessage } from 'node:http';
import { Pool } from 'pg';
import { applicationDeviceSchemaSql } from '../src/application-device-schema.ts';
import { assertApplicationAdminRole, bindApplicationDevice, assertApplicationDevice, authorizeDeviceTransfer, enrollBiometric, resolveBiometricUser, readDeviceProof } from '../src/application-devices.ts';
import { verifySessionJwt } from '../src/session-jwt.ts';

// A disposable local cluster: never reads application or production credentials.
const folder = mkdtempSync(join(tmpdir(), 'innova-device-test-'));
const bin = process.env.PG_TEST_BIN ?? 'C:/Program Files/PostgreSQL/17/bin';
const port = 55493;
const pool = new Pool({ host: '127.0.0.1', port, user: 'postgres', database: 'postgres' });
let started = false;
function pg(command: string, args: string[]) {
  const result = spawnSync(join(bin, command + (process.platform === 'win32' ? '.exe' : '')), args, { encoding: 'utf8', windowsHide: true, stdio: 'ignore', timeout: 120000 });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout || String(result.error));
}
before(async () => {
  pg('initdb', ['-D', folder, '-U', 'postgres', '-A', 'trust', '--no-locale', '-E', 'UTF8']);
  pg('pg_ctl', ['-D', folder, '-l', join(folder, 'server.log'), '-o', `-h 127.0.0.1 -p ${port}`, '-w', 'start']);
  started = true;
  await pool.query(`CREATE TABLE usuarios (id INTEGER PRIMARY KEY,session_version INTEGER NOT NULL DEFAULT 0,password_hash TEXT NOT NULL DEFAULT 'password-hash');
    INSERT INTO usuarios(id) SELECT generate_series(1,12);
    CREATE TABLE usuario_sesiones_dispositivo(usuario_id INTEGER,revoked_at TIMESTAMPTZ,updated_at TIMESTAMPTZ);
    ${applicationDeviceSchemaSql}`);
});
after(async () => {
  await pool.end();
  if (started) pg('pg_ctl', ['-D', folder, '-m', 'immediate', '-w', 'stop']);
  if (dirname(resolve(folder)) === resolve(tmpdir())) rmSync(folder, { recursive: true, force: true });
});
const device = (id: string, secret = 'a'.repeat(64), platform = 'ANDROID') => ({ headers: {
  'x-device-id': id, 'x-device-secret': secret, 'x-device-platform': platform,
}} as unknown as IncomingMessage);
const phone = device('phone_0001');

test('rejects missing device proof', () => {
  assert.throws(() => readDeviceProof({ headers: {} } as IncomingMessage));
});
test('one account and one device with proof on every request', async () => {
  await bindApplicationDevice(pool, 1, phone);
  await bindApplicationDevice(pool, 1, phone);
  await assertApplicationDevice(pool, 1, 'phone_0001', phone);
  await assert.rejects(bindApplicationDevice(pool, 1, device('browser_001', 'b'.repeat(64), 'WEB')));
  await assert.rejects(bindApplicationDevice(pool, 2, phone));
  await assert.rejects(assertApplicationDevice(pool, 1, 'phone_0001', device('phone_0001', 'b'.repeat(64))));
  await assert.rejects(assertApplicationDevice(pool, 1, null, phone));
});
test('concurrent logins cannot bind two devices or two accounts', async () => {
  const first = await Promise.allSettled([bindApplicationDevice(pool, 3, device('phone_0003')), bindApplicationDevice(pool, 3, device('phone_0004'))]);
  assert.equal(first.filter(r => r.status === 'fulfilled').length, 1);
  const second = await Promise.allSettled([bindApplicationDevice(pool, 4, device('phone_0005')), bindApplicationDevice(pool, 5, device('phone_0005'))]);
  assert.equal(second.filter(r => r.status === 'fulfilled').length, 1);
});
test('transfer revokes device and biometrics and requires an expiring single-use code', async () => {
  const bio = await enrollBiometric(pool, 1, 'phone_0001', 'password-hash');
  assert.equal((await resolveBiometricUser(pool, phone, bio)).userId, 1);
  const { code } = await authorizeDeviceTransfer(pool, 1, 12, 'Cambio de celular solicitado');
  await assert.rejects(assertApplicationDevice(pool, 1, 'phone_0001', phone));
  await assert.rejects(resolveBiometricUser(pool, phone, bio));
  await assert.rejects(bindApplicationDevice(pool, 1, phone));
  const next = device('phone_0006');
  await assert.rejects(bindApplicationDevice(pool, 1, next, 'incorrecto'));
  await bindApplicationDevice(pool, 1, next, code);
  await assert.rejects(bindApplicationDevice(pool, 1, phone, code));
  await assertApplicationDevice(pool, 1, 'phone_0006', next);
  assert.equal((await pool.query('SELECT session_version FROM usuarios WHERE id=1')).rows[0].session_version, 1);
  assert.equal((await pool.query('SELECT COUNT(*)::int AS n FROM aplicacion_cambios WHERE usuario_id=1')).rows[0].n, 1);
  const expired = await authorizeDeviceTransfer(pool, 1, 12, 'Otra solicitud');
  await pool.query("UPDATE aplicacion_dispositivos SET cambio_expira=NOW()-INTERVAL '1 second' WHERE usuario_id=1");
  await assert.rejects(bindApplicationDevice(pool, 1, next, expired.code));
});
test('web cannot enroll biometrics; disabled credentials stop working', async () => {
  await bindApplicationDevice(pool, 6, device('browser_006', 'c'.repeat(64), 'WEB'));
  await assert.rejects(enrollBiometric(pool, 6, 'browser_006', 'password-hash'));
  const request = device('phone_0007');
  await bindApplicationDevice(pool, 7, request);
  const secret = await enrollBiometric(pool, 7, 'phone_0007', 'password-hash');
  await pool.query('UPDATE aplicacion_dispositivos SET biometric_hash=NULL WHERE usuario_id=7');
  await assert.rejects(resolveBiometricUser(pool, request, secret));
});
test('JWT rejects forged, expired and unbound sessions', () => {
  const secret = 'test-secret';
  const claims = { sub: 1, email: 'test@example.test', did: 'phone_0001', sv: 0, iat: 100, exp: 200 };
  const sign = (payload: object, key = secret) => {
    const data = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url') + '.' + Buffer.from(JSON.stringify(payload)).toString('base64url');
    return data + '.' + createHmac('sha256', key).update(data).digest('base64url');
  };
  assert.equal(verifySessionJwt(sign(claims), secret, 150).sub, 1);
  assert.throws(() => verifySessionJwt(sign(claims, 'forged'), secret, 150));
  assert.throws(() => verifySessionJwt(sign(claims), secret, 200));
  assert.throws(() => verifySessionJwt(sign({ ...claims, exp: undefined }), secret, 150));
  assert.throws(() => verifySessionJwt(sign({ ...claims, did: null }), secret, 150));
});

test('only the general administrator can authorize transfers', () => {
  assert.doesNotThrow(() => assertApplicationAdminRole('ADMIN'));
  for (const role of ['OPERADOR','CONTROL','ADMIN_SALUD','ADMIN_EVENTUAL','ADMIN_CONSULTOR']) {
    assert.throws(() => assertApplicationAdminRole(role));
  }
});
test('password replacement invalidates biometric credentials', async () => {
  const request = device('phone_0008');
  await bindApplicationDevice(pool, 8, request);
  const secret = await enrollBiometric(pool, 8, 'phone_0008', 'password-hash');
  await pool.query("UPDATE usuarios SET password_hash='new-password-hash' WHERE id=8");
  await assert.rejects(resolveBiometricUser(pool, request, secret));
});
