# Pharos Mainnet Observer Disagreement Report

Date: 2026-05-13

Target: Pharos Pacific Ocean Mainnet only.

Network boundary:

- Chain ID: `1672 / 0x688`
- RPC: `https://rpc.pharos.xyz`
- Explorer: `https://pharosscan.xyz`
- Explorer/indexer backend observed in page HTML: `https://api.socialscan.io/pharos-mainnet/v1`

This pass is read-only. It compares observer layers: RPC, explorer/indexer API, decoded logs, token-transfer views, traces, contract code presence, block tags, and finality wording. It does not test live users, move funds, submit transactions, or provide exploit code.

## 1. Scope and Method

This pass only analyzes observer disagreement across:

- direct JSON-RPC state and receipts;
- explorer transaction/address/token/log displays as exposed through SocialScan-backed Pharosscan;
- event-derived token transfer records;
- trace-derived/internal transaction records;
- block/header depth and finality tags;
- UI-style status labels such as Mainnet/Active, method names, success/failure, transfers, and event names.

Checks performed:

- `eth_chainId`: returned `0x688`.
- `eth_blockNumber`: used to compute block depth during the selected transaction batch.
- `eth_getTransactionByHash`
- `eth_getTransactionReceipt`
- `eth_getBlockByNumber`
- `eth_getBlockByHash`
- `eth_getCode`
- `eth_getLogs`
- `eth_call` to ERC20 `balanceOf(address)` for selected token-transfer checks.
- SocialScan API:
  - `/explorer/transactions?page=...`
  - `/explorer/transaction/{tx}`
  - `/explorer/transaction/{tx}/logs`
  - `/explorer/transaction/{tx}/token_transfers`
  - `/explorer/transaction/{tx}/internal_transactions`
  - `/explorer/stats`

Finality tag check:

- `eth_getBlockByNumber("latest", false)`, `eth_getBlockByNumber("safe", false)`, and `eth_getBlockByNumber("finalized", false)` returned the same block in the sampled call.
- Pharosscan fetched HTML and SocialScan API did not expose a transaction-specific finality threshold in the sampled transaction pages/API responses.
- A later near-simultaneous sample showed SocialScan `/explorer/stats.latest_block = 7,197,443` while RPC `eth_blockNumber = 0x6dd307 = 7,197,447`, a four-block display/API lag at that moment. This is not an issue by itself; it is evidence that observer layers can be temporarily out of sync.

### Observer Layers

Layer: RPC transaction receipt
Source: `eth_getTransactionReceipt`
Observed data: inclusion block, block hash, status `0x1/0x0`, gas used, effective gas price, raw logs.
Missing data: human method label, decoded events, business-level completion, external chain delivery.
Status vocabulary: `status = 0x1` or `0x0`.
Canonical or derived: canonical execution result for that transaction.
Can lag: yes, before inclusion or if RPC is behind.
Can be wrong if: RPC node is stale or non-canonical.
Verification method: cross-check receipt block hash with `eth_getBlockByHash`, compare logs count with explorer API.

Layer: RPC block/header
Source: `eth_getBlockByNumber`, `eth_getBlockByHash`, `eth_blockNumber`
Observed data: block number, hash, parent hash, timestamp, roots, transaction hashes.
Missing data: explorer indexing status, business completion, external confirmations.
Status vocabulary: `latest`, `safe`, `finalized`, explicit block number.
Canonical or derived: canonical for the serving RPC node.
Can lag: yes.
Can be wrong if: RPC node is stale or serving a different head.
Verification method: compare block hash/number with receipt and indexer.

Layer: RPC state reads
Source: `eth_getCode`, `eth_call`, `eth_getStorageAt` if slot known.
Observed data: code presence, public state values, historical state where node supports it.
Missing data: decoded contract meaning unless ABI/source is known.
Status vocabulary: raw bytes/return data.
Canonical or derived: canonical state at requested block tag/number.
Can lag: yes when reading `latest`.
Can be wrong if: wrong block tag or ABI interpretation.
Verification method: historical block reads before/after transaction.

Layer: RPC balance reads
Source: `eth_getBalance`, ERC20 `balanceOf` via `eth_call`
Observed data: native or token balance at block.
Missing data: why balance changed; event names; bridge or app-level settlement.
Status vocabulary: numeric balance.
Canonical or derived: canonical state at requested block.
Can lag: yes at `latest`.
Can be wrong if: token has non-standard balance semantics or wrong token address.
Verification method: compare before/after balances with Transfer logs.

