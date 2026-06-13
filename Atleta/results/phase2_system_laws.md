# ФАЗА 2 — Законы системы
## Atleta Network — Mainnet Only

---

## КОНТЕКСТ: РЕАЛЬНОЕ СОСТОЯНИЕ MAINNET

Перед законами — важный факт, меняющий картину системы:

**Mainnet в июне 2026 = преимущественно TRON-оракул**
- 4,469,075 блоков, ~1.14M транзакций, 7,202 адресов
- 100% видимой on-chain активности = `updateLastProcessedTronBlock` от 1 EOA в PlatformController
- Единственный deployed ERC-20: `0x18888DFFA40A278C44D2a2cC58f1f6C97C3fD53c` (20B supply, 7 decimals, 1 holder)
- Мост "Coming Soon" в UI, но оракул уже работает
- Staking и governance — Substrate pallets, не EVM контракты

Система состоит из двух слоёв с разными наборами законов:
- **Substrate layer**: staking, governance, consensus (BABE+GRANDPA, NPoS)
- **EVM layer**: PlatformController (UUPS proxy), будущий bridge

---

## ЗАКОНЫ SUBSTRATE-СЛОЯ

### Закон S1: Одна эра — одно распределение наград
**Формулировка**: Каждая эра (36ч) производит ровно один цикл расчёта и распределения наград. Двойное начисление за одну эру невозможно.

**Полагаются**: validator stash accounts, nominators, pallet-staking reward logic

**Должен быть enforced**: pallet-staking (на уровне runtime), хранение era_reward_points per validator per era

**Только assumed**: indexer/UI (могут показывать неправильный accumulated balance до claim)

**Если ложный**: validator мог бы клеймить одну и ту же эру несколько раз → инфляция ATLA сверх 250M/year

---

### Закон S2: Slash номинатора пропорционален slash валидатора и его стейку в пуле
**Формулировка**: Если валидатор получает X% slash, каждый номинирующий его номинатор теряет X% от своего stake, атрибутированного этому валидатору.

**Полагаются**: nominators (модель рисков), pallet-staking (enforcement)

**Должен быть enforced**: pallet-staking slash distribution logic

**Только assumed**: UI, номинаторы при выборе валидаторов

**Если ложный**: 
- Slash может не дойти до номинаторов → снижение риска для плохих валидаторов
- Slash может превысить долю номинатора → потеря чужих средств

---

### Закон S3: Nomination изменяется не раньше следующей эры
**Формулировка**: Смена списка nominated validators вступает в силу только в следующую эру (до 36 часов задержки).

**Полагаются**: pallet-staking election algorithm

**Должен быть enforced**: pallet-staking (changes queued per era)

**Только assumed**: пользователи, считающие что смена nomination мгновенная

**Если ложный**: номинатор мог бы мгновенно выйти перед slash — уничтожает incentive alignment

---

### Закон S4: Unbonding необратим в течение периода ожидания
**Формулировка**: Начатый unbond (72h для номинаторов / 21d для валидаторов) не может быть отменён или ускорен.

**Полагаются**: pallet-staking, nominators, validators

**Должен быть enforced**: pallet-staking (unbonding_chunks с block deadline)

**Только assumed**: UI

**Если ложный**: валидатор мог бы мгновенно извлечь stake перед slash — destroys security

---

### Закон S5: Награды истекают ровно через 84 эры
**Формулировка**: Unclaimed rewards за эру E становятся недоступными после эры E+84 и переходят в treasury.

**Полагаются**: nominators, validators (должны клеймить вовремя)

**Должен быть enforced**: pallet-staking (HistoryDepth parameter)

**Только assumed**: пользователи, ожидающие награды накопятся автоматически

**Если ложный**: средства могут быть потеряны (already true — это feature) или наоборот клеймить после истечения

**ОСОБЕННОСТЬ**: Pool participants (nomination pools) — NEEDS VERIFICATION — клеймят ли отдельно или pool claim аккумулирует?

---

### Закон S6: Slash применяется только после 7-дневного challenge window
**Формулировка**: Обнаруженный misbehavior помещается в escrow на 7 дней. Stake не уменьшается мгновенно.

**Полагаются**: validators (время на challenge), system (отсрочка применения)

**Должен быть enforced**: pallet-offences + pallet-staking (deferred slashing)

**Только assumed**: nominators (не знают о pending slash в real-time)

**Если ложный**: 
- Slash применяется мгновенно → нет времени на challenge
- Slash применяется никогда → нет наказания

---

### Закон S7: Governance execution соответствует on-chain vote результату
**Формулировка**: Если proposal принят on-chain (majority vote, 21-day period), BCSports Foundation исполняет его точно.

**Полагаются**: all governance participants

**Должен быть enforced**: NOWHERE ON-CHAIN — только social contract с Foundation

**Только assumed**: все

**КРИТИЧНО**: Это НЕ enforced on-chain. Foundation может задержать, изменить или не исполнить proposal.

**Если ложный**: governance becomes theater — голосование не имеет силы

---

