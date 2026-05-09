# REPORT ROUND 2

## Candidate 5

Cross-collection replay of signed `NoDns` deploy payload.

## Итоговый статус

Кандидат подтвержден как `contract-level design flaw`, но не подтвержден как текущая production-уязвимость.

Что подтверждено:

- signed hash действительно не привязан к адресу collection;
- `full_domain` и, шире, semantic context берутся из состояния целевой collection;
- если две collection используют один и тот же `public_key + subwallet_id`, один и тот же signed payload может быть принят обеими;
- это воспроизводится в локальном sandbox PoC.

Что не подтверждено:

- в проверенной production-выборке не найдено двух разных collection с одинаковыми `public_key + subwallet_id`;
- в текущем gift-flow sender дополнительно привязан через `force_sender_address`, причем observed sender — это `Fragment Gift Minter`, а не конечный пользователь.

Практический вывод:

- архитектурный риск реальный;
- для текущего production-impact ключевой prerequisite пока не найден;
- значит это не `confirmed production vuln`, а `conditional candidate / design issue`.

## 1. Проверка кода: signed hash не включает collection context

В [common.fc](/c:/Users/Escape/Desktop/DELETEBOT/TON/TON%20DNS/telemint/func/common.fc:315) `unpack_signed_cmd` считает hash от slice после signature:

- `signature`
- `subwallet_id`
- `valid_since`
- `valid_till`
- `cmd`

В этот hash contract-side не добавляются:

- `my_address()`
- address collection
- `full_domain`
- `workchain`
- `network / chain id`

Следовательно, сама подпись не domain-separated по collection context.

## 2. Проверка кода: `full_domain` берется из target collection state

В [nft-collection-no-dns.fc](/c:/Users/Escape/Desktop/DELETEBOT/TON/TON%20DNS/telemint/func/nft-collection-no-dns.fc:80) collection читает собственные данные через `unpack_collection_data()`, а затем в [строках 81-82](/c:/Users/Escape/Desktop/DELETEBOT/TON/TON%20DNS/telemint/func/nft-collection-no-dns.fc:81) вызывает `deploy_item(..., full_domain, ...)`.

Дальше в [строке 54](/c:/Users/Escape/Desktop/DELETEBOT/TON/TON%20DNS/telemint/func/nft-collection-no-dns.fc:54) формируется:

- `cell token_info = pack_token_info(token_name, full_domain);`

Это означает:

- signed payload сам по себе не фиксирует namespace collection;
- semantic meaning payload зависит от того, какая именно collection его принимает.

## 3. Production-сравнение collection

Проверка воспроизводимо запускается так:

```bash
cd sandbox-tests
npm run round2
```

Скрипт: [round2.js](/c:/Users/Escape/Desktop/DELETEBOT/TON/TON%20DNS/sandbox-tests/round2.js:1)

### Проверенная выборка

- `Anonymous Telegram Numbers`
- `Telegram Usernames`
- `Snoop Doggs`
- `Heart Lockets`
- `Precious Peaches`
- `Snow Globes`
- `Xmas Stockings`
- `Jacks-in-the-Box`
- `Genie Lamps`

### Наблюдения по ключам и subwallet

`Anonymous Telegram Numbers`

- `public_key = 71de902f194a53293a0aa982070ca71acdbda490056d0ee8e821cc088451cda9`
- `subwallet_id = 12`

`Telegram Usernames`

- `public_key = 71de902f194a53293a0aa982070ca71acdbda490056d0ee8e821cc088451cda9`
- `subwallet_id = 3`

Вывод:

- usernames и anonymous numbers делят один `public_key`;
- но у них разные `subwallet_id`;
- значит cross-replay между ними этим механизмом блокируется.

Gift collections из выборки:

- `Snoop Doggs` -> `subwallet_id = 105`
- `Heart Lockets` -> `subwallet_id = 96`
- `Precious Peaches` -> `subwallet_id = 26`
- `Snow Globes` -> `subwallet_id = 77`
- `Xmas Stockings` -> `subwallet_id = 86`
- `Jacks-in-the-Box` -> `subwallet_id = 82`
- `Genie Lamps` -> `subwallet_id = 45`

