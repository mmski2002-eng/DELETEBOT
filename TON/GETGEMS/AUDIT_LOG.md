# GETGEMS / TON — Audit Log
**Date:** 2026-05-15  
**Contracts:** nft-fixprice-sale-v4r1.fc (468L), nft-auction-v3r3.func (503L), nft-marketplace.fc (53L), nft-item.fc (143L)  
**Sources:** downloaded from github.com/getgems-io/nft-contracts → `contracts/sources/`  
**Protocol:** vscode_agent_audit_protocol.md (PASS 0–4)

---

## PASS 0 — Source Map

### Таблица источников

| Источник | Статус | Надёжность |
|---|---|---|
| Code / contracts (.fc/.func) | PROVIDED | High |
| Скомпилированный BOC (в poc-testnet.js) | PROVIDED (частично) | Medium |
| Аудиторский отчёт (КОРЗИНА/) | PROVIDED (pre-existing) | Low-Medium — строки не верифицированы |
| README / PROOF_PLAN (01-08) | PROVIDED | Low без исходников |
| PoC скрипты (01/poc-testnet.js) | PROVIDED | Medium |
| Тесты (spec) | CLAIMED / MISSING | — |
| Transactions / traces | MISSING | — |
| API responses | MISSING | — |
| Backend / indexer | MISSING / INFERRED | — |
| Mainnet адреса | MISSING (заглушки EQD__) | — |
| testnet-wallets.seed | PROVIDED — ⚠️ SENSITIVE (mnemonics plaintext) | — |

### Выводы PASS 0

**Доступно:**
- Полные исходники 4 контрактов + stdlib + op-codes
- pre-existing отчёт на 8 уязвимостей
- PoC JS скрипт для уязвимости #01 на testnet

**Только предполагается (UNTRUSTED):**
- Результаты spec-тестов (файлы не найдены)
- Claim "testnet подтверждено" без tx hash
- Mainnet impact оценки

**Нельзя оценивать:**
- Backend/indexer логика верификации листингов
- Реальные gas costs в mainnet
- Jetton wallet адреса в jetton_price_dict на mainnet

**Первые файлы для открытия:**
1. `nft-fixprice-sale-v4r1.fc` — главная цель
2. `nft-auction-v3r3.func` — #02, #03
3. `nft-item.fc` — TEP-62 verification gap
4. `nft-marketplace.fc` — понять роль
5. `nft-offer.fc` — reference для raw_reserve pattern

---

## PASS 1 — Code-Grounded Mental Model

### Объекты

**Sale Contract** (`nft-fixprice-sale-v4r1.fc`)
- Lifecycle: `BLANK (nft_owner=null) → ACTIVE (is_complete=0) → TERMINAL (is_complete=1)`
  - `sold_at > 0` = продан; `sold_at = 0` = отменён
- `static_data_cell` неизменяем после деплоя (nft_address, fee%, royalty%)
- Events: нет (TON трассировка через сообщения)

**Auction Contract** (`nft-auction-v3r3.func`)
- Lifecycle: `UNACTIVATED → ACTIVE → ENDED/CANCELED`
- Хранит ТОЛЬКО последнюю ставку — история в message traces

**NFT Item** (`nft-item.fc`)
- Init только от `collection_address` [:118]
- Transfer только от текущего `owner_address` [:66]
- При transfer: отправляет `op::ownership_assigned(prev_owner)` новому владельцу [:86]

**Marketplace** (`nft-marketplace.fc`)
- 53 строки, только деплой auction контрактов (op=1, owner-only)
- **Нет реестра листингов** — все листинги автономны

### Акторы (code-confirmed)

| Актор | Функции | Теряет при сбое |
|---|---|---|
| Buyer | отправляет TON/jetton | full_price если transfer_nft fail |
| Seller | получает user_amount, может cancel | газ на cancel |
| Marketplace | fee, op=555, деплой auction | — |
| Royalty recipient | royalty_amount | ничего (nobounce send) |
| NFT contract | инициализирует через ownership_assigned | — |
| Jetton wallet (INFERRED) | transfer_notification | jettons при partial failure |

### Порядок событий

**Строго до:**
- `ownership_assigned` до покупки [`sale:330`]
- `is_complete=0` до buy [`sale:284`]

**Может не произойти:**
- `transfer_nft` — mode=130 IGNORE_ERRORS [`sale:113`]
- `return_last_bid` — mode=2 IGNORE_ERRORS [`auction:257`]
- Все `send_money` — nobounce + IGNORE_ERRORS [`sale:127`]

**Может произойти частично:**
- `send_money×3 → transfer_nft` [`sale:411-414`]
- `send_jettons×4 → transfer_nft` [`sale:259-263`]

### Память системы

| Что | Где |
|---|---|
| is_complete, nft_owner, full_price, sold_at | on-chain, sale contract |
| end?, last_bid, last_member, end_time | on-chain, auction contract |
| owner_address, collection_address, index | on-chain, NFT contract |
| История ставок | ТОЛЬКО в message traces |
| Метаданные листинга | UNKNOWN off-chain/IPFS |
| Реестр активных листингов | UNKNOWN backend/indexer INFERRED |

### Compact Mental Model (15 points)

1. `is_complete=1` не гарантирует доставку NFT [`sale:416-425`]
2. `transfer_nft` с `mode=130` (128+2) молча дропается при нехватке газа [`sale:113`]
3. `send_money` с `nobounce(0x10)+mode=3` — доставка TON НЕ гарантирована [`sale:121,127`]
4. `send_jettons` с `nobounce(0x10)+mode=3` — delivery НЕ гарантирована [`sale:86,94`]
5. `return_last_bid` с `mode=2` — возврат ставки НЕ гарантирован [`auction:257`]
6. `raw_reserve()` — 0 в sale contract, 3 раза в nft-offer.fc [`offer:136,266,332`]
7. Marketplace — только деплоер, нет on-chain реестра [`marketplace:53L`]
8. `op=555` = arbitrary message при `is_complete=1 OR ~init` [`sale:208-222`]
9. Auction хранит ТОЛЬКО последнюю ставку [`auction globals`]
10. NFT address = любой адрес в workchain 0, нет TEP-62 validation [`sale:29-39`]
11. Auction `end_time` автопродлевается при bid в конце торгов [`auction:381-383`]
12. `accept_message()` вызывается дважды в auction recv_external [`auction:174,424`]
13. Jetton buy: `try/catch` ловит compute exceptions, НЕ action phase failures [`sale:252-278`]
14. Sale contract никогда не деинициализируется — rescue только через `op=555` [`sale:172,416`]
15. `nft_owner` не проверяется на `addr_none` в отличие от `fee_address`/`royalty_address` [`sale:150-155`]

---

## PASS 2 — System Laws / Invariants

