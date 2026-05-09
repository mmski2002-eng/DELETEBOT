# Исследование Airdrop / Vesting контрактов BLUM

## Цель

Проверить on-chain контракты, связанные с распределением и вестингом `BLUM`, с фокусом на типовые баги:

- двойной `claim`
- обход proof-проверок
- обход временных ограничений
- несанкционированный выпуск токенов из distributor/vesting-логики

Контекст исследования:

- В июне 2025 у Blum был snapshot и pre-launch airdrop.
- По токеномике:
  - `20%` supply выделено на community
  - `50%` от community allocation ушло в pre-launch airdrop
  - `30%` pre-launch airdrop unlock на TGE
  - `70%` vesting на `6 месяцев`

Источник: [blum.io/post/blum-tokenomics](https://www.blum.io/post/blum-tokenomics)

## Ключевой вывод

По on-chain данным я **не нашел Merkle-based airdrop distributor**. Наблюдаемая архитектура выглядит не как “Merkle proof claim”, а как **кастомный stateful distribution/vesting pipeline**:

1. `BLUM` jetton master
2. крупные treasury / multisig кошельки
3. `root distributor` контракт
4. одинаковые `claim helper` контракты
5. одинаковые `beneficiary vesting locker` контракты
6. их jetton wallets, на которые root переводит BLUM

То есть для этой найденной ветки риск `Merkle proof bypass` **не подтверждается**, потому что Merkle-path здесь не обнаружен.

---

## Подтвержденные on-chain объекты

### 1. Реальный `BLUM` jetton master

- Address: `EQCAj5oiRRrXokYsg_B-e0KG9xMwh5upr5I8HQzErm0_BLUM`
- TonAPI:
  - `verification = whitelist`
  - `admin = zero address`
  - `mintable = true`, но admin уже сожжен
  - `total_supply ≈ 969.73M BLUM`

### 2. Крупные командные / allocation кошельки

#### Treasury-like multisig

- Owner: `0:75cf0ffd03c1e846128fb548fcff1feb002c67d395df174f79d584d668da563a`
- Interface: `multisig_v2`
- Jetton balance на момент анализа: `235,006,438.45 BLUM`

Этот multisig активен и отправлял `BLUM` на биржевые адреса, в том числе `Gate.io`.

#### Contributors-like multisig

- Owner: `0:7124f89cf4456f70a26677d6522a4e550552827b1a333833c54af60aecc04c40`
- Interface: `multisig_v2`
- Jetton balance на момент анализа: `161,100,000 BLUM`

Это очень хорошо совпадает с `Contributors 16.11% = 161.1M BLUM` из токеномики.

### 3. Root distributor

- Address: `0:230eecef7f4e302c4dbd38c401e10b5096651170fd9565f3bb1c11ef3d3b2046`
- Interface: неизвестен, `get_methods = []`
- В топ-холдерах держал `120,100,000 BLUM`
- Имеет собственный `BLUM` jetton wallet:
  - `0:4ce2ba0c4c881c7e1515528d890227c5252ec5222c1fcbad41a6a4c8d3a0b1d0`
- В `data` root также присутствует управляющий wallet:
  - `0:5d549a27996b4c9be4622cd49e54ce9fa5442c0177dd23bd4e51e376cf2a548f`
  - interface: `wallet_v5r1`

### 4. Beneficiary vesting lockers

Найдены несколько контрактов с **одинаковым code BOC** и разными beneficiary addresses:

- `0:91dafeaf8b8efda56e8aae3e1c2e6d45bef792c6148f20e803b9146a84c7e3ac`
- `0:f75b30e469c2975b11031d9817244631197f226a31b6b2b5d9e88512aab20b26`
- `0:17e36320ae09e32947b1316363624adbe45b5f7f01865f8de6f0576e0782bef4`
- `0:d8c743694f16eecb261a464c932e32294a4eff58fdda7ff2960c7370c45418e8`
- `0:c8747d8819cf8aa2bf7fb68f629bec6c198b704527657e5e3acc9fb8ffd01e5f`

Частичная декодировка их `data` показывает:

- `root distributor address`
- `beneficiary address`
- `BLUM jetton master`
- дополнительный `ref`, где лежат:
  - адрес jetton wallet этого locker-а
  - timestamp
  - `2592000` (`30 дней`)
  - дополнительные schedule/state поля

Это очень похоже на **индивидуальные vesting lockers**.

### 5. Claim helper contracts

Также найдены более простые контракты одинакового кода:

- `0:29906bac5cde7029381407ce574512c7fd6748167cb4e085f4b73d38bb8f3bf9`
- `0:d19f2ab731f5dc2857bce216a11e29add40bca69ac613e986dcad389ab6ab314`
- `0:4d4f8b2134a098d134c1aabbac9e4e14dfbc745ca38b20d6def0f3af04e52d47`

Code hash у них одинаковый:

- `piRU2WGJc26dwk856odudDX0xZxwhgwq2cfO28TixFM=`

Их `data` содержит:

- `root distributor`
- адрес beneficiary / инициатора
- небольшой integer/slot id

Эти helper-контракты отправляют в root вызов `0x43c7d5c9`.

---

## Наблюдаемая архитектура

### Root distributor flow

По событиям root-контракта виден повторяющийся паттерн:

1. `claim helper` вызывает root с `op = 0x43c7d5c9`
2. root вызывает конкретный beneficiary locker с одним из opcode:
   - `0x738d7ea4`
   - `0x705543df`
   - `0x5e8d4a51`
   - `0x7071afd4`
   - `0x71550f7d`
3. beneficiary locker возвращает часть TON обратно root
4. root делает `JettonTransfer` BLUM в beneficiary locker

Примеры подтвержденных выплат:

- `16,000,000 BLUM`
- `6,000,000 BLUM`
- `2,000,000 BLUM`
- `1,500,000 BLUM`
- `1,000 BLUM`

Это выглядит как **контрактно-управляемый unlock/release**, а не как Merkle claim.

---

## Что удалось подтвердить

### 1. Merkle claim path не обнаружен

- Severity: Informational
- Status: Confirmed observation

### Обоснование

В найденной distribution-ветке нет признаков Merkle distributor:

- не найден Merkle root в публичных get-methods
- у root нет публичных `get_methods`
- claim идет через кастомные helper/locker contracts
- observed flow stateful и message-driven, а не proof-driven

### Вывод

Риск “обход Merkle proof” для этой конкретно найденной архитектуры **не подтверждается**.

---

### 2. Root умеет отклонять преждевременные или невалидные claim attempts

- Severity: Informational
- Status: Confirmed observation

### Evidence

Контракт `0:29906...` многократно вызывал root через `0x43c7d5c9` и получал `Bounce`, без выдачи BLUM:

- несколько подряд failed attempts около `2026-03-09`
- позже, при другой попытке, тот же helper успешно инициировал release

### Значение

Это хороший сигнал, что в root есть хотя бы какая-то проверка состояния:

- времени unlock
- eligibility
- или статуса конкретного tranche/helper

### Вывод

Простейший баг вида “любой вызов helper всегда приводит к payout” не наблюдается.

---

### 3. Вестинг/распределение централизованно привязано к управляющим кошелькам

- Severity: Low
- Status: Confirmed observation

### Обоснование

Найденные компоненты сильно завязаны на privileged wallets:

- treasury multisig с `235M+ BLUM`
- contributors multisig с `161.1M BLUM`
- `wallet_v5r1` address внутри root data: `0:5d54...`

Исходный код root/locker/helper публично не найден, публичных getters почти нет.

### Impact

- пользователи и ресерчеры не могут легко самостоятельно верифицировать инварианты распределения
- trust model сильно зависит от off-chain знания того, кто контролирует эти кошельки

---

## Что НЕ подтверждено

### 1. Двойной claim

- Severity: Not confirmed
- Status: Inconclusive

### Что известно

- root отклоняет некоторые попытки claim
- успешные claim-события наблюдаются
- helper и locker state выглядят stateful

### Чего не хватает

Без исходника root/locker logic нельзя строго доказать:

- обновляется ли claim-state before transfer
- можно ли replay-ить тот же helper после success
- можно ли деплоить новый helper с теми же параметрами и получать payout повторно

### Текущий вывод

Я **не нашел on-chain evidence** уже произошедшего double-claim, но окончательно снять гипотезу без source/disassembly нельзя.

---

### 2. Обход proof-проверок

- Severity: Not applicable / not confirmed
- Status: Inconclusive

### Текущий вывод

Поскольку Merkle/path proof механизм в найденной архитектуре не выявлен, именно этот класс багов пока выглядит **неприменимым** к обнаруженному distributor flow.

Если существует **другой**, отдельный airdrop contract, не связанный с этой веткой, его нужно искать отдельно.

---

## Практические гипотезы для следующего этапа

### 1. Проверка replay на helper-контрактах

Что проверить:

- может ли уже успешный `claim helper` снова вызвать root
- появлялись ли повторные success payouts от одного и того же helper

На что смотреть:

- повторный `0x43c7d5c9` от того же helper
- был ли после него `JettonTransfer` в тот же beneficiary locker

### 2. Проверка deterministic redeploy

Что проверить:

- можно ли задеплоить helper с теми же полями `data`
- считает ли root helper по адресу, по коду или по payload

Риск:

- если root проверяет только “код похожий”, а не exact helper identity/state, возможен replay через клон

### 3. Проверка child locker state transitions

Что проверить:

- как меняется jetton balance wallet-а locker-а после success
- есть ли outbound transfers из locker к beneficiary
- нет ли циклов “helper -> root -> locker” без уменьшения internal state

---

## Итог

### Что мы знаем уверенно

1. Реальный `BLUM` jetton master подтвержден.
2. Найдены крупные командные multisig-кошельки, совпадающие с tokenomics allocations.
3. Найден кастомный `root distributor`.
4. Найдены одинаковые `beneficiary vesting lockers`.
5. Найдены одинаковые `claim helper` контракты.
6. Наблюдаемый claim flow не похож на Merkle distribution.
7. Root уже умеет отклонять некоторые claim attempts.

### Что пока не доказано

1. Double claim
2. Clone/redeploy replay
3. Ошибка в state accounting внутри root/locker после success claim

### Самый честный вывод на этом этапе

Найденная ветка BLUM distribution/vesting выглядит как **кастомная stateful система распределения**, а не как стандартный Merkle airdrop. Поэтому самый перспективный дальнейший вектор не “Merkle proof bypass”, а:

- replay одного и того же helper
- клон helper с теми же параметрами
- несовпадение root state и locker state после success release

