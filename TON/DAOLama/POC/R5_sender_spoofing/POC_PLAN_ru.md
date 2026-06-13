# R5 Plan: sender spoofing

## Гипотеза

Проверяем, можно ли обмануть trust model межконтрактных вызовов в TON:

1. заставить `vault` принять сообщение как будто оно пришло от trusted worker
2. использовать fake contract с тем же интерфейсом
3. подменить sender-bound semantics через неверную валидацию `msg.sender`

## Что должно быть у уязвимой системы

Для подтверждения `R5` обычно нужны признаки:

- контракт доверяет полям body вместо реального sender address
- контракт доверяет любому коду с тем же интерфейсом
- адрес trusted sender вычисляется небезопасно
- sender authorization отсутствует или обходится через clone/state-init pattern

## Что проверяем в observed DAOLama flow

1. Кто реально вызывает `daolama_vault_withdraw`
2. Есть ли признаки семьи trusted worker contracts
3. Есть ли связь `user action -> worker contract -> vault`
4. Ограничен ли recipient одним адресом на worker
5. Есть ли evidence, что `vault` принимает withdraw от кошельков или произвольных контрактов

## Критерии подтверждения

`R5` подтверждается, если найдено хотя бы одно:

- withdraw принимается от произвольных sender'ов
- fake/clone sender теоретически достаточен без address binding
- observed route показывает отсутствие real sender checks

## Критерии опровержения

`R5` не подтверждается, если:

- withdraw вызывается только ограниченным trusted sender-set
- sender'ы образуют однотипное protocol-controlled семейство
- каждый sender стабильно связан со своим recipient / position flow
- observed chain route выглядит как `user -> worker -> vault`, а не `user -> vault`
