const https = require('https');
const fs = require('fs');
const KEY = '9e2ffe1bae3ccdb220f2efa3a352e7857baa07c0cc6d41f574b2721b11a47782';
const MASTER = process.argv[2] || 'EQCsOdQPDO1Xndzutn9dDcloolWo1wHKICMz2jHL6UP8smcV';
const OUT = process.argv[3] || 'positions.json';

function get(u) {
  return new Promise((res) => {
    https.get(u, { headers: { 'X-API-Key': KEY, accept: 'application/json' } }, (r) => {
      let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d }));
    }).on('error', e => res({ s: 0, d: e.message }));
  });
}
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

(async () => {
  const counterparties = new Set();
  const liquidations = []; // {lt, now, op, src} for forensic
  let endLt = '';
  let total = 0, page = 0;
  while (true) {
    let url = `https://toncenter.com/api/v3/transactions?account=${MASTER}&limit=100&sort=desc`;
    if (endLt) url += `&end_lt=${endLt}`;
    const r = await get(url);
    if (r.s !== 200) { console.error('http', r.s, r.d.slice(0, 120)); await sleep(1000); continue; }
    let j; try { j = JSON.parse(r.d); } catch { break; }
    const txs = j.transactions || [];
    if (!txs.length) break;
    for (const tx of txs) {
      const inOp = tx.in_msg && tx.in_msg.opcode;
      const src = tx.in_msg && tx.in_msg.source;
      if (src) counterparties.add(src);
      for (const om of (tx.out_msgs || [])) if (om.destination) counterparties.add(om.destination);
      // liquidate ops: 0x0000041f liquidate_master_jetton? track liquidate-related opcodes seen
      if (inOp) {
        // record any tx for forensic; tag liquidations by opcode later
        if (['0x6ec6ee8f','0x00000003','0x0000041f','0x00000411'].includes(inOp)) {
          liquidations.push({ lt: tx.lt, now: tx.now, op: inOp, src });
        }
      }
    }
    total += txs.length; page++;
    endLt = (BigInt(txs[txs.length - 1].lt) - 1n).toString();
    if (page % 10 === 0) console.error(`page ${page} total ${total} cps ${counterparties.size}`);
    await sleep(120);
    if (page > 400) { console.error('cap reached'); break; }
  }
  fs.writeFileSync(__dirname + '/' + OUT, JSON.stringify({ counterparties: [...counterparties], liquidations, total }, null, 0));
  console.error(`DONE total_txs=${total} counterparties=${counterparties.size} liq_tagged=${liquidations.length}`);
})();
