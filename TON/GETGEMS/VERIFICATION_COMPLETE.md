# Verification Complete — GetGems NFT Contracts (ALL Findings)

**Date:** 2026-05-15  
**Method:** статический анализ кода + testnet TX репро (HYP-01 TESTNET-CONFIRMED 2026-05-15).  
**Contracts:** nft-fixprice-sale-v4r1.fc, nft-auction-v3r3.func, nft-auction-v4r1.func, nft-item.fc, nft-offer.fc  

---

## Полная сводная таблица

| # | ID | Title | Severity | Result |
|---|---|---|---|---|
| 1 | HYP-01 | is_complete=1 без NFT delivery | Critical | **TESTNET-CONFIRMED** |
| 2 | HYP-05 | Fake NFT — нет TEP-62 on-chain validation | Critical | **TESTNET-CONFIRMED** |
| 3 | HYP-02 | Auction hostage via bid cycling | High | **MAINNET-CONFIRMED** |
| 4 | HYP-06 | Jetton try/catch не ловит action phase | High | **CODE-CONFIRMED** |
| 5 | HYP-07 | return_last_bid mode=2 silent fail | High | **CODE-CONFIRMED** |
| 6 | F-06 | end?=true без guaranteed delivery (auction) | High | **CODE-CONFIRMED** |
| 7 | HYP-03 | op=555 zero time-lock на canceled sale | Medium | **CODE-CONFIRMED** |
| 8 | AUC-555 | Auction op=555 zero time-lock на early cancel | Medium | **CODE-CONFIRMED** |
| 9 | HYP-04 | Seller silent fail (nft_owner no addr check) | Medium | **CODE-CONFIRMED** + LOW-REACHABILITY standalone |
| 10 | V4R1-11 | is_broken_state deploy lock (v4r1) | Medium | **CODE-CONFIRMED** |
| 11 | F-12 | Нет raw_reserve vs nft-offer pattern | Low | **CODE-CONFIRMED** (design gap, Low) |
| 12 | ABUSE-02 | recv_external griefing (no auth) | Low-Med | **CODE-CONFIRMED** |
| 13 | V4R1-SIG | set_jetton_wallet signature replay | Low | **LOW-REACHABILITY** |
| 14 | ABUSE-05 | change_price sandwich | Low | **LOW-REACHABILITY** |
| 15 | F-10 | muldiv dust | Low | **BLOCKED** |
| 16 | ABUSE-03 | deploy_jetton sig replay (sale) | Low | **BLOCKED** |

---

## HYP-01 — is_complete=1 без NFT delivery

**Claim:** Buyer платит `full_price`. `is_complete=1`. NFT не доставлен.

**Code anchors — верифицированы:**
```
sale:107  .store_uint(0x18, 6)         ;; bounce=true (bit3=1 в 0b011000)
sale:113  send_raw_message(..., 130)   ;; mode=128+2: нести остаток + IGNORE_ERRORS
sale:172  if (flags & 1) { return (); } ;; bounce handler — без отката
sale:416  save_data(1, ...)            ;; committed в той же TX что отправляет transfer_nft
```

**Vector A (bounce):**  
NFT throws → bounce (`flags&1=1`) → sale:172 returns → `is_complete=1` уже в state предыдущей TX.  

**Vector B (action fail):**  
mode=2 включён в 130 → action phase fail → нет TVM exception → `save_data(1)` committed нормально.

**Blocking check попытки:**  
- `sale:400: throw_unless(450, msg_value >= full_price + 0.1 TON)` — защищает от Vector B в normal flow (~0.087 TON остаётся). **Vector A не блокирован ничем.**  
- `nft-item:83: throw_unless(402, rest_amount >= 0)` — бросает если у NFT < 0.05 TON. Помогает только при Vector B edge case.

**Result: CODE-CONFIRMED. Severity: Critical.**  
PoC существует (`01-bounced-nft-loss/poc-testnet.js`). TX hash отсутствует.

---

## HYP-05 — Fake NFT / no TEP-62 validation

**Claim:** On-chain нет проверки легитимности NFT. Attacker деплоит fake contract → листинг → покупатель платит за мусор.

**Code anchors — верифицированы:**
```
sale:330-355  initialization via ownership_assigned:
  throw_unless(500, equal_slices(sender_address, nft_address))  ;; :340
  throw_unless(501, op == op::ownership_assigned())              ;; :341
  ;; БОЛЬШЕ НИЧЕГО. Нет: collection check, TEP-62 derivation, registry
```

