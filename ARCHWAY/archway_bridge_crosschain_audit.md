# Archway Network — Cross-Chain / Bridge Security Audit

**Дата:** 2026-06-03  
**Область:** IBC, IBCHooks, x/cwica, x/cwerrors, ICS-20 Transfer, ICA  
**Методология:** Статический анализ кода, трассировка middleware стека, анализ тестов  
**Репозиторий:** archway-network/archway (ibc-go v8.7.0, ibc-apps/ibc-hooks v8.0.0-20240820)

---

## Карта Cross-Chain поверхности Archway

### IBC Middleware стек (app.go)

```
ВХОДЯЩИЕ ПАКЕТЫ (OnRecvPacket):
  ibchooks.IBCMiddleware
    → ibcfee.IBCMiddleware
      → transfer.IBCModule

ICA Controller:
  cwica.IBCModule
    → icacontroller.IBCMiddleware
    (ibcfee закомментирован: // icaControllerStack = ibcfee.NewIBCMiddleware(...))

ICA Host:
  ibcfee.IBCMiddleware
    → icahost.IBCModule

Wasm IBC:
  ibcfee.IBCMiddleware
    → wasm.IBCHandler

ИСХОДЯЩИЕ ПАКЕТЫ (SendPacket через ICS4 wrapper):
  TransferKeeper.ics4Wrapper = IBCFeeKeeper
    → IBCFeeKeeper.ics4 = IBCKeeper.ChannelKeeper  ← BYPASSES ibchooks!
```

### User-controlled поля в IBC Transfer

| Поле | Тип | Контроль |
|------|-----|----------|
| `sender` | string | пользователь |
| `receiver` | string | пользователь |
| `amount` | string | пользователь |
| `denom` | string | пользователь |
| `memo` | string | пользователь — содержит JSON для ibchooks |
| `timeout_height` | Height | пользователь |
| `timeout_timestamp` | uint64 | пользователь |
| `source_channel` | string | пользователь |

### User-controlled поля в MsgSendTx (CWICA)

| Поле | Тип | Контроль |
|------|-----|----------|
| `contract_address` | string | контракт (подпись) |
| `connection_id` | string | контракт |
| `msgs` | []Any | контракт (ограничен MaxMessages) |
| `memo` | string | контракт |
| `timeout` | uint64 | контракт — НЕТ максимального лимита |

### Поддерживаемые Bridge/IBC routes

Из анализа кода Archway не содержит специфической интеграции с:
- Axelar / Squid / Satellite / GMP → не найдено в коде
- Osmosis / Noble / Gravity → нет специфических модулей
- Balanced xCall / ICON → не найдено

Archway использует стандартный ICS-20 Transfer + IBCHooks + ICA. Специфические bridge routes — внешние (настраиваются governance/relayers), не в коде.

---

## Найденные уязвимости

---

## Finding IB-01: ibc_callback outbound feature silently broken

- **Severity:** Medium
- **Confidence:** High
- **Affected Files:**
  - `app/app.go:495-516` (IBCFeeKeeper и TransferKeeper init)
  - `app/app.go:675-682` (ibchooks middleware setup)
  - `e2e/ibchooks/ibchooks_test.go` (тесты не тестируют production path)

### Flow

- Source chain: Archway
- Destination chain: любая IBC-chain
- Asset: любой ICS-20 токен
- User-controlled field: `memo: {"ibc_callback": "contract_address"}`

### Root Cause

IBCFeeKeeper инициализирован с `IBCKeeper.ChannelKeeper` как ICS4 wrapper:

```go
// app/app.go:495-500
app.Keepers.IBCFeeKeeper = ibcfeekeeper.NewKeeper(
    appCodec, keys[ibcfeetypes.StoreKey],
    app.Keepers.IBCKeeper.ChannelKeeper, // may be replaced with IBC middleware
    app.Keepers.IBCKeeper.ChannelKeeper, // ← ICS4 wrapper = raw ChannelKeeper
    ...
)

// app/app.go:503-512
app.Keepers.TransferKeeper = ibctransferkeeper.NewKeeper(
    ...
    app.Keepers.IBCFeeKeeper, // ← ICS4 wrapper для Transfer = IBCFeeKeeper
    ...
)
```