Layer: Explorer transaction page
Source: `https://pharosscan.xyz/tx/{hash}` plus SocialScan API loaded by the app.
Observed data: human labels, overview, method name, status, decoded input/events after hydration.
Missing data: explicit finality threshold in sampled fetches, downstream completion.
Status vocabulary: success/failure, method names, transfer labels.
Canonical or derived: derived from indexer and ABI/event decoding.
Can lag: yes.
Can be wrong if: indexer is stale, ABI decoding is incomplete, or human label overstates meaning.
Verification method: compare to RPC receipt/logs/state.

Layer: Explorer address page
Source: Pharosscan/SocialScan address endpoints, not exhaustively crawled.
Observed data: indexed tx list, address labels, contract metadata.
Missing data: unindexed recent state and exact storage truth.
Status vocabulary: account/contract labels, token holdings, tx rows.
Canonical or derived: derived.
Can lag: yes.
Can be wrong if: indexing or metadata stale.
Verification method: direct RPC state reads and code checks.

Layer: Explorer token transfer page
Source: `/transaction/{tx}/token_transfers`
Observed data: ERC20-style Transfer-derived records.
Missing data: business-level completion, bridge destination delivery, whether transfer is mint/burn/lock/final settlement.
Status vocabulary: transferred token amount.
Canonical or derived: derived from logs.
Can lag: yes.
Can be wrong if: token is non-standard, log interpretation incomplete, or transfer is only one lifecycle step.
Verification method: compare Transfer logs and ERC20 `balanceOf` deltas.

Layer: Explorer logs/events display
Source: `/transaction/{tx}/logs`
Observed data: raw topics/data plus decoded event/function names where ABI is known.
Missing data: storage assertions unless event parameters are checked against state.
Status vocabulary: event names such as `LiFiTransferStarted`, `CommitReportAccepted`, `Transfer`, `Claimed`.
Canonical or derived: logs are canonical; names/parameters are decoded/derived.
Can lag: yes.
Can be wrong if: ABI mismatch or event name is overinterpreted.
Verification method: compare raw RPC logs count/topics and relevant storage/balances.

Layer: Explorer/indexer API
Source: `api.socialscan.io/pharos-mainnet/v1`
Observed data: transaction details, logs, token transfers, traces, contract verification metadata, stats.
Missing data: explicit finality policy and downstream app policy.
Status vocabulary: `receipt_status`, `method`, `function_name`, `trace_error_msg`, token transfer records.
Canonical or derived: mixed; receipt fields copied from chain, labels/decodes/traces derived.
Can lag: yes; sampled stats lagged RPC by four blocks.
Can be wrong if: stale index, decoder assumptions, trace backend mismatch.
Verification method: direct RPC comparison and repeated polling.

Layer: App/backend/API visible in selected flows
Source: LiFi/Glacis/CCIP labels and decoded calldata/events from Pharosscan.
Observed data: bridge integrator `pros-arb-bridge`, `destinationChainId = 8453`, CCIP-related `OnRamp`/`OffRamp`, `CCIPMessageSent`, `CommitReportAccepted`.
Missing data: destination-chain settlement status, relayer policy, confirmation threshold, app backend status.
Status vocabulary: bridge started, message sent, commit accepted.
Canonical or derived: derived from source-chain events plus external app semantics.
Can lag: yes.
Can be wrong if: source-chain success is treated as destination settlement.
Verification method: compare source tx with destination-chain records and app status API.

Layer: Bridge/relayer/oracle observer
Source: selected LiFi/CCIP/Keystone transactions.
Observed data: source-chain events and reports.
Missing data: off-chain queue state, external confirmations, oracle freshness policy.
Status vocabulary: report processed, message sent, commit report accepted.
Canonical or derived: event-derived plus off-chain policy.
Can lag: yes.
Can be wrong if: event is acted on before required confirmation depth.
Verification method: relayer/oracle confirmation policy and destination tx/proof records.

## 2. Selected Transactions

Observation batch used RPC current block `7,197,295` for the depth values below.

