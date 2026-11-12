'use strict';
// Runs inside the real Electron main process, exclusively with isolated userData.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { setTimeout: delay } = require('node:timers/promises');
const { writeAtomicJSON, readJSON } = require('./runtime-policy.cjs');

function waitForSmokeDocument(view) {
  return new Promise((resolve, reject) => {
    let finished = false, fontsReady = !document.fonts;
    let pollTimer, firstPaint, secondPaint;
    const finish = error => {
      if (finished) return;
      finished = true;
      clearTimeout(deadline); clearTimeout(pollTimer);
      cancelAnimationFrame(firstPaint); cancelAnimationFrame(secondPaint);
      if (error) reject(error); else resolve(true);
    };
    const deadline = setTimeout(() => finish(new Error('Renderer readiness timed out after 5000ms')), 5000);
    if (document.fonts) document.fonts.ready.then(() => { fontsReady = true; }, finish);
    const check = () => {
      if (finished) return;
      const loading = document.querySelector('#loading');
      const root = document.querySelector(view === 'rest' ? '#rest-view' : '#main-view');
      if (fontsReady && loading?.hidden === true && root?.hidden === false && root.getClientRects().length > 0) {
        firstPaint = requestAnimationFrame(() => { secondPaint = requestAnimationFrame(() => finish()); });
      } else pollTimer = setTimeout(check, 25);
    };
    check();
  });
}

async function waitForSmokeReady(window, view) {
  const readiness = window.webContents.executeJavaScript('(' + waitForSmokeDocument.toString() + ')(' + JSON.stringify(view) + ')');
  let deadline;
  try {
    return await Promise.race([readiness, new Promise((_resolve, reject) => { deadline = setTimeout(() => reject(new Error('Renderer readiness IPC timed out after 5000ms')), 5000); })]);
  } finally { clearTimeout(deadline); }
}

async function captureSmokeWindow(window, wait = delay, view = 'main') {
  await waitForSmokeReady(window, view);
  try { return await window.webContents.capturePage(); }
  catch (error) {
    if (error?.message !== 'UnknownVizError' && error?.name !== 'UnknownVizError') throw error;
    // Virtual Windows GPUs can transiently lose a compositor surface. Retry once.
    await wait(200);
    return window.webContents.capturePage();
  }
}

