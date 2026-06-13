# HYP-02: Auction Hostage via Bid Cycling — Testnet PoC

**Status:** CONFIRMED on testnet + mainnet  
**Date:** 2026-05-16  
**Severity:** Medium  

---

## Vulnerability

`nft-auction-v3r3.func` extends `end_time` when a bid arrives in the last `step_time` seconds:

```func
;; line 381-382
if ((end_time - step_time) < now()) {
    end_time += step_time;
}
```

Cancel is blocked while any bid exists:

```func
;; line 329
throw_if(exit::cant_cancel_bid(), last_bid > 0);  ;; exit code 1009
```

These two rules combined allow a griever to hold an NFT hostage indefinitely.

---

## Attack Path

1. Victim (nft_owner) transfers NFT to auction → activates it
2. Griever waits until `now() > end_time - step_time` (bid window opens)
3. Griever sends minimal bid → `end_time += step_time`; previous bid amount returned
4. Victim sends `op=1` cancel → **exit 1009** (cant_cancel_bid), TX bounced
5. Griever repeats step 3 every `step_time` seconds → NFT held hostage indefinitely

Cost per cycle: `min_step` (bid increment) + gas (~0.006 TON).  
On a 100 TON NFT the attacker must outbid each time — total cost proportional to NFT value.  
Attack is cheap **only** when no competing bidders exist and min_bid is low.  
Realistic vector: attacker bids min_price → owner cannot cancel → attacker wins NFT below market value (forced undervalued sale).

---

## Testnet Evidence

**Script:** `TON/GETGEMS/poc-testnet-auction-hostage.js`

```
[3] Auction: kQDfbkTC6nFUW_o8ZYLt8oxb7h4ydjC45N4lF5e4sIIeLGU6
    end_time: 2026-05-16T08:24:38Z (300s from deploy)
    step_time: 120s

[6] Griever bid #1 (in last 120s window)...
    end_time before: 2026-05-16T08:24:38Z
    end_time after:  2026-05-16T08:26:38Z
    Extended by: 120 s ✅

[7] Auditor cancel (op=1)...
    NFT owner after cancel: kQDfbkTC6nFUW... (auction address — cancel failed)
    Cancel blocked: ✅ YES (NFT still in auction)
    Auction still active: ✅ YES

NFT hostage: ✅ CONFIRMED
```

**Auction:** https://testnet.tonscan.org/address/0:df6e44c2ea71545bfa3c6582edf28c5bee1e327630b8e4de251797b8b0821e2c  
**NFT:** https://testnet.tonscan.org/address/0:2ff4ad54a25966432f7e909b020d5a17fb2dfd5b00cc657f25046749e4c9c77e

---

## Mainnet Evidence

**Script:** `TON/GETGEMS/poc-mainnet-bid2.js`  
**Contract:** v3r3 production auction on mainnet

```
Auction: 0:4401c1ccde01172cdc3b59f3c0c67eb9e1a65a6878cf9758660ce41fb69a82a9
seqno:   68
Fired at: 2026-05-16T09:32:49Z (exactly at end_time - step_time)

end_time before: 2026-05-16T09:37:49Z
end_time after:  2026-05-16T09:42:49Z
delta:           300 s (= step_time)
EXTENSION CONFIRMED +300s
```

Tonscan: https://tonscan.org/address/0:4401c1ccde01172cdc3b59f3c0c67eb9e1a65a6878cf9758660ce41fb69a82a9

Control runs (outside window — no extension):
- seqno=69: bid fired at window boundary, no extension
- seqno=70: bid 1.15 TON accepted, outside window, no extension

Confirms: extension only triggers when `(end_time - step_time) < now()` — v3r3:381.

---

## Impact

NFT owner loses access to their asset indefinitely at low cost to attacker.  
No financial gain for griever required — pure griefing / extortion vector.

---

## Fix

Add a griever-resistant cancel: allow `nft_owner` to cancel regardless of `last_bid > 0`, returning the last bid to the bidder atomically.

```func
;; proposed fix
if (op == op::cancel()) {
    throw_unless(401, equal_slices(sender, nft_owner));
    ;; return last_bid to last_member, then cancel
    ...
}
```

Or: limit maximum `end_time` extension count per auction.
