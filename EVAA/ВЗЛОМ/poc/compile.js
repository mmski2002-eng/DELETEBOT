const { compileFunc } = require('@ton-community/func-js');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', 'evaa-contracts', 'contracts');
const ENTRY = 'poc_stale_test.fc';

async function main() {
  const result = await compileFunc({
    targets: [ENTRY],
    sources: (p) => {
      const full = path.resolve(ROOT, p);
      return fs.readFileSync(full, 'utf8');
    },
  });

  if (result.status === 'error') {
    console.error('COMPILE ERROR:\n' + result.message);
    process.exit(1);
  }
  fs.writeFileSync(path.resolve(__dirname, 'stale_test.boc.base64'), result.codeBoc);
  console.log('COMPILE OK. codeBoc bytes(base64 len):', result.codeBoc.length);
}
main().catch((e) => { console.error(e); process.exit(1); });
