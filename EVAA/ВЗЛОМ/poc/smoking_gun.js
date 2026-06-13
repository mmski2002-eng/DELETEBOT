const https = require('https');
const { Address, Cell } = require('@ton/core');
const KEY = '9e2ffe1bae3ccdb220f2efa3a352e7857baa07c0cc6d41f574b2721b11a47782';
const MAIN = 'EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr';
const data = require('./forensic_main.json');

function get(u){return new Promise(r=>{https.get(u,{headers:{'X-API-Key':KEY,accept:'application/json'}},x=>{let d='';x.on('data',c=>d+=c);x.on('end',()=>{try{r(JSON.parse(d))}catch(e){r({})}});});});}
function parseFeeds(pf){const feeds=[];let cur=pf;while(cur){const s=cur.beginParse();const id=s.loadUintBig(256);const item=s.loadRef().beginParse().loadRef().beginParse();const price=item.loadIntBig(64);item.loadUintBig(64);const expo=item.loadInt(32);const ts=item.loadUint(64);feeds.push({id,p:Number(price)*Math.pow(10,expo),ts});cur=s.remainingRefs>0?s.loadRef():null;}return feeds;}
async function hermesAt(idHex,ts){const h=await get('https://hermes.pyth.network/v2/updates/price/'+ts+'?ids[]='+idHex+'&parsed=true');const pp=h.parsed&&h.parsed[0]&&h.parsed[0].price;return pp?Number(pp.price)*Math.pow(10,pp.expo):null;}

(async()=>{
  const staleLiqs = data.liqs.filter(r => r.lag > 30).sort((a,b)=>b.lag-a.lag);
  console.log('checking', staleLiqs.length, 'liquidations with price age >30s for price movement during staleness window\n');
  let flagged = 0;
  for (const r of staleLiqs) {
    const j = await get('https://toncenter.com/api/v3/transactions?account='+MAIN+'&hash='+encodeURIComponent(r.hash)+'&limit=1');
    const t = (j.transactions||[])[0]; if (!t || !t.in_msg.message_content) continue;
    let feeds; try { const s=Cell.fromBase64(t.in_msg.message_content.body).beginParse(); s.loadUint(32); s.loadUint(8); feeds=parseFeeds(s.loadRef()); } catch { continue; }
    // for each feed: used price (at publish_ts) vs hermes price at tx.now (fresher-if-exists)
    let maxMovePct = 0, worst = null;
    for (const f of feeds) {
      const idHex = f.id.toString(16).padStart(64,'0');
      const freshNow = await hermesAt(idHex, t.now);
      if (freshNow && f.p) {
        const movePct = Math.abs(freshNow - f.p) / f.p * 100;
        if (movePct > maxMovePct) { maxMovePct = movePct; worst = { id: idHex.slice(0,10), used: f.p, fresh: freshNow }; }
      }
    }
    const flag = maxMovePct > 1.0;
    if (flag) flagged++;
    console.log(`${flag?'**FLAG**':'  ok  '} lag=${r.lag}s maxMove=${maxMovePct.toFixed(2)}% ${worst?('feed 0x'+worst.id+' used=$'+worst.used.toFixed(4)+' fresh=$'+worst.fresh.toFixed(4)):''}  tx=${r.hash.slice(0,12)}`);
  }
  console.log(`\nflagged (price moved >1% during staleness window): ${flagged} of ${staleLiqs.length}`);
})();
