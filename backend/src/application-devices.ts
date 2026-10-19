import { createHash, randomBytes } from 'node:crypto';
import type { IncomingMessage } from 'node:http';
import type { Pool } from 'pg';
import { HttpError } from './http-error.ts';

export function assertApplicationAdminRole(role: string) {
  if (role !== 'ADMIN') throw new HttpError(403, 'Solo el administrador general puede autorizar dispositivos.');
}

const hash = (value: string) => createHash('sha256').update(value).digest('hex');
export function readDeviceProof(request: IncomingMessage) {
  const id = request.headers['x-device-id'];
  const secret = request.headers['x-device-secret'];
  const platform = request.headers['x-device-platform'];
  if (typeof id !== 'string' || !/^[a-zA-Z0-9_-]{8,120}$/.test(id) ||
      typeof secret !== 'string' || !/^[a-f0-9]{64}$/.test(secret) ||
      typeof platform !== 'string' || !['WEB', 'ANDROID', 'IOS', 'WINDOWS', 'MACOS', 'LINUX'].includes(platform)) {
    throw new HttpError(401, 'Actualiza la aplicacion e inicia sesion para vincular este dispositivo.');
  }
  return { id, secretHash: hash(secret), platform };
}

export async function bindApplicationDevice(pool: Pool, userId: number, request: IncomingMessage, changeCode?: unknown) {
  const proof = readDeviceProof(request);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Serializes first enrolment and administrator transfers, including two accounts on one device.
    await client.query('SELECT pg_advisory_xact_lock(9162026)');
    const { rows: [binding] } = await client.query('SELECT * FROM aplicacion_dispositivos WHERE usuario_id=$1 FOR UPDATE', [userId]);
    if (binding?.device_id != null) {
      if (binding.device_id !== proof.id || binding.secret_hash !== proof.secretHash) {
        throw new HttpError(403, 'Tu cuenta esta vinculada a otro dispositivo. Solicita el cambio al administrador.');
      }
    } else {
      if (binding && (!binding.cambio_hash || typeof changeCode !== 'string' ||
          hash(changeCode.trim()) !== binding.cambio_hash || new Date(binding.cambio_expira).getTime() <= Date.now())) {
        throw new HttpError(403, 'Ingresa el codigo de cambio vigente entregado por el administrador.');
      }
      const occupied = await client.query('SELECT 1 FROM aplicacion_dispositivos WHERE device_id=$1 AND usuario_id<>$2', [proof.id, userId]);
      if (occupied.rowCount) throw new HttpError(403, 'Este dispositivo ya esta vinculado a otra cuenta. Contacta al administrador.');
      await client.query(`INSERT INTO aplicacion_dispositivos (usuario_id,device_id,secret_hash,plataforma,vinculado_en)
        VALUES ($1,$2,$3,$4,NOW()) ON CONFLICT (usuario_id) DO UPDATE SET device_id=$2,secret_hash=$3,
        plataforma=$4,vinculado_en=NOW(),cambio_hash=NULL,cambio_expira=NULL,biometric_hash=NULL,biometric_expira=NULL`,
        [userId, proof.id, proof.secretHash, proof.platform]);
    }
    await client.query('COMMIT');
    return proof.id;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
}

export async function assertApplicationDevice(pool: Pool, userId: number, tokenDevice: string | null, request: IncomingMessage) {
  const proof = readDeviceProof(request);
  if (tokenDevice !== proof.id) throw new HttpError(401, 'La sesion no pertenece a este dispositivo.');
  const result = await pool.query('SELECT 1 FROM aplicacion_dispositivos WHERE usuario_id=$1 AND device_id=$2 AND secret_hash=$3', [userId, proof.id, proof.secretHash]);
  if (!result.rowCount) throw new HttpError(401, 'Dispositivo no autorizado. Inicia sesion o solicita el cambio al administrador.');
}

export async function authorizeDeviceTransfer(pool: Pool, userId: number, adminId: number, reason: string) {
  const code = randomBytes(16).toString('hex');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(9162026)');
    const user = await client.query('SELECT id FROM usuarios WHERE id=$1 FOR UPDATE', [userId]);
    if (!user.rowCount) throw new HttpError(404, 'Usuario no encontrado.');
    await client.query(`INSERT INTO aplicacion_cambios (usuario_id,administrador_id,dispositivo_anterior,motivo)
      VALUES ($1,$2,(SELECT device_id FROM aplicacion_dispositivos WHERE usuario_id=$1),$3)`, [userId, adminId, reason]);
    await client.query(`INSERT INTO aplicacion_dispositivos (usuario_id,cambio_hash,cambio_expira) VALUES ($1,$2,NOW()+INTERVAL '24 hours')
      ON CONFLICT (usuario_id) DO UPDATE SET device_id=NULL,secret_hash=NULL,plataforma=NULL,vinculado_en=NULL,
      biometric_hash=NULL,biometric_expira=NULL,cambio_hash=$2,cambio_expira=NOW()+INTERVAL '24 hours'`, [userId, hash(code)]);
    await client.query('UPDATE usuarios SET session_version=session_version+1 WHERE id=$1', [userId]);
    await client.query('UPDATE usuario_sesiones_dispositivo SET revoked_at=NOW(),updated_at=NOW() WHERE usuario_id=$1', [userId]);
    await client.query('COMMIT');
    return { code, expiresInHours: 24 };
  } catch (error) { await client.query('ROLLBACK'); throw error; }
  finally { client.release(); }
}

export async function enrollBiometric(pool: Pool, userId: number, deviceId: string, passwordHash: string) {
  const secret = randomBytes(32).toString('hex');
  const result = await pool.query(`UPDATE aplicacion_dispositivos SET biometric_hash=$3,biometric_password_hash=$4,biometric_expira=NOW()+INTERVAL '90 days'
    WHERE usuario_id=$1 AND device_id=$2 AND plataforma IN ('ANDROID','IOS')`, [userId, deviceId, hash(secret), hash(passwordHash)]);
  if (!result.rowCount) throw new HttpError(403, 'Activa la huella desde tu celular autorizado.');
  return secret;
}

export async function resolveBiometricUser(pool: Pool, request: IncomingMessage, secret: unknown) {
  const proof = readDeviceProof(request);
  if (typeof secret !== 'string' || !/^[a-f0-9]{64}$/.test(secret)) throw new HttpError(401, 'Ingreso biometrico invalido.');
  const { rows: [binding] } = await pool.query(`SELECT d.usuario_id,d.biometric_password_hash,u.password_hash FROM aplicacion_dispositivos d JOIN usuarios u ON u.id=d.usuario_id WHERE device_id=$1 AND secret_hash=$2
    AND biometric_hash=$3 AND biometric_expira>NOW() AND plataforma IN ('ANDROID','IOS')`, [proof.id, proof.secretHash, hash(secret)]);
  if (!binding || binding.biometric_password_hash !== hash(binding.password_hash)) throw new HttpError(401, 'La huella fue desactivada o vencio. Ingresa con tu contrasena.');
  return { userId: binding.usuario_id as number, deviceId: proof.id };
}