### Закон S8: Nomination Pool не даёт governance rights участникам
**Формулировка**: ATLA, размещённый в nomination pool, не конвертируется в voting power для ATLETAgov.

**Полагаются**: governance system (корректный подсчёт voting power)

**Должен быть enforced**: ATLETAgov pallet (voter eligibility check)

**Только assumed**: pool participants

**Если ложный**: pool master мог бы голосовать pooled ATLA, которым не владеет → governance hijack
**ИЛИ**: участники pools вообще теряют право голоса пока в pool

---

### Закон S9: Session keys привязаны к конкретному validator stash
**Формулировка**: Session keys (используемые для подписи блоков) уникально ассоциированы с validator стэшем и не могут использоваться другим валидатором.

**Полагаются**: consensus integrity, pallet-session

**Должен быть enforced**: pallet-session (key registration on-chain)

**Только assumed**: network security model

**Если ложный**: equivocation/impersonation possible

---

### Закон S10: Валидатор получает роль (Author/Publisher) на всю сессию (6 часов)
**Формулировка**: Роль в сессии присваивается при старте сессии и не меняется в течение 6 часов.

**Полагаются**: consensus participants, block production

**Должен быть enforced**: pallet-session (session plan + rotation)

**Только assumed**: BABE/GRANDPA scheduling

**Если ложный**: хаос в consensus — кто производит блоки?

---

### Закон S11: Era point deviation >25% от среднего = unresponsiveness
**Формулировка**: Если валидатор набирает era points на >25% ниже среднего по всем валидаторам, он помечается как unresponsive.

**Полагаются**: pallet-im-online (heartbeat + era points check)

**Должен быть enforced**: pallet-im-online + pallet-offences

**Только assumed**: честность метрики

**ВНИМАНИЕ**: Это ОТНОСИТЕЛЬНАЯ метрика. Если 255 валидаторов договорятся набирать points медленно, 256-й будет выглядеть как "overperforming" — и наоборот, все могут синхронно снизить производительность не триггеря slash

---

## ЗАКОНЫ EVM-СЛОЯ (PlatformController)

### Закон E1: lastProcessedTronBlock монотонно возрастает
**Формулировка**: ORACLE может только увеличивать `lastProcessedTronBlock`. Откат на более ранний block номер невозможен.

**Полагаются**: bridge logic (использует этот nonce для проверки обработанных транзакций)

**Должен быть enforced**: PlatformController (check: `BlockNotNewer` error если новый ≤ текущего)

**Только assumed**: downstream bridge contracts (если существуют)

**Если ложный**: 
- Реорг в TRON chain → блоки на TRON откатились, но Atleta уже "знает" о более высоком блоке → невозможность обработать reorged транзакции
- TRON реорг = silent loss или double processing

---

### Закон E2: Только адрес с ORACLE ролью может обновлять TRON state
**Формулировка**: `updateLastProcessedTronBlock` доступна исключительно ORACLE role. Любой другой caller получает revert.

**Полагаются**: bridge correctness

**Должен быть enforced**: OpenZeppelin AccessControl (`onlyRole(ORACLE)`)

**Только assumed**: все потребители этого state

**СОСТОЯНИЕ MAINNET**: ORACLE = один EOA (`0x3Aa473E3818AAB6F5bC103936466e7BCf78e31E2`)
→ Single point of failure / single point of trust

---

### Закон E3: SUPER_ADMIN может паузировать любую операцию
**Формулировка**: При любом pause level ≥ 1 определённые операции должны быть заблокированы. FULL pause = всё заблокировано.

**Полагаются**: все platform contracts (через PlatformController.isPaused checks)

**Должен быть enforced**: каждый зависимый контракт должен сам проверять pause state — NEEDS VERIFICATION (централизованная проверка или per-contract?)

**Только assumed**: UI (может не отображать paused state корректно)

**Если ложный**: операции проходят в paused state → обходит emergency stop

---

### Закон E4: executeBatch выполняет только авторизованные SUPER_ADMIN операции
**Формулировка**: Произвольные вызовы через `executeBatch` исходят от PlatformController (msg.sender), а не от SUPER_ADMIN напрямую.

**Полагаются**: target contracts (для авторизации входящих вызовов)

**Должен быть enforced**: НИГДЕ специально — зависит от того, как target contracts проверяют caller

**КРИТИЧНО**: Если любой контракт в экосистеме доверяет PlatformController адресу как SUPER_ADMIN → SUPER_ADMIN через executeBatch имеет права этих контрактов, даже если SUPER_ADMIN не имеет прямой роли. ESCALATION PATH.

---

### Закон E5: Platform fee ≤ 100% (10,000 bps)
**Формулировка**: `updatePlatformFee` принимает только значения ≤ 10,000 (bps). 10,000 = 100% fee.

**Полагаются**: users (платят fee), downstream fee calculation

**Должен быть enforced**: PlatformController (`FeeTooHigh` check)

**Только assumed**: контракты, использующие platformFee без дополнительной проверки

