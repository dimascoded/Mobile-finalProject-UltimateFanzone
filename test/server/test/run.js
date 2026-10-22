'use strict';

/**
 * Entry point `npm test`.
 * Lihat test/harness.js kenapa runner bawaan Node tidak dipakai.
 */

const fs = require('node:fs');
const path = require('node:path');
const { run, group, out } = require('./harness');

// Database bersih setiap kali test dijalankan.
fs.rmSync(path.join(__dirname, '..', 'data'), { recursive: true, force: true });

const files = fs
  .readdirSync(__dirname)
  .filter((f) => f.endsWith('.test.js'))
  .sort();

for (const file of files) {
  group(file);
  require(path.join(__dirname, file));
}

async function main() {
  const { pass, failures } = await run();

  if (failures.length > 0) {
    out(`\nserver: ${pass} passed, ${failures.length} failed`);
    out('\nGagal:');
    for (const f of failures) out(`  - ${f.name}`);
    process.exit(1);
  }

  out(`\nserver: ${pass} passed, 0 failed`);
  process.exit(0);
}

main();
