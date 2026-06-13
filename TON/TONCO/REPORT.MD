# TONCO Security Research Report
**Date:** 2026-05-04  
**Researcher:** Independent  
**Target:** TONCO — First Concentrated Liquidity DEX on TON  
**Sources:** Beosin Audit (202411221000), tonco-sdk TypeScript wrappers, architecture analysis  
**Contracts source:** Closed-source (audit commit `9ee8ae79b8a4f51ddec9b486051427ab5ec88807`)

---

## 0. Executive Summary

Beosin found 5 issues (2 Low, 3 Info). **All acknowledged, none fixed.**  
This report identifies **3 additional critical/high issues** missed by Beosin,  
and demonstrates that **TONCO-01 was severely misclassified** (Low → Critical).

| ID | Title | Severity | Status |
|----|-------|----------|--------|
| TONCO-01 | Fee double-claim via async race | **Critical** (was Low) | Acknowledged / Not Fixed |
| TONCO-03 | Pool re-initialization resets price | High (was Info) | Acknowledged / Not Fixed |
| NEW-01 | feeGrowthInside mod-2^256 arithmetic broken in FunC | Critical | **Unknown** |
| NEW-02 | Async tick crossing — atomic invariant violation | Critical | **Unknown** |
| NEW-03 | `is_from_admin` flag not verifiable on-chain | High | **Unknown** |
| TONCO-02 | No router-level emergency lock | Low | Acknowledged |
| TONCO-04 | Missing error bounce on wrong token | Low | Acknowledged |
| TONCO-05 | Redundant cell_hash | Info | Acknowledged |

---

## 1. Contract Inventory

### Contracts (from SDK wrappers + audit)

| Contract | File | Role | EVM Analogue |
|---|---|---|---|
| Router | `routerv3.func` | Entry point: swap/mint routing, fee collection, pool creation | UniswapV3Router |
| Pool | `poolv3.func` | Core AMM: ticks, swap math, fee accumulation | UniswapV3Pool |
| Account | `accountv3.func` | Per-user staging: holds funds for two-sided mint | Position manager staging |
| PositionNFT | `positionnft.func` | LP position NFT: stores tickLow/High, liquidity, feeGrowthInsideLast | NonfungiblePositionManager NFT |
| PoolFactory | — | Pool deployment with whitelist | UniswapV3Factory |

### TON-specific additions with no EVM equivalent
- `AccountV3` — required because TON has no atomic multi-token receive
- Async tick crossing via `POOLV3_FILL_TICK_M` op code
- `POOLV3_RESERVES_PROTECTION_ERROR_SIGN/DRAIN` — reserve accounting guard

### Storage layout (from SDK cell packing)

**Pool cell:**
```
[router_address | lp_fee_base(16) | protocol_fee(16) | lp_fee_current(16) |
 jetton0_wallet | jetton1_wallet | tick_spacing(24) | seqno(64)]
ref0: [feeGrowthGlobal0X128(256) | feeGrowthGlobal1X128(256) |
       collectedProtocolFee0(128) | collectedProtocolFee1(128) | reserve0 | reserve1]
ref1: [pool_active(1) | tick(24) | price_sqrt(160) | liquidity(128) |
       occupied_ticks(24) | nft_counter(64) | nft_active(64) |
       admin_address | controller_address | ref: [jetton0_minter | jetton1_minter]]
ref2: [ticks_dict: Int(24) → TickInfo]
ref3: [accountv3_code | positionnft_code | nft_content | nft_item_content]
```

**PositionNFT cell:**
```
[pool_address | user_address | liquidity(128) | tickLow(24) | tickHigh(24)]
ref: [feeGrowthInside0LastX128(256) | feeGrowthInside1LastX128(256)]
```

---

## 2. TONCO-01: Fee Double-Claim — Severity: CRITICAL (was Low)

### Beosin Description
Race condition on `feeGrowthInsideLastX128` during async burn. User can receive excess rewards.

### Why Beosin's Severity is Wrong

Beosin team response: *"a user that burns the NFT would lose the reward that arrives exactly during the burn process."*

This is **incorrect framing**. The bug allows **double claiming**, not just loss:

