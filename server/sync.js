'use strict';

const crypto = require('node:crypto');
const db = require('./db');
const { HttpError } = require('./auth');

/**
 * Body POST /sync sesuai sisi Flutter (lib/features/sync/data/sync_repository.dart):
 *   { expenses: [], chain: [], predictions: [], feedback: { kesan, saran } }
 *
 * Semua operasi dibuat idempoten:
 *   - expenses memakai (user_id, local_id) sehingga upload ulang tidak duplikat
 *   - chain memakai PRIMARY KEY (user_id, idx) dengan DO NOTHING sehingga blok
 *     yang sudah ada tidak pernah berubah (B4)
 *   - predictions memakai (user_id, match_id)
 */

const MAX_CHAIN = 5000;
const MAX_EXPENSES = 2000;
const MAX_PREDICTIONS = 1000;
const MAX_TEXT = 200;

const GENESIS_INDEX = 0;
const GENESIS_PREV_HASH = '0'.repeat(64);
const POW_PREFIX = '000';
const SHA256_RE = /^[0-9a-f]{64}$/i;

// ---------------------------------------------------------------- validasi

function bad(message) {
  return new HttpError(400, message);
}

function asArray(value, name, max) {
  if (value == null) return [];
  if (!Array.isArray(value)) throw bad(`${name} harus berupa array`);
  if (value.length > max) {
    throw new HttpError(413, `${name} terlalu banyak (maks ${max} item)`);
  }
  return value;
}

function asObject(value, name) {
  if (value == null || typeof value === 'object' && !Array.isArray(value)) {
    return value ?? {};
  }
  throw bad(`${name} harus berupa objek JSON`);
}

/** String wajib: bukan null, bukan objek, dan ada isinya. */
function requireText(value, name, { max = MAX_TEXT } = {}) {
  if (typeof value !== 'string') throw bad(`${name} harus berupa teks`);
  const text = value.trim();
  if (!text) throw bad(`${name} tidak boleh kosong`);
  if (text.length > max) throw bad(`${name} terlalu panjang (maks ${max} karakter)`);
  return text;
}

function requireInt(value, name, { min = -Infinity, max = Infinity } = {}) {
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw bad(`${name} harus bilangan bulat`);
  }
  if (value < min || value > max) throw bad(`${name} di luar rentang yang diizinkan`);
  return value;
}

function requireNumber(value, name, { min = -Infinity, max = Infinity } = {}) {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw bad(`${name} harus angka`);
  }
  if (value < min || value > max) throw bad(`${name} di luar rentang yang diizinkan`);
  return value;
}

/** String opsional: null/"" jadi null, tapi nilai non-teks tetap ditolak. */
function optionalText(value, name, opts) {
  if (value == null) return null;
  if (typeof value !== 'string') throw bad(`${name} harus berupa teks`);
  const text = value.trim();
  if (!text) return null;
  if (opts && opts.max && text.length > opts.max) {
    throw bad(`${name} terlalu panjang (maks ${opts.max} karakter)`);
  }
  return text;
}

function requireIsoDate(value, name) {
  const text = requireText(value, name, { max: 40 });
  if (Number.isNaN(Date.parse(text))) throw bad(`${name} bukan tanggal yang valid`);
  return text;
}

// ---------------------------------------------------------------- rantai

/**
 * Hash blok harus sama persis dengan `Block.computeHash` di sisi Flutter
 * (lib/features/gamification/data/blockchain.dart):
 *
 *   sha256(index|timestamp|type|JSON.stringify(data)|owner|prevHash|nonce)
 *
 * Notice `JSON.stringify` dipakai apa adanya supaya urutan key sama seperti
 * yang dikirim Dart. Kalau hash tidak cocok, blok ditolak, bukan disimpan.
 */
function computeBlockHash({ index, timestamp, type, dataJson, owner, prevHash, nonce }) {
  return crypto
    .createHash('sha256')
    .update(`${index}|${timestamp}|${type}|${dataJson}|${owner}|${prevHash}|${nonce}`)
    .digest('hex');
}

