# Verification Report — GetGems NFT Contracts

**Date:** 2026-05-15  
**Verifier role:** статический анализ кода (не testnet)  
**Scope:** FINAL_REPORT.md + AUDIT_LOG.md findings  
**Method:** построчная верификация контрактов vs заявленных anchors  
**Contracts read:** nft-fixprice-sale-v4r1.fc (468L), nft-auction-v3r3.func (503L), nft-auction-v4r1.func (685L), nft-item.fc (143L)

---

## Сводная таблица

| ID | Title | Status | Severity | Evidence type |
|---|---|---|---|---|
| HYP-01 | is_complete=1 без NFT delivery | **CODE-CONFIRMED** | Critical | Static + PoC exists |
| HYP-05 | Fake NFT / no TEP-62 validation | **CODE-CONFIRMED** | Critical (on-chain) | Static |
| HYP-02 | Auction hostage via bid cycling | **CODE-CONFIRMED** | High | Static (logic proof) |
| HYP-06 | Jetton try/catch не ловит action phase | **CODE-CONFIRMED** | High | Architectural (TON VM) |
| HYP-07 | return_last_bid mode=2 silent fail | **CODE-CONFIRMED** | High | Static |
| HYP-03 | op=555 zero time-lock на canceled | **CODE-CONFIRMED** | Medium | Static |
| ABUSE-02 | recv_external griefing | **CODE-CONFIRMED** | Low-Med | Static |

**Ни одна гипотеза не опровергнута.**

---

## HYP-01 — is_complete=1 без NFT delivery

**Claim:**  
Покупатель платит полную цену, sale переходит в `is_complete=1`, но NFT не доставлен — bounce ignored.

**Code anchors:**

`nft-fixprice-sale-v4r1.fc`:
```
:97-113  transfer_nft()
  .store_uint(0x18, 6)         ;; bounce=true (0x18 = 0b011000: bit3=bounce)
  send_raw_message(..., 130)   ;; mode=128+2: нести весь остаток + IGNORE_ERRORS

:172     if (flags & 1) { return (); }   ;; bounce handler — молча игнорирует

:397-428 buy flow:
  send_money(nft_owner_address, user_amount)   ;; :411
  send_money(fee_address, fee_amount)          ;; :412
  send_money(royalty_address, royalty_amount)  ;; :413
  transfer_nft(nft_address, query_id, buyer)   ;; :414
  save_data(1, ...)                            ;; :416  ← COMMITTED ЗДЕСЬ
```

**Детали Vector A (bounce):**  
1. `transfer_nft` отправляется с флагом `0x18` — bounce=true  
2. Если NFT контракт бросает (любая причина: уже передан, frozen, gas, custom logic) → TON создаёт bounce с `flags & 1 = 1`  
3. Bounce приходит обратно в sale → `sale:172: if (flags & 1) { return (); }` — exit без отката  
4. `save_data(1)` уже committed в той же предыдущей транзакции — необратимо  

**Детали Vector B (action phase fail):**  
- mode=130 = mode=128 (carry balance) + mode=2 (IGNORE_ERRORS)  
- Если action phase не может выполнить send — ошибка молча дропается, NO TVM exception  
- `save_data(1)` внутри compute phase уже закончен успешно до action phase  
- Комментарий PASS 8: Vector B ослаблен min_gas check (sale:400) — 0.087 TON остатка достаточно для NFT в нормальных условиях. Vector A не ослаблен ничем.

**Attacker capability:**  
Любой, чей NFT бросает при получении `op::transfer()`. Это достаточно широко: uninitialized NFT, contract с custom logic, cross-workchain try (принудительно провалится `force_chain`).

**Verification method:** статический анализ кода

**Evidence collected:**  
- trace: отсутствует  
- state diff: отсутствует  
- balance delta: отсутствует  
- Code path: **полностью верифицирован построчно**  
  - `sale:107` — bounce=true (`0x18`) в transfer_nft  
  - `sale:113` — mode=130  
  - `sale:172` — bounce handler returns без отката  
  - `sale:416-425` — save_data(1) ПОСЛЕ transfer_nft в compute phase  
- PoC: `01-bounced-nft-loss/poc-testnet.js` существует; TX hash отсутствует

