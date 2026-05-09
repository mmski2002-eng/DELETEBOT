# Blum TMA Initial Recon

## Статус

Рабочая папка для исследования Blum создана:

- [Blum](/home/escape/Документы/DELETEBOT/TON/MINI%20APPS/Blum)

Этот документ фиксирует стартовый reconnaissance по состоянию на 6 мая 2026 года и задает приоритетные направления дальнейшего исследования.

---

## Что уже подтверждено

### 1. Blum использует Telegram Mini App как основной пользовательский вход

Подтверждено из официальных материалов Blum:

- `Blum Crypto Bot` описывается как Telegram mini app
- Blum позволяет использовать продукт через Telegram mini app
- внутри Telegram доступны как минимум wallet-related, trading и perps-флоу

### 2. В Blum есть TON wallet integration

По Blum FAQ:

- можно подключать TON-кошельки
- в качестве поддерживаемых кошельков указаны `Tonkeeper`, `MyTonWallet`, `Tonhub`, `SafePal`, `@wallet`, а также некоторые внешние wallet apps
- после подключения TON address отображается в разделе Wallet

Это означает, что для ресерча актуальны:

- wallet binding
- TonConnect / wallet connection trust
- spoofing connected wallet state
- replay / stale session issues

### 3. У Blum есть transaction-bearing functionality

Публично заявлены:

- `Perps` прямо внутри Telegram mini app
- `Trading Bot` для multichain trading
- `Memepad` для запуска memecoin на TON
- операции, связанные с wallet balances, deposits, top-ups, cross-chain / multichain user flows

Это делает Blum особенно интересным для поиска:

- client-side trust flaws
- business logic issues
- wallet impersonation
- settlement / completion bugs
- referral / rewards abuse

### 4. Отдельный публичный bug bounty scope для Blum пока не подтвержден

На момент initial recon я не подтвердил отдельную публичную страницу bug bounty именно для Blum.

Важно:

- если целью является только формальный bounty scope, перед активным тестированием нужно отдельно подтвердить допустимость исследования
- как минимум есть публичные источники, подтверждающие, что Blum является реальным TMA и активно использует blockchain / wallet flows

---

## Подтвержденные публичные источники

### Официальные материалы Blum

1. Blum FAQ:
   https://help.blum.io/blum-general-faq

2. Blum troubleshooting FAQ:
   https://help.blum.io/blum-app-troubleshooting-faq

3. Blum main site:
   https://www.blum.io/

4. Blum Perps launch:
   https://www.blum.io/post/blum-perps-launch

5. Blum Trading Bot article:
   https://www.blum.io/zh/post/blum-trading-bot

### Дополнительные discovery-источники

6. FindMini listing for `@blumcryptobot`:
   https://www.findmini.app/blumcryptobot/

7. FindMini listing for `@blumcryptotradingbot`:
   https://www.findmini.app/blumcryptotradingbot/

8. Telegram entry for `@blumcryptotradingbot`:
   https://t.me/blumcryptotradingbot

9. Telegram channel `@blumcrypto`:
   https://t.me/blumcrypto

---

## Предварительная модель attack surface

### A. Telegram identity boundary

Наиболее вероятные риски:

- backend trust к `initDataUnsafe`
- отсутствие или частичная валидация `initData`
- replay старого `initData`
- несогласованность между Telegram account и Blum account state

Почему это интересно:

- Blum FAQ прямо упоминает связь аккаунта с Telegram
- troubleshooting-материалы упоминают проблемы, связанные с Telegram account behavior
- у продуктов с rewards / points / referrals auth-layer часто становится первой точкой фрода

### B. Wallet connection boundary

Наиболее вероятные риски:

- backend trust к wallet address из клиента
- отсутствие signed challenge при wallet binding
- spoofing connected wallet state
- stale wallet session или повторное использование подтвержденного состояния

Почему это интересно:

- Blum явно показывает connected TON address в app
- если ownership подтверждается слабо, возможны privilege bugs, payout confusion, false attribution of actions

### C. Trading / transaction intent boundary

Наиболее вероятные риски:

- клиент может менять payload до отправки
- backend доверяет client-reported success
- order / intent / trade completion не привязаны к server-side state
- trade / deposit / reward flow допускает replay

