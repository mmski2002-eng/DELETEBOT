# 🟡 05 — Манипуляция распределением средств через ошибки округления (MEDIUM)

**Файл:** `nft-fixprice-sale-v4r1.fc:144-149`  
**CWE:** CWE-682 (Incorrect Calculation)

## Суть

Распределение средств в `buy_logic` использует целочисленное деление:

```
fee_amount = muldiv(price, fee_percent, 100000);
royalty_amount = muldiv(price, royalty_percent, 100000);
user_amount = price - fee_amount - royalty_amount;
```

При определённых значениях `price`, `fee_percent` и `royalty_percent` округление вниз может создать остаток `user > price - fee - royalty` (за счёт того, что `muldiv` округляет вниз), который остаётся на балансе контракта.

## Цепочка атаки

```
price = 1 TON (1 000 000 000 наноTON)
fee_percent = 33333 (33.333%)
royalty_percent = 33333 (33.333%)

fee_amount = 1e9 * 33333 / 100000 = 333 330 000
royalty_amount = 1e9 * 33333 / 100000 = 333 330 000
user_amount = 1e9 - 333330000 - 333330000 = 333 340 000 ← больше на 10 000!
Остаток: 10 000 наноTON → застревает в контракте.
```

## Ущерб

Накопительный — за множество транзакций собираются пылевые остатки в контракте. При миллионах продаж может достичь значительных сумм.