**Result:** CODE-CONFIRMED  
Claim верифицирован статически. Оба вектора подтверждены кодом. Нет ни одного blocking check для Vector A.

**Severity после верификации:** Critical

**What would upgrade confidence:**  
TX hash с testnet: `poc-testnet.js` → `is_complete=1` + `NFT.owner = seller`. Это переведёт статус в SIM-CONFIRMED/TESTNET-CONFIRMED.

**What would downgrade/block it:**  
Bounce handler, который откатывает `is_complete=0` и возвращает деньги покупателю. В текущем коде отсутствует.

---

## HYP-05 — Fake NFT / no TEP-62 validation

**Claim:**  
Нет on-chain TEP-62 проверки. Любой может создать листинг с фейковым NFT контрактом. Покупатель платит реальные TON/jetton, получает мусор.

**Code anchors:**

`nft-fixprice-sale-v4r1.fc`:
```
:29-38   load_static_data() — загружает nft_address из static_data_cell:
  ds~load_msg_addr()   ;; nft_address = просто адрес, без проверки derivation

:330-355 ownership_assigned handler (инициализация sale):
  throw_unless(500, equal_slices(sender_address, nft_address)); ;; :340
  throw_unless(501, op == op::ownership_assigned());            ;; :341
  ;; БОЛЬШЕ НИКАКИХ ПРОВЕРОК
```

**Анализ blocking check:**  
Единственная проверка — `equal_slices(sender_address, nft_address)`.  
Это верифицирует что сообщение пришло ОТ адреса `nft_address`.  
НЕ верифицирует:
- Является ли адрес TEP-62 NFT (collection + index derivation)
- Принадлежит ли NFT к известной коллекции
- Есть ли у адреса легитимный код NFT контракта

**Attacker flow:**
1. Деплой `FakeNFT` на адрес X в workchain 0  
2. `FakeNFT` реализует `op::transfer()` и отправляет `op::ownership_assigned()` при получении  
3. Создать sale с `nft_address = X`  
4. `FakeNFT → ownership_assigned` → sale активирован (check:340 проходит)  
5. Victim `buy` → `send_money×3` → `transfer_nft(X, buyer)` → `FakeNFT.transfer(buyer)` OK  
6. `is_complete=1`. Нет ни одного throw. Victim "владеет" фейком.

**Attacker capability:**  
Любой, кто может деплоить контракт в TON. Нет on-chain барьеров.

**Verification method:** статический анализ

**Evidence collected:**  
- Code path: **верифицирован** — sale:330-355 содержит только address match check  
- Нет registry, нет collection check, нет TEP-62 addr_derivation check  
- nft-item.fc:66 — NFT transfer проверяет только `equal_slices(sender_address, owner_address)` — fake NFT может это имитировать

**Open question (незакрыт):**  
Есть ли off-chain проверка в GetGems backend/indexer? Если да — Impact снижается до Medium. Если нет — Critical для конечных пользователей. Код GetGems backend не исследован.

**Result:** CODE-CONFIRMED  
On-chain нет blockers. Impact зависит от off-chain mitigation.

**Severity после верификации:** Critical (on-chain); условно High при наличии off-chain mitigation

**What would upgrade confidence:**  
Testnet: деплой fake NFT → листинг → buy → `is_complete=1` без ошибок. Это SIM-CONFIRMED.

**What would downgrade/block it:**  
- On-chain: registry доверенных collection addresses  
- On-chain: проверка TEP-62 derivation `hash(collection, index) == nft_address`  
- Off-chain: GetGems indexer валидирует collection + TEP-62 перед показом листинга (если реализовано и неbypassable)

---

## HYP-02 — Auction hostage via bid cycling

**Claim:**  
Griever делает минимальные ставки перед истечением аукциона, продлевая `end_time` бесконечно. `cancel` заблокирован при наличии любой ставки. Защита через 20-day cap неэффективна.

**Code anchors:**

`nft-auction-v3r3.func`:
```
:329  throw_if(exit::cant_cancel_bid(), last_bid > 0)   ;; cancel заблокирован

:364-366  duration = end_time - now()
          throw_if(exit::its_too_log_auc(), duration > 60 * 60 * 24 * 20)  ;; cap

:380-383  if ((end_time - step_time) < now()) {
              end_time += step_time;   ;; продление
          }
```

