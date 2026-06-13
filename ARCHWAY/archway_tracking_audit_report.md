# Archway Network — Глубокий аудит x/tracking
## Gas Accounting Audit Report

**Дата:** 2026-06-03  
**Фокус:** x/tracking, gas rewards attribution, accounting integrity  
**Методология:** Статический анализ кода, трассировка всех write paths, анализ test coverage  

---

## Содержание

1. [Сводная таблица](#сводная-таблица)
2. [T-01: Массовое отключение unit-тестов для критической логики](#t-01-массовое-отключение-unit-тестов-для-критической-логики-high)
3. [T-02: mintbankkeeper паникует при пустых монетах](#t-02-mintbankkeeper-паникует-при-пустых-монетах-low)
4. [T-03: Query gas включается в rewards без фильтрации](#t-03-query-gas-включается-в-rewards-без-фильтрации-low)
5. [Карта gas tracking flow](#карта-gas-tracking-flow)
6. [Ответы на вопросы аудита](#ответы-на-вопросы-аудита)
7. [Слабые зацепки](#слабые-зацепки)
8. [Топ-5 подозрительных мест](#топ-5-подозрительных-мест)
9. [Тесты для написания](#тесты-для-написания)

---

## Сводная таблица

| ID | Название | Severity | Confidence | Статус |
|----|---------|----------|-----------|--------|
| T-01 | Unit-тесты distribution/fee/mint закомментированы | **High** | **High** | Confirmed |
| T-02 | mintbankkeeper panic на пустых монетах | Low | Medium | Lead |
| T-03 | Query gas в rewards attribution | Low | Medium | Lead |

---

## T-01: Массовое отключение unit-тестов для критической логики (High)

**Severity: High**  
**Confidence: High**  
**Статус: Confirmed**

### Затронутые файлы

- `x/rewards/keeper/distribution_test.go` — **весь файл закомментирован**
- `x/rewards/ante/fee_deduction_test.go` — **весь файл закомментирован**
- `x/rewards/mintbankkeeper/keeper_test.go` — **весь файл закомментирован**
- `x/rewards/ante/min_cons_fee_test.go` — **весь файл закомментирован**

### Summary

Четыре тестовых файла, покрывающих ключевую логику системы вознаграждений, полностью закомментированы. Это означает, что **ни одна из следующих критических функций** не имеет автоматической unit-тестовой проверки:

- `AllocateBlockRewards` (распределение rewards за блок)
- `estimateBlockGasUsage` (оценка gas usage)
- `estimateBlockRewards` (расчёт долей rewards)
- `deductFees` / `DeductFeeDecorator` (разделение fees)
- `SendCoinsFromModuleToModule` в mintbankkeeper (inflation split)
- `MinFeeDecorator` (проверка минимальной комиссии)

### Масштаб проблемы

Закомментированный тест `TestRewardsKeeper_Distribution` содержал **14 тест-кейсов**, покрывавших:

```go
// Примеры закомментированных сценариев:
"1 tx, 2 contracts (one without metadata)"          // контракт без metadata
"1 tx, 1 contract (no tx fees)"                     // нет fee → только inflation
"1 tx, 1 contract (no inflation)"                   // нет inflation → только fee rebate
"1 tx, 1 contract (no block gas limit)"             // MaxGas=0 → только fee, не inflation
"2 txs with contract ops intersection"              // один контракт в нескольких tx
"1 tx, 2 contracts with same rewardsAddress"        // two contracts → same rewards address
"1 tx with 1 contract receiving to wallet"          // WithdrawToWallet mode
```

Закомментированный `TestRewardsFeeDeductionAnteHandler` покрывал:

```go
"1000stake fees with 0.5 ratio"
"1000stake,500uarch fees with 0.1 ratio"
"fees with 0.5 ratio (no WASM msgs, rewards are skipped)"
// ...
```

### Почему это High severity

1. **Без тестов регрессии не обнаруживаются**: Любое изменение в `distribution.go` или `fee_deduction.go` может нарушить корректность расчётов незаметно для CI/CD.

2. **Нет проверки математических инвариантов**: Конкретно нет теста, что `Σ(distributed) + treasury == RewardsTotal` после каждого блока.

3. **Нет coverage edge cases**: Деление на ноль, zero rewards, multi-denom, очень маленькие/большие значения — всё без тестов.

4. **Существующие баги могут уже присутствовать**: F-02 (TxRewards InitGenesis wrong key) мог бы быть обнаружен тестами если бы они работали.

### PoC — демонстрация отсутствия coverage

```bash
# Запустить тесты только x/rewards
cd x/rewards && go test ./...

# distribution_test.go: 0 тестов (всё закомментировано)
# fee_deduction_test.go: 0 тестов
# mintbankkeeper/keeper_test.go: 0 тестов
# min_cons_fee_test.go: 0 тестов

# Единственные работающие тесты:
# - withdraw_test.go: TestWithdrawRewardsByLimit, TestWithdrawRewardsByIDs
# - metadata_test.go
# - flat_fee_test.go
# - params_test.go
```

### Counterarguments

- Возможно, есть e2e тесты в `contracts/go/voter/integration/` которые покрывают эти пути
- Закомментированные тесты могут быть в процессе переписывания на новый framework
- CI может включать integration/e2e тесты которые мы не видим в unit test файлах

### Suggested fix

1. **Немедленно:** Раскомментировать тесты или заменить их рабочими аналогами
2. **Добавить проверку в CI:** `go test ./x/rewards/... --count=1` должен выполнять > N тестов
3. **Минимальный набор:**

```go
// distribution_test.go — минимальный рабочий набор:
func TestAllocateBlockRewards_NoOp(t *testing.T) { ... }
func TestAllocateBlockRewards_SingleContractSingleTx(t *testing.T) { ... }
func TestAllocateBlockRewards_MultiContractSingleTx_FeeRebateSplit(t *testing.T) { ... }
func TestAllocateBlockRewards_ZeroInflation_OnlyFeeRebate(t *testing.T) { ... }
func TestAllocateBlockRewards_NoFees_OnlyInflation(t *testing.T) { ... }
func TestAllocateBlockRewards_RoundingDustGoesToTreasury(t *testing.T) { ... }
func TestAllocateBlockRewards_WithdrawToWallet_DirectTransfer(t *testing.T) { ... }
func TestAllocateBlockRewards_ContractWithoutMetadata_Skipped(t *testing.T) { ... }
func TestAllocateBlockRewards_ContractWithoutRewardsAddr_Skipped(t *testing.T) { ... }
```

---

## T-02: mintbankkeeper паникует при пустых монетах (Low)

**Severity: Low**  
**Confidence: Medium**  
**Статус: Lead**

### Затронутые файлы

- `x/rewards/mintbankkeeper/keeper.go` — `SendCoinsFromModuleToModule`

### Summary

В `mintbankkeeper` после разделения монет есть проверка:

```go
// Check that only one coin has been minted
if len(dappRewards) != 1 {
    panic(fmt.Errorf("unexpected dApp rewards: %s", dappRewards))
}
```

Если `dappRewards` пустой (0 монет) или содержит несколько деноминаций — паника → chain halt в EndBlocker x/mint.

### Technical details

```go
func (k Keeper) SendCoinsFromModuleToModule(goCtx context.Context, senderModule, recipientModule string, amt sdk.Coins) error {
    ctx := sdk.UnwrapSDKContext(goCtx)
    ratio := k.rewardsKeeper.InflationRewardsRatio(ctx)
    
    // Ранний return если ratio == 0 или recipient != FeeCollector
    if recipientModule != authTypes.FeeCollectorName || ratio.IsZero() {
        return k.bankKeeper.SendCoinsFromModuleToModule(...)
    }

    // SplitCoins на основе amt
    dappRewards, stakingRewards := pkg.SplitCoins(amt, ratio)

    // ...bank sends...

    // ПАНИКА если not exactly 1 coin:
    if len(dappRewards) != 1 {
        panic(fmt.Errorf("unexpected dApp rewards: %s", dappRewards))
    }
    
    k.rewardsKeeper.TrackInflationRewards(ctx, dappRewards[0])
    // ...
}
```

**Когда `len(dappRewards) != 1`?**

1. **`amt` пустой** (0 монет): `SplitCoins([], ratio)` → `dappRewards = []` → len = 0 → panic
2. **`amt` содержит 2+ деноминации**: `SplitCoins([1stake, 1uarch], ratio)` → `dappRewards = [xstake, yuarch]` → len = 2 → panic

**Когда возможен сценарий 1?**

В стандартном Cosmos SDK x/mint, если `MintedPerBlock.IsZero()`, модуль пропускает bank send:
```go
// cosmos-sdk/x/mint/keeper/keeper.go
if mintedCoins.IsZero() {
    return nil
}
```

Но версия Cosmos SDK может отличаться. Если x/mint отправляет пустые coins, паника возможна.

**Когда возможен сценарий 2?**

Если кастомный mint модуль или upgrade меняет логику mint, и монеты отправляются в двух деноминациях. В Archway пока только один staking token, так что это теоретически.

### Impact

- Panic в x/mint EndBlocker → chain halt
- Требует: либо zero-amount mint, либо multi-denom mint

### Counterarguments

- Стандартный x/mint в Cosmos SDK всегда минтит ровно один ненулевой coin
- Archway не меняет x/mint модуль
- Паника теоретически недостижима при текущей конфигурации

### Suggested fix

```go
// Вместо panic — explicit handling:
if len(dappRewards) == 0 {
    // Zero inflation — ничего не трекаем, это нормально
    return nil
}
if len(dappRewards) != 1 {
    k.logger.Error("unexpected dApp rewards coin count", "coins", dappRewards)
    // или вернуть ошибку, не паниковать
    return fmt.Errorf("unexpected dApp rewards: %s", dappRewards)
}
k.rewardsKeeper.TrackInflationRewards(ctx, dappRewards[0])
```

---

## T-03: Query gas включается в rewards attribution (Low)

*(Детальное описание — в основном отчёте `archway_full_audit_report.md`)*

---

## Карта Gas Tracking Flow

### Полная карта всех write paths

```
╔══════════════════════════════════════════════════════════════════════╗
║  TRACKING STATE WRITES                                               ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  [1] AnteHandler: TxGasTrackingDecorator                            ║
║      TxInfoState.CreateEmptyTxInfo()                                 ║
║      → KVStore: TxInfoPrefix/{id} = TxInfo{id=N, height=H}          ║
║      → KVStore: TxInfoBlockIndexPrefix/{H}/{N} = []                 ║
║      → KVStore: TxInfoIDKey = N  (monotonic counter)                ║
║      SCOPE: AnteHandler (persists even if msgs fail)                 ║
║                                                                      ║
║  [2] Wasm Execution: IngestGasRecord()                              ║
║      ContractOpInfoState.CreateContractOpInfo(txID=N, ...)          ║
║      → KVStore: ContractOpInfoPrefix/{id} = ContractOpInfo{...}     ║
║      → KVStore: ContractOpInfoTxIndexPrefix/{N}/{opID} = []         ║
║      → KVStore: ContractOpInfoIDKey = opID  (monotonic counter)     ║
║      SCOPE: Message execution context (ROLLBACK on msg failure)     ║
║                                                                      ║
║  [3] EndBlocker x/tracking: FinalizeBlockTxTracking()               ║
║      TxInfoState.SetTxInfo(txInfo)                                  ║
║      → UPDATES: TxInfo.TotalGas = Σ(ContractOpInfo.VmGas+SdkGas)  ║
║      SCOPE: EndBlocker (always commits)                              ║
║                                                                      ║
║  [4] EndBlocker x/rewards: cleanupTracking(height-10)               ║
║      DeleteTxInfosCascade(height-10)                                 ║
║      → DELETES: all TxInfo for height-10                            ║
║      → DELETES: all ContractOpInfo for those txIDs                  ║
║                                                                      ║
║  [5] ORPHANED: EndBlocker x/callback (AFTER x/rewards)             ║
║      IngestGasRecord() → ContractOpInfo(txID=lastN) persisted       ║
║      → Не влияет на rewards (уже рассчитаны)                        ║
║      → Удаляется при cleanup lastN's block (height+10)              ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════╗
║  TRACKING STATE READS (для rewards)                                  ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  x/rewards: AllocateBlockRewards(height=H)                          ║
║    GetBlockTrackingInfo(H):                                          ║
║      ├─ GetTxInfosByBlock(H)                                         ║
║      │   → reads TxInfoBlockIndexPrefix/{H}/* → TxInfo[]           ║
║      └─ GetContractOpInfoByTxID(txID)                               ║
║          → reads ContractOpInfoTxIndexPrefix/{txID}/* → OpInfo[]   ║
║                                                                      ║
║  Timing: вызывается ПОСЛЕ FinalizeBlockTxTracking()                 ║
║          и ПЕРЕД callback execution                                  ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════╗
║  GAS UNIT CONVERSION                                                 ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  wasmd record.OriginalGas:                                           ║
║    VMGas  → WasmGasRegister.FromWasmVMGas(VMGas) → SDK gas units   ║
║    SDKGas → as-is                                                    ║
║                                                                      ║
║  Stored: ContractOpInfo.VmGas = FromWasmVMGas(VMGas)                ║
║           ContractOpInfo.SdkGas = SDKGas                             ║
║                                                                      ║
║  Used: GasUsed() = VmGas + SdkGas                                   ║
║                                                                      ║
║  Key insight: Tracked = ACTUAL consumed gas, NOT gas limit          ║
║               Users cannot inflate rewards via high gas limit        ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
```

### Mint → Rewards flow

```
x/mint EndBlocker
  └─ MintCoins(mint_module, coin)
  └─ SendCoinsFromModuleToModule(mint → FeeCollector, coin)
     [INTERCEPTED by mintbankkeeper]:
       dappRewards = coin * InflationRewardsRatio
       stakingRewards = coin - dappRewards
       ├─ SendCoins(mint → FeeCollector, stakingRewards)
       ├─ SendCoins(mint → ContractRewardCollector, dappRewards)
       ├─ TrackInflationRewards(dappRewards[0])  → BlockRewards{height, coin, maxGas}
       └─ UpdateMinConsensusFee(dappRewards[0])  → MinConsFee item
```

---

## Ответы на вопросы аудита

### 1. Что именно считается?

**Gas limit или actual gas?**

```go
// gas_processor.go — IngestGasRecord
k.TrackNewContractOperation(
    ctx,
    contractAddr,
    opType,
    k.WasmGasRegister.FromWasmVMGas(record.OriginalGas.VMGas), // actual VM gas
    record.OriginalGas.SDKGas,                                   // actual SDK gas
)
```

**Ответ: actual gas used. Gas limit НЕ используется.** Нет способа получить больше rewards через высокий gas limit.

**Failed transactions:**

Timeline при failed tx:
1. AnteHandler: `TrackNewTx()` → TxInfo создан → **persist**
2. AnteHandler: `TrackFeeRebatesRewards(rewardsFees)` → TxRewards создан → **persist**
3. Msg execution FAILS → cache rollback
4. ContractOpInfo — **не создаётся** (создаётся только в msg context, откатившемся)
5. EndBlocker: TxInfo.TotalGas = 0 (нет ContractOpInfo для этой tx)
6. Rewards: fee rebate для этой tx = TxRewards exists, но ни один контракт не имеет TxGasUsed → fee rebate уходит в treasury

**Ответ: Failed tx НЕ дают rewards контрактам. Деньги в treasury.**

**Reverted wasm executions (submessage с ReplyOn::Error):**

При submessage failure с `ReplyOn::Error`:
- Родительская tx продолжает выполнение (не fail!)
- Wasmd вызывает `IngestGasRecord` для failed submessage ПЕРЕД откатом submessage state
- ContractOpInfo для failed submessage **записывается**
- Если родительская tx успешна → ContractOpInfo **persist**

**Ответ: Gas от failed submessage (при ReplyOn::Error) ЗАСЧИТЫВАЕТСЯ. Контракт получает rewards за газ, потраченный на failed submessage.**

Это технически корректно (газ реально был потреблён), но создаёт потенциальный вектор:

```rust
// Атакующий контракт: намеренно вызывает expensive failed submessage
pub fn execute(deps: DepsMut, env: Env, info: MessageInfo, msg: ExecuteMsg) -> StdResult<Response> {
    Ok(Response::new()
        .add_submessage(SubMsg::reply_on_error(
            WasmMsg::Execute {
                contract_addr: expensive_contract,
                msg: to_json_binary(&heavy_computation_msg)?,
                funds: vec![],
            },
            REPLY_ID,
        )))
}
```

**Ограничение:** Пользователь сам оплачивает весь газ. Rewards = часть от уплаченных fees. Экономически: `rewards ≤ TxFeeRebateRatio * fees`. Нельзя получить больше, чем заплатил.

**Nested contract calls:**

Каждый call (execute/query/instantiate/reply/sudo) создаёт отдельный `ContractOpInfo` с адресом **соответствующего контракта**. Nesting не влияет на attribution — каждый контракт получает ровно свой gas.

```
Tx вызывает A → A вызывает B → B вызывает C
ContractOpInfo[1] = {contract: A, gas: gasA}
ContractOpInfo[2] = {contract: B, gas: gasB}
ContractOpInfo[3] = {contract: C, gas: gasC}

Награда A = gasA / totalTxGas * fees
Награда B = gasB / totalTxGas * fees
Награда C = gasC / totalTxGas * fees
```

**Ответ: Attribution корректна при nested calls.**

**Callback failure:**

Callbacks выполняются в EndBlocker x/callback. Их gas записывается в ContractOpInfo с lastTxID (orphaned data). Rewards уже были рассчитаны в EndBlocker x/rewards. **Callback gas не влияет на rewards.**

**Reply failure:**

`ContractOperationReply` → `CONTRACT_OPERATION_REPLY` → tracked. Если reply fails с паникой/ошибкой, wasmd откатывает state, но gas был потреблён. `IngestGasRecord` вызывается до откатки → ContractOpInfo записан → если parent tx succeeds, replay gas засчитывается.

### 2. Attribution

**Как определяется contract address?**

```go
// gas_processor.go
contractAddr, err := sdk.AccAddressFromBech32(record.ContractAddress)
// record.ContractAddress приходит от wasmd — это РЕАЛЬНЫЙ адрес контракта, вызвавшего gas
```

Wasmd устанавливает `ContractAddress` как адрес контракта, в котором выполняется операция. Нет spoofing.

**Можно ли приписать gas чужому контракту?**

Нет. ContractAddress в GasRecord устанавливается wasmd VM, не пользователем.

**Можно ли искусственно увеличить tracked gas дешёвой tx?**

Нельзя через gas limit. Но можно через реальное потребление (expensive operations). Это by design — если контракт тратит много gas, он получает proportional rewards.

**Можно ли обойти tracking через нестандартный execution path?**

Все пути через wasmd используют `ContractGasProcessor.IngestGasRecord`. Нет публичного пути минуя этот интерфейс для реального wasm execution.

### 3. Accounting integrity

**Нет ли double counting?**

Каждый ContractOpInfo имеет уникальный monotonic ID. `GetContractOpInfoByTxID` итерирует по tx index — каждый opID встречается один раз. **Нет double counting.**

**Нет ли missed counting?**

Если `IngestGasRecord` вернёт ошибку (invalid contract address) — операция не записывается. Но при этом gas всё равно был потреблён. Контракт с невалидным адресом не получит rewards, но его gas уходит в общий txGas total, уменьшая долю других контрактов.

**Нет ли counting после rollback?**

ContractOpInfo создаётся в msg execution context. При rollback (msg failure) — ContractOpInfo откатывается. **Нет counting после rollback.**

**Counting до определения успешности tx?**

TxInfo создаётся в AnteHandler → persist. ContractOpInfo в msg context → rollback при failure. TxRewards в AnteHandler → persist. **Корректно:** если tx fails, нет ContractOpInfo → нет distribution rewards.

**Out-of-gas:**

При out-of-gas panic:
- Cosmos SDK ловит panic в runMsgs
- Msg execution откатывается (CacheContext discard)
- ContractOpInfo откатывается
- TxInfo persist (создан в ante)
- TxRewards persist (если ante прошёл)
- В EndBlocker: TxInfo с TotalGas=0, TxRewards exist → fee rebate в treasury
- **Нет rewards при out-of-gas. Корректно.**

### 4. Economic abuse

**Rewards > стоимость tx?**

`fee_rebate = TxFeeRebateRatio * fees`. Rewards для контракта = `fee_rebate * (contractGas / totalGas) + inflationShare`. Максимально возможные rewards ограничены уплаченными fees + инфляцией блока. **Нельзя получить больше, чем заплачено + inflation share.**

**Failed submessage farming:**

```
Сценарий: Deploy contract A с дорогими failed submessages
1. User calls A с 1000 gas fee
2. A dispatches N expensive failed submessages
3. Каждый submessage тратит X gas → ContractOpInfo записан
4. A (и submessage targets) получают rewards

Ограничение:
- User сам платит за N*X gas
- rewards(A + targets) ≤ TxFeeRebateRatio * user_paid_fees
- Экономически нейтрально: rewards ≤ cost
```

**Высокий gas limit:**

Нет эффекта. Tracked = actual gas used.

**Failed tx farming:**

Невозможно. ContractOpInfo rollback при msg failure.

### 5. Invariants — проверка

| Инвариант | Статус |
|----------|--------|
| Failed tx не дают rewards | ✓ Верно (ContractOpInfo rollback) |
| Один gas не засчитывается дважды | ✓ Верно (unique IDs) |
| Contract attribution однозначна | ✓ Верно (address из wasmd) |
| Rewards не зависят от gas limit | ✓ Верно (actual gas tracked) |
| Tracking согласован с wasm execution | ✓ Верно (IngestGasRecord атомарен с execution) |

**Незакрытый invariant: Query gas в rewards**

```
REQUIRED: только execute/instantiate/migrate/reply/sudo gas → rewards
ACTUAL:   включая CONTRACT_OPERATION_QUERY

Нет теста, проверяющего что query-тяжёлые контракты не получают неожиданно высокую долю
```

---

## Слабые зацепки

### Проверено — не баги

| Зацепка | Заключение |
|---------|-----------|
| Gas limit вместо actual gas | Tracked = actual. Gas limit не влияет. |
| Double counting | Unique IDs + indexed map. Нет. |
| Failed tx rewards | ContractOpInfo rollback. Нет rewards. |
| Out-of-gas rewards | Same — rollback. Нет rewards. |
| Callback gas атрибуция | Orphaned data, не влияет на rewards. |
| nested calls misattribution | Каждый call → свой ContractOpInfo с правильным addr. |
| IBC relay gas | Attributed к контракту который обрабатывает пакет. Design intent. |
| TxInfoIDKey overflow | uint64 → ~1.8×10^19 txs. Недостижимо. |

### Требуют уточнения

| Зацепка | Что нужно |
|---------|-----------|
| Submessage failure gas rewarded | Intentional? Exploitation possible? |
| Query gas в rewards | Design документация отсутствует |
| Callback gas orphaned cleanup | Проверить что cleanup происходит корректно в edge cases |
| TxInfo в genesis с Height=0 | `sdk.BigEndianToUint64(nil) = 0` — что если height = 0? |

---

## Топ-5 подозрительных мест

| # | Место | Риск | Основание |
|---|-------|------|-----------|
| 1 | `x/rewards/keeper/distribution_test.go` | **Critical** | Весь файл закомментирован — нет coverage критической логики |
| 2 | `x/rewards/mintbankkeeper/keeper.go:88` | Low | `panic` при `len(dappRewards) != 1` — fragile assumption |
| 3 | `x/tracking/keeper/gas_processor.go:IngestGasRecord` | Low | Query gas included — design intent неясен |
| 4 | `x/rewards/keeper/distribution.go:estimateBlockRewards` | Medium | Нет тестов для multi-denom, zero cases, rounding |
| 5 | `x/rewards/ante/fee_deduction_test.go` | High | Весь файл закомментирован — fee split logic не тестирован |

---

## Тесты для написания

### Приоритет 1 — немедленно (раскомментировать/переписать)

```go
// x/rewards/keeper/distribution_test.go
func TestAllocateBlockRewards_NoOp(t *testing.T) { ... }
func TestAllocateBlockRewards_SingleContract_SingleTx(t *testing.T) { ... }
func TestAllocateBlockRewards_TwoContracts_SingleTx_ProportionalSplit(t *testing.T) { ... }
func TestAllocateBlockRewards_ContractInMultipleTxs_AccumulatesRewards(t *testing.T) { ... }
func TestAllocateBlockRewards_NoMetadata_Skipped(t *testing.T) { ... }
func TestAllocateBlockRewards_NoRewardsAddress_Skipped(t *testing.T) { ... }
func TestAllocateBlockRewards_WithdrawToWallet_DirectTransfer(t *testing.T) { ... }
func TestAllocateBlockRewards_RoundingDust_GoesToTreasury(t *testing.T) { ... }
func TestAllocateBlockRewards_ZeroInflation_OnlyFeeRebate(t *testing.T) { ... }
func TestAllocateBlockRewards_ZeroFeeRebate_OnlyInflation(t *testing.T) { ... }
func TestAllocateBlockRewards_ZeroMaxGas_InflationSkipped(t *testing.T) { ... }
func TestAllocateBlockRewards_FailedTx_NoContractRewards(t *testing.T) { ... }

// x/rewards/ante/fee_deduction_test.go
func TestDeductFeeDecorator_WasmTx_SplitToRewards(t *testing.T) { ... }
func TestDeductFeeDecorator_NonWasmTx_AllToFeeCollector(t *testing.T) { ... }
func TestDeductFeeDecorator_ZeroFeeRebateRatio_AllToFeeCollector(t *testing.T) { ... }
func TestDeductFeeDecorator_FlatFee_DeductedFirst(t *testing.T) { ... }
func TestDeductFeeDecorator_CwFeesGranter_ContractPays(t *testing.T) { ... }

// x/rewards/mintbankkeeper/keeper_test.go
func TestMintBankKeeper_SplitsInflation(t *testing.T) { ... }
func TestMintBankKeeper_ZeroRatio_AllToFeeCollector(t *testing.T) { ... }
func TestMintBankKeeper_NonFeeCollectorRecipient_NotSplit(t *testing.T) { ... }
```

### Приоритет 2 — новые тесты для выявленных gap

```go
// Gas tracking специфические
func TestTrackingGasRecords_QueryOpIncluded(t *testing.T) {
    // Верифицировать что QUERY ops попадают в ContractOpInfo
    // и влияют на rewards
}

func TestTrackingGasRecords_FailedSubmessage_ParentSucceeds_GasTracked(t *testing.T) {
    // Контракт с failed submessage (ReplyOn::Error)
    // Verify: gas от failed submessage засчитывается
}

func TestTrackingGasRecords_CallbackGasOrphaned(t *testing.T) {
    // Callback создаёт ContractOpInfo в EndBlocker
    // Verify: не влияет на rewards текущего блока
    // Verify: корректно удаляется при pruning
}

func TestTrackingGasRecords_MultipleContractsOneTx_Proportional(t *testing.T) {
    // 3 контракта в одной tx, разные gas amounts
    // Verify: fee rebate делится пропорционально
    // Verify: totalGas = Σ(contractGas)
}

func TestTrackingInvariant_TotalGasConsistency(t *testing.T) {
    // После FinalizeBlockTxTracking:
    // TxInfo.TotalGas == Σ(ContractOpInfo.VmGas + SdkGas) для этой tx
}

// mintbankkeeper edge cases
func TestMintBankKeeper_EmptyAmt_NoPanic(t *testing.T) {
    // Если amt = [] → не должно паниковать
}
```

### Приоритет 3 — invariant tests

```go
func TestInvariant_RewardsTotal_Equals_Distributed_Plus_Treasury(t *testing.T) {
    // Для каждого блока:
    // blockRewards.InflationRewards + Σ(TxRewards.FeeRewards)
    //   == Σ(distributed to contracts) + treasury_leftover
}

func TestInvariant_ContractGasShare_LessOrEqual_One(t *testing.T) {
    // Для каждого контракта в tx:
    // contractTxGas / totalTxGas ≤ 1.0
}

func TestInvariant_ContractInflationShare_LessOrEqual_One(t *testing.T) {
    // contractBlockGas / MaxGas ≤ 1.0
}
```

---

## Confirmed Findings (этот аудит)

1. **T-01 (High):** distribution_test.go, fee_deduction_test.go, mintbankkeeper/keeper_test.go, min_cons_fee_test.go — полностью закомментированы. Критическая логика rewards без unit test coverage.

2. **T-02 (Low):** mintbankkeeper panic при `len(dappRewards) != 1` — fragile assertion в EndBlocker.

3. **T-03 (Low):** Query gas в rewards — design intent не задокументирован.

## Weak Leads (не тратить время)

- Gas limit влияет на rewards — НЕВЕРНО (actual gas tracked)
- Double counting — НЕВЕРНО (unique IDs)
- Failed tx rewards — НЕВЕРНО (ContractOpInfo rollback)
- Overflow uint64 IDs — НЕВЕРНО (недостижимо)
- IBC attribution — design intent (relay tx pays, relay tx's contract gets rewards)

---

*Отчёт составлен для целей легального bug bounty. Эксплуатация mainnet не проводилась.*