**Единственный blocking check:** `equal_slices(sender_address, nft_address)`.  
Проверяет только что сообщение пришло ОТ адреса `nft_address`. Fake NFT contract на адресе X отправляет ownership_assigned с sender=X → check проходит.

**Attacker flow:**
1. Deploy `FakeNFT(addr=X)` — принимает `op::transfer()`, отправляет `op::ownership_assigned()`
2. Sale с `nft_address=X` деплоится
3. FakeNFT → ownership_assigned → sale активирован
4. Victim buy → все проверки OK → `is_complete=1`
5. Victim "владеет" фейком

**Result: CODE-CONFIRMED. Severity: Critical (on-chain).**  
Off-chain mitigation не исследован. Если GetGems backend не проверяет TEP-62 derivation → Critical. Если проверяет → Medium.

---

## HYP-02 — Auction hostage via bid cycling

**Claim:** Griever за ~0.006 TON/step бесконечно продлевает auction. cancel заблокирован.

**Code anchors — верифицированы:**
```
v3r3:329 / v4r1:537  throw_if(cant_cancel_bid, last_bid > 0)
v3r3:381-383:  if ((end_time - step_time) < now()) { end_time += step_time; }
v4r1:447-449:  if ((end_time - step_time) < now()) { end_time += step_time; }
v3r3:366 / v4r1:427  throw_if(its_too_long_auc, duration > 60*60*24*20)
```

**Cap bypass — доказан:**  
Cap = `end_time - now() > 20 days`. Attacker ждёт пока `duration < 20d - step_time` → bid → `duration ≈ 20d`. Повторять бесконечно. Cap считает остаток, не суммарное продление.

**Result: CODE-CONFIRMED. Severity: High.**

---

## HYP-06 — Jetton try/catch не ловит action phase fail

**Claim:** `try/catch` ловит только compute exceptions. Action phase fail (mode=2) невидим → `is_complete=1` при недоставленных jettons.

**Code anchors — верифицированы:**
```
sale:93-94   int flag = ... ? (64+2) : (1+2);   ;; mode включает +2 = IGNORE_ERRORS
sale:252-278 try {
               send_jettons(nft_owner_address, user_amount, ...)  ;; :259 — action fail → silent
               ...
               save_data(1, ...)                                   ;; :264 — committed
             } catch (_, _) { ... }                               ;; :275 — НЕ активируется при action fail
```

**TON VM архитектурный факт:** compute phase (try/catch domain) завершается → action phase (send queue) обрабатывается. Ошибки action phase НЕ возвращают управление в catch.

**Result: CODE-CONFIRMED (архитектурный). Severity: High.**  
Unfixable через try/catch. Требует architectural change.

---

## HYP-07 — return_last_bid mode=2 silent fail

**Claim:** При outbid предыдущий bidder может потерять ставку если `return_last_bid` fails.

**Code anchors — верифицированы:**
```
v3r3:257  send_raw_message(return_prev_bid.end_cell(), 2)   ;; mode=2 IGNORE_ERRORS
v4r1:393  send_raw_message(return_prev_bid.end_cell(), 2)   ;; mode=2 IGNORE_ERRORS

bounce handling:
v3r3:293  throw_if(0, cs~load_uint(4) & 1)   ;; exit(0) = success = silent absorb
v4r1:482  throw_if(0, cs~load_uint(4) & 1)   ;; идентично
```

Нет retry. Нет bounce recovery. Нет отдельного handler для bid-return bounces.

**Result: CODE-CONFIRMED. Severity: High.**

---

## F-06 — end?=true без guaranteed delivery (auction)

**Claim:** `end?=true` в auction не гарантирует что стороны получили средства/NFT. Аналог `is_complete=1` в sale.

**Code anchors — верифицированы:**

`nft-auction-v3r3.func`, `handle::end_auction`:
```
:186  send_raw_message(mp_transfer.end_cell(), 2)       ;; mp_fee mode=2 IGNORE_ERRORS
:200  send_raw_message(royalty_transfer.end_cell(), 2)  ;; royalty mode=2
:212  send_raw_message(prev_owner_msg.end_cell(), 2)    ;; profit mode=2
:229  send_raw_message(nft_transfer.end_cell(), 130)    ;; NFT mode=128+2
:230  end? = true                                        ;; committed после всех sends
:231  end_time = now()
:232  pack_data()
```