| LAW-ID | Statement | Status |
|---|---|---|
| LAW-01 | is_complete=1 → NFT доставлен | ❌ НАРУШЕН |
| LAW-02 | nft_address — легитимный TEP-62 NFT | ❌ НАРУШЕН |
| LAW-03 | payment ↔ NFT delivery атомарны | ❌ НАРУШЕН |
| LAW-04 | продавец получает деньги ↔ NFT ушёл | ❌ НАРУШЕН |
| LAW-05 | outbid bidder всегда получает ставку обратно | ❌ НАРУШЕН |
| LAW-06 | cancel делает sale экономически мёртвым | ⚠️ ЧАСТИЧНЫЙ |
| LAW-07 | min_gas 0.1 TON достаточно для цепочки | ⚠️ ЧАСТИЧНЫЙ |
| LAW-08 | op=555 недоступен в нормальном flow | ⚠️ ЧАСТИЧНЫЙ — zero-delay на canceled |
| LAW-09 | jetton_notification от легитимного wallet | ⚠️ ЧАСТИЧНЫЙ |
| LAW-10 | auction end_time конечен | ⚠️ ЧАСТИЧНЫЙ — продлевается via bid |
| LAW-11 | init только от настоящего NFT | ⚠️ ЧАСТИЧНЫЙ — адрес проверяется, природа нет |
| LAW-12 | on-chain source of truth — сами контракты | ✅ ВЕРНО |
| LAW-13 | dust от muldiv бесхозен | ⚠️ ЧАСТИЧНЫЙ — фактически к marketplace |
| LAW-14 | auction end?=true → все выплаты доставлены | ❌ НАРУШЕН |

**Итог:** 9 из 14 законов нарушены или частично нарушены.

### Детали ключевых законов

**LAW-08 — op=555 time-lock gap:**
```
if (sold_at != 0) {   // проверяется ТОЛЬКО при sold_at != 0
    throw_if(406, (now() > (sold_at - ten_min)) & (now() < (sold_at + ten_min)));
}
```
Cancel → `sold_at=0` → time-lock пропускается. `sale:216-219`

**LAW-10 — auction DoS через step_time:**
```
if ((end_time - step_time) < now()) {
    end_time += step_time;  // auction:381-383
}
// BUT: throw_if(duration > 60*60*24*20) — cap на duration от текущего bid
```
Каждый bid в конце торгов сбрасывает clock. Стоимость: ~0.006 TON/step_time.

---

## PASS 3 — Weird Valid States

### Выбранные гипотезы (7)

---

#### HYP-01: Complete-but-empty
**Broken law:** LAW-01, LAW-03  
**Severity:** Critical  
**Evidence:** High

`is_complete=1`, `sold_at>0`, деньги распределены, NFT не доставлен.

Механизм: `transfer_nft` с `mode=130 = 128+2`:
- mode=128: несёт весь остаток баланса
- mode=2: IGNORE_ERRORS → action phase fail → молча дропается, исключение не бросается
- `save_data(1)` уже коммичен в той же транзакции

**Code anchors:**
- `sale:113` — `send_raw_message(nft_msg.end_cell(), 130)`
- `sale:416-425` — `save_data(1)` после transfer_nft
- `sale:172` — bounced handler: `if (flags & 1) { return (); }` без отката

**Два пути:**
1. **Vектор A**: NFT контракт бросает → bounce (`0x18` bounce=true) → `sale:172` игнорирует → `is_complete=1` уже committed
2. **Вектор B**: action phase fail (нет газа) + mode=2 → НЕТ исключения → НЕТ bounce → `save_data(1)` нормально

---

#### HYP-02: Auction Hostage
**Broken law:** LAW-10, LAW-06  
**Severity:** High  
**Evidence:** High

nft_owner не может вернуть NFT — аукцион бесконечно продлевается.

Механизм:
1. Bid в окне `(end_time - step_time, end_time)` → `end_time += step_time` [`auction:381-383`]
2. `throw_if(exit::cant_cancel_bid(), last_bid > 0)` → cancel заблокирован [`auction:329`]
3. `return_last_bid` возвращает `bid - 5577000` → net cost ~0.006 TON/extension
4. `throw_if(duration > 20 days)` — cap от ТЕКУЩЕГО момента, не суммарного [`auction:366`]

Attacker тратит ~0.006 TON за каждые `step_time` секунд продления.  
nft_owner теряет доступ к NFT на неограниченный срок.

---

#### HYP-03: Zero-delay op=555 на canceled продажах
**Broken law:** LAW-08  
**Severity:** Medium  
**Evidence:** High

Canceled sale (`is_complete=1, sold_at=0`) → time-lock не применяется → немедленный доступ marketplace.

Если cancel's `transfer_nft` (mode=128) провалился по любой причине → NFT в контракте → marketplace забирает без ожидания.

**Code anchor:** `sale:216` — `if (sold_at != 0)` перед time-lock

---

#### HYP-04: Seller-silent-fail
**Broken law:** LAW-04, LAW-03  
**Severity:** Medium  
**Evidence:** Medium

`is_complete=1`, NFT у buyer, `user_amount` потерян.

`send_money` использует `0x10 + mode=3`: доставка к продавцу при невалидном адресе → action phase fail → IGNORE_ERRORS → молча.

В `buy_logic`: fee/royalty проверяются на `addr_none` [`sale:150-155`], но `nft_owner` — НЕТ.

Триггер: `nft_owner_address = frozen account / wrong workchain / addr_none`.

---

#### HYP-05: Fake-NFT-perfect-sale
**Broken law:** LAW-02, LAW-11, LAW-01  
**Severity:** Critical  
**Evidence:** High

Sale выглядит валидной со всех сторон, но NFT — фейк.

1. FakeNFT(addr=X) принимает `op::transfer()` без throw
2. `sale.nft_address = X`
3. FakeNFT → `ownership_assigned` → sale активирован
4. Buyer buy → все send_money OK → `transfer_nft(X, buyer)` → FakeNFT принимает
5. FakeNFT → `ownership_assigned(buyer)` → buyer "владеет" фейком
6. `is_complete=1`. Нет ни одного throw. Все контракты "счастливы".

**Code anchor:** `sale:29-39` — нет TEP-62 проверки; `sale:340` — только `equal_slices(sender, nft_address)`

---

#### HYP-06: Jetton-invisible-fail
**Broken law:** LAW-03, LAW-07  
**Severity:** High  
**Evidence:** High

Jetton buy: `try/catch` не ловит action phase failures → `is_complete=1`, jetton'ы покупателя в void.

Механизм:
- `send_jettons` с `nobounce(0x10) + mode=3 (1+2)`: action phase fail → NO exception
- `try/catch` в FunC откатывает только при compute phase exception
- Нет исключения → try блок завершается → `save_data(1)` коммичен

**Code anchors:**
- `sale:86,94` — `0x10` + `mode=3` в send_jettons
- `sale:252-278` — try/catch обёртка
- `sale:275` — `catch (_, _)` — только compute exception

---

#### HYP-07: Auction max-bid double-loss
**Broken law:** LAW-14, LAW-05  
**Severity:** High  
**Evidence:** High

При достижении `max_bid`: `return_last_bid` (mode=2) → previous bidder теряет ставку, auction немедленно завершается через `handle::end_auction`.

Если `return_last_bid` fails silently (mode=2) → previous bidder теряет всю ставку. Нет retry, нет bounce.

**Code anchor:** `auction:369-378` — max_bid path; `auction:257` — mode=2

---

### Discarded

| ID | Причина |
|---|---|
| H-replay | query_id идемпотентен, нет value transfer |
| H-large-dict | marketplace контролирует, низкий impact |
| H-null-owner | addr_none NFT owner — необычное precondition |
| H-double-init | throw(0xffff) → bounce → NFT возвращается |
| H-hash-collision | computationally infeasible |
| H-uninitialized-drain | только deploy gas (~0.02 TON) |

