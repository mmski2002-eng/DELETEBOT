# ФАЗА 1 — Восстановление системы с первых принципов
## Atleta Network — Аудит в рамках легитимного анализа

---

## ТАБЛИЦА ИСТОЧНИКОВ

| Источник | Статус | Примечание |
|----------|--------|------------|
| Code / contracts | MISSING | GitHub существует (github.com/Atleta-network/atleta), pallet-код недоступен напрямую через WebFetch (403/404). Только общая структура каталогов |
| Docs | PROVIDED | GitBook документация (blockchain-sports.gitbook.io) — основной источник |
| UI assumptions | MISSING | Нет доступа к UI/dApp |
| Backend / indexer | MISSING | Нет данных об indexer-реализации |
| Events | MISSING | Нет on-chain данных, нет explorer с event log |
| API | MISSING | RPC endpoint известен (localhost:9944), публичный RPC неизвестен |
| Off-chain workers | MISSING | Неизвестны (Substrate OCW — возможны, не задокументированы) |
| Admin / governance actions | INFERRED | Документация описывает ATLETAgov, исполнение — BCSports Foundation |
| Economic incentives | PROVIDED | Tokenomics, emission schedule, slashing, rewards — задокументированы |
| Cross-chain integrations | INFERRED | XCM описан, статус — PLANNED post-mainnet, не активен |

**Ключевой факт**: большинство технических деталей взяты из документации (INFERRED/PROVIDED), а не из верифицированного кода. Всё описанное ниже — модель по документации, не по source.

---

## 1. ОБЪЕКТЫ

### 1.1 Account (Аккаунт)
- **Где живёт**: Substrate chain state (frame_system::Account), параллельно EVM-аккаунт (H160)
- **Создаётся**: при первом получении средств или явном создании
- **Изменяется**: при каждой транзакции, staking-операции
- **Уничтожается**: при обнулении баланса (dust collection rules)
- **ID**: SubstrateAccountId (SS58) + EVM-адрес (H160) — ВОЗМОЖЕН МАППИНГ между двумя пространствами
- **Владелец**: пара ключей (keypair) — UNKNOWN, есть ли multisig или threshold schemes
- **Жизненный цикл**: постоянный пока есть средства; архивируется при реапе (existential deposit)

### 1.2 Validator (Валидатор)
- **Где живёт**: pallet-staking (Substrate), validator set
- **Создаётся**: через bond + validate calls; минимум 75,000 ATLA
- **Изменяется**: при изменении commission, при ротации ролей (Author/Publisher) каждые 6 часов
- **Уничтожается/архивируется**: через chill или slash; exit fee 1 ATLA
- **ID**: SubstrateAccountId (stash + controller key model — NEEDS VERIFICATION)
- **Владелец**: stash account (контролируется через controller — NEEDS VERIFICATION)
- **Жизненный цикл**: Candidate → Active → Chilled/Slashed

**Состояния валидатора**:
- Candidate: в пуле до 1,000 ожидающих
- Active: до 256 участвуют в консенсусе
- Role in session: Author (собирает/пакует транзакции) ИЛИ Publisher (финализирует блоки)
- Роли ротируются рандомно (VRF) каждые 6 часов

### 1.3 Nominator (Номинатор)
- **Где живёт**: pallet-staking
- **Создаётся**: через bond + nominate calls; минимум 10 ATLA
- **Изменяется**: при изменении списка nominated validators, при получении наград
- **Уничтожается**: через unbond (72 часа) + withdraw
- **ID**: SubstrateAccountId
- **Владелец**: keypair
- **Жизненный цикл**: bonded → unbonding (72h) → free

### 1.4 Nominator Pool
- **Где живёт**: pallet-nomination-pools (Substrate standard)
- **Создаётся**: через pool creation; минимум 1 ATLA deposit
- **Изменяется**: при join/leave/slash участников
- **Уничтожается**: при дестракции пула (Master/root role)
- **ID**: pool_id (числовой)
- **Владельцы**: 4 роли — Creator, Nominator, Defender (bouncer), Master (root)
- **Жизненный цикл**: Open → Blocked → Destroying
- **Лимит**: до 512 пулов
- **Примечание**: pool participants не получают governance benefits — IMPORTANT

