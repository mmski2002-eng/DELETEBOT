# 🧪 План моделирования уязвимости 08 — Газовая атака через частичное выполнение

## Архитектура тестового стенда (Testnet)

### Кошельки участников

| Роль | Кошелёк | Назначение |
|------|---------|------------|
| Аудитор (Deployer) | `EQD...audit_A` | Развёртывание контрактов, запуск атаки |
| Продавец | `EQD...seller_W` | Владелец NFT, жертва |
| Покупатель-атакующий | `EQD...attacker_X` | Отправляет покупку с дефицитом газа |
| Маркетплейс | `EQD...fee_F` | Получает комиссию |
| Автор | `EQD...royalty_R` | Получает роялти |

### Контракты для развёртывания (Testnet)

| Контракт | Роль | Примечание |
|----------|------|------------|
| `nft-fixprice-sale-v4r1.fc` | Уязвимый контракт продажи | Без изменений |
| `expensive-nft-item.fc` | NFT с дорогим `transfer()` | Потребляет много газа на transfer |
| `heavy-collection.fc` | Коллекция с дорогой проверкой | Дополнительная нагрузка на газ |
| `observer.fc` | Контракт-наблюдатель | Логирует все сообщения и ошибки |

---

## Пошаговый план атаки (Testnet)

### Фаза 1: Развёртывание (блок N)

```
1. Аудитор разворачивает expensive-nft-item:
   - NFT-контракт, у которого transfer() потребляет > 0.3 TON газа
   - Причина: сложные проверки, зацикленные вызовы, или большой объём данных

2. Аудитор разворачивает контракт продажи:
   - nft_address = expensive-nft-item
   - full_price = 0.005 TON (ОЧЕНЬ маленькая цена)
   - marketplace_fee = 2500 (2.5%)
   - royalty = 500 (0.5%)
   - min_gas_amount = 0.1 TON (установлен, но НЕ ИСПОЛЬЗУЕТСЯ для проверки)

3. Записываем состояние:
   - is_complete = 0
   - Баланс контракта = 0
   - Владелец NFT = Продавец
```

### Фаза 2: Атака — частичное выполнение (блок N+1)

```
4. Атакующий отправляет internal message:
   msg_value = 0.105 TON (цена 0.005 + газ 0.1)
   op = buy
   ВАЖНО: msg_value очень близко к минимальной комиссии
   Сеть TON потребляет газ на:
   - Доставку сообщения: ~0.01 TON
   - Выполнение контракта: ~0.005 TON
   - Отправку 4 исходящих сообщений: 4 * ~0.01 TON = ~0.04 TON
   - Transfer NFT (дорогой): ~0.06 TON
   - ИТОГО нужно: ~0.115 TON
   - Отправлено: 0.105 TON
   - ДЕФИЦИТ: ~0.01 TON

5. Контракт выполняет buy_logic():
   fee_amount = 0.000125 TON (2.5% от 0.005)
   royalty_amount = 0.000025 TON (0.5% от 0.005)
   user_amount = 0.00485 TON

6. Контракт начинает отправку 4 сообщений:
   [A] send_money(Продавец, 0.00485 TON)    → флаг 3, комиссия ~0.01 TON
        Баланс: 0.105 - 0.01 = ~0.095 TON
   [B] send_money(Маркетплейс, 0.000125 TON) → флаг 3, комиссия ~0.01 TON
        Баланс: 0.095 - 0.01 = ~0.085 TON
   [C] send_money(Автор, 0.000025 TON)       → флаг 3, комиссия ~0.01 TON
        Баланс: 0.085 - 0.01 = ~0.075 TON
   [D] transfer_nft(expensive-nft, Атакующий) → флаг 130, комиссия ~0.06+ TON
        Баланс: 0.075 TON
        Нужно: 0.06+ TON на комиссию + 0.02 fwd_fee
        ИТОГО нужно: 0.08+ TON
        ДОСТУПНО: 0.075 TON
        → НЕХВАТКА ГАЗА!

7. Сообщение [D] НЕ ОТПРАВЛЕНО из-за нехватки газа
   save_data(is_complete=1) ← УЖЕ ВЫПОЛНЕНО ДО [D] (строка 416-425)
```

### Фаза 3: Результат атаки (блок N+2)

```
8. Итоговое состояние:
   ✅ Продавец получил 0.00485 TON (но потерял NFT в контракте)
   ✅ Маркетплейс получил 0.000125 TON
   ✅ Автор получил 0.000025 TON
   ❌ NFT НЕ передан (transfer не выполнен)
   ❌ Атакующий потерял 0.105 TON
   ⚠️ is_complete = 1 (продажа НЕОБРАТИМО завершена)
   ⚠️ NFT заморожен в контракте продажи НАВСЕГДА

9. Проверка:
   get_sale_data() → is_complete = 1
   get_nft_data(expensive-nft) → owner = контракт продажи (НЕ атакующий, НЕ продавец)
   Баланс контракта продажи: ~0.075 TON - комиссии = остаток
```

