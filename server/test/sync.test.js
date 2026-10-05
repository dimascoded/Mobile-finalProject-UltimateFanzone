'use strict';

// Test logika sinkronisasi (validasi payload, rantai yang tidak bisa dipalsukan,
// upsert idempoten + isolasi antar user).
// Jalankan: npm test  (di dalam folder server/)

const path = require('path');
const crypto = require('node:crypto');
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

/**
 * Hash blok dihitung ulang di sini, independen dari sync.js, supaya test benar
 *-benar menguji formula yang sama dengan `Block.computeHash` di sisi Flutter:
 *   sha256('index|timestamp|type|JSON.stringify(data)|owner|prevHash|nonce')
 */
function hashOf(b) {
  return crypto
    .createHash('sha256')
    .update(
      `${b.index}|${b.timestamp}|${b.type}|${JSON.stringify(b.data ?? {})}|${b.owner}|${b.prevHash}|${b.nonce}`
    )
    .digest('hex');
}

/** Mine blok sungguhan: naikkan nonce sampai hash mulai dengan '000' (PoW). */
function mine({ index, timestamp, type, data, owner, prevHash }) {
  for (let nonce = 0; nonce < 5_000_000; nonce++) {
    const candidate = { index, timestamp, type, data, owner, prevHash, nonce };
    const hash = hashOf(candidate);
    if (hash.startsWith('000')) return { ...candidate, hash };
  }
  throw new Error('nonce tidak ditemukan');
}

const GENESIS = () =>
  mine({ index: 0, timestamp: 1, type: 'genesis', data: {}, owner: 'system', prevHash: '0'.repeat(64) });

/** Rantai genesis + satu blok, dirangkai dengan benar. */
function chainWithStamp(data = { club: 'arsenal', stadium: 'Emirates' }) {
  const genesis = GENESIS();
  const stamp = mine({
    index: 1,
    timestamp: 2,
    type: 'stamp',
    data,
    owner: 'me',
    prevHash: genesis.hash,
  });
  return [genesis, stamp];
}

function expense(overrides = {}) {
  return {
    id: 'e1',
    title: 'Tiket',
    amountGbp: 45,
    amountIdr: 900000,
    category: 'tiket',
    clubKey: 'arsenal',
    date: '2026-08-15T14:00:00Z',
    ...overrides,
  };
}

const commitOf = (seed) => crypto.createHash('sha256').update(seed).digest('hex');

function assertStatus(fn, status) {
  try {
    fn();
  } catch (e) {
    assert.strictEqual(e.status, status, `harus ${status}, dapat ${e.status}: ${e.message}`);
    return e;
  }
  throw new Error(`harus ditolak dengan status ${status}, tapi tidak ada galat`);
}

// ---------------------------------------------------------------- expenses

test('push/pull expense bolak-balik konsisten', () => {
  const uid = makeUser();
  sync.push(uid, { expenses: [expense()] });
  const out = sync.pull(uid);
  assert.strictEqual(out.expenses.length, 1);
  assert.strictEqual(out.expenses[0].title, 'Tiket');
  assert.strictEqual(out.expenses[0].amountGbp, 45);
  assert.strictEqual(out.expenses[0].clubKey, 'arsenal');
});

test('push expense yang sama dua kali tidak duplikat', () => {
  const uid = makeUser();
  const body = { expenses: [expense()] };
  sync.push(uid, body);
  sync.push(uid, body);
  assert.strictEqual(sync.pull(uid).expenses.length, 1, 'idempoten lewat (user_id, local_id)');
});

test('push expense dengan local_id sama menimpa, bukan menambah', () => {
  const uid = makeUser();
  sync.push(uid, { expenses: [expense({ title: 'Awal', amountGbp: 10, amountIdr: 100, category: 'tiket' })] });
  sync.push(uid, {
    expenses: [expense({ title: 'Diperbarui', amountGbp: 20, amountIdr: 200, category: 'hotel' })],
  });
  const out = sync.pull(uid);
  assert.strictEqual(out.expenses.length, 1);
  assert.strictEqual(out.expenses[0].title, 'Diperbarui');
  assert.strictEqual(out.expenses[0].category, 'hotel');
});

