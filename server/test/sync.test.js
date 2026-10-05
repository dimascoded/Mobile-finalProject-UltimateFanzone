'use strict';

// Test logika sinkronisasi (upsert idempoten + isolasi antar user).
// Jalankan: npm test  (di dalam folder server/)

const path = require('path');
const { test, assert } = require('./harness');

process.env.DB_PATH = path.join(__dirname, '..', 'data', 'test-sync.db');
process.env.JWT_SECRET = 'test-secret';

const db = require('../db');
const sync = require('../sync');

function makeUser() {
  const info = db
    .prepare('INSERT INTO users (email, password_hash) VALUES (?, ?)')
    .run(`t${Date.now()}${Math.random()}@example.com`, 'x');
  return Number(info.lastInsertRowid);
}

test('push/pull expense bolak-balik konsisten', () => {
  const uid = makeUser();
  sync.push(uid, {
    expenses: [
      { id: 'e1', title: 'Tiket', amountGbp: 45, amountIdr: 900000, category: 'tiket', clubKey: 'arsenal', date: '2026-08-15T14:00:00Z' },
    ],
  });
  const out = sync.pull(uid);
  assert.strictEqual(out.expenses.length, 1);
  assert.strictEqual(out.expenses[0].title, 'Tiket');
  assert.strictEqual(out.expenses[0].amountGbp, 45);
  assert.strictEqual(out.expenses[0].clubKey, 'arsenal');
});

test('push expense yang sama dua kali tidak duplikat', () => {
  const uid = makeUser();
  const body = {
    expenses: [{ id: 'e1', title: 'Tiket', amountGbp: 45, amountIdr: 900000, category: 'tiket', date: '2026-08-15T14:00:00Z' }],
  };
  sync.push(uid, body);
  sync.push(uid, body);
  const out = sync.pull(uid);
  assert.strictEqual(out.expenses.length, 1, 'idempoten lewat (user_id, local_id)');
});

test('push expense dengan local_id sama menimpa, bukan menambah', () => {
  const uid = makeUser();
  sync.push(uid, { expenses: [{ id: 'e1', title: 'Awal', amountGbp: 10, amountIdr: 100, category: 'tiket', date: '2026-01-01T00:00:00Z' }] });
  sync.push(uid, { expenses: [{ id: 'e1', title: 'Diperbarui', amountGbp: 20, amountIdr: 200, category: 'hotel', date: '2026-01-01T00:00:00Z' }] });
  const out = sync.pull(uid);
  assert.strictEqual(out.expenses.length, 1);
  assert.strictEqual(out.expenses[0].title, 'Diperbarui');
  assert.strictEqual(out.expenses[0].category, 'hotel');
});

test('chain block tersimpan dengan urutan dan data json utuh', () => {
  const uid = makeUser();
  sync.push(uid, {
    chain: [
      { index: 0, timestamp: 0, type: 'genesis', data: {}, owner: 'system', prevHash: '0'.repeat(64), nonce: 1, hash: 'a'.repeat(64) },
      { index: 1, timestamp: 111, type: 'stamp', data: { club: 'arsenal', stadium: 'Emirates' }, owner: 'me', prevHash: 'a'.repeat(64), nonce: 2, hash: 'b'.repeat(64) },
    ],
  });
  const out = sync.pull(uid);
  assert.strictEqual(out.chain.length, 2);
  assert.strictEqual(out.chain[0].type, 'genesis');
  assert.strictEqual(out.chain[1].data.club, 'arsenal');
  assert.strictEqual(out.chain[1].data.stadium, 'Emirates');
});

test('chain dengan indeks sama ditimpa (idempoten)', () => {
  const uid = makeUser();
  const block = { index: 0, timestamp: 0, type: 'genesis', data: {}, owner: 'system', prevHash: '0'.repeat(64), nonce: 1, hash: 'a'.repeat(64) };
  sync.push(uid, { chain: [block] });
  sync.push(uid, { chain: [block] });
  assert.strictEqual(sync.pull(uid).chain.length, 1);
});

test('S4: payload commit-only tidak menyimpan skor maupun salt', () => {
  const uid = makeUser();
  sync.push(uid, {
    predictions: [{ matchId: 9001, commit: 'e'.repeat(64), createdAt: '2026-08-15T00:00:00Z' }],
  });
  const p = sync.pull(uid).predictions[0];
  assert.strictEqual(p.matchId, 9001);
  assert.strictEqual(p.commit, 'e'.repeat(64));
  assert.strictEqual(p.salt, null, 'salt tidak boleh tersimpan sebelum reveal');
  assert.strictEqual(p.homeScore, null, 'skor tebakan tidak boleh tersimpan sebelum reveal');
  assert.strictEqual(p.awayScore, null);
});

