# Pharos Mainnet Keystone Report vs Feed-State Triage

## 1. Contract/feed baseline

Network: Pharos Mainnet, chainId `1672 / 0x688`

Known sample tx:
`0x3ddc9bc41af31ed6377ebd21fd1dd45ce61fa4fb7c92328f74e37e26e0df316a`

Block: `7197163` (`0x6dd1eb`)  
Block timestamp: `2026-05-13T12:38:51Z`  
From: `0x025dccb60b320c9bdc581b38f10972fc8e630209`  
To: `0x76c9cf548b4179f8901cda1f8623568b58215e62`  
Method: `report(address receiver, bytes rawReport, bytes reportContext, bytes[] signatures)`  
Receipt status: `1`  
Log count: `2`  
Token/native transfers in receipt logs: `0`

Contracts:

| Role | Address | Label/source status | Proxy status | Evidence |
|---|---:|---|---|---|
| Forwarder / report processor | `0x76c9cf548b4179f8901cda1f8623568b58215e62` | SocialScan verified as `KeystoneForwarder`; code endpoint returns verified ABI/source metadata | SocialScan tx object marked proxy, contract code endpoint says `proxy=false`; EIP-1967 implementation slot is zero | `typeAndVersion()` returns `KeystoneForwarder 1.0.0`; `ReportProcessed` emitted here |
| Feed/cache receiver | `0xc71f7d98d3d9a000fdfe307fbdb9d94abd56424b` | SocialScan verified as `SelfManagedFeedsCache` | Non-proxy; EIP-1967 implementation slot is zero | `typeAndVersion()` returns `SelfManagedFeedsCache 1.0.0`; `AnswerUpdated` emitted here |

Feed id:
`0x000362205e10b3a147d02792eccee483dca6c7b44ecce7012cb8c6e0b68b3ae9`

The cache source exposes feed-specific public reads:

- `latestAnswerForFeed(bytes32)`
- `latestAnswerTimestampForFeed(bytes32)`
- batch variants for arrays of feed ids

Common Chainlink-style reads on the cache (`latestAnswer`, `latestRound`, `latestRoundData`, `decimals`, `description`, `aggregator`, `latestTransmissionDetails`) reverted. This cache is not a direct Chainlink aggregator interface; consumers need the feed-id-specific reads or a separate adapter.

## 2. Event decode

Raw topic verification:

| Event | Computed topic0 | Raw log topic0 | Match |
|---|---|---|---|
| `AnswerUpdated(bytes32,uint256,uint256)` | `0x6a74ab11f122447396829944f2bfdfc8d6f47930b6f9996ebe5c02346aa6b25d` | `0x6a74ab11f122447396829944f2bfdfc8d6f47930b6f9996ebe5c02346aa6b25d` | yes |
| `ReportProcessed(address,bytes32,bytes2,bool)` | `0x3617b009e9785c42daebadb6d3fb553243a4bf586d07ea72d65d80013ce116b5` | `0x3617b009e9785c42daebadb6d3fb553243a4bf586d07ea72d65d80013ce116b5` | yes |

Decoded events:

| Log | Emitter | Event | Decoded fields |
|---:|---|---|---|
| 0 | `SelfManagedFeedsCache` | `AnswerUpdated` | `feedId = 0x000362205e10b3a147d02792eccee483dca6c7b44ecce7012cb8c6e0b68b3ae9`; `timestamp = 1778675915` (`2026-05-13T12:38:35Z`); `answer = 2272900414415111300000` |
| 1 | `KeystoneForwarder` | `ReportProcessed` | `receiver = 0xc71f7d98d3d9a000fdfe307fbdb9d94abd56424b`; `workflowExecutionId = 0xf6344bac9058369b89025637dc29d2c81501c51d0e024326b279e9e4b9033faa`; `reportId = 0x0006`; `result = true` |

Forwarder state for this transmission at block `7197163`:

- `getTransmissionId(receiver, workflowExecutionId, reportId)` =
  `0x6832098939cbf6c5c9e82624261f9d5755a007a08f39ccc7061d13870935782a`
- `getTransmissionInfo(...)` =
  `state = 1`, `transmitter = 0x025dccb60b320c9bdc581b38f10972fc8e630209`, `invalidReceiver = false`, `success = true`, `gasLimit = 1872779`

## 3. Feed state before/after/latest

The verified cache source stores:

```solidity
mapping(bytes32 feedId => StoredAnswer) private s_latestAnswers;
struct StoredAnswer {
    uint256 answer;
    uint32 timestamp;
}
```

Because inherited owner state and cache config occupy earlier slots, `s_latestAnswers` is at storage slot `5`. For the sample feed id:

- base slot `keccak256(feedId . uint256(5))` =
  `0xb83b1617bc4eda2a369e5cb968e347d5db60d2b86612b0a3ae8125bfcd85a342`
- answer slot = base slot
- timestamp slot = base slot + 1 =
  `0xb83b1617bc4eda2a369e5cb968e347d5db60d2b86612b0a3ae8125bfcd85a343`

Storage reads:

| Block | Answer slot value | Decoded answer | Timestamp slot value | Decoded timestamp | Matches sample event? |
|---|---:|---:|---:|---|---|
| `7197162` (`N-1`) | `0x...7be7fd7002f150d550` | `2285666161616084850000` | `0x...6a046f0c` | `1778675468` (`2026-05-13T12:31:08Z`) | no, previous feed state |
| `7197163` (`N`) | `0x...7b36d464916ad9a3a0` | `2272900414415111300000` | `0x...6a0470cb` | `1778675915` (`2026-05-13T12:38:35Z`) | yes |
| latest at triage time | `0x...7a6fccebb7a4c22000` | `2258558850000000000000` | `0x...6a048119` | `1778680089` (`2026-05-13T13:48:09Z`) | no, later report superseded it |

