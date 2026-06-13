# Анализ активных релееров CallPermit — Moonbeam

**Дата:** 2026-05-14  
**Выборка:** последние 500 транзакций к `0x000000000000000000000000000000000000080a`  
**Период:** только 2026-05-14 (все 500 tx за один день)  

---

## Сводка

Найдено **3 уникальных диспетчера**. Все три активны сегодня. Рынок крайне концентрирован: #1 отправил 92% всех транзакций.

| # | Адрес | Txs | Success | Баланс GLMR | dApp |
|---|-------|-----|---------|------------|------|
| 1 | `0x7e4cd38d266902444dc9c8f7c0aa716a32497d0b` | 459 | 100% | 181.74 | Diode Network |
| 2 | `0xceca2f8cf1983b4cf0c1ba51fd382c2bc37aba58` | 37 | 97% (1 fail) | 131.61 | Diode Network |
| 3 | `0x937c492a77ae90de971986d003ffbc5f8bb2232c` | 4 | 100% | 219.27 | Diode Network |

---

## Профиль #1: `0x7e4cd38d266902444dc9c8f7c0aa716a32497d0b`

**Тип:** EOA  
**Баланс:** 181.74 GLMR  
**Активность:** 459 tx / 459 успешных / 0 failed  
**Gas потрачено:** 0.7306 GLMR  
**Последняя tx:** 2026-05-14  

**Цели (топ):**
| Контракт | Селектор | Кол-во |
|----------|----------|--------|
| `0x43e578407d81...` | `0x130dbfbb` (SubmitTransaction Diode) | 398 |
| `0x2be592374e49...` | `0x7693a3e9` (неизвестен) | 59 |
| `0xce99b811382c...` | `0xf57b330a` | 1 |
| `0xb5b812f8101b...` | `0xf57b330a` | 1 |

**Нonce rollback:** нет failed tx → нет случаев rollback.  
**Вывод:** Основной релеер Diode Network, чистый трек-рекорд. Не имеет failed dispatches — rollback не применим.

---

## Профиль #2: `0xceca2f8cf1983b4cf0c1ba51fd382c2bc37aba58`

**Тип:** EOA  
**Баланс:** 131.61 GLMR  
**Активность:** 37 tx / 36 успешных / **1 failed**  
**Gas потрачено:** 0.0969 GLMR  
**Последняя tx:** 2026-05-14  

**Цели (топ):**
| Контракт | Селектор | Кол-во |
|----------|----------|--------|
| `0x8fb1bc09a006...` | `0x130dbfbb` (SubmitTransaction Diode) | 28 |
| `0xc4b466f63c0a...` (`Proxy8`) | `0xd9a04da6` (неизвестен) | 3 |
| `0xce99b811382c...` | `0x130dbfbb` | 2 |
| `0x434116a99619...` (DIODE token) | `0x095ea7b3` (`approve`) | 1 |

**Ключевая находка — failed tx:**
```
TX:    0xfd164de94ae08b91e83389dedfc60ba652180dd085fe943847d179925fe6e973
Block: 15616976
Signer: 0xafbe621c3bca78437aa0299a6fc3cf893087e7fc
Target: 0xc4b466f63c0a31302bc8a688a7c90e1199bb6f84 (Proxy8)
Inner: 0xd9a04da6 (неизвестная функция)
Deadline: 2026-05-14T14:18:12Z (истёк)
```

**Nonce rollback проверен:**
- Nonce до блока 15616975: **1**
- Nonce после блока 15616976: **1** ← rollback подтверждён
- Nonce текущий (latest): **3** ← consumed in later txs
- **Replay window: ЗАКРЫТО** (deadline истёк + nonce потреблён)

**DIODE approve tx (2 блока раньше):**
```
TX:    0xd75213e47530e0163944b15c79e5aa5f2a04fea0adca71a2d1044cb4bbdbe72e  
Block: 15616974 (SUCCESS)
Signer: 0xafbe621c3bca78437aa0299a6fc3cf893087e7fc
Target: 0x434116a99619f2b465a137199c38c1aab0353913 (DIODE token)
Inner: approve(address,uint256)
Status: УСПЕШНО — nonce потреблён (0→1)
```

**Вывод:** Механика rollback подтверждена на failed tx. Финансовый интерес — dispatch DIODE.approve был успешным, window нет. Цель `Proxy8 / 0xd9a04da6` требует декомпиляции для понимания функции.

---

## Профиль #3: `0x937c492a77ae90de971986d003ffbc5f8bb2232c`

**Тип:** EOA  
**Баланс:** 219.27 GLMR (наибольший)  
**Активность:** 4 tx / 4 успешных / 0 failed  
**Gas потрачено:** 0.0346 GLMR  
**Последняя tx:** 2026-05-14  

**Цели:**
| Контракт | Селектор | Кол-во |
|----------|----------|--------|
| `0xd3220a793f8a...` | `0x130dbfbb` (Diode) | 1 |
| `0x8a093e3a83f6...` | `0x2f8866a0` | 1 |
| `0x8a093e3a83f6...` | `0x3e49fb7e` | 1 |
| `0xaf7de307eb22...` | `0x38b5bc9c` | 1 |

**Nonce rollback:** нет failed tx.  
**Вывод:** Низкая активность, скорее всего тестовый или редко используемый релеер Diode. Наибольший баланс из трёх.

---

## Оценка для PoC

| Критерий | #1 | #2 | #3 |
|----------|----|----|-----|
| Активность (сегодня) | ✅ HIGH | ✅ HIGH | ✅ LOW |
| Баланс | 181 GLMR | 131 GLMR | 219 GLMR |
| Failed dispatch (rollback) | ❌ | ✅ **ПОДТВЕРЖДЁН** | ❌ |
| Live replay window | ❌ | ❌ | ❌ |
| Финансовый innerCall | ❌ | ✅ DIODE approve (успешный) | ❌ |

**Лучший для PoC-демонстрации rollback механики:** `#2 (0xceca2f8c...)`  
— единственный с confirmed nonce rollback + финансовым dispatch (DIODE approve)  
— балans 131 GLMR подтверждает активный статус релеера  
— live window отсутствует → safe для демонстрации (не mainnet exploit)

---

## Вывод

Все три диспетчера принадлежат экосистеме **Diode Network** (decentralized filesystem/VPN). Финансово значимых failed dispatches с открытым replay window на момент анализа не обнаружено. Vulnerability подтверждена механически: failed tx relayer #2 зафиксировал nonce rollback (before=after=1), что доказывает что подпись v/r/s осталась валидной после failed dispatch.

Для получения bounty-grade finding с живым window необходимо перейти к историческим блокам (2023-2024) или расширить скан на другие протоколы (MoonBeans acceptOffer — уже доказано на fork).
