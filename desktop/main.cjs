'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { pathToFileURL } = require('node:url');
const { validateCommand, isOwnedSender, writeAtomicJSON, readJSON, imageDataURL, windowIntent, MAX_DOCUMENT_BYTES } = require('./scripts/runtime-policy.cjs');

const APP_ID = 'local.breather.windows';
const VERSION = '1.6.0';
const CSP = "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'none'; media-src 'none'; object-src 'none'; base-uri 'none'; frame-src 'none'; form-action 'none'";

function createRuntime({ electron, core, storageRoot, smokeMode = false }) {
  const { app, BrowserWindow, Tray, Menu, ipcMain, screen, powerMonitor, nativeImage, Notification, dialog } = electron;
  const { Monitor, defaultSettings, validateSettings, validateState, csv } = core;
  const entryFile = path.join(__dirname, 'renderer', 'index.html');
  const trustedURL = pathToFileURL(entryFile).href;
  const dataFile = path.join(storageRoot, 'state.json');
  const wallpaperFile = path.join(storageRoot, 'wallpaper.image');
  const owners = new Map();
  const restWindows = [];
  const powerListeners = [];
  let mainWindow, tray, timer, monitor, errorMessage = null, wallpaperURL = null;
  let challenge = null, page = 'overview', quitting = false, locked = false, suspended = false, idleAvailable = true;
  let lastNotifications = 0, lastMenuKey = '', lastPersist = 0, commandQueue = Promise.resolve();
  let launchAtLogin = false, advanceNotified = false, dailyLimitNotified = null, shutdownComplete = false;
  try {
    monitor = new Monitor(fs.existsSync(dataFile) ? validateState(readJSON(dataFile)) : { settings: defaultSettings(), records: [] });
  } catch (error) {
    monitor = new Monitor();
    errorMessage = 'Saved data could not be loaded. The original file has been preserved: ' + error.message;
  }
  // A corrupt source file is preserved until the user explicitly changes or restores data.
  let preserveCorruptData = Boolean(errorMessage);
  monitor.resetClock(Date.now());
  if (smokeMode && process.argv.includes('--language-en')) monitor.settings = validateSettings({ ...monitor.settings, language: 'en' });
  try { if (!smokeMode) launchAtLogin = Boolean(app.getLoginItemSettings().openAtLogin); } catch { /* unavailable platform facility */ }
  if (monitor.settings.wallpaperPath === wallpaperFile) {
    try { wallpaperURL = readWallpaper(wallpaperFile); } catch { monitor.settings = validateSettings({ ...monitor.settings, wallpaperPath: null }); }
  } else if (monitor.settings.wallpaperPath) monitor.settings = validateSettings({ ...monitor.settings, wallpaperPath: null });

  function readWallpaper(filename) {
    const stat = fs.lstatSync(filename);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > MAX_DOCUMENT_BYTES) throw new Error('Choose a regular image under 8 MB');
    const bytes = fs.readFileSync(filename);
    const url = imageDataURL(bytes);
    if (nativeImage.createFromBuffer(bytes).isEmpty()) throw new Error('Image could not be decoded');
    return url;
  }
  const isStrict = () => monitor.phase === 'resting' && monitor.breakIsStrict;
  const screenAvailable = () => !locked && !suspended && idleAvailable;
  const english = () => monitor.settings.language === 'en';
  const text = (zh, en) => english() ? en : zh;
  const snapshotDocument = () => ({ settings: monitor.settings, records: monitor.records });
  let lastBreakPhase = monitor.phase;
  let lastCompletedBreaks = monitor.records.reduce((sum, record) => sum + record.breaksCompleted, 0);
  function preserveSource(reason) {
    if (!fs.existsSync(dataFile)) return;
    const stat = fs.lstatSync(dataFile);
    if (!stat.isFile() || stat.isSymbolicLink()) throw new Error(text('原数据不是普通文件，已取消更改', 'Saved data is not a regular file; no changes were made'));
    const recoveryDirectory = path.join(storageRoot, 'recovery');
    fs.mkdirSync(recoveryDirectory, { recursive: true });
    const target = path.join(recoveryDirectory, reason + '-' + Date.now() + '-' + crypto.randomBytes(8).toString('hex') + '.json');
    fs.copyFileSync(dataFile, target, fs.constants.COPYFILE_EXCL);
    const descriptor = fs.openSync(target, 'r+');
    try { fs.fsyncSync(descriptor); } finally { fs.closeSync(descriptor); }
  }
  function preserveUnreadableSource() {
    if (preserveCorruptData) preserveSource('unreadable');
  }
  function persist() {
    if (preserveCorruptData) return;
    writeAtomicJSON(dataFile, snapshotDocument());
    lastPersist = Date.now();
  }
  function reportError(error) { errorMessage = error?.message || String(error); broadcast(); }
  function remainingText() {
    const remaining = monitor.phase === 'snoozed' && monitor.snoozeEnd !== null ? (monitor.snoozeEnd - Date.now()) / 1000 : monitor.phase === 'resting' ? monitor.breakRemaining : monitor.settings.workSeconds * monitor.settings.fatigueThreshold / 100 - monitor.workElapsed;
    const seconds = Math.max(0, Math.ceil(remaining));
    return Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0');
  }
  function state(view = 'main') {
    return {
      settings: { ...monitor.settings }, records: monitor.records, phase: monitor.phase,
      fatigue: monitor.fatigue, workElapsed: monitor.workElapsed, breakRemaining: monitor.breakRemaining,
      breakIsStrict: monitor.breakIsStrict, remainingText: remainingText(), platform: process.platform,
      version: VERSION, errorMessage, screenAvailable: screenAvailable(), view, page,
      challenge, wallpaperURL, launchAtLogin,
      shortcutLabels: { close: 'Ctrl+W', minimize: 'Ctrl+M', preferences: 'Ctrl+,', showMain: 'Ctrl+0', rest: 'Ctrl+Shift+R', quit: 'Ctrl+Q' },
    };
  }
  function broadcast() {
    for (const [contents, entry] of owners) {
      if (!entry.window.isDestroyed() && !contents.isDestroyed()) contents.send('breather:state', state(entry.view));
    }
  }
  function destroyRestWindows() {
    for (const window of restWindows.splice(0)) if (!window.isDestroyed()) window.destroy();
  }
  function navigate(target) {
    page = target;
    showMain();
    mainWindow.webContents.send('breather:navigate', target);
    broadcast();
  }
  function showMain() {
    if (!mainWindow || mainWindow.isDestroyed()) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show(); mainWindow.focus();
  }
  function handleWindowIntent(window, view, intent, event) {
    if (quitting) return;
    const outcome = windowIntent(monitor, view, intent);
    if (outcome !== 'minimize') event?.preventDefault();
    if (outcome === 'hide') window.hide();
    else if (outcome === 'skip') {
      void command('skip').then(result => {
        if (window.isDestroyed()) return;
        if (result.ok && monitor.phase !== 'resting' && view === 'main') {
          if (intent === 'close') window.hide();
          else window.minimize();
        } else if (intent === 'minimize') { window.restore(); window.show(); }
      });
    } else if (outcome === 'deny') {
      if (intent === 'minimize') setImmediate(() => { if (!window.isDestroyed()) { window.restore(); window.show(); window.focus(); } });
      broadcast();
    }
  }
  function registerWindow(window, view) {
    const contents = window.webContents;
    owners.set(contents, { window, view });
    contents.setWindowOpenHandler(() => ({ action: 'deny' }));
    contents.on('will-navigate', event => event.preventDefault());
    contents.on('will-frame-navigate', event => event.preventDefault());
    contents.on('will-redirect', event => event.preventDefault());
    contents.on('will-attach-webview', event => event.preventDefault());
    contents.on('did-finish-load', () => contents.send('breather:state', state(view)));
    contents.on('before-input-event', (event, input) => handleShortcut(window, view, event, input));
    window.on('close', event => handleWindowIntent(window, view, 'close', event));
    window.on('minimize', event => handleWindowIntent(window, view, 'minimize', event));
    window.on('closed', () => owners.delete(contents));
    return window;
  }
  function handleShortcut(window, view, event, input) {
    if (input.type !== 'keyDown' || input.isAutoRepeat) return;
    const key = String(input.key || '').toLowerCase();
    const control = Boolean(input.control || (process.platform === 'darwin' && input.meta));
    if (input.alt && key === 'f4') { event.preventDefault(); handleWindowIntent(window, view, 'close'); return; }
    if (!control || input.alt) return;
    if (!input.shift && key === 'w') { event.preventDefault(); handleWindowIntent(window, view, 'close'); }
    else if (!input.shift && key === 'm') {
      event.preventDefault();
      if (windowIntent(monitor, view, 'minimize') === 'minimize') window.minimize();
      else handleWindowIntent(window, view, 'minimize');
    } else if (!input.shift && key === ',') { event.preventDefault(); navigate('settings'); }
    else if (!input.shift && key === '0') { event.preventDefault(); navigate('overview'); }
    else if (input.shift && key === 'r') { event.preventDefault(); void command('rest'); }
    else if (!input.shift && key === 'q') { event.preventDefault(); void command('quit'); }
  }
  function webPreferences() {
    return { preload: path.join(__dirname, 'preload.cjs'), sandbox: true, contextIsolation: true, nodeIntegration: false, nodeIntegrationInWorker: false, nodeIntegrationInSubFrames: false, webSecurity: true, allowRunningInsecureContent: false, webviewTag: false, spellcheck: false, backgroundThrottling: false };
  }
  function createMainWindow() {
    mainWindow = registerWindow(new BrowserWindow({
      width: 1120, height: 790, minWidth: 860, minHeight: 640,
      show: false, title: 'Breather · 歇会儿', backgroundColor: '#f6f3ec',
      icon: path.join(__dirname, 'renderer', 'assets', 'logo.png'),
      autoHideMenuBar: false, webPreferences: webPreferences(),
    }), 'main');
    mainWindow.setSkipTaskbar(!monitor.settings.showDockIcon);
    return mainWindow.loadFile(entryFile).then(() => showMain());
  }
  function syncRestWindows() {
    if (monitor.phase !== 'resting') {
      challenge = null;
      destroyRestWindows();
      return;
    }
    if (!screenAvailable()) {
      for (const window of restWindows) if (!window.isDestroyed()) window.hide();
      return;
    }
    const mini = monitor.settings.reminderStyle === 'mini';
    const displays = mini ? [screen.getPrimaryDisplay()] : screen.getAllDisplays();
    const expected = new Set(displays.map(display => display.id));
    for (let index = restWindows.length - 1; index >= 0; index--) {
      const window = restWindows[index];
      if (window.isDestroyed() || !expected.has(window.breatherDisplayID) || window.breatherMini !== mini) {
        restWindows.splice(index, 1);
        if (!window.isDestroyed()) window.destroy();
      }
    }
    for (const display of displays) {
      let window = restWindows.find(value => value.breatherDisplayID === display.id);
      if (!window) {
        const area = display.workArea;
        const bounds = mini ? { width: 430, height: 350, x: area.x + area.width - 450, y: area.y + area.height - 370 } : display.bounds;
        window = registerWindow(new BrowserWindow({ ...bounds, show: false, title: 'Breather · ' + text('休息', 'Rest'), frame: mini, resizable: false, minimizable: !isStrict(), closable: !isStrict(), fullscreenable: false, skipTaskbar: true, alwaysOnTop: true, backgroundColor: '#f6f3ec', webPreferences: webPreferences() }), 'rest');
        window.breatherDisplayID = display.id; window.breatherMini = mini;
        restWindows.push(window);
        const createdWindow = window;
        void window.loadFile(entryFile).then(() => { if (!createdWindow.isDestroyed() && screenAvailable() && monitor.phase === 'resting') { createdWindow.show(); createdWindow.focus(); } }).catch(reportError);
      }
      window.setMinimizable(!isStrict());
      window.setClosable(!isStrict());
      if (!window.isVisible()) window.show();
    }
  }
  function focusedIntent(intent) {
    const focused = BrowserWindow.getFocusedWindow() || mainWindow;
    const entry = owners.get(focused?.webContents);
    if (!entry) return;
    if (intent === 'minimize' && windowIntent(monitor, entry.view, intent) === 'minimize') focused.minimize();
    else handleWindowIntent(focused, entry.view, intent);
  }
  function rebuildMenus() {
    const key = monitor.settings.language + ':' + monitor.phase;
    if (key === lastMenuKey) return;
    lastMenuKey = key;
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      { label: text('文件', 'File'), submenu: [
        { id: 'preferences', label: text('偏好设置…', 'Preferences…'), accelerator: 'Ctrl+,', click: () => navigate('settings') },
        { id: 'start-rest', label: text('立即休息', 'Rest now'), accelerator: 'Ctrl+Shift+R', click: () => void command('rest') },
        { type: 'separator' },
        { id: 'close-window', label: text('关闭窗口', 'Close window'), accelerator: 'Ctrl+W', click: () => focusedIntent('close') },
        { id: 'quit', label: text('退出 Breather', 'Quit Breather'), accelerator: 'Ctrl+Q', click: () => void command('quit') },
      ] },
      { label: text('编辑', 'Edit'), submenu: [{ role: 'undo' }, { role: 'redo' }, { type: 'separator' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'delete' }, { role: 'selectAll' }] },
      { label: text('窗口', 'Window'), submenu: [
        { id: 'minimize-window', label: text('最小化', 'Minimize'), accelerator: 'Ctrl+M', click: () => focusedIntent('minimize') },
        { id: 'show-main', label: text('显示主窗口', 'Show main window'), accelerator: 'Ctrl+0', click: () => navigate('overview') },
      ] },
    ]));
    tray?.setContextMenu(Menu.buildFromTemplate([
      { label: text('显示 Breather', 'Show Breather'), click: () => showMain() },
      { label: text('立即休息', 'Rest now'), click: () => void command('rest') },
      { label: monitor.phase === 'paused' ? text('继续监测', 'Resume monitoring') : text('暂停监测', 'Pause monitoring'), click: () => void command('pause') },
      { type: 'separator' }, { label: text('退出', 'Exit'), click: () => void command('quit') },
    ]));
  }
  function refresh() {
    const completed = monitor.records.reduce((sum, record) => sum + record.breaksCompleted, 0);
    if (!smokeMode && monitor.settings.soundEnabled && ((monitor.phase === 'resting' && lastBreakPhase !== 'resting') || completed > lastCompletedBreaks)) electron.shell.beep();
    lastBreakPhase = monitor.phase; lastCompletedBreaks = completed;
    syncRestWindows(); rebuildMenus();
    tray?.setToolTip(monitor.settings.showMenuBarTime ? 'Breather · ' + remainingText() : 'Breather');
    broadcast();
  }
  function notify(title, body) {
    if (smokeMode || !Notification.isSupported()) return;
    const notification = new Notification({ title, body, silent: !monitor.settings.soundEnabled, icon: path.join(__dirname, 'renderer', 'assets', 'logo.png') });
    notification.on('click', () => showMain());
    notification.show();
  }
  function tick(nowMs = Date.now()) {
    let idle = 0;
    try { idle = powerMonitor.getSystemIdleTime(); idleAvailable = Number.isFinite(idle) && idle >= 0; } catch { idleAvailable = false; }
    monitor.tick(nowMs, idleAvailable ? idle : 0, screenAvailable());
    if (monitor.notificationCount > lastNotifications) {
      lastNotifications = monitor.notificationCount;
      notify('Breather', text('望向远处，暂时离开屏幕', 'Look into the distance and take a screen break.'));
    }
    const remaining = Math.max(0, monitor.settings.workSeconds * monitor.settings.fatigueThreshold / 100 - monitor.workElapsed);
    if (remaining > 60) advanceNotified = false;
    if (monitor.settings.advanceNoticeEnabled && monitor.phase === 'monitoring' && remaining > 0 && remaining <= 60 && !advanceNotified) {
      advanceNotified = true;
      notify(text('还有 1 分钟，准备休息', 'Your break starts in 1 minute'), text('给手头的事情收个尾，马上让眼睛放松一下。', 'Finish what you are doing and get ready to rest your eyes.'));
    }
    const today = monitor.records.find(record => record.day === core.dayKey(new Date(nowMs)));
    if (monitor.settings.dailyLimitEnabled && today && today.activeSeconds >= monitor.settings.dailyLimitHours * 3600 && dailyLimitNotified !== today.day) {
      dailyLimitNotified = today.day;
      notify(text('今日用眼已达到目标上限', "You have reached today's screen time limit"), text('记得减少连续用眼，安排规律休息。', 'Take regular breaks and reduce continuous screen time.'));
    }
    refresh();
    if (!preserveCorruptData && nowMs - lastPersist >= 15000) { try { persist(); } catch (error) { reportError(error); } }
  }
  function restoreDocument(document) {
    if (monitor.phase === 'resting') throw new Error(text('请先结束当前休息', 'Finish the current rest before restoring a backup'));
    const validated = validateState(document);
    // Backups never authorize access to the filesystem path they contain.
    validated.settings = validateSettings({ ...validated.settings, wallpaperPath: null });
    const replacement = new Monitor(validated);
    replacement.resetClock(Date.now());
    preserveSource('before-restore');
    writeAtomicJSON(dataFile, { settings: replacement.settings, records: replacement.records });
    monitor = replacement;
    lastBreakPhase = monitor.phase; lastCompletedBreaks = monitor.records.reduce((sum, record) => sum + record.breaksCompleted, 0);
    preserveCorruptData = false; wallpaperURL = null; challenge = null; lastNotifications = monitor.notificationCount;
    lastMenuKey = ''; mainWindow?.setSkipTaskbar(!monitor.settings.showDockIcon);
    refresh();
  }
  function gatedAction(action, answered = false) {
    if (isStrict()) throw new Error(text('严格休息期间无法执行此操作', 'This action is unavailable during a strict rest'));
    if (monitor.phase === 'resting' && monitor.settings.skipChallengeEnabled && !answered) {
      challenge = { left: crypto.randomInt(2, 20), right: crypto.randomInt(2, 20), action };
      broadcast(); return;
    }
    const now = Date.now();
    const accepted = action === 'skip' ? monitor.skipBreak(now) : action === 'snooze' ? monitor.snooze(now, 300) : monitor.setPaused(monitor.phase !== 'paused', now);
    if (!accepted) throw new Error(text('当前状态不允许此操作', 'This action is unavailable in the current state'));
    challenge = null;
  }
  async function executeCommand(name, supplied) {
    const payload = validateCommand(name, supplied);
    if (name === 'get-state') return state();
    switch (name) {
      case 'settings': {
        if (monitor.phase === 'resting' && ['strictMode', 'skipChallengeEnabled'].some(key => Object.hasOwn(payload, key) && payload[key] !== monitor.settings[key])) throw new Error(text('休息期间不能更改严格模式或答题保护', 'Strict mode and challenge protection cannot be changed during a rest'));
        const settings = validateSettings({ ...monitor.settings, ...payload });
        preserveUnreadableSource();
        writeAtomicJSON(dataFile, { settings, records: monitor.records });
        monitor.settings = settings; preserveCorruptData = false;
        mainWindow?.setSkipTaskbar(!settings.showDockIcon);
        break;
      }
      case 'pause': case 'skip': case 'snooze': gatedAction(name); break;
      case 'rest':
        if (monitor.phase !== 'resting') { monitor.startBreak(Date.now()); challenge = null; }
        break;
      case 'quit':
        persist(); quitting = true; app.quit(); return { ok: true };
      case 'dismiss-error': errorMessage = null; break;
      case 'cancel-challenge': challenge = null; break;
      case 'answer-challenge': {
        if (!challenge) throw new Error(text('没有待回答的问题', 'There is no active challenge'));
        if (Number(payload) !== challenge.left + challenge.right) throw new Error(text('答案不正确，请重试', 'Incorrect answer. Try again.'));
        gatedAction(challenge.action, true); errorMessage = null; break;
      }
      case 'launch-at-login':
        if (!smokeMode) {
          app.setLoginItemSettings({ openAtLogin: payload, path: process.execPath });
          launchAtLogin = Boolean(app.getLoginItemSettings().openAtLogin);
          if (launchAtLogin !== payload) throw new Error(text('系统未接受开机启动设置', 'The operating system did not accept the login setting'));
        } else launchAtLogin = payload;
        break;
      case 'export-csv': case 'export-backup': {
        const backup = name === 'export-backup';
        const result = await dialog.showSaveDialog(mainWindow, { title: text('导出', 'Export'), defaultPath: backup ? 'breather-backup.json' : 'breather-statistics.csv', filters: [{ name: backup ? 'JSON' : 'CSV', extensions: [backup ? 'json' : 'csv'] }] });
        if (result.canceled || !result.filePath) return { ok: true, cancelled: true };
        if (backup) writeAtomicJSON(result.filePath, { settings: { ...monitor.settings, wallpaperPath: null }, records: monitor.records });
        else fs.writeFileSync(result.filePath, '\ufeff' + csv(monitor.records), { encoding: 'utf8', mode: 0o600 });
        break;
      }
      case 'restore-backup': {
        if (monitor.phase === 'resting') throw new Error(text('请先结束当前休息', 'Finish the current rest before restoring a backup'));
        const result = await dialog.showOpenDialog(mainWindow, { title: text('恢复备份', 'Restore backup'), properties: ['openFile'], filters: [{ name: 'JSON', extensions: ['json'] }] });
        if (result.canceled || !result.filePaths[0]) return { ok: true, cancelled: true };
        const validated = validateState(readJSON(result.filePaths[0]));
        const confirmation = await dialog.showMessageBox(mainWindow, { type: 'warning', buttons: [text('取消', 'Cancel'), text('恢复', 'Restore')], defaultId: 0, cancelId: 0, title: text('恢复备份', 'Restore backup'), message: text('使用此备份替换当前设置和统计？', 'Replace current settings and statistics with this backup?') });
        if (confirmation.response !== 1) return { ok: true, cancelled: true };
        restoreDocument(validated); break;
      }
      case 'choose-wallpaper': {
        const result = await dialog.showOpenDialog(mainWindow, { title: text('选择休息背景', 'Choose a rest background'), properties: ['openFile'], filters: [{ name: 'Images', extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'] }] });
        if (result.canceled || !result.filePaths[0]) return { ok: true, cancelled: true };
        const selected = result.filePaths[0];
        const url = readWallpaper(selected);
        const bytes = Buffer.from(url.slice(url.indexOf(',') + 1), 'base64');
        preserveUnreadableSource();
        fs.mkdirSync(storageRoot, { recursive: true });
        fs.writeFileSync(wallpaperFile, bytes, { mode: 0o600 });
        const settings = validateSettings({ ...monitor.settings, wallpaperPath: wallpaperFile });
        writeAtomicJSON(dataFile, { settings, records: monitor.records });
        monitor.settings = settings; wallpaperURL = url; preserveCorruptData = false;
        break;
      }
      case 'clear-wallpaper': {
        const settings = validateSettings({ ...monitor.settings, wallpaperPath: null });
        preserveUnreadableSource();
        writeAtomicJSON(dataFile, { settings, records: monitor.records });
        monitor.settings = settings; wallpaperURL = null; preserveCorruptData = false;
        break;
      }
    }
    if (name !== 'dismiss-error' && name !== 'answer-challenge') errorMessage = null;
    if (!preserveCorruptData) persist();
    refresh();
    return { ok: true };
  }
  function command(name, payload) {
    const next = commandQueue.then(() => executeCommand(name, payload)).catch(error => {
      reportError(error); return { ok: false, error: error.message };
    });
    commandQueue = next.then(() => undefined);
    return next;
  }
  async function init() {
    // Every renderer shares this restricted session. File chooser paths are handled only in main.
    const session = electron.session?.defaultSession;
    session?.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
    session?.setPermissionCheckHandler(() => false);
    session?.on('will-download', event => event.preventDefault());
    session?.webRequest.onHeadersReceived((details, callback) => callback({ responseHeaders: { ...details.responseHeaders, 'Content-Security-Policy': [CSP] } }));
    ipcMain.handle('breather:get-state', event => {
      if (!isOwnedSender(event, owners, trustedURL)) throw new Error('Unauthenticated sender');
      return state(owners.get(event.sender).view);
    });
    ipcMain.handle('breather:command', (event, name, payload) => {
      if (!isOwnedSender(event, owners, trustedURL)) return { ok: false, error: 'Unauthenticated sender' };
      if (name === 'get-state' && (payload === undefined || payload === null)) return state(owners.get(event.sender).view);
      return command(name, payload);
    });
    await createMainWindow();
    let icon = nativeImage.createFromPath(path.join(__dirname, 'renderer', 'assets', 'logo.png'));
    if (icon.isEmpty()) throw new Error('Missing tray icon');
    icon = icon.resize({ width: process.platform === 'win32' ? 32 : 22, height: process.platform === 'win32' ? 32 : 22 });
    tray = new Tray(icon);
    tray.on('click', () => showMain());
    tray.on('double-click', () => showMain());
    for (const [event, change] of [['lock-screen', () => { locked = true; }], ['unlock-screen', () => { locked = false; }], ['suspend', () => { suspended = true; }], ['resume', () => { suspended = false; }]]) {
      const listener = () => { change(); monitor.resetClock(Date.now()); tick(); };
      powerMonitor.on(event, listener); powerListeners.push([event, listener]);
    }
    try { locked = powerMonitor.getSystemIdleState?.(1) === 'locked'; } catch { /* idle time sampling remains authoritative */ }
    screen.on('display-added', refresh); screen.on('display-removed', refresh); screen.on('display-metrics-changed', refresh);
    tick();
    timer = setInterval(() => { try { tick(); } catch (error) { reportError(error); } }, 1000);
    timer.unref();
  }
  function shutdown() {
    if (shutdownComplete) return;
    shutdownComplete = true;
    quitting = true;
    clearInterval(timer);
    for (const [event, listener] of powerListeners) powerMonitor.removeListener(event, listener);
    for (const event of ['display-added', 'display-removed', 'display-metrics-changed']) screen.removeListener(event, refresh);
    ipcMain.removeHandler('breather:get-state'); ipcMain.removeHandler('breather:command');
    try { persist(); } catch { /* shutdown must still release native resources */ }
    destroyRestWindows();
    if (mainWindow && !mainWindow.isDestroyed()) mainWindow.destroy();
    tray?.destroy(); owners.clear();
  }
  return { init, shutdown, command, state, tick, persist, restoreDocument, showMain, navigate, owners, dataFile, get mainWindow() { return mainWindow; }, get restWindows() { return restWindows; }, get tray() { return tray; } };
}

function prepareStorage(app, smokeMode) {
  const storageRoot = smokeMode ? fs.mkdtempSync(path.join(os.tmpdir(), 'breather-electron-smoke-')) : path.join(app.getPath('appData'), 'BreatherWindows');
  for (const directory of ['session', 'logs', 'crashDumps']) fs.mkdirSync(path.join(storageRoot, directory), { recursive: true });
  app.setPath('userData', storageRoot);
  app.setPath('sessionData', path.join(storageRoot, 'session'));
  app.setPath('crashDumps', path.join(storageRoot, 'crashDumps'));
  app.setAppLogsPath?.(path.join(storageRoot, 'logs'));
  return storageRoot;
}

function finishSmoke({ app, storageRoot, outputDirectory, exitCode, removeDirectory = fs.rmSync }) {
  // Only the exact direct child of the OS temp directory created for smoke is eligible.
  if (typeof storageRoot !== 'string' || !path.isAbsolute(storageRoot) || path.resolve(storageRoot) !== storageRoot || path.dirname(storageRoot) !== path.resolve(os.tmpdir()) || !/^breather-electron-smoke-[A-Za-z0-9]+$/.test(path.basename(storageRoot))) throw new Error('Refusing cleanup outside isolated smoke storage');
  const reportFile = path.join(outputDirectory, 'report.json');
  const report = readJSON(reportFile);
  let cleanupDeferred = false, cleanupError;
  try { removeDirectory(storageRoot, { recursive: true, force: true }); }
  catch (error) {
    // Chromium can retain session handles until app.exit on Windows. Do not retry.
    if (!['EPERM', 'EBUSY'].includes(error.code)) throw error;
    cleanupDeferred = true; cleanupError = error.code;
  }
  writeAtomicJSON(reportFile, { ...report, cleanupDeferred, ...(cleanupError ? { cleanupError } : {}) });
  app.exit(exitCode);
}

function prepareSmokeRendering(app, smokeMode) {
  if (smokeMode) app.disableHardwareAcceleration();
}

async function boot() {
  const electron = require('electron');
  const { app } = electron;
  const smokeIndex = process.argv.indexOf('--smoke-test');
  const smokeMode = smokeIndex !== -1;
  let outputDirectory;
  if (smokeMode) {
    outputDirectory = process.argv[smokeIndex + 1];
    if (!outputDirectory || !path.isAbsolute(outputDirectory)) throw new Error('--smoke-test requires an absolute output directory');
    fs.mkdirSync(outputDirectory, { recursive: true });
  }
  prepareSmokeRendering(app, smokeMode); // Must run before app.ready; production rendering is unchanged.
  // Deliberately distinct from the native Mac bundle's data directory.
  const storageRoot = prepareStorage(app, smokeMode);
  app.setAppUserModelId(APP_ID);
  app.setName('Breather');
  if (!smokeMode && !app.requestSingleInstanceLock()) { app.quit(); return; }
  await app.whenReady();
  const rendererDiagnostics = [];
  if (smokeMode) app.on('web-contents-created', (_event, contents) => {
    contents.on('console-message', details => {
      const item = { kind: 'console', level: details.level, message: details.message };
      rendererDiagnostics.push(item);
      console.log('[renderer] ' + JSON.stringify(item));
    });
    contents.on('preload-error', (_event, preloadPath, error) => {
      const item = { kind: 'preload-error', preloadPath, message: error.message };
      rendererDiagnostics.push(item); console.error('[preload] ' + JSON.stringify(item));
    });
  });
  const runtime = createRuntime({ electron, core: require('./core.cjs'), storageRoot, smokeMode });
  app.on('second-instance', () => runtime.showMain());
  app.on('activate', () => runtime.showMain());
  app.on('window-all-closed', () => { /* tray owns the monitoring lifetime */ });
  app.on('before-quit', () => runtime.shutdown());
  await runtime.init();
  if (smokeMode) {
    let exitCode = 0;
    try { await require('./scripts/electron-smoke.cjs').run({ runtime, electron, outputDirectory, storageRoot, createRuntime, core: require('./core.cjs'), rendererDiagnostics }); }
    catch (error) {
      exitCode = 1;
      const reportFile = path.join(outputDirectory, 'report.json');
      let partial = {};
      try { partial = readJSON(reportFile); } catch { /* no partial report was written */ }
      writeAtomicJSON(reportFile, { ...partial, passed: false, platform: process.platform, version: VERSION, error: error.stack, rendererDiagnostics });
      console.error(error);
    }
    runtime.shutdown();
    finishSmoke({ app, storageRoot, outputDirectory, exitCode });
  }
}
function shouldBoot(processInfo, isNodeMain) {
  return isNodeMain || Boolean(processInfo.versions.electron && processInfo.type === 'browser');
}
if (shouldBoot(process, require.main === module)) boot().catch(error => { console.error(error); process.exitCode = 1; require('electron').app.exit(1); });
module.exports = { createRuntime, prepareStorage, prepareSmokeRendering, finishSmoke, shouldBoot, boot, APP_ID, VERSION, CSP };
