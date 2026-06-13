# Abstract mainnet: concrete production targets для stale / replay PoC

Дата проверки: 2026-05-12  
Scope: только production-used Abstract mainnet contracts.  
Важно: exact replay на fork не был исполнен на текущей машине из-за отсутствия рабочего `anvil-zksync` fork-доступа к Abstract RPC из WSL. Ниже зафиксированы реальные production addresses, real tx evidence, failed executions и PoC steps для запуска в корректном Linux/WSL окружении.

## Итог по подтверждению

- **Наиболее конкретный NFT target:** Seaport `0xDF3969...` — найдены реальные failed `fulfillAdvancedOrder` transactions и successful fixed-price/order fulfillment transactions на production.
- **Наиболее конкретный permit/meta-tx target:** Relay Approval Proxy V3 `0xccc88...` — найдены реальные `permit2TransferAndMulticall` transactions с Permit2 deadline, обязательными downstream calls и active usage.
- **Replay primitive:** подтвержден source-level: state/nonce/order-status update откатывается при revert, значит signed authorization/order остается reusable, если не истек deadline/endTime и не было cancel/successful fill.
- **Exact same calldata replay:** не подтвержден выполнением локально из-за fork tooling blocker; roadmap ниже использует реальные tx hashes и addresses.

## 1. Seaport fixed-price / signed NFT orders

PROJECT: Seaport on Abstract

CHAIN: Abstract mainnet

CONTRACT:
- `0xDF3969A315e3fC15B89A2752D0915cc76A5bd82D`
- Abscan: https://abscan.org/address/0xDF3969A315e3fC15B89A2752D0915cc76A5bd82D

FUNCTION:
- `fulfillAdvancedOrder` selector `0xe7acab24`
- `fulfillBasicOrder` selector `0xfb0f3ee1`
- `fulfillAvailableAdvancedOrders` selector `0x87201b41`
- `cancel` selector `0xfd9f1e10`

TYPE: NFT / fixed-price trade / signed order

REAL USAGE EVIDENCE:
- Abscan contract tx count: 633,574.
- Recent pages show real successful fulfillment txs:
  - `0x149a6bfdd663e8a6a4b1538281695349c948c9c9e6f3b3cf59482970e5484fcb` — status 1, selector `0xe7acab24`, block 37,846,494.
  - `0xe78312f724d241bada2820c046ba6dca81b27d3cf4385ddb1b77b16d42ff5780` — status 1, selector `0xfb0f3ee1`, block 35,725,690.
  - `0x4d01a41d2728c2780f624bc3b3b7ab9cd96a3adf5823a9dead3487e7eaf75dd6` — status 1, selector `0x87201b41`, block 29,451,148.
- Real failed fulfillment txs:
  - `0x2526ca20b4e170442509941b4bfd5dd443594d1d1cc8b047d3bd811f8e87aefa` — status 0, selector `0xe7acab24`, block 40,894,560.
  - `0xd1db441f8b45d04f67bb158f0f32c51cc5a5bcd0d104b18d5ba8eefafc9fcd00` — status 0, selector `0xe7acab24`, block 40,894,503.
  - `0x0441d334051864591b717eff11d0dd36dcad0efc5f36dfc36e97df28dc389e2a` — status 0, selector `0xe7acab24`, block 40,807,706.

PERMIT / AUTH MECHANISM:
- Off-chain signed Seaport order.
- Signature and order parameters are submitted to `fulfillAdvancedOrder` / `fulfillBasicOrder`.
- Order status is updated during fulfillment but only persists if the whole tx commits.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION: Yes

Reason:
- In Seaport, fulfillment validates signature/order, updates fill status, then transfers offer/consideration.
- If transfer/payment/approval fails, full tx reverts.
- Revert rolls back order-status update, so the signed order remains reusable until `endTime`, cancellation, or successful fill.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Seller signs fixed-price NFT listing.
- Buyer/relayer submits fulfillment with intentionally bad state: insufficient ETH/ERC20, missing approval, bad conduit/transfer condition.
- Tx fails; signed order remains valid.
- Later, market floor rises above signed price.
- Same order calldata can be replayed before `endTime` and filled at stale historical price.

