# Nad.fun — Аудит безопасности (Monad Mainnet)

**Дата:** 2026-05-10  
**Цель:** Только production контракты, mainnet транзакции, реально эксплуатируемые HIGH/CRITICAL уязвимости  
**Источники:** GitHub репозиторий `naddotfun/contracts`, v3 ABI (`contract-v3-abi`), Beosin audit (5 Low, 3 Info — Jul 2025)

---

## Адреса контрактов (Monad Mainnet)

| Контракт | Адрес |
|----------|-------|
| BONDING_CURVE | `0xA7283d07812a02AFB7C09B60f8896bCEA3F90aCE` |
| BONDING_CURVE_ROUTER | `0x6F6B8F1a20703309951a5127c45B49b1CD981A22` |
| DEX_ROUTER | `0x0B79d71AE99528D1dB24A4148b5f4F865cc2b137` |
| DEX_FACTORY | `0x6B5F564339DbAD6b780249827f2198a841FEB7F3` |
| LENS | `0x7e78A8DE94f21804F7a17F4E8BF9EC2c872187ea` |
| WMON | `0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A` |

**Архитектура v3:** Один контракт `BondingCurve` управляет всеми токенами через маппинг `curves(token)`. GitHub репозиторий (v1/v2) — устаревший код, не деплоится.

---

## Статус валидации находок

| # | Severity | Находка | Статус |
|---|----------|---------|--------|
| 1 | CRITICAL | sellPermit frontrunning (кража proceeds) | **INVALID** — owner = msg.sender, чужая подпись не работает |
| 2 | HIGH | graduate() без access control | **INVALID** — whitelist защита подтверждена |
| 3 | HIGH | wNative donation desync (price manipulation) | **INVALID** — v3 не уязвим |
| 4 | HIGH | exactOutSellPermit — `to` frontrunning | **INVALID** — тот же механизм защиты что #1 |
| 5 | HIGH | Lock.lock() без access control | **NEEDS MAINNET TEST** — Lock не верифицирован |
| 6 | HIGH | _checkTarget() strict equality DoS | **INVALID** — v1/v2 GitHub, не в v3 |
| 7 | CRITICAL | setConfig() admin drain | **INVALID** — функция не существует в deployed BC |
| 8 | HIGH | listing() manipulation через donation | **INVALID** — зависит от #2 и #3, оба невалидны |
| NEW | ~~HIGH~~ | BC.buy()/BC.sell() без EXECUTOR_ROLE — fee bypass | **INVALID** — fee внутри BC, bypass невозможен |

---

## Находка #1 — INVALID: Frontrunning sellPermit

**Статус: INVALID**

**Причина:** Router принудительно использует `msg.sender` как `owner` в вызове `token.permit()`.

**Доказательство (байткод Router, byte 1638):**
```
...1663 d505accf 33 30 60408601...
         ↑       ↑  ↑
  PUSH4(permit) CALLER ADDRESS
               (msg.sender) (router=spender)
```

Вызов: `token.permit(msg.sender, address(router), amountAllowance, deadline, v, r, s)`

**Почему атака не работает:**
- Пользователь подписал permit для `owner = себя` (свой адрес закодирован в хэше)
- Атакующий (msg.sender=attacker) вызывает sellPermit с чужой подписью
- Router вызывает `permit(attacker, router, ...)`
- Токен: `ecrecover(hash_with_attacker) = victim ≠ attacker` → **REVERT**

`to` не покрыт подписью — факт верный. Но атакующий не может подставить чужую (v,r,s) потому что owner жёстко привязан к msg.sender.

Находка основана на GitHub v1/v2 где `from` передавался как отдельный calldata-параметр. В v3 deployed Router этого параметра нет.

---

## Находка #2 — INVALID: graduate() без access control

**Статус: INVALID**  
**Причина:** `graduate(address)` (0xff6d8d05) существует в BC, но защищена whitelist-проверкой через `mapping(address => bool)` в storage slot 13. Вызов от произвольного адреса ревертится с `0x0b68bdfc` до любой проверки состояния токена.

**Верификация (eth_call):**
```
BC.graduate(real_active_token) from 0xdeadbeef...
→ revert: 0x0b68bdfc (whitelist check, не InvalidToken)
```

Ошибка возникает для dummy AND real токена одинаково → проверяется caller, не токен.  
graduate() в v3 защищена — Finding #2 **не эксплуатируем в deployed контракте**.

---

## Находка #3 — INVALID: wNative donation desync (v3)

**Статус: INVALID для v3**  
**Причина:** В v3 BC.buy() использует delta `WMON.balanceOf(BC) - wMonReserve` как `amountIn`. При donation жертвы нет — атакующий просто платит больше WMON и получает соответственно больше токенов по корректной кривой. Другие пользователи не страдают.

**Верификация:** `BC.wMonReserve() == WMON.balanceOf(BC)` всегда синхронизированы (4,301,535 WMON в обоих на момент проверки). Это отличается от v1/v2 GitHub кода где amountIn передавался как параметр.

**Примечание:** В v1/v2 GitHub уязвимость реальная. В deployed v3 — нет.

---

## Находка #4 — INVALID: exactOutSellPermit — `to` frontrunning

**Статус: INVALID**

Идентичный паттерн `d505accf 33 30` найден на byte 7610 (тело exactOutSellPermit). `owner = msg.sender` в обоих permit-вызовах Router. Атака не работает по той же причине что #1.

