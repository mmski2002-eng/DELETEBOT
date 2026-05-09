# Telegram Mini Apps Security Audit Matrix

## Область аудита и приоритет

Этот чеклист ориентирован на Telegram Mini Apps (TMA) в контексте реальных bug bounty программ, с фокусом на веб-attack surface, границы аутентификации, привязку кошелька и доверие к TON-транзакциям.

### Самые приоритетные классы находок

1. Отсутствие или некорректная валидация `initData` на бэкенде
2. Доверие бэкенда к `window.Telegram.WebApp` / `initDataUnsafe`
3. Ошибки привязки Telegram-пользователя к TON-кошельку
4. Проверка платежей и транзакций только на клиенте
5. XSS через Telegram-контролируемые поля или `start_param`
6. Replay auth- или payment-артефактов
7. Слабая проверка `postMessage` / origin в iframe-контексте
8. Утечка bot token во фронтенде или публичных артефактах

---

## 1. Валидация `initData`

### 1.1 Отсутствие серверной валидации `initData`

- Вектор атаки:
  Бэкенд принимает Telegram identity claims от клиента без проверки подписи Telegram.
- Что проверять:
  Отправлять API-запросы с поддельным `user.id`, `username` или полностью фальшивым `initData`. Пробовать прямой доступ к API без запуска через Telegram.
- Как воспроизвести:
  Перехватить запрос из TMA, заменить `initData` или поля идентичности, повторно отправить на бэкенд и проверить, создается ли сессия или открывается ли доступ к данным другого пользователя.
- Признак уязвимости:
  Сервер аутентифицирует или регистрирует пользователя, даже если `hash` отсутствует, неверен, устарел или полностью контролируется атакующим.
- Impact / severity:
  Обычно `Critical`, так как это authentication bypass или account takeover.
- Уязвимая реализация:
  Бэкенд доверяет `user.id` из JSON-запроса или `initDataUnsafe`.
- Безопасная реализация:
  Бэкенд валидирует raw `initData` по HMAC-схеме Telegram, проверяет `auth_date`, после чего выдает собственную серверную сессию.

### 1.2 Ошибки в HMAC-SHA256 валидации

- Вектор атаки:
  Проверка подписи реализована с ошибками, из-за чего возможны валидные подделки или bypass верификации.
- Что проверять:
  Менять порядок полей, дублировать параметры, убирать поля, изменять URL encoding, модифицировать вложенный `user`-объект, менять `hash`.
- Как воспроизвести:
  Захватить один валидный `initData`, затем изменять:
  `auth_date`, `query_id`, `user.id`, порядок параметров, URL encoding, дубликаты ключей, наличие или отсутствие `hash`.
- Признак уязвимости:
  Сервер принимает искаженный или модифицированный `initData`, который должен был быть отклонен.
- Impact / severity:
  `High` или `Critical`, если возможна подмена личности.
- Типичные ошибки:
  Нет корректной сортировки полей, `hash` включается в проверяемую строку, валидируется не raw input, а уже распарсенный объект, неправильно выводится secret, нет constant-time compare.
- Безопасная реализация:
  Каноникализация полностью соответствует Telegram spec, computed `hash` сравнивается с переданным в constant-time режиме, malformed input отклоняется.

### 1.3 Игнорирование `auth_date` и replay старого `initData`

- Вектор атаки:
  Старый, но когда-то валидный `initData` принимается бессрочно.
- Что проверять:
  Повторно отправлять ранее сохраненный валидный `initData` через часы или дни. Пробовать после logout, с другого устройства или IP.
- Как воспроизвести:
  Сохранить один успешный login request и позже отправить его без изменений.
- Признак уязвимости:
  Бэкенд принимает устаревший `initData` и создает новую аутентифицированную сессию.
- Impact / severity:
  Обычно `Medium` или `High`; может доходить до `Critical`, если это дает устойчивый захват аккаунта.
