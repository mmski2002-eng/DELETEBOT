# Blum Live Test Script: Wallet Export / Import / Reset

## Цель

Проверить, существуют ли уязвимости в самых критичных wallet-флоу `Blum Trading Bot`:

- `Export private key / recovery phrase`
- `Import wallet`
- `Reset wallet`
- связанные с ними session / auth / account confusion issues

---

## Что именно мы хотим подтвердить или опровергнуть

### Гипотеза A

`Export private key` доступен без достаточной повторной аутентификации.

### Гипотеза B

`Reset wallet` можно инициировать без достаточной защиты или с несогласованным контекстом сессии.

### Гипотеза C

`Import wallet` приводит к account confusion, stale bindings или доступу к данным/балансам не того wallet context.

### Гипотеза D

Wallet actions зависят от client-side state сильнее, чем должны.

---

## Подготовка

### Нужно иметь

1. Тестовый Telegram аккаунт
2. Доступ к `@BlumCryptoTradingBot`
3. Burp Suite / HTTP toolkit / mitm proxy
4. Два тестовых wallet context:
   - `Wallet A`
   - `Wallet B`
5. Желательно отдельный test user / второй Telegram аккаунт для cross-context checks

### Важно

- не использовать основной кошелек
- не держать значимые средства
- все действия выполнять на тестовых аккаунтах

---

## Что логировать с самого начала

### Сохранять обязательно

- скриншоты каждого шага
- raw requests / responses
- timestamps
- какой Telegram account используется
- какой wallet context активен до и после действия

### Именование evidence

Рекомендуемая структура:

- `evidence/wallet-export/`
- `evidence/wallet-import/`
- `evidence/wallet-reset/`
- `evidence/session-switch/`

Имена файлов:

- `01-main-menu.png`
- `02-wallet-screen.png`
- `03-export-request.txt`
- `04-export-response.txt`

---

## Этап 1. Baseline mapping

### Шаги

1. Открыть `@BlumCryptoTradingBot`
2. Пройти до `Wallet`
3. Зафиксировать:
   - TON address
   - Solana address
   - текущий balance
   - какие именно действия доступны в UI
4. Перехватить все запросы при открытии:
   - Main Menu
   - Wallet section
   - Settings

### Что искать

- токены сессии
- `initData`
- bot/webview auth exchange
- wallet identifiers
- user identifiers
- hidden action endpoints

### Ожидаемый результат

У нас должна появиться карта:

- какие запросы открывают wallet view
- какие идентификаторы участвуют в wallet context
- есть ли различие между UI state и backend state

---

## Этап 2. Export private key / recovery phrase

### Цель

Проверить, насколько жестко защищен экспорт секрета.

### Шаги

1. Найти в UI action:
   - `Export private key`
   - `Export recovery phrase`
2. Зафиксировать все запросы и ответы.
3. Проверить:
   - требует ли действие повторную аутентификацию
   - требуется ли PIN / пароль / wallet confirmation / Telegram re-auth
   - есть ли одноразовый challenge
4. Повторить экспорт:
   - сразу второй раз
   - после обновления UI
   - после relaunch бота

### Mutation tests

1. Повторно отправить export request вручную.
2. Убрать возможные client flags из request.
3. Подменить wallet/user identifiers, если они есть.
4. Проверить, можно ли инициировать export без прохождения UI шага.

### Признаки бага

- export доступен без повторного подтверждения
- export request можно replay-ить
- export работает при неполном UI flow
- export возвращает данные после изменения context / stale session

### Severity при подтверждении

- почти всегда `Critical`

---

## Этап 3. Reset wallet

### Цель

Проверить, можно ли сбросить кошелек слабо защищенным запросом или в неправильном сессионном контексте.

### Шаги

1. Найти в UI `Reset wallet`.
2. Зафиксировать:
   - предупреждения
   - подтверждения
   - backend requests
3. Проверить:
   - требуется ли повторный confirm step
   - есть ли одноразовый token/challenge
   - что меняется после reset:
     - wallet address
     - balances
     - referrals
     - history

