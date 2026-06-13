# PROMPT 0 — Карта поверхности атаки Archway Network
## Repo Mapping / Attack Surface Report

**Дата:** 2026-06-03  
**Репозиторий:** github.com/archway-network/archway (ветка: main)  
**Методология:** Статический анализ через GitHub API, трассировка entrypoints, анализ authorization flows  
**Цель:** Построить полную карту Archway-specific поверхности атаки для последующего глубокого аудита  

---

## Repository Map

### Структура директорий

```
archway/
├── app/
│   ├── app.go                    # Главный файл приложения, DI, module manager
│   ├── ante.go                   # Ante handler chain
│   ├── app_upgrades.go           # Регистрация upgrade handlers
│   ├── keepers/keepers.go        # Все keepers в одном месте
│   └── upgrades/
│       ├── 06/                   # v0.6.0
│       ├── 1_0_0_rc_4/           # v1.0.0-rc.4
│       ├── 2_0_0/                # v2.0.0
│       ├── 3_0_0/                # v3.0.0
│       ├── 4_0_0/                # v4.0.0
│       ├── 4_0_2/                # v4.0.2
│       ├── 6_0_0/                # v6.0.0
│       ├── 7_0_0/                # v7.0.0
│       ├── 9_0_0/                # v9.0.0
│       ├── 10_0_0/               # v10.0.0
│       ├── latest/               # текущий (только RunMigrations)
│       └── constantineupgrades/  # testnet-only патч
├── x/
│   ├── rewards/                  # ★ Archway-specific: вознаграждения разработчиков
│   ├── tracking/                 # ★ Archway-specific: gas tracking
│   ├── callback/                 # ★ Archway-specific: отложенные callbacks
│   ├── cwfees/                   # ★ Archway-specific: CW contract fee grants
│   ├── cwica/                    # ★ Archway-specific: CW interchain accounts
│   ├── cwerrors/                 # ★ Archway-specific: error callbacks
│   ├── genmsg/                   # ★ Archway-specific: genesis messages
│   └── gov/                      # ★ Модифицирован: custom keeper
├── pkg/
│   ├── utils.go                  # ExecuteWithGasLimit, catchOutOfGas
│   └── coins.go                  # SplitCoins
├── contracts/go/voter/           # Reference CosmWasm contract для тестов
└── proto/
    └── archway/                  # Protobuf definitions для всех x/ модулей
```

### Protobuf definitions

```
proto/archway/
├── rewards/v1/        # tx.proto, query.proto, genesis.proto, rewards.proto
├── tracking/v1/       # query.proto, genesis.proto, tracking.proto
├── callback/v1/       # tx.proto, query.proto, genesis.proto, callback.proto
├── cwfees/v1/         # tx.proto, query.proto, genesis.proto
├── cwica/v1/          # tx.proto, query.proto, genesis.proto
└── cwerrors/v1/       # tx.proto, query.proto, genesis.proto
```

---

## Archway-specific Modules

### Полный список модулей

| Модуль | Путь | Тип | Archway-specific |
|--------|------|-----|-----------------|
| `x/rewards` | Rewards distribution | EndBlocker + Ante | **ДА** |
| `x/tracking` | Gas tracking | EndBlocker + Ante | **ДА** |
| `x/callback` | Delayed callbacks | EndBlocker + Msg | **ДА** |
| `x/cwfees` | CW fee grants | Ante | **ДА** |
| `x/cwica` | CW interchain accounts | IBC + Msg | **ДА** |
| `x/cwerrors` | Error delivery | EndBlocker + Msg | **ДА** |
| `x/genmsg` | Genesis messages | Genesis | **ДА** |
| `x/gov` | Governance | — | Модифицирован |
| `x/auth`, `x/bank`, etc. | Standard Cosmos | — | Нет |
| `wasm` | CosmWasm (wasmd) | — | Используется как база |

### Порядок исполнения (критично для security анализа)

#### BeginBlocker order
```
capability → mint → distribution → slashing → evidence → staking →
auth → bank → gov → nft → crisis → genutil → genmsg → group →
authz → feegrant → params → vesting → consensus →
ibc → ibctransfer → ibcfee → ica →
ibchooks → wasm
```
**Важно:** Ни один Archway-specific модуль не имеет BeginBlocker.

