const { compileFunc } = require('@ton-community/func-js');
const { Cell } = require('@ton/core');
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..', 'evaa-contracts', 'contracts');

async function main() {
  const r = await compileFunc({
    targets: ['master.fc'],
    sources: (p) => fs.readFileSync(path.resolve(ROOT, p), 'utf8'),
  });
  if (r.status === 'error') { console.error('COMPILE ERROR:\n' + r.message.slice(0, 1500)); process.exit(1); }
  const code = Cell.fromBase64(r.codeBoc);
  const hash = code.hash().toString('hex');
  console.log('repo master.fc code hash:', hash.slice(0, 24), '(full', hash + ')');
  console.log('EQCsOdQ (in-scope deployed): 08b54a3ffc6dea19a27b8b1a');
  console.log('MAIN  EQC8rU:                b90881c4dc48b08dd92e5151');
  console.log('match in-scope:', hash.startsWith('08b54a3ffc6dea19a27b8b1a'));
}
main().catch(e => { console.error(e); process.exit(1); });