### Mutation tests

1. Повторить reset request вручную.
2. Отправить reset request после logout/relaunch.
3. Если есть identifier в request:
   - подставить другой context
4. Проверить race:
   - открыть wallet screen в двух клиентах / двух вкладках
   - попытаться reset из одного контекста при stale UI во втором

### Признаки бага

- reset без достаточного подтверждения
- reset по replay request
- reset не того wallet context
- после reset старые session artifacts продолжают работать

### Severity при подтверждении

- `High` / `Critical`

---

## Этап 4. Import wallet

### Цель

Проверить account confusion и несогласованность между imported wallet и существующим контекстом аккаунта.

### Шаги

1. Подготовить `Wallet A` и `Wallet B`.
2. На чистом тестовом аккаунте получить auto-generated wallet.
3. Выполнить import `Wallet A`.
4. Зафиксировать:
   - адрес после import
   - что происходит с history
   - что происходит с balances
   - что происходит с referrals / points / positions
5. Затем импортировать `Wallet B`.

### Проверки после import

- сохраняются ли старые данные от предыдущего wallet context
- соответствует ли UI реальному imported wallet
- правильно ли меняется deposit address
- не появляется ли чужая история / чужой баланс / чужие токены

### Mutation tests

1. Сделать import и сразу relaunch.
2. Сделать import, затем открыть другие разделы:
   - Positions
   - Orders
   - Referrals
   - Memepad
3. Сделать import, затем попробовать withdraw/export/reset.

### Признаки бага

- после import остаются артефакты старого wallet context
- один и тот же аккаунт видит смешанные состояния двух кошельков
- можно управлять активами не того импортированного кошелька

### Severity при подтверждении

- `High` / `Critical`

---

## Этап 5. Session and account switching

### Цель

Проверить, не ломается ли привязка при relaunch / reconnect / смене Telegram контекста.

### Шаги

1. Авторизоваться на `Telegram Account 1`.
2. Открыть wallet actions и сохранить все requests.
3. Разлогиниться / закрыть / relaunch.
4. При наличии второго аккаунта:
   - открыть `Telegram Account 2`
   - сравнить ответы
5. Проверить, не работают ли старые запросы из `Account 1` после переключения.

### Mutation tests

1. Replay старых wallet requests.
2. Отправить старый export/reset/import request после новой сессии.
3. Проверить, инвалидируются ли старые tokens/session handles.

### Признаки бага

- старые wallet actions продолжают работать после смены контекста
- stale session позволяет дергать sensitive actions
- backend не различает корректно Telegram-user context

### Severity при подтверждении

- `High` / `Critical`

---

## Что записывать в отчет по каждой проверке

Для каждого потенциального бага фиксируй:

1. `Название`
2. `Статус`
   - Confirmed
   - Disproved
   - Inconclusive
3. `Вектор атаки`
4. `Шаги воспроизведения`
5. `Фактический результат`
6. `Ожидаемое безопасное поведение`
7. `Потенциальный ущерб`
8. `Severity`
9. `Evidence files`

---

## Шаблон мини-фиксации

```md
### [Название проверки]

Статус: Confirmed / Disproved / Inconclusive

Вектор атаки:

Шаги:
1.
2.
3.

Фактический результат:

Безопасное поведение:

Потенциальный ущерб:

Severity:

Evidence:
- file1
- file2
```

---

## Приоритет прохождения

Проходить в таком порядке:

1. Baseline mapping
2. Export private key
3. Reset wallet
4. Import wallet
5. Session/account switching

---

## Что прислать мне после первого прогона

Минимально достаточно одного из вариантов:

1. raw requests / responses по export/reset/import
2. HAR file
3. скриншоты UI + короткое текстовое описание результата
4. список endpoints и параметры запросов

После этого я смогу:

- сразу обновить `Verification_Report_RU.md`
- перевести пункты в `Confirmed` или `Disproved`
- выделить уже bounty-worthy findings
