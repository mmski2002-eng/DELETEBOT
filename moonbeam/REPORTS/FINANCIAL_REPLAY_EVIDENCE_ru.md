# Финансовые replay-кандидаты: CallPermit nonce rollback — Moonbeam

**Дата анализа:** 2026-05-14  
**Уязвимость:** CallPermit precompile `0x000000000000000000000000000000000000080a` — nonce rollback при revert subcall  
**Механика:** `failed dispatch()` → публичные `v/r/s` в calldata → nonce не потреблён → любой может переиграть тот же calldata позже

---

## Executive Summary

Найдено **два on-chain случая**, где failed CallPermit dispatch содержал вложенный финансовый вызов `approve(spender, MAX_UINT256)` на **DIODE ERC-20 token**. Подтверждён nonce rollback (nonce после failed dispatch = nonce до него). Replay window существовало. Один случай имеет **cryptographically verified nonce rollback** (EIP-712 signature match до и после failed tx).

---

## Finding 1 — ПОДТВЕРЖДЁННЫЙ NONCE ROLLBACK + ФИНАНСОВЫЙ INNER CALL

### Метаданные транзакции

| Поле | Значение |
|------|---------|
| **TX Hash** | [`0xcd422a3a...fbebd`](https://moonbeam.moonscan.io/tx/0xcd422a3a9a3525b965f541d6b0537e846e37b38f520099077fe9b1ad792fbebd) |
| **Network** | Moonbeam (chainId 1284) |
| **Block** | 15441926 |
| **Block timestamp** | 2026-04-30T21:07:18Z |
| **Status** | `0x0` (failed / reverted) |
| **Dispatcher** | `0x937C492A77aE90DE971986d003fFbc5f8bb2232C` |
| **Signer (from)** | `0xb5A36021e107037F8b844766C6a7dB70e39d3F46` |
| **Target (to)** | `0x553FD260607B6D82474Aa06685eF6c2366647D7A` |
| **Signed nonce** | **4** |
| **Deadline** | 1777586833 → `2026-04-30T22:07:13Z` |

### Доказательство nonce rollback

| Проверка | Результат |
|----------|---------|
| nonce до failed tx (block 15441925) | **4** |
| nonce после failed tx (block 15441926) | **4** |
| EIP-712 signature verification | ✅ PASS — sig восстанавливает `0xb5A3...` |
| Текущий nonce (2026-05-14) | **4** — нonce НЕ потреблён до сегодняшнего дня |

**Вывод:** `dispatch()` откатился полностью включая инкремент nonce. Подпись с nonce=4 осталась публичной и переиспользуемой.

### Декодирование inner call

**Selector вызова к Target:** `0x130dbfbb` = `SubmitTransaction(address ca, bytes data)`

```
SubmitTransaction(
  ca   = 0x434116a99619f2b465a137199c38c1aab0353913  ← DIODE ERC-20 token
  data = 0x095ea7b3                                 ← approve(address,uint256)
         000000000000000000000000
         c933776da2f9fdc1e4531ad592a3fe5d0d964737  ← spender
         ffffffffffffffffffffffff...ffff            ← amount = MAX_UINT256
)
```

**Что делает inner call:**  
Submits a transaction to the multisig wallet `0x553FD260...` for execution of:
```
DIODE.approve(0xc933776da2f9fdc1e4531ad592a3fe5d0d964737, type(uint256).max)
```

### Идентификация контрактов

| Адрес | Тип | Имя |
|-------|-----|-----|
| `0x434116a99619f2b465a137199c38c1aab0353913` | ERC-20 token | **DIODE** (symbol: DIODE) |
| `0x553FD260607B6D82474Aa06685eF6c2366647D7A` | Smart contract (495 bytes) | Wallet / multisig |
| `0xc933776da2f9fdc1e4531ad592a3fe5d0d964737` | Smart contract (480 bytes) | Spender (authorized for MAX allowance) |

### Replay window

| Параметр | Значение |
|----------|---------|
| Window start | Block 15441926 (2026-04-30T21:07:18Z) — момент failed tx |
| Window end | 2026-04-30T22:07:13Z — истечение deadline |
| Длительность | **~1 час** |
| Статус сегодня | ❌ Expired — replay невозможен (deadline прошёл) |

**Во время окна:** любой observer calldata мог выполнить:
```javascript
// Replay with any address
await provider.sendTransaction({
  to: "0x000000000000000000000000000000000000080a",
  data: originalFailedTxInput,  // exact calldata from 0xcd422a3a...
  from: anyAddress,             // dispatcher NOT in signed payload
});
```

### Impact

Если бы replay был выполнен в течение 1 часа:
1. Multisig `0x553FD260...` выполнил бы `DIODE.approve(spender, MAX_UINT256)` 
2. Spender `0xc933776d...` получил бы unlimited allowance на DIODE токены multisig
3. Spender мог бы вызвать `DIODE.transferFrom(multisig, attacker, balance)` — **полный drain DIODE из multisig**

---

## Finding 2 — ДИОД + SAME PATTERN, ДРУГОЙ MULTISIG

### Метаданные транзакции

| Поле | Значение |
|------|---------|
| **TX Hash** | [`0x93153619...985`](https://moonbeam.moonscan.io/tx/0x93153619331c6ae3154e1792254d3d9c73a1baaeeb11dbeea8cff37603aba985) |
| **Network** | Moonbeam (chainId 1284) |
| **Block** | 15556164 |
| **Status** | `0x0` (failed / reverted) |
| **Dispatcher** | `0x68e0bafdda9ef323f692fc080d612718c941d120` |
| **Signer (from)** | `0xb73B78353Fb704FC6fd0c9a3350Be4942F3846F8` |
| **Target (to)** | `0xE664535Edfe130C9E7250DA50fddfbe2413f12Fc` |
| **Deadline** | 1778350673 → `2026-05-09T18:17:53Z` |

### Декодирование inner call

**Идентичный паттерн:**
```
SubmitTransaction(
  ca   = 0x434116a99619f2b465a137199c38c1aab0353913  ← DIODE ERC-20 token (тот же!)
  data = approve(0xc933776da2f9fdc1e4531ad592a3fe5d0d964737, MAX_UINT256)
)
```

- Тот же DIODE token
- Тот же spender
- Та же сумма MAX_UINT256
- Другой multisig: `0xE664535E...`
- Другой signer: `0xb73B...`

### Статус nonce

| Параметр | Значение |
|----------|---------|
| Текущий nonce signer | 9 (продвинулся — window CLOSED) |
| Deadline | 2026-05-09T18:17:53Z (expired) |
| Replay статус | ❌ Невозможен (nonce потреблён + deadline истёк) |

---

## Контекст: связанные failed txs одного кластера

На блоке ~15556162 диспетчер `0x68e0bafdda...` инициировал несколько CallPermit dispatch для signer `0xb73B...`:

| TX | Block | Inner call | Target |
|----|-------|-----------|--------|
| `0xf69757c1...` (block 15556162) | dispatch → `0xAf7De307...` | `0x38b5bc9c` (credential/cert fn) | — |
| `0x93153619...` (block 15556164) | dispatch → `0xE664535E...` | SubmitTransaction → **approve DIODE MAX** | DIODE token |

Оба failed, оба публичны в calldata.

---

## Методология верификации

### 1. Сканирование (scan_bounty_callpermit_candidates.js)
- Batch-запросы `eth_getBlockReceipts` по диапазонам блоков
- Фильтр: `to == CallPermit && status == 0x0 && input starts with 0xb5ea0966`
- Декодирование `dispatch(from, to, value, data, gaslimit, deadline, v, r, s)`

### 2. EIP-712 верификация (Finding 1)
```javascript
const domain = {
  name: "Call Permit Precompile", version: "1",
  chainId: 1284,
  verifyingContract: "0x000000000000000000000000000000000000080a"
};
const recovered = ethers.verifyTypedData(domain, types,
  { from, to, value, data, gaslimit, nonce: 4, deadline },
  { v: 28, r: "0xf7c58aa6...", s: "0x7f6d2311..." }
);
// recovered === "0xb5A36021e107037F8b844766C6a7dB70e39d3F46" ✅
```

### 3. Nonce rollback verification (Finding 1)
```javascript
// nonces(address) = selector 0x7ecebe00
const nonceBefore = await eth_call(CallPermit, "0x7ecebe00" + signer, block - 1); // → 4
const nonceAfter  = await eth_call(CallPermit, "0x7ecebe00" + signer, block);     // → 4
// nonceBefore === nonceAfter → CONFIRMED rollback ✅
```

### 4. Inner call decode
```
innerData[0:4]   = 0x130dbfbb → SubmitTransaction(address,bytes)
innerData[16:36] = 0x434116a9... → DIODE token address
innerData[100:104] = 0x095ea7b3 → approve(address,uint256)
innerData[116:136] = 0xc933776d... → spender
innerData[136:200] = 0xffff...ff → MAX_UINT256
```

---

## Итоговые утверждения

1. **Nonce rollback подтверждён on-chain (Finding 1):** EIP-712 signature верифицирована, nonceBefore = nonceAfter = 4 (до и после failed dispatch). Nonce остаётся 4 и сегодня (2026-05-14) — через 2 недели после инцидента.

2. **Финансовый inner call:** обе операции содержали `approve(spender, MAX_UINT256)` на реальный ERC-20 токен DIODE. Это не permission change, не обновление настроек — это прямая авторизация неограниченного расходования токенов.

3. **Replay window существовало:** 1 час после failed dispatch (Finding 1). В этом окне любой observer мог replay без разрешения signer.

4. **Прямой финансовый ущерб при replay:** спендер получил бы unlimited allowance → мог дренировать все DIODE из multisig через `transferFrom`.

5. **Impact не ограничен "relayer gas griefing":** атака направлена на изменение on-chain state (ERC-20 allowance) с последствием потенциальной потери токенов.

---

## Файлы и инструменты

| Файл | Назначение |
|------|-----------|
| `research/financial_replay_finder.js` | Скрипт анализа (создан в этой сессии) |
| `research/scan_bounty_callpermit_candidates.js` | Исходный сканер (EIP-712 + nonce verify) |
| `research/failed_callpermit_moonbeam_50k.json` | 98 failed dispatch txs (block 0–50k) |
| `research/bounty_candidates_moonbeam_100k_150k.jsonl` | EIP-712-verified кандидаты |
| `REPORTS/BOUNTY_GRADE_CallPermit_Replay_Proof_ru.md` | Fork replay PoC отчёт |