---

## Финальная сводка уязвимостей (верифицированных)

| # | Title | Severity | Anchor | Status |
|---|---|---|---|---|
| 01 | is_complete=1 без доставки NFT (mode=130 fail) | Critical | sale:113,172,416 | ✅ CONFIRMED + уточнён |
| 02 | return_last_bid mode=2 — ставка теряется | High | auction:257 | ✅ CONFIRMED |
| 03 | Race condition end_auction | ~~High~~ | — | ❌ INVALID для v3r3 |
| 04 | NFT Spoofing — нет TEP-62 check | Critical | sale:29-39,340 | ✅ CONFIRMED |
| 05 | Rounding dust через muldiv | Medium | sale:144-146 | ✅ CONFIRMED |
| 06 | Нет raw_reserve — NFT дропается при нехватке газа | High | sale:113 + offer:136 | ✅ CONFIRMED |
| 07 | Jetton buy — action phase fail undetected | High | sale:86,94,252-278 | ✅ CONFIRMED (уточнён) |
| NEW-01 | Auction DoS via bid cycling (HYP-02) | High | auction:329,366,381 | NEW |
| NEW-02 | op=555 zero time-lock на canceled (HYP-03) | Medium | sale:208-219 | NEW |
| NEW-03 | Seller-silent-fail: user_amount lost (HYP-04) | Medium | sale:121,127,150-155 | NEW |

---

---

## PASS 4 — Semantic Gap Analysis

| GAP-ID | Term | Gap | Severity | Evidence |
|---|---|---|---|---|
| GAP-01 | `is_complete=1` | contract="завершено", human/NFT contract="NFT ещё у seller" | Critical | High |
| GAP-02 | "transfer_nft отправлен" | contract="отправлен"≠"доставлен", NFT processing async | Medium | High |
| GAP-03 | "cancel" | human=reversible, contract=TERMINAL is_complete=1, op=555 немедленно доступен | Medium | High |
| GAP-04 | `nft_address` | contract=arbitrary addr, human=NFT из коллекции X, нет TEP-62 | Critical | High |
| GAP-05 | `return_last_bid` | contract="вернул" (mode=2), bidder может не получить | High | High |
| GAP-06 | `jetton_notification` как proof оплаты | contract доверяет amount из notification, не проверяет баланс | Medium | Medium |
| GAP-07 | `end?=true` в аукционе | human="завершён, все получили", contract="send отправлены" (mode=2/130) | Critical | High |
| GAP-08 | `op=555` emergency | "emergency rescue" = "arbitrary execution" при компрометации ключа | High | High |

### Ключевые разрывы

**GAP-01 + GAP-07:** Одинаковый паттерн в sale и auction.
`is_complete=1` / `end?=true` — финальные state flags, но не гарантируют delivery.
Любой компонент читающий эти флаги считает транзакцию успешной.

**GAP-04:** Самый широкий разрыв между человеческим восприятием и кодом.
UI показывает "NFT из коллекции X" → пользователь платит → получает что угодно.
Нет on-chain механизма проверки.

**GAP-08:** "Emergency tool" без ограничений по типу операции.
Единственная защита: `mode & 32` (DESTRUCT) + time-lock только для sold (sold_at != 0).

---

---

## PASS 5 — Normal Function Abuse

| Function | File | Abuse | Severity |
|---|---|---|---|
| cancel + op=555 | sale:358-394, 208-222 | marketplace cancels active sale → zero-delay op=555 drain | High |
| recv_external(op=2) | auction:414-428 | anyone ends auction → nft_owner теряет 0.5 TON profit | Medium |
| change_price + in-flight buy | sale:315-328 | seller sandwich: lower price → buyer buys cheap | Medium |
| deploy_jetton signature (no nonce) | sale:290-313 | replay старой подписи → откат marketplace_address/jetton config | Medium |
| bid + cancel block | auction:329,381-383 | griever bid blocks cancel → NFT hostage ~0.006 TON/step_time | High |
| op=555 on ~is_initialized | sale:208 | marketplace drains uninitialized contract before NFT arrives | Medium |

### Детали ключевых абьюзов

**ABUSE-01: cancel → op=555 без time-lock**
```
marketplace → cancel(sale) [sale:360 — marketplace may cancel]
  → save_data(is_complete=1, sold_at=0)
  → op=555 check: sold_at=0 → time-lock ПРОПУЩЕН [sale:216]
  → marketplace → op=555(arbitrary_msg) → НЕМЕДЛЕННО
```
Seller видит "отменено". NFT ушёл к marketplace. Нет защитного окна.

**ABUSE-02: recv_external griefing**
```
now() >= end_time:
  Griever → recv_external(op=2) [БЕСПЛАТНО, нет auth]
  → handle::end_auction(nft_owner, from_external=true)
  → profit -= 500000000  [auction:173]
  → nft_owner теряет 0.5 TON
nft_owner хотел internal op=2 → full profit — не успел
```

**ABUSE-03: deploy_jetton signature replay**
```
payload = slice_hash(new_mp_address + new_jetton_dict)
НЕТ nonce, timestamp, expiry, sale_address
→ любая действительная подпись может быть replayed
→ откат к старому marketplace или старым ценам jetton [sale:297-311]
```

**ABUSE-04: bid cycling (auction hostage)**
```
griever bid(min_bid) → last_member=griever → cancel BLOCKED [auction:329]
griever bid в окне end_time-step_time → end_time += step_time [auction:381]
return_last_bid(griever) - 5577000 ≈ net cost 0.006 TON/extension
max extension per bid: step_time seconds, unlimited iterations
```

---

---

## PASS 6 — Auction v4r1 Сравнительный Анализ

**Файл:** `nft-auction-v4r1.func` (685 строк)  
**Версия:** v4r1 — jetton-capable, переработанная архитектура vs v3r3

### Ключевые архитектурные отличия

| Аспект | v3r3 | v4r1 |
|---|---|---|
| Хранение | много глобальных vars | `pack_data()` / `init_data()` с константами в `constant_cell` |
| Jetton режим | нет | `is_jetton_mode`, `jetton_wallet`, `jetton_master` |
| Метрика газа | фиксированный `5577000` | `get_compute_fee(false, 11169)` — вычисляется |
| `public_key` | нет | есть, для `set_jetton_wallet` |
| `is_broken_state` | нет | флаг при невалидном jetton состоянии |
| `accept_message` | дважды (`recv_external` + `end_auction`) | один раз через `check_ok_balance` |
| Profit при external end | `-= 500000000` (0.5 TON) | `-= TON_FOR_NFT_PROCESS` (0.1 TON) |

---

### Статус каждой уязвимости v3r3 в v4r1

#### V4R1-01: return_last_bid mode=2 — PRESENT
`v4r1:393` — `send_raw_message(return_prev_bid.end_cell(), 2)` — IGNORE_ERRORS.  
Разница: `0x18` (bounce=true) vs v3r3 `0x10`, и вычисляемый gas, но mode=2 → silent fail остался.  
**Severity: High. Anchor: v4r1:393**

