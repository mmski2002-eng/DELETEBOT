# Blum Potential Findings and Research Notes

## Статус документа

Этот файл содержит:

- подтвержденные технические наблюдения по публичным артефактам Blum
- сильные гипотезы для проверки в живом TMA / bot / wallet flow
- предварительную оценку риска и impact

Важно:

- ниже не перечислены подтвержденные эксплуатацией баги в проде
- это рабочий security research log по состоянию на 6 мая 2026 года
- каждый пункт нужно доводить до подтверждения через живое тестирование

---

## 1. Слабая CSP на `help.blum.io`

### Статус

Подтвержденное техническое наблюдение

### Вектор атаки

Если на `help.blum.io` существует любой XSS, HTML injection, markdown injection, content injection или компрометация внешнего контента, текущая CSP почти не ограничивает эксплуатацию.

### Доказательство

Из HTTP response headers для `https://help.blum.io/blum-general-faq`:

- `script-src 'self' 'unsafe-inline' 'unsafe-eval' *`
- `connect-src *`
- `frame-src *`
- `default-src 'self' *`

Также:

- `frame-ancestors https:`

Что означает:

- разрешены inline scripts
- разрешен `unsafe-eval`
- разрешены внешние script sources практически откуда угодно
- разрешены внешние connect destinations

### Потенциальный ущерб

Если появляется XSS или injection в help center:

- кража пользовательских данных из help context
- phishing внутри доверенного домена Blum
- выполнение произвольного JS
- редирект на вредоносные wallet / support pages
- усиление impact любой контентной инъекции

### Предварительная severity-оценка

- сама по себе: `Low` / `Hardening gap`
- как усилитель реального XSS: `High`

### Что проверять дальше

- есть ли user-influenced content в help center
- можно ли инжектить HTML/markdown через support/workflow integrations
- есть ли unsafe search, reflected params или third-party widgets

### Безопасная реализация

- убрать `unsafe-inline` и `unsafe-eval`
- убрать wildcard из `script-src` и `connect-src`
- ограничить `frame-src`
- перейти на nonce/hash-based CSP

---

## 2. Высокорисковый пользовательский ввод в `Memepad`

### Статус

Подтвержденный product surface, потенциальная уязвимость

### Вектор атаки

`Memepad` позволяет создателю токена отправлять богатый пользовательский ввод:

- `Icon`
- `Name`
- `Ticker`
- `Description`
- `Banner`
- `Social media links`
- `Token Share`

Если хотя бы часть этого рендерится небезопасно или слабо валидируется, возможны:

- stored XSS
- phishing through malicious social links
- open redirect / javascript URL issues
- DOM injection
- impersonation of legitimate tokens

### Доказательство

Из `Memepad FAQ`:

- токен создается через форму с `Icon`, `Name`, `Ticker`, `Description`, `Banner`, `Social Media links`
- в FAQ отдельно предупреждают о fake tokens, подделке `Name`, `Ticker`, `Description`, `Social Links`

Это подтверждает, что:

- пользовательский контент действительно отображается другим пользователям
- spoofing и misleading content уже признаны продуктовым риском

### Потенциальный ущерб

- кража средств через malicious links
- массовый phishing под видом “официального” токена
- XSS при небезопасной отрисовке описания / ссылок / баннеров
- подмена визуальной идентичности известных токенов

### Предварительная severity-оценка

- phishing / fake-token abuse: `Medium`
- stored XSS с выполнением JS в приложении: `High` / `Critical`

### Что проверять дальше

- допускаются ли HTML entities, markdown, SVG, scriptable image formats
- фильтруются ли `javascript:`, `data:`, malformed URLs
- как рендерятся `Description` и `Social Links`
- есть ли preview / card / share screens с unsafe rendering
- можно ли создать токен с визуально неотличимым названием/тикером и обойти safeguards

### Безопасная реализация

- строгая валидация ссылок и схем URL
- только text rendering для описаний
- sanitize user-generated rich content
- дополнительная anti-impersonation логика для token metadata

---

## 3. Потенциальный takeover live stream через `stream key`

### Статус

Подтвержденный product surface, потенциальная уязвимость

### Вектор атаки

В `Memepad` только создатель токена может получить `stream key` и запустить live stream для token page.

Если stream key:

- можно переиспользовать бесконечно
- не ротируется
- отображается повторно без re-auth
- утаскивается через client-side leaks / logs / screenshots / debug APIs
- не привязан строго к конкретному token owner / active stream session

то возможен hijack live stream на странице токена.

### Доказательство

Из `Memepad Videostream Quick Start Guide`:

- создатель нажимает `Start Live Stream`
- получает `stream key`
- использует `rtmps://cf.stream.mvs.wtf:443/live`
- стрим отображается на token page

### Потенциальный ущерб

- захват прямого эфира чужого токена
- распространение scam/phishing контента
- репутационный ущерб
- манипуляция рынком и social engineering в реальном времени

### Предварительная severity-оценка

- `Medium` / `High`, зависит от того, удается ли реально захватить или подменить трансляцию

### Что проверять дальше

- можно ли получить stream key повторно без подтверждения
- меняется ли key после остановки стрима
- можно ли стримить в чужую token page по утекшему key
- есть ли API endpoint для stream key и насколько он защищен
- есть ли IDOR в token ownership check перед выдачей key

### Безопасная реализация

- короткоживущие одноразовые stream keys
- ротация после каждого старта/остановки
- строгая server-side проверка ownership
- аудит логов и исключение key из client-visible telemetry

---

## 4. Высокоценная поверхность в `Blum Trading Bot` из-за автоматически создаваемых кошельков

### Статус

Подтвержденный product surface, потенциальная уязвимость

### Вектор атаки

После принятия Terms & Conditions бот автоматически создает пользователю новые TON и Solana wallet addresses.

Также из интерфейса доступны:

- import wallet
- export private key / recovery phrase
- reset wallet
- withdraw funds

Это делает критичными любые баги в:

- session binding
- Telegram identity binding
- wallet ownership checks
- re-authentication перед export/reset
- CSRF / client-side trust / message spoofing в этих флоу

### Доказательство

Из `Your TON and Solana Wallets` и `Main Menu and Features`:

- бот автоматически генерирует TON и Solana кошельки
- доступен export private key / recovery phrase
- доступен reset wallet
- доступен import wallet
- доступны withdraw operations

### Потенциальный ущерб

- полная кража средств
- компрометация приватных ключей
- подмена или обнуление кошелька пользователя
- account/wallet takeover

### Предварительная severity-оценка

- при реальном bypass: `Critical`

### Что проверять дальше

- требуется ли повторное подтверждение / пароль / biometric step перед export key
- можно ли вызвать export/reset через forged request
- можно ли после session fixation получить доступ к wallet controls
- есть ли расхождения между Telegram session и wallet session
- влияет ли reconnect / relaunch на доступ к wallet export

### Безопасная реализация

- жесткая повторная аутентификация перед export/reset/import
- server-side session binding
- минимизация client-side trust
- строгий аудит high-risk wallet actions

---

## 5. Риск abuse в referral system через wash trading / self-referral / volume gaming

### Статус

Подтвержденный reward logic, потенциальная уязвимость

### Вектор атаки

Referral rewards начисляются только за:

- `Sell` operations
- токены, уже listed on DEX
- сделки через `Blum Memepad`

Также начисляются `Meme Points` за:

- launch token
- listing on DEX
- trading volume on Memepad
- trading volume via Blum Trading Bot

Это создает сильный стимул для:

- self-referral farming
- controlled multi-account trading
- wash trading on listed tokens
- artificial volume generation ради points / TON rewards

### Доказательство

Из `Trading Referral System FAQ`:

- Level 1: `20%` комиссий
- Level 2: `2.5%`
- учитываются только qualifying sell operations after DEX listing via Memepad

Из `Meme Points FAQ`:

- +500 за launch token
- +10,000 за DEX listing
- +50 points за каждые $10 volume on Memepad
- +750 points за каждые $10 volume via Trading Bot

### Потенциальный ущерб

- фарм rewards и points
- искусственное увеличение активности
- drain incentive pools
- экономический ущерб продукту
- искажение лидербордов и reward distribution

### Предварительная severity-оценка

- `Medium` / `High`, зависит от того, можно ли это монетизировать в TON / airdrop / withdrawable value

### Что проверять дальше

- есть ли anti-self-referral controls
- можно ли замкнуть сеть аккаунтов под одним оператором
- засчитываются ли circular trades
- можно ли получить reward без economic loss больше, чем награда
- есть ли защита от wash trading между связанными wallets
- блокируются ли trades в one-operator clusters

