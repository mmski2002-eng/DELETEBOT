const https = require('https');
const { Address, Cell } = require('@ton/core');
const KEY = '9e2ffe1bae3ccdb220f2efa3a352e7857baa07c0cc6d41f574b2721b11a47782';
const HASH = process.argv[2];
const MAIN = 'EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr';

function get(u){return new Promise(r=>{https.get(u,{headers:{'X-API-Key':KEY,accept:'application/json'}},x=>{let d='';x.on('data',c=>d+=c);x.on('end',()=>{try{r(JSON.parse(d))}catch(e){r({})}});});});}

function parseFeeds(pf) {
  // walk chained price_feeds_cell: [uint256 id, ref price_data{ref item}, (last ref = next)]
  const feeds = [];
  let cur = pf;
  while (cur) {
    const s = cur.beginParse();
    const id = s.loadUintBig(256);
    const item = s.loadRef().beginParse().loadRef().beginParse();
    const price = item.loadIntBig(64); const conf = item.loadUintBig(64); const expo = item.loadInt(32); const ts = item.loadUint(64);
    feeds.push({ id, price, expo, ts });
    cur = s.remainingRefs > 0 ? s.loadRef() : null;
  }
  return feeds;
}

(async () => {
  const j = await get('https://toncenter.com/api/v3/transactions?account=' + MAIN + '&hash=' + encodeURIComponent(HASH) + '&limit=1');
  const t = (j.transactions || [])[0];
  if (!t) { console.log('tx not found'); return; }
  const im = t.in_msg;
  const body = im.message_content.body;
  const s = Cell.fromBase64(body).beginParse();
  s.loadUint(32); s.loadUint(8);
  const feeds = parseFeeds(s.loadRef());
  s.loadAddress();
  const op = s.loadRef().beginParse(); const opCode = op.loadUint(32); const qid = op.loadUint(64);
  console.log('tx now=' + t.now, new Date(t.now * 1000).toISOString(), 'op=0x' + opCode.toString(16), 'qid=' + qid);
  console.log('prices used in this liquidation:');
  for (const f of feeds) {
    const realPrice = Number(f.price) * Math.pow(10, f.expo);
    console.log('  pythId 0x' + f.id.toString(16).slice(0, 16) + '  price=$' + realPrice.toFixed(4) + '  publish_ts=' + f.ts + ' (age ' + (t.now - f.ts) + 's)');
  }
  // Hermes: real price at publish_ts vs at tx.now for each feed
  console.log('\nHermes real price then vs at-execution:');
  for (const f of feeds) {
    const idHex = f.id.toString(16).padStart(64, '0');
    for (const [lbl, ts] of [['used_publish', f.ts], ['at_tx_now', t.now]]) {
      const h = await get('https://hermes.pyth.network/v2/updates/price/' + ts + '?ids[]=' + idHex + '&parsed=true');
      const pp = h.parsed && h.parsed[0] && h.parsed[0].price;
      if (pp) console.log('  0x' + idHex.slice(0, 12) + ' @' + lbl + '=' + ts + ' -> $' + (Number(pp.price) * Math.pow(10, pp.expo)).toFixed(4));
    }
  }
})();
