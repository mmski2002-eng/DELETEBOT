# Production DEX-like targets for stale favorable CallPermit replay

**Дата:** 2026-05-12  
**Target primitive:** failed/reverted CallPermit `dispatch(...)` publishes reusable `v/r/s`; nonce is not consumed on failed target call or future-nonce publication; exact same calldata can be replayed later.  
**Scope:** Moonbeam / Moonriver production-used DEX, router, RFQ, launchpad, bonding-curve targets.  
**CallPermit:** `0x000000000000000000000000000000000000080a`

---

## 1. Executive Summary

Найден один high-signal production candidate:

```text
StellaSwap Pulsar / Algebra Router V3
0xe6d0ED3759709b743707DcfeCAe39BC180C981fe
```

Почему он выделяется:

- production-used: Moonscan показывает `775,794` tx на Router V3;
- DefiLlama DEX volume для StellaSwap: `24h ~$35,885`, `7d ~$196,728`, `30d ~$2,730,584`;
- official StellaSwap docs указывают этот `SwapRouter`;
- функция `exactOutput(...)` / `exactOutputSingle(...)` не фиксирует final execution price fully: фактический `amountIn` вычисляется из текущего Algebra pool state;
- replay может исполниться позже при изменившейся цене/ликвидности, если `amountIn <= amountInMaximum`;
- failed-dispatch window может быть создан slippage/price manipulation, temporary liquidity movement, или signer-controlled allowance/balance failure.

Сильный экономический сценарий:

```text
sign exactOutput buy
-> dispatch fails when pool price requires amountIn > amountInMaximum
-> reusable signature becomes public
-> pool price later improves
-> replay exact same calldata
-> fixed output acquired with lower/current amountIn under the old maxIn authorization
```

Это не гарантированная third-party theft модель для обычного UI swap, потому что `recipient` часто signer. Но это production-grade stale favorable delayed execution primitive, особенно если `recipient`/strategy contract/relayer flow контролируется атакующей стороной или если прибыль извлекается MEV-обвязкой вокруг forced delayed swap.

---

## 2. Usage Evidence Snapshot

### StellaSwap

**Project:** StellaSwap  
**Chain:** Moonbeam  
**DefiLlama DEX volume:**

```text
24h:  35,885 USD
7d:   196,728 USD
30d:  2,730,584 USD
```

**DefiLlama current TVL:**

```text
Moonbeam: ~561,848 USD
```

**Router V3 Moonscan tx count:**

```text
775,794 transactions
```

Sources:

- StellaSwap Pulsar V3 docs: https://docs.stellaswap.com/dev-resource/pulsar-v3-contracts
- StellaSwap Router V3 on Moonscan: https://moonbeam.moonscan.io/address/0xe6d0ED3759709b743707DcfeCAe39BC180C981fe
- DefiLlama StellaSwap summary: https://api.llama.fi/summary/dexs/stellaswap?excludeTotalDataChart=true&excludeTotalDataChartBreakdown=true
- DefiLlama StellaSwap TVL: https://api.llama.fi/protocol/stellaswap

### Solarbeam

**Project:** Solarbeam  
**Chain:** Moonriver  
**DefiLlama DEX volume:**

```text
24h:  8,968 USD
7d:   77,901 USD
30d:  582,192 USD
```

**DefiLlama current TVL:**

```text
Moonriver: ~240,250 USD
```

**SolarRouter tx count:**

```text
1,868,772 transactions
```

Sources:

- Solarbeam contracts docs: https://docs.solarbeam.io/contracts
- Solarbeam SolarRouter: https://moonriver.moonscan.io/address/0xAA30eF758139ae4a7f798112902Bf6d65612045f
- DefiLlama Solarbeam summary: https://api.llama.fi/summary/dexs/solarbeam?excludeTotalDataChart=true&excludeTotalDataChartBreakdown=true
- DefiLlama Solarbeam TVL: https://api.llama.fi/protocol/solarbeam

### Beamswap

**Project:** Beamswap  
**Chain:** Moonbeam  
**DefiLlama DEX volume:**

```text
24h:  14 USD
7d:   388 USD
30d:  16,734 USD
```

**DefiLlama current TVL:**

```text
Moonbeam: ~63,777 USD
```

**Router counts:**

```text
V2 Router: 474,874 tx
V3 Router: 26,572 tx
```

Sources:

- Beamswap contracts docs: https://docs.beamswap.io/developers/beamswap-contracts
- Beamswap V3 Router source: https://moonscan.io/address/0x1Cfd10c0f4985CF124c3C99dc937280a1164ad74
- DefiLlama Beamswap summary: https://api.llama.fi/summary/dexs/beamswap?excludeTotalDataChart=true&excludeTotalDataChartBreakdown=true
- DefiLlama Beamswap TVL: https://api.llama.fi/protocol/beamswap

---

## 3. Candidate 1 - StellaSwap Pulsar / Algebra Router V3

```text
PROJECT: StellaSwap
CONTRACT: 0xe6d0ED3759709b743707DcfeCAe39BC180C981fe
LABEL: StellaSwap: Router V3
CHAIN: Moonbeam
```

### FUNCTION

Primary:

```solidity
exactOutput(ExactOutputParams params)
exactOutputSingle(ExactOutputSingleParams params)
```

Secondary:

```solidity
exactInput(ExactInputParams params)
exactInputSingle(ExactInputSingleParams params)
```

### REAL USAGE EVIDENCE

- Moonscan labels the address `StellaSwap: Router V3`.
- Moonscan shows `775,794` transactions.
- Official StellaSwap Pulsar V3 docs list:

```text
SwapRouter deployed to:
0xe6d0ED3759709b743707DcfeCAe39BC180C981fe
```

- DefiLlama reports current StellaSwap DEX volume:

```text
24h:  35,885 USD
7d:   196,728 USD
30d:  2,730,584 USD
```

### WHY REPLAY MAY BE DANGEROUS

`exactOutput(...)` fixes:

- `path`;
- `recipient`;
- `amountOut`;
- `amountInMaximum`;
- `deadline`.

It does not fix final `amountIn`. The router computes `amountIn` at execution time from current Algebra pool state:

```solidity
exactOutputInternal(...);
amountIn = amountInCached;
require(amountIn <= params.amountInMaximum, "Too much requested");
```

Therefore the same signed calldata can have different economic results at different times.

If a CallPermit dispatch fails and publishes the authorization, replay later can execute when:

- pool price moved favorably;
- liquidity returned;
- exact output became cheaper;
- `amountIn <= amountInMaximum`.

### PRICE MUTABILITY SOURCE

- Algebra concentrated liquidity pool price;
- active liquidity ranges;
- dynamic fee / pool state;
- mutable route path liquidity;
- current tick / sqrt price;
- LP additions/removals.

### POSSIBLE FAILED-DISPATCH VECTOR

Practical vectors:

1. **Reserve/price manipulation:** front-run against the pool so `amountIn > amountInMaximum`, causing `Too much requested`.
2. **Temporary liquidity removal:** on thin ranges, remove or move liquidity so exact output cannot be satisfied under `amountInMaximum`.
3. **Signer-controlled allowance/balance:** signer removes token allowance or balance, causing router callback payment failure after permit validation.
4. **Price limit:** for single-hop swaps with `limitSqrtPrice`, push pool toward the limit so the swap reverts/fails to satisfy amount.

Bad vectors:

- target `deadline` expiry is not useful, because the same calldata will remain expired later.

### POTENTIAL PROFIT PATH

#### Self-benefiting / signer-controlled stale favorable execution

```text
User signs exactOutput buy: receive 1,000 TOKEN_B, pay at most 100 TOKEN_A.
Dispatch fails when market temporarily requires 101 TOKEN_A.
Signature becomes public and nonce remains reusable.
Market later improves; 1,000 TOKEN_B costs 80 TOKEN_A.
Replay exact same CallPermit calldata.
User/recipient receives fixed output and spends only current lower input.
```

This is economically favorable delayed execution.

#### Third-party / MEV path

```text
Attacker induces failed dispatch via price manipulation.
Attacker waits for pool movement.
Attacker replays the stale swap and wraps it with MEV:
  - pre-position before forced exactOutput;
  - back-run pool imbalance;
  - arbitrage surrounding the delayed swap.
```

Profit depends on route depth, recipient, and whether the replayed swap creates extractable price movement.

#### Direct theft-like path

Only realistic if signed `recipient` is attacker-controlled or a strategy/order contract controlled by attacker. Standard frontend swaps usually set `recipient = signer`, so direct theft is not the default case.

### LIKELIHOOD

```text
Medium-High as stale favorable delayed execution.
Medium as third-party MEV opportunity.
Low-Medium as direct theft without malicious recipient/orderflow context.
```