---

## Находка #5 — NEEDS MAINNET TEST: Lock.lock() без access control

**Статус: NEEDS MAINNET TEST**  
**Причина:** Lock контракт не идентифицирован в deployed v3 инфраструктуре. Находка основана на GitHub v1/v2 коде. Возможно релевантна для v3 если Lock контракт используется аналогично.

**Что проверить:** Адрес Lock контракта в v3. Если `lock(token, account)` существует без `onlyCore` — уязвимость действительна.

---

## Находка #6 — INVALID: _checkTarget() strict equality DoS

**Статус: INVALID**  
**Причина:** Код GitHub v1/v2, не применим к v3. В v3 graduation управляется через `graduate(token)` с внутренней логикой, отличной от v1/v2 `_checkTarget()`.

---

## Находка #7 — INVALID: setConfig() admin drain

**Статус: INVALID**  
**Причина:** Функция `setConfig` не существует в deployed BC (`0xA7283d07812a02AFB7C09B60f8896bCEA3F90aCE`). Поиск по всем возможным ABI-сигнатурам (3, 5, 6 параметров) дал 0 совпадений в байткоде. Finding основан на предположении из v3 ABI.

---

## Находка #8 — INVALID: listing() manipulation через donation

**Статус: INVALID**  
**Причина:** Зависит от Finding #2 (graduate() без AC) и Finding #3 (donation desync), оба невалидны в v3.

---

## НОВАЯ Находка #9 — INVALID: BC.buy()/BC.sell() без EXECUTOR_ROLE — fee bypass

**Статус: INVALID**

**Причина:** Комиссия протокола берётся ВНУТРИ `BC.buy()`, не в Router. Прямой вызов BC не обходит fee.

### Доказательство (debug_traceTransaction на реальном buy tx 0x31770311...)

Полный трейс внутренних вызовов:
```
Router.buy(value=0x2386f26fc10000):
  → WMON.deposit()                          // wrap MON
  → WMON.transfer(→BC, fullAmount)          // весь amount в BC
  → BC.buy():
      → STATICCALL oracle
      → STATICCALL WMON.balanceOf(BC)
      → CALL WMON.transfer(→foundation, fee) // ← FEE ЗДЕСЬ, внутри BC
      → CALL token.transfer(→buyer)
      → STATICCALL WMON.balanceOf(BC)
```

Foundation address (`0x4ac5fd82b91a10de7f91343ddcca7a2541d3f509`) встроен в байткод BC как immutable — присутствует 6 раз. Router не участвует в fee-логике.

**Почему атака не работает:**
- Атакующий: `WMON.transfer(BC, 1e18)` → `BC.buy(attacker, token)`
- BC.buy() выполняет `WMON.transfer(foundation, fee)` независимо от caller
- Fee удерживается BC до перевода токенов
- Обойти fee без модификации BC невозможно

**Предварительный вывод (ошибочный):** State override симуляция показала `SUCCESS` при прямом вызове BC.buy() — подтвердила отсутствие AC, но не учла что fee берётся внутри BC, а не снаружи. Атака обходит Router, но не обходит fee.

---

## Сводная таблица (финал после верификации)

| # | Контракт | Функция | Severity | Статус | Эксплойт |
|---|----------|---------|----------|--------|-----------|
| 9 | BondingCurve | buy(), sell() fee bypass | ~~HIGH~~ | **INVALID** | fee внутри BC |
| 5 | Lock | lock() unaccounted | **HIGH** | **NEEDS TEST** | Если Lock v3 = v1/v2 |
| 1 | Router | sellPermit frontrunning | ~~CRITICAL~~ | **INVALID** | owner=msg.sender |
| 4 | Router | exactOutSellPermit frontrunning | ~~HIGH~~ | **INVALID** | owner=msg.sender |
| 2 | BondingCurve | graduate() AC | ~~HIGH~~ | **INVALID** | Whitelist slot 13 |
| 3 | BondingCurve | donation desync | ~~HIGH~~ | **INVALID** | v3 delta-механизм |
| 6 | BondingCurve | _checkTarget() DoS | ~~HIGH~~ | **INVALID** | v1/v2 только |
| 7 | BondingCurve | setConfig() | ~~CRITICAL~~ | **INVALID** | Функция не существует |
| 8 | BondingCurve | listing() manipulation | ~~HIGH~~ | **INVALID** | Зависимости невалидны |

---

## Верификационная методология

Все находки верифицированы через (итог: 0 VALID, 1 NEEDS TEST, 8 INVALID):

1. **Байткод анализ** — поиск селекторов, EXECUTOR_ROLE hash, custom error patterns в deployed BC/Router
2. **eth_call симуляция** — прямые вызовы функций на mainnet с `from=attacker`
3. **State override** — Foundry-style state patches для WMON balance (mapping_slot=3)
4. **hasRole проверки** — `BC.hasRole(EXECUTOR_ROLE, ROUTER)=true`, `hasRole(EXECUTOR_ROLE, ATTACKER)=false`
5. **Реальный токен** — `0x73349c43e7c0a5820460aeda215ebef13e337777` (активная кривая, curves() возвращает данные)
6. **Transaction decode** — разбор реального buy() tx `0x31770311...` из блока 73545077

**Используемые RPC:** `https://rpc.monad.xyz` (chainId=0x8F=143, Monad Mainnet)
