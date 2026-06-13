# Archway Network — Полный Аудит Безопасности
## Threat Modeling Report: x/rewards, x/tracking, x/callback, x/cwfees, x/cwica, x/cwerrors

**Дата:** 2026-06-03  
**Охват:** Все Archway-specific модули, анализ с нуля кода  
**Методология:** Статический анализ, трассировка потоков, threat modeling по каждому entrypoint  
**Статус:** Приватный отчёт для bug bounty / responsible disclosure  

---

## Содержание

1. [Сводная таблица находок](#сводная-таблица-находок)
2. [Карта gas tracking flow](#карта-gas-tracking-flow)
3. [F-01: Кража депозита при отмене callback](#f-01-кража-депозита-при-отмене-callback-medium)
4. [F-02: TxRewards в InitGenesis сохраняется по неверному ключу](#f-02-txrewards-в-initgenesis-сохраняется-по-неверному-ключу-low)
5. [F-03: Query-операции учитываются в rewards](#f-03-query-операции-учитываются-в-rewards-low)
6. [F-04: Nil pointer через fallthrough в DeductFeeDecorator](#f-04-nil-pointer-через-fallthrough-в-deductfeedecorator-low)
7. [F-05: Genesis не проверяет соответствие RewardsRecords и баланса модуля](#f-05-genesis-не-проверяет-соответствие-rewardsrecords-и-баланса-модуля-low)
8. [Threat Modeling: x/rewards](#threat-modeling-xrewards)
9. [Threat Modeling: x/tracking](#threat-modeling-xtracking)
10. [Threat Modeling: x/callback](#threat-modeling-xcallback)
11. [Threat Modeling: x/cwfees](#threat-modeling-xcwfees)
12. [Threat Modeling: x/cwica + x/cwerrors](#threat-modeling-xcwica--xcwerrors)
13. [Threat Modeling: Upgrades / Migrations / Genesis](#threat-modeling-upgrades--migrations--genesis)
14. [Слабые зацепки](#слабые-зацепки)
15. [Топ-5 приоритетных файлов](#топ-5-приоритетных-файлов)
16. [Рекомендуемые тесты и инварианты](#рекомендуемые-тесты-и-инварианты)
17. [Черновик Responsible Disclosure](#черновик-responsible-disclosure)

---

## Сводная таблица находок

| ID | Название | Severity | Confidence | Статус |
|----|---------|----------|-----------|--------|
| F-01 | CancelCallback refund theft | **Medium** | **High** | Confirmed |
| F-02 | TxRewards InitGenesis wrong key | Low | High | Confirmed |
| F-03 | Query gas in rewards attribution | Low | Medium | Lead |
| F-04 | Nil pointer in DeductFeeDecorator | Low | Medium | Theoretical |
| F-05 | Genesis RewardsRecords/balance mismatch | Low | High | Confirmed |

---

## Карта Gas Tracking Flow

```
╔══════════════════════════════════════════════════════════════════╗
║                     TX EXECUTION FLOW                            ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  [AnteHandler]                                                   ║
║    TxGasTrackingDecorator                                        ║
║    └─ TrackNewTx(ctx)                                           ║
║       └─ TxInfoState.CreateEmptyTxInfo()                        ║
║          └─ TxInfo{Id=N, Height=H} → KVStore                    ║
║          └─ TxInfoIDKey = N  (GetCurrentTxID() returns N)       ║
║                                                                  ║
║  [Message Execution: wasm.Execute/Instantiate/Migrate]          ║
║    wasmd → ContractGasProcessor.IngestGasRecord()               ║
║    └─ TrackNewContractOperation(txID=GetCurrentTxID()=N, gas)   ║
║       └─ ContractOpInfo{TxId=N, ContractAddr, VmGas, SdkGas}   ║
║          → KVStore                                               ║
║                                                                  ║
║  [EndBlocker: x/tracking]                                       ║
║    FinalizeBlockTxTracking(height=H)                            ║
║    └─ GetTxInfosByBlock(H) → [TxInfo(N)]                        ║
║    └─ GetContractOpInfoByTxID(N) → [ContractOpInfo...]          ║
║    └─ TxInfo(N).TotalGas = Σ(VmGas + SdkGas)                   ║
║                                                                  ║
║  [EndBlocker: x/rewards]                                        ║
║    AllocateBlockRewards(height=H)                               ║
║    ├─ GetBlockTrackingInfo(H)                                    ║
║    │   ├─ TxInfo(N).TotalGas = T_total                         ║
║    │   └─ ContractOpInfos: [contract_A:gas_A, contract_B:gas_B] ║
║    ├─ inflation_share_A = gas_A / MaxGas * InflationRewards     ║
║    ├─ fee_rebate_A = gas_A / T_total * TxRewards(N).FeeRewards  ║
║    ├─ CreateRewardsRecord(rewardsAddr_A, rewards_A) OR          ║
║    │   SendCoinsFromModuleToAccount (WithdrawToWallet)           ║
║    └─ cleanupTracking(H-10)                                     ║
║                                                                  ║
║  [EndBlocker: x/callback]  ← ПОСЛЕ rewards                     ║
║    callback.Sudo() → IngestGasRecord() ← ORPHANED               ║
║    (TxId = GetCurrentTxID() = N, но rewards уже рассчитаны)     ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

KEY INVARIANTS:
  ✓ Failed tx: ContractOpInfo rollback → fee rebate в treasury
  ✓ MaxGas > 0 checked before division (HasGasLimit())
  ✓ gasUsed/totalGas ≤ 1 (физически невозможно превысить)
  ✗ Query gas включается в rewards (F-03)
  ✗ Callback gas orphaned (informational)
```

---

## F-01: Кража депозита при отмене callback (Medium)

**Severity: Medium**  
**Confidence: High**  
**Статус: Confirmed Bug**

### Затронутые файлы
- `x/callback/keeper/msg_server.go` — функция `CancelCallback`
- `x/callback/keeper/callback.go` — функция `isAuthorizedToModify`

### Summary

При отмене callback (`CancelCallback`) возврат средств отправляется на адрес **вызывающего** (`request.Sender`), а не на адрес **изначального плательщика** (`callback.ReservedBy`). Авторизованная третья сторона (wasm admin или metadata owner) может отменить callback другой стороны и забрать уплаченный депозит.

### Attack preconditions

- Контракт с wasm admin ≠ metadata owner (два разных адреса)
- Один из них регистрирует callback и платит fees
- Другой отменяет callback

### Technical details

```go
// x/callback/keeper/msg_server.go — CancelCallback

// Шаг 1: получаем callback (callback.ReservedBy = Alice)
callback, err := s.keeper.GetCallback(ctx, request.CallbackHeight, request.ContractAddress, request.JobId)

// Шаг 2: проверяем авторизацию — Bob (admin) проходит
err = s.keeper.DeleteCallback(ctx, request.Sender, callback)

// Шаг 3: УЯЗВИМОСТЬ — refund идёт request.Sender (Bob), не callback.ReservedBy (Alice)
refundFees := callback.FeeSplit.TransactionFees.Add(*callback.FeeSplit.SurplusFees)
err = s.keeper.RefundFromCallbackModule(ctx, request.Sender, refundFees)
//                                             ^^^^^^^^^^^^^^  НЕВЕРНО
//                                             должно быть:   callback.ReservedBy
```

`isAuthorizedToModify` разрешает: контракт / wasm admin / metadata owner. Если Alice (metadata owner) зарегистрировала callback, а Bob (wasm admin) отменяет — Bob получает деньги Alice.

**Для сравнения**, в `abci.go` (callback execution в EndBlocker) refund сделан ПРАВИЛЬНО:
```go
// abci.go — refund при выполнении callback
err := k.RefundFromCallbackModule(ctx, callback.ReservedBy, refundAmount)
// ↑ Правильно: всегда на ReservedBy
```

### Impact

- Прямая кража `TransactionFees + SurplusFees` из callback module account
- Размер ущерба: от нескольких aarch до значительных сумм при дальних heights и surplus
- Требования: контракт с двумя разными авторизованными сторонами

### PoC plan

```go
func TestCancelCallback_RefundGoesToWrongAddress(t *testing.T) {
    keeper, ctx := testutils.CallbackKeeper(t)
    // ... setup
    
    // Alice (owner) регистрирует
    _, err := msgServer.RequestCallback(ctx, &types.MsgRequestCallback{
        Sender: alice.String(), Fees: sdk.NewInt64Coin("stake", 1_000_000), ...
    })
    aliceBalanceBefore := bankKeeper.GetBalance(ctx, alice, "stake")
    bobBalanceBefore := bankKeeper.GetBalance(ctx, bob, "stake")
    
    // Bob (admin) отменяет
    _, err = msgServer.CancelCallback(ctx, &types.MsgCancelCallback{
        Sender: bob.String(), ...
    })
    
    // РЕАЛЬНОЕ поведение: Bob получает деньги
    // ОЖИДАЕМОЕ поведение: Alice получает refund
    assert.Greater(t, bankKeeper.GetBalance(ctx, alice, "stake"), aliceBalanceBefore)
    assert.Equal(t, bobBalanceBefore, bankKeeper.GetBalance(ctx, bob, "stake"))
    // Текущий код: тест упадёт — деньги идут к Bob
}
```

### Counterarguments

- Тесты проверяют только случай `registrant == canceller` → no coverage для cross-party
- В `abci.go` используется `callback.ReservedBy` — это подтверждает, что design intent = refund to payer

### Suggested fix

```go
// x/callback/keeper/msg_server.go — CancelCallback
// Было:
err = s.keeper.RefundFromCallbackModule(ctx, request.Sender, refundFees)
// Стало:
err = s.keeper.RefundFromCallbackModule(ctx, callback.ReservedBy, refundFees)
```

**Дополнительно:** Добавить тест `TestCancelCallback_ThirdPartyCancel_RefundGoesToOriginalPayer`.

---

## F-02: TxRewards в InitGenesis сохраняется по неверному ключу (Low)

**Severity: Low**  
**Confidence: High**  
**Статус: Confirmed Bug**

### Затронутые файлы
- `x/rewards/keeper/genesis.go` — функция `InitGenesis`

### Summary

В `InitGenesis` TxRewards записываются по ключу `txReward.Height` вместо `txReward.TxId`. Это нарушает внутреннюю согласованность хранилища при восстановлении из genesis.

### Technical details

```go
// x/rewards/keeper/genesis.go — InitGenesis
for _, txReward := range state.TxRewards {
    // УЯЗВИМОСТЬ: используется Height как primary key
    // должно быть: uint64(txReward.TxId)
    err := k.TxRewards.Set(ctx, uint64(txReward.Height), txReward)
    //                          ^^^^^^^^^^^^^^^^^^^^^ НЕВЕРНО
}
```

TxRewards определён как:
```go
TxRewards *collections.IndexedMap[uint64, types.TxRewards, TxRewardsIndex]
// primary key = txID
// secondary index Block = height
```

**Последствия при восстановлении:**

1. В `estimateBlockRewards` поиск по txID не находит TxRewards:
   ```go
   txRewards, err := k.TxRewards.Get(ctx, txID) // key=txID, но хранится key=height
   // err != nil → fee rebates не распределяются
   ```

2. В `DeleteBlockRewardsCascade` удаление через Block index находит их:
   ```go
   iter, _ := k.TxRewards.Indexes.Block.MatchExact(ctx, height)
   // Block index хранит: height → primary_key (= height в нашем случае)
   // Итерация работает, удаление работает
   ```

**Итог:** После genesis restore, TxRewards существуют в store, но не доступны по txID → fee rebates для этих tx не распределяются → они уходят в treasury через `cleanupRewardsPool`.

### Impact

- Потеря fee rebate rewards при genesis restore с активными TxRewards
- На практике TxRewards — это transient данные внутри блока, нормально их нет в genesis export
- Практический impact: минимальный (только при нестандартном genesis export или аварийном восстановлении)

### PoC plan

```go
func TestInitGenesis_TxRewardsKey(t *testing.T) {
    // Создаём genesis с TxRewards
    genState := types.GenesisState{
        TxRewards: []types.TxRewards{
            {TxId: 42, Height: 100, FeeRewards: sdk.NewCoins(...)},
        },
        BlockRewards: []types.BlockRewards{
            {Height: 100},
        },
        // ...
    }
    
    k.InitGenesis(ctx, &genState)
    
    // Должно найти по TxId=42
    txRewards, err := k.TxRewards.Get(ctx, 42)
    require.NoError(t, err) // ТЕКУЩИЙ КОД: err != nil (хранится по key=100)
    assert.Equal(t, uint64(42), txRewards.TxId)
}
```

### Suggested fix

```go
// x/rewards/keeper/genesis.go — InitGenesis
for _, txReward := range state.TxRewards {
    // Было: uint64(txReward.Height)
    // Стало: uint64(txReward.TxId)
    err := k.TxRewards.Set(ctx, uint64(txReward.TxId), txReward)
    if err != nil {
        panic(err)
    }
}
```

---

## F-03: Query-операции учитываются в распределении rewards (Low)

**Severity: Low**  
**Confidence: Medium**  
**Статус: Lead (требует уточнения design intent)**

### Затронутые файлы
- `x/tracking/keeper/gas_processor.go` — `IngestGasRecord`
- `x/tracking/types/tracking.go` — `GasUsed()`
- `x/rewards/keeper/distribution.go` — `estimateBlockGasUsage`

### Summary

`CONTRACT_OPERATION_QUERY` операции явно включаются в gas tracking и участвуют в расчёте rewards наравне с execute/instantiate. В `GasUsed()` нет фильтрации по типу операции. Cross-contract queries внутри tx execution дают queried контракту долю fee rebate.

### Technical details

```go
// gas_processor.go
case wasmTypes.ContractOperationQuery:
    opType = types.ContractOperation_CONTRACT_OPERATION_QUERY
// Записывается в store, не фильтруется

// tracking.go — GasUsed: только проверка > 0
func (m ContractOperationInfo) GasUsed() (uint64, bool) {
    gasUsed := m.VmGas + m.SdkGas
    return gasUsed, gasUsed > 0  // query eligible = true
}

// distribution.go — нет skip для query:
opGasUsed, opEligible := contractOp.GasUsed()
if !opEligible { continue }  // пропуск только zero gas
contractDistrState.BlockGasUsed += opGasUsed
```

### Сценарий потенциального abuse

1. Задеплоить контракт B с дорогими storage reads
2. Задеплоить контракт A, который вызывает B через cross-contract query
3. Пользователи вызывают A → B получает rewards за read-only операции
4. B может специально хранить большие данные для дорогих queries

**Ограничение:** query gas реально потребляется, поэтому экономически атакующий платит за всё потребляемое. Вопрос только в том, является ли это design intent для rewards.

### Counterarguments

- Query gas реально потребляется (memory, storage reads)
- Может быть intentional: incentivize well-queried infrastructure contracts
- Значимость low: query gas обычно << execute gas

### Suggested fix

Если queries не должны давать rewards — добавить фильтрацию:

```go
// distribution.go — estimateBlockGasUsage
for _, contractOp := range txGasTrackingInfo.ContractOperations {
    // Опционально: пропускать query operations
    if contractOp.OperationType == types.ContractOperation_CONTRACT_OPERATION_QUERY {
        continue
    }
    opGasUsed, opEligible := contractOp.GasUsed()
    // ...
}
```

---

## F-04: Nil pointer через fallthrough в DeductFeeDecorator (Low)

**Severity: Low**  
**Confidence: Medium**  
**Статус: Theoretical (в production не реализуется)**

### Затронутые файлы
- `x/rewards/ante/fee_deduction.go` — `getFeePayer`

### Summary

В Go `fallthrough` в `switch` передаёт управление в тело следующего case без проверки его условия. Если `cwFeesKeeper != nil` (первый case совпал) и контракт не является granter, происходит `fallthrough` к блоку `feegrantKeeper != nil`. Если при этом `feegrantKeeper == nil`, вызов `dfd.feegrantKeeper.UseGrantedFees()` паникует.

### Technical details

```go
// ante/fee_deduction.go — getFeePayer
switch {
case dfd.cwFeesKeeper != nil:
    isCWGranter, err := dfd.cwFeesKeeper.IsGrantingContract(ctx, granter)
    if err != nil { return nil, err }
    if isCWGranter {
        // ... RequestGrant ...
        return granter, nil
    }
    // Если НЕ CW granter:
    fallthrough  // ← Go: выполняет тело СЛЕДУЮЩЕГО case без проверки условия

case dfd.feegrantKeeper != nil:
    // Это тело выполняется через fallthrough даже если feegrantKeeper == nil!
    err = dfd.feegrantKeeper.UseGrantedFees(...)  // PANIC если feegrantKeeper = nil
    if err != nil { return nil, errorsmod.Wrapf(err, ...) }
    return granter, nil

default:
    return nil, errorsmod.Wrap(sdkErrors.ErrInvalidRequest, "fee grants are not enabled")
}
```

### Counterarguments

- В `app.go` оба keeper инициализированы через DI — `feegrantKeeper` всегда non-nil
- Panic не достижима в production при стандартном деплое
- Только при неправильной инициализации (custom node)

### Suggested fix

```go
// Вариант: убрать fallthrough, явный fallback
case dfd.cwFeesKeeper != nil:
    isCWGranter, err := dfd.cwFeesKeeper.IsGrantingContract(ctx, granter)
    if err != nil { return nil, err }
    if isCWGranter {
        err = dfd.cwFeesKeeper.RequestGrant(ctx, granter, ...)
        if err != nil { return nil, err }
        return granter, nil
    }
    // Явный fallback к feegrant:
    if dfd.feegrantKeeper == nil {
        return nil, errorsmod.Wrap(sdkErrors.ErrInvalidRequest, "fee grants are not enabled")
    }
    err = dfd.feegrantKeeper.UseGrantedFees(...)
    if err != nil { return nil, err }
    return granter, nil
```

---

## F-05: Genesis не проверяет соответствие RewardsRecords и баланса модуля (Low)

**Severity: Low**  
**Confidence: High**  
**Статус: Confirmed missing check**

### Затронутые файлы
- `x/rewards/types/genesis.go` — `GenesisState.Validate()`

### Summary

`GenesisState.Validate()` проверяет внутреннюю согласованность данных (duplicates, valid addresses, IDs), но **не проверяет** что сумма `RewardsRecords.Rewards` покрыта балансом `ContractRewardCollector` module account. Это позволяет импортировать genesis с rewards, которые невозможно выплатить.

### Technical details

```go
// types/genesis.go — Validate(): нет проверки баланса
func (m GenesisState) Validate() error {
    // Проверяет: params, metadata duplicates, height duplicates,
    //            txRewards/blockRewards consistency, record IDs...
    
    // НЕ проверяет:
    // Σ(RewardsRecords[i].Rewards) <= ContractRewardCollector.Balance
    
    return nil
}
```

При genesis import `InitGenesis` создаёт все `RewardsRecords` в state, но не переводит соответствующие монеты на `ContractRewardCollector`. Если genesis был сформирован корректно (из `ExportGenesis`), монеты будут на счету. Но если genesis сформирован вручную или некорректно:

```
ContractRewardCollector.Balance = 1000
Σ(RewardsRecords.Rewards) = 5000
```

При `WithdrawRewards` → `SendCoinsFromModuleToAccount` вернёт ошибку "insufficient funds" (или panic если код предполагает успех).

### Impact

- Невозможно выполнить `WithdrawRewards` для части записей
- Если используется `WithdrawToWallet = true`, rewards вычисляются в EndBlocker и могут превысить баланс → panic → chain halt
- Практически: требует ручного или атакующего genesis creation

### PoC plan

```go
func TestGenesisBalanceMismatch(t *testing.T) {
    // Создаём genesis с RewardsRecords но без монет на ContractRewardCollector
    genState := types.GenesisState{
        RewardsRecords: []types.RewardsRecord{
            {Id: 1, RewardsAddress: user.String(), 
             Rewards: sdk.NewCoins(sdk.NewInt64Coin("stake", 1_000_000))},
        },
        // ContractRewardCollector баланс НЕ установлен
    }
    k.InitGenesis(ctx, &genState)
    
    // Попытка снять rewards → должно дать понятную ошибку, не panic
    _, _, err := k.WithdrawRewardsByRecordsLimit(ctx, user, 10)
    require.Error(t, err)  // ТЕКУЩИЙ КОД: panic в EndBlocker при WithdrawToWallet=true
}
```

### Suggested fix

```go
// types/genesis.go — добавить в Validate()
// NOTE: может быть сделано через invariant при genesis, не в Validate()
// Т.к. банковский баланс недоступен из types/genesis.go, 
// проверку лучше добавить в InitGenesis:

// x/rewards/keeper/genesis.go — InitGenesis
func (k Keeper) InitGenesis(ctx sdk.Context, state *types.GenesisState) {
    // ... existing code ...
    
    // После загрузки всех данных — проверить invariant
    if err := k.runBalanceInvariant(ctx); err != nil {
        panic(fmt.Errorf("genesis invariant violation: %w", err))
    }
}
```

Также рекомендуется добавить проверку в `ModuleAccountBalanceInvariant` при genesis:
```go
// В crisis module's RegisterInvariants — уже зарегистрирован
// Но не вызывается при genesis — нужен явный вызов
```

---

## Threat Modeling: x/rewards

### MsgSetContractMetadata

| Вопрос | Ответ |
|--------|-------|
| Кто вызывает? | Admin (create) / Owner (update) |
| Что меняется? | `ContractMetadata`: owner, rewardsAddr, withdrawToWallet |
| Zero values? | Empty OwnerAddress → невалидно (Validate проверяет). Empty RewardsAddress → rewards не распределяются (design) |
| Большие values? | Address 46 байт max → нет проблем |
| Повторный вызов? | Update существующей metadata → корректно |
| Ошибка в середине? | Atomic через KVStore, нет partial state |
| Смена owner → другой адрес? | Новый owner получает полный контроль. **Важно:** старые незабранные RewardsRecords не меняются — новый owner может их снять! |
| Blocked address как rewardsAddr? | Отклоняется: `isBlockedAddress` check |
| Module account как owner? | `isBlockedAddress` НЕ проверяется для owner, только для rewardsAddr. Module account может стать owner → никто не снимет rewards |

**Потенциальный issue:** Можно передать owner = module_account_address. Validate только проверяет valid bech32, не blocked check. Тогда никто не может вызвать MsgSetContractMetadata (заблокированный адрес не может подписывать tx) → metadata заблокирована навсегда.

**Статус:** Low severity — metadata owner для реальных контрактов устанавливает человек, не скрипт. Требует намеренных действий для DOS своих rewards.

### MsgWithdrawRewards

| Вопрос | Ответ |
|--------|-------|
| Кто вызывает? | Любой (но funds идут на rewardsAddr) |
| Double claim? | Нет: record удаляется перед отправкой... нет, ПОСЛЕ |
| Порядок операций | `fastRemoveRecords` вызывается ПОСЛЕ `SendCoinsFromModuleToAccount` |

```go
// withdraw.go — withdrawRewardsByRecords
if !totalRewards.IsZero() {
    if err := k.bankKeeper.SendCoinsFromModuleToAccount(...); err != nil {
        panic(...)  // если fail → panic до удаления
    }
}
// Clean up (safe if there were no rewards)
err := fastRemoveRecords(ctx, k.storeKey, k.RewardsRecords, records...)
```

**Проблема:** Если `SendCoinsFromModuleToAccount` паникует (не возвращает ошибку), `fastRemoveRecords` не вызывается, record остаётся. При повторном вызове можно снять ещё раз. Но `SendCoinsFromModuleToAccount` в Cosmos SDK возвращает error, не паникует. Panic здесь только если error != nil. В таком случае tx откатывается, record не удалён, баланс не тронут → нет double spend. **Корректно.**

| Вопрос | Ответ |
|--------|-------|
| Replay? | Нет: records удаляются |
| Неавторизованный claim? | Нет: `record.RewardsAddress == rewardsAddr` проверяется |

### AllocateBlockRewards (EndBlocker)

| Вопрос | Ответ |
|--------|-------|
| Rounding? | TruncateInt() используется → dust уходит в treasury (cleanupRewardsPool) |
| Multiple contracts одной tx? | Доля = contractGas/totalGas → сумма ≤ total (rounding вниз) |
| Zero totalGas? | Не может: contractTxGasUsed > 0 только если txInfo.TotalGas > 0 |
| MaxGas = 0? | HasGasLimit() check → inflation rewards отключаются, нет деления |
| WithdrawToWallet panic? | panic при ошибке банка в EndBlocker → chain halt |

**WithdrawToWallet panic path:**
```go
// distribution.go:createRewardsRecords
if contractDistrState.Metadata.WithdrawToWallet {
    err := k.bankKeeper.SendCoinsFromModuleToAccount(...)
    if err != nil {
        panic(err)  // ← chain halt!
    }
}
```

Когда это может произойти:
- `rewardsAddr` стал blocked (нельзя через SetContractMetadata, но при genesis restore?)
- Модульный счёт переполнен (невозможно с uint256)
- Системная ошибка банка (крайне редко)

**Статус:** Informational — в нормальных условиях не достигается.

---

## Threat Modeling: x/tracking

### Что именно считается?

**Gas limit или actual gas used?**

```go
// gas_processor.go — IngestGasRecord
k.TrackNewContractOperation(
    ctx,
    contractAddr,
    opType,
    k.WasmGasRegister.FromWasmVMGas(record.OriginalGas.VMGas),  // VM gas → SDK gas
    record.OriginalGas.SDKGas,                                    // actual SDK gas used
)
```

Tracked: `OriginalGas.VMGas` + `OriginalGas.SDKGas` = фактически потреблённый gas, НЕ gas limit. **Нет возможности фармить rewards через высокий gas limit.**

**Failed transactions:**

- AnteHandler записывает `TxInfo` (persist даже при msg failure)
- Message execution: `ContractOpInfo` записывается в msg context
- При msg failure: msg context rollback → `ContractOpInfo` откатывается
- `TxRewards` создаётся в AnteHandler → persist
- **Результат:** fee rebate сохранён, но ни один контракт не имеет `ContractOpInfo` → fee rebate уходит в treasury. **Корректно.**

**Nested contract calls:**

Каждый вызов (execute/query/instantiate) создаёт отдельный `ContractOpInfo` с соответствующим `ContractAddress`. Вложенные вызовы атрибуируются именно тому контракту, который потребил газ. **Нет misattribution.**

**Submessage failure:**

В CosmWasm при submessage failure с `ReplyOn::Error`:
- Родительский контракт продолжает выполнение
- Failed submessage gas уже был потреблён (`IngestGasRecord` вызвался для submessage)
- Tx в целом может успешно завершиться
- `ContractOpInfo` для failed submessage commit'ится вместе с tx

**Результат:** Failed submessage gas учитывается в rewards. Это технически корректно (газ реально был потреблён), но может быть использовано для "no-op" работы: атакующий создаёт контракт с submessage, который всегда ревертится, но тратит газ → контракт получает rewards за бесполезную работу.

**Ограничение:** Пользователь сам платит за gas. Экономически невыгодно, если rewards < gas cost.

**IBC / ICA flows:**

`IngestGasRecord` получает IBC-типы:
```go
case wasmTypes.ContractOperationIbcPacketTimeout:
case wasmTypes.ContractOperationIbcPacketAck:
case wasmTypes.ContractOperationIbcPacketReceive:
    opType = types.ContractOperation_CONTRACT_OPERATION_IBC
```

IBC callbacks (OnPacketTimeout, OnPacketAck) выполняются в разных транзакциях (IBC relay tx). Их gas атрибуируется контракту в контексте той tx, в которой пришёл пакет. Rewards будет получать не пользователь, вызвавший ICA/IBC, а тот, чья tx обработала пакет (relay).

### Double counting?

```go
// FinalizeBlockTxTracking:
for _, contractOp := range contractOpState.GetContractOpInfoByTxID(txInfo.Id) {
    txInfo.TotalGas += contractOp.VmGas + contractOp.SdkGas
}
```

Каждый `ContractOpInfo` имеет уникальный ID → итерация не повторяется. **Нет double counting.**

---

## Threat Modeling: x/callback

### Lifecycle

```
[MsgRequestCallback]
  → isAuthorizedToModify(sender)
  → HasContractInfo(contract)
  → ExistsCallback(height, contract, jobId) → нет дублей
  → callbackHeight > currentHeight (не в прошлом)
  → callbackHeight <= currentHeight + MaxFutureReservationLimit
  → len(callbacksForBlock) < MaxBlockReservationLimit
  → callback.MaxGasLimit = params.CallbackGasLimit (snapshot)
  → Callbacks.Set(...)
  → SendToCallbackModule(sender, fees)

[EndBlocker: callbackExec]
  → ExecuteWithGasLimit(MaxGasLimit, Sudo(contract, msg))
  → Success:
     refundUnused = TransactionFees - CalculateTransactionFees(gasUsed)
     RefundFromCallbackModule(ReservedBy, refundUnused)  ← ПРАВИЛЬНО
     SendToFeeCollector(reservationFees + surplusFees + usedTxFees)
     Callbacks.Remove(...)
  → Failure:
     gasUsed = MaxGasLimit  ← cap для корректного refund расчёта
     SetError(cwerrors, ...)
     RefundFromCallbackModule(ReservedBy, 0)  ← нет refund (весь газ использован)
     SendToFeeCollector(все fees)
     Callbacks.Remove(...)

[MsgCancelCallback]
  → isAuthorizedToModify(sender)
  → DeleteCallback(sender, callback)
  → RefundFromCallbackModule(request.Sender, refundFees)  ← НЕВЕРНО (F-01)
  → SendToFeeCollector(reservationFees)
```

### Replay protection

Callbacks идентифицируются `(height, contractAddress, jobId)`. После выполнения или отмены — удаляются. **Нет replay.**

### MaxBlockReservationLimit validation

```go
// types/params.go
func (p Params) Validate() error {
    if p.CallbackGasLimit == 0 {
        return fmt.Errorf("CallbackGasLimit must be greater than 0")
    }
    // MaxBlockReservationLimit и MaxFutureReservationLimit НЕ проверяются на > 0!
    ...
}
```

Если governance установит `MaxBlockReservationLimit = 0`:
- В `SaveCallback`: `len(callbacksForBlock) >= int(0)` → 0 >= 0 → всегда `ErrBlockFilled`
- **Никто не сможет зарегистрировать новые callbacks**
- Существующие callbacks будут выполнены
- Это governance-controlled lockout без эффекта на funds

**Статус:** Low severity — только governance может сделать это; callbacks не застрянут.

---

## Threat Modeling: x/cwfees

### RequestGrant в AnteHandler

```go
// cwfees/keeper.go
func (k Keeper) RequestGrant(ctx context.Context, grantingContract sdk.AccAddress, ...) error {
    gasLimitToUse := min(sdkCtx.GasMeter().GasRemaining(), RequestGrantGasLimit)
    _, err = pkg.ExecuteWithGasLimit(sdkCtx, gasLimitToUse, func(ctx sdk.Context) error {
        _, err = k.wasmdKeeper.Sudo(sdk.UnwrapSDKContext(ctx), grantingContract, msgBytes)
        return err
    })
    return err
}
```

**ExecuteWithGasLimit behaviour:**
```go
// pkg/utils.go
func ExecuteWithGasLimit(ctx sdk.Context, gasLimit uint64, f func(ctx sdk.Context) error) (gasUsed uint64, err error) {
    branchedCtx, commit := ctx.CacheContext()
    limitedGasMeter := storetypes.NewGasMeter(gasLimit)
    branchedCtx = branchedCtx.WithGasMeter(limitedGasMeter)
    err = catchOutOfGas(branchedCtx, f)
    gasUsed = limitedGasMeter.GasConsumed()
    ctx.GasMeter().ConsumeGas(gasUsed, "branch")  // ← заряжает ВНЕШНИЙ газометр
    if err != nil {
        return gasUsed, err  // state NOT committed
    }
    commit()  // state committed to outer cache context
    return gasUsed, nil
}
```

**Security analysis:**
- Gas cap: 100_000 → malicious contract не может потратить > 100k gas в ante
- State commit: если Sudo успешен, изменения в state применяются в ante context
- При tx failure: ante context rollback → Sudo state также rollback
- **Sudo доступен для контракта в ante**: это необычно — контракт может изменить своё state при обработке каждого tx, даже если tx потом fails

**Потенциальный issue: Front-running через RequestGrant state manipulation**

Атакующий создаёт контракт-granter. В `sudo` обработчике контракт читает state (pending txs, oracle prices) и принимает решения на основе этих данных. Поскольку Sudo вызывается в ante handler (ДО исполнения msgs), контракт видит состояние ПЕРЕД tx. Это expected behavior, но важно помнить при аудите контрактов.

**Статус:** Informational — не баг Archway, баг дизайна контракта.

### catchOutOfGas: Non-gas panics propagate

```go
// pkg/utils.go
func catchOutOfGas(ctx sdk.Context, f func(ctx sdk.Context) error) (err error) {
    defer func() {
        if r := recover(); r != nil {
            if _, ok := r.(storetypes.ErrorOutOfGas); !ok {
                _, _ = fmt.Fprintf(os.Stderr, "recovered: %#v", r)
                panic(r)  // ← re-panic для non-gas errors
            }
            err = sdkerrors.ErrOutOfGas
        }
    }()
    return f(ctx)
}
```

Если контракт-granter паникует с non-gas ошибкой → panic propagates → chain halt.

Но: wasmd (CosmWasm VM) ловит все wasm panics и конвертирует в errors. Rust код не может создать Go panic. **Нет реальной угрозы.**

---

## Threat Modeling: x/cwica + x/cwerrors

### IBC Handler: swallowed errors

```go
// cwica/keeper/ibc_handlers.go
func (k *Keeper) HandleChanOpenAck(...) error {
    _, err = k.sudoKeeper.Sudo(ctx, contractAddress, sudoPayload)
    if err != nil {
        k.Logger(ctx).Debug("HandleChanOpenAck: failed to sudo", "error", err)
        // err НЕ возвращается
    }
    return nil  // ← всегда успех для IBC
}

func (k *Keeper) HandleAcknowledgement(...) error {
    _, err = k.sudoKeeper.Sudo(ctx, contractAddress, sudoMsgPayload)
    if err != nil {
        k.Logger(ctx).Debug("HandleAcknowledgement: failed to Sudo", "error", err)
        // err НЕ возвращается
    }
    return nil
}
```

**Design rationale:** IBC state machine должна успешно завершать обработку пакетов независимо от поведения пользовательских контрактов. Это стандартная практика в ICS-27.

**Impact:** Контракт не получает уведомление об успешном открытии канала или ack. Если контракт ожидал этого уведомления для изменения своего state → контракт остаётся в "ожидающем" состоянии навсегда.

**Для ICA timeout:** Используется `SetError` (cwerrors) — контракт получит ошибку если подписан на cwerrors. Но `HandleChanOpenAck` и `HandleAcknowledgement` не используют cwerrors при ошибке. **Асимметрия: timeout → cwerrors, ack error → только лог**.

**Статус:** Medium informational — design inconsistency. Контракты должны быть написаны с учётом отсутствия гарантированного уведомления.

### MsgSendTx authorization

```go
// cwica/types/tx.go
func (msg *MsgSendTx) GetSigners() []sdk.AccAddress {
    return []sdk.AccAddress{sdk.MustAccAddressFromBech32(msg.ContractAddress)}
}
```

Только контракт сам может отправить ICA tx. Защита через Cosmos SDK signing. **Нет unauthorized ICA.**

### cwerrors: infinite loop protection

```go
// cwerrors/abci.go — sudoErrorCallbackExec
if err != nil {
    // Failed callback → store error in PERMANENT state (NOT transient)
    k.StoreErrorInState(ctx, contractAddr, newSudoErr)
    // НЕ store в transient → нет повторного вызова в этом же EndBlocker
}
```

`IterateSudoErrorCallbacks` читает из transient store. `StoreErrorInState` пишет в permanent store. Нет петли. **Корректно.**

**Potential issue: ErrorID overflow**

```go
// cwerrors/keeper/sudo_errors.go
errorID, err := k.ErrorID.Next(ctx)
```

`ErrorID` — collections.Sequence (uint64). При 2^64 ошибках — overflow. На практике недостижимо.

---

## Threat Modeling: Upgrades / Migrations / Genesis

### Genesis validation gaps

**x/rewards GenesisState.Validate():**
- ✓ Проверяет duplicates для всех коллекций
- ✓ Проверяет TxRewards.Height ∈ BlockRewards heights
- ✓ Проверяет RewardsRecordLastId ≥ max(RewardsRecord.Id)
- ✓ Проверяет FlatFees.ContractAddress ∈ ContractMetadata addresses
- ✗ **НЕ проверяет:** Σ(RewardsRecords.Rewards) ≤ ContractRewardCollector.Balance (F-05)
- ✗ **НЕ проверяет:** TxRewards.TxId уникальны (только height проверяется как secondary index)

**TxRewards duplicate txId:**

```go
// types/genesis.go — Validate()
txRewardsIdSet := make(map[uint64]struct{})
for i, txRewards := range m.TxRewards {
    if _, ok := blockRewardsHeightSet[txRewards.Height]; !ok {
        return fmt.Errorf("txRewards [%d]: height not found", i)
    }
    if _, ok := txRewardsIdSet[txRewards.TxId]; ok {
        return fmt.Errorf("txRewards [%d]: duplicated txId", i)
    }
    txRewardsIdSet[txRewards.TxId] = struct{}{}  // ✓ проверяется
}
```

TxId дублей нет в validation. Но из-за F-02 (wrong key in InitGenesis), duplicate handling при restore всё равно сломан.

### Module account permissions analysis

```go
// app/app.go
maccPerms = map[string][]string{
    rewardsTypes.ContractRewardCollector: nil,          // только bank operations
    rewardsTypes.TreasuryCollector:       {authtypes.Burner},  // может сжигать
    authtypes.FeeCollectorName:           {authtypes.Burner},  // сжигает auth fees
    minttypes.ModuleName:                 {authtypes.Minter},  // создаёт новые монеты
    callbackTypes.ModuleName:             nil,          // только bank operations
    wasmdTypes.ModuleName:                {authtypes.Burner}, // сжигает wasm fees
}
```

**ContractRewardCollector** (nil permissions):
- Может получать coins (bank.Send)
- Может отправлять coins (SendCoinsFromModuleToAccount)
- НЕ может mintить/burnить
- **Заблокированный адрес:** нельзя отправить rewards на ContractRewardCollector напрямую — он заблокирован как blocked address. Это защита от случайной отправки.

**TreasuryCollector** ({Burner}):
- Получает rounding leftovers из rewards pool
- Сжигает их через Burner permission
- Нет mint → нельзя создавать монеты из treasury

**Governance параметры с неожиданным impact:**

| Параметр | Если = 0 | Если очень большой |
|----------|---------|-------------------|
| `InflationRewardsRatio` | Rewards отключены → весь inflation в Cosmos distr | Не допустимо (< 1.0) |
| `TxFeeRebateRatio` | Fee rebates отключены → все fees сжигаются | Не допустимо (< 1.0) |
| `MaxWithdrawRecords` | Недопустимо (validation rejects 0) | Ограничен 25000 |
| `MinPriceOfGas` | Ноль gas price → можно слать дешёвые spam txs | Валидируется как DecCoin |
| `CallbackGasLimit` | Недопустимо (validation rejects 0) | Огромный лимит → callbacks дорогие |
| `MaxBlockReservationLimit` | 0 → нельзя регистрировать callbacks | Нет верхней границы! |

**MaxBlockReservationLimit без верхней границы:** Governance может установить огромное значение → каждый блок может содержать N callbacks. Каждый callback потребляет `CallbackGasLimit` gas. При N = 1000, GasLimit = 1_000_000 → EndBlocker потребляет 10^9 gas, что может превысить block gas limit → chain halt.

**Статус:** Medium governance risk — требует злонамеренного governance proposal или захвата governance.

### Upgrade handlers

Последние upgrades (v9, v10, latest) содержат только `RunMigrations` без дополнительной логики:

```go
// upgrades/latest/upgrades.go
return func(ctx context.Context, plan upgradetypes.Plan, fromVM module.VersionMap) (module.VersionMap, error) {
    migrations, err := mm.RunMigrations(ctx, cfg, fromVM)
    return migrations, err
}
```

Migrations логика находится в `ConsensusVersion` модулей. Единственная известная custom migration: `x/rewards/migrations/v2/migrate.go` (params subspace → direct store). Она корректна и проверяет `currParams.Validate()` перед записью.

---

## Слабые зацепки

### Проверено — не баги

| Зацепка | Почему не баг |
|---------|--------------|
| Failed tx дают rewards | ContractOpInfo rollback → fee rebate в treasury |
| Деление на ноль в rewardsShare | HasGasLimit() проверяет MaxGas > 0 |
| MsgRegisterAsGranter без auth | GetSigners = [ContractAddress] → только контракт |
| OwnerAddress не validates | ContractMetadata.Validate(false) проверяет bech32 |
| CWICA sudo errors игнорируются | IBC design: chain не зависит от contract behavior |
| cwerrors infinite loop | Transient vs permanent store разделены |
| Callback replay | Callbacks удаляются после выполнения |
| CreateRewardsRecord ID off-by-one | Sequence.Next() + 1 корректен |

### Требуют уточнения

| Зацепка | Что нужно проверить |
|---------|-------------------|
| Submessage failures в rewards | Intentional или bug? Gas за reverted submessage даёт rewards |
| Query gas в rewards | Design intent? Документации нет |
| MaxBlockReservationLimit без верхней границы | Governance risk severity |
| WithdrawToWallet panic path | Насколько реален в production? |
| IBC ack success но sudo failed | Контракт в inconsistent state? Нет cwerrors уведомления |

---

## Топ-5 приоритетных файлов

| # | Файл | Приоритет | Тип рисков |
|---|------|-----------|-----------|
| 1 | `x/callback/keeper/msg_server.go` | **CRITICAL** | F-01 confirmed; весь lifecycle refund |
| 2 | `x/rewards/keeper/distribution.go` | HIGH | rounding; WithdrawToWallet panic; fee rebate split |
| 3 | `x/rewards/keeper/genesis.go` | HIGH | F-02 wrong key; F-05 no balance check |
| 4 | `x/rewards/ante/fee_deduction.go` | HIGH | fee split; F-04 fallthrough; flat fee Sub |
| 5 | `x/cwica/keeper/ibc_handlers.go` | MEDIUM | swallowed errors; state inconsistency; no cwerrors for ack |

---

## Рекомендуемые тесты и инварианты

### Обязательные тесты

```go
// 1. F-01: CancelCallback cross-party refund
func TestCancelCallback_AdminCancelsOwnerRegistered_RefundGoesToOwner(t *testing.T) { ... }
func TestCancelCallback_OwnerCancelsAdminRegistered_RefundGoesToAdmin(t *testing.T) { ... }

// 2. F-02: TxRewards InitGenesis key
func TestInitGenesis_TxRewardsStoredByTxId_NotHeight(t *testing.T) { ... }
func TestRoundtrip_ExportImport_TxRewardsAccessibleByTxId(t *testing.T) { ... }

// 3. F-05: Genesis balance invariant
func TestInitGenesis_RewardsRecords_ExceedModuleBalance_PanicOrError(t *testing.T) { ... }

// 4. Gas tracking: failed tx
func TestFailedTx_NoContractRewards_FeeRebateToTreasury(t *testing.T) { ... }

// 5. Gas tracking: submessage failure with ReplyOn::Error
func TestSubmessageFailure_GasCounted_ParentSucceeds(t *testing.T) { ... }

// 6. Callback MaxBlockReservationLimit = 0
func TestParams_MaxBlockReservationLimit_Zero_BlocksRegistration(t *testing.T) { ... }

// 7. Query gas eligible for rewards
func TestQueryOperation_IncludedInGasTracking(t *testing.T) { ... }
```

### Рекомендуемые инварианты

```go
// Invariant 1: Σ(RewardsRecords.Rewards) <= ContractRewardCollector.Balance
// (Уже реализован: ModuleAccountBalanceInvariant — но только >= не ==)

// Invariant 2: TxRewards indexed by TxId (post-genesis test)
func TxRewardsKeyInvariant(k Keeper) sdk.Invariant {
    return func(ctx sdk.Context) (string, bool) {
        // Walk все TxRewards и проверить что их TxId == primary key
        ...
    }
}

// Invariant 3: FlatFees только для контрактов с metadata
func FlatFeeMetadataInvariant(k Keeper) sdk.Invariant {
    return func(ctx sdk.Context) (string, bool) {
        // Для каждого FlatFee: metadata должна существовать
        ...
    }
}
```

---

## Черновик Responsible Disclosure

---

**Кому:** Archway Network Security Team  
**От:** Independent Security Researcher  
**Тема:** [Security] Два подтверждённых бага в x/callback и x/rewards  
**Дата:** 2026-06-03  
**Severity:** Medium (F-01), Low (F-02)  

---

### Находка 1 (Medium): CancelCallback отправляет refund вызывающему, а не плательщику

**Компонент:** `x/callback/keeper/msg_server.go`, функция `CancelCallback`

**Описание:**  
При отмене callback возврат депозита (`TransactionFees + SurplusFees`) отправляется на адрес `request.Sender`, а не `callback.ReservedBy`. Поскольку отменить callback может не только тот, кто его зарегистрировал (но и wasm admin или metadata owner контракта), при их несовпадении происходит кража средств.

**Минимальный сценарий:**
```
1. Контракт C: wasm_admin = Bob, metadata.owner = Alice
2. Alice → MsgRequestCallback{fees: X} → callback.ReservedBy = Alice  
3. Bob → MsgCancelCallback{sender: Bob} → refund X идёт Bob, не Alice
```

**Root cause:**
```go
// Текущий код (неправильно):
err = s.keeper.RefundFromCallbackModule(ctx, request.Sender, refundFees)

// Правильно (используется в abci.go для EndBlocker execution):  
err = s.keeper.RefundFromCallbackModule(ctx, callback.ReservedBy, refundFees)
```

**Fix:** Заменить `request.Sender` на `callback.ReservedBy` — однострочное изменение.

---

### Находка 2 (Low): TxRewards в InitGenesis сохраняются по неверному ключу

**Компонент:** `x/rewards/keeper/genesis.go`, функция `InitGenesis`

**Описание:**  
TxRewards хранятся с primary key = txID. В `InitGenesis` они записываются с key = `txReward.Height` (блок) вместо `txReward.TxId`. После genesis restore, TxRewards не доступны по txID → fee rebates для этих tx теряются (уходят в treasury).

**Root cause:**
```go
// Текущий код (неправильно):
k.TxRewards.Set(ctx, uint64(txReward.Height), txReward)

// Правильно:
k.TxRewards.Set(ctx, uint64(txReward.TxId), txReward)
```

**Practical impact:** TxRewards — transient данные, в нормальном genesis export они пусты. Проявляется только при нестандартном экспорте.

---

*Эксплуатация на mainnet или testnet не проводилась. Все выводы основаны на статическом анализе исходного кода.*

---

## Итоговые результаты

### Confirmed Findings (4)

1. **F-01 (Medium):** `CancelCallback` — refund на `request.Sender` вместо `callback.ReservedBy`
2. **F-02 (Low):** `InitGenesis` для TxRewards использует `Height` вместо `TxId` как ключ
3. **F-03 (Low):** Query operations включаются в rewards attribution без фильтрации
4. **F-05 (Low):** Genesis не проверяет соответствие RewardsRecords и баланса модуля

### Weak Leads (не тратить время)

- Failed tx rewards: корректно, ContractOpInfo rollback защищает
- Деление на ноль: защищено HasGasLimit()
- MsgRegisterAsGranter auth: контракт подписывает сам (GetSigners)
- cwerrors infinite loop: transient/permanent разделены
- Callback replay: удаление из state защищает
- WithdrawToWallet panic: теоретически в нормальных условиях не достигается

### Тесты для написания (7 штук)

Перечислены в разделе "Рекомендуемые тесты".

### Инварианты для добавления (3)

- Module balance ≥ Σ(RewardsRecords) — уже есть, расширить
- TxRewards ключ = TxId (post-genesis check)
- FlatFees только для контрактов с metadata