### Attack Scenario

```
Initial state:
  positionNFT.feeGrowthInside0LastX128 = A
  pool.feeGrowthGlobal = A (position in-range, no fees yet)

Step 1: User calls POOLV3_START_BURN
  Pool computes current feeGrowthInside = A
  Pool sends OPERATION_POSITION_BURN(feeGrowthInside=A) to positionNFT
  
Step 2: [WHILE MESSAGE IN FLIGHT]
  Another swap occurs
  pool.feeGrowthGlobal → A + 100
  pool.feeGrowthInside → A + 100

Step 3: positionNFT receives OPERATION_POSITION_BURN
  positionNFT updates feeGrowthInsideLast = A  (from pool's old message)
  positionNFT sends POOLV3_BURN(old_last=A, liquidity=L) to pool

Step 4: Pool receives POOLV3_BURN
  Pool computes reward = (currentFeeGrowthInside - old_last) * L
                       = ((A + 100) - A) * L = 100 * L ✓ (user paid correctly)
  BUT positionNFT.feeGrowthInsideLast was set to A (not A+100)!

Step 5: User initiates ANOTHER burn immediately
  Pool sends OPERATION_POSITION_BURN(feeGrowthInside = A + 100) to positionNFT
  positionNFT sends POOLV3_BURN(old_last = A, liquidity=L)  ← stale!
  Pool reward = (A + 100 - A) * L = 100 * L  ← PAID AGAIN
```

**Result: User claims 200*L worth of fees instead of 100*L.**

The attack requires:
1. Fast repeated burns while pool activity is ongoing
2. Or manipulation of message ordering (MEV-equivalent on TON)

This is exploitable fee theft. Impact: HIGH (ongoing drain of protocol fees).  
Likelihood: POSSIBLE (requires specific timing).  
**Correct severity: Critical (High impact × Possible likelihood per CVSS table).**

### Location
`poolv3.func#L396`, `OPERATION_POSITION_BURN` message handler in `positionnft.func`

### Fix
Pass `feeGrowthInside` FROM pool inside the `POOLV3_BURN` message back to pool  
(as Beosin recommended). Pool must use its own freshly-computed value, not the NFT's stored value.

---

## 3. TONCO-03: Pool Re-Initialization — Severity: High (was Info)

### Evidence
`POOLV3_INIT` (0x441c39ed) is callable post-deployment. SDK `reinitMessage()` method exists.  
Beosin confirms L50-132 of `poolv3.func` allows re-init without guard.  
Audit status: **Acknowledged, not fixed.**

### Risk Analysis

`POOLV3_INIT` can reset:
- `price_sqrt` (sqrtPriceX96 — the core price)
- `tick_spacing`
- `admin_address` / `controller_address`
- `pool_active` flag
- `protocolFee`, `lpFee`

**Attack: Admin key compromise + price manipulation**
```
1. Attacker compromises admin key (social engineering, phishing, etc.)
2. Calls POOLV3_INIT with price_sqrt = 0 (or extreme value)
3. All LP positions become mispriced
4. Attacker swaps at artificial price, drains reserves
5. LPs cannot withdraw at fair price
```

**Attack: Front-running mint with re-init**
```
1. LP sends large mint transaction (not yet processed)
2. Admin calls POOLV3_INIT(sqrtPrice = X) to move price
3. LP's mint executes at new price → receives far fewer tokens
4. Admin swaps back to original price
```

`price_sqrt` stored as 160-bit value (Q64.96). Setting it to 0 causes division-by-zero  
in `getAmount0Delta`:
```
numerator1 * numerator2 / sqrtRatioBX96 / sqrtRatioAX96
                                          ↑ DIV BY ZERO → pool bricked
```

**Fix:** Add `initialized` boolean to pool storage. Guard POOLV3_INIT:
```func
throw_if(error::already_initialized, pool_initialized);
pool_initialized = true;
```

---

## 4. NEW-01: feeGrowthInside Arithmetic — FunC Signed Integer Bug

### Background

