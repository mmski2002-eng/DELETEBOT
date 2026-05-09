# R1 PoC: Unauthorized Treasury Execution / Withdrawal

Severity target: `Critical`

## Цель

Проверить, можно ли вызвать treasury execution / withdrawal:

- без governance vote;
- без timelock;
- не от доверенного sender;
- с произвольным payload.

## Гипотеза уязвимости

Treasury или executor контракт доверяет:

- только opcode;
- только формату payload;
- caller, переданному в body;
- proposal ID без жесткой сверки состояния и sender.

Если гипотеза верна, атакующий сможет инициировать вывод средств или исполнение произвольного action.

## Минимальные артефакты, без которых PoC не закрыть

Нужно получить хотя бы одно из:

1. FunC/Tact source treasury / executor
2. production address treasury + observed execute tx body
3. ABI / opcode schema
4. decompiled `recv_internal` ветки

## Пошаговый сценарий PoC

### Вариант A. Source-first

1. Найти `recv_internal`/`recv_external` treasury.
2. Найти ветки `withdraw`, `execute`, `send`, `transfer`, `upgrade`.
3. Проверить:
   - есть ли `sender == governance/timelock/multisig`
   - есть ли `proposal.executed == 0`
   - есть ли `now() >= eta`
   - есть ли `payload_hash == stored_hash`
4. Если хотя бы одна из проверок отсутствует:
   - собрать минимальный body
   - отправить его от недоверенного sender в sandbox/testnet/fork
   - подтвердить изменение state или outgoing action

### Вариант B. Transaction-first

1. Взять реальную execute/withdraw транзакцию treasury.
2. Извлечь opcode и структуру body.
3. Сформировать аналогичное сообщение:
   - с другим sender
   - без предшествующего queue/approve
   - с невалидным proposal state
4. Отправить сообщение в controlled environment.
5. Успех PoC:
   - контракт не отклоняет вызов на auth check;
   - возникает outgoing transfer / action;
   - или state меняется так, будто вызов был легитимным.

## Что именно должно быть отвергнуто безопасной реализацией

Контракт должен делать `throw` хотя бы по одному из условий:

- sender не равен trusted governance/timelock;
- proposal не существует;
- proposal не в `Queued/Executable`;
- timelock еще не истек;
- payload hash не совпадает;
- action уже исполнялся.

## Индикаторы уязвимости

- execute path вызывается только по opcode;
- нет sender check;
- sender check использует адрес из body, а не реальный `sender()`;
- execute принимает payload из текущего сообщения, а не из сохраненного proposal;
- withdraw доступен owner/admin path без timelock;
- executed flag ставится после external send.

## Критерий успешного PoC

PoC считается успешным, если недоверенный sender способен добиться хотя бы одного эффекта:

1. перевод TON / jetton / NFT из treasury;
2. запуск arbitrary internal message;
3. смена конфигурации/адресов;
4. фиксация `executed`/state transition без легитимного governance path.

## Следующий практический шаг

Заполнить `TARGET_TEMPLATE.json`, после чего:

1. декодировать реальный execute body;
2. собрать минимальный поддельный body;
3. прогнать через локальный тест или controlled endpoint.

## Текущий прогресс по локальным артефактам

Для observed `daolama_vault_withdraw` уже подтверждено:

- `opcode = 0x7bdd97de`
- `query_id = 0`
- далее в body идет поле, которое корректно парсится как `coins`
- следующее поле совпадает с фактическим outbound recipient

То есть практический forged template уже выглядит как:

`withdraw(opcode, query_id, amount, recipient, ...optional_tail)`

Неизвестным остается:

- есть ли обязательный trailing tail после `recipient`
- есть ли sender-bound auth в коде, которая делает body бесполезным без trusted caller
- есть ли state-dependent preconditions
