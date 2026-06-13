# Pharos Network / TopNod — Security Audit Report
**Режим:** Black-box → Grey-box  
**Дата:** 2026-05-03  
**Цель:** Responsible disclosure  
**Аудитор:** Claude Sonnet 4.6 (AI-assisted, требует валидации человеком)

---

## Контрактная карта (Pharos Network, Chain ID 50002)

| Контракт | Адрес | Тип |
|----------|-------|-----|
| USDC | `0x8182BEF887361F3312D344e229160C389616b6F0` | ERC-20, mint=owner |
| LST | `0xBB6f0beF915a4baaF6818c11BFeb648041f70959` | ERC-20, mint=owner |
| PUSD | `0x61edDE0E4B97D878C14F5f5706309d4572550Afa` | Stablecoin, 1:1 USDC |
| sPUSD | `0xe1Fd27F4390DcBE165f4D60DBF821e4B9Bb02dEd` | ERC-4626 Vault |
| Operator | `0xc582Bc0317dbb0908203541971a358c44b1F3766` | RWA оператор |
| Eigen | `0xB377a2EeD7566Ac9fCb0BA673604F9BF875e2Bab` | Делегирование LST |
| LoanManager | `0x66F625B8c4c635af8b74ECe2d7eD0D58b4af3C3d` | Кредиты операторов |
| Staking | (src/staking/Staking.sol) | UUPS, PoS валидаторы |
| TransactionDeny | (src/blacklist/) | Blacklist реестр |
| RuleManager | (src/ruleManager/) | Правила протокола |
| ChainConfig | (src/chainConfig/) | Конфиг сети |

**Proxy pattern:** TransparentUpgradeableProxy (инфраструктура) + UUPS (Staking)  
**Аудиты:** Zellic (4 отчёта), OpenZeppelin (1), Exvul (1) — тексты не публичны  
**Внешние зависимости:** EigenLayer (restaking), Circle CCTP (мост USDC), Centrifuge (JTRSY/JAAA токены), Chainlink (оракул — партнёрство, статус развёртывания неизвестен)

---

## Архитектура yield-потока

```
Пользователь (USDC)
  → depositAndMint() → PUSD (1:1)
  → sPUSD.deposit() → sPUSD shares (ERC-4626)
      ↑ yield накапливается через pricePerShare
  
LoanManager
  → transferToOperator(PUSD) ← из sPUSD vault
  → Оператор инвестирует в RWA (JTRSY, MMF, облигации)
  → transferFromOperator(PUSD + доходность)
  
LST делегирование → Eigen.addDelegation()
  → Обеспечение для createLoan()
  → Кол. обеспечения: 1.5x, liquidation threshold: 120%
```

**pAlpha Vault (отдельно, на Ethereum):**  
USDC → Ethereum vault → JTRSY + MMF → 18% APY → вывод через CCTP

---

## ФАЗА 2–6: НАХОДКИ УЯЗВИМОСТЕЙ

---

### УЯЗВИМОСТЬ #1

**КРИТИЧНОСТЬ:** Критическая  
**ЗАГОЛОВОК:** Нет on-chain оракула RWA — yield полностью client-side симуляция

**МЕСТОНАХОЖДЕНИЕ:** src/rwa/ (не существует on-chain), pharosdotmoney/Pharos-Frontend страница 7  
**ВОЗДЕЙСТВИЕ:**  
Вся система доходности sPUSD vault строится на значениях, которые "выполняются на стороне клиента с использованием симулированных данных". Нет on-chain механизма проверки того, что реальный RWA-доход поступает в vault. Оператор может заявить о любой доходности без доказательства.  
Прямое следствие: `pricePerShare` sPUSD (ERC-4626) обновляется только через `transferFromOperator()` — функцию, которую вызывает оператор. Протокол верит оператору на слово.

**ВЕРОЯТНОСТЬ:** Гарантированно выполнимо при недобросовестном операторе.

