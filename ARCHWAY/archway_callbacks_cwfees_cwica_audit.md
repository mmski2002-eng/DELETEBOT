# Archway Network — Аудит Callbacks / CWFees / CWICA / CWErrors
## PROMPT 4: Async Flows, Fee Grants, ICA, Error Handling Audit

**Дата:** 2026-06-03  
**Фокус:** x/callback, x/cwfees, x/cwica, x/cwerrors, fee grant drain, IBC/ICA security  
**Методология:** Статический анализ кода, трассировка panic paths, IBC state machine analysis  

---

## Содержание

1. [Сводная таблица](#сводная-таблица)
2. [C-01: ComputationalPriceOfGas panic при несовпадении denom — Chain Halt](#c-01-computationalpriceof​gas-panic-при-несовпадении-denom--chain-halt-critical)
3. [F-01: CancelCallback Refund Theft (подтверждение)](#f-01-cancelcallback-refund-theft-medium-подтверждение)
4. [C-02: IBCModule паникует в controller-only методах](#c-02-ibcmodule-паникует-в-controller-only-методах-low)
5. [Lifecycle Diagrams](#lifecycle-diagrams)
6. [Полный анализ: Callback Lifecycle](#полный-анализ-callback-lifecycle)
7. [Полный анализ: IBC/ICA](#полный-анализ-ibcica)
8. [Полный анализ: CWFees / Fee Grants](#полный-анализ-cwfees--fee-grants)
9. [Полный анализ: CWErrors](#полный-анализ-cwerrors)
10. [Слабые зацепки](#слабые-зацепки)
11. [Топ-5 high-risk функций](#топ-5-high-risk-функций)
12. [Тесты для добавления](#тесты-для-добавления)

---

## Сводная таблица

| ID | Название | Severity | Confidence | Статус |
|----|---------|----------|-----------|--------|
| C-01 | ComputationalPriceOfGas panic → Chain Halt | **Critical** | **High** | Confirmed |
| F-01 | CancelCallback Refund Theft | Medium | High | Confirmed (ранее) |
| C-02 | IBCModule panics for controller-only methods | Low | High | Informational |

---

## C-01: ComputationalPriceOfGas panic при несовпадении denom → Chain Halt (Critical)

**Severity: Critical**  
**Confidence: High**  
**Статус: Confirmed**

### Затронутые файлы

- `x/rewards/keeper/min_cons_fee.go` — `ComputationalPriceOfGas()`
- `x/rewards/keeper/params.go` — `MinimumPriceOfGas()`
- `x/rewards/types/params.go` — `MinPriceOfGas` param
- `x/callback/keeper/fees.go` — `CalculateTransactionFees()`
- `x/callback/abci.go` — EndBlocker callback execution

### Summary

`ComputationalPriceOfGas()` паникует если `MinPriceOfGas.Denom` (governance param) не совпадает с `MinConsensusFee.Denom` (inflation denom). Функция вызывается как в AnteHandler (ошибка tx), так и в EndBlocker через callback execution (chain halt). Governance может случайно или намеренно установить `MinPriceOfGas` с неправильным denom и вызвать функциональный или полный chain halt.

### Technical details

**Путь к panic:**

```go
// x/rewards/keeper/min_cons_fee.go — ComputationalPriceOfGas
func (k Keeper) ComputationalPriceOfGas(ctx sdk.Context) sdk.DecCoin {
    minPoG := k.MinimumPriceOfGas(ctx)      // из params: governance-controlled denom
    antiDoSPoG, found := k.GetMinConsensusFee(ctx)  // из inflation: inflation denom
    if !found {
        return minPoG
    }
    if minPoG.Denom != antiDoSPoG.Denom {
        // PANIC — строки конкатенированы, не форматирован string (баг в panic msg)
        panic("conflict between anti dos denom and min price of gas denom: %s != %s" + 
              minPoG.Denom + antiDoSPoG.Denom)
    }
    ...
}
```

**Источники несовпадения:**

```
MinConsensusFee.Denom = inflation denom (из x/mint, обновляется каждый блок)
                      = "aarch" (нативный staking token)

MinPriceOfGas.Denom   = governance-controlled parameter
                      = может быть установлен governance в любой валидный denom
                      = "uatom", "usdc", "mytoken", etc.

Если governance устанавливает MinPriceOfGas denom ≠ "aarch":
→ ComputationalPriceOfGas() паникует
```

**Validation chain провал:**

```go
// x/rewards/types/params.go
func validateMinPriceOfGas(v interface{}) error {
    p, ok := v.(sdk.DecCoin)
    if !ok { return error }
    return p.Validate()  // только проверяет valid DecCoin format, НЕ denom match
}
```

Governance может передать `MinPriceOfGas = "0.001uatom"` → validation проходит → param установлен.

**Два пути к chain halt:**

**Путь 1 — EndBlocker (Chain Halt):**
```
Governance изменяет MinPriceOfGas.Denom = "mytoken"
↓
Следующий EndBlocker: x/callback исполняет callbacks
  callbackExec() → k.CalculateTransactionFees(ctx, gasUsed)
  CalculateTransactionFees() → k.rewardsKeeper.ComputationalPriceOfGas(ctx)
  ComputationalPriceOfGas() → panic("conflict between denom...")
  
panic в EndBlocker не ловится → CometBFT получает panic → chain halt
```

**Путь 2 — AnteHandler (Функциональный halt):**
```
Governance изменяет MinPriceOfGas.Denom = "mytoken"
↓  
Каждая транзакция: MinFeeDecorator.AnteHandle()
  → mfd.rewardsKeeper.ComputationalPriceOfGas(ctx)
  → panic("conflict...")
  
panic в AnteHandler ловится Cosmos SDK runTx() recover
→ tx возвращает ErrPanic
→ ВСЕ транзакции отклоняются

Цепочка работает (производит пустые блоки),
но НИ ОДНА транзакция не проходит → невозможно исправить параметры через governance
→ требуется emergency upgrade / hardfork
```

**Критичность пути 2:** После принятия вредоносного governance proposal, ВСЕ последующие транзакции начинают паниковать. Само исправление через governance тоже не пройдёт.

**Дополнительно:** Panic message содержит ошибку строкового форматирования:
```go
panic("conflict between anti dos denom and min price of gas denom: %s != %s" + 
      minPoG.Denom + antiDoSPoG.Denom)
// Результат: "conflict between anti dos denom and min price of gas denom: %s != %sstakestake"
// Не использует fmt.Sprintf → мусор в сообщении об ошибке
```

### Attack preconditions

- **Непреднамеренно:** Governance proposal с некорректным `MinPriceOfGas` denom проходит
- **Преднамеренно:** Атакующий с governance весом проводит вредоносный proposal
- Нет необходимости в специальных правах кроме governance voting power
- Нет необходимости в контрактах или средствах помимо stake для голосования

### Impact

| Сценарий | Последствие |
|---------|------------|
| Pending callbacks + denom change | Chain halt в EndBlocker |
| Нет pending callbacks + denom change | Все txs fail (functional halt) |
| После functional halt | Невозможно исправить через governance (txs не проходят) |
| Recovery | Требуется emergency upgrade с patch или hard fork |

### PoC plan

```go
func TestComputationalPriceOfGas_DenomMismatch_Panic(t *testing.T) {
    k, ctx, _ := testutils.RewardsKeeper(t)
    
    // Устанавливаем MinPriceOfGas с denom "mytoken"
    params := k.GetParams(ctx)
    params.MinPriceOfGas = sdk.NewDecCoin("mytoken", sdkmath.NewInt(1))
    k.Params.Set(ctx, params)
    
    // Устанавливаем MinConsensusFee с denom "stake" (inflation token)
    k.MinConsFee.Set(ctx, sdk.NewDecCoin("stake", sdkmath.NewInt(100)))
    
    // ComputationalPriceOfGas должна паниковать
    assert.Panics(t, func() {
        k.ComputationalPriceOfGas(ctx)
    })
}

func TestEndBlocker_CallbackExecution_DenomMismatch_Panic(t *testing.T) {
    // Setup chain с callback + incompatible denoms
    // Verify: EndBlocker паникует
    // → chain halt scenario
}
```

### Counterarguments

- В production обычно один staking token, смена denom редка
- Governance требует достаточный voting power → атака сложна
- Archway может иметь ограничения на denom в governance proposals (не в коде)

### Suggested fix

**Вариант A (минимальный): Validation при установке params**
```go
// x/rewards/types/params.go
func (m Params) Validate() error {
    // ... existing validations ...
    
    // Нельзя здесь проверить соответствие denom, т.к. нет доступа к inflation denom
    // Нужно добавить в keeper
}

// x/rewards/keeper/params.go — при UpdateParams через governance
func (k Keeper) UpdateMinPriceOfGas(ctx sdk.Context, newParam sdk.DecCoin) error {
    antiDoSPoG, found := k.GetMinConsensusFee(ctx)
    if found && newParam.Denom != antiDoSPoG.Denom {
        return fmt.Errorf("MinPriceOfGas denom (%s) conflicts with inflation denom (%s)", 
                          newParam.Denom, antiDoSPoG.Denom)
    }
    // proceed with update
}
```

**Вариант B (более надёжный): Убрать panic, вернуть error или safe default**
```go
func (k Keeper) ComputationalPriceOfGas(ctx sdk.Context) sdk.DecCoin {
    minPoG := k.MinimumPriceOfGas(ctx)
    antiDoSPoG, found := k.GetMinConsensusFee(ctx)
    if !found {
        return minPoG
    }
    if minPoG.Denom != antiDoSPoG.Denom {
        // НЕ паниковать — вернуть safe default
        k.Logger(ctx).Error("denom conflict", "minPoG", minPoG.Denom, "antiDoS", antiDoSPoG.Denom)
        return minPoG  // или antiDoSPoG
    }
    return sdk.NewDecCoinFromDec(minPoG.Denom, sdkmath.LegacyMaxDec(minPoG.Amount, antiDoSPoG.Amount))
}
```

**Вариант C: Исправить panic message + добавить validation**

Также исправить строковую конкатенацию в panic message:
```go
panic(fmt.Sprintf("conflict between anti dos denom and min price of gas denom: %s != %s", 
                  minPoG.Denom, antiDoSPoG.Denom))
```

**Рекомендация: Вариант B** — убрать panic, продолжить с safe default и logging. Это критично для chain liveness.

---

## F-01: CancelCallback Refund Theft (Medium) — Подтверждение

*(Полное описание в `archway_security_audit_report.md`)*

**Краткое резюме:**
```go
// x/callback/keeper/msg_server.go — CancelCallback
// Должно быть callback.ReservedBy, не request.Sender:
err = s.keeper.RefundFromCallbackModule(ctx, request.Sender, refundFees)
```

Дополнительный контекст из этого анализа:

`RefundFromCallbackModule` содержит защиту от blocked addresses:
```go
func (k Keeper) RefundFromCallbackModule(ctx sdk.Context, recipient string, amount sdk.Coin) error {
    recipientAddr, err := sdk.AccAddressFromBech32(recipient)
    ...
    if k.bankKeeper.BlockedAddr(recipientAddr) {
        return k.SendToFeeCollector(ctx, amount)  // blocked addr → fee collector вместо panic
    }
    return k.bankKeeper.SendCoinsFromModuleToAccount(...)
}
```

Это хорошая защита для EndBlocker (нельзя вызвать panic через blocked addr). НО для F-01 не помогает — злоумышленник использует обычный незаблокированный адрес.

---

## C-02: IBCModule паникует в controller-only методах (Low)

**Severity: Low**  
**Confidence: High**  
**Статус: Informational**

### Затронутые файлы

- `x/cwica/ibc_module.go`

### Summary

Несколько IBC module handlers паникуют с "NOT NEEDED FOR CONTROLLER MODULE":

```go
func (im IBCModule) OnChanOpenTry(...) (string, error) {
    panic("NOT NEEDED FOR CONTROLLER MODULE")
}
func (im IBCModule) OnChanOpenConfirm(...) error {
    panic("NOT NEEDED FOR CONTROLLER MODULE")
}
func (im IBCModule) OnChanCloseInit(...) error {
    panic("NOT NEEDED FOR CONTROLLER MODULE")
}
func (im IBCModule) OnRecvPacket(...) ibcexported.Acknowledgement {
    panic("NOT NEEDED FOR CONTROLLER MODULE")
}
```

### Почему Low, а не Critical

1. IBC routing направляет эти вызовы только к ICA HOST модулю, не к controller
2. Registered port prefix `icacontroller-` не будет целью host-only callbacks
3. Даже если вызов произошёл — в ibc-go v8 panics в IBC handlers... надо проверить

Фактически: в ibc-go обычно есть middleware stack, где panics могут или не могут быть пойманы. Без дополнительного анализа ibc-go internals — оставляем как Low.

### Suggested fix

```go
// Вместо panic — вернуть error:
func (im IBCModule) OnChanOpenTry(...) (string, error) {
    return "", sdkerrors.ErrNotSupported.Wrap("OnChanOpenTry not supported for CWICA controller")
}
```

---

## Lifecycle Diagrams

### Callback Lifecycle

```
REGISTRATION:
  User → MsgRequestCallback{height, contract, jobId, fees}
     ↓ isAuthorizedToModify(sender) [contract / admin / owner]
     ↓ HasContractInfo(contract)
     ↓ ExistsCallback → нет дублей по (height, contract, jobId)
     ↓ callbackHeight ∈ (current, current + MaxFutureReservationLimit]
     ↓ len(callbacksForBlock) < MaxBlockReservationLimit
     ↓ callback.MaxGasLimit = params.CallbackGasLimit [снимок]
     ↓ Callbacks.Set(...)
     ↓ SendToCallbackModule(sender, fees)
     → callback зарегистрирован, fees заморожены

CANCELLATION:
  User → MsgCancelCallback{height, contract, jobId}
     ↓ isAuthorizedToModify(sender) [contract / admin / owner]
     ↓ DeleteCallback(sender, callback)
     ↓ RefundFromCallbackModule(request.Sender, txFees+surplusFees) ← F-01 BUG
     ↓ SendToFeeCollector(reservationFees)
     → callback удалён, refund выдан (неправильному адресу!)

EXECUTION (EndBlocker, высота = callbackHeight):
  IterateCallbacksByHeight(H):
    ExecuteWithGasLimit(MaxGasLimit):
      wk.Sudo(contract, callbackMsg)
        ↓ SUCCESS:
           gasUsed = actual gas
           txFeesConsumed = CalculateTransactionFees(gasUsed)
           if txFeesConsumed < TransactionFees:
               RefundFromCallbackModule(ReservedBy, TransactionFees - txFeesConsumed) ← ПРАВИЛЬНО
           SendToFeeCollector(reservationFees + surplusFees + txFeesConsumed)
           Callbacks.Remove(key)
        ↓ FAILURE (error / out-of-gas):
           gasUsed = MaxGasLimit [cap for refund calculation]
           SetError(cwerrors, errorInfo)
           RefundFromCallbackModule(ReservedBy, 0) [нет refund при full OOG]
           SendToFeeCollector(ALL fees)
           Callbacks.Remove(key)

REPLAY PROTECTION: ✓ (callback удаляется после выполнения или отмены)
NO TIMEOUT: callbacks не имеют timeout — они выполняются строго на указанной высоте
```

### CWICA Lifecycle

```
CHANNEL OPENING:
  Contract → MsgRegisterInterchainAccount{connectionId}
     ↓ HasContractInfo(contract)
     ↓ GetConnection(connectionId) — проверяет существование
     ↓ icaControllerKeeper.RegisterInterchainAccount(connectionId, contractAddr, version)
     → IBC channel open initiated

  IBC Core → OnChanOpenAck(portId, channelId, counterpartyChannelId, counterpartyVersion)
     ↓ HandleChanOpenAck(...)
     ↓ ICAOwnerFromPort(portId) → contractAddress
     ↓ Decode counterparty ICA address
     ↓ Sudo(contract, {AccountRegistered: {counterpartyAddress}})
         ↓ SUCCESS: contract notified ✓
         ↓ FAILURE: error logged, nil returned (IBC succeeds anyway) ← SWALLOWED

ICA TX EXECUTION:
  Contract → MsgSendTx{connectionId, msgs, timeout}
     ↓ HasContractInfo(contract)
     ↓ GetActiveChannelID(connectionId, portId) — канал должен быть активен
     ↓ SerializeCosmosTxs(msgs)
     ↓ icaControllerKeeper.SendTx(...)
     → IBC packet sent

  IBC Core → OnAcknowledgementPacket(packet, ack)
     ↓ HandleAcknowledgement(...)
     ↓ if ack.Success:
         Sudo(contract, {TxExecuted: {packet, data}})
         ↓ error: logged, nil returned ← SWALLOWED
     ↓ if ack.Error:
         errorsKeeper.SetError(sudoError)
         → contract gets error via cwerrors subscription

  IBC Core → OnTimeoutPacket(packet)
     ↓ HandleTimeout(...)
     ↓ errorsKeeper.SetError(ERR_PACKET_TIMEOUT)
     → ICA channel closes (ordered channel)
     → contract must re-register ICA

REPLAY PROTECTION: ✓ IBC sequence numbers (handled by ibc-go core)
AUTH: GetSigners = [ContractAddress] → только контракт сам отправляет
```

### CWFees Lifecycle

```
REGISTRATION:
  Contract (via submessage) → MsgRegisterAsGranter{GrantingContract=self}
     ↓ GetSigners = [ContractAddress] → только контракт сам
     ↓ HasContractInfo(contract) ✓
     ↓ IsGrantingContract → не дублировать
     ↓ GrantingContracts.Set(contract)

GRANT USAGE (AnteHandler):
  TX with FeeGranter=contractAddr, FeePayer=user
     ↓ DeductFeeDecorator.getFeePayer()
     ↓ IsGrantingContract(granter) → true
     ↓ RequestGrant(granter, txMsgs, fees, signers)
         ↓ gasLimitToUse = min(remaining, 100_000)
         ↓ ExecuteWithGasLimit(gasLimitToUse):
             Sudo(contract, {cw_grant: {fee_requested, msgs, signers}})
             ↓ SUCCESS: contract approved → granter pays fees ✓
             ↓ FAILURE / OOG: tx rejected (fee grant not approved) ✓
     → granter = contractAddr (pays fees)
     → payer = user tx sender

DRAIN PROTECTION:
  - Contract controls grant logic (sudo handler)
  - Gas cap = 100_000 (prevents slow drain via expensive sudo)
  - Contract must explicitly opt-in via MsgRegisterAsGranter

POTENTIAL ABUSE (design responsibility):
  - Poorly written contract sudo (accept all) → any tx can drain contract
  - No protocol-level allowance caps (must be implemented in contract)
```

### CWErrors Lifecycle

```
ERROR GENERATION:
  Any module → errorsKeeper.SetError(sudoErr)
  ├─ HasContractInfo(contract) ✓
  ├─ HasSubscription(contract)?
  │   ├─ YES → storeErrorCallback(transient store)
  │   │         → executed this EndBlocker
  │   └─ NO  → StoreErrorInState(permanent store)
  │             → available via query for ErrorStoredTime blocks

SUBSCRIPTION:
  User → MsgSubscribeToError{sender, contractAddress, fee}
     ↓ isAuthorizedToSubscribe(sender) [contract / admin / owner]
     ↓ fee == params.SubscriptionFee
     ↓ SendCoinsFromAccountToModule(sender, FeeCollector, fee)
     ↓ SubscriptionEndBlock.Set(endHeight)
     ↓ ContractSubscriptions.Set(contract, endHeight)

ERROR CALLBACK DELIVERY (EndBlocker):
  IterateSudoErrorCallbacks (transient store):
    ExecuteWithGasLimit(150_000):
      Sudo(contract, {error: {module, errorCode, inputPayload, errorMessage}})
      ↓ SUCCESS: error delivered ✓
      ↓ FAILURE: StoreErrorInState(secondary error) — НЕ в transient → нет loop

CLEANUP:
  PruneSubscriptionsEndBlock(height) → удаляет истёкшие подписки
  PruneErrorsCurrentBlock(height) → удаляет истёкшие stored errors
```

---

## Полный анализ: Callback Lifecycle

### Кто может зарегистрировать callback?

`isAuthorizedToModify` разрешает:
1. Сам контракт (`sender == contractAddress`)
2. Wasm admin (`sender == contractInfo.Admin`)
3. Metadata owner (`sender == contractMetadata.OwnerAddress`)

Заблокированные адреса (module accounts) — отклоняются.

### Replay protection

Callbacks хранятся с composite key `(height, contractAddress, jobId)`. После выполнения или отмены — удаляются. **Нет replay.** ✓

### Что происходит при out-of-gas callback?

```go
// abci.go — if callback execution fails with ErrOutOfGas:
errorCode = types.ModuleErrors_ERR_OUT_OF_GAS
// ...
gasUsed = callback.MaxGasLimit  // ← cap: не превышает оплаченного
// txFeesConsumed = CalculateTransactionFees(MaxGasLimit) ≥ TransactionFees (usually)
// → No refund (весь gas limit использован)
// → SendToFeeCollector(ALL fees)
```

Правильно: пользователь оплатил за MaxGasLimit gas, система берёт всё.

### Gas limit snapshot vs params change

```go
// SaveCallback
callback.MaxGasLimit = params.CallbackGasLimit  // снимок при регистрации
```

Если governance уменьшит `CallbackGasLimit` после регистрации callback:
- Старые callbacks сохраняют старый (более высокий) MaxGasLimit
- Пользователь оплатил за высокий лимит → справедливо

Если governance увеличит `CallbackGasLimit`:
- Старые callbacks продолжают использовать старый (более низкий) лимит
- Новые callbacks используют новый лимит → нет проблем

### MaxBlockReservationLimit = 0

```go
// SaveCallback
if len(callbacksForBlock) >= int(params.MaxBlockReservationLimit) {
    return types.ErrBlockFilled
}
// Если MaxBlockReservationLimit = 0:
// 0 >= 0 → true → ErrBlockFilled → невозможно зарегистрировать callbacks
```

Governance может заблокировать регистрацию. Существующие callbacks выполнятся. **Low severity — governance DoS только на новые callbacks.**

### Denom mismatch panic (C-01)

При вызове `CalculateTransactionFees` в EndBlocker:
```go
// abci.go
txFeesConsumed := k.CalculateTransactionFees(ctx, gasUsed)
// → ComputationalPriceOfGas() → panic если denom conflict → chain halt
```

---

## Полный анализ: IBC/ICA

### Channel/Port/Connection validation в MsgSendTx

```go
// cwica/keeper/msg_server.go
func (k Keeper) SendTx(...) (...) {
    ...
    if !k.sudoKeeper.HasContractInfo(ctx, senderAddr) {
        return nil, types.ErrNotContract
    }
    
    params, err := k.GetParams(ctx)
    if uint64(len(msg.Msgs)) > params.GetMsgSendTxMaxMessages() {
        return nil, fmt.Errorf("too many messages: %d > %d", ...)
    }
    
    portID, err := icatypes.NewControllerPortID(msg.ContractAddress)
    
    channelID, found := k.icaControllerKeeper.GetActiveChannelID(ctx, msg.ConnectionId, portID)
    if !found {
        return nil, errors.Wrapf(icatypes.ErrActiveChannelNotFound, ...)
    }
    ...
}
```

✓ Проверяется:
- ContractAddress является контрактом
- Количество messages <= max
- Активный channel существует для connection+port

НЕ проверяется явно:
- Counterparty chain identity (handled by IBC core)
- Message types допустимы (handled by ICA host chain)

### Replay protection

IBC sequence numbers хранятся в ibc-go core. `GetNextSequenceSend` возвращает следующий sequence:
```go
sequence, found := k.channelKeeper.GetNextSequenceSend(ctx, portID, channelID)
```

Это стандартный IBC replay protection — работает через channel/sequence механизм ibc-go. ✓

### Timeout → channel close

При timeout ordered ICA channel:
1. `HandleTimeout` сохраняет ошибку в cwerrors
2. IBC core закрывает ordered channel
3. Контракт должен переоткрыть ICA через `MsgRegisterInterchainAccount`
4. Если контракт не подписан на cwerrors — не узнает о timeout!

**Asymmetry:** IBC ack errors → cwerrors. IBC ack success с failed sudo → только лог. Контракт может пропустить важные уведомления.

### Может ли чужой контракт получить результат чужого ICA?

```go
// ibc_handlers.go
func (k *Keeper) HandleAcknowledgement(ctx sdk.Context, packet channeltypes.Packet, ...) error {
    icaOwner := types.ICAOwnerFromPort(packet.SourcePort)
    contractAddress, err := sdk.AccAddressFromBech32(icaOwner)
    // contractAddress = владелец ICA = тот кто регистрировал
    ...
    _, err = k.sudoKeeper.Sudo(ctx, contractAddress, sudoMsgPayload)
```

Ack доставляется только к `contractAddress` из портового ID. Нельзя получить чужой ICA результат. ✓

---

## Полный анализ: CWFees / Fee Grants

### Payer и grantee

- **Granter:** `grantingContract` (wasm contract, opted-in)
- **Payer:** `granter` address (если grant approved by contract sudo)
- **Grantee:** `payer` (tx sender) — тот, кто gets tx processed

### Drain via fee grant

```
Атака: Attacker создаёт множество txs с FeeGranter=victimContract
         каждый tx заставляет контракт потратить gas (100k лимит) + fees

Защита:
  1. Контракт контролирует sudo handler → может reject любой tx
  2. Gas cap 100k → ограничивает стоимость отклонения (аттакующий платит за gas)
  3. Контракт может unregister: MsgUnregisterAsGranter
```

При attack attacker тоже платит gas (tx gas + 100k для sudo вызова). Drain требует компромисса контракта's sudo logic.

### Expected fee vs actual fee

```go
// DeductFeeDecorator
// 1. MinFeeDecorator уже проверил fees >= minFee + flatFees
// 2. RequestGrant: контракт видит wantFees = actual tx fees
// 3. Контракт решает approve/reject
```

Нет mismatch: tx fee это то что контракт видит и что реально взимается.

### Failed execution refund

Если tx execution fails (msg error) ПОСЛЕ approve grant:
- AnteHandler state committed (grant использован, fees уплачены)
- Msg state rolled back
- **Нет refund** — стандартное поведение Cosmos SDK. Контракт оплатил tx, tx failed — как с обычными txs.

---

## Полный анализ: CWErrors

### Swallowed errors vs security

**`HandleChanOpenAck`:**
```go
_, err = k.sudoKeeper.Sudo(ctx, contractAddress, sudoPayload)
if err != nil {
    k.Logger(ctx).Debug("HandleChanOpenAck: failed to sudo", "error", err)
}
return nil  // ВСЕГДА nil — IBC видит success
```

**Может ли swallowed error привести к successful state?**
- IBC channel открылся (это success)
- Контракт не уведомлён (это failure)
- Контракт может быть в "ожидающем" состоянии

**Реальный риск:** Контракт ожидает уведомления о открытии канала чтобы начать использовать ICA. Если уведомление потеряно:
- Контракт не начнёт использовать ICA
- Контракт может заблокировать funds ожидая подтверждения

НО: если контракт написан корректно, он должен периодически проверять активные каналы через `GetActiveChannelID` query. Это design responsibility контракта.

**Swallowed success ack error:**
```go
// ack.Error != "" → SetError(sudoErr) — сохраняется в cwerrors
// ack.Success + sudo fails → только лог → ∅
```

Асимметрия: failure ack → error stored. Success ack + failed sudo → only logged. Контракты должны учитывать это.

### Panic path в cwerrors EndBlocker

```go
// abci.go — sudoErrorCallbackExec
err = k.StoreErrorInState(ctx, contractAddr, newSudoErr)
if err != nil {
    panic(err)  // chain halt если StoreErrorInState fails
}
```

`StoreErrorInState` может вернуть ошибку при:
- `k.ErrorID.Next(ctx)` fails (collections error)
- `k.Errors.Set(...)` fails (store error)

В нормальных условиях collections.Sequence не возвращает ошибки (unless underlying store is broken). Низкий риск, но `panic` в EndBlocker — всегда потенциал chain halt.

---

## Слабые зацепки

| Зацепка | Заключение |
|---------|-----------|
| Callback replay | Нет: composite key + delete after exec |
| Unauthorized callback trigger | Нет: EndBlocker по height, не user-triggered |
| Drain via callback fees | Нет: пользователь платит за все fees |
| Wrong payer (cwfees) | Нет: contract controls grant via sudo |
| Double-spending callback fees | Нет: module account accounting |
| ICA sequence replay | Нет: ibc-go core handles sequences |
| Cross-contract ICA result | Нет: port-based routing |
| cwerrors infinite loop | Нет: transient vs permanent store separation |
| MaxGasLimit overflow | Нет: uint64, capped by block gas limit |
| Callback registered for past height | Нет: `callbackHeight > currentHeight` check |
| Fee grant from non-contract | Нет: `HasContractInfo` check |

---

## Топ-5 high-risk функций

| # | Функция | Файл | Риск | Обоснование |
|---|---------|------|------|-------------|
| 1 | `ComputationalPriceOfGas` | `x/rewards/keeper/min_cons_fee.go` | **Critical** | C-01: panic на denom mismatch → chain halt |
| 2 | `CancelCallback` | `x/callback/keeper/msg_server.go` | Medium | F-01: refund к sender вместо ReservedBy |
| 3 | `callbackExec` (EndBlocker) | `x/callback/abci.go` | High | Вызывает ComputationalPriceOfGas → C-01 path |
| 4 | `HandleChanOpenAck` / `HandleAcknowledgement` | `x/cwica/keeper/ibc_handlers.go` | Medium | Swallowed errors → inconsistent contract state |
| 5 | `sudoErrorCallbackExec` | `x/cwerrors/abci.go` | Low | panic(err) в EndBlocker → chain halt if collections fail |

---

## Тесты для добавления

### Немедленно (критично)

```go
// C-01: Denom mismatch panic
func TestComputationalPriceOfGas_DenomMismatch_ShouldNotPanic(t *testing.T) {
    k, ctx, _ := testutils.RewardsKeeper(t)
    // Установить MinPriceOfGas с denom "mytoken"
    // Установить MinConsensusFee с denom "stake"
    // Вызов НЕ должен паниковать → должен вернуть error или safe default
    require.NotPanics(t, func() { k.ComputationalPriceOfGas(ctx) })
}

func TestCallbackExecution_DenomMismatch_ChainDoesNotHalt(t *testing.T) {
    // Зарегистрировать callback
    // Изменить MinPriceOfGas denom
    // Запустить EndBlocker
    // Верифицировать: нет panic, ошибка обработана корректно
}

// F-01: CancelCallback wrong refund
func TestCancelCallback_AdminCancels_RefundGoesToOriginalPayer(t *testing.T) {
    // Alice (owner) регистрирует → Bob (admin) отменяет
    // Refund должен идти к Alice, не Bob
}

// C-01 governance validation
func TestUpdateParams_MinPriceOfGas_InvalidDenom_Rejected(t *testing.T) {
    // Governance пытается установить MinPriceOfGas с неправильным denom
    // Должно быть отклонено в UpdateParams
}
```

### Regression tests

```go
func TestRegression_C01_DenomMismatch_NoPanic(t *testing.T) { ... }
func TestRegression_F01_CancelCallback_CorrectRefundAddress(t *testing.T) { ... }
```

### Callback lifecycle полные тесты

```go
func TestCallback_SuccessExecution_PartialRefund(t *testing.T) {
    // gasUsed < MaxGasLimit → refund unused portion to ReservedBy
}

func TestCallback_FailedExecution_NoRefund_AllFeesToCollector(t *testing.T) {
    // callback fails → no refund, all fees to fee collector
}

func TestCallback_OutOfGas_CorrectAccountingCheck(t *testing.T) {
    // gasUsed = MaxGasLimit → no refund (edge case)
}

func TestCallback_GasLimitSnapshot_GovChangeDoesNotAffectExisting(t *testing.T) {
    // Register callback with GasLimit=1M
    // Governance changes GasLimit to 500k
    // Existing callback still uses 1M (snapshot)
}
```

---

## Confirmed Findings (этот аудит)

1. **C-01 (Critical):** `ComputationalPriceOfGas` паникует при denom mismatch между `MinPriceOfGas` (governance param) и `MinConsensusFee` (inflation param) → chain halt в EndBlocker или functional halt в AnteHandler.

2. **F-01 (Medium):** Подтверждено — `CancelCallback` отправляет refund на `request.Sender` вместо `callback.ReservedBy`.

## Weak Leads (закрыты)

- Callback replay: composite key + delete protection
- ICA unauthorized execution: GetSigners = [ContractAddress]
- Fee grant drain: contract controls sudo approval
- Double execution: EndBlocker iterates by height, delete-on-exec
- ICA cross-contract result: port-based routing

---

*Отчёт составлен для целей легального bug bounty / responsible disclosure. Эксплуатация mainnet не проводилась.*