| # | Tx | Block | Method / contract | RPC status | API status | Logs | Token transfers | Why selected |
|---:|---|---:|---|---|---:|---:|---:|---|
| 1 | `0x53183357ffdc6ebe83e6d7e062e2e54e6e324e7ec983338860683e04f2887419` | 7,197,111 | `swapAndStartBridgeTokensViaGlacis` / `LiFiDiamond` | `0x1` | 1 | 14 | 6 | Bridge-like flow with swaps, WPROS transfers, CCIP/Glacis events, destination `8453`. |
| 2 | `0x389b34ef2c1da514f80509326413106d614c485c23b61eff2ec200019b887d41` | 7,197,106 | `commit` / `OffRamp` | `0x1` | 1 | 3 | 0 | CCIP-style OffRamp commit with `CommitReportAccepted` and `Transmitted`. |
| 3 | `0x1ffa47cb0fae32439d1d763d85d2b5f4e1268c1d1380fd8d866d2a7a9c211510` | 7,197,102 | `mixSwap` / `DODOFeeRouteProxy` | `0x0` | 0 | 0 | 0 | Failed contract call with decoded method and trace error. |
| 4 | `0xbf9b95fedab7b325f6424235ef8d8ee3d153064aa27004c87b248ff412d2a857` | 7,197,137 | `claim` / `TokenDistributor` | `0x1` | 1 | 2 | 1 | Claim flow with `Transfer` plus `Claimed`; useful for event-vs-state meaning. |
| 5 | `0x799ed1eaabb013518acae0f73dca89348d5a1cba50fa272d5c3bf5113e3fcf50` | 7,197,142 | `transfer` / `USDC` | `0x1` | 1 | 1 | 1 | Simple ERC20 transfer used as control; balance deltas were checked. |
| 6 | `0xb0e974ffe3578831b85a19721c6a6391675d632a1f1353f400984face43eaf99` | 7,197,155 | `batchBuyPixels` / `PROSPixel` | `0x1` | 1 | 2 | 0 | Unverified/proxy app contract with decoded event labels. |
| 7 | `0x3ddc9bc41af31ed6377ebd21fd1dd45ce61fa4fb7c92328f74e37e26e0df316a` | 7,197,163 | `report` / `KeystoneForwarder` | `0x1` | 1 | 2 | 0 | Oracle/report-style transaction with `AnswerUpdated` and `ReportProcessed`. |

The prompt requested at least five transactions; seven were selected because the additional failed and oracle/report flows sharpen the observer comparison.

## 3. RPC vs Explorer Comparison

| Tx | Explorer URL | Explorer/API status | RPC status | Explorer/API block | RPC block | Events by API | RPC logs | Token transfers by API | Mismatch | Semantic or cosmetic |
|---|---|---:|---|---:|---:|---|---:|---:|---|---|
| `0x5318...7419` | `https://pharosscan.xyz/tx/0x53183357ffdc6ebe83e6d7e062e2e54e6e324e7ec983338860683e04f2887419` | 1 | `0x1` | 7,197,111 | 7,197,111 | `FeesForwarded`, `AssetSwapped`, `Deposit`, `Transfer`, `Locked`, `CCIPMessageSent`, `GlacisAirliftFacet_Send`, `LiFiTransferStarted` | 14 | 6 | No factual mismatch in receipt/log count/block. | Semantic gap: source-chain success and `LiFiTransferStarted` do not prove destination-chain settlement. |
| `0x389b...7d41` | `https://pharosscan.xyz/tx/0x389b34ef2c1da514f80509326413106d614c485c23b61eff2ec200019b887d41` | 1 | `0x1` | 7,197,106 | 7,197,106 | `UsdPerUnitGasUpdated`, `CommitReportAccepted`, `Transmitted` | 3 | 0 | No factual mismatch. | Semantic gap: commit accepted is not necessarily final delivery/execution. |
| `0x1ffa...1510` | `https://pharosscan.xyz/tx/0x1ffa47cb0fae32439d1d763d85d2b5f4e1268c1d1380fd8d866d2a7a9c211510` | 0 | `0x0` | 7,197,102 | 7,197,102 | none | 0 | 0 | No mismatch. API trace error: `DODORouteProxy: Return amount is not enough`. | Mostly benign; decoded method name can still invite human overreading unless failure is prominent. |
| `0xbf9b...a857` | `https://pharosscan.xyz/tx/0xbf9b95fedab7b325f6424235ef8d8ee3d153064aa27004c87b248ff412d2a857` | 1 | `0x1` | 7,197,137 | 7,197,137 | `Transfer`, `Claimed` | 2 | 1 | No mismatch. | `Claimed` proves this claim tx executed, not any broader entitlement lifecycle unless storage confirms it. |
| `0x799e...cf50` | `https://pharosscan.xyz/tx/0x799ed1eaabb013518acae0f73dca89348d5a1cba50fa272d5c3bf5113e3fcf50` | 1 | `0x1` | 7,197,142 | 7,197,142 | `Transfer` | 1 | 1 | No mismatch. | Control case: event-derived transfer matched balance deltas. |
| `0xb0e9...af99` | `https://pharosscan.xyz/tx/0xb0e974ffe3578831b85a19721c6a6391675d632a1f1353f400984face43eaf99` | 1 | `0x1` | 7,197,155 | 7,197,155 | `PixelPremiumDistributed`, `BatchPixelsBought` | 2 | 0 | No mismatch. | Contract source not verified at proxy label level, so event labels should not be treated as full app state proof. |
| `0x3ddc...316a` | `https://pharosscan.xyz/tx/0x3ddc9bc41af31ed6377ebd21fd1dd45ce61fa4fb7c92328f74e37e26e0df316a` | 1 | `0x1` | 7,197,163 | 7,197,163 | `AnswerUpdated`, `ReportProcessed` | 2 | 0 | No mismatch. | Oracle/report event proves report acceptance/update on Pharos, not external data correctness or consumer use. |

