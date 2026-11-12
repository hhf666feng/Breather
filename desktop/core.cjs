'use strict';

// Pure domain logic. Runtime owns clocks, OS activity signals, persistence and windows.
function defaultSettings() {
  return {
    language: 'zh-Hans', monitoringMode: 'smart', workSeconds: 1200,
    restSeconds: 20, idleSeconds: 60, fatigueThreshold: 100, strictMode: false,
    skipChallengeEnabled: false, soundEnabled: true, reminderStyle: 'fullscreen',
    scheduleEnabled: false, scheduleStartHour: 9, scheduleEndHour: 18,
    weekdays: [2, 3, 4, 5, 6], restMessage: '望向远处，暂时离开屏幕',
    wallpaperPath: null, showDockIcon: true, showMenuBarTime: true,
    dailyLimitEnabled: false, dailyLimitHours: 8, advanceNoticeEnabled: false,
  };
}
const ranges = Object.freeze({ workSeconds: [10, 14400], restSeconds: [5, 3600],
  idleSeconds: [5, 600], fatigueThreshold: [10, 100], dailyLimitHours: [0.5, 24],
  scheduleStartHour: [0, 23], scheduleEndHour: [0, 23] });
const enums = Object.freeze({ language: ['zh-Hans', 'en'], monitoringMode: ['smart', 'continuous'], reminderStyle: ['fullscreen', 'mini', 'notification'] });
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const finite = value => typeof value === 'number' && Number.isFinite(value);
function validateSettings(input) {
  const clean = defaultSettings();
  if (!object(input)) return clean;
  for (const key of Object.keys(clean)) {
    if (!own(input, key)) continue;
    const value = input[key];
    if (own(ranges, key)) {
      if (finite(value)) {
        clean[key] = Math.min(ranges[key][1], Math.max(ranges[key][0], value));
        if (key === 'scheduleStartHour' || key === 'scheduleEndHour') clean[key] = Math.trunc(clean[key]);
      }
    } else if (own(enums, key)) {
      if (enums[key].includes(value)) clean[key] = value;
    } else if (key === 'weekdays') {
      if (Array.isArray(value)) clean[key] = [...new Set(value.filter(day => Number.isInteger(day) && day >= 1 && day <= 7))].sort((a, b) => a - b);
    } else if (key === 'wallpaperPath') {
      if (value === null || typeof value === 'string') clean[key] = value;
    } else if (typeof value === typeof clean[key]) clean[key] = value;
  }
  return clean;
}
function dayKey(date) {
  if (!(date instanceof Date) || !finite(date.getTime())) throw new TypeError('Invalid date');
  return `${String(date.getFullYear()).padStart(4, '0')}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}
function validDay(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(0); date.setUTCFullYear(year, month - 1, day); date.setUTCHours(0, 0, 0, 0);
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}
function newRecord(day) {
  return { day, activeSeconds: 0, peakFatigueSeconds: 0, breaksOffered: 0,
    breaksCompleted: 0, breaksSkipped: 0, hourlySeconds: Array(24).fill(0) };
}
function invalidBackup(detail) { throw new TypeError(`Invalid backup: ${detail}`); }
function validateState(input) {
  if (!object(input) || !own(input, 'settings') || !object(input.settings) || !Array.isArray(input.records)) invalidBackup('expected settings object and records array');
  const defaults = defaultSettings();
  for (const key of Object.keys(defaults)) {
    if (!own(input.settings, key)) continue;
    const value = input.settings[key];
    let valid;
    if (own(ranges, key)) valid = finite(value) && (!(key === 'scheduleStartHour' || key === 'scheduleEndHour') || Number.isInteger(value));
    else if (own(enums, key)) valid = enums[key].includes(value);
    else if (key === 'weekdays') valid = Array.isArray(value) && value.every(Number.isInteger);
    else if (key === 'wallpaperPath') valid = value === null || typeof value === 'string';
    else valid = typeof value === typeof defaults[key];
    if (!valid) invalidBackup(`invalid setting ${key}`);
  }
  const days = new Set();
  const records = Array.from(input.records, record => {
    if (!object(record) || !validDay(record.day) || days.has(record.day)) invalidBackup('invalid or duplicate record day');
    days.add(record.day);
    if (!finite(record.activeSeconds) || record.activeSeconds < 0 || record.activeSeconds > 90000 ||
        !finite(record.peakFatigueSeconds) || record.peakFatigueSeconds < 0 || record.peakFatigueSeconds > record.activeSeconds) invalidBackup('invalid usage totals');
    for (const key of ['breaksOffered', 'breaksCompleted', 'breaksSkipped']) {
      if (!Number.isSafeInteger(record[key]) || record[key] < 0 || record[key] > 1000000) invalidBackup('invalid break counter');
    }
    if (record.breaksCompleted > record.breaksOffered || record.breaksSkipped > record.breaksOffered - record.breaksCompleted) invalidBackup('break outcomes exceed offers');
    if (!Array.isArray(record.hourlySeconds) || record.hourlySeconds.length !== 24 ||
        Array.from(record.hourlySeconds).some(value => !finite(value) || value < 0 || value > 7200)) invalidBackup('invalid hourly usage');
    return { day: record.day, activeSeconds: record.activeSeconds, peakFatigueSeconds: record.peakFatigueSeconds,
      breaksOffered: record.breaksOffered, breaksCompleted: record.breaksCompleted,
      breaksSkipped: record.breaksSkipped, hourlySeconds: [...record.hourlySeconds] };
  }).sort((a, b) => a.day.localeCompare(b.day));
  return { settings: validateSettings(input.settings), records };
}
function isScheduled(settings, date) {
  if (!settings.scheduleEnabled) return true;
  const hour = date.getHours();
  let weekday = date.getDay() + 1;
  const { scheduleStartHour: start, scheduleEndHour: end } = settings;
  if (start === end) return settings.weekdays.includes(weekday);
  if (start < end) return settings.weekdays.includes(weekday) && hour >= start && hour < end;
  if (hour < end) weekday = weekday === 1 ? 7 : weekday - 1;
  return settings.weekdays.includes(weekday) && (hour >= start || hour < end);
}
function timestamp(value) {
  if (!finite(value) || !finite(new Date(value).getTime())) throw new TypeError('Invalid timestamp');
  return value;
}
class Monitor {
  constructor({ settings = {}, records = [] } = {}) {
    this.settings = settings;
    this.records = validateState({ settings: {}, records }).records;
    this.phase = 'monitoring'; this.fatigue = 0; this.workElapsed = 0;
    this.breakRemaining = 0; this.breakIsStrict = false; this.notificationCount = 0;
    this.snoozeEnd = null; this._lastTick = null; this._breakEnd = null;
    this._breakRecordDay = null; this._paused = false; this._lastNotification = null;
  }
  get settings() { return this._settings; }
  set settings(value) { this._settings = validateSettings(value); }
  tick(nowMs, idleSeconds, available = true) {
    timestamp(nowMs);
    const previous = this._lastTick;
    this._lastTick = nowMs;
    const rawDelta = previous === null ? 0 : Math.max(0, (nowMs - previous) / 1000);
    const delta = rawDelta <= 15 ? rawDelta : 0;
    if (this._paused) { this.phase = 'paused'; return; }
    if (this._breakEnd !== null) {
      this.breakRemaining = Math.max(0, (this._breakEnd - nowMs) / 1000);
      if (this.breakRemaining <= 0) {
        if (this._breakRecordDay !== null) this._record(this._breakRecordDay).breaksCompleted++;
        this._breakEnd = null; this._breakRecordDay = null; this.fatigue = 0;
        this.workElapsed = 0; this.phase = 'monitoring';
      } else {
        this.phase = 'resting';
        this.fatigue = Math.max(0, this.fatigue - delta * 100 / this.settings.restSeconds);
      }
      return;
    }
    if (rawDelta > 15) this._recover(rawDelta);
    if (!available || (this.settings.monitoringMode === 'smart' && idleSeconds >= this.settings.idleSeconds)) {
      this.phase = 'idle'; this._recover(delta); return;
    }
    const wasAtPeak = this.fatigue >= 100 - 0.000001;
    this.fatigue = Math.min(100, this.fatigue + delta * 100 / this.settings.workSeconds);
    this.workElapsed = this.fatigue * this.settings.workSeconds / 100;
    if (previous !== null && delta > 0) this._recordUsage(previous, nowMs, wasAtPeak);
    if (this.snoozeEnd !== null && nowMs < this.snoozeEnd) { this.phase = 'snoozed'; return; }
    this.snoozeEnd = null;
    if (!isScheduled(this.settings, new Date(nowMs))) { this.phase = 'outsideSchedule'; return; }
    this.phase = 'monitoring';
    if (this.fatigue + 0.000001 >= this.settings.fatigueThreshold) {
      if (this.settings.reminderStyle === 'notification') {
        if (this._lastNotification === null || nowMs - this._lastNotification >= 300000) {
          this.notificationCount++; this._lastNotification = nowMs;
        }
      } else this.startBreak(nowMs);
    } else if (this.fatigue < this.settings.fatigueThreshold - 1) this._lastNotification = null;
  }
  startBreak(nowMs) {
    timestamp(nowMs);
    if (this._breakEnd !== null) return;
    this._paused = false; this.snoozeEnd = null; this.phase = 'resting';
    this.breakRemaining = this.settings.restSeconds; this.breakIsStrict = this.settings.strictMode;
    this._breakEnd = nowMs + this.settings.restSeconds * 1000;
    const record = this._record(dayKey(new Date(nowMs)));
    // A saturated imported day can still take a real break without corrupting its counters.
    this._breakRecordDay = record.breaksOffered < 1000000 ? record.day : null;
    if (this._breakRecordDay !== null) record.breaksOffered++;
    this._lastTick = nowMs;
  }
  skipBreak(nowMs) {
    timestamp(nowMs);
    if (this.phase !== 'resting' || this.breakIsStrict) return false;
    this._cancelBreak(); this.snoozeEnd = nowMs + 300000;
    this.phase = 'snoozed'; this._lastTick = nowMs; return true;
  }
  snooze(nowMs, seconds = 300) {
    timestamp(nowMs);
    if (this.phase === 'resting' && this.breakIsStrict) return false;
    if (!finite(seconds) || seconds < 0 || !finite(new Date(nowMs + seconds * 1000).getTime())) throw new TypeError('Invalid snooze duration');
    if (this._breakEnd !== null) this._cancelBreak();
    this.snoozeEnd = nowMs + seconds * 1000; this.phase = 'snoozed'; return true;
  }
  setPaused(value, nowMs) {
    timestamp(nowMs);
    if (typeof value !== 'boolean') throw new TypeError('Invalid pause value');
    if (this._breakEnd !== null) {
      if (!value) return true;
      if (this.breakIsStrict) return false;
      this._cancelBreak();
    }
    this._paused = value; this.phase = value ? 'paused' : 'monitoring'; this._lastTick = nowMs; return true;
  }
  resetClock(nowMs) { this._lastTick = timestamp(nowMs); }
  _recover(seconds) {
    this.fatigue = Math.max(0, this.fatigue - seconds * 100 / this.settings.restSeconds);
    this.workElapsed = this.fatigue * this.settings.workSeconds / 100;
  }
  _cancelBreak() {
    if (this._breakRecordDay !== null) this._record(this._breakRecordDay).breaksSkipped++;
    this._breakEnd = null; this._breakRecordDay = null; this.breakRemaining = 0;
  }
  _record(day) {
    let record = this.records.find(record => record.day === day);
    if (!record) { record = newRecord(day); this.records.push(record); this.records.sort((a, b) => a.day.localeCompare(b.day)); }
    return record;
  }
  _recordUsage(start, end, atPeak) {
    let cursor = start;
    while (cursor < end) {
      const date = new Date(cursor);
      // Use elapsed time to the next local hour, preserving both repeated DST hours.
      const untilHour = (60 - date.getMinutes()) * 60000 - date.getSeconds() * 1000 - date.getMilliseconds();
      const segmentEnd = Math.min(end, cursor + untilHour);
      const seconds = (segmentEnd - cursor) / 1000;
      const record = this._record(dayKey(date));
      record.activeSeconds = Math.min(90000, record.activeSeconds + seconds);
      if (atPeak) record.peakFatigueSeconds = Math.min(record.activeSeconds, record.peakFatigueSeconds + seconds);
      const hour = date.getHours();
      record.hourlySeconds[hour] = Math.min(7200, record.hourlySeconds[hour] + seconds);
      cursor = segmentEnd;
    }
  }
}
function csv(records) {
  const lines = ['date,active_seconds,peak_fatigue_seconds,breaks_offered,breaks_completed,breaks_skipped,completion_rate'];
  for (const record of [...records].sort((a, b) => a.day.localeCompare(b.day))) {
    const day = /^\d{4}-\d{2}-\d{2}$/.test(record.day) ? record.day : `"${String(record.day).replaceAll('"', '""')}"`;
    lines.push([day, Math.trunc(record.activeSeconds), Math.trunc(record.peakFatigueSeconds), record.breaksOffered,
      record.breaksCompleted, record.breaksSkipped, (record.breaksOffered === 0 ? 0 : record.breaksCompleted / record.breaksOffered).toFixed(4)].join(','));
  }
  return lines.join('\r\n') + '\r\n';
}
module.exports = { Monitor, defaultSettings, validateSettings, validateState, csv, dayKey };
