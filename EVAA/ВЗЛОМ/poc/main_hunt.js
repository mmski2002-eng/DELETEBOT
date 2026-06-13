const https = require('https');
const { Blockchain } = require('@ton/sandbox');
const { TupleBuilder, beginCell, Dictionary } = require('@ton/core');
const { forkAccount } = require('./fork');
const KEY = '9e2ffe1bae3ccdb220f2efa3a352e7857baa07c0cc6d41f574b2721b11a47782';
const MAIN = 'EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr';
const TON_ID = 0x1a4219fe5e60d63af2a3cc7dce6fec69b45c6b5718497a6148e7c232ac87bd8an;
const SCALE = 1e9;

function get(u){return new Promise(r=>{https.get(u,{headers:{'X-API-Key':KEY,accept:'application/json'}},x=>{let d='';x.on('data',c=>d+=c);x.on('end',()=>r(JSON.parse(d)));});});}
function prices(map){const V={serialize:(s,b)=>b.storeCoins(s),parse:s=>s.loadCoins()};const d=Dictionary.empty(Dictionary.Keys.BigUint(256),V);for(const[k,v]of map)d.set(k,BigInt(Math.round(v)));return beginCell().storeDictDirect(d).endCell();}

async function main(){
  // collect MAIN counterparties (a few pages)
  const cps=new Set();let endLt='';
  for(let p=0;p<5;p++){
    let u=`https://toncenter.com/api/v3/transactions?account=${MAIN}&limit=100&sort=desc`; if(endLt)u+=`&end_lt=${endLt}`;
    const j=await get(u);const txs=j.transactions||[];if(!txs.length)break;
    for(const t of txs){if(t.in_msg&&t.in_msg.source)cps.add(t.in_msg.source);for(const o of(t.out_msgs||[]))if(o.destination)cps.add(o.destination);}
    endLt=(BigInt(txs[txs.length-1].lt)-1n).toString();
  }
  console.log('MAIN counterparties sampled:',cps.size);

  const bc=await Blockchain.create();
  const m=await forkAccount(bc,MAIN);
  const cfg=(await bc.runGetMethod(m.address,'getAssetsConfig',[])).stackReader.readCell();
  const dyn=(await bc.runGetMethod(m.address,'getAssetsData',[])).stackReader.readCell();
  const BV={serialize:()=>{},parse:s=>s.loadIntBig(65)};
  const basePrice=id=>(id===TON_ID?3.0:1.0);

  const res=[];let users=0,liqCapable=0;
  for(const a of cps){
    let acc;try{acc=await forkAccount(bc,a);}catch{continue;}
    try{const r=await bc.runGetMethod(acc.address,'isUserSc',[]);if(r.exitCode!==0||r.stackReader.readBigNumber()===0n)continue;}catch{continue;}
    users++;
    let bals;try{const tb=new TupleBuilder();tb.writeCell(dyn);const r=await bc.runGetMethod(acc.address,'getAccountBalances',tb.build());if(r.exitCode!==0)continue;const c=r.stackReader.readCellOpt();if(!c)continue;bals=Dictionary.loadDirect(Dictionary.Keys.BigUint(256),BV,c);}catch{continue;}
    const assets=[];let hasD=false,hasC=false;for(const[k,v]of bals){assets.push([k,v]);if(v<0n)hasD=true;if(v>0n)hasC=true;}
    if(!(hasD&&hasC))continue;
    async function liqAt(f){const map=new Map();for(const[k,v]of assets){let p=basePrice(k)*SCALE;if(v>0n)p*=f;map.set(k,p);}const tb=new TupleBuilder();tb.writeCell(cfg);tb.writeCell(dyn);tb.writeCell(prices(map));const r=await bc.runGetMethod(acc.address,'getIsLiquidable',tb.build());if(r.exitCode!==0)return null;return r.stackReader.readBigNumber()===-1n;}
    const at1=await liqAt(1.0);if(at1===null)continue; // getIsLiquidable not supported -> skip
    liqCapable++;
    if(at1){res.push({a,drop:0,assets,already:true});continue;}
    let lo=0,hi=1;for(let i=0;i<16;i++){const mid=(lo+hi)/2;if(await liqAt(mid))lo=mid;else hi=mid;}
    res.push({a,drop:(1-hi)*100,assets});
  }
  res.sort((x,y)=>x.drop-y.drop);
  console.log(`users=${users} getIsLiquidable-capable=${liqCapable} borrowers=${res.length}\n`);
  console.log('NEAR-THRESHOLD on $1.6M MAIN pool (smallest collateral drop to flip):');
  for(const r of res.slice(0,12)){console.log(`  drop ${r.drop.toFixed(1)}%${r.already?' ALREADY-LIQ':''}  ${r.a}`);for(const[k,v]of r.assets)console.log(`       0x${k.toString(16).slice(0,10)} = ${v}`);}
}
main().catch(e=>{console.error(e);process.exit(1);});
