# DIODE Balance Risk Analysis — CallPermit Nonce Rollback

**Дата:** 2026-05-14T09:57:54.798Z
**Цель:** Найти failed CallPermit dispatch где target multisig имел DIODE баланс в момент failed tx

---

## Executive Summary

| Метрика | Значение |
|---------|---------|
| Проверено кандидатов | 22 |
| Нашли DIODE > 0 в multisig AT BLOCK | 0 |
| Auth check PASS (owner/member) | 22 |
| Nonce rollback confirmed | 19 |
| 🔴 КРИТИЧЕСКИЕ (все три) | 0 |
| Диапазон сканирования | 15440000-15538000, 15350000-15440000 |

## ❌ Случаев с DIODE > 0 в multisig на момент failed tx — НЕ НАЙДЕНО

Все known Diode Drive multisigs имели **0 DIODE** в момент каждого failed dispatch.

**Вероятная причина:** Diode Drive контракты используются для децентрализованного хранения (Drive/filesystem),
а не для хранения DIODE токенов. DIODE токены хранятся у individual users или в staking contract.

## Все проверенные кандидаты

| TX | Block | Multisig | DIODE@block | Rollback | Auth | Inner |
|----|-------|----------|-------------|---------|------|-------|
| [0xcd422a3a...](https://moonbeam.moonscan.io/tx/0xcd422a3a9a3525b965f541d6b0537e846e37b38f520099077fe9b1ad792fbebd) | 15441926 | `0x553FD260...` | 0 | ✅ | ✅ | nested |
| [0xd5e49fc3...](https://moonbeam.moonscan.io/tx/0xd5e49fc3e721a70059348b1186f3d7cfa14f52e7ac6af1fefb12eece4e6f862f) | 15410765 | `0x597B2084...` | 0 | ✅ | ✅ | nested |
| [0x93153619...](https://moonbeam.moonscan.io/tx/0x93153619331c6ae3154e1792254d3d9c73a1baaeeb11dbeea8cff37603aba985) | 15556164 | `0xE664535E...` | 0 | ✅ | ✅ | nested |
| [0xa14c6108...](https://moonbeam.moonscan.io/tx/0xa14c61084385e78310c6cdaa90267ab51d53400cabccaf122a4521c4f5795c0a) | 15543893 | `0x20b04B32...` | 0 | ✅ | ✅ | nested |
| [0x65af37a7...](https://moonbeam.moonscan.io/tx/0x65af37a7a37a10415d6d67a5a7754f551dd37d50504ab3e6aaa6488692535a06) | 15539580 | `0x45573253...` | 0 | ❌ | ✅ | nested |
| [0x6b05f1a0...](https://moonbeam.moonscan.io/tx/0x6b05f1a080adb350fcbb2239e6c251589f5b096054aa11e268dd36f6b89284a4) | 15539579 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0x3a1297f7...](https://moonbeam.moonscan.io/tx/0x3a1297f779c75a5f32574b46ea241c89deba2f9f5ed8e529d073a14db5e933f8) | 15539579 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0x873820e2...](https://moonbeam.moonscan.io/tx/0x873820e25762061612668b53ce7b558a1833c703be8f4ff4482dd4e8bc1fd355) | 15539579 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0x59361cf3...](https://moonbeam.moonscan.io/tx/0x59361cf34375cf8c4b5ed841c612155515ccccca3cc26dde2301ec120804b7a8) | 15539579 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0x5a43c68d...](https://moonbeam.moonscan.io/tx/0x5a43c68de79efc1d95b1839a6246218c2f2c5b67f972ec4ffa288dea904d8f05) | 15539579 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0x14b92500...](https://moonbeam.moonscan.io/tx/0x14b9250099542a6d808af90927780074303fbe81cbfaf2b019bb7f4a0c32a5f8) | 15539578 | `0x45573253...` | 0 | ❌ | ✅ | nested |
| [0x9d7ecb64...](https://moonbeam.moonscan.io/tx/0x9d7ecb64ef5c3af66c796b99ea1123c31cf24d9e0a6b6e0a594a29cba5925627) | 15539575 | `0x45573253...` | 0 | ❌ | ✅ | nested |
| [0xd1d73aa0...](https://moonbeam.moonscan.io/tx/0xd1d73aa0d3b1c316d10d3c739896191711bf4f14508e8f3bc39b03c78ccbc020) | 15539574 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0xd6eb1268...](https://moonbeam.moonscan.io/tx/0xd6eb12685094c83c37b600a767310bee51f3d7a55c294d58c19b42c05f531f6e) | 15539574 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0x369bd98a...](https://moonbeam.moonscan.io/tx/0x369bd98acf93bb2253fb5ffeffe400a12a6e9a1b63d72987a8eb06d4513a35d4) | 15539574 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0x5eaa494c...](https://moonbeam.moonscan.io/tx/0x5eaa494c3fe9ea163f75cb74aa30048536d4fb6e3c9e835e84881fa649f74f26) | 15539574 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0x6463c796...](https://moonbeam.moonscan.io/tx/0x6463c79635ee36f3f9e32494bc0846e72b95b13047e019d23b0b27b393241551) | 15539219 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0xc0b87682...](https://moonbeam.moonscan.io/tx/0xc0b87682cd940e341479e006b2abf43f744aa6f33addeb6e5c59c36f1c059eae) | 15539219 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0x479b6e4e...](https://moonbeam.moonscan.io/tx/0x479b6e4ece650e6ee004008399b6dd4034608d3528f59948f971250fc578cd28) | 15539219 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0x4878e7c5...](https://moonbeam.moonscan.io/tx/0x4878e7c53b3c282c9b3570bdf7e8c2089bb80d50404dfa831c3326a877a498d6) | 15539219 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0x7cea0b0e...](https://moonbeam.moonscan.io/tx/0x7cea0b0e762493841674413ebf30f21a5225b8e10b8932d941021fd90218549a) | 15539219 | `0x45573253...` | 0 | ✅ | ✅ | nested |
| [0x734bff54...](https://moonbeam.moonscan.io/tx/0x734bff5442664553f2a829996ed018b900fa3651f44c31138e8298db043d810d) | 15539219 | `0x45573253...` | 0 | ✅ | ✅ | nested |

---

## Лучшие находки без DIODE баланса (но с подтверждённым rollback + auth)

Nonce rollback подтверждён + signer авторизован на multisig, но DIODE баланс = 0:

### 🟠 Rollback + Auth (нет баланса): `0xcd422a3a9a3525b965f541d6b0537e846e37b38f520099077fe9b1ad792fbebd`

**Block:** 15441926 (2026-04-30T21:07:18.000Z)
**Signer:** `0xb5A36021e107037F8b844766C6a7dB70e39d3F46`
**Target multisig:** `0x553FD260607B6D82474Aa06685eF6c2366647D7A`
**DIODE balance at block:** 0.0000 DIODE 
**Nonce rollback:** ✅ CONFIRMED (2 → 2)
**Auth (isOwner/isMember):** ✅ OWNER
**Deadline:** 1777586833 (2026-04-30T22:07:13.000Z)
**Replay window:** 3595 seconds
**Inner call:** 0x130dbfbb
**Nested financial:** none



---

### 🟠 Rollback + Auth (нет баланса): `0xd5e49fc3e721a70059348b1186f3d7cfa14f52e7ac6af1fefb12eece4e6f862f`

**Block:** 15410765 (2026-04-28T13:12:24.000Z)
**Signer:** `0x6A210A61dC8112C1344858d82B1dbDE850b957a1`
**Target multisig:** `0x597B2084f1a74df59f3431AbE38dBeEc42dFd1c2`
**DIODE balance at block:** 0.0000 DIODE 
**Nonce rollback:** ✅ CONFIRMED (7 → 7)
**Auth (isOwner/isMember):** ✅ OWNER
**Deadline:** 1777385542 (2026-04-28T14:12:22.000Z)
**Replay window:** 3598 seconds
**Inner call:** 0x130dbfbb
**Nested financial:** none



---

### 🟠 Rollback + Auth (нет баланса): `0x93153619331c6ae3154e1792254d3d9c73a1baaeeb11dbeea8cff37603aba985`

**Block:** 15556164 (2026-05-09T17:18:00.000Z)
**Signer:** `0xb73B78353Fb704FC6fd0c9a3350Be4942F3846F8`
**Target multisig:** `0xE664535Edfe130C9E7250DA50fddfbe2413f12Fc`
**DIODE balance at block:** 0.0000 DIODE 
**Nonce rollback:** ✅ CONFIRMED (9 → 9)
**Auth (isOwner/isMember):** ✅ OWNER
**Deadline:** 1778350673 (2026-05-09T18:17:53.000Z)
**Replay window:** 3593 seconds
**Inner call:** 0x130dbfbb
**Nested financial:** none



---

### 🟠 Rollback + Auth (нет баланса): `0xa14c61084385e78310c6cdaa90267ab51d53400cabccaf122a4521c4f5795c0a`

**Block:** 15543893 (2026-05-08T17:42:30.000Z)
**Signer:** `0x427F87957267c1105Bc6F417a13a4b266C6b8A8E`
**Target multisig:** `0x20b04B32F34a1c9F9155429b577154C01Cb7178B`
**DIODE balance at block:** 0.0000 DIODE 
**Nonce rollback:** ✅ CONFIRMED (16 → 16)
**Auth (isOwner/isMember):** ✅ MEMBER
**Deadline:** 1778265745 (2026-05-08T18:42:25.000Z)
**Replay window:** 3595 seconds
**Inner call:** 0x130dbfbb
**Nested financial:** none



---

### 🟠 Rollback + Auth (нет баланса): `0x6b05f1a080adb350fcbb2239e6c251589f5b096054aa11e268dd36f6b89284a4`

**Block:** 15539579 (2026-05-08T09:25:48.000Z)
**Signer:** `0x542FB9a71A47d99B49673a32535396D513e5ae32`
**Target multisig:** `0x4557325332496425DBa39Fe04288052F1F1DA207`
**DIODE balance at block:** 0.0000 DIODE 
**Nonce rollback:** ✅ CONFIRMED (160 → 160)
**Auth (isOwner/isMember):** ✅ OWNER
**Deadline:** 1778235941 (2026-05-08T10:25:41.000Z)
**Replay window:** 3593 seconds
**Inner call:** 0x130dbfbb
**Nested financial:** none



---


---

## Методология

1. Загружены existing candidates из scan files
2. Дополнительный scan блоков: 15440000-15538000, 15350000-15440000
3. Для каждого SubmitTransaction кандидата: eth_call balanceOf(multisig) AT BLOCK
4. Nonce rollback: eth_call nonces(signer) при block-1 vs block
5. Auth: eth_call Members() + owner() на multisig
6. Приоритет: DIODE > 0 + rollback confirmed + auth pass = CRITICAL
