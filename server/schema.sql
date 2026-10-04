-- Skema database Smart Football Fan.
-- Domain sudah diubah dari Traveler ke sepak bola: tidak ada trips/countries.

CREATE TABLE IF NOT EXISTS users (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  email         TEXT    NOT NULL UNIQUE,
  -- Client mengirim SHA-256(password); server menambah bcrypt di atasnya.
  password_hash TEXT    NOT NULL,
  created_at    TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Pengeluaran Away Day (mata uang utama GBP, disimpan juga dalam Rupiah).
-- UNIQUE (user_id, local_id) dipakai Upsert agar upload ulang tidak duplikat.
CREATE TABLE IF NOT EXISTS expenses (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  local_id    TEXT    NOT NULL,
  title       TEXT    NOT NULL,
  amount_gbp  REAL    NOT NULL,
  amount_idr  REAL    NOT NULL,
  category    TEXT    NOT NULL,
  club_key    TEXT,
  created_at  TEXT    NOT NULL,
  UNIQUE (user_id, local_id)
);
CREATE INDEX IF NOT EXISTS idx_expenses_user ON expenses(user_id);

-- Rantai blok (stamp stadion, prediksi skor, achievement mini game).
-- PRIMARY KEY (user_id, idx) mengikuti urutan blok yang tidak boleh berubah.
CREATE TABLE IF NOT EXISTS chain_blocks (
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  idx        INTEGER NOT NULL,
  timestamp  INTEGER NOT NULL,
  type       TEXT    NOT NULL,
  data_json  TEXT    NOT NULL,
  owner      TEXT    NOT NULL,
  prev_hash  TEXT    NOT NULL,
  nonce      INTEGER NOT NULL,
  hash       TEXT    NOT NULL,
  PRIMARY KEY (user_id, idx)
);

-- Prediksi skor: hanya commit yang boleh naik ke server.
-- Salt TIDAK ikut dikirim, karena itu rahasianya sampai laga selesai.
CREATE TABLE IF NOT EXISTS predictions (
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  match_id   INTEGER NOT NULL,
  home_score INTEGER NOT NULL,
  away_score INTEGER NOT NULL,
  salt       TEXT    NOT NULL,
  -- "commit" adalah reserved word SQL, jadi kolomnya commit_hash.
  commit_hash TEXT   NOT NULL,
  created_at TEXT    NOT NULL,
  PRIMARY KEY (user_id, match_id)
);

CREATE TABLE IF NOT EXISTS feedback (
  user_id  INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  kesan    TEXT,
  saran    TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