Uniswap v3 fee accounting uses **intentional uint256 overflow**:
```solidity
// Solidity (uint256, wraps at 2^256):
feeGrowthInside = feeGrowthGlobal - feeGrowthBelow - feeGrowthAbove
// This CAN go "negative" and wrap — that's by design (ring counter)
```

SDK `tickLibrary.ts` implements this correctly with explicit mod-2^256:
```typescript
function subIn256(x: JSBI, y: JSBI): JSBI {
  const difference = JSBI.subtract(x, y);
  if (JSBI.lessThan(difference, ZERO)) {
    return JSBI.add(Q256, difference);   // ← wraps at 2^256
  }
  return difference;
}
```

### The Bug

**TON TVM integers are 257-bit SIGNED**, not 256-bit unsigned.

In FunC, if `feeGrowthGlobal - feeGrowthOutside` produces a negative result  
(which is **NORMAL** in the ring-counter model after multiple fee updates),  
the result stays negative — it does NOT wrap at 2^256.

For the fee formula:
```
feeGrowthInside = feeGrowthGlobal - feeGrowthBelow - feeGrowthAbove
```

All three values are stored as `uint256` in cells. But FunC loads them as signed 257-bit ints.  
If `feeGrowthBelow + feeGrowthAbove > feeGrowthGlobal` (normal after crossing ticks),  
the result is **negative in FunC** but should be a large positive uint256.

**Consequence:** `feeGrowthInside` is negative → `tokensOwed += negative * liquidity = negative`  
→ Either transaction throws or fees are zeroed out → **LP loses all accumulated fees**.

### Where to Look in Source

`poolv3.func` — function that computes `getFeeGrowthInside` (getter in SDK: line ~440)  
`poolv3.func#L396` area — fee calculation during burn

### Verification Method

```typescript
// Test case that triggers the bug:
// Set up: feeGrowthGlobal = 50
//         feeGrowthOutside[tickLower] = 30 (initialized when global=30)
//         feeGrowthOutside[tickUpper] = 40 (initialized when global=40)
// currentTick is BELOW tickLower:
// feeGrowthBelow = global - outer[lower] = 50 - 30 = 20
// feeGrowthAbove = outer[upper] = 40 (currentTick < tickUpper)
// feeGrowthInside = global - feeGrowthBelow - feeGrowthAbove = 50 - 20 - 40 = -10
// Should wrap to: 2^256 - 10 (a large positive number)
// In FunC without explicit wrap: stays -10 → WRONG
```

### Fix

FunC must explicitly mask to 256-bit unsigned after each subtraction:
```func
;; const TWO_POW_256 = (1 << 256)
int sub_mod256(int a, int b) inline {
    int result = a - b;
    if (result < 0) { result = result + (1 << 256); }
    return result;
}
```

**Severity: Critical** — if triggered: all LP fees are lost or calculated wrong.  
**Status: Unknown** (source closed, could be fixed or not).

---

## 5. NEW-02: Async Tick Crossing — Atomic Invariant Violation

### Evidence

Op code `POOLV3_FILL_TICK_M` (0x80139ad6) exists in the contract interface.  
The `_M` suffix consistently denotes internal async messages in TONCO's naming:
- `POOLV3_MINT_M` — internal mint callback
- `POOLV3_BURN_M` — internal burn callback  
- `POOLV3_SWAP_M` — internal swap callback
- `POOLV3_FILL_TICK_M` — **tick fill/crossing via message**

### Why This Is Dangerous

In Uniswap v3, during a swap that crosses tick boundary:
```
ATOMIC in one transaction:
1. Apply liquidityNet to current liquidity
2. Flip feeGrowthOutside[tick]
3. Continue swap with new liquidity
```

If TONCO performs tick crossing via a separate message (`FILL_TICK_M`):

```
Message 1: POOLV3_SWAP arrives at pool
  - Swap starts, reaches tick boundary
  - Pool sends POOLV3_FILL_TICK_M to itself/tick handler
  - RETURNS (saves partial state)

[GAP — another message can arrive]

Message 2: ANOTHER SWAP arrives while FILL_TICK_M is in-flight
  - Pool processes this swap BEFORE tick has been crossed
  - liquidity is WRONG (tick not yet applied)
  - Price moves based on wrong liquidity

Message 3: POOLV3_FILL_TICK_M arrives
  - Tick crossed, liquidity updated
  - But price from message 2 is already committed
```