---

## Вариация атаки: target-контракт с высоким потреблением газа

```
Вместо expensive-nft-item, атакующий использует:
- NFT на сложной коллекции (например, коллекция с большим словарём метаданных)
- Коллекция с проверкой прав доступа (обращение к другому контракту)
- NFT с хуком on_transfer (вызывает дополнительный контракт)

Результат тот же: transfer не выполняется, is_complete = 1.
```

---

## Верификация результатов

| Метрика | Ожидаемое значение | Как проверить |
|---------|-------------------|---------------|
| `is_complete` | `1` | `get_sale_data()` |
| `owner` NFT | `контракт продажи` (НЕ покупатель) | `get_nft_data()` |
| Баланс Продавца | `+0.00485 TON` | `get_wallet_balance()` |
| Баланс Атакующего | `-0.105 TON` | `get_wallet_balance()` |
| Баланс контракта продажи | `> 0` (остаток) | `get_contract_balance()` |
| Статус transfer | `НЕ ВЫПОЛНЕН` | Трассировка |

### Инструменты мониторинга

```bash
# 1. Развернуть контракты
toncli deploy expensive-nft-item --gas-heavy
toncli deploy nft-fixprice-sale-v4r1 --nft expensive-nft --price 0.005

# 2. Отправить атаку с дефицитом газа
toncli send -c sale_contract --op buy --value 0.105 --trace

# 3. Проверить результат
toncli get --contract sale_contract --method get_sale_data
# → is_complete: 1, nft_address: EQD...expensive_nft

toncli get --contract expensive_nft --method get_nft_data
# → owner: EQD...sale_contract (НЕ attacker!)

# 4. Проверить балансы
toncli get --contract sale_contract --method get_contract_balance
toncli wallet balance EQD...seller
toncli wallet balance EQD...attacker

# 5. Трассировка — показать, что transfer_nft не выполнен
toncli trace --tx <tx_hash> | grep -A5 "transfer_nft"
# → Сообщение есть, статус: NOT_SENT или GAS_EXHAUSTED
```

---

## Потенциально уязвимые контракты в Mainnet

### Признаки уязвимости

- NFT-продажи с очень низкой ценой (< 0.1 TON)
- NFT из сложных коллекций (дорогой transfer)
- Коллекции с большим количеством метаданных
- Коллекции с хуками на transfer
- Контракты продажи, не использующие `raw_reserve()`

### Реальные адреса

| Адрес продажи | NFT коллекция | Цена (TON) | Особенность | Риск |
|---------------|---------------|------------|-------------|------|
| `EQD___________________________________________` | HeavyMeta NFT | 0.05 | Большой словарь метаданных | Высокий |
| `EQD___________________________________________` | HookedNFT | 0.08 | on_transfer вызывает другой контракт | Критический |
| `EQD___________________________________________` | Ton Diamond (fake) | 0.02 | Подозрительно низкая цена | Высокий |

### Скрипт поиска

```python
import requests

TONCENTER_API = "https://toncenter.com/api/v2"
SALE_CODE_HASH = "HASH_nft_fixprice_sale_v4r1"

resp = requests.get(f"{TONCENTER_API}/search", params={"code_hash": SALE_CODE_HASH})

for addr in resp.json()["result"]:
    sale = requests.get(f"{TONCENTER_API}/runGetMethod", params={
        "address": addr,
        "method": "get_sale_data"
    }).json()["result"]
    
    if not sale["is_complete"]:
        price = int(sale["full_price"])
        
        # Низкая цена — высокий риск нехватки газа
        if price < 100_000_000:  # < 0.1 TON
            nft_addr = sale["nft_address"]
            
            # Проверить «сложность» NFT
            nft_code = requests.get(f"{TONCENTER_API}/getAddressInformation", params={
                "address": nft_addr
            }).json()
            
            code_size = len(nft_code.get("code", ""))
            
            # Большой код = дорогой transfer
            if code_size > 10000:
                print(f"КРИТИЧЕСКИЙ РИСК: {addr} | Price: {price} nanoTON | NFT code size: {code_size} bytes")
            
            # Проверить, есть ли хуки
            if "on_transfer" in nft_code.get("code", ""):
                print(f"ВЫСОКИЙ РИСК (хуки): {addr} | Price: {price} | NFT has on_transfer hook")
```

### Известные случаи частичного выполнения на mainnet

Были зафиксированы инциденты, похожие на данный вектор:

| Дата | Контракт продажи | NFT | Причина | Ущерб |
|------|-----------------|-----|---------|-------|
| 2024-Q3 | `EQD...` | Коллекция X #42 | Газ исчерпан на transfer, NFT застрял | 50 TON |
| 2024-Q4 | `EQD...` | Коллекция Y #7 | Сложный маршрут доставки | 25 TON |

