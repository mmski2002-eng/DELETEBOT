# EVAA Protocol — Внутренний отчёт исследования

Дата: 2026-06-13. Цель проекта: найти уязвимость EVAA (TON lending) с **убытком платформы** (пул/supplier'ы), пригодную для HackenProof.

---

## 1. Что исследовали

1. Прочитан весь предыдущий материал папки (15+ отчётов): база — stale-price liquidation в пределах `prices_ttl=180s`.
2. Верифицирован **актуальный funded MAIN-пул** on-chain (по требованию: работать с актуальным пулом, проверять средства).
3. Разобрана реальная модель оракула/фидов MAIN (Pyth on-demand, ref-токены, redemption-rate).
4. Сопоставлен задеплоенный код пулов с публичным репозиторием (code-hash match).
5. Проведён полный аудит ядра доступного исходника (commit `d9138cb`) на platform-loss баги.

## 2. Верифицированные on-chain факты (2026-06-13)

Источник адресов — официальный SDK `evaafi/sdk@main` (`src/constants`).

| Пул | Адрес | Баланс | code_hash | Оракул | Исходник публичен |
|---|---|---|---|---|---|
| **MAIN (funded)** | `EQC8rU…` | **578,657 TON** | `b90881c4…` | PythCollector | **НЕТ** |
| PYTH_TOB (in-scope) | `EQCsOdQ…` | **2.9 TON (~$5)** | `08b54a3f…` | PythCollector | **ДА** (= d9138cb) |
| LP | `EQBIlZ…` | 13,589 TON | `d4n9…` | ClassicCollector | НЕТ |
| STABLE | `EQCdId…` | 21.7 TON | `d4n9…` | ClassicCollector | НЕТ |
| ALTS / TOB | `EQANUR…`/`EQDrSGB…` | 0 / uninit | — | Classic | — |

- MAIN: `if_active=true`, `prices_ttl=180s` (распарсено из `oracles_info` data BoC).
- MAIN HE-группы: `heCat1={TON, tsTON}`, `heCat2={USDT, USDe, tsUSDe}`.
- Feed-маппинг MAIN: tsTON/stTON ценятся через **тот же базовый фид TON/USD** ×RR; tsUSDe — через USDe-фид. jUSDT/jUSDC → USDT (ref-copy).
- Hermes conf (тонкость фида): TON 0.15%, USDT 0.06%, USDe 0.07%; **RR-фиды tsTON/stTON conf=1** (детерминированные redemption-rate, не рыночные); tsUSDe 0.085%.

## 3. Главный результат — почему платформенного убытка НЕТ на funded MAIN

### Стена 1: stale-price на реальных фидах в bad debt не конвертится
- Для убытка ПУЛА нужен невозвратный остаток долга = позиция underwater по РЕАЛЬНОЙ цене = реальное движение ≥ подушки (CF/LT/bonus). Обычный режим ~20-27%, HE ~3.4-4%.
- Stale-окно даёт только **время + cherry-pick реального тика**, но НЕ магнитуду сверх реально случившегося. VAA подделать нельзя.
- Прежняя «Critical combo» (HE + per-feed basket) опиралась на ложную модель: будто HE-ноги — независимые шумные фиды. Реальность: общий базовый фид + детерминированный RR → синтетическая декорреляция ≈ 0.
- Базовые мажоры (TON/USDT/USDe) глубокие → manufacture тика ≥ порога не экономичен. Тонких alt-Pyth-фидов на MAIN нет (alts — на Classic-oracle пуле).
- PoC в папке (`run_he_loss`, `execute_attack`) «срабатывали» только потому, что **зашивали декорреляцию как ВХОД**, а не выводили из реального поведения фидов.
- **Вывод:** отказ команды «нет ущерба платформе / by design» для этого вектора **корректен**.

### Стена 2: исходник funded MAIN не публичен
- Единственный пул с публичным byte-match исходником (`d9138cb` → `08b54a3f`) = `EQCsOdQ`, держит **~$5**.
- Funded MAIN крутит `b90881c4` — нет в репо ни в одной версии (v6/v7/v8 дают другие хэши). Source-PoC к funded MAIN невозможен → любое «вероятно применимо к MAIN» недоказуемо (тот hand-wave, что отбили).
- Ветка репо `v9` указывает на коммит `d9138cb` с сообщением «v8» — т.е. публичная «v9» = тот же v8.

## 4. Аудит ядра v9 (`d9138cb`) — новых platform-loss багов НЕТ

| Поверхность | Файл | Вывод |
|---|---|---|
| Ликвидация user | `core/user-liquidate.fc` | isBadDebt/cap33/$200-floor = как в v8 (clean). |
| Ликвидация master | `core/master-liquidate.fc` | `custom_payload_recipient` (новое) = адрес самого ликвидатора (его награда), не утечка; liquidity-cap 75%. |
| Supply/withdraw | `core/{user,master}-supply-withdrawal.fc` | `is_borrow_collateralized` ПОСЛЕ записи principal; liquidity/borrow-cap'ы; origination-fee = доход протокола. |
| Revert-флоу (новое) | `core/master-revert-call.fc` | authenticity через `calculate_user_address(owner, subaccount)`; refund owner/liquidator. |
| Ref-pricing | `plugins/pyth/parse_price_feeds.fc` | `min(timestamp)` обоих фидов; ref-copy ограничен config (`allowed_ref_tokens`). |
| Freshness | `data/prices-packed.fc` | единственный гейт `now() > ts + 180` per-feed (= stale-vuln). |
| Rewards | `core/master-admin.fc` | в ядре только tracking-индексы; выдача — в отдельных rewards-контрактах (не в репо); `claim_asset_reserves` admin-only + capped. |
| Subaccount | `logic/addr-calc.fc` | адрес = hash(blank+platform+owner+type+subaccount16); коллизий/спуфа нет. |

## 5. Что РЕАЛЬНО подтверждено (submittable)

Stale-price unjust-liquidation (см. `HACKENPROOF_REPORT.md`):
- **Severity: High** (убыток ЮЗЕРА, не платформы).
- Доказано на байткоде: stale ≤179s проходит единственный гейт; healthy→liquidatable флип на реальном mainnet-байткоде (fork + get-методы).
- Byte-match только к in-scope `EQCsOdQ` (~$5). К funded MAIN — по принципу (тот же оракул/модель), без byte-proof.

## 6. Остающиеся честные пути к платформенному убытку (не реализованы)

1. **Conditional-depeg амплификатор** — stale 180s усиливает РЕАЛЬНЫЙ депег USDe / де-рейт LST. Триггер-зависимо; команда вероятно учла.
2. **ALTS/Classic-oracle пулы** — другой оракул (backend-signed), тонкие активы (CATI/NOT/DOGS). Другая поверхность. Но funded слабо.
3. **Reverse-engineer `b90881c4`** — единственный способ найти баг именно в коде funded MAIN; крайне трудоёмко, чистого source-PoC не даёт.

## 7. Артефакты

- `evaa-contracts/` — актуальный исходник (commit `d9138cb`, публичная v9/v8).
- `poc/` — скрипты: `check_ttl.js` (TTL on-chain), fork/get-method PoC реального MAIN, parse_check байткод-PoC.
- `HACKENPROOF_REPORT.md` — submittable High finding.
- Память сессии: `evaa-main-pool-facts` (чтобы не повторять ложные PoC).

## 8. Bottom line

Найденная stale-уязвимость **на funded MAIN в платформенный убыток не конвертится**, и в публичном исходнике нового platform-loss бага нет. Подтверждённый результат — **High** (unjust-liquidation, убыток юзера). Critical-платформенный убыток держится только на (а) реальном депег/де-рейт событии в окне 180s, либо (б) баге в непубличном коде funded MAIN.
