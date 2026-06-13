# Audit Reasoning Report — GetGems NFT Contracts (TON)

**Date:** 2026-05-15  
**Scope:** `nft-fixprice-sale-v4r1.fc`, `nft-auction-v3r3.func`, `nft-auction-v4r1.func`, `nft-marketplace.fc`, `nft-item.fc`  
**Protocol:** vscode_agent_audit_protocol.md (PASS 0–9)  
**Language:** FunC / TON Blockchain  

---

## 1. Mental Model

Система состоит из автономных контрактов-акторов. Нет атомарности между контрактами.

**Sale flow:**
```
Buyer → sale(buy) → sale commits is_complete=1 → send_money×3 (nobounce, IGNORE_ERRORS)
                                                → transfer_nft (bounce=true, IGNORE_ERRORS)
                                                ← bounce if NFT throws (IGNORED)
```

**Auction flow:**
```
Marketplace → deploy auction → nft_owner sends NFT → auction activated
Bidder → bid → return_last_bid (IGNORE_ERRORS) → update state
(anyone) → recv_external(finish) → handle::end_auction → send payments (IGNORE_ERRORS) → return_nft (IGNORE_ERRORS)
```

**Критические свойства системы:**
- `is_complete=1` и `end?=true` — state flags, NOT delivery confirmations
- Все outgoing payments используют IGNORE_ERRORS (mode=2 или mode=3)
- Bounced messages игнорируются во всех контрактах
- try/catch ловит только compute phase exceptions, не action phase failures
- NFT address = arbitrary workchain-0 address; нет TEP-62 validation
- Marketplace может cancel любую активную продажу и немедленно вызвать op=555

---

## 2. Source Reliability

| Источник | Статус | Уровень доверия |
|---|---|---|
| Исходники `.fc/.func` | Верифицированы построчно | High |
| Скомпилированный BOC (poc-testnet.js) | Частично — pre-existing | Medium |
| PoC скрипт (01-bounced-nft-loss/) | Существует, TX hash отсутствует | Medium |
| Mainnet адреса | Заглушки (`EQD__`) | Не верифицировано |
| Off-chain логика (GetGems backend) | Не исследована | Unknown |
| Spec-тесты | Не найдены | Отсутствует |
| TX traces | Не получены | Отсутствует |

**Что НЕ проверялось:** backend/indexer верификация листингов, off-chain TEP-62 validation, реальные gas costs в mainnet, jetton wallet адреса в jetton_price_dict.

---

## 3. Non-Obvious System Laws

Законы, нарушение которых не очевидно из документации:

| LAW | Statement | Status |
|---|---|---|
| LAW-01 | `is_complete=1` → NFT доставлен покупателю | **НАРУШЕН** |
| LAW-03 | payment ↔ NFT delivery атомарны | **НАРУШЕН** |
| LAW-05 | Outbid bidder всегда получает ставку обратно | **НАРУШЕН** |
| LAW-09 | jetton_notification = proof of payment | **ЧАСТИЧНЫЙ** |
| LAW-10 | Auction end_time конечен | **ЧАСТИЧНЫЙ** (bid cycling) |
| LAW-14 | `end?=true` → все выплаты доставлены | **НАРУШЕН** |

**Наиболее опасный закон:** LAW-01. Человек и все downstream системы интерпретируют `is_complete=1` как "сделка завершена успешно". Контракт гарантирует только "TX прошёл". NFT может быть не доставлен.

---

## 4. Weird Hypotheses

| ID | Hypothesis | Status | Severity |
|---|---|---|---|
| HYP-01 | `is_complete=1` без NFT delivery (bounce ignored + mode=130) | **CLOSED** — оба вектора заблокированы backend GetGems | ~~Critical~~ → Info |
| HYP-02 | Auction bid cycling: end_time продлевается при ставке в окне | **MAINNET-CONFIRMED** | Low (нормальная механика; атака требует рыночную ставку) |
| HYP-03 | op=555 zero time-lock при canceled sale (sold_at=0) | **CONFIRMED** | Medium |
| HYP-04 | Seller silent fail: nft_owner undeliverable, деньги в void | **SUSPICIOUS** (редкий precondition) | Medium |
| HYP-05 | Fake NFT: нет TEP-62 on-chain check | **TESTNET-CONFIRMED** | Info (закрыт backend-валидацией GetGems) |
| HYP-06 | Jetton buy: try/catch не ловит action phase fail → is_complete=1, jettons в void | **CLOSED** — нет реального тригера для обычного пользователя, только edge cases | High → Info |
| HYP-07 | Auction max-bid: return_last_bid mode=2 → previous bidder теряет ставку | **CLOSED** — реально только для контрактов-bidder'ов, не обычных пользователей | Medium → Info |
| ABUSE-01 | cancel + op=555: marketplace cancel → zero-delay op=555 | **CONFIRMED** | High |
| ABUSE-02 | recv_external griefing: anyone ends auction, nft_owner теряет 0.1-0.5 TON | **CLOSED** — intended TON behavior, деньги идут корректно, косметика | Low → Info |
| ABUSE-04 | deploy_jetton signature replay (sale) | **LIKELY BLOCKED** | Low |

