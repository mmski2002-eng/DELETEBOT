# 🧪 План моделирования уязвимости 07 — Неатомарная jetton-покупка

## Архитектура тестового стенда (Testnet)

### Кошельки участников

| Роль | Кошелёк | Назначение |
|------|---------|------------|
| Аудитор (Deployer) | `EQD...audit_A` | Развёртывание контрактов, мониторинг |
| Продавец | `EQD...seller_S` | Продаёт NFT за jettons |
| Покупатель | `EQD...buyer_B` | Покупает NFT через jettons |
| Jetton-минтер | `EQD...minter_M` | Управляет jetton-кошельком покупателя |

### Контракты для развёртывания (Testnet)

| Контракт | Роль | Примечание |
|----------|------|------------|
| `nft-fixprice-sale-v4r1.fc` | Оригинальный контракт продажи | Без изменений (уязвимый — неатомарный) |
| `nft-item.fc` | Обычный NFT | Без изменений |
| `jetton-minter.fc` | Jetton-минтер | Управляет эмиссией jettons |
| `jetton-wallet.fc` | Jetton-кошелёк покупателя | Отправляет jettons на контракт продажи |
| `bad-jetton-wallet.fc` | Jetton-кошелёк злоумышленника | Отправляет jettons НЕ через стандартный transfer |
| `fake-jetton-wallet.fc` | Фейковый jetton-кошелёк | Имитирует transfer, но не отправляет jettons |

---

## Пошаговый план атаки (Testnet)

### Фаза 1: Развёртывание (блок N)

```
1. Аудитор разворачивает nft-item (обычный NFT)
2. Аудитор разворачивает jetton-minter (управляет эмиссией)
3. Аудитор разворачивает контракт продажи:
   - nft_address = адрес nft-item
   - full_price = 1000 USDT (jetton, цена в минимальных единицах)
   - marketplace_fee = 2.5%
   - royalty = 5%
   - is_jetton = true
   - jetton_master_address = адрес jetton-minter

4. Аудитор минтит 2000 USDT на кошелёк покупателя
5. Аудитор разворачивает bad-jetton-wallet для покупателя:
   - При transfer: отправляет jettons напрямую (МОЖЕТ МАНИПУЛИРОВАТЬ)
   - МОЖЕТ отправить частичную сумму
   - МОЖЕТ вызвать transfer без уведомления
   - МОЖЕТ отправить jettons на другой адрес
```

### Фаза 2: Эксплойт — неатомарная jetton-покупка (блок N+1)

```
6. Покупатель (через bad-jetton-wallet) вызывает transfer:
   destination = контракт продажи
   amount = 1000 USDT (цена)
   op = jetton_transfer

7. Сообщение доставляется на контракт продажи как internal message:
   op = jetton_notification  (оповещение о том, что jettons отправлены)
   amount = 1000 USDT
   sender = bad-jetton-wallet

8. Контракт продажи выполняет buy_logic():
   fee_amount = 25 USDT (2.5%)
   royalty_amount = 50 USDT (5%)
   user_amount = 925 USDT
   
   ВАЖНО: контракт ДОВЕРЯЕТ значению amount из jetton_notification
   Но РЕАЛЬНЫЙ баланс контракта может быть ДРУГИМ!

9. Контракт отправляет 4 сообщения:
   [A] send_money(Продавец, 925 USDT)  — через jetton_transfer
   [B] send_money(Маркетплейс, 25 USDT) — через jetton_transfer
   [C] send_money(Автор, 50 USDT)       — через jetton_transfer
   [D] transfer_nft(nft-item, Покупатель)
   
   НО! На балансе контракта МЕНЬШЕ 1000 USDT (злоумышленник отправил меньше)

10. Сообщения [A], [B], [C] пытаются отправить jettons:
    → Если баланс недостаточен: jetton_transfer ПАДАЕТ
    → НО в jetton-стандарте: transfer возвращает BOUNCE с ошибкой
    → Контракт не обрабатывает bounce (строка 172: return)
    → Продавец не получает USDT
    → Комиссии не выплачены
    → НО! transfer_nft МОГ БЫТЬ ОТПРАВЛЕН ДО попытки jetton_transfer
```

### Фаза 3: Порядок сообщений и неатомарность (блок N+2)

```
11. Ключевая проблема: ПОРЯДОК ОТПРАВКИ СООБЩЕНИЙ
    В buy_logic() порядок:
    - send_money(owner)        # [A] ← может упасть (недостаточно jettons)
    - send_money(fee_addr)     # [B] ← может упасть
    - send_money(royalty_addr) # [C] ← может упасть
    - transfer_nft(nft_addr)   # [D] ← может пройти ДО того как [A] упадёт

12. Если [D] отправлен ДО того как [A] получает bounce:
    → NFT уже у покупателя
    → Деньги НЕ у продавца
    → Контракт помечен is_complete=1
    → Bounce от [A] приходит ПОСЛЕ → игнорируется (строка 172)

13. Результат:
    - Покупатель получил NFT
    - Продавец НЕ получил jettons (или получил НЕПОЛНУЮ сумму)
    - Комиссии не выплачены
    - Контракт завершён (is_complete=1)
```

### Фаза 4: Альтернативные векторы атаки

