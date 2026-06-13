# Blum Verification Report

## Статус

Этот документ фиксирует результат попытки **подтвердить или опровергнуть** ранее сформулированные гипотезы по Blum.

Категории статусов:

- `Confirmed` — наблюдение или слабость подтверждена технически
- `Not confirmed` — гипотеза не подтвердилась на доступном материале
- `Needs live TMA access` — для верификации нужен реальный Telegram / wallet / bot flow
- `Blocked by edge` — проверка упирается в Cloudflare / access layer и не дает сделать вывод о самом приложении

---

## 1. Слабая CSP на `help.blum.io`

### Статус

`Confirmed`

### Что проверено

Запрошены HTTP headers у:

- `https://help.blum.io/blum-general-faq`

### Что подтверждено

Возвращается CSP:

- `default-src 'self' *`
- `script-src 'self' 'unsafe-inline' 'unsafe-eval' *`
- `connect-src *`
- `frame-src *`
- `frame-ancestors https:`

Также:

- `X-Frame-Options` отсутствует

### Вывод

Это подтвержденная **слабая защитная конфигурация** help-домена.

### Практический смысл

Само по себе это не remote exploit, но:

- сильно повышает impact любого XSS / HTML injection
- делает help-домен плохим кандидатом на containment
- потенциально допускает framing с любого `https` origin

### Severity

- standalone: `Low`
- как multiplier для реальной injection bug: `High`

---

## 2. Clickjacking / permissive framing на `help.blum.io`

### Статус

`Confirmed`

### Что проверено

Из response headers:

- `frame-ancestors https:`
- отсутствует `X-Frame-Options`

### Что это означает

Любой `https` origin формально подходит под `frame-ancestors https:`.

Это не лучшая практика и создает **разрешающий framing policy**.

### Ограничения

- это не равно автоматически exploit-ready clickjacking on critical actions
- help center сам по себе может не содержать чувствительных state-changing действий

### Вывод

Технически permissive framing policy подтверждена.

### Severity

- обычно `Low` / `Info`
- выше только если удастся связать с чувствительными действиями на help-домене

---

## 3. Stored XSS / malicious-link injection в `Memepad` metadata

### Статус

`Needs live TMA access`

### Что подтверждено

Из официальной документации подтверждено, что пользователь при создании токена может задавать:

- `Icon`
- `Name`
- `Ticker`
- `Description`
- `Banner`
- `Social media links`

Также docs прямо предупреждают о fake tokens и подмене:

- `Name`
- `Ticker`
- `Description`
- `Social Links`

### Что еще не подтверждено

Не подтверждено, что:

- description рендерится небезопасно
- social links допускают опасные схемы
- metadata может приводить к XSS

### Почему нельзя закрыть вопрос сейчас

Нужен живой доступ к:

- форме создания токена
- token page render
- share/preview/card views

### Следующая проверка

Попробовать через реальный `Memepad`:

- `javascript:` / `data:` / malformed `https` links
- HTML entities / SVG / long unicode payloads
- phishing-like duplicate branding

---

## 4. Takeover live stream через `stream key`

### Статус

`Needs live TMA access`

### Что подтверждено

Docs подтверждают:

- только creator может нажать `Start Live Stream`
- приложение выдает `stream key`
- используется RTMPS endpoint `rtmps://cf.stream.mvs.wtf:443/live`

### Что не подтверждено

Не подтверждено, что:

- ключ можно переиспользовать
- ключ не ротируется
- ключ можно украсть или применить к чужой token page
- существует IDOR при выдаче ключа

### Следующая проверка

В живом флоу проверить:

- повторная выдача ключа
- смена ключа после stop/start
- возможность использовать старый key
- выдачу ключа после смены владельца / другого аккаунта / другого токена

---

## 5. Wallet export / import / reset authorization в Trading Bot

### Статус

`Needs live TMA access`

### Что подтверждено

Из docs подтверждено, что в `Blum Trading Bot` есть:

- auto-generated TON and Solana wallets
- import wallet
- export private key / recovery phrase
- reset wallet
- withdraw operations

Также подтверждено, что в публично доступной документации для этих действий не найдено явного описания дополнительных security steps, таких как:

- повторная аутентификация
- PIN / password prompt
- second-factor confirmation
- отдельный challenge перед export/reset

### Что не подтверждено

Не подтверждено, что:

- export доступен без re-auth
- reset можно вызвать без достаточного подтверждения
- import/export/reset страдают от session confusion
- чужой Telegram context может получить доступ к wallet controls

### Почему это важно

Если любой из этих bypass существует, impact почти наверняка `Critical`.

### Следующая проверка

Нужен live bot path с проверкой:

- требуется ли отдельное подтверждение перед export/reset
- можно ли дернуть эти действия через подмененные client requests
- сохраняется ли доступ после relaunch / account switch / reconnect

---

## 6. Abuse referral / Meme Points через wash trading / self-referral

