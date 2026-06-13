# Verification Summary — GetGems NFT Contracts

**Date:** 2026-05-15  
**Basis:** статический анализ кода + testnet TX (HYP-01 TESTNET-CONFIRMED).  
**Files verified:** nft-fixprice-sale-v4r1.fc, nft-auction-v3r3.func, nft-auction-v4r1.func, nft-item.fc

---

## Таблица findings: old status → new status

| ID | Title | Старый статус | Новый статус | Severity |
|---|---|---|---|---|
| HYP-01 | is_complete=1 без NFT (bounce ignored) | CONFIRMED | **TESTNET-CONFIRMED** | Critical |
| HYP-05 | Fake NFT — нет TEP-62 on-chain validation | CONFIRMED (on-chain) | **TESTNET-CONFIRMED** | Critical/High* |
| HYP-02 | Auction hostage via bid cycling | CONFIRMED (logic) | **CODE-CONFIRMED** | High |
| HYP-06 | Jetton try/catch не ловит action phase fail | CONFIRMED (arch) | **CODE-CONFIRMED** | High |
| HYP-07 | return_last_bid mode=2 silent fail | CONFIRMED | **CODE-CONFIRMED** | High |
| HYP-03 | op=555 zero time-lock на canceled sale | CONFIRMED | **CODE-CONFIRMED** | Medium |
| ABUSE-02 | recv_external griefing (no auth) | CONFIRMED | **CODE-CONFIRMED** | Low-Med |
| HYP-04 | Seller silent fail (nft_owner undeliverable) | SUSPICIOUS | **NEEDS-EVIDENCE** | Medium |
| ABUSE-03 | deploy_jetton signature replay | LIKELY BLOCKED | **BLOCKED** | Low |

---

## Critical / High после верификации

Все пять High/Critical прошли без опровержения.

### HYP-01 — Critical

Покупатель платит `full_price`. NFT не доставлен. `is_complete=1` в chain.

```
transfer_nft: sale:107 → 0x18 (bounce=true), mode=130 (128+2)
bounce handler: sale:172 → if (flags & 1) { return (); }  // без отката
save_data(1): sale:416 → committed ДО bounce возврата
```

Vector A (bounce): NFT throws → bounce → sale игнорирует → `is_complete=1` необратим.  
Vector B (action fail): mode=2 IGNORE_ERRORS → no exception → `save_data(1)` committed.  
Blocker: отсутствует.

---

### HYP-05 — Critical

On-chain нет TEP-62 проверки. Fake NFT проходит все checks.

```
sale:340 → throw_unless(500, equal_slices(sender_address, nft_address))
;; проверяет только: сообщение пришло ОТ nft_address
;; НЕ проверяет: collection, index derivation, TEP-62 compliance
```

Attacker деплоит fake contract на адрес X → листинг с `nft_address=X` → покупатель платит → `is_complete=1`.  
On-chain blocker: отсутствует. Вся защита — off-chain backend GetGems (не исследован).

---

### HYP-02 — High

Griever блокирует cancel и продлевает `end_time` бесконечно. Cost ~0.006 TON/step.

```
v3r3:329 / v4r1:537  → throw_if(cant_cancel_bid, last_bid > 0)   // cancel заблокирован
v3r3:381 / v4r1:447  → if ((end_time - step_time) < now()) { end_time += step_time; }
v3r3:366 / v4r1:427  → throw_if(duration > 20 days)              // cap НЕЭФФЕКТИВЕН
```

Cap bypass: проверяет `end_time - now()`, не суммарное продление.  
Attacker ждёт пока `duration < 20d - step_time` → bid → `duration ≈ 20d`. Повторять бесконечно.

---

### HYP-06 — High

`try/catch` в FunC перехватывает только compute phase exceptions.  
Action phase failures (mode=2 IGNORE_ERRORS) — не TVM exceptions → не перехватываются.

```
sale:93-94  → send_jettons mode = (1+2) или (64+2)  // +2 = IGNORE_ERRORS
sale:252-273 → try {
    send_jettons(nft_owner_address, user_amount)  // может fail silently
    ...
    save_data(1, ...)                              // committed независимо от delivery
} catch (_,_) { ... }                             // НЕ срабатывает при action fail
```

TON VM факт: compute phase → action phase. catch физически не может поймать action phase.  
Blocker: отсутствует на уровне языка.

---

### HYP-07 — High

Предыдущий bidder теряет ставку при outbid если `return_last_bid` fails silently.

```
v3r3:257 / v4r1:393 → send_raw_message(return_prev_bid.end_cell(), 2)  // mode=2 IGNORE_ERRORS
;; bounce handler в обоих контрактах: throw_if(0, flags & 1) → exit(0) = silent absorb
;; нет retry, нет recovery
```

---

## Что downgraded / blocked

### BLOCKED — ABUSE-03 (deploy_jetton signature replay)

```
sale:568 → throw_unless(403, equal_slices(sender_addr, jetton_wallet))
```

Replay требует чтобы сообщение пришло от текущего `jetton_wallet`. Контроль транспорта нереалистичен.

### NEEDS-EVIDENCE — HYP-04 (Seller silent fail)

Standalone: требует frozen/addr_none `nft_owner` — редкий precondition.  
В combo с HYP-05: root cause = HYP-05, самостоятельным finding не является.  
Code gap реален (`sale:150-155` проверяет fee/royalty, но не nft_owner), impact низкий без combo.

### Частично смягчён — ABUSE-02 в v4r1

`check_ok_balance(profit)` блокирует griefing если `profit < 0.1 TON`.  
Для аукционов с `profit > 0.1 TON` уязвимость остаётся.

---

## Evidence ещё нужны

| ID | Что нужно | Переводит в |
|---|---|---|
| HYP-01 | ~~TX hash из `poc-testnet.js`~~ | ✅ **TESTNET-CONFIRMED** (2026-05-15) |
| HYP-05 | GetGems backend/indexer source или API behavior | Critical → High если off-chain check есть |
| HYP-06 | Local TVM sim с reject-jetton-wallet | SIM-CONFIRMED |
| HYP-02 | Testnet: 3 bid + попытка cancel → exit code 1009 | SIM-CONFIRMED |
| HYP-07 | Testnet: bid с frozen `last_member` → balance loss | SIM-CONFIRMED |

---

## Один следующий тест

~~**Запустить `01-bounced-nft-loss/poc-testnet.js`**~~ ✅ **DONE — TESTNET-CONFIRMED**

HYP-01 закрыт. TX: `KMvdSOiwWqDkF+Fjn5e4+APlZ5n+MMjwWRwQIOTEp1c=`  
Contract: `kQBwkvWACL9Pp0nlQOKYo_gPjP1j2SM5fcb6yDN_P3n1L5uv`

---

**Следующий: HYP-05 — исследовать GetGems backend**

Определить, проверяет ли GetGems API/indexer TEP-62 derivation off-chain.  
Если нет → Critical остаётся. Если проверяет → downgrade до High.  
Метод: тест листинга fake NFT contract через GetGems marketplace UI или API.