### WHY THIS IS THE BEST PRODUCTION TARGET

Unlike generic V2 exact-input swaps, StellaSwap V3 `exactOutput` has:

- production usage;
- concentrated liquidity mutable pricing;
- exact output with runtime-computed input;
- active router transaction count;
- official contract docs;
- clear revert condition: `Too much requested`;
- replayable calldata can become successful later under changed pool state.

---

## 4. Candidate 2 - StellaSwap V2 Router

```text
PROJECT: StellaSwap
CONTRACT: 0x70085a09d30d6f8c4ecf6ee10120d1847383bb57
LABEL: StellaSwap: Router V2
CHAIN: Moonbeam
```

### FUNCTION

```solidity
swapTokensForExactTokens(uint amountOut, uint amountInMax, address[] path, address to, uint deadline)
swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] path, address to, uint deadline)
```

### REAL USAGE EVIDENCE

Moonscan tx count:

```text
1,228,330 transactions
```

### WHY REPLAY MAY BE DANGEROUS

For `swapTokensForExactTokens`, `amountIn` is derived at execution time:

```solidity
amounts = StellaSwapV2Library.getAmountsIn(factory, amountOut, path);
require(amounts[0] <= amountInMax, "StellaSwapV2Router: EXCESSIVE_INPUT_AMOUNT");
```

The mutable source is pair reserves.

### PRICE MUTABILITY SOURCE

- V2 pair reserves;
- LP liquidity changes;
- current pool balance/reserve state.

### POSSIBLE FAILED-DISPATCH VECTOR

- reserve manipulation to make `amounts[0] > amountInMax`;
- temporary liquidity exhaustion;
- signer allowance/balance failure.

### POTENTIAL PROFIT PATH

Same as exactOutput:

```text
fail when required input is too high
replay when reserves improve
execute exact output with lower current input
```

### LIKELIHOOD

```text
Medium as production-used stale favorable replay.
Lower than StellaSwap V3 because it is a generic V2 exact-output pattern and slippage bounds are explicit.
```

### NOTE

This is included because StellaSwap V2 is heavily used historically and still part of a production system. However, it is less interesting than V3 because it is a standard UniswapV2-style pattern and the user explicitly asked not to spend time on generic clones unless there is a specific production reason.

---

## 5. Candidate 3 - Solarbeam SolarRouter

```text
PROJECT: Solarbeam
CONTRACT: 0xAA30eF758139ae4a7f798112902Bf6d65612045f
LABEL: Solarbeam: Solar Router
CHAIN: Moonriver
```

### FUNCTION

```solidity
swapTokensForExactTokens(uint amountOut, uint amountInMax, address[] path, address to, uint deadline)
swapTokensForExactETH(uint amountOut, uint amountInMax, address[] path, address to, uint deadline)
swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] path, address to, uint deadline)
```

### REAL USAGE EVIDENCE

- Official Solarbeam docs list `SolarRouter` at this address.
- Moonscan tx count:

```text
1,868,772 transactions
```

- DefiLlama Solarbeam DEX volume:

```text
24h:  8,968 USD
7d:   77,901 USD
30d:  582,192 USD
```

### WHY REPLAY MAY BE DANGEROUS

For exact-output functions:

```solidity
amounts = SolarLibrary.getAmountsIn(factory, amountOut, path, fee);
require(amounts[0] <= amountInMax, "SolarRouter: EXCESSIVE_INPUT_AMOUNT");
```

So final required input is derived from current reserves at execution time.

### PRICE MUTABILITY SOURCE

- pair reserves;
- liquidity state;
- path reserves across hops.

### POSSIBLE FAILED-DISPATCH VECTOR

- front-run reserve movement so `amounts[0] > amountInMax`;
- temporary liquidity removal/exhaustion;
- signer balance/allowance failure.

### POTENTIAL PROFIT PATH

```text
sign exact output swap
-> attacker or signer causes temporary reserve state where input needed exceeds max
-> failed CallPermit reveals reusable signature
-> reserves later improve
-> replay executes same exact-output swap successfully
```

### LIKELIHOOD

```text
Medium.
```

Reasoning:

- production evidence is real;
- Moonriver volume is still non-zero;
- router is generic V2-style, so this is less novel than StellaSwap V3;
- direct third-party profit still depends on recipient/orderflow/MEV.

---

## 6. Rejected / Low Priority

### Beamswap V3 Router