#### EndBlocker order
```
gov → staking → ibctransfer → ibcfee → ibc → ica →
feegrant → authz → capability → auth → bank → distribution →
nft → slashing → mint → genutil → genmsg → group → evidence →
params → upgrade → vesting → consensus →
ibchooks → wasm →
[tracking] → [rewards] → [callback] →
crisis →
[cwerrors]
```

**Критичный порядок Archway модулей:**
1. `x/tracking` — финализирует gas tracking (`FinalizeBlockTxTracking`)
2. `x/rewards` — рассчитывает и распределяет rewards (`AllocateBlockRewards`)
3. `x/callback` — выполняет callbacks (`Sudo` calls)
4. `x/cwerrors` — доставляет ошибки контрактам

**Следствие:** callbacks выполняются ПОСЛЕ расчёта rewards → callback gas не влияет на текущий блок.

#### InitGenesis order
```
capability → auth → bank → distribution → staking → slashing → gov →
nft → mint → [rewards] → genutil → group → evidence → authz →
feegrant → params → upgrade → vesting → consensus →
ibc → ibctransfer → ibcfee → ica →
ibchooks → wasm →
[cwfees] → [tracking] → genmsg → [callback] → [cwerrors] →
crisis → [cwica]
```

**Важно:** `rewards` инициализируется до `wasm`, что означает metadata для контрактов задаётся после деплоя wasm.

---

## User-controlled Entrypoints

### Полная таблица entrypoints

#### x/rewards — вознаграждения

| Функция | Файл | Кто вызывает | State writes | Движение средств | Auth checks | Edge cases |
|---------|------|-------------|-------------|------------------|-------------|-----------|
| `MsgSetContractMetadata` | `keeper/msg_server.go` | contract admin (create) / metadata owner (update) | `ContractMetadata` | нет | admin при создании; owner при изменении | передача owner → invalid addr? |
| `MsgWithdrawRewards` | `keeper/msg_server.go` | **любой** | `RewardsRecords` (удаление) | `ContractRewardCollector → rewardsAddr` | `record.RewardsAddress == caller` | нет records → 0 rewards, не ошибка |
| `MsgSetFlatFee` | `keeper/msg_server.go` | metadata owner | `FlatFees` | нет | `metadata.OwnerAddress == sender` | zero fee → удаление записи |
| `MsgUpdateParams` | `keeper/msg_server.go` | governance (authority) | `Params` | нет | `authority == govAddr` | InflationRatio/TxFeeRebateRatio диапазон [0, 1) |

#### x/tracking — gas tracking

| Функция | Файл | Кто вызывает | State writes | Движение средств | Auth checks | Edge cases |
|---------|------|-------------|-------------|------------------|-------------|-----------|
| `IngestGasRecord` | `keeper/gas_processor.go` | wasmd (автоматически) | `ContractOpInfo` | нет | нет (только wasmd вызывает) | query ops включаются; failed tx ops откатываются |
| `TrackNewTx` | `keeper/keeper.go` | AnteHandler | `TxInfo` | нет | нет | вызывается до msg exec → persists при msg failure |
| `FinalizeBlockTxTracking` | `keeper/keeper.go` | EndBlocker | `TxInfo.TotalGas` | нет | нет | нет |

#### x/callback — отложенные callbacks

| Функция | Файл | Кто вызывает | State writes | Движение средств | Auth checks | Edge cases |
|---------|------|-------------|-------------|------------------|-------------|-----------|
| `MsgRequestCallback` | `keeper/msg_server.go` | contract / admin / owner | `Callbacks` | `sender → callbackModule` | `isAuthorizedToModify` | maxFutureReservationLimit; maxBlockReservationLimit |
| `MsgCancelCallback` | `keeper/msg_server.go` | contract / admin / owner | `Callbacks` (удаление) | `callbackModule → request.Sender` | `isAuthorizedToModify` | **⚠ refund на Sender, не ReservedBy** |
| `MsgUpdateParams` | `keeper/msg_server.go` | governance | `Params` | нет | authority check | CallbackGasLimit = 0 → error |
| `callbackExec` (EndBlocker) | `abci.go` | EndBlocker (авто) | `Callbacks` (удаление) | `callbackModule → ReservedBy` (partial refund) | нет | out-of-gas → gasUsed = MaxGasLimit; failed → cwerrors |

#### x/cwfees — CW fee grants

