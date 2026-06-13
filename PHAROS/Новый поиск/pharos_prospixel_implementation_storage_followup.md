# Pharos Mainnet PROSPixel Implementation / ABI / State Follow-up

Scope: one tx only.

- Proxy: `0xf81fb02f13917db6fa8f5a1f2e39a86ece2a626a`
- Sample tx: `0xb0e974ffe3578831b85a19721c6a6391675d632a1f1353f400984face43eaf99`
- Pixel: `round=0`, `x=816`, `y=838`
- Buyer: `0xeca112eab807e2c02c42bf898edcbdda1d1d0347`
- Seller from event: `0xa7c71156897cae095a098c5474bef9ed39c5596d`

## 1. Implementation comparison

| Item | Displayed implementation | Live implementation |
|---|---:|---:|
| Address | `0x801bf82791104dfe5af507067f6c93b6d92efb95` | `0x5b631863df1b20afb2715ee1f1381d6dc1dd065d` |
| Runtime length | `10825` bytes | `10823` bytes |
| Runtime hash | `0x360079c7fe6e12ca8f10c07a75de856610d3991b19b65e9eeeab644c78a14475` | `0xf23528e5194059aac76ad84876150c64a520c71a7d74f80e58f5fd66fafd41c3` |
| Identical bytecode | no | no |
| Metadata-only difference | no, best-effort metadata stripping still differs | no |
| SocialScan source availability | verified source available | SocialScan `/contract/{addr}/code` returns `Contract code not found` |

EIP-1967 implementation slot:

