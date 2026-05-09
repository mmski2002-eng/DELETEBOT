const fs = require('fs');
const path = require('path');
const { runTolkCompiler } = require('../bug-bounty/node_modules/.pnpm/@ton+tolk-js@1.0.0/node_modules/@ton/tolk-js');

const root = path.resolve('./torch-tgusd-contract/contracts/tgusd-staking');
const cache = new Map();

function normalize(pathname, contents) {
  let transformed = contents;
  // Update Tolk version
  transformed = transformed.replace(/^\s*tolk 0\.11/m, 'tolk 1.0');
  // getter -> fun
  transformed = transformed.replace(/\bget\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/g, 'fun $1(');
  // self: -> this:
  transformed = transformed.replace(/\bself\s*:/g, 'this:');
  // mutate self -> mutate this
  transformed = transformed.replace(/\bmutate\s+this\s*:/g, 'mutate this:');
  // Remove return type `self` and replace with the actual type
  transformed = transformed.replace(/\)\s*:\s*self\s*\{/g, '): builder {');
  // Replace now() with currentTime()
  transformed = transformed.replace(/\bnow\s*\(\s*\)/g, 'now()');
  return transformed;
}

async function compile() {
  const res = await runTolkCompiler({
    entrypointFileName: 'main.tolk',
    optimizationLevel: 1,
    fsReadCallback: (name) => {
      const file = path.isAbsolute(name) ? name : path.resolve(root, name);
      const key = path.relative(root, file);
      if (cache.has(key)) return cache.get(key);
      const contents = fs.readFileSync(file, 'utf8');
      const patched = normalize(file, contents);
      cache.set(key, patched);
      return patched;
    },
  });
  
  console.log('compile result', res.status);
  if (res.status === 'error') {
    console.error(res.message);
    process.exit(1);
  } else {
    console.log('codeHashHex:', res.codeHashHex);
    fs.writeFileSync('tmp_staking_code.boc', Buffer.from(res.codeBoC, 'base64'));
    console.log('Compiled code saved to tmp_staking_code.boc');
  }
}

compile().catch((e) => { console.error(e); process.exit(1); });
