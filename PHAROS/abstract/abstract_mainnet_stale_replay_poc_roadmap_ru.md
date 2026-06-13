# Abstract mainnet: production candidates для stale / replay / failed-execution permit

Дата: 2026-05-12. Scope: только Abstract mainnet, production-used контракты с verified source и активной историей.  
Формат: candidates для fork/testnet PoC, не инструкция для live exploitation.

## Короткий рейтинг

1. **Seaport + Universal Router / Permit2**: лучший NFT fixed-price candidate. Есть official Abstract deployment, 633k tx у Seaport и 707k tx у Universal Router.
2. **Relay Depository**: лучший signed CallRequest / delayed relayer candidate. 236k tx, replay guard откатывается при downstream revert.
3. **Relay Approval Proxy V3 + Router V3**: лучший permit-like multicall candidate. 41k tx у proxy и 142k tx у router.
4. **LayerZero LZMultiCall**: signed multicall candidate. 2.9k tx, nonce откатывается при revert.
5. **SeaDrop ERC1155 Contract Offerer**: NFT launchpad/signed mint candidate. 3.6k tx, signed mint digest откатывается при failed mint.
6. **Aborean/Veldrome-style Gauge с ERC2771Context**: reward claim watchlist. 38k tx, но signed authorization живет во внешнем forwarder, поэтому нужен отдельный source/tx decode trusted forwarder.

## 1. NFT fixed-price: Seaport на Abstract + Universal Router / Permit2

PROJECT: Seaport / Uniswap Universal Router NFT flow

CHAIN: Abstract mainnet

CONTRACT:
- Seaport: `0xDF3969A315e3fC15B89A2752D0915cc76A5bd82D`
- Universal Router: `0xE1b076ea612Db28a0d768660e4D81346c02ED75e`
- Permit2: `0x0000000000225e31d15943971f47ad3022f714fa`
- Official Abstract docs list these mainnet deployments: https://docs.abs.xyz/tooling/deployed-contracts
- Abscan: https://abscan.org/address/0xDF3969A315e3fC15B89A2752D0915cc76A5bd82D
- Abscan: https://abscan.org/address/0xE1b076ea612Db28a0d768660e4D81346c02ED75e

FUNCTIONS:
- Seaport `fulfillBasicOrder`
- Seaport `fulfillOrder`
- Seaport `fulfillAdvancedOrder`
- Seaport `_validateAndFulfillAdvancedOrder`
- Seaport `_updateStatus`
- Universal Router `execute(bytes commands, bytes[] inputs, uint256 deadline)`
- Universal Router command `PERMIT2_PERMIT`, `PERMIT2_TRANSFER_FROM`, `SEAPORT`

TYPE: NFT / fixed-price trades / meta-router / permit-like

REAL USAGE EVIDENCE:
- Seaport: 633,574 tx on Abscan.
- Universal Router: 707,224 tx on Abscan.
- Permit2: 13,798 tx on Abscan.
- These are official Abstract mainnet deployed contracts, not staging.

PERMIT / AUTH MECHANISM:
- Seaport orders are off-chain signed orders with order hash, offer/consideration, start/end time, salt, conduit key, zone.
- Universal Router can combine Permit2 authorization with NFT marketplace execution.
- Permit2 nonce/deadline and Seaport order status are consumed only if the transaction commits.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Yes.
- In Seaport, `_updateStatus` can mark an order filled before item transfers, but any later revert in `_transferEach` reverts the whole transaction and rolls back the status update.
- In Universal Router, a command failure with `successRequired` causes `ExecutionFailed`, reverting prior Permit2 permit/transfer effects in the same tx.
- Therefore a failed Seaport fill or failed router sequence can leave the signed order / Permit2 authorization reusable until expiry, unless another successful fill/cancel consumes it.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Seller signs fixed-price NFT sale.
- Buyer/relayer intentionally makes fulfillment fail during an unfavorable moment, for example insufficient buyer balance, insufficient Permit2 allowance, missing msg.value, temporary NFT approval/ownership issue, or forced downstream command failure.
- The signed order remains live.
- Later, if floor price rises above the stale fixed price, the same signed order can be replayed before `endTime`.
- With Universal Router, a single leaked/reused route may bundle Permit2 funding plus Seaport purchase.

ECONOMIC IMPACT / PROFIT PATH:
- Classic stale fixed-price NFT sale: buy NFT at old signed price after market moves.
- Profit path: acquire underpriced NFT, immediately list/sell at current floor, or capture spread between stale consideration and current market value.
- This is the closest Abstract candidate to MoonBeans-style stale favorable execution for NFT sales.

LIKELIHOOD / FEASIBILITY:
- High.
- This is expected marketplace behavior unless mitigated by short expirations/cancellations, but it fits the requested primitive: failed execution does not consume the signed order, and delayed execution can be economically favorable.