| Функция | Файл | Кто вызывает | State writes | Движение средств | Auth checks | Edge cases |
|---------|------|-------------|-------------|------------------|-------------|-----------|
| `MsgRegisterAsGranter` | `msg_server.go` | **контракт сам** (submessage) | `GrantingContracts` | нет | `GetSigners = [ContractAddress]` | double registration → error |
| `MsgUnregisterAsGranter` | `msg_server.go` | **контракт сам** | `GrantingContracts` (удаление) | нет | `GetSigners = [ContractAddress]` | нет |
| `RequestGrant` | `keeper.go` | DeductFeeDecorator | transient (Sudo call) | контракт оплачивает tx fee | Sudo call контракта | gas cap = 100_000; out-of-gas → tx fail |

#### x/cwica — CW interchain accounts

| Функция | Файл | Кто вызывает | State writes | Движение средств | Auth checks | Edge cases |
|---------|------|-------------|-------------|------------------|-------------|-----------|
| `MsgRegisterInterchainAccount` | `keeper/msg_server.go` | **контракт сам** (submessage) | IBC channel state | нет | `GetSigners = [ContractAddress]` | connectionId не существует → error |
| `MsgSendTx` | `keeper/msg_server.go` | **контракт сам** | IBC packet | tx fees на host chain | `GetSigners = [ContractAddress]` | timeout → channel close (ordered ICA) |
| `HandleChanOpenAck` | `keeper/ibc_handlers.go` | IBC (авто) | Sudo call | нет | нет | **sudo error игнорируется** |
| `HandleAcknowledgement` | `keeper/ibc_handlers.go` | IBC (авто) | Sudo call / cwerrors | нет | нет | **sudo error игнорируется** |
| `HandleTimeout` | `keeper/ibc_handlers.go` | IBC (авто) | `cwerrors.SetError` | нет | нет | канал закрывается |

#### x/cwerrors — error callbacks

| Функция | Файл | Кто вызывает | State writes | Движение средств | Auth checks | Edge cases |
|---------|------|-------------|-------------|------------------|-------------|-----------|
| `MsgSubscribeToErrors` | `keeper/msg_server.go` | contract / admin / owner | `ContractSubscriptions` | `sender → FeeCollector` | `isAuthorizedToSubscribe` | fee = 0 по умолчанию |
| `MsgUnsubscribeFromErrors` | `keeper/msg_server.go` | contract / admin / owner | `ContractSubscriptions` (удаление) | нет | `isAuthorizedToSubscribe` | нет |
| `MsgUpdateParams` | `keeper/msg_server.go` | governance | `Params` | нет | authority check | ErrorStoredTime ≤ 0 → error |
| `sudoErrorCallbackExec` (EndBlocker) | `abci.go` | EndBlocker (авто) | transient → permanent state | нет | нет | failed callback → StoreErrorInState (no loop) |

---

## State-changing Keeper Methods (Archway-specific)

### x/rewards Keeper

| Метод | State | Движение средств |
|-------|-------|-----------------|
| `SetContractMetadata` | `ContractMetadata` | нет |
| `WithdrawRewardsByRecordsLimit` | `RewardsRecords` (удаление) | `ContractRewardCollector → rewardsAddr` |
| `WithdrawRewardsByRecordIDs` | `RewardsRecords` (удаление) | `ContractRewardCollector → rewardsAddr` |
| `SetFlatFee` | `FlatFees` | нет |
| `CreateRewardsRecord` | `RewardsRecords` (создание) | нет |
| `CreateFlatFeeRewardsRecords` | `RewardsRecords` (создание) | нет |
| `AllocateBlockRewards` | `BlockRewards`, `TxRewards`, `RewardsRecords` | `ContractRewardCollector → rewardsAddr` или `→ TreasuryCollector` |
| `TrackFeeRebatesRewards` | `TxRewards` | нет |
| `TrackInflationRewards` | `BlockRewards` | нет |
| `DeleteBlockRewardsCascade` | `BlockRewards`, `TxRewards` (удаление) | нет |

### x/tracking Keeper

| Метод | State | Примечание |
|-------|-------|-----------|
| `TrackNewTx` | `TxInfo` (создание) | Вызывается в AnteHandler |
| `TrackNewContractOperation` | `ContractOpInfo` (создание) | Вызывается из wasmd |
| `FinalizeBlockTxTracking` | `TxInfo.TotalGas` (обновление) | EndBlocker |
| `RemoveBlockTrackingInfo` | `TxInfo`, `ContractOpInfo` (удаление) | Pruning height-10 |

