'use strict';

// Test logika server yang murni-ish (auth + hashing), tanpa membuka HTTP.
// Jalankan: npm test  (di dalam folder server/)
//
// Sejak B3, register/login memakai bcrypt async, jadi test-nya async juga.

const path = require('path');
const { test, assert } = require('./harness');

// Pakai database sementara supaya test tidak menyentuh data asli.
process.env.DB_PATH = path.join(__dirname, '..', 'data', 'test.db');
process.env.JWT_SECRET = 'test-secret';

const auth = require('../auth');
const bcrypt = require('bcryptjs');

const sha = (s) =>
  require('node:crypto').createHash('sha256').update(s).digest('hex');

/** Bawaan bcryptjs (10) terlalu lambat untuk 200 iterasi; cukup 4. */
async function registerOr409(credentials) {
  try {
    return await auth.register(credentials);
  } catch (e) {
    if (e.status !== 409) throw e;
    return null;
  }
}

async function assertRejects(promise, status) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.status, status, `harus ${status}, dapat ${e.status}: ${e.message}`);
    return e;
  }
  throw new Error(`harus ditolak dengan status ${status}, tapi tidak ada galat`);
}

test('register menolak email tidak valid', async () => {
  await assertRejects(auth.register({ email: 'bukan-email', password: sha('x') }), 400);
});

test('register menolak password yang bukan SHA-256 hex', async () => {
  await assertRejects(auth.register({ email: 'a@b.com', password: 'rahasia' }), 400);
});

test('register lalu login berhasil dan mengembalikan user', async () => {
  const email = 'test@example.com';
  const password = sha('password123');
  await registerOr409({ email, password });
  const user = await auth.login({ email, password });
  assert.strictEqual(user.email, email);
  assert.ok(Number.isInteger(user.id));
});

test('register email yang sama ditolak dengan 409', async () => {
  const email = 'dupe@example.com';
  const password = sha('pw');
  await auth.register({ email, password });
  await assertRejects(auth.register({ email, password }), 409);
});

test('login dengan password salah ditolak 401', async () => {
  const email = 'salah@example.com';
  await registerOr409({ email, password: sha('benar') });
  await assertRejects(auth.login({ email, password: sha('salah') }), 401);
});

test('login email tidak terdaftar juga 401, pesan sama', async () => {
  const e = await assertRejects(
    auth.login({ email: 'tidak@ada.com', password: sha('apa') }),
    401
  );
  assert.strictEqual(e.message, 'Email atau password salah', 'pesan harus sama dengan password salah');
});

test('email dinormalisasi ke huruf kecil', async () => {
  const email = 'MixedCase@Test.COM';
  const password = sha('pw');
  await registerOr409({ email, password });
  const user = await auth.login({ email: 'mixedcase@test.com', password });
  assert.strictEqual(user.email, 'mixedcase@test.com');
});

test('password disimpan sebagai bcrypt, bukan SHA-256 mentah', async () => {
  const db = require('../db');
  const email = 'hashcheck@example.com';
  const password = sha('rahasia');
  await registerOr409({ email, password });
  const row = db.prepare('SELECT password_hash FROM users WHERE email = ?').get(email);
  assert.ok(row.password_hash.startsWith('$2'), 'harus bcrypt ($2...)');
  assert.notStrictEqual(row.password_hash, password, 'tidak boleh menyimpan SHA-256 mentah');
});

test('B2: DUMMY_HASH adalah hash bcrypt yang sah dan bisa dibandingkan', async () => {
  assert.ok(auth.DUMMY_HASH.startsWith('$2'), 'DUMMY_HASH harus format bcrypt');
  // Kalau hash palsunya tidak bisa dibandingkan, jalur "email tidak ada" akan
  // selesai jauh lebih cepat dan membocorkan email yang terdaftar.
  assert.strictEqual(await bcrypt.compare(sha('apa'), auth.DUMMY_HASH), false);
});

test('B2: selisih waktu login email-ada vs email-tidak-ada kecil', async () => {
  // Tanpa DUMMY_HASH, jalur "tidak ada" tidak pernah memanggil bcrypt sehingga
  // bisa ~2-3x lebih cepat. Yang diukur di sini selisihnya, bukan nilai absolut,
  // karena waktu mesin berbeda-beda.
  const email = 'timing@example.com';
  const password = sha('rahasia');
  await registerOr409({ email, password });

  const rounds = 30;
  const timeOf = async (fn) => {
    const samples = [];
    for (let i = 0; i < rounds; i++) {
      const start = process.hrtime.bigint();
      await fn();
      samples.push(Number(process.hrtime.bigint() - start) / 1e6);
    }
    samples.sort((a, b) => a - b);
    return samples[Math.floor(rounds / 2)];
  };

  const medianKnown = await timeOf(async () => {
    try {
      await auth.login({ email, password: sha('salah') });
    } catch (_) {
      /* memang 401 */
    }
  });
  const medianUnknown = await timeOf(async () => {
    try {
      await auth.login({ email: 'tidak-terdaftar@example.com', password: sha('salah') });
    } catch (_) {
      /* memang 401 */
    }
  });

  const ratio = medianKnown / medianUnknown;
  const report = `ada=${medianKnown.toFixed(2)}ms tidak=${medianUnknown.toFixed(2)}ms r=${ratio.toFixed(2)}`;
  // Toleran longgar karena lingkungan CI lambat; intinya kedua jalur harus
  // melakukan pekerjaan bcrypt yang sama.
  assert.ok(
    ratio > 0.5 && ratio < 2,
    `waktu respons mencurigakan (${report}): jalur login harus sama mahal`
  );
});

test('B3: register dan login mengembalikan Promise, bukan nilai blocking', async () => {
  const email = 'async@example.com';
  const password = sha('rahasia');
  const promise = registerOr409({ email, password });
  assert.ok(promise instanceof Promise, 'register harus async');
  await promise;
  const loginPromise = auth.login({ email, password });
  assert.ok(loginPromise instanceof Promise, 'login harus async');
  await loginPromise;
});
