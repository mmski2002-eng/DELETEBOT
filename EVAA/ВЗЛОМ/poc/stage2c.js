const { Blockchain } = require('@ton/sandbox');
const { TupleBuilder, beginCell, Dictionary, Address } = require('@ton/core');
const { httpGet, forkAccount } = require('./fork');

const MASTER = 'EQCsOdQPDO1Xndzutn9dDcloolWo1wHKICMz2jHL6UP8smcV';
const TON_ID = 0x1a4219fe5e60d63af2a3cc7dce6fec69b45c6b5718497a6148e7c232ac87bd8an;
const PRICE_SCALE = 1e9;

function pricesCell(map) {
  const V = { serialize: (src, b) => b.storeCoins(src), parse: (s) => s.loadCoins() };
  const d = Dictionary.empty(Dictionary.Keys.BigUint(256), V);
  for (const [k, v] of map) d.set(k, BigInt(Math.round(v)));
  return beginCell().storeDictDirect(d).endCell();
}

async function getBorrowers() {
  const base = `https://tonapi.io/v2/blockchain/accounts/${Address.parse(MASTER).toString({urlSafe:true,bounceable:true})}/transactions`;
  const cps = new Set();
  let before = '';
  for (let page = 0; page < 6; page++) {
    const r = await httpGet(`${base}?limit=100${before}`);
    const j = JSON.parse(r.d); const txs = j.transactions || [];
    if (!txs.length) break;
    for (const tx of txs) {
      if (tx.in_msg && tx.in_msg.source && tx.in_msg.source.address) cps.add(tx.in_msg.source.address);
      for (const om of (tx.out_msgs || [])) if (om.destination && om.destination.address) cps.add(om.destination.address);
    }
    before = `&before_lt=${txs[txs.length - 1].lt}`;
  }
  return [...cps];
}

async function main() {
  const bc = await Blockchain.create();
  const m = await forkAccount(bc, MASTER);
  const cfg = (await bc.runGetMethod(m.address, 'getAssetsConfig', [])).stackReader.readCell();
  const dyn = (await bc.runGetMethod(m.address, 'getAssetsData', [])).stackReader.readCell();

  // real-ish fresh prices: TON=$3, stable jettons=$1
  const FRESH_TON = 3.0;
  const cps = await getBorrowers();
  console.log('candidates:', cps.length);

  const BV = { serialize: () => {}, parse: (s) => s.loadIntBig(65) };
  const results = [];

  for (const a of cps) {
    let acc; try { acc = await forkAccount(bc, a); } catch { continue; }
    try {
      const ru = await bc.runGetMethod(acc.address, 'isUserSc', []);
      if (ru.exitCode !== 0 || ru.stackReader.readBigNumber() === 0n) continue;
    } catch { continue; }
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

    // build price map at multiplier f on COLLATERAL assets (positive balances), debt held at base
    const basePrice = (id) => (id === TON_ID ? FRESH_TON : 1.0);
    async function liqAt(f) {
      const map = new Map();
      for (const [k, v] of assets) {
        let p = basePrice(k) * PRICE_SCALE;
        if (v > 0n) p *= f; // depress collateral price
        map.set(k, p);
      }
      const pr = pricesCell(map);
      const tb = new TupleBuilder(); tb.writeCell(cfg); tb.writeCell(dyn); tb.writeCell(pr);
      const r = await bc.runGetMethod(acc.address, 'getIsLiquidable', tb.build());
      return r.exitCode === 0 && r.stackReader.readBigNumber() === -1n;
    }
    if (await liqAt(1.0)) continue; // already liquidatable at fresh -> skip (not "healthy now")
    // binary search smallest f (largest price) that is still liquidatable boundary
    let lo = 0.0, hi = 1.0;
    for (let i = 0; i < 18; i++) { const mid = (lo + hi) / 2; if (await liqAt(mid)) lo = mid; else hi = mid; }
    const flipF = hi; // just above this collateral keeps healthy; at/below flips
    const dropPct = (1 - flipF) * 100;
    results.push({ a, dropPct, assets });
  }

  results.sort((x, y) => x.dropPct - y.dropPct);
  console.log(`\nborrowers healthy-now, ranked by collateral-drop needed to flip (smaller = realistic target):`);
  for (const r of results.slice(0, 10)) {
    console.log(`  drop ${r.dropPct.toFixed(1)}%  ${r.a}`);
    for (const [k, v] of r.assets) console.log(`       0x${k.toString(16).slice(0,10)} = ${v}`);
  }
  console.log(`\ntotal healthy borrowers: ${results.length}`);
}
main().catch(e => { console.error(e); process.exit(1); });
