# KernelDAO — Результаты аудита логики

**Репозиторий:** `Kelp-DAO/kernel-smart-contracts-public`  
**Сеть:** BSC Mainnet  
**Контекст:** авторизованный аудит / bug bounty (Immunefi)  
**Проверенный код:** StakerGateway, KernelVault, AssetRegistry, KernelConfig + тесты

---

## Инвентаризация источников

| Источник | Статус |
|---|---|
| StakerGateway, KernelVault, AssetRegistry, KernelConfig, тесты | PROVIDED |
| DVNCoordinator, DVNGateway, slash mechanism, Merkle rewards, dispute | MISSING — не в репо |
| asBNB / slisBNB / BNBx token contracts (rebase vs exchange-rate) | NEEDS VERIFICATION |
| Балансы BSC mainnet, история транзакций | NOT CHECKED |
| Отчёты Bailsec / ChainSecurity / Sigma Prime | NOT ACCESSIBLE |

---

## Верификация законов системы

| Закон | Статус | Где enforced |
|---|---|---|
| L1 — Conservation user balance | ENFORCED | `balances[owner] -= amount` → `forceApprove` → `safeTransferFrom` — атомично |
| L2 — StakerGateway monopoly | ENFORCED | `onlyFromStakerGateway` modifier на `deposit()` и `withdraw()` |
| L3 — Asset-vault uniqueness | ENFORCED | `addAsset` ревертит при `_hasAsset(asset)`; `removeAsset` требует `balance() == 0` |
| L4 — Deposit cap atomicity | ENFORCED | `require(_balance() + depositAmount <= depositLimit)` до записи; один tx |
| L5 — Native BNB conservation | ENFORCED | EVM atomicity; revert откатывает `IWBNB.deposit()` + `safeTransferFrom` + `vault.deposit()` |
| L6 — Pause independence | ENFORCED | 3 независимых ключа: PROTOCOL, VAULTS_DEPOSIT, VAULTS_WITHDRAW |
| L7 — asBNB value stability | **ASSUMED ONLY** | Vault хранит raw token count; exchange rate logic отсутствует полностью |
| L8 — DVN upgrade neutrality | MISSING CODE | DVN layer не в репо |
| L9 — Slash precedes withdrawal | MISSING CODE | `slash()` функции нет в StakerGateway / KernelVault |
| L10 — Reward Merkle integrity | MISSING CODE | Merkle contracts не в репо |
| L11 — Dispute finality | MISSING CODE | Dispute contracts не в репо |

---

## Результаты по гипотезам H1–H9

### H1 — asBNB double-yield
**Вердикт: DESIGN INTENT, не баг.**
Vault хранит principal в raw token units. Протокол явно позиционирует layered yields как feature — пользователь сохраняет appreciation asBNB и одновременно получает DVN rewards. Exchange rate logic в vault отсутствует намеренно.

### H2 — Slash/unstake race
**Вердикт: MISSING CODE.**
Функций `slash()`, `penalty()`, `deduct()` нет ни в StakerGateway, ни в KernelVault. Механизм слэша полностью отсутствует в этом репо. Это критичный unknown — как DVN воздействует на vault balance оператора — неизвестно.

### H3 — Vault cap race
**Вердикт: BLOCKED.**
Блокирующие механизмы:
- EVM sequential execution — нет параллельных транзакций в одном блоке
- Delta accounting: `depositAmount = balanceERC20() - vaultBalanceBefore` изолирует donation attacks
- Тест `test_Stake_WithERC20TransferSpoofingDepositLimit` явно покрывает сценарий с прямой отправкой токенов на vault

### H4 — stakeNative() BNB stuck
**Вердикт: BLOCKED.**
`stakeNative()` — один атомарный tx: `IWBNB.deposit()` → `safeTransferFrom()` → `vault.deposit()`. Если любой шаг ревертит — все три откатываются. Подтверждено тестами:
- `test_StakeNative_RevertIfDepositLimitIsReached`
- `test_StakeNative_RevertIfVaultsDepositIsPaused`

### H5 — AssetRegistry vault migration
**Вердикт: BLOCKED.**
`removeAsset()` содержит: `require(IKernelVault(vault).balance() == 0, VaultNotEmpty())`. Нет функции `updateVault()`. Vault address immutable после регистрации — миграция без полного вывода средств невозможна.

