# Pharos Mainnet LiFi/Glacis Base Settlement Follow-up

Scope: Pharos Mainnet only for source chain, chainId `1672 / 0x688`. Destination evidence checked on Base, chainId `8453`.

Source tx: `0x53183357ffdc6ebe83e6d7e062e2e54e6e324e7ec983338860683e04f2887419`

## 1. Source-side facts

- Pharos RPC receipt status: `0x1`.
- SocialScan/Pharos API receipt status: `1`.
- Source block: `7197111`, timestamp `2026-05-13T12:38:10Z`.
- Sender: `0x7cc6eed5fb840fb7a72ff8157a0c7c21158a978a`.
- Target: `0xff70f4a1d11995621854f3692acf286d8acd04b2` (`LiFiDiamond`).
- Method: `swapAndStartBridgeTokensViaGlacis`.
- Source route flags: `hasSourceSwaps = true`, `hasDestinationCall = false`.
- WPROS moved into `LockReleaseTokenPool`: `2292917053782110626629` raw units.

## 2. Decoded identifiers

### LiFi bridge data

- `transactionId`: `0x6a2396340e693ff45d94010cf6708fba6570870534579ef5b5f27615501a0d25`
- `bridge`: `glacis`
- `integrator`: `pros-arb-bridge`
- `sendingAssetId`: `0x52c48d4213107b20bc583832b0d951fb9ca8f0b0` (Pharos WPROS)
- `receivingAssetId`: `0x8b7dde054be9d180c1be7fae0874697374a49832` (Base Wrapped PROS), present as `_glacisData.outputToken` and CCIP `destTokenAddress`
- `receiver`: `0x7cc6eed5fb840fb7a72ff8157a0c7c21158a978a`
- `amount` in LiFi `bridgeData.minAmount`: `2293834587617157489624`
- `destinationChainId`: `8453`

### Source events

- `FeesForwarded` at `0xd23fb66108971325f302bf0f209216d705adf987`:
  - token: native `0x0000000000000000000000000000000000000000`
  - recipient: `0xc06ebbefd94032b85424d51906e2a335efae264b`
  - amount: `5748958866208414760`
- `AssetSwapped` #1:
  - transactionId: `0x6a2396340e693ff45d94010cf6708fba6570870534579ef5b5f27615501a0d25`
  - dex: `0xd23fb66108971325f302bf0f209216d705adf987`
  - fromAssetId/toAssetId: native -> native
  - fromAmount: `2299583546483365904384`
  - toAmount: `2294090730063560584683`
- `AssetSwapped` #2:
  - dex: `0x1de7889c440d4fefa0e5f4f83a021f6f41cdf26b`
  - fromAssetId/toAssetId: native -> `0x52c48d4213107b20bc583832b0d951fb9ca8f0b0`
  - fromAmount/toAmount: `2293834587617157489624`
- `Transfer` events:
  - `0x1de7889c440d4fefa0e5f4f83a021f6f41cdf26b` -> `LiFiDiamond`, `2293834587617157489624`
  - `LiFiDiamond` -> `0x290d54179960984599f16f77dcda81320301b158`, `2293834587617157489624`
  - `Router` -> `OnRamp`, fee `256142446403095059`
  - `0x290d54179960984599f16f77dcda81320301b158` -> `LockReleaseTokenPool`, `2292917053782110626629`
- `Locked` at `0xcb79097744d5266bfca287a43612d9613be46300`:
  - sender: `0x193beb1e11731b8b740b9fbbb62655553c3b4a25`
  - amount: `2292917053782110626629`