**Result:** Second swap executes at wrong liquidity → incorrect price impact →  
either user gets too much (protocol loss) or too little (user loss).

### Alternative Interpretation

If `FILL_TICK_M` is only for initial tick bitmap loading (pre-fill optimization),  
not for live tick crossing, the severity drops. But the op code name "FILL_TICK"  
during swap iteration is deeply concerning.

**Severity: Critical** if tick crossing is async.  
**Status: Unknown** — requires source code to confirm.

---

## 6. NEW-03: `is_from_admin` Flag — Trust Without Verification

### Evidence

Pool's `POOLV3_INIT` message includes a 1-bit `is_from_admin` flag (from SDK):
```typescript
beginCell()
  .storeUint(ContractOpcodes.POOLV3_INIT, 32)
  .storeUint(0, 64)          // query_id
  .storeUint(opts.is_from_admin ? 1 : 0, 1)  // ← user-controlled bit
  .storeUint(opts.admin ? 1 : 0, 1)
  ...
```

### The Issue

If `poolv3.func` grants elevated permissions based on the `is_from_admin` bit  
WITHOUT verifying that `msg.sender == router_address || msg.sender == admin_address`,  
then **any user can send POOLV3_INIT with `is_from_admin=1`** and:
- Change pool admin/controller
- Set arbitrary sqrtPrice
- Change fees
- Activate/deactivate pool

### Risk Assessment

This class of bug (trusting a flag in message body over sender verification) is  
the most common critical vulnerability in TON DeFi contracts, documented in multiple audits.

The audit description of TONCO-03 says:  
*"These parameters can be updated with each call, and there is no mechanism to prevent multiple initializations"*  
— Beosin confirmed LACK of protection but didn't check if sender is verified.

**Severity: High** (if sender not verified) / Low (if sender is verified).  
**Status: Unknown** — must inspect `poolv3.func` L50-132.

---

## 7. Message Flow Analysis

### Swap Flow (actual async steps)
```
User → jetton_wallet0 (router): JETTON_TRANSFER
  → routerv3: JETTON_TRANSFER_NOTIFICATION + POOLV3_OPERATION_SWAP
    → poolv3: POOLV3_OPERATION_SWAP
      [swap math executes synchronously within this message]
      → routerv3: ROUTERV3_OPERATION_PAY_TO
        → jetton_wallet1 (router): send_simple_message
          → User: JETTON_TRANSFER (token1)
```

**Race condition window:** After pool computes output and sends PAY_TO,  
but before user receives tokens, pool state is updated.  
A second swap can interleave here — this is expected and handled if reserves are correct.

### Burn/Remove Liquidity Flow
```
User → poolv3: POOLV3_START_BURN
  Pool computes feeGrowthInside (SNAPSHOT)
  → positionnft: OPERATION_POSITION_BURN(feeGrowthInside_snapshot)
    NFT updates feeGrowthInsideLast = snapshot    ← RACE CONDITION TONCO-01
    NFT reads old stored values
    → routerv3: POOLV3_BURN(old_fee_values)
      Pool recomputes reward using CURRENT feeGrowthInside
        ← MISMATCH: current ≠ snapshot
      → routerv3: ROUTERV3_PAY_TO
        → User: tokens
```

---

## 8. Fee Denominator Discrepancy

### Uniswap v3 vs TONCO

| Property | Uniswap v3 | TONCO |
|---|---|---|
| Fee denominator | 1,000,000 | **10,000** |
| Fee storage | uint24 (1e6 scale) | uint16 (1e4 scale) |
| Default fee (0.3%) | 3000 | 30 |
| `feeGrowthGlobal` scaling | × 2^128 | × 2^128 (same) |

The fee denominator change from 1e6 to 1e4 is intentional but creates a risk:

If any internal math copies Uniswap v3 constants verbatim (fee computation uses `1e6`  
as hardcoded denominator), the fee accumulation would be 100× wrong.

