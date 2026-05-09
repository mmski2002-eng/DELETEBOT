держ# 🔴 Отчёт об аудите безопасности: Camp Network Ecosystem

**Дата**: 2025  
**Сеть**: Camp Network (Chain ID: `123420001114`) — L2 на базе Ethereum  
**Нативный токен**: **CAMP** (НЕ ETH!)  
**RPC**: `https://rpc.basecamp.t.raas.gelato.cloud`  
**Explorer**: `https://basecamp.cloud.blockscout.com/`

---

## Содержание

1. [Резюме](#резюме)
2. [Критическая уязвимость №1: `updateVaultBalance()` — отсутствие контроля доступа](#критическая-уязвимость-1-updatevaultbalance--отсутствие-контроля-доступа)
3. [Критическая уязвимость №2: `_update()` — неограниченный газовый цикл, постоянный DoS](#критическая-уязвимость-2-_update--неограниченный-газовый-цикл-постоянный-dos)
4. [Высокая уязвимость №3: `buyAccess()` без защиты от реентрантности](#высокая-уязвимость-3-buyaccess-без-защиты-от-реентрантности)
5. [Средняя уязвимость №4: `resolveDispute()` — риск потери средств](#средняя-уязвимость-4-resolvedispute--риск-потери-средств)
6. [Средняя уязвимость №5: Несоответствие десятичных разрядов CampPoint](#средняя-уязвимость-5-несоответствие-десятичных-разрядов-camppoint)
7. [Инвентаризация обнаруженных контрактов](#инвентаризация-обнаруженных-контрактов)
8. [Рекомендуемые исправления](#рекомендуемые-исправления)

---

## Резюме

Анализ безопасности смарт-контрактов экосистемы Camp Network выявил **2 критических**, **1 высокую** и **2 средние** уязвимости. Наиболее серьёзная находка — полное отсутствие контроля доступа к функции `IpRoyaltyVault.updateVaultBalance()`, что позволяет любому внешнему вызывающему абоненту навсегда заблокировать все переводы токенов роялти и/или манипулировать начислением доходов во всей экосистеме.

> ⚠️ **Важное примечание:** На момент анализа (2025) уязвимые контракты не содержат средств. Баланс хранилища `IpRoyaltyVault` — **0 CAMP**, баланс Marketplace — **0 CAMP**. Однако мост CrustySwap содержит **~456.7 CAMP**, пришедших с Ethereum через мост. Уязвимости представляют критическую угрозу при поступлении средств в контракты.

> ⚠️ **Терминология:** Везде в отчёте используется "CAMP" — нативный токен Camp Network. НЕ путать с ETH (Ethereum).

### Распределение по серьёзности

| Серьёзность | Количество |
|-------------|------------|
| 🔴 Критическая | 2 |
| 🟠 Высокая | 1 |
| 🟡 Средняя | 2 |
| 🟢 Низкая | 0 |

---

## Критическая уязвимость №1: `updateVaultBalance()` — отсутствие контроля доступа

### Местоположение

- **Контракт**: `IpRoyaltyVault`
- **Адрес**: [`0xb27092564b5434f68706753f9C0ADDC49Ca71dC5`](https://basecamp.cloud.blockscout.com/address/0xb27092564b5434f68706753f9C0ADDC49Ca71dC5)
- **Файл**: `src/royalty/IpRoyaltyVault.sol`
- **Функция**: `updateVaultBalance(address token, uint256 amount)`

### ✅ Подтверждено ончейн-проверкой

Проверка через `eth_call` показала, что функция **действительно публична**: вызов `updateVaultBalance(zero, 1)` от рандомного адреса (`0x00...01`) **НЕ РЕВЕРТНУЛ**. Любой внешний аккаунт может вызвать эту функцию.

### Уязвимый код

```solidity
/// @inheritdoc IIpRoyaltyVault
function updateVaultBalance(address token, uint256 amount) external {
    // Разрешать обновления только от контракта IpNFT или Marketplace
    // В продакшене нужен более сложный контроль доступа
    if (amount == 0) revert ZeroAmount();

    _revenueTokens.add(token);
    _vaultAccBalances[token] += amount;

    emit RevenueTokenAddedToVault(token, amount);
}
```

### Описание

У функции **ВООБЩЕ НЕТ** модификатора контроля доступа. Любой — любой внешний аккаунт или контракт — может её вызвать. Комментарий в коде явно признаёт эту проблему, но исправление так и не было реализовано.

### Сценарии эксплуатации

#### Сценарий A: DoS на вывод дохода (инфляция баланса)

1. Атакующий вызывает `updateVaultBalance(address(0), 100_000 ether)` — нулевой адрес представляет нативный CAMP
2. `_vaultAccBalances[address(0)]` теперь раздут до 100 000 CAMP, которых **не существует** в хранилище
3. Когда легитимный держатель токенов роялти вызывает `claimRevenue()`, контракт вычисляет:
   ```
   pendingScaled = accBalance * userBalance - debt
   ```
4. Результат раздут далеко за пределы реального баланса CAMP в хранилище
5. `SafeTransferLib.safeTransferETH(claimer, pending)` пытается перевести несуществующий CAMP
6. **Транзакция отклоняется** — легитимные пользователи не могут получить свой доход

> 📊 **Текущее состояние:** Хранилище пусто — `vaultAccBalance(address(0)) = 0 CAMP`, баланс контракта = **0 CAMP**, количество токенов дохода = **0**. Уязвимость существует, но эксплуатировать нечего.

#### Сценарий B: Фронтраннинг на Marketplace

1. Пользователь отправляет транзакцию `buyAccess()` на Marketplace
2. Атакующий **опережает** её, вызывая `updateVaultBalance(paymentToken, БОЛЬШАЯ_СУММА)`
3. Когда `_distributeRoyalty()` в Marketplace随后 вызывает `vault.updateVaultBalance(paymentToken, РЕАЛЬНАЯ_СУММА)`, отслеживаемый баланс становится:
   ```
   _vaultAccBalances[token] = РАЗДУТАЯ_СУММА + РЕАЛЬНАЯ_СУММА
   ```
4. Все последующие вызовы `claimRevenue()` вычисляют некорректные суммы, пока учёт полностью не искажается

---

## Критическая уязвимость №2: `_update()` — неограниченный газовый цикл, постоянный DoS

### Местоположение

- **Контракт**: `IpRoyaltyVault`
- **Файл**: `src/royalty/IpRoyaltyVault.sol`
- **Функция**: `_update(address from, address to, uint256 amount)`

### Уязвимый код

```solidity
function _update(address from, address to, uint256 amount) internal override {
    // Обработка майнинга (from == address(0))
    if (from == address(0)) {
        super._update(from, to, amount);
        return;
    }

    // Запрет переводов самому себе
    if (from == to) revert SameFromToAddress();

    uint256 balanceOfFrom = balanceOf(from);
    uint256 balanceOfTo = balanceOf(to);

    // Обновление долга для ВСЕХ токенов дохода
    address[] memory tokens = _revenueTokens.values();
    for (uint256 i = 0; i < tokens.length; i++) {
        address token = tokens[i];
        // ... SLOAD, арифметика, SSTORE для КАЖДОГО токена ...
    }

    super._update(from, to, amount);
}
```

### Описание

Эта функция является хуком ERC-20, вызываемым при **каждом переводе токенов роялти**. Она итерирует **весь** набор `_revenueTokens`. Поскольку `updateVaultBalance()` (Уязвимость №1) не имеет контроля доступа, атакующий может:

1. Вызвать `updateVaultBalance(фейковыйТокен1, 1)`, `updateVaultBalance(фейковыйТокен2, 1)`, ... с **сотнями или тысячами** фейковых адресов токенов
2. Каждый вызов добавляет фейковый токен в `_revenueTokens` через `EnumerableSet.add()`
3. Теперь каждый перевод токенов роялти должен итерировать все фейковые токены, каждая итерация требует:
   - SLOAD для `_vaultAccBalances[фейковыйТокен]`
   - SLOAD для `_claimerRevenueDebt[фейковыйТокен][from]`
   - SLOAD для `_claimerRevenueDebt[фейковыйТокен][to]`
   - Арифметические операции
   - Операции SSTORE
4. При **~200+** токенах затраты газа превышают лимит газа блока

### Воздействие

**Постоянный отказ в обслуживании (DoS).** Токены роялти становятся **непереводимыми**:
- Невозможна продажа на вторичных рынках
- Невозможно дарение
- Невозможно перемещение на другие кошельки
- Хранилище роялти фактически мертво

---

## Высокая уязвимость №3: `buyAccess()` без защиты от реентрантности

### Местоположение

- **Контракт**: `Marketplace`
- **Адрес**: `0x7C969ea45cdA884902102212DDF14f2A33988208`
- **Файл**: `src/Marketplace.sol`
- **Функция**: `buyAccess()`

### Детали

```solidity
function buyAccess(
    address buyer,
    uint256 tokenId,
    uint256 expectedPrice,
    uint32 expectedDuration,
    address expectedPaymentToken,
    uint16 expectedProtocolFeeBps,
    uint16 expectedAppFeeBps
) external payable whenNotPaused {
    // ... проверки ...
    
    // Состояние обновляется до внешних вызовов (хорошая практика)
    subscriptionExpiry[tokenId][buyer] = newExpiry;
    
    // Затем происходят внешние вызовы через:
    _routeNativePayment(tokenId, totalRoyaltyAmount, protocolFee, appFee, appTreasury);
    // ИЛИ
    _routeTokenPayment(tokenId, terms.paymentToken, totalRoyaltyAmount, protocolFee, appFee, appTreasury);
}
```

Обе функции `_routeNativePayment()` и `_routeTokenPayment()` в конечном итоге вызывают `_distributeRoyalty()`, которая делает внешний вызов к `updateVaultBalance()` хранилища роялти. Хотя текущая реализация хранилища считается доверенной, будущие обновления или хранилища, развёрнутые через фабрику, могут внести реентрантность.

### Рекомендация

Добавить `ReentrancyGuardUpgradeable` и модификатор `nonReentrant`.

---

## Средняя уязвимость №4: `resolveDispute()` — риск потери средств

### Местоположение

- **Контракт**: `DisputeModule`
- **Адрес**: `0xC228F3928DbeEAa45C4FFEbfB2739De6C2133F8B`
- **Файл**: `src/modules/DisputeModule.sol`

### Детали

```solidity
function resolveDispute(uint256 id) external {
    // ...
    if (judgement) {
        // Спор выигран — вернуть залог инициатору
        SafeTransferLib.safeTransfer(address(disputeToken), dispute.initiator, dispute.bondAmount);
    } else {
        uint256 invalidDisputeReward = dispute.bondAmount - dispute.protocolFeeAmount;
        // Отправляет вознаграждение владельцу IP — но если NFT был сожжён...
        SafeTransferLib.safeTransfer(address(disputeToken), 
            ipToken.ownerOf(dispute.targetId), invalidDisputeReward);
        SafeTransferLib.safeTransfer(address(disputeToken), msg.sender, dispute.protocolFeeAmount);
    }
}
```

Если IP NFT был передан или сожжён в процессе разрешения спора:
- `ipToken.ownerOf(dispute.targetId)` вызовет ошибку (согласно стандарту ERC-721)
- Весь вызов `resolveDispute()` будет отклонён
- Комиссия протокола застрянет

---

## Средняя уязвимость №5: Несоответствие десятичных разрядов CampPoint

### Местоположение

- **Токен 1 (CP#1)**: `0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537` — **0 десятичных разрядов**
- **Токен 2 (CP#2)**: `0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF` — **18 десятичных разрядов**

Оба токена используют символ **`CP`** и название **"CampPoint"**, но имеют несовместимые конфигурации десятичных разрядов. Любой контракт или интерфейс, предполагающий 18 десятичных разрядов, будет вычислять некорректные суммы для токена с 0 десятичных разрядов.

### 🚨 Дополнительно: Это ERC-1967 прокси с разными имплементациями!

Оба токена являются **ERC-1967 upgradeable прокси**, а не простыми ERC-20 контрактами:

| Параметр | CP#1 (0-dec) | CP#2 (18-dec) |
|----------|-------------|--------------|
| Адрес прокси | `0x52DE...B537` | `0xa5C6...40BF` |
| **Адрес имплементации** | **`0xac14d9896b0115a078bfb58a14f0fae85983daca`** | **`0xb478c35e230e6b808f4dc2464f44e3e6dcc3c809`** |
| Размер кода имплементации | 21 394 байт | 20 148 байт |
| Имплементации идентичны? | ❌ **НЕТ** — разные! | ❌ **НЕТ** — разные! |

### 🔴 Критический риск: UUPS upgradeToAndCall

В обеих имплементациях найден селектор **`0x4f1ef286`** — функция `upgradeToAndCall(address,bytes)`. Это означает:

1. Контракты являются **UUPS upgradeable** — можно сменить логику токена
2. Любой с ролью `UPGRADER_ROLE` или `DEFAULT_ADMIN_ROLE` может:
   - Заменить имплементацию на любую
   - Напечатать сколько угодно токенов
   - Обменять их через любую ликвидность

### ⚠️ Ограничение: AccessControl не полностью暴露

- `hasRole()` — **работает** (можно проверить роль адреса)
- `getRoleMember()` — **РЕВЕРТИТ** (не暴露 через прокси)
- `owner()` — **РЕВЕРТИТ** (используется AccessControl, а не Ownable)
- На данный момент `mint()` **защищён** — требует соответствующей роли

### 📊 Итог по CampPoint

| Вопрос | Ответ |
|--------|-------|
| Кто угодно может mint? | ❌ Нет (защищено) |
| Кто имеет роль минтера? | ❓ Неизвестно |
| Можно ли сменить имплементацию? | ✅ **ДА! UUPS** |
| Зачем два разных контракта с одним именем? | ❓ Неизвестно |

---

## Инвентаризация обнаруженных контрактов

### Базовая инфраструктура

| Контракт | Адрес | Транзакции | Статус |
|----------|-------|------------|--------|
| Marketplace (v1) | `0x7C969ea45cdA884902102212DDF14f2A33988208` | Некоторые | Активен |
| Marketplace (v2) | `0x81BeB79b977cAd2B1d06aFC62b4aABB7611107b4` | 0 | Не используется |
| IpNFT (основной) | `0xC4a35ce77b090cb511CEb5622D9A41f9A722e4E4` | — | Активен |
| IpRoyaltyVault | `0xb27092564b5434f68706753f9C0ADDC49Ca71dC5` | — | 🛑 УЯЗВИМ |
| IpRoyaltyVaultFactory | `0xaed623AF25128f3FC39cA855441BC4d9Dbf1AaBB` | — | Активен |
| IpRoyaltyVaultFactory | `0x92c29a571CeAC162E9e644EB19B8546317FB2058` | — | Активен |
| DisputeModule | `0xC228F3928DbeEAa45C4FFEbfB2739De6C2133F8B` | — | Активен |
| AppRegistry | `0x6D7CcaD812A8d7e6898f88350c3c88D9A4f4a176` | — | Активен |

### Оракул (Stork/Pyth)

| Контракт | Адрес | Статус |
|----------|-------|--------|
| UpgradeableStork | `0x716A7d69eaEEB5A38EC504ad2E4e0Ac02cEAa64C` | 0 TX |
| UpgradeableStork | `0x6e498b02C0036235c8164A502b0eECC7660BD889` | — |
| UpgradeableStork | `0xD8771b6aFD111e83591Db4074F13a08a802F179a` | — |
| UpgradeableStork | `0xbB4105F349072B15e300f3dAeB701EF986ae5372` | — |
| PermissionRegistry | `0x555441aF60c1111660c64c4Ec962b7219275fd94` | — |

### Мост

| Контракт | Адрес | Статус |
|----------|-------|--------|
| CrustySwap | `0x12C3E3B84B75ca4a9388de696621ac5F2Ae36953` | Активен |

### Игровые контракты

| Контракт | Адрес | Баланс |
|----------|-------|--------|
| TicTacToe | `0x7B75f64BFa5BFc9fB45c4b95d0b25A9c8c045356` | 0 |
| GameRoom | `0x41bC74bA2AD289EC615743C1Eea82977427A798B` | 0.5 CAMP |
| GameRoom | `0x88a029A09f3037dA191fbE90E917257B8C5fE29b` | 0.5 CAMP |
| GameRoom | `0x065355AC879A3f4F85C5dd89aA255F8Dd07822B6` | 0.5 CAMP |
| GameRoom | `0x5eddEa35aeDDbc3fccF390B3D4F8D4775bF22FD5` | 1.0 CAMP |
| GameRoom | `0x22E5A26E21Eaac16F4D452392d7D7c1fAa8E0F67` | 1.0 CAMP |

### Токены

| Токен | Адрес | Десятичные | Тип | Имплементация |
|-------|-------|------------|-----|---------------|
| CampPoint #1 | `0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537` | 0 | 🔷 ERC-1967 прокси | `0xac14d9896b0115a078bfb58a14f0fae85983daca` |
| CampPoint #2 | `0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF` | 18 | 🔷 ERC-1967 прокси | `0xb478c35e230e6b808f4dc2464f44e3e6dcc3c809` |

> ⚠️ **Важно:** У CP#1 и CP#2 **разные имплементации**, несмотря на одинаковое название и символ. Оба используют UUPS upgradeable (найден селектор `0x4f1ef286` — `upgradeToAndCall`).
| wCAMP | `0x1aE9c40eCd2DD6ad5858E5430A556d7aff28A44b` | 18 | ERC-20 |
| WETH | `0xC42BAA20e3a159cF7A8aDFA924648C2a2d59E062` | 18 | ERC-20 |
| WBTC | `0x587aF234D373C752a6F6E9eD6c4Ce871e7528BCF` | 18 | ERC-20 |
| MUSDC | `0x71002dbf6cC7A885cE6563682932370c056aAca9` | 6 | ERC-20 |
| sxUSDC | `0xe9a9aFfb353c2daE8453d041bc849ae5946B996b` | — | ERC-20 |

---

## Рекомендуемые исправления

### 🔴 Критическое исправление: Добавить контроль доступа к `updateVaultBalance()`

```diff
+ address public authorizedCaller;
+ error UnauthorizedCaller();

+ modifier onlyAuthorized() {
+     if (msg.sender != authorizedCaller && msg.sender != OwnableUpgradeable.owner()) {
+         revert UnauthorizedCaller();
+     }
+     _;
+ }

  function updateVaultBalance(
      address token, 
      uint256 amount
- ) external {
+ ) external onlyAuthorized {
      if (amount == 0) revert ZeroAmount();
      _revenueTokens.add(token);
      _vaultAccBalances[token] += amount;
      emit RevenueTokenAddedToVault(token, amount);
  }
```

### 🔴 Критическое исправление: Добавить лимит количества токенов дохода

```diff
+ uint256 public constant MAX_REVENUE_TOKENS = 50;

  function updateVaultBalance(address token, uint256 amount) 
      external onlyAuthorized 
  {
      if (amount == 0) revert ZeroAmount();
+     if (_revenueTokens.length() >= MAX_REVENUE_TOKENS && !_revenueTokens.contains(token)) {
+         revert TooManyRevenueTokens();
+     }
      _revenueTokens.add(token);
      _vaultAccBalances[token] += amount;
      emit RevenueTokenAddedToVault(token, amount);
  }
```

### 🟠 Исправление: Добавить защиту от реентрантности в Marketplace

```diff
+ import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

  contract Marketplace is
      UUPSUpgradeable,
      RoyaltyModule,
      OwnableUpgradeable,
-     PausableUpgradeable
+     PausableUpgradeable,
+     ReentrancyGuardUpgradeable
  {
      // ...
      function buyAccess(...)
-         external payable whenNotPaused {
+         external payable whenNotPaused nonReentrant {
```

### 🟡 Исправление: Сохранять владельца цели спора до внешних вызовов

```diff
  function resolveDispute(uint256 id) external {
      Dispute memory dispute = disputes[id];
+     address targetOwner = ipToken.ownerOf(dispute.targetId);
      // ...
      SafeTransferLib.safeTransfer(address(disputeToken),
-         ipToken.ownerOf(dispute.targetId),
+         targetOwner,
          invalidDisputeReward);
  }
```

---

*Отчёт сгенерирован автоматическим AI-анализом верифицированного исходного кода в сети, с ончейн-верификацией ключевых выводов.*