```
14. Манипуляция с notification:
    - bad-jetton-wallet вызывает send_raw_message на контракт продажи
    - Подделывает op = jetton_notification с amount = 1000
    - НО реальные jettons НЕ отправлены
    - Контракт доверяет notification → выполняет логику продажи
    - Покупатель получает NFT БЕСПЛАТНО

15. Манипуляция с balance_after_transfer:
    - bad-jetton-wallet отправляет 500 USDT (половина цены)
    - В notification указывает amount = 500
    - Контракт выполняет buy_logic():
      fee_amount = 12.5 USDT, royalty_amount = 25 USDT, user_amount = 462.5 USDT
    - Контракт отправляет jettons на основе amount из notification
    - Либо контракт проверяет баланс → расхождение → ошибка
    - Либо контракт доверяет notification → частичная покупка
```

---

## Верификация результатов

| Метрика | Ожидаемое значение | Как проверить |
|---------|-------------------|---------------|
| `is_complete` контракта продажи | `1` | `get_sale_data()` |
| Баланс продавца (jetton) | 0 или < 1000 USDT | `get_jetton_balance()` |
| Владелец NFT | Покупатель | `get_nft_data()` |
| Jetton-баланс контракта продажи | > 0 (застрявшие jettons) | `get_jetton_balance()` |
| Bounce-сообщение от jetton_transfer | Есть, но игнорируется | Трассировка |

### Инструменты мониторинга

```bash
# 1. Развернуть контракты
toncli deploy nft-fixprice-sale-v4r1 --jetton --price 1000 --jetton-master EQD...minter

# 2. Проверить jetton-баланс
toncli get --contract sale_contract --method get_wallet_balance --jetton

# 3. Отправить jettons с манипуляцией
toncli send-jetton --from bad_wallet --to sale_contract --amount 500

# 4. Трассировка покупки
toncli trace --tx <tx_hash>

# 5. Проверить результат
toncli get --contract sale_contract --method get_sale_data
toncli get --contract nft_item --method get_nft_data
toncli get --contract seller_wallet --method get_jetton_balance
```

---

## Потенциально уязвимые контракты в Mainnet

### Признаки уязвимости

- Jetton-продажи GetGems (продажа NFT за USDT, NOTcoin, и т.д.)
- Продажи, где `jetton_master_address` указывает на популярный стейблкоин
- Высокая цена в jettons (> 1000 USDT)
- Нестандартные jetton-минтеры (малоизвестные токены)

### Реальные адреса

| Адрес продажи | NFT коллекция | Цена (USDT) | Jetton | Риск |
|---------------|---------------|-------------|--------|------|
| `EQD___________________________________________` | Ton Diamond | 500 USDT | USDT | Высокий |
| `EQD___________________________________________` | Anonymous | 200 USDT | NOT | Средний |
| `EQD___________________________________________` | TON Punks | 1000 USDT | USDT | Критический |

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
    
    if not sale["is_complete"] and sale.get("is_jetton"):
        price = sale["full_price"]
        
        # Проверить jetton-мастер
        jetton_master = sale.get("jetton_master_address")
        
        # Проверить, верифицирован ли jetton
        jetton_info = requests.get(f"{TONCENTER_API}/getWalletInformation", params={
            "address": jetton_master
        }).json()
        
        if not jetton_info.get("verified"):
            print(f"НЕВЕРИФИЦИРОВАННЫЙ JETTON: {addr} | Master: {jetton_master} | Price: {price}")
        
        # Проверить баланс контракта
        jetton_balance = requests.get(f"{TONCENTER_API}/runGetMethod", params={
            "address": addr,
            "method": "get_wallet_balance"
        }).json()
        
        if int(jetton_balance.get("result", 0)) > 0 and sale["is_complete"]:
            print(f"ЗАСТРЯВШИЕ JETTONS: {addr} | Balance: {jetton_balance}")
```

---

## Сравнение с атомарным подходом

### Правильная реализация (атомарная jetton-покупка)

```func
;; ПРАВИЛЬНО: атомарность через deferred transfer
() recv_internal(...) {
    if (op == jetton_notification) {
        ;; ПРОВЕРИТЬ актуальный баланс, а не верить notification
        int my_balance = get_jetton_balance(my_address, jetton_wallet);
        
        if (my_balance < full_price) {
            throw(400);  ;; Откат: недостаточно jettons
        }
        
        ;; РЕЗЕРВИРОВАТЬ jettons перед распределением
        raw_reserve(0, 0);  ;; Защита от нехватки газа
        
        ;; АТОМАРНО: сначала перевести NFT, потом деньги
        transfer_nft(nft_address, buyer);
        ;; Если transfer_nft упал → ВСЁ откатывается
        
        ;; Только после успешного transfer_nft:
        send_jetton(owner, user_amount);
        send_jetton(fee, fee_amount);
        send_jetton(royalty, royalty_amount);
    }
}
```

### Уязвимая реализация (GetGems)

```func
;; УЯЗВИМО: порядок обратный
() buy_logic(...) {
    send_money(owner, user_amount);   ;; СНАЧАЛА деньги
    send_money(fee, fee_amount);
    send_money(royalty, royalty_amount);
    transfer_nft(nft_address, buyer); ;; ПОТОМ NFT
    ;; Если transfer_nft упадёт → деньги уже ушли
}
```

---

## Ожидаемые результаты

### Если уязвимость подтверждена:
- Отправка недостаточного количества jettons + корректный notification → NFT передан, деньги потеряны
- Порядок операций: деньги → NFT (должно быть: NFT → деньги для атомарности)
- Bounce от jetton_transfer игнорируется

### Если опровергнута:
- Контракт сверяет баланс с суммой из notification
- Установлен `raw_reserve` для защиты от неатомарности
- Порядок: NFT → деньги