# Отчет №3: тест-кейсы и POC-сценарии для багов Fuel

Дата: 2026-05-13  
Цель: подготовить воспроизводимые сценарии для проверки на локальном devnet, тестнете или mainnet-fork/indexer environment.  
Статус: тест-план и POC blueprints. Фактическое поле `Actual outcome` заполняется после запуска.

Дополнительные артефакты:

- `data/test_case_matrix_fuel_bugs.csv` - машинно-читаемая матрица тест-кейсов.
- `pocs/fuel_bug_poc_blueprints.md` - POC skeletons для быстрого переноса в Rust/Fuels или TS tests.

Локальная заметка: `forc` в текущем окружении не найден, поэтому POC не запускались. Сценарии привязаны к уже загруженным исходникам `sources/repos/*`.

## 1. Методология моделирования

Что моделируем:

- delayed execution: L1 deposit -> L2 message relay, L2 withdraw -> L1 finalize.
- async queues: повтор сообщения, out-of-order metadata/deposit, delayed finalization.
- multicall: oracle update + withdraw/borrow/liquidate/buy collateral в одной транзакции.
- competing tx: два ликвидатора, два matchers, stale hints, cancel/fill race.
- MEV: stale oracle buy, liquidation sandwich, donation-before-mint, first LP capture.
- resource lifecycle: native asset mint/burn, bridge escrow, refund map, LP reserves, reward snapshots.

Критерии баг-сигнала:

- Supply или escrow расходятся с balances.
- Один packet/message финализируется дважды.
- Ресурс burned/minted без recoverable path.
- Reserve/accounting drift растет после повторяемых циклов.
- Reward snapshot дает outsized reward тому, кто вошел прямо перед событием.
- Governance/proxy/hook меняет outcome без задержки или проверки target.

## 2. Матрица тест-кейсов

| ID | Contract(s) involved | Steps | Expected outcome | Actual outcome | Risk |
|---|---|---|---|---|---|
| TC-001 | FuelERC20GatewayV4 + Fuel L2 Bridge | Deposit ERC20 on L1; relay same message to L2; try relay same msg_idx again | Second relay impossible/fails; L2 supply unchanged | TBD | Critical double mint |
| TC-002 | Fuel L2 Bridge + malicious receiver | DepositWithData to receiver; receiver reenters `process_message(msg_idx)` | Reentrancy guard blocks nested relay | TBD | Critical replay |
| TC-003 | Fuel L2 Bridge + reverting receiver | DepositWithData to receiver that reverts | Full revert or defined refund path; no stuck mint | TBD | High stuck funds |
| TC-004 | Fuel L2 Bridge | Multiple overflow deposits same `from/token/token_id`; claim refund | Refund equals sum; cannot claim twice | TBD | High refund accounting |
| TC-005 | Fuel L2 Bridge + L1 Gateway | L2 withdraw; L1 finalize; try same finalize again | Second finalize rejected | TBD | Critical escrow drain |
| TC-006 | FuelERC20GatewayV4 | Fee-on-transfer ERC20 deposit | Reject or conservative accounting | TBD | High undercollateralization |
| TC-007 | FuelERC20GatewayV4 | Finalize around rate-limit period boundary | Limit cannot be bypassed | TBD | Medium/high |
| TC-008 | Mira AMM | Donate assets before first LP mint | Donation cannot be unfairly captured or drift documented | TBD | High LP drift |
| TC-009 | Mira AMM | Flash swap, callback repays wrong/insufficient asset | Tx reverts atomically | TBD | High invariant bypass |
| TC-010 | Mira AMM | Fee recipient equals receiver during swap | No reserve drift/double fee | TBD | Medium accounting |
| TC-011 | Mira AMM | Repeated tiny mint/burn cycles | Dust bounded; reserves match balances | TBD | Medium value leak |
| TC-012 | Mira AMM | Hook reverts/high gas/reenters | Grief possible if owner-set, no corruption | TBD | Medium governance |
| TC-013 | Swaylend Market | Multicall withdraw_base then supply_base crossing principal sign | Principal/rewards/totals consistent | TBD | High reward accounting |
| TC-014 | Swaylend Market | `absorb([A,A])` duplicate borrower | Reject or no-op second pass | TBD | High liquidation accounting |
| TC-015 | Swaylend Market | Absorb then buy collateral with stale vs fresh oracle | Stale price cannot be exploited | TBD | High oracle MEV |
| TC-016 | Swaylend Market | First oracle stale-valid, second fresh | Freshness/order rules prevent stale acceptance | TBD | High oracle ordering |
| TC-017 | Swaylend Market | Two liquidators compete absorb/buy | No negative reserves; at most one wins | TBD | High MEV/race |
| TC-018 | Fluid BorrowOperations + SortedTroves | Generate hints, reorder list, submit stale hints | Safe reinsert or revert; list invariant preserved | TBD | High list corruption |
| TC-019 | Fluid ProtocolManager | Redeem with bad partial hint and low max_iterations | No partial drift; remaining USDF returned | TBD | High redemption |
| TC-020 | Fluid StabilityPool | Deposit right before liquidation/offset, withdraw after | Rewards proportional | TBD | High reward manipulation |
| TC-021 | Fluid StabilityPool | Tiny deposits + large offset triggers epoch/scale | `P` nonzero and gains precise | TBD | High precision |
| TC-022 | Fluid BorrowOperations | Close trove exact/excess/wrong asset | Exact burn, excess refund, wrong asset rejected | TBD | Medium lifecycle |
| TC-023 | Fluid ProtocolManager | Child contract reverts during `register_asset` | Whole tx reverts; no partial registration | TBD | Medium governance init |
| TC-024 | V12 Orderbook | User cancels after matcher snapshot, matcher fills stale order | Fill fails after cancel | TBD | High async matcher |
| TC-025 | V12 Orderbook | Two matchers fill same order | One fill max, fee once | TBD | High MEV/double-fill |

