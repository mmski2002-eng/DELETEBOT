'use strict';
// Faithful numeric port of torch-dex-contract/contracts/pools/algorithms/curve_algorithm.fc
// Goal: test whether imbalanced add_liquidity fee deviation lets a round-trip
// (deposit one coin -> withdraw_one other coin) extract value vs a direct swap.

const PRECISION      = 10n ** 18n;
const MUL_PRECISION  = 10n ** 36n;
const A_PRECISION    = 100n;
const FEE_DENOMINATOR= 10n ** 10n;

// pool params (2-coin, 18-decimals each)
const N = 2n;
const DEC = [PRECISION, PRECISION];                 // decimal_tuple = 1e18
const RATES = DEC.map(d => MUL_PRECISION / d);      // = 1e18  (get_rates_tuple)
const AMP = 2000n;                                  // amp already *A_PRECISION (A=20)
const FEE_NUM = 4_000_000n;                          // 0.04% in 1e10 denom (typical curve)
const ADMIN_FEE_NUM = 5_000_000_000n;               // 50% admin (irrelevant to user delta)

function muldiv(a,b,c){ return (a*b)/c; }           // floor, matches FunC muldiv for positives

function xp_mem(bal){ return bal.map((b,i)=> muldiv(RATES[i], b, PRECISION)); }

function get_d(_xp, amp){
  let sum=0n; for(const x of _xp) sum+=x;
  if(sum===0n) return 0n;
  let d=sum; const ann=amp*N;
  for(let it=0; it<255; it++){
    let d_p=d;
    for(let i=0;i<Number(N);i++){ d_p = muldiv(d_p, d, (_xp[i]*N)); }
    const d_prev=d;
    const numerator = muldiv(ann,sum,A_PRECISION) + d_p*N;
    const denominator = muldiv((ann-A_PRECISION),d,A_PRECISION) + (N+1n)*d_p;
    d = muldiv(numerator, d, denominator);
    if(d>d_prev){ if(d-d_prev<=1n) return d; } else { if(d_prev-d<=1n) return d; }
  }
  throw new Error('no D');
}

function get_y(i,j,x,_xp,amp){
  const d=get_d(_xp,amp); const ann=amp*N;
  let c=d, sum=0n, _x=0n;
  for(let k=0;k<Number(N);k++){
    if(k!==j){
      _x = (k===i)? x : _xp[k];
      sum+=_x; c=muldiv(c,d,(_x*N));
    }
  }
  c=muldiv(c, d*A_PRECISION, (ann*N));
  const b=sum+muldiv(d,A_PRECISION,ann);
  let y=d;
  for(let it=0;it<255;it++){
    const y_prev=y;
    y=(y*y+c)/(2n*y+b-d);
    if(y>y_prev){ if(y-y_prev<=1n) return y; } else { if(y_prev-y<=1n) return y; }
  }
  throw new Error('no Y');
}
function get_y_d(amp,i,_xp,d){
  const ann=amp*N; let c=d,sum=0n,_x=0n;
  for(let k=0;k<Number(N);k++){
    if(k!==i){ _x=_xp[k]; sum+=_x; c=muldiv(c,d,(_x*N)); }
  }
  c=muldiv(c,d*A_PRECISION,(ann*N));
  const b=sum+muldiv(d,A_PRECISION,ann);
  let y=d;
  for(let it=0;it<255;it++){
    const y_prev=y; y=(y*y+c)/(2n*y+b-d);
    if(y>y_prev){ if(y-y_prev<=1n) return y; } else { if(y_prev-y<=1n) return y; }
  }
  throw new Error('no Yd');
}

// ---- TORCH get_fee (exact port) ----
function torch_deposit(reserve, targets, lp_supply, amp){
  const d_0=get_d(xp_mem(reserve),amp);
  const new_res = reserve.map((r,i)=> r+targets[i]);
  const d_1=get_d(xp_mem(new_res),amp);
  if(!(d_1>d_0)) throw new Error('invalid liq');
  if(lp_supply===0n){ return {mint:d_1, reserve:new_res, lp: d_1}; }
  const fee = FEE_NUM * N / (4n*(N-1n)); // fee_deposit
  // get_fee
  const rates=RATES, decimals=DEC;
  let inv_rate_sum=0n;
  for(let j=0;j<Number(N);j++){ inv_rate_sum += muldiv(MUL_PRECISION,PRECISION,(rates[j]*decimals[j])); }
  const newReserves=[...new_res];
  for(let i=0;i<Number(N);i++){
    const decimals_i=decimals[i];
    const deposit_i=targets[i];
    const old_reserve=reserve[i];
    const inv_rate_i=muldiv(MUL_PRECISION,PRECISION,(rates[i]*decimals_i));
    const ideal=muldiv(d_1, inv_rate_i, muldiv(inv_rate_sum,PRECISION,decimals_i));
    const needed = (ideal-old_reserve>0n)? (ideal-old_reserve):0n;
    const difference = deposit_i - (deposit_i<needed?deposit_i:needed);
    const fee_for_reserve = muldiv(difference,fee,FEE_DENOMINATOR);
    newReserves[i] = newReserves[i]-fee_for_reserve;
  }
  const d_2=get_d(xp_mem(newReserves),amp);
  const mint=muldiv(lp_supply,(d_2-d_0),d_0);
  return {mint, reserve:newReserves /* note: admin fee omitted */, lp: lp_supply+mint, d_0,d_1,d_2};
}