Additional RPC checks:

- For all selected transactions, receipt block hash matched the SocialScan API block hash and `eth_getBlockByHash`.
- `eth_getCode` for each recipient returned non-empty code.
- Gas used matched between RPC and API for all selected transactions.
- The failed DODO transaction had `status = 0x0`, zero logs by RPC/API, and an API trace error. No partial event-derived state was observed.

## 4. Event vs State Findings

### LiFi/Glacis bridge-start transaction

Tx: `0x53183357ffdc6ebe83e6d7e062e2e54e6e324e7ec983338860683e04f2887419`

Important events:

- `LiFiTransferStarted`
- `CCIPMessageSent`
- `Locked`
- `Transfer`
- `AssetSwapped`
- `FeesForwarded`

What the events prove:

- The source-chain Pharos transaction executed successfully.
- LiFi emitted a transfer-start event with bridge data:
  - `bridge = glacis`
  - `integrator = pros-arb-bridge`
  - `destinationChainId = 8453`
  - `hasSourceSwaps = True`
  - `hasDestinationCall = False`
- WPROS token movement was logged and indexed.
- A lock/release pool received WPROS.
- A CCIP-style message was emitted on Pharos.

What they do not prove:

- They do not prove destination-chain receipt on chain `8453`.
- They do not prove the recipient was credited on the destination chain.
- They do not prove the bridge cannot later fail, refund, retry, or require off-chain processing.
- They do not prove an app/backend should label the whole user journey as "settled".

Storage/balance confirmation:

- RPC `balanceOf` showed WPROS balance of `LockReleaseTokenPool` increased by `2292917053782110626629` raw units, matching `2292.917053782110626629` WPROS from the indexed transfer.
- This confirms source-chain lock/accounting, not destination settlement.

Possible overinterpretation:

- Treating `LiFiTransferStarted` or `CCIPMessageSent` as "bridge complete".

Downstream risk:

- A backend, support process, or UI could tell the user "complete" based only on Pharos source events while the destination side is still pending.

Evidence needed:

- Destination-chain `8453` transaction/message status.
- LiFi/Glacis backend status for transaction id `0x6a2396340e693ff45d94010cf6708fba6570870534579ef5b5f27615501a0d25`.
- CCIP/Glacis confirmation policy and finality threshold.

### OffRamp commit transaction

Tx: `0x389b34ef2c1da514f80509326413106d614c485c23b61eff2ec200019b887d41`

Events:

- `UsdPerUnitGasUpdated`
- `CommitReportAccepted`
- `Transmitted`

What the events prove:

- The `OffRamp.commit` transaction executed successfully on Pharos.
- A commit report was accepted and transmission was logged.

What they do not prove:

- They do not prove every message in the committed report has been executed.
- They do not prove downstream app-level settlement.
- They do not prove a user-facing transfer is final.

Storage/balance confirmation:

- Not checked because exact OffRamp state variables and message ids require ABI-specific reads.

Possible overinterpretation:

- Treating `CommitReportAccepted` as "user message delivered".

Downstream risk:

- A monitoring backend could trigger "ready/complete" before execution stage.

Evidence needed:

- OffRamp ABI/source for commit state.
- Message execution transaction, if any.
- CCIP explorer/API status for the report.

### Failed DODO swap

Tx: `0x1ffa47cb0fae32439d1d763d85d2b5f4e1268c1d1380fd8d866d2a7a9c211510`

Event situation:

- No RPC logs.
- No API logs.
- No token transfers.
- API trace error: `DODORouteProxy: Return amount is not enough`.

What this proves:

- The transaction was included and failed at EVM receipt level.
- No event-derived token movement was indexed.

What it does not prove:

- It does not prove no gas/native balance was spent; gas was used.
- It does not prove a UI cannot display the decoded method in a way a human misreads.

Possible overinterpretation:

- Seeing method `Mix Swap` and assuming swap occurred despite receipt failure.

Downstream risk:

- Low in the sampled data because status is failed and logs are empty.

Evidence needed:

- Transaction-page screenshot or rendered DOM to confirm how prominent failure is visually.

### TokenDistributor claim

Tx: `0xbf9b95fedab7b325f6424235ef8d8ee3d153064aa27004c87b248ff412d2a857`

Events:

- `Transfer`
- `Claimed`

What the events prove:

- The claim call succeeded.
- USDC was transferred from `TokenDistributor` to `0x39581287bb2c105d2f9f38df6e235f64de84c682`.

Storage/balance confirmation:

- Recipient USDC balance changed from `0` to `15,630,000` raw units = `15.63` USDC.
- Distributor balance changed by `-15,630,000` raw units.

What it does not prove:

- It does not prove all future or historical entitlement state without reading the distributor storage.
- It does not prove whether the claim is single-use unless storage/ABI confirms a consumed flag.

Possible overinterpretation:

- Treating event name `Claimed` as proof of all claim lifecycle invariants rather than this one executed claim.

Evidence needed:

- `TokenDistributor` source/ABI storage for claimed bitmap/mapping and allocation rules.

### USDC transfer control

Tx: `0x799ed1eaabb013518acae0f73dca89348d5a1cba50fa272d5c3bf5113e3fcf50`

Event:

- `Transfer`

Storage/balance confirmation:

- Sender USDC balance changed from `46,950,000` to `46,000,000` raw units.
- Recipient USDC balance changed from `0` to `950,000` raw units.
- Delta matches `0.95` USDC transfer shown by API.

Finding:

- No disagreement observed. This is a benign control case where event-derived transfer matched canonical token state at the transaction block.

### PROSPixel batch purchase

Tx: `0xb0e974ffe3578831b85a19721c6a6391675d632a1f1353f400984face43eaf99`

Events:

- `PixelPremiumDistributed`
- `BatchPixelsBought`

What the events prove:

- The transaction executed and emitted the app-level events.

What they do not prove:

- They do not prove pixel ownership/state layout without reading contract storage.
- The contract was shown as proxy and `is_verified = false` for the displayed contract metadata, although the method/events were decoded by the indexer.

Possible overinterpretation:

- Treating `BatchPixelsBought` as sufficient proof of final pixel state without contract storage.

Evidence needed:

- Implementation/source verification and public state reads for pixel ownership.

### Keystone report

Tx: `0x3ddc9bc41af31ed6377ebd21fd1dd45ce61fa4fb7c92328f74e37e26e0df316a`

Events:

- `AnswerUpdated`
- `ReportProcessed`

What the events prove:

- A report was processed and an answer was updated in the observed Pharos contracts.

What they do not prove:

- They do not prove the reported value is economically safe for every consumer.
- They do not prove every downstream app consumed the updated answer.
- They do not prove freshness policy, staleness windows, or consumer-specific thresholds.

Possible overinterpretation:

- Treating report processing as universal oracle finality.

Evidence needed:

- Feed contract state, answer id, timestamp, and consumer contract checks.

## 5. Finality Semantics Findings

Observed practical tooling:

- RPC receipts expose transaction execution status.
- RPC blocks expose block number/hash/depth.
- RPC supports `latest`, `safe`, and `finalized` tags in the sampled call; all three returned the same block in that sample.
- Pharosscan/SocialScan transaction API exposes `receipt_status`, block number, block hash, timestamp, method labels, logs, token transfers, and traces.
- The sampled explorer/API responses do not display a per-transaction finality threshold or distinguish "executed" from "business complete".
- The explorer home/status view uses human-facing network labels: `Mainnet`, `Active`, latest block, TPS, gas, tx count.
- The stats API can lag RPC head; one read showed SocialScan latest block four blocks behind RPC.

Questions from the prompt:

- Does "success" mean executed? In sampled transaction/API fields, yes: it corresponds to `receipt_status = 1` and RPC `status = 0x1`.
- Does "success" mean economically final? Not necessarily. For bridge-like flows, source success proves source execution, not destination settlement.
- Does "success" mean block-final? The sampled explorer/API did not show an explicit block-final threshold.
- Does "confirmed" mean one block or final? The sampled API did not expose a distinct "confirmed" count/threshold field.
- Could an app act on receipt success before a stronger finality condition? Yes, plausibly, unless that app has a separate depth/finality policy. Evidence of actual app policy was not available.
- Could relayer/indexer/backend use different confirmation thresholds? Yes. SocialScan stats lag and external bridge/oracle flows make this likely, but exact policies are missing.

Transaction finality summary:

| Transaction | Receipt available | Explorer/API visible | Explorer/API status | Depth in observation batch | Finality indicator shown | Semantic compression |
|---|---|---|---:|---:|---|---|
| LiFi/Glacis | yes | yes | 1 | 184 | no explicit threshold | Source tx success may be read as bridge completion. |
| OffRamp commit | yes | yes | 1 | 189 | no explicit threshold | Commit accepted may be read as execution/delivery. |
| Failed DODO | yes | yes | 0 | 193 | no explicit threshold | Method label remains visible even though execution failed. |
| TokenDistributor claim | yes | yes | 1 | 158 | no explicit threshold | Claim event may be read as full entitlement lifecycle. |
| USDC transfer | yes | yes | 1 | 153 | no explicit threshold | Low semantic risk; balance deltas match. |
| PROSPixel | yes | yes | 1 | 140 | no explicit threshold | Event name may be read as storage state without storage proof. |
| Keystone report | yes | yes | 1 | 132 | no explicit threshold | Report processed may be read as universal consumer-ready oracle state. |

## 6. Observer Disagreement Hypotheses

Pattern ID: OD-1 Source bridge success vs destination settlement
Observed basis: LiFi/Glacis tx emitted `LiFiTransferStarted`, `CCIPMessageSent`, `Locked`, and token transfers; no destination-chain evidence was fetched.
Observer A believes: Pharos RPC/explorer can honestly say source transaction succeeded.
Observer B believes: bridge app/user may need destination-chain credit before calling the flow complete.
Why both can be honest: they observe different lifecycle stages.
What state or meaning diverges: source-chain execution vs cross-chain settlement.
Potential impact: premature downstream execution or incorrect user-visible completion.
How to confirm safely: compare the LiFi transaction id and destination `8453` records against destination chain/app status.
How to disprove: show app UI/API labels source tx only as started/pending until destination execution.
Confidence: High as a semantic gap; not a confirmed issue.

Pattern ID: OD-2 Commit accepted vs message executed
Observed basis: OffRamp tx emitted `CommitReportAccepted` and `Transmitted`, with no token transfers.
Observer A believes: OffRamp commit happened.
Observer B believes: user message is not complete until execution/settlement.
Why both can be honest: commit and execution can be separate phases.
What state or meaning diverges: report acceptance vs message delivery.
Potential impact: backend triggers "ready/complete" on commit event.
How to confirm safely: locate matching execution tx/message id and compare CCIP status.
How to disprove: OffRamp/app policy requires explicit execution event/state before completion.
Confidence: Medium.