`nft-auction-v4r1.func`:
```
:427  throw_if(exit::its_too_long_auc(), duration > 60 * 60 * 24 * 20)  ;; cap

:447-449  if ((end_time - step_time) < now()) {
              end_time += step_time;
          }

:537  throw_if(exit::cant_cancel_bid(), last_bid > 0)  ;; cancel заблокирован
```

**Доказательство bypass cap (формально):**

Cap проверяет `end_time - now() > 20 days` — это ТЕКУЩИЙ остаток, не суммарное продление.

```
step_time = T
Griever ждёт пока: end_time - now() ≈ 20d - 2T
Bid → end_time += T → duration ≈ 20d - T  (<20d, cap не срабатывает) ✓
Griever ждёт ещё T секунд: duration ≈ 20d - 2T
Bid → end_time += T → duration ≈ 20d - T ✓
... бесконечно
```

Единственная остановка: `duration + step_time > 20 days` — но attacker контролирует момент bid.

**Стоимость атаки:**  
- `return_last_bid` возвращает `bid - gas_fee ≈ bid - 0.006 TON`  
- Net cost griever ≈ `0.006 TON × N бидов`  
- Захват NFT на 30 дней при step_time=1h ≈ 720 бидов × 0.006 = 4.32 TON  

**Attacker capability:**  
Любой. Нет auth для bid. Нужен только min_bid (~0.1 TON депозит).

**Verification method:** статический анализ + логическое доказательство

**Evidence collected:**  
- code path: **верифицирован** — все три строки (cancel block, cap, extension) подтверждены  
- mathematical proof: cap bypass доказан аналитически  
- testnet confirmation: отсутствует

**Result:** CODE-CONFIRMED  
Все три компонента механизма верифицированы в коде. Cap bypass доказан логически.

**Severity после верификации:** High

**What would upgrade confidence:**  
TEST-02 на testnet: 3 bid + попытка cancel → exit code 1009 + измерение end_time после каждого bid. Это SIM-CONFIRMED.

**What would downgrade/block it:**  
- Cap на суммарное число продлений (counter в state)  
- Разрешение cancel с penalty return при `last_bid > 0`  
- Текущего кода недостаточно для блокировки

---

## HYP-06 — Jetton buy: try/catch не ловит action phase fail

**Claim:**  
`try/catch` в FunC ловит только compute phase exceptions. Action phase failures (failed message sends) не являются TVM exceptions → не перехватываются → `is_complete=1` committed, jettons не доставлены.

**Code anchors:**

`nft-fixprice-sale-v4r1.fc`:
```
:63-95  send_jettons():
  .store_uint(0x10, 6)   ;; nobounce
  int flag = should_carry_gas ? (64 + 2) : (1 + 2);   ;; :93
  send_raw_message(msg, flag)                          ;; :94
  ;; mode включает +2 = IGNORE_ERRORS

:252-278  try/catch block:
  try {
    ...
    send_jettons(sender_address, ..., nft_owner_address, user_amount, ...) ;; :259
    send_jettons(sender_address, ..., fee_address, fee_amount, ...)        ;; :260
    send_jettons(sender_address, ..., royalty_address, ...)                ;; :261
    send_jettons(sender_address, ..., buyer_address, jetton_tail, ...)     ;; :262
    transfer_nft(nft_address, query_id, buyer_address)                     ;; :263
    save_data(1, ...)                                                       ;; :264-273
  } catch (_,_) {                                                           ;; :275
    send_jettons(sender_address, ..., buyer_address, jetton_amount, ...)   ;; refund
    return ();
  }
```

**Архитектурный факт TON VM (не мнение):**

TON выполнение разделено на фазы:
1. **Compute phase** — TVM исполняет код контракта. `try/catch` перехватывает исключения ТОЛЬКО здесь.
2. **Action phase** — после compute phase, TVM обрабатывает накопленную очередь действий (send_raw_message). Ошибки здесь = action phase failures.

`send_jettons` с mode=3 (1+2) → mode=2 (IGNORE_ERRORS) означает: если action phase не может выполнить отправку — ошибка игнорируется, **TVM exception НЕ бросается**.

Следствие:  
- `send_jettons(nft_owner, user_amount)` → action phase fail → NO throw  
- compute phase продолжается → `save_data(1)` выполняется → committed  
- `catch` блок не активируется  
- nft_owner не получает jettons, is_complete=1  

