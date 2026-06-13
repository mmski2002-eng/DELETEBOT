# Abstract mainnet: bug bounty readiness по stale/replay targets

Дата: 2026-05-12  
Scope: production contracts из `abstract_mainnet_concrete_production_poc_targets_ru.md`.

## Executive summary

**Полный executable PoC `fail -> reusable authorization -> exact calldata replay -> stale economic execution` на текущей машине не подтвержден.**

Причина не в отсутствии кандидатов, а в инфраструктуре:
- обычный Hardhat fork непригоден для Abstract, потому что Abstract возвращает zkSync-style bytecode (`0x0003...`), который обычный EVM fork не исполняет корректно;
- корректный `anvil-zksync` на Windows не поддерживается официальным plugin;
- `anvil-zksync` Linux binary был запущен в WSL, но WSL в этой среде не имеет working outbound network/DNS до Abstract RPC.

Поэтому для bug bounty submission сейчас корректный статус: **source-level + onchain evidence confirmed, executable exploit not yet confirmed**.

## Final status table

| Target | Primitive | Real production evidence | Economic impact | Exact fork replay | Submission readiness |
|---|---|---:|---|---|---|
| Seaport `0xDF3969...` | Signed NFT order replay after failed fill | 633,574 tx + failed real fills | High: stale fixed-price NFT | Not executed locally | Needs Linux `anvil-zksync` replay |
| Relay Approval Proxy V3 `0xccc88...` | Permit2 witness reusable after downstream revert | 41,262 tx + real Permit2 multicalls | Medium/High if target is fixed-price flow | Not executed locally | Needs target-specific payload replay |
| Universal Router `0xE1b0...` | Permit2 command rollback on route revert | 707,224 tx | Low/Medium; sampled flows mostly AMM | Not executed locally | Exclude generic swaps |
| Relay Depository `0x4cD0...` | Signed CallRequest guard rollback | 236,702 tx | Medium; depends on decoded calls | Not executed locally | Needs signed request payload |
| SeaDrop `0x00b19...` | Signed mint digest rollback | 3,627 tx | Medium: delayed mint option | Not executed locally | Needs signed mint payload |
| Gauge `0xa171...` | ERC2771 reward watchlist | 38,122 tx | Low | Not applicable | Excluded unless forwarder proves replay |

## 1. Seaport fixed-price NFT orders

PROJECT: Seaport on Abstract

CHAIN: Abstract mainnet

CONTRACT:
- `0xDF3969A315e3fC15B89A2752D0915cc76A5bd82D`
- Abscan: https://abscan.org/address/0xDF3969A315e3fC15B89A2752D0915cc76A5bd82D

FUNCTION:
- `fulfillAdvancedOrder`, selector observed in production: `0xe7acab24`
- `fulfillBasicOrder`, selector observed in production: `0xfb0f3ee1`
- `fulfillAvailableAdvancedOrders`, selector observed in production: `0x87201b41`

TYPE: NFT / fixed-price trade

REAL USAGE EVIDENCE:
- Abscan tx count: 633,574.
- Successful production fulfill examples:
  - `0x149a6bfdd663e8a6a4b1538281695349c948c9c9e6f3b3cf59482970e5484fcb`, status 1, block 37,846,494, selector `0xe7acab24`.
  - `0xe78312f724d241bada2820c046ba6dca81b27d3cf4385ddb1b77b16d42ff5780`, status 1, block 35,725,690, selector `0xfb0f3ee1`.
- Failed production fulfill examples:
  - `0x2526ca20b4e170442509941b4bfd5dd443594d1d1cc8b047d3bd811f8e87aefa`, status 0, block 40,894,560, selector `0xe7acab24`.
  - `0xd1db441f8b45d04f67bb158f0f32c51cc5a5bcd0d104b18d5ba8eefafc9fcd00`, status 0, block 40,894,503, selector `0xe7acab24`.

PERMIT / AUTH MECHANISM:
- Off-chain signed Seaport order.
- The signed order authorizes sale/purchase parameters including offer, consideration, time range, salt and conduit.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION: Yes

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- A seller signs a fixed-price NFT order.
- Fulfiller causes payment/approval/transfer failure.
- Revert rolls back order fill status.
- The same signed order can be filled later if still valid and not cancelled.

ECONOMIC IMPACT / PROFIT PATH:
- Buy NFT at stale historical price after floor moves upward.
- Profit is current resale/floor value minus signed consideration and fees.

LIKELIHOOD / FEASIBILITY: High source-level, not fully PoC-confirmed locally

POC STEPS:
1. Fork Abstract with `anvil-zksync`.
2. Use a real active listing or a historical fulfillment template.
3. Submit fulfillment with insufficient buyer balance/approval.
4. Verify order status is still unfilled after revert.
5. Restore buyer balance/approval.
6. Replay exact same calldata.
7. Verify NFT owner changed and consideration paid at signed price.