**ДОКАЗАТЕЛЬСТВО КОНЦЕПЦИИ:**
```
1. Оператор A регистрируется (вetting отсутствует — см. #2)
2. Пользователи делегируют LST → оператор получает право на createLoan()
3. createLoan(PUSD_amount) → PUSD уходит к оператору
4. Оператор НЕ инвестирует в RWA — просто держит PUSD
5. Через 5400 секунд (90 мин) срок истекает
6. repayLoan() никогда не вызывается
7. slashLoan() теоретически возможен, но нет автоматизированного keeper
8. Убыток: весь PUSD объём займа = прямой ущерб sPUSD vault
```

**РЕКОМЕНДАЦИЯ:**
- Интегрировать Chainlink Price Feed on-chain для каждого RWA-актива  
- `transferFromOperator()` должна проверять: `returnedAmount >= principal + minYield(oracle_price)`  
- Добавить Proof-of-Reserve механизм (Chainlink PoR) для JTRSY/JAAA

**ССЫЛКИ:** Chainlink PoR, Compound Oracle Manipulation (2020), Euler Finance exploit (оракульная манипуляция)

---

### УЯЗВИМОСТЬ #2

**КРИТИЧНОСТЬ:** Критическая  
**ЗАГОЛОВОК:** Произвольная регистрация операторов без vetting + отсутствие лимитов делегирования

**МЕСТОНАХОЖДЕНИЕ:** Eigen contract (`0xB377a2EeD7566Ac9fCb0BA673604F9BF875e2Bab`), LoanManager  
**ВОЗДЕЙСТВИЕ:**  
Любой адрес может зарегистрироваться оператором. Нет ограничений на объём принимаемых делегирований.악意的ный оператор может:
1. Привлечь максимальный объём делегированного LST от пользователей
2. Создать займ на полную сумму доступного обеспечения
3. Исчезнуть с PUSD

Документация прямо говорит: "current implementation is a mock registration process that simulates a successful registration."

**ВЕРОЯТНОСТЬ:** Высокая при отсутствии governance и whitelist операторов.

**ДОКАЗАТЕЛЬСТВО КОНЦЕПЦИИ:**
```solidity
// Атакующий:
IEigen(EIGEN).registerOperator(); // без проверки
// Маркетинг → пользователи делегируют LST
IEigen(EIGEN).addDelegation(largeAmount); // нет максимума
// Займ:
ILoanManager(LOAN_MGR).createLoan(maxAmount);
// Вывод PUSD — rug pull
```

**РЕКОМЕНДАЦИЯ:**
- Whitelist операторов через on-chain governance (multisig + timelock)
- Ограничить максимальный объём займа на оператора
- Требовать stake от самого оператора как "skin in the game"
- Добавить минимальный период работы перед получением займов

**ССЫЛКИ:** EigenLayer Operator vetting, Maple Finance default incidents

---

### УЯЗВИМОСТЬ #3

**КРИТИЧНОСТЬ:** Критическая  
**ЗАГОЛОВОК:** Единственный `onlyOwner` без timelock и multisig на всех критических функциях

**МЕСТОНАХОЖДЕНИЕ:** PUSD, LST, USDC контракты; LoanManager; RuleManager  
**ВОЗДЕЙСТВИЕ:**  
Если ключ owner-адреса скомпрометирован или owner злонамерен — моментальный полный ущерб:

| Функция | Контракт | Последствие |
|---------|---------|-------------|
| `mint(uint256)` | USDC, LST | Бесконечная инфляция токенов |
| `setLoanManager(address)` | PUSD | Перенаправление всех PUSD-переводов |
| `setsPUSDAddress(address)` | PUSD | Замена vault на вредоносный контракт |
| `setEigenAddress(address)` | LST | Перехват делегирований |
| `updateBaseRate(uint256)` | LoanManager | Мгновенное изменение ставки 0%→100% |
| `setRoleAdmin(bytes32,bytes32)` | RuleManager | Захват всех ролей |
| `upgradeToAndCall()` | Staking (UUPS) | Замена реализации |

Нет timelock (24h+), нет multisig (3/5 минимум), нет on-chain governance.

**ВЕРОЯТНОСТЬ:** Средняя (требует компрометации owner-ключа или внутренней угрозы).