**Attacker capability:**  
Не требует активного attacker. Достаточно что jetton wallet nft_owner отклоняет трансферы (неинициализирован, frozen, неправильный адрес в jetton_price_dict).

**Verification method:** статический анализ + TON VM архитектурный факт

**Evidence collected:**  
- code path: **верифицирован** — send_jettons mode=3 (line:93-94), try/catch (line:252-278), save_data(1) внутри try (line:264)  
- TON VM model: официальная документация — compute phase ≠ action phase  
- local TVM simulation: отсутствует

**Result:** CODE-CONFIRMED (архитектурный)  
Не требует дополнительной верификации по коду. Это фундаментальное свойство TON VM.

**Severity после верификации:** High

**What would upgrade confidence:**  
TEST-04: local TVM sim с jetton_wallet настроенным на reject. Это SIM-CONFIRMED. Но архитектурный статус уже CONFIRMED без simulation.

**What would downgrade/block it:**  
- Bounce handler для `0x18` jetton messages с откатом `is_complete=0`  
- Принципиально невозможно фиксировать через try/catch в TON  
- Единственное решение: change architecture (2-phase commit или проверка баланса)

---

## HYP-07 — return_last_bid mode=2 IGNORE_ERRORS

**Claim:**  
При outbid или max_bid: `return_last_bid` отправляется с mode=2. Если action phase fails — предыдущий bidder теряет ставку. Нет retry, нет bounce handler.

**Code anchors:**

`nft-auction-v3r3.func`:
```
:239-258  return_last_bid():
  builder return_prev_bid = begin_cell()
  .store_uint(0x18, 6)     ;; bounce=true
  .store_slice(last_member)
  .store_coins(return_bid_amount)
  ...
  send_raw_message(return_prev_bid.end_cell(), 2)   ;; :257  mode=2 IGNORE_ERRORS
```

`nft-auction-v4r1.func`:
```
:384-393  return_last_bid():
  builder return_prev_bid = begin_cell()
  .store_uint(0x18, 6)     ;; bounce=true
  .store_slice(last_member)
  .store_coins(return_bid_amount)
  ...
  send_raw_message(return_prev_bid.end_cell(), 2)   ;; :393  mode=2 IGNORE_ERRORS
```

**Bounce handling:**

`nft-auction-v3r3.func:293`:  
`throw_if(0, cs~load_uint(4) & 1)` — bounced message → throw(0) → exit code 0 = success → молча absorbed

`nft-auction-v4r1.func:482`:  
`throw_if(0, cs~load_uint(4) & 1)` — аналогично

**Механизм потери:**
1. Новый bidder → `return_last_bid(prev_bidder)` → mode=2  
2. Если action phase fail (нехватка gas, frozen address, workchain mismatch) → bid потерян  
3. Если delivered но prev_bidder contract throws → bounce → auction absorbs as exit(0) → bid потерян  
4. Нет ни retry, ни recovery механизма  

**Attacker capability:**  
Пассивная потеря — никакого attacker не нужно. Достаточно что `last_member` адрес неdeliverable.  
Активная атака: attacker делает bid с адреса, который будет frozen к моменту outbid.

**Verification method:** статический анализ

**Evidence collected:**  
- code path: **верифицирован** — mode=2 в обоих контрактах (v3r3:257, v4r1:393)  
- bounce handler: **верифицирован** — throw(0) = silent absorb  
- Нет retry, нет separate bounce recovery handler  
- testnet trace: отсутствует

**Result:** CODE-CONFIRMED

**Severity после верификации:** High

**What would upgrade confidence:**  
Testnet: bid с адреса, который затем frozen → check prev bidder balance после outbid.

**What would downgrade/block it:**  
- Bounce handler для return_last_bid сообщений с пересылкой bid обратно в auction  
- Использование mode=64 (carry inbound value) вместо прямой суммы  
- Текущего кода недостаточно для защиты

---

## HYP-03 — op=555 zero time-lock на canceled

**Claim:**  
Cancel устанавливает `sold_at=0`. Time-lock в op=555 обёрнут в `if (sold_at != 0)`. Marketplace может вызвать op=555 немедленно после cancel без ожидания 10 минут.