### x/callback Keeper

| Метод | State | Движение средств |
|-------|-------|-----------------|
| `SaveCallback` | `Callbacks` | нет |
| `DeleteCallback` | `Callbacks` (удаление) | нет |
| `SendToCallbackModule` | нет | `sender → callbackModule` |
| `RefundFromCallbackModule` | нет | `callbackModule → addr` |
| `SendToFeeCollector` | нет | `callbackModule → FeeCollector` |

### x/cwerrors Keeper

| Метод | State | Примечание |
|-------|-------|-----------|
| `SetError` | transient / `Errors` | Роутит в subscription или permanent state |
| `StoreErrorInState` | `Errors`, `ContractErrors`, `DeletionBlocks` | Permanent, автоудаление через ErrorStoredTime |
| `SetSubscription` | `ContractSubscriptions`, `SubscriptionEndBlock` | Автопрерывается через SubscriptionPeriod |
| `PruneSubscriptionsEndBlock` | `ContractSubscriptions` (удаление) | EndBlocker |
| `PruneErrorsCurrentBlock` | `Errors`, `ContractErrors`, `DeletionBlocks` (удаление) | EndBlocker |

---

## Governance-controlled Parameters

### x/rewards Params

| Параметр | По умолчанию | Диапазон | Влияние |
|----------|-------------|---------|---------|
| `InflationRewardsRatio` | 0.20 (20%) | [0, 1) | доля inflation → rewards pool |
| `TxFeeRebateRatio` | 0.50 (50%) | [0, 1) | доля tx fees → rewards pool |
| `MaxWithdrawRecords` | 25000 | [1, 25000] | лимит records за один withdraw |
| `MinPriceOfGas` | 0 stake | ≥ 0 | минимальная цена газа |

### x/callback Params

| Параметр | По умолчанию | Валидация | Влияние |
|----------|-------------|---------|---------|
| `CallbackGasLimit` | 1_000_000 | > 0 | макс газ для callback execution |
| `MaxBlockReservationLimit` | 3 | нет | макс callbacks за блок |
| `MaxFutureReservationLimit` | 10_000 | нет | макс высота в будущем |
| `BlockReservationFeeMultiplier` | 1.0 | ≥ 0 | множитель fee за позицию в блоке |
| `FutureReservationFeeMultiplier` | 1.0 | ≥ 0 | множитель fee за дальность |

### x/cwica Params

| Параметр | По умолчанию | Валидация | Влияние |
|----------|-------------|---------|---------|
| `MsgSendTxMaxMessages` | 5 | > 0 | макс msgs в одном ICA tx |

### x/cwerrors Params

| Параметр | По умолчанию | Валидация | Влияние |
|----------|-------------|---------|---------|
| `ErrorStoredTime` | 302400 (~21 дней) | > 0 | как долго ошибки хранятся в state |
| `SubscriptionFee` | 0 stake | valid coin | плата за подписку на ошибки |
| `SubscriptionPeriod` | 302400 (~21 дней) | > 0 | срок подписки |

---

## Версии upgrades

```
v0.6.0        → upgrade_0_6
v1.0.0-rc.4   → upgrade1_0_0_rc_4
v2.0.0        → upgrade2_0_0
v3.0.0        → upgrade3_0_0
v4.0.0        → upgrade4_0_0
v4.0.2        → upgrade4_0_2
v6.0.0        → upgrade6_0_0
v7.0.0        → upgrade7_0_0
v9.0.0        → upgrade9_0_0
v10.0.0       → upgrade10_0_0
latest        → RunMigrations only (текущий)
```

**x/rewards migration v2:** Миграция params из x/params subspace напрямую в x/rewards store.

---

## High-value Audit Targets

### Топ-10 файлов для аудита