ECONOMIC IMPACT / PROFIT PATH:
- Buy NFT at stale fixed price.
- Profit from spread between historical listing price and current floor/resale.
- This is the strongest concrete MoonBeans-like target on Abstract.

LIKELIHOOD / FEASIBILITY: High

POC STEPS:
1. Fork mainnet with `anvil-zksync fork --fork-url abstract --fork-block-number <block before active listing fill/fail>`.
2. Use a real `fulfillAdvancedOrder` tx as template, preferably one of the status 0 txs above or a currently active listing.
3. Sign/obtain authorization: use existing Seaport order signature from calldata, or create a controlled listing on fork with the same production Seaport contract.
4. Induce fail: remove buyer balance/approval or force consideration transfer to fail.
5. Verify reusable: query Seaport order status; order must remain unfilled after failed tx.
6. Restore state: fund buyer / restore approval / keep order within time window.
7. Replay exact same calldata.
8. Verify stale sale: NFT owner changes, old fixed consideration paid, order status consumed only after successful replay.

## 2. Relay Approval Proxy V3 Permit2 multicall

PROJECT: Relay

CHAIN: Abstract mainnet

CONTRACT:
- Approval Proxy V3: `0xccc88a9d1b4ed6b0eaba998850414b24f1c315be`
- Router V3: `0xb92fe925DC43a0ECdE6c8b1a2709c170Ec4fFf4f`
- Abscan: https://abscan.org/address/0xccc88a9d1b4ed6b0eaba998850414b24f1c315be

FUNCTION:
- `permit2TransferAndMulticall` selector `0x0a2b8f36`
- `transferAndMulticall` selector `0xf9e4bab4`

TYPE: meta-tx / relayer / permit-like

REAL USAGE EVIDENCE:
- Approval Proxy V3 tx count: 41,262.
- Router V3 tx count: 142,091.
- Recent production `permit2TransferAndMulticall` txs:
  - `0xf94fdf0017480284abe66fef112de8d6d46f9b85c183fae8b390198b059430d4` — status 1, block 61,301,558, 1 permitted token, 5 downstream calls, Permit2 deadline `1778608121`.
  - `0x58a418818fe1c2c5cedd363e823a4f3c35c6dd7cec2d90d09962122f36ac8b76` — status 1, block 61,300,644, 1 permitted token, 4 downstream calls, Permit2 deadline `1778607865`.
  - `0x8b14ab46937451699be3e4d17eb8b039392e2c34f299bf6201c0c8a274a2e819` — status 1, block 61,300,404, 1 permitted token, 3 downstream calls, Permit2 deadline `1778607802`.
- Real failed production txs exist on same proxy, but observed failed txs in sampled pages are `transferAndMulticall`, not signed Permit2:
  - `0x91df2dca4c91f8740662d546144e15eec3f4bd96267e5791b00185924ff4f54c` — status 0, selector `0xf9e4bab4`, block 61,294,862.
  - `0xfd4d315d3dc4443bfd11312143e669c04115372bd2a8767498a19adcff50645a` — status 0, selector `0xf9e4bab4`, block 61,294,745.

PERMIT / AUTH MECHANISM:
- Permit2 `PermitBatchTransferFrom` + `permitWitnessTransferFrom`.
- Witness binds relayer, `refundTo`, `nftRecipient`, metadata, and full calls hash.
- Downstream calls are executed via Relay Router V3 `multicall`.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION: Yes

Reason:
- Proxy consumes Permit2 before router multicall.
- Router `_aggregate3Value` reverts if a required call has `allowFailure=false` and fails.
- Full transaction revert rolls back Permit2 nonce consumption and token transfers.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- User signs a Permit2 authorization for a fixed token amount and fixed call bundle.
- Relayer/solver attempts execution; downstream call fails due to balance, allowance, liquidity, target state, slippage, or purchase condition.
- Permit2 authorization remains reusable until deadline.
- Replay later when target state is favorable.