### 1.5 Bond / Stake Record
- **Где живёт**: pallet-staking (ledger per stash)
- **Состояния**: bonding → active → unbonding chunks
- **Особенность**: unbonding для валидаторов — 21 день (504 часа), для номинаторов — 72 часа
- АСИММЕТРИЯ: номинатор выходит в 7 раз быстрее валидатора

### 1.6 Session (Сессия)
- **Период**: 6 часов
- **Содержит**: validator role assignments (Author/Publisher)
- **Ротация**: рандомная через VRF + pseudo-random modality
- **Жизненный цикл**: автоматическое переключение

### 1.7 Era (Эра)
- **Период**: 36 часов = 6 sessions
- **Содержит**: validator election, reward calculation, distribution
- **ID**: числовой, монотонно возрастает
- **Критично**: rewards expiration через 84 эры (~126 дней) → treasury

### 1.8 Slash Record
- **Где живёт**: pallet-staking (offences/slashing)
- **Создаётся**: при обнаружении misbehavior (heartbeat failure, equivocation, unjustified vote)
- **Период эскроу**: 7 дней (challenge window)
- **Исход**: применяется к stake или отменяется по доказательству
- **Получатель**: treasury (если не заreimburse)

### 1.9 Governance Proposal
- **Где живёт**: ATLETAgov pallet
- **Создаётся**: staker с bonded ATLA (≥10 ATLA для submission — NEEDS VERIFICATION)
- **Voting period**: 21 дней (604,800 блоков)
- **Исполнение**: BCSports Foundation — OFF-CHAIN (CRITICAL GAP)
- **Жизненный цикл**: Proposed → Voting → Passed/Failed → Executed (by Foundation)

### 1.10 Parachain Slot
- **Где живёт**: IO layer (relay hub)
- **Создаётся**: через governance proposal + blind candle auction + competence test
- **Период**: 3 года (31,536,000 блоков)
- **Минимальная ставка**: 100,000 ATLA
- **Жизненный цикл**: Auctioned → Active → Expired/Renewed
- **Статус**: PLANNED — не активен на mainnet

---

## 2. АКТОРЫ

### 2.1 User (Пользователь)
- **Может делать**: отправлять транзакции (EVM/Substrate), переводить ATLA, стейкать, голосовать, взаимодействовать с EVM-контрактами
- **Видит**: свой баланс, pending транзакции, validator список, governance proposals
- **Доверяет**: RPC node (NEEDS VERIFICATION — нет данных о trustless light-client)
- **Может пропустить**: событие slash на номинируемом валидаторе (нет push-уведомлений)
- **Может сделать поздно**: claim rewards (до 84 эр)
- **Может сделать дважды**: nominate одних и тех же валидаторов; отправить дублирующую транзакцию (если nonce management слабый)
- **Убыток при**: slash nominated validator (пропорционально); unbonding в невыгодный момент

### 2.2 Validator (Валидатор)
- **Может делать**: производить блоки (Author role), финализировать (Publisher role), устанавливать commission %
- **Видит**: мемпул, текущую сессию, награды
- **Доверяет**: своим session keys
- **Может пропустить**: heartbeat → slash Level 1
- **Может сделать дважды (equivocation)**: подписать два блока на одном слоте → slash Level 4 (100%)
- **Убыток при**: equivocation, offline, unjustified votes
- **Награда**: emissions (~24.112 ATLA/block) + transaction fees; доля зависит от era points

### 2.3 Nominator (Номинатор)
- **Может делать**: выбрать до 16 валидаторов, изменить nominations в следующую эру
- **Видит**: список кандидатов, их stake и commission
- **Доверяет**: выбранным валидаторам (несёт их slash пропорционально!)
- **Может пропустить**: момент slash на валидаторе (нет alerts)
- **Может сделать поздно**: unbond (72h задержка) — не успеет избежать slash
- **Убыток при**: slash nominated validator; все номинированные offline