**ДОКАЗАТЕЛЬСТВО КОНЦЕПЦИИ:**
```
// Атака через скомпрометированный owner:
1. PUSD.setLoanManager(attacker_contract)
2. Вызов любой функции, которая триггерит transferToOperator()
3. attacker_contract получает все PUSD из sPUSD vault
4. Весь TVL протокола = потеря
```

**РЕКОМЕНДАЦИЯ:**
- Timelock минимум 48 часов на все setter-функции
- Multisig 3/5 на owner роль (Gnosis Safe — Pharos уже форкнул репозитории Safe)
- Разделить роли: owner (только upgrade) и operator (параметры)

---

### УЯЗВИМОСТЬ #4

**КРИТИЧНОСТЬ:** Высокая  
**ЗАГОЛОВОК:** ERC-4626 инфляционная атака (первый депозит) на sPUSD vault

**МЕСТОНАХОЖДЕНИЕ:** sPUSD contract (`0xe1Fd27F4390DcBE165f4D60DBF821e4B9Bb02dEd`)  
**ВОЗДЕЙСТВИЕ:**  
Классическая атака на ERC-4626: первый депозитор манипулирует `pricePerShare`, похищая средства последующих депозиторов.

**ВЕРОЯТНОСТЬ:** Высокая при запуске vault (требует только первого депозита).

**ДОКАЗАТЕЛЬСТВО КОНЦЕПЦИИ:**
```solidity
// Атакующий — первый депозитор:
1. deposit(1 wei PUSD) → получает 1 share
2. Прямой transfer(largeAmount PUSD) в vault (не через deposit)
   → totalAssets() растёт, totalSupply() = 1
   → pricePerShare = largeAmount
3. Жертва deposit(N PUSD):
   → shares = N * 1 / largeAmount → round down to 0
   → Жертва получает 0 shares, теряет N PUSD
4. Атакующий redeem(1 share) → забирает всё
```

**РЕКОМЕНДАЦИЯ:**
- Виртуальные shares (EIP-4626 рекомендация): добавить `10**decimalsOffset()` при инициализации
- Или: первый депозит из контракта в размере минимального `MINIMUM_DEPOSIT`
- Проверить использование OpenZeppelin ERC4626 с `_decimalsOffset`

**ССЫЛКИ:** EIP-4626 Security Considerations, OpenZeppelin ERC4626 decimals offset

---

### УЯЗВИМОСТЬ #5

**КРИТИЧНОСТЬ:** Высокая  
**ЗАГОЛОВОК:** UUPS кастомные override `_checkProxy()` / `_checkNotDelegated()` — риск захвата реализации

**МЕСТОНАХОЖДЕНИЕ:** `src/staking/Staking.sol`, функции `_checkProxy()` и `_checkNotDelegated()`  
**ВОЗДЕЙСТВИЕ:**  
Стандартный UUPS использует `_checkProxy()` чтобы убедиться, что `upgradeToAndCall()` вызывается через proxy (delegatecall), а не напрямую на implementation. Переопределение этих функций — нестандартная практика, открывающая риск:
- Прямой вызов `upgradeToAndCall()` на implementation-контракте
- Потенциальный selfdestruct implementation через `upgradeToAndCall(0xdead...)`
- После разрушения implementation — proxy становится нефункциональным навсегда

**ВЕРОЯТНОСТЬ:** Средняя (требует детального анализа кода реализации).

**ДОКАЗАТЕЛЬСТВО КОНЦЕПЦИИ:**
```
Если _checkProxy() содержит ошибку в логике:
1. Вызвать upgradeToAndCall() напрямую на implementation
2. Передать адрес вредоносного контракта или selfdestruct calldata
3. Implementation уничтожена → все proxy вызовы reverting
4. Весь стейкинг заморожен навсегда
```

**РЕКОМЕНДАЦИЯ:**
- Удалить кастомные override и использовать стандартный OpenZeppelin UUPS
- Либо добавить explicit invariant test: `testProxyCheckCannotBeCalledDirectly()`
- Провести отдельный аудит именно этих функций