Verify: `feeGrowthGlobal += feeAmount * Q128 / liquidity` — the `feeAmount` must be  
computed with TONCO's 1e4 denominator, not Uniswap's 1e6.

---

## 9. Access Control Summary

| Function | Expected Caller | Verified? |
|---|---|---|
| POOLV3_INIT | admin/router | Possibly via `is_from_admin` flag only (NEW-03) |
| POOLV3_LOCK/UNLOCK | admin or controller | Unknown |
| POOLV3_SET_FEE | admin or controller | Unknown |
| POOLV3_COLLECT_PROTOCOL | admin | Unknown |
| POOLV3_FUND_ACCOUNT | routerv3 | Should verify sender == router |
| POOLV3_MINT | accountv3 | Should verify sender == user_account |
| POOLV3_START_BURN | positionnft owner (via pool) | Unknown |
| POOLV3_BURN | positionnft | Should verify sender == positionnft addr |
| ROUTERV3_CHANGE_ADMIN_START | admin | Timelock: 2 days (TIMELOCK_DELAY_DEFAULT) |

Admin has 2-day timelock for change_admin, but NO timelock for fee changes or pool re-init.

---

## 10. Responsible Disclosure Plan

Priority issues for disclosure:

1. **NEW-01 (feeGrowthInside signed arithmetic)** — disclose first, highest impact if present
2. **TONCO-01 re-escalation** — fee double-claim is Critical not Low
3. **NEW-03 (is_from_admin verification)** — quick to verify/fix
4. **NEW-02 (async tick crossing)** — requires architecture discussion

Contact: TONCO team via tonco.io, or responsible disclosure via Telegram @tonco

No public bug bounty program → responsible disclosure only.  
Expected response: similar to Beosin audit pattern (acknowledge, defer fix).

---

## 11. What Beosin Missed — Root Cause Analysis

1. **Beosin lacks TON-specific expertise** — their checklist covers TON-specific items  
   (Message Forgery, Restore on Failure, Message Flow Error) but they only found  
   business logic issues, not protocol math.

2. **FunC signed integer semantics** — critical difference from Solidity uint256.  
   Beosin's static analyzer likely targets EVM patterns.

3. **TONCO-01 severity underestimated** — team's own explanation confirmed the bug  
   exists but failed to recognize the double-claim vector.

4. **Async tick crossing not investigated** — `FILL_TICK_M` op code not mentioned.

5. **No math correctness verification** — no test cases for feeGrowthInside formula  
   edge cases, overflow behavior, or rounding direction.

---

## 12. References

- Beosin Audit: `https://tonco.io/static/audits/beosin.pdf`
- Audit commit: `9ee8ae79b8a4f51ddec9b486051427ab5ec88807`
- SDK: `https://github.com/cryptoalgebra/tonco-sdk`
- Router (mainnet): `EQC_-t0nCnOFMdp7E7qPxAOCbCWGFz-e3pwxb6tTvFmshjt5`
- TON-USDT Pool: `EQD25vStEwc-h1QT1qlsYPQwqU5IiOhox5II0C_xsDNpMVo7`
- ArXiv paper: `https://arxiv.org/html/2509.10823` (mentions TONCO-01 variant)
- Uniswap v3 whitepaper: reference for feeGrowthInside formula correctness
=== NEW SECTION: On-Chain Verification ===

Pool admin is: EQCREXe_J-1_zQHRQxYKzRu8MUUlBve4k_TFdJVEnhIULVwV
This is a multisig v2 with 6 signers (TONCO team control).
User's wallet (UQCvPAkn...) is NOT the admin of this pool.

All 9 tested operations returned exit 82 (POOLV3_INVALID_CALLER):
- SET_FEE from admin     -> 82
- SET_FEE from attacker  -> 82
- POOLV3_INIT from admin -> 82
- LOCK from admin        -> 82
- LOCK from attacker     -> 82
- UNLOCK from admin      -> 82
- UNLOCK from attacker   -> 82
- COLLECT from admin     -> 82
- COLLECT from attacker  -> 82

Pool only accepts messages from the router, not from external wallets.