### H6 — Pause asymmetry exploitation
**Вердикт: BLOCKED.**
Нет in-flight state. `stake()` / `unstake()` — атомарные транзакции. Пауза между мемпулом и включением в блок вызывает revert, не exploitable state.

### H7 — DVNCoordinator beacon breaks DVNGateway
**Вердикт: MISSING CODE.** DVN layer не в репо.

### H8 — Reward Merkle overclaim
**Вердикт: MISSING CODE.** Merkle contracts не в репо.

### H9 — Referral ID side-effects
**Вердикт: BLOCKED.**
`referralId` используется только в `emit AssetStaked(msg.sender, asset, depositAmount, referralId)` и `emit AssetUnstaked(...)`. Никакой логики маршрутизации, комиссий или вычислений не затрагивает.

---

## Активные находки

---

### НАХОДКА 1 — Rebase yield permanently trapped

**Severity:** Medium  
**Confidence:** Medium (зависит от типа токенов)  

**Сломанное допущение:** Vault предполагает, что все поддерживаемые токены используют exchange-rate модель (как wstETH — balance не меняется автоматически).

**Weird state:**
```
totalBalance = 100   // внутренний учёт
balanceERC20() = 110 // после auto-rebase события
delta = 10 → нет владельца → заморожено навсегда
```

**Почему обычный ревью пропускает:** happy path не включает период между deposit и rebase event. Vault.deposit() использует delta `balanceERC20() - vaultBalanceBefore` — rebase tokens автоматически поглощаются в snapshot следующего депозита, а не в `totalBalance`.

**Attack path:**
1. Пользователь депонирует 100 rToken → `totalBalance = 100`, `balanceERC20() = 100`
2. Время проходит, токен rebases → `balanceERC20() = 110`, `totalBalance = 100`
3. Пользователь анстейкает 100 → получает 100 ✓
4. `balanceERC20() = 10`, `totalBalance = 0`
5. 10 токенов заморожены навсегда — нет ни admin rescue, ни sweep функции

**Affected function:** `KernelVault.deposit()`, `KernelVault.withdraw()`

**Impact:** Accumulated rebase yield теряется — ни пользователи, ни протокол не могут его вывести. При большом TVL и агрессивном rebasing — значительные потери.

**Minimum required powers:** Никаких — срабатывает автоматически со временем.

**Следующий тест:**
```bash
# Снять показание balanceERC20() vault для slisBNB/BNBx/asBNB
cast call 0x<vault_address> "balanceERC20()(uint256)" --rpc-url https://bsc-dataseed.binance.org

# Подождать одну эпоху rebase
# Снять снова БЕЗ deposit/withdraw events

# Expected if TRUE: balanceERC20() увеличилось без транзакций
# Expected if FALSE: balanceERC20() стабильно между deposit events
```

---

### НАХОДКА 2 — DVN slash layer полностью отсутствует в коде

**Severity:** Информационная (по факту MISSING) / потенциально Critical  
**Confidence:** High (факт отсутствия кода подтверждён)  

**Факт:** В StakerGateway и KernelVault нет ни одной функции с `slash`, `penalty`, `deduct` в имени. Слэш-механизм полностью отсутствует.

**Критический вопрос:** Как DVN уменьшает delegated stake оператора?

**Вариант A (off-chain только):** DVN ведёт учёт в своих контрактах, vault.balances[operator] не меняется. Тогда:
- Оператор слэшнут DVN, но его vault balance не уменьшен
- Оператор может `unstake()` и получить полный баланс после slash
- **L9 нарушен по дизайну**

**Вариант B (через отдельный контракт):** Слэш-механизм в DVNCoordinator/DVNGateway которые не предоставлены для анализа. Если этот контракт имеет right вызывать `vault.withdraw()` — нарушает L2 (StakerGateway monopoly). Если идёт через StakerGateway — нужна отдельная авторизованная функция которой нет в текущем коде.

**Следующий тест:**
```bash
# Найти все функции в DVNCoordinator на mainnet
cast code 0x<DVNCoordinator_address> --rpc-url https://bsc-dataseed.binance.org
# Найти исторические slash events
cast logs \
  --address 0x<DVNCoordinator> \
  --sig "Slashed(address,uint256)" \
  --from-block 0 \
  --rpc-url https://bsc-dataseed.binance.org
```

---

### НАХОДКА 3 — stakeClisBNB: event vs vault credit расхождение