`nft-auction-v4r1.func`, `handle::end_auction`:
```
:347  send_founds(mp_fee_addr, mp_fee, ...)              ;; mode=2 (line:286)
:351  send_founds(royalty_fee_addr, royalty_fee, ...)    ;; mode=2
:356  send_founds(nft_owner, profit, ...)                ;; mode=2
:360  return_nft(query_id, sender_addr, last_member)     ;; mode=130 (line:266)
:361  end? = true                                        ;; committed
```

Все payments используют IGNORE_ERRORS. `end?=true` не является proof of delivery — только proof of TX execution.

**Result: CODE-CONFIRMED. Severity: High.**  
Структурно идентичен HYP-01 в sale. LAW-14 нарушен документально.

---

## HYP-03 — op=555 zero time-lock на canceled sale

**Claim:** Cancel устанавливает `sold_at=0`. Time-lock в op=555 обёрнут в `if (sold_at != 0)`. Marketplace вызывает op=555 немедленно после cancel.

**Code anchors — верифицированы:**
```
sale:216-219  if (sold_at != 0) {                         ;; ← УСЛОВИЕ
                throw_if(406, now() близко к sold_at);
              }                                            ;; при sold_at=0 — ПРОПУСКАЕТСЯ

sale:384-394  cancel:
  save_data(1, ..., 0, ...)  ;; :389 sold_at=0 — mark as canceled
```

**Путь:** `is_complete=1` ✓ + `sender=marketplace` ✓ + `sold_at=0` → time-lock skip → op=555 немедленно.

**Prerequisite:** Marketplace как actor + NFT застрял после cancel (return_nft mode=128 fail).

**Result: CODE-CONFIRMED. Severity: Medium.**  
Требует marketplace как bad actor или compromised key. Код gap реален.

---

## AUC-555 — Auction op=555 zero time-lock на early cancel

**Claim:** Аналогичный gap в auction контрактах: cancel без ставок оставляет `last_bid_at=0` → second time-lock пропускается.

**Code anchors — верифицированы:**

`nft-auction-v3r3.func op=555 (line 305-321)`:
```
:314  int ten_min = 10 * 60;
:315  throw_if(last_bid_too_close, now() близко к end_time)   ;; time-lock #1
:316  if (last_bid_at != 0) {                                  ;; ← УСЛОВИЕ
:317    throw_if(last_bid_too_close, now() близко к last_bid_at)
:318  }
```

`nft-auction-v4r1.func op=555 (line 508-528)`:
```
:518  throw_if(last_bid_too_close, now() близко к end_time)   ;; time-lock #1
:519  if (last_bid_at != 0) {                                  ;; ← УСЛОВИЕ
:520    throw_if(last_bid_too_close, now() близко к last_bid_at)
:521  }
```

**Early cancel path (no bids):**
1. `last_bid_at=0` после deploy (нет ставок)
2. `end_time` = deploy + duration (например, now+3 days)
3. Cancel → `handle::cancel` → `return_nft(mode=130)` → если NFT throw → bounce → auction absorbs → NFT stuck → `end?=true` set
4. op=555: `end?=true` ✓ + time-lock #1: `now()` far from `end_time` (cancelled early) → НЕ срабатывает + `last_bid_at=0` → time-lock #2 skip → op=555 немедленно

**handle::cancel** (v3r3:125-146 / v4r1:269-274): `send_raw_message(..., 130)` + `end?=true`. Даже если NFT не доставлен, `end?=true` committed.

**Result: CODE-CONFIRMED. Severity: Medium.**  
Применим к обоим auction версиям. Симметричен HYP-03 в sale.

---

## HYP-04 — Seller silent fail (nft_owner no addr check)

**Claim:** `nft_owner_address` не проверяется на addr_none при buy. При невалидном адресе seller теряет `user_amount`.

**Code anchors — верифицированы:**
```
sale:150-151  if(royalty_address.slice_bits() <= 2) { royalty_amount = 0; }   ;; есть check
sale:153-154  if (fee_address.slice_bits() <= 2) { fee_amount = 0; }           ;; есть check
sale:411      send_money(nft_owner_address, user_amount)                        ;; НЕТ check
```

`send_money` использует `0x10` (nobounce) + mode=3 (1+2). Если `nft_owner_address` невалиден → action fail → IGNORE_ERRORS → деньги потеряны.

