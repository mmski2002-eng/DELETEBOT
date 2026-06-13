# Hipo Finance — Security Research Report

**Протокол:** HipoFinance/contract  
**Язык:** FunC  
**Аудиты пройдены:** 4 (последний — Quantstamp, апрель 2025)  
**Дата анализа:** 2026-05-05  
**Scope:** treasury.fc, wallet.fc, parent.fc, collection.fc, bill.fc, loan.fc

---

## Методология

1. Инвентаризация контрактов и op codes
2. Трассировка deposit/withdrawal flow
3. NFT mint/burn/transfer механика
4. Exchange rate корректность
5. Referral и reward система
6. Privileged операции и upgrade механизм
7. Async/bounce failure сценарии

---

## CRITICAL

---

### [C-01] Пустые bounce handlers — необратимая потеря средств

**Severity:** Critical  
**Exploitability:** Нет специальной позиции. Достаточно сетевых условий (congestion, недостаток газа у получателя, frozen account).  
**Impact:** Необратимая потеря пользовательских средств, заморозка раундов.

**Root Cause:**

Все три ключевых контракта имеют полностью пустые `on_bounce`:

```func
// treasury.fc:1851-1857
() on_bounce(slice src, slice s) impure inline {
    s~skip_bits(32);
    int op = s~load_uint(32);
    int query_id = s~load_uint(64);
    throw(0); ;; just accept bounced TON
}

// parent.fc:304-309 — идентичный паттерн
// collection.fc:109-114 — идентичный паттерн
```

**Attack Path A — Instant Deposit (потеря TON):**

```
tx1: User → Treasury (100 TON, text "d")
     deposit_coins():
       total_coins += 100      ;; treasury.fc:240 — STATE ИЗМЕНЁН ДО SEND
       total_tokens += tokens  ;; treasury.fc:241 — STATE ИЗМЕНЁН ДО SEND
       → send proxy_tokens_minted → Parent → Wallet

tx2: Wallet заморожен/нет газа → bounce
     Treasury::on_bounce → throw(0) — проигнорировано

Результат: total_coins/total_tokens завышены, hTON не выдан,
           100 TON заблокированы в протоколе навсегда.
```

**Attack Path B — Deferred Deposit (frozen staking):**

```
tx1: User → Treasury (100 TON, deferred path)
     deposit_coins():
       total_staking += 100   ;; treasury.fc:252
       → send mint_bill → Collection

tx2: Collection bounce → Treasury::on_bounce → ignored

Результат: total_staking растёт без соответствующего Bill.
           При финализации раунда — несоответствие учёта.
```

**Attack Path C — Bill Burn Chain DoS:**

```
tx1: Раунд финализируется → Collection::burn_next(0)
tx2: Bill[N] заморожен (storage fee исчерпан)
     burn_bill → bounce → collection::on_bounce → throw(0)
     burn_next(N+1) НИКОГДА не вызывается
     last_bill_burned НИКОГДА не отправляется в Treasury

Результат: Раунд навсегда в состоянии "burning".
           Все deferred depositors и unstakers заблокированы.
```

**Рекомендация:**  
Реализовать полный state rollback в `on_bounce` для каждого op. Для collection — при bounce от Bill пропускать frozen Bill и продолжать chain: `burn_next(index+1)`.

---

### [C-02] upgrade_code без timelock — мгновенный захват протокола

**Severity:** Critical  
**Exploitability:** Требует компрометации governor ключа.  
**Impact:** Полный захват протокола, кража всех средств.

**Root Cause:**

```func
// treasury.fc:1707-1721
() upgrade_code(slice src, slice s) impure inline {
    ...
    throw_unless(err::access_denied, equal_slice_bits(src, governor));
    set_code(new_code);                       // МГНОВЕННЫЙ апгрейд, нет задержки
    set_c3(new_code.begin_parse().bless());
    upgrade_data(src, query_id, new_data, return_excess);
}

// treasury.fc:1723-1743
() proxy_upgrade_code(...) impure inline {
    // Governor апгрейдит Parent и любой child контракт — тоже без timelock
    throw_unless(err::access_denied, equal_slice_bits(src, governor));
    send_msg(true, destination, ..., upgrade_code, ...);
}
```

**PoC:**
```
tx1: Governor → Treasury (op::upgrade_code, malicious_code)
     → set_code(malicious_code) немедленно

tx2: Attacker → Treasury (любой op из malicious_code)
     → дренаж total_coins + treasury_storage

Результат: Все средства украдены за 2 транзакции.
```

**Примечание:** Governor заявлен как multisig — операционная мера, не onchain защита.

**Рекомендация:** Timelock 48-72h аналогично `propose_governor` (24h, treasury.fc:1300). Паттерн уже есть в кодовой базе.

