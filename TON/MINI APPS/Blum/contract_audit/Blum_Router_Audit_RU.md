# Аудит Router-контракта Blum / STON.fi v2 (TON, FunC)

## Идентификация контракта

- Исходный пул: `EQDPLWHkkQtlb28MX4WUnNNFkCEU9pcJaofKQsCmNg8nM5JS`
- Router был получен on-chain через `get_pool_data().router_address`
- Router address:
  - raw: `0:c03f27bb1c03c0025e165e9cf98ce09d85fd87f61f50924cd143ee8ae6eb22b9`
  - friendly: `EQDAPye7HAPAAl4WXpz5jOCdhf2H9h9QkkzRQ-6K5usiuQeC`
- Версия router:
  - `major = 2`
  - `minor = 2`
  - `development = release`
- Тип:
  - `dex_type = constant_product`
- Текущее on-chain состояние:
  - `is_locked = false`
  - `admin_address = EQBAj_9iYponyRxQgNurrn4t7UNS0aQeteHY7U-H-F_XTy-Z`

## Что было проверено

Я проанализировал:

- `contracts/router.fc`
- `contracts/router/router.fc`
- `contracts/router/storage.fc`
- `contracts/router/dex.fc`
- `contracts/router/get.fc`
- `contracts/router/utils.fc`
- `contracts/router/msgs/admin.fc`
- `contracts/router/msgs/jetton.fc`
- `contracts/router/msgs/pool.fc`
- `contracts/router/msgs/vault.fc`
- `contracts/router/msgs/getter.fc`
- связанные общие модули:
  - `contracts/common/{common.fc,contracts.fc,errors.fc,gas.fc,op.fc,params.fc,utils.fc}`
- связанные контракты, необходимые для trust-model:
  - `contracts/pool.fc`
  - `contracts/pool/msgs/router.fc`
  - `contracts/vault.fc`

## Executive Summary

Router в этой связке является главным trust anchor контракта:

- он принимает пользовательские `transfer_notification`
- маршрутизирует swap / provide LP
- валидирует pool callbacks
- принимает admin governance-сообщения
- контролирует pause
- контролирует fee updates
- контролирует code/admin/pool upgrades

Прямого внешнего exploit-path, позволяющего любому пользователю без privileged access украсть ликвидность, по reviewed коду не найдено. Главные риски здесь governance-централизованные:

1. `admin_address` может немедленно менять fee-параметры и fee recipient.
2. `admin_address` может немедленно останавливать router и отдельные pools.
3. Router и pool являются upgradeable, а значит безопасность в сильной степени зависит от доверия к admin key.

---

## Findings

### 1. Single-admin может мгновенно менять `protocol_fee_address` и торговые комиссии в любых пулах

- Severity: Low
- Location: `contracts/router.fc:27-32`, `contracts/router/msgs/admin.fc:6-52`

### Описание

`router.fc` обрабатывает governance-сообщения только если `ctx.at(SENDER) == storage::admin_address`:

- `contracts/router.fc:27-32`

Дальше `handle_admin_messages()` позволяет вызвать `op::set_fees`, который:

- принимает `new_lp_fee`
- принимает `new_protocol_fee`
- принимает `new_protocol_fee_address`
- вычисляет адрес целевого пула
- шлет в него `pool::internal_set_fees(...)`

Код:

- `contracts/router/msgs/admin.fc:6-52`

Никакого timelock для этой операции нет. Единственное ограничение:

- fee values должны быть в диапазоне `0..100` bps по локальным правилам:
  - `contracts/router/msgs/admin.fc:27-32`
  - `contracts/common/params.fc:11-13`

### Impact

- Компрометация `admin_address` дает возможность мгновенно перенаправить protocol fees на произвольный адрес.
- Также можно сразу изменить effective fee configuration любого пула.
- Это не является прямым drain user reserves, но создает сильный governance risk.

### Recommendation

- Перевести `set_fees` под timelock.
- Перейти с single-admin на multisig.
- Публиковать pending fee changes до их применения.

---

### 2. Single-admin может мгновенно блокировать router и любые привязанные pools

- Severity: Low
- Location: `contracts/router/msgs/admin.fc:86-115`, `contracts/router/msgs/admin.fc:148-154`

### Описание

В router есть две privileged pause-функции:

1. `op::update_status`
   - переключает `storage::is_locked` самого router
   - `contracts/router/msgs/admin.fc:148-154`