**Severity:** Low / Informational  
**Confidence:** Medium  

**Код:**
```solidity
// StakerGateway.sol:129-132
uint256 clisBNBAmount = IHelioProvider(helioProvider).provide{ value: msg.value }(address(vault));
vault.deposit(vaultBalance, msg.sender);  // кредитует balanceERC20() delta
emit AssetStaked(msg.sender, assetAddress, clisBNBAmount, referralId);  // репортит return value
```

**Расхождение:** vault кредитует `balanceERC20() - vaultBalanceBefore`, а event репортит `clisBNBAmount` (return value от HelioProvider). Если HelioProvider возвращает значение отличное от фактически отправленного на vault (rounding, fees), off-chain инструменты имеют неверный баланс пользователя.

**Impact:** Некорректный учёт в дашбордах, reward калькуляторах. Пользователи видят неверные суммы если инструменты используют event-data вместо прямого `balanceOf` запроса.

**Следующий тест:**
```bash
# Найти txhash stakeClisBNB на BSC
# Сравнить: AssetStaked.amount из logs vs vault.balanceOf(user) после tx
```

---

### НАХОДКА 4 — ERC20WithTranferTaxDemo mock имеет неверную FOT семантику

**Severity:** Low (test infrastructure, не production)  
**Confidence:** High  

**Код мока:**
```solidity
// test/mock/ERC20WithTranferTaxDemo.sol:23-31
function _update(address from, address to, uint256 value) internal override {
    uint256 taxAmount = _calculatePercentage(value, tax);
    value = value - taxAmount;
    ERC20._update(from, to, value);  // sender теряет (value-tax), не value!
}
```

**Реальный FOT behaviour:** sender всегда теряет полный `value`, receiver получает `value - fee`.

**Поведение мока:** sender теряет `value - tax` (меньше чем запрошено через `transferFrom`), receiver получает `value - tax`. Allowance при этом decremented на полный `value`.

**Эффект при unstake:** vault отправляет 90 токенов → vault теряет только 81 (не 90) → 9 токенов "застревают" в vault с нулевым владельцем. Тест для unstake с FOT токеном отсутствует.

**Риск:** Ложная уверенность, что FOT токены обрабатываются корректно при withdrawal. В production с реальным FOT токеном behaviour отличается, но vault balance conservation сохраняется (реальный FOT списывает полный amount с sender).

---

## Итоговая приоритизация

| # | Находка | Severity | Confidence | Reachability | Action |
|---|---|---|---|---|---|
| 1 | DVN slash layer absent | Critical potential | High (факт) | Unknown | Получить DVN contracts |
| 2 | Rebasing token yield trap | Medium | Medium | Depends on assets | Проверить каждый токен |
| 3 | stakeClisBNB event mismatch | Low | Medium | High | BSC trace check |
| 4 | FOT mock wrong semantics | Low | High | Test only | Fix test mock |

---

## Рекомендуемые следующие шаги

1. **Предоставить DVN layer для анализа** — DVNCoordinator, DVNGateway, slash mechanism. Это самый критичный пробел.

2. **Верифицировать тип каждого поддерживаемого токена:**
   - slisBNB — rebasing или exchange-rate?
   - BNBx — rebasing или exchange-rate?
   - asBNB — rebasing или exchange-rate?
   - Если хотя бы один rebasing → добавить sweep/recovery mechanism в vault.

3. **BSC trace stakeClisBNB** — сравнить AssetStaked event amount vs vault.balanceOf(user).

4. **Исправить ERC20WithTranferTaxDemo** — привести к стандартному FOT поведению, добавить тест для unstake с FOT токеном.

---

## Подтверждённые invariants (что точно работает)

- EVM atomicity защищает `stakeNative()` от stuck BNB при любом revert
- `onlyFromStakerGateway` корректно изолирует vault от прямого доступа
- Delta-balance accounting (`balanceERC20() - vaultBalanceBefore`) корректно обрабатывает fee-on-transfer токены при deposit
- Donation attacks на vault не влияют на `totalBalance` учёт и deposit limit
- `referralId` является pure event logging без side-effects
- `removeAsset()` не позволяет миграцию с непустым vault
- `canReceiveNativeTokens` флаг корректно защищает от прямых ETH-отправок на gateway
- Reentrancy защищена `nonReentrant` на всех внешних entry points