| # | Файл | Приоритет | Тип рисков |
|---|------|-----------|-----------|
| 1 | `x/callback/keeper/msg_server.go` | **CRITICAL** | ★ Confirmed bug F-01; authorization flows; refund logic |
| 2 | `x/rewards/keeper/distribution.go` | HIGH | Rounding/truncation; share calculation; cleanupRewardsPool; WithdrawToWallet panic |
| 3 | `x/rewards/ante/fee_deduction.go` | HIGH | Fee split; flatFee Sub; cwfees/feegrant fallthrough; fee payer manipulation |
| 4 | `x/tracking/keeper/gas_processor.go` | HIGH | Query gas eligibility; IngestGasRecord attribution; all gas goes through here |
| 5 | `x/cwfees/keeper.go` | HIGH | RequestGrant gas limit; state commit in ante; sudo abort path |
| 6 | `x/callback/abci.go` | HIGH | out-of-gas handling; fee refund in EndBlocker; panic paths |
| 7 | `x/cwica/keeper/ibc_handlers.go` | MEDIUM | Swallowed sudo errors; ICA state machine; timeout handling |
| 8 | `x/cwerrors/keeper/sudo_errors.go` | MEDIUM | Error routing; transient vs permanent store; panic in StoreErrorInState |
| 9 | `x/rewards/keeper/metadata.go` | MEDIUM | Ownership transfer; authorization bypass; admin/owner separation |
| 10 | `app/upgrades/*/upgrades.go` | MEDIUM | Migration correctness; state invariants post-upgrade |

---

## Полный Flow системы вознаграждений

```
[Tx отправлена]
     │
     ▼
[AnteHandler chain]
  1. TxGasTrackingDecorator
     └─ TrackNewTx(ctx) → TxInfo(id=N, height=H) создан в KV store
  
  2. MinFeeDecorator
     ├─ Проверяет: txFees ≥ computationalGas*gasPrice + flatFees
     └─ CreateFlatFeeRewardsRecords() → RewardsRecord создан (flat fee portion)
  
  3. DeductFeeDecorator
     ├─ Определяет fee payer (cwfees / feegrant / sender)
     ├─ flatFees → ContractRewardCollector (bank send)
     ├─ authFees → FeeCollector → burn
     ├─ rewardsFees → ContractRewardCollector (bank send)
     └─ TrackFeeRebatesRewards(rewardsFees) → TxRewards(id=N) создан
     │
[Msg execution]
  wasm.Execute/Instantiate/Migrate/Reply/Sudo
  └─ IngestGasRecord() → TrackNewContractOperation(txID=N, vmGas, sdkGas)
     → ContractOpInfo создан
     │
[EndBlocker: x/tracking]
  FinalizeBlockTxTracking()
  └─ TxInfo(N).TotalGas = Σ ContractOpInfo(txID=N).gas
     │
[EndBlocker: x/rewards]
  AllocateBlockRewards(height=H):
  ├─ estimateBlockGasUsage()
  │   └─ читает GetBlockTrackingInfo(H)
  │       → для каждой tx: итерирует ContractOpInfo
  │       → contractDistrState.BlockGasUsed, TxGasUsed
  │
  ├─ estimateBlockRewards()
  │   ├─ inflation share = contractBlockGas / MaxGas * InflationRewards
  │   └─ fee rebate share = contractTxGas / totalTxGas * TxRewards.FeeRewards
  │
  ├─ createRewardsRecords()
  │   ├─ если metadata.WithdrawToWallet=false → RewardsRecord создан
  │   └─ если metadata.WithdrawToWallet=true → SendCoinsFromModuleToAccount
  │
  ├─ cleanupRewardsPool()
  │   └─ остатки (rounding dust) → TreasuryCollector
  │
  └─ cleanupTracking(H) → удаляет данные за H-10
     │
[EndBlocker: x/callback]
  IterateCallbacksByHeight(H):
  └─ для каждого callback:
      ├─ ExecuteWithGasLimit(MaxGasLimit, Sudo(contract, callbackMsg))
      ├─ success → refund unused txFees → ReservedBy
      ├─ failure → SetError(cwerrors); gasUsed = MaxGasLimit
      └─ SendToFeeCollector(reservationFees + surplusFees + usedTxFees)
     │
[EndBlocker: x/cwerrors]
  ├─ IterateSudoErrorCallbacks() → Sudo(contract, errorMsg)
  ├─ PruneSubscriptionsEndBlock()
  └─ PruneErrorsCurrentBlock()
     │
[MsgWithdrawRewards (любое время)]
  └─ WithdrawRewardsByRecordsLimit / ByRecordIDs
      ├─ проверяет record.RewardsAddress == caller
      └─ SendCoinsFromModuleToAccount(ContractRewardCollector, rewardsAddr, amount)
```

---

