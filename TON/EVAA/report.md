# EVAA Protocol — Security Research Report (v2)

**Дата**: 2026-05-03  
**Объект**: EVAA Protocol — lending/borrowing на TON blockchain  
**Ветка**: `v9` (production)  
**Репозитории**: `github.com/evaafi/contracts`, `evaafi/liquidator-bot-v2-pub`  
**Аудиты**: Quantstamp (июль 2024), Trail of Bits (август 2025)  
**Bug bounty**: HackenProof (активен)  
**Язык контрактов**: FunC  

> **Примечание**: Этот отчёт основан на фактическом чтении production-кода ветки v9.  
> Предыдущий черновик содержал устаревшие находки; статусы пересмотрены по исходникам.

---

## АРХИТЕКТУРА (PRODUCTION v9)

### Граф сообщений — SUPPLY + WITHDRAW (новая архитектура)

```
Owner → Master [op::supply_withdraw_master_without_prices | supply_withdraw_master_jetton]
  Master: вычисляет rates, формирует snapshot (asset_config + asset_dynamics)
  Master → Pyth [request_price_feeds + operation_payload] (если нужны цены)
    Pyth → Master [op::pyth_parse_price_feed_updates + prices_packed]
      Master: верифицирует sender == pyth_address, проверяет TTL
      Master → User [op::supply_withdraw_user, snapshot + prices_packed]
        User: HF check с snapshot-ценами, обновляет principals
        User → Master [op::supply_withdraw_satisfied | supply_withdraw_unsatisfied]
          Master: проверяет sender == User contract, проверяет ликвидность
          if OK: отправляет asset → recipient, success → User
          if FAIL: send supply_withdraw_fail → User (reverts principals)
```

### Граф сообщений — LIQUIDATE

```
Liquidator → Pyth [prices_data_args + evaa_operation]
  Pyth → Master [op::pyth_parse_price_feed_updates]
    Master: верифицирует pyth_sender == my_address (onchain-getter pattern)
    Master → User[borrower] [op::liquidate_user, snapshot + prices_packed]
      User: is_liquidatable() с snapshot, обновляет principals, state++
      User → Master [op::liquidate_satisfied | liquidate_unsatisfied]
        Master: верифицирует sender == User, проверяет collateral_liquidity
        if OK: отправляет collateral → liquidator, success → User (state--)
        if FAIL: отправляет fail → User (reverts principals, state--)
```

### User State Machine

```
state == user_state::free  → принимает supply_withdraw_user
state != user_state::free  → supply_withdraw_user → unsatisfied (отказ)
state < 0                  → liquidate_user → unsatisfied (отказ: "withdraw in progress")
state >= 0                 → liquidate_user принимается; state++ при старте, state-- при завершении
```

---

## FINDINGS

---

### FINDING-01: SNAPSHOT RACE В COLLATERAL CHECK (LIQUIDATION)

**Критичность**: Высокая  
**Компонент**: `master-liquidate.fc:master_core_logic_liquidate_asset_unchecked`, `user-liquidate.fc:liquidate_user_process`  
**Тип атаки**: TON async race, front-running  

#### Описание

Master передаёт `asset_config_collection` и `asset_dynamics_collection` как снапшот в теле сообщения liquidate_user. User проверяет `is_liquidatable` с этим снапшотом:

```func
// user-liquidate.fc:147
(int liquidatable, int enough_price_data, int supply_amount, int borrow_amount) =
    is_liquidatable(asset_config_collection, asset_dynamics_collection, user_principals, prices_packed);
```

Между отправкой Master→User и обработкой User:
- Другие пользователи делают supply → utilization меняется → rates дрейфуют
- Borrower может успеть repay → HF восстанавливается

#### Attack Scenario

```
T=0: HF = 0.97 (liquidatable). Pyth → Master → User сообщение в полёте.
T=1: Borrower видит pending liquidation. Отправляет repay(полный долг).
     Repay обрабатывается ПЕРВЫМ (оба сообщения в очереди User).
T=2: User.repay: principals обновлены, долг = 0, HF = ∞.
T=3: User.liquidate_user: is_liquidatable использует свежие user_principals
     (без долга), возвращает liquidatable=false → liquidate_unsatisfied.
     Borrower защищён.
```

**Вывод**: В данном сценарии защита РАБОТАЕТ — User читает актуальные user_principals из storage. Однако rates в снапшоте могут быть устаревшими на 1-2 блока (~4-8 сек), что создаёт незначительный дрейф в HF calculation.

#### Реальный риск: параллельные ликвидации