#### V4R1-02: recv_external без auth — PRESENT (смягчён)
`v4r1:620-634` — нет проверки отправителя. Любой вызывает `finish_auction` через external.  
Стоимость для nft_owner: `0.1 TON` (было `0.5 TON`).  
Но `check_ok_balance(profit)` при `from_external=true` бросает если profit < 0.1 TON → частичная защита при малых ставках.  
**Severity: Low-Medium (снижена с Medium). Anchor: v4r1:626-631**

#### V4R1-03: double accept_message — FIXED
v3r3: два вызова `accept_message()`. v4r1: один, через `check_ok_balance()` в `handle::end_auction`.

#### V4R1-04: cancel + bid cycling auction hostage — PRESENT
```
v4r1:537 — throw_if(exit::cant_cancel_bid(), last_bid > 0)
v4r1:447-449 — if ((end_time - step_time) < now()) { end_time += step_time; }
```
Механизм идентичен v3r3. Стоимость ~`get_compute_fee(false,11169)` ≈ 0.006 TON/step.  
**Severity: High. Anchor: v4r1:447,537**

#### V4R1-05: op=555 — PARTIAL FIX, новая дыра
v4r1 time-lock основан на `end_time` и `last_bid_at`:
```func
throw_if(exit::last_bid_too_close(), (now() > (end_time - ten_min)) & (now() < (end_time + ten_min)));
if (last_bid_at != 0) {
    throw_if(exit::last_bid_too_close(), (now() > (last_bid_at - ten_min)) & (now() < (last_bid_at + ten_min)));
}
```
**Дыра:** ранний cancel без ставок (`last_bid_at=0`):
- `end_time` остаётся исходным (через 3 дня)
- `now()` далеко от `end_time` → time-lock НЕ срабатывает
- `return_nft(mode=130)` в `handle::cancel` может fail silently
- NFT застрял → marketplace вызывает op=555 немедленно

**Условие:** cancel при `last_bid=0` + `return_nft` fail → mp немедленный drain.  
**Severity: Medium. Anchor: v4r1:508-528, 269-274, 266**

#### V4R1-06: return_nft mode=130 — PRESENT
`v4r1:266` — `send_raw_message(nft_return_msg.end_cell(), 130)` — IGNORE_ERRORS.  
Идентично v3r3. NFT может застрять при cancel или при отправке winner.  
**Severity: High. Anchor: v4r1:266**

#### V4R1-07: все выплаты IGNORE_ERRORS — PRESENT
- `send_founds` TON mode `v4r1:286` — mode=2
- `send_jettons` `v4r1:131` — mode=3 или mode=66, оба включают +2
- `return_last_bid` `v4r1:393` — mode=2  
LAW-14 нарушен идентично v3r3.  
**Severity: High (LAW-14). Anchor: v4r1:131,286,393**

#### V4R1-08: bounced messages игнорируются — PRESENT
`v4r1:482` — `throw_if(0, cs~load_uint(4) & 1)` — идентично v3r3.

---

### Новые проблемы v4r1 (не было в v3r3)

#### V4R1-NEW-01: set_jetton_wallet — signature без replay-protection
`v4r1:564-566`:
```func
var signature = in_msg_body~load_bits(512);
var payload = slice_hash(in_msg_body);  // = hash(new_jetton_wallet_addr)
throw_unless(35, check_signature(payload, signature, public_key));
```
Нет: nonce, expiry, auction_address binding.  
Дополнительная защита: `equal_slices(sender_addr, jetton_wallet)` — сообщение должно прийти ОТ текущего jetton_wallet.  
Но подпись сама по себе воспроизводима — если atacker перехватил transport или имеет старую signed payload → replay к другому auction с тем же public_key.  
**Severity: Low (ограничено транспортной защитой). Anchor: v4r1:560-583**

#### V4R1-NEW-02: is_broken_state блокирует все ставки
`v4r1:415-418`:
```func
if (is_broken_state == true) {
    throw(exit::broken_state());
}
```
`is_broken_state=true` устанавливается когда `has_public_key=1` в `jt_cell` (`v4r1:200`).  
Т.е. аукцион с public_key в initial state **физически не принимает ставки** пока jetton wallet не установлен через op=`set_jetton_wallet`.  
Если marketplace деплоит с `has_public_key=1` но `set_jetton_wallet` никогда не вызывается → auction hostage без какого-либо action от atacker.  
Это скорее **deployment bug surface** чем уязвимость, но nft_owner теряет NFT в broken auction.  
**Severity: Medium (deployment risk). Anchor: v4r1:192-201, 415**

---

### Итоговая сравнительная таблица

| # | Проблема | v3r3 | v4r1 | Severity |
|---|---|---|---|---|
| 1 | return_last_bid mode=2 | ✓ | ✓ | High |
| 2 | recv_external no auth | ✓ | ✓ | Low-Med (снижена) |
| 3 | double accept_message | ✓ | ✗ FIXED | — |
| 4 | bid cycling / cancel block | ✓ | ✓ | High |
| 5 | op=555 early cancel no timelock | ✓ | ✓ (иной механизм) | Medium |
| 6 | return_nft mode=130 | ✓ | ✓ | High |
| 7 | payments IGNORE_ERRORS | ✓ | ✓ | High |
| 8 | bounced ignored | ✓ | ✓ | — |
| NEW-01 | set_jetton_wallet sig replay | — | ✓ | Low |
| NEW-02 | is_broken_state deploy lock | — | ✓ | Medium |

**Вывод:** v4r1 исправил double accept_message и снизил recv_external griefing cost. Все структурные уязвимости (mode=2, mode=130, bid cycling, op=555 gap) сохранились.

---

---

## PASS 7 — Validation Planning

Топ-гипотезы по severity + evidence. Каждая → один минимальный безопасный тест.

---

```text
TEST-01:
Hypothesis: HYP-01 — is_complete=1 без доставки NFT (Vector B: mode=130 action fail)
Goal: Подтвердить что sale переходит в is_complete=1 при нехватке газа на transfer_nft
Setup:
  - testnet sale contract (уже задеплоен в poc-testnet.js)
  - NFT на sale contract
  - buyer wallet с МИНИМАЛЬНЫМ газом (0.1 TON — ровно min_gas)
Actions:
  1. Отправить buy(op=0x2) с value = full_price + 0.1 TON (без запаса на transfer_nft)
  2. Дождаться завершения TX
Data to capture:
  - get_sale_data() → is_complete, sold_at после TX
  - Баланс NFT contract — изменился ли owner
  - Message traces: был ли transfer_nft message отправлен? доставлен?
Expected result if TRUE:
  - is_complete=1, sold_at>0
  - NFT owner = seller (не изменился)
  - transfer_nft message: ABSENT или FAILED в traces
Expected result if FALSE:
  - TX revert (exit code != 0) или NFT доставлен
Safety notes: testnet only, используй адреса из testnet-wallets.seed
Required files/functions: poc-testnet.js, sale:397-425, sale:113
```

---