ECONOMIC IMPACT / PROFIT PATH:
- Not from Permit2 alone.
- Profit path exists if `calls` target fixed-price NFT purchase, launchpad mint, vault/bonding-curve action, or stale reward/claim with output to relayer/solver/user-controlled recipient.
- Observed production calls include approvals, router calls, ERC20 transfers and external targets, so this is a real relayer execution surface.

LIKELIHOOD / FEASIBILITY: High primitive / Medium economic proof

POC STEPS:
1. Fork mainnet at a block close to one of the successful `permit2TransferAndMulticall` txs above.
2. Use decoded tx as template: same proxy address, same Permit2 permit, same `calls`, same metadata.
3. Induce fail: modify fork state so one required call target reverts, or remove token balance/approval before execution.
4. Verify reusable: check Permit2 nonce bitmap/allowance state unchanged after revert.
5. Restore state: fund token balance, restore target state/liquidity/approval.
6. Replay exact same proxy calldata.
7. Verify stale execution: Permit2 nonce consumed, downstream calls succeed, output asset/state changes atomically.

## 3. Universal Router + Permit2

PROJECT: Uniswap Universal Router / Permit2

CHAIN: Abstract mainnet

CONTRACT:
- Universal Router: `0xE1b076ea612Db28a0d768660e4D81346c02ED75e`
- Permit2: `0x0000000000225e31d15943971f47ad3022f714fa`
- Abscan router: https://abscan.org/address/0xE1b076ea612Db28a0d768660e4D81346c02ED75e

FUNCTION:
- `execute(bytes commands, bytes[] inputs, uint256 deadline)` selector `0x3593564c`
- `execute(bytes commands, bytes[] inputs)` selector `0x24856bc3`

TYPE: meta-tx / permit-like / router

REAL USAGE EVIDENCE:
- Universal Router tx count: 707,224.
- Permit2 tx count: 13,798.
- Real sampled Permit2 command txs:
  - `0xc4f2994e9ad452aa25e1f78551d3be07a1eae4eb1b5087a4b425d989d1edd4e1` — commands `0x0a08000c`, includes `PERMIT2_PERMIT`.
  - `0x3c77469f9533cf56a1647521920a970d2f8da576ffafb43afad8a7921bdfe82b` — commands `0x0a08`.
  - `0x1d304086bc64670e4da0a0af50eec1fb73b3f43c655d5fc9c17378803dcebfdc` — commands `0x0a08`.

PERMIT / AUTH MECHANISM:
- Permit2 allowance permit inside router command stream.
- Router reverts if command without allow-revert flag fails.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION: Yes

Reason:
- Permit2 permit is executed in the same transaction as later commands.
- If later required command reverts, Permit2 state update rolls back.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Concrete sampled Permit2 routes are mostly AMM swap commands, which are excluded by scope if they only do dynamic swap price calculation.
- It becomes in-scope when command stream includes NFT marketplace, launchpad, vault, bonding curve, or fixed-price action.

ECONOMIC IMPACT / PROFIT PATH:
- Medium only when bundled with fixed-price target.
- Generic swaps are excluded.

LIKELIHOOD / FEASIBILITY: Medium

POC STEPS:
1. Fork mainnet with `anvil-zksync`.
2. Select router tx with `0x0a` Permit2 command and an in-scope fixed-price downstream command.
3. Induce fail in downstream command.
4. Verify Permit2 nonce unchanged.
5. Restore state.
6. Replay exact same router calldata.
7. Verify output asset/state change.

## 4. Relay Depository

PROJECT: Relay

CHAIN: Abstract mainnet

CONTRACT:
- `0x4cD00E387622C35bDDB9b4c962C136462338BC31`
- Abscan: https://abscan.org/address/0x4cD00E387622C35bDDB9b4c962C136462338BC31

FUNCTION:
- `execute(CallRequest request, bytes signature)`

TYPE: meta-tx / relayer

REAL USAGE EVIDENCE:
- Tx count: 236,702.
- Sampled recent selectors:
  - `0x49290c1c` status 1: 91/100 sampled txs.
  - `0xe8017952` status 1: 5/100 sampled txs.
  - `0x2d9fb478` status 1: 4/100 sampled txs.

