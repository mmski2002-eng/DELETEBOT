# R2 Result: payload substitution

## Verdict

Для текущих артефактов `R2` как `payload substitution between approval and execution` **не подтверждается** и на уровне исследованного `vault` выглядит **малоприменимым**.

## Главный вывод

На исследованном контракте `daolama-ton-vault.ton` не найдено признаков классической двухфазной схемы:

- `approve`
- `queue`
- `execute`

Вместо этого observed модель выглядит так:

- пользовательские wallet-вызовы идут в `daolama_vault_supply`
- internal worker/position contracts вызывают `daolama_vault_withdraw`
- после inbound `withdraw` vault сразу делает outbound transfer

То есть на уровне `vault` execution path сейчас выглядит **однофазным**, а не `approved payload -> later execute payload`.

## Что подтверждено

### 1. Реальные inbound opcode'ы vault

По live history последних `100` tx vault:

- `0x00000002` — массовый internal flow
- `0x05138d91` — `nft_ownership_assigned`
- `0x7bdd97de` — `daolama_vault_withdraw`
- `0x5c11ada9` — `daolama_vault_supply`

### 2. Не найден отдельный execute opcode

В observed tx history vault нет отдельного семейства транзакций, похожего на:

- queued execution
- governance execution
- timelock execution
- proposal finalization with payload replay

### 3. `withdraw` path однофазный

Observed `0x7bdd97de` tx:

- приходит от trusted-looking worker contracts
- внутри body несёт `amount` и `recipient`
- сразу после этого vault делает outbound transfer

Это не похоже на схему:

- сначала `approve(payload_hash)`
- потом `execute(payload)`

### 4. `query_id` не выглядит защитой между фазами

Во всех observed `withdraw` body:

- `query_id = 0`

Это не похоже на multi-step binding между approval и execute.

## Почему payload substitution не подтверждается

Для подтверждения `R2` нужен минимум один из признаков:

1. отдельный approve state
2. отдельный execute state
3. payload hash binding
4. replay/replace между двумя фазами

На текущих артефактах этого не найдено.

Вместо этого всё указывает на другую модель:

- `vault` — конечный liquidity / custody контракт
- бизнес-логика маршрутизации живёт в child / NFT-related / worker contracts
- именно они формируют outbound intent, который vault исполняет в одном шаге

## Что это значит practically

### Для `vault`

Классическая уязвимость `payload substitution between approve and execute` сейчас **не воспроизводится**.

### Для всей DAO / governance системы

Это **не означает**, что `R2` глобально закрыт для всего протокола.

Причина:

- в рабочей папке нет исходников governance / timelock / proposal execution contracts
- именно там мог бы существовать настоящий `approve -> queue -> execute` flow

Поэтому корректный статус такой:

- `vault-level R2`: not confirmed / likely not applicable
- `governance-level R2`: still unassessed due to missing contracts

## Артефакты

- `POC/R2_payload_substitution/POC_PLAN_ru.md`
- `POC/R2_payload_substitution/scripts/research_r2_live.js`

## Следующий лучший шаг

Если хотим именно подтвердить `R2` как DAO finding, нужны:

1. адреса governance / timelock / executor контрактов
2. их live tx history
3. исходники или decompilation execute path
