'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const config = require('../package.json');

test('Windows builder configuration is valid and produces distinct exact-version x64 artifacts', async () => {
  const { validateConfiguration } = require('app-builder-lib/out/util/config/config.js');
  await validateConfiguration(config.build, { add() {} });
  const { expandMacro } = require('app-builder-lib/out/util/macroExpander.js');
  const appInfo = { name: config.name, productName: config.build.productName, sanitizedProductName: config.build.productName, version: config.version };
  const names = ['nsis', 'portable'].map(target => {
    const pattern = config.build[target]?.artifactName || config.build.win.artifactName || '${productName}-${version}-${arch}.${ext}';
    return expandMacro(pattern, 'x64', appInfo, { ext: 'exe', os: 'win' });
  });
  assert.notEqual(names[0], names[1]);
  for (const name of names) assert.match(name, /^Breather-1\.6\.0-x64-.*\.exe$/);
  assert.equal(config.build.appId, 'local.breather.windows');
  assert.equal(config.version, '1.6.0');
  for (const version of Object.values(config.devDependencies)) assert.match(version, /^\d+\.\d+\.\d+$/);
});
