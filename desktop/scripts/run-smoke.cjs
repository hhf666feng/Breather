'use strict';
// Bounded parent process: a hung Electron child must never hang CI.
const fs = require('node:fs');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const outputDirectory = path.resolve(process.argv[2] || path.join(__dirname, '../dist/reports/native'));
const { resolveSmokeLaunch } = require('./smoke-launch.cjs');
const launch = resolveSmokeLaunch(outputDirectory, process.argv.slice(3));
fs.mkdirSync(outputDirectory, { recursive: true });
// The default CLI's lazy binary download and packaged EXE both run inside
// the child process tree, so the same deadline covers the entire launch.
const environment = { ...process.env };
delete environment.ELECTRON_RUN_AS_NODE;
const child = spawn(launch.executable, launch.arguments, {
  cwd: path.resolve(__dirname, '..'), env: environment, stdio: ['ignore', 'pipe', 'pipe'],
  windowsHide: false, detached: process.platform !== 'win32',
});
let stdout = '', stderr = '', timedOut = false;
const limit = 1024 * 1024;
child.stdout.on('data', bytes => { stdout = (stdout + bytes).slice(-limit); process.stdout.write(bytes); });
child.stderr.on('data', bytes => { stderr = (stderr + bytes).slice(-limit); process.stderr.write(bytes); });
const deadline = setTimeout(() => {
  timedOut = true;
  if (child.pid && Number.isInteger(child.pid)) {
    if (process.platform === 'win32') spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], { timeout: 10000, windowsHide: true });
    else { try { process.kill(-child.pid, 'SIGKILL'); } catch { child.kill('SIGKILL'); } }
  }
}, 120000);
function finish(code, error) {
  clearTimeout(deadline);
  fs.writeFileSync(path.join(outputDirectory, 'stdout.log'), stdout);
  fs.writeFileSync(path.join(outputDirectory, 'stderr.log'), stderr + (error ? '\n' + error.stack : ''));
  let report;
  try { report = JSON.parse(fs.readFileSync(path.join(outputDirectory, 'report.json'), 'utf8')); } catch { /* failure below is explicit */ }
  const passed = !timedOut && !error && code === 0 && stdout.includes('BREATHER_SMOKE_PASSED ' + path.join(outputDirectory, 'report.json')) && report?.passed === true && Array.isArray(report.screenshots) && report.screenshots.length > 0 && report.screenshots.every(file => path.basename(file) === file && fs.statSync(path.join(outputDirectory, file)).size > 0);
  if (!passed) {
    fs.writeFileSync(path.join(outputDirectory, 'runner-failure.json'), JSON.stringify({ passed: false, code, timedOut, error: error?.message || null }, null, 2));
    process.exitCode = 1;
    console.error('Native Electron smoke failed; see reports in ' + outputDirectory);
  }
}
child.once('error', error => finish(null, error));
child.once('close', code => finish(code));