У них общий `public_key`:

- `be3a1bc943496314139a36e2ab85f53fefb5e32c098fe6cef85094d6cdebc898`

Но в проверенной выборке у каждой collection свой `subwallet_id`.

Ключевой вывод по production:

- reuse `public_key` подтвержден;
- reuse `public_key + same subwallet_id` в проверенной выборке не найден.

Это самый важный аргумент против немедленной квалификации как production bug.

## 4. Что видно по текущему gift-flow

Для `Xmas Stockings` я отдельно проверил свежий `TelemintDeployV2` event через tonapi.

Наблюдаемый payload показывает:

- `SubwalletId: 86`
- `ForceSenderAddress: Fragment Gift Minter`
- `RewriteSenderAddress: конечный получатель`

То есть в текущем observed flow sender-bound проверка есть, и sender — это не пользователь, а minter/backend wallet.

Это меняет модель атаки:

- даже если бы две gift-collection случайно делили один `subwallet_id`, внешний пользователь не смог бы сам replay-нуть payload;
- для replay понадобился бы тот же `forced sender`, то есть сам minter flow.

Поэтому текущий observed production-pattern выглядит менее эксплуатируемым, чем исходная гипотеза.

## 5. Sandbox PoC

Локальный PoC подтверждает сам design flaw.

В sandbox были созданы три `NoDns` collection:

- `Collection A`: same `public_key`, same `subwallet_id`, `full_domain = "numbers"`
- `Collection B`: same `public_key`, same `subwallet_id`, `full_domain = "other"`
- `Collection C`: same `public_key`, but `subwallet_id = S + 1`

Один и тот же signed `deploy_v2` payload был отправлен:

1. в `A`
2. затем тем же sender в `B`
3. затем как control в `C`

### Результат

`A`

- collection tx success
- item deploy tx success
- `teleitem_msg_deploy.tokenInfo.name = "round2-proof"`
- `teleitem_msg_deploy.tokenInfo.domain = "numbers"`

`B`

- collection tx success
- item deploy tx success
- `teleitem_msg_deploy.tokenInfo.name = "round2-proof"`
- `teleitem_msg_deploy.tokenInfo.domain = "other"`

`C`

- collection tx aborted
- `exitCode = 203`
- это `wrong_subwallet_id`

То есть один и тот же signed payload был валиден сразу в двух разных collection, пока у них совпадали `public_key + subwallet_id`.

Именно это и доказывает cross-collection replay на уровне дизайна.

## 6. Почему finding пока не production-confirmed

Для production-impact этой находке нужен хотя бы один из двух сильных признаков:

1. две реальные production collection с одинаковыми `public_key + subwallet_id`;
2. наблюдаемый flow, где `force_sender_address` не мешает внешнему replay.

На данный момент:

- признак `1` не найден;
- признак `2` тоже не подтвержден для текущих gift-flow, потому что sender привязан к `Fragment Gift Minter`.

Поэтому сильная, но аккуратная квалификация такая:

- `confirmed design flaw`
- `not confirmed as current production exploit`

## 7. Рекомендуемый статус для репорта

Лучше всего описывать находку так:

- `Signed NoDns deploy payloads are not domain-separated by collection context.`
- `This enables cross-collection replay if signing key and subwallet_id are reused.`
- `Local sandbox confirms exploitability under that configuration.`
- `Current production reuse of the same public_key + subwallet_id pair was not confirmed in the checked sample.`

Итоговая severity-рекомендация:

- `Medium / conditional` как design issue;
- повышать до `High` только если будет найден реальный production pair с одинаковыми `public_key + subwallet_id` и релевантным sender model.

## 8. Финальный вывод

Раунд 2 не дал подтверждения текущей production-уязвимости, но дал важный и чистый технический результат:

- signed payload действительно не привязан к collection;
- локально это exploitable;
- в реальном production я нашел reuse ключа между разными collection, но не нашел reuse того же `subwallet_id`;
- observed современные gift payload содержат `force_sender_address = Fragment Gift Minter`, что дополнительно сужает практическую атаку.

Итог:

- гипотеза как архитектурный баг подтверждается;
- как текущий bounty-grade production bug — пока недостаточно доказательств.