- slot: `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
- at tx block `7197155`: `0x0000000000000000000000005b631863df1b20afb2715ee1f1381d6dc1dd065d`
- latest: same

SocialScan’s displayed implementation `0x801b...fb95` does not match the EIP-1967 slot at the tx block. Runtime differs materially, but function selectors and event topics checked below are compatible.

Classification: `DIFFERENT_RUNTIME_COMPATIBLE_ABI`.

## 2. ABI/function selector compatibility

All tested read selectors returned successfully through the proxy at block `7197155` and latest. Return lengths were consistent with the verified ABI.

| Function | Selector | Return length | Decoded result at block N | Supports ABI? |
|---|---:|---:|---|---|
| `getPixel(uint256,uint16,uint16)` | `0xa626be5a` | 64 | owner `0xeca112...0347`, price `13500000000000000` | yes |
| `pixels(bytes32)` | `0xf76b75af` | 64 | same owner/price for computed pixel key | yes |
| `isAlreadyBought(uint16,uint16)` | `0x145b572f` | 32 | `true` | yes |
| `premiumClaimable(address)` | `0x35965896` | 32 | `42585900000000000000` | yes |
| `principalClaimable(address)` | `0x71412cd2` | 32 | `162232000000000000000` | yes |
| `inviterRewardClaimable(address)` | `0xb7718d6e` | 32 | `0` | yes |
| `players(address)` | `0xe2eb41ff` | 64 | `7093700`, `53235468421313760560972433` | yes for public getter shape |
| `lastBuyer(uint256)` | `0x13238dd6` | 32 | `0xeca112...0347` | yes |
| `totalBoughtAmountRound(uint256)` | `0xd4301fd6` | 32 | `1322017` | yes |
| `currentRound()` | `0x8a19c8bc` | 32 | `0` | yes |

These calls show ABI compatibility. They do not by themselves prove identical runtime source.

## 3. Storage diff map

`debug_traceTransaction` with `prestateTracer` identified the proxy storage slots touched during the delegatecall. The most important changed slots:

| Slot | Before | After | Recognized fields | Possible meaning | Evidence | Confidence | Alternative explanation |
|---|---|---|---|---|---|---|---|
| `0x6916a5bc91bcdc9a02a33d530088e7fe5b30e3512daea9f63514121a61389893` | `0x0` in tracer diff | `0x2ff62db077c000eca112eab807e2c02c42bf898edcbdda1d1d0347` | buyer address, price `13500000000000000` | pixel ownership/price slot | matches `getPixel(0,816,838)` and contains buyer/price | High | packed pixel state |
| `0x4ff5c212d08ccb61233930ba8af3e3d34947035d87749b421a47f6888a7533a0` | historical storage: `0x...24ef62eff23c5b...08cb485182d16b0000` | historical storage: `0x...24eff826b944ec...08cb6bd875412c0000` | low96 principal, mid96 premium | seller claimable accounting slot | maps to `_players[seller]` slot `9`, offset `+1`; deltas match event exactly | High | packed player accounting |
| `0x6d5257204ebe7d88fd91ae87941cb2dd9d8062b64ae5a2bd2d28ec40b9fbf6df` | `0x0` in tracer diff | `0x6a0470d5eca112eab807e2c02c42bf898edcbdda1d1d034701` | buyer address | buyer/player or round state | contains buyer and timestamp-like value | Medium | packed round/player state |
| `0x6d5257204ebe7d88fd91ae87941cb2dd9d8062b64ae5a2bd2d28ec40b9fbf6e0` | `0x0` in tracer diff | `0x142c20` | count-like value | round counter | close to `totalBoughtAmountRound(0)` pre/post area | Medium | round total |

Note: the prestateTracer diff output listed zero for some pre-values. For the seller accounting slot, exact pre/post values were taken with `eth_getStorageAt` at block `7197154` and `7197155`, because that is the amount-critical proof.

Seller slot derivation:

- The verified layout has `_players` mapping at slot `9`.
- `keccak256(abi.encode(seller, uint256(9))) + 1` equals:
  `0x4ff5c212d08ccb61233930ba8af3e3d34947035d87749b421a47f6888a7533a0`.
- This is the changed slot containing packed claimable amounts.

Packed slot decode:

Before at block `7197154`:

- principal low96: `162222000000000000000`
- premium mid96: `42583275000000000000`

After at block `7197155`:

- principal low96: `162232000000000000000`
- premium mid96: `42585900000000000000`

Deltas:

- principal delta: `10000000000000000`
- premium delta: `2625000000000000`

These exactly match `lastPrice` and `premiumToSeller` from `PixelPremiumDistributed`.

## 4. Seller accounting analysis

Seller: `0xa7c71156897cae095a098c5474bef9ed39c5596d`

Event says:

- `lastPrice = 10000000000000000`
- `premiumToSeller = 2625000000000000`

Result:

- Immediate native transfer: no. Trace and SocialScan internal transactions show no native subcall to seller.
- Claimable accounting: yes.
- Storage proof: `_players[seller]` slot `9`, offset `+1`, decoded as packed principal/premium.
- Public read proof after tx:
  - `principalClaimable(seller) = 162232000000000000000`
  - `premiumClaimable(seller) = 42585900000000000000`
- Amount reconciliation:
  - principal increased by `10000000000000000`
  - premium increased by `2625000000000000`
  - both match the event exactly.

The event label is not stronger than the proof after mapping the packed seller accounting slot.

## 5. Event topic/ABI validation

Computed topics:

- `PixelPremiumDistributed(address,uint256,uint16,uint16,uint256,uint256)`
  - computed topic0: `0x12f751fdf6bce511c2df477197aa39e5336d5f0aaa637b66b859a69fca651645`
  - raw log topic0: same
- `BatchPixelsBought(address,address,uint256,uint16[],uint16[],uint24[],uint256,uint256)`
  - computed topic0: `0x43a83ac6855083513eff16ce08f81ca523ae4e65d03d76979d2976ba126c32da`
  - raw log topic0: same

Raw logs decode cleanly:

- `PixelPremiumDistributed`:
  - seller `0xa7c711...596d`
  - round `0`
  - x/y `816/838`
  - lastPrice `10000000000000000`
  - premiumToSeller `2625000000000000`
- `BatchPixelsBought`:
  - user `0xeca112...0347`
  - x/y `[816]/[838]`
  - totalValue `13770000000000000`

Classification: `DECODE_USES_STALE_BUT_COMPATIBLE_ABI`.

The displayed implementation is stale relative to the EIP-1967 slot, but the event topics and relevant public reads are compatible, and the seller accounting is verifiable.

## 6. Disproved explanations

- Not a premium-accounting evidence gap: seller principal/premium deltas are proven by storage.
- Not a wrong event decode for the two sample logs: raw topic0 values match the verified ABI event signatures.
- Not a contradiction between `PixelPremiumDistributed` and claimable state: the event amounts reconcile exactly with the packed seller accounting slot.
- Not a user-facing owner mismatch: pixel state after tx shows buyer `0xeca112...0347`.

## 7. Remaining suspicious states

No unresolved semantic mismatch for this tx.

Remaining cosmetic issue:

- SocialScan displays implementation `0x801bf...fb95`, while the live EIP-1967 slot points to `0x5b631...065d`.
- The live implementation source was not available through SocialScan’s contract-code endpoint.
- This is stale/incomplete metadata for this case, but not a semantic contradiction after storage reconciliation.

## 8. Triage decision

STOP.

The premium event semantics were reconciled with active proxy storage. No expansion to more transactions is warranted for this exact lead.

## 9. Final judgment

STOP: Premium event semantics reconciled with active implementation/storage.
