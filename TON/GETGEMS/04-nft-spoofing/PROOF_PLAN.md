# 🧪 План моделирования уязвимости 04 — Подделка NFT (NFT Spoofing)

## Архитектура тестового стенда (Testnet)

### Кошельки участников

| Роль | Кошелёк | Назначение |
|------|---------|------------|
| Аудитор (Deployer) | `EQD...audit_A` | Развёртывание контрактов, мониторинг |
| Мошенник (Scammer) | `EQD...scammer_S` | Создаёт фейковый NFT, обманывает покупателя |
| Жертва (Buyer) | `EQD...victim_V` | Покупает «NFT из коллекции X», получает подделку |

### Контракты для развёртывания (Testnet)

| Контракт | Роль | Примечание |
|----------|------|------------|
| `real-collection.fc` | Настоящая коллекция (например, Ton Diamonds) | Без изменений |
| `fake-nft-item.fc` | Фейковый NFT, **НЕ** принадлежащий real-collection | Вычисленный адрес НЕ совпадает с `hash(collection, index)` |
| `nft-fixprice-sale-v4r1.fc` | Оригинальный контракт продажи | Без изменений (уязвимый — нет проверки TEP-62) |

---

## Пошаговый план атаки (Testnet)

### Фаза 1: Развёртывание (блок N)

```
1. Аудитор разворачивает real-collection (Ton Diamonds demo):
   - collection_address = EQD...real_collection
   - next_item_index = 0

2. Аудитор минтит NFT#0 внутри real-collection:
   - Адрес NFT#0 = hash(real_collection, 0) → EQD...real_nft_0

3. Мошенник разворачивает fake-nft-item ОТДЕЛЬНО (не через коллекцию!):
   - Адрес fake-nft-item = EQD...fake_nft (произвольный адрес)
   - fake-nft-item.fc принимает op::transfer (обычная реализация)
   - ВАЖНО: EQD...fake_nft ≠ hash(real_collection, 0)
   - fake-nft-item НЕ ПРИНАДЛЕЖИТ real-collection

4. Мошенник разворачивает контракт продажи:
   - nft_address = EQD...fake_nft (фейковый адрес!)
   - full_price = 100 TON
   - marketplace_fee = 2.5%
   - royalty = 5%
   
5. Мошенник в UI/metadata указывает:
   - «NFT из коллекции Ton Diamonds #0» (ЛОЖЬ)
   - Цена: 100 TON
```

### Фаза 2: Эксплойт — покупка жертвой (блок N+1)

```
6. Жертва видит объявление на маркетплейсе:
   «Ton Diamonds #0 — 100 TON»
   
7. Жертва НЕ проверяет адрес NFT вручную (доверяет UI)
   Жертва отправляет 100.1 TON на контракт продажи

8. Контракт продажи выполняет buy_logic():
   user_amount = 92.5 TON
   fee_amount = 2.5 TON
   royalty_amount = 5 TON

9. Контракт отправляет 4 сообщения:
   [A] send_money(Мошенник, 92.5 TON)       → успех
   [B] send_money(Маркетплейс, 2.5 TON)      → успех
   [C] send_money(Автор, 5 TON)               → успех
   [D] transfer_nft(EQD...fake_nft, Жертва)  → успех (fake-nft-item ПРИНИМАЕТ)

10. save_data(is_complete=1) → продажа завершена
```

### Фаза 3: Обнаружение подделки (блок N+2)

```
11. Жертва проверяет свой кошелёк:
    - Получен NFT с адресом EQD...fake_nft
    - Жертва проверяет коллекцию NFT: get_nft_data()
    - collection_address = EQD...fake_nft (или 0, или другая коллекция)
    - Это НЕ Ton Diamonds!

12. Проверка через TEP-62:
    expected_nft_address = hash(EQD...real_collection, 0)
    actual_nft_address = EQD...fake_nft
    expected_nft_address ≠ actual_nft_address → ПОДДЕЛКА

13. Жертва потеряла 100 TON, получив бесполезный NFT
    Реальная цена fake-nft-item = 0 TON
```

---

## Верификация результатов