FORK / TESTNET POC ROADMAP:
- fail: fork Abstract at a block with an active Seaport fixed-price listing, or recreate an equivalent listing on testnet. Attempt fulfillment with intentionally insufficient payment or missing approval so transfer fails.
- leak permit/signature: capture the same signed order payload and, if using Universal Router, the same Permit2/router inputs in the local test harness.
- replay: restore buyer funds/allowance or advance state to a more favorable simulated floor price while keeping order within `endTime`.
- execution: replay the same order/router calldata on fork/testnet.
- verify stale NFT sale: assert Seaport order status was unchanged after failed tx, then filled after replay; assert NFT owner changed and consideration paid at stale fixed price.

## 2. Relay Depository

PROJECT: Relay

CHAIN: Abstract mainnet

CONTRACT:
- `0x4cD00E387622C35bDDB9b4c962C136462338BC31`
- Abscan: https://abscan.org/address/0x4cD00E387622C35bDDB9b4c962C136462338BC31

FUNCTIONS:
- `execute(CallRequest request, bytes signature)`
- `_executeCalls`
- `callRequests(bytes32)`

TYPE: meta-tx / relayer / signed authorization / cross-contract calls

REAL USAGE EVIDENCE:
- 236,702 tx on Abscan.
- Verified Relay production contract.

PERMIT / AUTH MECHANISM:
- EIP-712-style `CallRequest`.
- `CallRequest` contains `Call[] calls`, `nonce`, `expiration`.
- Signature is validated against `allocator.isValidSignatureNow(eip712Hash, signature)`.
- Replay guard is `callRequests[structHash]`.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Yes.
- Contract sets `callRequests[structHash] = true` before `_executeCalls`.
- If any call with `allowFailure=false` reverts, the full tx reverts and `callRequests[structHash]` rolls back to false.
- Same signed request can remain reusable until `expiration`.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- A solver/relayer receives a signed CallRequest and controls execution timing.
- Initial execution fails due to balance, target state, liquidity, slippage guard, closed claim window, or downstream revert.
- Because replay guard is rolled back, the same signed request can be retried later.
- If calls include payout, fixed-price purchase, vault action, NFT settlement, or reward/claim target, delayed execution can become favorable.

ECONOMIC IMPACT / PROFIT PATH:
- Option-like relayer execution window.
- Impact depends on the decoded `calls`; strongest paths are stale payout, fixed-value settlement, stale bridge/depository release, or stale purchase with output to relayer-controlled recipient.

LIKELIHOOD / FEASIBILITY:
- High as a replay-on-revert primitive.
- Economic proof requires decoding real `CallRequest.calls` and finding price/reward-sensitive targets.

FORK / TESTNET POC ROADMAP:
- fail: build or extract a signed CallRequest with one call that reverts under current simulated state, with `allowFailure=false`.
- leak permit/signature: store the identical `request` and `signature` after the failed local transaction.
- replay: mutate fork/testnet state so downstream target succeeds, for example fund account, restore allowance, move time into valid claim window, seed liquidity, or satisfy vault/claim condition.
- execution: submit identical `execute(request, signature)`.
- verify stale reward/fixed execution: compare `callRequests[structHash]` before/after failed tx, verify it is still false after failure and true after success; assert output asset/reward/NFT moved on replay.

## 3. Relay Approval Proxy V3 + Router V3

PROJECT: Relay

CHAIN: Abstract mainnet

CONTRACT:
- Approval Proxy V3: `0xccc88a9d1b4ed6b0eaba998850414b24f1c315be`
- Router V3: `0xb92fe925DC43a0ECdE6c8b1a2709c170Ec4fFf4f`
- Abscan: https://abscan.org/address/0xccc88a9d1b4ed6b0eaba998850414b24f1c315be
- Abscan: https://abscan.org/address/0xb92fe925DC43a0ECdE6c8b1a2709c170Ec4fFf4f

FUNCTIONS:
- `permitTransferAndMulticall`
- `permit2TransferAndMulticall`
- `permit3009TransferAndMulticall`
- Router `multicall`
- Router `_aggregate3Value`

TYPE: meta-tx / permit-like / relayer flow / arbitrary multicall

REAL USAGE EVIDENCE:
- Approval Proxy V3: 41,262 tx on Abscan.
- Router V3: 142,091 tx on Abscan.
- Verified Relay contracts.

