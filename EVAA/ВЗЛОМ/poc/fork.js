// Shared helpers: fork real mainnet accounts (code+data) into a sandbox Blockchain.
const { Blockchain, createShardAccount } = require('@ton/sandbox');
const { Cell, Address, toNano } = require('@ton/core');
const https = require('https');

function httpGet(u) {
  return new Promise((res) => {
    https.get(u, { headers: { 'User-Agent': 'x', accept: 'application/json' } }, (r) => {
      let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d }));
    }).on('error', e => res({ s: 0, d: e.message }));
  });
}

function toCell(data) {
  const c = data.startsWith('0x') ? data.slice(2) : data;
  if (/^[0-9a-fA-F]+$/.test(c) && c.length % 2 === 0) {
    try { return Cell.fromBoc(Buffer.from(c, 'hex'))[0]; } catch (e) {}
  }
  return Cell.fromBase64(data);
}

async function fetchAccount(addr) {
  const a = Address.parse(addr).toString({ urlSafe: true, bounceable: true });
  const r = await httpGet(`https://tonapi.io/v2/blockchain/accounts/${a}`);
  const j = JSON.parse(r.d);
  if (!j.code || !j.data) throw new Error(`no code/data for ${addr} (status ${r.s})`);
  return { address: Address.parse(addr), code: toCell(j.code), data: toCell(j.data), balance: BigInt(j.balance || 0) };
}

async function forkAccount(bc, addr, minBalance = toNano('10')) {
  const acc = await fetchAccount(addr);
  const balance = acc.balance > minBalance ? acc.balance : minBalance;
  await bc.setShardAccount(acc.address, createShardAccount({
    address: acc.address, code: acc.code, data: acc.data, balance, workchain: 0,
  }));
  return acc;
}

module.exports = { httpGet, toCell, fetchAccount, forkAccount };

// ---- Stage 1 self-test ----
if (require.main === module) {
  const MASTER = 'EQCsOdQPDO1Xndzutn9dDcloolWo1wHKICMz2jHL6UP8smcV';
  const PYTH = 'EQA5NPyjfZztDm8jcTBwTAU9NGsgJEkw19z61yecX0TlseSB';
  (async () => {
    const bc = await Blockchain.create();
    const m = await forkAccount(bc, MASTER);
    const p = await forkAccount(bc, PYTH);
    console.log('forked master + pyth');
    // confirm real state parses under real code: call getAssetsData (no args)
    for (const method of ['getAssetsData', 'get_assets_rates', 'getStore']) {
      try {
        const r = await bc.runGetMethod(m.address, method, []);
        console.log(`  master.${method}() -> exit=${r.exitCode} stackItems=${r.stack.length} gas=${r.gasUsed}`);
      } catch (e) { console.log(`  master.${method}() -> ERROR ${e.message}`); }
    }
    try {
      const r = await bc.runGetMethod(p.address, 'get_methods_list', []);
      console.log(`  pyth getmethods exit=${r.exitCode}`);
    } catch (e) { /* pyth method names unknown; not critical */ }
  })().catch(e => { console.error(e); process.exit(1); });
}
