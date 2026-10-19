import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { test } from 'node:test';
import { verifySessionJwt } from '../src/session-jwt.ts';

const claims = { sub: 1, email: 'user@example.test', sv: 2, iat: 100, exp: 200 };
function sign(payload: object, secret = 'current-key') {
  const data = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url')
    + '.' + Buffer.from(JSON.stringify(payload)).toString('base64url');
  return data + '.' + createHmac('sha256', secret).update(data).digest('base64url');
}
const upgrade = (token: string) => verifySessionJwt(token, 'current-key', 300, false, true);

test('legacy upgrade accepts an expired token with a valid current signature', () => {
  const token = sign(claims);
  assert.equal(upgrade(token).sub, 1);
  assert.throws(() => verifySessionJwt(token, 'current-key', 300, false));
  assert.throws(() => upgrade(sign(claims, 'previous-key')));
});

test('legacy upgrade rejects incorrect signatures and missing session claims', () => {
  const token = sign(claims);
  assert.throws(() => upgrade(token.slice(0, token.lastIndexOf('.') + 1) + 'incorrect'));
  assert.throws(() => upgrade(sign({ sub: 1, email: claims.email })));
});

test('legacy upgrade preserves identity and revocation claims', () => {
  const payload = upgrade(sign({ ...claims, did: 'device_123' }));
  assert.equal(payload.sv, 2);
  assert.equal(payload.did, 'device_123');
  assert.equal(payload.email, claims.email);
});

test('legacy upgrade rejects malformed tokens and invalid identities', () => {
  for (const token of ['invalid', 'a.not-json.b', sign({ ...claims, sub: 0 }),
    sign({ ...claims, sv: -1 }), sign({ ...claims, email: null })]) {
    assert.throws(() => upgrade(token));
  }
});
