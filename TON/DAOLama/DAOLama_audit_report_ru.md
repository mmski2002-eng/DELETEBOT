# Аудит безопасности DAOLama

Дата анализа: 2026-05-06

Формат анализа: on-chain reverse engineering + публичная документация.

Статус исходников: в рабочей папке исходный код отсутствовал. Публичный FunC/Tact-репозиторий контрактов DAOLama в ходе анализа не был найден. Выводы ниже основаны на:

- публичной документации `docs.daolama.co`;
- live-данных `tonapi.io` на 2026-05-06;
- наблюдении реальных транзакций и декодированных сообщений TON;
- байткоде и persistent data нескольких on-chain контрактов.

Важно: из-за отсутствия исходников часть проверок можно выполнить только частично. В отчете это явно помечено как `Insufficient information to confirm this finding`.

## 1. Модель протокола

### 1.1. Подтвержденные контракты и роли

По публичным данным удалось подтвердить следующие сущности:

- `daolama.ton`
  - адрес кошелька/операционного owner-контракта: `0:30b036e8165fe21ae69f94d9f9f79f4739a99e9e4bd01100f06a43b9e4263648`
  - интерфейс: `wallet_v4r2`
- `daolama-ton-vault.ton`
  - адрес: `0:a4793bce49307006d3f4e97d815fb4c78ff7655faecf8606111ae29f8d6b41f4`
  - интерфейсы по tonapi: `daolama_vault`, `jetton_master`
  - контракт реально принимает NFT через `nft_ownership_assigned`
  - после получения NFT создаёт/финансирует отдельный адрес займа и переводит NFT дальше
- индивидуальные адреса займов
  - пример: `0:35ec80cbe770695608eef8e41d962be015bb55a0a408be16231c8d7954c9cbbc`
  - интерфейсы tonapi не распознаны
  - on-chain поведение: получают TON от vault и пересылают почти всю сумму заемщику, сохраняя состояние активным
- sale/auction контракты формата Getgems
  - пример: `0:4573d70ff04a5b75b1ff09fd89ede48dd14d8845c2e26bd504db0f7d68f02f81`
  - интерфейс: `nft_sale_getgems_v3`
  - используются для продажи NFT, выставленных во время займа или после дефолта

### 1.2. Подтвержденный жизненный цикл займа

Наблюдаемый on-chain flow для TON-займа:

1. Пользователь отправляет NFT в `daolama-ton-vault.ton`.
2. Vault получает внутреннее сообщение `nft_ownership_assigned` (`0x05138d91`).
3. В том же tx vault:
   - отправляет сообщение `0x00000001` на новый или заранее рассчитанный адрес займа;
   - отправляет `nft_transfer` (`0x5fcc3d14`) обратно NFT-контракту с новым владельцем = адрес займа.
4. Адрес займа получает TON от vault.
5. Адрес займа почти полностью пересылает сумму пользователю.

Подтвержденный пример:

- vault tx `lt=75250121000005`
- затем loan tx `lt=75250121000007`
- loan получил `152.84 TON` от vault и отправил `152.69 TON` пользователю

Это подтверждает модель `vault -> loan escrow -> borrower`.

### 1.3. Подтвержденный жизненный цикл NFT-залога

Наблюдаемый путь NFT:

1. NFT-контракт присылает `nft_ownership_assigned` в vault.
2. Vault инициирует `nft_transfer` того же NFT на адрес конкретного займа.
3. После этого именно loan-контракт, а не vault, становится фактическим держателем залога.
4. Для некоторых активов после дефолта или листинга используется отдельный sale-контракт.

### 1.4. Какие сообщения подтверждены

Подтверждены следующие сообщения:

- `nft_ownership_assigned` (`0x05138d91`) от NFT item -> vault
- `nft_transfer` (`0x5fcc3d14`) от vault -> NFT item
- `0x00000001` от vault -> loan contract
- пустое внутреннее сообщение / plain TON transfer от loan -> borrower
- сообщения в Getgems-style sale контракт при листинге

### 1.5. Какие сообщения могут bounce-иться

По архитектуре TON bounce-риски есть как минимум у следующих сообщений:

- `vault -> loan` при финансировании адреса займа;
- `vault -> NFT item` при передаче NFT на loan address;
- `loan -> borrower` при выдаче займа;
- `loan -> NFT item` при возврате NFT;
- `loan/seller -> sale contract` при листинге;
- возможные служебные excess/burn_notification сообщения LP/jetton-ветки vault.

Однако без исходников нельзя подтвердить, какие именно `send_mode`, `bounce` и `bounced` handlers использованы.

