'use strict';

/**
 * Harness test minimal untuk server.
 *
 * Node 24 + addon native better-sqlite3 bisa assertion failure di
 * environment cleanup hook saat proses ditutup. Karena itu:
 *   1. test tidak memakai runner node:test, tapi dieksekusi sinkron di sini;
 *   2. semua output ditulis dengan fs.writeSync, karena write ke pipe di Node
 *      itu async dan akan hilang kalau proses sempat abort di akhir.
 */

const fs = require('node:fs');
const assert = require('node:assert');

function out(line) {
  fs.writeSync(1, `${line}\n`);
}

const registry = [];
let currentGroup = '(umum)';

function group(name) {
  currentGroup = name;
}

function test(name, fn) {
  registry.push({ name, fn, group: currentGroup });
}

function run() {
  let pass = 0;
  const failures = [];
  let lastGroup = null;

  for (const { name, fn, group: g } of registry) {
    if (g !== lastGroup) {
      out(`\n# ${g}`);
      lastGroup = g;
    }
    try {
      fn();
      pass++;
      out(`  ok   ${name}`);
    } catch (e) {
      failures.push({ name, e });
      out(`  FAIL ${name}`);
      out(`       ${((e && e.message) || String(e)).split('\n')[0]}`);
    }
  }

  return { pass, failures };
}

module.exports = { test, run, group, assert, out };