2. `op::update_pool_status`
   - отправляет в пул `pool::internal_update_status(...)`
   - `contracts/router/msgs/admin.fc:86-115`

В обоих случаях используется toggle-семантика, а не явная установка нужного состояния.

### Impact

- Администратор может моментально остановить новые `swap`/`provide_lp` flows на router level.
- Может отдельно замораживать конкретные pools.
- Toggle-подход повышает операционный риск ошибочного двойного переключения.

### Recommendation

- Заменить toggle на explicit `set_locked(bool)`.
- Для pause/unpause использовать timelock или отдельную emergency-policy.
- Вести off-chain мониторинг всех `update_status` и `update_pool_status`.

---

### 3. Upgradeable архитектура роутера и пула создает высокую зависимость от admin key

- Severity: Medium
- Location: `contracts/router/msgs/admin.fc:156-260`, `contracts/router/storage.fc:7-9`

### Описание

Router поддерживает staged-upgrades:

- `init_code_upgrade`
- `init_admin_upgrade`
- `init_pool_code_upgrade`
- `cancel_*`
- `finalize_upgrades`

Код:

- `contracts/router/msgs/admin.fc:156-260`

Детали:

- upgrade самого router code: delay `7 days`
- смена `admin_address`: delay `2 days`
- подготовка `upgrade_pool_code`: delay `2 days`
- затем `update_pool_code` может раскатить новый code в конкретный pool:
  - `contracts/router/msgs/admin.fc:117-146`

Данные об upgrade-процессе хранятся в:

- `storage::temp_upgrade`
- `storage::upgrade_pool_code`

см. `contracts/router/storage.fc:7-9`, `contracts/router/storage.fc:27`

### Impact

- При компрометации `admin_address` атакующий получает не мгновенный, но очень мощный путь к произвольной смене логики роутера и пулов.
- После завершения timelock такой upgrade может привести уже к полному компромиссу маршрутизации и custody логики.
- Это не “мгновенная” уязвимость, но ключевой centralization / governance risk.

### Recommendation

- Использовать multisig.
- Увеличить delay для `pool_code` и governance-critical upgrades.
- Публиковать хеши нового кода и связывать их с on-chain announcement/event practice.
- Настроить алерты на `init_*_upgrade`, `finalize_upgrades`, `update_pool_code`.

---

## Проверка по категориям

### 1. Access Control

#### Кто контролирует `protocol_fee_address`

- Результат: issue found

`protocol_fee_address` меняется через admin flow:

- `contracts/router/msgs/admin.fc:12-18`
- `contracts/router/msgs/admin.fc:44-49`

Затем пул применяет новые значения:

- `contracts/pool/msgs/router.fc:308-317`

Вывод:

- Контроль односторонне у `admin_address`.

#### Есть ли admin-функции без timelock / multisig

- Результат: issue found

Без timelock выполняются:

- `set_fees`
- `reset_pool_gas`
- `update_pool_status`
- `update_status`
- `reset_gas`

С timelock выполняются только:

- router code upgrade
- admin change
- pool code upgrade

Multisig в reviewed коде отсутствует.

#### Можно ли spoof-ить router callers

- Результат: No issue found

Обоснование:

- governance path доступен только для `storage::admin_address`:
  - `contracts/router.fc:27-32`
- pool callbacks проверяют детерминированно вычисленный адрес пула:
  - `contracts/router/msgs/pool.fc:18-29`
  - `contracts/router/msgs/pool.fc:103-113`
- vault callbacks проверяют детерминированно вычисленный адрес vault:
  - `contracts/router/msgs/vault.fc:9-14`

По reviewed sender verification spoofing privileged callers не просматривается.

---

### 2. Router message routing / swap flow

#### Валидация входящего `transfer_notification`

- Результат: No issue found

Обоснование:

- router обрабатывает `op::ft::transfer_notification`:
  - `contracts/router/msgs/jetton.fc:5-31`
- если ref payload отсутствует, токены сразу рефандятся:
  - `contracts/router/msgs/jetton.fc:9-20`
- дальше `route_dex_messages()` валидирует:
  - допустимый `transferred_op`
  - разность token wallets
  - `storage::is_locked`
  - workchain caller-а
  - `tx_deadline`
  - достаточный gas budget

см. `contracts/router/dex.fc:42-75`

#### Slippage / deadline

- Результат: No issue found

`deadline` и затем `min_out`/`min_lp_out` проверяются on-chain на downstream уровнях:

- router level:
  - `contracts/router/dex.fc:51`
- pool level:
  - `contracts/pool/msgs/router.fc:111`
  - `contracts/pool/msgs/router.fc:114`
  - `contracts/pool/msgs/router.fc:238`

#### Flash loan support

- Результат: No issue found

Отдельного flash-loan primitive в reviewed коде нет.

---

### 3. Reentrancy / TON async behavior

#### Обновление state до outbound messages

- Результат: No issue found

Router сам почти не ведет сложное балансовое состояние при swap-routing, но критичные подчиненные контракты обновляют state до исходящих сообщений. Для самого router важнее корректность sender derivation и gas accounting; явного reentrancy bug не найдено.

#### Bounced messages

- Результат: No issue found

`router.fc` на bounced messages просто `return ()`:

- `contracts/router.fc:11-13`

Это не дало exploitable path по reviewed flow, потому что роутер не хранит пользовательские jetton balances как внутренний ledger; фактические перемещения делает через jetton wallets / pools / vaults.

---

### 4. MEV / sandwich / price manipulation

#### Есть ли on-chain anti-MEV

- Результат: Partial protection only

Есть:

- `tx_deadline`
- downstream `min_out`

Нет:

- anti-sandwich sequencing
- private order flow
- commit-reveal
- auction execution

Вывод:

- Router не содержит специальной on-chain защиты от MEV beyond standard slippage + deadline.
- Это ожидаемо для AMM router, но важно для threat model low-liquidity pools.

---

### 5. Vault interaction

#### Может ли любой пользователь вывести referral fees из vault на себя

- Результат: No issue found

`vault.fc` действительно разрешает вызывать `withdraw_fee` кому угодно:

- `contracts/vault.fc:50-70`

Но payout всегда уходит в `storage::owner_address`, а не вызывающему:

- `contracts/vault.fc:60-65`

После этого router дополнительно принимает `vault_pay_to` только от корректно вычисленного vault:

- `contracts/router/msgs/vault.fc:9-14`

Так что “permissionless trigger” здесь не равен theft.

---

### 6. TON-specific issues

#### Workchain checks

- Результат: No issue found

Обоснование:

- sender workchain:
  - `contracts/router.fc:15`
- payload addresses:
  - `contracts/router/dex.fc:21-25`
  - `contracts/router/msgs/admin.fc:22-25`
  - `contracts/router/msgs/admin.fc:66-68`
  - `contracts/router/msgs/admin.fc:97-99`
  - `contracts/router/get.fc:7-8`
  - `contracts/router/get.fc:21-22`

#### Storage fee depletion handling

- Результат: No issue found

Во всех критичных маршрутах есть явные gas / storage reserve checks:

- `contracts/router/dex.fc:56-75`
- `contracts/router/msgs/admin.fc:8-10`, `57-59`, `88-90`, `119-121`
- `contracts/router/msgs/pool.fc:45-66`
- `contracts/router/msgs/vault.fc:15`

Явного depletion-атака сценария на reviewed router logic не найдено.

---

## On-chain observations

На момент анализа:

- Router: `EQDAPye7HAPAAl4WXpz5jOCdhf2H9h9QkkzRQ-6K5usiuQeC`
- Admin: `EQBAj_9iYponyRxQgNurrn4t7UNS0aQeteHY7U-H-F_XTy-Z`
- Version: `2.2 release`
- `is_locked = false`
- `temp_upgrade` выглядит пустым, то есть активного pending upgrade по get-method snapshot не видно

---

## Итог

### Подтвержденные проблемы

1. Single-admin контролирует fee updates и `protocol_fee_address` без timelock.
2. Single-admin может мгновенно pause/unpause router и отдельные pools.
3. Router и pools upgradeable, а значит компрометация admin key критична для всей системы.

### Наиболее важный вывод

Router действительно важнее самого пула: именно он является центром доверия и главным governance chokepoint. С точки зрения внешнего permissionless attacker reviewed sender checks и message routing выглядят достаточно аккуратно, но с точки зрения governance risk это сильно централизованная архитектура.

### Рекомендации высокого уровня

1. Перевести `set_fees` и pause-операции под timelock.
2. Использовать multisig для `admin_address`.
3. Мониторить `init_*_upgrade`, `finalize_upgrades`, `update_pool_code`, `update_status`, `set_fees`.
4. Рассматривать router как основной high-value target при дальнейшем исследовании всей Blum/STON.fi интеграции.