PERMIT / AUTH MECHANISM:
- ERC-2612 permit via `trustlessPermit`.
- Permit2 `permitWitnessTransferFrom`.
- ERC-3009 `receiveWithAuthorization`.
- Witness hash binds relayer `msg.sender`, `refundTo`, `nftRecipient`, `metadata`, and calls hash.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Yes.
- Proxy consumes permit/authorization and transfers tokens to router before calling router `multicall`.
- If router call reverts because a required call fails, full tx reverts and authorization consumption is rolled back.
- Same permit/signature can remain valid until token/Permit2 deadline.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- User signs fixed token amount and fixed call bundle.
- Solver can delay until downstream price/liquidity/NFT/claim state becomes favorable.
- If an initial execution fails, permit remains reusable and can be retried later.
- Exclude generic AMM exactInput/exactOutput-only cases unless the bundle contains fixed external settlement, NFT, vault, reward, or bonding-curve behavior.

ECONOMIC IMPACT / PROFIT PATH:
- Option value over signed funding + multicall route.
- Potential profit if the route targets a fixed-price NFT sale, fixed-ratio vault, launchpad mint, bonding curve, or claim that becomes more favorable before deadline.

LIKELIHOOD / FEASIBILITY:
- High primitive, medium economic certainty until real payloads are decoded.

FORK / TESTNET POC ROADMAP:
- fail: take a real or synthetic `permit2TransferAndMulticall` where a required downstream call reverts.
- leak permit/signature: preserve identical permit, witness, calls, metadata, refund/nft recipient.
- replay: adjust state so downstream target succeeds while permit deadline remains valid.
- execution: resubmit the exact same proxy call.
- verify stale favorable execution: check Permit2/token authorization nonce unchanged after failed tx, then consumed after replay; verify downstream target output improved versus initial state.

## 4. LayerZero LZMultiCall

PROJECT: LayerZero / LZMultiCall

CHAIN: Abstract mainnet

CONTRACT:
- `0xa8752e1ceeab44cd84214ebfcefd9c8cb535fb98`
- Abscan: https://abscan.org/address/0xa8752e1ceeab44cd84214ebfcefd9c8cb535fb98

FUNCTIONS:
- `execute(Call[] calls, bytes32 quoteId, uint256 expiration, address signer, bytes signature)`
- `_executeCalls`
- `_handleTransfer`
- `_handleCall`

TYPE: meta-tx / signed multicall / relayer flow

REAL USAGE EVIDENCE:
- 2,897 tx on Abscan.
- Verified production contract.

PERMIT / AUTH MECHANISM:
- EIP-712 digest over calls, `quoteId`, `expiration`, and current `nonces[signer]`.
- Signature checked with `SignatureChecker.isValidSignatureNow`.
- Nonce increments before calls but is reverted on failed tx.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Yes.
- `_handleCall` bubbles target reverts.
- If a signed call fails, nonce increment rolls back, so same signature can be replayed until expiration if no other successful tx uses the nonce.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Signed quote/call bundle is held by relayer.
- Temporary failure preserves signature.
- Later replay succeeds when state/liquidity/approval/reward condition changes.

ECONOMIC IMPACT / PROFIT PATH:
- Option-like timing over a signed quote bundle.
- Strongest if real payload includes fixed transfer delegate plus settlement/mint/vault call.

LIKELIHOOD / FEASIBILITY:
- Medium-high primitive, medium economic certainty.

FORK / TESTNET POC ROADMAP:
- fail: submit signed `execute` with a target call that reverts.
- leak permit/signature: preserve identical calls, quoteId, expiration, signer, signature.
- replay: mutate state so target call succeeds before expiration.
- execution: replay identical signed execute.
- verify stale execution: assert nonce unchanged after failed tx and incremented only after successful replay.

## 5. SeaDrop ERC1155 Contract Offerer / signed mint

PROJECT: SeaDrop / ERC1155 launchpad-style mint

CHAIN: Abstract mainnet

CONTRACT:
- `0x00b19a5200a100e5fc4c9800772f4d002f218400`
- Abscan: https://abscan.org/address/0x00b19a5200a100e5fc4c9800772f4d002f218400

FUNCTIONS:
- Seaport contract-offerer `generateOrder`
- `_createOrder`
- `_mintSigned`
- `_currentPrice`
- `_validateMint`

TYPE: NFT / launchpad / signed mint

REAL USAGE EVIDENCE:
- 3,627 tx on Abscan.
- Verified NFT mint/contract-offerer contract.

PERMIT / AUTH MECHANISM:
- ECDSA signed mint params.
- Digest includes minter, fee recipient, mint params and salt.
- `_usedDigests[digest]` is replay guard.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Yes.
- `_usedDigests[digest] = true` is set before later validation/mint effects, but any revert rolls it back.
- Failed mint leaves digest reusable until mint params expire or successful mint consumes it.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Signed mint can encode fixed price or dynamic start/end price.
- Failed execution preserves signed mint authorization.
- Replay later can be favorable if Dutch price decreases, supply state changes, or secondary market rises.

