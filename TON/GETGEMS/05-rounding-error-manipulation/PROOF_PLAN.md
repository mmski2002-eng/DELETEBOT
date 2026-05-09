# 🧪 План моделирования уязвимости 05 — Манипуляция распределением через ошибки округления

## Архитектура тестового стенда (Testnet)

### Кошельки участников

| Роль | Кошелёк | Назначение |
|------|---------|------------|
| Аудитор (Deployer) | `EQD...audit_A` | Развёртывание контрактов, запуск симуляций |
| Продавец | `EQD...seller_S` | Продаёт NFT |
| Покупатель | `EQD...buyer_B` | Покупает NFT |
| Маркетплейс | `EQD...fee_F` | Получает комиссию |
| Автор | `EQD...royalty_R` | Получает роялти |

### Контракты для развёртывания (Testnet)

| Контракт | Роль | Примечание |
|----------|------|------------|
| `nft-fixprice-sale-v4r1.fc` | Оригинальный контракт продажи | Без изменений |
| `normal-nft-item.fc` | Обычный NFT | Без изменений |
| `observer.fc` | Контракт-наблюдатель | Логирует все входящие суммы для анализа |

---

## Пошаговый план моделирования (Testnet)

### Фаза 1: Развёртывание с разными параметрами

Создаём НЕСКОЛЬКО контрактов продажи с разными комбинациями `price`, `fee_percent`, `royalty_percent` для поиска максимального остатка.

```
Контракт №1: price=1 TON, fee=33333, royalty=33333  (33.333% + 33.333%)
Контракт №2: price=1 TON, fee=33333, royalty=33334  (33.333% + 33.334%)
Контракт №3: price=1 TON, fee=25000, royalty=25000  (25% + 25%)
Контракт №4: price=1 TON, fee=10000, royalty=5000   (10% + 5%)
Контракт №5: price=1.5 TON, fee=33333, royalty=33333
Контракт №6: price=0.99 TON, fee=50000, royalty=50000 (50%+50% = 100%!)
Контракт №7: price=1 TON, fee=99999, royalty=1      (99.999% + 0.001%)
```

### Фаза 2: Запуск покупок и сбор остатков

Для каждого контракта:

```
1. Покупатель отправляет msg_value = price + 0.1 TON
2. Контракт выполняет buy_logic():
   fee_amount = muldiv(price, fee_percent, 100000)
   royalty_amount = muldiv(price, royalty_percent, 100000)
   user_amount = price - fee_amount - royalty_amount

3. После завершения проверяем баланс контракта:
   actual_balance = get_contract_balance(sale)
   expected_zero = 0
   remainder = actual_balance - expected_zero
   
4. Записываем remainder для каждого контракта
```

### Фаза 3: Анализ результатов

```python
# Псевдокод для анализа
results = []

for (price, fee, royalty) in test_cases:
    fee_amount = (price * fee) // 100000
    royalty_amount = (price * royalty) // 100000
    user_amount = price - fee_amount - royalty_amount
    total_distributed = fee_amount + royalty_amount + user_amount
    remainder = price - total_distributed
    
    results.append({
        "price": price,
        "fee_percent": fee,
        "royalty_percent": royalty,
        "fee_amount": fee_amount,
        "royalty_amount": royalty_amount,
        "user_amount": user_amount,
        "total": total_distributed,
        "remainder": remainder
    })

# Сортируем по величине остатка
results.sort(key=lambda r: r["remainder"], reverse=True)

for r in results[:5]:
    print(f"Remainder: {r['remainder']} nanoTON | Price: {r['price']} | Fee%: {r['fee_percent']} | Royalty%: {r['royalty_percent']}")
```

---

## Верификация результатов

| Метрика | Как измерить | Ожидаемый результат |
|---------|-------------|---------------------|
| `remainder` на контракте | `get_contract_balance()` после покупки | > 0 (остаток застрял) |
| Сумма всех выплат | `fee + royalty + user` | `< price` (недоплата) |
| Баланс продавца | `get_wallet_balance()` | `= user_amount` |
| Баланс маркетплейса | `get_wallet_balance()` | `= fee_amount` |
| Баланс автора | `get_wallet_balance()` | `= royalty_amount` |

### Инструменты для верификации

