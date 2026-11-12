'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const files = ['test', 'scripts'].flatMap(directory => fs.readdirSync(path.join(root, directory)).filter(name => name.endsWith('.test.cjs')).map(name => path.join(root, directory, name))).sort();
const reportIndex = process.argv.indexOf('--report-dir');
const arguments_ = ['--test'];
let reportDirectory;
if (reportIndex !== -1) {
  if (!process.argv[reportIndex + 1]) throw new Error('--report-dir requires a directory');
  reportDirectory = path.resolve(process.argv[reportIndex + 1]);
  fs.mkdirSync(reportDirectory, { recursive: true });
  arguments_.push('--test-reporter=spec', '--test-reporter-destination=stdout', '--test-reporter=junit', '--test-reporter-destination=' + path.join(reportDirectory, 'node-tests.xml'));
}
const result = spawnSync(process.execPath, [...arguments_, ...files], { cwd: root, stdio: 'inherit', timeout: 120000 });
if (reportDirectory) fs.writeFileSync(path.join(reportDirectory, 'node-tests.json'), JSON.stringify({ passed: result.status === 0, exitCode: result.status, files: files.map(file => path.relative(root, file)), error: result.error?.message || null }, null, 2));
if (result.error) console.error(result.error);
process.exitCode = result.status === 0 ? 0 : 1;