### 1.6. Какие данные приходят от пользователя, NFT-контракта и внешних систем

Подтверждено:

- от NFT-контракта в `nft_ownership_assigned` приходят:
  - `query_id`
  - `prev_owner`
  - `forward_payload`
- в `forward_payload` присутствует дополнительная бизнес-логика DAOLama
  - это видно по нестандартному вложенному payload внутри `nft_ownership_assigned`
- от пользователя на адрес займа приходит plain TON при обслуживании долга или иных действиях

Не подтверждено:

- наличие on-chain оракула floor price;
- наличие on-chain LTV;
- наличие on-chain USDT loan path;
- наличие on-chain interest accrual логики;
- наличие on-chain liquidation threshold формулы.

### 1.7. Trusted contracts

С высокой вероятностью доверенными являются:

- `daolama-ton-vault.ton`
- `daolama.ton`
- NFT item contracts одобренных коллекций
- sale contracts, совместимые с Getgems/marketplace flow

Не удалось подтвердить:

- отдельный price oracle contract;
- отдельный admin/config contract;
- отдельный USDT jetton vault/wallet.

## 2. Проверка критических инвариантов

### 2.1. Заём не выдаётся, если NFT фактически не получен протоколом

Частично подтверждено.

По наблюдаемому flow vault сначала получает `nft_ownership_assigned`, и только затем:

- переводит NFT на адрес займа;
- финансирует loan address;
- loan address уже потом выплачивает TON пользователю.

Это сильный положительный сигнал: в подтвержденном сценарии выдача займа не происходила до получения `nft_ownership_assigned`.

Ограничение:

- без исходника нельзя доказать, что существует строгая проверка `sender == expected_nft_item`;
- без исходника нельзя доказать, что `nft_ownership_assigned` от фальшивого NFT отвергается.

### 2.2. NFT не возвращается, если долг не погашен полностью

Insufficient information to confirm this finding.

Нужен исходный код loan-контракта и обработчиков входящих TON-сообщений, либо хотя бы полные истории нескольких контрактов с успешным repayment.

### 2.3. Один NFT нельзя использовать в нескольких активных займах

Insufficient information to confirm this finding.

По observed flow NFT после получения переводится на отдельный loan address, что уменьшает риск double-pledge на том же item address. Но без кода нельзя подтвердить:

- блокировку повторного использования одного и того же NFT при реентри-подобной асинхронности;
- защиту от direct transfer / duplicate init flow;
- запрет переиспользования при bounced transfer.

### 2.4. LTV считается только по актуальной и проверенной цене

Insufficient information to confirm this finding.

Во всех доступных on-chain следах не удалось подтвердить ни oracle contract, ни price feed, ни getter для floor price/LTV.

### 2.5. Ликвидация возможна, если LTV выше порога

Insufficient information to confirm this finding.

Наблюдаемый публичный DAOLama flow больше похож на сроковой NFT-backed pawn/escrow с продажей по expiry, чем на классический mark-to-market liquidation engine. Без кода или документации по oracle/LTV это утверждение не проверяется.

### 2.6. Протокол не принимает фальшивые NFT

Insufficient information to confirm this finding.

Это одна из самых критичных непроверенных областей текущего анализа.

### 2.7. Bounced-сообщения не оставляют контракт в неконсистентном состоянии

Insufficient information to confirm this finding.

Без исходников невозможно надежно проверить:

- наличие `recv_bounced`;
- корректный rollback state;
- идемпотентность после failed external send;
- порядок `state update -> external send`.

## 3. Findings

Подтвержденных эксплуатируемых уязвимостей по имеющимся данным не установлено.

Причина отсутствия findings не в том, что протокол доказанно безопасен, а в том, что:

- исходный FunC/Tact-код отсутствует;
- не найден публичный репозиторий с contract source;
- часть ключевой логики, критичной для безопасности, не выводится достоверно только из байткода и нескольких декодированных tx.

Ниже перечислены области, где риск высокий, но подтверждение без исходников невозможно.

## 4. Additional Security Checklist

### 4.1. На что нужно получить код в первую очередь

- полный исходник `daolama-ton-vault.ton`
- полный исходник индивидуального loan-контракта
- контракт/модуль, который формирует `forward_payload` внутри `nft_ownership_assigned`
- контракт sale/auction handoff logic
- если существует: oracle/floor-price contract
- если существует: USDT jetton vault/wallet path

### 4.2. Самые важные ручные проверки