---

### [C-03] set_parent без timelock — перехват всего wallet flow

**Severity:** Critical  
**Exploitability:** Требует компрометации governor ключа.  
**Impact:** Все deposit/withdrawal операции перенаправляются на вредоносный контракт.

**Root Cause:**

```func
// treasury.fc:1572-1590
() set_parent(slice src, slice s) impure inline {
    ...
    throw_unless(err::access_denied, equal_slice_bits(src, governor));
    parent = new_parent;   // МГНОВЕННАЯ замена
```

`parent` используется в каждом deposit и withdrawal как router к wallet контрактам (treasury.fc:250, 270, 280, 348, 370, 408, 492).

**PoC:**
```
tx1: Governor → Treasury (op::set_parent, attacker_contract)
     → parent = attacker_contract немедленно

tx2: User → Treasury (100 TON, deposit)
     → proxy_tokens_minted → attacker_contract (вместо real Parent)
     → funds captured

Результат: Все новые депозиты перехвачены.
```

**Рекомендация:** Timelock 48h + двухшаговое подтверждение как у `propose_governor`.

---

## HIGH

---

### [H-01] Deferred depositors всегда получают худший exchange rate

**Severity:** High  
**Exploitability:** Нет. Структурная проблема.  
**Impact:** Систематические потери для всех deferred depositors.

**Root Cause:**

Instant deposit минтит по текущему rate (treasury.fc:237):
```func
tokens = muldiv(coins, total_tokens, total_coins);  // rate NOW
```

Deferred deposit минтит при финализации раунда — `mint_tokens` (treasury.fc:392-395):
```func
tokens = muldiv(coins, total_tokens, total_coins);  // rate AT ROUND END
```

К концу раунда `total_coins` вырос от validator rewards → rate выше → deferred depositor получает **меньше hTON** за те же TON.

**Пример при 5% годовом yield за раунд:**
```
Instant deposit 100 TON → 100 hTON (rate 1.0)
Deferred deposit 100 TON → 95.2 hTON (rate 1.05 на конец раунда)
Разница: 4.8 hTON ≈ 5 TON потеряно
```

Пользователи, попавшие в deferred path (активный раунд), всегда несут скрытые потери которые нигде не задокументированы в UI flow.

---

### [H-02] Нет slippage protection при unstake

**Severity:** High  
**Exploitability:** Нет. Рыночные условия / tx ordering.  
**Impact:** Пользователь получает значительно меньше TON чем ожидал.

**Root Cause:**

`reserve_tokens` вычисляет выплату из live state (treasury.fc:292-296):
```func
coins = muldiv(tokens, total_coins, total_tokens);
```

Нет параметра `min_amount_out`. Rate может измениться между подписью и исполнением.

**PoC:**
```
t=0: User: rate=1.05, unstake 100 hTON, ожидает 105 TON
t=1: Validator slash → total_coins -= X → rate=0.95
t=2: User tx исполняется → получает 95 TON

Потери: 10 TON (9.5%)
```

**Рекомендация:** Параметр `min_ton_out` в `unstake_tokens` (wallet.fc:155). Проверка в `reserve_tokens` (treasury.fc:284).

---

### [H-03] Halter имеет широкий blast radius без timelock

**Severity:** High  
**Exploitability:** Требует компрометации halter ключа.  
**Impact:** Заморозка протокола, изменение критических параметров.

**Root Cause:**

Halter без timelock может (treasury.fc:1349, 1368, 1383, 1415, 1446, 1468, 1487, 1555):
- `set_stopped` → паузит все новые deposits
- `set_instant_mint` → меняет mint path для всех пользователей
- `set_rounds_imbalance` → меняет кап на validator loans
- `set_halter` → сменить halter на произвольный адрес
- `send_message_to_loan` → произвольное сообщение в Loan контракт
- `retry_distribute/recover/burn` → вмешательство в state машину раундов
- `send_upgrade_wallet` → форсировать upgrade любого wallet

Скомпрометированный halter ≈ частичный контроль над протоколом.

---

### [H-04] Frozen Wallet — hTON безвозвратно заблокирован

**Severity:** High  
**Exploitability:** Нет. Достаточно истощения storage fee у пользователя.  
**Impact:** Пользователь теряет доступ к hTON, средства не возвращаются.

**Root Cause:**

```func
// wallet.fc:97
raw_reserve(wallet_storage_fee(), reserve::at_most);
```

`reserve::at_most` — если баланс ниже порога, резервируется 0. Wallet замораживается TON-механизмом.