COMMENTS / OBSERVATIONS:
- This is the best bug-bounty candidate.
- It still needs exact fork replay and signed price extraction from a live listing/current order.
- Historical failed txs show real failed execution on production, but do not by themselves prove later profitable replay.

## 2. Relay Approval Proxy V3 Permit2 multicall

PROJECT: Relay

CHAIN: Abstract mainnet

CONTRACT:
- Approval Proxy V3: `0xccc88a9d1b4ed6b0eaba998850414b24f1c315be`
- Router V3: `0xb92fe925DC43a0ECdE6c8b1a2709c170Ec4fFf4f`

FUNCTION:
- `permit2TransferAndMulticall`, selector `0x0a2b8f36`
- `transferAndMulticall`, selector `0xf9e4bab4`

TYPE: meta-tx / relayer / permit-like

REAL USAGE EVIDENCE:
- Approval Proxy V3 tx count: 41,262.
- Router V3 tx count: 142,091.
- Real production Permit2 examples:
  - `0xf94fdf0017480284abe66fef112de8d6d46f9b85c183fae8b390198b059430d4`, status 1, block 61,301,558, Permit2 deadline `1778608121`.
  - `0x58a418818fe1c2c5cedd363e823a4f3c35c6dd7cec2d90d09962122f36ac8b76`, status 1, block 61,300,644, Permit2 deadline `1778607865`.
- Real failed proxy examples exist but sampled failed txs were `transferAndMulticall`, not signed Permit2:
  - `0x91df2dca4c91f8740662d546144e15eec3f4bd96267e5791b00185924ff4f54c`, status 0, selector `0xf9e4bab4`.

PERMIT / AUTH MECHANISM:
- Permit2 `PermitBatchTransferFrom`.
- `permitWitnessTransferFrom` binds relayer, recipients, metadata and calls hash.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION: Yes

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- User signs Permit2 for fixed token amount and fixed call bundle.
- Required downstream call fails with `allowFailure=false`.
- Revert rolls back Permit2 nonce consumption.
- Relayer can replay before deadline if state becomes favorable.

ECONOMIC IMPACT / PROFIT PATH:
- Permit itself is not profit.
- Profit requires downstream call to be fixed-price NFT, launchpad mint, vault/bonding curve, or stale settlement.

LIKELIHOOD / FEASIBILITY: High primitive / Medium exploitability

POC STEPS:
1. Fork at a block near a real `permit2TransferAndMulticall`.
2. Replay copied calldata with one downstream call forced to fail.
3. Verify Permit2 nonce/bitmap unchanged.
4. Restore target state.
5. Replay exact same calldata.
6. Verify nonce consumed and downstream state changed.

COMMENTS / OBSERVATIONS:
- This is a valid stale option primitive.
- For bounty submission, the missing piece is a production payload with fixed economic target, not merely approvals/swaps.

## 3. Universal Router + Permit2

PROJECT: Uniswap Universal Router / Permit2

CHAIN: Abstract mainnet

CONTRACT:
- Universal Router: `0xE1b076ea612Db28a0d768660e4D81346c02ED75e`
- Permit2: `0x0000000000225e31d15943971f47ad3022f714fa`

FUNCTION:
- `execute(bytes,bytes[],uint256)`, selector `0x3593564c`
- `execute(bytes,bytes[])`, selector `0x24856bc3`

TYPE: meta-tx / permit-like / router

REAL USAGE EVIDENCE:
- Universal Router tx count: 707,224.
- Permit2 tx count: 13,798.
- Sampled Permit2 command txs:
  - `0xc4f2994e9ad452aa25e1f78551d3be07a1eae4eb1b5087a4b425d989d1edd4e1`, commands `0x0a08000c`.
  - `0x3c77469f9533cf56a1647521920a970d2f8da576ffafb43afad8a7921bdfe82b`, commands `0x0a08`.

PERMIT / AUTH MECHANISM:
- Permit2 command inside router command stream.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION: Yes

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Later required command fails, rolling back Permit2.
- Replay is possible before deadline.

ECONOMIC IMPACT / PROFIT PATH:
- Sampled commands are mostly AMM swap-like flows, which are out of scope.
- Needs NFT/launchpad/fixed-price downstream command.

LIKELIHOOD / FEASIBILITY: Medium primitive / Low current bounty readiness

POC STEPS:
1. Find router tx with Permit2 plus in-scope command, not generic AMM.
2. Force downstream command failure.
3. Verify Permit2 state unchanged.
4. Replay after restoring state.

COMMENTS / OBSERVATIONS:
- Exclude from bounty draft unless a concrete fixed-price target is found.

## 4. Relay Depository

PROJECT: Relay

CHAIN: Abstract mainnet

CONTRACT:
- `0x4cD00E387622C35bDDB9b4c962C136462338BC31`

