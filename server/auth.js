'use strict';

const bcrypt = require('bcryptjs');
const db = require('./db');

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SHA256_RE = /^[0-9a-f]{64}$/i;

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

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

function register({ email, password }) {
  const cred = validateCredentials({ email, password });
  const hash = bcrypt.hashSync(cred.password, 10);
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

function login({ email, password }) {
  const cred = validateCredentials({ email, password });
  const user = db.prepare('SELECT * FROM users WHERE email = ?').get(cred.email);
  // Pesan error sama untuk email tidak ada maupun password salah,
  // supaya tidak bisa dipakai menebak email yang terdaftar.
  const invalid = new HttpError(401, 'Email atau password salah');
  if (!user) {
    // Tetap jalankan bcrypt agar waktu respons tidak membocorkan keberadaan email.
    bcrypt.compareSync(cred.password, '$2a$10$invalidinvalidinvalidinvalidinvalidinvalidinvalidinvalidiu');
    throw invalid;
  }
  if (!bcrypt.compareSync(cred.password, user.password_hash)) throw invalid;
  return { id: user.id, email: user.email };
}

module.exports = { register, login, HttpError, EMAIL_RE, SHA256_RE };