- Проверить, что vault валидирует `sender` как реальный NFT item из разрешённой коллекции, а не любой контракт, умеющий послать `0x05138d91`.
- Проверить, что `prev_owner` сверяется с ожидаемым заемщиком.
- Проверить, что `forward_payload` нельзя подделать для изменения суммы займа, receiver, срока, скидки или fee path.
- Проверить, что `nft_transfer` в loan contract происходит только после полного закрытия долга.
- Проверить, что при failed transfer NFT не остаётся заблокированным и не возникает zombie-loan.
- Проверить, что loan contract не может отправить заемщику средства, если NFT transfer на loan address не завершился успешно.
- Проверить все `bounced` handler и то, что `query_id` не допускает replay/duplicate processing.
- Проверить, что direct plain TON transfer в loan contract не позволяет обойти expected payment format.
- Проверить, что default/expiry path нельзя grief-ить частичными платежами или dust TON.
- Проверить send modes, особенно для:
  - `vault -> loan`
  - `vault -> NFT item`
  - `loan -> borrower`
  - `loan -> NFT item`
  - `loan -> sale contract`

### 4.3. Подозрительные паттерны, которые обязательно аудировать в исходнике

- `state updated before external message success`
- отсутствие или неполный `recv_bounced`
- отсутствие строгой проверки коллекции и item address
- использование `query_id = 0` без собственной anti-replay логики
- передача бизнес-параметров через `forward_payload` без аутентификации
- plain internal messages без строгой авторизации по `sender`
- отсутствие `raw_reserve`/reserve discipline для долгоживущих escrow-контрактов
- sale contract handoff без атомарной связки долга и права на NFT

### 4.4. Edge cases TON, которые требуют тестов

- bounce при `nft_transfer` из vault в loan address
- bounce при выплате займа заемщику
- bounce при возврате NFT
- недофинансированный gas budget в цепочке `NFT -> vault -> loan -> borrower`
- повторный `nft_ownership_assigned` с тем же item
- прямой перевод NFT без корректного payload
- прямой перевод TON без expected body
- repayment в точный момент expiry
- repayment после начала sale/auction
- partial repayment, overpayment, dust payment
- storage fee erosion для старых loan-контрактов

### 4.5. Неподтвержденные экономические риски

- on-chain oracle/LTV path не подтвержден
- USDT support не подтвержден
- interest accrual logic не подтверждена
- liquidation threshold / stale price handling не подтверждены

Если эти механики существуют off-chain или в закрытом контракте, риск профиля протокола значительно повышается, и без исходников аудит нельзя считать полным.

## 5. Final Assessment

Текущее состояние безопасности нельзя оценить как полностью проверенное, потому что ключевая логика протокола недоступна в исходном виде.

Что удалось подтвердить положительно:

- observed TON loan flow действительно построен через отдельный escrow/loan address;
- выдача средств в подтвержденных транзакциях происходила только после `nft_ownership_assigned`;
- протокол использует отдельный vault-уровень и sale/market handoff, а не прямую выдачу с одного кошелька;
- NFT в observed flow переводится дальше на dedicated loan address, что архитектурно лучше, чем хранение всех залогов на одном простом hot wallet.

Самые опасные классы рисков при текущей нехватке исходников:

1. NFT validation
2. Async message handling и bounce recovery
3. Аутентификация `forward_payload`
4. Correctness repayment/default/sale state machine
5. Trusted-contract boundary между vault, loan и sale contracts

Приоритет исправлений и проверки:

1. Получить и зааудировать исходник vault.
2. Получить и зааудировать исходник loan contract.
3. Подтвердить правила whitelist коллекций и item validation.
4. Подтвердить repayment/default/sale transitions на тестах.
5. Подтвердить `recv_bounced`, send modes и reserve policy.

Recommended next steps:

1. Предоставить полный репозиторий FunC/Tact-контрактов.
2. Предоставить TL-B схемы всех кастомных payload и op-кодов.
3. Предоставить тесты на:
   - fake NFT
   - bounced NFT transfer
   - bounced loan payout
   - duplicate `nft_ownership_assigned`
   - expiry to sale transition
   - repayment around deadline
4. Если есть USDT path, отдельно предоставить:
   - jetton wallet/master addresses
   - decimal handling
   - fee path
   - oracle path
   - stale price rules

Итог: на основании доступных данных нельзя честно выпустить заключение уровня `secure` или `no issues`. Можно лишь сказать, что базовый observed TON escrow flow выглядит архитектурно осмысленным, но наиболее критичные инварианты безопасности остаются неподтвержденными без исходного кода.