При заморозке:
- `unstake_tokens` невозможен (контракт frozen, tx rejected)
- `total_tokens` в Treasury не убывает — dilutes других holders
- Нет механизма rescue: `send_upgrade_wallet` не размораживает аккаунт
- Bill Bills для deferred deposits тоже могут замёрзнуть → [C-01] Path C

**PoC:**
```
t=0: User делает мелкий deferred deposit → Bill создан с минимальным балансом
t+N: Storage fee Bill исчерпана → Bill аккаунт заморожен
t+M: Раунд финализируется → burn_bill → bounce → DoS раунда
```

**Рекомендация:** При mint_bill резервировать TON на хранение на весь срок жизни раунда (2 * validators_elected_for уже используется в utils.fc:390).

---

## MEDIUM

---

### [M-01] governance_fee без верхнего cap — изъятие 100% yield

**Severity:** Medium  
**Exploitability:** Требует governor.  
**Impact:** Все validator rewards идут governor, stakers получают 0.

**Root Cause:**

```func
// treasury.fc:1395
governance_fee = s~load_uint(16);  // диапазон: 0..65535, нет проверки
```

При `governance_fee = 65535`:
```func
// treasury.fc:1186
fee = muldiv(treasury_reward, 65535, 65535);  // = treasury_reward (100%)
new_coins = treasury_reward - fee;             // = 0
total_coins += 0;                              // stakers не получают ничего
```

Нет onchain ограничения. Защита — только доверие к governor.

**Рекомендация:** `throw_unless(err::invalid_parameters, governance_fee <= MAX_FEE)` где `MAX_FEE` = 30% (19660/65535).

---

### [M-02] Нет гарантии монотонности exchange rate

**Severity:** Medium  
**Exploitability:** Нет. Validator slash сценарий.  
**Impact:** hTON holders теряют часть стоимости, нарушение инвариантов интеграций.

**Root Cause:**

```func
// treasury.fc:1210-1212
previous_rate = current_rate;
if total_tokens {
    current_rate = muldiv(total_coins, 1000000000, total_tokens);
    // нет проверки: current_rate >= previous_rate
}
```

`previous_rate` хранится (treasury.fc:16, 63, 77) но нигде не используется для enforcement. Любой интегратор, полагающийся на монотонный рост rate, может работать некорректно при slash.

---

### [M-03] gift_coins — бесконтрольное изменение rate, MEV вектор

**Severity:** Medium  
**Exploitability:** Любой адрес.  
**Impact:** Rate manipulation, front-running возможности.

**Root Cause:**

```func
// treasury.fc:1832-1848
() gift_coins(slice src, slice s) impure inline {
    int query_id = s~load_uint(64);
    int coins = s~load_coins();
    s.end_parse();
    if total_tokens {
        total_coins += coins;  // нет access check
    }
    raw_reserve(coins, reserve::add_original_balance);
    send_msg(..., unreserved_balance);  // gas возвращается
}
```

Любой может добровольно пожертвовать TON в протокол, мгновенно подняв rate. Создаёт вектор: наблюдатель видит pending `gift_coins` в mempool → покупает hTON → gift исполняется → rate растёт → продаёт с прибылью.

---

### [M-04] Referral и HPO rewards полностью offchain — нет верификации

**Severity:** Medium  
**Exploitability:** Требует доверия к Hipo team.  
**Impact:** Централизованный контроль над распределением наград.

**Root Cause:**

```func
// treasury.fc:196
s~load_msg_addr(); ;; only used to mark the referrer of this deposit on-chain
```

Адрес referrer читается и **сразу выбрасывается**. Нет state changes, нет onchain reward transfer. HPO токен не упоминается ни в одном контракте.

Пользователи не могут верифицировать получение referral reward. При смене команды или инфраструктуры — награды могут быть не выплачены.

---

### [M-05] propose_governor — запись состояния до access check

**Severity:** Medium  
**Exploitability:** Нет. Технически безопасно из-за revert mechanics.  
**Impact:** Опасный паттерн, риск при рефакторинге.

**Root Cause:**

```func
// treasury.fc:1301-1306
proposed_governor = begin_cell()
    .store_uint(accept_after, 32)
    .store_slice(new_governor)
    .end_cell();                  // ЗАПИСЬ В ПАМЯТЬ

throw_unless(err::access_denied, equal_slice_bits(src, governor));  // ПРОВЕРКА

pack_extension();  // НЕ ВЫЗЫВАЕТСЯ при throw → storage не обновляется
```

Запись reverts при throw (pack_extension не вызывается → set_data не вызывается → storage не изменён). Технически не уязвимость, но нарушает CEI паттерн. При любом будущем рефакторинге с перемещением `pack_extension()` — превращается в реальную уязвимость.

Аналогичный паттерн в `set_governance_fee` (treasury.fc:1395 vs 1398).