// ---- CURVE reference get_fee (proportional ideal, abs difference) ----
function curve_deposit(reserve, targets, lp_supply, amp){
  const d_0=get_d(xp_mem(reserve),amp);
  const new_res = reserve.map((r,i)=> r+targets[i]);
  const d_1=get_d(xp_mem(new_res),amp);
  const fee = FEE_NUM * N / (4n*(N-1n));
  const newReserves=[...new_res];
  for(let i=0;i<Number(N);i++){
    const ideal = muldiv(d_1, reserve[i], d_0);        // proportional to OLD balances
    let diff = ideal - new_res[i]; if(diff<0n) diff=-diff; // abs
    const fee_i = muldiv(diff, fee, FEE_DENOMINATOR);
    newReserves[i]=new_res[i]-fee_i;
  }
  const d_2=get_d(xp_mem(newReserves),amp);
  const mint=muldiv(lp_supply,(d_2-d_0),d_0);
  return {mint};
}

function torch_swap(reserve, i, j, amount_in, amp){
  const xp=xp_mem(reserve);
  const x = xp[i] + muldiv(amount_in, RATES[i], PRECISION);
  const y = get_y(i,j,x,xp,amp);
  let dy = xp[j]-y-1n;
  const dy_fee = muldiv(dy, FEE_NUM, FEE_DENOMINATOR);
  dy = muldiv((dy-dy_fee), PRECISION, RATES[j]);
  return dy;
}

function torch_withdraw_one(reserve, remove_lp, token_out, lp_supply, amp){
  const xp=xp_mem(reserve);
  const d_0=get_d(xp,amp);
  const d_1=d_0 - muldiv(remove_lp,d_0,lp_supply);
  const new_y=get_y_d(amp,token_out,xp,d_1);
  const remove_fee = FEE_NUM * N / (4n*(N-1n));
  const xp_reduced=[...xp];
  for(let i=0;i<Number(N);i++){
    let dx_expected;
    if(i===token_out) dx_expected = muldiv(xp[i],d_1,d_0)-new_y;
    else dx_expected = xp[i]-muldiv(xp[i],d_1,d_0);
    const xp_fee=muldiv(dx_expected,remove_fee,FEE_DENOMINATOR);
    xp_reduced[i]=xp[i]-xp_fee;
  }
  let d_y = xp_reduced[token_out]-get_y_d(amp,token_out,xp_reduced,d_1);
  d_y = muldiv(d_y-1n, PRECISION, RATES[token_out]);
  return d_y;
}

// ===== Scenarios =====
const PR = (x)=> (Number(x)/1e18).toFixed(4);

function scenario(label, reserve, targets, withdrawCoin){
  const lp = get_d(xp_mem(reserve), AMP);
  const t = torch_deposit(reserve, targets, lp, AMP);
  const c = curve_deposit(reserve, targets, lp, AMP);
  console.log(`\n===== ${label} =====`);
  console.log('reserves', reserve.map(PR).join(' / '), ' deposit', targets.map(PR).join(' / '));
  console.log('Torch mint_lp:', PR(t.mint), ' Curve mint_lp:', PR(c.mint),
              ' excess:', (Number(t.mint-c.mint)/Number(c.mint)*100).toFixed(4),'%');
  // round-trip: deposit -> withdraw_one(withdrawCoin)
  const lpAfter = lp + t.mint;
  const dyRT = torch_withdraw_one(t.reserve, t.mint, withdrawCoin, lpAfter, AMP);
  const inIdx = targets[0]>0n?0:1;
  const inAmt = targets[inIdx];
  const dySwap = (inIdx!==withdrawCoin)? torch_swap(reserve, inIdx, withdrawCoin, inAmt, AMP) : 0n;
  console.log(`round-trip: put ${PR(inAmt)} coin${inIdx} -> withdraw_one coin${withdrawCoin} = ${PR(dyRT)}`);
  if(inIdx!==withdrawCoin) console.log(`direct swap coin${inIdx}->coin${withdrawCoin} = ${PR(dySwap)}  (RT advantage ${PR(dyRT-dySwap)})`);
  // value extraction: total out value vs in value (stable ~1:1)
  console.log(`net vs input (out coin${withdrawCoin} - in coin${inIdx}): ${PR(dyRT-inAmt)}  (>0 = profit)`);
  return {t,c,dyRT};
}

const M = 10n**6n * PRECISION;
const dx = 10n**4n * PRECISION;

// 1. balanced, deposit coin0, withdraw coin1
scenario('BALANCED deposit coin0', [M, M], [dx, 0n], 1);

// 2. IMBALANCED pool, deposit SCARCE coin (coin1 scarce) -> Torch charges ~0 fee
scenario('IMBALANCED[1.8M/0.2M] deposit SCARCE coin1', [18n*M/10n, 2n*M/10n], [0n, dx], 0);

// 3. IMBALANCED pool, deposit ABUNDANT coin0 (worsen imbalance)
scenario('IMBALANCED[1.8M/0.2M] deposit ABUNDANT coin0', [18n*M/10n, 2n*M/10n], [dx, 0n], 1);

// 4. Extreme imbalance, large scarce deposit
scenario('IMBALANCED[1.9M/0.1M] deposit SCARCE coin1 (large)', [19n*M/10n, 1n*M/10n], [0n, 5n*dx], 0);

// 5. deposit scarce coin1, withdraw SAME coin1 (pure fee probe, rebalancing deposit)
scenario('IMBALANCED[1.8M/0.2M] deposit coin1 withdraw coin1', [18n*M/10n, 2n*M/10n], [0n, dx], 1);