```text
CONTRACT: 0x1Cfd10c0f4985CF124c3C99dc937280a1164ad74
```

Technically similar to V3 exactOutput:

```solidity
require(amountIn <= params.amountInMaximum, "Too much requested");
```

But usage evidence is weak relative to StellaSwap:

```text
Moonscan tx count: 26,572
DefiLlama 24h volume: 14 USD
DefiLlama 7d volume: 388 USD
DefiLlama 30d volume: 16,734 USD
TVL: ~63,777 USD
```

Verdict:

```text
Technically valid pattern, but not a priority production target.
```

### Beamswap V2 Router

```text
CONTRACT: 0x96b244391D98B62D19aE89b1A4dCcf0fc56970C7
```

Moonscan shows substantial historical tx count (`474,874`), but current DefiLlama volume for Beamswap is too low. Also the pattern is generic V2 exact-output routing.

Verdict:

```text
Rejected for main target list.
```

### RFQ / offchain order systems

No production Moonbeam/Moonriver RFQ/orderbook target with material usage was identified in this pass. No strong candidate with:

- active volume;
- verified source;
- fixed quote fields;
- mutable execution state;
- CallPermit-compatible replay path.

### Launchpads / bonding curves

No active production launchpad/bonding-curve target with meaningful current usage and verified mutable price logic was identified in this pass.

---

## 7. Important Non-Finding

I did not find a production-used router where replay bypasses slippage protection.

The risk is more specific:

```text
failed CallPermit makes a signed swap authorization public and reusable;
the router computes price-dependent amounts from mutable market state;
the same calldata can fail at time T and later succeed at time T+n under favorable state.
```

For normal UI swaps where:

- recipient is signer;
- deadline is short;
- slippage bounds are sane;
- no one can profit from forcing the delayed swap;

impact is lower.

The risk becomes stronger when:

- deadline is long;
- recipient is an attacker-controlled address or strategy contract;
- exactOutput uses high `amountInMaximum`;
- pair is thin and manipulable;
- replay can be MEV-wrapped;
- user/signer intentionally wants an option-like delayed stale execution.

---

## 8. Best Next PoC Target

### Primary

```text
StellaSwap Router V3
0xe6d0ED3759709b743707DcfeCAe39BC180C981fe
Function: exactOutputSingle / exactOutput
```

PoC shape:

1. Fork Moonbeam.
2. Choose active StellaSwap V3 pool with enough but manipulable liquidity.
3. Sign CallPermit for `exactOutputSingle`:
   - fixed `amountOut`;
   - high but finite `amountInMaximum`;
   - long router deadline and CallPermit deadline.
4. Manipulate price or liquidity so `amountIn > amountInMaximum`.
5. Submit CallPermit `dispatch`; target reverts with `Too much requested`.
6. Confirm nonce unchanged and `v/r/s` public.
7. Restore or wait for favorable pool price.
8. Replay exact same calldata.
9. Confirm:
   - same dispatch calldata hash;
   - nonce consumed only on success;
   - output delivered;
   - actual input derived from later pool state.

Expected verdict if successful:

```text
STELLA_V3_EXACT_OUTPUT_STALE_REPLAY_SUCCEEDED
```

### Secondary

```text
Solarbeam SolarRouter
0xAA30eF758139ae4a7f798112902Bf6d65612045f
Function: swapTokensForExactTokens
```

Use only if a Moonriver fork and active pair can be selected with enough liquidity to demonstrate reserve-state failure and later replay.

---

## 9. Final Ranking

| Rank | Project | Contract | Function | Usage | Replay risk | Likelihood |
|---:|---|---|---|---|---|---|
| 1 | StellaSwap V3 / Pulsar | `0xe6d0...81fe` | `exactOutput`, `exactOutputSingle` | High | Runtime input from mutable concentrated liquidity | Medium-High |
| 2 | StellaSwap V2 | `0x7008...bb57` | `swapTokensForExactTokens` | High historical | Runtime input from reserves, generic V2 | Medium |
| 3 | Solarbeam | `0xAA30...045f` | `swapTokensForExactTokens` | Real Moonriver usage | Runtime input from reserves, generic V2 | Medium |
| 4 | Beamswap V3 | `0x1Cfd...ad74` | `exactOutput` | Low current volume | Technically valid but low production weight | Low |

Best candidate for actual exploit-grade PoC:

```text
StellaSwap Router V3 exactOutput / exactOutputSingle
```
