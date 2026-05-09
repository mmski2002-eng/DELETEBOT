# R2 Plan: payload substitution

## Гипотеза

Проверяем, можно ли:

1. согласовать один payload;
2. исполнить другой payload;
3. или повторно использовать старый approval / intent с подменёнными параметрами.

## Что должно быть у уязвимой системы

Для подтверждения `R2` обычно нужны признаки:

- раздельные фазы `approve/queue` и `execute`
- отдельный `proposal_id`, `payload_hash`, `query_id` или `execution_id`
- хранение intent в state между двумя транзакциями
- возможность подать на execute другой body / recipient / amount / state_init

## Что проверяем в DAOLama artifacts

1. Есть ли у `vault` отдельный execute opcode
2. Есть ли у `vault` двухфазная модель исполнения
3. Есть ли on-chain evidence `queue -> execute`
4. Есть ли binding между `query_id` и фактическим payload
5. Есть ли признаки mutable payload в `withdraw` path

## Критерии подтверждения

`R2` подтверждается, если найдено хотя бы одно:

- payload в state хранится не по hash, а в mutable форме
- execute принимает payload, не связанный с ранее approved hash
- recipient / amount / body / state_init можно подменить между фазами
- replay другого approved payload приводит к новому выводу средств

## Критерии опровержения

`R2` не подтверждается, если:

- у исследуемого контракта вообще нет двухфазной approve/execute модели
- observed path однофазный и вызывается trusted worker-контрактом
- нет evidence отдельного execution opcode или queued state
