'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const core = require('../core.cjs');
const { Monitor, defaultSettings, validateSettings, validateState, csv, dayKey } = core;
const start = new Date(2025, 0, 1, 12).getTime();
const settings = (overrides = {}) => ({ workSeconds: 60, restSeconds: 20, idleSeconds: 10, ...overrides });
const make = (overrides = {}) => new Monitor({ settings: settings(overrides) });
function advance(m, from, seconds, idle = 0, available = true) {
  for (let n = 1; n <= seconds; n++) m.tick(from + n * 1000, idle, available);
}
const record = (overrides = {}) => ({ day: '2025-01-01', activeSeconds: 0, peakFatigueSeconds: 0, breaksOffered: 0, breaksCompleted: 0, breaksSkipped: 0, hourlySeconds: Array(24).fill(0), ...overrides });
const sum = m => m.records.reduce((total, r) => total + r.activeSeconds, 0);
const near = (actual, expected) => assert.ok(Math.abs(actual - expected) < 0.00001, `${actual} ~= ${expected}`);

test('core exposes the contracted API', () => {
  for (const name of ['Monitor', 'defaultSettings', 'validateSettings', 'validateState', 'csv', 'dayKey']) assert.equal(typeof core[name], 'function', name);
});
test('defaults expose working desktop features with native defaults', () => {
  assert.deepEqual(defaultSettings(), { language: 'zh-Hans', monitoringMode: 'smart', workSeconds: 1200, restSeconds: 20, idleSeconds: 60, fatigueThreshold: 100, strictMode: false, skipChallengeEnabled: false, soundEnabled: true, reminderStyle: 'fullscreen', scheduleEnabled: false, scheduleStartHour: 9, scheduleEndHour: 18, weekdays: [2, 3, 4, 5, 6], restMessage: '望向远处，暂时离开屏幕', wallpaperPath: null, showDockIcon: true, showMenuBarTime: true, dailyLimitEnabled: false, dailyLimitHours: 8, advanceNoticeEnabled: false });
  const a = defaultSettings(); a.weekdays.push(1); assert.equal(defaultSettings().weekdays.length, 5);
});
test('settings clamp finite numeric fields to Swift limits', () => {
  const clean = validateSettings({ workSeconds: -1, restSeconds: 0, idleSeconds: 999, fatigueThreshold: 200, dailyLimitHours: 100, scheduleStartHour: -1, scheduleEndHour: 25, weekdays: [0, 2, 2, 7, 8] });
  assert.deepEqual([clean.workSeconds, clean.restSeconds, clean.idleSeconds, clean.fatigueThreshold, clean.dailyLimitHours, clean.scheduleStartHour, clean.scheduleEndHour], [10, 5, 600, 100, 24, 0, 23]);
  assert.deepEqual(clean.weekdays, [2, 7]);
});
test('settings sanitize invalid types and remove unsupported native features', () => {
  const clean = validateSettings({ workSeconds: Infinity, restSeconds: NaN, idleSeconds: '10', strictMode: 'yes', language: 'xx', monitoringMode: 'unknown', reminderStyle: 'unknown', weekdays: null, restMessage: 42, wallpaperPath: 42, enhancedInputDetection: true, screenActivityDetection: true, unknown: true });
  assert.deepEqual(clean, defaultSettings());
  assert.deepEqual(validateSettings(null), defaultSettings());
});
test('settings assignment sanitizes replacement settings', () => { const m = make(); m.settings = { workSeconds: 1, strictMode: true }; assert.equal(m.settings.workSeconds, 10); assert.equal(m.settings.restSeconds, 20); });
test('first sample establishes clock without inventing usage', () => { const m = make(); m.tick(start, 0); assert.equal(sum(m), 0); assert.equal(m.fatigue, 0); assert.equal(m.phase, 'monitoring'); });
test('active use triggers one break at threshold', () => { const m = make(); m.tick(start, 0); advance(m, start, 60); assert.equal(m.phase, 'resting'); near(m.fatigue, 100); near(sum(m), 60); assert.equal(m.records[0].breaksOffered, 1); m.startBreak(start + 61000); assert.equal(m.records[0].breaksOffered, 1); });
test('idle restores fatigue and excludes idle interval', () => { const m = make(); m.tick(start, 0); m.tick(start + 5000, 0); m.tick(start + 6000, 10); assert.equal(m.phase, 'idle'); near(sum(m), 5); near(m.fatigue, 100 * 5 / 60 - 5); near(m.workElapsed, m.fatigue * 0.6); });
test('continuous reading ignores input idle', () => { const m = make({ monitoringMode: 'continuous' }); m.tick(start, 600); m.tick(start + 5000, 605); assert.equal(sum(m), 5); assert.equal(m.phase, 'monitoring'); });
test('screen unavailability overrides continuous mode', () => { const m = make({ monitoringMode: 'continuous' }); m.tick(start, 0); m.tick(start + 5000, 0, false); assert.equal(sum(m), 0); assert.equal(m.phase, 'idle'); });
test('rest completion counts once and resets fatigue', () => { const m = make(); m.tick(start, 0); advance(m, start, 60); advance(m, start + 60000, 20); assert.equal(m.phase, 'monitoring'); assert.equal(m.fatigue, 0); assert.equal(m.workElapsed, 0); assert.equal(m.breakRemaining, 0); assert.equal(m.records[0].breaksCompleted, 1); m.tick(start + 81000, 0); assert.equal(m.records[0].breaksCompleted, 1); near(sum(m), 61); });
test('break completion belongs to the day on which it began', () => { const m = make(); const t = new Date(2025, 0, 1, 23, 59, 55).getTime(); m.startBreak(t); m.tick(t + 20000, 0); assert.equal(m.records.length, 1); assert.equal(m.records[0].day, '2025-01-01'); assert.equal(m.records[0].breaksCompleted, 1); });
test('strict rest blocks skip snooze and pause using current round snapshot', () => { const m = make({ strictMode: true }); m.startBreak(start); m.settings = { ...m.settings, strictMode: false }; assert.equal(m.skipBreak(start + 1000), false); assert.equal(m.snooze(start + 1000), false); assert.equal(m.setPaused(true, start + 1000), false); assert.equal(m.phase, 'resting'); assert.equal(m.breakIsStrict, true); assert.equal(m.records[0].breaksSkipped, 0); });
test('enabling strict setting does not change an existing normal round', () => { const m = make(); m.startBreak(start); m.settings = { ...m.settings, strictMode: true }; assert.equal(m.breakIsStrict, false); assert.equal(m.skipBreak(start), true); });
test('skip records cancellation and starts five-minute snooze', () => { const m = make(); m.startBreak(start); assert.equal(m.skipBreak(start + 1000), true); assert.equal(m.phase, 'snoozed'); assert.equal(m.breakRemaining, 0); assert.equal(m.snoozeEnd, start + 301000); assert.equal(m.records[0].breaksSkipped, 1); assert.equal(m.records[0].breaksCompleted, 0); assert.equal(m.skipBreak(start + 2000), false); });
test('snooze continues recording use and expires into due break', () => { const m = make(); m.tick(start, 0); assert.equal(m.snooze(start, 70), true); advance(m, start, 69); assert.equal(m.phase, 'snoozed'); assert.equal(sum(m), 69); m.tick(start + 70000, 0); assert.equal(m.phase, 'resting'); assert.equal(m.snoozeEnd, null); });
test('snoozing a normal rest records a skip once', () => { const m = make(); m.startBreak(start); m.snooze(start + 1000); m.snooze(start + 2000); assert.equal(m.records[0].breaksSkipped, 1); assert.equal(m.records[0].breaksCompleted, 0); });
test('pausing excludes time and preserves fatigue until resumed', () => { const m = make(); m.tick(start, 0); m.tick(start + 5000, 0); const fatigue = m.fatigue; assert.equal(m.setPaused(true, start + 5000), true); m.tick(start + 10000, 0); assert.equal(m.phase, 'paused'); assert.equal(sum(m), 5); assert.equal(m.fatigue, fatigue); assert.equal(m.setPaused(false, start + 10000), true); m.tick(start + 15000, 0); assert.equal(sum(m), 10); });
test('pausing normal rest is a skip not a completed rest', () => { const m = make(); m.startBreak(start); m.setPaused(true, start + 1000); m.tick(start + 30000, 0); assert.equal(m.phase, 'paused'); assert.equal(m.records[0].breaksSkipped, 1); assert.equal(m.records[0].breaksCompleted, 0); });
test('manual rest clears pause and snooze', () => { const m = make(); m.snooze(start); m.setPaused(true, start); m.startBreak(start); m.tick(start + 1000, 0); assert.equal(m.phase, 'resting'); assert.equal(m.snoozeEnd, null); });
test('notifications are throttled without pretending a break occurred', () => { const m = make({ reminderStyle: 'notification' }); m.tick(start, 0); advance(m, start, 359); assert.equal(m.notificationCount, 1); assert.equal(m.phase, 'monitoring'); assert.equal(m.records[0].breaksOffered, 0); assert.equal(m.records[0].breaksCompleted, 0); near(sum(m), 359); m.tick(start + 360000, 0); assert.equal(m.notificationCount, 2); });
test('fatigue recovery resets notification throttle after dropping below threshold', () => { const m = make({ reminderStyle: 'notification' }); m.tick(start, 0); advance(m, start, 60); m.tick(start + 61000, 10); m.tick(start + 62000, 0); advance(m, start + 62000, 4); assert.equal(m.notificationCount, 2); });
test('peak usage begins only after the preceding sample was at 100 percent', () => { const m = make({ fatigueThreshold: 50 }); m.tick(start, 0); m.snooze(start, 1000); advance(m, start, 60); assert.equal(m.records[0].peakFatigueSeconds, 0); m.tick(start + 61000, 0); assert.equal(m.records[0].peakFatigueSeconds, 1); });
test('fifteen-second gaps count while longer gaps only restore fatigue', () => { const m = make(); m.tick(start, 0); m.tick(start + 15000, 0); assert.equal(sum(m), 15); m.tick(start + 30001, 0); assert.equal(sum(m), 15); assert.equal(m.fatigue, 0); });
test('sleep gaps never accumulate active usage', () => { const m = make(); m.tick(start, 0); m.tick(start + 3600000, 0); assert.equal(sum(m), 0); assert.equal(m.fatigue, 0); });
test('clock reset excludes the reset interval', () => { const m = make(); m.tick(start, 0); m.resetClock(start + 100000); m.tick(start + 105000, 0); assert.equal(sum(m), 5); });
test('backward clock does not subtract metrics', () => { const m = make(); m.tick(start, 0); m.tick(start - 1000, 0); assert.equal(sum(m), 0); assert.equal(m.fatigue, 0); });
test('local midnight splits active and hourly totals', () => { const m = make(); const midnight = new Date(2025, 0, 2).getTime(); m.tick(midnight - 2000, 0); m.tick(midnight + 2000, 0); assert.deepEqual(m.records.map(r => [r.day, r.activeSeconds]), [['2025-01-01', 2], ['2025-01-02', 2]]); assert.equal(m.records[0].hourlySeconds[23], 2); assert.equal(m.records[1].hourlySeconds[0], 2); });
test('hour boundary divides usage between buckets', () => { const m = make(); const hour = new Date(2025, 0, 1, 13).getTime(); m.tick(hour - 3000, 0); m.tick(hour + 2000, 0); assert.equal(m.records[0].hourlySeconds[12], 3); assert.equal(m.records[0].hourlySeconds[13], 2); });
test('schedule suppresses reminders while retaining use and fatigue', () => { const m = make({ scheduleEnabled: true, scheduleStartHour: 8, scheduleEndHour: 9, weekdays: [1, 2, 3, 4, 5, 6, 7] }); m.tick(start, 0); advance(m, start, 61); assert.equal(m.phase, 'outsideSchedule'); assert.equal(sum(m), 61); assert.equal(m.fatigue, 100); assert.equal(m.records[0].breaksOffered, 0); });
test('overnight schedule uses previous weekday after midnight', () => { const opts = { scheduleEnabled: true, scheduleStartHour: 22, scheduleEndHour: 6, weekdays: [4] }; for (const [day, hour, phase] of [[1, 23, 'monitoring'], [2, 2, 'monitoring'], [2, 10, 'outsideSchedule'], [3, 2, 'outsideSchedule']]) { const m = make(opts); m.tick(new Date(2025, 0, day, hour).getTime(), 0); assert.equal(m.phase, phase); } });
test('equal schedule hours mean the entire selected weekday', () => { const m = make({ scheduleEnabled: true, scheduleStartHour: 9, scheduleEndHour: 9, weekdays: [4] }); m.tick(start, 0); assert.equal(m.phase, 'monitoring'); m.tick(start + 86400000, 0); assert.equal(m.phase, 'outsideSchedule'); });
test('day key uses local calendar with zero padding', () => assert.equal(dayKey(new Date(2025, 0, 2, 3)), '2025-01-02'));
test('older settings backups merge defaults and retain saved values', () => { const input = { settings: { workSeconds: 600 }, records: [] }; const clean = validateState(input); assert.equal(clean.settings.workSeconds, 600); assert.equal(clean.settings.monitoringMode, 'smart'); assert.equal(clean.settings.restSeconds, 20); assert.deepEqual(clean.records, []); assert.notEqual(clean.settings, input.settings); });
test('validated records are sorted and detached from input', () => { const r = record({ activeSeconds: 5 }); const clean = validateState({ settings: {}, records: [record({ day: '2025-01-02' }), r] }); assert.equal(clean.records[0].day, '2025-01-01'); clean.records[0].hourlySeconds[0] = 9; assert.equal(r.hourlySeconds[0], 0); });
for (const [name, input] of [
  ['missing settings', { records: [] }], ['missing records', { settings: {} }], ['null settings', { settings: null, records: [] }], ['wrong settings field type', { settings: { workSeconds: '600' }, records: [] }], ['wrong enum', { settings: { language: 'fr' }, records: [] }], ['duplicate days', { settings: {}, records: [record(), record()] }], ['invalid calendar day', { settings: {}, records: [record({ day: '2025-02-30' })] }], ['negative usage', { settings: {}, records: [record({ activeSeconds: -1 })] }], ['excess daily usage', { settings: {}, records: [record({ activeSeconds: 90001 })] }], ['peak beyond use', { settings: {}, records: [record({ peakFatigueSeconds: 1 })] }], ['unsafe counters', { settings: {}, records: [record({ breaksOffered: Number.MAX_SAFE_INTEGER, breaksCompleted: Number.MAX_SAFE_INTEGER, breaksSkipped: 1 })] }], ['counter sum beyond offers', { settings: {}, records: [record({ breaksOffered: 1, breaksCompleted: 1, breaksSkipped: 1 })] }], ['fractional counter', { settings: {}, records: [record({ breaksOffered: 0.5 })] }], ['missing daily field', { settings: {}, records: [{ day: '2025-01-01' }] }], ['short hourly array', { settings: {}, records: [record({ hourlySeconds: [0] })] }], ['excess hourly usage', { settings: {}, records: [record({ hourlySeconds: Array(24).fill(7201) })] }], ['nonfinite usage', { settings: {}, records: [record({ activeSeconds: Infinity })] }]
]) test(`backup rejects ${name}`, () => { assert.equal(typeof validateState, 'function'); assert.throws(() => validateState(input), { name: 'TypeError', message: /Invalid backup/ }); });
test('valid backup boundary counters survive round trip', () => { const r = record({ activeSeconds: 90000, peakFatigueSeconds: 90000, breaksOffered: 1000000, breaksCompleted: 999999, breaksSkipped: 1, hourlySeconds: Array(24).fill(7200) }); const state = validateState({ settings: {}, records: [r] }); assert.deepEqual(validateState(JSON.parse(JSON.stringify(state))), state); });
test('CSV uses stable sorted ASCII columns CRLF and actual metrics', () => { const output = csv([record({ day: '2025-01-02' }), record({ activeSeconds: 5.9, peakFatigueSeconds: 1.9, breaksOffered: 3, breaksCompleted: 2, breaksSkipped: 1 })]); assert.equal(output, 'date,active_seconds,peak_fatigue_seconds,breaks_offered,breaks_completed,breaks_skipped,completion_rate\r\n2025-01-01,5,1,3,2,1,0.6667\r\n2025-01-02,0,0,0,0,0,0.0000\r\n'); });
test('CSV quotes unexpected dates and escapes embedded quotes', () => { assert.ok(csv([record({ day: 'bad,"day' })]).includes('"bad,""day",')); });
test('resume cannot change an active strict break into a cancellable phase', () => {
  const m = make({ strictMode: true }); m.startBreak(start);
  m.setPaused(false, start + 1000);
  assert.equal(m.phase, 'resting');
  assert.equal(m.snooze(start + 1000), false);
  assert.equal(m.setPaused(true, start + 1000), false);
  m.tick(start + 20000, 0);
  assert.equal(m.records[0].breaksCompleted, 1);
  assert.equal(m.records[0].breaksSkipped, 0);
});
test('resume during a normal rest preserves its deadline and phase', () => {
  const m = make(); m.startBreak(start); m.setPaused(false, start + 1000);
  assert.equal(m.phase, 'resting'); m.tick(start + 20000, 0);
  assert.equal(m.records[0].breaksCompleted, 1);
});
test('saturated break counts stay valid while another round can still finish', () => {
  const m = new Monitor({ settings: settings(), records: [record({ breaksOffered: 1000000, breaksCompleted: 1000000 })] });
  m.startBreak(start); m.tick(start + 20000, 0);
  assert.equal(m.phase, 'monitoring');
  assert.equal(m.records[0].breaksOffered, 1000000);
  assert.equal(m.records[0].breaksCompleted, 1000000);
  assert.doesNotThrow(() => validateState({ settings: m.settings, records: m.records }));
});
test('saturated usage stays reloadable and preserves peak and hourly bounds', () => {
  const hours = Array(24).fill(0); hours[12] = 7200;
  const m = new Monitor({ settings: settings({ reminderStyle: 'notification' }), records: [record({ activeSeconds: 90000, peakFatigueSeconds: 90000, hourlySeconds: hours })] });
  m.tick(start, 0); advance(m, start, 61);
  assert.equal(m.records[0].activeSeconds, 90000);
  assert.equal(m.records[0].peakFatigueSeconds, 90000);
  assert.equal(m.records[0].hourlySeconds[12], 7200);
  assert.doesNotThrow(() => validateState({ settings: m.settings, records: m.records }));
});
test('break duration is fixed when settings change mid-round', () => {
  const m = make(); m.startBreak(start); m.settings = { ...m.settings, restSeconds: 5 };
  m.tick(start + 5000, 0); assert.equal(m.phase, 'resting'); assert.equal(m.breakRemaining, 15);
  m.tick(start + 20000, 0); assert.equal(m.records[0].breaksCompleted, 1);
});
test('invalid clock input does not poison subsequent samples', () => {
  const m = make(); m.tick(start, 0);
  for (const value of [NaN, Infinity, '0', null]) assert.throws(() => m.tick(value, 0), TypeError);
  m.tick(start + 5000, 0); assert.equal(sum(m), 5);
});
test('invalid snooze durations and pause values are rejected', () => {
  const m = make();
  for (const value of [NaN, Infinity, -1, '300']) assert.throws(() => m.snooze(start, value), TypeError);
  assert.throws(() => m.setPaused('true', start), TypeError);
});