```text
TEST-02:
Hypothesis: HYP-02 — Auction hostage via bid cycling (griever locks NFT)
Goal: Подтвердить что повторные bid в окне step_time продлевают end_time бесконечно
Setup:
  - testnet auction contract с short end_time (e.g. now + 3*step_time)
  - griever wallet, nft_owner wallet
Actions:
  1. nft_owner деплоит auction, отправляет NFT → auction активирован
  2. griever делает bid(min_bid) при (end_time - step_time) < now()
  3. Записать новый end_time через get_auction_data()
  4. Повторить шаг 2 три раза
  5. nft_owner пытается cancel → ожидается throw(cant_cancel_bid)
Data to capture:
  - end_time после каждого bid
  - Результат cancel попытки (exit code)
  - Баланс griever: return_last_bid сумма vs bid сумма (net cost)
Expected result if TRUE:
  - end_time увеличивается на step_time каждый раз
  - cancel → exit::cant_cancel_bid (1009)
  - net cost griever = bid_amount - return_bid_amount ≈ compute_fee(11169)
Expected result if FALSE:
  - cancel успешен или end_time не изменяется
Safety notes: testnet only; не использовать реальные NFT
Required files/functions: nft-auction-v4r1.func:447,537; nft-auction-v3r3.func:381,329
```

---

```text
TEST-03:
Hypothesis: HYP-03 / ABUSE-01 — op=555 zero time-lock на canceled sale
Goal: Подтвердить что marketplace может вызвать op=555 немедленно после cancel (sold_at=0)
Setup:
  - testnet sale contract, is_complete=0, NFT на контракте
  - Симулировать stuck NFT: принудительно задержать return_nft (невозможно на testnet напрямую)
  - Альтернатива: read-only chain query — проверить логику через state inspection
Actions (read-only вариант):
  1. Прочитать sale contract state: is_complete, sold_at
  2. Симулировать cancel → save_data(is_complete=1, sold_at=0) локально
  3. Применить op=555 check logic: sold_at=0 → time-lock branch пропущен
  4. Verify: op=555 доступен немедленно без ожидания
Actions (testnet вариант):
  1. Задеплоить sale, отправить NFT → is_complete=0
  2. Marketplace вызывает cancel
  3. В той же секунде marketplace вызывает op=555(arbitrary_msg)
  4. Проверить: принят ли op=555 без ожидания
Data to capture:
  - Exit code op=555 TX
  - Время между cancel TX и op=555 TX (block время)
  - Состояние sale после обоих TX
Expected result if TRUE:
  - op=555 принят немедленно (exit code 0)
  - sold_at check пропущен в sale:216
Expected result if FALSE:
  - op=555 → throw(406) time-lock
Safety notes: testnet only; не тестировать op=555 против реального NFT
Required files/functions: sale:208-222, sale:358-394
```

---

```text
TEST-04:
Hypothesis: HYP-06 — Jetton buy action phase fail undetected (try/catch не ловит)
Goal: Подтвердить что is_complete=1 при failed jetton send (nobounce + mode=3 action fail)
Setup:
  - local simulation / testnet с контролируемым jetton_wallet
  - jetton_wallet настроен на REJECT входящих transfer (или неправильный адрес)
Actions:
  1. Buyer отправляет jetton_transfer_notification с корректным amount
  2. Sale вызывает send_jettons(nft_owner, amount) → action phase fail (wallet rejects)
  3. try/catch: НЕ ловит action phase fail → try block завершается успешно
  4. save_data(is_complete=1) коммитится
Data to capture:
  - is_complete после TX
  - Баланс jetton_wallet nft_owner: изменился ли?
  - Message traces: action phase результат send_jettons
Expected result if TRUE:
  - is_complete=1
  - nft_owner jetton balance = не изменился
  - send_jettons message: action fail в traces
Expected result if FALSE:
  - TX revert (catch срабатывает) или jettons доставлены
Safety notes: local simulation предпочтительнее; не использовать реальные jetton суммы
Required files/functions: sale:252-278, sale:86,94
```

---

```text
TEST-05:
Hypothesis: ABUSE-02 — recv_external griefing (nft_owner теряет 0.1 TON без согласия)
Goal: Подтвердить что anonymous external call завершает аукцион и вычитает из profit
Setup:
  - testnet auction contract, end_time прошёл, last_bid > 0
  - griever wallet (или вообще без wallet — external сообщение бесплатно)
Actions:
  1. Дождаться now() >= end_time
  2. Griever отправляет external message op=finish_auction
  3. Записать profit до и после
  4. Проверить nft_owner received amount
Data to capture:
  - nft_owner balance delta: ожидаемый profit vs фактический
  - check_ok_balance result: profit до вычета TON_FOR_NFT_PROCESS
  - TX traces: fee deduction
Expected result if TRUE:
  - nft_owner получает profit - 0.1 TON вместо полного profit
  - External TX принят без аутентификации
Expected result if FALSE:
  - throw(exit::not_activated_yet или exit::cant_stop_time)
Safety notes: testnet only; small auction amount
Required files/functions: nft-auction-v4r1.func:620-634, 337-345
```

---

```text
TEST-06:
Hypothesis: HYP-04 — Seller silent fail (nft_owner получает addr_none или frozen)
Goal: Подтвердить что buy завершается успешно при недоставляемом nft_owner адресе
Setup:
  - Signature payload inspection: проверить sale:150-155 на наличие nft_owner check
  - Read-only: верифицировать что nft_owner НЕ проверяется в buy_logic
Actions (static analysis):
  1. Читать sale:150-155 — fee_address и royalty_address проверяются на addr_none
  2. Читать sale:397-425 — nft_owner_address используется без проверки
  3. Документировать отсутствие check
Actions (testnet вариант):
  1. Деплоить sale с nft_owner = frozen/invalid address
  2. Buyer выполняет buy
  3. Записать is_complete, sold_at, nft_owner balance
Data to capture:
  - Наличие/отсутствие nft_owner addr_none check в code (static)
  - TX result при invalid nft_owner (testnet)
Expected result if TRUE:
  - is_complete=1, sold_at>0
  - nft_owner balance = 0 (деньги потеряны в void)
Expected result if FALSE:
  - throw или nft_owner деньги доставлены
Safety notes: static analysis sufficient; testnet для confirmation
Required files/functions: sale:150-155, sale:397-410
```

---

```text
TEST-07:
Hypothesis: V4R1-NEW-02 — is_broken_state deploy lock (аукцион не принимает ставки)
Goal: Подтвердить что аукцион с has_public_key=1 блокирует все bid до set_jetton_wallet
Setup:
  - Signature payload inspection: проверить init_data() logic
  - Деплоить v4r1 auction с jt_cell содержащим has_public_key=1 bit
Actions (static analysis):
  1. Читать v4r1:192-201 — when is is_broken_state=true установлен
  2. Читать v4r1:415-418 — process_new_bid проверяет is_broken_state
  3. Проверить: есть ли путь сбросить is_broken_state без set_jetton_wallet
Actions (testnet вариант):
  1. Деплоить auction с has_public_key=1
  2. NFT owner отправляет NFT → auction activated
  3. Buyer пытается bid
Data to capture:
  - Exit code от bid (ожидается exit::broken_state = 1016)
  - set_jetton_wallet доступен без действий nft_owner?
Expected result if TRUE:
  - bid → throw(1016 broken_state)
  - nft_owner не может разблокировать без marketplace помощи
Expected result if FALSE:
  - is_broken_state сбрасывается автоматически
Safety notes: testnet only
Required files/functions: nft-auction-v4r1.func:192-201,415-418,560-583
```

---

