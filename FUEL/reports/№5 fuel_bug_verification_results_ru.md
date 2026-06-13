# Fuel: верификация P0/P1 баг-кандидатов и готовность к bounty

Дата проверки: 2026-05-13  
Режим: безопасный, без подписанных транзакций и без движения реальных активов.  
Mainnet RPC read-only: `https://mainnet.fuel.network/v1/graphql`, сеть `Ignition`, высота при проверке `53411985`.

## 1. Ограничения проверки

В этом окружении не найден Fuel toolchain: `forc`, `fuelup`, `forc-client` недоступны. Поэтому я не смог честно выполнить локальные Fuel integration tests или отправить testnet/mainnet транзакции. Проверка ниже основана на:

- локально скачанных исходниках Fuel Bridge, Mira, Swaylend, Fluid;
- уже собранных ABI/deployment snapshots;
- read-only проверке доступности Fuel mainnet RPC;
- анализе existing tests и guard logic.

Итог: **подтвержденных live exploit POC пока нет**. Часть сценариев по исходникам выглядит защищенной и помечена как `Not reproduced / Guarded`. Часть остается `Inconclusive` и требует локального harness или testnet кошелька.

## 2. Verification matrix P0/P1

| Bug ID | Scenario | Contract(s) | Verification status | Expected vs Actual | Risk after verification | Reproducibility | NonObviousness | POC description |
|---|---|---|---|---|---|---|---|---|
| TC-005 | L2 withdraw double finalize | Fuel L2 Bridge + FuelERC20GatewayV4 | Not reproduced / Guarded by source | Expected: one finalization. Actual source-level: L1 portal checks `_incomingMessageSuccessful[messageId]` and reverts `AlreadyRelayed`; gateway has `onlyFromPortal` and `messageSender() == assetIssuerId`. | Reduced from P0 to watchlist P1 until proof bypasses portal replay guard. | Medium: needs valid withdrawal proof tooling. | High: bridge replay path is non-trivial. | Build local L1+Fuel bridge harness; relay same message twice; evidence must show second relay succeeds despite `AlreadyRelayed`. |
| TC-001 | Replay L1->L2 deposit message | FuelERC20GatewayV4 + L2 bridge asset contract | Not reproduced / Guarded by VM + source | Expected: same L1 message consumed once. Actual source-level: L2 `process_message(msg_idx)` checks `input_message_sender == BRIDGED_TOKEN_GATEWAY`; replay should be blocked by Fuel message UTXO consumption and reentrancy guard. | Reduced from P0 to P1/watchlist. | Medium-high with local message harness. | High due Fuel message input lifecycle. | Try to include same message input twice across two transactions and inside a multi-call; success criteria is duplicate mint. |
| TC-002 | DepositWithData receiver reentrancy | Fuel L2 Bridge + malicious receiver | Not reproduced / Existing test indicates guarded | Expected: receiver cannot reenter bridge. Actual source/test evidence: `process_message` calls `reentrancy_guard()`; repo contains `rejects_reentrancy_attempts` test asserting revert. | Reduced from P0 to guarded P1. | High if toolchain installed. | Medium-high; callback after mint is Fuel-specific. | Re-run upstream reentrancy attacker test; extend attacker to try `claim_refund`, `withdraw`, and second message processing. |
| TC-009 | Mira flash swap wrong-asset repayment | Mira AMM | Not reproduced / likely guarded by invariant | Expected: wrong repayment reverts. Actual source-level: swap performs optimistic transfer, optional callee hook, then computes `asset_0_in/asset_1_in` and calls `validate_curve`; existing tests include curve violation cases. | Reduced to P2 unless numeric edge bypasses `validate_curve`. | High locally. | Medium: AMM invariant bug class is known, Fuel transfer accounting makes it worth testing. | Add malicious callee that repays only opposite asset; assert `CurveInvariantViolation` or reserve drift. |
| TC-015 | Buy collateral stale oracle | Swaylend Market | Inconclusive / source confirms dependency on external price update | Expected: buy uses fresh price. Actual source-level: `buy_collateral` does not update oracle; comment says caller is expected to update in same multicall. `get_price_internal` returns first valid oracle price. | Still P1 candidate if stale-but-valid price can be selected. | Medium: requires oracle mocks and timing. | High: first-valid oracle ordering + multicall expectation. | Controlled oracle test: two feeds with different freshness/prices, absorb, then buy collateral without update or with reordered feeds. |
| TC-014 | Absorb duplicate account | Swaylend Market | Not reproduced / likely transaction reverts on duplicate | Expected: duplicate account rejected or idempotent. Actual source-level: `absorb` loops accounts; `absorb_internal` requires liquidatable status each time. After first absorb, second same account should fail `NotLiquidatable`, likely reverting whole tx. | Reduced to P2/DoS-of-caller, not asset drain, unless partial commits observed. | High locally. | Medium. | Add test with `[borrower, borrower]`; success criteria for bug is state change persists despite second revert. Expected safe result is full revert. |
| TC-020 | Deposit-before-liquidation reward capture | Fluid StabilityPool | Inconclusive | Expected: snapshots prevent unfair late reward capture. Actual source-level: deposit pays pending gains then updates deposit snapshots; `offset` updates reward sum/product. Need numeric local test. | Remains P1 candidate. | Medium-high locally. | High for reward snapshot timing. | Create two depositors, deposit second immediately before liquidation/offset, compare asset gain vs intended share. |
| TC-018 | Stale hint adjust_trove | Fluid BorrowOperations + SortedTroves | Not reproduced / source has correction path | Expected: stale hints cannot corrupt list. Actual source-level: `internal_insert` checks `internal_valid_insert_position`; if invalid, calls `internal_find_insert_position`. Existing tests verify hint gas and list ordering. | Reduced to P2 unless gas grief or traversal DoS is measurable. | High locally. | Medium. | Test stale hints after neighbor reorder; bug requires corrupted prev/next or excessive traversal causing practical DoS. |
| TC-024 | Cancel-fill race | V12 Orderbook | Not verifiable / missing exact source and deployment mapping | Expected: cancel/fill mutually exclusive. Actual: no contract source/ABI in workspace, cannot verify. | Keep P1 discovery candidate, not bounty-ready. | Unknown. | High. | Collect V12 contract ids, ABI, matcher assumptions; then simulate same-block cancel/fill ordering. |
| TC-025 | Double matcher fill | V12 Orderbook | Not verifiable / missing exact source and deployment mapping | Expected: filled amount cannot exceed order amount. Actual: no contract source/ABI in workspace. | Keep P1 discovery candidate, not bounty-ready. | Unknown. | High. | Same as TC-024; need overfill settlement evidence. |
| TC-003 | DepositWithData receiver revert | Fuel L2 Bridge + reverting receiver | Inconclusive / source contains known TODO | Expected: failed receiver cannot leave stuck minted funds. Actual source-level: `_process_deposit` mints then calls receiver for `ContractWithData`; code has TODO that failed call may leave funds stuck. Need execution to know rollback semantics in this path. | P1 if stuck resources persist; lower if whole tx reverts atomically. | High locally. | Medium; public TODO reduces novelty. | Receiver reverts after receiving coins; inspect total supply, bridge balance, receiver balance and message consumability after revert. |
| TC-021 | Epoch/scale boundary liquidation | Fluid StabilityPool | Inconclusive | Expected: epoch/scale math preserves rewards. Actual source-level: complex `current_epoch`, `current_scale`, `P`, `S`, `G` math; no numeric run here. | P1 if precision loss materially reallocates rewards. | Medium. | High. | Construct offset that crosses scale boundary; compare exact rational expected gains with contract gains. |
| TC-013 | Multicall withdraw_base then supply_base | Swaylend Market | Inconclusive | Expected: principal/reward accounting stable across sign crossing. Actual source-level: `withdraw_base` and `supply_base` accrue and update principal; existing multicall tests exist but specific reward manipulation not executed here. | P1/P2 depending on numeric delta. | Medium-high locally. | Medium. | One transaction: withdraw to borrow side, then supply back; compare tracking indices and rewards vs two separate txs. |
| TC-016 | First-valid stale oracle | Swaylend Market | Inconclusive / source confirms first-valid selection | Expected: stale feed rejected. Actual source-level: loop breaks on first `is_fetched_price_valid`; must test oracle validity thresholds. | P1 if stale-but-valid feed can dominate fresher feed. | Medium. | High. | Configure Pyth/Stork mocks with divergent timestamps and prices; reorder oracle asset configs. |
| TC-006 | Fee-on-transfer ERC20 deposit | FuelERC20GatewayV4 | Source-confirmed compatibility risk, not live reproduced | Expected: bridge mints only actual received amount. Actual source-level: `_deposit` increments `_deposits` and sends Fuel message before `safeTransferFrom(amount)`; comment says not compatible with fee-on-transfer tokens. | P1 only if such token is whitelisted/accepted; otherwise known limitation. | High in local EVM test. | Low-medium because source comment is explicit. | Deploy fee-on-transfer ERC20 in local L1; deposit 100, gateway receives 99, L2 message mints 100. |
| TC-019 | Partial redemption cancellation | Fluid ProtocolManager | Inconclusive | Expected: partial redemption cancellation preserves accounting. Actual source-level: multi-asset redemption and hints are complex; no execution here. | P1 if accounting drift or unfair cancellation observed. | Medium. | High. | Multi-asset redemption with stale partial hints; compare USDF burned, collateral drawn, fee, surplus. |