- Уязвимая реализация:
  Подпись проверяется, но свежесть данных не проверяется.
- Безопасная реализация:
  Узкий TTL, отклонение stale `auth_date`, по возможности one-time server-side login exchange.

### 1.4 Можно ли подделать `initData` без bot token

- Свойство безопасности:
  Если валидация реализована правильно и bot token не утек, практическая подделка `initData` невозможна.
- Что это значит на практике:
  Если подделка проходит, причина обычно в одном из следующих пунктов:
  сломанная валидация, прямое доверие к клиентским данным, утечка токена или replay.
- Severity при утечке токена:
  `Critical`.

---

## 2. Клиентский объект `window.Telegram.WebApp`

### 2.1 Доверие к `initDataUnsafe` или клиентскому `user`

- Вектор атаки:
  Приложение считает клиентские значения из Telegram WebApp-authoritative источником identity или authorization.
- Что проверять:
  Переопределять в DevTools `window.Telegram.WebApp.initDataUnsafe.user.id`, `username`, `language_code`, `is_premium` и похожие поля, затем повторять чувствительные действия.
- Как воспроизвести:
  Monkey-patch значений до `fetch`/XHR либо редактирование request payload через прокси.
- Признак уязвимости:
  Поведение бэкенда меняется в зависимости от attacker-controlled client values.
- Impact / severity:
  `High` или `Critical`, если это дает impersonation или privilege changes.
- Уязвимая реализация:
  API использует `user.id` из фронтенд-запроса, чтобы решать, чьи данные загружать.
- Безопасная реализация:
  Клиент отправляет raw `initData`, а бэкенд сам извлекает identity после проверки подписи.

### 2.2 Авторизация или бизнес-логика по `username`

- Вектор атаки:
  Доступ, бонусы или admin-поведение завязаны на `username`, а не на верифицированную идентичность аккаунта.
- Что проверять:
  Менять `username` на клиенте или искать флоу, где в запросах фигурирует только `username`.
- Как воспроизвести:
  Попробовать имитировать привилегированного пользователя путем редактирования `username` или установить allowlisted handle.
- Признак уязвимости:
  Меняются роли, появляется доступ к чужим данным или открываются привилегированные ресурсы только по `username`.
- Impact / severity:
  Обычно `Medium` или `High`; если затрагивается админка, возможно `Critical`.
- Безопасная реализация:
  Авторизация должна быть привязана к проверенному Telegram `id` и server-side ролям.

### 2.3 Abuse через `start_param` / `startapp`

- Вектор атаки:
  Deep-link параметры влияют на чувствительное поведение без валидации.
- Что проверять:
  Подставлять произвольные referral code, tenant ID, promo identifier, feature flag или URL через `start_param`.
- Как воспроизвести:
  Запускать приложение с crafted `startapp` / `start_param` и отслеживать backend routing, rewards или выбор контекста.
- Признак уязвимости:
  Referral fraud, unauthorized tenant selection, hidden feature access, IDOR или open redirect.
- Impact / severity:
  Обычно `Medium` или `High`.
- Уязвимая реализация:
  `start_param` используется напрямую как доверенный ключ или URL.
- Безопасная реализация:
  Считать его untrusted input, валидировать по строгой схеме и привязывать чувствительные действия к server-side state.

---

## 3. TON Connect (`@tonconnect/ui`, `@tonconnect/sdk`)

### 3.1 Spoofing wallet address при привязке

- Вектор атаки:
  Бэкенд сохраняет адрес кошелька, который прислал клиент, без криптографического доказательства владения.
- Что проверять:
  Подменять wallet address в запросах во время или после подключения. Пытаться привязать чужой адрес к своему Telegram-аккаунту.
- Как воспроизвести:
  Перехватить запросы wallet binding и заменить отправляемый адрес на произвольный.
- Признак уязвимости:
  Привязка кошелька проходит без подписи challenge со стороны кошелька.