**ССЫЛКИ:** UUPS Proxies (OZ), Audius Exploit (2022, UUPS initialization), Tornado Cash UUPS selfdestruct

---

### УЯЗВИМОСТЬ #6

**КРИТИЧНОСТЬ:** Высокая  
**ЗАГОЛОВОК:** TopNod: 8-digit PIN — слабая аутентификация для кошелька с RWA-активами

**МЕСТОНАХОЖДЕНИЕ:** TopNod mobile app, server-side shard verification  
**ВОЗДЕЙСТВИЕ:**  
Пространство PIN: 10^8 = 100,000,000 комбинаций. Для финансового приложения с потенциально $50M+ TVL — катастрофически мало.

Архитектура 3 шардов: mobile + TEE + enterprise server. Для реконструкции ключа нужны 2 шарда (либо 3 — неизвестно, 2-of-3 или 3-of-3).

**Сценарии атаки:**
1. **Сервер-стороны brute-force:** Если проверка PIN происходит сервером при реконструкции шарда — rate limiting критически важен. Отсутствие evidence о rate limiting.
2. **Компрометация enterprise-server + TEE:** 2 сервисных шарда = все пользовательские ключи. Инсайдерская угроза или supply-chain атака.
3. **Apple/Google OAuth phishing:** Первый фактор — социальный аккаунт. Если скомпрометирован — атакующий получает доступ к PIN-вводу.
4. **Отсутствие биометрии как обязательного фактора:** Документация не упоминает принудительное использование TouchID/FaceID.

**ВЕРОЯТНОСТЬ:** Средняя (требует векторы атаки на серверную инфраструктуру или социальную инженерию).

**РЕКОМЕНДАЦИЯ:**
- Минимум 12 символов или обязательная биометрия как второй фактор
- Rate limiting: max 5 PIN попыток, 30-минутная блокировка
- 3-of-3 схема вместо 2-of-3 для реконструкции
- Публичный аудит TEE-реализации
- Hardware security key поддержка (FIDO2) для старших аккаунтов

**ССЫЛКИ:** NIST SP 800-63B (PIN requirements), MPC Wallet Security

---

### УЯЗВИМОСТЬ #7

**КРИТИЧНОСТЬ:** Высокая  
**ЗАГОЛОВОК:** `TransactionDeny` blacklist может навсегда заморозить средства пользователей

**МЕСТОНАХОЖДЕНИЕ:** `src/blacklist/TransactionDeny.sol`, интеграция в токен-трансферы  
**ВОЗДЕЙСТВИЕ:**  
Owner может добавить любой адрес в blacklist. Если PUSD и sPUSD токены проверяют `isBlacklisted()` перед трансфером — blacklisted пользователь не может:
- Выводить PUSD из vault
- Продавать sPUSD на DEX
- Перемещать средства куда-либо

Это **постоянная заморозка средств** без судебного решения, без timelock, без права на обжалование в протоколе.

Дополнительно: `pause()` в TransactionDeny останавливает ИЗМЕНЕНИЯ blacklist, но не сам blacklist — замороженные адреса остаются заморожены.

**ВЕРОЯТНОСТЬ:** Высокая (единственный owner, нет governance, нет timelock).

**ДОКАЗАТЕЛЬСТВО КОНЦЕПЦИИ:**
```
1. owner вызывает addBlacklistedAddresses([victim_address])
2. Жертва пытается withdraw() из sPUSD
3. sPUSD.withdraw() → PUSD._transfer() → isBlacklisted(victim) == true → revert
4. Средства жертвы заморожены навсегда (или до решения owner)
```

**РЕКОМЕНДАЦИЯ:**
- Добавить timelock (72h+) на blacklisting
- Требовать on-chain governance (голосование токенхолдеров) для blacklist actions
- Реализовать "challenge period" — пользователь может оспорить в течение 48h
- Audit: убедиться, что blacklist не применяется к withdraw() — только к новым транзакциям

---

### УЯЗВИМОСТЬ #8

**КРИТИЧНОСТЬ:** Высокая  
**ЗАГОЛОВОК:** pAlpha Vault кросс-чейн: CCTP мост как единая точка отказа