---

## PASS 8 — Kill Your Own Ideas

Попытка опровергнуть каждую сильную гипотезу через поиск блокирующих механизмов.

---

```text
HYP-ID: HYP-01
Hypothesis: is_complete=1 без доставки NFT
Blocking checks found:
  1. throw_unless(450, msg_value >= full_price + 0.1 TON) [sale:400] — buyer обязан
     предоставить достаточно газа
  2. NFT contract: throw_unless(402, rest_amount >= 0) [nft-item:83] — бросает
     если у него нет 0.05 TON для storage
  3. forward_amount=1 nanoTON [sale:104] — минимальный forward, не съедает баланс
Exact code/data anchor:
  sale:400 — min_gas check
  sale:104 — forward_amount=1
  nft-item:83 — storage throw
  sale:113 — mode=130 (128+2)
  sale:172 — bounced handler пустой
Gas trace (нормальный flow):
  buyer →  full_price + 0.1 TON
  -compute phase: ~0.01 TON
  -3x send_money mode=3 fees: ~0.003 TON
  = ~0.087 TON остаток → mode=128 несёт к NFT
  NFT имеет 0.087 TON > 0.05 TON → throw_unless(402) НЕ бросает → NFT transfer OK
Status: SUSPICIOUS (Vector B ослаблен; Vector A подтверждён)
Reason:
  Vector B (нехватка газа) — сложно триггернуть при min_gas=0.1 TON в нормальных условиях.
  0.087 TON остатка достаточно для NFT contract.
  Vector A (bounce) — ПОДТВЕРЖДЁН: если NFT контракт бросает ПО ЛЮБОЙ ПРИЧИНЕ
  (неинициализирован, уже передан, wrong workchain, любая custom logic) →
  bounce → sale:172 игнорирует → is_complete=1 уже committed.
  Существует poc-testnet.js для этой уязвимости.
What would fully kill it:
  bounce handler с откатом is_complete + refund buyer при получении bounced msg
What would make it stronger:
  Реальный TX trace где NFT бросает + bounce игнорируется + is_complete=1 на chain
```

---

```text
HYP-ID: HYP-02
Hypothesis: Auction hostage via bid cycling (end_time продлевается бесконечно)
Blocking checks found:
  1. throw_if(duration > 60*60*24*20) [v3r3:366 / v4r1:427] — cap на duration
Exact code/data anchor:
  v4r1:426-427 — duration = end_time - now(); throw_if > 20 days
  v4r1:447-449 — end_time += step_time при bid в окне
  v4r1:537 — cant_cancel_bid при last_bid > 0
Analysis of cap:
  throw_if check = end_time - now() > 20 days
  Это cap на ОСТАВШЕЕСЯ время от текущего момента, не суммарное.
  Пример: step_time=1h, end_time=now+1h
  Bid#1 at t=55min → end_time=now+2h, duration=2h < 20 days → OK
  Bid#2 at t=115min → end_time=now+3h → OK
  ... → Bid#N → end_time=now+20days-1min → OK (всё ещё < cap)
  Bid#N+1 при duration=20days-1min → end_time=now+20days-1min+step_time
  Если step_time=1h → duration=20days+1h → throw! ← ЕДИНСТВЕННАЯ ОСТАНОВКА
  Но attacker просто ждёт 1.5h → duration снова < 20 days → bid снова работает
Status: CONFIRMED
Reason:
  Cap проверяет ТЕКУЩИЙ остаток, не суммарную длительность.
  При ожидании между bidами attacker сбрасывает cap.
  Нет ограничения на количество продлений.
  cancel заблокирован last_bid > 0.
  Блокирующий механизм НЕЭФФЕКТИВЕН.
What would fully kill it:
  cap на суммарное продление (max_extensions * step_time) OR
  cancel разрешить при last_bid > 0 с penalty возвратом
What would make it stronger:
  Посчитать net cost за 30-дневный захват NFT (число bid × 0.006 TON)
```

---

```text
HYP-ID: HYP-03
Hypothesis: op=555 zero time-lock на canceled sale (sold_at=0)
Blocking checks found:
  1. throw_if(408, ~is_complete) [sale:208] — op=555 только при is_complete=1
  2. throw_unless(403, equal_slices(sender_addr, marketplace_address)) [sale:211]
  3. mode & 32 check [sale:213] — DESTRUCT запрещён
  4. if (sold_at != 0) { throw_if(406, ...) } [sale:216-219]
Analysis:
  Check #4 — условие НА time-lock, не сам time-lock.
  При canceled: sold_at=0 → condition false → throw_if блок не выполняется.
  Check #1 и #2 — выполняются (is_complete=1, sender=marketplace).
  Нет другого time-lock для cancel path.
Status: CONFIRMED
Reason:
  Единственный time-lock обёрнут в `if (sold_at != 0)`.
  Cancel устанавливает sold_at=0 [sale:393].
  Путь полностью открыт для marketplace немедленно.
  Требует: marketplace actor (доверенный в системе) + failed return_nft.
What would fully kill it:
  time-lock независимо от sold_at: использовать max(sold_at, cancel_at) или
  отдельный canceled_at timestamp
What would make it stronger:
  TX trace: cancel TX block + op=555 TX block в следующем блоке
```

---

```text
HYP-ID: HYP-06
Hypothesis: Jetton buy — try/catch не ловит action phase fail → is_complete=1
Blocking checks found:
  1. try/catch в FunC [sale:252-278]
  2. send_jettons использует 0x10 (nobounce) + mode=3 [sale:86,94]
Analysis:
  try/catch в FunC: ловит TVM EXCEPTIONS (compute phase) только.
  Пример compute exception: cell underflow, div by zero, throw().
  Action phase fail: НЕ является TVM exception.
  mode=3 включает mode=2 (IGNORE_ERRORS) → action fail → нет exception → нет throw.
  Механизм: action phase происходит ПОСЛЕ compute phase.
  К моменту action phase try блок уже завершён успешно.
  save_data(1) вызывается в compute phase → уже committed.
Status: CONFIRMED (архитектурный факт TON VM)
Reason:
  Не мнение — это фундаментальная модель TON: compute ≠ action phase.
  try/catch физически не может поймать action phase failures.
  Это не баг в коде — это misuse of the pattern.
  Единственный блокирующий механизм отсутствует на уровне language.
What would fully kill it:
  Bounce handlers на 0x18 messages + is_complete flag rollback
  ИЛИ check jetton balance before/after (невозможно в one-TX TON model)
What would make it stronger:
  Local TVM simulation с принудительным action phase fail
```

---