```bash
# 1. Развернуть серию контрактов с разными параметрами
for i in 1 2 3 4 5 6 7; do
    toncli deploy nft-fixprice-sale-v4r1 \
        --price ${PRICES[$i]} \
        --fee ${FEES[$i]} \
        --royalty ${ROYALTIES[$i]} \
        --name sale_$i
done

# 2. Выполнить покупки
for i in 1 2 3 4 5 6 7; do
    toncli send -a $((${PRICES[$i]} + 100000000)) -c sale_$i --op buy
done

# 3. Проверить остатки
for i in 1 2 3 4 5 6 7; do
    echo "Sale $i balance:"
    toncli get --contract sale_$i --method get_contract_balance
done
```

---

## Математическое доказательство

### Формула остатка

```
remainder = price - (muldiv(price, fee, 100000) + muldiv(price, royalty, 100000) + (price - muldiv(...) - muldiv(...)))
           = price - (price_fee + price_royalty + (price - price_fee - price_royalty))
           = price - price
           = 0  ← в идеале

НО: muldiv округляет ВНИЗ
    price_fee = floor(price * fee / 100000)
    price_royalty = floor(price * royalty / 100000)
    user = price - floor(...) - floor(...)

    remainder = price - (floor(price*fee/100000) + floor(price*royalty/100000) + user)
              = price - (price_fee + price_royalty + (price - price_fee - price_royalty))
              = price - price
              = 0  ← user «компенсирует» округление

НО! Есть случай, когда remainder > 0:
    Если floor(price*fee/100000) + floor(price*royalty/100000) < price
    то user = price - floor(...) - floor(...) — это точная сумма
    Но если floor(...) + floor(...) + user < price из-за того,
    что floor теряет дробную часть, а user не получает остаток...

На самом деле:
    user = price - price_fee - price_royalty (ТОЧНО)
    total = price_fee + price_royalty + user
          = price_fee + price_royalty + price - price_fee - price_royalty
          = price ✓

Остаток возникает только если есть ДРУГИЕ вычисления или пересылка избыточного msg_value.
```

### Уточнение уязвимости

Остаток возникает, когда `msg_value > price` и избыток не возвращается:

```
msg_value = price + excess
after distributions:
  fee = floor(price * fee_pct / 100000)
  royalty = floor(price * royalty_pct / 100000)
  user = price - fee - royalty
  // excess НЕ возвращается покупателю
  // excess остаётся в контракте
```

---

## Потенциально уязвимые контракты в Mainnet

### Признаки накопления остатков

- Контракты продажи с балансом > 0 после завершения (`is_complete = true`)
- Контракты, где `user_amount + fee_amount + royalty_amount < full_price`
- Контракты с нетипичными процентами (например, fee=33333)

### Поиск через API

```python
import requests

TONCENTER_API = "https://toncenter.com/api/v2"
SALE_CODE_HASH = "HASH_nft_fixprice_sale_v4r1"

resp = requests.get(f"{TONCENTER_API}/search", params={"code_hash": SALE_CODE_HASH})

for addr in resp.json()["result"]:
    # Проверить баланс контракта
    balance = requests.get(f"{TONCENTER_API}/getAddressBalance", params={
        "address": addr
    }).json()["result"]
    
    sale = requests.get(f"{TONCENTER_API}/runGetMethod", params={
        "address": addr,
        "method": "get_sale_data"
    }).json()["result"]
    
    if sale["is_complete"] and int(balance) > 100_000_000:  # > 0.1 TON остаток
        print(f"ОСТАТОК: {addr} | Balance: {balance} | Price was: {sale['full_price']}")
    
    if not sale["is_complete"]:
        # Проверить арифметику
        fee = (sale["full_price"] * sale["fee_percent"]) // 100000
        royalty = (sale["full_price"] * sale["royalty_percent"]) // 100000
        user = sale["full_price"] - fee - royalty
        total = fee + royalty + user
        remainder = sale["full_price"] - total
        
        if remainder > 0:
            print(f"НЕДОПЛАТА: {addr} | Remainder: {remainder} | Price: {sale['full_price']}")
```

---

## Ожидаемые результаты

### Если уязвимость подтверждена:
- На некоторых комбинациях параметров остаток > 0
- Особенно при ценах, не кратных 100000
- Накопительный эффект при большом объёме продаж

### Если опровергнута:
- `user = price - fee - royalty` всегда точно компенсирует округление
- Остаток = 0 для всех комбинаций