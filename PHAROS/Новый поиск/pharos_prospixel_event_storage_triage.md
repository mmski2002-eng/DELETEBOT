# Pharos Mainnet PROSPixel Event-vs-State Triage

Scope: Pharos Mainnet, chainId `1672 / 0x688`.

Focus: whether PROSPixel event-derived labels such as `BatchPixelsBought` and `PixelPremiumDistributed` are confirmed by canonical/public state.

## 1. Contract/ABI baseline

- PROSPixel proxy: `0xf81fb02f13917db6fa8f5a1f2e39a86ece2a626a`
- Sample tx target: `0xf81fb02f13917db6fa8f5a1f2e39a86ece2a626a`
- SocialScan tx metadata:
  - contract name: `PROSPixel`
  - `is_proxy = true`
  - proxy contract itself marked not verified
  - displayed implementation: `0x801bf82791104dfe5af507067f6c93b6d92efb95`
  - displayed implementation marked verified
- Direct EIP-1967 implementation slot read:
  - slot `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
  - at sample block and latest: `0x5b631863df1b20afb2715ee1f1381d6dc1dd065d`
- SocialScan contract-code endpoint for `0x5b631863df1b20afb2715ee1f1381d6dc1dd065d` returned `Contract code not found`.
- RPC `eth_getCode` for `0x5b631863df1b20afb2715ee1f1381d6dc1dd065d` returned non-empty code, length about `10823` bytes.

Public reads exposed by the verified implementation ABI at `0x801bf...` include:

- `getPixel(uint256 round, uint16 x, uint16 y) -> (address owner, uint256 price)`
- `pixels(bytes32) -> (address owner, uint96 price)`
- `isAlreadyBought(uint16 x, uint16 y)`
- `premiumClaimable(address)`
- `principalClaimable(address)`
- `inviterRewardClaimable(address)`
- `players(address)`
- `lastBuyer(uint256)`
- `totalBoughtAmountRound(uint256)`
- `currentRound()`

Important baseline finding: the verified ABI is useful for decoding known event topics and some public reads, but the live proxy implementation slot points to another implementation address. Therefore event labels and source-level names are not enough by themselves.

## 2. Sample tx decode

Sample tx: `0xb0e974ffe3578831b85a19721c6a6391675d632a1f1353f400984face43eaf99`

- block: `7197155`
- timestamp: `2026-05-13T12:38:45Z`
- from / buyer: `0xeca112eab807e2c02c42bf898edcbdda1d1d0347`
- to: `0xf81fb02f13917db6fa8f5a1f2e39a86ece2a626a`
- method: `batchBuyPixels(uint16[],uint16[],uint24[])`
- receipt status: `1`
- tx value: `13770000000000000`
- token transfers: `0`
- calldata:
  - `x = [816]`
  - `y = [838]`
  - `colors = [0]`

Decoded events:

- `PixelPremiumDistributed`
  - `lastOwner = 0xa7c71156897cae095a098c5474bef9ed39c5596d`
  - `round = 0`
  - `x = 816`
  - `y = 838`
  - `lastPrice = 10000000000000000`
  - `premiumToSeller = 2625000000000000`
- `BatchPixelsBought`
  - `user = 0xeca112eab807e2c02c42bf898edcbdda1d1d0347`
  - `inviter = 0x0000000000000000000000000000000000000000`
  - `round = 0`
  - `x = [816]`
  - `y = [838]`
  - `colors = [0]`
  - `totalValue = 13770000000000000`
  - `totalInviterReward = 0`

Trace:

- SocialScan trace and `debug_traceTransaction` both show only the proxy call and delegatecall.
- No native subcall to `lastOwner` is visible.
- SocialScan internal transactions endpoint returned `total = 0`.

## 3. State before/after table

RPC `eth_call` against `getPixel(0, 816, 838)` returned the same result for historical and latest tags:

| Pixel/object | Event says | State before by `eth_call` at `N-1` | State after by `eth_call` at `N` | Latest state | Matches event | Evidence | Notes |
|---|---|---|---|---|---|---|---|
| Pixel `(round=0,x=816,y=838)` | bought by `0xeca112...0347` | owner `0xeca112...0347`, price `13500000000000000` | owner `0xeca112...0347`, price `13500000000000000` | same | yes for post-owner | `getPixel` public read | Historical `eth_call` appears not usable for pre-state here because it returns the post/latest value even at earlier tags. |
| Premium/principal for event `lastOwner=0xa7c711...596d` | seller should receive `lastPrice=10000000000000000` and `premiumToSeller=2625000000000000` under the verified source semantics | no delta visible by public `premiumClaimable/principalClaimable` eth_call from `N-1` to `N` | no delta visible | UNKNOWN | not confirmed | public reads + trace | Because historical `eth_call` is not reliable here and live implementation differs from displayed verified implementation, this cannot be reconciled from public reads alone. |

`debug_traceTransaction` with `prestateTracer` is the stronger state evidence:

- The proxy implementation slot in the trace points to `0x5b631863df1b20afb2715ee1f1381d6dc1dd065d`, not the displayed verified implementation `0x801bf...fb95`.
- The trace shows a pixel-related storage slot changing from `0x0` to a packed value containing buyer `0xeca112...0347` and price `13500000000000000`.
- The trace does not expose an external native transfer to the event `lastOwner`.

This confirms the buyer-facing pixel state after the tx, but it does not confirm the premium-distribution label under the explorer-decoded semantics.

## 4. Additional tx checks

Recent `BatchPixelsBought` logs found by RPC in the same contract:

- `0x9d0d25fb1cf8d1e0b1a6b0a97f99b22da6cb07b5f25df9f6a7ce57dfce48e5f9`
- `0xc4c221de9b9fd5befa8f718d912e8843ab6a8d0f27ed15539d0804e50a2a0a18`

I did not expand full state checks after the sample because the Stage 1 sample already produced a concrete suspicious state: event/source metadata cannot be cleanly reconciled with the live implementation and public state evidence. The next step should be targeted expansion around this exact pattern, not a broad scan.

## 5. Observer comparison

| Observer | What it proves | What it cannot prove | Uses bought/distributed labels? | Storage confirms label? | Stronger than evidence? |
|---|---|---|---|---|---|
| RPC receipt | tx succeeded | pixel owner, seller accounting | no | no | no |
| Raw logs | topics/data were emitted | semantic meaning of `lastOwner` or payout | no, raw only | partly | no |
| SocialScan decoded events | decodes `BatchPixelsBought` and `PixelPremiumDistributed` using ABI metadata | that displayed implementation is the one active in proxy slot | yes | bought owner partly confirmed; premium not confirmed | yes for premium label |
| Public state via `getPixel` | current/latest owner is buyer `0xeca112...0347` | reliable pre-state at `N-1` on this RPC; seller accounting under tx-time implementation | no | confirms buyer after | no |
| Tx-time implementation slot | live proxy target is `0x5b631...065d` | ABI/source semantics of unverified implementation | no | shows metadata mismatch | yes, if explorer uses different implementation ABI |
| Human/app interpretation | “pixel bought” and “premium distributed” | canonical seller accounting without tx-time ABI/storage proof | yes | only buyer ownership is confirmed | premium label is stronger than current evidence |

## 6. Suspicious states

Suspicious state 1:

- tx: `0xb0e974ffe3578831b85a19721c6a6391675d632a1f1353f400984face43eaf99`
- event: `PixelPremiumDistributed(lastOwner=0xa7c711..., lastPrice=10000000000000000, premiumToSeller=2625000000000000)`
- expected state: seller/principal/premium accounting should be confirmable for `lastOwner` under the surfaced ABI/source semantics.
- observed state:
  - no token transfers
  - no native internal transfer
  - public reads do not provide a clean before/after accounting proof
  - tx-time implementation slot points to `0x5b631...065d`, while SocialScan metadata surfaces verified implementation `0x801bf...fb95`
- exact mismatch: event-decoded premium label is stronger than the state evidence currently available from public reads and displayed source metadata.
- possible benign explanation: `0x5b631...065d` may have compatible event topics but different internal accounting layout/semantics; current explorer metadata may be stale or attached to a similar implementation.
- evidence needed: verified/source ABI for `0x5b631863df1b20afb2715ee1f1381d6dc1dd065d`, or storage-layout decode of the `prestateTracer` diff proving seller principal/premium slots.
- confidence: Medium.
- next safe test: decode the tx with the actual implementation bytecode/source for `0x5b631...065d`, then map the pre/post storage slots touched for `lastOwner`.

Suspicious state 2:

- tx: same sample.
- event: `BatchPixelsBought(user=0xeca112..., x=[816], y=[838])`
- expected state: pixel owner after tx should be buyer.
- observed state: latest/public `getPixel(0,816,838)` returns owner `0xeca112...0347`, price `13500000000000000`; `prestateTracer` post-storage also includes the buyer and price.
- exact mismatch: no owner mismatch after tx; the suspicious part is only pre-state and event/accounting interpretation.
- possible benign explanation: normal purchase finality, with unrelated metadata ambiguity.
- confidence: Low for owner mismatch; disproved for post-owner.

## 7. Disproved/cosmetic differences

- `token_transfers = 0` is not itself suspicious because PROSPixel uses native value and internal accounting, not ERC20/NFT transfer events.
- `BatchPixelsBought` post-owner meaning is supported by public `getPixel` latest state for the sample pixel.
- Proxy status alone is not the issue. The issue is the mismatch between the displayed verified implementation and the implementation address read directly from the proxy slot.

## 8. Triage decision

CONTINUE.

Stage 1 found a concrete event-vs-state verification gap in the known sample. The pixel buyer state is confirmed after the tx, but the premium-distribution label and surfaced implementation/source metadata are not cleanly supported by canonical state reads.

## 9. Recommended next target if STOP

Not applicable because the triage decision is CONTINUE.

Final judgment:

CONTINUE: Suspicious event-vs-storage mismatch found; expand sample.
