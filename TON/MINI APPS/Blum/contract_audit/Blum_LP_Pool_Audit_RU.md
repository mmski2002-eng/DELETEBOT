# Аудит смарт-контракта Blum DEX LP Pool (TON, FunC)

## Объект аудита

- Контракт: `EQDPLWHkkQtlb28MX4WUnNNFkCEU9pcJaofKQsCmNg8nM5JS`
- Тип: constant-product AMM pool
- Язык: FunC
- Точка входа: `contracts/pool.fc`

## Методология

Я проанализировал код пула, роутера и связанных модулей LP account / LP wallet, которые соответствуют интерфейсу `stonfi_pool_v2_const_product`, который tonviewer показывает для данного адреса. Для полной проверки логики были прочитаны все релевантные исходники:

- `contracts/pool.fc`
- `contracts/pool/headers.fc`
- `contracts/pool/get.fc`
- `contracts/pool/msgs/router.fc`
- `contracts/pool/msgs/protocolfee.fc`
- `contracts/pool/msgs/lp_account.fc`
- `contracts/pool/msgs/lp_wallet.fc`
- `contracts/pool/pools/constant_product/{pool.fc,math.fc,get.fc,storage.fc,state_init.fc,constant_product.fc,gas.fc}`
- `contracts/lp_account.fc`
- `contracts/lp_account/msgs/{pool.fc,user.fc,getter.fc}`
- `contracts/lp_wallet.fc`
- `contracts/common/{common.fc,contracts.fc,errors.fc,gas.fc,op.fc,params.fc,utils.fc}`
- `contracts/router.fc`
- `contracts/router/{router.fc,dex.fc,storage.fc,utils.fc,get.fc}`
- `contracts/router/msgs/{admin.fc,pool.fc,jetton.fc,vault.fc,getter.fc}`

## Executive Summary

Критических багов, позволяющих внешнему атакующему напрямую украсть ликвидность без контроля над `router` или `admin`, по прочитанному коду не выявлено. Основные риски лежат в трех зонах:

1. Сильная централизация через `admin_address` роутера.
2. Логический дефект сбора комиссий протокола: сбор возможен только если накоплены комиссии сразу в обоих токенах.
3. Отсутствие какой-либо on-chain защиты от экономических атак уровня low-liquidity MEV, кроме пользовательских `min_out` и `deadline`.

---

## Findings

### 1. Single-admin может мгновенно изменить `protocol_fee_address` и торговые комиссии

- Severity: Low
- Location: `contracts/router/msgs/admin.fc:6`, `contracts/pool/msgs/router.fc:308`

### Описание

Роутер принимает `op::set_fees` только от `storage::admin_address`, после чего немедленно пересылает в пул `op::internal_set_fees`. В пуле новые значения `lp_fee`, `protocol_fee` и `protocol_fee_address` записываются сразу, без timelock, without multisig и без дополнительной on-chain аутентификации кроме доверия к `router_address`.

Код:

- `contracts/router/msgs/admin.fc:6-52` отправляет `pool::internal_set_fees(...)`
- `contracts/pool/msgs/router.fc:308-321` сразу применяет новые значения

### Impact

- Администратор или тот, кто скомпрометировал `admin_address`, может мгновенно перенаправить весь будущий protocol fee на произвольный адрес.
- Также можно немедленно изменить комиссии пула в допустимом диапазоне `0%..1%`.
- Это не дает немедленного drain пользовательской ликвидности само по себе, но создает выраженный governance / trust risk.

### Recommendation

- Перевести `set_fees` под timelock.
- Использовать multisig вместо одиночного `admin_address`.
- Эмитить отложенные governance-операции и давать LP время на выход до применения новых fee params.

---

### 2. Single-admin может мгновенно ставить роутер и конкретный пул на паузу

- Severity: Low
- Location: `contracts/router/msgs/admin.fc:86`, `contracts/router/msgs/admin.fc:148`, `contracts/pool/msgs/router.fc:294`

### Описание

Есть две независимые точки управления блокировкой:

- `contracts/router/msgs/admin.fc:148-154` переключает `storage::is_locked` у роутера через `op::update_status`
- `contracts/router/msgs/admin.fc:86-115` шлет в конкретный пул `op::internal_update_status`
- `contracts/pool/msgs/router.fc:294-299` в пуле тоже просто переключает `storage::is_locked`

Блокировка реализована как `toggle`, а не как явная установка в нужное состояние.

### Impact