- Impact / severity:
  `High` или `Critical`, в зависимости от того, что дает владение кошельком в системе.
- Уязвимая реализация:
  Бэкенд доверяет `walletAddress` из фронтенда после UI-события "connected".
- Безопасная реализация:
  Бэкенд выдает nonce, кошелек его подписывает, сервер верифицирует подпись и один раз связывает address с пользователем.

### 3.2 Доверие к frontend-state "wallet connected"

- Вектор атаки:
  Приложение считает, что UI-состояние подключения доказывает ownership или authorization.
- Что проверять:
  Пробовать флоу, требующие кошелек, только через подмену клиентского состояния или имитацию TonConnect callbacks.
- Как воспроизвести:
  Подменить local state, `postMessage` events или API requests так, чтобы приложение думало, что кошелек подключен.
- Признак уязвимости:
  Защищенные операции проходят без реального подтверждения владения кошельком.
- Impact / severity:
  `High`.
- Безопасная реализация:
  Connection state используется только для UX; ownership подтверждается server-verified signature.

### 3.3 Манипуляция payload перед подписью

- Вектор атаки:
  Атакующий или внедренный скрипт меняет параметры транзакции до показа wallet prompt.
- Что проверять:
  Подменять `to`, `amount`, `payload`, `stateInit`, expiration в объекте, который передается в `sendTransaction`.
- Как воспроизвести:
  Hook TonConnect вызов в DevTools и заменить поля payload до того, как wallet их получит.
- Признак уязвимости:
  Приложение или бэкенд считают, что будет подписана одна транзакция, хотя реально можно подписать materially different payload.
- Impact / severity:
  `High`.
- Уязвимая реализация:
  UI показывает одну сумму/адрес/назначение, а подписываемые данные остаются свободно изменяемыми на клиенте без server-side reconciliation.
- Безопасная реализация:
  Transaction intent строится из server-side состояния, а итоговый settlement проверяется по recipient, amount и payload on-chain.

### 3.4 MITM или spoofing сообщений между TMA и wallet

- Вектор атаки:
  На практике опаснее не классический TLS MITM, а spoofing сообщений внутри приложения, XSS, bridge misuse или fake callbacks.
- Что проверять:
  Изучать wallet communication flow, bridge endpoints, callback handling и любое доверие к client-reported success.
- Как воспроизвести:
  Эмулировать wallet success/cancel состояния, по возможности менять bridge responses, либо использовать XSS для модификации pre-signature состояния.
- Признак уязвимости:
  Бэкенд завершает чувствительные действия только на основании клиентского callback или UI-result.
- Impact / severity:
  `High`.
- Безопасная реализация:
  Финальные state changes должны происходить только после server-side verification, а не после wallet UI callback.

---

## 4. Прямое межконтрактное взаимодействие

### 4.1 Бэкенд верит клиенту, что транзакция отправлена

- Вектор атаки:
  Пользователь сообщает tx hash или success flag, а бэкенд выдает активы, завершает order или claim без on-chain верификации.
- Что проверять:
  Пропускать реальную транзакцию и отправлять fake success artifacts, поддельные tx hash или hash другой нерелевантной транзакции.
- Как воспроизвести:
  Повторно вызывать purchase-complete endpoint с произвольными transaction references или клиентскими success flags.
- Признак уязвимости:
  Товар, кредит, mint или доступ выдаются без соответствующего платежа в блокчейне.
- Impact / severity:
  `Critical`.
- Уязвимая реализация:
  Fulfillment происходит только по результату TonConnect callback на клиенте.
- Безопасная реализация:
  Бэкенд проверяет транзакцию через доверенный node/indexer и только потом завершает операцию.

### 4.2 Слабая проверка отправителя

- Вектор атаки:
  Система видит, что контракт получил платеж, но не проверяет, что отправитель совпадает с ожидаемым кошельком для данного пользователя или order.
