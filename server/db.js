'use strict';

/**
 * Adapter database.
 *
 * Driver utama `node:sqlite` (bawaan Node 22.5+/24, tanpa addon native) dan
 * jatuh ke `better-sqlite3` bila tidak tersedia.
 *
 * Alasan: pada Node 24.21 + Windows, memuat addon native better-sqlite3
 * membuat proses crash dengan assertion failure di environment cleanup hook
 * saat `bcrypt.hashSync()` dipanggil, sehingga test suite tidak stabil.
 * API kedua driver ini kompatibel untuk yang kita pakai (exec/prepare/
 * run/get/all/close), jadi pergantian driver tidak mengubah kode lain.
 */

const fs = require('node:fs');
const path = require('node:path');

let driverName;
let DatabaseCtor;

try {
  const { DatabaseSync } = require('node:sqlite');
  driverName = 'node:sqlite';
  DatabaseCtor = (file) => new DatabaseSync(file);
} catch (e) {
  const BetterSqlite3 = require('better-sqlite3');
  driverName = 'better-sqlite3';
  DatabaseCtor = (file) => new BetterSqlite3(file);
}

const dbPath = process.env.DB_PATH || path.join(__dirname, 'data', 'app.db');
fs.mkdirSync(path.dirname(dbPath), { recursive: true });

const db = DatabaseCtor(dbPath);
db.exec('PRAGMA journal_mode = WAL');
db.exec('PRAGMA foreign_keys = ON');

const schema = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
db.exec(schema);

db.driverName = driverName;

module.exports = db;
