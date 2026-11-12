'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const files = [];
function collect(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (['node_modules', 'dist', 'build'].includes(entry.name)) continue;
    const filename = path.join(directory, entry.name);
    if (entry.isDirectory()) collect(filename);
    else if (/\.(cjs|js)$/.test(entry.name)) files.push(filename);
  }
}
collect(root);
for (const filename of files) {
  const result = spawnSync(process.execPath, ['--check', filename], { encoding: 'utf8', timeout: 10000 });
  if (result.status !== 0) { process.stderr.write(result.stderr || String(result.error)); process.exit(1); }
}
console.log('Syntax checked ' + files.length + ' JavaScript files.');