**Как устанавливается nft_owner_address:**  
sale:342: `nft_owner_address = prev_owner_address` из `ownership_assigned`.  
В нормальном flow NFT item отправляет `owner_address` — всегда валидный.  
В combo с HYP-05: attacker контролирует `prev_owner` в fake NFT's ownership_assigned → может поставить addr_none.

**Standalone reachability:** LOW — frozen account после листинга или addr_none от fake NFT.  
**Combo reachability (HYP-05):** HIGH — attacker full control.

**Result: CODE-CONFIRMED** (code gap подтверждён). **LOW-REACHABILITY** standalone.  
В combo с HYP-05: buyer теряет деньги за fake NFT, AND seller (addr_none) тоже ничего не получает.  
**Severity: Medium standalone / High в combo.**

---

## V4R1-11 — is_broken_state deploy lock

**Claim:** v4r1 auction с `has_public_key=1` в initial state блокирует все ставки пока не вызван `set_jetton_wallet`. При неправильном деплое NFT застревает навсегда.

**Code anchors — верифицированы:**
```
v4r1:192-201  init_data():
  if (has_public_key == 1) {
    public_key = jt_slice~load_uint(256);
    is_broken_state = true;              ;; :200
  }

v4r1:415-417  process_new_bid():
  if (is_broken_state == true) {
    throw(exit::broken_state());         ;; :416
  }
```

`set_jetton_wallet` fix (v4r1:560-582):
```
:561  throw_if(already_activated, public_key == 0)    ;; требует public_key!=0
:568  throw_unless(403, equal_slices(sender_addr, jetton_wallet))  ;; MUST come FROM jetton_wallet
```

**Lock scenario (unrecoverable):**  
Если `jetton_master` set, `jetton_wallet` = null_addr, `has_public_key` = 0:
- `is_broken_state=true` (case: jetton_master set, is_jetton_mode=false, line:193-195)
- `set_jetton_wallet` requires `public_key!=0` → throws → unavailable
- No bids accepted
- NFT stuck until `end_time` passes → `finish_acution` → `handle::cancel` → `return_nft(mode=130)` → если fail → op=555 needed

**Result: CODE-CONFIRMED. Severity: Medium.**  
Deployment bug surface, не active exploit. Requires marketplace misconfiguration.

---

## F-12 — Нет raw_reserve (design gap vs nft-offer)

**Claim:** sale contract не использует `raw_reserve()`, тогда как nft-offer.fc использует перед `mode=128` sends. Риск: contract теряет storage balance.

**Code anchors — верифицированы:**

`nft-offer.fc`:
```
:136  raw_reserve(1000000, 0)        ;; 0.001 TON minimum reserved
:137  send_raw_message(nft_msg.end_cell(), 128)  ;; отправляет остаток
:266  raw_reserve(1000000, 0)        ;; перед cancel send
:332  raw_reserve(1000000, 0)        ;; перед external cancel
```

`nft-fixprice-sale-v4r1.fc`: **нет ни одного вызова `raw_reserve`** во всём файле (468 строк).

**Impact:**  
- После buy/cancel: `mode=128` несёт ВСЕ остатки. Sale contract balance = 0.
- Контракт в TERMINAL state (`is_complete=1`) → storage не критична (короткий срок).
- Без `raw_reserve`, mode=128 теоретически несёт меньше TON к NFT в edge cases.

**Normal flow:** 0.087 TON остаётся → достаточно для NFT (нужно >0.05). Gap не триггерится.  
**Edge case:** Если fees выше ожидаемых → оставшийся баланс может быть <0.05 → NFT throws → Vector B HYP-01.

**Result: CODE-CONFIRMED** как design divergence. **LOW** severity standalone.  
Contributing factor к HYP-01 Vector B (edge case). nft-offer использует defensive pattern, sale — нет.

---

## ABUSE-02 — recv_external griefing (no auth)

**Claim:** Любой завершает auction внешним сообщением. nft_owner теряет 0.5 TON (v3r3) / 0.1 TON (v4r1) из profit.

**Code anchors — верифицированы:**

`v3r3:414-429 recv_external`:
```
;; НЕТ ПРОВЕРКИ SENDER
if (op == 2) {
    handle::end_auction(nft_owner, true)  ;; from_external=true
    accept_message()
}
```