## 3. Detailed findings

### Bridge candidates

#### TC-005: L2 withdraw double finalize

Source evidence:

- `FuelMessagePortalV3._executeMessage` checks `_incomingMessageSuccessful[messageId]` and reverts `AlreadyRelayed`.
- `FuelMessagePortalV3._executeMessage` is `nonReentrant`.
- `FuelERC20GatewayV4.finalizeWithdrawal` is `onlyFromPortal`.
- `FuelERC20GatewayV4.finalizeWithdrawal` checks `messageSender() == assetIssuerId`.
- Gateway reduces `_deposits[tokenAddress]` before `safeTransfer`.

Actual outcome in this environment: **not reproduced**. The hypothesized double-finalization is guarded unless a POC bypasses portal message id uniqueness, proof verification, or sender domain validation.

Bounty readiness: **not ready**. Needs real proof replay attempt. A valid bounty POC must show the second relay succeeded and escrow transferred twice.

#### TC-001: L1->L2 deposit replay

Source evidence:

- L2 `process_message(msg_idx)` starts with `reentrancy_guard()`.
- It reads `input_message_sender(msg_idx)` and requires it equals `BRIDGED_TOKEN_GATEWAY`.
- No contract-local processed-message mapping is visible, so replay prevention relies on Fuel message input/UTXO lifecycle plus the guard.

