# Fuel: приоритизация баг-сценариев и bounty-ready POC notes

Дата: 2026-05-13  
База: отчеты `№1`, `№2`, `№3`, локальные ABI/source snapshots и on-chain sample `data/recent_transactions_sample.json`.

## 1. Методика приоритизации

Оценка дана по 4 критериям, каждый от 1 до 5:

| Критерий | Что означает 5/5 |
|---|---|
| Impact on assets | Возможен drain, unauthorized mint, double-finalization, блокировка значимых средств или системный accounting break. |
| Reproducibility | Последовательность шагов стабильна и может быть превращена в локальный/тестнет harness без сильной зависимости от удачи. |
| Non-obviousness | Сценарий не является банальной ошибкой доступа; требует комбинации механик Fuel, bridge/resource lifecycle, multicall, oracle ordering или off-chain matching. |
| Fuel-specific complexity | Использует Fuel UTXO/input-output модель, messages, contract resources, parallel/ordered execution assumptions, external call hooks или async bridge flow. |

Итоговый приоритет:

- `P0`: потенциальный critical, bounty-first.
- `P1`: высокий шанс high/critical impact, нужен быстрый POC.
- `P2`: ценный сценарий, но impact или reproducibility слабее.
- `P3`: оставить в backlog или проверять после исходников/адресов.

Важно: `Actual outcome` пока не подтвержден исполнением. Эти сценарии являются приоритетной картой для воспроизводимых проверок на testnet/local harness/mainnet read-only simulation.

## 2. Приоритетный список всех сценариев

| Rank | ID | Scenario | Contracts | Impact | Repro | Non-obvious | Fuel-specific | Priority | Rationale |
|---:|---|---|---|---:|---:|---:|---:|---|---|
| 1 | TC-005 | L2 withdraw double finalize | Fuel L2 Bridge + FuelERC20GatewayV4 | 5 | 4 | 4 | 5 | P0 | Если withdrawal message можно финализировать дважды/форжить sender, L1 escrow под риском. |
| 2 | TC-001 | Replay L1->L2 deposit message | FuelERC20GatewayV4 + L2 asset bridge | 5 | 4 | 4 | 5 | P0 | Двойной mint bridge asset из replay/duplicate input-message lifecycle. |
| 3 | TC-002 | DepositWithData receiver reentrancy | Fuel L2 Bridge + malicious receiver | 5 | 4 | 5 | 5 | P0 | Mint/transfer/call receiver в async bridge flow; проверяет reentrancy и повторное потребление message. |
| 4 | TC-009 | Mira flash swap wrong-asset repayment | Mira AMM | 4 | 5 | 4 | 4 | P1 | Optimistic transfer before invariant validation + hook path; стабильный AMM POC. |
| 5 | TC-015 | Buy collateral stale oracle | Swaylend Market | 4 | 4 | 4 | 4 | P1 | Liquidation buy path + oracle ordering может дать value extraction. |
| 6 | TC-014 | Absorb duplicate account | Swaylend Market | 4 | 4 | 4 | 3 | P1 | Batch liquidation with duplicate accounts может ломать accounting/rewards. |
| 7 | TC-020 | Deposit-before-liquidation reward capture | Fluid StabilityPool | 4 | 4 | 4 | 3 | P1 | Reward snapshot/order manipulation вокруг liquidation offset. |
| 8 | TC-018 | Stale hint adjust_trove | Fluid BorrowOperations + SortedTroves | 4 | 4 | 4 | 3 | P1 | Ordered-list state corruption/DoS через устаревшие hints. |
| 9 | TC-024 | Cancel-fill race | V12 Orderbook | 4 | 3 | 5 | 5 | P1 | Async/off-chain matcher race между cancel и fill. |
| 10 | TC-025 | Double matcher fill | V12 Orderbook | 4 | 3 | 5 | 5 | P1 | Off-chain/on-chain рассинхрон может привести к double fill/value extraction. |
| 11 | TC-003 | DepositWithData receiver revert | Fuel L2 Bridge + reverting receiver | 4 | 4 | 4 | 5 | P1 | Stuck minted funds/resource leak при receiver failure. |
| 12 | TC-021 | Epoch/scale boundary liquidation | Fluid StabilityPool | 4 | 3 | 4 | 3 | P1 | Precision/snapshot bug на границе epoch/scale. |
| 13 | TC-013 | Multicall withdraw_base then supply_base | Swaylend Market | 4 | 4 | 3 | 3 | P1 | Principal sign crossing/reward drift через multicall sequence. |
| 14 | TC-016 | First-valid stale oracle | Swaylend Market | 4 | 3 | 4 | 3 | P1 | Oracle ordering bug, если первый валидный feed stale but acceptable. |
| 15 | TC-006 | Fee-on-transfer ERC20 deposit | FuelERC20GatewayV4 | 4 | 5 | 3 | 4 | P1 | L1 gateway сам предупреждает про fee-on-transfer incompatibility; impact high, novelty ниже. |
| 16 | TC-019 | Partial redemption cancellation | Fluid ProtocolManager | 4 | 3 | 4 | 3 | P1 | Multi-asset redemption cancellation/accounting drift. |
| 17 | TC-008 | Donation before first LP mint | Mira AMM | 3 | 5 | 3 | 3 | P2 | First LP/reserve skew может быть economic exploit, но impact зависит от pool bootstrapping. |
| 18 | TC-004 | Overflow refund aggregation | Fuel L2 Bridge | 4 | 2 | 4 | 5 | P2 | High impact, но нужен точный source-level path и edge values. |
| 19 | TC-017 | Concurrent liquidation MEV | Swaylend Market | 4 | 3 | 3 | 3 | P2 | Вероятный MEV/race, но может быть expected market behavior. |
| 20 | TC-011 | Repeated tiny mint/burn dust drift | Mira AMM | 3 | 5 | 3 | 3 | P2 | Хорошо воспроизводится, но обычно capped by fees/dust. |
| 21 | TC-012 | Hook grief and reentry | Mira AMM | 3 | 4 | 3 | 4 | P2 | Hook-surface важна, но owner-controlled path снижает bounty value. |
| 22 | TC-007 | Withdrawal rate-limit boundary | FuelERC20GatewayV4 | 3 | 3 | 3 | 4 | P2 | Зависит от конфигурации лимитов и admin timing. |
| 23 | TC-010 | Fee recipient equals swap receiver | Mira AMM | 3 | 4 | 3 | 3 | P2 | Accounting perturbation вероятнее medium. |
| 24 | TC-022 | Close trove excess USDF refund | Fluid BorrowOperations | 3 | 4 | 3 | 3 | P2 | Resource lifecycle bug, но impact вероятно ограничен одним trove. |
| 25 | TC-023 | Register asset fan-out consistency | Fluid ProtocolManager | 3 | 3 | 3 | 3 | P3 | Governance/init bug; высокая ценность только при partial commit или bad auth. |

