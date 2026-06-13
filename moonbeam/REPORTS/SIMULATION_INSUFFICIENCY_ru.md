# Доказательство: «Симуляция перед отправкой» не защищает от nonce rollback

**Сеть:** Moonbeam (chainId 1284)  
**Дата анализа:** 2026-05-14  
**Статус:** Уязвимость подтверждена на mainnet + fork PoC

---

## Тезис Moonbeam (предполагаемый митигейшн)

> «Релееры должны симулировать транзакции перед отправкой, чтобы избежать потерь газа от неудачных dispatches.»

---

## Почему симуляция недостаточна

### Аргумент 1: Race condition между симуляцией и включением

Moonbeam производит блок каждые ~8.75 секунд. Между симуляцией на блоке N-1 и включением tx в блок N состояние может измениться:

| Событие | Симуляция (блок N-1) | Реальный tx (блок N) |
|---------|---------------------|---------------------|
| Баланс токена signer | > 0 | = 0 (другая tx опустошила) |
| Approval signer → spender | существует | отозван |
| Листинг NFT (price, seller) | актуален | изменён |
| Nonce signer в CallPermit | = X (совпадает с подписью) | = X+1 (другая tx потребила) |

В любом из этих случаев:
- **Симуляция при N-1: SUCCESS** (состояние ещё не изменилось)
- **Реальный tx при N: FAIL** (состояние изменилось конкурирующей tx)
- **Результат: nonce rollback** → подпись v/r/s остаётся валидной и пригодной для повтора

Это фундаментальное свойство блокчейнов — релеер физически не может знать содержимое блока N в момент симуляции на N-1.

---

### Аргумент 2: Эмпирическое подтверждение — nonce rollback на mainnet

**Транзакция:** `0xfd164de94ae08b91e83389dedfc60ba652180dd085fe943847d179925fe6e973`  
**Блок:** 15616976  
**Релеер:** `0xceca2f8cf1983b4cf0c1ba51fd382c2bc37aba58`  
**Signer:** `0xafbe621c3bca78437aa0299a6fc3cf893087e7fc`  
**Цель:** `0xc4b466f63c0a31302bc8a688a7c90e1199bb6f84` (Proxy8)  
**Inner selector:** `0xd9a04da6`

**Проверка nonce rollback:**
```
Nonce signer до блока 15616976:   3
Nonce signer после блока 15616976: 3
Rollback подтверждён: ДА ✅
```

**Детали tx:**
```
Дедлайн (outer CallPermit): 2026-05-14T14:18:12Z  
Timestamp блока N: 2026-05-14T13:18:18Z (за 1 час до дедлайна)  
Статус receipt: 0 (FAILED)
Gas потрачено: 38,708 units
GLMR потрачено релеером: 0.001330 GLMR
```

Релеер заплатил за газ, dispatch провалился, **nonce signer не изменился**. Это означает:
- Подпись `(v=27, r=0xfb84..., s=0x7905...)` остаётся валидной
- Любой, кто получил эту подпись, может вызвать replay в будущем
- Релеер не защищён от этого даже симуляцией

---

### Аргумент 3: Fork PoC — MoonBeans acceptOffer

Прямое доказательство сценария «симуляция успех → реальный tx провал → replay»:

**Контракт:** MoonBeans V9 `0x683724817a7d526d6256Aec0D6f8ddF541b924de`  
**Функция:** `acceptOffer(address ca, uint256 tokenId, uint256 price, address from, bool escrowedBid)`

**Сценарий:**
1. Продавец подписывает `acceptOffer(NFT, tokenId, price=100 WGLMR, buyer)` через CallPermit
2. Релеер симулирует при блоке N-1: `dispatch` → SUCCESS (у покупателя есть allowance, price актуальна)
3. В блоке N покупатель отзывает allowance конкурирующей tx (front-run / собственная tx)
4. Реальный `dispatch` при блоке N: FAIL (WGLMR.transferFrom → allowance insufficient)
5. **Nonce rollback**: подпись продавца v/r/s остаётся при nonce=0
6. Покупатель (или attacker) позже снова выставляет allowance
7. **Replay succeed**: NFT переведён продавцу, 100 WGLMR снято с покупателя

**Результат fork PoC (Chopsticks):**
```
✅ STALE_ACCEPT_OFFER_REPLAY_SUCCEEDED
nonce before dispatch:  0
nonce after fail:       0  (rollback)
nonce after replay:     1  (consumed)
NFT owner after replay: buyer_address
WGLMR transferred:      100 (стейл цена, не текущая)
```

Все 8 assertions прошли. Replay выполнен от несвязанного аккаунта (не покупатель).

---

### Аргумент 4: Масштаб проблемы

Анализ последних 2000 транзакций к CallPermit (2026-05-14):

| Метрика | Значение |
|---------|---------|
| Всего dispatches | 2000 |
| Неудачных | 109 (5.45%) |
| Цель Staking precompile (0x800) | 87 txs |
| Цель 0xbe8d7c11... | 20 txs |
| Nonce rollback на каждом | ДА (по механике) |

При каждом failed dispatch:
- Релеер теряет газ безвозвратно
- Подпись signer остаётся реplayable
- Signer не получает уведомления

---

## Почему митигейшн «симулируй» не работает

1. **Race condition неустраним**: блокчейн недетерминирован из перспективы relayer. Состояние между N-1 и N может измениться любым участником сети.

2. **Nonce rollback амплифицирует потери**: при обычном failed tx — только gas loss. При nonce rollback в CallPermit — gas loss + signed data остаётся валидным бессрочно (до expiry deadline).

3. **Signer не контролирует replay**: после rollback signer не знает, что подпись «заморожена». Он думает, что tx не прошёл → всё. На самом деле подпись готова к replay при изменении состояния.

4. **Deadline не защищает от replay window**: если deadline = 1 час, то в течение 1 часа после failed dispatch любой, владеющий v/r/s, может выполнить replay без ведома signer.

---

## Вывод

«Simulate before sending» — необходимое, но **недостаточное** условие для защиты. Правильный митигейшн требует изменения на уровне протокола:

**Вариант A (рекомендуемый):** При failure inner call — NE откатывать nonce в CallPermit. Потребляемый nonce даже при реверте делает подпись одноразовой.

**Вариант B:** Добавить механизм invalidation подписи со стороны signer (аналог `permit` + `cancelPermit`).

**Вариант C:** Emit event при nonce rollback, чтобы signer мог отслеживать состояние своих подписей.

Текущее поведение (`dispatch` roll back nonce при failed inner call) нарушает ожидаемую семантику: пользователь считает, что подпись одноразовая по определению, но это не так при failure.
