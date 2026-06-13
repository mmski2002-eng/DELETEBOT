# Archway Network — Аудит Upgrades / Migrations / Genesis / Params
## PROMPT 5: Upgrade Safety, Genesis Validation, Parameter Security

**Дата:** 2026-06-03  
**Фокус:** Upgrade handlers, genesis validation, governance params, module accounts, invariants  
**Методология:** Статический анализ всех upgrade handlers, genesis validation, params boundaries  

---

## Содержание

1. [Сводная таблица](#сводная-таблица)
2. [G-01: Callback InitGenesis не восстанавливает callbacks — потеря средств](#g-01-callback-initgenesis-не-восстанавливает-callbacks--потеря-средств-high)
3. [G-02: Rewards migration handler закомментирован при ConsensusVersion=2](#g-02-rewards-migration-handler-закомментирован-при-consensusversion2-medium)
4. [G-03: Callback genesis нет проверки дублей](#g-03-callback-genesis-нет-проверки-дублей-low)
5. [C-01: ComputationalPriceOfGas denom mismatch (подтверждение)](#c-01-computationalpriceof​gas-denom-mismatch-critical)
6. [Полный анализ: Upgrade Handlers](#полный-анализ-upgrade-handlers)
7. [Полный анализ: Genesis Validation](#полный-анализ-genesis-validation)
8. [Полный анализ: Governance Params](#полный-анализ-governance-params)
9. [Полный анализ: Module Accounts](#полный-анализ-module-accounts)
10. [Полный анализ: Invariants](#полный-анализ-invariants)
11. [Топ-5 risky файлов](#топ-5-risky-файлов)
12. [Рекомендуемые инварианты](#рекомендуемые-инварианты)
13. [Тесты для добавления](#тесты-для-добавления)

---

## Сводная таблица

| ID | Название | Severity | Confidence | Статус |
|----|---------|----------|-----------|--------|
| G-01 | Callback InitGenesis игнорирует callbacks → locked funds | **High** | **High** | Confirmed |
| G-02 | Rewards migration handler закомментирован (ConsensusVersion=2) | Medium | High | Confirmed |
| G-03 | Callback genesis нет duplicate check | Low | High | Confirmed |
| C-01 | ComputationalPriceOfGas denom panic (ранее) | Critical | High | Confirmed |
| F-02 | TxRewards InitGenesis wrong key (ранее) | Low | High | Confirmed |
| F-05 | Genesis RewardsRecords no balance check (ранее) | Low | High | Confirmed |

---

## G-01: Callback InitGenesis не восстанавливает callbacks — потеря средств (High)

**Severity: High**  
**Confidence: High**  
**Статус: Confirmed**

### Затронутые файлы

- `x/callback/genesis.go` — `InitGenesis()` и `ExportGenesis()`

### Summary

`ExportGenesis` экспортирует все pending callbacks в genesis state. `InitGenesis` НЕ восстанавливает их — только загружает params. При перезапуске цепочки через genesis export/import все pending callbacks теряются, а средства навсегда блокируются в module account.

### Technical details

```go
// x/callback/genesis.go — ExportGenesis ЭКСПОРТИРУЕТ callbacks:
func ExportGenesis(ctx sdk.Context, k keeper.Keeper) *types.GenesisState {
    params, _ := k.Params.Get(ctx)
    callbacks, _ := k.GetAllCallbacks(ctx)       // ← callbacks ВКЛЮЧЕНЫ
    return types.NewGenesisState(params, callbacks)  // ← в genesis state
}

// x/callback/genesis.go — InitGenesis ИГНОРИРУЕТ callbacks:
func InitGenesis(ctx sdk.Context, k keeper.Keeper, genState types.GenesisState) {
    params := genState.Params
    err := k.Params.Set(ctx, params)
    if err != nil {
        panic(err)
    }
    // genState.Callbacks = [callback1, callback2, ...] — ИГНОРИРУЕТСЯ!
    // Нет: k.Callbacks.Set(...) для каждого callback
}
```

### Последствия

```
Сценарий: Chain upgrade / genesis export-import

Состояние ДО:
  CallbackModule account balance: 1000 ARCH
  Pending callbacks:
    - callback_A (height=H+100, reservedBy=Alice, fees=500 ARCH)
    - callback_B (height=H+200, reservedBy=Bob, fees=500 ARCH)

Шаг 1: ExportGenesis
  genesis.json содержит callbacks = [callback_A, callback_B]

Шаг 2: InitGenesis с экспортированным genesis
  k.Params.Set(params) — OK
  genState.Callbacks = [callback_A, callback_B] — ИГНОРИРУЕТСЯ

Состояние ПОСЛЕ:
  CallbackModule account balance: 1000 ARCH (сохранён из bank state)
  Pending callbacks: [] (пусто — не восстановлены)

Результат:
  - Alice и Bob потеряли callbacks
  - Fees (1000 ARCH) заблокированы в module account навсегда
  - Нет механизма возврата (module account не имеет Burner permission, нет доступа)
```

### Attack preconditions

- Не требует атаки — проявляется при любом genesis export/import
- Типичные сценарии: chain upgrade, chain halt с перезапуском, тестовая миграция
- Пользователи, зарегистрировавшие callbacks до upgrade, теряют средства

### Impact

- Постоянная блокировка средств в callback module account
- Сумма потерь = Σ(fees) всех pending callbacks на момент genesis export
- При частых upgrades и активном использовании callbacks: значительные потери

### Proof of concept

```go
func TestCallbackGenesisRoundtrip_CallbacksPreserved(t *testing.T) {
    // Setup: register callbacks
    keeper, ctx := testutils.CallbackKeeper(t)
    contractAddr := genContractAddr()
    
    // Зарегистрировать callback
    callback := types.NewCallback(
        contractAddr.String(), contractAddr.String(), 
        ctx.BlockHeight()+10, 1,
        sdk.NewInt64Coin("stake", 100), sdk.ZeroInt64Coin("stake"),
        sdk.ZeroInt64Coin("stake"), sdk.ZeroInt64Coin("stake"),
    )
    keeper.Callbacks.Set(ctx, key, callback)
    
    // Export
    genState := ExportGenesis(ctx, keeper)
    require.Len(t, genState.Callbacks, 1)
    
    // Fresh keeper
    keeper2, ctx2 := testutils.CallbackKeeper(t)
    InitGenesis(ctx2, keeper2, *genState)
    
    // Verify callback was restored
    callbacks, _ := keeper2.GetAllCallbacks(ctx2)
    require.Len(t, callbacks, 1)  // FAILS — callbacks is empty!
}
```

### Counterarguments

- Возможно, намеренно: callbacks не должны переживать upgrades
- Но `ExportGenesis` явно включает их → design intent = восстановление
- `types.GenesisState.Callbacks` поле существует именно для этого

### Suggested fix

```go
// x/callback/genesis.go — InitGenesis
func InitGenesis(ctx sdk.Context, k keeper.Keeper, genState types.GenesisState) {
    params := genState.Params
    err := k.Params.Set(ctx, params)
    if err != nil {
        panic(err)
    }
    
    // ДОБАВИТЬ: восстановить callbacks из genesis state
    for _, callback := range genState.GetCallbacks() {
        contractAddr, err := sdk.AccAddressFromBech32(callback.ContractAddress)
        if err != nil {
            panic(fmt.Errorf("invalid callback contract address: %w", err))
        }
        key := collections.Join3(callback.CallbackHeight, contractAddr.Bytes(), callback.JobId)
        if err := k.Callbacks.Set(ctx, key, *callback); err != nil {
            panic(fmt.Errorf("failed to set callback: %w", err))
        }
    }
}
```

---

## G-02: Rewards migration handler закомментирован при ConsensusVersion=2 (Medium)

**Severity: Medium**  
**Confidence: High**  
**Статус: Confirmed**

### Затронутые файлы

- `x/rewards/module.go` — `RegisterServices()`
- `x/rewards/keeper/migrations.go` — `Migrate1to2()`

### Summary

`ConsensusVersion = 2` для модуля rewards, но handler миграции 1→2 закомментирован как в `RegisterServices`, так и в `Migrator`. Если любая цепочка попытается выполнить upgrade с rewards на версии 1, `RunMigrations` завершится ошибкой, прерывая upgrade.

### Technical details

```go
// x/rewards/module.go
const ConsensusVersion = 2  // ← Объявляет версию 2

func (a AppModule) RegisterServices(cfg module.Configurator) {
    types.RegisterQueryServer(cfg.QueryServer(), ...)
    types.RegisterMsgServer(cfg.MsgServer(), ...)

    // ЗАКОММЕНТИРОВАНО:
    // m := keeper.NewMigrator(a.keeper)
    // if err := cfg.RegisterMigration(types.ModuleName, 1, m.Migrate1to2); err != nil {
    //     panic(fmt.Sprintf("failed to migrate x/%s from version 1 to 2: %v", types.ModuleName, err))
    // }
}

// x/rewards/keeper/migrations.go
// ЗАКОММЕНТИРОВАНО:
// func (m Migrator) Migrate1to2(ctx sdk.Context) error {
//     return v2.MigrateStore(ctx, m.keeper.storeKey, m.keeper.paramStore, m.keeper.cdc)
// }
```

Файл миграции `x/rewards/migrations/v2/migrate.go` содержит реальную логику, но недоступен через зарегистрированный handler.

### Когда это проявляется

```
Проблема: chain с rewards на version 1 пытается upgrade
  RunMigrations(ctx, cfg, fromVM={rewards: 1, ...})
  → Для rewards: fromVersion=1, toVersion=2
  → Ищет handler migrations[rewards][1] → НЕ НАЙДЕН
  → Возвращает ошибку
  → Upgrade handler возвращает error
  → Upgrade fails → chain panic on upgrade height

Безопасно: chain с rewards уже на version 2
  RunMigrations(ctx, cfg, fromVM={rewards: 2, ...})
  → fromVersion=2 == toVersion=2 → пропускает
  → OK

Безопасно: новый genesis
  → InitGenesis не использует миграции
  → OK
```

### Практический риск

На Archway mainnet/testnet rewards уже на v2 (после v6/v7 upgrade). Текущие цепочки безопасны. Риск проявляется при:
- Разворачивании нового testnet из старого snapshot
- Форк, воспроизводящий старую историю
- Новая цепочка, стартующая с genesis от старого кода

### Suggested fix

**Вариант A:** Раскомментировать migration handler (правильно если цепочки с v1 ещё существуют):

```go
// x/rewards/module.go
func (a AppModule) RegisterServices(cfg module.Configurator) {
    types.RegisterQueryServer(cfg.QueryServer(), keeper.NewQueryServer(a.keeper))
    types.RegisterMsgServer(cfg.MsgServer(), keeper.NewMsgServer(a.keeper))
    
    m := keeper.NewMigrator(a.keeper)
    if err := cfg.RegisterMigration(types.ModuleName, 1, m.Migrate1to2); err != nil {
        panic(fmt.Sprintf("failed to migrate x/%s from version 1 to 2: %v", types.ModuleName, err))
    }
}

// x/rewards/keeper/migrations.go
func (m Migrator) Migrate1to2(ctx sdk.Context) error {
    return v2.MigrateStore(ctx, m.keeper.storeKey, m.keeper.paramStore, m.keeper.cdc)
}
```

**Вариант B:** Если v1 chains не существуют — снизить ConsensusVersion до 1 или задокументировать что migration не нужна.

---

## G-03: Callback genesis нет проверки дублей (Low)

**Severity: Low**  
**Confidence: High**  
**Статус: Confirmed**

### Затронутые файлы

- `x/callback/types/genesis.go` — `GenesisState.Validate()`

### Summary

Callback genesis validation проверяет каждый callback индивидуально, но не проверяет дубли по composite key `(height, contractAddress, jobId)`. Если genesis содержит два callback'а с идентичным ключом, второй молча перезаписывает первый.

### Technical details

```go
// x/callback/types/genesis.go
func (g GenesisState) Validate() error {
    if err := g.Params.Validate(); err != nil {
        return err
    }
    for _, callback := range g.GetCallbacks() {
        if err := callback.Validate(); err != nil {
            return err
        }
        // НЕТ проверки уникальности (height, contractAddress, jobId)
    }
    return nil
}
```

В InitGenesis (когда будет исправлен G-01) — `Callbacks.Set(key, callback)` перезаписывает существующий callback.

### Impact

- Тихая потеря одного из двух дублирующихся callbacks
- Fees, заплаченные за overwritten callback, теряются
- Затрагивает только genesis state (не runtime регистрацию, которая проверяет дубли)

### Suggested fix

```go
func (g GenesisState) Validate() error {
    if err := g.Params.Validate(); err != nil {
        return err
    }
    
    // Добавить проверку уникальности
    keySet := make(map[string]struct{})
    for i, callback := range g.GetCallbacks() {
        if err := callback.Validate(); err != nil {
            return fmt.Errorf("callback[%d]: %w", i, err)
        }
        key := fmt.Sprintf("%d_%s_%d", 
            callback.CallbackHeight, callback.ContractAddress, callback.JobId)
        if _, ok := keySet[key]; ok {
            return fmt.Errorf("callback[%d]: duplicate key (height=%d, contract=%s, jobId=%d)",
                i, callback.CallbackHeight, callback.ContractAddress, callback.JobId)
        }
        keySet[key] = struct{}{}
    }
    return nil
}
```

---

## C-01: ComputationalPriceOfGas denom mismatch (Critical)

*(Полное описание в `archway_callbacks_cwfees_cwica_audit.md`)*

Краткое резюме для этого отчёта:

- **Params**: `MinPriceOfGas` (governance) — любой denom
- **Inflation**: `MinConsensusFee` — inflation denom (обычно "aarch")
- **Impact**: если denoms расходятся → panic в AnteHandler + EndBlocker → chain halt
- **Fix**: Убрать panic из `ComputationalPriceOfGas`; добавить validation в `UpdateParams`

---

## Полный анализ: Upgrade Handlers

### История upgrades и Archway-specific изменения

| Версия | Стор-изменения | Archway-specific |
|--------|---------------|-----------------|
| v0.6.0 | — | Ранние rewards params |
| v2.0.0 | — | — |
| v3.0.0 | — | — |
| v4.0.0 | — | — |
| v4.0.2 | — | — |
| v6.0.0 | +crisis, +consensus, +group, +nft | Params subspace migration (rewards→own store) |
| v7.0.0 | +callback, +cwfees, +cwerrors, +cwica, +icacontroller | Default params setup для новых модулей |
| v9.0.0 | +ibchooks | — |
| v10.0.0 | — | RunMigrations only |
| latest | — | RunMigrations only |

### v7.0.0 — Critical parameters установленные при upgrade

```go
// app/upgrades/7_0_0/upgrades.go
callbackParams.CallbackGasLimit = 150000
callbackParams.MaxBlockReservationLimit = 10
callbackParams.MaxFutureReservationLimit = 432000 // ~30 days
callbackParams.BlockReservationFeeMultiplier = "0.0"    // ← ZERO!
callbackParams.FutureReservationFeeMultiplier = "1000000000000.0"  // 1e12

cwerrorsParams.ErrorStoredTime = 302400               // ~21 days
cwerrorsParams.SubscriptionFee = "1000000000000000000 aarch"  // 1 ARCH
cwerrorsParams.SubscriptionPeriod = 302400

cwicaParams.MsgSendTxMaxMessages = 5
```

**BlockReservationFeeMultiplier = 0:** Congestion pricing для слотов в одном блоке отключена. Все 10 слотов бесплатны (относительно) → нет ценового преимущества у ранних регистраторов. Только `FutureReservationFee` растёт с расстоянием.

**FutureReservationFeeMultiplier = 1e12:** Fee = `1e12 * distance_in_blocks`. При ARCH ~0.00001, 1 блок = 1e12 aarch = 0.000001 ARCH = ~0.0000001 USD. Незначительная стоимость для близких callbacks. Это design intent.

### Все последние upgrades — только RunMigrations

Начиная с v9.0.0, все upgrades выполняют только `RunMigrations` без дополнительной бизнес-логики. Это означает:
- Миграции управляются консенсусными версиями модулей
- Нет ручной инициализации params → безопасно
- Новых потенциальных проблем от upgrade logic нет

---

## Полный анализ: Genesis Validation

### Сводка по всем модулям

| Модуль | Проверяет дубли | Проверяет балансы | Проверяет addresses | Completeness |
|--------|----------------|------------------|---------------------|-------------|
| `x/rewards` | ✓ (contractAddr, blockH, txId, recordId) | ✗ | ✓ | Частично |
| `x/tracking` | ✓ (txId, opId) | n/a | ✓ (contractAddr) | Хорошо |
| `x/callback` | ✗ | ✗ | ✓ (per callback) | **Слабо** |
| `x/cwfees` | n/a | n/a | ✓ (grantors) | OK |
| `x/cwica` | n/a | n/a | n/a | Params only |
| `x/cwerrors` | n/a | n/a | n/a | Params only |

### x/rewards GenesisState.Validate() детали

**Проверяет:**
- ✓ ContractMetadata: нет дублей по contractAddr
- ✓ BlockRewards: нет дублей по height
- ✓ TxRewards: нет дублей по txId; height ∈ BlockRewards heights
- ✓ RewardsRecords: нет дублей по Id; LastId ≥ max(Id)
- ✓ FlatFees: нет дублей; contractAddr ∈ ContractMetadata

**НЕ проверяет:**
- ✗ Σ(RewardsRecords.Rewards) ≤ ContractRewardCollector.Balance
- ✗ TxRewards.TxId согласован с реальными TxInfo (разные модули)

### x/tracking GenesisState.Validate() детали

**Проверяет:**
- ✓ TxInfos: нет дублей по Id; LastId ≥ max(Id)
- ✓ ContractOpInfos: нет дублей по Id; TxId ∈ TxInfos; LastId ≥ max(Id)

**Слабость:** ContractOpInfos валидируются только против TxInfos IN SAME genesis. Если TxInfo был экспортирован отдельно или сброшен, cross-module consistency не проверяется.

### InitGenesis ordering важность

В InitGenesis порядке (из app.go):
```
rewards → ... → wasm → ... → tracking → callback → cwerrors → cwica
```

**rewards ПЕРЕД wasm:** Metadata для контрактов загружается ДО деплоя самих контрактов. При `GetContractInfo(ctx, contractAddr)` в BeginBlock сразу после genesis — контракт уже существует (wasm инициализирован раньше из-за порядка, но rewards.InitGenesis запускается РАНЬШЕ wasm.InitGenesis).

На самом деле нет — `SetContractMetadata` в InitGenesis не проверяет существование контракта:
```go
for _, contractMetadata := range state.ContractsMetadata {
    err := k.ContractMetadata.Set(ctx, contractMetadata.MustGetContractAddress(), contractMetadata)
    // Нет проверки HasContractInfo!
}
```

Это означает: в genesis можно задать metadata для несуществующих контрактов. Когда они будут задеплоены — metadata уже будет ждать. Это может быть intentional для pre-deploying configuration.

---

## Полный анализ: Governance Params

### Полная таблица governance params с risk assessment

#### x/rewards Params

| Параметр | Default | Boundaries | Risk at Edge |
|----------|---------|-----------|-------------|
| `InflationRewardsRatio` | 0.20 | [0, 1.0) | `=0`: inflation отключена; `→1.0`: validator rewards исчезают |
| `TxFeeRebateRatio` | 0.50 | [0, 1.0) | `=0`: fee rebate отключен; `→1.0`: все fees → rewards, zero burn |
| `MaxWithdrawRecords` | 25000 | [1, 25000] | Validation enforced |
| `MinPriceOfGas` | 0 stake | ≥0, valid DecCoin | **CRITICAL: неправильный denom → chain halt (C-01)** |

#### x/callback Params

| Параметр | Установлен в v7 | Validation | Risk |
|----------|----------------|-----------|------|
| `CallbackGasLimit` | 150000 | > 0 | Huge value → high gas consumption in EndBlocker |
| `MaxBlockReservationLimit` | 10 | НЕТ (> 0) | `=0` → невозможно регистрировать callbacks |
| `MaxFutureReservationLimit` | 432000 | НЕТ | `=0` → невозможно регистрировать callbacks |
| `BlockReservationFeeMultiplier` | 0.0 | ≥ 0 | `=0` текущее значение (no congestion pricing) |
| `FutureReservationFeeMultiplier` | 1e12 | ≥ 0 | Огромное значение → callbacks очень дорогие |

**Важно:** `MaxBlockReservationLimit` и `MaxFutureReservationLimit` не проверяются на > 0. Governance может установить их в 0, блокируя регистрацию.

#### x/cwerrors Params

| Параметр | Default | Validation | Risk |
|----------|---------|-----------|------|
| `ErrorStoredTime` | 302400 | > 0 | Маленькое → errors быстро удаляются |
| `SubscriptionFee` | 1 ARCH | valid coin | Huge → подписка невозможна |
| `SubscriptionPeriod` | 302400 | > 0 | Маленькое → частые re-subscribe |

#### x/cwica Params

| Параметр | Default | Validation | Risk |
|----------|---------|-----------|------|
| `MsgSendTxMaxMessages` | 5 | > 0 | `=1` → ограниченная функциональность |

### Governance attack vectors

**Наиболее опасные:**

1. `MinPriceOfGas` с неправильным denom → chain halt (C-01)
2. `MaxBlockReservationLimit = 0` → блокировка callback registration
3. `InflationRewardsRatio → 1.0` → validators receive near-zero staking rewards
4. `CallbackGasLimit = MaxUint64` → integer overflow в gas accounting

---

## Полный анализ: Module Accounts

### Полный список и permissions

```go
// app/app.go
maccPerms = map[string][]string{
    rewardsTypes.ContractRewardCollector: nil,          // банковские операции
    rewardsTypes.TreasuryCollector:       {Burner},     // может сжигать
    authtypes.FeeCollectorName:           {Burner},     // сжигает auth fees
    minttypes.ModuleName:                 {Minter},     // создаёт inflation
    distrtypes.ModuleName:                nil,
    stakingtypes.BondedPoolName:          {Burner, Staking},
    stakingtypes.NotBondedPoolName:       {Burner, Staking},
    govtypes.ModuleName:                  {Burner},
    nft.ModuleName:                       nil,
    ibctransfertypes.ModuleName:          {Minter, Burner},
    ibcfeetypes.ModuleName:               nil,
    icatypes.ModuleName:                  nil,
    wasmdTypes.ModuleName:                {Burner},
    callbackTypes.ModuleName:             nil,          // банковские операции
}
```

**BlockedAddresses** = все из `maccPerms` (module accounts) → пользователи не могут отправить монеты на модульные счета напрямую.

### Анализ module account security

| Счёт | Permissions | Риски |
|------|-------------|-------|
| `ContractRewardCollector` | nil | Правильно: только bank ops. Нет лишних permissions. |
| `TreasuryCollector` | Burner | Может сжигать. Только получает leftovers → OK |
| `FeeCollectorName` | Burner | Сжигает auth fees. Правильно. |
| `callbackTypes.ModuleName` | nil | Только bank ops. Нет Burner. **Locked funds from G-01 не сжигаются** |
| `minttypes.ModuleName` | Minter | Только минтинг. Не может сжигать → OK |

**callback module account (nil permissions):** Важно для G-01. Если callbacks потеряны после genesis import, средства на callback module account не могут быть сожжены (нет Burner). Они остаются заблокированными навсегда.

### Можно ли отправить rewards на module account?

```go
// x/rewards/keeper/metadata.go
if k.isBlockedAddress(addr) {
    return types.ErrInvalidRequest.Wrap("rewards address cannot be a blocked address")
}
```

✓ Нет — blocked address check предотвращает это.

### Согласованность bank balances

Инвариант `ModuleAccountBalanceInvariant` проверяет:
```
ContractRewardCollector.Balance == Σ(RewardsRecords.Rewards)
```

**Не покрывает:**
- Flat fee records (создаются напрямую в MinFeeDecorator, не в EndBlocker)
- WithdrawToWallet flow (монеты уходят без RewardsRecord)
- Callback module account vs pending callbacks

---

## Полный анализ: Invariants

### Существующие инварианты

| Модуль | Инвариант | Файл | Тесты |
|--------|----------|------|-------|
| x/rewards | `ModuleAccountBalanceInvariant` | `keeper/invariants.go` | `keeper/invariants_test.go` ✓ |

`TestRewardsModuleAccountInvariant` содержит 6 тест-кейсов (АКТИВНЫ, не закомментированы).

**Что проверяет:** `ContractRewardCollector.Balance == Σ(RewardsRecords.Rewards)`

**Что НЕ проверяет:**
1. Flat fee coins (contributed to pool, but pre-credited to records)
2. CallbackModule.Balance vs Σ(callbacks.fees)
3. TxRewards existence vs actual txs
4. Orphaned callbacks (G-01 scenario)

### Регистрация инвариантов

```go
// x/rewards/module.go
func (a AppModule) RegisterInvariants(ir sdk.InvariantRegistry) {
    keeper.RegisterInvariants(ir, a.keeper)
}
```

Инварианты регистрируются и выполняются crisis module в EndBlocker. ✓

---

## Топ-5 risky файлов

| # | Файл | Риск | Обоснование |
|---|------|------|-------------|
| 1 | `x/callback/genesis.go` | **High** | G-01: InitGenesis игнорирует callbacks → locked funds |
| 2 | `x/rewards/keeper/min_cons_fee.go` | **Critical** | C-01: denom mismatch panic → chain halt |
| 3 | `x/rewards/module.go` | Medium | G-02: migration handler закомментирован при ConsensusVersion=2 |
| 4 | `x/rewards/keeper/genesis.go` | Low | F-02: TxRewards stored by wrong key; F-05: no balance check |
| 5 | `x/callback/types/genesis.go` | Low | G-03: нет duplicate check для callbacks |

---

## Рекомендуемые инварианты

### 1. Callback Module Balance Invariant

```go
// x/callback/keeper/invariants.go (новый файл)
func CallbackModuleBalanceInvariant(k Keeper) sdk.Invariant {
    return func(ctx sdk.Context) (string, bool) {
        // Проверить: Σ(callback.fees) == CallbackModule.Balance
        allCallbacks, _ := k.GetAllCallbacks(ctx)
        
        expectedBalance := sdk.ZeroInt()
        denom := ""
        for _, cb := range allCallbacks {
            if cb.FeeSplit != nil {
                // TransactionFees + BlockReservationFees + FutureReservationFees + SurplusFees
                total := cb.FeeSplit.TransactionFees.Amount.
                    Add(cb.FeeSplit.BlockReservationFees.Amount).
                    Add(cb.FeeSplit.FutureReservationFees.Amount).
                    Add(cb.FeeSplit.SurplusFees.Amount)
                expectedBalance = expectedBalance.Add(total)
                if denom == "" { denom = cb.FeeSplit.TransactionFees.Denom }
            }
        }
        
        moduleBalance := k.bankKeeper.GetAllBalances(ctx, 
            authTypes.NewModuleAddress(types.ModuleName))
        // Compare...
        broken := !expectedBalance.Equal(moduleBalance.AmountOf(denom))
        return sdk.FormatInvariant(...), broken
    }
}
```

### 2. TxRewards Key Correctness Invariant

```go
// x/rewards/keeper/invariants.go
func TxRewardsKeyInvariant(k Keeper) sdk.Invariant {
    return func(ctx sdk.Context) (string, bool) {
        // Каждый TxRewards должен быть доступен по своему TxId
        var broken bool
        k.TxRewards.Walk(ctx, nil, func(key uint64, value types.TxRewards) (bool, error) {
            if key != value.TxId {
                broken = true
                return true, nil
            }
            return false, nil
        })
        return sdk.FormatInvariant(...), broken
    }
}
```

### 3. FlatFees Metadata Consistency Invariant

```go
// x/rewards/keeper/invariants.go
func FlatFeeMetadataInvariant(k Keeper) sdk.Invariant {
    return func(ctx sdk.Context) (string, bool) {
        // Каждый FlatFee должен ссылаться на контракт с metadata
        broken := false
        k.FlatFees.Walk(ctx, nil, func(key []byte, value sdk.Coin) (bool, error) {
            meta := k.GetContractMetadata(ctx, sdk.AccAddress(key))
            if meta == nil {
                broken = true
                return true, nil
            }
            if meta.RewardsAddress == "" {
                broken = true
                return true, nil
            }
            return false, nil
        })
        return sdk.FormatInvariant(...), broken
    }
}
```

---

## Тесты для добавления

### Критично (G-01)

```go
// x/callback/genesis_test.go
func TestInitGenesis_CallbacksRestored(t *testing.T) {
    // Создать callbacks в state
    // ExportGenesis → получить genState с callbacks
    // InitGenesis на новом keeper
    // Verify: callbacks в новом state совпадают с экспортированными
    
    // Текущий результат: FAIL (callbacks not restored)
    // Ожидаемый результат после фикса: PASS
}

func TestGenesisRoundtrip_CallbackModuleBalance_Preserved(t *testing.T) {
    // Register callbacks + pay fees
    // Export genesis
    // Fresh init from genesis
    // Verify: module balance == Σ(callback fees in state)
}
```

### Migration safety (G-02)

```go
func TestRewards_Migration1to2_RestoresParams(t *testing.T) {
    // Simulate state from v1 (params in x/params subspace)
    // Run Migrate1to2
    // Verify: params accessible from x/rewards direct store
    
    // Requires: uncomment migration handler
}

func TestRewards_ConsensusVersion_MigrationHandlerRegistered(t *testing.T) {
    // Verify migration handler exists for each ConsensusVersion step
    // ConsensusVersion=2 → handler for 1→2 must exist
}
```

### Genesis validation (G-03)

```go
func TestCallbackGenesis_DuplicateKey_Rejected(t *testing.T) {
    // Two callbacks with same (height, contract, jobId)
    // Validate() should return error
}

func TestCallbackGenesis_DifferentJobIds_Accepted(t *testing.T) {
    // Two callbacks with same (height, contract) but different jobIds
    // Validate() should pass
}
```

### C-01 params safety

```go
func TestRewardsParams_MinPriceOfGas_DenomValidated(t *testing.T) {
    // Governance tries to set MinPriceOfGas with wrong denom
    // UpdateParams should reject or ComputationalPriceOfGas should not panic
}

func TestCallbackParams_MaxBlockReservationLimit_Zero_Handled(t *testing.T) {
    // MaxBlockReservationLimit = 0 via governance
    // SaveCallback should return ErrBlockFilled (not panic)
}

func TestCallbackParams_CallbackGasLimit_ExtremeValue_NoOverflow(t *testing.T) {
    // CallbackGasLimit = math.MaxUint64
    // EndBlocker should not overflow
}
```

---

## Confirmed Findings (этот аудит)

1. **G-01 (High):** `InitGenesis` x/callback игнорирует callbacks из genesis state → pending callbacks теряются при genesis import → fees навсегда заблокированы в module account.

2. **G-02 (Medium):** Rewards migration handler закомментирован при `ConsensusVersion = 2` → upgrade с v1 → ошибка `RunMigrations` → upgrade fail.

3. **G-03 (Low):** Callback genesis `Validate()` нет duplicate check по composite key → тихая потеря данных при ручном genesis.

## Weak Leads (закрыты)

- InitGenesis ordering conflict (rewards before wasm): metadata для несуществующих контрактов принимается — intentional design
- InflationRewardsRatio = 0.99: governance risk, не протокольный баг
- TreasuryCollector с Burner: только получает leftovers, нет избыточных permissions
- BlockedAddresses: все module accounts заблокированы → нет риска отправки rewards на них
- FlatFees в genesis без баланса: аналогично F-05, нет strict check, но не эксплуатируется в runtime

---

*Отчёт составлен для легального bug bounty. Эксплуатация mainnet не проводилась.*