## 3. Топ-10 bounty candidates

### 1. TC-005: L2 Withdraw Double Finalization

| Field | Notes |
|---|---|
| Contracts | Fuel L2 bridge implementation + L1 `FuelERC20GatewayV4.finalizeWithdrawal`. |
| Steps | 1. Mint/obtain bridged test asset on L2. 2. Call L2 `withdraw` to burn asset and emit L1 withdrawal message. 3. Finalize withdrawal on L1 once. 4. Re-submit same proof/message or variant with same nonce/index. 5. Try sender/domain mismatch variants. |
| Expected | Same withdrawal can be finalized exactly once; replay must revert before escrow transfer. |
| Actual to test | If second finalize transfers again, or if state is marked after external transfer and can be bypassed, escrow drain/double withdrawal. |
| Impact | Critical: direct movement of L1 escrowed assets. |
| Risk | `Critical / Bridge drain`. |
| Reproducibility | High if local bridge harness can generate proofs; medium on public testnet because finalization proof tooling is needed. |
| Bounty note | Emphasize message id, nonce/index, sender validation, and whether finalization marker is written before asset transfer. |

### 2. TC-001: Replay L1->L2 Deposit Message

| Field | Notes |
|---|---|
| Contracts | L1 `FuelERC20GatewayV4.deposit/depositWithData`, L2 `process_message(msg_idx)`. |
| Steps | 1. Deposit ERC20 from L1 to L2. 2. Wait until message is available on Fuel. 3. Call `process_message(msg_idx)` once. 4. Attempt repeated `process_message` with same index/input. 5. Repeat inside batched/multi-call transaction if possible. |
| Expected | Message is consumed once by Fuel input-message lifecycle; second attempt reverts or cannot construct valid inputs. |
| Actual to test | Duplicate mint, duplicate asset transfer, or inconsistent refund/accounting event. |
| Impact | Critical: unauthorized L2 mint of bridged asset. |
| Risk | `Critical / Bridge mint replay`. |
| Reproducibility | High locally, medium on public net depending on message tooling. |
| Bounty note | This is most valuable if it bypasses both VM-level message consumption and contract-level guard. |

