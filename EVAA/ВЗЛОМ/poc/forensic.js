const https = require('https');
const { Address, Cell } = require('@ton/core');
const KEY = '9e2ffe1bae3ccdb220f2efa3a352e7857baa07c0cc6d41f574b2721b11a47782';
const MAIN = process.argv[2] || 'EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr';
const PYTH = Address.parse('EQA5NPyjfZztDm8jcTBwTAU9NGsgJEkw19z61yecX0TlseSB').toRawString();

function get(u){return new Promise(r=>{https.get(u,{headers:{'X-API-Key':KEY,accept:'application/json'}},x=>{let d='';x.on('data',c=>d+=c);x.on('end',()=>{try{r(JSON.parse(d))}catch(e){r({})}});});});}

(async () => {
  let endLt = '', checked = 0; const lags = [];
  for (let p = 0; p < 10; p++) {
    let u = 'https://toncenter.com/api/v3/transactions?account=' + MAIN + '&limit=100&sort=desc';
    if (endLt) u += '&end_lt=' + endLt;
    const j = await get(u); const txs = j.transactions || [];
    if (!txs.length) break;
    for (const t of txs) {
      const im = t.in_msg; if (!im || !im.source) continue;
      let src; try { src = Address.parse(im.source).toRawString(); } catch { continue; }
      if (src !== PYTH) continue;
      checked++;
      const body = im.message_content && im.message_content.body; if (!body) continue;
      try {
        const s = Cell.fromBase64(body).beginParse();
        s.loadUint(32); // op
        s.loadUint(8);  // num_price_feeds
        const pf = s.loadRef().beginParse(); // price_feeds_cell
        pf.loadUintBig(256); // pyth feed id
        const pdata = pf.loadRef().beginParse();
        const item = pdata.loadRef().beginParse();
        item.loadIntBig(64); item.loadUintBig(64); item.loadInt(32);
        const ts = item.loadUint(64); // publish_time
        lags.push(t.now - ts);
      } catch (e) {}
    }
    endLt = (BigInt(txs[txs.length - 1].lt) - 1n).toString();
  }
  lags.sort((a, b) => a - b);
  console.log('Pyth->master callbacks seen:', checked, '| price-ts parsed:', lags.length);
  if (lags.length) {
    const med = lags[Math.floor(lags.length / 2)];
    console.log('price age at use (tx.now - publish_time), seconds:');
    console.log('  min', lags[0], 'median', med, 'max', lags[lags.length - 1]);
    console.log('  >30s:', lags.filter(x => x > 30).length, '>60s:', lags.filter(x => x > 60).length, '>120s:', lags.filter(x => x > 120).length, 'of', lags.length);
    console.log('  sample lags:', lags.slice(0, 25).join(','));
  }
})();