- Что проверять:
  Платить с другого кошелька, relay или proxy и смотреть, засчитывается ли действие нужному аккаунту.
- Как воспроизвести:
  Использовать транзакцию другого кошелька или подменить связь между Telegram user и wallet identity.
- Признак уязвимости:
  Платеж или действие засчитываются не тому пользователю или без доказательства intended ownership.
- Impact / severity:
  `High`.
- Безопасная реализация:
  Проверять sender address, recipient address, amount, payload и связь с заранее созданным order.

### 4.3 Replay attacks на TON transaction references

- Вектор атаки:
  Одна успешная транзакция может быть использована для нескольких действий.
- Что проверять:
  Повторно отправлять один и тот же tx hash, order reference, payload memo или signed intent.
- Как воспроизвести:
  Завершить одну покупку, затем повторно вызвать fulfillment endpoint с теми же transaction identifiers.
- Признак уязвимости:
  Double credit, repeated reward claims, повторный mint или несколько state changes по одной транзакции.
- Impact / severity:
  `High` или `Critical`.
- Уязвимая реализация:
  Нет consumed-state tracking для transaction IDs, order IDs или уникальных payload reference.
- Безопасная реализация:
  One-time order IDs, уникальные payload markers и проверка processed-records.

---

## 5. Типичные web-уязвимости в контексте TMA

### 5.1 XSS через Telegram-контролируемые поля профиля

- Вектор атаки:
  Telegram user-controlled поля небезопасно рендерятся в DOM.
- На какие поля смотреть:
  `username`, `first_name`, `last_name`, `photo_url`, любые отраженные profile fields и значения из `start_param`.
- Что проверять:
  Stored и reflected XSS через `innerHTML`, template injection, markdown renderer или небезопасные component APIs.
- Как воспроизвести:
  Установить crafted profile field там, где это возможно, или инжектить payload через backend storage, а затем открыть TMA или admin views.
- Признак уязвимости:
  Выполнение JavaScript, кража токена, форсированные действия или манипуляция wallet flow.
- Impact / severity:
  Обычно `High`; `Critical`, если это ведет к account takeover, wallet drain или privileged backend actions.
- Уязвимая реализация:
  Рендер user fields как raw HTML.
- Безопасная реализация:
  Только text rendering или строгий sanitizer для действительно необходимого rich content.

### 5.2 Применимость CSRF в TMA

- Вектор атаки:
  Бэкенд TMA использует cookie-based auth и state-changing endpoints без CSRF-защиты.
- Что проверять:
  Можно ли инициировать аутентифицированные state-changing запросы cross-site с автоматической отправкой cookies.
- Как воспроизвести:
  Собрать PoC HTML form или cross-site fetch и проверить чувствительные endpoints.
- Признак уязвимости:
  Изменение профиля, wallet binding или другие действия проходят через cross-site request.
- Impact / severity:
  `Medium` или `High` в зависимости от чувствительности action.
- Примечание:
  Если используются bearer token в заголовках и корректный CORS, классический CSRF менее вероятен, но это нужно проверять, а не предполагать.
- Безопасная реализация:
  `SameSite` cookies, anti-CSRF token, корректный CORS и отсутствие state changes через GET.

### 5.3 Безопасность `postMessage` в iframe / embedded-контексте

- Вектор атаки:
  Приложение доверяет любому posted message или использует wildcard origin rules.
- Что проверять:
  Найти все listeners на `message` и определить, валидируются ли `origin`, `source` и message schema.
- Как воспроизвести:
  Отправлять crafted `postMessage` payloads из другого окна или вложенного контекста, имитируя auth, wallet или payment events.
- Признак уязвимости:
  State changes происходят из сообщений произвольного происхождения.
- Impact / severity:
  `Medium` до `Critical`, в зависимости от достижимого действия.