/**
 * B4: validasi rantai sebelum disimpan.
 *
 * Dua hal yang sebelumnya bisa menimpa data di server:
 *   - blok yang sudah ada bisa ditimpa hash palsu, jadi blok lama bisa "dibuat ulang";
 *   - blok baru bisa tidak nyambung dari rantai lama, jadi `prevHash` tidak merujuk
 *     ke blok sebelumnya.
 *
 * Yang diperiksa di sini: bentuk tiap blok, hash yang dihitung ulang, awalan
 * `000` sebagai bukti proof-of-work, indeks berurutan mulai dari 0, dan
 * `prevHash` menunjuk hash blok sebelumnya.
 */
function validateChain(chain, storedBlocks) {
  let expectedPrev = GENESIS_PREV_HASH;
  let expectedIndex = GENESIS_INDEX;

  for (const raw of chain) {
    const block = asObject(raw, 'chain[]');
    const index = requireInt(block.index, 'chain[].index', { min: 0, max: MAX_CHAIN });
    if (index !== expectedIndex) {
      throw bad(`chain[].index harus berurutan; diharapkan ${expectedIndex}, dapat ${index}`);
    }
    const timestamp = requireInt(block.timestamp, 'chain[].timestamp', { min: 0 });
    const type = requireText(block.type, 'chain[].type', { max: 40 });
    const owner = requireText(block.owner, 'chain[].owner', { max: 80 });
    const prevHash = requireText(block.prevHash, 'chain[].prevHash', { max: 64 });
    const nonce = requireInt(block.nonce, 'chain[].nonce', { min: 0, max: 2 ** 53 });
    const hash = requireText(block.hash, 'chain[].hash', { max: 64 });
    if (!SHA256_RE.test(hash)) throw bad('chain[].hash harus hex 64 karakter');

    const data = block.data == null ? {} : asObject(block.data, 'chain[].data');
    const dataJson = JSON.stringify(data);

    if (prevHash !== expectedPrev) {
      throw bad('chain[].prevHash tidak menunjuk blok sebelumnya');
    }
    const hitung = computeBlockHash({
      index,
      timestamp,
      type,
      dataJson,
      owner,
      prevHash,
      nonce,
    });
    if (hitung !== hash.toLowerCase()) {
      throw bad('chain[].hash tidak cocok dengan isi bloknya');
    }
    if (!hash.toLowerCase().startsWith(POW_PREFIX)) {
      throw bad(`chain[].hash tidak memenuhi proof-of-work (harus mulai ${POW_PREFIX})`);
    }

    // Kalau indeks ini sudah ada di server, blok lama harus sama persis.
    // Kalau berbeda, tolak; ini yang mencegah blok lama "dibuat ulang".
    const stored = storedBlocks.get(index);
    if (stored && stored.hash.toLowerCase() !== hash.toLowerCase()) {
      throw bad(`Blok ${index} sudah ada dengan isi berbeda dan tidak boleh diubah`);
    }

    expectedPrev = hash.toLowerCase();
    expectedIndex = index + 1;
  }
}

function storedChain(userId) {
  const rows = db
    .prepare('SELECT idx, hash FROM chain_blocks WHERE user_id = ? ORDER BY idx')
    .all(userId);
  return new Map(rows.map((r) => [r.idx, r]));
}

// ---------------------------------------------------------------- upsert

function upsertExpenses(userId, rawExpenses) {
  const expenses = asArray(rawExpenses, 'expenses', MAX_EXPENSES);
  const stmt = db.prepare(`
    INSERT INTO expenses (user_id, local_id, title, amount_gbp, amount_idr, category, club_key, created_at)
    VALUES (@user_id, @local_id, @title, @amount_gbp, @amount_idr, @category, @club_key, @created_at)
    ON CONFLICT(user_id, local_id) DO UPDATE SET
      title = excluded.title,
      amount_gbp = excluded.amount_gbp,
      amount_idr = excluded.amount_idr,
      category = excluded.category,
      club_key = excluded.club_key
  `);
  let n = 0;
  for (const raw of expenses) {
    const e = asObject(raw, 'expenses[]');
    // B6: validasi dulu, baru tulis. Sebelumnya `Number('abc')` jadi NaN dan
    // better-sqlite3 melempar error yang tidak terduga (500).
    const title = requireText(e.title, 'expenses[].title');
    const amountGbp = requireNumber(e.amountGbp, 'expenses[].amountGbp', { min: 0, max: 1e9 });
    const amountIdr = requireNumber(e.amountIdr, 'expenses[].amountIdr', { min: 0, max: 1e12 });
    const category = requireText(e.category, 'expenses[].category', { max: 40 });
    const localId = requireText(e.id, 'expenses[].id', { max: 60 });
    const date = e.date == null ? new Date().toISOString() : requireIsoDate(e.date, 'expenses[].date');
    stmt.run({
      user_id: userId,
      local_id: localId,
      title,
      amount_gbp: amountGbp,
      amount_idr: amountIdr,
      category,
      club_key: optionalText(e.clubKey, 'expenses[].clubKey', { max: 40 }),
      created_at: date,
    });
    n++;
  }
  return n;
}

