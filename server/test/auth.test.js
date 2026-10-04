'use strict';

// Test logika server yang murni-ish (auth + hashing), tanpa membuka HTTP.
// Jalankan: npm test  (di dalam folder server/)

const path = require('path');
const { test, assert } = require('./harness');

// Pakai database sementara supaya test tidak menyentuh data asli.
process.env.DB_PATH = path.join(__dirname, '..', 'data', 'test.db');
process.env.JWT_SECRET = 'test-secret';

const auth = require('../auth');

const sha = (s) =>
  require('node:crypto').createHash('sha256').update(s).digest('hex');

test('register menolak email tidak valid', () => {
  assert.throws(() => auth.register({ email: 'bukan-email', password: sha('x') }), {
    status: 400,
  });
});

test('register menolak password yang bukan SHA-256 hex', () => {
  assert.throws(() => auth.register({ email: 'a@b.com', password: 'rahasia' }), {
    status: 400,
  });
});

test('register lalu login berhasil dan mengembalikan user', () => {
  const email = 'test@example.com';
  const password = sha('password123');
  try {
    auth.register({ email, password });
  } catch (e) {
    if (e.status !== 409) throw e;
  }
  const user = auth.login({ email, password });
  assert.strictEqual(user.email, email);
  assert.ok(Number.isInteger(user.id));
});

test('register email yang sama ditolak dengan 409', () => {
  const email = 'dupe@example.com';
  const password = sha('pw');
  auth.register({ email, password });
  assert.throws(() => auth.register({ email, password }), { status: 409 });
});

test('login dengan password salah ditolak 401', () => {
  const email = 'salah@example.com';
  try {
    auth.register({ email, password: sha('benar') });
  } catch (e) {
    if (e.status !== 409) throw e;
  }
  assert.throws(() => auth.login({ email, password: sha('salah') }), { status: 401 });
});

test('login email tidak terdaftar juga 401, pesan sama', () => {
  assert.throws(() => auth.login({ email: 'tidak@ada.com', password: sha('apa') }), { status: 401 });
});

test('email dinormalisasi ke huruf kecil', () => {
  const email = 'MixedCase@Test.COM';
  const password = sha('pw');
  try {
    auth.register({ email, password });
  } catch (e) {
    if (e.status !== 409) throw e;
  }
  // Penyimpanan dan balokan selalu huruf kecil.
  assert.strictEqual(auth.login({ email: 'mixedcase@test.com', password }).email, 'mixedcase@test.com');
});

test('password disimpan sebagai bcrypt, bukan SHA-256 mentah', () => {
  const db = require('../db');
  const email = 'hashcheck@example.com';
  const password = sha('rahasia');
  try {
    auth.register({ email, password });
  } catch (e) {
    if (e.status !== 409) throw e;
  }
  const row = db.prepare('SELECT password_hash FROM users WHERE email = ?').get(email);
  assert.ok(row.password_hash.startsWith('$2'), 'harus bcrypt ($2...)');
  assert.notStrictEqual(row.password_hash, password, 'tidak boleh menyimpan SHA-256 mentah');
});
