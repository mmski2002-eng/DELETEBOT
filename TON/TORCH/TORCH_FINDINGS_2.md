# Torch Finance — findings (сессия 2)

Дата проверки: 2026-06-11. Метод: чтение исходников + числовой порт curve-формул (PoC) + замеры mainnet API/оракула.

Статусы честные, severity не завышены. Два лида проверены до конца и понижены.

---

## Finding A — imbalanced add_liquidity fee расходится с Curve

- **Severity:** Low
- **Файл:** `torch-dex-contract/contracts/pools/algorithms/curve_algorithm.fc:210-267` (`get_fee`)
- **Root Cause:** идеальный баланс считается как РАВНЫЙ вес (`ideal = d_1/n`), а не как пропорция текущего пула (`D1*old_balance/D0`, как в Curve). Плюс комиссия односторонняя: `difference = deposit_i - min(deposit_i, max(ideal-old,0))` вместо симметричного `abs(ideal - new)`.
- **Эффект:** депозит дефицитной монеты в имбалансный пул заряжается почти нулевой комиссией → минтится чуть больше LP, чем честно. Маршрут swap через deposit+withdraw на ~0.01–0.035% дешевле прямого swap.
- **PoC:** `poc/torch_curve_poc.js`
  - сбаланс. пул, депозит coin0: excess LP +0.010%, RT-преимущество +0.0099%
  - имбаланс 1.8M/0.2M, депозит дефицитной: excess +0.034%, RT-преимущество +0.034%
  - **принципал не извлекается** — это утечка комиссии у LP (~половина swap-fee), не кража.
- **Confidence:** High (точный порт формул). Impact Low.

---

## Finding B — signed-rate: нет anti-replay / монотонности / deviation-cap

- **Severity:** Low / informational (defense-in-depth). Изначально подозревался Medium, **опровергнут на достижимости**.
- **Файлы:** `torch-dex-contract/contracts/pools/utils.fc:197-224` (`handle_signed_rates`), `parser.fc` (signed_rates из тела сообщения).
- **Механизм (реален, подтверждён кодом):**
  - signed_rate приходит из сообщения свопера (`ctx::body~load_maybe_ref()`), не пинится контрактом.
  - проверки только: подпись + `expiration < now()` + hash assets.
  - НЕТ: anti-replay (payload_hash не хранится), монотонности timestamp, deviation-cap. Storage пула без nonce/last_rate.
  - окно подписи замерено с mainnet оракула: **~600с**.
- **Почему опровергнуто (экономическая недостижимость):**
  - rate-bearing активы во всех useRates-пулах = медленные LST: stgUSD, stTON, tsTON.
  - подписывается **redemption-курс** (totalStaked/totalShares), НЕ рыночная цена. Эмпирически: опрос оракула с интервалом — значение не тикает, меняется только expiration.
  - redemption-курс монотонный, ~0.03%/день; падений нет (слэш на TON ограничен и размазан → ≪1%). Порог рентабельности атаки ≈0.7% за 600с — недостижим.
  - рыночная цена двигается 1%/10мин, но она НЕ реплеится; рыночные отклонения отыгрывает обычный арбитраж вокруг peg.
- **PoC (показывает, что БЫЛО БЫ при сдвиге курса, которого нет):** `poc/torch_rate_poc.js`
  - сдвиг 1% → профит +236$, 2% → +806$, 5% → +2517$ на трейд 50k (порог рентабельности ~0.7%).
- **Остаточный риск:** если редкий дискретный LST-инцидент совпадёт с окном 600с — отсутствие guard даст эксплойт. Рекомендация: монотонность timestamp + deviation-cap + короче TTL (как EVAA prices_ttl, Storm max_deviation).
- **Confidence:** механизм High, эксплуатируемость Low (на текущих активах ~нулевая).

---

## Контекст: ранее заявленный Critical (tgUSD staking freeze)

- `TORCH_FINANCE_CRITICAL_1_REPORT.md` — freeze при `totalShares==0 && totalStaked>0`.
- Путь достижим (подтверждён), рефанда при throw в OP_STAKE_FP нет.
- **НО:** admin-recoverable через `OP_UPGRADE_CONTRACT` (`tgusd-staking/main.tolk:546`), + узкий триггер (last-exit при `unvested>0`; если награда вызрела — `totalStaked→0` чисто).
- → «permanent freeze» — неверная формулировка; вероятная причина отскока/даунгрейда. Не Critical.

---

## Mainnet-данные (для воспроизведения)

- API (GraphQL): `https://api.torch.finance/graphql` — 3 пула, 2 с `useRates=true`.
- Оракул: `https://oracle.torch.finance/signed-rates?poolAddresses=<addr>` — окно ~600с.
- useRates пулы:
  - `0:649a4e0df1d7adbb32dea9618b1ace7f8ac271066f6e45317ce829a8dbe578b2` — tgUSD / stgUSD
  - `0:38aff89e3b7bc98ec42d6a4705bbe887a53d4b17175993057ccaa34d1254a651` — TON / stTON / tsTON