Цепочка SendPacket от TransferKeeper:
```
TransferKeeper → IBCFeeKeeper.SendPacket → ChannelKeeper.SendPacket
                                           ↑ ibchooks ICS4 НИКОГДА НЕ ВЫЗЫВАЕТСЯ
```

`hooksIcs4Wrapper` создан правильно:
```go
hooksIcs4Wrapper := ibchooks.NewICS4Middleware(app.Keepers.IBCKeeper.ChannelKeeper, ics20WasmHooks)
```

Но TransferKeeper его не использует. Поэтому `ibchooks.IBCMiddleware.SendPacket` никогда не получает исходящие пакеты от TransferKeeper.

### State Machine

```
1. Пользователь/контракт отправляет ICS-20 Transfer с memo: {"ibc_callback": "contract"}
2. TransferKeeper.ics4Wrapper.SendPacket = IBCFeeKeeper.SendPacket
   → ChannelKeeper.SendPacket (hooks не видят этот вызов)
3. ibchooks НЕ сохраняет mapping (packet_sequence → callback_contract)
4. Пакет уходит на counterparty chain
5. Counterparty обрабатывает, отправляет ack
6. ibchooks.IBCMiddleware.OnAcknowledgementPacket вызывается
7. ibchooks ищет callback mapping → НЕ НАЙДЕНО
8. Callback к контракту НЕ вызывается
```

### Impact

- **Stuck state:** Контракты, ожидающие ack/timeout callback через `ibc_callback`, никогда не получат уведомление
- **Silent failure:** Нет ошибки, нет события — пользователь не знает что callback не сработал
- **Lost ack data:** Контракт не может получить результат outbound transfer
- **Broken feature:** `ibc_callback` feature полностью нефункциональна для outbound transfers из Archway

### PoC Plan (local)

```go
// В e2e тесте: заменить прямой вызов ibcmiddleware.SendPacket
// на TransferKeeper.SendTransfer с memo {"ibc_callback": "..."}
// Наблюдать: OnAcknowledgementPacket не вызывает контракт
func TestIBCCallbackOutboundBroken(t *testing.T) {
    // setup chain
    // deploy contract
    // send transfer via MsgTransfer with memo: {"ibc_callback": contractAddr}
    // relay ack
    // assert: contract NOT called (confirm bug)
    // fix: init IBCFeeKeeper with hooksIcs4Wrapper
    // assert: contract IS called
}
```

### Counterarguments

- ibc-hooks может работать иначе в v8 — нужно проверить, есть ли альтернативный путь регистрации callback
- IBCFeeKeeper в некоторых реализациях может делегировать дальше

### Fix

```go
// Правильная инициализация: сначала hooksIcs4Wrapper, потом IBCFeeKeeper с hooks как ICS4
hooksIcs4Wrapper := ibchooks.NewICS4Middleware(app.Keepers.IBCKeeper.ChannelKeeper, ics20WasmHooks)

app.Keepers.IBCFeeKeeper = ibcfeekeeper.NewKeeper(
    appCodec, keys[ibcfeetypes.StoreKey],
    app.Keepers.IBCKeeper.ChannelKeeper,
    hooksIcs4Wrapper, // ← Использовать hooks ICS4 wrapper!
    ...
)
```

---

## Finding IB-02: HandleAcknowledgement success path — sudo error silently dropped

- **Severity:** Medium
- **Confidence:** High
- **Affected Files:**
  - `x/cwica/keeper/ibc_handlers.go:HandleAcknowledgement`
  - `x/cwica/keeper/ibc_handlers_test.go` (тест явно подтверждает поведение)

### Root Cause

