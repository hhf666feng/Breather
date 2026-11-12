'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const MAX_DOCUMENT_BYTES = 8 * 1024 * 1024;
const NO_PAYLOAD = new Set(['get-state', 'pause', 'rest', 'snooze', 'skip', 'quit', 'export-csv', 'export-backup', 'restore-backup', 'choose-wallpaper', 'clear-wallpaper', 'dismiss-error', 'cancel-challenge']);
const BOOLEAN_SETTINGS = new Set(['strictMode', 'skipChallengeEnabled', 'soundEnabled', 'scheduleEnabled', 'showDockIcon', 'showMenuBarTime', 'dailyLimitEnabled', 'advanceNoticeEnabled']);
const NUMBER_SETTINGS = new Set(['workSeconds', 'restSeconds', 'idleSeconds', 'fatigueThreshold', 'scheduleStartHour', 'scheduleEndHour', 'dailyLimitHours']);
const ENUM_SETTINGS = { language: ['zh-Hans', 'en'], monitoringMode: ['smart', 'continuous'], reminderStyle: ['fullscreen', 'mini', 'notification'] };

function validateCommand(name, payload) {
  if (typeof name !== 'string') throw new Error('Invalid command');
  if (NO_PAYLOAD.has(name)) {
    if (payload !== undefined && payload !== null) throw new Error('This command has no payload');
    return undefined;
  }
  if (name === 'launch-at-login') {
    if (typeof payload !== 'boolean') throw new Error('Expected a boolean');
    return payload;
  }
  if (name === 'answer-challenge') {
    if ((typeof payload !== 'number' || !Number.isFinite(payload)) && (typeof payload !== 'string' || !/^\s*\d{1,4}\s*$/.test(payload))) throw new Error('Expected a numeric answer');
    return payload;
  }
  if (name !== 'settings') throw new Error('Unknown command');
  if (!payload || typeof payload !== 'object' || Array.isArray(payload) || ![Object.prototype, null].includes(Object.getPrototypeOf(payload))) throw new Error('Expected a settings object');
  const result = {};
  for (const [key, value] of Object.entries(payload)) {
    if (BOOLEAN_SETTINGS.has(key)) {
      if (typeof value !== 'boolean') throw new Error('Invalid setting: ' + key);
    } else if (NUMBER_SETTINGS.has(key)) {
      if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 86400) throw new Error('Invalid setting: ' + key);
    } else if (Object.hasOwn(ENUM_SETTINGS, key)) {
      if (!ENUM_SETTINGS[key].includes(value)) throw new Error('Invalid setting: ' + key);
    } else if (key === 'weekdays') {
      if (!Array.isArray(value) || value.length > 7 || value.some(day => !Number.isInteger(day) || day < 1 || day > 7)) throw new Error('Invalid weekdays');
    } else if (key === 'restMessage') {
      if (typeof value !== 'string' || value.length > 2000) throw new Error('Invalid rest message');
    } else throw new Error('Unknown or protected setting: ' + key);
    result[key] = value;
  }
  return result;
}

function isOwnedSender(event, owners, trustedURL) {
  const sender = event?.sender;
  const entry = owners.get(sender);
  return Boolean(entry && !entry.window.isDestroyed() && entry.window.webContents === sender && !sender.isDestroyed() && event.senderFrame === sender.mainFrame && event.senderFrame?.url === trustedURL && sender.getURL() === trustedURL);
}

function writeAtomicJSON(target, value) {
  const body = JSON.stringify(value, null, 2);
  if (Buffer.byteLength(body) > MAX_DOCUMENT_BYTES) throw new Error('Document too large');
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const temporary = target + '.' + crypto.randomBytes(8).toString('hex') + '.tmp';
  let descriptor;
  try {
    descriptor = fs.openSync(temporary, 'wx', 0o600);
    fs.writeFileSync(descriptor, body, 'utf8');
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor); descriptor = undefined;
    fs.renameSync(temporary, target);
  } finally {
    if (descriptor !== undefined) fs.closeSync(descriptor);
    // temporary was created by this operation beside the validated target.
    if (fs.existsSync(temporary) && path.dirname(temporary) === path.dirname(target)) fs.unlinkSync(temporary);
  }
}

function readJSON(target, maxBytes = MAX_DOCUMENT_BYTES) {
  const stat = fs.lstatSync(target);
  if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('Expected a regular file');
  if (stat.size > maxBytes) throw new Error('Document too large');
  return JSON.parse(fs.readFileSync(target, 'utf8'));
}

function imageDataURL(bytes) {
  if (!Buffer.isBuffer(bytes) || bytes.length > MAX_DOCUMENT_BYTES) throw new Error('Image too large');
  let mime;
  if (bytes.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'))) mime = 'image/png';
  else if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) mime = 'image/jpeg';
  else if (['GIF87a', 'GIF89a'].includes(bytes.subarray(0, 6).toString('ascii'))) mime = 'image/gif';
  else if (bytes.subarray(0, 4).toString('ascii') === 'RIFF' && bytes.subarray(8, 12).toString('ascii') === 'WEBP') mime = 'image/webp';
  else throw new Error('Choose a PNG, JPEG, GIF or WebP image');
  return 'data:' + mime + ';base64,' + bytes.toString('base64');
}

function windowIntent(monitor, view, intent) {
  if (monitor.phase === 'resting') return monitor.breakIsStrict ? 'deny' : 'skip';
  if (view === 'rest') return 'deny';
  return intent === 'close' ? 'hide' : 'minimize';
}

module.exports = { validateCommand, isOwnedSender, writeAtomicJSON, readJSON, imageDataURL, windowIntent, MAX_DOCUMENT_BYTES };
