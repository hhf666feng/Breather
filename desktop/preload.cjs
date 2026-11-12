'use strict';
// Sandboxed preloads can require Electron, but cannot load arbitrary Node modules.
const { contextBridge, ipcRenderer } = require('electron');
const commands = new Set(['get-state', 'settings', 'pause', 'rest', 'snooze', 'skip', 'quit', 'export-csv', 'export-backup', 'restore-backup', 'choose-wallpaper', 'clear-wallpaper', 'launch-at-login', 'dismiss-error', 'answer-challenge', 'cancel-challenge']);
function listen(channel, callback) {
  if (typeof callback !== 'function') throw new TypeError('Expected a callback');
  const listener = (_event, value) => callback(value);
  ipcRenderer.on(channel, listener);
  return () => ipcRenderer.removeListener(channel, listener);
}
contextBridge.exposeInMainWorld('breather', Object.freeze({
  getState: () => ipcRenderer.invoke('breather:get-state'),
  subscribe: callback => listen('breather:state', callback),
  onNavigate: callback => listen('breather:navigate', callback),
  command: (name, payload) => commands.has(name)
    ? ipcRenderer.invoke('breather:command', name, payload)
    : Promise.resolve({ ok: false, error: 'Unknown command' }),
}));
