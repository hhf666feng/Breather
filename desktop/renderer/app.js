'use strict';

(() => {
  const DEFAULT_MESSAGE = '望向远处，暂时离开屏幕';
  const DEFAULT_MESSAGE_EN = 'Look into the distance and step away from the screen';
  const words = {
    navigation:['主导航','Main navigation'], overview:['今日','Today'], stats:['用眼记录','Screen time'], settings:['偏好设置','Preferences'],
    tagline:['用眼之间，留一段空白','A pause between screen time'], localRecords:['记录保存在此电脑','Records saved on this computer'],
    overviewSub:['专注 / 休息','Focus / rest'], statsSub:['时间 / 节律','Time / rhythm'], settingsSub:['规则 / 提醒','Rules / reminders'],
    strain:['当前用眼负荷','Current eye strain'], strainInfo:['根据用眼与休息时长估算，并非医学测量。','Estimated from screen time and rest; not a medical measurement.'],
    estimate:['估算值','Estimate'], screenToday:['今日用眼时长','Screen time today'], activeOnly:['仅计算活跃使用','Active use only'], completion:['休息完成率','Break completion'],
    pause:['暂停监测','Pause'], resume:['继续监测','Resume'], snooze:['稍后 5 分钟','Snooze 5 min'], skip:['跳过本次','Skip break'], startBreak:['开始休息','Start break'],
    sessionProgress:['本次用眼进度','Current work interval progress'], restProgress:['本次休息进度','Current break progress'], hourly:['每小时用眼时长','Screen time by hour'], minutesPerHour:['分钟 / 小时','Minutes per hour'],
    range:['时间范围','Date range'], range7:['7 天','7 days'], range30:['30 天','30 days'], range90:['90 天','90 days'], range365:['12 个月','12 months'], rangeAll:['全部','All'],
    exportCSV:['导出 CSV','Export CSV'], totalScreen:['累计用眼','Total screen time'], breaksCompleted:['完成休息','Breaks completed'], notificationsExcluded:['系统通知不计入','System notifications excluded'],
    dailyScreen:['每日用眼时长','Daily screen time'], hours:['小时','Hours'], completedOffered:['完成倒计时 / 弹窗次数','Completed / offered breaks'], peak:['疲劳峰值时长','Time at peak strain'], peakDetail:['达到 100 后继续用眼 / 分钟','Minutes of use after reaching 100'],
    autoSave:['更改会自动保存','Changes are saved automatically'], dismiss:['关闭','Dismiss'], cancel:['取消','Cancel'], confirm:['确认','Confirm'],
    aMoment:['留一点时间给眼睛','A moment for your eyes'], restHint:['放下屏幕，眨眨眼，让视线走远一点。','Step away, blink, and let your eyes look into the distance.'],
    restCloseNote:['关闭普通休息窗口会按跳过处理；严格休息不能关闭或最小化。','Closing a normal break counts as skipping. Strict breaks cannot be closed or minimized.'], quitApp:['退出歇会儿','Quit Breather'],
    challengeTitle:['先停一下，想一想','Pause for a thought'], challengeHelp:['完成这道计算，再继续操作。','Complete this calculation to continue.'],
    workRest:['工作与休息','Work and rest'], workRestDetail:['安排用眼间隔','Set your break rhythm'], monitoringMode:['检测模式','Monitoring mode'], monitoringModeDetail:['智能模式在无操作时恢复；阅读模式在屏幕可用时持续计时','Smart mode recovers during inactivity; reading mode keeps counting while the screen is available'], smart:['智能检测','Smart detection'], continuous:['阅读 / 观影','Reading / video'],
    workSeconds:['连续用眼','Work interval'], workSecondsDetail:['达到设定时长后提醒休息','Remind you to rest after this much screen time'], restSeconds:['每次休息','Break duration'], restSecondsDetail:['建议至少远眺 20 秒','Look into the distance for at least 20 seconds'], fatigueThreshold:['提醒阈值','Reminder threshold'], fatigueThresholdDetail:['较低的数值会提前提醒','Lower values trigger an earlier reminder'], idleSeconds:['离开判断','Idle detection'], idleSecondsDetail:['无操作达到此时间后，智能模式停止累计用眼时长','In smart mode, stop counting after this period of inactivity'],
    detection:['Windows 活动检测','Windows activity detection'], detectionDetail:['系统空闲信号','System idle signal'], detectionNote:['Windows 使用系统空闲时间，并在锁屏或休眠时暂停检测。仅推断电脑是否在使用，不判断真人是否在场。不使用摄像头，不读取按键内容。此版本不提供 macOS 的辅助功能或屏幕录制增强检测。','Windows uses system idle time and pauses detection while locked or asleep. This estimates computer use, not whether a person is present. It does not use a camera or read keystroke content. This version does not provide the macOS Accessibility or Screen Recording enhancements.'],
    schedule:['监测时段','Monitoring schedule'], scheduleDetail:['按自己的作息','Follow your own rhythm'], scheduleEnabled:['启用时间表','Use a schedule'], scheduleEnabledDetail:['仅在选定日期和时段提醒；起止相同表示全天，支持跨午夜','Remind only on selected days and hours. Equal hours mean all day; overnight schedules are supported.'], scheduleStartHour:['开始时间','Start hour'], scheduleEndHour:['结束时间','End hour'], weekdays:['监测日期','Monitoring days'],
    reminders:['休息提醒','Break reminders'], remindersDetail:['留一段空白','Make room for a pause'], reminderStyle:['提醒方式','Reminder style'], fullscreen:['全屏休息','Full-screen break'], mini:['迷你浮窗','Mini window'], notification:['系统通知','System notification'], reminderStyleDetail:['系统通知不会开始或记为完成一次休息','System notifications do not start or complete a break'], strictMode:['严格休息','Strict breaks'], strictModeDetail:['休息期间不能跳过、延后、暂停、关闭或最小化；仍可明确退出应用','During a strict break, skip, snooze, pause, close, and minimize are blocked. Explicit quit remains available.'], skipChallengeEnabled:['跳过前计算','Arithmetic challenge'], skipChallengeEnabledDetail:['跳过、延后或暂停前，由主进程要求一道计算题','The main process requires a calculation before skipping, snoozing, or pausing'], soundEnabled:['提示音','Reminder sound'], advanceNoticeEnabled:['提前通知','Advance notice'], advanceNoticeEnabledDetail:['在休息前提前提醒','Show a notice before a break'], restMessage:['休息文字','Break message'], restMessageDetail:['自定义文字按原文保存。默认文字随界面语言显示，编辑框保留原文。','Custom messages are saved exactly as entered. The default message follows the display language; this editor preserves its original text.'], wallpaper:['休息背景','Break wallpaper'], wallpaperDetail:['通过系统对话框选择本地图片','Choose a local image with the system dialog'], chooseWallpaper:['选择图片','Choose image'], clearWallpaper:['移除图片','Remove image'], noWallpaper:['使用纸灰背景','Paper background'], hasWallpaper:['已选择本地图片','Local image selected'],
    dailyLimit:['每日用眼目标','Daily screen time target'], dailyLimitEnabled:['启用每日目标','Use a daily target'], dailyLimitEnabledDetail:['达到目标时提醒，不会锁住电脑','Show a reminder at the target; does not lock the computer'], dailyLimitHours:['每日时长','Daily time'], general:['通用','General'], generalDetail:['此电脑上的偏好','Preferences on this computer'], language:['界面语言','Language'], launchAtLogin:['登录时启动','Launch at login'], launchAtLoginDetail:['登录 Windows 后启动歇会儿','Start Breather when you sign in to Windows'], showDockIcon:['在任务栏中显示','Show in taskbar'], showDockIconDetail:['隐藏任务栏图标后仍可从系统托盘打开','Open the app from the system tray when the taskbar icon is hidden'], showMenuBarTime:['托盘提示显示计时','Show timer in tray tooltip'],
    data:['记录与备份','Records and backups'], dataDetail:['本地保存','Saved locally'], exportBackup:['导出备份','Export backup'], restoreBackup:['恢复备份','Restore backup'], backupDetail:['备份包括设置与记录。恢复文件由主进程验证后载入。','Backups include settings and records. The main process validates a backup before restoring it.'],
    shortcuts:['Windows 快捷键','Windows shortcuts'], shortcutsDetail:['仅应用内生效','Active within the app'], closeTray:['关闭窗口至托盘','Close window to tray'], minimize:['最小化当前窗口','Minimize current window'], openSettings:['打开偏好设置','Open Preferences'], restoreWindow:['显示主窗口','Show main window'], nativeEdit:['剪切 / 复制 / 粘贴 / 全选','Cut / copy / paste / select all'], nativeUndo:['撤销 / 重做','Undo / redo'], shortcutAction:['操作','Action'], shortcutKey:['快捷键','Shortcut'], trayNote:['关闭主窗口后，歇会儿会继续在 Windows 系统托盘运行。点击托盘图标可重新打开；退出应用请使用“退出歇会儿”或 Ctrl+Q。快捷键由原生菜单处理，只在应用内生效。','Closing the main window keeps Breather running in the Windows system tray. Click its tray icon to reopen. Use Quit Breather or Ctrl+Q to exit. Native menus handle shortcuts within the app.'],
    minUnit:['分钟','min'], secUnit:['秒','sec'], hourUnit:['小时','hours'], hourOfDay:['时','hour'],
    noRecords:['还没有用眼记录','No screen time recorded yet'], noRecordsDetail:['监测开始后，每日使用时间会自动记在这里','Daily activity is recorded automatically when monitoring starts'], noBreaks:['尚未收到休息提醒','No breaks offered yet'], noPeak:['没有达到疲劳峰值的记录','No time at peak strain recorded'], noHours:['今天还没有用眼记录','No screen time recorded today'],
    nextBreak:['距离下次休息','Next break in'], breakRemaining:['休息剩余','Break time remaining'], pausedTimer:['监测已暂停','Monitoring paused'], outsideTimer:['休息提醒在时段外','Outside reminder hours'], snoozedTimer:['提醒已延后','Reminder snoozed'],
    monitoring:['正在监测','Monitoring'], idle:['空闲恢复中','Recovering while idle'], resting:['正在休息','Taking a break'], paused:['已暂停','Paused'], snoozed:['稍后提醒','Snoozed'], outsideSchedule:['非监测时段','Outside schedule'],
    activeNote:['用眼负荷随活跃使用逐渐累积','Eye strain gradually rises with active use'], idleNote:['未检测到近期操作，用眼负荷正在恢复','No recent activity detected. Eye strain is recovering'], unavailableNote:['屏幕不可用，检测暂时停止','Screen unavailable. Detection is temporarily stopped'], continuousNote:['阅读 / 观影模式：屏幕可用时持续计时','Reading / video mode: counting while the screen is available'], pausedNote:['监测暂停期间不累计用眼时长','Screen time is not counted while monitoring is paused'], restingNote:['正在休息，让眼睛慢慢恢复','Taking a break. Give your eyes time to recover'], outsideNote:['继续记录用眼；休息提醒在下一个选定时段恢复','Screen time is still recorded; break reminders resume in the next scheduled period'], snoozedNote:['延后期间继续记录活跃用眼','Active screen time continues to be recorded while snoozed'],
    source:['活动来源：Windows 系统空闲时间','Activity source: Windows system idle time'], strictBreak:['严格休息','Strict break'], normalBreak:['休息时间','Break time'], strictNote:['完成倒计时后自动结束。仍可通过底部按钮或 Ctrl+Q 退出应用。','Ends automatically after the countdown. You can still quit below or with Ctrl+Q.'], normalNote:['倒计时完成后会自动继续监测','Monitoring resumes automatically when the countdown finishes'],
    saved:['已保存','Saved'], done:['操作完成','Done'], failed:['操作未完成，请重试','The action could not be completed. Please try again.'], bridgeMissing:['无法连接桌面主进程，请重新打开应用。','Unable to connect to the desktop process. Reopen the app.'], invalidNumber:['请输入有效数字','Enter a valid number'], challengeWait:['请完成计算题后继续','Complete the calculation to continue'], unknownPhase:['正在同步状态','Synchronizing state']
  };
  let state = null;
  let language = 'zh-Hans';
  let localPage = 'overview';
  let lastNativePage;
  let range = 7;
  let lastCharts = '';
  let challengeKey = '';
  let previousFocus = null;
  const fieldPending = new Set();
  const $ = (selector) => document.querySelector(selector);
  const $$ = (selector) => [...document.querySelectorAll(selector)];
  const t = (key) => (words[key] || [key, key])[language === 'en' ? 1 : 0];
  const choose = (zh, en) => language === 'en' ? en : zh;
  const escapeHTML = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const finite = (value) => Number.isFinite(Number(value)) ? Math.max(0, Number(value)) : 0;
  const number = (value) => Math.round(finite(value));
  const dayKey = (date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  const duration = (seconds) => {
    const minutes = Math.floor(finite(seconds) / 60);
    return minutes < 60 ? `${minutes} ${t('minUnit')}` : choose(`${Math.floor(minutes / 60)}时 ${String(minutes % 60).padStart(2,'0')}分`, `${Math.floor(minutes / 60)}h ${String(minutes % 60).padStart(2,'0')}m`);
  };
  const clock = (seconds) => {
    const whole = Math.ceil(finite(seconds));
    return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
  };
  function bind(name, value) {
    $$(`[data-bind="${name}"]`).forEach((node) => { if (node.textContent !== String(value)) node.textContent = String(value); });
  }
  function localize() {
    document.documentElement.lang = language;
    document.title = choose('歇会儿 · Breather','Breather · 歇会儿');
    $$('[data-i18n]').forEach((node) => { node.textContent = t(node.dataset.i18n); });
    $$('[data-aria-i18n]').forEach((node) => node.setAttribute('aria-label',t(node.dataset.ariaI18n)));
    $$('[data-title-i18n]').forEach((node) => node.title = t(node.dataset.titleI18n));
    bind('brand', choose('歇会儿','Breather'));
    bind('brand-sub', choose('Breather','歇会儿'));
    updatePage();
  }
  function fieldRow(key, detail, control, wide = false) {
    return `<div class="setting-row"><div class="setting-copy"><label for="setting-${key}" data-i18n="${key}"></label>${detail ? `<p id="help-${key}" data-i18n="${detail}"></p>` : ''}</div><div class="setting-control${wide ? ' wide' : ''}">${control}</div></div>`;
  }
  function numberField(key, min, max, step, unit, scale = 1, detail = `${key}Detail`) {
    return fieldRow(key, detail, `<input id="setting-${key}" data-setting="${key}" type="number" min="${min}" max="${max}" step="${step}" data-scale="${scale}"${detail ? ` aria-describedby="help-${key}"` : ''}><span class="unit" data-i18n="${unit}"></span>`);
  }
  function toggle(key, detail = '') {
    return fieldRow(key,detail,`<input id="setting-${key}" data-setting="${key}" type="checkbox"${detail ? ` aria-describedby="help-${key}"` : ''}>`);
  }
  function select(key, values, detail = '') {
    return fieldRow(key,detail,`<select id="setting-${key}" data-setting="${key}"${detail ? ` aria-describedby="help-${key}"` : ''}>${values.map(([value,label]) => `<option value="${value}" data-i18n="${label}"></option>`).join('')}</select>`);
  }
  function section(title, detail, body) {
    return `<section class="settings-section"><div class="section-heading"><h2 data-i18n="${title}"></h2><span data-i18n="${detail}"></span></div><div class="settings-card">${body}</div></section>`;
  }
  function buildSettings() {
    const weekdays = [2,3,4,5,6,7,1].map((day) => `<label class="weekday"><input type="checkbox" data-weekday="${day}"><span data-weekday-label="${day}"></span></label>`).join('');
    const scheduleHours = (key) => fieldRow(key,'',`<select id="setting-${key}" data-setting="${key}" data-numeric="true">${Array.from({length:24},(_,hour) => `<option value="${hour}">${String(hour).padStart(2,'0')}:00</option>`).join('')}</select>`);
    const shortcuts = [['closeTray','Ctrl+W / Alt+F4'],['minimize','Ctrl+M'],['openSettings','Ctrl+,'],['restoreWindow','Ctrl+0'],['startBreak','Ctrl+Shift+R'],['quitApp','Ctrl+Q'],['nativeEdit','Ctrl+X / C / V / A'],['nativeUndo','Ctrl+Z / Ctrl+Y']];
    $('#settings-sections').innerHTML = [
      section('workRest','workRestDetail', select('monitoringMode',[['smart','smart'],['continuous','continuous']],'monitoringModeDetail') + numberField('workSeconds',1/6,240,'any','minUnit',60) + numberField('restSeconds',5,3600,1,'secUnit') + numberField('fatigueThreshold',10,100,1,'',1) + numberField('idleSeconds',5,600,1,'secUnit')),
      section('detection','detectionDetail','<p class="settings-note" data-i18n="detectionNote"></p>'),
      section('schedule','scheduleDetail',toggle('scheduleEnabled','scheduleEnabledDetail') + scheduleHours('scheduleStartHour') + scheduleHours('scheduleEndHour') + `<div class="setting-row"><div class="setting-copy"><span id="weekdays-label" class="setting-label" data-i18n="weekdays"></span></div><div class="setting-control weekdays" role="group" aria-labelledby="weekdays-label">${weekdays}</div></div>`),
      section('reminders','remindersDetail',select('reminderStyle',[['fullscreen','fullscreen'],['mini','mini'],['notification','notification']],'reminderStyleDetail') + toggle('strictMode','strictModeDetail') + toggle('skipChallengeEnabled','skipChallengeEnabledDetail') + toggle('soundEnabled') + toggle('advanceNoticeEnabled','advanceNoticeEnabledDetail') + fieldRow('restMessage','restMessageDetail','<textarea id="setting-restMessage" data-setting="restMessage" maxlength="2000" aria-describedby="help-restMessage"></textarea>',true) + `<div class="setting-row"><div class="setting-copy"><span class="setting-label" data-i18n="wallpaper"></span><p data-i18n="wallpaperDetail"></p><p data-bind="wallpaper-status"></p></div><div class="setting-control wide"><img id="wallpaper-preview" class="wallpaper-preview" alt="" hidden><div class="actions"><button type="button" data-command="choose-wallpaper" data-i18n="chooseWallpaper"></button><button type="button" data-command="clear-wallpaper" data-i18n="clearWallpaper"></button></div></div></div>`),
      section('dailyLimit','scheduleDetail',toggle('dailyLimitEnabled','dailyLimitEnabledDetail') + numberField('dailyLimitHours',.5,24,.5,'hourUnit',1,'')),
      section('general','generalDetail',fieldRow('language','', '<select id="setting-language" data-setting="language"><option value="zh-Hans">简体中文</option><option value="en">English</option></select>') + fieldRow('launchAtLogin','launchAtLoginDetail','<input id="setting-launchAtLogin" type="checkbox" data-login aria-describedby="help-launchAtLogin">') + toggle('showDockIcon','showDockIconDetail') + toggle('showMenuBarTime')),
      section('data','dataDetail',`<p class="settings-note" data-i18n="backupDetail"></p><div class="setting-row"><div class="actions"><button type="button" data-command="export-csv" data-i18n="exportCSV"></button><button type="button" data-command="export-backup" data-i18n="exportBackup"></button><button type="button" data-command="restore-backup" data-i18n="restoreBackup"></button></div></div>`),
      section('shortcuts','shortcutsDetail',`<p class="settings-note" data-i18n="trayNote"></p><table class="shortcut-table"><thead><tr><th scope="col" data-i18n="shortcutAction"></th><th scope="col" data-i18n="shortcutKey"></th></tr></thead><tbody>${shortcuts.map(([label,keys]) => `<tr><td data-i18n="${label}"></td><td><kbd>${keys}</kbd></td></tr>`).join('')}</tbody></table><div class="setting-row"><button type="button" data-command="quit" data-i18n="quitApp"></button></div>`)
    ].join('');
    // An empty unit has no label and should not expose an untranslated dictionary key.
    $$('[data-i18n=""]').forEach((node) => node.remove());
  }
  function updatePage() {
    for (const page of ['overview','stats','settings']) {
      $(`#page-${page}`).hidden = page !== localPage;
      const button = $(`[data-page="${page}"]`);
      if (page === localPage) button.setAttribute('aria-current','page');
      else button.removeAttribute('aria-current');
    }
    bind('page-title',t(localPage));
    bind('page-subtitle',t(`${localPage}Sub`));
  }
  function navigate(page, native = false) {
    if (!['overview','stats','settings'].includes(page) || state?.view === 'rest') return;
    if (localPage !== page) {
      localPage = page;
      updatePage();
      if (native) $('#content').focus({preventScroll:true});
      window.scrollTo(0,0);
    }
  }
  function setControl(node, value) {
    if (node === document.activeElement || fieldPending.has(node)) return;
    if (node.type === 'checkbox') node.checked = Boolean(value);
    else {
      const display = node.dataset.scale ? Number(value) / Number(node.dataset.scale) : value;
      if (node.value !== String(display ?? '')) node.value = String(display ?? '');
    }
  }
  function updateSettings() {
    const settings = state.settings || {};
    $$('[data-setting]').forEach((node) => setControl(node,settings[node.dataset.setting]));
    $$('[data-setting="strictMode"], [data-setting="skipChallengeEnabled"]').forEach((node) => { node.disabled = state.phase === 'resting'; });
    setControl($('[data-login]'),state.launchAtLogin);
    const weekdays = Array.isArray(settings.weekdays) ? settings.weekdays : [];
    $$('[data-weekday]').forEach((node) => setControl(node,weekdays.includes(Number(node.dataset.weekday))));
    const dayNames = language === 'en' ? ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'] : ['日','一','二','三','四','五','六'];
    $$('[data-weekday-label]').forEach((node) => { node.textContent = dayNames[Number(node.dataset.weekdayLabel)-1]; });
    const url = safeWallpaper(state.wallpaperURL);
    for (const node of [$('#wallpaper'),$('#wallpaper-preview')]) {
      node.hidden = !url;
      if (url && node.getAttribute('src') !== url) node.src = url;
      if (!url) node.removeAttribute('src');
    }
    bind('wallpaper-status',t(url || settings.wallpaperPath ? 'hasWallpaper' : 'noWallpaper'));
    $$('[data-command="clear-wallpaper"]').forEach((node) => { node.disabled = !(url || settings.wallpaperPath); });
  }
  function safeWallpaper(value) {
    // Main supplies a data URI; the renderer never opens a filesystem path.
    return typeof value === 'string' && /^data:image\/(png|jpe?g|webp|gif|bmp);base64,[a-z0-9+/=\s]+$/i.test(value) ? value : '';
  }
  function renderState(next) {
    if (!next || typeof next !== 'object' || !next.settings) return;
    const oldLanguage = language;
    state = next;
    language = next.settings.language === 'en' ? 'en' : 'zh-Hans';
    if (next.page !== lastNativePage) {
      lastNativePage = next.page;
      if (next.view !== 'rest' && ['overview','stats','settings'].includes(next.page)) localPage = next.page;
    }
    if (oldLanguage !== language) {
      localize();
      $('#action-status').textContent='';
      $('#challenge-error').textContent='';
    }
    const isRest = next.view === 'rest';
    $('#loading').hidden = true;
    $('#main-view').hidden = isRest;
    $('#rest-view').hidden = !isRest;
    updatePage();
    bind('version',`Windows · ${next.version || '—'}`);
    bind('date',new Intl.DateTimeFormat(language === 'en' ? 'en-US':'zh-CN',{dateStyle:'full'}).format(new Date()));
    bind('phase',t(words[next.phase] ? next.phase : 'unknownPhase'));
    const error = typeof next.errorMessage === 'string' ? next.errorMessage : '';
    $('#error-banner').hidden = !error;
    bind('error',error);
    $('#rest-error').textContent = error;
    const settings = next.settings;
    const today = (Array.isArray(next.records) ? next.records : []).find((r) => r.day === dayKey(new Date()));
    const offered = number(today?.breaksOffered);
    const completed = number(today?.breaksCompleted);
    bind('fatigue',number(next.fatigue));
    $('#strain-gauge').setAttribute('aria-label',`${t('strain')}: ${number(next.fatigue)} / 100`);
    const gaugeX = Math.min(100,finite(next.fatigue)) * 8;
    $('#gauge-marker').setAttribute('x1',gaugeX);
    $('#gauge-marker').setAttribute('x2',gaugeX);
    bind('threshold-note',choose(`达到 ${number(settings.fatigueThreshold)} 时提醒`,`Remind at ${number(settings.fatigueThreshold)}`));
    bind('today-time',duration(today?.activeSeconds));
    bind('today-rate',offered ? `${Math.floor(completed / offered * 100)}%` : '—');
    bind('today-breaks',choose(`${completed} 次完成 / ${offered} 次提醒`,`${completed} completed / ${offered} offered`));
    const note = next.screenAvailable === false ? 'unavailableNote' : ({idle:'idleNote',paused:'pausedNote',resting:'restingNote',outsideSchedule:'outsideNote',snoozed:'snoozedNote'}[next.phase] || (settings.monitoringMode === 'continuous' ? 'continuousNote' : 'activeNote'));
    bind('activity-note',t(note));
    bind('activity-source',t('source'));
    const resting = next.phase === 'resting';
    const strict = resting && next.breakIsStrict === true;
    bind('timer-title',t(({resting:'breakRemaining',paused:'pausedTimer',outsideSchedule:'outsideTimer',snoozed:'snoozedTimer'})[next.phase] || 'nextBreak'));
    bind('timer',next.phase === 'paused' || next.phase === 'outsideSchedule' ? '—' : (resting ? clock(next.breakRemaining) : (typeof next.remainingText === 'string' && next.remainingText ? next.remainingText : clock(Math.max(0,finite(settings.workSeconds) - finite(next.workElapsed))))));
    bind('pause-label',t(next.phase === 'paused' ? 'resume':'pause'));
    bind('session',choose(`本次用眼：${duration(next.workElapsed)}`,`This session: ${duration(next.workElapsed)}`));
    bind('rhythm',choose(`用眼 ${duration(settings.workSeconds)} / 休息 ${number(settings.restSeconds)} 秒`,`Work ${duration(settings.workSeconds)} / rest ${number(settings.restSeconds)} sec`));
    $('#session-progress').value = Math.min(1,finite(next.workElapsed)/Math.max(1,finite(settings.workSeconds)));
    $$('[data-command="skip"]').forEach((node) => { node.hidden = !resting || strict; });
    $$('[data-command="snooze"], [data-command="pause"]').forEach((node) => { node.hidden = strict; });
    $$('[data-command="rest"]').forEach((node) => { node.disabled = resting; });
    bind('rest-mode',t(strict ? 'strictBreak':'normalBreak'));
    const rawMessage = typeof settings.restMessage === 'string' ? settings.restMessage : '';
    bind('rest-message',rawMessage === DEFAULT_MESSAGE && language === 'en' ? DEFAULT_MESSAGE_EN : rawMessage);
    bind('rest-timer',clock(next.breakRemaining));
    bind('strict-note',t(strict ? 'strictNote':'normalNote'));
    $('#rest-progress').value = Math.min(1,Math.max(0,1-finite(next.breakRemaining)/Math.max(1,finite(settings.restSeconds))));
    updateSettings();
    renderCharts();
    renderChallenge();
  }
  function selectedRecords() {
    const records = Array.isArray(state?.records) ? state.records : [];
    const start = new Date();
    start.setDate(start.getDate() - (range - 1));
    const startKey = dayKey(start), todayKey = dayKey(new Date());
    return records.filter((r) => r && typeof r.day === 'string' && (!range || (r.day >= startKey && r.day <= todayKey))).sort((a,b) => a.day.localeCompare(b.day));
  }
  function renderCharts() {
    const records = Array.isArray(state.records) ? state.records : [];
    const signature = JSON.stringify([records,range,language,dayKey(new Date())]);
    if (signature === lastCharts) return;
    lastCharts = signature;
    const today = records.find((r) => r.day === dayKey(new Date()));
    const hours = Array.from({length:24},(_,hour) => ({label:`${String(hour).padStart(2,'0')}:00`,short:hour % 4 === 0 ? `${hour}` : '',value:finite(today?.hourlySeconds?.[hour])/60,today:hour === new Date().getHours()}));
    chart('hours-chart',hours,{title:t('hourly'),empty:t('noHours'),unit:t('minutesPerHour'),floor:60});
    const selected = selectedRecords();
    const sum = (key) => selected.reduce((total,r) => total + finite(r[key]),0);
    const offered = sum('breaksOffered'), completed = sum('breaksCompleted');
    bind('stats-time',duration(sum('activeSeconds')));
    bind('stats-completed',number(completed));
    bind('stats-offered',choose(`共提醒 ${number(offered)} 次`,`${number(offered)} breaks offered`));
    bind('stats-rate',offered ? `${Math.floor(completed/offered*100)}%` : '—');
    bind('stats-range',range ? choose(`最近 ${range} 天`,`Last ${range} days`) : t('rangeAll'));
    const rows = (key,divisor=1) => selected.map((r,i) => ({label:r.day,short:i===0 || i===selected.length-1 || i % Math.max(1,Math.ceil(selected.length/6)) === 0 ? r.day.slice(5).replace('-','/') : '',value:finite(r[key])/divisor,today:r.day===dayKey(new Date())}));
    chart('daily-chart',rows('activeSeconds',3600),{title:t('dailyScreen'),empty:t('noRecords'),detail:t('noRecordsDetail'),unit:t('hours')});
    const dailyRows = rows('activeSeconds');
    const rates = selected.map((r,i) => ({...dailyRows[i],value:finite(r.breaksOffered) ? finite(r.breaksCompleted)/finite(r.breaksOffered)*100 : null}));
    chart('completion-chart',rates,{title:t('completion'),empty:t('noBreaks'),unit:'%',floor:100,line:true,hasData:offered>0,compact:true});
    chart('peak-chart',rows('peakFatigueSeconds',60),{title:t('peak'),empty:t('noPeak'),unit:t('minUnit'),peak:true,compact:true});
  }
  function chart(id,rows,options) {
    const host = $(`#${id}`);
    const hasData = options.hasData ?? rows.some((row) => row.value > 0);
    if (!hasData) {
      host.innerHTML = `<div class="empty-chart"><p>${escapeHTML(options.empty)}</p>${options.detail ? `<small>${escapeHTML(options.detail)}</small>`:''}</div>`;
      return;
    }
    const width=900, height=options.compact ? 160:230, left=44, right=18, top=16, bottom=30;
    const plotWidth=width-left-right, plotHeight=height-top-bottom;
    const max=Math.max(options.floor || 1,...rows.map((r) => finite(r.value)));
    const step=plotWidth/Math.max(1,rows.length);
    const y=(value) => top+plotHeight*(1-finite(value)/max);
    let svg=`<svg viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="${id}-title ${id}-desc"><title id="${id}-title">${escapeHTML(options.title)}</title><desc id="${id}-desc">${escapeHTML(rows.map((r) => `${r.label}: ${r.value===null ? '—' : Math.round(r.value*10)/10} ${options.unit}`).join('; '))}</desc>`;
    [0,.5,1].forEach((fraction) => {
      const value=max*fraction, lineY=y(value);
      svg+=`<line x1="${left}" x2="${width-right}" y1="${lineY}" y2="${lineY}" class="gridline"/><text x="${left-9}" y="${lineY+4}" text-anchor="end">${Math.round(value*10)/10}</text>`;
    });
    let path='';
    rows.forEach((row,i) => {
      const x=left+(i+.5)*step;
      if (options.line) {
        if (row.value===null) { path+='|'; }
        else { path+=`${path && !path.endsWith('|') ? ' L':' M'} ${x.toFixed(2)} ${y(row.value).toFixed(2)}`; svg+=`<circle cx="${x}" cy="${y(row.value)}" r="2.6" class="point"><title>${escapeHTML(row.label)}: ${Math.round(row.value)}%</title></circle>`; }
      } else {
        const barWidth=Math.max(.7,Math.min(34,step*.62));
        svg+=`<rect x="${x-barWidth/2}" y="${y(row.value)}" width="${barWidth}" height="${Math.max(0,top+plotHeight-y(row.value))}" class="${options.peak ? 'peak-bar' : row.today ? 'today-bar':'bar'}"><title>${escapeHTML(row.label)}: ${Math.round(row.value*10)/10} ${escapeHTML(options.unit)}</title></rect>`;
      }
      if (row.short) svg+=`<text x="${x}" y="${height-7}" text-anchor="middle">${escapeHTML(row.short)}</text>`;
    });
    if (options.line) svg+=`<path d="${path.replaceAll('|','')}" class="line"/>`;
    host.innerHTML=svg+'</svg>';
  }
  function renderChallenge() {
    const dialog=$('#challenge-dialog');
    const challenge=state?.challenge;
    if (!challenge || !Number.isFinite(challenge.left) || !Number.isFinite(challenge.right)) {
      challengeKey='';
      if (dialog.open) { dialog.close(); if (previousFocus?.isConnected && !previousFocus.closest('[hidden]')) previousFocus.focus({preventScroll:true}); }
      return;
    }
    const key=JSON.stringify(challenge);
    $('#challenge-question').textContent=`${challenge.left} + ${challenge.right} = ?`;
    if (key !== challengeKey) {
      challengeKey=key;
      $('#challenge-answer').value='';
      $('#challenge-error').textContent='';
    }
    if (!dialog.open) { previousFocus=document.activeElement; dialog.showModal(); $('#challenge-answer').focus(); }
  }
  function showStatus(message,error=false) {
    $('#action-status').textContent=message;
    if (state?.view === 'rest') $('#rest-error').textContent=message;
    if ($('#challenge-dialog').open && error) $('#challenge-error').textContent=message;
  }
  async function command(name,payload) {
    if (!window.breather?.command) { showStatus(t('bridgeMissing'),true); return {ok:false}; }
    try {
      const result=await window.breather.command(name,payload);
      if (!result?.ok && !result?.cancelled) showStatus(result?.error || t('failed'),true);
      else if (result?.ok && !result.cancelled) {
        if (state?.challenge && ['skip','snooze','pause'].includes(name)) showStatus(t('challengeWait'));
        else showStatus(t(name==='settings' || name==='launch-at-login' ? 'saved':'done'));
      }
      return result || {ok:false};
    } catch { showStatus(t('failed'),true); return {ok:false}; }
  }
  async function saveControl(node) {
    let key=node.dataset.setting;
    let value;
    if (node.matches('[data-weekday]')) {
      key='weekdays';
      value=$$('[data-weekday]:checked').map((field) => Number(field.dataset.weekday));
    } else if (node.type === 'checkbox') value=node.checked;
    else if (node.type === 'number' || node.dataset.numeric) {
      if (!node.checkValidity() || node.value==='') { node.reportValidity(); showStatus(t('invalidNumber'),true); return; }
      value=Number(node.value)*Number(node.dataset.scale || 1);
    } else value=node.value; // Preserve the raw restMessage, including whitespace and default text.
    fieldPending.add(node);
    const result=await command(node.matches('[data-login]') ? 'launch-at-login':'settings',node.matches('[data-login]') ? value : {[key]:value});
    fieldPending.delete(node);
    if (!result.ok && state) updateSettings();
  }
  buildSettings();
  $('#gauge-ticks').innerHTML=Array.from({length:41},(_,i) => `<line x1="${i*20}" x2="${i*20}" y1="${i%10===0 ? 2:12}" y2="34" class="gauge-tick"/>`).join('');
  localize();
  document.addEventListener('click',(event) => {
    const node=event.target.closest('button');
    if (!node || node.disabled) return;
    if (node.dataset.page) navigate(node.dataset.page);
    if (node.dataset.range!==undefined) {
      range=Number(node.dataset.range);
      $$('[data-range]').forEach((button) => button.setAttribute('aria-pressed',String(Number(button.dataset.range)===range)));
      if (state) renderCharts();
    }
    if (node.dataset.command) void command(node.dataset.command);
  });
  document.addEventListener('change',(event) => {
    const node=event.target;
    if (node.matches('[data-setting], [data-login], [data-weekday]')) void saveControl(node);
  });
  document.addEventListener('focusout',(event) => {
    const node=event.target;
    if (state && node.matches('[data-setting], [data-login], [data-weekday]')) {
      // Wait until the browser has emitted change; state remains authoritative after validation.
      queueMicrotask(() => { if (!fieldPending.has(node)) updateSettings(); });
    }
  });
  $('#challenge-form').addEventListener('submit',async (event) => {
    event.preventDefault();
    const node=$('#challenge-answer');
    if (!node.value.trim()) { node.reportValidity(); return; }
    const submit=$('#challenge-form button[type="submit"]');
    submit.disabled=true;
    const result=await command('answer-challenge',node.value);
    submit.disabled=false;
    if (!result.ok) node.focus();
  });
  $('#challenge-dialog').addEventListener('cancel',(event) => { event.preventDefault(); void command('cancel-challenge'); });
  // Native menus own app and editing shortcuts. No renderer key interception or global hooks.
  if (window.breather?.subscribe && window.breather?.getState) {
    let received=false;
    const unsubscribe=window.breather.subscribe((next) => { received=true; renderState(next); });
    const offNavigate=window.breather.onNavigate?.((value) => navigate(typeof value==='string' ? value : value?.page,true));
    window.breather.getState().then((initial) => { if (!received) renderState(initial); }).catch(() => { $('#loading').textContent=t('bridgeMissing'); });
    window.addEventListener('unload',() => { unsubscribe?.(); offNavigate?.(); },{once:true});
  } else $('#loading').textContent=t('bridgeMissing');
})();