### 3. TC-002: DepositWithData Receiver Reentrancy

| Field | Notes |
|---|---|
| Contracts | Fuel L2 bridge + malicious `MessageReceiver` contract. |
| Steps | 1. Deploy receiver implementing bridge callback. 2. Send L1 `depositWithData` to receiver. 3. In callback, attempt nested calls: `process_message` on same/other message, `claim_refund`, `withdraw`, or asset forwarding. 4. Compare balances, consumed messages, events. |
| Expected | Reentrant bridge entrypoints revert or cannot affect current message lifecycle; total minted amount equals one deposit. |
| Actual to test | Reentrant second mint, premature refund, stuck asset, or inconsistent bridge accounting. |
| Impact | Critical if double mint/withdraw; high if stuck bridge funds. |
| Risk | `Critical / Reentrancy in async bridge path`. |
| Reproducibility | High once malicious receiver is deployed. |
| Bounty note | Highlight Fuel-specific contract call after mint/transfer and resource ownership of the minted asset. |

### 4. TC-009: Mira Flash Swap Wrong-Asset Repayment

| Field | Notes |
|---|---|
| Contracts | Mira AMM `swap` with optional hook/callee. |
| Steps | 1. Create or use low-liquidity test pool. 2. Execute swap taking asset A out. 3. In hook, repay mostly/only asset B or use transfer timing to perturb balances. 4. Verify invariant, reserves, fees, LP token value. 5. Repeat with fee recipient equal to receiver and with exact boundary amounts. |
| Expected | Swap reverts unless post-callback balances satisfy invariant with correct fee accounting. |
| Actual to test | Pool accepts wrong-asset repayment, reserve drift, or LP value leakage. |
| Impact | High: AMM pool drain/value extraction. |
| Risk | `High / AMM invariant bypass`. |
| Reproducibility | High in local test harness. |
| Bounty note | The non-obvious part is optimistic transfer before invariant validation plus Fuel asset/resource transfer semantics. |

### 5. TC-015: Swaylend Buy Collateral Stale Oracle

| Field | Notes |
|---|---|
| Contracts | Swaylend Market `absorb`, `buy_collateral`, oracle update path. |
| Steps | 1. Configure two price feeds with different freshness/order. 2. Create underwater account. 3. Absorb account using one price. 4. Before/inside buy path, provide stale-but-valid feed or reorder feed list. 5. Buy collateral and measure discount vs true price. |
| Expected | Buy collateral uses fresh, intended oracle value and cannot be sandwiched by stale feed ordering. |
| Actual to test | Buyer receives underpriced collateral or protocol accounting diverges from expected reserves. |
| Impact | High: oracle MEV/value extraction from lending market. |
| Risk | `High / Oracle ordering + liquidation`. |
| Reproducibility | Medium-high; requires oracle mocks or controlled testnet feeds. |
| Bounty note | Include exact oracle timestamps, feed order and before/after collateral/base balances. |

### 6. TC-014: Swaylend Absorb Duplicate Account

| Field | Notes |
|---|---|
| Contracts | Swaylend Market `absorb`. |
| Steps | 1. Create one liquidatable borrower. 2. Call `absorb` with the same account repeated in the accounts array. 3. Repeat with partially liquidatable and already-liquidated state. 4. Compare reserves, principal, reward events and collateral seized. |
| Expected | Duplicate accounts are rejected or processed idempotently. |
| Actual to test | Double seizure, double reserve accounting, duplicate reward credit, or inconsistent borrower principal. |
| Impact | High: liquidation accounting break. |
| Risk | `High / Batch liquidation idempotency`. |
| Reproducibility | High in a unit/integration test. |
| Bounty note | Strong bounty candidate because steps are simple and failure is easy to prove with before/after balances. |

### 7. TC-020: Fluid Deposit-Before-Liquidation Reward Capture

| Field | Notes |
|---|---|
| Contracts | Fluid StabilityPool + liquidation/offset caller. |
| Steps | 1. Prepare trove close to liquidation. 2. User A deposits to StabilityPool immediately before liquidation. 3. Liquidate/offset. 4. User A withdraws. 5. Compare reward gain vs time-weighted/existing depositor share. |
| Expected | Rewards are distributed according to protocol economics and snapshots; last-block depositor cannot capture disproportionate gains unless designed. |
| Actual to test | New depositor captures prior-risk liquidation gain or manipulates snapshot boundary. |
| Impact | High: reward theft/value extraction from stability pool participants. |
| Risk | `High / Reward snapshot manipulation`. |
| Reproducibility | High with local liquidation setup. |
| Bounty note | Show exact snapshot values before deposit, after deposit, after offset and after withdraw. |

