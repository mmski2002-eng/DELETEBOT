# Исследование контрактов Blum Memepad

Дата: 7 мая 2026

## Scope

Цель исследования: проверить on-chain поверхность **Blum Memepad** как launchpad для memecoin-контрактов на TON, с фокусом на:

- инициализацию токенов
- права `admin` / `mint`
- сбор средств на bonding curve
- комиссионную модель
- миграцию в DEX
- creator vs platform control

## Ограничения

Для Memepad-контрактов публичный FunC-исходник найти не удалось. Поэтому это исследование выполнено как **reverse-audit по живому chain state**, getter-методам, SDK и официальной документации Blum.

Из-за отсутствия публичного исходника:

- нет надежных `filename + line number`
- нельзя формально доказать все privileged branches
- выводы по правам сделаны по `get_jetton_data`, `get_bcl_data`, адресам админов и наблюдаемой архитектуре

Где это важно, я отмечаю это явно.

---

## Ключевые адреса

### Main Memepad contract / factory-like root

- `EQCCR3ChGA_4qY9s9HjASX7OmBaAFHZi8_lkqlkDl6R8FPvW`
- raw: `0:824770a1180ff8a98f6cf478c0497ece981680147662f3f964aa590397a47c14`

Наблюдаемый паттерн по событиям:

- пользователь/кошелек вызывает root с `op = 0xd7ab4f41`
- root форвардит в downstream token/master-like контракт с `op = 0xaf750d34`

Это хорошо согласуется с Memepad launch / buy flow.

### Проверенные downstream Memepad token masters

- `0:8a1f5bae39dfd730b086faa5474b74693efe28eea84a03bf5c271b9f4f54b0a3`
- `0:024f7f190799be92a7d12d811a3011fc71ac6a19fcff347a7d786e52b8bda11c`
- `0:0b38ffabfaf5e594af0dd6560bbd0dbf40b6c40ed361bec6916abecfb12734e1`
- `0:176352657c63e82c80e3b16cf7958e158ce1800b2096144dade76b045ad35810`
- `0:22441417e5d8eff6a46675bab19795bbaebefc86c897ac4fdb094c6f6996c9e5`

Все они:

- успешно отвечают на `get_jetton_data`
- успешно отвечают на `get_bcl_data`
- имеют одинаковую `BCL`-конфигурацию

### Глобальный admin, повторяющийся на всех проверенных токенах

- `EQCFQ00GPLirirqQnRZlH7R4ivnfhGQaFphUi8FPRC2nuVux`
- raw: `0:85434d063cb8ab8aba909d16651fb4788af9df84641a1698548bc14f442da7b9`
- interface: `wallet_v5r1`

### Повторяющийся fee recipient

- `EQAleeqJ5oWDWSIAwfS6eSKVx9u3vLpHTJ_piqn1s8yeYY-5`
- raw: `0:2579ea89e68583592200c1f4ba792295c7dbb7bcba474c9fe98aa9f5b3cc9e61`
- interface: `wallet_v5r1`
- name: `tonkinside-tg-community.ton`

### Router / DEX-related address

На одном из образцов `ctxRouterAddress` декодируется как:

- `EQBQ_UBQvR9ryUjKDwijtoiyyga2Wl-yJm6Y8gl0k-HDh_5x`
- TonAPI: `STON.fi DEX`
- interface: `stonfi_router_v2`

Это подтверждает связку Memepad -> bonding curve -> STON.fi DEX migration.

---

## Подтвержденная конфигурация BCL

На всех пяти проверенных Memepad token masters значения `get_bcl_data` были консистентны:

- `ctxBclSupply = 800,000,000 * 10^9`
- `ctxLiqSupply = 200,000,000 * 10^9`
- `ctxTradeFeeNumerator = 1`
- `ctxTradeFeeDenominator = 100`
- `ctxTradingCloseFee = 10 TON`
- `fullPriceTonNeed = 1515.151515153 TON`
- `fullPriceTonFees = 15.151515151 TON`

Это хорошо коррелирует с публичной документацией Blum:

- total supply: `1,000,000,000`
- bonding curve sale: `800,000,000`
- DEX liquidity: `200,000,000`
- trading fee: `1%`
- migration target / market cap: `1500 TON`

