# Матрица доказательств

Этот файл отслеживает, какие утверждения из `REPORT.md` доказаны, какие остаются гипотезами, а какие лучше рассматривать как дизайн-риски. По умолчанию статус консервативный: если отсутствует исходный код ключевого контракта или bytecode-доказательство, утверждение не считается подтверждённым.

## Легенда статусов

| Статус | Значение |
|---|---|
| `Подтверждено` | Доказано исходным кодом, bytecode, trace транзакции, чтением storage или воспроизводимым PoC. |
| `Вероятно` | Есть сильные доказательства, но отсутствует хотя бы один обязательный артефакт. |
| `Не подтверждено` | Правдоподобно, но не доказано доступными материалами. |
| `Дизайн-риск` | Валидный архитектурный или операционный риск без доказанной exploitability. |
| `Опровергнуто` | Доказательства опровергают исходное утверждение. |

## Матрица

| ID | Утверждение | Текущий статус | Текущие доказательства | Чего не хватает | Как проверить | Как подавать в disclosure |
|---|---|---|---|---|---|---|
| #1 | Нет on-chain RWA oracle; yield является client-side simulation. | `Не подтверждено` | Отчёт ссылается на frontend/docs и отсутствие `src/rwa/`. | Исходники/bytecode `sPUSD`, `LoanManager`, oracle-интеграции, `transferFromOperator()`, `totalAssets()`. | Изучить verified source или decompile bytecode; перечислить external calls/selectors; проверить traces yield update транзакций. | Не утверждать как подтверждённое. Запросить у команды описание yield accounting и oracle/proof-механизма. |
| #2 | Любой адрес может зарегистрироваться оператором; нет delegation caps. | `Не подтверждено` | Отчёт цитирует документацию, где registration назван mock. | Access control в `Eigen.registerOperator()`, storage delegation caps, borrow cap logic в `LoanManager.createLoan()`. | Проверить ABI/source/bytecode; безопасно симулировать/read-only call от произвольного адреса; изучить events. | Формулировать как запрос на валидацию до подтверждения. |
| #3 | Один `onlyOwner` без timelock/multisig контролирует критические функции. | `Не подтверждено` | Отчёт перечисляет предполагаемые setters и owner powers. | Фактические owners/admins, proxy admin, role admin addresses, тип адресов: EOA/Safe/Timelock. | Прочитать EIP-1967 slots, `owner()`, `getRoleAdmin()`, bytecode Safe/timelock; проверить access control setter-функций. | Высокий приоритет проверки; не утверждать single EOA до доказательства. |
| #4 | `sPUSD` уязвим к ERC-4626 first-deposit inflation. | `Не подтверждено` | Описан общий сценарий атаки на ERC-4626. | Реализация `sPUSD`, `_decimalsOffset`, virtual shares/assets, dead shares, initial seed, `previewDeposit()`. | Проверить source/bytecode; запустить fork/local test: first deposit + donation + victim deposit. | Держать как гипотезу; повышать статус только после PoC. |
| #5 | Кастомные `_checkProxy()` / `_checkNotDelegated()` в Staking UUPS позволяют takeover/destruction implementation. | `Не подтверждено` | Отчёт утверждает наличие custom overrides и описывает условный риск. | Тела функций, состояние initializer, upgrade authorization, implementation address, версии Solidity/OZ. | Изучить `src/staking/Staking.sol`; написать тесты на direct implementation calls и upgrade authorization. | Рассматривать как цель code review, не как finding, пока не показана ошибка логики. |
| #6 | 8-значный PIN TopNod является слабой аутентификацией кошелька. | `Дизайн-риск` | Пространство PIN математически равно 100,000,000 комбинаций. | Rate limits, lockout, shard threshold, TEE design, server-side verification details, biometric/2FA policy. | Запросить архитектурную документацию; тестировать rate-limit только с разрешения; изучить публичные security docs. | Advisory/question. Не называть exploitable без evidence по auth-flow. |
| #7 | `TransactionDeny` blacklist может permanently freeze user funds. | `Не подтверждено` | Отчёт указывает на `TransactionDeny` и описывает условную интеграцию. | Вызывают ли PUSD/sPUSD blacklist в `withdraw`, `redeem`, `transfer`, `transferFrom`; admin process; unblacklist path. | Проверить token/vault source или traces; в контролируемой среде протестировать, может ли blacklisted address redeem. | Запросить детали интеграции; повышать статус, если withdrawals действительно блокируются. |
| #8 | pAlpha/CCTP bridge является single point of failure. | `Дизайн-риск` | Перечислены общие риски зависимости от CCTP. | Конкретная CCTP-интеграция, domain separation, fallback, withdrawal delay, TVL proof. | Проверить bridge contracts, Circle integration config, chain domain IDs, operational docs. | Оставить дизайн-риском, пока не найдена конкретная ошибка интеграции. |
| #9 | Нет timelock на изменение `baseInterestRate` и `ltvRatio`. | `Не подтверждено` | Отчёт называет `updateBaseRate()` / `updateLTVRatio()`. | Access control функций, timelock/governance path, применяются ли изменения к активным займам. | Проверить `LoanManager`; изучить admin call traces; проверить storage/history. | Объединить с #3, если подтвердится. |
| #10 | Нет keeper/incentive для `slashLoan()`; просроченные займы могут оставаться необработанными. | `Не подтверждено` | Отчёт утверждает loan duration 5400 секунд и отсутствие keeper. | Access control slashing, incentives, off-chain keepers, automated hooks, events. | Проверить `LoanManager`; изучить docs/events; запросить у команды automation design; найти историю keeper/liquidation tx. | Формулировать как operational validation request до подтверждения. |
| #11 | `migrateV1ToV2()` может нарушить blacklist index при неправильном/повторном вызове. | `Не подтверждено` | Отчёт цитирует один `require` и предлагает migration flag. | Полная реализация функции, access control, idempotency behavior, storage invariants. | Изучить `TransactionDeny.sol`; написать unit test на repeated/out-of-order migration. | Может стать подтверждённым, если локальный source докажет проблему. |
| #12 | `RuleManager.setRoleAdmin()` позволяет полный takeover системы ролей. | `Дизайн-риск` | Описан стандартный сценарий admin compromise. | Защищена ли функция timelock/multisig; intended role model; есть ли путь misuse для non-admin. | Изучить `RuleManager.sol` и deployed role admins; проверить admin holder. | Включать в общий privileged-access risk, если нет non-admin escalation. |
| #13 | Нет unbonding period для LST delegation. | `Не подтверждено` | Отчёт утверждает отсутствие documented unbonding period. | Реализация `Eigen.removeDelegation()`, active-loan lock checks, queue/delay storage. | Проверить source/bytecode; протестировать delegate-borrow-undelegate flow в fork/local среде. | Оставить гипотезой. |
| #14 | Owner может mint LST/USDC без cap; PUSD может mint без backing. | `Не подтверждено` | Отчёт перечисляет token addresses и предполагаемые `mint()`/`mintToPUSD()`. | Реальные minter roles, caps, owner address, backing checks, production/testnet intent. | Проверить token source/bytecode; прочитать roles/caps; подтвердить mint functions и access control. | Если подтвердится, классифицировать как centralization/testnet risk, если нет production funds. |

## Срочные приоритеты сбора доказательств

1. Найти proxy implementation/admin addresses для deployed contracts.
2. Получить или восстановить ABI для `sPUSD`, `PUSD`, `LoanManager`, `Eigen`.
3. Проверить owner/role/admin holders и определить, являются ли они EOA, multisig или timelock.
4. Подготовить read-only scripts для selectors, storage slots и role checks.
5. Переносить в `DISCLOSURE.md` только воспроизведённые и подтверждённые issues.