**МЕСТОНАХОЖДЕНИЕ:** pAlpha Vault на Ethereum ↔ Pharos Network (Circle CCTP)  
**ВОЗДЕЙСТВИЕ:**  
pAlpha Vault хранит $50M+ USDC на Ethereum и инвестирует в JTRSY/MMF. Связь с Pharos через Circle CCTP.

**Риски:**
1. **CCTP attestation delay:** Финализация трансфера занимает минуты. В этот период атакующий может манипулировать состоянием vault на одной стороне.
2. **Replay через разные chainId:** Если домен-сепаратор CCTP не уникален для Pharos Network — возможна replay-атака сообщений.
3. **Зависимость от Circle availability:** CCTP downtime = невозможность вывода USDC из Ethereum vault на Pharos.
4. **MEV на attestation:** Frontrun получения USDC после CCTP attestation.

**ВЕРОЯТНОСТЬ:** Средняя для CCTP downtime; низкая для replay при корректной реализации.

**РЕКОМЕНДАЦИЯ:**
- Проверить chain ID в каждом CCTP сообщении
- Реализовать fallback механизм при CCTP downtime
- Установить withdrawal delay соответствующий CCTP finality
- Публичный аудит CCTP интеграции

---

### УЯЗВИМОСТЬ #9

**КРИТИЧНОСТЬ:** Высокая  
**ЗАГОЛОВОК:** Отсутствие timelock на изменение `baseInterestRate` и `ltvRatio` в LoanManager

**МЕСТОНАХОЖДЕНИЕ:** `LoanManager`, функции `updateBaseRate()`, `updateLTVRatio()`  
**ВОЗДЕЙСТВИЕ:**  
Admin может мгновенно изменить:
- `baseInterestRate` с 5% до 100% → ретроактивный долг для операторов с активными займами
- `ltvRatio` → изменение collateral requirements для существующих позиций

В отличие от традиционных lending протоколов (Aave, Compound — 48h+ timelock на rate changes), здесь нет никакой задержки.

**Сценарий:**
```
1. Admin повышает baseInterestRate до 50%
2. Активные займы операторов становятся нерентабельными
3. Операторы не успевают погасить → slashLoan() по всем позициям
4. Пользователи теряют делегированный LST
```

**РЕКОМЕНДАЦИЯ:**
- Timelock 48h на любые изменения rate/ratio
- Ограничить максимальное изменение за транзакцию (±2% за раз)
- Новые ставки применяются только к НОВЫМ займам, не к активным

---

### УЯЗВИМОСТЬ #10

**КРИТИЧНОСТЬ:** Высокая  
**ЗАГОЛОВОК:** Нет автоматического keeper для slashLoan() — операторы могут дефолтить безнаказанно

**МЕСТОНАХОЖДЕНИЕ:** `LoanManager.slashLoan()`, loan duration = 5400 секунд  
**ВОЗДЕЙСТВИЕ:**  
Срок займа: 5400 секунд (~90 минут). По истечении — `slashLoan()` теоретически выполнимо, но:
- Нет автоматического keeper/bot для вызова функции
- Нет incentive для внешних участников вызывать `slashLoan()`
- Оператор может просто не repay → средства зависают

Также: если LST цена упала ниже liquidation threshold (120%), нет on-chain механизма принудительной ликвидации.

**ДОКАЗАТЕЛЬСТВО КОНЦЕПЦИИ:**
```
1. createLoan(1,000,000 PUSD) с LST обеспечением
2. 5401 секунда → срок истёк
3. Никто не вызывает slashLoan() (нет incentive)
4. PUSD заморожен в операторе
5. sPUSD depositors не получают доходность
6. Если LST цена упала — underwater loan
```

**РЕКОМЕНДАЦИЯ:**
- Добавить liquidation bonus (5-10% от collateral) для третьих сторон
- Интегрировать on-chain Keeper (Chainlink Automation)
- Добавить автоматический slashing в `_advanceEpoch()` стейкинга

---

### УЯЗВИМОСТЬ #11