function upsertChain(userId, rawChain) {
  const chain = asArray(rawChain, 'chain', MAX_CHAIN);
  validateChain(chain, storedChain(userId));

  // B4: DO NOTHING. Blok yang sudah ada tidak boleh berubah, jadi jangan pernah
  // menulis ulang isi indeks yang sama.
  const stmt = db.prepare(`
    INSERT INTO chain_blocks (user_id, idx, timestamp, type, data_json, owner, prev_hash, nonce, hash)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(user_id, idx) DO NOTHING
  `);
  let n = 0;
  for (const raw of chain) {
    const b = asObject(raw, 'chain[]');
    const info = stmt.run(
      userId,
      b.index,
      b.timestamp,
      b.type.trim(),
      JSON.stringify(b.data == null ? {} : asObject(b.data, 'chain[].data')),
      b.owner.trim(),
      b.prevHash.trim(),
      b.nonce,
      b.hash.trim()
    );
    // Hanya blok baru yang dihitung; blok yang sudah ada dilewati.
    if (info.changes > 0) n++;
  }
  return n;
}

/**
 * Upsert prediksi (S4/B5).
 *
 * Klien mengirim bentuk commit-only sebelum kickoff: { matchId, commit,
 * createdAt }. Kolom home_score / away_score / salt sengaja NULL sampai
 * klien mengirim bentuk ter-reveal setelah blok result ditulis.
 *
 * Kolom yang NULL pada payload tidak menimpa nilai yang sudah ter-reveal:
 * memakai COALESCE(excluded.x, x). Tanpa itu, sinkronisasi berikutnya
 * (yang masih commit-only) akan menghapus salt yang sudah terexpose.
 */
function upsertPredictions(userId, rawPredictions) {
  const predictions = asArray(rawPredictions, 'predictions', MAX_PREDICTIONS);
  const stmt = db.prepare(`
    INSERT INTO predictions (user_id, match_id, home_score, away_score, salt, commit_hash, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(user_id, match_id) DO UPDATE SET
      home_score = COALESCE(excluded.home_score, home_score),
      away_score = COALESCE(excluded.away_score, away_score),
      salt       = COALESCE(excluded.salt, salt),
      commit_hash = excluded.commit_hash
  `);
  let n = 0;
  for (const raw of predictions) {
    const p = asObject(raw, 'predictions[]');
    const matchId = requireInt(p.matchId, 'predictions[].matchId', { min: 0, max: 1e9 });
    const commit = requireText(p.commit, 'predictions[].commit', { max: 64 });
    if (!SHA256_RE.test(commit)) {
      throw bad('predictions[].commit harus hex 64 karakter');
    }
    const createdAt =
      p.createdAt == null ? new Date().toISOString() : requireIsoDate(p.createdAt, 'predictions[].createdAt');

    // Bentuk ter-reveal hanya sah kalau tiga field sekaligus ada.
    const adaSkor = p.homeScore != null || p.awayScore != null;
    const adaSalt = p.salt != null;
    if (adaSkor !== adaSalt) {
      throw bad(
        'predictions[] harus commit-only (tanpa skor dan salt) atau ter-reveal (lengkap)'
      );
    }
    const revealed = adaSkor && adaSalt;
    stmt.run(
      userId,
      matchId,
      revealed ? requireInt(p.homeScore, 'predictions[].homeScore', { min: 0, max: 99 }) : null,
      revealed ? requireInt(p.awayScore, 'predictions[].awayScore', { min: 0, max: 99 }) : null,
      revealed ? requireText(p.salt, 'predictions[].salt', { max: 64 }) : null,
      commit,
      createdAt
    );
    n++;
  }
  return n;
}