### Безопасная реализация

- anti-sybil и anti-wash heuristics
- запрет саморефералов и связанных аккаунтов
- reward eligibility по net economic activity, а не по сырому объему
- anomaly detection на referral / volume patterns

---

## 6. Риск spoofing / weak verification в wallet binding для `Perps`

### Статус

Подтвержденный product flow, потенциальная уязвимость

### Вектор атаки

Для `Blum Perps` требуется:

- connected wallet via TON Connect
- USDT on TON
- перевод из connected wallet в `Perps wallet`
- затем перевод обратно в `main Blum wallet`

Если wallet ownership или deposit completion подтверждаются слабо, возможны:

- spoofing connected wallet
- зачет депозита не тому пользователю
- fake completion
- replay старого transaction reference
- несогласованность между `main Blum wallet` и `Perps wallet`

### Доказательство

Из `Perpetual Wallet and Balance`:

- deposit делается через TON Connect wallet
- баланс затем отображается в Perps wallet
- withdrawal отправляет средства обратно в main Blum wallet
- Perps используют cross margin

### Потенциальный ущерб

- ошибки атрибуции средств
- unauthorized balance credit
- withdrawal abuse
- trading with incorrectly credited collateral

### Предварительная severity-оценка

- `High` / `Critical`, если удастся добиться неверного зачета средств или неправомерного вывода

### Что проверять дальше

- есть ли signed ownership proof beyond UI connection state
- как backend подтверждает deposit success
- можно ли reuse tx hash / reference
- можно ли манипулировать client-side confirmation flow
- можно ли race-condition’ом выводить при незавершенном settlement

### Безопасная реализация

- строгая server-side verification wallet ownership
- on-chain confirmation before balance credit
- consumed-state tracking for tx references
- atomic accounting between perps balance and main wallet balance

---

## 7. Поверхность для account confusion через import/export/reset wallet flows

### Статус

Подтвержденный product surface, потенциальная уязвимость

### Вектор атаки

В `Blum Trading Bot` одновременно поддерживаются:

- auto-generated wallets
- imported wallets
- private key export
- reset and create new wallet

Комбинация этих флоу часто приводит к:

- account confusion
- stale binding bugs
- wallet reassignment issues
- recovery / export actions against the wrong account context

### Потенциальный ущерб

- пользователь управляет не тем кошельком, который видит интерфейс
- funds sent to one wallet while actions apply to another
- referral / points / positions привязаны к старому или чужому wallet context

### Предварительная severity-оценка

- `Medium` / `High`, при прямой потере средств — `Critical`

### Что проверять дальше

- что происходит с referral state, balances и positions после reset
- корректно ли очищаются старые wallet bindings
- можно ли импортировать wallet и получить доступ к данным/активности другого контекста
- как ведет себя система после relaunch / reconnect / Telegram account switch

### Безопасная реализация

- явные server-side ownership transitions
- полная инвалидизация старых session/binding artifacts
- невозможность смешивания нескольких wallet contexts без explicit confirmation

---

## 8. Публичные caveats и инфраструктурные заметки

### `app.blum.io` закрыт за Cloudflare Access

Это не уязвимость, а наблюдение:

- `app.blum.io` редиректит на Cloudflare Access login flow
- публичный web terminal, похоже, не открыт полностью анонимно

Практический вывод:

- часть живого surface потребует Telegram / bot / authenticated path

### Отсутствие `security.txt`

На `https://www.blum.io/.well-known/security.txt` возвращается “Invalid .well-known request”.

Это:

- не security bug само по себе
- максимум informational/hardening note

---

## Приоритет следующей верификации

### Самые сильные кандидаты на реальные баги

1. wallet export / reset / import authorization
2. perps deposit / withdraw accounting and completion logic
3. referral and meme points abuse via wash trading / self-referral
4. stored XSS / malicious-link injection in Memepad token metadata
5. stream key takeover / unauthorized livestream control

### Что нужно для следующей итерации

- живой запуск `@Blum` / `@BlumCryptoBot` / `@BlumCryptoTradingBot`
- перехват auth и wallet-related traffic
- проверка session storage / request structure
- mutation testing на wallet, referral, points и perps flows
