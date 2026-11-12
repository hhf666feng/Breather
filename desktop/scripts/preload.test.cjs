'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { EventEmitter } = require('node:events');

test('sandbox bridge exposes narrow API, strips Electron events and unsubscribes safely', async () => {
  const filename = path.join(__dirname, '../preload.cjs');
  assert.ok(fs.existsSync(filename), 'preload bridge must exist');
  const ipc = new EventEmitter();
  const calls = [];
  ipc.invoke = async (...args) => { calls.push(args); return { ok: true }; };
  let exposed;
  vm.runInNewContext(fs.readFileSync(filename, 'utf8'), {
    require(name) { assert.equal(name, 'electron'); return { contextBridge: { exposeInMainWorld(name, api) { assert.equal(name, 'breather'); exposed = api; } }, ipcRenderer: ipc }; },
  });
  assert.deepEqual(Object.keys(exposed).sort(), ['command', 'getState', 'onNavigate', 'subscribe']);
  await exposed.getState();
  assert.deepEqual(calls[0], ['breather:get-state']);
  assert.equal((await exposed.command('arbitrary-code', 'secret')).ok, false);
  assert.equal(calls.length, 1);
  await exposed.command('pause');
  assert.deepEqual(calls[1], ['breather:command', 'pause', undefined]);
  let delivered;
  const unsubscribe = exposed.subscribe((...args) => { delivered = args; });
  ipc.emit('breather:state', { privileged: true }, { phase: 'monitoring' });
  assert.equal(delivered.length, 1);
  assert.equal(delivered[0].phase, 'monitoring');
  unsubscribe();
  assert.equal(ipc.listenerCount('breather:state'), 0);
  let page;
  const offNavigate = exposed.onNavigate(value => { page = value; });
  ipc.emit('breather:navigate', {}, 'settings');
  assert.equal(page, 'settings');
  offNavigate();
  assert.equal(ipc.listenerCount('breather:navigate'), 0);
});