---

## 5. Semantic Gaps

Расхождения между тем что понимает человек и что делает код:

**GAP-01 — `is_complete=1` (КРИТИЧНЫЙ)**
- Contract meaning: "TX execution завершена"
- Human meaning: "NFT куплен, delivered"
- Next component (indexer/UI): читает флаг как "successful sale"
- Economic meaning: "деньги ушли, NFT не пришёл" — возможно

**GAP-04 — `nft_address` (КРИТИЧНЫЙ)**
- Contract meaning: arbitrary workchain-0 address, прошедший `equal_slices` check
- Human meaning: NFT из известной коллекции, с верифицированными метаданными
- UI meaning: "показываем картинку из metadata"
- Gap: attacker деплоит fake contract → все checks проходят on-chain → buyer получает мусор

**GAP-05 — `return_last_bid` (HIGH)**
- Contract meaning: "send message с mode=2 отправлен"
- Human meaning: "предыдущий bidder получил деньги обратно"
- Actual: silent fail возможен, нет retry, нет bounce handler

**GAP-07 — `end?=true` (КРИТИЧНЫЙ)**
- Contract meaning: "auction end processing выполнен в рамках TX"
- Human meaning: "all parties received their funds/NFT"
- All outgoing sends: mode=2 IGNORE_ERRORS — delivery не гарантирована

**GAP-08 — `op=555` emergency**
- Marketed meaning: "emergency rescue for stuck NFTs"
- Actual: arbitrary message sending, zero time-lock при canceled (sold_at=0)
- Risk: if marketplace compromised → arbitrary drain of any stuck sale

---

## 6. Strongest Leads

### Lead #1: HYP-01 — Bounced NFT transfer ignored (Critical)

**Why it matters:** Buyer теряет full_price. NFT остаётся у seller. `is_complete=1` на chain. Нет механизма recovery кроме ручного op=555 через marketplace.

**Weird state:** `is_complete=1, sold_at>0, NFT.owner = seller_address`

**Disagreeing components:**
- sale contract: "продано успешно"
- NFT contract: "owner не изменился"
- Buyer: "деньги ушли, NFT не получен"

**Mechanism (Vector A):**
```
buy TX → send_money×3 → send transfer_nft(0x18, mode=130)
       → NFT contract throws (any reason: gas, state, custom)
       → bounce message → sale:172: if(flags&1){return();} — ИГНОРИРУЕТСЯ
       → save_data(is_complete=1) уже committed в той же TX
```

**Safe first test:** запустить `01-bounced-nft-loss/poc-testnet.js` → capture TX hash → проверить state через get_sale_data()

---

### Lead #2: HYP-05 — Fake NFT (No TEP-62 Validation) (Critical)

**Why it matters:** Любой может создать листинг с fake NFT. Покупатель платит реальные TON. On-chain нет защиты.

**Weird state:** `sale.nft_address = FakeContract.address`, `is_complete=1`, buyer "владеет" фейком

**Disagreeing components:**
- UI/indexer: "показывает NFT из коллекции X" (off-chain)
- sale contract: "адрес совпал — OK"
- TEP-62 spec: "NFT address = hash(collection, index)" — НЕ ПРОВЕРЯЕТСЯ

**Blocking check (единственный):** `equal_slices(sender_address, nft_address)` при ownership_assigned — проверяет только что сообщение пришло от nft_address, не что это легитимный NFT

**Safe first test:** деплоить fake NFT contract на testnet, выставить через sale, купить → проверить что `is_complete=1` без ошибок

