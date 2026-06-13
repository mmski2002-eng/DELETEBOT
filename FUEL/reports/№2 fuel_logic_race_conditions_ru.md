# Отчет №2: логика, deferred execution и race conditions в Fuel dApps

Дата: 2026-05-13  
Цель: определить зоны, где баги логики, resource lifecycle и race conditions наиболее вероятны.  
Статус: гипотезы для bug hunting, не подтвержденные уязвимости.

## Использованные исходники

Локально загружены:

- `sources/repos/fuel-bridge`
- `sources/repos/mira-v1-core`
- `sources/repos/swaylend-monorepo`
- `sources/repos/fluid-protocol`

Таблица гипотез также сохранена в `data/potential_logic_race_vulnerabilities.csv`.

## 1. Асинхронное и deferred execution

Главные deferred paths:

- Fuel bridge L1 -> L2: `FuelERC20GatewayV4.deposit/depositWithData` формирует сообщение, L2 `process_message(msg_idx)` позже mint-ит bridged asset. Это классический async bridge lifecycle.
- Fuel bridge L2 -> L1: L2 `withdraw(to)` burn-ит asset и отправляет L1 message, а L1 `finalizeWithdrawal` позже unlock-ит ERC20.
- Fuel bridge deposit-to-contract: `_process_deposit` может вызвать `dest_contract.process_message { coins: amount }(msg_idx)`. Это deferred callback в чужой контракт.
- V12: on-chain order book + off-chain matcher/indexer. Фактическое исполнение зависит от внешнего сервиса и актуальности индексера.
- Fluid redemption/liquidation: не async между блокчейнами, но deferred по состоянию: hints, sorted list, pending rewards, snapshots и batch loops.
- Swaylend oracle updates: часть функций ожидает, что price update будет сделан в той же транзакции или перед вызовом; `buy_collateral` прямо документирует ожидание multicall-style обновления цены.

## 2. Сложные state transitions

Mira:

- `mint`: вычисляет входящие assets через разницу между `this_balance` и stored reserves, mint-ит LP, затем обновляет reserves.
- `burn`: burn LP, рассчитывает пропорциональные outputs, переводит оба assets, затем обновляет reserves.
- `swap`: optimistically transfer assets out, optional callee hook, затем вычисляет input и проверяет curve invariant.
- `set_hook`: добавляет внешний stateful hook ко всем действиям.

Swaylend:

- `supply_base/withdraw_base`: principal может переходить через ноль между supplier и borrower; обновляются total supply/borrow и reward indices.
- `withdraw_collateral`: сначала уменьшает collateral maps, затем обновляет oracle и проверяет collateralization.
- `absorb`: batch liquidation, обнуляет collateral пользователя, меняет totals, использует oracle lower-bound prices.
- `buy_collateral`: продает protocol collateral reserves за base asset, полагаясь на актуальные цены и reserve accounting.
- `accrue_internal/update_base_principal`: reward snapshots завязаны на timestamp, utilization и sign principal.

Fluid:

- `open_trove`: несколько контрактов меняются в одной операции: TroveManager, SortedTroves, ActivePool, USDF token, FPT staking fee.
- `internal_adjust_trove`: apply pending rewards, пересчет ICR/NICR, reinsert в sorted list, перемещение USDF/collateral.
- `close_trove`: repay/burn USDF, close trove, send collateral, refund excess USDF.
- `redeem_collateral`: multi-asset traversal по sorted troves, partial redemption hints, fee transfer to staking, burn redeemed USDF.
- `StabilityPool`: deposit snapshots, FPT issuance, asset gain snapshots, epoch/scale/product math.
- `SortedTroves`: linked list с hints, head/tail, remove/reinsert.

## 3. Межконтрактные вызовы

Bridge:

- L1 `FuelERC20GatewayV4` -> `FuelMessagePortal.sendMessage`.
- L2 `process_message` -> optional destination `MessageReceiver.process_message`.
- L2 `withdraw/claim_refund` -> `send_message` обратно в L1 gateway.

