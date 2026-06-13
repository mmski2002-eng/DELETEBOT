const { fetchAccount } = require('./fork');
const { Address, TupleBuilder } = require('@ton/core');
const { Blockchain } = require('@ton/sandbox');
const https = require('https');

const MAIN = 'EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr';
const TON_ID = 0x1a4219fe5e60d63af2a3cc7dce6fec69b45c6b5718497a6148e7c232ac87bd8an;
const SCALE = 1e9;

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
    try { return (require('@ton/core').Cell).fromBoc(Buffer.from(c, 'hex'))[0]; } catch (e) {}
  }
  return (require('@ton/core').Cell).fromBase64(data);
}

async function findUsers() {
  const a = Address.parse(MAIN).toString({ urlSafe: true, bounceable: true });
  const r = await httpGet(`https://tonapi.io/v2/blockchain/accounts/${a}/transactions?limit=100`);
  const j = JSON.parse(r.d);
  const txs = j.transactions || [];
  const users = new Set();
  for (const tx of txs) {
    if (tx.in_msg && tx.in_msg.source && tx.in_msg.source.address) users.add(tx.in_msg.source.address);
    for (const om of (tx.out_msgs || [])) {
      if (om.destination && om.destination.address) users.add(om.destination.address);
    }
  }
  return [...users];
}

async function main() {
  const bc = await Blockchain.create();
  const m = await fetchAccount(MAIN);
  await bc.setShardAccount(m.address, require('@ton/sandbox').createShardAccount({
    address: m.address, code: m.code, data: m.data, balance: m.balance > 10n**9n ? m.balance : 10n**9n, workchain: 0,
  }));
  console.log('MAIN forked. code hash:', m.code.hash().toString('hex'));

  const cfg = (await bc.runGetMethod(m.address, 'getAssetsConfig', [])).stackReader.readCell();
  const dyn = (await bc.runGetMethod(m.address, 'getAssetsData', [])).stackReader.readCell();

  // Get the asset ID for TON
  const tonAssetId = TON_ID;
  
  // Find users from tx history
  const candidates = await findUsers();
  console.log(`Found ${candidates.length} candidate addresses`);

  const results = [];
  for (const addrStr of candidates.slice(0, 30)) {
    let acc;
    try {
      acc = await fetchAccount(addrStr);
    } catch (e) {
      continue;
    }
    // Try running get-methods on user SC
    try {
      const ru = await bc.runGetMethod(acc.address, 'isUserSc', []);
      if (ru.exitCode !== 0 || ru.stackReader.readBigNumber() === 0n) continue;
    } catch (e) {
      continue;
    }
    console.log(`  User SC found: ${addrStr}`);

    // Get user's principals
    let bals;
    try {
      const tb = new TupleBuilder();
      tb.writeCell(dyn);
      const rr = await bc.runGetMethod(acc.address, 'getAccountBalances', tb.build());
      if (rr.exitCode !== 0) continue;
      const c = rr.stackReader.readCellOpt();
      if (!c) continue;
      const BV = { serialize: () => {}, parse: (s) => s.loadIntBig(65) };
      bals = (require('@ton/core').Dictionary).loadDirect(
        (require('@ton/core').Dictionary).Keys.BigUint(256), BV, c
      );
    } catch (e) {
      continue;
    }

    // Check if user has both collateral and debt
    let hasDebt = false, hasColl = false;
    const assets = [];
    for (const [k, v] of bals) {
      assets.push([k, v]);
      if (v < 0n) hasDebt = true;
      if (v > 0n) hasColl = true;
    }
    if (!(hasDebt && hasColl)) continue;

    // Simple test: fresh price vs stale price
    const basePrice = (id) => id === tonAssetId ? 3.0 : 1.0;
    
    async function testLiq(multiplier) {
      const { Dictionary, beginCell } = require('@ton/core');
      const V = { serialize: (s, b) => b.storeCoins(s), parse: (s) => s.loadCoins() };
      const d = Dictionary.empty(Dictionary.Keys.BigUint(256), V);
      for (const [k, v] of assets) {
        let p = basePrice(k) * SCALE;
        if (v > 0n) p *= multiplier; // depress collateral price
        d.set(k, BigInt(Math.round(p)));
      }
      const pr = beginCell().storeDictDirect(d).endCell();
      const tb = new TupleBuilder();
      tb.writeCell(cfg);
      tb.writeCell(dyn);
      tb.writeCell(pr);
      const r = await bc.runGetMethod(acc.address, 'getIsLiquidable', tb.build());
      return r.exitCode === 0 && r.stackReader.readBigNumber() === -1n;
    }

    const freshLiq = await testLiq(1.0);
    if (freshLiq) continue; // already liquidatable at fresh price
    
    const staleLiq = await testLiq(0.5); // 50% collateral price
    if (staleLiq) {
      console.log(`  >>> FRESH=healthy, STALE(-50%)=LIQUIDATABLE!`);
      results.push({ addr: addrStr, assets, dropPct: 50 });
    } else {
      console.log(`  Fresh=healthy, Stale(-50%)=still healthy (needs bigger drop)`);
    }
  }
  
  console.log(`\n=== RESULTS ===`);
  console.log(`Total vulnerable positions found (50% drop): ${results.length}`);
  if (results.length > 0) {
    for (const r of results) {
      console.log(`  ${r.addr} - need ${r.dropPct}% drop`);
      for (const [k, v] of r.assets) {
        console.log(`    asset 0x${k.toString(16).slice(0,12)}... = ${v}`);
      }
    }
  }
}

main().catch(e => { console.error(e); process.exit(1); });
