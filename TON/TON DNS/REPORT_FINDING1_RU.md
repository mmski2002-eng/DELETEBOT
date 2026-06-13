# Отчет по гипотезе 1

## Тема

Возможность фронтрана или повторного использования `signed deploy payload` в `Telemint NoDns`, если в подписанном сообщении отсутствует обязательная привязка к `sender_address`.

## Краткий вывод

Да, из всех проверенных гипотез именно эта выглядит действительно стоящей.

Она подтверждается на двух уровнях:

1. На уровне кода контрактов риск реален:
   `telemint/func/nft-collection-no-dns.fc` допускает `signed deploy` без обязательного `force_sender_address`.

2. На уровне ончейн-данных найден реальный успешный production-кейс:
   в истории коллекции анонимных номеров есть успешная транзакция `telemint_deploy_v2`, где `restrictions == null`.

Это означает, что гипотеза не является чисто теоретической. Контракт действительно допускает такой режим, и такой payload реально использовался в production.

При этом после дополнительной проверки свежей выборки нужно квалифицировать находку точнее.

Подтверждено следующее:

- подтвержден исторический production-risk;
- подтвержден exploitable design pattern;
- подтверждено, что production исторически использовал payload без `restrictions`;
- в свежей наблюдаемой выборке последние найденные deploy-попытки уже используют `force_sender_address`.

Поэтому корректнее говорить не “текущий production массово уязвим”, а:

`контракт архитектурно допускает фронтран signed first-bid deploy; исторически такой режим реально использовался в production; в более поздних наблюдаемых deploy-попытках виден переход на sender binding.`

Дополнительно важно понимать вероятный характер исправления.

По доступным данным это выглядит не как исправление самого контракта, а как operational mitigation на стороне backend. Иными словами, контрактный дизайн остался прежним, а эксплуатируемый сценарий, вероятно, был закрыт тем, что backend начал всегда добавлять `force_sender_address` в выдаваемый payload.

## Что проверялось

### 1. Код контракта

Файл:
[nft-collection-no-dns.fc](/c:/Users/Escape/Desktop/DELETEBOT/TON/TON%20DNS/telemint/func/nft-collection-no-dns.fc:1)

Ключевые места:

- [строки 1-9](/c:/Users/Escape/Desktop/DELETEBOT/TON/TON%20DNS/telemint/func/nft-collection-no-dns.fc:1)
  `unwrap_signed_cmd` проверяет подпись, `subwallet_id`, `valid_since`, `valid_till`, но не делает обязательной привязки к фактическому `sender_address`.

- [строки 25-39](/c:/Users/Escape/Desktop/DELETEBOT/TON/TON%20DNS/telemint/func/nft-collection-no-dns.fc:25)
  `check_restrictions` показывает, что `force_sender_address` является опциональным.

- [строка 44](/c:/Users/Escape/Desktop/DELETEBOT/TON/TON%20DNS/telemint/func/nft-collection-no-dns.fc:44)
  Проверка sender выполняется только через `check_restrictions(restrictions, sender_address)`.

Из этого следует:

- если `restrictions == null`, sender не привязан к signed payload;
- если `restrictions` есть, но `has_force_sender_address == 0`, sender также не привязан;
- такой signed deploy payload ведет себя как bearer token: кто первым отправил, тот и использовал.

### 2. Production on-chain проверка

Была проверена production-коллекция анонимных номеров:

- collection address: `EQAOQdwdw8kGftJCSFgOErM1mBjYPe4DBPq8-AhF6vr9si5N`
- explorer page:
  https://tonviewer.com/EQAOQdwdw8kGftJ70D5dnQCNEG_sFrYd5a2yNrQ6FkFW3ugq

Дополнительно была просмотрена история `telemint_deploy_v2` через публичный TON API.

Проверка шла в два этапа:

1. Подтверждение самого факта существования production-транзакций без `restrictions`.
2. Проверка свежей выборки последних `telemint_deploy_v2`, чтобы понять, наблюдается ли такой же паттерн в более позднем production-потоке.

### 3. Результат ончейн-поиска

Найдена успешная production-транзакция без `restrictions`:

- tx hash: `22156ea5d6ca49dfab8196e740b93fd0e31858f05b79456ddd67e901836181ae`
- дата: `2022-12-24`
- `success: true`
- `token_name: 88808088880`
- `restrictions: null`

Это важное доказательство, потому что оно показывает не просто “контракт допускает”, а “такой режим реально использовался в production”.

### 4. Результат проверки более свежей выборки

Отдельно была проверена свежая наблюдаемая выборка последних `46` транзакций `telemint_deploy_v2`, найденных в истории этой production-коллекции.

Результат:

- `7` payload были с `force_sender_address`;
- `39` payload были без `restrictions`;
- `0` payload были с `restrictions`, но без `force_sender_address`.