Mira:

- `create_pool` вызывает SRC20 metadata (`get_symbol_and_decimals`).
- `swap` может вызвать callee hook.
- `mint/burn/swap` вызывают global hook через `IBaseHook`.

Swaylend:

- Oracle layer: Pyth/Stork через `Oracle.get_price/update_price_feeds`.
- Market зависит от native transfer и external oracle contracts.

Fluid:

- BorrowOperations вызывает Oracle, TroveManager, SortedTroves, ActivePool, USDF, FPTStaking.
- ProtocolManager вызывает StabilityPool, BorrowOperations, USDFToken, FPTStaking, CollSurplusPool, DefaultPool, ActivePool, SortedTroves, TroveManager.
- StabilityPool вызывает CommunityIssuance, TroveManager, ActivePool, USDF.
- SortedTroves вызывает TroveManager для NICR/ICR checks.

## 4. Таблица потенциальных уязвимостей

| Contract | Function | Potential Bug | Risk Type | Notes |
|---|---|---|---|---|
| Fuel L2 Bridge | `process_message(msg_idx)` | replay/double mint если message input lifecycle или guard обходится | Replay / double-finalization | Проверяет L1 sender и reentrancy guard; тестировать nested replay и повтор msg_idx |
| Fuel L2 Bridge | `_process_deposit` | deposit-to-contract может оставить minted assets stuck при failing receiver | Deferred execution / resource leak | В исходнике есть TODO о stuck funds на failed call |
| Fuel L2 Bridge | `claim_refund` | refund aggregation по `from+asset` может конфликтовать при нескольких failed deposits | Accounting / replay | Reset before `send_message`; тестировать ordering claims |
| Fuel L2 Bridge | `withdraw` | burn-before-L1-finalization может приводить к stuck withdrawal при bad metadata/proof path | Deferred finalization | Burn на L2, unlock позже на L1 |
| Fuel ERC20 Gateway V4 | `_deposit` | `sendMessage` до `safeTransferFrom`; fee-on-transfer/reentrant token может нарушить escrow assumptions | Bridge accounting | Комментарий Hexens: fee-on-transfer несовместим |
| Fuel ERC20 Gateway V4 | `finalizeWithdrawal` | replay/forged sender drain при ошибке portal/messageSender validation | Bridge finalization | Проверяет `onlyFromPortal` и `messageSender == assetIssuerId` |
| Fuel ERC20 Gateway V4 | `_addWithdrawnAmount` | boundary race around `currentPeriodEnd` и admin limit changes | Rate limit race | Тестировать границы периода и reduce/increase limit |
| Mira AMM | `swap` | optimistic transfer + optional callback до invariant validation | Callback / invariant race | Есть `reentrancy_guard`, но нужен malicious callee fuzz |
| Mira AMM | `swap` | protocol fee transfer до reserve update может менять balance assumptions | Accounting / callback composition | Особенно если fee recipient - contract |
| Mira AMM | `mint` | direct donations/pre-sent assets влияют на inferred `amount_in` | LP accounting | Проверить donation attack и first LP rounding |
| Mira AMM | `burn` | repeated small burns могут накапливать dust/reserve drift | Resource leak / rounding | Особенно stable pools и decimals |
| Mira AMM | `set_hook` | owner hook может grief-ить все pool actions | Governance / integration | Интерфейс не проверяется при установке |
| Swaylend | `withdraw_collateral` | storage update до oracle/collateral check полагается на atomic revert | State ordering | Фаззить oracle failure и underflow amount |
| Swaylend | `withdraw_base` | market/user state меняется до oracle/collateral check | State ordering | Проверить revert safety и logs/state rollback |
| Swaylend | `buy_collateral` | `storage(read)` + transfer + stale oracle assumption | Reserve lifecycle | Цена должна быть обновлена отдельным шагом |
| Swaylend | `absorb` | duplicate accounts/stale price в batch liquidation | Liquidation race | Проверить повтор одного account и order effects |
| Swaylend | `get_price_internal` | first-valid oracle wins, возможно stale-first source | Oracle ordering | Тест disabled flags, confidence bounds, ordering |
| Swaylend | `update_base_principal` | reward snapshots при переходе principal через 0 | Reward accounting | Supplier -> borrower и borrower -> supplier |
| Fluid BorrowOperations | `open_trove` | много external state writes до финального mint/move | Cross-contract state | Проверять revert atomicity across TroveManager/SortedTroves/ActivePool |
| Fluid BorrowOperations | `internal_adjust_trove` | lock + external calls + sorted reinsert | Reentrancy / list race | Тестировать malicious mocks и stale hints |
| Fluid BorrowOperations | `close_trove` | close/repay/send collateral/refund excess ordering | Resource lifecycle | Overpay/exact pay/bad asset id |
| Fluid ProtocolManager | `redeem_collateral` | partial redemption hints и traversal могут cancel/under-redeem | Ordered-list race | max_iterations, stale hints, changing CR |
| Fluid ProtocolManager | `register_asset` | fan-out init across many contracts can produce inconsistent config if migration assumptions fail | Governance init | Fuel atomicity helps; deployment scripts still need verification |
| Fluid StabilityPool | `provide_to_stability_pool` | payout prior gains before snapshot update around issuance/liquidation | Reward snapshot race | Deposit right before/after offset |
| Fluid StabilityPool | `withdraw_from_stability_pool` | liveness grief if undercollateralized troves block withdrawals | Liveness coupling | Depends on oracle/list freshness |
| Fluid StabilityPool | `update_reward_sum_and_product` | epoch/scale precision and zero-product boundary | Precision / reward math | Test tiny deposits and large offsets |
| Fluid SortedTroves | `insert/re_insert/remove` | linked-list corruption or traversal DoS with stale hints | Ordered data structure | Head/tail, duplicates, long list |
| Fluid USDF Token | `mint/burn` | minter authorization or asset/subId mismatch desyncs supply | Mint authority | Test only trove managers and exact asset id |
| V12 Orderbook | matcher execution | stale indexer/cancel-fill race | Async off-chain race | Need source/contract id in next pass |
| Proxy/Governance | target/owner update | storage layout break or malicious target redirect | Upgrade governance | Check proxy owner, code hash, delay |

