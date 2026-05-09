# Находка 7: `depositWithId` / `depositNativeWithId` — Обход ограничений депозита

**Серьезность:** Low / Informational  
**Категория:** Логика / Частичный обход контроля доступа  
**Уязвимый контракт:** `DVFDepositContract.sol`  
**Уязвимые функции:** `depositWithId()` (строка 84–88), `depositNativeWithId()` (строка 113–115)  
**Сеть:** Все EVM-цепи (Ethereum, Arbitrum, Optimism, BSC, Polygon и др.)

---

## План доказательства уязвимости

### Цель
Доказать, что функции `depositWithId()` и `depositNativeWithId()` не используют модификатор `_areDepositsAllowed` и проверку `checkMaxDepositAmount`, что позволяет обходить глобальный запрет депозитов и лимиты.

---

### Шаг 1: Подготовка тестового окружения

1. Открыть проект в Foundry: `cd c:\DELETEBOT\RHINOfi\poc`
2. Убедиться, что все зависимости установлены:
   ```
   forge install OpenZeppelin/openzeppelin-contracts-upgradeable OpenZeppelin/openzeppelin-contracts foundry-rs/forge-std --no-commit
   ```
3. Проверить конфигурацию `foundry.toml`

**Исходные файлы PoC (уже есть):**
- `poc/src/DVFDepositContract.sol` — точная копия оригинального контракта с уязвимостями
- `poc/src/AttackHelpers.sol` — вспомогательные контракты (SimplePermitToken для permit-тестов)
- `poc/test/PoC_RhinoFi.t.sol` — тесты для всех находок

---

### Шаг 2: Тест `test_Finding7_depositWithId_Bypass()` — обход глобального запрета

**Логика теста:**

```
1. Деактивировать все депозиты через allowDepositsGlobal(false)
   → depositsDisallowed = true

2. Попытаться внести депозит через deposit(token, 100)
   → ОЖИДАЕМ: REVERT "DEPOSITS_NOT_ALLOWED" (корректная работа)

3. Внести депозит через depositWithId(token, 100, 99999)
   → ОЖИДАЕМ: SUCCESS (УЯЗВИМОСТЬ — обход защиты!)
```

**Данные для логирования:**
```
depositsDisallowed = true (глобальный запрет)
deposit()          → REVERT "DEPOSITS_NOT_ALLOWED"  ✅
depositWithId()    → SUCCESS                        ❌ УЯЗВИМОСТЬ
```

**Команда запуска:**
```bash
cd c:\DELETEBOT\RHINOfi\poc
forge test -vvvv --match-test test_Finding7_depositWithId_Bypass
```

---

### Шаг 3: Тест `test_Finding7_depositNativeWithId_Bypass()` — обход лимита + запрета

**Логика теста:**

```
1. Деактивировать депозиты: allowDepositsGlobal(false)
2. Установить лимит 1 ETH для нативного депозита: allowDeposits(address(0), 1 ether)

3. Попытаться внести 0.5 ETH через depositNative{value: 0.5 ether}
   → ОЖИДАЕМ: REVERT "DEPOSITS_NOT_ALLOWED" (корректно)

4. Внести 100 ETH через depositNativeWithId{value: 100 ether}(88888)
   → ОЖИДАЕМ: SUCCESS (УЯЗВИМОСТЬ — обход и запрета, и лимита!)
```

**Данные для логирования:**
```
depositsDisallowed  = true
maxDepositAmount[ETH] = 1 ETH
depositNative(0.5 ETH)          → REVERT "DEPOSITS_NOT_ALLOWED"  ✅
depositNativeWithId(100 ETH)    → SUCCESS                        ❌ УЯЗВИМОСТЬ
Фактически внесено: 100 ETH при лимите 1 ETH!
```

**Команда запуска:**
```bash
cd c:\DELETEBOT\RHINOfi\poc
forge test -vvvv --match-test test_Finding7_depositNativeWithId_Bypass
```

---