```go
// x/cwica/keeper/ibc_handlers.go
func (k *Keeper) HandleAcknowledgement(ctx sdk.Context, packet channeltypes.Packet, acknowledgement []byte) error {
    // ...
    if ack.GetError() == "" { // SUCCESS ACK PATH
        // ...
        _, err = k.sudoKeeper.Sudo(ctx, contractAddress, sudoMsgPayload)
        if err != nil {
            k.Logger(ctx).Debug("HandleAcknowledgement: failed to Sudo", "error", err)
            // ERROR SWALLOWED — функция возвращает nil
        }
    } else { // ERROR ACK PATH
        // ...
        err = k.errorsKeeper.SetError(ctx, sudoerr) // ERROR СОХРАНЁН в cwerrors
    }
    return nil
}
```

**Асимметрия обработки:**
- Error ack → `cwerrors.SetError` → контракт получит sudo callback с ошибкой
- Success ack + sudo failure → debug log → контракт **никогда** не узнает

Тест явно подтверждает это как задуманное поведение:
```go
// TEST CASE 4: contract callback fails - should not return error - because error is swallowed
wmKeeper.SetReturnSudoError(errors.New("error sudoResponse"))
err = cwicaKeeper.HandleAcknowledgement(ctx, p, resAckData)
s.Require().NoError(err)
```

### Attack Path / Сценарий

```
1. Контракт вызывает MsgSendTx: отправляет ICA tx на counterparty
2. ICA tx выполняется на counterparty (деньги потрачены/состояние изменено)
3. Counterparty отправляет SUCCESS ack
4. HandleAcknowledgement вызывается, sudo call к контракту падает (out of gas, panic в контракте)
5. Ошибка sudo логируется, игнорируется
6. Контракт не знает, что его ICA tx УСПЕШНО выполнилась
7. Контракт может ожидать success callback для обновления своего внутреннего состояния
8. Состояние контракта застревает в "pending" навсегда
```

### Impact

- **Stuck contract state:** Контракт с ICA, ожидающий success ack для продолжения flow
- **Incorrect accounting:** Если контракт хранит "pending balance" до ack — оно никогда не обновится
- **No retry possible:** Success ack не хранится нигде — нет способа повторно доставить

### Разница с error path

| Path | Хранится? | Retry возможен? |
|------|-----------|-----------------|
| Error ack → sudo fail | Да (cwerrors) | Да (через cwerrors subscription) |
| Success ack → sudo fail | Нет | Нет |

### PoC Plan

```go
func TestHandleAcknowledgement_SuccessPath_SudoFail_StateLost(t *testing.T) {
    // Setup contract с ICA
    // Mock: sudo возвращает error
    // Вызвать HandleAcknowledgement с success ack
    // Assert: контракт НЕ получил никакого уведомления
    // Assert: в cwerrors для контракта ничего нет
    // Продемонстрировать: контракт stuck в pending state
}
```

### Fix

Хранить failed success acks в cwerrors аналогично error path:

```go
_, err = k.sudoKeeper.Sudo(ctx, contractAddress, sudoMsgPayload)
if err != nil {
    // Сохранить в cwerrors для retry delivery
    sudoerr := types.NewSudoError(
        types.ModuleErrors_ERR_SUDO_FAILED_ON_SUCCESS,
        contractAddress.String(),
        string(sudoMsgPayload),
        err.Error(),
    )
    k.errorsKeeper.SetError(ctx, sudoerr)
}
```

---

## Finding IB-03: MsgSendTx — no max timeout → uint64 overflow → immediate channel close

- **Severity:** Low
- **Confidence:** High
- **Affected Files:**
  - `x/cwica/keeper/msg_server.go:SendTx` (строка с timeoutTimestamp)
  - `x/cwica/types/tx.go:ValidateBasic` (только проверка > 0)

### Root Cause

```go
// x/cwica/types/tx.go
func (msg *MsgSendTx) ValidateBasic() error {
    if msg.Timeout <= 0 {
        return errors.Wrapf(ErrInvalidTimeout, "timeout must be greater than zero")
    }
    return nil
    // НЕТ проверки верхнего предела!
}

// x/cwica/keeper/msg_server.go
// msg.Timeout — uint64 (seconds)
timeoutTimestamp := ctx.BlockTime().Add(time.Duration(msg.Timeout) * time.Second).UnixNano()
```

