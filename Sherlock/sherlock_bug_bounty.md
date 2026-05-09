# Sherlock Bug Bounty - Immunefi

## Общая информация

**Проект:** Sherlock  
**Описание:** Sherlock — это платформа управления рисками, предназначенная для предоставления DeFi протоколам доступного и надёжного покрытия от эксплойтов смарт-контрактов с первого дня.  
**Платформа:** Ethereum, DeFi  
**Сервисы:** Стейкинг, страхование  
**Язык смарт-контрактов:** Solidity  
**Максимальный размер вознаграждения:** $500,000  
**Live Since:** 12 October 2021  
**Last Updated:** 22 July 2025  
**PoC Required:** Да  
**KYC:** Не требуется  

**Ссылки на ресурсы:**
- [GitHub смарт-контрактов](https://github.com/sh…e/tree/main/contracts)
- [Sherlock website](https://sherlock.xyz/about/)

## Награды

**Награды распределяются в USDC на Ethereum.**

### Награды по уровню угрозы

| Severity  | Reward |
|-----------|--------|
| Critical  | Up to $500,000 |
| High      | Flat: $25,000 |

**Описание:**
- Награды распределяются на основе Immunefi Vulnerability Severity Classification System V2.
- PoC требуется для критических и high-impact уязвимостей.
- Эксплойты, приводящие к потере средств для пользователей и приносящие прибыль хакеру, классифицируются как Critical. Всё остальное — High.
- Критические уязвимости ограничены 10% экономического ущерба, минимум $50,000 за Critical баг-репорты.

## Программа и цели

- Потеря средств пользователями через профитабельное хищение или заморозку
- Потеря средств стейкеров через профитабельное хищение
- Профитабельное уменьшение фонда стейкеров (infinite mining of staking positions)
- Профитабельные payout эксплойты
- DoS или заморозка атак

## Запрещенные действия

- Тестирование на mainnet или публичном тестнете без локального форка
- Тестирование прайсинг ораклов или сторонних смарт-контрактов
- Фишинг или социальная инженерия против сотрудников
- Тестирование сторонних систем и расширений браузеров
- Denial of service сторонних сервисов
- Автоматическое тестирование сервисов, создающее высокий трафик
- Публикация незакрытых уязвимостей в эмбарго
- Любые действия, запрещённые правилами Immunefi

## Ограничения по осуществимости

- Проект может получать баг-репорты с невалидными векторами атаки или отсутствующими активами — такие баги должны быть реалистично воспроизводимыми.
- Immunefi разработал набор стандартов feasibility limitation для оценки багов.

**Документы по feasibility:**
- Chain Rollbacks
- Pre-Impact Bug Monitoring
- Attack Investment Amount
- Attacks With A Financial Risk To The Attacker
- When Is An Impactful Attack Downgraded To Briefing?

## Scope (Активы в рамках программы)

### Smart Contracts в Scope:

| Type | Target | Name | Added on |
|------|--------|------|----------|
| Contract | 0x...IC7R | InfoStorage | 14 July 2022 |
| Contract | 0x...0RRA | AlphaBetaEqualDepositMaxSplitter | 14 July 2022 |
| Contract | 0x...0b5t | AlphaBetaEqualDepositSplitter | 14 July 2022 |
| Contract | 0x...77GE | AaveStrategy | 14 July 2022 |
| Contract | 0x...1F8E | CompoundStrategy | 14 July 2022 |
| Contract | 0x...62a6 | SherBuy | 10 May 2022 |
| Contract | 0x...8D03 | SherClaim | 10 May 2022 |
| Contract | 0x...9354 | timelockController | 10 May 2022 |
| Contract | 0x...Et64 | SherlockClaimManager | 10 May 2022 |
| Contract | 0x...a1D3 | SherlockProtocolManager | 10 May 2022 |
| Contract | 0x...B31b | SherDistributionManager | 10 May 2022 |
| Contract | 0x...D857 | MasterStrategy | 10 May 2022 |

**Итого:** 15 активов в scope  
**Итого impacts в scope:** 5  

### Impacts в Scope:

- Direct theft of any user funds (critical)
- Permanent freezing of funds (critical)
- Theft of unclaimed yield (critical)
- Permanent freezing of unclaimed yield (critical)
- Temporary freezing of funds > 1 month (high)

### Out of Scope:

**Smart Contract specific:**
- Incorrect data supplied by third party oracles (flash loan / oracle manipulation attacks not covered)
- Impacts requiring basic economic and governance attacks (e.g., 51% attacks)
- Lack of liquidity impacts
- Sybil attacks
- Centralization risks

**All categories:**
- Attacks reporter already exploited
- Attacks requiring leaked keys/credentials
- Access to privileged addresses (governance/strategist contracts) without modifications
- Deppegging external stablecoins without direct impact
- Secrets, API keys, private keys in GitHub without proof of production usage
- Best practice recommendations
- Feature requests
- Test files/configurations unless stated otherwise
- Phishing or social engineering attacks against employees/customers

## Resources

- [GitHub Contracts](https://github.com/sh…e/tree/main/contracts)
- Информация по активам, наградам и ограничениях в рамках bug bounty программы доступна на сайте Immunefi.