PERMIT / AUTH MECHANISM:
- EIP-712-like signed `CallRequest` checked by allocator.
- Replay guard `callRequests[structHash]`.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION: Yes

Reason:
- Replay guard is set before downstream calls.
- If a required downstream call reverts, the entire transaction reverts and replay guard rolls back.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Signed relayer request can be delayed and retried before expiration.
- Economic path depends on concrete decoded `calls`.

ECONOMIC IMPACT / PROFIT PATH:
- Potential stale payout/settlement/claim if calls target fixed-value or reward systems.
- Needs request decode from production calldata.

LIKELIHOOD / FEASIBILITY: High primitive / Medium economic proof

POC STEPS:
1. Fork mainnet.
2. Decode a real `execute` request or obtain controlled allocator signature.
3. Induce target call failure.
4. Verify `callRequests[structHash]` remains false.
5. Restore target state.
6. Replay exact calldata.
7. Verify state/value transfer.

## 5. SeaDrop ERC1155 signed mint

PROJECT: SeaDrop ERC1155 Contract Offerer

CHAIN: Abstract mainnet

CONTRACT:
- `0x00b19a5200a100e5fc4c9800772f4d002f218400`

FUNCTION:
- `generateOrder` / signed mint path
- observed selector `0x7e734c5a` in 100/100 sampled txs

TYPE: NFT / launchpad / signed mint

REAL USAGE EVIDENCE:
- Tx count: 3,627.
- All 100 sampled recent txs were status 1 with selector `0x7e734c5a`.

PERMIT / AUTH MECHANISM:
- Signed mint params verified inside `_mintSigned`.
- Replay guard `_usedDigests[digest]`.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION: Yes

Reason:
- `_usedDigests[digest] = true` is set before later validation, but full revert rolls it back.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Failed signed mint leaves signature usable.
- Replay later when price window/supply/secondary value is favorable.

ECONOMIC IMPACT / PROFIT PATH:
- Delayed mint option.

LIKELIHOOD / FEASIBILITY: Medium

POC STEPS:
1. Fork mainnet.
2. Use a real signed mint calldata or controlled signed mint params.
3. Induce fail via payment/stage/supply condition.
4. Verify digest unused after failed tx.
5. Restore state or move time.
6. Replay exact calldata.
7. Verify NFT minted and digest consumed.

## Excluded / weak after concrete scan

### Gauge reward claim

CONTRACT:
- `0xa171bb8b0805ddccc8721ccb1e13f6dd09633cfc`

Evidence:
- 38,122 tx.
- Sampled selectors: `0xc00007b0`, `0xb6b55f25`, `0x2e1a7d4d`, all status 1 in first 100 sampled txs.

Reason for exclusion:
- Gauge itself does not verify signed authorization.
- ERC2771 signature semantics live in trusted forwarder, not this contract.
- Reward is paid to `_account`, so direct relayer profit is weak unless a broader forwarder/multicall flow exists.

## Concrete next PoC command path

Use Linux with working network:

```bash
./anvil-zksync --host 0.0.0.0 --port 8011 fork --fork-url abstract
npm run check:zksync-fork
```

For Seaport-specific PoC:

```text
target tx template: 0x2526ca20b4e170442509941b4bfd5dd443594d1d1cc8b047d3bd811f8e87aefa
contract: 0xDF3969A315e3fC15B89A2752D0915cc76A5bd82D
selector: 0xe7acab24
expected fail phase: payment/approval/transfer revert
verify after fail: order status remains unfilled
restore: fund buyer / approval
replay: exact same calldata
verify: NFT ownership + stale consideration
```

For Relay Permit2 PoC:

```text
target tx template: 0xf94fdf0017480284abe66fef112de8d6d46f9b85c183fae8b390198b059430d4
contract: 0xccc88a9d1b4ed6b0eaba998850414b24f1c315be
selector: 0x0a2b8f36
permit deadline: 1778608121
expected fail phase: downstream call with allowFailure=false
verify after fail: Permit2 nonce/bitmap unchanged
restore: target state / token balance / approval
replay: exact same calldata
verify: Permit2 nonce consumed and downstream state changed
```

