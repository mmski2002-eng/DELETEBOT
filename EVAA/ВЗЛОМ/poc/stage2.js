const { Blockchain } = require('@ton/sandbox');
const { TupleBuilder, Address } = require('@ton/core');
const { httpGet, forkAccount } = require('./fork');

const MASTER = 'EQCsOdQPDO1Xndzutn9dDcloolWo1wHKICMz2jHL6UP8smcV';

async function masterCells(bc, m) {
  const cfg = (await bc.runGetMethod(m.address, 'getAssetsConfig', [])).stackReader.readCell();
  const dyn = (await bc.runGetMethod(m.address, 'getAssetsData', [])).stackReader.readCell();
  return { cfg, dyn };
}

async function main() {
  const bc = await Blockchain.create();
  const m = await forkAccount(bc, MASTER);
  const { cfg, dyn } = await masterCells(bc, m);
  console.log('got master config + dynamics cells');

  // collect counterparties
  const r = await httpGet(`https://tonapi.io/v2/blockchain/accounts/${Address.parse(MASTER).toString({urlSafe:true,bounceable:true})}/transactions?limit=60`);
  const txs = JSON.parse(r.d).transactions || [];
  const cps = new Set();
  for (const tx of txs) {
    if (tx.in_msg && tx.in_msg.source && tx.in_msg.source.address) cps.add(tx.in_msg.source.address);
    for (const om of (tx.out_msgs || [])) if (om.destination && om.destination.address) cps.add(om.destination.address);
  }
  console.log('counterparties:', cps.size);

  const borrowers = [];
  for (const a of cps) {
    let acc;
    try { acc = await forkAccount(bc, a); } catch (e) { continue; }
    // isUserSc?
    let isUser = false;
    try { const rr = await bc.runGetMethod(acc.address, 'isUserSc', []); isUser = rr.exitCode === 0 && rr.stackReader.readBigNumber() !== 0n; } catch (e) { continue; }
    if (!isUser) continue;
    // balances
    try {
      const tb = new TupleBuilder(); tb.writeCell(dyn);
      const rr = await bc.runGetMethod(acc.address, 'getAccountBalances', tb.build());
      if (rr.exitCode !== 0) continue;
      const dictCell = rr.stackReader.readCellOpt();
      if (!dictCell) continue;
      // parse dict asset_id(256) -> int(65)
      const { Dictionary } = require('@ton/core');
      const V = { serialize: () => {}, parse: (s) => s.loadIntBig(65) };
      const d = Dictionary.loadDirect(Dictionary.Keys.BigUint(256), V, dictCell);
      const entries = [];
      let hasDebt = false, hasColl = false;
      for (const [k, v] of d) { entries.push([k, v]); if (v < 0n) hasDebt = true; if (v > 0n) hasColl = true; }
      if (hasDebt && hasColl) {
        borrowers.push({ addr: a, entries });
        console.log(`\nBORROWER ${a}`);
        for (const [k, v] of entries) console.log(`   asset 0x${k.toString(16).slice(0,12)}... balance=${v}`);
      }
    } catch (e) { continue; }
  }
  console.log(`\nfound ${borrowers.length} borrowers with debt+collateral`);
}
main().catch(e => { console.error(e); process.exit(1); });
