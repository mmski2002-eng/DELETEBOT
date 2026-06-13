const { Blockchain } = require('@ton/sandbox');
const { TupleBuilder, beginCell, Dictionary } = require('@ton/core');
const { forkAccount } = require('./fork');

const MASTER = 'EQCsOdQPDO1Xndzutn9dDcloolWo1wHKICMz2jHL6UP8smcV';
const VICTIM = '0:b6b3f10840d4927b658673a9ff1120563ee8767d354f36e61b6c5c90c0e0c682';
const TON_ID = 0x1a4219fe5e60d63af2a3cc7dce6fec69b45c6b5718497a6148e7c232ac87bd8an;
const DEBT_ID = 0xca9006bd3fb0bc234f8f9ec1227e1ca5d124b85f6a8e8c1c2e5dc43c0ea2bc1fn; // will fix from real id

const PRICE_SCALE = 1000000000n; // 1e9

function pricesCell(map) {
  // evaa prices_packed: udict 256 -> slice with store_coins(price)
  const V = { serialize: (src, b) => b.storeCoins(src), parse: (s) => s.loadCoins() };
  const d = Dictionary.empty(Dictionary.Keys.BigUint(256), V);
  for (const [k, v] of map) d.set(k, v);
  return beginCell().storeDictDirect(d).endCell();
}

async function main() {
  const bc = await Blockchain.create();
  const m = await forkAccount(bc, MASTER);
  const cfg = (await bc.runGetMethod(m.address, 'getAssetsConfig', [])).stackReader.readCell();
  const dyn = (await bc.runGetMethod(m.address, 'getAssetsData', [])).stackReader.readCell();

  // discover the real debt asset id from victim balances
  const v = await forkAccount(bc, VICTIM);
  const tbB = new TupleBuilder(); tbB.writeCell(dyn);
  const balCell = (await bc.runGetMethod(v.address, 'getAccountBalances', tbB.build())).stackReader.readCellOpt();
  const BV = { serialize: () => {}, parse: (s) => s.loadIntBig(65) };
  const bals = Dictionary.loadDirect(Dictionary.Keys.BigUint(256), BV, balCell);
  let debtId = null;
  for (const [k, val] of bals) { if (val < 0n) debtId = k; }
  console.log('victim debt asset id = 0x' + debtId.toString(16));

  async function isLiq(tonPriceUsd) {
    const map = new Map();
    map.set(TON_ID, BigInt(Math.round(tonPriceUsd * 1e9)));      // TON price (evaa-scaled 1e9 = $1)
    map.set(debtId, PRICE_SCALE);                                // debt asset $1 (USDT-like)
    const pr = pricesCell(map);
    const tb = new TupleBuilder(); tb.writeCell(cfg); tb.writeCell(dyn); tb.writeCell(pr);
    const r = await bc.runGetMethod(v.address, 'getIsLiquidable', tb.build());
    if (r.exitCode !== 0) return `exit ${r.exitCode}`;
    return r.stackReader.readBigNumber(); // -1 liquidatable, 0 not
  }

  console.log('\ngetIsLiquidable(victim) at various TON prices:');
  for (const p of [3.0, 1.0, 0.5, 0.3, 0.2, 0.15, 0.1, 0.05]) {
    const res = await isLiq(p);
    console.log(`  TON=$${p.toFixed(2)} -> ${res === -1n ? 'LIQUIDATABLE' : res === 0n ? 'healthy' : res}`);
  }
}
main().catch(e => { console.error(e); process.exit(1); });
