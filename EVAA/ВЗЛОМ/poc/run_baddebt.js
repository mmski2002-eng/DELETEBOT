const { compileFunc } = require('@ton-community/func-js');
const { Blockchain, createShardAccount } = require('@ton/sandbox');
const { Cell, beginCell, contractAddress, toNano, TupleBuilder } = require('@ton/core');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', 'evaa-contracts', 'contracts');
const PRICE_SCALE = 1000000000n; // 1e9
const USD_ALLOWED = 200n;
const COLL_DEC_SCALE = 1000000000n; // fast_dec_pow(9)
const ASSET_COEFF_SCALE = 10000n;

async function main() {
  const c = await compileFunc({
    targets: ['poc_baddebt.fc'],
    sources: (p) => fs.readFileSync(path.resolve(ROOT, p), 'utf8'),
  });
  if (c.status === 'error') { console.error('COMPILE ERROR:\n' + c.message); process.exit(1); }
  console.log('compiled poc_baddebt OK\n');

  const code = Cell.fromBase64(c.codeBoc);
  const data = beginCell().endCell();
  const bc = await Blockchain.create();
  const address = contractAddress(0, { code, data });
  await bc.setShardAccount(address, createShardAccount({ address, code, data, balance: toNano('1'), workchain: 0 }));

  // priceC in USD * 1e9 ; priceB = $1
  const priceB = PRICE_SCALE;
  const scenarios = [
    ['FRESH   collateral $1.00', PRICE_SCALE],
    ['stale   collateral $0.80 (-20%)', 800000000n],
    ['stale   collateral $0.60 (-40%)', 600000000n],
  ];

  console.log('Position: 1.0 collateral token, 0.7 debt token | LT=80% bonus=5%');
  console.log('healthy at fresh $1 (limit $0.80 > debt $0.70)\n');

  for (const [label, priceC] of scenarios) {
    const tb = new TupleBuilder();
    tb.writeNumber(priceC);
    tb.writeNumber(priceB);
    const r = await bc.runGetMethod(address, 'run', tb.build());
    const s = r.stackReader;
    const liq = s.readBigNumber();
    const ep = s.readBigNumber();
    const sup = s.readBigNumber();
    const bor = s.readBigNumber();
    const collAmt = s.readBigNumber();
    const collPresent = s.readBigNumber();
    const badDebt = s.readBigNumber();

    // max_not_too_much = max(collateral_present*33%, $200/collateral_price)
    // mirrors user-liquidate.fc:247-264
    const cap33 = collPresent / 3n;
    const floorUsd = priceC !== 0n
      ? USD_ALLOWED * PRICE_SCALE * COLL_DEC_SCALE / priceC
      : cap33;
    const maxNotTooMuch = floorUsd > cap33 ? floorUsd : cap33;

    const rewardNormal = min(collAmt, collPresent, maxNotTooMuch);
    const rewardBypass = min2(collAmt, collPresent); // isBadDebt: skip max_not_too_much
    const reward = badDebt !== 0n ? rewardBypass : rewardNormal; // FunC true = -1n

    console.log(label);
    console.log(`  liquidatable=${liq}  isBadDebt=${badDebt}  supply=${sup} borrow=${bor}`);
    console.log(`  collateral_quote=${collAmt}  collateral_present=${collPresent}`);
    console.log(`  cap33=${cap33}  floor$200=${floorUsd}  maxNotTooMuch=${maxNotTooMuch}`);
    console.log(`  -> seizable collateral_reward = ${reward}  (${(Number(reward)/Number(collPresent)*100).toFixed(1)}% of victim collateral)\n`);
  }
}
function min2(a,b){return a<b?a:b;}
function min(a,b,c){return min2(min2(a,b),c);}
main().catch((e)=>{console.error(e);process.exit(1);});