test('B7: pull mengurutkan expense menurut waktu', () => {
  const uid = makeUser();
  sync.push(uid, {
    expenses: [
      expense({ id: 'b', title: 'Kedua', date: '2026-03-02T00:00:00Z' }),
      expense({ id: 'a', title: 'Pertama', date: '2026-03-01T00:00:00Z' }),
    ],
  });
  const out = sync.pull(uid);
  assert.deepStrictEqual(out.expenses.map((e) => e.title), ['Pertama', 'Kedua']);
});

// ---------------------------------------------------------------- rantai

test('chain block tersimpan dengan urutan dan data json utuh', () => {
  const uid = makeUser();
  const chain = chainWithStamp();
  sync.push(uid, { chain });
  const out = sync.pull(uid);
  assert.strictEqual(out.chain.length, 2);
  assert.strictEqual(out.chain[0].type, 'genesis');
  assert.strictEqual(out.chain[1].data.club, 'arsenal');
  assert.strictEqual(out.chain[1].data.stadium, 'Emirates');
  assert.strictEqual(out.chain[1].index, 1);
  assert.strictEqual(out.chain[1].prevHash, chain[0].hash);
});

test('B4: computeBlockHash server sama dengan formula Block.computeHash', () => {
  const block = chainWithStamp()[1];
  const expected = hashOf(block);
  assert.strictEqual(
    sync.computeBlockHash({
      index: block.index,
      timestamp: block.timestamp,
      type: block.type,
      dataJson: JSON.stringify(block.data),
      owner: block.owner,
      prevHash: block.prevHash,
      nonce: block.nonce,
    }),
    expected
  );
});

test('B4: push rantai identik dua kali idempoten dan tidak menimpa', () => {
  const uid = makeUser();
  const chain = chainWithStamp();
  const first = sync.push(uid, { chain });
  const second = sync.push(uid, { chain });
  assert.strictEqual(first.chain, 2);
  assert.strictEqual(second.chain, 0, 'blok yang sudah ada tidak dihitung lagi');
  const out = sync.pull(uid);
  assert.strictEqual(out.chain.length, 2);
  assert.strictEqual(out.chain[1].hash, chain[1].hash);
});

test('B4: blok lama tidak boleh ditimpa hash palsu', () => {
  const uid = makeUser();
  const asli = chainWithStamp();
  sync.push(uid, { chain: asli });

  // Klaim indeks 1 dengan isi berbeda: harus ditolak, bukan ditimpa.
  const palsu = [
    asli[0],
    mine({ index: 1, timestamp: 2, type: 'stamp', data: { club: 'chelsea' }, owner: 'me', prevHash: asli[0].hash }),
  ];
  assertStatus(() => sync.push(uid, { chain: palsu }), 400);

  const out = sync.pull(uid);
  assert.strictEqual(out.chain[1].data.club, 'arsenal', 'isi blok lama harus utuh');
  assert.strictEqual(out.chain[1].hash, asli[1].hash);
});

test('B4: hash yang tidak cocok dengan isi blok ditolak 400', () => {
  const uid = makeUser();
  const chain = chainWithStamp();
  // Data diubah tapi hash lama dipakai: ini pemalsuan rantai.
  const dipalsukan = [{ ...chain[0] }, { ...chain[1], data: { club: 'chelsea', stadium: 'Emirates' } }];
  assertStatus(() => sync.push(uid, { chain: dipalsukan }), 400);
  assert.strictEqual(sync.pull(uid).chain.length, 0, 'tidak ada blok yang tersimpan');
});

test('B4: prevHash yang tidak nyambung ditolak 400', () => {
  const uid = makeUser();
  const genesis = GENESIS();
  const yatim = mine({
    index: 1,
    timestamp: 2,
    type: 'stamp',
    data: {},
    owner: 'me',
    prevHash: 'f'.repeat(64),
  });
  assertStatus(() => sync.push(uid, { chain: [genesis, yatim] }), 400);
});

