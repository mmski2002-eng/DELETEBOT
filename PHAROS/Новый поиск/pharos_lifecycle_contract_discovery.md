# Pharos Mainnet Lifecycle-Contract Discovery

Network: Pharos Mainnet, chainId `1672 / 0x688`  
RPC: `https://rpc.pharos.xyz`  
SocialScan API: `https://api.socialscan.io/pharos-mainnet/v1`

## 1. Discovery method

I used a limited discovery pass, not a deep audit:

- sampled recent SocialScan transaction pages and grouped non-trivial contract calls by target address;
- used address transaction endpoints for high-activity contracts;
- queried verified source/ABI metadata for candidate contracts;
- searched SocialScan by lifecycle-ish terms such as `bridge`, `vault`, `staking`, `refund`, `cancel`, `queue`, `settle`, `receiver`, `airdrop`;
- re-used known closed-path addresses only to reject or downgrade them where appropriate.

The strongest recent activity cluster not already closed was DODO routing:

- `DODOFeeRouteProxy` at `0xa5ca5fbe34e444f366b373170541ec6902b0f75c`
- about `100,992` address txs from SocialScan address transaction endpoint at discovery time
- recent representative tx `0xdbe7b075e43bc11eafb89c2778858ddfcf7d7c3b832f4e92e1dabbc101b5ef98`
- representative decoded method: `mixSwap(...)`
- representative event: `OrderHistory(...)`
- real native/token value movement

## 2. Candidate table

| address | name/label | verified/proxy status | representative tx | lifecycle signals | value movement | external domain | score | verdict |
|---|---|---|---|---|---|---|---:|---|
| `0xa5ca5fbe34e444f366b373170541ec6902b0f75c` | `DODOFeeRouteProxy` | verified, non-proxy | `0xdbe7b075...ef98`; sample `0x3de490ee...327f` decoded in detail | `mixSwap`, `externalSwap`, `dodoMutliSwap`, `deadLine`, `minReturnAmount`, `OrderHistory`, route fee config, whitelist config, `superWithdraw` | yes, native/WPROS/USDC and routed token transfers | no cross-chain, but external pool/adapters | 31 | STRONG CANDIDATE |
| `0x4146d192da6428c9e1c243d2a953c625b5765623` | DODO GSP/UniV3 pool-like pair from DODO route | unverified at address; code exists; source available in DODO bundle as GSP/UniV3 interfaces | appears as `mixPairs[0]` in `0x3de490ee...327f` | pool swap/reserve/share lifecycle inferred from route and bundled GSP source; likely reserve/accounting state | yes, receives/returns route assets | no | 24 | MAYBE |
| `0x7126c3fef4e6a680eee09fb039b2236f638384b0` | `FiatTokenProxy` / Bridged USDC.e token | verified proxy contract ABI; token search result says Bridged USDC (Pharos) | `0x93c80059...b7f7` | `transfer`, proxy upgrade surface, mint/burn/pause/blacklist in implementation family if active | yes | bridged asset identity only; no bridge lifecycle visible here | 26 | MAYBE |
| `0xff70f4a1d11995621854f3692acf286d8acd04b2` | `LiFiDiamond` | verified diamond | `0x5c95a16d...11d5`; failed sample `0x49568d66...ae48` | bridge/swap start events, failed/success route statuses, cross-chain message lifecycle | yes, high-value route txs | yes, Glacis/CCIP/Base | 28 | REJECT for this pass: prior bridge-completion direction already sampled cleanly |
| `0x40858070814a57fdf33a613ae84fe0a8b4a874f7` | CCIP `OffRamp` | verified | `0xaf63b84b...2ff`; prior sample `0x389b34ef...7d41` | `commit`, `execute`, `manuallyExecute`, `getExecutionState`, `ExecutionStateChanged`, `CommitReportAccepted` | possible for user messages; sampled recent commits had none | yes, CCIP | 27 | REJECT for now: sampled activity was operational reports with empty roots |
| `0x76c9cf548b4179f8901cda1f8623568b58215e62` | `KeystoneForwarder` | verified | `0xbe1cbe2c...419d`; prior sample `0x3ddc9b...316a` | `report`, `ReportProcessed`; receiver updates cache | no token value | oracle/report path | 20 | REJECT: feed state reconciled in previous triage |
| `0x7c06f7d4e0f77b5e1d6499f2a1dc291de044f100` | `TokenDistributor` | verified, non-proxy | `0x109e1f22...a7e`; prior sample `0xbf9b95...a857` | `claim`, `claimedAmounts`, `totalClaimed`, Merkle proof, time window | yes, USDC | no | 24 | REJECT: consumed-state proof already matched |
| `0x7435fb3dceb1a3a21fa66c6e4913f9925599a80d` | `Vault Share` token search result | code exists but SocialScan contract metadata not available; only 4 txs seen | `0x43be1e2f...7e1c` | token name suggests vault, but txs observed were simple approvals | maybe | no evidence | 12 | REJECT |