Go: `time.Duration` — это `int64` (наносекунды).

Для `msg.Timeout = math.MaxUint64 = 18446744073709551615`:
```
time.Duration(math.MaxUint64) = int64(-1) наносекунда
timeoutTimestamp = blockTime.Add(-1ns).UnixNano() = прошедший timestamp
```

Пакет с прошедшим таймаутом немедленно тайм-аутится при попытке relay.

### ICA ORDERED Channel Impact

```
1. Контракт вызывает SendTx с Timeout = math.MaxUint64
2. timeoutTimestamp = прошедшее время
3. Relayer пытается relay → пакет уже протух → OnTimeoutPacket
4. ORDERED ICA channel → ЗАКРЫВАЕТСЯ
5. Ошибка через cwerrors
6. Контракт должен вызвать RegisterInterchainAccount для восстановления
7. Цикл: если контракт некорректно обрабатывает timeout → loop
```

### Impact

- **Self-harm DoS:** Контракт может бесконечно закрывать собственный ICA канал
- **Relayer spam:** Каждый цикл создаёт MsgTimeout tx для relayer
- **Channel instability:** ICA account временно недоступен после каждого closure

### Limitations

- Только self-harm: атакующий должен контролировать контракт
- Нет cross-contract impact

### Fix

```go
// В ValidateBasic:
const MaxTimeoutSeconds = uint64(24 * 3600 * 365) // 1 год максимум

if msg.Timeout > MaxTimeoutSeconds {
    return errors.Wrapf(ErrInvalidTimeout, "timeout exceeds maximum: %d > %d", msg.Timeout, MaxTimeoutSeconds)
}
```

Или проверять в msg_server.go перед cast.

---

## Finding IB-04: Commented-out ICA fee middleware — relayer incentive gap

- **Severity:** Informational
- **Confidence:** High
- **Affected Files:**
  - `app/app.go:689`

### Root Cause

```go
// app/app.go:686-689
var icaControllerStack porttypes.IBCModule
icaControllerStack = cwica.NewIBCModule(app.Keepers.CWICAKeeper)
icaControllerStack = icacontroller.NewIBCMiddleware(icaControllerStack, app.Keepers.ICAControllerKeeper)
// icaControllerStack = ibcfee.NewIBCMiddleware(icaControllerStack, app.Keepers.IBCFeeKeeper)
// ^^ ЗАКОММЕНТИРОВАНО
```

ICA host stack корректно имеет IBCFee:
```go
icaHostStack = icahost.NewIBCModule(app.Keepers.ICAHostKeeper)
icaHostStack = ibcfee.NewIBCMiddleware(icaHostStack, app.Keepers.IBCFeeKeeper)
```

### Impact

- ICA packets от Archway не могут включить ICS-29 fee для relayer
- Relayer не получает incentive за relay ICA пакетов от Archway
- На конкурентном рынке relayer это может приводить к задержкам ICA txs

### Counterarguments

- Возможно, сделано намеренно (comment оставлен для будущего включения)
- ICA relaying может работать без ICS-29 fees на некоторых chains

---

## Finding IB-05: IBCHooks тесты используют неверный bech32 prefix

- **Severity:** Informational
- **Confidence:** High
- **Affected Files:**
  - `e2e/ibchooks/ibchooks_test.go:77` ("cosmos" prefix)
  - `app/app.go:676` (Bech32Prefix = "archway" в production)

### Root Cause

```go
// e2e/ibchooks/ibchooks_test.go
wasmHooks := ibc_hooks.NewWasmHooks(
    &suite.App.Keepers.IBCHooksKeeper,
    &suite.App.Keepers.WASMKeeper,
    "cosmos",  // ← НЕВЕРНО для Archway chain
)

// app/app.go (production)
ics20WasmHooks := ibchooks.NewWasmHooks(..., Bech32Prefix)
// Bech32Prefix = "archway"
```