**Code anchors:**

`nft-fixprice-sale-v4r1.fc`:
```
:208-223  op=555 handler:
  if ((op == 555) & ((is_complete == 1) | (~ is_initialized)) & equal_slices(sender_address, marketplace_address)) {
      var msg = in_msg_body~load_ref().begin_parse();
      var mode = msg~load_uint(8);
      throw_if(405, mode & 32);                                ;; :214  DESTRUCT запрещён
      if (sold_at != 0) {                                      ;; :216  ← УСЛОВИЕ
          int ten_min = 10 * 60;
          throw_if(406, (now() > (sold_at - ten_min)) & (now() < (sold_at + ten_min)));
      }                                                        ;; :219
      send_raw_message(msg~load_ref(), mode);
      return ();
  }

:384-394  cancel handler:
  save_data(
      1,             ;; is_complete = 1
      ...
      0,             ;; sold_at = 0  ← :389
      0,             ;; sold_query_id = 0
      ...
  );
```

**Логический путь:**
1. `marketplace → cancel(sale)` → `save_data(is_complete=1, sold_at=0)`  
2. `marketplace → op=555(arbitrary_msg)` сразу после  
3. Check: `is_complete == 1` → true ✓; `sender == marketplace` → true ✓  
4. `if (sold_at != 0)` → `0 != 0` → FALSE → time-lock блок пропускается  
5. `send_raw_message(arbitrary_msg, mode)` — ВЫПОЛНЯЕТСЯ немедленно  

**Аттакер capability:**  
Только `marketplace_address`. Требует marketplace как bad actor ИЛИ compromised marketplace key.  
В стандартной threat model marketplace = trusted → риск снижен.

**Verification method:** статический анализ

**Evidence collected:**  
- code path: **верифицирован** — `if (sold_at != 0)` at line 216, cancel sets `sold_at=0` at line 389  
- Логический путь полностью прослежен  
- testnet: отсутствует  
- Prerequisite: failed `return_nft` при cancel (NFT застрял в контракте) + marketplace cooperation

**Result:** CODE-CONFIRMED

**Severity после верификации:** Medium  
(требует marketplace как actor; в нормальном flow return_nft при cancel Mode=128 обычно успешен)

**What would upgrade confidence:**  
TEST-03 testnet: cancel → op=555 в следующем блоке → exit code 0.

**What would downgrade/block it:**  
- time-lock независимо от sold_at: `max(sold_at, is_complete_at)` или отдельный `canceled_at`  
- Текущий код не защищает canceled sales от немедленного op=555

---

## ABUSE-02 — recv_external griefing

**Claim:**  
`recv_external` не проверяет отправителя. Любой может завершить аукцион внешним сообщением. nft_owner теряет 0.5 TON (v3r3) или 0.1 TON (v4r1) из profit.

**Code anchors:**

`nft-auction-v3r3.func`:
```
:414-429  recv_external():
  init_data();
  var (op, _) = get_command_code(in_msg);
  if (op == 2) {
    throw_if(exit::not_activated_yet(), activated? == false);
    throw_if(exit::auction_end(), end? == true);
    throw_if(exit::cant_stop_time(), now() < end_time);
    handle::end_auction(nft_owner, true);  ;; :423  from_external=true
    accept_message();
    ;; НИГДЕ НЕТ ПРОВЕРКИ SENDER
    return ();
  }

handle::end_auction with from_external=true:
:167-175:
  throw_if(exit::low_bid(), profit < 500000000);  ;; partial protection
  profit = profit - 500000000;                    ;; :173  0.5 TON вычитается
  accept_message();
```

`nft-auction-v4r1.func`:
```
:620-634  recv_external():
  init_data();
  int op = in_msg~load_uint(32);
  int query_id = in_msg~load_uint(64);
  if (op == op::finish_acution) {
    throw_if(exit::not_activated_yet(), activated? == false);
    throw_if(exit::auction_end(), end? == true);
    throw_if(exit::cant_stop_time(), now() < end_time);
    handle::end_auction(nft_owner, true, query_id);  ;; :630  from_external=true
    ;; НИГДЕ НЕТ ПРОВЕРКИ SENDER
    return ();
  }

handle::end_auction v4r1 с from_external=true (TON mode):
:337-344:
  check_ok_balance(profit)           ;; throw if profit < 0.1 TON
  profit = profit - 0.1 TON
```