async function run({ runtime, electron, outputDirectory, storageRoot, createRuntime, core, rendererDiagnostics = [] }) {
  const { app, Menu, BrowserWindow } = electron;
  const checks = [];
  const screenshots = [];
  const check = (name, assertion) => { assertion(); checks.push(name); };
  const reportFile = path.join(outputDirectory, 'report.json');
  const initialTray = runtime.tray;
  const initialWindow = runtime.mainWindow;
  const language = process.argv.includes('--language-en') ? 'en' : 'zh-Hans';
  const compact = process.argv.includes('--smoke-compact');
  async function screenshot(window, name) {
    const view = runtime.owners.get(window.webContents)?.view || 'main';
    const image = await captureSmokeWindow(window, delay, view);
    assert.equal(image.isEmpty(), false, 'native window screenshot must contain pixels');
    const target = path.join(outputDirectory, name + '.png');
    fs.writeFileSync(target, image.toPNG());
    screenshots.push(path.basename(target));
  }
  async function key(window, value, modifiers = []) {
    if (window.isMinimized()) window.restore();
    window.show(); window.focus();
    await delay(120);
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => { window.webContents.removeListener('before-input-event', listener); reject(new Error('Native input did not reach registered accelerator: ' + value)); }, 5000);
      const listener = (_event, input) => {
        if (input.type === 'keyDown' && String(input.key).toLowerCase() === value.toLowerCase()) {
          clearTimeout(timeout); window.webContents.removeListener('before-input-event', listener); resolve();
        }
      };
      window.webContents.on('before-input-event', listener);
      window.webContents.sendInputEvent({ type: 'keyDown', keyCode: value, modifiers });
      window.webContents.sendInputEvent({ type: 'keyUp', keyCode: value, modifiers });
    });
    await runtime.command('get-state');
    await delay(80);
  }
  async function menu(id) {
    const item = Menu.getApplicationMenu().getMenuItemById(id);
    assert.ok(item, 'Real native application menu item exists: ' + id);
    item.click(item, BrowserWindow.getFocusedWindow(), {});
    await runtime.command('get-state');
    await delay(100);
  }
  try {
    check('isolated-storage-and-version', () => {
      assert.equal(app.getPath('userData'), storageRoot);
      assert.ok(path.basename(storageRoot).startsWith('breather-electron-smoke-'));
      assert.equal(runtime.state().version, '1.6.0');
      assert.equal(runtime.state().settings.language, language);
    });
    await screenshot(initialWindow, 'main-' + language);
    const sandbox = await initialWindow.webContents.executeJavaScript("({node: typeof require, process: typeof process, bridge: typeof window.breather?.getState, csp: document.querySelector('meta[http-equiv=\"Content-Security-Policy\"]')?.content, loadingHidden: document.querySelector('#loading')?.hidden, mainVisible: !document.querySelector('#main-view')?.hidden, fatigue: document.querySelector('[data-bind=\"fatigue\"]')?.textContent})");
    check('renderer-ready-with-real-state', () => { assert.equal(sandbox.loadingHidden, true); assert.equal(sandbox.mainVisible, true); assert.notEqual(sandbox.fatigue, '—'); assert.ok(sandbox.fatigue); });
    check('renderer-sandbox-and-preload', () => { assert.equal(sandbox.node, 'undefined'); assert.equal(sandbox.process, 'undefined'); assert.equal(sandbox.bridge, 'function'); assert.ok(sandbox.csp?.includes("connect-src 'none'")); });
    await key(initialWindow, 'W', ['control']);
    check('registered-ctrl-w-hides-main-and-preserves-tray', () => {
      assert.equal(initialWindow.isVisible(), false); assert.equal(initialWindow.isDestroyed(), false);
      assert.equal(runtime.tray, initialTray); assert.equal(initialTray.isDestroyed(), false);
      assert.notEqual(runtime.state().phase, 'paused');
    });
    await menu('show-main');
    check('ctrl-zero-menu-restores-same-main-window', () => { assert.equal(runtime.mainWindow, initialWindow); assert.equal(initialWindow.isVisible(), true); });
    await key(initialWindow, 'F4', ['alt']);
    check('alt-f4-hides-main-without-quitting', () => { assert.equal(initialWindow.isVisible(), false); assert.equal(initialWindow.isDestroyed(), false); });
    initialTray.emit('click');
    check('tray-click-restores-identical-window', () => { assert.equal(initialWindow.isVisible(), true); assert.equal(runtime.tray, initialTray); });
    await key(initialWindow, 'M', ['control']);
    check('ctrl-m-minimizes-main', () => assert.equal(initialWindow.isMinimized(), true));
    await menu('show-main');
    await menu('preferences');
    check('preferences-menu-targets-root-page', () => assert.equal(runtime.state().page, 'settings'));
    await screenshot(initialWindow, 'preferences-' + language);
    await runtime.command('settings', { strictMode: true, restSeconds: 20, skipChallengeEnabled: false, reminderStyle: compact ? 'mini' : 'fullscreen' });
    await menu('start-rest');
    await delay(250);
    const strictWindow = runtime.restWindows[0];
    assert.ok(strictWindow, 'A real BrowserWindow must present the strict rest');
    await screenshot(strictWindow, 'strict-rest-' + language);
    await key(strictWindow, 'W', ['control']);
    await key(strictWindow, 'M', ['control']);
    await key(strictWindow, 'F4', ['alt']);
    strictWindow.close();
    check('strict-rest-rejects-native-close-minimize-and-shortcuts', () => {
      assert.equal(runtime.state().phase, 'resting'); assert.equal(strictWindow.isDestroyed(), false); assert.equal(strictWindow.isMinimized(), false);
    });
    const pauseReply = await runtime.command('pause');
    const skipReply = await runtime.command('skip');
    check('strict-rest-rejects-pause-and-skip', () => { assert.equal(pauseReply.ok, false); assert.equal(skipReply.ok, false); });
    // Advance the pure monitor clock while leaving the real native windows under test.
    runtime.tick(Date.now() + 21000);
    check('strict-rest-completes-through-clock-only', () => {
      assert.notEqual(runtime.state().phase, 'resting');
      assert.equal(runtime.restWindows.length, 0);
      assert.ok(runtime.state().records.some(record => record.breaksCompleted === 1));
    });
    assert.equal((await runtime.command('pause')).ok, true);
    check('pause-and-resume-real-runtime', () => assert.equal(runtime.state().phase, 'paused'));
    await runtime.command('pause');
    await runtime.command('settings', { strictMode: false, skipChallengeEnabled: false, restSeconds: 20 });
    await runtime.command('rest');
    await delay(150);
    await key(runtime.restWindows[0], 'W', ['control']);
    check('normal-rest-close-accounts-as-skipped', () => {
      assert.notEqual(runtime.state().phase, 'resting');
      assert.ok(runtime.state().records.some(record => record.breaksSkipped === 1));
    });
    await runtime.command('settings', { skipChallengeEnabled: true });
    await runtime.command('rest');
    await delay(150);
    await key(runtime.restWindows[0], 'W', ['control']);
    const challenge = runtime.state().challenge;
    check('close-cannot-bypass-arithmetic-gate', () => { assert.ok(challenge); assert.equal(runtime.state().phase, 'resting'); });
    assert.equal((await runtime.command('answer-challenge', challenge.left + challenge.right + 1)).ok, false);
    await runtime.command('answer-challenge', challenge.left + challenge.right);
    check('correct-answer-finishes-skip-command', () => { assert.notEqual(runtime.state().phase, 'resting'); assert.equal(runtime.state().challenge, null); });
    await runtime.command('settings', { language: language === 'en' ? 'zh-Hans' : 'en', restSeconds: 35 });
    check('language-rebuilds-native-menu', () => assert.equal(Menu.getApplicationMenu().getMenuItemById('preferences').label, language === 'en' ? '偏好设置…' : 'Preferences…'));
    await runtime.command('launch-at-login', true);
    check('smoke-login-setting-is-simulated-and-isolated', () => assert.equal(runtime.state().launchAtLogin, true));
    await runtime.command('launch-at-login', false);
    runtime.persist();
    const before = fs.readFileSync(runtime.dataFile, 'utf8');
    assert.throws(() => runtime.restoreDocument({ settings: { language: 'bad' }, records: [] }));
    check('invalid-restore-is-transactional', () => assert.equal(fs.readFileSync(runtime.dataFile, 'utf8'), before));
    const backup = readJSON(runtime.dataFile);
    runtime.restoreDocument({ settings: { ...backup.settings, language }, records: backup.records });
    check('valid-backup-restore-commits', () => { assert.equal(runtime.state().settings.language, language); assert.equal(readJSON(runtime.dataFile).settings.language, language); });
    runtime.shutdown();
    const reloaded = createRuntime({ electron, core, storageRoot, smokeMode: true });
    try {
      await reloaded.init();
      check('persistent-state-reloads-in-new-runtime', () => {
        assert.equal(reloaded.state().settings.restSeconds, 35);
        assert.equal(reloaded.state().settings.language, language);
        assert.deepEqual(reloaded.state().records.map(({ day, breaksCompleted, breaksSkipped }) => ({ day, breaksCompleted, breaksSkipped })), backup.records.map(({ day, breaksCompleted, breaksSkipped }) => ({ day, breaksCompleted, breaksSkipped })));
      });
      await screenshot(reloaded.mainWindow, 'restored-' + language);
    } finally { reloaded.shutdown(); }
    check('renderer-no-preload-or-console-errors', () => assert.deepEqual(rendererDiagnostics.filter(item => item.kind === 'preload-error' || item.level === 'error' || item.level === 3), []));
    writeAtomicJSON(reportFile, { passed: true, platform: process.platform, version: '1.6.0', electron: process.versions.electron, architecture: process.arch, isolated: true, packaged: Boolean(app.isPackaged), language, compact, checks, screenshots, rendererDiagnostics });
    console.log('BREATHER_SMOKE_PASSED ' + reportFile);
  } catch (error) {
    writeAtomicJSON(reportFile, { passed: false, platform: process.platform, version: '1.6.0', error: error.stack, checks, screenshots, rendererDiagnostics });
    throw error;
  }
}
module.exports = { run, captureSmokeWindow };