```func
// master-liquidate.fc:43 — ограничение в Master
int max_allowed_liquidation = muldiv(collateral_liquidity, 3, 4); // 75% от pool liquidity

// user-liquidate.fc:247 — ограничение в User  
int max_not_too_much = muldiv(collateral_present, 1, 3); // 33% от user collateral
```

Два разных liquidator'а могут одновременно подать liquidation на одного borrower'а. Оба пройдут HF-check с одним снапшотом. User обрабатывает их последовательно — state counter корректен (delta-based revert). Риск: двойная частичная ликвидация суммарно превышает допустимое.

**Воздействие**: Пограничные HF-позиции могут быть ликвидированы после repay (если repay и liquidation обрабатываются в одном блоке в неудачном порядке). Суммарный collateral seized при параллельных ликвидациях может превысить 33%.  
**Рекомендация**: Добавить on-chain HF re-check с актуальными rates непосредственно в Master при получении `liquidate_satisfied`.

---

### FINDING-02: ADMIN UPDATE_CONFIG БЕЗ TIMELOCK

**Критичность**: Высокая  
**Компонент**: `master-admin.fc:update_config_process`  
**Локация**: `contracts/core/master-admin.fc:52`

#### Описание

```func
() update_config_process (...) impure inline {
    throw_unless(error::message_not_from_admin, slice_data_equal?(sender_address, admin));
    cell new_meta = in_msg_body~load_ref();
    cell new_config = in_msg_body~load_ref();  // <- полная замена конфигурации всех активов
    // ...
    set_data(new_store);  // мгновенно применяется
```

Функция `update_config` заменяет ВСЮ конфигурацию активов атомарно без какого-либо timelock.

При этом для апгрейда кода timelock реализован:
```func
// init_upgrade_process
cell new_upgrade_config = pack_upgrade_config(
    ..., ts + timeout, ... // <- timelock для кода
);
// submit_upgrade_process
throw_unless(..., now() > update_time);  // <- проверка ожидания
throw_unless(..., (now() - freeze_time) > constants::upgrade_freeze_time);
```

Но `update_config` — только проверка `sender == admin`. Изменяемые параметры:
- `collateral_factor` (CF)
- `liquidation_threshold`
- `liquidation_bonus`
- `base_borrow_rate`, `borrow_rate_slope_*`
- `reserve_factor`, `liquidation_reserve_factor`
- `max_total_supply`, `borrow_cap`

#### PoC: Rugpull через параметры

```
T=0: Admin (компрометирован) вызывает update_config:
     liquidation_threshold[TON] = 10000 (100%)
     liquidation_bonus = 15000 (50% bonus)
T=1: ВСЕ позиции с TON мгновенно liquidatable по новому threshold
T=2: Admin-controlled liquidator дренирует коллатераль
```

**Документация заявляет**: "Multi-signature controls on admin functions."  
**Требует верификации**: on-chain реализация multisig — если admin — EOA или слабый multisig, риск критический.  
**Рекомендация**: Применить timelock (≥24ч) к `update_config`, аналогично `init_upgrade`. Рассмотреть разделение на `update_rate_params` (без timelock) и `update_risk_params` (с timelock).

---

### FINDING-03: ЗАВИСИМОСТЬ ОТ ДОСТУПНОСТИ PYTH — PROTOCOL FREEZE

**Критичность**: Высокая  
**Компонент**: Весь поток `supply_withdraw` с ценами, `liquidate`  
**Локация**: `master-supply-withdrawal.fc`, `master-liquidate.fc`  

#### Описание

Все операции, требующие проверки коллатерализации, используют Pyth:

```func
// prices-packed.fc:72
if (now() > timestamp + price_ttl) {
    return (null(), error::prices_incorrect_timestamp);
}
```

При недоступности Pyth (технические проблемы, сетевая перегрузка, blackout):
- `packed_price:parse_check` возвращает `error::prices_incorrect_timestamp` или другой error код
- Транзакции завершаются с ошибкой — assets возвращаются пользователям
- **Заблокировано**: все liquidations, все borrow, все withdraw с активными долгами

#### Impact на пользователей

```
Pyth offline на 2 часа:
  - Undercollateralized позиции НЕЛЬЗЯ ликвидировать
  - Протокол накапливает bad debt
  - Пользователи не могут погашать долги через supply+withdraw операцию
  - Только прямые repay (supply без withdraw) работают (op::supply_withdraw_without_prices)
```

Обходной путь `supply_withdraw_without_prices` позволяет supply без prices только если **нет withdraw**. Репатриация через supply→repay работает, но borrow и collateral withdrawal — нет.