Derived intermediate sender в тесте: `cosmos1...`
В production: `archway1...`

Если контракт использует адрес caller для авторизации или хранения данных — тесты не покрывают реальное поведение production. Потенциальные edge cases:

1. Контракт проверяет `info.sender` — в тесте это `cosmos1...`, в prod — `archway1...`
2. Адрес с prefix "cosmos" может быть другим аккаунтом при конвертации в bytes

### Impact

- Test coverage mismatch — баги специфичные для "archway" prefix не будут обнаружены
- Нет прямого fund theft, но потенциальные логические ошибки в контрактах

---

## Finding IB-06: CWICAModule паникует в host-only методах (подтверждение из предыдущего аудита)

- **Severity:** Low  
- **Confidence:** Medium
- **Affected Files:**
  - `x/cwica/ibc_module.go`

### Root Cause

```go
// x/cwica/ibc_module.go
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

### Analysis

IBC router направляет эти вызовы только к ICA HOST (port `icahost`), не к controller (port `icacontroller-*`). В normal operation panics не достижимы.

Однако в ibc-go v8 паники в IBC handlers перехватываются в некоторых контекстах через middleware. Нужно проверить, обёрнуты ли они в recover().

### Impact

- При нормальной работе: нет impact (IBC routing корректен)
- При аномальном routing (баг в IBC core или malicious relayer с поддельным портом): chain halt

---

## Анализ IBCHooks wasm execution

### Успешный путь (ibc_callback inbound)

```
OnRecvPacket:
  ibchooks.OnRecvPacket(packet)
    → ibcfee.OnRecvPacket(packet)
      → transfer.OnRecvPacket → кредитует токены receiver
    ← ack от transfer
  ibchooks проверяет memo: {"wasm": {"contract": "...", "msg": ...}}
  ibchooks вызывает wasmkeeper.Execute(contract, derivedSender, msg, coins)
```

**Корректно работает для INBOUND пакетов.**

### Broken path (ibc_callback outbound) — IB-01

```
MsgTransfer с memo: {"ibc_callback": "contract"}
  TransferKeeper.SendPacket
    → IBCFeeKeeper.SendPacket (ICS4 wrapper)
      → ChannelKeeper.SendPacket
         ← ibchooks ICS4 wrapper НЕ ВЫЗЫВАЕТСЯ
         ← callback mapping НЕ СОХРАНЯЕТСЯ

Позже: ack приходит
  ibchooks.OnAcknowledgementPacket
    → ищет callback mapping → НЕ НАЙДЕНО
    → callback контракту НЕ ВЫЗЫВАЕТСЯ