- Администратор может мгновенно остановить новые swap/provide flows.
- При ошибочном повторном вызове toggle-семантика может неожиданно вернуть контракт в противоположное состояние.
- Это в первую очередь риск централизации и availability, а не внешний exploit.

### Recommendation

- Заменить toggle на явный `set_status(bool locked)`.
- Для pause/unpause использовать timelock или emergency-role с отдельной governance-политикой.
- Логировать ожидаемое целевое состояние в сообщении, а не вычислять его на стороне контракта.

---

### 3. Router admin имеет путь к произвольному обновлению кода роутера и пула

- Severity: Medium
- Location: `contracts/router/msgs/admin.fc:156`, `contracts/router/msgs/admin.fc:186`, `contracts/router/msgs/admin.fc:235`, `contracts/pool/msgs/router.fc:302`

### Описание

В коде предусмотрен upgrade-механизм:

- `op::init_code_upgrade` с задержкой `7 days`
- `op::init_admin_upgrade` с задержкой `2 days`
- `op::init_pool_code_upgrade` с задержкой `2 days`
- `op::finalize_upgrades` применяет отложенные обновления
- `op::update_pool_code` затем прокатывает новый pool code в конкретный пул

Ключевые места:

- `contracts/router/msgs/admin.fc:156-169`
- `contracts/router/msgs/admin.fc:171-183`
- `contracts/router/msgs/admin.fc:186-199`
- `contracts/router/msgs/admin.fc:235-260`
- `contracts/pool/msgs/router.fc:302-305`
- тайминги: `contracts/common/params.fc:16-17`

### Impact

- Прямого мгновенного drain-функционала в текущем reviewed коде нет.
- Но при компрометации `admin_address` атакующий может подготовить и затем активировать произвольный код роутера и/или пула.
- После успешного upgrade это уже может привести к полному компромиссу логики, включая изъятие средств, подмену маршрутизации или ценовой логики.

### Recommendation

- Заменить single-admin на multisig.
- Вынести upgrade под более длинный timelock и on-chain announcement.
- Для `pool_code` и `router code` хранить hash ожидаемой реализации и публиковать его заранее.
- Добавить off-chain monitoring для всех `init_*_upgrade` операций.

---

### 4. `collect_fees` не работает, если накоплена комиссия только в одном токене

- Severity: Low
- Location: `contracts/pool/msgs/protocolfee.fc:5`

### Описание

Сбор протокольных комиссий требует одновременно:

```func
(storage::collected_token0_protocol_fee > 0) & (storage::collected_token1_protocol_fee > 0)
```

То есть если в пуле накоплена protocol fee только по одной стороне, `collect_fees` завершится ошибкой `error::zero_output`.

Это легко достижимо в реальной эксплуатации: при одностороннем потоке swap комиссии накапливаются только в одном из двух счетчиков:

- `contracts/pool/msgs/router.fc:97`
- `contracts/pool/msgs/router.fc:104`

### Impact

- Протокол не может вывести комиссию, пока не накопится ненулевое значение и по второму токену.
- При однонаправленном объеме торгов protocol fees могут зависнуть на неопределенный срок.
- Это не приводит к краже пользовательских средств, но является дефектом fee-accounting / fee-collection logic.

### Recommendation

- Разрешить сбор комиссий независимо по каждой стороне.
- Заменить условие на:
  - `token0_fee > 0 || token1_fee > 0`
- Отправлять только ненулевую сторону, а вторую пропускать.

---

## Проверка по категориям

### 1. Access Control

#### `protocol_fee_address`

- Результат: issue found
- Контроль осуществляется через `router admin`.
- `contracts/router/msgs/admin.fc:6-52` позволяет администратору изменить `protocol_fee_address`.
- `contracts/pool/msgs/router.fc:308-321` применяет изменение немедленно.

Вывод:

- Да, `protocol_fee_address` может быть изменен администратором в одностороннем порядке.
- On-chain timelock для `set_fees` отсутствует.

#### Admin/owner функции без timelock или multisig

- Результат: issue found

Без timelock выполняются сразу:

- `set_fees`
- `update_status`
- `update_pool_status`
- `reset_pool_gas`

С timelock выполняются:

- `init_code_upgrade` -> `7 days`
- `init_admin_upgrade` -> `2 days`
- `init_pool_code_upgrade` -> `2 days`

Multisig в коде не реализован.

#### Spoofing callers в `router.fc`

- Результат: No issue found

Обоснование:

- Пул принимает router-only сообщения только если `ctx.at(SENDER) == storage::router_address`:
  - `contracts/pool.fc:28-30`
