# Bug Bounty Report — Pharos Network SPV

**Date:** 2026-04-28  
**Severity:** CRITICAL  
**Status:** Unpatched — mainnet launched today  
**PoC:** `pharos_skipempty_poc.py` (attached)  
**Live validation:** `pharos_live_validation.py` — confirmed on mainnet block ~5,849,370

---

## Резюме

В механизме SPV-верификации Pharos Network обнаружена уязвимость класса **hash commitment без кодирования позиции** (slot position ambiguity). Хеш Internal-ноды trie вычисляется путём конкатенации только непустых слотов без включения их индексов. Это позволяет атакующему переместить существующий слот в другую позицию, сохранив тот же хеш родительского узла.

**Доказанный вектор эксплуатации:** forgery non-existence proof — доказательство того, что существующий ключ отсутствует в дереве. Это напрямую позволяет двойное снятие средств с любого моста, использующего Pharos SPV для верификации состояния.

Pharos явно указывает в документации, что SPV предназначен для верификации в кросс-чейн мостах. Защитный механизм sibling sub-proofs, добавленный Pharos именно для предотвращения этого класса атак, **обходится** тем же SkipEmpty багом.

Уязвимость подтверждена на реальных данных Pharos Pacific Mainnet (Chain ID 1672, block ~5,849,370).

---

## Технические детали

### Затронутый компонент

`MerkleIndex::GetSPV` / Internal node hashing (SkipEmpty scheme)  
Pharos state trie — hexary nibble trie с SHA-256

### Уязвимый код (из документации Pharos)

```cpp
std::string hash_val = "";
for (int i = 0; i < kInternalSlotCount; i++) {  // i = 0..15
    if (node_impl->IsSlotCommittedEmpty(i)) {
        continue;   // ← позиция слота НЕ записывается
    }
    hash_val = hash_update(hash_val, node_impl->GetSlotHash[i]);
}
node_hash = sha256(hash_val);
```

**Проблема:** хеш = SHA256(конкатенация непустых значений), позиции слотов не кодируются.

### Доказательство коллизии

```
Нода A: slot[0]=H0, slot[1]=H_target, остальные=0x00…00
Нода B: slot[0]=H0, slot[3]=H_target, остальные=0x00…00

SkipEmpty(A) = SHA256(H0 || H_target)
SkipEmpty(B) = SHA256(H0 || H_target)
→ hash(A) == hash(B)  ✓ ПОДТВЕРЖДЕНО PoC
```

---

## Вектор атаки: Non-Existence Forgery

### Почему не existence forgery

Pharos SPV верификатор проверяет `key_hash` на уровне листа:

```
proof[-1][1] == key_hash  ← явная проверка ключа
```

Поэтому простая подстановка фейкового листа не работает — верификатор дойдёт до листа и обнаружит несовпадение ключа.

### Рабочий вектор: Non-Existence Forgery

**Цель:** доказать что ключ K **не существует**, хотя он существует.

**Реальное состояние:**
```
Internal нода: slot[0]=H_sibling, slot[1]=H_target
                                  ↑
                             K существует (nibble=1)
```

**Атака — перемещение слота:**
```
Фейковая нода: slot[0]=H_sibling, slot[3]=H_target
               slot[1] = 0x00…00  ← теперь пуст

SkipEmpty(реал) = SHA256(H_sibling || H_target)
SkipEmpty(фейк) = SHA256(H_sibling || H_target)
→ хеши совпадают → родитель принимает фейковую ноду
```

**Верификатор читает slot[1] = 0 → K не существует (ЛОЖНО)**

### Обход защиты sibling sub-proofs

Pharos знали об этом классе атак и добавили sibling sub-proofs. Документация явно описывает угрозу:

> *"only main chain, no sibling information allows attackers to fabricate empty slots while concealing real subtrees"*

**Почему защита не работает:**

Sibling sub-proof верифицирует что хеши в непустых слотах ведут к реальным поддеревьям. Для фейковой ноды:
- `slot[0]=H_sibling` → реальное поддерево → sub-proof **валиден** ✓
- `slot[3]=H_target` → реальное поддерево (просто перемещённое) → sub-proof **валиден** ✓
- Родительский хеш в цепочке sub-proof = `SHA256(H_sibling || H_target)` = совпадает с реальным ✓

Защита проверяет **значение** (хеш корректен), но не проверяет **позицию** (slot[3] vs slot[1]). Та же SkipEmpty уязвимость применима к родительскому узлу в цепочке верификации sibling.

### Сценарий двойного снятия с моста

```
1. Атакующий вносит 1000 USDC на Pharos (запись K появляется в state)
2. Мост на Chain B верифицирует депозит → выдаёт 1000 USDC ✓
3. Атакующий снова предъявляет тот же депозит на Chain B:
   - Мост проверяет: "был ли уже использован депозит K?"
   - Pharos state: withdrawal record для K = EXISTS
   - Атакующий форжит non-existence proof для withdrawal record
   - Мост видит: "снятия не было" → выдаёт ещё 1000 USDC ✗
4. Итог: +1000 USDC из воздуха
```

Применимо к любому мосту, хранящему записи об использованных депозитах в Pharos state trie.

---

## Вторая уязвимость: опциональная проверка offset

Из официальной документации (дословно):

> *"check: proof[-2][slot_idx[-1]] == tmp_hash*  
> *# Additionally, the correspondence between next_begin_offset and slot_idx **can be** checked"*

