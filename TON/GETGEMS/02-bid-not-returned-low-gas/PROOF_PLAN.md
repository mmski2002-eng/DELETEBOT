# 🧪 План моделирования уязвимости 02 — Невозврат ставки при mode=2

## Архитектура тестового стенда (Testnet)

### Кошельки участников

| Роль | Кошелёк | Назначение |
|------|---------|------------|
| Аудитор (Deployer) | `EQD...audit_A` | Развёртывание аукционного контракта, мониторинг |
| Владелец NFT | `EQD...owner_O` | Владелец NFT, инициирует аукцион |
| Первый участник (Bidder-1) | `EQD...bid1` | Делает первую ставку — станет жертвой |
| Второй участник (Bidder-2) | `EQD...bid2` | Делает вторую ставку — триггерит возврат с mode=2 |

### Контракты для развёртывания (Testnet)

| Контракт | Роль | Примечание |
|----------|------|------------|
| `nft-auction.fc` | Оригинальный аукционный контракт GetGems | Без изменений (уязвимый) |
| `fake-nft-item.fc` | NFT-токен | Обычный NFT, принимает transfer |
| `bad-wallet.fc` | Кошелёк Bidder-1, **отклоняет все сообщения** | Модифицирован: `recv_internal` — всегда return bounced |

---

## Пошаговый план атаки (Testnet)

### Фаза 1: Развёртывание (блок N)

```
1. Аудитор разворачивает fake-nft-item (обычный NFT)
2. Владелец разворачивает nft-auction с параметрами:
   - nft_address = адрес fake-nft-item
   - min_bid = 5 TON
   - end_time = now() + 3600 (1 час)
   - marketplace_fee = 2.5%
   - royalty = 0%
3. Аудитор разворачивает bad-wallet для Bidder-1:
   - recv_internal всегда возвращает ошибку (throw или return с флагом 2)
4. Записываем состояние:
   - current_bid = 0
   - current_bidder = null
```

### Фаза 2: Эксплойт (блок N+1)

```
5. Bidder-1 (через bad-wallet) отправляет ставку:
   msg_value = 5.1 TON (ставка + газ)
   op = bid

6. Аукционный контракт обрабатывает ставку:
   - current_bid = 0 → ставка принимается без возврата предыдущей
   - save_data(current_bid = 5, current_bidder = Bidder-1)
   ✅ Bidder-1 становится лидером

7. Bidder-2 отправляет вторую ставку:
   msg_value = 10.1 TON (ставка + газ)
   op = bid

8. Аукционный контракт обрабатывает вторую ставку:
   - current_bid = 5 → нужно вернуть 5 TON предыдущему лидеру (Bidder-1)
   - send_raw_message(Bidder-1, 5 TON, MODE=2)  ← КРИТИЧЕСКОЕ МЕСТО
   - MODE=2 = SEND_MODE_IGNORE_ERRORS + PAY_FEES_SEPARATELY
   - Сообщение летит в bad-wallet

9. bad-wallet (Bidder-1) получает 5 TON:
   - recv_internal → возвращает ошибку
   - Сообщение должно стать bounced...
   - НО MODE=2 = IGNORE_ERRORS → bounced НЕ ГЕНЕРИРУЕТСЯ
   - 5 TON просто ИСЧЕЗАЮТ (уходят на комиссии валидаторам)

10. Контракт продолжает:
    - save_data(current_bid = 10, current_bidder = Bidder-2)
    ✅ Bidder-2 становится лидером
    ❌ Bidder-1 потерял 5 TON навсегда
```

### Фаза 3: Подтверждение (блок N+2)

```
11. Проверяем баланс Bidder-1 (bad-wallet):
    - Было: X TON
    - Стало: X - 5 TON (ставка не вернулась)
    
12. Проверяем баланс аукционного контракта:
    - Хранит 10 TON (только текущая ставка Bidder-2)
    - 5 TON от Bidder-1 потеряны в сети (не в контракте и не у Bidder-1)

13. Проверяем логи транзакций:
    - Транзакция возврата Bidder-1 имеет статус FAILED
    - Но контракт аукциона не получил bounced
    - Никакого обработчика ошибок не вызвано
```

---

## Верификация результатов

| Метрика | Ожидаемое значение | Как проверить |
|---------|-------------------|---------------|
| `current_bid` | `10 TON` | `get_auction_data()` |
| `current_bidder` | `Bidder-2` | `get_auction_data()` |
| Баланс Bidder-1 | `-5 TON` (относительно до атаки) | `get_wallet_balance()` |
| Баланс аукциона | `10 TON` | `get_contract_balance()` |
| Bounced message count | `0` (MODE=2 подавляет) | Трассировка транзакции |

---

## Потенциально уязвимые контракты в Mainnet

### Признаки уязвимости

- Активные аукционы GetGems с `current_bid > 50 TON`
- Предыдущий лидер имеет нестандартный кошелёк (например, смарт-кошелёк с кастомной логикой)
- Аукцион близок к завершению (большой интерес → много ставок → высокий риск)

### Реальные адреса аукционов (GetGems mainnet)

| Адрес аукциона | NFT коллекция | Текущая ставка | Риск |
|----------------|---------------|----------------|------|
| `EQD___________________________________________` | Ton Diamond #7 | 150 TON | Высокий |
| `EQD___________________________________________` | Anonymous #42 | 80 TON | Средний |

### Скрипт поиска уязвимых аукционов

```python
import requests

TONCENTER_API = "https://toncenter.com/api/v2"
AUCTION_CODE_HASH = "HASH_nft_auction"

resp = requests.get(f"{TONCENTER_API}/search", params={"code_hash": AUCTION_CODE_HASH})

for addr in resp.json()["result"]:
    data = requests.get(f"{TONCENTER_API}/runGetMethod", params={
        "address": addr,
        "method": "get_auction_data"
    })
    
    auction = data.json()["result"]
    
    # Активный аукцион с высокой ставкой
    if not auction["is_complete"] and auction["current_bid"] > 50_000_000_000:
        # Проверить, какой тип кошелька у current_bidder
        bidder_type = requests.get(f"{TONCENTER_API}/getWalletInformation", params={
            "address": auction["current_bidder"]
        })
        
        if bidder_type["wallet_type"] != "wallet v4 r2":  # нестандартный
            print(f"УЯЗВИМ: {addr} | Ставка: {auction['current_bid']} TON | Bidder: {auction['current_bidder']}")
```

---

## Ожидаемые результаты тестирования

### Если уязвимость подтверждена:
- Ставка Bidder-1 (5 TON) потеряна навсегда
- Аукцион продолжается с Bidder-2
- Никакого bounced не сгенерировано (mode=2)
- Контракт не имеет обработчика для этого сценария

### Если уязвимость опровергнута:
- Bidder-1 получает свои 5 TON обратно
- Должен существовать механизм ручного возврата (manual repayment)
- Или mode должен быть изменён на 130 (IGNORE_ERRORS + CARRY_REMAINING_BALANCE)