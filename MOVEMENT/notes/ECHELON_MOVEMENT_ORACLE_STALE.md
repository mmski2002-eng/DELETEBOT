# Echelon Market (Movement) — анализ оракула на stale-price

Дата: 2026-06-13. Направление перенесено из EVAA-кейса (stale-price в pull-оракуле Pyth).
Цель: проверить, применим ли тот же класс к лендингу на Movement. Главный кандидат — **Echelon Market** (lead-лендинг сети, ~$180M TVL, Move).

---

## 1. Scope / адреса (Movement mainnet, verify on-chain 2026-06-13)

REST: `https://mainnet.movementnetwork.xyz/v1`

| Компонент | Адрес |
|---|---|
| Lending пакет | `0x6a01d5761d43a5b5a0ccbfc42edf2d02c0611464aae99a2ea0e0d4819f0550b5` (модули: `lending`, `scripts`, `farming`, `package`) |
| Oracle пакет | `0xc27677a285b5183118d831d4a6be98719c0566f17c87da9488ec0bbd73d8de09` (`oracle`, `pyth_oracle`, `tiered_oracle`, `switchboard_oracle`, `params`, `status`, `math`) |

Рынки (market-объекты):
| Актив | Market addr |
|---|---|
| USDT.e | `0x8191d4…3bc3d2` |
| USDC.e | `0x789d77…22a0a0` |
| sUSDe | `0x481fe6…3423d` |
| MOVE | `0x568f96…25db7` |
| wBTC | `0xa24e2e…bebee4` |
| solvBTC | `0x185f42…c60aca` |
| LBTC | `0x62cb5f…1eaf23` |
| wETH | `0x688993…7b21b7c` |
| ezETH | `0x8dd513…f3542` |
| rsETH | `0x4cbeca…86614b` |

Исходник Echelon **не публичен** (анализ по on-chain байткоду + ABI; та же кодовая база задеплоена и на Aptos `0xc6bc65…`, `0x092e95…` — использована для сверки имён модулей/функций).

---

## 2. Ключевое архитектурное отличие от EVAA

EVAA (TON) = **pull-оракул**: ликвидатор передаёт подписанный Pyth-VAA прямо в calldata, `publish_gap` без верхней границы → атакующий cherry-pick'ает исторический тик в окне TTL=180s.

Echelon (Movement) = **push + lazy-cache**. Entry-функции `scripts::{borrow,liquidate,supply,withdraw,repay}` принимают только `&signer`, Market-объект и суммы — **VAA/price-bytes в транзакции НЕТ**. Цена берётся из on-chain состояния Pyth, которое обновляют внешние кейперы отдельными транзакциями. `lending` зовёт **checked**-путь `oracle::get_and_update_price_by_name/_by_metadata` (не `*_unsafe`).

Вывод: точный EVAA-вектор (подделать выбор тика через calldata) **не применим**. Но базовый класс — «протокол готов считать цену свежей дольше, чем безопасно» — присутствует, и в более широкой форме (см. §4).

---

## 3. Модель свежести Echelon (распарсено из ABI/байткода)

`params::CoinParam { staleness_seconds, staleness_broken_seconds, price_deviate_reject_pct }` (per-asset, Table).

`tiered_oracle::CoinData { last_price, tier_1, tier_2: Option<u8> }`. Enum-типы оракула:
`0 = NULL`, `1 = STABLECOIN (fixed $1)`, `2 = SWITCHBOARD`, `3 = PYTH`.

`status` модуль: `NORMAL / STALE / BROKEN`.

`pyth_oracle::get_price(name, staleness, broken, deviate_pct, last_price) -> (status:u8, price)`:
- `age ≤ staleness_seconds` → **NORMAL** → цена отдаётся как есть (даже если близко к порогу старая).
- `staleness < age ≤ broken` → **STALE** → tiered_oracle уходит на `tier_2`, если задан; иначе обрабатывает по статусу.
- `age > broken_seconds` → **BROKEN** → reject.
- `deviate_largely_from_old_price`: новый апдейт отвергается, если отклоняется > `deviate_pct` от `last_price` (анти-манипуляция **на запись**, НЕ на чтение).

---

## 4. On-chain факты — реальные пороги (view-вызовы, 2026-06-13, now≈1781355888)

`params::get_oracle_params_fa(metadata)` → `[staleness_s, broken_s, deviate%]`; `tiered_oracle::get_tiers_fa` → `[tier1,tier2]`; `pyth_oracle::get_timestamp_at_source_fa` → возраст текущей on-chain цены.

| Актив | staleness | broken | dev% | tier1/2 | возраст live-цены |
|---|---|---|---|---|---|
| USDT.e | 3600 | 7200 | 20 | 3 / 1 | свежая |
| wBTC | **3600** | 7200 | 20 | 3 / 0 | 387s |
| wETH | **3600** | 7200 | 20 | 3 / 0 | 387s |
| sUSDe | 3600 | 7200 | 20 | 3 / 0 | 387s |
| solvBTC | **900** | 3600 | 20 | 3 / 0 | **2825s** |
| ezETH | **3600** | 7200 | 20 | 3 / 0 | **2825s** |
| rsETH | **3600** | 7200 | 20 | 3 / 0 | **2825s** |