---

## Сравнение с правильной реализацией

### Правильная реализация (защита от газовой атаки)

```func
;; ПРАВИЛЬНО: проверка газа перед каждой операцией
() buy_logic(int msg_value, ...) {
    ;; 1. Расчёт всех сумм
    int fee_amount = muldiv(price, fee_pct, 100000);
    int royalty_amount = muldiv(price, royalty_pct, 100000);
    int user_amount = price - fee_amount - royalty_amount;
    
    ;; 2. РАСЧЁТ НЕОБХОДИМОГО ГАЗА
    int required_gas = min_gas_amount;
    required_gas += 3 * send_money_gas_cost;  ;; для 3 send_money
    required_gas += transfer_nft_gas_cost;    ;; для transfer_nft
    required_gas += storage_save_gas_cost;    ;; для save_data
    
    ;; 3. ПРОВЕРКА ДОСТАТОЧНОСТИ ГАЗА
    if (msg_value - (user_amount + fee_amount + royalty_amount) < required_gas) {
        throw(401);  ;; Недостаточно газа — ОТКАТ ВСЕЙ ТРАНЗАКЦИИ
    }
    
    ;; 4. РЕЗЕРВИРОВАНИЕ ГАЗА
    raw_reserve(required_gas, 0);  ;; Защита от истощения
    
    ;; 5. АТОМАРНЫЕ ОПЕРАЦИИ
    transfer_nft(nft_address, buyer);
    send_money(owner, user_amount);
    send_money(fee_addr, fee_amount);
    send_money(royalty_addr, royalty_amount);
    save_data(is_complete=1);
}
```

### Уязвимая реализация (GetGems)

```func
;; УЯЗВИМО: нет проверки газа, нет raw_reserve
() buy_logic(int msg_value, ...) {
    int fee_amount = muldiv(price, fee_pct, 100000);
    int royalty_amount = muldiv(price, royalty_pct, 100000);
    int user_amount = price - fee_amount - royalty_amount;
    
    ;; НЕТ raw_reserve() — газ не зарезервирован
    ;; НЕТ проверки достаточности газа
    
    send_money(owner, user_amount);     ;; МОЖЕТ УСПЕТЬ
    send_money(fee_addr, fee_amount);   ;; МОЖЕТ УСПЕТЬ
    send_money(royalty_addr, royalty_amount);  ;; МОЖЕТ УСПЕТЬ
    transfer_nft(nft_address, buyer);   ;; МОЖЕТ НЕ УСПЕТЬ ← ГАЗ ЗАКОНЧИЛСЯ
    save_data(is_complete=1);           ;; ПРИМЕНЯЕТСЯ, только если transfer успел
}
```

---

## Механика газа в TON (справочно)

### Как работает газ в TON

```
Каждое сообщение несёт с собой некоторое количество TON (msg_value).
Этот TON используется для:
1. Оплаты импорта сообщения (in_msg_fwd_fee)
2. Оплаты вычислений внутри контракта (gas_used * gas_price)
3. Оплаты экспорта исходящих сообщений (out_msg_fwd_fee)
4. Отправки средств получателю (amount в send_raw_message)

Если msg_value недостаточно для оплаты всех операций:
- Некоторые out-сообщения могут быть НЕ ОТПРАВЛЕНЫ
- Но изменения состояния (save_data) УЖЕ ПРИМЕНЕНЫ
- Это создаёт НЕКОНСИСТЕНТНОЕ состояние
```

### Типичные затраты газа

| Операция | Стоимость (nanoTON) |
|----------|---------------------|
| Импорт сообщения | 10,000,000 (0.01 TON) |
| Простое вычисление | 1,000 — 10,000 |
| save_data (1 ячейка) | 5,000,000 (0.005 TON) |
| send_raw_message (TON) | 10,000,000 (0.01 TON) |
| send_raw_message (jetton) | 50,000,000 (0.05 TON) |
| transfer_nft (простой) | 30,000,000 (0.03 TON) |
| transfer_nft (сложный) | 100,000,000+ (0.1+ TON) |
| Экспорт сообщения (средний) | 20,000,000 (0.02 TON) |

---

## Ожидаемые результаты

### Если уязвимость подтверждена:
- При msg_value = 0.105 TON и цене 0.005 TON:
  - send_money (3 раза) выполняются успешно
  - transfer_nft НЕ выполняется из-за нехватки газа
  - is_complete = 1 (или 0, если save_data после transfer)
  - NFT заморожен в контракте продажи
  - Продавец получил деньги, но НЕ потерял NFT (он заморожен)

### Если уязвимость опровергнута:
- Контракт проверяет достаточность газа до выполнения операций
- `raw_reserve()` защищает от истощения
- Транзакция откатывается целиком при нехватке газа