`check_ok_balance (v4r1:298-301)`:
```
() check_ok_balance(int my_balance) impure inline {
    throw_if(exit::low_bid(), my_balance < get_price_for_end_auction());  ;; :299
    accept_message();
}
```

**Анализ mitigation v4r1:**  
- `check_ok_balance(profit)` бросает если `profit < 0.1 TON`  
- `accept_message()` вызывается ВНУТРИ check_ok_balance — это означает что при throw до accept_message, внешнее сообщение не принимается (griefing не проходит)  
- Защита: для аукционов с profit ≤ 0.1 TON griefing заблокирован  
- Для аукционов с profit > 0.1 TON: griefing работает, nft_owner теряет 0.1 TON  

**Attacker capability:**  
Любой. Внешние сообщения в TON бесплатны для отправителя (газ берётся из баланса контракта). Нет auth.

**Verification method:** статический анализ

**Evidence collected:**  
- code path: **верифицирован** — отсутствие sender check в обоих recv_external  
- v3r3: 0.5 TON deduction at line 173  
- v4r1: 0.1 TON deduction + частичная защита check_ok_balance (line 299)  
- testnet: отсутствует

**Result:** CODE-CONFIRMED  
Оба контракта подтверждены. v4r1 частично защищён для малых аукционов.

**Severity после верификации:** Low-Med (v3r3: Med; v4r1: Low для большинства случаев)

**What would upgrade confidence:**  
TEST-05 testnet: external call после end_time → trace profit delta.

**What would downgrade/block it:**  
- Добавить подпись nft_owner или marketplace в external message  
- В v4r1 для малых аукционов уже частично заблокировано через check_ok_balance

---

## Итоговая матрица уязвимостей после верификации

| # | ID | Title | Status | Severity | Blocker существует? |
|---|---|---|---|---|---|
| 1 | HYP-01 | is_complete=1 без NFT (bounce ignored) | **CODE-CONFIRMED** | Critical | Нет |
| 2 | HYP-05 | Fake NFT — нет TEP-62 on-chain validation | **CODE-CONFIRMED** | Critical | Нет (on-chain) |
| 3 | HYP-02 | Auction hostage via bid cycling | **CODE-CONFIRMED** | High | Нет (cap bypass доказан) |
| 4 | HYP-06 | Jetton try/catch action phase misuse | **CODE-CONFIRMED** | High | Нет (TON VM fact) |
| 5 | HYP-07 | return_last_bid mode=2 silent fail | **CODE-CONFIRMED** | High | Нет |
| 6 | HYP-03 | op=555 zero time-lock на canceled | **CODE-CONFIRMED** | Medium | Только trusted MP |
| 7 | ABUSE-02 | recv_external griefing | **CODE-CONFIRMED** | Low-Med | Частичный (v4r1 малые аукционы) |

## Что требует дополнительных данных

| Finding | Что нужно | Для чего |
|---|---|---|
| HYP-01 | TX hash из poc-testnet.js | SIM-CONFIRMED/TESTNET-CONFIRMED |
| HYP-05 | GetGems backend source / API | Определить on-chain vs Critical |
| HYP-02 | TEST-02 testnet | SIM-CONFIRMED |
| HYP-06 | Local TVM sim с reject-jetton | SIM-CONFIRMED (архитектурно уже ясно) |
| HYP-07 | Testnet с frozen last_member | SIM-CONFIRMED |
| ABUSE-02 | Размер реальных аукционов mainnet | Уточнение реального impact |

## Нераскрытые риски

Следующие findings из FINAL_REPORT.md не верифицировались в этом отчёте (вне scope приоритетного списка):
- V4R1-NEW-02 (is_broken_state deploy lock) — требует проверки mainnet deployments
- HYP-04 (Seller silent fail) — sub-finding HYP-05 в combo сценарии
- muldiv dust, raw_reserve отсутствие — Low severity, code якоря в AUDIT_LOG верифицированы

---

*Все верификации основаны исключительно на статическом анализе исходного кода. Testnet/mainnet TX traces отсутствуют. Статус CODE-CONFIRMED не означает TESTNET-CONFIRMED или IMPACT-CONFIRMED.*
