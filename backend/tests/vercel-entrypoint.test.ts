import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('Vercel exports an idle server and handles iOS and web preflight without database initialization', async () => {
  process.env.VERCEL = '1';
  process.env.NODE_ENV = 'production';
  process.env.DATABASE_URL = 'postgresql://unused:unused@127.0.0.1:1/unused';
  process.env.JWT_SECRET = 'serverless-entrypoint-test';
  const logDir = mkdtempSync(join(tmpdir(), 'innova-vercel-test-'));
  process.env.LOG_DIR = logDir;
  process.env.CORS_ALLOWED_ORIGINS = 'https://innovafuncionario.cochabamba.bo';
  const { server } = await import('../src/index.ts');
  assert.equal(server.listening, false);
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const url = `http://127.0.0.1:${address.port}/api/auth/login`;
    const requests: Record<string, string>[] = [{}, { Origin: 'https://innovafuncionario.cochabamba.bo' }];
    for (const headers of requests) {
      const response = await fetch(url, { method: 'OPTIONS', headers });
      assert.equal(response.status, 204);
    }
    const rejected = await fetch(url, { method: 'OPTIONS', headers: { Origin: 'https://invalid.example' } });
    assert.equal(rejected.status, 403);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    rmSync(logDir, { recursive: true, force: true });
  }
});