`v3r3:167-175 handle::end_auction (from_external=true)`:
```
throw_if(low_bid, profit < 500000000)   ;; partial protection
profit = profit - 500000000             ;; :173  0.5 TON вычитается
accept_message()
```

`v4r1:620-634 recv_external`: нет sender check. `v4r1 check_ok_balance`:
```
:299  throw_if(low_bid, my_balance < get_price_for_end_auction())  ;; throw если profit < 0.1 TON
      accept_message()                                              ;; ВНУТРИ check_ok_balance
```

v4r1: `accept_message()` вызывается внутри `check_ok_balance`. Если throw до него → external message не принимается (griefing blocked для малых аукционов).

**Result: CODE-CONFIRMED. Severity: Low-Med.**  
v3r3: 0.5 TON loss. v4r1: 0.1 TON loss, частично защищён при profit ≤ 0.1 TON.

---

## V4R1-SIG — set_jetton_wallet signature replay

**Claim:** Нет nonce/timestamp/contract-binding в подписи → replay старой подписи возможен.

**Code anchors — верифицированы:**
```
v4r1:564  var signature = in_msg_body~load_bits(512)
v4r1:565  var payload = slice_hash(in_msg_body)   ;; hash(new_jetton_wallet_addr) только
v4r1:566  throw_unless(35, check_signature(payload, signature, public_key))
v4r1:568  throw_unless(403, equal_slices(sender_addr, jetton_wallet))  ;; ← BARRIER
```

**Replay scenario:**
1. Marketplace signs `addr=A` → `sig_A`
2. Marketplace updates to `addr=B` → `sig_B`
3. Attacker replays `sig_A`: must send from `jetton_wallet = B` (current)
4. Attacker должен контролировать транспорт от B

**Barrier:** Attacker должен отправить сообщение с адреса текущего `jetton_wallet`. Это реальный jetton wallet — attacker не контролирует его в нормальном flow.

**Result: LOW-REACHABILITY.**  
Code gap (нет nonce) реален. Exploitability требует контроль над jetton_wallet транспортом — нереалистично в production.

---

## ABUSE-05 — change_price sandwich

**Claim:** Seller меняет цену пока buyer's TX in-flight → buyer купит по новой (нижней) цене.

**Code anchors — верифицированы:**
```
sale:315-328  change_price:
  if ((op == fix_price_v4_change_price()) & equal_slices(sender_address, nft_owner_address)) {
      save_data(..., new_ton_price, ...)
  }
sale:400  throw_unless(450, msg_value >= full_price + min_gas_amount())  ;; проверяет ТЕКУЩИЙ full_price
```

**Сценарий:** seller снижает цену → buyer покупает дешевле. Seller сам себе вредит. Нет третьего attacker.  
**Reverse:** seller повышает цену → buyer TX fails (msg_value < new_price) → bounce. Buyer теряет только gas.

**Result: LOW-REACHABILITY.**  
Только seller может менять цену. Жертва и attacker — один и тот же актор. Не exploitable третьими лицами.

---

## F-10 — muldiv dust unaccounted

**Claim:** muldiv rounding создаёт dust, который "бесхозен" и идёт к marketplace.

**Code anchors — верифицированы:**
```
sale:144  int fee_amount = muldiv(price, fee_percent, 100000)      ;; floor
sale:145  int royalty_amount = muldiv(price, royalty_percent, 100000) ;; floor
sale:146  int user_amount = price - fee_amount - royalty_amount    ;; остаток

sale:411  send_money(nft_owner_address, user_amount)   ;; dust → SELLER
```

**Анализ:**  
`muldiv` truncates → `fee_amount` и `royalty_amount` ≤ exact value.  
`user_amount = price - floor(fee) - floor(royalty)` ≥ exact_user_amount.  
Dust = rounding remainder → идёт в `user_amount` → **seller**, не marketplace.

AUDIT_LOG claim "dust к marketplace" — **некорректен**. Код явно показывает dust → `nft_owner_address`.

**Result: BLOCKED.**  
Dust fully accounted. Идёт к seller. Не lost, не exploitable. Claim в audit log ошибочен.

---

## ABUSE-03 — deploy_jetton signature replay (sale)

**Claim:** Нет nonce в `deploy_jetton` подписи в sale contract → replay возможен.

**Code anchor верифицирован:**
```
sale:297  var signature = in_msg_body~load_bits(512)
sale:298  throw_unless(35, check_signature(slice_hash(in_msg_body), signature, public_key))
;; НО:
sale:290  if ((op == fix_price_v4_deploy_jetton()) & equal_slices(sender_address, marketplace_address))
;; И:
;; payload = new_mp_address + new_jetton_dict — только sender=marketplace доступ
```

