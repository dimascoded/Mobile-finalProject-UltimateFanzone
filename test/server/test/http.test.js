'use strict';

// Test lewat HTTP sungguhan: start Express di port acak, lalu panggil dengan
// fetch bawaan Node. Ini yang mengunci perilaku B1 (server gagal start tanpa
// JWT_SECRET), B3 (percobaan ke-N dibalas 429), dan B7 (header helmet).
// Jalankan: npm test  (di dalam folder server/)

const path = require('path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { test, assert, out } = require('./harness');

process.env.DB_PATH = path.join(__dirname, '..', 'data', 'test-http.db');
process.env.JWT_SECRET = 'test-secret-http';
// B3 diuji dengan batas kecil supaya tidak perlu 11 permintaan.
process.env.AUTH_RATE_LIMIT = '3';
process.env.AUTH_RATE_WINDOW_MS = '60000';
process.env.TRUST_PROXY_HOPS = '0';

const app = require('../index');
const jwt = require('jsonwebtoken');

const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');

let server;
let baseUrl;

async function start() {
  if (server) return;
  server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
}

function stop() {
  if (server) {
    server.close();
    server = null;
  }
}

async function call(method, url, { body, token, raw, headers: extra } = {}) {
  const headers = {};
  if (body !== undefined) headers['content-type'] = 'application/json';
  if (token) headers.authorization = `Bearer ${token}`;
  Object.assign(headers, extra || {});
  const response = await fetch(`${baseUrl}${url}`, {
    method,
    headers,
    body: raw !== undefined ? raw : body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await response.json();
  } catch (_) {
    /* body bukan JSON */
  }
  return { status: response.status, json, headers: response.headers };
}

test('B1: server gagal start kalau JWT_SECRET tidak diisi', () => {
  const result = spawnSync(process.execPath, ['-e', "require('./index.js')"], {
    cwd: path.join(__dirname, '..'),
    env: { ...process.env, JWT_SECRET: '' },
    encoding: 'utf8',
  });
  assert.notStrictEqual(result.status, 0, 'proses harus berhenti dengan error');
  const stderr = String(result.stderr || '');
  assert.ok(
    stderr.includes('JWT_SECRET'),
    `pesan error harus menyebut JWT_SECRET, dapat: ${stderr.split('\n')[0]}`
  );
});

test('B1: ada .env.example yang menyebut JWT_SECRET', () => {
  const fs = require('node:fs');
  const example = fs.readFileSync(path.join(__dirname, '..', '.env.example'), 'utf8');
  assert.ok(example.includes('JWT_SECRET'), '.env.example harus memuat JWT_SECRET');
});

test('health membalas 200 dan header keamanan helmet aktif', async () => {
  await start();
  const res = await call('GET', '/health');
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.json.ok, true);
  assert.strictEqual(res.headers.get('x-content-type-options'), 'nosniff');
  assert.ok(res.headers.get('content-security-policy'), 'helmet harus memasang CSP');
  stop();
});

test('register, login, dan sync memakai token yang benar', async () => {
  await start();
  const email = `http${Date.now()}@example.com`;
  const password = sha('rahasia');

  const registered = await call('POST', '/auth/register', { body: { email, password } });
  assert.strictEqual(registered.status, 201);
  assert.strictEqual(registered.json.email, email);

  const login = await call('POST', '/auth/login', { body: { email, password } });
  assert.strictEqual(login.status, 200);
  const token = login.json.token;
  assert.ok(token, 'login harus mengembalikan token');
  assert.strictEqual(jwt.verify(token, 'test-secret-http').email, email);

  const sync = await call('POST', '/sync', {
    token,
    body: { expenses: [{ id: 'e1', title: 'Tiket', amountGbp: 10, amountIdr: 1000, category: 'tiket', date: '2026-08-15T00:00:00Z' }] },
  });
  assert.strictEqual(sync.status, 200);
  assert.strictEqual(sync.json.expenses, 1);

  const pulled = await call('GET', '/sync', { token });
  assert.strictEqual(pulled.status, 200);
  assert.strictEqual(pulled.json.expenses.length, 1);
  stop();
});

test('B6: body JSON rusak membalas 400, bukan 500', async () => {
  await start();
  const res = await call('POST', '/sync', {
    raw: '{"expenses": [',
    headers: { 'content-type': 'application/json' },
  });
  assert.strictEqual(res.status, 400, `harus 400, dapat ${res.status}`);
  stop();
});

test('/sync tanpa token ditolak 401', async () => {
  await start();
  const res = await call('GET', '/sync');
  assert.strictEqual(res.status, 401);
  stop();
});

test('token yang ditandatangani dengan kunci lain ditolak 401', async () => {
  await start();
  const forged = jwt.sign({ uid: 1, email: 'korup@example.com' }, 'kunci-orang', { expiresIn: '1h' });
  const res = await call('GET', '/sync', { token: forged });
  assert.strictEqual(res.status, 401);
  stop();
});

test('B6: payload rusak membalas 400 dengan pesan, bukan 500', async () => {
  await start();
  const login = await call('POST', '/auth/login', {
    body: { email: `bad${Date.now()}@example.com`, password: sha('x') },
  });
  // Login email tak dikenal = 401 dan sekaligus memakai satu jatah rate limit.
  assert.strictEqual(login.status, 401);
  const token = jwt.sign({ uid: 1, email: 'a@b.com' }, 'test-secret-http', { expiresIn: '1h' });

  const res = await call('POST', '/sync', { token, body: { expenses: [{ title: 'tanpa id' }] } });
  assert.strictEqual(res.status, 400);
  assert.ok(typeof res.json.error === 'string' && res.json.error.length > 0);
  stop();
});

test('B3: percobaan setelah batas membalas 429', async () => {
  await start();
  const statuses = [];
  // Batasnya 3, dan sebagian jatah sudah dipakai test lain di proses ini,
  // jadi cukup meminta sampai kena 429 lalu memastikan balasannya benar.
  for (let i = 0; i < 12; i++) {
    const res = await call('POST', '/auth/login', {
      body: { email: `ratelimit${i}@example.com`, password: sha('x') },
    });
    statuses.push(res.status);
    if (res.status === 429) {
      assert.ok(res.headers.get('ratelimit'), 'header RateLimit harus ada');
      assert.ok(res.json.error.includes('Terlalu banyak'), 'pesan 429 harus jelas');
      break;
    }
  }
  out(`       status auth berurutan: ${statuses.join(',')}`);
  assert.ok(statuses.includes(429), `harus ada 429 dalam ${statuses.join(',')}`);
  stop();
});
