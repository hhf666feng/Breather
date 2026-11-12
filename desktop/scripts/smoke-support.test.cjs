'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');

function pendingRenderer(view = 'main') {
  const state = { loadingHidden: false, mainVisible: false, restVisible: false };
  const polls = [], paints = [], deadlines = [];
  let resolveFonts, captures = 0;
  const fonts = new Promise(resolve => { resolveFonts = resolve; });
  const nodes = {
    '#loading': { get hidden() { return state.loadingHidden; } },
    '#main-view': { get hidden() { return !state.mainVisible; }, getClientRects: () => state.mainVisible ? [{}] : [] },
    '#rest-view': { get hidden() { return !state.restVisible; }, getClientRects: () => state.restVisible ? [{}] : [] },
  };
  const context = {
    document: { querySelector: selector => nodes[selector], fonts: { ready: fonts } },
    setTimeout(callback, milliseconds) { (milliseconds === 5000 ? deadlines : polls).push(callback); return callback; },
    clearTimeout() {}, requestAnimationFrame(callback) { paints.push(callback); return callback; }, cancelAnimationFrame() {},
  };
  const image = { nativeCapture: true };
  const window = { webContents: { executeJavaScript: source => vm.runInNewContext(source, context), capturePage: async () => { captures++; return image; } } };
  return { state, polls, paints, deadlines, resolveFonts, window, image, view, get captures() { return captures; } };
}

test('every screenshot waits for bridge state, its expected view, loaded fonts and two paint frames', async () => {
  const { captureSmokeWindow } = require('./electron-smoke.cjs');
  for (const view of ['main', 'rest']) {
    const renderer = pendingRenderer(view);
    const captured = captureSmokeWindow(renderer.window, undefined, view);
    assert.equal(renderer.captures, 0, 'loading screen must never be captured');
    renderer.state.loadingHidden = true;
    renderer.state[view === 'main' ? 'restVisible' : 'mainVisible'] = true;
    renderer.resolveFonts();
    await Promise.resolve();
    renderer.polls.shift()?.();
    assert.equal(renderer.captures, 0, 'the opposite view does not satisfy readiness');
    renderer.state.mainVisible = view === 'main';
    renderer.state.restVisible = view === 'rest';
    renderer.polls.shift()?.();
    assert.equal(renderer.captures, 0, 'layout is ready but has not painted');
    renderer.paints.shift()?.();
    assert.equal(renderer.captures, 0, 'first frame still precedes compositor paint');
    renderer.paints.shift()?.();
    assert.equal(await captured, renderer.image);
    assert.equal(renderer.captures, 1);
  }
});

test('visible bridge state alone cannot bypass waiting for document fonts', async () => {
  const { captureSmokeWindow } = require('./electron-smoke.cjs');
  const renderer = pendingRenderer();
  renderer.state.loadingHidden = true; renderer.state.mainVisible = true;
  const captured = captureSmokeWindow(renderer.window);
  renderer.polls.shift()?.();
  assert.equal(renderer.captures, 0);
  assert.equal(renderer.paints.length, 0);
  renderer.resolveFonts(); await Promise.resolve();
  renderer.polls.shift()?.(); renderer.paints.shift()?.(); renderer.paints.shift()?.();
  assert.equal(await captured, renderer.image);
});

test('renderer readiness times out within five seconds without taking a loading screenshot', async () => {
  const { captureSmokeWindow } = require('./electron-smoke.cjs');
  const renderer = pendingRenderer();
  const captured = captureSmokeWindow(renderer.window);
  renderer.deadlines.shift()?.();
  await assert.rejects(captured, /ready|readiness/i);
  assert.equal(renderer.captures, 0);
});

test('software rendering is enabled only for isolated smoke before app readiness', () => {
  const { prepareSmokeRendering } = require('../main.cjs');
  assert.equal(typeof prepareSmokeRendering, 'function');
  let ready = false, changes = 0;
  const app = { disableHardwareAcceleration() { assert.equal(ready, false); changes++; } };
  prepareSmokeRendering(app, false);
  assert.equal(changes, 0);
  prepareSmokeRendering(app, true);
  assert.equal(changes, 1);
  ready = true;
  prepareSmokeRendering(app, false);
  assert.equal(changes, 1);
});

test('native screenshot retries UnknownVizError once after 200ms and returns real capture result', async () => {
  const { captureSmokeWindow } = require('./electron-smoke.cjs');
  assert.equal(typeof captureSmokeWindow, 'function');
  let captures = 0;
  const waits = [];
  const image = { nativeCapture: true };
  const window = { webContents: { executeJavaScript: async () => true, capturePage: async () => { captures++; if (captures === 1) throw new Error('UnknownVizError'); return image; } } };
  assert.equal(await captureSmokeWindow(window, async milliseconds => waits.push(milliseconds)), image);
  assert.equal(captures, 2);
  assert.deepEqual(waits, [200]);
});

test('native screenshot does not retry unrelated failures and never makes a third capture', async () => {
  const { captureSmokeWindow } = require('./electron-smoke.cjs');
  assert.equal(typeof captureSmokeWindow, 'function');
  for (const message of ['UnknownVizError', 'Permission denied']) {
    let captures = 0;
    const waits = [];
    const window = { webContents: { executeJavaScript: async () => true, capturePage: async () => { captures++; throw new Error(message); } } };
    await assert.rejects(captureSmokeWindow(window, async milliseconds => waits.push(milliseconds)), { message });
    assert.equal(captures, message === 'UnknownVizError' ? 2 : 1);
    assert.deepEqual(waits, message === 'UnknownVizError' ? [200] : []);
  }
});