function upsertFeedback(userId, feedback) {
  if (feedback == null) return 0;
  const f = asObject(feedback, 'feedback');
  const kesan = optionalText(f.kesan, 'feedback.kesan', { max: 2000 });
  const saran = optionalText(f.saran, 'feedback.saran', { max: 2000 });
  // Formulir yang belum diisi tidak boleh membuat atau menimpa baris kosong.
  if (kesan == null && saran == null) return 0;
  db.prepare(`
    INSERT INTO feedback (user_id, kesan, saran, updated_at)
    VALUES (?, ?, ?, datetime('now'))
    ON CONFLICT(user_id) DO UPDATE SET
      kesan = excluded.kesan,
      saran = excluded.saran,
      updated_at = datetime('now')
  `).run(userId, kesan, saran);
  return 1;
}

// ---------------------------------------------------------------- push/pull

/**
 * B6: seluruh penulisan dibungkus transaksi.
 *
 * Sebelumnya expenses bisa tersimpan lalu prediksi gagal, jadi server menyimpan
 * setengah data yang tidak pernah lengkap. Sekarang salah satu galat berarti
 * semua perubahan dibatalkan (ROLLBACK).
 */
function push(userId, body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw bad('Body harus objek JSON');
  }
  // Validasi bentuk array sebelum transaksi supaya error validasi tidak
  // menyisakan transaksi terbuka.
  const expenses = asArray(body.expenses, 'expenses', MAX_EXPENSES);
  const chain = asArray(body.chain, 'chain', MAX_CHAIN);
  const predictions = asArray(body.predictions, 'predictions', MAX_PREDICTIONS);
  const hasFeedback = body.feedback != null;
  if (hasFeedback) asObject(body.feedback, 'feedback');

  db.exec('BEGIN IMMEDIATE');
  try {
    const result = {
      expenses: upsertExpenses(userId, expenses),
      chain: upsertChain(userId, chain),
      predictions: upsertPredictions(userId, predictions),
      feedback: upsertFeedback(userId, body.feedback),
      syncedAt: new Date().toISOString(),
    };
    db.exec('COMMIT');
    return result;
  } catch (e) {
    try {
      db.exec('ROLLBACK');
    } catch (rollbackError) {
      console.error('ROLLBACK gagal:', rollbackError);
    }
    throw e;
  }
}

function pull(userId) {
  return {
    // B7: urutkan berdasarkan waktu, bukan alias kolom, supaya urutannya
    // sama seperti di perangkat.
    expenses: db
      .prepare('SELECT local_id AS id, title, amount_gbp AS amountGbp, amount_idr AS amountIdr, category, club_key AS clubKey, created_at AS date FROM expenses WHERE user_id = ? ORDER BY created_at')
      .all(userId),
    chain: db
      .prepare('SELECT idx AS "index", timestamp, type, data_json AS data, owner, prev_hash AS prevHash, nonce, hash FROM chain_blocks WHERE user_id = ? ORDER BY idx')
      .all(userId)
      .map((b) => ({ ...b, data: JSON.parse(b.data) })),
    predictions: db
      .prepare('SELECT match_id AS matchId, home_score AS homeScore, away_score AS awayScore, salt, commit_hash AS "commit", created_at AS createdAt FROM predictions WHERE user_id = ? ORDER BY match_id')
      .all(userId),
    feedback: db
      .prepare('SELECT kesan, saran, updated_at AS updatedAt FROM feedback WHERE user_id = ?')
      .get(userId) ?? null,
  };
}

module.exports = {
  push,
  pull,
  // Diekspor untuk test B4.
  computeBlockHash,
  validateChain,
  MAX_CHAIN,
  MAX_EXPENSES,
  MAX_PREDICTIONS,
  GENESIS_PREV_HASH,
  POW_PREFIX,
};