```text
HYP-ID: ABUSE-02
Hypothesis: recv_external griefing — anonymous caller завершает аукцион, nft_owner теряет 0.1 TON
Blocking checks found:
  1. v4r1: check_ok_balance(profit) [v4r1:339] — throw если profit < 0.1 TON
  2. v4r1: throw_if(exit::cant_stop_time(), now() < end_time) [v4r1:629] — только после дедлайна
  3. v4r1: throw_if(exit::auction_end(), end? == true) [v4r1:628] — только один раз
  4. v3r3: те же checks + НЕТ balance check
Analysis:
  v4r1 check_ok_balance: если profit < TON_FOR_NFT_PROCESS=0.1 TON → throw BEFORE accept_message.
  Это реально блокирует griefing для малых аукционов.
  НО: для аукционов с profit > 0.1 TON griefing работает.
  Нет аутентификации отправителя в recv_external.
  Аттакер не тратит TON (external msgs бесплатны для отправителя).
  nft_owner может потерять именно 0.1 TON от profit.
v3r3 analysis:
  profit -= 500000000 жёстко закодировано [v3r3:173].
  Нет balance check. Griefing стоит nft_owner 0.5 TON при любом profit.
Status: CONFIRMED (оба контракта)
Reason:
  check_ok_balance частично защищает v4r1 при малых аукционах.
  Для продуктивных аукционов (profit >> 0.1 TON) griefing полностью работает.
  Отсутствие sender auth в recv_external — архитектурный gap.
What would fully kill it:
  Требовать подпись nft_owner или marketplace в external message
What would make it stronger:
  Размер реальных аукционов на mainnet (наличие аукционов с profit > 0.1 TON)
```

---

```text
HYP-ID: HYP-04
Hypothesis: Seller silent fail — nft_owner получает addr_none или undeliverable address
Blocking checks found:
  1. fee_address check: preload_uint(2) != 0 [sale:150-151]
  2. royalty_address check: preload_uint(2) != 0 [sale:153-154]
  3. Нет аналогичного check для nft_owner_address
Exact code/data anchor:
  sale:150-155 — check только fee и royalty
  sale:407 — send_money(nft_owner_address, user_amount) без check
Analysis:
  Precondition: nft_owner_address = addr_none ИЛИ frozen account ИЛИ cross-workchain.
  В нормальном flow: nft_owner_address устанавливается при ownership_assigned [sale:330-350].
  Если sender при ownership_assigned = addr_none → нереальный сценарий (NFT должен иметь owner).
  НО: при Fake NFT (HYP-05) создатель контролирует sender в ownership_assigned.
  Создатель может указать nft_owner = addr_none → buyer платит, никто не получает NFT деньги.
  Другой сценарий: nft_owner freezes account после listing, до buy.
  Frozen account: messages могут быть отклонены. mode=3 IGNORE_ERRORS → деньги потеряны.
Status: SUSPICIOUS (низкая вероятность в нормальном flow, CONFIRMED в Fake NFT combo)
Reason:
  Standalone: требует редкий precondition (frozen nft_owner).
  В combo с HYP-05: нарушитель сам ставит addr_none в ownership_assigned.
  Отсутствие check — code gap, но exploit требует нестандартного precondition.
What would fully kill it:
  throw_unless(addr_none check, nft_owner_address.preload_uint(2) != 0) при ownership_assigned
What would make it stronger:
  Combo с HYP-05: fake NFT с addr_none owner
```

---

```text
HYP-ID: HYP-05
Hypothesis: Fake NFT — sale выглядит валидной, buyer получает мусор
Blocking checks found:
  1. equal_slices(sender_address, nft_address) при ownership_assigned [sale:340]
  2. Нет других on-chain checks
Analysis:
  Check #1 — проверяет что сообщение пришло ОТ адреса nft_address.
  Если attacker деплоит fake NFT contract на адрес X и устанавливает nft_address=X:
  - Fake NFT отправляет ownership_assigned с sender=X → check проходит
  - Нет проверки: collection, TEP-62 compliance, index validity
  - Нет registry или allowlist на sale contract
  Off-chain: marketplace frontend может проверять легитимность.
  On-chain: нет механизма.
Status: CONFIRMED (on-chain)
Reason:
  on-chain нет blockers кроме address match.
  Любой fake contract на workchain 0 может пройти все checks.
  Это design decision (permissionless listing) с неявным доверием к off-chain.
  Impact: buyer платит → получает fake NFT (мусор).
  Requires: victim видит "легитимный" листинг в UI.
What would fully kill it:
  On-chain: registry легитимных collection addresses (централизованно)
  ИЛИ TEP-62 address derivation verify (collection + index → expected_addr == nft_address)
What would make it stronger:
  Фактические случаи fake NFT листингов в GetGems history
```

---

### Итог PASS 8

| HYP-ID | Status | Severity | Требует |
|---|---|---|---|
| HYP-01 | SUSPICIOUS→CONFIRMED (Vector A) | Critical | TX trace |
| HYP-02 | CONFIRMED | High | step_time mainnet values |
| HYP-03 | CONFIRMED | Medium | marketplace cooperation |
| HYP-06 | CONFIRMED (архитектурный) | High | local TVM sim |
| ABUSE-02 | CONFIRMED | Low-Med | mainnet auction sizes |
| HYP-04 | SUSPICIOUS (combo CONFIRMED) | Medium | fake NFT precondition |
| HYP-05 | CONFIRMED (on-chain) | Critical | off-chain mitigation unclear |

**Ни одна гипотеза полностью не опровергнута.**

---

---

## PASS 9 — Prioritization

Оценка по 1–5 для распределения ручного времени.

---

```text
HYP-ID: HYP-01 (is_complete=1 без доставки NFT)
Impact: 5 — buyer теряет full_price, NFT застрял
Reachability: 4 — любой throw NFT контракта тригерит (uninitialized, gas, custom logic)
Novelty: 2 — паттерн "async delivery + sync state" известен в TON
Evidence Strength: 5 — poc-testnet.js существует, code path подтверждён
Testability: 5 — PoC уже написан
Cross-component Disagreement: 5 — sale.is_complete=1 vs NFT.owner=seller
Economic Plausibility: 5 — full_price на кону
Priority: Critical Lead
Why: Единственная уязвимость с готовым PoC. Vector A (bounce ignore)
  технически неопровержим. Потеря = full price любого NFT.
Next best action: запустить poc-testnet.js, получить TX hash → закрыть Evidence
```

---

```text
HYP-ID: HYP-05 (Fake NFT — нет TEP-62 check)
Impact: 5 — buyer платит за мусор, on-chain нет защиты
Reachability: 4 — деплой fake contract + листинг на GetGems (off-chain friction)
Novelty: 2 — известен, но часто dismissed как "off-chain responsibility"
Evidence Strength: 5 — code gap абсолютно чист, нет blockers
Testability: 5 — деплой fake NFT на testnet, листинг, buy
Cross-component Disagreement: 5 — UI="настоящий NFT", on-chain="любой addr"
Economic Plausibility: 5 — scam любого размера
Priority: Critical Lead
Why: Нет on-chain механизма проверки легитимности NFT.
  Единственная защита — off-chain (marketplace UI/indexer).
  Если off-chain проверка обходима → критическая уязвимость для пользователей.
Next best action: проверить off-chain проверку GetGems (что именно верифицирует?)
  если off-chain нет → Critical; если есть → Medium
```

---

```text
HYP-ID: HYP-02 (Auction hostage via bid cycling)
Impact: 4 — NFT заблокирован бесконечно, nft_owner не может вернуть
Reachability: 4 — нужен только min_bid (~0.1 TON), нет auth
Novelty: 3 — step_time + cancel_block combo менее известна
Evidence Strength: 4 — 20-day cap bypass доказан логически, нет testnet confirmation
Testability: 4 — тест на testnet простой (3-4 bid + cancel попытка)
Cross-component Disagreement: 3 — внутри auction contract
Economic Plausibility: 4 — дорогой NFT + дешёвый attack (~0.006 TON/step)
Priority: Strong Lead
Why: Дешёвый DoS с высоким impact для nft_owner.
  cap через 20 дней не работает при ожидании между bidами.
  Testnet подтверждение нужно для полноты.
Next best action: TEST-02 на testnet, замерить end_time после 3 bid + попытка cancel
```

