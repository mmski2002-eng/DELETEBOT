const { Blockchain, createShardAccount } = require('@ton/sandbox');
const { Cell, beginCell, contractAddress, Dictionary, toNano } = require('@ton/core');
const fs = require('fs');

const PRICES_INCORRECT_TIMESTAMP = 0x50Fe; // 20734
const PRICES_NOT_POSITIVE = 0x50F6;

const U256 = {
  serialize: (src, b) => b.storeUint(src, 256),
  parse: (s) => s.loadUintBig(256),
};

function feedsData(pythId, evaaId) {
  const map = Dictionary.empty(Dictionary.Keys.BigUint(256), U256);
  map.set(pythId, evaaId);
  const refs = Dictionary.empty(Dictionary.Keys.BigUint(256), U256); // evaa_refs: empty
  return beginCell().storeDict(map).storeDict(refs).endCell();
}

// matches parse_pyth_price_data + unpack_pyth_data_item parsing
function priceFeeds(pythId, price, conf, expo, ts) {
  const item = beginCell()
    .storeInt(price, 64)   // price
    .storeUint(conf, 64)   // conf
    .storeInt(expo, 32)    // expo
    .storeUint(ts, 64)     // timestamp (publish_time)
    .endCell();
  const priceData = beginCell().storeRef(item).endCell();
  return beginCell().storeUint(pythId, 256).storeRef(priceData).endCell();
}

async function main() {
  const bc = await Blockchain.create();
  const code = Cell.fromBase64(fs.readFileSync(__dirname + '/stale_test.boc.base64', 'utf8'));
  const data = beginCell().endCell();
  const address = contractAddress(0, { code, data });
  await bc.setShardAccount(address, createShardAccount({ address, code, data, balance: toNano('1'), workchain: 0 }));

  const T = 1900000000;
  bc.now = T;

  const pythId = 0x1234n;
  const evaaId = 0xabcdn;
  const TTL = 180n;

  const cases = [
    ['fresh   (age 0s,   within TTL)', 0],
    ['stale   (age 120s, within TTL 180)', 120],
    ['stale   (age 179s, within TTL 180)', 179],
    ['expired (age 200s, beyond TTL 180)', 200],
  ];

  console.log(`now()=${T}, prices_ttl=${TTL}`);
  console.log(`expect: err=0 accepted | err=0x50fe(${PRICES_INCORRECT_TIMESTAMP}) rejected-stale\n`);

  for (const [label, age] of cases) {
    const pf = priceFeeds(pythId, 500000000n, 1000n, -8, BigInt(T - age));
    const fd = feedsData(pythId, evaaId);
    const r = await bc.runGetMethod(address, 'test_parse_check', [
      { type: 'cell', cell: pf },
      { type: 'cell', cell: fd },
      { type: 'int', value: TTL },
    ]);
    const err = r.stackReader.readBigNumber();
    const verdict = err === 0n ? 'ACCEPTED' : (Number(err) === PRICES_INCORRECT_TIMESTAMP ? 'REJECTED(stale)' : 'OTHER');
    console.log(`${label.padEnd(38)} -> err=${err} (0x${err.toString(16)}) vmExit=${r.exitCode} gas=${r.gasUsed}  [${verdict}]`);
  }
}
main().catch((e) => { console.error(e); process.exit(1); });
