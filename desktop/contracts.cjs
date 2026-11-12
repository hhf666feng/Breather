'use strict';

// These are optional pure helpers. Sender authentication belongs in the runtime.
const COMMANDS = Object.freeze([
  'get-state', 'settings', 'pause', 'rest', 'snooze', 'skip', 'quit',
  'export-csv', 'export-backup', 'restore-backup', 'choose-wallpaper',
  'clear-wallpaper', 'launch-at-login', 'dismiss-error', 'answer-challenge', 'cancel-challenge',
]);
function isAllowedCommand(name) { return typeof name === 'string' && COMMANDS.includes(name); }
function shortcutMap(platform = 'win32') {
  const modifier = platform === 'darwin' ? 'Command' : 'Ctrl';
  return { close: `${modifier}+W`, minimize: `${modifier}+M`, preferences: `${modifier}+,`,
    showMain: `${modifier}+0`, rest: `${modifier}+Shift+R`, quit: `${modifier}+Q` };
}
function closePolicy({ view = 'main', phase, breakIsStrict = false, action = 'close', quitting = false } = {}) {
  if (quitting) return 'allow';
  if (view === 'rest' && phase === 'resting') return breakIsStrict ? 'block' : 'skip';
  if (view === 'main' && action === 'close') return 'hide';
  return 'allow';
}
module.exports = { COMMANDS, isAllowedCommand, shortcutMap, closePolicy };