FUNCTION:
- `execute(((address,bytes,uint256,bool)[],uint256,uint256),bytes)`, selector `0x2d9fb478`
- Other sampled selectors: `0x49290c1c`, `0xe8017952`

TYPE: meta-tx / relayer

REAL USAGE EVIDENCE:
- Tx count: 236,702.
- 100 sampled recent txs were successful; sampled distribution: `0x49290c1c` 91, `0xe8017952` 5, `0x2d9fb478` 4.

PERMIT / AUTH MECHANISM:
- Signed `CallRequest`.
- Replay guard `callRequests[structHash]`.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION: Yes

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Signed request fails in downstream call.
- Replay guard rolls back.
- Same request can be replayed before expiration.

ECONOMIC IMPACT / PROFIT PATH:
- Depends entirely on decoded calls.
- No standalone economic impact proven from sampled data.

LIKELIHOOD / FEASIBILITY: High primitive / Medium-low bounty readiness

POC STEPS:
1. Decode a production signed `CallRequest`.
2. Force `allowFailure=false` target revert.
3. Verify `callRequests[structHash] == false`.
4. Restore state.
5. Replay exact calldata.

COMMENTS / OBSERVATIONS:
- Strong engineering primitive, but not enough for bounty without a concrete value-moving request.

## 5. SeaDrop signed mint

PROJECT: SeaDrop ERC1155 Contract Offerer

CHAIN: Abstract mainnet

CONTRACT:
- `0x00b19a5200a100e5fc4c9800772f4d002f218400`

FUNCTION:
- observed production selector `0x7e734c5a`
- internal signed path `_mintSigned`

TYPE: NFT / launchpad / signed mint

REAL USAGE EVIDENCE:
- Tx count: 3,627.
- 100/100 sampled recent txs were successful with selector `0x7e734c5a`.

PERMIT / AUTH MECHANISM:
- ECDSA signed mint params.
- Replay guard `_usedDigests[digest]`.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION: Yes

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Failed signed mint rolls back `_usedDigests`.
- Replay later when price/supply/window is favorable.

ECONOMIC IMPACT / PROFIT PATH:
- Delayed mint option.
- Potential resale spread if mint remains valid.

LIKELIHOOD / FEASIBILITY: Medium primitive / Low current bounty readiness

POC STEPS:
1. Obtain real signed mint calldata.
2. Force payment/stage/supply failure.
3. Verify digest remains unused.
4. Restore favorable state/time.
5. Replay exact calldata.

COMMENTS / OBSERVATIONS:
- No failed production signed mint was found in sampled pages.
- Treat as secondary unless a live signed mint payload is captured.

## 6. Gauge reward claim

PROJECT: Aborean/Veldrome-style Gauge

CHAIN: Abstract mainnet

CONTRACT:
- `0xa171bb8b0805ddccc8721ccb1e13f6dd09633cfc`

FUNCTION:
- reward/staking functions; sampled selectors `0xc00007b0`, `0xb6b55f25`, `0x2e1a7d4d`

TYPE: reward / staking

REAL USAGE EVIDENCE:
- Tx count: 38,122.

PERMIT / AUTH MECHANISM:
- None in Gauge itself.
- It uses ERC2771 context, but signature/nonce semantics are in external trusted forwarder.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION: Not confirmed

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Only if trusted forwarder leaves signed request reusable after target revert.

ECONOMIC IMPACT / PROFIT PATH:
- Weak: reward transfers to `_account`, not relayer.

LIKELIHOOD / FEASIBILITY: Low

POC STEPS:
1. Identify trusted forwarder.
2. Decode forwarder signed request.
3. Test nonce rollback on failed `getReward`.

COMMENTS / OBSERVATIONS:
- Exclude from current bounty submission.

## Submission recommendation

Do not submit as “confirmed exploit” yet. Submit only after one of these is completed:

1. **Seaport PoC:** exact replay of signed fixed-price order on `anvil-zksync` fork showing:
   - failed fill leaves order unfilled;
   - exact calldata replay succeeds;
   - NFT transfers at stale signed price;
   - measurable stale price spread.

2. **Relay Permit2 PoC:** exact replay of `permit2TransferAndMulticall` showing:
   - failed downstream call leaves Permit2 nonce reusable;
   - exact calldata replay succeeds;
   - downstream fixed-price/mint/vault action yields value.

Current best bounty angle:

```text
Primary: Seaport fixed-price signed NFT order can be kept as an option after failed fulfillment and replayed later at stale price.
Secondary: Relay Permit2 witness multicall gives solver/relayer option-like delayed execution when downstream required call reverts.
```

## Remaining blockers

- Need working Abstract fork backend: `anvil-zksync` on Linux with network access.
- Need active signed order or replayable historical state before order expiration.
- Need economic delta: signed NFT price vs current/forked market value, or fixed downstream value in Relay call.

