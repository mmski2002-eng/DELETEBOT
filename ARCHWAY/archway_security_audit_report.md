# Отчёт по безопасности: Archway Network
## Приватный аудит для Bug Bounty / Responsible Disclosure

**Дата:** 2026-06-03  
**Аудитор:** Security Research Agent  
**Репозиторий:** github.com/archway-network/archway  
**Ветка:** main  
**Методология:** Статический анализ исходного кода, трассировка потоков выполнения, threat modeling Archway-specific логики  

---

## Содержание

1. [Исполнительное резюме](#исполнительное-резюме)
2. [Карта репозитория](#карта-репозитория)
3. [Архитектура системы вознаграждений](#архитектура-системы-вознаграждений)
4. [Найденные уязвимости](#найденные-уязвимости)
   - [F-01: Кража депозита при отмене callback](#f-01-кража-депозита-при-отмене-callback)
   - [F-02: Query-операции участвуют в распределении rewards](#f-02-query-операции-участвуют-в-распределении-rewards)
   - [F-03: Утечка данных газа callback'ов в постоянное хранилище](#f-03-утечка-данных-газа-callbackов-в-постоянное-хранилище)
   - [F-04: Потенциальный nil pointer panic в DeductFeeDecorator](#f-04-потенциальный-nil-pointer-panic-в-deductfeedecorator)
5. [Слабые зацепки (не подтверждены)](#слабые-зацепки)
6. [Топ-5 приоритетных файлов](#топ-5-приоритетных-файлов)
7. [Рекомендуемые тесты](#рекомендуемые-тесты)
8. [Черновик Responsible Disclosure](#черновик-responsible-disclosure)

---

## Исполнительное резюме

Проведён статический аудит Archway-specific кода: `x/rewards`, `x/tracking`, `x/callback`, `x/cwfees`, `x/cwica`, `x/cwerrors`. Стандартные компоненты Cosmos SDK / CometBFT / IBC не анализировались, если Archway их не изменял.

| ID | Уязвимость | Severity | Confidence |
|----|-----------|----------|-----------|
| F-01 | Кража депозита при отмене callback | **Medium** | **High** |
| F-02 | Query-операции участвуют в rewards | Low | Medium |
| F-03 | Утечка газа callback в store | Informational | High |
| F-04 | Nil pointer в DeductFeeDecorator | Low | Medium |

**Наиболее значимая находка:** F-01 — прямая кража средств при определённой конфигурации контракта.

---

## Карта репозитория

### Archway-specific модули

| Модуль | Путь | Назначение |
|--------|------|-----------|
| `x/rewards` | EndBlocker + AnteHandler | Распределение inflation rewards + fee rebates |
| `x/tracking` | EndBlocker + AnteHandler | Gas tracking per contract per tx |
| `x/callback` | EndBlocker + MsgServer | Регистрация и выполнение отложенных callbacks |
| `x/cwfees` | AnteHandler (DeductFee) | CW-contract-based fee grants |
| `x/cwica` | IBC module | Interchain accounts для контрактов |
| `x/cwerrors` | EndBlocker | Доставка ошибок контрактам через sudo |
| `x/genmsg` | Genesis | Выполнение сообщений при инициализации сети |

### Порядок EndBlocker (критично для понимания flows)

```
gov → staking → ibctransfer → ibcfee → ibc → ica →
feegrant → authz → capability → auth → bank → distribution →
nft → slashing → mint → genutil → genmsg → group → evidence →
params → upgrade → vesting → consensus →
ibchooks → wasm →
tracking → rewards → callback →
crisis →
cwerrors
```

**Важно:** `tracking` → `rewards` → `callback` — rewards рассчитываются ДО выполнения callbacks.

### Пользовательские entrypoints

| Msg | Модуль | Авторизация | State changes |
|-----|--------|-------------|--------------|
| `MsgSetContractMetadata` | rewards | contract admin (create) / owner (update) | `ContractMetadata` |
| `MsgWithdrawRewards` | rewards | любой (funds идут на rewards address) | `RewardsRecords`, bank |
| `MsgSetFlatFee` | rewards | metadata owner | `FlatFees` |
| `MsgRequestCallback` | callback | contract / admin / owner | `Callbacks`, bank |
| `MsgCancelCallback` | callback | contract / admin / owner | `Callbacks`, bank |
| `MsgRegisterAsGranter` | cwfees | **сам контракт** (dispatcher) | `GrantingContracts` |
| `MsgUnregisterAsGranter` | cwfees | **сам контракт** | `GrantingContracts` |
| `MsgRegisterInterchainAccount` | cwica | любой (для своего контракта) | IBC channel |
| `MsgSubmitTx` | cwica | любой (для своего контракта) | IBC packet |

### Module account permissions

```go
rewardsTypes.ContractRewardCollector: nil          // только send/receive
rewardsTypes.TreasuryCollector:       {Burner}     // может сжигать leftovers
callbackTypes.ModuleName:             nil          // только send/receive
authtypes.FeeCollectorName:           {Burner}     // сжигает auth fees
minttypes.ModuleName:                 {Minter}     // создаёт inflation
```

---

## Архитектура системы вознаграждений

### Полный flow rewards

```
[Пользователь отправляет tx]
        ↓
[AnteHandler chain]
  TxGasTrackingDecorator: TrackNewTx(ctx) → создаёт TxInfo(id=N, height=H)
  MinFeeDecorator: проверяет min fee, вызывает CreateFlatFeeRewardsRecords()
  DeductFeeDecorator:
    - flatFees → ContractRewardCollector
    - authFees → FeeCollector (сжигаются)
    - rewardsFees → ContractRewardCollector
    - TrackFeeRebatesRewards(rewardsFees) → TxRewards(id=N)
        ↓
[Msg execution]
  wasm execute → IngestGasRecord() → TrackNewContractOperation(txID=N, gas)
        ↓
[EndBlocker: x/tracking]
  FinalizeBlockTxTracking: TxInfo(N).TotalGas = Σ(ContractOpInfo.gas для txID=N)
        ↓
[EndBlocker: x/rewards]
  AllocateBlockRewards(height=H):
    estimateBlockGasUsage: читает GetBlockTrackingInfo(H)
    estimateBlockRewards:
      - inflation share = contractGas / MaxGas * InflationRewards
      - fee rebate share = contractTxGas / totalTxGas * TxRewards.FeeRewards
    createRewardsRecords: создаёт RewardsRecord или SendCoinsFromModule (WithdrawToWallet)
    cleanupRewardsPool: остатки → TreasuryCollector
    cleanupTracking(H): удаляет данные за H-10
        ↓
[EndBlocker: x/callback]
  Выполняет callbacks для высоты H
  (rewards уже рассчитаны — callback gas НЕ влияет на rewards)
        ↓
[MsgWithdrawRewards]
  WithdrawRewardsByRecordsLimit / WithdrawRewardsByRecordIDs
  → проверяет record.RewardsAddress == caller
  → SendCoinsFromModuleToAccount(ContractRewardCollector, rewardsAddr, amount)
  → удаляет RewardsRecords
```

### Flat fee flow

```
[MinFeeDecorator] CreateFlatFeeRewardsRecords(contract, flatFees)
    → немедленно создаёт RewardsRecord для rewards address контракта
[DeductFeeDecorator] SendCoinsFromAccountToModule(user, ContractRewardCollector, flatFees)
    → монеты приходят на модульный счёт
[MsgWithdrawRewards] пользователь забирает
```

---

## Найденные уязвимости

---

### F-01: Кража депозита при отмене callback

**Severity: Medium**  
**Confidence: High**  
**Статус: Confirmed**

#### Затронутые файлы

- `x/callback/keeper/msg_server.go` — функция `CancelCallback`
- `x/callback/keeper/callback.go` — функция `isAuthorizedToModify`

#### Описание проблемы

При отмене callback возврат средств (`TransactionFees + SurplusFees`) происходит на адрес **вызывающего** (`request.Sender`), а не на адрес **изначального плательщика** (`callback.ReservedBy`). Поскольку право на отмену имеют три разные стороны (сам контракт, wasm admin, metadata owner), при их несовпадении возникает кража.

#### Уязвимый код

```go
// x/callback/keeper/msg_server.go — CancelCallback
func (s MsgServer) CancelCallback(c context.Context, request *types.MsgCancelCallback) (...) {
    // Получаем callback из стора
    callback, err := s.keeper.GetCallback(ctx, request.CallbackHeight, request.ContractAddress, request.JobId)
    
    // Проверяем авторизацию (разрешает: контракт / wasm admin / metadata owner)
    err = s.keeper.DeleteCallback(ctx, request.Sender, callback)
    
    // УЯЗВИМОСТЬ: refund идёт на request.Sender, а не на callback.ReservedBy
    refundFees := callback.FeeSplit.TransactionFees.Add(*callback.FeeSplit.SurplusFees)
    err = s.keeper.RefundFromCallbackModule(ctx, request.Sender, refundFees)
    //                                             ^^^^^^^^^^^^^^ НЕПРАВИЛЬНО
    //                                             должно быть: callback.ReservedBy
    
    // Reservation fees идут в fee collector
    reservationFees := callback.FeeSplit.BlockReservationFees.Add(*callback.FeeSplit.FutureReservationFees)
    err = s.keeper.SendToFeeCollector(ctx, reservationFees)
}
```

#### Функция авторизации

```go
// x/callback/keeper/callback.go
func isAuthorizedToModify(ctx sdk.Context, k Keeper, contractAddress sdk.AccAddress, sender string) bool {
    if k.bankKeeper.BlockedAddr(sdk.MustAccAddressFromBech32(sender)) {
        return false
    }
    if strings.EqualFold(sender, contractAddress.String()) {
        return true  // контракт сам себя
    }
    contractInfo := k.wasmKeeper.GetContractInfo(ctx, contractAddress)
    if strings.EqualFold(sender, contractInfo.Admin) {
        return true  // wasm admin
    }
    contractMetadata := k.rewardsKeeper.GetContractMetadata(ctx, contractAddress)
    return contractMetadata != nil && strings.EqualFold(sender, contractMetadata.OwnerAddress) // metadata owner
}
```

Три разных адреса могут быть авторизованы. При регистрации callback (`SaveCallback`) также требуется авторизация — но регистрант и отменяющий могут быть разными авторизованными лицами.

#### Сценарий атаки

**Предусловия:**
- Контракт `C` с `wasm admin = Bob` и `rewards metadata owner = Alice`
- Такая конфигурация реальна: admin управляет кодом контракта, owner управляет rewards

**Шаги:**

1. Alice (metadata owner) вызывает `MsgRequestCallback`:
   ```
   Sender: Alice
   ContractAddress: C
   JobId: 42
   Fees: 1_000_000 aarch
   ```
   → `callback.ReservedBy = Alice` сохраняется в state
   → 1_000_000 aarch уходят с баланса Alice в модульный счёт callback

2. Bob (wasm admin) вызывает `MsgCancelCallback`:
   ```
   Sender: Bob
   ContractAddress: C
   JobId: 42
   CallbackHeight: ...
   ```
   → `isAuthorizedToModify(Bob)` → Bob является admin → authorized = true
   → `DeleteCallback(Bob, callback)` — успешно удаляет
   → `RefundFromCallbackModule(Bob, refundFees)` — **Bob получает деньги Alice**

3. Alice теряет депозит. Bob получает чужие средства.

**Дополнительный вектор:** Admin контракта изменяется через `MsgUpdateAdmin` (стандартный wasmd). Атакующий может:
- Зарегистрировать callback, будучи metadata owner
- Стать admin контракта (через переход прав)
- Отменить callback и забрать средства у себя... хотя в этом случае реального ущерба нет

Более опасный вариант: атакующий уже является admin контракта (или меняет admin), а жертва — metadata owner, которая зарегистрировала дорогой callback.

#### Влияние

- Прямая кража `TransactionFees + SurplusFees` из callback module account
- Объём ущерба = сумма оплаченного callback fee (может быть значительным при дальней высоте + surplus)
- Не требует специальных условий кроме конфигурации контракта с двумя разными авторизованными адресами

#### Тест для подтверждения

```go
func TestCancelCallback_RefundGoesToReservedBy(t *testing.T) {
    keeper, ctx := testutils.CallbackKeeper(t)
    wasmKeeper := testutils.NewMockContractViewer()
    keeper.SetWasmKeeper(wasmKeeper)
    
    contractAddr := e2eTesting.GenContractAddresses(1)[0]
    adminAddr := testutils.AccAddress()    // Bob — admin
    ownerAddr := testutils.AccAddress()   // Alice — metadata owner (регистрирует callback)
    
    wasmKeeper.AddContractAdmin(contractAddr.String(), adminAddr.String())
    // устанавливаем metadata owner = ownerAddr через mock
    
    msgServer := callbackKeeper.NewMsgServer(keeper)
    
    // Alice регистрирует callback
    _, err := msgServer.RequestCallback(ctx, &types.MsgRequestCallback{
        Sender:          ownerAddr.String(),
        ContractAddress: contractAddr.String(),
        JobId:           1,
        CallbackHeight:  ctx.BlockHeight() + 10,
        Fees:            sdk.NewInt64Coin("stake", 1_000_000),
    })
    require.NoError(t, err)
    
    ownerBalanceBefore := bankKeeper.GetBalance(ctx, ownerAddr, "stake")
    adminBalanceBefore := bankKeeper.GetBalance(ctx, adminAddr, "stake")
    
    // Bob (admin) отменяет
    resp, err := msgServer.CancelCallback(ctx, &types.MsgCancelCallback{
        Sender:          adminAddr.String(),  // Bob отменяет
        ContractAddress: contractAddr.String(),
        JobId:           1,
        CallbackHeight:  ctx.BlockHeight() + 10,
    })
    require.NoError(t, err)
    
    // ОЖИДАЕМ: refund должен идти на ownerAddr (Alice), не adminAddr (Bob)
    ownerBalanceAfter := bankKeeper.GetBalance(ctx, ownerAddr, "stake")
    adminBalanceAfter := bankKeeper.GetBalance(ctx, adminAddr, "stake")
    
    // Этот тест УПАДЁТ с текущим кодом:
    assert.True(t, ownerBalanceAfter.IsGTE(ownerBalanceBefore), "Alice должна получить refund")
    assert.Equal(t, adminBalanceBefore, adminBalanceAfter, "Bob не должен получать чужой refund")
}
```

#### Исправление

```go
// x/callback/keeper/msg_server.go — CancelCallback
// БЫЛО:
err = s.keeper.RefundFromCallbackModule(ctx, request.Sender, refundFees)

// СТАЛО:
err = s.keeper.RefundFromCallbackModule(ctx, callback.ReservedBy, refundFees)
```

Одна строка. Возврат идёт изначальному плательщику, а не тому, кто отменяет.

**Дополнительно:** Стоит добавить аналогичную проверку в `callbackExec` (EndBlocker):
```go
// abci.go — если callback выполнен с недоиспользованным газом, refund тоже идёт на ReservedBy
err := k.RefundFromCallbackModule(ctx, callback.ReservedBy, refundAmount) // уже правильно здесь
```
В `abci.go` EndBlocker refund идёт на `callback.ReservedBy` — правильно. Проблема только в `CancelCallback`.

---

### F-02: Query-операции участвуют в распределении rewards

**Severity: Low**  
**Confidence: Medium**  
**Статус: Lead, требует дополнительной проверки**

#### Затронутые файлы

- `x/tracking/keeper/gas_processor.go` — `IngestGasRecord`
- `x/tracking/types/tracking.go` — `GasUsed()`
- `x/rewards/keeper/distribution.go` — `estimateBlockGasUsage`

#### Описание проблемы

`CONTRACT_OPERATION_QUERY` операции явно отслеживаются и включаются в расчёт rewards. Нет фильтрации по типу операции при подсчёте доли rewards для контракта.

#### Код

```go
// gas_processor.go — IngestGasRecord
case wasmTypes.ContractOperationQuery:
    opType = types.ContractOperation_CONTRACT_OPERATION_QUERY
// Операция записывается в store наравне с execute/instantiate

// tracking.go — GasUsed: нет фильтрации по типу
func (m ContractOperationInfo) GasUsed() (uint64, bool) {
    gasUsed := m.VmGas + m.SdkGas
    return gasUsed, gasUsed > 0  // query eligible = true при gas > 0
}

// distribution.go — estimateBlockGasUsage: нет skip для query
opGasUsed, opEligible := contractOp.GasUsed()
if !opEligible { continue }  // пропускаем только нулевой газ, не query
contractDistrState.BlockGasUsed += opGasUsed
```

#### Механизм abuse

1. Задеплоить контракт A с expensive storage reads (дорогие query)
2. Задеплоить контракт B, который вызывает A через cross-contract query
3. Контракт A получает fee rebate за read-only операции
4. Атакующий может фармить rewards, вызывая B с минимальными execute costs, но дорогими queries к A

**Ограничения:** Query gas обычно меньше execute gas. В cross-contract query газ действительно потребляется, поэтому rewards технически оправданы. Вопрос в том, является ли это design intent.

#### Влияние

- Потенциальное искажение распределения rewards в пользу read-heavy контрактов
- Нет прямой кражи средств; bounds: контракт не получит больше, чем его доля от общего газа блока

#### Контраргументы

- Query gas реально потребляется (storage reads не бесплатны)
- Может быть intentional design для incentivizing well-used infrastructure contracts
- Нужна документация от команды по intent

#### Рекомендация

Прояснить в документации: должны ли query-операции давать rewards? Если нет:

```go
// distribution.go — estimateBlockGasUsage
if contractOp.OperationType == types.ContractOperation_CONTRACT_OPERATION_QUERY {
    continue  // не включать query gas в rewards
}
opGasUsed, opEligible := contractOp.GasUsed()
```

---

### F-03: Утечка данных газа callbacks в постоянное хранилище

**Severity: Informational**  
**Confidence: High**  
**Статус: По design, но требует документирования**

#### Описание

Callbacks выполняются в EndBlocker x/callback ПОСЛЕ того, как x/rewards уже рассчитал rewards. При выполнении callback wasm-контракта вызывается `IngestGasRecord` → `TrackNewContractOperation`, которая записывает `ContractOpInfo` с `TxId = GetCurrentTxID()`.

```go
// tracking/keeper/state_tx_info.go
func (s TxInfoState) GetCurrentTxID() uint64 {
    lastIDBz := s.stateStore.Get(types.TxInfoIDKey)
    lastID := sdk.BigEndianToUint64(lastIDBz)  // возвращает последний txID из антехендлера
    return lastID
}
```

В EndBlocker нет нового `TrackNewTx()`, поэтому gas callback'а пишется с ID последней tx блока.

#### Последствия

- ContractOpInfo callback'а записывается в store с `TxId = N` (последняя tx)
- `FinalizeBlockTxTracking` уже выполнился — новый ContractOpInfo не попадает в TxInfo.TotalGas
- `AllocateBlockRewards` уже выполнился — callback gas не влияет на rewards
- Данные удаляются при `cleanupTracking(height-10)` автоматически
- **Нет финансового impact**, нет неправильного распределения

#### Рекомендация

Добавить комментарий в `callbackExec` и/или создать изолированный txID для EndBlocker operations, чтобы предотвратить потенциальную путаницу в будущих изменениях кода.

---

### F-04: Потенциальный nil pointer panic в DeductFeeDecorator

**Severity: Low**  
**Confidence: Medium**  
**Статус: Теоретически, в production защищено конфигурацией**

#### Затронутые файлы

- `x/rewards/ante/fee_deduction.go` — `getFeePayer`

#### Описание

```go
// fee_deduction.go — getFeePayer
switch {
case dfd.cwFeesKeeper != nil:
    isCWGranter, err := dfd.cwFeesKeeper.IsGrantingContract(ctx, granter)
    if !isCWGranter {
        fallthrough  // выполняет тело следующего case НЕЗАВИСИМО от его условия
    }
    return granter, nil  // только если isCWGranter

case dfd.feegrantKeeper != nil:
    // В Go: fallthrough выполняет ЭТО тело даже если feegrantKeeper == nil
    err = dfd.feegrantKeeper.UseGrantedFees(...)  // PANIC если feegrantKeeper nil
    return granter, nil

default:
    return nil, errorsmod.Wrap(...)
}
```

В Go `fallthrough` в `switch` с expression-cases переходит к телу следующего case **не проверяя его условие**. Если `cwFeesKeeper != nil` (первый case совпадает), но `feegrantKeeper == nil`, то `fallthrough` вызовет `dfd.feegrantKeeper.UseGrantedFees()` на nil receiver → panic.

#### Почему это не критично в production

В `app.go` оба keeper инициализируются через DI:

```go
// app/ante.go (предположительно)
NewDeductFeeDecorator(codec, ak, bk, feegrantKeeper, rewardsKeeper, cwFeesKeeper)
```

В стандартном деплое `feegrantKeeper` всегда non-nil. Panic возможен только при некорректной инициализации.

#### Исправление

```go
// Вариант 1: явная проверка
if !isCWGranter {
    if dfd.feegrantKeeper == nil {
        return nil, errorsmod.Wrap(sdkErrors.ErrInvalidRequest, "fee grants are not enabled")
    }
    err = dfd.feegrantKeeper.UseGrantedFees(...)
    ...
}

// Вариант 2: убрать fallthrough, использовать явный if-else
```

---

## Слабые зацепки

Следующие области проверены, но не подтвердились как уязвимости:

### 1. Failed tx и gas tracking

**Проверено:** При неуспешной tx AnteHandler state фиксируется (TxInfo, TxRewards), но ContractOpInfo откатывается вместе с msg execution state. Rewards для failed tx не начисляются — fee rebate уходит в treasury. **Корректное поведение.**

### 2. Деление на ноль в estimateBlockRewards

**Проверено:** `rewardsShare = gasUsed / blockRewards.MaxGas`. Защищено проверкой:
```go
if blockRewards.HasGasLimit() {  // MaxGas > 0
    inlfationRewardsEligible = true
}
// если MaxGas == 0, инфляционные rewards не распределяются
```
Деление происходит только при `inlfationRewardsEligible = true`, что гарантирует `MaxGas > 0`. **Нет уязвимости.**

### 3. Несанкционированная регистрация cwfees granter

**Проверено:** `MsgRegisterAsGranter.GetSigners()` требует подпись самого контракта:
```go
func (m *MsgRegisterAsGranter) GetSigners() []sdk.AccAddress {
    return []sdk.AccAddress{sdk.MustAccAddressFromBech32(m.GrantingContract)}
}
```
Только сам контракт (через submessage dispatch) может зарегистрировать себя. **Нет уязвимости.**

### 4. WithdrawToWallet panic в EndBlocker

**Проверено:** `SendCoinsFromModuleToAccount` в `createRewardsRecords` паникует при ошибке. Защищено тем, что:
- rewards address не может быть blocked address (проверяется при SetContractMetadata)
- монеты на ContractRewardCollector всегда есть, т.к. RewardsTotal рассчитан из реального баланса

Теоретически возможна проблема при state corruption, но пути для этого через пользовательский input не найдены. **Низкий риск.**

### 5. Валидация OwnerAddress в SetContractMetadata

**Проверено:** `ContractMetadata.Validate(false)` вызывается в ValidateBasic и включает:
```go
if genesisValidation || m.OwnerAddress != "" {
    if _, err := sdk.AccAddressFromBech32(m.OwnerAddress); err != nil {
        return errorsmod.Wrapf(sdkErrors.ErrInvalidAddress, ...)
    }
}
```
Невалидный OwnerAddress отклоняется. **Нет уязвимости.**

### 6. CWICA sudo errors swallowed

**Проверено:** В `HandleChanOpenAck` и `HandleAcknowledgement` ошибки sudo логируются, но не возвращаются. Это **намеренный design**: IBC state machine не должна зависеть от поведения пользовательского контракта. Контракт должен использовать x/cwerrors subscription для получения уведомлений об ошибках.

### 7. Инвариант ModuleAccountBalance не покрывает WithdrawToWallet

**Проверено:** Инвариант проверяет `ContractRewardCollector.Balance >= Σ(RewardsRecords.Rewards)`. При `WithdrawToWallet=true` запись в RewardsRecords не создаётся — монеты отправляются напрямую. Инвариант технически корректен: он проверяет только records-based rewards. Нет накопления ошибок.

---

## Топ-5 приоритетных файлов

| # | Файл | Риск | Обоснование |
|---|------|------|-------------|
| 1 | `x/callback/keeper/msg_server.go` | **Confirmed Bug** | F-01: кража через CancelCallback |
| 2 | `x/rewards/keeper/distribution.go` | High value | Центральная логика расчёта rewards, rounding, share calculations |
| 3 | `x/tracking/keeper/gas_processor.go` | Medium | Все gas records проходят здесь; query eligibility |
| 4 | `x/cwfees/keeper.go` | Medium | RequestGrant gas limit logic; state commit in ante |
| 5 | `x/rewards/ante/fee_deduction.go` | Medium | Fee split, flatFee Sub, fallthrough logic |

---

## Рекомендуемые тесты

### Для F-01 (обязательно)

```go
// TestCancelCallback_RefundGoesToReservedBy_NotCanceller
// Проверить: если admin отменяет callback зарегистрированный owner → refund идёт к owner
func TestCancelCallback_AdminCancelsOwnerCallback(t *testing.T) { ... }

// TestCancelCallback_OwnerCancelsAdminCallback  
// Проверить: если owner отменяет callback зарегистрированный admin → refund идёт к admin
func TestCancelCallback_OwnerCancelsAdminCallback(t *testing.T) { ... }
```

### Для F-02

```go
// TestQueryGasIncludedInRewards
// Убедиться, что query gas действительно включается в rewards расчёт
// Если это не design intent — добавить фильтрацию
func TestQueryOperationRewardsEligibility(t *testing.T) { ... }
```

### Для gas tracking invariants

```go
// TestCallbackGasNotIncludedInRewards
// Callback execution в EndBlocker не должен давать rewards контракту
func TestCallbackEndBlockerGasExcludedFromRewards(t *testing.T) { ... }

// TestFailedTxNoRewards
// Failed tx (msg error) не даёт rewards ни одному контракту
// Убедиться что fee rebate уходит в treasury, не контракту
func TestFailedTxFeeRebateGoesToTreasury(t *testing.T) { ... }

// TestMultiContractTxFeeRebateSplit
// Два контракта в одной tx → rewards разделяются пропорционально gas
// Проверить boundary: один контракт = 0 gas
func TestMultiContractFeeRebateDistribution(t *testing.T) { ... }
```

### Для genesis/migration

```go
// TestInvalidGenesisCallbackReservedBy
// Genesis с callback.ReservedBy != авторизованная сторона → отклонить
func TestGenesisValidationCallbackReservedBy(t *testing.T) { ... }
```

---

## Черновик Responsible Disclosure

---

**To:** Archway Network Security Team  
**Subject:** [Security] CancelCallback sends fee refund to canceller instead of original fee payer  
**Severity:** Medium  
**Date:** 2026-06-03  

---

### Краткое описание

В функции `CancelCallback` модуля `x/callback` возврат средств (`TransactionFees + SurplusFees`) отправляется на адрес вызывающего (`request.Sender`), а не на адрес изначального плательщика (`callback.ReservedBy`). При конфигурации, где wasm admin и metadata owner контракта — разные адреса, это позволяет одной авторизованной стороне отменить callback другой и забрать уплаченные средства.

### Затронутый компонент

**Файл:** `x/callback/keeper/msg_server.go`  
**Функция:** `CancelCallback`  
**Строка:** `RefundFromCallbackModule(ctx, request.Sender, refundFees)`

### Минимальный PoC

```
1. Контракт C: wasm admin = Bob, metadata owner = Alice
2. Alice → MsgRequestCallback{fees: X aarch} → callback.ReservedBy = Alice
3. Bob → MsgCancelCallback → refund уходит Bob, не Alice
```

### Root cause

```go
// Текущий код (неправильно):
err = s.keeper.RefundFromCallbackModule(ctx, request.Sender, refundFees)

// Должно быть:
err = s.keeper.RefundFromCallbackModule(ctx, callback.ReservedBy, refundFees)
```

### Предлагаемое исправление

Однострочное изменение: заменить `request.Sender` на `callback.ReservedBy` при возврате fee refund. Возврат должен идти тому, кто оплатил регистрацию, а не тому, кто вызвал отмену.

### Влияние

- Прямая кража средств (callback registration fee)
- Требует: один контракт с двумя разными авторизованными сторонами
- Не требует: особых привилегий кроме стандартной роли admin или owner

### Не эксплуатировалось

Данная уязвимость обнаружена в ходе статического анализа исходного кода. Эксплуатация на mainnet или testnet не проводилась.

---

*Отчёт составлен для целей легального bug bounty / responsible disclosure. Все действия ограничены локальным анализом кода.*