- `CCIPMessageSent` at `0x193beb1e11731b8b740b9fbbb62655553c3b4a25`:
  - messageId: `0x7dcd061355b95283721a68e7b22d51be45f9f7da4e5dc52a7406dc364ac65449`
  - sourceChainSelector: `7801139999541420232`
  - destChainSelector: `15971525489660198786`
  - sequenceNumber: `2089`
  - nonce: `0`
  - sender: `0x290d54179960984599f16f77dcda81320301b158`
  - receiver bytes: `0x0000000000000000000000007cc6eed5fb840fb7a72ff8157a0c7c21158a978a`
  - payload data: `0x`
  - feeToken: `0x52c48d4213107b20bc583832b0d951fb9ca8f0b0`
  - feeTokenAmount: `256142446403095059`
  - sourcePoolAddress: `0xcb79097744d5266bfca287a43612d9613be46300`
  - destTokenAddress: `0x0000000000000000000000008b7dde054be9d180c1be7fae0874697374a49832`
  - token amount: `2292917053782110626629`
  - destExecData: `0x0000000000000000000000000000000000000000000000000000000000015f90`
- `GlacisAirliftFacet_Send`:
  - token: `0x52c48d4213107b20bc583832b0d951fb9ca8f0b0`
  - destinationChain: `8453`
  - receiver: `0x0000000000000000000000007cc6eed5fb840fb7a72ff8157a0c7c21158a978a`
  - amount: `2293834587617157489624`
  - sendResponse/messageId: `0x7dcd061355b95283721a68e7b22d51be45f9f7da4e5dc52a7406dc364ac65449`
- `LiFiTransferStarted`:
  - transactionId: `0x6a2396340e693ff45d94010cf6708fba6570870534579ef5b5f27615501a0d25`
  - bridge: `glacis`
  - integrator: `pros-arb-bridge`
  - sendingAssetId: `0x52c48d4213107b20bc583832b0d951fb9ca8f0b0`
  - receiver: `0x7cc6eed5fb840fb7a72ff8157a0c7c21158a978a`
  - minAmount: `2293834587617157489624`
  - destinationChainId: `8453`

## 3. Destination-side search results

Candidate destination tx:

- tx hash: `0x7341122609a0bd7a70bfcc5214d07e5d76f0f92cb2be2138a14baa94cabe173b`
- chain: Base, chainId `8453`
- block: `45943294`
- timestamp: `2026-05-13T12:38:55Z`
- status: `0x1`
- from: `0x73b78ba23cd53e3a3b5edc9860fd84f741368213`
- to: `0xf09afe78d3c7d359b334d7cb88995751f7ec5e13`
- token transfer/credit:
  - token: `0x8b7dde054be9d180c1be7fae0874697374a49832`
  - ERC20 `Transfer`: zero address -> `0x7cc6eed5fb840fb7a72ff8157a0c7c21158a978a`
  - amount: `2292917053782110626629`
- CCIP-linked event:
  - emitting address: `0xf09afe78d3c7d359b334d7cb88995751f7ec5e13`
  - topic0: `0x05665fe9ad095383d018353f4cbcba77e84db27dd215081bbf7cdf9ae6fbe48b`
  - topic1: `0x0000000000000000000000000000000000000000000000006c43377f53c1e0c8` (source selector `7801139999541420232`)
  - topic2: `0x...0829` (sequence `2089`)
  - topic3: `0x7dcd061355b95283721a68e7b22d51be45f9f7da4e5dc52a7406dc364ac65449`
- Link confidence: High.
  - The Base tx contains the exact CCIP `messageId`, source selector, sequence number, destination token, receiver, and raw token amount from the Pharos `CCIPMessageSent` event.

Additional Base log scan for token `0x8b7dde054be9d180c1be7fae0874697374a49832` to receiver found other nearby credits, but only `0x734112...173b` matched the exact source CCIP `messageId` and exact amount.

## 4. Status API / explorer results

- LI.FI `/v1/status`, queried by source tx with `fromChain=1672`, `toChain=8453`, `bridge=glacis`:
  - `transactionId`: `0x6a2396340e693ff45d94010cf6708fba6570870534579ef5b5f27615501a0d25`
  - `status`: `DONE`
  - `substatus`: `COMPLETED`
  - message: `The transfer is complete.`
  - receiving tx: `0x7341122609a0bd7a70bfcc5214d07e5d76f0f92cb2be2138a14baa94cabe173b`
  - receiving amount: `2292917053782110626629`
