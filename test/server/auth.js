'use strict';

const bcrypt = require('bcryptjs');
const db = require('./db');

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SHA256_RE = /^[0-9a-f]{64}$/i;
const BCRYPT_ROUNDS = 10;

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/**
 * B2: hash bcrypt yang sah untuk membandingkan saat email tidak terdaftar.
 *
 * Sebelumnya kode memakai string palsy '$2a$10$invalid...' yang tidak pernah
 * bisa dibandingkan dengan bcrypt asli, sehingga jalur "email tidak ada" selesai
 * jauh lebih cepat daripada "email ada". Selisih waktu itu cukup untuk menebak
 * email mana yang terdaftar.
 *
 * Hash dihitung SEKALI saat modul dimuat, lalu dipakai ulang. Jadi respons login
 * membutuhkan satu `bcrypt.compare` sama saja untuk kedua kasus.
 */
const DUMMY_HASH = bcrypt.hashSync('dummy-password-for-timing', BCRYPT_ROUNDS);

/**
 * Password dari klien arrives as SHA-256 hex (sesuai guideline).
 * Server bcrypt-hash ulang nilai itu, jadi hash bocor tetap tidak
 * cukup untuk login. Ini satu-satunya lapis kedua yang kita punya.
 */
function validateCredentials({ email, password }) {
  if (typeof email !== 'string' || !EMAIL_RE.test(email.trim())) {
    throw new HttpError(400, 'Email tidak valid');
  }
  if (typeof password !== 'string' || !SHA256_RE.test(password)) {
    throw new HttpError(400, 'Password harus berupa hash SHA-256 hex (64 karakter)');
  }
  return { email: email.trim().toLowerCase(), password };
}

/**
 * B3: `hash`/`compare` versi async.
 *
 * Versi sinkron (`hashSync`/`compareSync`) memblokir event loop selama proses
 * bcrypt, jadi satu permintaan login bisa menggagalkan semua permintaan lain.
 * Versi async melepas eksekusinya ke thread pool libuv.
 */
async function register({ email, password }) {
  const cred = validateCredentials({ email, password });
  const hash = await bcrypt.hash(cred.password, BCRYPT_ROUNDS);
  try {
    const info = db
      .prepare('INSERT INTO users (email, password_hash) VALUES (?, ?)')
      .run(cred.email, hash);
    return { id: info.lastInsertRowid, email: cred.email };
  } catch (e) {
    if (String(e.message).includes('UNIQUE')) {
      throw new HttpError(409, 'Email sudah terdaftar');
    }
    throw e;
  }
}

async function login({ email, password }) {
  const cred = validateCredentials({ email, password });
  const user = db.prepare('SELECT * FROM users WHERE email = ?').get(cred.email);
  // Pesan error sama untuk email tidak ada maupun password salah,
  // supaya tidak bisa dipakai menebak email yang terdaftar.
  const invalid = new HttpError(401, 'Email atau password salah');
  if (!user) {
    // Tetap jalankan bcrypt terhadap hash yang sah supaya waktu respons tidak
    // membocorkan keberadaan email (B2).
    await bcrypt.compare(cred.password, DUMMY_HASH);
    throw invalid;
  }
  if (!(await bcrypt.compare(cred.password, user.password_hash))) throw invalid;
  return { id: user.id, email: user.email };
}

module.exports = {
  register,
  login,
  HttpError,
  EMAIL_RE,
  SHA256_RE,
  BCRYPT_ROUNDS,
  // Diekspor khusus untuk test B2.
  DUMMY_HASH,
};
