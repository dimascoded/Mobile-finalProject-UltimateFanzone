'use strict';

const db = require('./db');
const { HttpError } = require('./auth');

/**
 * Body POST /sync sesuai sisi Flutter (lib/features/sync/data/sync_repository.dart):
 *   { expenses: [], chain: [], predictions: [], feedback: { kesan, saran } }
 *
 * Semua operasi idempoten:AUS
 *   - expenses memakai (user_id, local_id) sehingga upload ulang tidak duplikat
 *   - chain memakai PRIMARY KEY (user_id, idx) sehingga indeks sama ditimpa
 *   - predictions memakai (user_id, match_id)
 */

const MAX_CHAIN = 5000;

function upsertExpenses(userId, expenses) {
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
  for (const e of expenses) {
    stmt.run({
      user_id: userId,
      local_id: String(e.id ?? ''),
      title: String(e.title ?? ''),
      amount_gbp: Number(e.amountGbp ?? 0),
      amount_idr: Number(e.amountIdr ?? 0),
      category: String(e.category ?? 'lainnya'),
      club_key: e.clubKey == null ? null : String(e.clubKey),
      created_at: String(e.date ?? new Date().toISOString()),
    });
    n++;
  }
  return n;
}

function upsertChain(userId, chain) {
  if (chain.length > MAX_CHAIN) {
    throw new HttpError(413, `Rantai terlalu panjang (maks ${MAX_CHAIN} blok)`);
  }
  const stmt = db.prepare(`
    INSERT INTO chain_blocks (user_id, idx, timestamp, type, data_json, owner, prev_hash, nonce, hash)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(user_id, idx) DO UPDATE SET
      timestamp = excluded.timestamp,
      type = excluded.type,
      data_json = excluded.data_json,
      owner = excluded.owner,
      prev_hash = excluded.prev_hash,
      nonce = excluded.nonce,
      hash = excluded.hash
  `);
  let n = 0;
  for (const b of chain) {
    stmt.run(
      userId,
      Number(b.index),
      Number(b.timestamp),
      String(b.type),
      JSON.stringify(b.data ?? {}),
      String(b.owner ?? ''),
      String(b.prevHash ?? ''),
      Number(b.nonce ?? 0),
      String(b.hash ?? ''),
    );
    n++;
  }
  return n;
}

/**
 * Upsert prediksi (S4).
 *
 * Klien mengirim bentuk commit-only sebelum kickoff: { matchId, commit,
 * createdAt }. Kolom home_score / away_score / salt sengaja NULL sampai
 * klien mengirim bentuk ter-reveal setelah blok result ditulis.
 *
 * Kolom yang NULL pada payload tidak menimpa nilai yang sudah ter-reveal:
 * memakai COALESCE(excluded.x, x). Tanpa itu, sinkronisasi berikutnya
 * (yang masih commit-only) akan menghapus salt yang sudah terexpose.
 */
function upsertPredictions(userId, predictions) {
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
  for (const p of predictions) {
    // Bentuk commit-only berarti "belum ada yang boleh dibuka".
    const revealed = p.salt != null && p.homeScore != null && p.awayScore != null;
    stmt.run(
      userId,
      Number(p.matchId),
      revealed ? Number(p.homeScore) : null,
      revealed ? Number(p.awayScore) : null,
      revealed ? String(p.salt) : null,
      String(p.commit ?? ''),
      String(p.createdAt ?? new Date().toISOString()),
    );
    n++;
  }
  return n;
}

function upsertFeedback(userId, feedback) {
  if (!feedback || typeof feedback !== 'object') return 0;
  db.prepare(`
    INSERT INTO feedback (user_id, kesan, saran, updated_at)
    VALUES (?, ?, ?, datetime('now'))
    ON CONFLICT(user_id) DO UPDATE SET
      kesan = excluded.kesan,
      saran = excluded.saran,
      updated_at = datetime('now')
  `).run(userId, feedback.kesan ?? null, feedback.saran ?? null);
  return 1;
}

function push(userId, body) {
  if (!body || typeof body !== 'object') throw new HttpError(400, 'Body harus objek JSON');
  const expenses = Array.isArray(body.expenses) ? body.expenses : [];
  const chain = Array.isArray(body.chain) ? body.chain : [];
  const predictions = Array.isArray(body.predictions) ? body.predictions : [];

  const result = {
    expenses: upsertExpenses(userId, expenses),
    chain: upsertChain(userId, chain),
    predictions: upsertPredictions(userId, predictions),
    feedback: upsertFeedback(userId, body.feedback),
    syncedAt: new Date().toISOString(),
  };
  return result;
}

function pull(userId) {
  return {
    expenses: db
      .prepare('SELECT local_id AS id, title, amount_gbp AS amountGbp, amount_idr AS amountIdr, category, club_key AS clubKey, created_at AS date FROM expenses WHERE user_id = ? ORDER BY id')
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

module.exports = { push, pull };