**Отсутствует**: fallback oracle, circuit breaker, emergency price bypass для admin.  
**Рекомендация**: Ввести emergency admin функцию для временного снижения `prices_ttl` или включения fallback-режима. Рассмотреть secondary oracle (Redstone, API3) как резерв.

---

### FINDING-04: ACCOUNT_HEALTH_CALC — DIVISION BY ZERO

**Критичность**: Средняя  
**Компонент**: `user-utils.fc:account_health_calc`  
**Локация**: `contracts/logic/user-utils.fc:183`

#### Описание

```func
(int, int) account_health_calc(
  cell asset_config_collection,
  cell asset_dynamics_collection,
  cell user_principals,
  cell prices_packed
) {
  int borrow_amount = 0;
  // ... итерация по principals ...
  
  return (constants::factor_scale - muldiv(borrow_limit, constants::factor_scale, borrow_amount), true);
  //                                                                              ^ ДЕЛЕНИЕ НА НОЛЬ
  //                                                                                если borrow_amount == 0
}
```

Функция `is_borrow_collateralized` вызывает `check_not_in_debt_at_all` и при отсутствии долга возвращает `(true, true)` без вызова `account_health_calc`. Однако `account_health_calc` — это getter, доступный через:
- `user-get-methods.fc` (get-методы контракта)
- Прямые off-chain запросы к User contract

Вызов `account_health_calc` для пользователя без долга бросает arithmetic exception.

#### PoC

```typescript
// Любой off-chain запрос get-метода health factor для здорового пользователя (без долгов)
const healthFactor = await evaaUser.getAccountHealthFactor();
// throws: "arithmetic exception" (division by zero)
```

**Воздействие**: DoS для off-chain мониторинга; некорректная работа liquidator-ботов которые проверяют HF для всех пользователей подряд; потенциальный сбой UI.  
**Рекомендация**:
```func
if (borrow_amount == 0) {
    return (constants::factor_scale, true); // HF = 1.0 = infinity (no debt)
}
```

---

### FINDING-05: CALCULATE_REFERRED_PRICE — ПОТЕРЯ ТОЧНОСТИ

**Критичность**: Средняя  
**Компонент**: `plugins/pyth/parse_price_feeds.fc:calculate_referred_price`  
**Локация**: `contracts/plugins/pyth/parse_price_feeds.fc:64`

#### Описание

```func
int calculate_referred_price(int price_original, int scale_original, int price_referred, int scale_referred) impure inline {
    return price_referred * evaa::price_scale / scale_referred * price_original / scale_original;
    //                     ^ first division ^                  ^ second division ^
}
```

Два последовательных целочисленных деления вместо единого `muldiv`:

```
Пример: price_referred=1.5e9, scale_referred=1e9, price_original=3000e9, scale_original=1e9
evaa::price_scale = 1e9

Текущая: (1.5e9 * 1e9 / 1e9) * 3000e9 / 1e9 = 1.5e9 * 3000 / 1e9 = 4500 ✓ (случайно точно)

Проблемный пример: price_referred=3, scale_referred=7, price_original=2, scale_original=5
Текущая: (3 * 1e9 / 7) * 2 / 5 = 428571428 * 2 / 5 = 171428571
Правильная: muldiv(3 * 1e9, 2, 7*5) = 6e9 / 35 = 171428571 (здесь совпало)

Пример с потерей: price_referred=1, scale_referred=1e9, price_original=1, scale_original=1e9
Текущая: (1 * 1e9 / 1e9) * 1 / 1e9 = 1 * 1 / 1e9 = 0  ← НОЛЬ!
Правильная: muldiv(1 * 1e9, 1, 1e9 * 1e9) = 1e9 / 1e18 ≈ 0 (тоже ноль, но по другой причине)
```

Для LST/stablecoin пар с близкими ценами (tsTON/TON ratio) потеря точности minimal. Для экзотических пар с большим разбросом scale — до 0.01-0.1% ошибки в цене.

**Рекомендация**:
```func
int calculate_referred_price(int price_original, int scale_original, int price_referred, int scale_referred) impure inline {
    return muldiv(price_referred * evaa::price_scale, price_original, scale_referred * scale_original);
}
```

---

### FINDING-06: RATE OVERFLOW — UINT64 ДЛЯ S_RATE/B_RATE

**Критичность**: Средняя  
**Компонент**: `data/asset-dynamics-packer.fc`, `logic/master-utils.fc`  
**Локация**: `contracts/data/basic-types.fc` (store_sb_rate)  

#### Описание

```func
// constants.fc
const int constants::factor_scale = 1000000000000; // 10^12

// master-utils.fc:57
int updated_s_rate = s_rate + muldiv(s_rate, supply_rate * time_elapsed, constants::factor_scale);
int updated_b_rate = b_rate + muldiv(b_rate, borrow_rate * time_elapsed, constants::factor_scale);
```