- Base RPC:
  - destination tx receipt `status = 0x1`
  - ERC20 mint/credit to receiver present in receipt.
- BaseScan:
  - transaction page metadata says `Success` and `Transfer 2,292.92 PROS to 0x7cC6EeD5...1158A978A`.
- Chainlink CCIP Explorer:
  - public explorer accepts message ID / tx hash / address lookup.
  - I did not obtain a structured API response from the explorer.
  - On-chain Base receipt independently contains the exact CCIP `messageId` in a destination-side event.
- Glacis:
  - public docs describe Airlift `/transactions/{txHash}` status API and `DONE` meaning destination tokens are available.
  - endpoint requires `x-apikey`; no unauthenticated Glacis status response was obtained.

## 5. Observer comparison

| Observer | What it can prove | What it cannot prove alone | Status word | Lifecycle meaning | Overinterpretation risk |
|---|---|---|---|---|---|
| Pharos RPC | Source tx included and executed successfully (`status=0x1`) | Destination execution or receiver credit on Base | success | source tx executed | High if read as bridge complete |
| Pharosscan/SocialScan | Source tx success, decoded source events, source token lock/send | Destination settlement without Base/status evidence | success / method label | source start and CCIP send | High if method label is read as complete |
| LiFi/Glacis source events | `LiFiTransferStarted`, `GlacisAirliftFacet_Send`, `CCIPMessageSent`, token lock | Whether Base tx later executed | started / sent | bridge started and message sent | Medium if treated as final settlement |
| CCIP status | Source `messageId`; Base receipt has messageId event | Explorer API status was not retrieved | on-chain executed evidence, no explorer word | destination message execution evidenced on-chain | Low after matching Base event |
| Base chain | Destination tx success, exact token mint/credit to receiver | UI/backend semantics | success | destination executed and receiver credited | Low |
| App/backend status | LI.FI `DONE/COMPLETED` plus receiving tx | It is a backend interpretation unless paired with Base receipt | DONE / COMPLETED | complete | Low here because Base receipt confirms it |

## 6. Current bridge lifecycle classification

Classification: `5. Destination credited receiver`.

Evidence:

- Source `CCIPMessageSent` messageId `0x7dcd...5449`, sequence `2089`, amount `2292917053782110626629`, receiver `0x7cc6...978a`, dest token `0x8b7dde...9832`.
- Base tx `0x734112...173b` status `0x1` includes a destination-side event with the exact `messageId`, source selector, and sequence.
- The same Base tx mints/transfers `2292917053782110626629` of `0x8b7dde...9832` from zero address to `0x7cc6...978a`.
- LI.FI status returns `DONE / COMPLETED` and gives that same Base tx as the receiving transaction.

## 7. Semantic mismatch result

Result: Disproved for this transaction.

`Source Success Read As Bridge Completion` is not confirmed here because destination completion is not missing. The weaker Pharos observer still only proves source execution, but stronger observers prove destination settlement:

- Base chain proves destination tx success and receiver credit.
- LI.FI status provides `DONE / COMPLETED` plus the same destination tx.
- Destination receipt links to source by exact CCIP messageId/sequence/amount/receiver/token.

## 8. Missing evidence

- No unauthenticated Glacis Airlift status API response was obtained because the documented production endpoint requires an API key.
- No structured Chainlink CCIP Explorer API response was obtained. This is not blocking because Base on-chain logs include the source `messageId`.
- Destination event ABI names for two Base events emitted by `0x7126...84b0` and `0xf09a...5e13` were not decoded; the raw topics and data are sufficient for linkage and token-credit proof.

## 9. Final judgment

This was not merely source-started on Pharos. The bridge flow completed on Base and credited the receiver.

The observer-disagreement risk remains conceptually valid: Pharos RPC/Pharosscan source success alone cannot prove bridge completion. For this specific tx, however, the stronger destination evidence exists and resolves the disagreement in favor of completed settlement.