- Роутер принимает pool callbacks только если `ctx.at(SENDER)` совпадает с детерминированно вычисленным адресом конкретного пула:
  - `contracts/router/msgs/pool.fc:18-29`
- Аналогичная схема используется для `lp_account` и `lp_wallet`:
  - `contracts/pool/msgs/lp_account.fc:18-27`
  - `contracts/pool/msgs/lp_wallet.fc:11-20`

С учетом deterministic address derivation spoofing sender-а по reviewed коду не просматривается.

---

### 2. AMM Math

#### Корректность swap formula

- Результат: No issue found
- Location: `contracts/pool/pools/constant_product/pool.fc:1-17`

Формула:

```func
amount_in_with_fee = amount_in * (fee_divider - lp_fee)
base_out = muldiv(amount_in_with_fee, reserve_out, reserve_in * fee_divider + amount_in_with_fee)
```

Это стандартная constant-product схема с последующим вычитанием `protocol_fee` и `ref_fee` из `base_out`.

#### Overflow / underflow

- Результат: No issue found

Обоснование:

- `load_coins()` ограничивает входные денежные значения TVM coin range.
- Код явно предполагает `0 < amountX < 2^120-1`:
  - `contracts/pool/msgs/router.fc:8`
- После вычислений есть дополнительные проверки верхней границы резервов:
  - `contracts/pool/msgs/router.fc:115-118`
  - `contracts/pool/msgs/lp_account.fc:68-72`
- Потенциальные underflow-paths приводят к throw и не маскируются.

Практического exploitable arithmetic bug в reviewed logic не найдено.

#### Slippage enforcement

- Результат: No issue found

Обоснование:

- `min_out` проверяется on-chain:
  - `contracts/pool/msgs/router.fc:114`
- `tx_deadline` проверяется и на router, и на pool:
  - `contracts/router/dex.fc:51`
  - `contracts/pool/msgs/router.fc:111`
  - `contracts/pool/msgs/router.fc:238`
- Для добавления ликвидности есть `min_lp_out`:
  - `contracts/pool/msgs/lp_account.fc:69`

#### Price impact при низкой ликвидности

- Результат: Informational

Это не баг кода, а свойство constant-product AMM.

Если в пуле порядка `$25k` TVL и он примерно сбалансирован как `$12.5k / $12.5k`, то даже один крупный swap может сильно сдвинуть spot price. Например, вход на `$5k` в одну сторону способен изменить пост-трейд отношение резервов примерно на десятки процентов до арбитража.

Вывод:

- Да, при такой ликвидности один tx может значительно манипулировать ценой.
- Для интеграторов это означает риск oracle manipulation / sandwich / poor execution, если они полагаются на spot-price этого пула.

---

### 3. Reentrancy / TON async messaging

#### Обновление состояния до outbound messages

- Результат: No issue found

Обоснование:

- Swap обновляет резервы и protocol fee counters до исходящих сообщений:
  - `contracts/pool/msgs/router.fc:92-105`
  - send начинается с `contracts/pool/msgs/router.fc:120`
- Burn уменьшает `reserve0`, `reserve1`, `total_supply_lp` до отправки payout:
  - `contracts/pool/msgs/lp_wallet.fc:30-32`
  - send начинается с `contracts/pool/msgs/lp_wallet.fc:56`
- Provide LP обновляет supply/reserves до mint:
  - `contracts/pool/msgs/lp_account.fc:39-61`
  - mint отправляется с `contracts/pool/msgs/lp_account.fc:119`

Для TON это правильный паттерн: state-first, messages-after.

#### Callback / bounce based reentrancy

- Результат: No issue found

Обоснование:

- `pool.fc`, `router.fc` и `lp_account.fc` игнорируют bounced messages:
  - `contracts/pool.fc:11-13`
  - `contracts/router.fc:11-13`
  - `contracts/lp_account.fc:10-12`
- `lp_wallet.fc` отдельно восстанавливает баланс при bounce `internal_transfer` или `burn_notification_ext`:
  - `contracts/lp_wallet.fc:136-147`

Exploitable reentrancy path через synchronous callback pattern не обнаружен.

#### Комментарий `mint should never`

- Результат: No issue found
- Location: `contracts/pool.fc:11-13`

Комментарий относится к bounced message в пуле. Mint здесь реализован как `jetton_wallet::mint(...)`, который на самом деле формирует `op::internal_transfer` в LP wallet:

- `contracts/common/contracts.fc:206-220`