| Метрика | Ожидаемое значение | Как проверить |
|---------|-------------------|---------------|
| `nft_address` в контракте продажи | `EQD...fake_nft` | `get_sale_data()` |
| `collection_address` у NFT | НЕ `EQD...real_collection` | `get_nft_data()` |
| `index` у NFT | не совпадает с ожидаемым | `get_nft_data()` |
| `hash(collection, index)` | ≠ `nft_address` | Вычислить вручную |
| Баланс жертвы | `-100.1 TON` | `get_wallet_balance()` |
| NFT у жертвы | фейковый | `get_nft_data()` |

### Проверка через консоль

```bash
# 1. Получить данные продажи
toncli get --contract sale_contract --method get_sale_data
# → nft_address = EQD...fake_nft

# 2. Получить данные NFT
toncli get --contract fake_nft --method get_nft_data
# → collection_address = EQD... (другая коллекция или 0)
# → index = ???

# 3. Вычислить ожидаемый адрес
toncli compute-nft-address --collection EQD...real_collection --index 0
# → EQD...real_nft_0

# 4. Сравнить
[ "EQD...fake_nft" != "EQD...real_nft_0" ] && echo "SPOOF DETECTED"
```

---

## Потенциально уязвимые контракты в Mainnet

### Признаки мошенничества

- Контракт продажи, где `nft_address` не совпадает с `hash(collection_address, index)`
- Продавец не является владельцем NFT (уже передан другому)
- NFT указывает на неизвестную коллекцию (не верифицированную)
- Цена значительно ниже рыночной (приманка)

### Реальные адреса для проверки

| Адрес продажи | Заявленная коллекция | Цена | Риск |
|---------------|---------------------|------|------|
| `EQD___________________________________________` | Ton Diamond | 50 TON | Высокий (цена подозрительно низкая) |
| `EQD___________________________________________` | Anonymous Numbers | 10 TON | Критический (известны случаи подделок) |

### Скрипт поиска подделок

```python
import requests, hashlib

TONCENTER_API = "https://toncenter.com/api/v2"
SALE_CODE_HASH = "HASH_nft_fixprice_sale_v4r1"

def compute_nft_address(collection_addr: str, index: int) -> str:
    """TEP-62: NFT address = hash(collection_address, item_index)"""
    import hashlib
    data = collection_addr.encode() + index.to_bytes(32, 'big')
    return "EQ" + hashlib.sha256(data).hexdigest()[:64]

resp = requests.get(f"{TONCENTER_API}/search", params={"code_hash": SALE_CODE_HASH})

for addr in resp.json()["result"]:
    sale = requests.get(f"{TONCENTER_API}/runGetMethod", params={
        "address": addr,
        "method": "get_sale_data"
    }).json()["result"]
    
    if not sale["is_complete"]:
        # Получить данные NFT
        nft = requests.get(f"{TONCENTER_API}/runGetMethod", params={
            "address": sale["nft_address"],
            "method": "get_nft_data"
        }).json()["result"]
        
        # Проверить TEP-62
        expected = compute_nft_address(nft["collection_address"], nft["index"])
        if expected != sale["nft_address"]:
            print(f"🚨 ПОДДЕЛКА: Sale={addr} | NFT={sale['nft_address']} | Expected={expected} | Price={sale['full_price']} TON")
```

### Известные коллекции для мониторинга

| Коллекция | Адрес коллекции | Риск подделки |
|-----------|----------------|---------------|
| Ton Diamonds | `EQD___________________________________________` | Высокий (дорогие NFT) |
| Anonymous Numbers | `EQD___________________________________________` | Критический (популярная) |
| TON Punks | `EQD___________________________________________` | Высокий |

---

## Ожидаемые результаты

### Если уязвимость подтверждена:
- Контракт продажи принимает любой `nft_address` без проверки TEP-62
- Жертва получает фейковый NFT, теряет деньги
- Маркетплейс не может автоматически обнаружить подделку
- UI маркетплейса показывает ложную информацию о коллекции

### Если уязвимость опровергнута:
- Существует валидация `nft_address` на уровне контракта (не найдена в коде)
- Маркетплейс проверяет `nft_address` перед отображением