test('B4: indeks tidak berurutan dari 0 ditolak 400', () => {
  const uid = makeUser();
  const genesis = GENESIS();
  const lompat = mine({ index: 5, timestamp: 2, type: 'stamp', data: {}, owner: 'me', prevHash: genesis.hash });
  assertStatus(() => sync.push(uid, { chain: [genesis, lompat] }), 400);
});

test('B4: hash tanpa proof-of-work ditolak 400', () => {
  const uid = makeUser();
  const genesis = GENESIS();
  // Hash dihitung benar, tapi tidak dimulai dengan '000'.
  let nonce = 0;
  let block;
  do {
    block = { index: 1, timestamp: 2, type: 'stamp', data: {}, owner: 'me', prevHash: genesis.hash, nonce };
    block.hash = hashOf(block);
    nonce++;
  } while (block.hash.startsWith('000'));
  assertStatus(() => sync.push(uid, { chain: [genesis, block] }), 400);
});

test('B4: blok yang dihapus dari rantai ditolak, bukan diterima sebagai rantai baru', () => {
  const uid = makeUser();
  const chain = chainWithStamp();
  sync.push(uid, { chain });
  // Klaim hanya blok kedua (tanpa genesis).
  assertStatus(() => sync.push(uid, { chain: [chain[1]] }), 400);
});

// ---------------------------------------------------------------- prediksi

test('S4/B5: payload commit-only tidak menyimpan skor maupun salt', () => {
  const uid = makeUser();
  sync.push(uid, {
    predictions: [{ matchId: 9001, commit: commitOf('a'), createdAt: '2026-08-15T00:00:00Z' }],
  });
  const p = sync.pull(uid).predictions[0];
  assert.strictEqual(p.matchId, 9001);
  assert.strictEqual(p.commit, commitOf('a'));
  assert.strictEqual(p.salt, null, 'salt tidak boleh tersimpan sebelum reveal');
  assert.strictEqual(p.homeScore, null, 'skor tebakan tidak boleh tersimpan sebelum reveal');
  assert.strictEqual(p.awayScore, null);
});

test('S4/B5: sinkronisasi commit-only berikutnya tidak menghapus salt yang sudah terbuka', () => {
  const uid = makeUser();
  // Bentuk ter-reveal (setelah blok result ditulis).
  sync.push(uid, {
    predictions: [
      { matchId: 9002, homeScore: 2, awayScore: 1, salt: 'bcdf', commit: commitOf('b'), createdAt: '2026-08-15T00:00:00Z' },
    ],
  });
  // Sync berikutnya masih commit-only (mis. dari perangkat lain).
  sync.push(uid, {
    predictions: [{ matchId: 9002, commit: commitOf('b'), createdAt: '2026-08-15T00:00:00Z' }],
  });
  const p = sync.pull(uid).predictions[0];
  assert.strictEqual(p.salt, 'bcdf', 'salt yang sudah reveal tidak ditimpa');
  assert.strictEqual(p.homeScore, 2);
  assert.strictEqual(p.awayScore, 1);
});

test('B5: bentuk setengah ter-reveal ditolak 400', () => {
  const uid = makeUser();
  const commit = commitOf('c');
  // Skor tanpa salt: server tidak boleh menyimpannya karena salt yang bocor
  // adalah cheat, dan tanpa salt reveal tidak bisa diverifikasi.
  assertStatus(
    () => sync.push(uid, { predictions: [{ matchId: 9100, homeScore: 1, awayScore: 0, commit, createdAt: '2026-08-15T00:00:00Z' }] }),
    400
  );
  // Salt tanpa skor juga ditolak.
  assertStatus(
    () => sync.push(uid, { predictions: [{ matchId: 9101, salt: 'abc', commit, createdAt: '2026-08-15T00:00:00Z' }] }),
    400
  );
  assert.strictEqual(sync.pull(uid).predictions.length, 0, 'tidak boleh ada yang tersimpan');
});