Источник: [Memepad FAQ](https://help.blum.io/memepad-faq.md)

---

## Findings

### 1. Platform-wide admin control over user-launched Memepad tokens

- Severity: High
- Location: `get_jetton_data` / `get_bcl_data` у проверенных Memepad token masters

### Description

У всех проверенных Memepad token masters поле `ctxAdmin` указывает не на создателя токена, а на один и тот же **глобальный wallet_v5r1 admin**:

- `EQCFQ00GPLirirqQnRZlH7R4ivnfhGQaFphUi8FPRC2nuVux`

При этом `ctxAuthorAddress` у токенов **разный**. Это означает, что:

- автор токена и admin токен-контракта разделены
- привилегированный контроль находится у платформенного адреса, а не у token creator

### Evidence

Примеры:

- `0:8a1f...b0a3`
  - `ctxAdmin = EQCFQ00GPLirirqQnRZlH7R4ivnfhGQaFphUi8FPRC2nuVux`
  - `ctxAuthorAddress = EQA8oPY_0K_YaCTDh7NQmAT6X2UKXdoGJrEO1t_nE5XPLMFx`
- `0:024f...a11c`
  - `ctxAdmin = EQCFQ00GPLirirqQnRZlH7R4ivnfhGQaFphUi8FPRC2nuVux`
  - `ctxAuthorAddress = EQAC5R0NWTfGGknsfYYJFPObtEC4oORAccA3qNUG00q9UmH_`
- `0:0b38...34e1`
  - `ctxAdmin = EQCFQ00GPLirirqQnRZlH7R4ivnfhGQaFphUi8FPRC2nuVux`
  - `ctxAuthorAddress = EQBxXZkNbsLiMzhnJ9si6AUShf2Jn-_RG-O7SEeSAA-gAB9h`

### Impact

Если privileged admin-path реализован стандартно или близко к стандартному, это означает:

- единая точка отказа для всех Memepad tokens
- при компрометации admin key можно затронуть сразу множество токенов
- у пользователей и создателей токенов нет on-chain суверенного контроля над master-level правами
- trust model launchpad становится существенно более централизованной, чем ожидается от “user-launched token”

### Recommendation

- по возможности renounce / burn admin после безопасной инициализации токена
- если admin нужен для migration или emergency flow, держать его только в `multisig + timelock`
- публично и явно документировать, что Memepad-created tokens находятся под platform admin control
- отделить “migration helper role” от полного token admin role

---

### 2. Mintable flag remains enabled on all sampled Memepad token masters

- Severity: High
- Location: `get_jetton_data` у проверенных Memepad token masters

### Description

У всех проверенных Memepad token masters `get_jetton_data` возвращает:

- `mintable = -1`

Одновременно `ctxAdmin` не zero и указывает на один и тот же platform wallet.

### Why this matters

В TON jetton-экосистеме `mintable = -1` обычно означает, что токен **не зафиксирован как окончательно неминтимый**. В сочетании с непустым admin это создает сильный centralization/backdoor сигнал.

Из-за отсутствия публичного FunC-кода я не могу формально доказать точный privileged mint handler по строкам исходника. Но с точки зрения on-chain интерфейса и trust model это уже существенный риск.

### Impact

При наличии реального privileged mint-path:

- возможно размывание supply после запуска
- creator / buyers не защищены от неожиданной эмиссии
- компрометация одного platform admin key может привести к массовой эмиссии по нескольким токенам

### Recommendation

- после завершения launch/migration переводить jetton в неминтимое состояние
- использовать explicit “mint disabled forever” invariant
- если mint должен существовать только до migration, зафиксировать это on-chain и документировать

---

### 3. Fee recipient is centralized and constant across sampled Memepad tokens

- Severity: Medium
- Location: `get_bcl_data` у проверенных Memepad token masters

### Description

У всех проверенных токенов `ctxFeeAddress` одинаковый:

- `EQAleeqJ5oWDWSIAwfS6eSKVx9u3vLpHTJ_piqn1s8yeYY-5`
- `tonkinside-tg-community.ton`

Это означает, что fee distribution для user-launched tokens централизована на один wallet.

### Impact

Это не “эксплойт” само по себе, но это:

- усиливает platform custody risk
- создает единый чувствительный fee sink
- делает компрометацию fee wallet значимой для всей launchpad-экосистемы

### Recommendation

- использовать `multisig`
- публиковать policy для fee custody
- если fee wallet меняем, сделать его изменение прозрачным и аудитируемым

---

### 4. Public docs do not transparently explain the real admin/mint trust model

- Severity: Medium
- Location: product documentation vs on-chain state

### Description

Публичные FAQ Memepad описывают:

- supply model
- 1% trading fee
- launch fee
- DEX migration

Но не объясняют явно, что:

- `ctxAdmin` у launchpad-токенов не принадлежит creator
- sampled token masters остаются `mintable = -1`
- fee recipient централизован

### Impact

Для launchpad-продукта это важная transparency gap:

- трейдеры и creators могут переоценивать decentralization
- security assumptions пользователя не совпадают с реальной on-chain моделью

### Recommendation

- добавить в документацию явный раздел `Admin / Mint / Fee custody model`
- описать, кто контролирует token master после deploy
- описать, когда и как mint authority renounce-ится, если это вообще происходит

---

### 5. Documentation / on-chain economics mismatch deserves clarification

- Severity: Low
- Location: [Memepad FAQ](https://help.blum.io/memepad-faq.md) vs `get_bcl_data`

### Description

FAQ говорит:

- market cap threshold: `1500 TON`
- DEX listing commission: `50 TON`

Проверенные `get_bcl_data` одновременно показывают:

- `fullPriceTonNeed = 1515.151515153 TON`
- `fullPriceTonFees = 15.151515151 TON`
- `ctxTradingCloseFee = 10 TON`

Часть этих чисел хорошо согласуется с 1% fee и целью `1500 TON`, но роль `10 TON` close fee и ее связь с публично заявленными `50 TON` описана недостаточно прозрачно.

### Impact

Риск здесь в первую очередь экономический и продуктовый:

- creators могут неверно понимать фактическую цену достижения migration
- исследователю труднее верифицировать, где именно удерживаются migration-related fees

### Recommendation

- документировать exact formula migration cost
- отдельно пояснить `bonding curve fees`, `close fee`, `DEX listing fee`
- опубликовать пример расчета для launch from 0 to DEX migration

---

## No issue found

### 1. On-chain slippage guard is present at interface level

- Status: No issue found

SDK для Memepad подтверждает, что пользовательские buy/sell сообщения включают on-chain пределы:

- `BUY (0xaf750d34)` содержит `limit`
- `SELL (0x742b36d8)` содержит `minReceive`

Источник:

- `BlumJetton.createBuyJetton()`
- `BlumJettonWallet.createSell()`
- публичный SDK: `attikusfinch/blum-sdk`

Это хороший сигнал: slippage protection не выглядит purely client-side.

### 2. Token metadata appears immutable after deployment

- Status: No issue found

Официальный troubleshooting FAQ утверждает:

- после успешного deploy изменить social links / token info невозможно

Источник: [Memepad Troubleshooting FAQ](https://help.blum.io/memepad-troubleshooting-faq.md)

Это снижает класс рисков “creator silently edits token presentation after launch”. Полностью on-chain проверить этот инвариант без исходника сложно, но публичная политика продукта здесь выглядит строгой.

---

## Open hypotheses / what remains unresolved

### 1. Exact privileged admin opcode surface

Без FunC-исходника пока нельзя формально доказать:

- какие именно admin messages принимает token master
- может ли admin не только mint, но и менять router / fee recipient / trading flags
- существует ли path для renounce admin после migration

### 2. Migration-complete state

По выборке из 20 downstream token masters, вызванных main Memepad root из recent event traces:

- `tradingEnabled = 1` у всех 20
- sample с `tradingEnabled = 0` не найден

Это означает, что в этой выборке я не подтвердил on-chain вид уже “закрытого” bonding curve после DEX migration.

### 3. Whether platform admin can drain or remap accumulated TON directly

Getter’ы показывают `ctxTonLiqCollected`, но без исходника пока нельзя окончательно доказать:

- кто именно может финализировать migration
- существует ли privileged withdrawal path вне ожидаемого DEX-migration flow

---

## Практический вывод

Самый важный вывод по Memepad-контрактам не в классическом AMM-баге, а в **trust model**:

- Memepad-created tokens выглядят не как fully creator-controlled token masters
- у них есть **единый platform admin**
- sampled tokens остаются **mintable**
- fee custody централизована

Для bug bounty это не обязательно “моментальный exploit”, но это очень значимый security finding класса:

- hidden centralization
- latent mint authority
- platform-wide blast radius if admin is compromised

Если получится добыть публичный FunC-код или BOC-дизассемблирование этих token masters, следующий лучший шаг:

1. подтвердить privileged mint opcode
2. проверить, может ли admin менять `ctxFeeAddress` / router / trading state
3. проверить, есть ли irreversible renounce path
4. проверить migration finalize flow на предмет fund redirection

---

## Использованные источники

- Memepad FAQ: https://help.blum.io/memepad-faq.md
- Memepad Troubleshooting FAQ: https://help.blum.io/memepad-troubleshooting-faq.md
- Memepad Videostream Quick Start Guide: https://help.blum.io/memepad-videostream-quick-start-guide.md
- публичный SDK: https://github.com/attikusfinch/blum-sdk
- TonAPI account / getter data по указанным адресам