## Archway-specific изменения vs стандартный Cosmos SDK / wasmd

### Custom ante handlers

```go
// Archway добавляет в ante chain:
TxGasTrackingDecorator  // x/tracking — создаёт TxInfo
MinFeeDecorator         // x/rewards — проверяет min fee + flat fees
DeductFeeDecorator      // x/rewards — custom fee split (заменяет стандартный)
// Стандартный DeductFeeDecorator заменён полностью
```

### Custom gas meter / gas processor

```go
// x/tracking реализует wasmTypes.ContractGasProcessor interface:
IngestGasRecord()         // перехватывает все gas records из wasmd
GetGasCalculationFn()     // no-op (не меняет gas values)
CalculateUpdatedGas()     // no-op
```

### Custom wasm integration

```go
// app/keepers/keepers.go:
trackingWasmVm.SetGasRecorder(app.Keepers.TrackingKeeper)
// ↑ Все gas records от wasmd перенаправляются в x/tracking
```

### Modified keepers

- `x/rewards/mintbankkeeper/keeper.go` — обёртка для bank keeper с поддержкой mint (inflation rewards)
- `x/gov/keeper.go` — custom governance keeper

---

## Потенциальные edge cases по модулям

### x/rewards

| Edge case | Файл | Описание |
|-----------|------|---------|
| `WithdrawToWallet` panic | `distribution.go:createRewardsRecords` | panic если SendCoins fails в EndBlocker → chain halt |
| Double rewards via flat fee + rebate | `ante/fee_deduction.go` + `distribution.go` | flat fee даёт прямой RewardsRecord; rebate даёт отдельный; нет double count — но нужна проверка |
| Zero InflationRewardsRatio | `types/params.go` | allowed (= 0 в диапазоне); не validation error |
| MaxWithdrawRecords = 0 | `types/params.go` | отклонится validation (должно be ≥ 1) |
| Rewards после admin change | `keeper/metadata.go` | metadata.OwnerAddress меняется → новый owner получает rewards старого периода |
| Zero rewards record | `keeper/withdraw.go` | withdrawRewardsByRecords не паникует на zero records |

### x/tracking

| Edge case | Файл | Описание |
|-----------|------|---------|
| Query gas в rewards | `gas_processor.go` | `CONTRACT_OPERATION_QUERY` eligible для rewards — см. F-02 |
| Callback gas orphaned | `keeper.go` + EndBlocker order | ContractOpInfo пишется после FinalizeBlockTxTracking — не влияет на rewards, но занимает store |
| Failed tx tracking | `state_tx_info.go` | TxInfo persists, ContractOpInfo rollback → fee rebate в treasury |
| Empty block + callbacks | `state_tx_info.go:GetCurrentTxID` | в empty block GetCurrentTxID() = последний ID из прошлого → callback gas = orphaned с чужим txID |

### x/callback

| Edge case | Файл | Описание |
|-----------|------|---------|
| **Refund theft (F-01)** | `msg_server.go:CancelCallback` | refund → request.Sender ≠ callback.ReservedBy |
| MaxBlockReservationLimit validation | `types/params.go` | нет проверки на > 0; MaxBlockReservationLimit = 0 → нельзя регистрировать callbacks |
| Out-of-gas в callback | `abci.go` | gasUsed = MaxGasLimit; полный txFee не refundится → корректно |
| Callback gas limit snapshot | `keeper/callback.go:SaveCallback` | сохраняется при регистрации; если governance уменьшит лимит — старые callbacks используют старый (более высокий) |
| panic в SendToFeeCollector | `abci.go` | panic при ошибке bank send в EndBlocker → chain halt |

### x/cwfees

| Edge case | Файл | Описание |
|-----------|------|---------|
| Sudo commit в ante | `keeper.go:RequestGrant` | если sudo успешен, изменения стора коммитятся в ante cache; если tx потом fails — rollback |
| Gas cap для RequestGrant | `keeper.go` | 100_000 gas; если контракт потребляет больше — out-of-gas error, tx fails |
| `fallthrough` nil pointer (F-04) | `ante/fee_deduction.go` | cwFeesKeeper != nil + feegrantKeeper == nil → panic (теоретически) |

### x/cwica

