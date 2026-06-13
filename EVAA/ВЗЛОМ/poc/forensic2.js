const https = require('https');
const { Address, Cell } = require('@ton/core');
const KEY = '9e2ffe1bae3ccdb220f2efa3a352e7857baa07c0cc6d41f574b2721b11a47782';
const MAIN = process.argv[2] || 'EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr';
const PYTH = Address.parse('EQA5NPyjfZztDm8jcTBwTAU9NGsgJEkw19z61yecX0TlseSB').toRawString();
const OPN = { 0x3: 'LIQUIDATE_ton', 0x32: 'LIQUIDATE_jetton', 0x4: 'supply_withdraw', 0x42: 'supply_withdraw_jetton' };

function get(u){return new Promise(r=>{https.get(u,{headers:{'X-API-Key':KEY,accept:'application/json'}},x=>{let d='';x.on('data',c=>d+=c);x.on('end',()=>{try{r(JSON.parse(d))}catch(e){r({})}});});});}

(async () => {
  let endLt = ''; const rows = [];
  for (let p = 0; p < 12; p++) {
    let u = 'https://toncenter.com/api/v3/transactions?account=' + MAIN + '&limit=100&sort=desc';
    if (endLt) u += '&end_lt=' + endLt;
    const j = await get(u); const txs = j.transactions || [];
    if (!txs.length) break;
    for (const t of txs) {
      const im = t.in_msg; if (!im || !im.source) continue;
      let src; try { src = Address.parse(im.source).toRawString(); } catch { continue; }
      if (src !== PYTH) continue;
      const body = im.message_content && im.message_content.body; if (!body) continue;
      try {
        const s = Cell.fromBase64(body).beginParse();
        s.loadUint(32); s.loadUint(8);
        const pf = s.loadRef().beginParse();
        pf.loadUintBig(256);
        const item = pf.loadRef().beginParse().loadRef().beginParse();
        item.loadIntBig(64); item.loadUintBig(64); item.loadInt(32);
        const ts = item.loadUint(64);
        s.loadAddress(); // pyth_sender
        const opPayload = s.loadRef().beginParse();
        const opCode = opPayload.loadUint(32);
        rows.push({ hash: t.hash, now: t.now, lag: t.now - ts, op: opCode });
      } catch (e) {}
    }
    endLt = (BigInt(txs[txs.length - 1].lt) - 1n).toString();
  }
  // classify
  const byOp = {};
  for (const r of rows) { const n = OPN[r.op] || ('0x' + r.op.toString(16)); byOp[n] = byOp[n] || []; byOp[n].push(r.lag); }
  console.log('total Pyth callbacks parsed:', rows.length, '\n');
  for (const [n, lags] of Object.entries(byOp)) {
    lags.sort((a, b) => a - b);
    console.log(`${n.padEnd(22)} count=${lags.length} lag(min/med/max)=${lags[0]}/${lags[Math.floor(lags.length/2)]}/${lags[lags.length-1]}  >30s=${lags.filter(x=>x>30).length} >60s=${lags.filter(x=>x>60).length}`);
  }
  // stale liquidations specifically
  const liqs = rows.filter(r => (r.op === 0x3 || r.op === 0x32));
  const staleLiqs = liqs.filter(r => r.lag > 30).sort((a, b) => b.lag - a.lag);
  console.log(`\nLIQUIDATIONS: ${liqs.length} total, ${staleLiqs.length} with price age >30s:`);
  for (const r of staleLiqs.slice(0, 20)) console.log(`  lag=${r.lag}s  op=${OPN[r.op]}  tx=${r.hash}`);
})();
