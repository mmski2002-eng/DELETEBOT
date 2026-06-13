# Observed R1 Case From Local Artifacts

Источник: `vault_txs.json`

## Наблюдение

В локальном артефакте есть подтвержденная входящая транзакция в:

- `0:a4793bce49307006d3f4e97d815fb4c78ff7655faecf8606111ae29f8d6b41f4`
- alias: `daolama-ton-vault.ton`

Ключевые поля observed tx:

- `op_code = 0x7bdd97de`
- `decoded_op_name = daolama_vault_withdraw`
- `source = 0:ca7d0cc5688f4ecc490428fea63b264cd9031f78ed120a91571d30b4a5b45265`
- `success = true`

После этой входящей транзакции vault создает крупный outbound transfer:

- `value = 484093005671`
- destination `0:3edc43486341876383e2d778916cc8cdd066cc353eaab5601d0c6948ee2dae47`

## Почему это важно для R1

Это уже подтверждает, что:

1. у контракта есть рабочий `withdraw`-path;
2. у нас есть реальный opcode для проверки authz;
3. можно строить PoC вокруг вопроса:
   - кто именно имеет право прислать `0x7bdd97de`
   - что именно валидируется кроме opcode
   - можно ли воспроизвести тот же path от недоверенного sender

## Что уже удалось восстановить из body

Observed body успешно декодируется как минимум до следующих полей:

- `opcode = 0x7bdd97de`
- `query_id = 0`
- `amount = 371128857363`
- `recipient = 0:3edc43486341876383e2d778916cc8cdd066cc353eaab5601d0c6948ee2dae47`

Важно:

- `recipient` совпадает с фактическим `out_msgs[0].destination`
- значит body действительно несет адрес вывода
- observed `amount` не равен в точности `out_msgs[0].value`, что указывает либо на fee subtraction, либо на более сложную бизнес-логику

## Что пока неизвестно

- полная схема body;
- является ли source trusted contract, admin proxy или другой internal worker;
- есть ли проверка sender в коде;
- есть ли дополнительные state checks.

## Следующий шаг PoC

1. Восстановить структуру body для `0x7bdd97de`.
2. Выделить минимальные обязательные поля.
3. Смоделировать то же сообщение от недоверенного sender.
4. Проверить, приводит ли это к:
   - reject на auth stage
   - или к несанкционированному outgoing transfer.