### 2.4 Nominator Pool Roles

**Master (root)**:
- полный контроль над пулом
- может изменить любую роль
- может уничтожить пул

**Creator**:
- создал пул, изначально все роли

**Nominator**:
- определяет validator nominations от имени пула
- НЕ имеет других прав

**Defender (bouncer)**:
- управляет членством (block/kick участников)
- НЕ управляет номинациями

**КРИТИЧНО**: роли могут быть разделены между разными аккаунтами. Конфликт интересов возможен.

### 2.5 Foundation / BCSports Admin
- **Может делать**: исполнять governance proposals (off-chain)
- **Видит**: все on-chain события
- **Доверяет**: on-chain voting результатам
- **Может сделать поздно**: задержать исполнение принятого предложения
- **КРИТИЧНО**: исполнение off-chain — нет on-chain enforcement

### 2.6 Backend / Indexer
- **Статус**: MISSING — нет данных о реализации
- **Предположительно**: индексирует события (staking, transfers, governance)
- **Риск**: может расходиться с on-chain state при reorg или при пропуске событий

### 2.7 Oracle
- **Статус**: MISSING — не упомянут в документации
- **UNKNOWN**: как определяется цена ATLA в USD для любых on-chain расчётов?

### 2.8 Bridge / Relayer
- **Статус**: INFERRED — XCM описан, не активен
- **Предположительно**: relay validators между parachains и IO hub
- **UNKNOWN**: конкретная реализация relayer, trust model

---

## 3. ПОРЯДОК СОБЫТИЙ

### 3.1 Строго упорядоченные последовательности
- bond → validate/nominate (нельзя номинировать без bond)
- эффект nomination вступает в следующую эру (не текущую)
- slash escrow 7 дней → потом применяется
- unbond → выжидание 72h/21d → withdraw_unbonded
- reward claim до истечения 84 эр

### 3.2 Произвольный порядок
- governance proposals — независимы друг от друга
- nominations от разных номинаторов на одного валидатора

### 3.3 Повторяемые события
- nominate — можно обновлять список каждую эру
- heartbeat — должен отправляться КАЖДУЮ сессию
- reward claim — номинаторы должны клеймить сами (NEEDS VERIFICATION — авто или manual?)

### 3.4 Могут не произойти вовсе
- slash challenge — необязателен для пострадавшего
- reward claim — если не заклеймить до 84 эр → treasury
- governance execution — Foundation может не исполнить

### 3.5 Могут произойти частично
- partial slash — Level 1 (0.1%), не полный
- partial era rewards — если валидатор offline часть сессий

### 3.6 Видит один, но не другой
- slash event виден on-chain; nominator может не мониторить
- governance passage видна on-chain; Foundation может медленно реагировать
- session rotation видна on-chain; UI может кэшировать старое состояние

### 3.7 Зависит от времени
- era boundaries — строго по блокам
- 7-day slash challenge window — by block count
- 84-era reward expiration — абсолютный deadline
- parachain slot lifetime — 3 года блоками (31,536,000)

---

## 4. ПАМЯТЬ СИСТЕМЫ

### 4.1 Хранит on-chain
- Balances (Substrate + EVM)
- Staking ledger (bond, unbonding chunks)
- Validator/Nominator preferences
- Slash records (7-day escrow)
- Era reward points
- Governance proposals и votes
- Nomination pool state
- Session keys

### 4.2 Забывает / Истекает
- Rewards после 84 эр → treasury (данные об unclaimed rewards возможно очищаются)
- Slash records после challenge period + применения

### 4.3 Выводится только из событий (UNKNOWN)
- Indexer state — MISSING, неизвестно что кэшируется
- Historical era data — неизвестно хранится ли полная история

### 4.4 Существует только в off-chain состоянии
- Foundation execution record — нет on-chain подтверждения исполнения governance
- Validator reputation — упоминается в docs, но on-chain хранение UNKNOWN

### 4.5 Восстанавливается после сбоя
- Substrate runtime state — полностью из block history
- Slash records — on-chain, не теряются
- Unbonding chunks — on-chain