ECONOMIC IMPACT / PROFIT PATH:
- NFT mint option: hold/retry signed mint and execute when mint price or resale value becomes favorable.

LIKELIHOOD / FEASIBILITY:
- Medium.
- Likely intentional for drop mechanics, but still fits stale/replay-on-revert candidate class.

FORK / TESTNET POC ROADMAP:
- fail: simulate signed mint with invalid payment, inactive stage, or condition that reverts after digest check.
- leak permit/signature: preserve signed mint params, salt, signature.
- replay: move block timestamp/state into favorable valid stage or lower price window.
- execution: replay same mint.
- verify stale NFT mint: assert digest unused after failure and used after replay; compare mint price/value at replay time.

## 6. Reward claim watchlist: Aborean/Veldrome-style Gauge with ERC2771Context

PROJECT: Aborean / Veldrome-style Gauge

CHAIN: Abstract mainnet

CONTRACT:
- Gauge example: `0xa171bb8b0805ddccc8721ccb1e13f6dd09633cfc`
- Voter example: `0xc0f53703e9f4b79fa2fb09a2aeba487fa97729c9`
- Abscan Gauge: https://abscan.org/address/0xa171bb8b0805ddccc8721ccb1e13f6dd09633cfc

FUNCTIONS:
- Gauge `getReward(address account)`
- Voter `claimRewards(address[] gauges)`
- Gauge inherits `ERC2771Context`

TYPE: reward / staking / meta-tx watchlist

REAL USAGE EVIDENCE:
- Gauge: 38,122 tx on Abscan.
- Contract balance shown by Abscan around $10k at check time.
- Verified source, active gauge/reward flow.

PERMIT / AUTH MECHANISM:
- Gauge itself does not verify signatures.
- It trusts an ERC-2771 forwarder supplied at construction.
- The signed authorization/replay logic must be inspected in the trusted forwarder, not only in Gauge.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Unconfirmed.
- If the trusted forwarder consumes nonce in the same transaction and reverts on target failure, failed `getReward` could leave the meta-tx signature reusable.
- Gauge `getReward` itself sets `rewards[account] = 0` before token transfer, but a transfer revert rolls back the reward state.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- A user signs a gasless `getReward`.
- Relayer intentionally causes/observes failed claim, keeps signed forward request, then replays when rewards grow or token/state changes.
- This only works if forwarder signature remains valid and `getReward` recomputes claimable reward upward on replay.

ECONOMIC IMPACT / PROFIT PATH:
- Potential stale reward claim / gasless claim timing.
- Profitability depends on whether relayer can redirect output. In current Gauge, reward goes to `_account`, so direct relayer profit is weak unless the forward request targets a claim-and-transfer multicall elsewhere.

LIKELIHOOD / FEASIBILITY:
- Low-medium until trusted forwarder is identified and decoded.
- Keep as reward-system watchlist, not primary exploit candidate.

FORK / TESTNET POC ROADMAP:
- fail: identify trusted forwarder from constructor args or factory tx; submit signed forward request calling `getReward` where token transfer/target call reverts.
- leak permit/signature: preserve signed forward request.
- replay: advance time/reward accrual or repair transfer condition.
- execution: replay same forward request.
- verify stale reward: assert forwarder nonce unchanged after failure, reward unchanged/increased, and claim succeeds on replay.

## Negative filters / excluded

- Generic AMM exactInput/exactOutput swaps are excluded unless bundled with fixed external settlement, NFT, vault, claim, launchpad, or bonding curve logic.
- Plain ERC20 permit tokens are excluded when permit is not coupled to a price-sensitive execution path.
- Admin/governance/paused/upgrade attacks are out of scope.
- AGW account contracts and Safe-style multisig flows need separate analysis; they are not included here unless a specific production payload shows stale economic execution.

## General fork/testnet harness plan

1. Pick candidate and collect a real successful tx plus, ideally, a failed tx with same function family.
2. Decode signed payload:
   - Seaport: order parameters, signature, start/end time, offer/consideration.
   - Permit2/Relay: permit nonce/deadline/witness/calls.
   - Depository/LZ: typed request, nonce/expiration, calls.
3. On fork/testnet, force `fail` with a reversible condition:
   - insufficient buyer balance or msg.value;
   - missing approval/allowance;
   - downstream target revert;
   - slippage/liquidity condition;
   - inactive mint/claim window.
4. After failed tx, verify replay guard/nonce/order status is unchanged.
5. Keep identical signature/calldata and mutate only chain state/time within allowed deadline.
6. Replay identical signature/calldata.
7. Verify economic stale result:
   - NFT transferred at old fixed price;
   - reward claim amount/time improved;
   - vault/bonding-curve output changed favorably;
   - relayer/solver recipient captured value;
   - nonce/order status consumed only after successful replay.