Actual outcome: **not reproduced**. Expected safe result is that the same message input cannot be spent twice.

Bounty readiness: **not ready**. Strong POC would include two accepted transactions using the same message and a duplicated minted supply delta.

#### TC-002: DepositWithData receiver reentrancy

Source evidence:

- `process_message` is protected with `reentrancy_guard`.
- Upstream bridge tests include `rejects_reentrancy_attempts`, which expects the attacker transaction to revert.

Actual outcome: **not reproduced in this environment**, but existing source/tests indicate the straightforward reentrancy path is guarded.

Residual useful test: extend the malicious receiver beyond direct reentry into `process_message`: try `claim_refund`, `withdraw`, and interaction with a second pending message.

#### TC-003: DepositWithData receiver revert

Source evidence:

- `_process_deposit` updates `tokens_minted`, mints, then for `ContractWithData` calls receiver `process_message` with coins.
- The code contains a TODO warning that if this call fails, funds may get stuck.

Actual outcome: **inconclusive**. This is the bridge scenario most worth executing next, because the source itself flags a stuck-funds risk. The key question is whether Fuel transaction rollback fully restores mint/supply/message state after receiver failure.

### Mira AMM

#### TC-009: flash swap wrong-asset repayment

Source evidence:

- `swap` optimistically transfers output assets before callback.
- It then computes input accounting and calls `validate_curve`.
- Existing tests include curve-invariant violation cases.

Actual outcome: **not reproduced**. Source strongly suggests wrong repayment should revert through `validate_curve`, unless there is an edge in fee subtraction, multi-pool accounting, or fee-recipient transfer.

Bounty readiness: **not ready**. Needs a malicious callee test that produces reserve drift after success.

### Swaylend

#### TC-014: duplicate absorb

Source evidence:

- `absorb(accounts)` loops over supplied accounts.
- `absorb_internal(account)` requires `is_liquidatable_internal(account, old_balance)`.
- First absorb zeroes collateral and updates principal; a repeated account should no longer be liquidatable.

Actual outcome: **not reproduced**. Most likely result is full transaction revert on the second duplicate, not partial double-accounting. This remains worth testing because the difference between full revert and partial persisted state is decisive.

#### TC-015 / TC-016: stale oracle / first-valid oracle

Source evidence:

- `buy_collateral` explicitly does not update price feeds; comments say caller is expected to update prices in the same transaction using multicall.
- `get_price_internal` loops oracle configs and stops at the first fetched valid price.

Actual outcome: **inconclusive**. This remains one of the best P1 candidates because it depends on live oracle validity thresholds, feed order, and multicall conventions, not just a simple access-control guard.

### Fluid

#### TC-018: stale hints

Source evidence:

- `SortedTroves.internal_insert` validates the provided position.
- If hints are invalid, it calls `internal_find_insert_position`.
- Existing tests include sorted-list ordering and hint gas usage.

Actual outcome: **not reproduced**. Corruption by stale hints looks unlikely. A gas/traversal grief angle may remain if a bad hint forces expensive scans.

#### TC-020 / TC-021: StabilityPool snapshots and epoch/scale

Source evidence:

- `provide_to_stability_pool` pays pending gains and updates snapshots.
- `offset` updates reward sum/product.
- Reward accounting uses `current_epoch`, `current_scale`, `P`, `S`, `G`, and second-scale portions.

Actual outcome: **inconclusive**. These require numeric local tests; static reading is insufficient. The best POC is a before/after table comparing mathematically expected gain vs contract gain for late deposit and scale-boundary liquidation.