### 4.6 Различие chain state vs backend state
- UNKNOWN — нет данных об indexer реализации
- РИСК: indexer может пропустить события при reorg (BABE + GRANDPA — reorgs возможны до финализации)

---

## 5. ЭКОНОМИКА

### 5.1 Кто платит
- User: gas fees (base 2 gwei + priority tip)
- Validator при выходе: 1 ATLA exit fee
- Parachain operator: 100,000+ ATLA collateral

### 5.2 Кто получает
- Validators: emissions + transaction fees (pro-rata по era points)
- Nominators: доля от validator rewards (по commission %)
- Treasury: slash penalties (после challenge period) + unclaimed rewards (после 84 эр)

### 5.3 Кто авансирует средства
- Nominators: bonded ATLA заморожен до unbonding
- Validators: 75,000+ ATLA заморожен до 21-дневного unbonding
- Parachain: 100,000 ATLA в escrow на 3 года

### 5.4 Кто получает refund
- Challenged slash: если доказательство принято — stake возвращается
- Parachain: collateral возвращается после окончания slot lifetime

### 5.5 Кому выгодны задержки
- Validator с pending slash: 7-дневный challenge window даёт время
- Foundation: задержка execution дает гибкость (но без accountability)
- Nominator с unbonding 72h vs validator 21d: номинатор может быстро выйти перед slash

### 5.6 Кому выгодны повторы
- Reward claimer: compound rewards если клеймить часто (NEEDS VERIFICATION)

### 5.7 Кому выгодно частичное исполнение
- Era point система: validator получает больше за большее количество authored/published блоков

### 5.8 Кому выгодна отмена
- Nominator: быстро un-nominate для избегания slash — НО смена effective в следующую эру (36h задержка)
- КРИТИЧНО: если slash происходит в текущей эре, nominator уже не успевает выйти

### 5.9 Кому выгоден fallback path
- Validator candidate: если все 256 active slots заняты, candidate ждёт следующей эры для Election
- Backup block production: round-robin fallback при empty slots (BABE secondary)

---

## КЛЮЧЕВЫЕ СТРУКТУРНЫЕ НАБЛЮДЕНИЯ

1. **Governance execution gap**: on-chain vote → off-chain execution Foundation. Нет enforcement.

2. **Unbonding asymmetry**: номинатор (72h) vs валидатор (21d). Разная скорость выхода при slash.

3. **Nomination effect delay**: эффект nomination (и отмены) — следующая эра. 36-часовая задержка.

4. **Pool governance exclusion**: участники пула не получают governance rights. Кто голосует от имени pool's ATLA?

5. **Reward expiration**: 84 эры (~126 дней). Если nominator неактивен — средства в treasury.

6. **Slash challenge**: кто имеет право подать challenge? Только слэшнутый? Кто-то ещё? UNKNOWN.

7. **Session role randomization**: Author vs Publisher ротируются. Что происходит с мемпулом при ротации? UNKNOWN.

8. **Foundation allocation**: 140M ATLA в treasury, governance-controlled. Foundation исполняет — но сама же держит allocation. Circular authority?

9. **Validator exit fee 1 ATLA**: нет entry fee, но есть exit fee. Экономический смысл? Блокирует ли это быстрый выход при угрозе slash?

10. **Era points as reward basis**: >25% deviation от среднего → unresponsiveness. Относительная метрика — зависит от поведения других валидаторов.

---

## СТАТУС ИСТОЧНИКОВ ДЛЯ ВЕРИФИКАЦИИ

Для продолжения анализа необходимы:
- `runtime/src/lib.rs` — конфигурация pallets, параметры staking/session/governance
- `pallets/` — исходники custom pallets (faucet и любые другие)
- `precompiles/` — EVM precompiles (доступ к staking/governance из EVM контрактов?)
- On-chain explorer данные — реальные события, era history
- RPC endpoint — read-only queries для verification state

---

*Фаза 1 завершена. Ожидаю отмашку на Фазу 2.*