### Статус

`Needs live TMA access`

### Что подтверждено

Из docs подтверждено:

- referral rewards начисляются за qualifying `Sell` operations after DEX listing via `Blum Memepad`
- 2 уровня рефералок: `20%` и `2.5%`
- `Meme Points` начисляются за:
  - launch token
  - DEX listing
  - trading volume on Memepad
  - trading volume via Trading Bot

Также по доступной публичной документации не найдено явного описания того, что система:

- блокирует self-referral
- дисквалифицирует one-operator multi-account patterns
- фильтрует wash-trading-like reward abuse

### Что не подтверждено

Не подтверждено, что система реально допускает:

- self-referral
- circular referrals
- wash trading for rewards
- volume inflation with positive net reward

### Следующая проверка

Нужны controlled test accounts и test wallets:

- one operator / multi-account
- buy-sell loops
- DEX-listed token only
- сверка TON rewards / Meme Points / T+1 accrual

---

## 7. Weak verification / spoofing в `Perps` deposit-withdraw flow

### Статус

`Needs live TMA access`

### Что подтверждено

Из docs подтверждено:

- deposit делается из connected TON wallet via TON Connect
- требуется USDT on TON + TON for gas
- средства идут в `Perps wallet`
- withdraw возвращает средства в `main Blum wallet`
- используется cross margin

### Что не подтверждено

Не подтверждено, что:

- backend слабо проверяет ownership
- возможен fake completion
- можно replay-ить transaction reference
- есть race between deposit/withdraw/accounting

### Следующая проверка

Нужен живой deposit/withdraw flow с:

- перехватом запросов
- проверкой server-side confirmation
- попыткой reuse / race / stale reference

---

## 7a. Documentation gap around critical wallet actions

### Статус

`Confirmed`

### Что проверено

Проверены публичные страницы:

- `Your TON and Solana Wallets`
- `Main Menu and Features`
- `Trading Bot Settings`
- русская версия wallet FAQ

### Что подтверждено

Публичная документация прямо описывает высокорисковые wallet-функции:

- auto-generated wallets
- import wallet
- export private key / recovery phrase
- reset wallet
- withdraws

Но в ней не найдено явного описания дополнительных security steps перед чувствительными действиями.

### Что это означает

Это не доказывает отсутствие защиты в продукте, но:

- повышает приоритет live-проверки
- показывает, что по публичным материалам безопасность этих действий не прозрачна

### Severity

- `Info` как документационное наблюдение
- не является самостоятельной уязвимостью

---

## 8. Query reflection / reflected XSS на `help.blum.io`

### Статус

`Blocked by edge`

### Что проверено

Были отправлены запросы вида:

- `https://help.blum.io/blum-general-faq?xss_test=<payload>`
- `https://help.blum.io/search?q=<payload>`

### Что произошло

Запросы попали на Cloudflare anti-bot challenge page.

Payload отразился в HTML **страницы Cloudflare challenge**, а не в приложении Blum.

### Вывод

Это **не подтверждает reflected XSS у Blum**.

Сейчас корректный статус:

- нельзя подтвердить
- нельзя уверенно опровергнуть
- edge layer мешает тесту

---

## 9. Отсутствие `security.txt`

### Статус

`Confirmed`

### Что проверено

`https://www.blum.io/.well-known/security.txt`

### Что подтверждено

Возвращается:

- `Invalid .well-known request`

### Вывод

`security.txt` отсутствует или не настроен корректно.

### Severity

- `Info`

---

## 10. `app.blum.io` защищен Cloudflare Access

### Статус

`Confirmed`

### Что проверено

Запрос к:

- `https://app.blum.io`

### Что подтверждено

Возвращается редирект на Cloudflare Access login flow и protected resource metadata.

### Практический смысл

- часть surface закрыта от анонимного web recon
- многие гипотезы нельзя честно верифицировать без Telegram / authenticated path

### Severity

Не баг. Это просто важный operational note.

---

## Сводка по статусам

### Подтверждено

- weak CSP on `help.blum.io`
- permissive `frame-ancestors https:` on `help.blum.io`
- absence of `security.txt`
- `app.blum.io` sits behind Cloudflare Access

### Не подтверждено как баг, но поверхность реальна

- `Memepad` metadata injection surface
- `stream key` abuse
- wallet export/import/reset authorization flaws
- referral / Meme Points abuse
- perps deposit/withdraw accounting flaws

### Что требует следующего этапа

Нужен **живой Telegram/TMA доступ** для:

1. `@Blum` / `@BlumCryptoBot`
2. `@BlumCryptoTradingBot`
3. тестовых wallet flows
4. controlled multi-account checks

---

## Рекомендуемый следующий порядок верификации

1. `wallet export / reset / import`
2. `Perps deposit / withdraw`
3. `Memepad metadata rendering`
4. `referral + Meme Points`
5. `stream key lifecycle`