**Open question:** есть ли off-chain validation в GetGems backend? Если да — impact снижается до Medium. Если нет — Critical.

---

### Lead #3: HYP-02 — Auction Hostage (Bid Cycling) (High)

**Why it matters:** Griever тратит ~0.006 TON/шаг чтобы заблокировать NFT владельца навсегда. `cancel` недоступен при любой ставке.

**Weird state:** `end_time = now + 20_days - 1_min` повторно, бесконечно. nft_owner не может cancel.

**Mechanism:**
```
griever bid(min_bid) при (end_time - step_time) < now()
  → end_time += step_time
  → return_last_bid(griever) - gas_fee ≈ net_cost ~0.006 TON
  → repeat при сближении с end_time
nft_owner → cancel → throw(1009 cant_cancel_bid)
```

**20-day cap bypass:** `throw_if(duration > 20 days)` проверяет `end_time - now()`, не суммарное продление. Attacker ждёт пока duration < 20d → продлевает снова.

**Safe first test:** TEST-02 на testnet — 3 bid + cancel попытка → verify exit code 1009

---

## 7. Disproved / Likely Blocked Ideas

**H-race-condition-end-auction (v3r3)**
- Blocking check: `end?` флаг устанавливается в первой TX → повторный вызов бросает
- Code anchor: `v3r3: if end? { throw(); }` перед processing
- Confidence: High (DISPROVED для v3r3)

**H-double-init (sale)**
- Blocking check: повторный ownership_assigned → `throw_if(sales_data already initialized)` → bounce → NFT возвращается
- Code anchor: sale:323-349
- Confidence: High (DISPROVED)

**H-query-id-replay**
- Blocking check: query_id идемпотентен по дизайну TON, нет value transfer через query_id
- Code anchor: query_id используется только как correlation ID
- Confidence: High (DISPROVED)

**ABUSE-03 — deploy_jetton signature replay (sale)**
- Blocking check: `equal_slices(sender_addr, jetton_wallet)` — сообщение должно прийти ОТ текущего jetton_wallet
- Code anchor: sale:303
- Confidence: Medium — replay возможен если attacker контролирует jetton_wallet transport, но это нереалистично
- Status: LIKELY BLOCKED

**HYP-01 Vector B — Malicious NFT (throw on 2nd transfer) ✅ TESTNET-CONFIRMED 2026-05-16**
- Attacker deploys TEP-62-compatible NFT with `transfer_count` in storage
- 1st transfer (owner→sale): allowed, count 0→1
- 2nd transfer (sale→buyer): `throw_if(450, transfer_count > 0)` → bounce → sale:172 ignores → `is_complete=1`
- NFT appears legitimate in tonapi/GetGems UI ("Kepka #0", sale indexed at correct price)
- PoC: `02-fake-nft-listing/poc-hyp01-malicious-nft.js`
- Contracts: NFT `0:cbf255ca...` / Sale `0:68a02ff2...` (testnet)
- Result: `is_complete=true`, NFT stuck in sale contract, buyer paid 0.05 TON

---

## 8. Suggested Experiments

**EXP-01 (HYP-01 — Critical, PoC ready)**
- Цель: подтвердить is_complete=1 при bounced transfer_nft
- Setup: testnet, `01-bounced-nft-loss/poc-testnet.js`
- Действия: запустить скрипт → записать TX hash → get_sale_data()
- Expected true: is_complete=1, sold_at>0, NFT.owner = seller
- Expected false: TX revert или NFT доставлен
- Data to save: TX hash, block seq, get_sale_data output

**EXP-02 (HYP-02 — Bid Cycling)**
- Цель: подтвердить бесконечное продление end_time + cancel block
- Setup: testnet auction, step_time=60s, end_time=now+120s
- Действия: 3 bid в окне (end_time - step_time) → попытка cancel
- Expected true: end_time увеличивается каждый раз, cancel → exit code 1009
- Expected false: cancel успешен или end_time не меняется
- Data to save: end_time после каждого bid, exit code cancel

**EXP-03 (HYP-05 — Fake NFT)**
- Цель: подтвердить on-chain отсутствие TEP-62 verification
- Setup: testnet fake NFT contract (принимает transfer, отправляет ownership_assigned)
- Действия: листинг через sale → buy → проверить is_complete
- Expected true: is_complete=1, buyer "владеет" fake NFT
- Expected false: throw на любом этапе
- Data to save: TX hashes, get_sale_data output, fake NFT owner

