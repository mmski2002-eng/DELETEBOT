const https = require('https');
const { Blockchain } = require('@ton/sandbox');
const { TupleBuilder, beginCell, Dictionary, Address } = require('@ton/core');
const { forkAccount, fetchAccount } = require('./fork');
const KEY = '9e2ffe1bae3ccdb220f2efa3a352e7857baa07c0cc6d41f574b2721b11a47782';
const MAIN = 'EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr';
const SCALE = 1e9;
function get(u,h){return new Promise(r=>{https.get(u,{headers:Object.assign({'User-Agent':'x',accept:'application/json'},h||{})},x=>{let d='';x.on('data',c=>d+=c);x.on('end',()=>{try{r(JSON.parse(d))}catch(e){r({})}});});});}

async function feedMap() {
  // MAIN data -> ref2 market_config -> dict, int8, addr, ref oracles_config -> addr, ref feeds_data
  const acc = await fetchAccount(MAIN);
  const root = acc.data.beginParse();
  root.loadRef(); root.loadRef();
  const mc = root.loadRef().beginParse();
  mc.loadMaybeRef(); mc.loadInt(8); mc.loadAddress();
  const oc = mc.loadRef().beginParse();
  oc.loadAddress(); // pyth
  const fd = oc.loadRef().beginParse();
  const pythToEvaa = fd.loadDict(Dictionary.Keys.BigUint(256), { serialize:()=>{}, parse:s=>s.loadUintBig(256) });
  return pythToEvaa; // pyth_feed_id -> evaa_asset_id
}

async function hermesLatest(feedHexes) {
  const ids = feedHexes.map(h=>'ids[]='+h).join('&');
  const j = await get('https://hermes.pyth.network/v2/updates/price/latest?'+ids+'&parsed=true');
  const out = {};
  for (const p of (j.parsed||[])) out['0x'+p.id.toLowerCase()] = Number(p.price.price)*Math.pow(10,p.price.expo);
  return out;
}

async function main() {
  const map = await feedMap();
  const pythIds = [...map.keys()];
  const feedHexes = pythIds.map(id=>id.toString(16).padStart(64,'0'));
  const usd = await hermesLatest(feedHexes);
  // build evaa_asset -> real price (1e9 scaled)
  const evaaPrice = new Map();
  for (const pid of pythIds) {
    const evaaId = map.get(pid);
    const hex = '0x'+pid.toString(16).padStart(64,'0');
    if (usd[hex] != null) evaaPrice.set(evaaId, usd[hex]);
  }
  console.log('assets with real price:', evaaPrice.size);
  for (const [k,v] of evaaPrice) console.log('  0x'+k.toString(16).slice(0,10)+' = $'+v.toFixed(4));

  // sample MAIN positions
  const cps=new Set();let endLt='';
  for(let p=0;p<15;p++){let u='https://toncenter.com/api/v3/transactions?account='+MAIN+'&limit=100&sort=desc';if(endLt)u+='&end_lt='+endLt;const j=await get(u,{'X-API-Key':KEY});const txs=j.transactions||[];if(!txs.length)break;for(const t of txs){if(t.in_msg&&t.in_msg.source)cps.add(t.in_msg.source);for(const o of(t.out_msgs||[]))if(o.destination)cps.add(o.destination);}endLt=(BigInt(txs[txs.length-1].lt)-1n).toString();}

  const bc=await Blockchain.create();const m=await forkAccount(bc,MAIN);
  const cfg=(await bc.runGetMethod(m.address,'getAssetsConfig',[])).stackReader.readCell();
  const dyn=(await bc.runGetMethod(m.address,'getAssetsData',[])).stackReader.readCell();
  const BV={serialize:()=>{},parse:s=>s.loadIntBig(65)};
  function pricesCell(scaleColl){const V={serialize:(s,b)=>b.storeCoins(s),parse:s=>s.loadCoins()};const d=Dictionary.empty(Dictionary.Keys.BigUint(256),V);for(const[k,v]of evaaPrice)d.set(k,BigInt(Math.round(v*SCALE)));return d;}

  const res=[];
  for(const a of cps){let acc;try{acc=await forkAccount(bc,a);}catch{continue;}
    try{const r=await bc.runGetMethod(acc.address,'isUserSc',[]);if(r.exitCode!==0||r.stackReader.readBigNumber()===0n)continue;}catch{continue;}
    let bals;try{const tb=new TupleBuilder();tb.writeCell(dyn);const r=await bc.runGetMethod(acc.address,'getAccountBalances',tb.build());if(r.exitCode!==0)continue;const c=r.stackReader.readCellOpt();if(!c)continue;bals=Dictionary.loadDirect(Dictionary.Keys.BigUint(256),BV,c);}catch{continue;}
    const assets=[];let hasD=false,hasC=false;for(const[k,v]of bals){assets.push([k,v]);if(v<0n)hasD=true;if(v>0n)hasC=true;}
    if(!(hasD&&hasC))continue;
    // all assets must have a price
    let priced=true;for(const[k,v]of assets)if(!evaaPrice.has(k))priced=false;
    async function liqAt(f){const V={serialize:(s,b)=>b.storeCoins(s),parse:s=>s.loadCoins()};const d=Dictionary.empty(Dictionary.Keys.BigUint(256),V);for(const[k,v]of evaaPrice){let p=v*SCALE;if(assets.find(x=>x[0]===k&&x[1]>0n))p*=f;d.set(k,BigInt(Math.round(p)));}const pr=beginCell().storeDictDirect(d).endCell();const tb=new TupleBuilder();tb.writeCell(cfg);tb.writeCell(dyn);tb.writeCell(pr);const r=await bc.runGetMethod(acc.address,'getIsLiquidable',tb.build());if(r.exitCode!==0)return null;return r.stackReader.readBigNumber()===-1n;}
    const at1=await liqAt(1.0);if(at1===null)continue;
    if(at1){res.push({a,drop:0,assets,already:true,priced});continue;}
    let lo=0,hi=1;for(let i=0;i<16;i++){const mid=(lo+hi)/2;if(await liqAt(mid))lo=mid;else hi=mid;}
    res.push({a,drop:(1-hi)*100,assets,priced});
  }
  res.sort((x,y)=>x.drop-y.drop);
  console.log(`\nMAIN borrowers (priced): ${res.length}. Ranked by REAL collateral-drop-to-flip (buffer):`);
  for(const r of res.slice(0,20)){
    console.log(`  buffer ${r.drop.toFixed(1)}%${r.already?' ALREADY-LIQ':''}${r.priced?'':' (unpriced!)'}  ${r.a.slice(0,18)}`);
    if(r.already||r.drop<10){for(const[k,v]of r.assets){const px=evaaPrice.get(k);const usd=px?(Number(v)/1e9*px):null;console.log(`        0x${k.toString(16).slice(0,10)} = ${v}${usd!=null?(' (~$'+usd.toFixed(2)+')'):''}`);}}
  }
  const thin=res.filter(r=>!r.already&&r.drop<5).length;
  console.log(`\nsurvivor positions with buffer <5% (realistically exploitable by a 2-5% wick): ${thin}`);
}
main().catch(e=>{console.error(e);process.exit(1);});