Слово "can be" означает необязательность. Независимый второй вектор атаки для реализаций, пропускающих эту проверку.

---

## Live Validation на Mainnet

**RPC:** `https://rpc.pharos.xyz` — Pharos Pacific Mainnet, Chain ID 1672  
**Дата:** 2026-04-28

```
eth_getProof → 0x4100000000000000000000000000000000000000

Нода #3: 515 байт, Internal
  Непустые слоты: [0, 2, 3, 5, 6, 8, 10, 11, 14, 15]
  Пустые слоты:   [1, 4, 7, 9, 12, 13]

Манипуляция: slot[0] → slot[1] (пустой в оригинале)

SkipEmpty hash оригинал: 511084ab0c3c30660788debb65e54d30…
SkipEmpty hash фейк:     511084ab0c3c30660788debb65e54d30…
Хеши совпадают: TRUE ✅
slot[1] оригинал: 0x0000…0000 (ПУСТОЙ)
slot[1] фейк:     0x061e2cdf5f20d439… (НЕПУСТОЙ)
```

---

## Текущее состояние экосистемы

| Адрес | Тип | Баланс | SPV-уязвим |
|-------|-----|--------|------------|
| `0x4100…0000` | Системный контракт / PROS | **115,402,800 PROS** | нет |
| `0xe5bfde…` | TGE claim | **1,157,195 PROS** | нет |
| `0x3c2269…` | LayerZero v1 Endpoint | **0** (код есть) | потенциально |
| Fiamma Bridge | не задеплоен на mainnet | **0** | да (при запуске) |

Mainnet запущен сегодня. Основной bridge.pharosnetwork.xyz использует Chainlink CCIP (не SPV). Fiamma Bridge использует ZKP. **Прямой текущей TVL под угрозой нет.**

Однако: SPV задокументирован и рекламируется для кросс-чейн верификации. Любой протокол, построенный по документации Pharos, будет уязвим. Уязвимость должна быть исправлена до появления таких протоколов.

---

## PoC — результаты

```bash
python3 pharos_skipempty_poc.py
```

| Part | Тест | Результат |
|------|------|-----------|
| 1 | Hash collision (позиции разные, хеш одинаковый) | ✅ PASS |
| 2 | Raw данные расходятся при одинаковом хеше | ✅ PASS |
| 3 | Верификатор принимает манипулированный proof | ✅ PASS |
| 4 | Optional offset check — второй вектор | ✅ INFO |
| **5** | **Non-existence forgery + sibling bypass** | ✅ **PASS** |

---

## Рекомендуемое исправление

**Вариант 1 (минимальный):** включить индекс слота в хеш:

```cpp
std::string hash_val = "";
for (int i = 0; i < kInternalSlotCount; i++) {
    if (node_impl->IsSlotCommittedEmpty(i)) {
        continue;
    }
    uint8_t idx = static_cast<uint8_t>(i);
    hash_val += std::string(reinterpret_cast<char*>(&idx), 1);  // ← индекс
    hash_val += node_impl->GetSlotHash[i];
}
node_hash = sha256(hash_val);
```

**Вариант 2 (надёжный):** хешировать полный 515-байтный узел целиком:

```cpp
node_hash = sha256(full_515_byte_raw_node);
```

Ethereum MPT использует этот подход (RLP полного узла). Устраняет проблему позиционно и не требует изменений в логике обхода.

**Для второй уязвимости:** сделать проверку `nextBeginOffset` **обязательной**.

---

## Оценка серьёзности

| Критерий | Оценка |
|----------|--------|
| Тип | Нарушение soundness криптографического доказательства |
| Компонент | SPV — задокументированное ядро кросс-чейн верификации |
| Exploitability | Non-existence forgery доказана в PoC; sibling defense обходится |
| Текущий TVL под угрозой | ~$0 (мосты не накопили средства) |
| Потенциальный ущерб | Все активы в мостах, использующих Pharos SPV |
| **Итого** | **Critical** |

---

## Временная шкала

| Дата | Событие |
|------|---------|
| 2026-04-28 | Pharos mainnet + TGE |
| 2026-04-28 | Уязвимость обнаружена, PoC создан (Parts 1-4) |
| 2026-04-28 | Live validation на mainnet подтверждена |
| 2026-04-28 | Non-existence forgery + sibling bypass доказан (Part 5) |
| 2026-04-28 | **Отправка отчёта** ← сейчас |
| TBD | Патч от команды |
| TBD + 90 дней | Публичное раскрытие (если нет ответа) |

---

## Куда отправлять

1. DM [@wishlonger](https://x.com/wishlonger) (CEO, бэкграунд в security)
2. DM [@pharos_network](https://x.com/pharos_network)
3. Email: `security@pharosnetwork.xyz`
4. Immunefi: мониторить `immunefi.com/bug-bounty/pharos`

---

## Ссылки

- Pharos SPV Proof Theory: https://docs.pharos.xyz/api-and-sdk/eth-getproof/spv-proof-theory
- Pharos eth_getProof API: https://docs.pharos.xyz/api-and-sdk/eth-getproof.md
- LayerZero v1 на Pharos: `0x3c2269811836af69497E5F486A85D7316753cf62`
- Аналог: Binance Bridge IAVL proof bypass ($570M, Oct 2022)
- Аналог: Nomad Bridge uninitialized root ($190M, Aug 2022)
