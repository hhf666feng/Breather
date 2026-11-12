'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { EventEmitter } = require('node:events');

function electronFixture() {
  let focused;
  class Window extends EventEmitter {
    static fromWebContents(sender) { return sender.owner; }
    static getFocusedWindow() { return focused; }
    constructor(options) {
      super(); this.options = options; this.visible = false; this.destroyed = false; this.minimized = false;
      this.webContents = new EventEmitter(); this.webContents.owner = this;
      Object.assign(this.webContents, { session: { setPermissionRequestHandler() {}, setPermissionCheckHandler() {} }, isDestroyed: () => this.destroyed, getURL: () => this.url, send() {}, setWindowOpenHandler(handler) { this.openHandler = handler; } });
    }
    loadFile(filename) { this.url = require('node:url').pathToFileURL(filename).href; this.webContents.mainFrame = { url: this.url }; this.webContents.emit('did-finish-load'); return Promise.resolve(); }
    isDestroyed() { return this.destroyed; }
    show() { this.visible = true; }
    hide() { this.visible = false; }
    focus() { focused = this; }
    isVisible() { return this.visible; }
    isMinimized() { return this.minimized; }
    setSkipTaskbar(value) { this.skipTaskbar = value; }
    setMinimizable(value) { this.minimizable = value; }
    setClosable(value) { this.closable = value; }
    setAlwaysOnTop() {}
    setFullScreen() {}
    setBounds() {}
    restore() { this.minimized = false; this.visible = true; }
    minimize() { let blocked = false; this.emit('minimize', { preventDefault() { blocked = true; } }); if (!blocked) this.minimized = true; }
    close() { let blocked = false; this.emit('close', { preventDefault() { blocked = true; } }); if (!blocked) this.destroy(); }
    destroy() { this.destroyed = true; this.visible = false; this.emit('closed'); }
  }
  class Tray extends EventEmitter { constructor(icon) { super(); this.icon = icon; } setToolTip(value) { this.tooltip = value; } setContextMenu(menu) { this.menu = menu; } setTitle() {} destroy() {} isDestroyed() { return false; } }
  let menu;
  const notifications = [], beeps = [];
  return {
    notifications, beeps, shell: { beep() { beeps.push(Date.now()); } },
    app: { getVersion: () => '1.6.0', getLoginItemSettings: () => ({ openAtLogin: false }), setLoginItemSettings() {}, quit() {}, setAppUserModelId() {} },
    BrowserWindow: Window, Tray,
    Menu: { buildFromTemplate(template) { return { items: template }; }, setApplicationMenu(value) { menu = value; }, getApplicationMenu() { return menu; } },
    ipcMain: { handlers: new Map(), handle(name, handler) { this.handlers.set(name, handler); }, removeHandler(name) { this.handlers.delete(name); } },
    powerMonitor: Object.assign(new EventEmitter(), { getSystemIdleTime: () => 0 }),
    screen: Object.assign(new EventEmitter(), { getAllDisplays: () => [{ id: 1, bounds: { x: 0, y: 0, width: 1200, height: 800 }, workArea: { x: 0, y: 0, width: 1200, height: 760 } }], getPrimaryDisplay: () => ({ id: 1, bounds: { x: 0, y: 0, width: 1200, height: 800 }, workArea: { x: 0, y: 0, width: 1200, height: 760 } }) }),
    nativeImage: { createFromPath: () => ({ isEmpty: () => false, resize() { return this; } }), createFromBuffer: () => ({ isEmpty: () => false }) },
    Notification: class extends EventEmitter { static isSupported() { return true; } constructor(options) { super(); this.options = options; } show() { notifications.push(this.options); } }, dialog: {},
  };
}

async function fixture(t, smokeMode = true, initialRaw = null) {
  const filename = path.join(__dirname, '../main.cjs');
  assert.ok(fs.existsSync(filename), 'main runtime must exist');
  const { createRuntime } = require(filename);
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'breather-runtime-'));
  const electron = electronFixture();
  if (initialRaw !== null) fs.writeFileSync(path.join(directory, 'state.json'), initialRaw);
  const runtime = createRuntime({ electron, core: require('../core.cjs'), storageRoot: directory, smokeMode });
  t.after(() => { runtime.shutdown(); assert.ok(directory.startsWith(path.join(os.tmpdir(), 'breather-runtime-'))); fs.rmSync(directory, { recursive: true, force: true }); });
  await runtime.init();
  return { runtime, electron, directory };
}

