# Security Recon Report: movematch.xyz

**Дата:** 2026-05-10  
**Цель:** https://www.movematch.xyz  
**Метод:** Пассивная разведка — HTTP fuzzing, анализ JS chunks, без эксплойтов

---

## Итоговые ответы

| # | Вопрос | Ответ |
|---|--------|-------|
| A | Найдены UI API endpoints? | **YES** |
| B | Endpoints без авторизации? | **YES — 5 штук** |
| C | Admin/debug/internal endpoints? | **YES — /admin открыт** |
| D | Потенциальное чтение данных? | **YES — live stats, player config** |
| E | Потенциальные write endpoints? | Нет HTTP write — всё через blockchain (wallet signature) |
| F | Что блокировать/защитить? | см. раздел Рекомендации |

---

## Технический стек

- **Framework:** Next.js (App Router), Vercel hosting
- **Auth:** Web3 wallet-based (Aptos/Movement wallet)
- **Blockchain:** Movement Network
- **Внешний API:** `https://v3.football.api-sports.io` (api-sports.io)
- **Основной домен:** `movematch.xyz` → redirect 307 → `www.movematch.xyz`

---

## Найденные endpoints

### 1. `/admin` — КРИТИЧНО (UI exposure)

| Поле | Значение |
|------|----------|
| URL | `https://www.movematch.xyz/admin` |
| Метод | GET |
| Auth required? | НЕТ (HTTP level) |
| Статус | **200 OK** |
| Content-Type | `text/html` |
| CORS | `Access-Control-Allow-Origin: *` |

**Ответ (snippet):**
```
Admin Panel
"Please connect your wallet to access admin functions."
```

**Примечания:**  
- Страница полностью загружается без авторизации
- Проверка прав — **клиентская** (JS): сравнивает адрес кошелька с `admins[]` из blockchain `get_config` view
- `Access-Control-Allow-Origin: *` означает любой сайт может читать ответ через fetch
- Страница раскрывает кол-во admin-адресов: `"Admins: " + S.admins.length`
- Доступные admin-функции видны в UI (и в JS): создание/закрытие игровой недели, отправка статистики игроков, управление призовым фондом, обновление комиссий
- Записи в контракт требуют подписи admin-кошелька — **обход UI не даёт прав**, но разведка функционала полная

**Admin-функции (из JS chunk `app/admin/page-8fb0fd946fc4de51.js`):**
- `submit_player_stats` — отправка статистики игроков в контракт
- `admin_sponsor_prize_pool` — спонсирование призового пула
- `set_prize_pool_percent` — изменение % призового пула
- `create_gameweek` / `close_gameweek` / `reopen_gameweek`
- Обновление комиссий (entryFee, titleFee, guildFee)

---

### 2. `/api/players` — Открыт без auth

| Поле | Значение |
|------|----------|
| URL | `https://www.movematch.xyz/api/players` |
| Метод | GET |
| Auth required? | НЕТ |
| Статус | **200 OK** |
| Content-Type | `application/json` |
| Cache | `public` |

**Ответ (структура):**
```json
[
  {
    "id": 1,
    "fplId": 1,
    "name": "David Raya Martín",
    "webName": "Raya",
    "team": "Arsenal",
    "teamId": 1,
    "position": "GK",
    "positionId": 0,
    "photo": "https://resources.premierleague.com/...",
    "fplPhotoCode": 154561,
    "status": "a",
    "chanceOfPlaying": null,
    "news": "",
    "totalPoints": 147,
    "form": 5.54,
    "selectedByPercent": 35.4
  },
  ...
]
```

**Примечания:** Полная база игроков EPL с очками, формой, процентом выбора. Не является критически чувствительными данными, но полная.

---

### 3. `/api/fixtures` — Открыт без auth

| Поле | Значение |
|------|----------|
| URL | `https://www.movematch.xyz/api/fixtures` |
| Метод | GET |
| Auth required? | НЕТ |
| Статус | **200 OK** |
| Content-Type | `application/json` |
| Cache | `private, no-store` (динамический) |

**Ответ (структура):**
```json
{
  "gameweek": {
    "id": 36,
    "name": "...",
    "deadlineTime": "2026-05-09T11:30:00Z",
    "deadlineEpochMs": ...,
    "isCurrent": true,
    "isNext": false
  },
  "fixtures": [
    {
      "id": 355,
      "kickoffTime": "...",
      "teamH": { "id": 12, "name": "Liverpool", "shortName": "LIV", "badge": "..." },
      "teamA": { "id": 7, "name": "Chelsea", ... },
      "finished": true,
      "started": true,
      "scoreH": 1,
      "scoreA": 1
    },
    ...
  ]
}
```

**Примечания:** Текущая игровая неделя + все матчи со счётами. Стандартные данные для fantasy игры.

---

### 4. `/data/players.json` — ВАЖНО (утечка internal IDs)

| Поле | Значение |
|------|----------|
| URL | `https://www.movematch.xyz/data/players.json` |
| Метод | GET |
| Auth required? | НЕТ |
| Статус | **200 OK** |
| Content-Type | `application/json` |
| Content-Length | **173,680 байт (173KB)** |
| CORS | `Access-Control-Allow-Origin: *` |
| Cache | `public`, ETag присутствует |

**Ответ (структура):**
```json
[
  {
    "id": 1,
    "apiId": 50132,
    "name": "A. Bayındır",
    "team": "Manchester United",
    "teamId": 1,
    "apiTeamId": 33,
    "position": "GK",
    "positionId": 0,
    "price": 4.5,
    "photo": "https://media.api-sports.io/football/players/50132.png"
  },
  ...
]
```

