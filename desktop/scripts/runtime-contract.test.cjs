'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const policyPath = path.join(__dirname, 'runtime-policy.cjs');

function policy() {
  assert.ok(fs.existsSync(policyPath), 'runtime policy must exist before desktop can expose IPC');
  return require(policyPath);
}

test('IPC accepts only documented commands and exact payload shapes', () => {
  const { validateCommand } = policy();
  for (const name of ['get-state', 'pause', 'rest', 'snooze', 'skip', 'quit', 'export-csv', 'export-backup', 'restore-backup', 'choose-wallpaper', 'clear-wallpaper', 'dismiss-error', 'cancel-challenge']) {
    assert.equal(validateCommand(name), undefined);
    assert.throws(() => validateCommand(name, { injected: true }));
  }
  assert.deepEqual(validateCommand('settings', { language: 'en', weekdays: [2, 3], restSeconds: 30 }), { language: 'en', weekdays: [2, 3], restSeconds: 30 });
  assert.equal(validateCommand('launch-at-login', false), false);
  assert.equal(validateCommand('answer-challenge', '12'), '12');
  for (const [name, payload] of [['exec', 'x'], ['settings', { wallpaperPath: '/etc/passwd' }], ['settings', { workSeconds: Infinity }], ['settings', { strictMode: 'false' }], ['settings', { language: 'fr' }], ['settings', { weekdays: [0, 8] }], ['settings', { __proto__: { hacked: true } }], ['launch-at-login', 1], ['answer-challenge', {}]]) {
    assert.throws(() => validateCommand(name, payload), `${name} must reject unsafe payload`);
  }
});

test('IPC requires a registered BrowserWindow owner and its exact trusted top frame', () => {
  const { isOwnedSender } = policy();
  const url = pathToFileURL(path.join(__dirname, '../renderer/index.html')).href;
  const frame = { url };
  const sender = { mainFrame: frame, isDestroyed: () => false, getURL: () => url };
  const owner = { webContents: sender, isDestroyed: () => false };
  const owners = new Map([[sender, { window: owner }]]);
  assert.equal(isOwnedSender({ sender, senderFrame: frame }, owners, url), true);
  assert.equal(isOwnedSender({ sender, senderFrame: { url } }, owners, url), false);
  assert.equal(isOwnedSender({ sender: { ...sender }, senderFrame: frame }, owners, url), false);
  frame.url = 'https://evil.example/';
  assert.equal(isOwnedSender({ sender, senderFrame: frame }, owners, url), false);
  frame.url = url;
  owner.isDestroyed = () => true;
  assert.equal(isOwnedSender({ sender, senderFrame: frame }, owners, url), false);
});

test('atomic persistence preserves the previous document when serialization fails', () => {
  const { writeAtomicJSON, readJSON } = policy();
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'breather-policy-'));
  const target = path.join(directory, 'state.json');
  try {
    writeAtomicJSON(target, { settings: { language: 'en' }, records: [] });
    const circular = {}; circular.self = circular;
    assert.throws(() => writeAtomicJSON(target, circular));
    assert.deepEqual(readJSON(target), { settings: { language: 'en' }, records: [] });
    assert.throws(() => readJSON(target, 1), /large/i);
  } finally {
    assert.equal(path.dirname(target), directory);
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('wallpaper reader rejects symlinks, unknown formats and oversized files', () => {
  const { imageDataURL } = policy();
  const png = Buffer.from('89504e470d0a1a0a00000000', 'hex');
  assert.equal(imageDataURL(png), 'data:image/png;base64,' + png.toString('base64'));
  assert.throws(() => imageDataURL(Buffer.from('<svg onload="evil()"/>')));
  assert.throws(() => imageDataURL(Buffer.alloc(8 * 1024 * 1024 + 1)));
});

test('strict break guards every close/minimize entry and normal rest requests skip accounting', () => {
  const { windowIntent } = policy();
  for (const intent of ['close', 'minimize']) {
    assert.equal(windowIntent({ phase: 'resting', breakIsStrict: true }, 'rest', intent), 'deny');
    assert.equal(windowIntent({ phase: 'resting', breakIsStrict: false }, 'rest', intent), 'skip');
    assert.equal(windowIntent({ phase: 'resting', breakIsStrict: true }, 'main', intent), 'deny');
  }
  assert.equal(windowIntent({ phase: 'working', breakIsStrict: false }, 'main', 'close'), 'hide');
  assert.equal(windowIntent({ phase: 'working', breakIsStrict: false }, 'main', 'minimize'), 'minimize');
});