test('S4: sinkronisasi commit-only berikutnya tidak menghapus salt yang sudah terbuka', () => {
  const uid = makeUser();
  // Bentuk ter-reveal (setelah blok result ditulis).
  sync.push(uid, {
    predictions: [{ matchId: 9002, homeScore: 2, awayScore: 1, salt: 'bcdf', commit: 'f'.repeat(64), createdAt: '2026-08-15T00:00:00Z' }],
  });
  // Sync berikutnya masih commit-only (mis. dari perangkat lain).
  sync.push(uid, {
    predictions: [{ matchId: 9002, commit: 'f'.repeat(64), createdAt: '2026-08-15T00:00:00Z' }],
  });
  const p = sync.pull(uid).predictions[0];
  assert.strictEqual(p.salt, 'bcdf', 'salt yang sudah reveal tidak ditimpa');
  assert.strictEqual(p.homeScore, 2);
  assert.strictEqual(p.awayScore, 1);
});

test('prediksi menyimpan salt dan commit', () => {
  const uid = makeUser();
  sync.push(uid, {
    predictions: [{ matchId: 7001, homeScore: 2, awayScore: 1, salt: 'abc', commit: 'd'.repeat(64), createdAt: '2026-08-15T00:00:00Z' }],
  });
  const out = sync.pull(uid);
  assert.strictEqual(out.predictions.length, 1);
  assert.strictEqual(out.predictions[0].matchId, 7001);
  assert.strictEqual(out.predictions[0].salt, 'abc');
  assert.strictEqual(out.predictions[0].homeScore, 2);
});

test('prediksi untuk match yang sama menimpa, tidak menambah', () => {
  const uid = makeUser();
  sync.push(uid, { predictions: [{ matchId: 1, homeScore: 1, awayScore: 0, salt: 'a', commit: 'x', createdAt: '2026-01-01T00:00:00Z' }] });
  sync.push(uid, { predictions: [{ matchId: 1, homeScore: 3, awayScore: 2, salt: 'a', commit: 'x', createdAt: '2026-01-01T00:00:00Z' }] });
  const out = sync.pull(uid);
  assert.strictEqual(out.predictions.length, 1);
  assert.strictEqual(out.predictions[0].homeScore, 3);
});

test('feedback tersimpan dan bisa diperbarui', () => {
  const uid = makeUser();
  sync.push(uid, { feedback: { kesan: 'Bagus', saran: 'Tambah dark mode' } });
  let out = sync.pull(uid);
  assert.strictEqual(out.feedback.kesan, 'Bagus');
  sync.push(uid, { feedback: { kesan: 'Lebih baik', saran: 'Tambah statistik' } });
  out = sync.pull(uid);
  assert.strictEqual(out.feedback.kesan, 'Lebih baik');
});

test('user berbeda tidak saling melihat data', () => {
  const a = makeUser();
  const b = makeUser();
  sync.push(a, { expenses: [{ id: 'x', title: 'Milik A', amountGbp: 1, amountIdr: 1, category: 'tiket', date: '2026-01-01T00:00:00Z' }] });
  assert.strictEqual(sync.pull(b).expenses.length, 0, 'user B tidak boleh melihat data A');
});

test('body bukan objek ditolak 400', () => {
  const uid = makeUser();
  assert.throws(() => sync.push(uid, null), { status: 400 });
});

test('chain melebihi batas ditolak 413', () => {
  const uid = makeUser();
  const tooMany = Array.from({ length: 5001 }, (_, i) => ({
    index: i, timestamp: i, type: 'x', data: {}, owner: 'o', prevHash: 'p', nonce: i, hash: 'h',
  }));
  assert.throws(() => sync.push(uid, { chain: tooMany }), { status: 413 });
});

test('push mengembalikan jumlah per koleksi', () => {
  const uid = makeUser();
  const res = sync.push(uid, {
    expenses: [{ id: 'a', title: 'T', amountGbp: 1, amountIdr: 1, category: 'tiket', date: '2026-01-01T00:00:00Z' }],
    chain: [{ index: 0, timestamp: 0, type: 'genesis', data: {}, owner: 's', prevHash: 'p', nonce: 0, hash: 'h' }],
    predictions: [{ matchId: 5, homeScore: 0, awayScore: 0, salt: 's', commit: 'c', createdAt: '2026-01-01T00:00:00Z' }],
    feedback: { kesan: 'ok', saran: '' },
  });
  assert.strictEqual(res.expenses, 1);
  assert.strictEqual(res.chain, 1);
  assert.strictEqual(res.predictions, 1);
  assert.strictEqual(res.feedback, 1);
  assert.ok(res.syncedAt);
});