- Уязвимая реализация:
  `postMessage('*')` или `window.addEventListener('message', ...)` без строгих проверок.
- Безопасная реализация:
  Жесткий origin allowlist, валидация типа сообщения и отказ от доверия к client-only success signals.

### 5.4 Слабый CSP и реальность TMA-окружения

- Вектор атаки:
  Слабый CSP упрощает эксплуатацию XSS или не ограничивает script injection.
- Что проверять:
  Наличие `unsafe-inline`, `unsafe-eval`, слишком широких script allowlist, JSONP-подобных гаджетов и доверенных third-party цепочек.
- Как воспроизвести:
  Анализировать CSP заголовки вместе с DOM sinks; сам по себе CSP не спасает, если dangerous rendering уже существует.
- Признак уязвимости:
  CSP практически не мешает exploit chain, который должен был быть ограничен.
- Impact / severity:
  Часто `Low` сам по себе, но `High` как часть XSS-цепочки.
- Безопасная реализация:
  Tight `script-src`, nonce/hash-based script execution и устранение unsafe DOM sinks.

---

## 6. Инфраструктурные векторы и утечки секретов

### 6.1 Перехват трафика и HTTPS-допущения

- Вектор атаки:
  Чувствительный трафик раскрывается из-за plain HTTP, mixed content, слабых cookie flags или доверия к враждебным устройствам / прокси.
- Что проверять:
  Что все API работают только по HTTPS, нет mixed content, выставлен HSTS, а auth tokens не утекaют в URL.
- Как воспроизвести:
  Проксировать приложение, просматривать все запросы и искать downgrade или plaintext-каналы.
- Признак уязвимости:
  Секреты или session tokens передаются небезопасно.
- Impact / severity:
  `High` или `Critical`, если раскрываются токены или персональные данные.
- Примечание:
  Отсутствие certificate pinning само по себе обычно не является валидной находкой.
- Безопасная реализация:
  HTTPS везде, `Secure` и `HttpOnly` cookies, HSTS и отсутствие чувствительных данных в query string.

### 6.2 Утечка bot token во фронтенде или публичных артефактах

- Вектор атаки:
  Telegram bot token попадает в JavaScript bundle, source maps, config files, logs или публичный репозиторий.
- Что проверять:
  Искать секреты в bundle, static assets, env leaks, debug endpoints и CI artifacts.
- Как воспроизвести:
  Grep по собранным JS, source maps, public config и архивным фронтенд-артефактам на token-shaped patterns.
- Признак уязвимости:
  Извлекаемый bot token или эквивалентный signing secret.
- Impact / severity:
  Обычно `Critical`.
- Безопасная реализация:
  Bot token хранится только на сервере, ротируется при утечке и никогда не отправляется клиенту.

### 6.3 Чувствительные данные в `localStorage` / `sessionStorage`

- Вектор атаки:
  Долгоживущие auth artifacts доступны любому XSS или hostile script в TMA-контексте.
- Что проверять:
  Проверять browser storage на session tokens, raw `initData`, wallet binding secrets, order nonces и privileged flags.
- Как воспроизвести:
  Просмотреть storage после login, wallet binding и purchase flows.
- Признак уязвимости:
  В JavaScript-readable storage лежат переиспользуемые секреты.
- Impact / severity:
  `Medium` или `High`, в зависимости от типа данных.
- Уязвимая реализация:
  Долгоживущие bearer tokens в `localStorage`.
- Безопасная реализация:
  Предпочтительны server-managed sessions или short-lived rotating tokens; high-value secrets не должны храниться в web storage.

---

## Практический workflow для тестирования

### Фаза 1: Граница идентичности

1. Запустить TMA штатно и перехватить все auth-related запросы.
2. Определить, получает ли бэкенд raw `initData`, распарсенные user fields или оба формата.
3. Подменять `user.id`, `username`, `auth_date` и проверять, сохраняется ли успешная аутентификация.
4. Повторно использовать тот же валидный login payload позже, чтобы проверить freshness и replay handling.