test('prediksi menyimpan salt dan commit', () => {
  const uid = makeUser();
  sync.push(uid, {
    predictions: [
      { matchId: 7001, homeScore: 2, awayScore: 1, salt: 'abc', commit: commitOf('d'), createdAt: '2026-08-15T00:00:00Z' },
    ],
  });
  const out = sync.pull(uid);
  assert.strictEqual(out.predictions.length, 1);
  assert.strictEqual(out.predictions[0].matchId, 7001);
  assert.strictEqual(out.predictions[0].salt, 'abc');
  assert.strictEqual(out.predictions[0].homeScore, 2);
});

test('prediksi untuk match yang sama menimpa, tidak menambah', () => {
  const uid = makeUser();
  const commit = commitOf('e');
  sync.push(uid, { predictions: [{ matchId: 1, homeScore: 1, awayScore: 0, salt: 'a', commit, createdAt: '2026-01-01T00:00:00Z' }] });
  sync.push(uid, { predictions: [{ matchId: 1, homeScore: 3, awayScore: 2, salt: 'a', commit, createdAt: '2026-01-01T00:00:00Z' }] });
  const out = sync.pull(uid);
  assert.strictEqual(out.predictions.length, 1);
  assert.strictEqual(out.predictions[0].homeScore, 3);
});

// ---------------------------------------------------------------- feedback

test('feedback tersimpan dan bisa diperbarui', () => {
  const uid = makeUser();
  sync.push(uid, { feedback: { kesan: 'Bagus', saran: 'Tambah dark mode' } });
  let out = sync.pull(uid);
  assert.strictEqual(out.feedback.kesan, 'Bagus');
  sync.push(uid, { feedback: { kesan: 'Lebih baik', saran: 'Tambah statistik' } });
  out = sync.pull(uid);
  assert.strictEqual(out.feedback.kesan, 'Lebih baik');
});

test('feedback kosong disimpan sebagai null, bukan error', () => {
  const uid = makeUser();
  // Formulir yang belum diisi harus tetap bisa tersinkron.
  sync.push(uid, { feedback: { kesan: '', saran: '' } });
  const row = db.prepare('SELECT kesan FROM feedback WHERE user_id = ?').get(uid);
  assert.strictEqual(row, undefined, 'feedback kosong berarti tidak ada baris');
});

// ---------------------------------------------------------------- validasi B6

test('B6: body bukan objek ditolak 400', () => {
  const uid = makeUser();
  assertStatus(() => sync.push(uid, null), 400);
  assertStatus(() => sync.push(uid, []), 400);
  assertStatus(() => sync.push(uid, 'bukan objek'), 400);
});

test('B6: koleksi harus berupa array', () => {
  const uid = makeUser();
  assertStatus(() => sync.push(uid, { expenses: 'bukan array' }), 400);
  assertStatus(() => sync.push(uid, { chain: { index: 0 } }), 400);
  assertStatus(() => sync.push(uid, { predictions: 42 }), 400);
  assertStatus(() => sync.push(uid, { feedback: 'teks' }), 400);
});

test('B6: item bukan objek ditolak 400', () => {
  const uid = makeUser();
  assertStatus(() => sync.push(uid, { expenses: ['tiket'] }), 400);
});

test('B6: angka yang bukan angka ditolak 400, bukan 500', () => {
  const uid = makeUser();
  assertStatus(() => sync.push(uid, { expenses: [expense({ amountGbp: 'banyak' })] }), 400);
  assertStatus(() => sync.push(uid, { expenses: [expense({ amountIdr: null })] }), 400);
  assertStatus(() => sync.push(uid, { expenses: [expense({ amountGbp: NaN })] }), 400);
  assert.strictEqual(sync.pull(uid).expenses.length, 0);
});