test('locked Windows smoke storage defers cleanup without changing passed report or successful exit', t => {
  const { finishSmoke } = require('../main.cjs');
  assert.equal(typeof finishSmoke, 'function');
  const outputDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'breather-cleanup-report-'));
  t.after(() => { assert.ok(path.basename(outputDirectory).startsWith('breather-cleanup-report-')); fs.rmSync(outputDirectory, { recursive: true, force: true }); });
  const reportFile = path.join(outputDirectory, 'report.json');
  const storageRoot = path.join(os.tmpdir(), 'breather-electron-smoke-regression');
  for (const code of ['EPERM', 'EBUSY']) {
    fs.writeFileSync(reportFile, JSON.stringify({ passed: true, checks: ['native-window-checks'] }));
    const exits = [], removals = [];
    finishSmoke({ app: { exit: value => exits.push(value) }, storageRoot, outputDirectory, exitCode: 0, removeDirectory: (target, options) => { removals.push({ target, options }); throw Object.assign(new Error('Chromium holds session directory'), { code }); } });
    const report = JSON.parse(fs.readFileSync(reportFile, 'utf8'));
    assert.equal(report.passed, true);
    assert.equal(report.cleanupDeferred, true);
    assert.equal(report.cleanupError, code);
    assert.deepEqual(exits, [0]);
    assert.equal(removals.length, 1);
    assert.equal(removals[0].target, storageRoot);
  }
  let attempts = 0;
  assert.throws(() => finishSmoke({ app: { exit() {} }, storageRoot: path.join(os.tmpdir(), 'BreatherWindows'), outputDirectory, exitCode: 0, removeDirectory: () => { attempts++; } }), /isolated/i);
  assert.equal(attempts, 0);
});

test('Electron browser entry boots even when Electron owns require.main and Node imports remain inert', () => {
  const { shouldBoot } = require('../main.cjs');
  assert.equal(typeof shouldBoot, 'function');
  assert.equal(shouldBoot({ versions: { electron: '45.3.0' }, type: 'browser' }, false), true);
  assert.equal(shouldBoot({ versions: { electron: '45.3.0' }, type: 'browser' }, true), true);
  assert.equal(shouldBoot({ versions: { electron: '45.3.0' }, type: 'renderer' }, false), false);
  assert.equal(shouldBoot({ versions: {} }, false), false);
  assert.equal(shouldBoot({ versions: {} }, true), true);
});