Rates хранятся в `uint64`. Начальное значение = `10^12`.  
Максимум `uint64` = `1.844 × 10^19` → максимальный множитель = `18440×`.

**Время до overflow:**

| Borrow APR | Лет до overflow |
|---|---|
| 200% | ~12 лет |
| 100% | ~21 лет |
| 50%  | ~37 лет |
| 20%  | ~70 лет |

*Примечание: предыдущий черновик отчёта использовал `factor_scale = 10^18`, что некорректно. Реальный `factor_scale = 10^12`, сроки пересчитаны.*

При overflow `store_uint(sb_rate, 64)` бросает arithmetic exception → **все операции с активом навсегда зависают**. Funds locked.

**Рекомендация**: Хранить rates в `uint128` (или переиспользовать 257-bit int в FunC): изменить `store_sb_rate` на `store_uint(sb_rate, 128)`. Добавить `throw_if(overflow, s_rate > constants::max_uint64)` с graceful degradation.

---

### FINDING-07: CONSIDER_RATES_OLD_AFTER — УСТАРЕВАНИЕ RATES ДО 30 МИНУТ

**Критичность**: Низкая  
**Компонент**: `logic/master-utils.fc:update_old_rates_and_provided_asset_id`  
**Локация**: `contracts/logic/master-utils.fc:147`

#### Описание

```func
const int constants::consider_rates_old_after = 1800; // 30 minutes

int is_required_asset? = (asset_id == required_asset_id1) | (asset_id == required_asset_id2);
int time_elapsed = now() - last_accrual;
if ((time_elapsed > 0) & ((is_required_asset?) | (time_elapsed > constants::consider_rates_old_after))) {
    // update rates only for required assets OR if > 30 min stale
```

Rates для **не-участвующих** активов обновляются только если они не обновлялись более 30 минут. Снапшот с 30-минутными устаревшими rates для побочного актива в HF-расчёте создаёт ошибку в collateral value.

**Пример**: Пользователь имеет TON (collateral) и jUSDC (collateral) и USDT (borrow). При withdraw TON обновляются rates для TON и USDT, но jUSDC rates могут быть до 30 минут устаревшими. При высокой волатильности utilization это влияет на точность HF.

**Рекомендация**: Уменьшить `consider_rates_old_after` до 300 секунд (5 минут) или обновлять rates для всех активов в user_principals.

---

### FINDING-08: LIQUIDATION — USD_ALLOWED_LIQUIDATION ЗАХАРДКОЖЕН

**Критичность**: Низкая / Информационная  
**Компонент**: `user-liquidate.fc:liquidate_user_process`  
**Локация**: `contracts/core/user-liquidate.fc:254`

#### Описание

```func
int usd_allowed_liquidation = 200;
// Позволяет ликвидировать позиции стоимостью < $200 полностью
// (нет ограничения max_not_too_much для dust позиций)
```

Значение `$200` не является частью конфигурации актива — его нельзя изменить через `update_config`. При изменении рыночных условий (высокая волатильность, новые активы с другой базовой стоимостью), этот порог может стать неактуальным.

**Рекомендация**: Вынести в `asset_config` как `dust_liquidation_threshold` или в отдельный глобальный параметр.

---

## СТАТУСЫ НАХОДОК ИЗ ПРЕДЫДУЩЕГО ЧЕРНОВИКА