### 8. TC-018: Fluid Stale Hint Adjust Trove

| Field | Notes |
|---|---|
| Contracts | Fluid BorrowOperations + SortedTroves. |
| Steps | 1. Open multiple troves with ordered collateral ratios. 2. Compute valid hints for one trove. 3. Change neighboring troves so hints become stale. 4. Call `adjust_trove` or `re_insert` using old hints. 5. Inspect sorted list invariants and traversal behavior. |
| Expected | Stale hints are rejected or corrected; list remains sorted and traversable. |
| Actual to test | List corruption, wrong ordering, DoS via expensive traversal, or broken redemption/liquidation order. |
| Impact | High: protocol accounting/availability risk. |
| Risk | `High / Ordered-list state corruption`. |
| Reproducibility | High locally; deterministic ordering makes good POC. |
| Bounty note | Include invariant checker: prev/next consistency, sorted ICR order, head/tail reachability. |

### 9. TC-024: V12 Cancel-Fill Race

| Field | Notes |
|---|---|
| Contracts | V12 orderbook / matcher / settlement path. |
| Steps | 1. Place order. 2. Send cancel transaction. 3. Have matcher submit fill based on stale off-chain order state. 4. Vary transaction order, same block inclusion and partial fill amount. 5. Compare order status and asset settlement. |
| Expected | Either cancel wins or fill wins deterministically; no state allows both asset movement and cancelled status. |
| Actual to test | Cancelled order is filled, partial fill escapes status update, or maker/taker balances mismatch. |
| Impact | High: orderbook value extraction or user asset loss. |
| Risk | `High / Async matcher race`. |
| Reproducibility | Medium until source/contracts are fully mapped. |
| Bounty note | Needs exact deployed contract and matcher assumptions before submission. Keep as top-10 because uniqueness is high. |

### 10. TC-025: V12 Double Matcher Fill

| Field | Notes |
|---|---|
| Contracts | V12 orderbook / matcher / settlement path. |
| Steps | 1. Create order with limited fillable amount. 2. Submit two fills from same or competing matcher identities using same order state. 3. Try same-block ordering and split partial fills. 4. Inspect filled amount, order status, maker/taker settlement. |
| Expected | Filled amount is monotonic and cannot exceed order size; duplicate fill is rejected. |
| Actual to test | Overfill, double settlement, or accounting mismatch between off-chain order state and on-chain storage. |
| Impact | High: direct value extraction from orderbook users. |
| Risk | `High / Double-fill race`. |
| Reproducibility | Medium until contract/source path is collected. |
| Bounty note | Best submitted only with exact tx ordering and proof that both fills were accepted by on-chain state. |

## 4. POC execution notes

### Bridge POCs

Minimum harness requirements:

| Component | Need |
|---|---|
| L1 local chain | Deploy/mock `FuelMessagePortal`, gateway, ERC20. |
| Fuel local node/testnet | Ability to consume messages and inspect message status. |
| Malicious receiver | Contract implementing callback that attempts nested bridge calls. |
| Assertions | Message consumed once, minted amount equals deposit, finalization marker prevents replay, escrow balance decreases once. |

POC evidence to capture:

- L1 deposit tx hash and message id.
- L2 `process_message` tx id and minted asset id.
- Balance before/after for depositor, receiver, bridge escrow.
- Revert reason or success for replay attempt.
- For reentrancy: nested call trace and final resource ownership.

### AMM POCs

Minimum harness requirements:

| Component | Need |
|---|---|
| Mira pool | Test pool with two assets and controllable initial reserves. |
| Hook/callee | Contract that receives swap callback and sends custom repayment. |
| Assertions | Constant-product/invariant check, reserve update, LP token supply, fee recipient balance. |

POC evidence to capture:

- Reserves before and after each call.
- Exact asset inputs/outputs from transaction receipts.
- LP token supply and LP holder value delta.
- Whether wrong-asset repayment succeeds or reverts.

### Lending POCs

Minimum harness requirements:

| Component | Need |
|---|---|
| Swaylend market | Local deployment or fork-like environment with oracle mocks. |
| Oracle mocks | Ability to set freshness, timestamp and price ordering. |
| Liquidatable users | Borrowers with controlled collateral/base debt. |
| Assertions | Idempotent absorb, reserves consistency, no stale oracle discount. |

POC evidence to capture:

- Borrower principal/collateral before and after absorb.
- Protocol reserves before and after duplicate account array.
- Oracle timestamps and selected feed.
- Collateral bought vs expected fair amount.

### Fluid POCs

Minimum harness requirements:

| Component | Need |
|---|---|
| Trove set | Multiple troves with controlled collateral ratios. |
| Sorted list checker | Script/contract helper to verify prev/next and order. |
| StabilityPool | Deposits before and after liquidation/offset. |
| Assertions | No stale-hint corruption; reward snapshots distribute as intended. |

POC evidence to capture:

- SortedTroves head/tail and full traversal.
- Per-user deposit snapshots before/after liquidation.
- Reward gain for late depositor vs existing depositor.
- Redemption/liquidation success after attempted stale hint.

### Orderbook POCs

Minimum harness requirements:

| Component | Need |
|---|---|
| V12 contract ids/source | Exact deployed contract and ABI. |
| Matcher simulator | Two competing fill/cancel transactions from stale local state. |
| Assertions | No fill after cancel, no overfill, no double settlement. |

POC evidence to capture:

- Order id and order state before each tx.
- Mempool/block ordering if available.
- Final filled amount and maker/taker balances.
- Off-chain matcher state vs on-chain status.

## 5. Что отсеяно из топ-10

| Scenario | Reason |
|---|---|
| TC-006 Fee-on-transfer ERC20 deposit | Impact high, но публично известный класс; сам gateway code/comment already warns. Проверять стоит, но bounty novelty ниже. |
| TC-003 DepositWithData receiver revert | Очень важный ресурсный сценарий, но чаще приводит к stuck funds, а не direct drain. Держать как bridge P1 сразу после топ-10. |
| TC-013 Multicall principal sign crossing | Хороший Swaylend POC, но вероятность expected behavior/covered tests выше. |
| TC-016 First-valid stale oracle | Близко к TC-015; лучше объединить как oracle bundle после основного buy-collateral POC. |
| TC-021 Epoch/scale boundary | Потенциально ценный, но сложнее доказать significant impact без precise numeric edge. |
| TC-019 Partial redemption cancellation | Требует больше Fluid-specific setup; оставить вторым Fluid POC после stale hints/reward snapshots. |

## 6. Рекомендуемый порядок работы

1. Bridge replay/finalization bundle: `TC-005`, `TC-001`, `TC-002`, затем `TC-003`.
2. Mira AMM invariant bundle: `TC-009`, затем `TC-008`, `TC-011`.
3. Swaylend liquidation/oracle bundle: `TC-014`, `TC-015`, затем `TC-016`, `TC-013`.
4. Fluid state machine bundle: `TC-018`, `TC-020`, затем `TC-019`, `TC-021`.
5. V12 async matcher bundle: `TC-024`, `TC-025` после сбора точного ABI/source/deployments.

## 7. Формат bounty submission для каждого найденного бага

Использовать одинаковый skeleton:

```text
Title:
  [Protocol] [Contract] Bug class and impact in one sentence

Summary:
  What state transition/resource lifecycle breaks and why it matters.

Affected contracts:
  Contract id, source commit, function names.

Preconditions:
  Asset, oracle state, pool reserves, user balances, message id, or order state.

Steps to reproduce:
  1. ...
  2. ...
  3. ...

Expected result:
  Correct invariant / revert / single finalization.

Actual result:
  Observed balance/state mismatch.

Impact:
  Quantified asset movement, locked value, protocol insolvency, or user loss.

Proof:
  Test name, tx ids, logs, balance tables.

Notes:
  Why this is Fuel-specific or non-obvious.
```

## 8. Итог

Самая высокая expected bounty value сейчас у bridge-сценариев (`TC-005`, `TC-001`, `TC-002`), потому что они напрямую затрагивают cross-chain escrow/mint lifecycle и используют Fuel message/resource модель. Следующая группа - AMM/lending/liquidation сценарии (`TC-009`, `TC-015`, `TC-014`, `TC-020`, `TC-018`), где POC проще довести до стабильного local harness. V12 сценарии (`TC-024`, `TC-025`) потенциально очень ценные из-за async matcher модели, но требуют дополнительного source/deployment mapping перед реальным bounty submission.