test('storage directories exist before Electron overrides userData and sessionData', () => {
  const { prepareStorage } = require('../main.cjs');
  assert.equal(typeof prepareStorage, 'function');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'breather-storage-'));
  const paths = {};
  try {
    const root = prepareStorage({ getPath: () => directory, setPath(name, filename) { assert.equal(fs.statSync(filename).isDirectory(), true); paths[name] = filename; } }, false);
    assert.equal(root, path.join(directory, 'BreatherWindows'));
    assert.equal(paths.userData, root);
    assert.equal(paths.sessionData, path.join(root, 'session'));
  } finally {
    assert.ok(directory.startsWith(path.join(os.tmpdir(), 'breather-storage-')));
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('normal main close and Ctrl W hide the real runtime window without ending monitoring', async t => {
  const { runtime } = await fixture(t);
  runtime.mainWindow.close();
  assert.equal(runtime.mainWindow.isVisible(), false);
  assert.equal(runtime.mainWindow.isDestroyed(), false);
  runtime.showMain();
  let prevented = false;
  runtime.mainWindow.webContents.emit('before-input-event', { preventDefault() { prevented = true; } }, { type: 'keyDown', key: 'w', control: true });
  assert.equal(prevented, true);
  assert.equal(runtime.mainWindow.isVisible(), false);
  assert.equal(runtime.state().phase, 'monitoring');
});

test('normal main close during rest accounts a skip before hiding and threshold countdown matches break time', async t => {
  const { runtime } = await fixture(t);
  await runtime.command('settings', { workSeconds: 120, fatigueThreshold: 50 });
  assert.equal(runtime.state().remainingText, '1:00');
  await runtime.command('rest');
  runtime.mainWindow.close();
  await runtime.command('get-state');
  assert.equal(runtime.mainWindow.isVisible(), false);
  assert.notEqual(runtime.state().phase, 'resting');
  assert.equal(runtime.state().records[0].breaksSkipped, 1);
  assert.equal(runtime.state().records[0].breaksCompleted, 0);
});

test('strict rest blocks close/minimize/pause/skip and non-strict close records a skip', async t => {
  const { runtime } = await fixture(t);
  await runtime.command('settings', { strictMode: true });
  await runtime.command('rest');
  assert.equal(runtime.state().phase, 'resting');
  const rest = runtime.restWindows[0];
  rest.close(); rest.minimize(); runtime.mainWindow.close();
  assert.equal(rest.isDestroyed(), false);
  assert.equal(rest.isMinimized(), false);
  assert.equal(runtime.state().phase, 'resting');
  assert.equal((await runtime.command('pause')).ok, false);
  assert.equal((await runtime.command('skip')).ok, false);
  // Changes to strictMode cannot remove an active break's snapshot guard.
  await runtime.command('settings', { strictMode: false });
  assert.equal((await runtime.command('skip')).ok, false);
});

test('resting guards cannot be changed through settings while identical values and unrelated settings remain editable', async t => {
  const { runtime } = await fixture(t);
  await runtime.command('settings', { strictMode: false, skipChallengeEnabled: true });
  await runtime.command('rest');
  const before = fs.readFileSync(runtime.dataFile, 'utf8');
  assert.equal((await runtime.command('settings', { skipChallengeEnabled: false, restSeconds: 99 })).ok, false);
  assert.equal((await runtime.command('settings', { strictMode: true })).ok, false);
  assert.equal(runtime.state().settings.skipChallengeEnabled, true);
  assert.equal(runtime.state().settings.strictMode, false);
  assert.equal(runtime.state().settings.restSeconds, 20);
  assert.equal(fs.readFileSync(runtime.dataFile, 'utf8'), before);
  assert.equal((await runtime.command('settings', { strictMode: false, skipChallengeEnabled: true, language: 'en' })).ok, true);
  assert.equal(runtime.state().settings.language, 'en');
  await runtime.command('skip');
  const challenge = runtime.state().challenge;
  assert.ok(challenge);
  assert.equal(runtime.state().phase, 'resting');
  await runtime.command('answer-challenge', challenge.left + challenge.right);
  assert.notEqual(runtime.state().phase, 'resting');
  assert.equal((await runtime.command('settings', { skipChallengeEnabled: false, strictMode: true })).ok, true);
});

test('challenge cannot be bypassed by pause/close, cancellation preserves the break', async t => {
  const { runtime } = await fixture(t);
  await runtime.command('settings', { skipChallengeEnabled: true });
  await runtime.command('rest');
  runtime.restWindows[0].close();
  await runtime.command('get-state'); // Close routes through the same serialized command queue as IPC.
  const challenge = runtime.state().challenge;
  assert.ok(challenge);
  assert.equal(runtime.state().phase, 'resting');
  assert.equal((await runtime.command('answer-challenge', -1)).ok, false);
  assert.equal(runtime.state().phase, 'resting');
  await runtime.command('cancel-challenge');
  assert.equal(runtime.state().challenge, null);
  await runtime.command('skip');
  const current = runtime.state().challenge;
  await runtime.command('answer-challenge', current.left + current.right);
  assert.notEqual(runtime.state().phase, 'resting');
});

test('restore validates before replacing disk and in-memory settings', async t => {
  const { runtime, directory } = await fixture(t);
  await runtime.command('settings', { language: 'en', restSeconds: 40 });
  runtime.persist();
  const before = fs.readFileSync(path.join(directory, 'state.json'), 'utf8');
  assert.throws(() => runtime.restoreDocument({ settings: { language: 'evil' }, records: [] }));
  assert.equal(fs.readFileSync(path.join(directory, 'state.json'), 'utf8'), before);
  assert.equal(runtime.state().settings.language, 'en');
  runtime.restoreDocument({ settings: { ...runtime.state().settings, language: 'zh-Hans' }, records: runtime.state().records });
  assert.equal(runtime.state().settings.language, 'zh-Hans');
  assert.equal(JSON.parse(fs.readFileSync(path.join(directory, 'state.json'))).settings.language, 'zh-Hans');
});

test('snooze countdown shows the remaining defer time', async t => {
  const { runtime } = await fixture(t);
  await runtime.command('snooze');
  assert.equal(runtime.state().phase, 'snoozed');
  assert.equal(runtime.state().remainingText, '5:00');
});

test('rest start and actual completion beep when enabled, while smoke never beeps', async t => {
  const { runtime, electron } = await fixture(t, false);
  await runtime.command('rest');
  assert.equal(electron.beeps.length, 1);
  runtime.tick(Date.now() + 21000);
  assert.equal(electron.beeps.length, 2);
  await runtime.command('settings', { soundEnabled: false });
  await runtime.command('rest'); runtime.tick(Date.now() + 21000);
  assert.equal(electron.beeps.length, 2);
  const isolated = await fixture(t, true);
  await isolated.runtime.command('rest'); isolated.runtime.tick(Date.now() + 21000);
  assert.equal(isolated.electron.beeps.length, 0);
});

test('restore preserves a byte-for-byte pre-restore copy and copy failure leaves data untouched', async t => {
  const { runtime, directory } = await fixture(t);
  await runtime.command('settings', { language: 'en' });
  const before = fs.readFileSync(runtime.dataFile, 'utf8');
  runtime.restoreDocument({ settings: { ...runtime.state().settings, language: 'zh-Hans' }, records: runtime.state().records });
  const recovery = path.join(directory, 'recovery');
  const copies = fs.readdirSync(recovery);
  assert.equal(copies.length, 1);
  assert.match(copies[0], /^before-restore-/);
  assert.equal(fs.readFileSync(path.join(recovery, copies[0]), 'utf8'), before);
  const blocked = await fixture(t);
  fs.writeFileSync(path.join(blocked.directory, 'recovery'), 'not a directory');
  const blockedBefore = fs.readFileSync(blocked.runtime.dataFile, 'utf8');
  assert.throws(() => blocked.runtime.restoreDocument({ settings: { language: 'en' }, records: [] }));
  assert.equal(fs.readFileSync(blocked.runtime.dataFile, 'utf8'), blockedBefore);
  assert.equal(blocked.runtime.state().settings.language, 'zh-Hans');
});

test('first settings change preserves unreadable startup data and failed preservation blocks overwrite', async t => {
  const original = '{broken-data-retain-exactly';
  const { runtime, directory } = await fixture(t, true, original);
  await runtime.command('settings', { language: 'en' });
  const copies = fs.readdirSync(path.join(directory, 'recovery'));
  assert.equal(fs.readFileSync(path.join(directory, 'recovery', copies[0]), 'utf8'), original);
  const blocked = await fixture(t, true, original);
  fs.writeFileSync(path.join(blocked.directory, 'recovery'), 'not a directory');
  const reply = await blocked.runtime.command('settings', { language: 'en' });
  assert.equal(reply.ok, false);
  assert.equal(fs.readFileSync(blocked.runtime.dataFile, 'utf8'), original);
  assert.equal(blocked.runtime.state().settings.language, 'zh-Hans');
});

test('tray timer preference removes countdown without affecting monitoring', async t => {
  const { runtime } = await fixture(t);
  assert.match(runtime.tray.tooltip, /\d+:\d+/);
  await runtime.command('settings', { showMenuBarTime: false });
  assert.equal(runtime.tray.tooltip, 'Breather');
});

test('advance and daily-limit notifications fire once and never invent rest', async t => {
  const { runtime, electron } = await fixture(t, false);
  await runtime.command('settings', { monitoringMode: 'continuous', workSeconds: 120, advanceNoticeEnabled: true });
  const now = Date.now();
  for (let seconds = 10; seconds <= 70; seconds += 10) runtime.tick(now + seconds * 1000);
  assert.equal(electron.notifications.length, 1);
  assert.equal(runtime.state().phase, 'monitoring');
  const core = require('../core.cjs');
  const record = { day: core.dayKey(new Date()), activeSeconds: 1801, peakFatigueSeconds: 0, breaksOffered: 0, breaksCompleted: 0, breaksSkipped: 0, hourlySeconds: Array(24).fill(0) };
  runtime.restoreDocument({ settings: { ...runtime.state().settings, advanceNoticeEnabled: false, dailyLimitEnabled: true, dailyLimitHours: 0.5 }, records: [record] });
  runtime.tick(); runtime.tick();
  assert.equal(electron.notifications.length, 2);
  assert.equal(runtime.state().phase, 'monitoring');
  assert.equal(runtime.state().records[0].breaksCompleted, 0);
});

test('IPC rejects unknown senders, external documents and get-state payload smuggling', async t => {
  const { runtime, electron } = await fixture(t);
  const handler = electron.ipcMain.handlers.get('breather:command');
  const sender = runtime.mainWindow.webContents;
  const event = { sender, senderFrame: sender.mainFrame };
  assert.equal((await handler(event, 'pause')).ok, true);
  assert.equal((await handler(event, 'get-state', { evil: true })).ok, false);
  assert.equal((await handler({ sender: {}, senderFrame: {} }, 'pause')).ok, false);
  sender.mainFrame.url = 'http://localhost/';
  assert.equal((await handler(event, 'pause')).ok, false);
});

test('lock/suspend override system availability and all renderer windows stay sandboxed', async t => {
  const { runtime, electron } = await fixture(t);
  electron.powerMonitor.emit('lock-screen');
  assert.equal(runtime.state().screenAvailable, false);
  electron.powerMonitor.emit('suspend');
  electron.powerMonitor.emit('unlock-screen');
  assert.equal(runtime.state().screenAvailable, false);
  electron.powerMonitor.emit('resume');
  assert.equal(runtime.state().screenAvailable, true);
  await runtime.command('rest');
  for (const window of [runtime.mainWindow, ...runtime.restWindows]) {
    assert.equal(window.options.webPreferences.sandbox, true);
    assert.equal(window.options.webPreferences.contextIsolation, true);
    assert.equal(window.options.webPreferences.nodeIntegration, false);
    assert.deepEqual(window.webContents.openHandler({ url: 'https://evil.example/' }), { action: 'deny' });
  }
});
