const https = require('https');
const fs = require('fs');
const { Address, Cell } = require('@ton/core');
const KEY = '9e2ffe1bae3ccdb220f2efa3a352e7857baa07c0cc6d41f574b2721b11a47782';
const MAIN = process.argv[2] || 'EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr';
const OUT = process.argv[3] || 'forensic_main.json';
const PYTH = Address.parse('EQA5NPyjfZztDm8jcTBwTAU9NGsgJEkw19z61yecX0TlseSB').toRawString();
const sleep = ms => new Promise(r => setTimeout(r, ms));
function get(u){return new Promise(r=>{https.get(u,{headers:{'X-API-Key':KEY,accept:'application/json'}},x=>{let d='';x.on('data',c=>d+=c);x.on('end',()=>{try{r(JSON.parse(d))}catch(e){r({})}});});});}

(async () => {
  let endLt = '', page = 0, total = 0, callbacks = 0;
  const liqs = []; const staleSW = []; // liquidations(all), stale supply/withdraw(>30s)
  while (true) {
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
        s.loadAddress();
        const opCode = s.loadRef().beginParse().loadUint(32);
        callbacks++;
        const lag = t.now - ts;
        if (opCode === 0x3 || opCode === 0x32) liqs.push({ hash: t.hash, now: t.now, lag, op: opCode });
        else if (lag > 30) staleSW.push({ hash: t.hash, now: t.now, lag, op: opCode });
      } catch (e) {}
    }
    total += txs.length; page++;
    endLt = (BigInt(txs[txs.length - 1].lt) - 1n).toString();
    if (page % 20 === 0) console.error('page', page, 'txs', total, 'callbacks', callbacks, 'liqs', liqs.length, 'staleSW', staleSW.length);
    await sleep(100);
    if (page > 600) break;
  }
  liqs.sort((a, b) => b.lag - a.lag);
  staleSW.sort((a, b) => b.lag - a.lag);
  fs.writeFileSync(__dirname + '/' + OUT, JSON.stringify({ total, callbacks, liqs, staleSW }, null, 0));
  console.error('DONE txs', total, 'callbacks', callbacks, 'liquidations', liqs.length, 'staleSW', staleSW.length);
  console.error('stalest liquidations:', liqs.slice(0, 10).map(r => r.lag + 's').join(', '));
})();
