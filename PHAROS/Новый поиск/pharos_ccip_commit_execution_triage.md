# Pharos Mainnet CCIP Commit-vs-Execution Triage

Scope: Pharos Mainnet, chainId `1672 / 0x688`.

Focus: whether `CommitReportAccepted` on the Pharos OffRamp can be concretely observed as being overread as message execution, delivery, receiver credit, or app-level completion.

## 1. Candidate collection method

- Seeded from known sample tx `0x389b34ef2c1da514f80509326413106d614c485c23b61eff2ec200019b887d41`.
- Identified OffRamp: `0x40858070814a57fdf33a613ae84fe0a8b4a874f7`.
- Queried recent Pharos RPC logs for OffRamp `CommitReportAccepted` topic:
  - `0xb967c9b9e1b7af9a61ca71ff00e9f5b89ec6f2e268de8dacf12f0de8e51f3e47`
- Took the 5 most recent commit-stage transactions.
- For each tx, checked SocialScan transaction details, decoded logs, token transfer count, and event names.

## 2. Five candidate commit transactions

| Tx | Block/time | From | To | Method | Status | Events | Logs | Token transfers | CommitReportAccepted | Transmitted | High-signal reason |
|---|---:|---|---|---|---:|---|---:|---:|---|---|---|
| `0xadbf4d5d09ddd27621dd132a3731cf663699e8b975c917bd5853cbf0d3882654` | `7199091`, `2026-05-13T13:04:09Z` | `0x12c38eb49f8e83b65ae0cbd3b81713c89e47cba9` | OffRamp | `Commit` | `1` | `UsdPerUnitGasUpdated`, `CommitReportAccepted`, `Transmitted` | 3 | 0 | yes | yes | recent OffRamp commit with decoded commit/transmit events |
| `0x130adfef0893a4698c3ddffd3b25d8a6a36f5514e6bc2b1e7c3e25973a040b00` | `7199066`, `2026-05-13T13:03:50Z` | `0x37557c61dbcb7ab4e6743306a679974a8d670b75` | OffRamp | `Commit` | `1` | same | 3 | 0 | yes | yes | recent OffRamp commit |
| `0x395f74d0e49517a2875809596b3b170b16007c5ef93c4eed7863fc081f552579` | `7198995`, `2026-05-13T13:02:55Z` | `0x6c5a9f7334a208d0f20a5f8e1cbe2c14b6d1400a` | OffRamp | `Commit` | `1` | same | 3 | 0 | yes | yes | recent OffRamp commit |
| `0x2d3e6e5559248f48ef3efe1b3f46a2d8eac75851604085bc5a851c73662ad032` | `7198952`, `2026-05-13T13:02:21Z` | `0x6c5a9f7334a208d0f20a5f8e1cbe2c14b6d1400a` | OffRamp | `Commit` | `1` | same | 3 | 0 | yes | yes | recent OffRamp commit |
| `0xdd1eb34ff02a27b066fd209714a8c3aeed63894c54d2d361af60f151b6e5065b` | `7198888`, `2026-05-13T13:01:29Z` | `0xbe307f40ee3e96df7110a25adf645634ddafbb2c` | OffRamp | `Commit` | `1` | same | 3 | 0 | yes | yes | recent OffRamp commit |

All five have:

- `blessedMerkleRoots = ()`
- `unblessedMerkleRoots = ()`
- `priceUpdates = ((), ((2442541497099098535, <usdPerUnitGas>),))`
- no token transfers
- no message ids
- no receiver
- no amount

## 3. Commit-vs-execution table

| Tx | Event | Proves | Does not prove | Message-level or report-level | Execution evidence in same tx | Token/user credit in same tx | Overinterpretation risk |
|---|---|---|---|---|---|---|---|
| all 5 | `UsdPerUnitGasUpdated` from `FeeQuoter` | a gas price value was updated for dest selector `2442541497099098535` | message execution, delivery, user credit | report/config-level price data | no | no | low if UI labels it as gas update |
| all 5 | `CommitReportAccepted` from OffRamp | the OffRamp accepted a commit report containing only price updates | execution, receiver state, token movement, message completion | report-level; roots arrays are empty | no | no | low; event name says accepted report, not executed |
| all 5 | `Transmitted` from OffRamp | OCR transmit occurred with config digest `0x000aa2e85587b0acce93a552e5837faaa1475f6f15d1e36db368209612a571bb` and a transmit sequence number | execution, message delivery, app completion | OCR/report-level | no | no | low; does not contain message ids or receiver fields |

## 4. Matching execution search results

No message-level execution search was possible for these five commits because the accepted reports contain no merkle roots, no sequence interval, no message id, no receiver, no token, and no amount.

Classification for all five: `G. Benign operational commit with no user-facing message traceable`.

There is no evidence of destination/user execution in the same tx, but that is expected for these sampled records: they are gas-price update commits, not message-bearing commits.

## 5. Observer comparison

| Observer | What it can prove | What it cannot prove | Status word used | Says commit/accepted/executed/complete? | Could be overread? |
|---|---|---|---|---|---|
| Pharos RPC | tx included and succeeded, receipt `status=1` | message execution or user credit | success | only tx success | yes, only if a backend treats tx success as delivery |
| SocialScan/Pharosscan | target `OffRamp`, method `Commit`, decoded events | user-facing completion | `Commit`, `CommitReportAccepted`, `Transmitted` | commit/transmit, not executed/complete | low; labels are commit-stage |
| Event log | gas update, report accepted, OCR transmit | message delivery, receiver/app state | event names only | accepted/transmitted | low; no message ids or roots |
| CCIP/offchain status | not queried by message id because no message id exists | user completion for these reports | unavailable | unavailable | no concrete overstatement observed |
| Receiver/app/token state | no token transfers in commit tx | later app state unrelated to absent message ids | none | no credit | no evidence of mismatch |

## 6. Suspicious states

None in Stage 1.

Not observed:

- explorer/API labeling commit-stage tx as delivered, executed, or complete
- commit with message roots but no later execution after delay
- duplicated incompatible report/message evidence
- token/user credit shown from commit tx alone
- app/backend treating commit as user-facing completion
- report status saying complete while no execution/receiver state exists

## 7. Disproved/cosmetic differences

- `receipt_status = 1` is only transaction success, not execution semantics.
- `Transmitted` is OCR/report transmission, not user message delivery.
- `CommitReportAccepted` in this sample has empty merkle root arrays, so absence of execution evidence is not suspicious.

## 8. Triage decision

STOP.

Stage 1 did not find a concrete suspicious observer disagreement. The sampled transactions clearly separate commit/report acceptance from execution: they are price-update commit reports with no message-level identifiers and no token/user credit.

## 9. Recommended next target

Next highest-value target: `Gas-limit charge vs refund expectation`.

Final judgment:

STOP: No strong lead in sampled CCIP commit-vs-execution transactions.