Scoring categories were 0-5 each:

1. lifecycle complexity
2. observer disagreement potential
3. state verifiability
4. value/accounting relevance
5. novelty versus closed paths
6. testability
7. evidence availability

## 3. Rejected candidates

- `LiFiDiamond`: real lifecycle complexity, but the Pharos -> Base bridge-completion mismatch direction was already tested and resolved cleanly in sampled flows. Keep only for a different, explicitly scoped failed-route audit.
- CCIP `OffRamp`: strong contract-level lifecycle, but recent sampled commits were operational reports with no user-message roots. Do not continue without first finding non-empty message execution candidates.
- `KeystoneForwarder`: prior sample reconciled `ReportProcessed` / `AnswerUpdated` with canonical cache storage.
- `TokenDistributor`: prior sample reconciled `Claimed`, transfer, consumed marker, and repeat-call rejection.
- `Vault Share` token: low activity, no verified contract metadata from SocialScan code endpoint, no visible lifecycle beyond token approvals.
- `UniV3Adapter`: verified adapter, but it is part of DODO route execution rather than a lifecycle owner; useful only as supporting context for the DODO target.

## 4. Top 3 mini-analyses

### Candidate 1: DODOFeeRouteProxy

Mental model: Users submit routed swaps with expected/minimum return, deadline, adapters/pairs, and optional fee data. The route executes atomically across adapters/pools, then emits `OrderHistory` with from/to token, sender, input amount, and return amount. A human or backend can treat `OrderHistory` as swap completion, but the stronger proof is token balance movement and min-return/deadline semantics.

Lifecycle objects:

- route/order attempt
- adapter/pool hop
- output token settlement
- route fee / positive slippage handling

Lifecycle events:

- `OrderHistory(fromToken,toToken,sender,fromAmount,returnAmount)`
- `PositiveSlippage(token,amount)`
- token `Deposit`, `Transfer`, pool swap events in called contracts

Public state:

- `routeFeeRate()`
- `routeFeeReceiver()`
- `totalWeight()`
- `isWhiteListedContract(address)`
- `isApproveWhiteListedContract(address)`
- `_WETH_()`
- `_DODO_APPROVE_PROXY_()`
- owner/config functions for whitelist and route fee

Weird states to test:

1. `OrderHistory` return amount says route completed, but recipient token balance delta differs because a fee/slippage path changed settlement.
2. The route emits success-like history while an intermediate pool/adaptor event shows a different asset or amount than the final recipient received.
3. Config or whitelist state changes between quoted route calldata and execution, so the same UI route meaning no longer matches the on-chain route path.

Fastest safe next test:

Pick 5 recent `mixSwap` txs, compare calldata `minReturnAmount/expReturnAmount/deadLine`, `OrderHistory.returnAmount`, token transfer deltas to the sender, route-fee receiver transfers, and `trace` calls to adapters/pools.

### Candidate 2: DODO pool / GSP pair in routed swap

Mental model: The pool/pair address appears as a route `mixPairs` target and moves assets during DODO route execution. It likely owns reserve/share/accounting state that determines swap output and LP lifecycle. Because the address itself is not cleanly verified in SocialScan, confidence is lower, but the source bundle used by DODO includes GSP pool contracts and interfaces.

Lifecycle objects:

- pool reserve state
- swap hop
- LP share/deposit/withdraw state if GSP source matches runtime

Lifecycle events:

- not decoded from SocialScan for the pair address in this pass
- route tx showed token transfers around this pair and DODO route-level `OrderHistory`

Public state:

- unknown from SocialScan ABI for the deployed pair
- possible GSP-derived reads from bundled source if runtime match can be established

Weird states to test:

1. Route-level event says a swap returned amount X, while pool reserve delta indicates a different effective hop output.
2. Pool token transfer direction differs from the route path encoded in `mixSwap`.
3. The pair runtime does not match the bundled source/interface assumptions used to decode route semantics.

Fastest safe next test:

Fetch runtime code hash for `0x4146...5623`, compare against known DODO GSP/pool compiled artifacts if available, then trace a recent DODO route and reconcile pair token deltas with route output.

### Candidate 3: Bridged USDC.e `FiatTokenProxy`

Mental model: This token is labeled as Bridged USDC (Pharos) and has proxy/upgradable token semantics. Token transfers are simple, but mint/burn/pause/upgrade/bridge-origin semantics can affect what a UI means by "bridged USDC". The lifecycle complexity is weaker unless mint/burn or bridge-side admin events are found.

Lifecycle objects:

- token balance
- bridged asset representation
- proxy implementation state
- mint/burn/pause/admin state if visible in implementation activity

Lifecycle events:

- `Transfer`
- proxy `Upgraded`, `AdminChanged` if used
- implementation-family events such as `Mint`, `Burn`, `Pause`, `Unpause`, `Blacklisted`, depending on active implementation and tx history

Public state:

- proxy `implementation()`, `admin()`
- token reads through proxy if non-admin call path is usable
- implementation ABI includes `paused()`, `isBlacklisted(address)`, `totalSupply()`, `balanceOf(address)`

Weird states to test:

1. Token label says bridged asset, but no bridge/mint source evidence is visible for a balance-changing tx.
2. Proxy metadata / active implementation differs from the ABI used to decode token lifecycle events.
3. Pause/admin state changes between a bridge/mint source action and a user-facing token transfer status.

Fastest safe next test:

Search recent `Mint`/`Burn`/`Upgraded`/`Pause` logs for `0x7126...84b0`, then compare active implementation storage with SocialScan metadata and token supply/balance deltas.

## 5. Chosen next target

Chosen target: `DODOFeeRouteProxy` swap/order lifecycle.

Why it wins:

- It is not one of the already closed paths.
- It has very high recent activity: about `100,992` address txs in SocialScan's address transaction endpoint.
- It is verified and has ABI/source.
- It moves real value and tokens.
- It has event-derived completion semantics via `OrderHistory`.
- It has route inputs that can be objectively checked: `fromTokenAmount`, `expReturnAmount`, `minReturnAmount`, `deadLine`, adapters, pairs, asset recipients, fee data.
- It has mutable config that can affect route meaning: route fee, whitelist, approve whitelist, owner-controlled parameters.

Representative tx:

- `0xdbe7b075e43bc11eafb89c2778858ddfcf7d7c3b832f4e92e1dabbc101b5ef98`

Detailed decoded sample used during discovery:

- `0x3de490eec96536f9f1cdcf59ccca1914413fa00b0350eb6741a3443bc14b327f`
- method: `mixSwap(address,address,uint256,uint256,uint256,address[],address[],address[],uint256,bytes[],bytes,uint256)`
- route input: native PROS -> USDC
- `fromTokenAmount = 26840000000000000000`
- `expReturnAmount = 19831748`
- `minReturnAmount = 19633431`
- `OrderHistory.returnAmount = 19831748`
- token logs include WPROS deposit/transfer and USDC transfer to sender

Exact next prompt focus:

`Pharos Mainnet DODOFeeRouteProxy OrderHistory vs actual swap settlement: compare calldata minReturn/deadline/route, emitted OrderHistory returnAmount, token balance deltas, route fee/slippage transfers, adapter/pool traces, and mutable route config for 5 recent mixSwap/externalSwap txs.`

## 6. Stop condition

Abandon this target during Stage 1 if 5 recent DODO route txs all show:

- receipt status success and no misleading failed-route labels;
- `OrderHistory.returnAmount` equals actual recipient output token delta after accounting for route fees/slippage;
- output token and recipient match the calldata route semantics;
- `minReturnAmount` is respected;
- `deadLine` is not expired at block timestamp;
- no route-fee/positive-slippage transfer is hidden from the event-derived result;
- adapter/pool traces and final token movements agree;
- no config/state change affects the route between calldata construction assumptions and execution.

Final judgment:

STRONG_NEXT_TARGET_FOUND: proceed with focused lifecycle audit on DODOFeeRouteProxy swap/order lifecycle.