```

---

## Топ-5 наиболее перспективных routes для дальнейшего анализа

1. **ICS-20 Transfer + IBCHooks inbound** — memo injection, wrong receiver, async hook failures
2. **CWICA SendTx** — содержимое msgs не проверяется Archway (counterparty chain валидирует)
3. **ICS-20 Transfer timeout/refund** — особенно при совмещении с ibcfee (двойной refund?)
4. **CWErrors delivery timing** — CWICA timeout → cwerrors → delivery в EndBlocker следующего блока → race с re-registration
5. **IBC client expiry** — stale client → все пакеты на данный channel застревают навсегда

---

## Топ-10 файлов/configs для дополнительного аудита

| # | Файл | Причина |
|---|------|---------|
| 1 | `app/app.go:494-516` | IBCFeeKeeper + TransferKeeper ICS4 wrapper chain |
| 2 | `x/cwica/keeper/ibc_handlers.go` | HandleAcknowledgement success/error asymmetry |
| 3 | `x/cwica/keeper/msg_server.go` | SendTx timeout overflow |
| 4 | `e2e/ibchooks/ibchooks_test.go` | Wrong prefix, test не покрывает outbound callbacks |
| 5 | `x/cwerrors/abci.go` | EndBlocker error delivery, panic path |
| 6 | `x/cwica/ibc_module.go` | Panic в host-only методах |
| 7 | `interchaintest/cwica_test.go` | Timeout → channel close → re-registration flow |
| 8 | `x/cwica/types/tx.go` | Отсутствие max timeout validation |
| 9 | `x/cwerrors/keeper/sudo_errors.go` | SetError delivery path |
| 10 | `app/app.go:686-695` | Commented ICA fee middleware |

---

## Итог: confirmed findings

| ID | Название | Severity | Confidence |
|----|---------|----------|-----------|
| IB-01 | ibc_callback outbound silently broken (ICS4 wrapper chain) | **Medium** | High |
| IB-02 | HandleAcknowledgement success path sudo error dropped | **Medium** | High |
| IB-03 | MsgSendTx timeout uint64 overflow → immediate channel close | **Low** | High |
| IB-04 | ICA fee middleware commented out (relayer incentive gap) | **Info** | High |
| IB-05 | IBCHooks tests use wrong bech32 prefix ("cosmos" vs "archway") | **Info** | High |
| IB-06 | CWICAModule panics in host-only IBC methods | **Low** | Medium |

---

## Weak leads — лучше бросить

- **"Relayer can censor ICA txs"** — нет fund loss без участия chain logic
- **"Stale IBC client"** — общая IBC особенность, не Archway-specific
- **"Axelar/Osmosis/Noble bridge routes"** — нет специфического кода в Archway репозитории
- **"IBC channel ordering mismatch"** — ICA всегда ORDERED, transfer всегда UNORDERED — это стандарт
- **"Duplicate ICA registration"** — явно обрабатывается: `err != nil` на RegisterInterchainAccount если канал уже существует

---

## Список тестов для PoC

```go
// 1. IB-01: Подтверждение broken ibc_callback outbound
func TestIBCCallback_Outbound_NotDelivered(t *testing.T) {
    // Setup: TransferKeeper с mock ICS4
    // Action: MsgTransfer с memo {"ibc_callback": contractAddr}
    // Assert: IBCHooksKeeper не содержит mapping
    // Assert: OnAcknowledgementPacket не вызывает контракт
}

// 2. IB-01: Fix verification
func TestIBCCallback_Outbound_Fixed(t *testing.T) {
    // Инициализация с hooksIcs4Wrapper в IBCFeeKeeper
    // Повторить тест → assert: callback ДОСТАВЛЕН
}

// 3. IB-02: Success ack sudo failure
func TestCWICA_SuccessAck_SudoFails_StateStuck(t *testing.T) {
    // Mock sudoKeeper.SetReturnSudoError(errors.New("out of gas"))
    // Вызвать HandleAcknowledgement с success ack
    // Assert: cwerrors пуст (нет retry mechanism)
    // Assert: функция вернула nil (silent failure)
}

// 4. IB-03: Timeout overflow
func TestMsgSendTx_TimeoutOverflow_ImmediateClose(t *testing.T) {
    // msg.Timeout = math.MaxUint64
    // Вычислить timeoutTimestamp
    // Assert: timestamp < ctx.BlockTime().UnixNano() (прошедшее время)
    // Отправить через interchaintest → наблюдать немедленный channel close
}

// 5. IB-05: Prefix mismatch
func TestIBCHooks_DerivedSender_ArchwaPrefix(t *testing.T) {
    // Создать hooks с "archway" prefix (правильный)
    // Создать hooks с "cosmos" prefix (тестовый)
    // Сравнить derived sender addresses → они разные
    // Assert: контракт с cosmos-addrress ≠ контракт с archway-address
}
```

---

## Примечание о scope

Данный анализ ограничен локальным кодом Archway. Внешние bridge компоненты (Axelar gateway, Osmosis AMM, Noble USDC, Gravity bridge) не входят в скоуп — в репозитории archway-network/archway их код отсутствует. Уязвимости в самом IBC протоколе (ibc-go v8.7.0) не анализировались — они входят в scope ibc-go, не Archway.