Однако здесь критически важна хронология.

Последние найденные deploy-попытки в выборке относятся к `2025-07-21`, и в них уже используется:

- `force_sender_address`
- в части случаев также `rewrite_sender_address`

Последние найденные payload без `restrictions` в этой же выборке относятся к декабрю `2022`.

Из этого следует более точный вывод:

- исторически production действительно использовал unsafe payload без `restrictions`;
- в свежей наблюдаемой части потока подтверждается использование sender binding;
- по ончейну не подтверждается тезис, что backend до сих пор массово выдает такие payload;
- но архитектурная возможность проблемы в контракте сама по себе не устранена.

### 5. Вероятный способ исправления

Отдельно была проверена история репозитория `telemint` в части `nft-collection-no-dns.fc`.

Наблюдение:

- логика с опциональным `force_sender_address` была добавлена в контракт сразу при появлении `NoDns`-варианта;
- в доступной git-истории не видно отдельного последующего исправления этой части логики;
- при этом ончейн-поведение production-потока со временем меняется: старые payload бывают без `restrictions`, а более поздние deploy-попытки уже несут `force_sender_address`.

Практически это сильнее всего похоже на следующий сценарий:

- сам контракт не менялся;
- контрактный риск остался на уровне дизайна;
- mitigation был сделан на стороне backend/payload generation policy.

Это правдоподобно и с технической стороны: уже используемый on-chain контракт часто невозможно просто “поправить на месте”, если в нем заранее не был предусмотрен безопасный upgrade path. Поэтому для production-системы наиболее реалистичный путь снижения риска — оставить контракт как есть и перестать выдавать unsafe payload.

## Почему гипотеза действительно ценная

Это не косметический issue и не спор о TVM semantics.

Если signed deploy выдается без `force_sender_address`, то:

- payload можно перехватить из pending transaction;
- другой участник может отправить тот же signed body раньше;
- контракт примет его как валидный, потому что подпись и окно валидности корректны;
- первый bidder будет не тот, кому payload выдавался изначально.

Для редких анонимных номеров или других ценных NoDns-активов это уже имеет прямой бизнес-эффект.

## Статус находки

Рекомендуемый статус:

`Подтверждено как исторический production issue / подтверждено как реальный design flaw`

Не рекомендую писать:

`100% актуальная текущая production-уязвимость для всех deploy flow`

Рекомендую писать:

`Контракт допускает фронтран signed first-bid deploy, если backend выдает payload без force_sender_address; такой тип payload исторически подтвержден в production on-chain, однако в свежей наблюдаемой выборке более поздние deploy-попытки уже используют sender binding. По наблюдаемым данным mitigation, вероятно, был внедрен на стороне backend, а не в самом контракте.`

## Рекомендуемая severity

Базово:

- `High`, если речь идет о production flow без обязательного sender binding;
- `Medium`, если текущий backend уже везде исправлен, но контракт сам по себе по-прежнему допускает unsafe integration.

С учетом найденного успешного production-кейса я бы описывал находку как минимум не ниже `Medium`, а при bounty-подаче аргументировал как `High historical impact / High conditional severity`.

## Рекомендация по формулировке для submission

Можно использовать такую формулировку:

`NftCollectionNoDns accepts signed deploy payloads where sender binding is optional. I confirmed from code that sender verification is only enforced if restrictions.force_sender_address is present. I also found a successful production transaction from December 24, 2022 in the Anonymous Numbers collection where telemint_deploy_v2 was executed with restrictions = null. This confirms that production historically used bearer-style signed deploy payloads. At the same time, more recent observable deploy attempts use force_sender_address, so the current production flow should be described as historically confirmed and architecturally possible, but not proven to be still broadly unmitigated today.`

## Что можно считать финальным выводом

Если отвечать коротко:

Да, первая гипотеза стоящая.

Это единственная из проверенных гипотез, которая:

- подтверждается кодом;
- подтверждается реальным on-chain production-кейсом;
- описывает понятный и значимый атакующий сценарий;
- не разваливается при проверке TON message semantics.

При этом после дополнительной ончейн-проверки правильнее утверждать не то, что текущий production массово выдает unsafe payload, а то, что:

- такой режим достоверно существовал в production;
- контрактный дизайн остается опасным;
- в более поздних наблюдаемых deploy-потоках виден переход на `force_sender_address`.

То есть наиболее точная интерпретация на сегодня такая:

- баг был реальным;
- в контракте он концептуально остался;
- текущая наблюдаемая защита, вероятнее всего, обеспечивается backend-политикой выдачи payload, а не исправлением on-chain логики.

Остальные гипотезы из исходного отчета либо не подтвердились, либо пока остаются только исследовательскими.
