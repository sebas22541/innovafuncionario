import { createHmac, timingSafeEqual } from 'node:crypto';
import { HttpError } from './http-error.ts';

// Expired legacy tokens may only be upgraded by /api/auth/refresh after
// signature verification and database revocation checks. New access tokens
// always expire, including when the compatibility option is requested.
export function verifySessionJwt(token: string, secret: string, now = Math.floor(Date.now() / 1000), requireDevice = true, allowExpiredLegacy = false) {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) throw new Error();
    const [header, body, signature] = parts;
    const metadata = JSON.parse(Buffer.from(header, 'base64url').toString());
    if (metadata.alg !== 'HS256' || metadata.typ !== 'JWT') throw new Error();
    const expected = createHmac('sha256', secret).update(`${header}.${body}`).digest('base64url');
    if (signature.length !== expected.length || !timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) throw new Error();
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString());
    if (!Number.isSafeInteger(payload.sub) || payload.sub <= 0 ||
        !Number.isSafeInteger(payload.exp) ||
        (payload.exp <= now && !(allowExpiredLegacy && payload.token_use == null)) ||
        (payload.token_use != null && payload.token_use !== 'access') ||
        !Number.isSafeInteger(payload.iat) || payload.iat > now + 60 ||
        !Number.isSafeInteger(payload.sv) || payload.sv < 0 ||
        (requireDevice && (typeof payload.did !== 'string' || !/^[a-zA-Z0-9_-]{8,120}$/.test(payload.did))) ||
        typeof payload.email !== 'string') throw new Error();
    return { sub: payload.sub as number, exp: payload.exp as number, iat: payload.iat as number,
      sv: payload.sv as number, did: typeof payload.did === 'string' ? payload.did : null, email: payload.email.trim().toLowerCase(),
      rol: typeof payload.rol === 'string' ? payload.rol : '',
      legacy: payload.token_use == null };
  } catch (_) { throw new HttpError(401, 'Sesion invalida o expirada.'); }
}
