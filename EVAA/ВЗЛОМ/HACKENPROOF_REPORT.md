# EVAA Protocol — Stale-Price Liquidation of Solvent Positions

**Program:** EVAA Protocol @ HackenProof
**Repo / commit (in-scope, public):** `github.com/evaafi/contracts` @ `d9138cb24f03b53522774351aceb38c51a047eee`
**In-scope deployed target (byte-matched):** EVAA v8 PYTH ToB pool `EQCsOdQPDO1Xndzutn9dDcloolWo1wHKICMz2jHL6UP8smcV` (code hash `08b54a3f…`), Pyth oracle `EQA5NPyjfZztDm8jcTBwTAU9NGsgJEkw19z61yecX0TlseSB`.
**Severity:** **High** — unjust liquidation of positions that are solvent at current market price (theft of liquidation penalty/equity from users).

---

## Title
Liquidation of a position that is **solvent (healthy) at execution time**, using a cherry-picked, validly-signed historical Pyth price up to `prices_ttl` (180s) stale within the only freshness gate.

## Affected Functions
- `plugins/pyth/pyth_request.fc` — `request_price_feeds`: `min_publish_time = now() - publish_gap`; `publish_gap` is taken from liquidator calldata with **no upper bound**.
- `core/master-liquidate.fc:679` — `unpack_prices_data_args`: `min_publish_gap` loaded from calldata, no cap; forwarded to Pyth.
- `data/prices-packed.fc:72` — `packed_price:parse_check`: the sole EVAA freshness gate `now() > timestamp + price_ttl` (per-feed, `price_ttl = 180s` on mainnet).
- `logic/user-utils.fc:201` — `is_liquidatable`: reads price directly from `prices_packed`, **no independent freshness re-check** (only a `price == -1` missing-check).
- External: Pyth TON `Pyth.fc` `parse_price_feeds_from_data` — filters only by caller-supplied `[min_publish_time, max_publish_time]`; **no internal staleness** (the staleness-aware `getPriceNoOlderThan` exists but is unused by EVAA).

## Root Cause
EVAA delegates price freshness entirely to a single TTL gate. The `publish_gap` that determines how old a VAA Pyth will accept is fully attacker-controlled via calldata with no cap, and the Pyth TON contract imposes no staleness of its own. A liquidator submits a validly-signed historical VAA whose `publish_time` is within 180s; `parse_check` accepts it, and `is_liquidatable` evaluates the position at that stale price with no further freshness check.

## Attack Path
1. Asset price briefly dips (a 30–120s wick) then recovers. Some near-threshold positions were momentarily liquidatable during the dip; they are **healthy now**.
2. Attacker fetches the signed VAA from the dip timestamp via Pyth Hermes (`/v2/updates/price/{publish_time}`).
3. Attacker sends liquidation (`liquidate_master_jetton_request` / TON path) with `prices_data_args` carrying that VAA and `min_publish_gap ≥ its age`.
4. Master → Pyth `request_price_feeds`; Pyth verifies Wormhole signatures and that `publish_time ∈ window` → passes.
5. `parse_check`: `now() > timestamp + 180` is false (age < 180s) → price accepted.
6. `is_liquidatable` computes with the stale dip price → position appears liquidatable.
7. Liquidation executes; collateral + liquidation bonus transferred to the liquidator. **The victim, solvent at current price, loses the liquidation penalty / part of equity.**

## Impact
A liquidator extracts value from users who are fully collateralized at the current market price. The liquidation provides no protocol-protective benefit (the position is solvent), so it is pure value extraction from users. Per-tx bounded by the "too much" cap (`core/user-liquidate.fc:247`, ≈33% of collateral or the `$200/price` floor); repeatable across positions and across every qualifying dip.

**Honest bound on platform impact:** this vector does **not** create protocol bad debt by itself. Pool bad debt requires the position to be underwater at the *real* price (residual unbacked debt), which needs a real adverse move exceeding the CF/LT/bonus cushion. A stale price within 180s only re-applies a *real, historical, signed* tick — it does not manufacture magnitude beyond what actually occurred. Therefore the demonstrable, unconditional impact is **user loss (unjust liquidation)**, not supplier/pool loss — hence **High**, not Critical. (A pool-bad-debt escalation is only realizable if a real ≥cushion dislocation/depeg occurs within the 180s window; that is conditional and trigger-dependent.)

## Proof of Concept — executed on real bytecode (TVM)
Real `parse_check` (verbatim from `data/prices-packed.fc`) compiled with `@ton-community/func-js`, executed via `@ton/sandbox` `runGetMethod` with `blockchain.now` fixed and a TLB-correct Pyth price-feed cell.

Raw TVM result (now=1900000000, prices_ttl=180):
```
fresh   (age 0s,   within TTL)         -> err=0      vmExit=0  [ACCEPTED]
stale   (age 120s, within TTL 180)     -> err=0      vmExit=0  [ACCEPTED]
stale   (age 179s, within TTL 180)     -> err=0      vmExit=0  [ACCEPTED]
expired (age 200s, beyond TTL 180)     -> err=20734 (prices_incorrect_timestamp) [REJECTED]
```
**Proven:** a price up to 179s stale passes EVAA's only freshness gate; the boundary is exactly `prices_ttl`.

**Mainnet-fork replay (real deployed bytecode + real on-chain position):** the master, Pyth, and a real borrower user-SC were forked into `@ton/sandbox` from mainnet; the victim's own `getIsLiquidable` and the master's `getCollateralQuote` were called with fresh vs stale prices. A stale price flips a healthy real position to liquidatable, and the protocol's own quote awards the collateral for repaying a small debt. Both the liquidatability decision and the payout executed on unmodified mainnet bytecode/state.

## Remediation (any one)
- Use a `getPriceNoOlderThan`-equivalent with ttl ≤ ~30s for liquidation pricing.
- Cap `publish_gap` from calldata to a small constant (`min_publish_time = max(min_publish_time, now() - 30)`).
- Force `min_publish_time ≈ now()` in `request_price_feeds`.
- Re-verify the position is liquidatable at the most recent price before executing.

## Assumptions
- `prices_ttl = 180s` and pool active — **confirmed on-chain** by parsing `oracles_info` from the pool data BoC.
- Hermes serves historical signed VAAs — Pyth standard endpoint.
- Requires a real transient price move (a VAA cannot be forged) → opportunistic on natural volatility against positions near the liquidation threshold.

## Confidence
High. Price-flow chain confirmed in source; TTL-acceptance of stale prices proven by executed bytecode; healthy→liquidatable flip proven on real mainnet bytecode via fork.

---

### Note on the funded MAIN pool (`EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr`)
The funded MAIN pool (~578k TON) uses the **same Pyth oracle** and the same on-demand price model, so the same stale-price weakness is present in principle. However, its deployed code hash (`b90881c4…`) does **not** match any public repo version, so it cannot be byte-verified from available source. Byte-matched proof is provided only against the in-scope public-source pool `EQCsOdQ…`.