**КРИТИЧНОСТЬ:** Средняя  
**ЗАГОЛОВОК:** `migrateV1ToV2()` в TransactionDeny — нарушение целостности индекса при неправильном порядке

**МЕСТОНАХОЖДЕНИЕ:** `src/blacklist/TransactionDeny.sol`, функция `migrateV1ToV2()`  
**ВОЗДЕЙСТВИЕ:**  
Функция migration проверяет: `require(_blacklistedAddresses[idx] == account, "Index mismatch, run migrateV1ToV2")`. Если миграция вызвана не в правильный момент или дважды — индексы расходятся, функция `removeBlacklistedAddresses()` будет reverting для корректных записей, или удалять НЕПРАВИЛЬНЫЕ адреса из blacklist.

**РЕКОМЕНДАЦИЯ:**
- Добавить `onlyOwner` guard (уже есть) + флаг `migrationCompleted` аналогичный Staking.sol
- Добавить `require(!migrationCompleted, "Already migrated")`

---

### УЯЗВИМОСТЬ #12

**КРИТИЧНОСТЬ:** Средняя  
**ЗАГОЛОВОК:** RuleManager: `setRoleAdmin()` позволяет полный захват системы ролей

**МЕСТОНАХОЖДЕНИЕ:** `src/ruleManager/RuleManager.sol`, функция `setRoleAdmin(bytes32, bytes32)`  
**ВОЗДЕЙСТВИЕ:**  
`setRoleAdmin()` переназначает, кто управляет какой ролью. Если DEFAULT_ADMIN_ROLE скомпрометирована — атакующий может:
1. `setRoleAdmin(DEFAULT_ADMIN_ROLE, attacker_role)`
2. Стать единственным администратором всей системы правил
3. Добавить правила, блокирующие определённые функции или разрешающие новые

**РЕКОМЕНДАЦИЯ:**
- `setRoleAdmin()` должна быть защищена timelock или требовать multisig
- Рассмотреть неизменяемую иерархию ролей

---

### УЯЗВИМОСТЬ #13

**КРИТИЧНОСТЬ:** Средняя  
**ЗАГОЛОВОК:** Отсутствие unbonding period для LST делегирования — манипуляция collateral

**МЕСТОНАХОЖДЕНИЕ:** `Eigen contract`, функции `addDelegation()` / `removeDelegation()`  
**ВОЗДЕЙСТВИЕ:**  
Нет документированного unbonding period. Пользователь может:
1. Делегировать LST → оператор получает право на займ
2. Оператор создаёт максимальный займ
3. Делегатор мгновенно отзывает LST
4. Займ становится необеспеченным (undercollateralized)

В стандартных restaking протоколах unbonding period — минимум 7-21 день.

**РЕКОМЕНДАЦИЯ:**
- Ввести unbonding period ≥ loan duration + settlement buffer
- LST, обеспечивающий активный займ, нельзя undelegate до погашения

---

### УЯЗВИМОСТЬ #14

**КРИТИЧНОСТЬ:** Средняя  
**ЗАГОЛОВОК:** LST/USDC `mint()` доступен owner — возможна инфляционная атака на collateral

**МЕСТОНАХОЖДЕНИЕ:** USDC (`0x8182...`), LST (`0xBB6f...`), функции `mint()`  
**ВОЗДЕЙСТВИЕ:**  
Owner может минтить неограниченное количество LST. Это создаёт риск:
- Инфляция LST → обесценивание collateral операторов
- Owner может mint LST себе → createLoan() с большим займом → rug

Для USDC: `mintToPUSD()` позволяет создавать PUSD без реального USDC обеспечения.

**РЕКОМЕНДАЦИЯ:**
- Supply cap на mint функции
- Удалить централизованный mint для production — использовать только governance-controlled

---

## ФАЗА 6: ИНВАРИАНТЫ

