# R3 Plan: replay executed proposal / replay executed intent

## Гипотеза

Проверяем, можно ли повторно использовать уже исполненный intent:

1. повторно отправить тот же execute body
2. повторно использовать тот же proposal / execution id
3. повторно вызвать тот же path после успешного вывода

## Что должно быть у уязвимой системы

Для подтверждения replay обычно нужны признаки:

- идентификатор исполнения не помечается как consumed
- `query_id` / `proposal_id` / `nonce` не проверяется
- identical body может быть принят повторно
- одна и та же команда приводит к повторному выводу средств

## Что проверяем в observed DAOLama flow

1. Есть ли повторы `raw_body` среди executed `withdraw`
2. Есть ли стабильный `query_id` без признаков consumed-state
3. Есть ли одинаковые sender + recipient + amount комбинации
4. Есть ли evidence, что replay блокируется отдельным state marker
5. Есть ли признаки, что replay-prevention делегирована worker-контрактам, а не vault

## Критерии подтверждения

`R3` подтверждается, если найдено хотя бы одно:

- повтор одного и того же body приводит к повторному успешному выводу
- identical `proposal_id` / `query_id` допускается повторно
- execution uniqueness никак не bind'ится к state

## Критерии опровержения

`R3` не подтверждается, если:

- identical executed bodies не наблюдаются
- каждая executed команда уникальна по body
- observed anti-replay логика, вероятно, живёт во внешних worker contracts
- нет evidence повторного исполнения одного и того же intent