**EXP-04 (HYP-06 — Jetton Action Phase Fail)**
- Цель: подтвердить что try/catch не ловит action phase failure
- Setup: local TVM simulation с jetton_wallet настроенным на reject transfers
- Действия: send jetton_transfer_notification → observe try/catch behavior
- Expected true: compute phase успешна, action fail не поймана, is_complete=1
- Expected false: catch срабатывает
- Data to save: TVM execution log, compute/action phase results

---

## 9. Final Judgment

**HYP-01 (is_complete=1 без NFT): ❌ CLOSED — заблокирован backend GetGems**
> Vector A (bounce ignore): on-chain подтверждён, но backend проверяет nft_address — только реальный NFT-контракт принимается.
> Vector B (malicious NFT, throw on 2nd transfer): on-chain подтверждён (testnet), но GetGems не показывает NFT из неодобренных коллекций (approved_by=[]).
> Уязвимость контракта реальна архитектурно. Для эксплуатации через GetGems UI требуется одобренная коллекция — что не в силах атакера.
> Severity для bounty: Info (аналогично HYP-05).

**HYP-05 (Fake NFT): ❌ CLOSED — закрыт backend-валидацией GetGems**
> Подтверждён on-chain: нет TEP-62 проверки в контракте. Но GetGems backend отклоняет листинги без верифицированной коллекции.  
> Для баунти не подходит. Info severity.

**HYP-02 (Auction Hostage): ✅ MAINNET-CONFIRMED — нормальная механика, Low severity**
> Подтверждён на mainnet 2026-05-16 (auction `0:4401c1cc...`, +300s при ставке в окне).  
> Атака требует рыночную ставку (outbid all competitors). Не бесплатная эксплуатация.

**HYP-06 (Jetton action phase fail):**
> Confirmed divergence between components; impact depends on how frequently jetton delivery fails.  
> try/catch misuse — архитектурный факт TON VM. Reachability trigger нужен.

**HYP-07 (return_last_bid mode=2):**
> Strong lead; confirmed by code (mode=2 IGNORE_ERRORS, no bounce handler).  
> Previous bidder теряет ставку при любом action phase fail.

**Общий вердикт:**  
> Система содержит множество confirmed divergences между state flags и actual delivery. Нет ни одного invariant, который гарантирует доставку при is_complete=1 или end?=true. Strongest invariant (min_gas check) защищает от Vector B HYP-01 в нормальных условиях, но не блокирует Vector A (bounce). Fake NFT уязвимость целиком зависит от off-chain.

---

## Финальная таблица уязвимостей

| # | Title | Severity | Anchor | Confidence |
|---|---|---|---|---|
| 01 | is_complete=1 без NFT (bounce ignored, mode=130) | **Critical** | sale:113,172,416 | **TESTNET-CONFIRMED** (TX: KMvdSOiw...) |
| 02 | Fake NFT — нет TEP-62 on-chain validation | **Info** | sale:29-39,340 | Закрыт backend GetGems |
| 03 | return_last_bid mode=2 IGNORE_ERRORS | **High** | v3r3:257, v4r1:393 | High (code verified) |
| 04 | Auction bid cycling (end_time extension) | **Low** | v3r3:329,381 v4r1:537,447 | Нормальная механика; атакующий платит рыночную цену |
| 05 | Jetton buy: try/catch misuse (action phase undetected) | **High** | sale:86,94,252-278 | High (architectural) |
| 06 | end?=true без guaranteed delivery (mode=2/130) | **High** | v3r3:257,266 v4r1:266,393 | High |
| 07 | cancel + op=555 zero time-lock (sold_at=0) | **Medium** | sale:208-219,393 | High (code verified) |
| 08 | Seller silent fail (nft_owner no addr check) | **Medium** | sale:150-155,407 | Medium (rare precondition) |
| 09 | recv_external no auth (griefing) | **Low-Med** | v3r3:414, v4r1:620 | High |
| 10 | muldiv dust unaccounted | **Low** | sale:144-146 | High |
| 11 | V4R1: is_broken_state deploy lock | **Medium** | v4r1:192-201,415 | High (theoretical) |
| 12 | Нет raw_reserve — balance drain risk | **Medium** | sale vs offer:136 | High |