### Фаза 2: Доверие к клиенту и deep links

1. Переопределить значения `window.Telegram.WebApp.initDataUnsafe` в DevTools.
2. Найти логику, завязанную на `username`, `is_premium` или `start_param`.
3. Подавать произвольные `startapp` / `start_param` значения для referral, tenant, feature и routing abuse.

### Фаза 3: Привязка кошелька и целостность транзакции

1. Определить, как состояние wallet connection отражается в запросах.
2. Проверить, требует ли wallet ownership signed nonce.
3. Перехватить построение TonConnect transaction и менять recipient, amount и payload.
4. Проверить, опирается ли fulfillment на client-reported success или на on-chain confirmation.

### Фаза 4: Web attack surface

1. Проследить все render paths для Telegram-controlled data.
2. Проверить все `message` listeners и origin checks.
3. Оценить CSP вместе с dangerous DOM APIs.
4. Определить cookie-модель и применимость CSRF.

### Фаза 5: Секреты и storage

1. Ищите bot token и другие credentials в client assets.
2. Проверьте `localStorage`, `sessionStorage`, cookies и IndexedDB.
3. Посмотрите, не попадают ли чувствительные данные в URL, logs или analytics payloads.

---

## Самые сильные bug bounty сценарии

### Наиболее перспективные находки

- Полный auth bypass через подделку или replay `initData`
- Account takeover через backend trust к Telegram identity fields
- Spoofing wallet ownership без signed challenge
- Завершение покупки / mint / claim без реальной on-chain верификации
- Replay одной оплаты или транзакции для нескольких credit/claim
- Stored или reflected XSS с кражей сессии или манипуляцией транзакцией
- Утечка bot token, позволяющая злоупотреблять подписью или контролем бота

### Более слабые находки сами по себе

- Отсутствие certificate pinning
- Слабый CSP без exploit path
- Client-side spoofing, который меняет только UI и не влияет на бэкенд

---

## Эталон безопасной реализации

### Telegram identity

- Сервер валидирует raw `initData`
- HMAC рассчитывается строго по Telegram spec
- `auth_date` проверяется с узким TTL
- После валидации бэкенд выдает собственную сессию

### Wallet ownership

- Бэкенд выдает nonce
- Кошелек подписывает nonce
- Бэкенд проверяет подпись и привязывает address
- Nonce одноразовый и быстро истекает

### Payment settlement

- Бэкенд создает order до оплаты
- Ожидаемые recipient, amount и payload хранятся server-side
- Fulfillment происходит только после on-chain verification
- Order и transaction references помечаются как consumed

### Web security

- Telegram-controlled данные рендерятся как text, а не HTML
- `postMessage` проверяется по origin и schema
- Нет чувствительных state changes по client-only callbacks
- Секреты никогда не отправляются клиенту

---

## Быстрые эвристики для severity

- `Critical`:
  auth bypass, account takeover, fake wallet ownership с monetary impact, завершение платежа без реальной оплаты, утечка bot token
- `High`:
  XSS с влиянием на сессию или wallet flow, replay с дублированием ценности, слабая sender verification, client-side only trust в критичных действиях
- `Medium`:
  referral abuse, CSRF для не-финансовых действий, storage exposure переиспользуемых auth artifacts
- `Low` / `Info`:
  UI-only spoofing, отсутствие pinning без других проблем, hardening gaps без эксплуатируемости

---

## Заметки для реальных ассессментов

- Все, что приходит из браузера или TMA runtime, нужно считать attacker-controlled, если это не подтверждено криптографически на сервере.
- Всегда разделяйте три разных trust-вопроса:
  Telegram identity, wallet ownership и transaction finality.
- Многие high-impact баги появляются потому, что разработчики смешивают эти три доверительные границы в одно предположение.
