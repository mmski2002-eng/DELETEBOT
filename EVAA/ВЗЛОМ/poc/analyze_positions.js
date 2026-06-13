const { Blockchain } = require('@ton/sandbox');
const { TupleBuilder, beginCell, Dictionary } = require('@ton/core');
const { forkAccount } = require('./fork');
const fs = require('fs');

const MASTER = process.argv[2] || 'EQCsOdQPDO1Xndzutn9dDcloolWo1wHKICMz2jHL6UP8smcV';
const INFILE = process.argv[3] || 'positions.json';
const TON_ID = 0x1a4219fe5e60d63af2a3cc7dce6fec69b45c6b5718497a6148e7c232ac87bd8an;
const SCALE = 1e9;

function pricesCell(map) {
  const V = { serialize: (s, b) => b.storeCoins(s), parse: (s) => s.loadCoins() };
  const d = Dictionary.empty(Dictionary.Keys.BigUint(256), V);
  for (const [k, v] of map) d.set(k, BigInt(Math.round(v)));
  return beginCell().storeDictDirect(d).endCell();
}

async function main() {
  const { counterparties } = JSON.parse(fs.readFileSync(__dirname + '/' + INFILE, 'utf8'));
  console.log('counterparties to check:', counterparties.length);

  const bc = await Blockchain.create();
  const m = await forkAccount(bc, MASTER);
  const cfg = (await bc.runGetMethod(m.address, 'getAssetsConfig', [])).stackReader.readCell();
  const dyn = (await bc.runGetMethod(m.address, 'getAssetsData', [])).stackReader.readCell();

  const BV = { serialize: () => {}, parse: (s) => s.loadIntBig(65) };
  const basePrice = (id) => (id === TON_ID ? 3.0 : 1.0); // TON $3, stables $1

  const results = [];
  let checked = 0, users = 0;
  for (const a of counterparties) {
    let acc; try { acc = await forkAccount(bc, a); } catch { continue; }
    checked++;
    try {
      const ru = await bc.runGetMethod(acc.address, 'isUserSc', []);
      if (ru.exitCode !== 0 || ru.stackReader.readBigNumber() === 0n) continue;
    } catch { continue; }
    users++;
    let bals;
    try {
      const tb = new TupleBuilder(); tb.writeCell(dyn);
      const rr = await bc.runGetMethod(acc.address, 'getAccountBalances', tb.build());
      if (rr.exitCode !== 0) continue;
      const c = rr.stackReader.readCellOpt(); if (!c) continue;
      bals = Dictionary.loadDirect(Dictionary.Keys.BigUint(256), BV, c);
    } catch { continue; }
    const assets = []; let hasDebt = false, hasColl = false;
    for (const [k, v] of bals) { assets.push([k, v]); if (v < 0n) hasDebt = true; if (v > 0n) hasColl = true; }
    if (!(hasDebt && hasColl)) continue;

    async function liqAt(f) {
      const map = new Map();
      for (const [k, v] of assets) { let p = basePrice(k) * SCALE; if (v > 0n) p *= f; map.set(k, p); }
      const tb = new TupleBuilder(); tb.writeCell(cfg); tb.writeCell(dyn); tb.writeCell(pricesCell(map));
      const r = await bc.runGetMethod(acc.address, 'getIsLiquidable', tb.build());
      return r.exitCode === 0 && r.stackReader.readBigNumber() === -1n;
    }
    if (await liqAt(1.0)) { results.push({ a, dropPct: 0, assets, alreadyLiq: true }); continue; }
    let lo = 0, hi = 1;
    for (let i = 0; i < 16; i++) { const mid = (lo + hi) / 2; if (await liqAt(mid)) lo = mid; else hi = mid; }
    results.push({ a, dropPct: (1 - hi) * 100, assets });
  }

  results.sort((x, y) => x.dropPct - y.dropPct);
  console.log(`\nchecked ${checked} accounts, ${users} user-SCs, ${results.length} borrowers\n`);
  console.log('TOP near-threshold (smallest collateral drop to flip = realistic stale-price target):');
  for (const r of results.slice(0, 15)) {
    console.log(`  drop ${r.dropPct.toFixed(1)}%${r.alreadyLiq ? ' (ALREADY liquidatable!)' : ''}  ${r.a}`);
    for (const [k, v] of r.assets) console.log(`       0x${k.toString(16).slice(0, 10)} = ${v}`);
  }
  fs.writeFileSync(__dirname + '/borrowers.json', JSON.stringify(results, (k, v) => typeof v === 'bigint' ? v.toString() : v));
}
main().catch(e => { console.error(e); process.exit(1); });