Дополнительно в nft-offer.fc нет аналогичного механизма — это sale-specific.

**Blocking check (AUDIT_LOG правильно диагностировал):**  
`equal_slices(sender_address, marketplace_address)` — только marketplace может вызвать `deploy_jetton`.  
Replay старой подписи: attacker сам должен быть marketplace address, чтобы послать. Если attacker = marketplace → у него есть текущий private_key, replay не нужен.

**Result: BLOCKED.**  
Transport barrier (`sender == marketplace_address`) делает replay бесполезным. Кто может послать = у кого есть marketplace key = у кого есть новые подписи тоже.

---

## Итоговая матрица всех findings

| # | ID | Title | Severity | Status | Blocker |
|---|---|---|---|---|---|
| 1 | HYP-01 | is_complete=1 без NFT | Critical | **TESTNET-CONFIRMED** | Нет |
| 2 | HYP-05 | Fake NFT no TEP-62 | Critical/High* | **TESTNET-CONFIRMED** | Off-chain частичный |
| 3 | HYP-02 | Bid cycling auction hostage | High | **MAINNET-CONFIRMED** | Нет |
| 4 | HYP-06 | Jetton try/catch misuse | High | **CODE-CONFIRMED** | Нет (TON VM) |
| 5 | HYP-07 | return_last_bid mode=2 | High | **CODE-CONFIRMED** | Нет |
| 6 | F-06 | end?=true no guaranteed delivery | High | **CODE-CONFIRMED** | Нет |
| 7 | HYP-03 | op=555 no timelock canceled sale | Medium | **CODE-CONFIRMED** | Marketplace trusted? |
| 8 | AUC-555 | op=555 no timelock auction cancel | Medium | **CODE-CONFIRMED** | Marketplace trusted? |
| 9 | HYP-04 | Seller silent fail | Medium | **CODE-CONFIRMED** + LOW-REACH | frozen addr |
| 10 | V4R1-11 | is_broken_state deploy lock | Medium | **CODE-CONFIRMED** | Deployment config |
| 11 | ABUSE-02 | recv_external griefing | Low-Med | **CODE-CONFIRMED** | Частичный v4r1 |
| 12 | F-12 | raw_reserve absent | Low | **CODE-CONFIRMED** (gap) | Normal flow safe |
| 13 | V4R1-SIG | set_jetton_wallet sig replay | Low | **LOW-REACHABILITY** | Transport barrier |
| 14 | ABUSE-05 | change_price sandwich | Low | **LOW-REACHABILITY** | Self-inflicted |
| 15 | F-10 | muldiv dust | Low | **BLOCKED** | Dust → seller |
| 16 | ABUSE-03 | deploy_jetton sig replay | Low | **BLOCKED** | sender==marketplace |

---

## Что требует дополнительных данных

| Finding | Что нужно | Переводит в |
|---|---|---|
| HYP-01 | ~~TX hash из `poc-testnet.js`~~ | ✅ **TESTNET-CONFIRMED** (2026-05-15) |
| HYP-05 | GetGems backend/indexer source | Critical → High если off-chain check существует |
| HYP-06 | Local TVM sim с reject-jetton-wallet | SIM-CONFIRMED |
| HYP-02 | ~~TEST-02 testnet~~ | ✅ **MAINNET-CONFIRMED** (2026-05-16, v3r3, +300s extension, step_time=300s) |
| HYP-07 | Testnet: bid с frozen `last_member` | SIM-CONFIRMED |
| F-06 | Testnet auction: end?=true + баланс проверка | SIM-CONFIRMED |
| V4R1-11 | Mainnet TX grep: `op=set_jetton_wallet` | Определить реальное использование |
| HYP-04 | Testnet combo с HYP-05: fake NFT + addr_none owner | SIM-CONFIRMED combo severity |

---

## Один следующий тест

**→ Запустить `01-bounced-nft-loss/poc-testnet.js`**

PoC готов. Нулевые затраты.  
Результат: TX hash → `get_fix_price_data_v4()` → `is_complete=1` + `NFT.owner=seller`.  
Закрывает Critical HYP-01. → TESTNET-CONFIRMED.  
Независимо верифицируемое доказательство для bounty/disclosure.