## 3. Bridge POC scenarios

### TC-001: Replay L1->L2 Deposit

Contracts:

- L1 `FuelERC20GatewayV4`
- L2 bridge `process_message(msg_idx)`

Steps:

1. Deposit ERC20 on L1.
2. Relay generated message to L2.
3. Snapshot `tokens_minted[asset_id]`, receiver balance, bridge balance.
4. Attempt to relay same message input/proof again.
5. Attempt to mutate message data while preserving same nonce/proof in test harness.

Expected outcome:

- Second relay fails before mint.
- Supply and balances unchanged.

Actual outcome:

- TBD.

Risk:

- Critical if double mint possible.

### TC-002/003: DepositWithData Receiver Reentrancy/Revert

Contracts:

- L2 bridge
- malicious `MessageReceiver`

Steps:

1. Implement receiver variants:
   - `ReenterReceiver`: calls bridge `process_message(msg_idx)`.
   - `RevertReceiver`: reverts after receiving bridged coins.
   - `ConsumeReceiver`: transfers received funds elsewhere then returns.
2. Relay `DepositType::ContractWithData`.
3. Check tx status, receiver balance, bridge balance, `tokens_minted`, `refund_amounts`.

Expected outcome:

- Reentry blocked.
- Revert path does not leave minted unrecoverable assets.
- Consume path cannot register refund after successful delivery.

Actual outcome:

- TBD.

Risk:

- Critical/high: replay, stuck funds, refund drift.

### TC-005: L2 Withdraw Double Finalization

Steps:

1. User has bridged asset on Fuel.
2. User calls `withdraw(to)` and burns L2 asset.
3. Generate message proof.
4. Call L1 `finalizeWithdrawal`.
5. Replay same proof.
6. Try altered `to`, `tokenAddress`, `l2BurntAmount`.

Expected outcome:

- Exactly one unlock.
- Altered data rejected.

Risk:

- Critical escrow drain.

## 4. Mira AMM POC scenarios

### TC-008: Donation Before First LP Mint

Steps:

1. Deploy AMM and two assets.
2. Create pool.
3. Transfer assets directly to AMM without calling `mint`.
4. First LP deposits normal amounts and calls `mint`.
5. LP immediately calls `burn`.
6. Compare LP profit/loss, `total_reserves`, pool reserves, actual contract balances.

Expected outcome:

- No unfair capture or reserve desync.

Risk:

- High if first LP can capture donation or distort LP supply.

### TC-009: Flash Swap Wrong Repayment

Steps:

1. Seed pool.
2. Call `swap` with output and `data=Some`.
3. Malicious callee variants:
   - repay nothing.
   - repay wrong asset.
   - repay just below required input.
   - repay exact required input.
   - reenter AMM protected function.
4. Verify tx status and reserve/balance invariants.

Expected outcome:

- Invalid variants revert atomically.
- Valid variant preserves curve invariant.

Risk:

- High invariant bypass/value extraction.

### TC-011: Tiny Mint/Burn Drift

Steps:

1. Use assets with different decimals.
2. Initialize volatile and stable pools.
3. Loop 10k cycles of minimal mint/burn/swap.
4. Track cumulative dust, LP supply, reserves, balances.

Expected outcome:

- Drift bounded by documented rounding.

Risk:

- Medium/high if extractable drift grows monotonically.

## 5. Swaylend POC scenarios

### TC-013: Multicall Principal Sign Crossing

Reference:

- Existing repo tests include `multicall_withdraw_supply.rs`.

Steps:

1. User supplies base.
2. Same tx: update oracle, withdraw enough base to become borrower, then supply/repay to become supplier again.
3. Repeat reverse order.
4. Compare `user_basic.principal`, `base_tracking_index`, `base_tracking_accrued`, `market_basic.total_supply_base`, `total_borrow_base`.

Expected outcome:

- No reward double accrual around zero crossing.

Risk:

- High reward manipulation if index delta applies to wrong sign.

### TC-014/015: Absorb + Buy Collateral Race

Reference:

- Existing repo tests include `multicall_absorb_buy_collateral.rs`.

Steps:

1. Borrower becomes liquidatable after oracle update.
2. Liquidator calls `absorb([borrower, borrower])`.
3. Immediately call `buy_collateral` in same multicall and in next tx.
4. Repeat with stale oracle data and fresh oracle data.
5. Run two liquidators in parallel: both attempt absorb/buy.

Expected outcome:

- Duplicate account cannot double seize.
- Buyer cannot exploit stale price.
- Only one liquidator captures collateral.

Risk:

- High liquidation/reserve drift and MEV.

### TC-016: First-Valid Oracle Ordering

Steps:

1. Configure two oracle sources for same asset.
2. Source A returns stale but confidence-valid price.
3. Source B returns fresh price.
4. Call liquidation/withdraw/buy paths.
5. Swap oracle order.

Expected outcome:

- Stale source rejected or explicit priority behavior is safe.

Risk:

- High oracle manipulation.

## 6. Fluid POC scenarios

### TC-018: Stale Hint Reinsert

Steps:

1. Open troves A/B/C.
2. Generate hints for A adjustment.
3. B changes collateral/debt and reorders list.
4. A submits adjustment with stale hints.
5. Verify list:
   - no duplicate A.
   - head/tail correct.
   - size unchanged.
   - NICR order descending.

Expected outcome:

- Safe reinsert or revert.

Risk:

- High list corruption or DoS.

### TC-019: Partial Redemption Cancellation

Steps:

1. Create multiple troves near MCR.
2. Redeemer calls `redeem_collateral(max_iterations=1, bad partial hint)`.
3. Repeat with `max_iterations` high.
4. Check:
   - redeemed USDF burned exactly.
   - remaining USDF returned.
   - active pool debt decreased exactly.
   - sorted list invariant preserved.

Expected outcome:

- No partial state drift on cancelled partial redemption.

Risk:

- High redemption accounting bug.

### TC-020/021: StabilityPool Reward Snapshot Manipulation

Steps:

1. Depositor A provides USDF early.
2. Depositor B provides just before liquidation.
3. Trigger liquidation/offset.
4. B withdraws immediately.
5. Repeat near epoch/scale boundaries using tiny total deposits and large liquidation.
6. Compare gains to mathematical expected pro-rata values.

Expected outcome:

- B receives proportional gain only.
- `P`, `S`, `G`, epoch/scale stay consistent.

Risk:

- High reward extraction/precision bug.

## 7. V12 Orderbook POC scenarios

Status: source/contract id still needed. Test should be built once V12 ABI or verified contract source is collected.

### TC-024: Cancel-Fill Race

Steps:

1. User places order.
2. Matcher/indexer snapshot observes order.
3. User cancels order.
4. Matcher submits stale fill.

Expected outcome:

- Fill fails after cancel.

Risk:

- High async matcher race.

### TC-025: Double Matcher Fill

Steps:

1. Two matchers compute same match.
2. Submit both fills with same order ids in adjacent blocks or same block if possible.
3. Check order remaining amount, balances and matcher fee.

Expected outcome:

- One succeeds, one fails/no-ops; fee once.

Risk:

- High double-fill/MEV.

## 8. Load and competing transaction plan

Local/devnet:

1. Use custom provider with manual block production if available.
2. Disable automining or batch transactions where tooling supports it.
3. Submit competing txs without waiting for receipts.
4. Compare final state against serial execution.

Patterns:

- Two liquidators absorb/buy same account.
- Two LPs mint around donation.
- Two matchers fill same order.
- Oracle update tx and liquidation tx reorder.
- Bridge metadata message delayed after deposit message.

Metrics:

- final balances by asset id.
- contract native balance vs stored reserve.
- total supply vs minted/burned counters.
- event count vs state delta.
- failed/success tx ratio under load.

## 9. Mainnet/testnet safety

Mainnet:

- Only read/simulate unless using tiny amounts and explicit authorization.
- Prefer `simulate`/dry-run and tracing before live tx.
- Never send exploit tx against third-party funds.

Testnet:

- Use fresh wallets and faucet assets.
- Start with isolated mock deployments where possible.
- Preserve tx ids, block heights, calldata/script data, receipts and logs for every POC.

## 10. Приоритет запуска

1. TC-002/003 bridge DepositWithData receiver reentrancy/revert.
2. TC-009 Mira flash swap wrong repayment.
3. TC-014/015 Swaylend absorb + buy collateral stale/duplicate path.
4. TC-018/019 Fluid stale hints + redemption cancellation.
5. TC-020/021 Fluid StabilityPool snapshot boundary.
6. TC-001/005 bridge replay/double-finalization.

Эти сценарии дают максимальную вероятность найти воспроизводимый logic/race bug с понятным impact.