| Edge case | Файл | Описание |
|-----------|------|---------|
| Sudo error swallowed | `keeper/ibc_handlers.go` | HandleChanOpenAck/HandleAcknowledgement: ошибка sudo логируется, не возвращается |
| Timeout → channel close | `keeper/ibc_handlers.go` | ORDERED ICA channel; один timeout → закрытие; нужна переregистрация ICA |
| Нет auth на msg level | `keeper/msg_server.go` | GetSigners = [ContractAddress] → только сам контракт; защищено |

### x/cwerrors

| Edge case | Файл | Описание |
|-----------|------|---------|
| Повторный error callback | `abci.go` | failed sudo → StoreErrorInState; НЕ в transient store → нет infinite loop |
| ErrorStoredTime = 0 | `types/params.go` | validation reject (> 0) |
| SubscriptionFee изменена governance | `keeper/subscriptions.go` | существующие подписки не пересчитываются; только новые подписки используют новый fee |

---

## Suggested Next Prompts to Run

### PROMPT 1 — x/rewards глубокий аудит
**Фокус:** `distribution.go`, `withdraw.go`, `metadata.go`, `flat_fee.go`
**Вопросы:**
- Точный механизм rounding в `estimateBlockRewards` — может ли кто-то получить > своей доли?
- `WithdrawToWallet` flow: когда и как могут не совпадать балансы?
- Invariant `ModuleAccountBalanceInvariant` — что он НЕ покрывает?
- После смены metadata owner — получает ли новый owner pending rewards?

### PROMPT 2 — x/tracking gas accounting аудит
**Фокус:** `gas_processor.go`, `distribution.go:estimateBlockGasUsage`
**Вопросы:**
- Query operations в rewards — intentional? Exploit path?
- Могут ли nested contract calls искусственно завысить газ одного контракта?
- Как обрабатываются submessage failures?
- Могут ли callbacks в EndBlocker приводить к неверной газовой атрибуции?

### PROMPT 3 — x/callback полный аудит
**Фокус:** `msg_server.go`, `abci.go`, `keeper/fees.go`
**Вопросы:**
- F-01 верификация через unit test
- Что происходит при panic внутри callback (не gas)?
- Могут ли `BlockReservationFeeMultiplier = 0` и `FutureReservationFeeMultiplier = 0` создать экономически невыгодные условия?
- Можно ли зарегистрировать callback для контракта без metadata?

### PROMPT 4 — x/cwfees + DeductFeeDecorator аудит
**Фокус:** `cwfees/keeper.go`, `rewards/ante/fee_deduction.go`
**Вопросы:**
- Может ли контракт-granter через Sudo call манипулировать своим состоянием в ante context?
- `fallthrough` nil pointer — реален ли в production конфиге?
- Что происходит с flatFees при очень большом количестве контрактов в одной authz tx?

### PROMPT 5 — Upgrades / migrations / genesis аудит
**Фокус:** `app/upgrades/*/upgrades.go`, `x/rewards/migrations/v2/migrate.go`
**Вопросы:**
- Все ли state keys мигрируются при каждом upgrade?
- Проверяются ли инварианты post-migration?
- `genesis.go` — принимаются ли invalid states?
- Logging `latest` upgrade — что входит в RunMigrations?

### PROMPT 6 — x/cwica + x/cwerrors IBC аудит
**Фокус:** `cwica/keeper/ibc_handlers.go`, `cwerrors/keeper/sudo_errors.go`
**Вопросы:**
- Конкретные сценарии stuck state при swallowed sudo errors
- Что происходит с контрактом, который никогда не получает ack/timeout notification?
- Replay protection для ICA packets?
- Может ли контракт через cwerrors subscription вызвать DoS (газ на каждый блок)?

---

## Выводы PROMPT 0

**Наиболее критичные зоны для следующих проходов:**

1. **x/callback CancelCallback** — подтверждённый bug F-01 с прямым financial impact
2. **x/rewards distribution** — центральная логика с несколькими panic paths и rounding вопросами  
3. **x/tracking + gas attribution** — query gas в rewards; callback gas orphaned data
4. **x/cwfees RequestGrant** — state mutation в ante handler; gas cap logic
5. **Governance params** — несколько параметров могут неожиданно влиять на финансовое поведение системы

**Не тратить время на:**
- Стандартные Cosmos SDK модули (auth, bank, staking, etc.)
- wasmd базовая логика (если не изменена Archway)
- IBC base protocol
- `x/genmsg` — только genesis, минимальная attack surface