**Главное:**
- Волатильные BTC/ETH-активы и LST принимают цену возрастом до **3600s (1 час)** со статусом NORMAL. Это **в 20× больше**, чем TTL=180s у EVAA.
- В момент проверки **solvBTC / ezETH / rsETH отдавали цену возрастом 2825s ≈ 47 минут**, и она проходит как NORMAL (порог 3600s). Кейперы Pyth на Movement редкие → лаг реальный, не теоретический.
- `tier_2 = 0` (NULL) у всех волатильных → fallback'а нет: при STALE/BROKEN сделка ревертит (DoS), но в окне NORMAL stale-цена отдаётся без оговорок.
- `deviate% = 20` ограничивает прыжок одного апдейта, но **не помогает против устаревания**: если свежий апдейт не пришёл, старая цена живёт и отдаётся весь NORMAL-период.

---

## 5. Вектор (направление, не добитый PoC)

* Title: Приём устаревшей цены до 1 часа на волатильном залоге (BTC/ETH/LST) в Echelon Market
* Severity: **High** (потенциально Critical при реальном движении ≥ подушки в окне)
* Affected: `pyth_oracle::get_price` + per-asset `params::CoinParam.staleness_seconds` (3600s на wBTC/wETH/LST), читается из `lending` через `oracle::get_and_update_price_by_*`
* Root Cause: окно допустимой устаревшести (`staleness_seconds`) задано избыточно широко для волатильных активов; свежесть полностью делегирована внешним кейперам Pyth, которые на Movement обновляют фиды редко (наблюдаемый лаг ~47 мин)
* Attack Path:
  1. Реальное движение цены залога/долга (BTC/ETH/LST дают >5% за час штатно).
  2. On-chain Pyth-цена ещё отражает старое значение (до 3600s), статус NORMAL.
  3. Атакующий НЕ обновляет фид (обновление — добровольное, в calldata его нет) и действует на stale-цене:
     - **borrow / withdraw** против stale-завышенного залога (или stale-заниженного долга) → позиция выходит за реальную обеспеченность → при апдейте фида возникает невозвратный долг → **bad debt = убыток пула (Critical)**;
     - **уклонение от ликвидации**: underwater-позиция защищена stale-выгодной ценой до 1 часа → bad debt накапливается;
     - **несправедливая ликвидация**: если реальная цена восстановилась, а on-chain ещё показывает провал → ликвидация здоровой позиции (убыток юзера).
* Impact: при достаточном реальном движении в окне 3600s — невозвратный долг пула; иначе — извлечение стоимости у юзеров.
* Honest bound: как и в EVAA, **магнитуду подделать нельзя** — нужна реальная дислокация в окне. Но окно 3600s vs 180s → вероятность/величина захваченного движения радикально выше; на LST/BTC/ETH часовой лаг практически гарантированно ловит значимое движение в волатильный день.
* Assumptions: кейперы Pyth на Movement лагают (подтверждено: live-возраст 2825s); checked-путь не ревертит внутри NORMAL (подтверждено статусной моделью).
* Confidence: Средне-высокая по архитектуре и порогам (verify on-chain); вектор требует исполняемого PoC.

---

## 6. Что осталось добить (PoC-план, по стандарту проекта — исполнять байткод)

1. Форк Movement-состояния (`@aptos-labs/ts-sdk` + локальный MoveVM / `aptos move replay`), вызвать `lending::account_liquidity` / `liquidate` на реальной позиции при (а) свежей и (б) stale on-chain Pyth-цене → показать флип healthy↔liquidatable и/или избыточный borrow. Только исполнение байткода, не арифметика.
2. Подтвердить поведение `tiered_oracle::get_and_update_price` при `age` в зонах NORMAL / STALE / BROKEN (получить статус-коды реальным вызовом).
3. Оценить экономику: найти near-threshold позицию + день с реальным движением ≥ подушки (CF wBTC=80%? проверить LT) в окне 3600s.

---

## 7. Другие цели того же направления (ранжир)

1. **Storm Trade (TON, перпы)** — тот же Pyth-контракт TON, что и EVAA (pull, слабая staleness). Перпы = маржа, прямой EVAA-аналог. Приоритет.
2. **Прочие Move-лендинги на Movement** — `0x108f56…` (market/oracle/farming/scripts/token_hub) выглядит как отдельный лендинг (Meridian?/форк): проверить его `oracle` модуль и пороги тем же методом.
3. **Aptos-двойник Echelon** (`0xc6bc65…`/`0x092e95…`) — те же модули; проверить, не шире ли там пороги; на Aptos кейперы Pyth плотнее → лаг меньше.
4. Aptos/Sui лендинги (Aries, Echelon, Navi, Scallop) и перпы (Merkle, Kana) — везде смотреть `staleness_seconds` / `get_price_unsafe` / отсутствие re-check на свежайшей цене.

---

## 8. Bottom line

Echелon — НЕ pull как EVAA, поэтому точный calldata-вектор закрыт, а оракул в целом аккуратный (статусы, deviation-guard, broken-reject, fallback для стейблов). НО: **порог staleness=3600s на волатильных BTC/ETH/LST избыточно широк**, fallback там отсутствует (`tier_2=0`), а кейперы Pyth на Movement реально лагают (наблюдаемые 47 мин). Это тот же класс «слишком долго считаем цену свежей», что и в EVAA, в более опасной форме по ширине окна. Перспективно довести до исполняемого PoC (borrow-against-stale / liquidation-avoidance → bad debt). Параллельно — Storm Trade как чистый EVAA-аналог.