Почему это интересно:

- Blum позиционируется как in-Telegram trading product
- чем больше “app-like” торговый UX, тем выше риск лишнего доверия к клиентскому состоянию

### D. Rewards / referrals / campaigns

Наиболее вероятные риски:

- referral abuse
- self-referral
- repeated claim / race / replay
- rewards без полной server-side валидации eligibility

Почему это интересно:

- Blum активно использует growth mechanics, points и campaign-like UX
- такие флоу часто содержат business logic flaws даже при нормальной криптографии

### E. TMA-specific web surface

Наиболее вероятные риски:

- XSS через Telegram-controlled fields
- trust к `start_param`
- `postMessage` origin issues
- storage of reusable auth/session artifacts

---

## Самые приоритетные гипотезы для Blum

### Гипотеза 1. Telegram identity не полностью отделена от клиентского состояния

Что проверить:

- какие запросы уходят при первом открытии mini app
- отправляется ли raw `initData`
- принимает ли backend запросы с модифицированными Telegram user fields
- есть ли повторное использование старого login payload

Ожидаемый impact:

- auth bypass
- account confusion
- referral / rewards fraud

### Гипотеза 2. Wallet ownership подтверждается слабо

Что проверить:

- есть ли nonce challenge
- можно ли отправить произвольный wallet address в bind/update flow
- можно ли после connect UI изменить адрес в запросе
- зависит ли доступ к wallet-related действиям от client-side state

Ожидаемый impact:

- wallet spoofing
- attribution bypass
- ошибки при начислениях, привилегиях или подтверждении действий

### Гипотеза 3. Trade / deposit / reward completion слишком доверяет клиенту

Что проверить:

- как backend узнает, что действие завершено
- можно ли отправить completion endpoint без фактического действия
- можно ли повторно отправить один и тот же completion / tx reference
- можно ли использовать старую транзакцию для новой логики

Ожидаемый impact:

- fake completion
- repeated claim
- balance / reward abuse

### Гипотеза 4. `start_param` и growth-механики дают бизнес-логические баги

Что проверить:

- referral onboarding через deep links
- self-referral
- повторная активация промо / квестов / rewards
- изменение параметров контекста запуска

Ожидаемый impact:

- массовый фарм
- обход ограничений
- некорректное начисление reward / points

---

## Приоритетный практический план

### Этап 1. Passive recon

1. Зафиксировать все публичные entrypoints:
   `@blum`, `@blumcryptobot`, `@blumcryptotradingbot`, web endpoints, help center
2. Понять, какие части продукта реально открываются как TMA, а какие как bot/web hybrid
3. Определить, где есть:
   wallet connect, rewards, referral, deposits, perps, memepad

### Этап 2. Identity and session mapping

1. Перехватить первый auth exchange
2. Определить, используется ли raw `initData`
3. Проверить session issuance, TTL, replay behavior
4. Проверить storage: cookies, `localStorage`, `sessionStorage`, IndexedDB

### Этап 3. Wallet binding

1. Подключить тестовый TON wallet
2. Отследить все bind / verify / session refresh запросы
3. Понять, есть ли cryptographic proof of wallet ownership
4. Проверить, что address нельзя подменить в transit или после connect

### Этап 4. Sensitive flows

1. Wallet top-up / deposit
2. Perps entry / order creation / confirmation
3. Rewards / campaigns / claims
4. Referral onboarding

### Этап 5. TMA-specific client surface

1. Telegram fields in DOM
2. `start_param`
3. `postMessage`
4. client-side feature flags and hidden actions

---

## Что делать дальше

Следующий полезный шаг:

- открыть Blum как реальный TMA и начать живую карту запросов

Цель следующей итерации:

- составить уже не общий recon, а конкретный `endpoint map`
- выделить auth flow
- выделить wallet binding flow
- выделить first high-signal mutation tests

---

## Рабочие заметки

- Blum выглядит как очень перспективная цель именно из-за комбинации:
  Telegram identity + wallet connection + trading + rewards
- Наиболее опасная зона здесь не обязательно smart contract level, а граница доверия между TMA-клиентом и backend/API
- До подтверждения формального scope нужно держать в голове отдельный legal/scope caveat
