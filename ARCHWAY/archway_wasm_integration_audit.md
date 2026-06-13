# Archway Network — Аудит Custom Wasm Integration
## PROMPT 3: CosmWasm / wasmbinding Security Audit

**Дата:** 2026-06-03  
**Фокус:** Archway-specific wasm modifications, wasmbinding, gas processor wiring, authorization  
**Методология:** Статический анализ кода wasmbinding/, app/app.go, x/rewards keeper  

---

## Содержание

1. [Сводная таблица](#сводная-таблица)
2. [Archway-specific Wasm Modifications](#archway-specific-wasm-modifications)
3. [W-01: WithdrawToWallet молча сбрасывается через wasmbinding](#w-01-withdrawtowallet-молча-сбрасывается-через-wasmbinding-low)
4. [W-02: Wasmbinding тесты полностью закомментированы](#w-02-wasmbinding-тесты-полностью-закомментированы-high)
5. [Entrypoint Analysis](#entrypoint-analysis)
6. [Authorization Analysis](#authorization-analysis)
7. [State Consistency Analysis](#state-consistency-analysis)
8. [Edge Case Analysis](#edge-case-analysis)
9. [Слабые зацепки](#слабые-зацепки)
10. [Топ-5 high-risk файлов](#топ-5-high-risk-файлов)
11. [Тесты для добавления](#тесты-для-добавления)

---

## Сводная таблица

| ID | Название | Severity | Confidence | Статус |
|----|---------|----------|-----------|--------|
| W-01 | WithdrawToWallet молча сбрасывается через wasmbinding | Low | High | Confirmed |
| W-02 | Wasmbinding тесты полностью закомментированы | **High** | **High** | Confirmed |

---

## Archway-specific Wasm Modifications

### Полный список изменений vs стандартный wasmd

#### 1. Custom Gas Processor (x/tracking)

```go
// app/app.go
trackingWasmVm := wasmdTypes.NewTrackingWasmerEngine(wasmer, &wasmdTypes.NoOpContractGasProcessor{})
wasmOpts = append(wasmOpts, wasmdKeeper.WithWasmEngine(trackingWasmVm), ...)
// ... keepers initialized ...
trackingWasmVm.SetGasRecorder(app.Keepers.TrackingKeeper)  // ← wired AFTER init
```

Archway устанавливает кастомный `TrackingWasmerEngine` вместо стандартного. Сначала используется `NoOpContractGasProcessor`, затем заменяется на `TrackingKeeper.IngestGasRecord`. Разделение на двух-шаговую инициализацию необходимо для разрыва circular dependency (WASMKeeper → TrackingKeeper → WASMKeeper).

**Безопасность:** Между `NewTrackingWasmerEngine` и `SetGasRecorder` — только инициализация, не runtime. Gas recording не пропускается. ✓

#### 2. Custom Message Handler (wasmbinding)

```go
// wasmbinding/plugin.go
wasmKeeper.WithMessageHandlerDecorator(BuildWasmMsgDecorator(rKeeper))
```

Contracts могут dispatch custom messages:
- `UpdateContractMetadata` — обновление metadata контракта
- `WithdrawRewards` — получение rewards
- `SetFlatFee` — установка flat fee

#### 3. Custom Query Plugin (wasmbinding)

```go
wasmKeeper.WithQueryPlugins(BuildWasmQueryPlugin(rKeeper, govKeeper))
```

Contracts могут делать custom queries:
- `ContractMetadata` — запрос metadata контракта
- `RewardsRecords` — список rewards records
- `FlatFee` — запрос flat fee
- `GovVote` — запрос голосования

#### 4. Wasm bindings dispatch chain

```
Contract dispatches custom CosmosMsg
    ↓
MsgDispatcher.DispatchMsg()
    ↓ if msg.Custom != nil
    Parse JSON → types.Msg
    Validate() — ensures exactly one field set
    ↓ switch
    UpdateContractMetadata → rewards.MsgHandler.UpdateContractMetadata()
    WithdrawRewards        → rewards.MsgHandler.WithdrawContractRewards()
    SetFlatFee             → rewards.MsgHandler.SetFlatFee()
    ↓
    x/rewards keeper methods
```

#### 5. Контракты могут управлять rewards через стандартные CosmosMsg

Через стандартный wasm dispatch (не custom), contracts могут отправлять:
- `MsgSetContractMetadata` — стандартный tx msg
- `MsgWithdrawRewards`
- `MsgSetFlatFee`
- `MsgRegisterAsGranter` (cwfees)
- `MsgRegisterInterchainAccount` (cwica)
- `MsgSendTx` (cwica)

Все эти msgs используют `GetSigners() = [contractAddress]` → только контракт сам себя подписывает.

---

## W-01: WithdrawToWallet молча сбрасывается через wasmbinding (Low)

**Severity: Low**  
**Confidence: High**  
**Статус: Confirmed Bug**

### Затронутые файлы

- `wasmbinding/rewards/types/msg_metadata.go` — `ToSDK()`
- `x/rewards/keeper/metadata.go` — `SetContractMetadata()`

### Summary

`UpdateContractMetadataRequest.ToSDK()` не включает поле `WithdrawToWallet`. При вызове `UpdateContractMetadata` через wasmbinding, `SetContractMetadata` сравнивает `metaUpdates.WithdrawToWallet (false)` с `metaOld.WithdrawToWallet`, и если старое значение было `true` — сбрасывает его в `false`.

### Technical details

**Цепочка:**

```go
// 1. wasmbinding/rewards/types/msg_metadata.go — ToSDK()
func (r UpdateContractMetadataRequest) ToSDK() rewardsTypes.ContractMetadata {
    return rewardsTypes.ContractMetadata{
        OwnerAddress:   r.OwnerAddress,
        RewardsAddress: r.RewardsAddress,
        // WithdrawToWallet: НЕ ВКЛЮЧЕНО (defaults to false)
    }
}

// 2. wasmbinding/rewards/msg_handler.go — UpdateContractMetadata
h.rewardsKeeper.SetContractMetadata(ctx, senderAddr, contractAddr, req.ToSDK())
// req.ToSDK().WithdrawToWallet == false всегда

// 3. x/rewards/keeper/metadata.go — SetContractMetadata
if metaUpdates.WithdrawToWallet != metaOld.WithdrawToWallet {
    metaNew.WithdrawToWallet = metaUpdates.WithdrawToWallet
}
// Если metaOld.WithdrawToWallet == true:
//   false != true → metaNew.WithdrawToWallet = false ← СБРОС!
```

### Attack preconditions

- Не требует никаких специальных прав
- Контракт или его owner обновляет metadata через wasmbinding
- Контракт ранее имел `WithdrawToWallet = true` (установлено через стандартный MsgSetContractMetadata)

### Сценарий

```
1. Admin устанавливает WithdrawToWallet=true для контракта C через MsgSetContractMetadata
   → EndBlocker автоматически распределяет rewards прямо в кошелёк

2. Контракт C обновляет свой RewardsAddress через wasmbinding:
   { "update_contract_metadata": { "rewards_address": "new_addr" } }
   → ToSDK() возвращает { RewardsAddress: "new_addr", WithdrawToWallet: false }
   → SetContractMetadata сравнивает false != true → сбрасывает в false

3. Теперь rewards идут в RewardsRecords, а не в кошелёк
   → Пользователь должен вручную вызывать WithdrawRewards
   → Если не вызывает — rewards накапливаются в records
```

### Impact

- Не теряет средства (coins остаются в RewardsRecords)
- Меняет UX: пользователь должен ручно withdraw
- Неожиданное поведение для разработчика контракта

### PoC plan

```go
func TestUpdateMetadataViaWasmbinding_WithdrawToWallet_Reset(t *testing.T) {
    // Setup contract with WithdrawToWallet=true via MsgSetContractMetadata
    metadata := rewardsTypes.ContractMetadata{
        OwnerAddress:    contractAddr.String(),
        RewardsAddress:  rewardsAddr.String(),
        WithdrawToWallet: true,
    }
    require.NoError(t, keeper.SetContractMetadata(ctx, adminAddr, contractAddr, metadata))
    
    // Verify initial state
    meta := keeper.GetContractMetadata(ctx, contractAddr)
    require.True(t, meta.WithdrawToWallet)
    
    // Contract updates metadata via wasmbinding (only changing RewardsAddress)
    req := types.UpdateContractMetadataRequest{
        RewardsAddress: newRewardsAddr.String(),
    }
    handler := rewards.NewRewardsMsgHandler(keeper)
    _, _, err := handler.UpdateContractMetadata(ctx, contractAddr, req)
    require.NoError(t, err)
    
    // Check: WithdrawToWallet should still be true!
    meta = keeper.GetContractMetadata(ctx, contractAddr)
    // FAILS with current code — WithdrawToWallet was reset to false
    require.True(t, meta.WithdrawToWallet, "WithdrawToWallet must not be reset")
}
```

### Counterarguments

- Может быть намеренным ограничением: wasmbinding умышленно не предоставляет доступ к WithdrawToWallet
- Разработчик контракта должен знать что поле не поддерживается в wasmbinding
- Нет документации, подтверждающей design intent в одну или другую сторону

### Suggested fix

**Вариант A:** Добавить `WithdrawToWallet` в wasmbinding request и `ToSDK()`:

```go
// wasmbinding/rewards/types/msg_metadata.go
type UpdateContractMetadataRequest struct {
    ContractAddress  string `json:"contract_address"`
    OwnerAddress     string `json:"owner_address"`
    RewardsAddress   string `json:"rewards_address"`
    WithdrawToWallet *bool  `json:"withdraw_to_wallet"` // ← nullable pointer
}

func (r UpdateContractMetadataRequest) ToSDK() rewardsTypes.ContractMetadata {
    meta := rewardsTypes.ContractMetadata{
        OwnerAddress:   r.OwnerAddress,
        RewardsAddress: r.RewardsAddress,
    }
    if r.WithdrawToWallet != nil {
        meta.WithdrawToWallet = *r.WithdrawToWallet
    }
    return meta
}
```

**Вариант B:** Изменить `SetContractMetadata` чтобы не трогать WithdrawToWallet если он не явно указан:

```go
// x/rewards/keeper/metadata.go
// Только обновлять если metaUpdates явно устанавливает поле:
// Нужен sentinel/nullable approach, т.к. в proto bool не nullable
```

**Вариант A более надёжен.** Также нужно добавить тест:
```go
func TestUpdateMetadataViaWasmbinding_WithdrawToWallet_Preserved(t *testing.T) { ... }
```

---

## W-02: Wasmbinding тесты полностью закомментированы (High)

**Severity: High**  
**Confidence: High**  
**Статус: Confirmed**

### Затронутые файлы

- `wasmbinding/plugin_test.go` — **весь файл закомментирован**
- `wasmbinding/integration_test.go` — **весь файл закомментирован**

### Summary

Два тестовых файла для wasmbinding custom message handler и query plugin полностью закомментированы. Это продолжение паттерна T-01 из x/tracking аудита — системное отключение тестов для критической логики.

Закомментированные тесты включали:

**plugin_test.go:**
- `TestWASMBindingPlugins` — dispatch failure scenarios, metadata query, rewards query, gov vote query
- Тесты форматов запросов и ответов

**integration_test.go:**
- `TestGovQuerier` — полный e2e тест с реальным wasm контрактом

### Что теряется

| Тест | Покрытие |
|------|---------|
| Invalid JSON dispatch | Rejection path |
| UpdateContractMetadata dispatch | Core functionality |
| WithdrawRewards dispatch | Core functionality |
| SetFlatFee dispatch | Core functionality |
| Gov vote query | Integration with governance |
| End-to-end wasm→rewards flow | Full integration |

### Suggested fix

Раскомментировать или переписать тесты. Минимальный набор:

```go
func TestDispatchMsg_UpdateMetadata_Ok(t *testing.T) { ... }
func TestDispatchMsg_UpdateMetadata_Unauthorized(t *testing.T) { ... }
func TestDispatchMsg_WithdrawRewards_Ok(t *testing.T) { ... }
func TestDispatchMsg_SetFlatFee_Ok(t *testing.T) { ... }
func TestDispatchMsg_InvalidJSON_Rejected(t *testing.T) { ... }
func TestDispatchMsg_MultipleFields_Rejected(t *testing.T) { ... }
func TestQueryPlugin_ContractMetadata_Ok(t *testing.T) { ... }
func TestQueryPlugin_ContractMetadata_NotFound(t *testing.T) { ... }
func TestQueryPlugin_RewardsRecords_Empty(t *testing.T) { ... }
func TestQueryPlugin_GovVote_Ok(t *testing.T) { ... }
// W-01 specific:
func TestDispatchMsg_UpdateMetadata_WithdrawToWallet_Preserved(t *testing.T) { ... }
```

---

## Entrypoint Analysis

### Custom Wasm Messages

#### UpdateContractMetadata

```
Contract → DispatchMsg(contractAddr, msg.Custom) 
         → MsgDispatcher.DispatchMsg()
         → rewards.MsgHandler.UpdateContractMetadata(ctx, senderAddr=contractAddr, req)
         → SetContractMetadata(ctx, senderAddr, targetContract, metadata)
```

**Authorization:**
- `senderAddr` = вызывающий контракт (не подделать)
- Новый owner: нужно быть wasm admin целевого контракта
- Существующее изменение: нужно быть metadata owner

**Issues:**
- W-01: WithdrawToWallet сброс
- Нет expose ContractAddress для хождения по другим контрактам через wasmbinding — ТОЛЬКО если явно указан

#### WithdrawContractRewards

```
Contract → DispatchMsg(contractAddr, msg.Custom)
         → rewards.MsgHandler.WithdrawContractRewards(ctx, contractAddr, req)
         → WithdrawRewardsByRecordsLimit(ctx, rewardsAddr=contractAddr, ...)
```

**Authorization:**
- Contracts withdrawal: только где `RewardsRecord.RewardsAddress == contractAddr`
- Контракт не может withdraw чужие rewards ✓

**Double-withdrawal check:**
```go
// Validate() предотвращает оба поля одновременно:
if (r.RecordsLimit == nil && len(r.RecordIDs) == 0) || 
   (r.RecordsLimit != nil && len(r.RecordIDs) > 0) {
    return fmt.Errorf("one of (RecordsLimit, RecordIDs) fields must be set")
}
```
✓ Нет double-withdrawal через wasmbinding.

#### SetFlatFee

```
Contract → DispatchMsg(contractAddr, msg.Custom)
         → rewards.MsgHandler.SetFlatFee(ctx, senderAddr=contractAddr, req)
         → keeper.SetFlatFee(ctx, senderAddr, flatFeeUpdate)
```

**Authorization:**
- `contractInfo.OwnerAddress != senderAddr` → error
- Только metadata owner может устанавливать flat fee
- Контракт может быть metadata owner другого контракта — тогда может управлять его flat fee ✓

### Wasm Entrypoints (instantiate/execute/migrate)

| Entrypoint | Archway-specific действия |
|------------|--------------------------|
| **Instantiate** | IngestGasRecord() для всех wasm ops; metadata НЕ создаётся автоматически |
| **Execute** | IngestGasRecord(); при custom msg → wasmbinding dispatch |
| **Migrate** | IngestGasRecord(); metadata НЕ удаляется и НЕ обновляется автоматически |
| **Reply** | IngestGasRecord() для reply op |
| **Sudo** | IngestGasRecord() для sudo op |
| **AdminChange** | Стандартный wasmd; metadata.OwnerAddress НЕ обновляется автоматически |

**Критично для Migrate:** При migrate контракта, metadata (owner, rewardsAddress, flatFee) **сохраняется неизменной**. Новый код контракта получает те же rewards configuration. Это design intent: ownership не меняется при upgrade кода.

**Критично для AdminChange:** При смене wasm admin (через `MsgUpdateAdmin`), metadata.OwnerAddress остаётся на старого owner. Новый admin может создать metadata для контракта (если её нет) или изменить существующую только если уже является metadata owner.

---

## Authorization Analysis

### Иерархия ролей в контексте Archway rewards

```
WASM Admin (contractInfo.Admin)
    ├─ Может создавать metadata (если её нет)
    ├─ Может регистрировать callbacks
    ├─ Может подписываться на cwerrors
    ├─ Может удалять callbacks
    └─ НЕ может изменять существующую metadata без metadata owner права

Metadata Owner (ContractMetadata.OwnerAddress)
    ├─ Может изменять metadata (rewardsAddress, ownerAddress)
    ├─ Может устанавливать flat fee
    ├─ Может регистрировать/отменять callbacks
    ├─ Может подписываться на cwerrors
    └─ Может передать ownership другому адресу

Contract Address Itself
    ├─ Может регистрировать callbacks (через submessage)
    ├─ Может регистрироваться как cwfees granter
    ├─ Может регистрировать ICA (через submessage)
    └─ Может обновлять свою metadata (если admin === contract или owner === contract)

Transaction Signer (обычный пользователь)
    └─ Может вызывать контракт → контракт выполняет действия от своего имени
```

### Разграничение: creator vs admin vs owner vs sender

| Роль | Источник | Используется |
|------|---------|-------------|
| `creator` | Задаётся при instantiate, неизменен | НЕ используется в Archway rewards logic |
| `admin` | `contractInfo.Admin`, изменяем через MsgUpdateAdmin | Создание metadata; управление callbacks/cwerrors |
| `owner` | `ContractMetadata.OwnerAddress` | Изменение metadata; flat fee; callbacks |
| `sender` | tx.GetSigners()[0] | Не используется напрямую в keeper — только через msg validation |
| `contractAddr` | Реальный адрес контракта | В wasmbinding всегда = senderAddr |

**Spoofing невозможен:** В wasmbinding `senderAddr = contractAddr` (аргумент `DispatchMsg`) — устанавливается wasmd VM, не пользователем.

### Rewards address vs contract address

`rewards.WithdrawContractRewards` использует `contractAddr` (вызывающий контракт) как `rewardsAddr` для `WithdrawRewardsByRecordsLimit`. Контракт может только снять rewards где **его собственный адрес** является `RewardsAddress` в records.

Если чужой контракт `X` имеет `metadata.RewardsAddress = contractA`, то только контракт A может снять эти rewards (или любой пользователь может вызвать MsgWithdrawRewards через стандартный tx на этот адрес).

---

## State Consistency Analysis

### Failed Wasm Execution

При любой ошибке wasm execution → CacheContext discard:
- ContractOpInfo → откатывается ✓
- Изменения metadata через wasmbinding custom msg → откатываются ✓
- TxInfo (AnteHandler) → НЕ откатывается (persist, но нет ContractOpInfo)
- TxRewards (AnteHandler) → НЕ откатывается (persist, fee rebate → treasury)

### Failed Metadata Update

`SetContractMetadata` является atomic KVStore write. Partial state невозможен — либо успех, либо error без записи.

### Failed Migrate

При `MsgMigrateContract`:
- Если migrate fails → все изменения откатываются
- Metadata сохраняется из старого состояния ✓
- Gas за failed migrate через `IngestGasRecord` записывается, но если parent tx fails → также откатывается

### Failed Callback (EndBlocker)

При failed callback:
- `SetError` в cwerrors ← записывается
- `Callbacks.Remove` ← записывается (callback удаляется даже при failure)
- `RefundFromCallbackModule(ReservedBy, ...)` ← refund происходит
- Fee accounting ← корректно
- **Нет stuck state** ✓

### Contract Admin Change

При `MsgUpdateAdmin`:
- metadata.OwnerAddress остаётся неизменным
- Новый admin получает право создавать metadata только если её нет
- Существующий metadata owner сохраняет права
- **Edge case:** Если old_admin == metadata_owner и admin изменился → old_admin сохраняет metadata control

---

## Edge Case Analysis

### Contract without metadata

```
Contract без metadata:
- IngestGasRecord: ContractOpInfo создаётся → tracked
- estimateBlockGasUsage: contractDistrState создаётся, но Metadata == nil
- createRewardsRecords: фильтрует "if metadata == nil → skip"
→ Gas tracked, но rewards НЕ распределяются → dust в treasury
```

### Contract with changed admin (MsgUpdateAdmin)

```
Before: admin = Alice, metadata.owner = Alice
After MsgUpdateAdmin: admin = Bob, metadata.owner = Alice (unchanged!)

Bob (new admin):
- Может создавать metadata → Только если метаданные ЕЩЁ не существуют
- НЕ может изменять существующую metadata (Alice по-прежнему owner)
- НЕ может изменить rewards без Alice

Alice (old admin, now metadata owner):
- Сохраняет полный контроль над rewards configuration
- Может изменять metadata, flat fee, callbacks
```

### Migrated contract

```
Contract migrated (code upgrade):
- ContractAddress не меняется ✓
- metadata не меняется (owner, rewardsAddress сохранены) ✓
- Gas tracking продолжает работать для нового кода ✓
- flat fee сохраняется ✓
- pending callbacks выполнятся ✓
```

### Self-calls / Nested calls

```
Contract A → calls itself (A → A):
- Два ContractOpInfo: A_execute_1 и A_execute_2
- Оба с contractAddress = A
- ContractDistrState.BlockGasUsed = gas1 + gas2
- Rewards атрибутируются A, не двойной счёт (они же accumulate)
- Результат: A получает суммарные rewards за оба вызова ✓
```

### Blocked module accounts как rewards address

```
SetContractMetadata validates:
if k.isBlockedAddress(addr) {
    return types.ErrInvalidRequest.Wrap("rewards address cannot be a blocked address")
}
→ Нельзя установить blocked address как rewardsAddress ✓
→ Нельзя случайно отправить rewards на mint/staking/etc module ✓
```

---

## Слабые зацепки

| Зацепка | Заключение |
|---------|-----------|
| Gas processor race condition | Нет: SetGasRecorder вызывается до запуска сети |
| Contracts can forge senderAddr | Нет: wasmd устанавливает contractAddr как senderAddr |
| WithdrawRewards для чужих records | Нет: records фильтруются по caller address |
| Double withdrawal через wasmbinding | Нет: Validate() запрещает оба поля |
| MustGet* panic paths | Защищены: Validate() вызывается перед каждым MustGet |
| Creator vs admin confusion | Нет: creator не используется в Archway rewards |
| Metadata survives migrate | Design intent: явный выбор Archway |
| Custom query gas tracking | Нет: queries вне tx context, gas не tracked для rewards |
| SetFlatFee → wrong contract | Нет: keeper проверяет senderAddr == metadata owner |

---

## Топ-5 high-risk файлов

| # | Файл | Риск | Обоснование |
|---|------|------|-------------|
| 1 | `wasmbinding/plugin_test.go` | **Critical** | Полностью закомментирован (W-02) |
| 2 | `wasmbinding/rewards/types/msg_metadata.go` | Medium | W-01: ToSDK() не включает WithdrawToWallet |
| 3 | `wasmbinding/rewards/msg_handler.go` | Medium | Core dispatch logic; W-01 path |
| 4 | `wasmbinding/msg_plugin.go` | Medium | Main dispatcher; единая точка входа для всех custom msgs |
| 5 | `x/rewards/keeper/metadata.go` | Low | SetContractMetadata: WithdrawToWallet logic |

---

## Тесты для добавления

### Немедленно (критично)

```go
// wasmbinding/plugin_test.go — раскомментировать + добавить:

func TestDispatchMsg_UpdateMetadata_WithdrawToWallet_Preserved(t *testing.T) {
    // Setup: contract with WithdrawToWallet=true
    // Action: update RewardsAddress via wasmbinding
    // Assert: WithdrawToWallet still true
}

func TestDispatchMsg_UpdateMetadata_WithdrawToWallet_CanBeSetViaWasmbinding(t *testing.T) {
    // If fix variant A: verify WithdrawToWallet can be set via custom msg
}

func TestDispatchMsg_UpdateMetadata_OnlyOwnerCanModify(t *testing.T) {
    // contract A tries to update contract B's metadata where A is NOT owner
    // → ErrUnauthorized
}

func TestDispatchMsg_WithdrawRewards_OnlyOwnRecords(t *testing.T) {
    // contract A cannot withdraw rewards where record.RewardsAddress != A
}

func TestDispatchMsg_InvalidJSON_Rejected(t *testing.T) { ... }
func TestDispatchMsg_MultipleFields_Rejected(t *testing.T) { ... }
func TestDispatchMsg_EmptyMsg_Rejected(t *testing.T) { ... }

func TestQueryPlugin_ContractMetadata_NotFound_ReturnsError(t *testing.T) { ... }
func TestQueryPlugin_RewardsRecords_PaginationWorks(t *testing.T) { ... }
```

### Regression tests для найденных багов

```go
// W-01 regression
func TestRegression_W01_WithdrawToWallet_NotReset(t *testing.T) {
    // должен падать до фикса, проходить после
}

// Authorization matrix test
func TestWasmbindingAuthMatrix(t *testing.T) {
    // Таблица: [caller] × [target] × [operation] → expected result
    // Покрыть: owner, admin, random contract, blocked addr
}
```

---

## Confirmed Findings

1. **W-01 (Low):** `WithdrawToWallet` молча сбрасывается в false при вызове `UpdateContractMetadata` через wasmbinding — `ToSDK()` не включает поле.

2. **W-02 (High):** Wasmbinding тесты (`plugin_test.go`, `integration_test.go`) полностью закомментированы. Расширение паттерна T-01 из x/tracking аудита.

## Weak Leads (закрыты)

- Gas processor spoofing: невозможен (SetGasRecorder before runtime)
- Sender address forgery: невозможен (wasmd устанавливает contractAddr)
- Double withdrawal: заблокирован Validate()
- Rewards address spoofing: заблокирован адресной проверкой
- MustGet* panics: защищены предварительным Validate()

---

## Итоговый список Archway-specific Wasm Modifications

1. **x/tracking ContractGasProcessor** — перехват всех gas records из wasmd VM
2. **mintbankkeeper** — перехват inflation distribution (см. T-02)
3. **wasmbinding custom msg handler** — UpdateMetadata, WithdrawRewards, SetFlatFee
4. **wasmbinding custom query plugin** — ContractMetadata, RewardsRecords, FlatFee, GovVote
5. **Nет BeginBlocker для wasm** — Archway wasm модификации только в EndBlocker
6. **Нет post-handlers** — все кастомные действия через ante handlers
7. **Нет wasm hooks на instantiate/migrate** — metadata создаётся только вручную

*Отчёт составлен для целей легального bug bounty. Эксплуатация mainnet не проводилась.*