## 5. Наиболее вероятные race conditions

1. Bridge double-finalization/replay.
   Основной риск там, где одна сторона уже изменила supply/escrow, а другая сторона финализирует позже. Проверять повтор message proof, повтор msg_idx, неправильный `messageSender`, mismatch decimals/token id.

2. Bridge deposit-to-contract failure.
   L2 `_process_deposit` mint-ит перед вызовом receiver. Если receiver revert/consume funds не так, возможны stuck funds или refund inconsistency. Это самый явный deferred-execution target.

3. AMM optimistic swap callback.
   Mira отправляет output до проверки входа/invariant. Такой паттерн допустим для flash swaps, но все accounting edge cases должны быть закрыты: reentrancy, wrong asset repayment, same-recipient balance accounting, protocol fee transfer.

4. Oracle freshness race.
   Swaylend и Fluid используют цены во многих critical paths. Любая возможность подать stale-but-valid price, изменить oracle order или не обновить price перед `buy_collateral` может стать liquidation/withdraw bug.

5. Sorted list stale hints.
   Fluid sorted troves и redemption path зависят от hints и traversal. Это fertile ground для cancel griefing, long traversal DoS, wrong borrower selection на границе MCR.

6. Reward snapshot boundary.
   Swaylend reward accrual и Fluid StabilityPool snapshots/epoch/scale чувствительны к моменту deposit/withdraw/liquidation/issuance. Самые ценные сценарии - deposit right before liquidation and withdraw right after.

## 6. Resource lifecycle и ownership

Fuel-specific ресурсы:

- UTXO/message input должен быть потреблен ровно один раз.
- Native asset mint/burn должен держать total supply в синхроне с minted/burned balances.
- `msg_asset_id()` и `msg_amount()` критичны: неправильный payable asset приводит к чужим ресурсам в контракте.
- Direct donations в native assets возможны и влияют на accounting, если контракт считает input через `this_balance - reserve`.
- Contract ownership/proxy ownership не меняет байткод, но может менять target/hook/admin configs.

Где смотреть:

- Bridge: `tokens_minted`, `refund_amounts`, `_deposits`, decimal conversion, message data encoding.
- Mira: `total_reserves`, `pools.reserve_0/1`, LP total supply, protocol fee recipient, hook.
- Swaylend: `totals_collateral`, `user_collateral`, `market_basic`, `user_basic`, oracle configs.
- Fluid: trove status/coll/debt/stake, sorted list nodes/head/tail/size, StabilityPool `P`, epoch/scale/sums, USDF supply.

## 7. Сценарии для следующих этапов

Bridge:

1. Повторить один и тот же L1->L2 message input дважды; убедиться, что второй replay невозможен.
2. DepositWithData в malicious receiver, который reenter-ит `process_message`.
3. DepositWithData в receiver, который всегда reverts; проверить, где оказываются minted assets/refund state.
4. Несколько overflow deposits одного `from/token/token_id`, затем `claim_refund` в разном порядке.
5. Fee-on-transfer ERC20 deposit: сравнить `_deposits`, фактический escrow balance и L2 minted amount.
6. L2 withdraw -> L1 finalize twice; finalize with modified tokenAddress/to/amount proof.
7. Rate limit: finalize на boundary `currentPeriodEnd`, reduce/increase limit in same period.

Mira:

1. Donation before first mint; first LP получает ли завышенную/заниженную долю.
2. Donation between swaps; проверить `get_amount_in_accounting_out`.
3. Flash swap callback repays wrong asset, too little, too much, and via third contract.
4. `to == fee_recipient`, `to == hook`, `to == pool contract` edge cases.
5. Repeated minimal burns/mints and stable pool decimals mismatch.
6. Hook reverts/high gas/reenters via allowed paths.

Swaylend:

1. `withdraw_collateral` with stale oracle, failing oracle update, amount > collateral.
2. `withdraw_base` where principal crosses from supply to borrow and back in one block.
3. `absorb([same_account, same_account])` duplicate liquidation list.
4. `buy_collateral` without prior oracle update vs with multicall update.
5. Multi-oracle config where first oracle stale but within confidence and second fresh.
6. Accrual around `base_min_for_rewards`, zero total supply/borrow, timestamp unchanged.

Fluid:

1. `open_trove` where SortedTroves insert succeeds but later ActivePool/USDF call fails in mock environment.
2. `internal_adjust_trove` with stale hints and rapidly changing NICR.
3. Close trove with exact USDF, excess USDF, wrong asset, and active pool transfer failure.
4. Redemption with `max_iterations=1`, invalid partial hint, and list changes between hint generation and execution.
5. StabilityPool deposit just before liquidation, withdraw just after; verify asset/FPT gains.
6. Extreme liquidation offset that changes epoch/scale; verify `P` never zeroes incorrectly.
7. SortedTroves long-list traversal gas and head/tail remove/reinsert invariants.

V12:

1. Place order, matcher observes it, user cancels, matcher tries fill with stale indexer state.
2. Two matchers submit same match.
3. Partial fill then cancel in adjacent blocks.
4. Fee calculation under gas price changes.
5. Indexer outage/reorg-like stale data handling.

## 8. Приоритеты

High priority:

- Fuel bridge deposit-to-contract and withdrawal finalization.
- Mira `swap` callback and LP accounting.
- Swaylend liquidation/oracle paths.
- Fluid redemption + sorted list + stability snapshots.

Medium priority:

- Governance/proxy/hook ownership.
- Reward accrual precision.
- Rate-limit boundary behavior.

Needs more data:

- V12 contract id/source.
- Labels for unlabeled hot contracts from `data/contract_activity_sample.csv`.
- On-chain ownership/proxy targets for deployed Fluid/Swaylend components.
