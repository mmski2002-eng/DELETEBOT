# R1 Result: unauthorized treasury execution / withdrawal

## Verdict

`R1` в формулировке `произвольный внешний атакующий может вызвать withdrawal из vault` по текущим данным **не подтверждается**.

Более точная формулировка статуса:

- `Confirmed`: нет
- `Refuted by current evidence`: частично, против исходной гипотезы `arbitrary caller`
- `Residual risk`: остаётся до получения исходников или более глубокой decompilation sender-checks

## Что было проверено

1. Локальный артефакт `vault_txs.json`
2. Live tx history vault через `tonapi`
3. Live account state vault и контрактов-отправителей `0x7bdd97de`
4. Декодирование observed body для `withdraw`
5. Сравнение `code_hash` / `data_hash` у sender-контрактов

## Подтверждённые факты

### 1. У vault действительно есть рабочий `withdraw` path

- vault: `0:a4793bce49307006d3f4e97d815fb4c78ff7655faecf8606111ae29f8d6b41f4`
- opcode: `0x7bdd97de`
- tonapi decode: `daolama_vault_withdraw`

### 2. Это не единичный tx

Live research показал:

- `20` tx с `op_code = 0x7bdd97de` в последних `100` tx vault
- `5` уникальных sender-контрактов

### 3. Все observed sender'ы являются контрактами, не wallet'ами

Ни один observed sender не выглядит как обычный user wallet:

- `source_is_wallet = false` во всех `withdraw` tx

### 4. Sender'ы образуют однотипное семейство контрактов

У 5 разных sender'ов совпадает один и тот же `code_hash`:

- sender `code_hash = 1b9c374c91cf251615da603055fe7fdee1effe45a21536cdd97eedec16675428`

При этом `code_hash` vault другой:

- vault `code_hash = 7920372bb8d58cc9ee0d280d36d1db363a037481e44ab97b5530d9acd9c74e4f`

Это сильный индикатор, что vault принимает `withdraw` не от произвольных сущностей, а от семейства protocol-controlled worker/position contracts.

### 5. Body `withdraw` стабилен по формату

Для всех observed `0x7bdd97de` body стабильно декодируется как минимум до:

- `uint32 opcode`
- `uint64 query_id`
- `coins amount`
- `address recipient`
- затем остаётся `267` бит хвоста

Пример:

- `query_id = 0`
- `amount = 371128857363`
- `recipient = 0:3edc43486341876383e2d778916cc8cdd066cc353eaab5601d0c6948ee2dae47`

### 6. Recipient в body совпадает с фактическим outbound recipient

Это подтверждает, что sender-контракт задаёт адрес вывода внутри `withdraw` body, а не vault вычисляет его независимо.

## Почему это не подтверждает уязвимость

Чтобы подтвердить `R1` как Critical/High vuln, нужно было бы показать хотя бы одно из следующего:

1. `0x7bdd97de` принимается от произвольного sender
2. sender-check отсутствует или обходится
3. можно воспроизвести тот же path с атакующего контракта
4. observed sender не доверенный internal contract, а внешний user-controlled caller

По текущим данным получилось обратное:

1. observed senders не произвольные, а однотипные protocol-like контракты
2. observed sender-set ограничен малым числом контрактов
3. все sender'ы имеют одинаковый код и разные data-state
4. это больше похоже на `vault <- child loan/position contracts`, чем на открытую внешнюю точку входа

## Что именно опровергнуто

Опровергнута упрощённая гипотеза:

`Раз есть observed tx на withdraw, значит любой может вызвать такой же withdraw и вывести средства из vault`

Эта гипотеза **не выдерживает проверки**.

## Что пока не опровергнуто полностью

Остаётся остаточный риск, который без исходников нельзя закрыть на 100%:

1. vault может проверять не `sender address`, а только структуру body
2. vault может доверять любому контракту с определённым поведением
3. возможен edge-case через state-init / clone / address-derivation, если trust model построена неверно
4. хвостовые `267` бит могут нести auth/state binding, но пока они не восстановлены полностью

## Практический итог для responsible disclosure

`R1` сейчас **не стоит отправлять команде как подтверждённую уязвимость**.

Корректный статус:

- `Not confirmed`
- `Needs source / decompilation for final closure`

Если включать `R1` в disclosure, то только как:

- `investigated attack hypothesis`
- `not reproduced`
- `current on-chain evidence suggests internal trusted sender model`

## Артефакты

- `POC/R1_unauthorized_treasury_execution/scripts/decode_observed_withdraw.js`
- `POC/R1_unauthorized_treasury_execution/scripts/build_withdraw_template.js`
- `POC/R1_unauthorized_treasury_execution/scripts/probe_treasury_auth.js`
- `POC/R1_unauthorized_treasury_execution/scripts/research_r1_live.js`

## Следующий лучший шаг

Чтобы закрыть `R1` окончательно, нужен один из двух путей:

1. исходники vault + sender-контрактов
2. decompilation / symbolic review с явной верификацией sender authorization внутри `recv_internal`