Important RPC observation:

Historical `eth_call` to `latestAnswerForFeed(feedId)` at `N-1` and `N` returned the same value as a later/latest feed state in one check, while `eth_getStorageAt` at explicit block tags returned the expected before/after slots. For this triage, canonical before/after evidence is taken from `eth_getStorageAt` and the verified storage layout, not from historical `eth_call`.

Public reads at latest:

| Function | Result |
|---|---|
| `latestAnswerForFeed(feedId)` | succeeds; returns the latest current answer for that feed |
| `latestAnswerTimestampForFeed(feedId)` | succeeds; returns the latest current timestamp for that feed |
| `latestAnswerForFeeds([feedId])` | succeeds |
| `latestAnswerTimestampForFeeds([feedId])` | succeeds |
| `getForwarderAddress()` | `0x76c9cf548b4179f8901cda1f8623568b58215e62` |
| `typeAndVersion()` | `SelfManagedFeedsCache 1.0.0` |

## 4. Consumer-ready semantics analysis

`AnswerUpdated` proves that the cache wrote a new answer and timestamp for the specific `feedId` in this tx. The storage slot at block `7197163` matches the event exactly.

`ReportProcessed(result=true)` proves the forwarder accepted and routed this report to the receiver successfully. It does not by itself prove that every downstream app should use the value without checking feed id, timestamp, answer bounds, or app-specific rules.

The cache exposes timestamp reads, so freshness is visible to a consumer. It does not expose `latestRoundData()` or round ids on this contract, so a consumer expecting a Chainlink aggregator interface would need an adapter or feed-id-specific integration.

No consuming contract was found in the sample tx. The tx only involves the transmitter EOA, `KeystoneForwarder`, `SelfManagedFeedsCache`, and `ecrecover` precompile calls. No separate consumer/app state update appears in the call trace.

No evidence was found that SocialScan, the RPC receipt, or the verified ABI labels the value as globally consumer-ready. The labels observed are report/update labels, and the cache state confirms the update label.

## 5. Observer comparison

| Observer | What it proves | What it cannot prove | Label/status used | Stronger than evidence? |
|---|---|---|---|---|
| RPC receipt | Tx included successfully; two logs emitted; status `1` | Consumer freshness policy or app-specific acceptance | success | No, only tx-level |
| Raw logs | Exact `AnswerUpdated` and `ReportProcessed` topics/data | Suitability for all consumers | event topics only | No |
| SocialScan decoded events | ABI decoding of `feedId`, `timestamp`, `answer`, `receiver`, `workflowExecutionId`, `reportId`, `result` | Consumer-specific readiness | `AnswerUpdated`, `ReportProcessed` | No observed overstatement |
| Feed public/storage state | Answer/timestamp storage changed from previous value to event value at block `7197163` | Whether a downstream app should use it | feed-id-specific answer/timestamp reads | No |
| Consumer contract | Not found in sample trace | Cannot assess consumer validation | UNKNOWN | Not applicable |
| Human/UI interpretation | May read "answer updated" as "feed cache updated" | Should not infer universal readiness | update/report labels | Potential only; no concrete mismatch |

## 6. Suspicious states

None found in Stage 1.

Checked conditions:

- `AnswerUpdated` value differs from feed state after tx: disproved by storage at block `7197163`.
- `ReportProcessed` emitted but feed state did not update as implied: disproved; cache storage changed to the event answer/timestamp.
- Event timestamp differs from public/canonical state after tx: disproved by storage at block `7197163`.
- Consumer-facing API/UI treats report processed as globally usable without freshness checks: not observed.
- Known consuming contract reads the feed without timestamp/freshness validation: no consumer found quickly in the sample trace.

## 7. Disproved/cosmetic differences

- SocialScan contract metadata discrepancy on `KeystoneForwarder`: the transaction object marked it as proxy, while the contract code endpoint reported `proxy=false` and EIP-1967 implementation slot was zero. This did not affect event decoding or state reconciliation for the sampled tx.
- Latest feed state differs from the sampled event because later reports superseded the value. This is normal feed progression, not a mismatch for the sampled block.
- Standard aggregator-style functions reverted on `SelfManagedFeedsCache`; the verified source shows feed-id-specific reads instead. This is an integration-shape detail, not an event/state mismatch.

## 8. Triage decision

STOP.

The known sample tx is sufficient for Stage 1:

- `AnswerUpdated` raw log decodes correctly.
- The verified cache storage layout identifies exact answer/timestamp slots.
- At block `7197163`, storage matches the event answer and timestamp exactly.
- `ReportProcessed(result=true)` is consistent with forwarder transmission state.
- No consumer/app observer was found that treats the event alone as consumer-ready data.

No additional Keystone/report transactions were sampled because the prompt's immediate STOP condition was met by the known sample.

## 9. Recommended next target

1. TokenDistributor claim lifecycle / consumed-state proof
2. Explorer/indexer temporary lag around newest transactions
3. Search for verified bridge/OFT contracts with pending/refund lifecycle

Final judgment:

STOP: No strong lead in sampled Keystone report-vs-feed-state behavior.