| Инвариант | Статус | Обоснование |
|-----------|--------|-------------|
| `totalShares × pricePerShare == totalAssets` | **НЕОПРЕДЕЛЕНО** | ERC-4626 формально держит, но `transferToOperator()` выносит активы off-vault без соответствующего изменения `totalAssets` — возможен дрейф |
| Ни один пользователь не получает доходность сверх пропорциональной доли | **НЕОПРЕДЕЛЕНО** | Зависит от реализации `transferFromOperator()` — нет исходного кода |
| RWA коллатерал ≥ суммарные yield-обязательства | **НАРУШЕН** | Нет on-chain оракула для верификации (#1). Неизвестно |
| Непривилегированный адрес не меняет global yield rate | **ВЫПОЛНЕН** | `onlyOwner` на `updateBaseRate()` — но owner сам и есть риск |
| Вывод всегда возможен для погашенных позиций | **НЕОПРЕДЕЛЕНО** | Blacklist + pause могут блокировать (#7) |
| EIP-712 nonces строго монотонны | **НЕОПРЕДЕЛЕНО** | Нет исходного кода wallet-контракта |
| Session key права проверяются on-chain | **НЕОПРЕДЕЛЕНО** | TopNod не публикует детали session key |
| Цена оракула не манипулируется в одном блоке | **НАРУШЕН** | Оракула нет (#1) |

---

## СВОДНАЯ ТАБЛИЦА РИСКОВ

| # | Критичность | Заголовок | Вектор |
|---|-------------|-----------|--------|
| 1 | 🔴 Критическая | Нет on-chain RWA оракула | Экономический |
| 2 | 🔴 Критическая | Произвольная регистрация операторов | Доступ |
| 3 | 🔴 Критическая | Единственный owner без timelock | Централизация |
| 4 | 🟠 Высокая | ERC-4626 инфляционная атака | Экономический |
| 5 | 🟠 Высокая | UUPS кастомные override | Контракт |
| 6 | 🟠 Высокая | 8-digit PIN аутентификация | Кошелёк |
| 7 | 🟠 Высокая | Blacklist заморозка средств | Доступ |
| 8 | 🟠 Высокая | CCTP кросс-чейн риски | Инфраструктура |
| 9 | 🟠 Высокая | Нет timelock на rate changes | Централизация |
| 10 | 🟠 Высокая | Нет keeper для liquidation | Механика |
| 11 | 🟡 Средняя | migrateV1ToV2 blacklist индекс | Контракт |
| 12 | 🟡 Средняя | RuleManager setRoleAdmin захват | Доступ |
| 13 | 🟡 Средняя | Нет unbonding period | Механика |
| 14 | 🟡 Средняя | Централизованный LST/USDC mint | Централизация |

---

## ПРИОРИТЕТ RESPONSIBLE DISCLOSURE

**Немедленно (до активных пользователей с реальными средствами):**
1. #1 — Нет оракула (системный риск всего TVL)
2. #3 — Отсутствие multisig/timelock
3. #2 — Оператор vetting

**До mainnet:**
4. #4 — ERC-4626 инфляция (один блок атака при запуске)
5. #5 — UUPS проверка
6. #7 — Blacklist механизм

**До TopNod production release:**
7. #6 — PIN аутентификация
8. Запросить публичный аудит TEE реализации

---

## ОГРАНИЧЕНИЯ АУДИТА

Этот отчёт основан на:
- Публично доступном frontend коде (pharosdotmoney/Pharos-Frontend)
- Инфраструктурных контрактах (PharosNetwork/contracts)
- DeepWiki документации
- Публичных блог-постах и пресс-релизах
- Адресах контрактов на pharosscan.xyz

**НЕ ДОСТУПНО:** Исходный код sPUSD, PUSD, LoanManager, Eigen (не верифицированы на explorer или не в публичном репозитории). Тексты аудитов Zellic/OpenZeppelin/Exvul (только PDF, недоступны через web scraping).

**Обязательно для подтверждения:** Ручная проверка bytecode через Tenderly/4byte, получение верифицированного исходного кода контрактов напрямую от команды Pharos.

---

*Отчёт подготовлен для responsible disclosure. Перед публикацией — уведомить команду Pharos Network и TopNod с 90-дневным disclosure window согласно стандарту Google Project Zero.*
