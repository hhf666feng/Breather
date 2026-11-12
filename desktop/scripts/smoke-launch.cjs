'use strict';
const fs = require('node:fs');
const path = require('node:path');

// Trusted CLI input only. This selector is never exposed to renderer IPC.
function resolveSmokeLaunch(outputDirectory, options, applicationRoot = path.resolve(__dirname, '..')) {
  let binary;
  const forwarded = [];
  for (let index = 0; index < options.length; index++) {
    const option = options[index];
    if (option === '--binary' && binary === undefined) {
      binary = options[++index];
      if (typeof binary !== 'string' || !path.isAbsolute(binary)) throw new Error('--binary requires an absolute executable path');
      if (path.extname(binary).toLowerCase() !== '.exe') throw new Error('--binary requires an .exe');
      const stat = fs.lstatSync(binary);
      if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('--binary requires a regular executable file');
    } else if (['--language-en', '--smoke-compact'].includes(option)) forwarded.push(option);
    else throw new Error('Unknown smoke option: ' + option);
  }
  const smokeArguments = ['--smoke-test', outputDirectory, ...forwarded];
  return binary
    ? { executable: binary, arguments: smokeArguments }
    : { executable: process.execPath, arguments: [require.resolve('electron/cli.js'), applicationRoot, ...smokeArguments] };
}
module.exports = { resolveSmokeLaunch };