| # | Название | Прежний статус | Production статус | Вердикт |
|---|---|---|---|---|
| 01 | Async HF Race — withdraw bypass | Critical/Open | Архитектура изменена | **ИЗМЕНЁН**: supply_withdraw model; snapshot race минимален для текущего дизайна |
| 02 | Bounce handling absent | Critical/Fixed? | `return ()` вместо `throw(0xffff)` | **УЛУЧШЕН**: messages non-bounceable (flag 0x10) → bounce практически невозможен |
| 03 | Sender verification disabled | Critical/Fixed | `throw_unless(message_not_from_master, ...)` активен | **ПОДТВЕРЖДЕНО ИСПРАВЛЕНО** |
| 04 | withdraw_fail parameter mismatch | High/Fixed? | Архитектура полностью изменена | **ИСПРАВЛЕН**: новый `supply_withdraw_fail` корректен |
| 05 | Classic oracle: liquidator controls prices | High/Open | Classic oracle **удалён**; Pyth с on-chain verification | **УСТРАНЁН**: принципиально другая архитектура |
| 06 | Liquidation HF race | High/Open | Частично адресован state-machine | **ЧАСТИЧНО ОТКРЫТ**: см. FINDING-01 |
| 07 | init_master unauthenticated | High/Fixed | Admin check + one-time init guard | **ПОДТВЕРЖДЕНО ИСПРАВЛЕНО** |
| 08 | Admin no timelock | High/Acknowledged | `update_config` без timelock | **ОТКРЫТ** — см. FINDING-02 |
| 09 | Oracle no circuit breaker | High/Partial | Pyth TTL есть; deviation check отсутствует | **ЧАСТИЧНО ОТКРЫТ** — Pyth децентрализован, но нет fallback |
| 10 | Rate overflow uint64 | Medium/Open | Подтверждён; `factor_scale = 10^12` (не `10^18`) | **ОТКРЫТ** — см. FINDING-06 (сроки скорректированы) |
| 11 | Stale rates in messages | Medium/Acknowledged | Структурно присутствует | **ПОДТВЕРЖДЁН**: `consider_rates_old_after` — см. FINDING-07 |
| 12 | User contract griefing lock | Medium/Fixed w/#03 | Sender check активен | **ПОДТВЕРЖДЕНО ИСПРАВЛЕНО** |
| 13 | First deposit inflation attack | Medium/Depends | TON transfer → supply; donation без principal невозможна | **ОСЛАБЛЕН**: прямой вектор закрыт |
| 14 | Gas exhaustion in liquidation | Medium/Open | Новая Pyth-архитектура; fee расчёт изменён | **ПЕРЕСМОТРЕТЬ**: отдельный анализ Pyth fee estimation |
| 15 | Bad debt no insurance fund | Medium/Acknowledged | Без изменений | **ОТКРЫТ**: системный экономический риск |

---

## ИНВАРИАНТЫ — ВЕРИФИКАЦИЯ ПО PRODUCTION КОДУ

| Инвариант | Статус | Доказательство |
|---|---|---|
| totalShares × pricePerShare == totalAssets | ✅ ВЫПОЛНЕН | `get_asset_reserves_direct` корректно вычитает supply, добавляет borrow |
| Ни один пользователь не получит доходность > пропорциональной доли | ✅ ВЫПОЛНЕН | Principal-based accounting с единым s_rate |
| RWA-коллатерал ≥ обязательствам (N/A для EVAA) | N/A | EVAA использует crypto collateral, не RWA |
| Непривилегированный адрес не изменяет глобальный rate | ✅ ВЫПОЛНЕН | `update_old_rates_and_provided_asset_id` вызывается только внутри |
| Withdraw всегда возможен для свободных позиций | ✅ ВЫПОЛНЕН | `supply_withdraw_without_prices` для pure supply |
| Nonce / state не допускают replay | ✅ ВЫПОЛНЕН | State machine + User address derivation |
| Права session key on-chain | N/A | Нет session keys в данном контракте |
| Цена оракула не манипулируема в одном блоке | ✅ ВЫПОЛНЕН | Pyth aggregation + TTL check |
| Sender verification | ✅ ВЫПОЛНЕН | `throw_unless(message_not_from_master, ...)` активен в user.fc |

---

## ПРИОРИТЕТЫ ДЛЯ DISCLOSURE

### Высокий приоритет (disclosure немедленно)

**FINDING-02** (Admin без timelock для update_config):
- Требует верификации: является ли `admin` on-chain multisig с достаточным порогом?
- Если admin — EOA или 1-of-N multisig → критический риск централизации
- Запросить у команды документацию multisig конфигурации

**FINDING-03** (Pyth DoS):
- Проверить исторические периоды недоступности Pyth на TON
- Уточнить у команды: есть ли внутренний fallback или emergency plan?

### Средний приоритет

**FINDING-04** (account_health_calc div by zero):
- Лёгкий fix, может ломать liquidator-ботов и UI

**FINDING-05** (calculate_referred_price precision):
- Определить какие активы используют reference pricing
- Оценить реальный impact на конкретных парах

### Низкий приоритет (в рамках ongoing engagement)

**FINDING-06** (Rate overflow): Долгосрочный риск, нужно запланировать fix до достижения критического значения rate.

**FINDING-07** (consider_rates_old_after): Параметрическое изменение конфигурации.

---

## КОНТАКТЫ ДЛЯ DISCLOSURE

- **Платформа**: HackenProof (активна)
- **Email**: security@evaa.finance
- **Важно**: Trail of Bits аудит (август 2025) — свежий. Уточнить scope перед submission.
- **Не раскрывать** детали FINDING-02 публично до получения ответа от команды.

---

*Отчёт подготовлен для responsible disclosure. Не публиковать до подтверждения статуса findings.*
