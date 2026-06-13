# R3 Result: replay executed proposal / replay executed intent

## Verdict

`R3` как `replay уже исполненного withdraw/execute intent` по текущим данным **не подтверждается**.

Более точный статус:

- `Confirmed`: нет
- `Not confirmed`: да
- `Residual risk`: остаётся, потому что без исходников невозможно доказать точную anti-replay логику внутри worker contracts

## Что было проверено

1. Последние `100` tx vault
2. Все observed `0x7bdd97de` (`daolama_vault_withdraw`)
3. Повторы `raw_body`
4. Декодированные поля `query_id`, `amount`, `recipient`

## Подтверждённые факты

### 1. В observed dataset нет точных повторов `withdraw` body

Среди `20` observed `withdraw` tx:

- `duplicateBodies = 0`

То есть один и тот же `raw_body` повторно не встречается.

### 2. `query_id` во всех observed body равен `0`

Это важно двояко:

- само по себе это выглядит слабо, если anti-replay ожидался на уровне `query_id`
- но при этом replay всё равно не наблюдается, потому что сами body различаются

### 3. Уникальность observed исполнения обеспечивается не `query_id`, а самим body

В observed body меняются:

- `amount`
- иногда длина body
- хвостовые данные после `recipient`

Это означает, что execution intent фактически различается на уровне полного payload.

### 4. Повторного исполнения идентичного withdraw не найдено

Не найдено evidence такого вида:

- тот же sender
- тот же `raw_body`
- повторный успешный outbound transfer

## Почему replay не подтверждается

Чтобы подтвердить `R3`, нужен минимум один из следующих фактов:

1. тот же body был принят дважды
2. тот же execution id был принят дважды
3. observed duplicate intent привёл к повторному выводу

По текущим данным не найдено ни одного из них.

## Что это значит по модели риска

Наиболее вероятная модель сейчас такая:

- `vault` исполняет однофазную команду от trusted worker contract
- replay uniqueness, если она есть, контролируется на стороне worker / position contract
- `vault` может вообще не быть главным местом anti-replay логики

То есть для `vault-level replay` данных недостаточно, а observed tx history не даёт положительного сигнала на уязвимость.

## Что не доказано окончательно

Остаточный риск всё ещё есть:

1. мы не отправляли identical body повторно в live environment
2. нет исходников worker contracts
3. хвостовые `267` бит body пока не разложены полностью по смыслу
4. именно в этих хвостовых битах может жить per-intent uniqueness marker

## Практический итог

`R3` сейчас **не стоит эскалировать как подтверждённую находку**.

Корректный статус для disclosure:

- `investigated`
- `not reproduced`
- `current on-chain evidence does not show replay of executed withdraw intent`

## Артефакты

- `POC/R3_replay_executed_proposal/POC_PLAN_ru.md`
- `POC/R3_replay_executed_proposal/scripts/research_r3_live.js`

## Следующий лучший шаг

Чтобы закрыть `R3` сильнее, нужен один из путей:

1. исходники sender worker contracts
2. decompilation их anti-replay state transitions
3. controlled testnet reproduction с повторной отправкой identical body