### Шаг 4: Развертывание на тестовой сети (опционально — ончейн-верификация)

Для убедительного доказательства можно развернуть контракт на тестовой сети:

1. Развернуть `SimplePermitToken` на тестовой сети (например, Sepolia)
2. Развернуть `DVFDepositContract` через UpgradeableProxy
3. Настроить состояние:
   - `allowDepositsGlobal(false)` — запретить депозиты
   - `allowDeposits(token_address, 1000 ether)` — установить лимит
4. Выполнить транзакции:
   - `deposit(token_address, 100 ether)` → должна ревертнуть с `"DEPOSITS_NOT_ALLOWED"`
   - `depositWithId(token_address, 10000 ether, 12345)` → должна пройти успешно

**Инструменты для ончейна:**
- Использовать `cast` (Foundry) для отправки транзакций
- Или использовать `poc/verify_onchain.js` для верификации

---

### Шаг 5: Анализ результатов

**Ожидаемые результаты тестов:**

```
=== Finding #7: depositWithId Bypass ===
[PASS] test_Finding7_depositWithId_Bypass()
  Logs:
    CORRECT: deposit() reverts with DEPOSITS_NOT_ALLOWED
    BUG: depositWithId() bypassed global deposit restrictions!

[PASS] test_Finding7_depositNativeWithId_Bypass()
  Logs:
    CORRECT: depositNative() reverts
    BUG: depositNativeWithId() bypassed ALL restrictions
    Deposited 100 ETH despite 1 ETH limit
```

---

### Шаг 6: Оценка Impact

| Метрика | Значение |
|---------|----------|
| Обход `depositsDisallowed` | ✅ Подтвержден |
| Обход `maxDepositAmount` для ERC20 | ✅ Подтвержден |
| Обход `maxDepositAmount` для ETH | ✅ Подтвержден |
| Возможность кражи средств | ❌ Нет (средства зачисляются на контракт) |
| Нарушение бизнес-логики | ✅ Да (депозиты в режиме обслуживания) |
| Серьезность | Low/Info |

---

### Приложение: Исходный код уязвимых функций

```solidity
// ❌ НЕТ модификатора _areDepositsAllowed, НЕТ checkMaxDepositAmount
function depositWithId(address token, uint256 amount, uint256 commitmentId) public {
    require(token != address(0), 'BLACKHOLE_NOT_ALLOWED');
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
    emit BridgedDepositWithId(msg.sender, tx.origin, token, amount, commitmentId);
}

// ❌ НЕТ модификатора _areDepositsAllowed, НЕТ checkMaxDepositAmount
function depositNativeWithId(uint256 commitmentId) external payable {
    emit BridgedDepositWithId(msg.sender, tx.origin, address(0), msg.value, commitmentId);
}
```

### Сравнение с защищенными функциями:

```solidity
// ✅ ЕСТЬ модификатор _areDepositsAllowed, ЕСТЬ checkMaxDepositAmount
function deposit(address token, uint256 amount) external _areDepositsAllowed {
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
    checkMaxDepositAmount(token, amount);
    require(token != address(0), 'BLACKHOLE_NOT_ALLOWED');
    emit BridgedDeposit(msg.sender, token, amount);
}

// ✅ ЕСТЬ модификатор _areDepositsAllowed, ЕСТЬ checkMaxDepositAmount
function depositNative() external payable _areDepositsAllowed {
    checkMaxDepositAmount(address(0), msg.value);
    emit BridgedDeposit(msg.sender, address(0), msg.value);
}
```

### Вывод

Уязвимость подтверждается двумя независимыми тестами. Функции `depositWithId()` и `depositNativeWithId()` полностью игнорируют механизмы контроля депозитов (`depositsDisallowed` и `maxDepositAmount`), что позволяет вносить средства даже в режиме аварийной остановки моста и превышать установленные лимиты. Однако direct loss средств отсутствует — бэкенд может самостоятельно отфильтровывать такие депозиты.