Pattern ID: OD-3 Event-derived token transfer vs business completion
Observed basis: LiFi token transfers and lock event matched source state, but not destination settlement; TokenDistributor/USDC transfer matched local token balances.
Observer A believes: token transfer occurred.
Observer B believes: business process is complete only after a second condition.
Why both can be honest: token transfer is a ledger fact; app completion is a higher-level meaning.
What state or meaning diverges: balance movement vs full lifecycle.
Potential impact: accounting or support decisions based only on transfer table.
How to confirm safely: for each app, compare event table to storage lifecycle flags and external status.
How to disprove: app labels token transfer only as token movement, not completion.
Confidence: Medium-high.

Pattern ID: OD-4 Decoded method label survives failed execution
Observed basis: failed DODO tx shows method `Mix Swap`, `receipt_status = 0`, no logs, trace error.
Observer A believes: method label identifies attempted call.
Observer B may believe: swap happened if reading method label without failure context.
Why both can be honest: decoders label calldata, not outcome.
What state or meaning diverges: attempted action vs completed action.
Potential impact: human/support/backend misclassification if status is ignored.
How to confirm safely: inspect rendered explorer page prominence of failed status vs method label.
How to disprove: explorer UI strongly marks failure and downstream APIs key on receipt status.
Confidence: Low-medium; likely benign if status is prominent.

Pattern ID: OD-5 Indexer head vs RPC head
Observed basis: sampled SocialScan stats latest block was `7,197,443` while RPC head was `7,197,447`.
Observer A believes: explorer stats head is latest.
Observer B believes: RPC latest is four blocks ahead.
Why both can be honest: indexer/stats cache can lag the chain.
What state or meaning diverges: latest indexed state vs latest RPC state.
Potential impact: very recent tx may exist by RPC but not explorer/API, or explorer may show stale aggregate status.
How to confirm safely: repeated polling with timestamps.
How to disprove: show stats are explicitly cache-labeled and tx detail APIs reconcile within bounded delay.
Confidence: High for temporary lag; low as an issue by itself.

Pattern ID: OD-6 Report processed vs consumer-ready data
Observed basis: Keystone tx emitted `AnswerUpdated` and `ReportProcessed`.
Observer A believes: report was processed on Pharos.
Observer B believes: app-specific oracle condition requires freshness/range/round checks.
Why both can be honest: oracle update and consumer validation are separate.
What state or meaning diverges: feed update vs safe downstream use.
Potential impact: external app acts on event without consumer checks.
How to confirm safely: inspect consuming contracts and feed state variables at the tx block.
How to disprove: consumers always read feed state and validate timestamp/round before action.
Confidence: Medium.

Pattern ID: OD-7 Decoded app events without verified displayed contract source
Observed basis: PROSPixel tx had decoded `BatchPixelsBought` but displayed contract metadata included `is_verified = false`, proxy = true.
Observer A believes: decoded event was emitted.
Observer B believes: pixel ownership/storage is final.
Why both can be honest: event decoding can be available even when full implementation/source trust is incomplete.
What state or meaning diverges: emitted event vs actual app storage.
Potential impact: UI or indexer treats event as ownership source of truth.
How to confirm safely: read pixel ownership public state or verified implementation source.
How to disprove: app/indexer reconciles event-derived pixel state with contract storage.
Confidence: Medium.

## 7. Strongest Leads

### Lead 1: Bridge-start compression into completion

Disagreeing components:

- RPC/explorer: source tx succeeded, logs emitted.
- Bridge/app/user expectation: destination chain `8453` settlement must occur.

Weird valid state:

- Pharos source transaction has `status = 0x1`, `LiFiTransferStarted`, `CCIPMessageSent`, and `Locked`; destination settlement may still be pending or unknown.

Potential impact:

- premature downstream execution;
- incorrect user-visible completion;
- support/admin treating source event as final bridge result.

Next safe test:

- Query LiFi/Glacis/CCIP status for `transactionId = 0x6a2396340e693ff45d94010cf6708fba6570870534579ef5b5f27615501a0d25` and compare with Base (`8453`) destination records.

### Lead 2: CCIP commit accepted vs execution complete

Disagreeing components:

- OffRamp/indexer: commit report accepted and transmitted.
- Message recipient/downstream app: completion requires later execution or verified delivery.

Weird valid state:

- `CommitReportAccepted` exists with no token transfer and no proof in this pass of message execution.