**Рекомендация:** Перенести все записи в globals ПОСЛЕ access check.

---

## LOW

---

### [L-01] NFT Bill нетрансферабельна — нет DeFi composability

**Severity:** Low  
**Exploitability:** Нет.  
**Impact:** Pending positions не могут использоваться как collateral или торговаться.

**Root Cause:**

`bill.fc:215-246` — нет обработчика `op::transfer_ownership`. Единственные ops: `assign_bill`, `burn_bill`, `destroy`, `prove_ownership`, `request_owner`, `get_static_data`. `owner` устанавливается один раз в `assign_bill` (bill.fc:40) и не меняется.

По дизайну. Но нестандартно относительно TEP-62 и ограничивает composability.

---

### [L-02] Withdrawal rate зависит от tx ordering

**Severity:** Low  
**Exploitability:** Нет специальной позиции. Ограниченный MEV в TON.  
**Impact:** Незначительное отклонение rate для instant unstake.

**Root Cause:**

В TON сообщения обрабатываются последовательно. `reserve_tokens` читает `total_coins/total_tokens` в момент исполнения. Если `recover_stake_result` (обновляет rate, treasury.fc:1210-1212) попал в очередь перед unstake — пользователь получает post-reward rate. Нет TWAP, нет snapshot механизма.

---

### [L-03] parent::on_bounce полностью пустой

**Severity:** Low (covered C-01)  
**Exploitability:** Нет специальной позиции.  
**Impact:** Bounced proxy сообщения не откатывают state в Parent.

**Root Cause:**

Parent хранит `total_tokens` (parent.fc:3, 39, 128, 183, 203). При bounce `proxy_tokens_minted` или `proxy_tokens_burned` — `total_tokens` в Parent расходится с реальным состоянием. Влияет на `get_jetton_data()` (parent.fc:392-396) который используется всеми Jetton-совместимыми интеграторами.

---

## Сводная таблица

| ID | Название | Severity | Требует | Impact |
|----|----------|----------|---------|--------|
| C-01 | Пустые bounce handlers | Critical | Сетевые условия | Потеря средств / DoS раунда |
| C-02 | upgrade_code без timelock | Critical | Governor key | Захват протокола |
| C-03 | set_parent без timelock | Critical | Governor key | Перехват wallet flow |
| H-01 | Deferred depositors — худший rate | High | — | Систематические скрытые потери |
| H-02 | Нет slippage protection | High | — | Неожиданные потери при unstake |
| H-03 | Halter широкий blast radius | High | Halter key | Заморозка / изменение параметров |
| H-04 | Frozen wallet — hTON заблокирован | High | Storage exhaustion | Потеря доступа к средствам |
| M-01 | governance_fee без cap | Medium | Governor | Изъятие 100% yield |
| M-02 | Нет монотонности rate | Medium | Validator slash | Потеря стоимости hTON |
| M-03 | gift_coins rate manipulation | Medium | Любой | MEV / front-running |
| M-04 | Referral/HPO offchain | Medium | Доверие | Централизация наград |
| M-05 | propose_governor write-before-check | Medium | — | Опасный паттерн |
| L-01 | NFT нетрансферабельна | Low | — | Нет composability |
| L-02 | Withdrawal rate ordering | Low | MEV | Незначительное отклонение |
| L-03 | parent::on_bounce пустой | Low | Сетевые условия | Расхождение total_tokens |

---

## Рекомендации

### Критические (немедленно)

1. **Bounce handlers**: Полный state rollback для каждого op. Collection — при bounce от Bill продолжать chain (`burn_next(index+1)`), а не останавливаться.

2. **upgrade_code timelock**: 48-72h задержка. Паттерн `propose/accept` уже есть (treasury.fc:1291-1337).

3. **set_parent timelock**: Аналогичный двухшаговый механизм с 48h задержкой.

### Высокие

4. **Slippage protection**: Параметр `min_ton_out` в `unstake_tokens`. Проверка в `reserve_tokens`.

5. **Minimum Bill balance**: Резервировать TON при `mint_bill` для покрытия storage всего раунда.

6. **Halter restriction**: Отделить emergency ops (set_stopped) от параметрических (set_rounds_imbalance). Последние — только governor.

### Средние

7. **governance_fee cap**: Onchain максимум 30% (19660/65535).

8. **Rate monotonicity**: Assert `new_rate >= current_rate` при нормальных условиях. Slash — отдельный explicit флаг.

9. **CEI pattern**: Перенести все записи в globals после access check во всех privileged функциях.

---

*Анализ проведён на основе кода репозитория HipoFinance/contract, commit HEAD (shallow clone, 2026-05-05).*  
*Не является финальным аудитом. Требует верификации командой протокола и подтверждения через тесты.*
