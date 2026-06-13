# Исследовательские заметки

Этот файл отделяет гипотезы и открытые вопросы от черновика responsible disclosure. Ничего из этого файла нельзя представлять как подтверждённую уязвимость, пока не обновлена матрица доказательств.

## Ограничения источников

`REPORT.md` указывает, что исходный код `sPUSD`, `PUSD`, `LoanManager`, `Eigen` недоступен или не верифицирован, а PDF-аудиты Zellic, OpenZeppelin и Exvul не доступны публично. Это ограничение определяет confidence level большинства утверждений.

## Наиболее ценные гипотезы

### H-001: RWA yield accounting может быть trust-based

Вопрос: Проверяет ли протокол RWA yield on-chain, или оператор/admin вручную сообщает returned value?

Нужные доказательства:

- Реализация `LoanManager.transferFromOperator()`.
- Реализация `sPUSD.totalAssets()`.
- Любые вызовы oracle, proof-of-reserve, NAV или pricing contracts.
- Events, показывающие loan creation, operator repayment и изменения vault accounting.

Потенциальное влияние при подтверждении: некорректный или доверительный yield accounting может привести к bad debt, mispriced shares или unbacked returns.

### H-002: Регистрация операторов может быть permissionless

Вопрос: Может ли произвольный адрес стать оператором и занимать под делегированный LST?

Нужные доказательства:

- Access control в `Eigen.registerOperator()`.
- Проверки delegation cap.
- Borrow limits для оператора.
- Любой whitelist/governance path.

Потенциальное влияние при подтверждении: злонамеренные операторы могут привлечь delegation и занять value из vault.

### H-003: Критические admin-функции могут не иметь delayed governance

Вопрос: Owners и role admins являются EOA, multisig, timelock или governance contracts?

Нужные доказательства:

- Чтение `owner()` и roles.
- EIP-1967 proxy admin и implementation slots.
- Классификация bytecode admin-адресов.
- Setter functions и их access modifiers.

Потенциальное влияние при подтверждении: компрометация admin key может стать immediate protocol compromise.

### H-004: sPUSD может быть уязвим к ERC-4626 initial-deposit inflation

Вопрос: Использует ли `sPUSD` virtual shares/assets или эквивалентную защиту?

Нужные доказательства:

- Source ERC-4626 implementation.
- Поведение `_decimalsOffset()`, если используется OpenZeppelin.
- Поведение `previewDeposit()` после direct asset donation.
- Initial seed/dead shares configuration.

Потенциальное влияние при подтверждении: первый depositor может манипулировать share price и украсть средства следующих depositors.

### H-005: Blacklist может блокировать вывод существующих средств

Вопрос: Применяется ли `TransactionDeny` к vault exits или только к отдельным token transfers?

Нужные доказательства:

- Transfer hooks PUSD/sPUSD.
- Traces `withdraw()` / `redeem()`.
- Blacklist admin process и unblacklist path.
- Emergency escape или appeal mechanism.

Потенциальное влияние при подтверждении: user funds могут быть frozen admin action.

### H-006: Liquidation займов может зависеть от off-chain action

Вопрос: Какие гарантии обеспечивают slashing просроченных или undercollateralized loans?

Нужные доказательства:

- Access control `slashLoan()`.
- Liquidation incentives.
- Keeper/automation contract или documented bot.
- Historical calls liquidation functions.

Потенциальное влияние при подтверждении: defaults могут оставаться unresolved, а losses могут накапливаться.

### H-007: TopNod PIN threat model неполон

Вопрос: Защищён ли 8-значный PIN строгим rate limiting, device binding, TEE policy и shard threshold controls?

Известный факт:

- 8-значный numeric PIN имеет 100,000,000 комбинаций.

Нужные доказательства:

- Rate limiting и lockout policy.
- Является ли reconstruction схемой 2-of-3 или 3-of-3.
- TEE attestation и enclave audit.
- Обязательная biometric/second factor policy.

Потенциальное влияние при подтверждении слабых controls: wallet recovery или signing flow может быть уязвим к online guessing или infrastructure compromise.

## Формулировки из исходного отчёта, которые нужно заменить

Следующие фразы нельзя использовать до доказательства:

- "Гарантированно выполнимо"
- "Полностью client-side"
- "Любой адрес может"
- "Нет timelock"
- "Навсегда заморозить"
- "Катастрофически мало"
- "Весь TVL = потеря"

Использовать evidence-bound формулировки:

- "Если подтвердится..."
- "Доступные публичные материалы не устанавливают..."
- "Отчёт не смог верифицировать..."
- "Требуется проверка исходников или bytecode..."
- "Потенциальное влияние..."

## Предлагаемый тон первичного обращения

Первое сообщение команде лучше формулировать так:

"Мы выявили несколько потенциально значимых областей риска, которые требуют валидации, поскольку исходный код соответствующих deployed contracts публично не верифицирован. Сейчас мы не рассматриваем эти пункты как подтверждённые уязвимости. Хотели бы скоординироваться с вашей командой и проверить предположения до подготовки публичного отчёта."

## Следующая очередь работ

1. Создать read-only verification scripts для deployed bytecode, proxy slots, owners и role admins.
2. Попробовать восстановить ABI по selectors и публичным explorers.
3. Переносить source-confirmed issues в `DISCLOSURE.md`.
4. Держать TopNod и CCTP как design-risk questions, пока не появится конкретное implementation evidence.