test('B6: field wajib kosong atau salah tipe ditolak 400', () => {
  const uid = makeUser();
  assertStatus(() => sync.push(uid, { expenses: [expense({ title: '' })] }), 400);
  assertStatus(() => sync.push(uid, { expenses: [expense({ title: 42 })] }), 400);
  assertStatus(() => sync.push(uid, { expenses: [expense({ category: null })] }), 400);
  assertStatus(() => sync.push(uid, { expenses: [expense({ id: '' })] }), 400);
  assertStatus(() => sync.push(uid, { expenses: [expense({ date: 'bukan tanggal' })] }), 400);
});

test('B6: commit prediksi harus hex 64 karakter', () => {
  const uid = makeUser();
  assertStatus(
    () => sync.push(uid, { predictions: [{ matchId: 5, commit: 'pendek', createdAt: '2026-01-01T00:00:00Z' }] }),
    400
  );
});

test('B6: matchId harus bilangan bulat', () => {
  const uid = makeUser();
  assertStatus(
    () => sync.push(uid, { predictions: [{ matchId: 'lima', commit: commitOf('f'), createdAt: '2026-01-01T00:00:00Z' }] }),
    400
  );
});

test('B6: tidak ada tulis sebagian saat satu item gagal (rollback)', () => {
  const uid = makeUser();
  // Expenses-nya valid dan akan ditulis lebih dulu; prediksi berikutnya salah
  // format. Tanpa transaksi, expense ini akan tersimpan sendirian.
  assertStatus(
    () =>
      sync.push(uid, {
        expenses: [expense({ id: 'rollback-1' })],
        predictions: [{ matchId: 6, commit: 'bukan-hex', createdAt: '2026-01-01T00:00:00Z' }],
      }),
    400
  );
  const out = sync.pull(uid);
  assert.strictEqual(out.expenses.length, 0, 'expense tidak boleh tersisa setelah rollback');
  assert.strictEqual(out.predictions.length, 0);
});

test('B6: rollback juga membatalkan blok rantai yang gagal disimpan', () => {
  const uid = makeUser();
  const genesis = GENESIS();
  const rusak = { ...genesis, data: { dirusak: true } }; // hash tidak cocok lagi
  assertStatus(
    () =>
      sync.push(uid, {
        expenses: [expense({ id: 'rollback-2' })],
        chain: [rusak],
      }),
    400
  );
  assert.strictEqual(sync.pull(uid).chain.length, 0);
  assert.strictEqual(sync.pull(uid).expenses.length, 0);
});

test('B6: chain melebihi batas ditolak 413', () => {
  const uid = makeUser();
  const tooMany = Array.from({ length: 5001 }, (_, i) => ({
    index: i, timestamp: i, type: 'x', data: {}, owner: 'o', prevHash: 'p', nonce: i, hash: 'h',
  }));
  assertStatus(() => sync.push(uid, { chain: tooMany }), 413);
});

// ---------------------------------------------------------------- lain-lain

test('user berbeda tidak saling melihat data', () => {
  const a = makeUser();
  const b = makeUser();
  sync.push(a, { expenses: [expense({ id: 'x', title: 'Milik A' })] });
  assert.strictEqual(sync.pull(b).expenses.length, 0, 'user B tidak boleh melihat data A');
});

test('push mengembalikan jumlah per koleksi', () => {
  const uid = makeUser();
  const res = sync.push(uid, {
    expenses: [expense({ id: 'a', title: 'T', amountGbp: 1, amountIdr: 1 })],
    chain: [GENESIS()],
    predictions: [
      { matchId: 5, homeScore: 0, awayScore: 0, salt: 's', commit: commitOf('g'), createdAt: '2026-01-01T00:00:00Z' },
    ],
    feedback: { kesan: 'ok', saran: 'bagus' },
  });
  assert.strictEqual(res.expenses, 1);
  assert.strictEqual(res.chain, 1);
  assert.strictEqual(res.predictions, 1);
  assert.strictEqual(res.feedback, 1);
  assert.ok(res.syncedAt);
});