**ВНИМАНИЕ**: 100% fee технически VALID. SUPER_ADMIN может установить fee = 10,000 → конфискация 100% пользовательских средств через bridge

---

### Закон E6: Upgrade PlatformController требует SUPER_ADMIN
**Формулировка**: Новая implementation может быть установлена только SUPER_ADMIN через `_authorizeUpgrade`.

**Полагаются**: system integrity

**Должен быть enforced**: UUPS pattern + AccessControl

**Только assumed**: пользователи (верят что implementation неизменна)

**КРИТИЧНО**: SUPER_ADMIN = deployer EOA `0xB4349Fb7Fe240E24E8c5b2fF5caF4Cc265d38aF7` (684K ATLA, non-multisig, non-timelock)
→ Мгновенный upgrade без задержки, без on-chain governance approval

---

### Закон E7: lockPeriod минимум 30 дней
**Формулировка**: Vesting lock period не может быть установлен меньше 30 дней.

**Полагаются**: users с vested tokens

**Должен быть enforced**: PlatformController (`LockTooShort` check)

**Только assumed**: downstream vesting contracts

**UNKNOWN**: существуют ли vesting contracts на mainnet сейчас?

---

## КРИТИЧЕСКИЕ МЕЖСЛОЙНЫЕ ЗАКОНЫ

### Закон X1: Native ATLA (Substrate) и EVM ATLA — одно и то же
**Формулировка**: Баланс ATLA на Substrate-адресе и EVM-адресе (через H160 маппинг) представляют один и тот же актив без двойного учёта.

**Полагаются**: все пользователи, EVM dApps, staking pallets

**Должен быть enforced**: Frontier precompiles (Substrate ↔ EVM balance bridge)

**Только assumed**: UI, dApps

**NEEDS VERIFICATION**: как именно происходит маппинг? Если Substrate address и EVM address — разные счета, существует ли возможность иметь средства в "обоих местах"?

---

### Закон X2: Governance не может изменить consensus параметры
**Формулировка**: ATLETAgov не может изменить consensus механизм, finality, block production или экспульсировать валидаторов — только параметры emissions, treasury, block-time, validator requirements.

**Полагаются**: validators (защищены от governance attack)

**Должен быть enforced**: ATLETAgov pallet (limited change scope)

**Только assumed**: documents + Foundation

**NEEDS VERIFICATION**: где именно в коде ограничен scope governance proposals?

---

## ИТОГОВАЯ ТАБЛИЦА ЗАКОНОВ

| ID | Закон | Слой | Enforced On-Chain | Риск если ложный |
|----|-------|------|-------------------|-----------------|
| S1 | Одна эра = одно распределение | Substrate | YES | Инфляция |
| S2 | Slash номинатора пропорционален | Substrate | YES | Broken incentives |
| S3 | Nomination delay = следующая эра | Substrate | YES | Slash avoidance |
| S4 | Unbonding необратим | Substrate | YES | Security broken |
| S5 | Rewards expire 84 eras | Substrate | YES | Treasury drain |
| S6 | Slash deferred 7 days | Substrate | YES | No challenge possible |
| S7 | Governance execution by Foundation | Cross | **NO** | Governance theater |
| S8 | Pool ≠ governance rights | Substrate | UNKNOWN | Voting manipulation |
| S9 | Session keys unique per validator | Substrate | YES | Impersonation |
| S10 | Role per session = 6h | Substrate | YES | Consensus chaos |
| S11 | Era points deviation threshold | Substrate | YES | Relative metric gaming |
| E1 | TRON block monotonic | EVM | YES | Reorg blindness |
| E2 | ORACLE = единственный updater | EVM | YES | Single point failure |
| E3 | Pause propagates to all contracts | EVM | UNKNOWN | Emergency bypass |
| E4 | executeBatch caller = Platform | EVM | **NO** | Authority escalation |
| E5 | Fee ≤ 100% | EVM | YES (technically) | 100% fee valid |
| E6 | Upgrade = SUPER_ADMIN only | EVM | YES | Instant upgrade |
| E7 | Lock period ≥ 30 days | EVM | YES | Fast unlock |
| X1 | ATLA balance unified | Cross | UNKNOWN | Double accounting |
| X2 | Governance scope limited | Cross | UNKNOWN | Consensus attack |

---

## НАИБОЛЕЕ ТРЕВОЖНЫЕ ЗАКОНЫ (ДЛЯ ФАЗЫ 3)

1. **S7** (Governance execution) — полностью вне on-chain enforcement
2. **E4** (executeBatch authority escalation) — не enforced как закон
3. **E2** (Single ORACLE EOA) — structural single point of failure
4. **E6** (Upgrade без timelock) — SUPER_ADMIN = 1 EOA = мгновенный upgrade
5. **S3 + S6 взаимодействие** (Nomination delay vs slash window) — timing race
6. **S11** (Relative era points metric) — коллективное снижение threshold
7. **E1** (TRON reorg blindness) — монотонный oракул не может откатиться

---

*Фаза 2 завершена. Ожидаю отмашку на Фазу 3.*