LP wallet принимает `internal_transfer` как штатный путь mint-а:

- `contracts/lp_wallet.fc:174-176`

Если же внутренний transfer отскочит, LP wallet умеет восстановить свой баланс на bounce; критического exploit path из этого комментария не следует.

---

### 4. Flash loan / Sandwich / MEV

#### Flash loans

- Результат: No issue found

В reviewed коде нет отдельного flash-loan opcode, callback API или схемы “borrow-then-callback-then-repay”.

#### On-chain MEV protection

- Результат: Partial protection only

Есть on-chain:

- `tx_deadline`
- `min_out`
- `min_lp_out`

Нет on-chain:

- commit-reveal
- batch auction
- private order flow
- anti-sandwich sequencing

Вывод:

- От классического TON/DEX sandwich это не защищает, если пользователь выставляет слишком слабый `min_out`.
- Это отраслевое ограничение, а не отдельная уязвимость реализации.

---

### 5. Centralization Risks

#### Может ли owner/admin pause contract?

- Результат: issue found
- Да, и router, и конкретные pools можно ставить на паузу через admin-controlled сообщения.

#### Может ли owner/admin drain liquidity?

- Результат: No direct drain function found

В reviewed коде нет прямой функции немедленного вывода пользовательских резервов администрацией.

Однако:

- через code upgrade admin потенциально получает путь к произвольной логике после timelock
- это делает безопасность сильно зависящей от trust в governance/admin key

#### Upgradeable proxy pattern

- Результат: issue found

Proxy в EVM-смысле нет, но есть runtime code upgrade через `set_code(...)` и staged upgrades.

---

### 6. TON-specific checks

#### Workchain checks

- Результат: No issue found

Обоснование:

- глобальный workchain: `contracts/common/params.fc:2`
- sender workchain проверяется в:
  - `contracts/pool.fc:16`
  - `contracts/router.fc:15`
  - `contracts/lp_account.fc:15`
- адреса из payload дополнительно валидируются в:
  - `contracts/router/dex.fc:21-25`
  - `contracts/pool/msgs/router.fc:44-47`
  - `contracts/pool/msgs/router.fc:211`
  - `contracts/pool/get.fc:10`
  - `contracts/pool/get.fc:42`

#### Storage fee depletion handling

- Результат: No issue found

Обоснование:

- Во всех критичных местах есть газовые оценки и `reserves::max_balance(...)` / `reserves::exact(...)`:
  - `contracts/pool/msgs/router.fc:54-55`, `120`, `156`
  - `contracts/pool/msgs/protocolfee.fc:21`
  - `contracts/pool/msgs/lp_account.fc:29`, `153`
  - `contracts/pool/msgs/lp_wallet.fc:56`
  - `contracts/router/msgs/admin.fc:39`, `75`, `106`, `137`
  - `contracts/router/dex.fc:29`, `83`, `94`

Явного storage-fee depletion vector, который позволял бы внешнему атакующему сломать pool accounting, не обнаружено.

#### Bounce handlers completeness

- Результат: No issue found, с operational caveat

Обоснование:

- `lp_wallet` обрабатывает свои критичные bounce cases явно:
  - `contracts/lp_wallet.fc:136-147`
- `pool`, `router`, `lp_account` bounced messages игнорируют.

Это не дало мне exploitable path по reviewed коду, но повышает зависимость от корректности downstream message delivery и от точности gas estimation.

---

## Итог

### Подтвержденные проблемы

1. `Single-admin` может мгновенно изменить `protocol_fee_address` и fee params.
2. `Single-admin` может мгновенно останавливать router и отдельные pools.
3. Существует upgrade path к произвольному коду через admin-controlled staged upgrades.
4. `collect_fees` логически заблокирован, если комиссия накоплена только в одном токене.

### Наиболее важный вывод

Главный риск этого пула не во внешнем permissionless exploit, а в сочетании:

- admin-centric governance
- немедленных privileged operations без timelock
- upgradeable architecture

С точки зрения внешнего атакующего без контроля над admin/router, базовая sender-authentication, slippage checks и async state ordering выглядят достаточно аккуратно.

### Рекомендации высокого уровня

1. Перевести `set_fees`, `pause`, `pool status changes` под timelock.
2. Использовать multisig для `admin_address`.
3. Разрешить `collect_fees` по одной стороне, а не только при двух ненулевых счетчиках.
4. Мониторить все `init_*_upgrade` и `finalize_upgrades` операции как high-risk governance events.