Potential impact:

- relayer/backend acting too early;
- monitoring or UI status stronger than actual message lifecycle.

Next safe test:

- Use OffRamp ABI/source to map commit report data to message ids and locate matching execution events/transactions.

### Lead 3: Indexer-derived status and human labels stronger than state

Disagreeing components:

- Explorer/API labels: method names, event names, token-transfer rows, Mainnet Active/latest stats.
- Canonical checks: receipt status, balance deltas, storage flags, block depth.

Weird valid state:

- A decoded method/event label is correct as a label but stronger than what storage/balance/finality proves.

Potential impact:

- duplicate or missing off-chain record;
- human support decision from explorer rather than state;
- UI showing "bought", "claimed", "processed", or "started" as if no further state checks are needed.

Next safe test:

- For PROSPixel, TokenDistributor, and Keystone, read verified/public state immediately after the selected transaction block and compare to event-derived labels.

## 8. Disproved or Likely Benign Differences

| Difference / idea | Evidence | Status |
|---|---|---|
| Explorer/API says success while RPC says failure | No selected tx showed this. All seven matched `receipt_status` vs RPC `status`. | DISPROVED in sampled set |
| Explorer/API omits logs shown by RPC | No selected tx showed this. RPC log counts matched API log totals. | DISPROVED in sampled set |
| Explorer/API shows token transfer unsupported by logs | No selected tx showed this. Token transfers mapped to Transfer logs in sampled cases. | DISPROVED in sampled set |
| Failed DODO emitted partial events | RPC/API log count was zero; token transfers zero. | DISPROVED for selected tx |
| USDC transfer table mismatches token state | ERC20 `balanceOf` before/after matched `0.95` USDC movement. | DISPROVED for selected tx |
| TokenDistributor transfer mismatch | ERC20 `balanceOf` before/after matched `15.63` USDC claim movement. | DISPROVED for selected tx |
| SocialScan lag implies wrong tx detail | The sampled lag was stats head only; selected tx details matched RPC. | LIKELY BENIGN, needs timing window tests |
| `safe`/`finalized` tags absent from RPC | Sampled RPC accepted both tags and returned a block. | DISPROVED for RPC capability |

## 9. Evidence Still Needed

Exact missing data:

- Destination-chain records for LiFi/Glacis transaction id `0x6a2396340e693ff45d94010cf6708fba6570870534579ef5b5f27615501a0d25`.
- LiFi/Glacis app/backend status API for the selected bridge flow.
- CCIP explorer/status records for `CCIPMessageSent`, `CommitReportAccepted`, and matching execution events.
- OffRamp ABI/source storage reads for report/message lifecycle.
- TokenDistributor source or ABI details for consumed/claimed state.
- PROSPixel implementation source or storage layout for pixel ownership after `BatchPixelsBought`.
- Keystone/SelfManagedFeedsCache feed state after `AnswerUpdated`, including answer, round, timestamp, and consumer freshness checks.
- Rendered explorer screenshots for failed transaction pages to assess whether failure status is visually stronger than decoded method labels.
- Repeated block-depth observations with timestamps comparing:
  - RPC `eth_blockNumber`
  - SocialScan `/explorer/stats.latest_block`
  - transaction-detail API availability
  - explorer rendered visibility.
- Explicit Pharos finality documentation for operational thresholds used by explorers, relayers, bridges, or oracle consumers.
- Bridge/relayer confirmation policy: whether downstream components wait for `latest`, `safe`, `finalized`, fixed block depth, or external proof.

## 10. Final Judgment

Strong lead; next test should compare source-chain bridge events against destination-chain/app status for the LiFi/Glacis transaction, and compare CCIP commit events against later execution/delivery state.

No confirmed semantic mismatch was proven in the sampled RPC-vs-indexer facts: receipt status, block number/hash, gas used, log counts, and token-transfer records matched direct RPC for the selected transactions. The strongest risk is semantic compression: explorer/API labels and event names are accurate as observations, but they do not by themselves prove finality, destination settlement, app-level completion, oracle consumer readiness, or storage-level lifecycle closure.

Current status: SUSPICIOUS OBSERVER DISAGREEMENT; needs evidence from destination-chain records, bridge/relayer policies, app status APIs, and contract storage reads before calling any issue confirmed.