### V12 orderbook

TC-024 and TC-025 are **not verifiable** in the current workspace. There is no exact V12 source/ABI/deployment mapping in the local artifacts. They remain discovery candidates, not bounty-ready findings.

## 4. Bounty readiness ranking after verification

| Rank | Bug ID | Current bounty status | Why |
|---:|---|---|---|
| 1 | TC-003 | Next to execute | Source TODO directly flags stuck-funds risk in `ContractWithData` receiver failure path. |
| 2 | TC-015 / TC-016 | Next to execute | Source confirms first-valid oracle and no update inside `buy_collateral`; needs controlled oracle POC. |
| 3 | TC-020 / TC-021 | Next to execute | Snapshot/epoch/scale math can hide non-obvious numeric bugs; needs deterministic harness. |
| 4 | TC-014 | Quick negative test | Likely guarded by full revert; easy to confirm with duplicate array. |
| 5 | TC-009 | Quick negative test | Likely guarded by invariant; useful to prove with malicious callee. |
| 6 | TC-005 / TC-001 / TC-002 | Guarded unless deeper bypass found | High impact, but source and existing tests point to replay/reentry protections. |
| 7 | TC-024 / TC-025 | Needs discovery | Cannot verify until V12 source/ABI/contracts are collected. |

## 5. Bugs not reproduced and reason

| Bug ID | Reason |
|---|---|
| TC-005 | L1 portal has replay marker and nonReentrant; gateway restricts caller and Fuel sender. No proof bypass available. |
| TC-001 | L2 message processing is tied to Fuel input-message lifecycle; no ability here to spend same input twice. |
| TC-002 | Reentrancy guard present; upstream test already expects reentrant attacker to revert. |
| TC-009 | Curve validation should reject wrong repayment; no malicious callee execution available. |
| TC-014 | Duplicate account should cause `NotLiquidatable` on second pass and revert whole tx; not executed. |
| TC-018 | Stale hints are corrected by `internal_find_insert_position`; no corruption reproduced. |
| TC-024 | Missing V12 source/ABI/deployment mapping. |
| TC-025 | Missing V12 source/ABI/deployment mapping. |

## 6. Candidate POC scripts/tests to implement next

| Target | Test name | Pass condition for bug | Expected safe result |
|---|---|---|---|
| Fuel Bridge | `receiver_revert_does_not_lock_minted_assets` | Receiver revert leaves bridge supply/balance changed or message consumed unrecoverably. | Full rollback or safe refund path. |
| Fuel Bridge | `deposit_message_replay_rejected` | Same message mints twice. | Second spend impossible/reverts. |
| Fuel Bridge | `withdrawal_message_double_relay_rejected` | Same L2 withdrawal releases L1 escrow twice. | Portal reverts `AlreadyRelayed`. |
| Mira | `flash_swap_wrong_asset_repayment_reverts` | Swap succeeds and reserves drift. | Revert with curve/invariant error. |
| Swaylend | `absorb_duplicate_account_is_idempotent_or_reverts_cleanly` | Partial state persists after duplicate account revert or double reward/seizure appears. | Full revert or idempotent no-op. |
| Swaylend | `buy_collateral_rejects_stale_first_valid_oracle` | Underpriced collateral purchase succeeds using stale feed. | Stale feed rejected or fresh feed selected. |
| Fluid | `late_deposit_cannot_capture_prior_liquidation_gain` | Late depositor gets gain exceeding expected pro-rata exposure. | Gain equals intended share. |
| Fluid | `scale_boundary_reward_math_matches_reference` | Contract gain differs materially from reference math at scale boundary. | Difference bounded to documented rounding. |
| Fluid | `stale_hints_do_not_corrupt_sorted_troves` | prev/next inconsistency, wrong order, or unreachable node. | Hints corrected and list remains sorted. |

## 7. Final status

На текущем этапе нет багов, которые можно честно пометить как “успешно воспроизведены и готовы к bounty submission”. Самые сильные P0 bridge-гипотезы после source-level проверки выглядят защищенными стандартными guards. Наиболее перспективные для следующего реального POC:

1. `TC-003` bridge `ContractWithData` receiver revert/stuck funds.
2. `TC-015/TC-016` Swaylend oracle ordering + stale price in `buy_collateral`.
3. `TC-020/TC-021` Fluid StabilityPool reward snapshot and epoch/scale math.
4. `TC-014` Swaylend duplicate absorb as quick negative/positive confirmation.
5. `TC-009` Mira wrong-asset flash repayment as quick invariant confirmation.

Для превращения этого отчета в bounty-ready пакет нужен следующий минимальный шаг: установить Fuel toolchain (`fuelup/forc`), запустить upstream tests, затем добавить targeted regression tests из раздела 6 и сохранить receipts/balance diffs.