---

```text
HYP-ID: HYP-06 (Jetton action phase fail в try/catch)
Impact: 4 — buyer теряет jettons, is_complete=1
Reachability: 3 — требует failure jetton delivery (unusual but no mitigation)
Novelty: 3 — TON try/catch misuse задокументирован, но не всегда проверяется
Evidence Strength: 5 — архитектурный факт TON VM (не мнение)
Testability: 3 — требует контролируемый jetton wallet (reject transfers)
Cross-component Disagreement: 4 — sale.is_complete=1, jetton_balance=не изменился
Economic Plausibility: 3 — зависит от jetton price, delivery failure trigger
Priority: Strong Lead
Why: Architecturally certain — try/catch не ловит action phase в TON.
  Reachability снижена отсутствием common trigger.
  Но когда триггерится → buyer теряет деньги без recourse.
Next best action: TEST-04 local TVM simulation с reject-jetton-wallet
```

---

```text
HYP-ID: ABUSE-02 (recv_external griefing)
Impact: 2 — 0.1 TON потери на аукцион (v4r1), 0.5 TON (v3r3)
Reachability: 5 — любой, бесплатно, после end_time
Novelty: 2 — отсутствие auth в recv_external — классика
Evidence Strength: 4 — code подтверждён
Testability: 4 — testnet простой
Cross-component Disagreement: 2 — внутри auction
Economic Plausibility: 3 — дешёвый griefing, малый финансовый impact
Priority: Interesting But Weak
Why: Impact низкий (0.1 TON), но reachability максимальный.
  Скорее nuisance чем серьёзная уязвимость.
  v4r1 частично защищён check_ok_balance.
Next best action: отметить как Low в отчёте, не тратить testnet время
```

---

```text
HYP-ID: HYP-03 (op=555 zero time-lock на canceled)
Impact: 3 — NFT stolen если return_nft failed
Reachability: 2 — требует marketplace cooperation + failed return_nft
Novelty: 3 — time-lock gap через sold_at=0 нетривиален
Evidence Strength: 5 — code path абсолютно чист
Testability: 4 — read-only verification достаточно
Cross-component Disagreement: 2 — внутри sale
Economic Plausibility: 2 — marketplace должен быть bad actor ИЛИ compromised
Priority: Interesting But Weak
Why: Code gap реален, но эксплуатация требует trusted actor (marketplace).
  В threat model: marketplace = trusted → Low.
  В threat model: marketplace compromised → Medium/High.
  Зависит от scope аудита.
Next best action: уточнить threat model (marketplace trusted?) → если нет → повысить
```

---

```text
HYP-ID: HYP-04 (Seller silent fail)
Impact: 3 — seller теряет user_amount
Reachability: 2 — standalone: требует frozen/addr_none nft_owner (редко)
              combo с HYP-05: attacker контролирует nft_owner → Reachability 4
Novelty: 3 — missing validation классика
Evidence Strength: 4 — code gap подтверждён, precondition нетривиален
Testability: 4 — static analysis достаточно для standalone
Cross-component Disagreement: 2 — внутри sale
Economic Plausibility: 2 — standalone редко; в combo с HYP-05 возможно
Priority: Needs More Data
Why: Standalone слаб (редкий precondition).
  В combo с HYP-05 усиливается, но тогда root cause = HYP-05.
  Отдельно: задокументировать как missing check, не как отдельный high.
Next best action: TEST-06 static analysis, включить в отчёт как sub-finding HYP-05
```

---

```text
HYP-ID: V4R1-NEW-02 (is_broken_state deploy lock)
Impact: 3 — NFT заблокирован в broken auction
Reachability: 3 — требует deployment с has_public_key=1 без follow-up set_jetton_wallet
Novelty: 4 — специфично для v4r1 jetton mode
Evidence Strength: 4 — code confirmed
Testability: 4 — static analysis + deploy test
Cross-component Disagreement: 2 — внутри auction
Economic Plausibility: 2 — deployment error, не активный exploit
Priority: Needs More Data
Why: Неизвестно используется ли has_public_key=1 в mainnet deployments.
  Если нет → theoretical. Если да → Medium risk для тех аукционов.
Next best action: grep mainnet TX для op=set_jetton_wallet чтобы узнать используется ли
```

---

```text
HYP-ID: ABUSE-03 (deploy_jetton signature replay, sale)
Impact: 2 — откат marketplace config или jetton prices
Reachability: 1 — требует перехват старой подписи + отправка с текущего jetton_wallet
Novelty: 3 — signature replay классика, partial mitigation через sender check
Evidence Strength: 3 — code gap есть, но transport friction высока
Testability: 2 — требует capture старой подписи
Cross-component Disagreement: 1 — внутри sale
Economic Plausibility: 1 — config rollback малый impact
Priority: Likely Blocked
Why: Sender must = current jetton_wallet — это существенный barrier.
  Attacker должен контролировать jetton_wallet ИЛИ перехватить его transport.
  В реальном сценарии маловероятно.
Next best action: закрыть как Low / theoretical в отчёте
```

---

### Приоритетный список

| Rank | HYP-ID | Priority | Следующий шаг |
|---|---|---|---|
| 1 | HYP-01 | **Critical Lead** | запустить poc-testnet.js → TX hash |
| 2 | HYP-05 | **Critical Lead** | проверить off-chain mitigation GetGems |
| 3 | HYP-02 | **Strong Lead** | TEST-02 testnet (bid cycling) |
| 4 | HYP-06 | **Strong Lead** | TEST-04 local TVM sim |
| 5 | HYP-03 | **Interesting But Weak** | зависит от threat model |
| 6 | ABUSE-02 | **Interesting But Weak** | Low в отчёте, не тестировать |
| 7 | HYP-04 | **Needs More Data** | статика, sub-finding HYP-05 |
| 8 | V4R1-NEW-02 | **Needs More Data** | grep mainnet TXs |
| 9 | ABUSE-03 | **Likely Blocked** | Low/theoretical в отчёте |

---

## TODO / Next

- [x] PASS 0-8 выполнены
- [x] PASS 9 — Prioritization
- [x] PASS 10 — Final Report → FINAL_REPORT.md
- [x] #1: HYP-01 TESTNET-CONFIRMED — TX: KMvdSOiwWqDkF+Fjn5e4+APlZ5n+MMjwWRwQIOTEp1c=
- [x] #2: HYP-05 TESTNET-CONFIRMED — off-chain partial mitigation (wallet not indexed; fake TEP-62 contract would be)
- [x] #3: HYP-02 TESTNET+MAINNET-CONFIRMED — testnet: 120s extension; mainnet v3r3: +300s, seqno=68
- [ ] #4: TEST-04 local sim jetton fail (HYP-06) — архитектурно подтверждено, testnet sim опционален
- [x] Финальный отчёт → FINAL_REPORT.md, VERIFICATION_COMPLETE.md, HYP-0[125]_REPRO.md