**Примечания:**  
- Раскрывает `apiId` — внутренние ID из `api-sports.io` (внешний платный API)  
- Раскрывает `apiTeamId` — mapping команд к api-sports.io  
- Раскрывает `price` — ценообразование игроков (game config)  
- URL фото явно указывает на провайдера: `media.api-sports.io`  
- Это **внутренний маппинг данных**, не предназначенный для публичного использования

---

### 5. `/api/fpl-live?gw={N}` — Открыт без auth

| Поле | Значение |
|------|----------|
| URL | `https://www.movematch.xyz/api/fpl-live?gw=36` |
| Метод | GET |
| Auth required? | НЕТ |
| Статус | **200 OK** |
| Content-Type | `application/json` |
| Cache | `public` |

**Ответ (структура):**
```json
{
  "gameweekId": 36,
  "players": [
    {
      "playerId": 67,
      "position": 0,
      "minutesPlayed": 90,
      "goals": 0,
      "assists": 0,
      "cleanSheet": true,
      "saves": 2,
      "penaltiesSaved": 0,
      "penaltiesMissed": 0,
      "ownGoals": 0,
      "yellowCards": 0,
      "redCards": 0,
      "rating": 60,
      "bonus": 0,
      "goalsConceded": 0,
      "fplCleanSheets": 1,
      "tackles": 0,
      "interceptions": 0,
      "successfulDribbles": 0,
      "freeKickGoals": 0
    },
    ...
  ]
}
```

**Примечания:**  
- Полная live-статистика всех игроков по игровой неделе  
- Принимает любое число `gw=` — можно запросить исторические данные  
- Эти данные используются **до** отправки в blockchain: теоретически можно читать pending stats раньше финализации  
- Потенциально даёт преимущество в игре при доступе до обновления UI

---

## Дополнительные находки из JS-анализа

### Контракты (Movement Network)
```
0xc9f5444ab989c2a7ef73b1eab58b66947c4c5788e25d997d649c7d6ddfbeb5a1
0xf598f059a0353b0d9ea80c9fd9d1c3e15b71ff4535388dd79acf813b567c5b47
```

### Внешний API провайдер
```
https://v3.football.api-sports.io
```
- API ключ вводится вручную в admin-панели
- Используется для синхронизации статистики матчей
- Лимит: 100 запросов/день (Free tier — упомянуто в коде)

### Admin auth flow (client-side, из chunk `213-825cec967bb0a417.js`)
```js
// Запрос к смарт-контракту (view function, публично)
get_config() → [admins[], oracle, entryFee, titleFee, guildFee, prizePoolPercent, currentGameweek]

// Проверка в JS (клиентская)
isAdmin = admins.some(addr => addr.toLowerCase() === connectedWallet.toLowerCase())
isOracle = oracle.toLowerCase() === connectedWallet.toLowerCase()
```

**Риск:** Список admin-адресов **публичен** (blockchain view function). Кол-во admins показано в UI. Oracle — единственный адрес.

### Внешние пути в admin chunk
- `/fixtures/players?fixture={id}` → запросы к api-sports.io
- `/fixtures?league={id}` → запросы к api-sports.io
- `/status` → проверка API ключа у api-sports.io

---

## Не найдено (404)

```
/admin/login        /api/admin         /api/debug
/api/secret         /api/user/list     /api/stats/upload
/api/config         /api/user          /api/game
/api/sync           /api/cron          /internal
/debug              /status            /.env
/.gitignore         /.well-known/security.txt
/api/gameweek       /api/my-result
/_next/static/chunks/pages/_app.js
/_next/static/chunks/main.js
```

---

## Рекомендации (F)

### Критично

| Endpoint | Проблема | Рекомендация |
|----------|----------|--------------|
| `/admin` | Открыт публично, CORS `*`, client-side auth | Добавить server-side auth (JWT/session + wallet sig), убрать `*` CORS |
| `/data/players.json` | CORS `*`, 173KB, раскрывает apiId провайдера и ценообразование | Убрать `apiId`/`apiTeamId` из ответа или закрыть endpoint |

### Средний приоритет

| Endpoint | Проблема | Рекомендация |
|----------|----------|--------------|
| `/api/fpl-live?gw=` | Публичный, нет rate limit, нет auth | Rate limiting, возможно требовать подключённый кошелёк |
| `/api/players` | Полная база без auth | Rate limiting, возможно кешировать на CDN без `apiId` |
| `/api/fixtures` | Нет auth | Приемлемо для публичных данных, rate limiting |

### Инфо

- Admin-адреса публичны через blockchain view — ожидаемо для web3, но стоит проверить ротацию
- Oracle — единственный адрес: компрометация oracle критична для игры
- Лимит api-sports.io 100 req/day на Free tier — возможен DoS через принудительное исчерпание лимита если API ключ утечёт

---

## Сводная таблица endpoint статусов

| Endpoint | Метод | Статус | Auth | Чувствительность |
|----------|-------|--------|------|-----------------|
| `/admin` | GET | 200 | НЕТ (wallet UI only) | ВЫСОКАЯ |
| `/api/players` | GET | 200 | НЕТ | НИЗКАЯ |
| `/api/fixtures` | GET | 200 | НЕТ | НИЗКАЯ |
| `/data/players.json` | GET | 200 | НЕТ | СРЕДНЯЯ |
| `/api/fpl-live?gw=N` | GET | 200 | НЕТ | СРЕДНЯЯ |
| `/api/admin` | GET | 404 | — | — |
| `/api/debug` | GET | 404 | — | — |
| `/.env` | GET | 404 | — | — |
| `/internal` | GET | 404 | — | — |
| `/debug` | GET | 404 | — | — |
