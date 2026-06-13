# ФАЗА 3 — Невозможные, но валидные состояния
## Atleta Network — Mainnet Only

Для каждого закона из Фазы 2 — конкретные ситуации, где закон ложен, но каждый шаг технически валиден.

---

## H01 — TRON Reorg Blindness / Монотонный оракул против реорга

**Закон ломается**: E1 (lastProcessedTronBlock монотонно возрастает)

**Странное валидное состояние**:
TRON имеет DPoS-консенсус с возможными реорганизациями. Оракул (`0x3Aa473E3818AAB6F5bC103936466e7BCf78e31E2`) обновляет `lastProcessedTronBlock = 83,370,629`. TRON reorg откатывает блоки 83,370,600–83,370,629. На TRON эти блоки исчезли, но Atleta-контракт уже знает их как "обработанные". Новый TRON блок 83,370,600' (с другим содержимым) никогда не будет обработан — закон E1 запрещает оракулу уменьшить lastProcessedTronBlock.

**Расходятся**:
- PlatformController: считает блоки 1..83,370,629 окончательно обработанными
- TRON chain: блоки 83,370,600–83,370,629 заменены новой историей

**Что получено неправильно**: транзакции из reorged блоков (депозиты/withdrawals на стороне TRON) уже "в истории", но новые транзакции из тех же номеров блоков никогда не обработаются

**Что проверить**: механизм финальности TRON перед отправкой в оракул; есть ли finality threshold в коде оракула

**Оценка**: Medium — зависит от того, есть ли downstream bridge logic

---

## H02 — Oracle Advance Attack / Массовый пропуск блоков

**Закон ломается**: E1 + E2

**Странное валидное состояние**:
Ключ ORACLE EOA скомпрометирован. Атакующий вызывает `updateLastProcessedTronBlock(99999999)` — номер далеко впереди реального состояния TRON. Один транзакция. Контракт принимает (новый > текущий). Теперь все реальные TRON-блоки между текущим (~83.3M) и 99.9M будут пропущены bridge-ом навсегда — он считает их "уже обработанными".

**Расходятся**:
- PlatformController: lastProcessedTronBlock = 99,999,999 (finalized)
- TRON chain: реальный блок ~83,370,629
- Bridge downstream: все депозиты из TRON-блоков 83M–99M не будут обработаны

**Что получено неправильно**: невозможность обработки легитимных TRON-транзакций на миллионы блоков вперёд; locked funds в TRON bridge

**Что проверить**: есть ли max_advance_limit в updateLastProcessedTronBlock? Нет — только `block > current`

**Оценка**: High — полностью достижимо при компрометации 1 EOA ключа

---

## H03 — executeBatch Authority Escalation / Эскалация через реестр

**Закон ломается**: E4 (executeBatch не enforced как authority check)

**Странное валидное состояние**:
SUPER_ADMIN вызывает `executeBatch([bridgeContract], [grantRole(WITHDRAWER_ROLE, attackerAddr)])`. Если `bridgeContract` проверяет `msg.sender == address(platformController)` для privileged calls, то SUPER_ADMIN через executeBatch эффективно имеет WITHDRAWER_ROLE в bridge — даже если у SUPER_ADMIN этой роли нет напрямую.

Либо: SUPER_ADMIN вызывает `executeBatch([registryContract], [setTreasury(attackerAddr)])` где registryContract читает treasury из PlatformController registry. `getContract("Treasury")` вернёт attackerAddr.

**Расходятся**:
- PlatformController: видит легитимный batch call от SUPER_ADMIN
- BridgeContract: видит вызов от trusted platformController address
- Users: ожидают что SUPER_ADMIN не имеет прямого доступа к bridge funds

**Что получено неправильно**: funds routing в attackerAddr через treasury; unauthorized role grants

**Что проверить**: как dependent contracts проверяют caller; использует ли bridge `onlyRole` или `msg.sender == platformController`

**Оценка**: High — если bridge использует address-based auth от PlatformController

---

## H04 — Instant Upgrade Without Timelock / Мгновенная замена реализации

**Закон ломается**: E6 (upgrade требует только SUPER_ADMIN, без задержки)

**Странное валидное состояние**:
SUPER_ADMIN (`0xB4349Fb7Fe240E24E8c5b2fF5caF4Cc265d38aF7`) вызывает `upgradeTo(maliciousImpl)`. Нет timelock, нет governance vote, нет задержки. maliciousImpl переопределяет `updateLastProcessedTronBlock` чтобы drain ETH или записывать произвольные данные в slots. Одна транзакция. Пользователи не уведомлены.

**Расходятся**:
- Users: думают PlatformController = code at 0xf42CC99...
- Proxy: теперь указывает на maliciousImpl
- Transaction: выглядит как стандартный `upgradeTo` вызов

**Что получено неправильно**: полная потеря bridge integrity; возможность drain любых funds под управлением контракта

**Что проверить**: есть ли timelock controller, multisig защита на SUPER_ADMIN; `0xB4349...` — EOA, подтверждено

**Оценка**: Critical — структурная проблема централизации; реализуемо за 1 транзакцию

---

## H05 — 100% Fee Configuration / Легальная конфискация

**Закон ломается**: E5 (fee ≤ 100% — технически разрешено)

**Странное валидное состояние**:
SUPER_ADMIN вызывает `updatePlatformFee(10000)`. Контракт принимает (10000 ≤ 10000). Теперь platformFee = 100%. Следующий пользователь bridge-ует 1000 ATLA с TRON. Bridge logic берёт fee = 1000 ATLA. Пользователь получает 0. Технически валидная транзакция. Нарушения нет.

**Расходятся**:
- User: ожидает получить ~1000 ATLA (минус небольшая комиссия)
- Contract: применяет 100% fee на основе platformFee
- Treasury: получает 1000 ATLA

**Что получено неправильно**: 100% user funds → treasury; нет возможности оспорить

**Что проверить**: downstream contracts — используют ли они platformFee напрямую без sanity check

**Оценка**: High — если bridge contracts читают platformFee без собственного cap

---

## H06 — Slash Escape via Nominator Unbonding / Окно побега

**Закон ломается**: S6 (slash deferred 7 дней) × S4 (unbonding необратим)

**Странное валидное состояние**:
Эра X: Validator A equivocates. Slash записан в offences pallet (Level 4, 100%). Начинается 7-дневный escrow.
Nominator N видит событие (если мониторит). N вызывает `unbond()`. Unbonding period = 72 часа.
Day 3: unbonding завершён, N вызывает `withdraw_unbonded`. Stake выведен.
Day 7: slash пытается примениться к Nominator N. Но stake уже withdrawn.

**Вопрос**: применяется ли slash к unbonding chunks? В Substrate pallet-staking slashing может применяться к unbonding chunks, но это NEEDS VERIFICATION для текущей конфигурации.

**Если unbonding chunks НЕ защищены от slash**: номинаторы могут убегать от slash при условии, что они мониторят chain и успевают за 7 дней (>72h для unbonding).

**Расходятся**:
- Validator: slash применяется полностью (21d unbonding >> 7d window)
- Nominator: может выйти за 72h, до применения slash

**Что получено неправильно**: нарушение incentive alignment; номинаторы не несут риск за недобросовестных валидаторов

**Что проверить**: `pallet-staking/src/slashing.rs` — применяется ли slash к `unlocking` chunks vs `active` only

**Оценка**: Medium — критично если unbonding chunks не слэшатся

---

## H07 — Nomination Pool Reward Expiry / Коллективная потеря без виновных

**Закон ломается**: S5 (rewards expire 84 eras) × Pool mechanics

**Странное валидное состояние**:
Pool X накапливает era rewards за 83 эры. Ни один участник не клеймил. На 84-й эре rewards истекают → treasury. Каждый участник думал, что "кто-то другой" или "pool автоматически" клеймит. Pool Nominator role не отвечает за claim. Pool Creator уже отдал Master роль другому. Нет responsibility assignment.

**Расходятся**:
- Pool participants: ожидают ~83 эры наград
- Pallet-staking: rewards expired, now in treasury
- Pool accounting: pool's earned points = 0 после expiry

**Что получено неправильно**: collective reward loss; no individual actor is "wrong"

**Что проверить**: кто может вызвать claim_for_pool или аналог; есть ли автоматический claim в pool lifecycle

**Оценка**: Medium — реально при отсутствии active pool management

---

## H08 — Governance Execution Selective / Foundation выбирает что исполнять

**Закон ломается**: S7 (governance execution не enforced on-chain)

**Странное валидное состояние**:
Proposal A: снизить emissions с 250M до 200M ATLA/год → проходит голосованием.
Proposal B: увеличить validator minimum с 75K до 200K ATLA → проходит голосованием.
Foundation исполняет только Proposal A (снижение emissions — выгодно ecosystem, Foundation поддерживала).
Proposal B (высокий порог — выгоден крупным стейкерам в т.ч. Foundation) — задерживается "для технической проверки". Навсегда.

**Расходятся**:
- On-chain governance: оба proposal прошли = должны быть исполнены
- Foundation: один из них реально на-chain, другой "в процессе"
- Participants: думали что voted outcome = enforced outcome

**Что получено неправильно**: governance legitimacy — система votes но не enforces; Foundation de-facto veto

**Что проверить**: есть ли on-chain execution mechanism вообще или всё через Foundation off-chain

**Оценка**: High — structural issue, не требует exploit

---

## H09 — Nomination Pool Master Hijack / Смена власти в пуле

**Закон ломается**: S8 (pool roles separation)

**Странное валидное состояние**:
Step 1: Creator создаёт pool. Step 2: Creator назначает внешний адрес Master (root). Step 3: Creator объявляет "мы передали управление DAO". Step 4: Master-address назначает себя Nominator И Defender. Step 5: Master меняет nominations на валидатор, который затем получает Level 4 slash. Step 6: Все участники теряют 100% stake.

Каждый шаг валиден по pool mechanics. Нет on-chain protection против этого.

**Расходятся**:
- Pool participants: думают что Creator контролирует pool
- Master: имеет полный контроль
- Pallet: все вызовы легитимны

**Что получено неправильно**: 100% stake loss для всех участников; governance rights уже недоступны для pool members

**Что проверить**: может ли Master в одной транзакции изменить nominations И validator немедленно подвергается slash? Timing важен.

**Оценка**: High — реально при capture Master role

---

## H10 — Era Points Cartel / Коллективное снижение порога

**Закон ломается**: S11 (era points deviation — относительная метрика)

**Странное валидное состояние**:
200 из 256 active validators договариваются участвовать минимально — подписывать ровно необходимый минимум блоков/attestations. Average era points падает. Порог "25% ниже среднего" тоже падает. 56 несогласных валидаторов набирают нормальные points — они НЕ выглядят как outliers (они выше среднего, не ниже). Cartel не получает slash. Cartel получает меньше points → меньше rewards. Но: chain throughput снижается при этом.

**Расходятся**:
- pallet-im-online: все valидаторы отправляют heartbeats, нет unresponsiveness
- Network users: меньше TPS, более долгая finality
- Cartel members: intentionally underperform но legit

**Что получено неправильно**: network degradation без slash mechanism triggering

**Что проверить**: конкретный minimum viable era points per validator per session

**Оценка**: Low-Medium — требует координации 78% валидаторов

---

## H11 — Slash After Re-nomination / Призрачный slash

**Закон ломается**: S3 + S2 взаимодействие

**Странное валидное состояние**:
Era X: Nominator N номинирует Validator A.
Era X+0.5: Validator A мisbehaves. Slash записан.
Era X+1: N перепосылает nomination → убирает A из списка. Nomination change scheduled for next era.
Era X+1 (slash application, день 7): slash пытается взять с N долю за то что N номинировал A.

Вопрос: берётся ли slash snapshot on-chain в момент misbehavior (era X) или в момент применения (7 дней спустя)?

Если snapshot в момент misbehavior: N всё равно теряет (был nominator в era X).
Если в момент применения: N уже не номинирует A → возможно нет slash.

**Расходятся**:
- N: думает что снял nomination → вышел из риска
- Slash logic: зависит от snapshot timing

**Что получено неправильно**: либо unfair slash, либо unfair escape

**Что проверить**: `pallet-staking slashing.rs` — snapshot timing для nominator exposure

**Оценка**: Medium — важно для понимания реального risk model

---

## H12 — Pause Registry Mismatch / Паузирование не того контракта

**Закон ломается**: E3 (pause propagates correctly)

**Странное валидное состояние**:
SUPER_ADMIN регистрирует bridge как `registerContract("Bridge", 0xAAA)`.
SUPER_ADMIN вызывает `pauseContract("Bridge")`.
PlatformController хранит паузу для имени "Bridge".
Bridge contract при каждой операции проверяет `isPaused(address(this))` — по своему адресу 0xAAA.

Если `contractPauses` хранит `mapping(address => bool)` и ключ это address 0xAAA, pause работает.
Если `contractPauses` хранит `mapping(string => bool)` и ключ это "Bridge", но bridge contract ищет по своему address — mismatch. Pause не применяется.

**Расходятся**:
- SUPER_ADMIN: думает bridge остановлен
- Bridge: продолжает работать

**Что получено неправильно**: emergency pause не работает; bridge operations continue в paused state

**Что проверить**: тип ключа в `contractPauses` mapping; как bridge contract проверяет pause

**Оценка**: Medium — зависит от реализации; PlatformController source показывает `mapping(address => bool)`, но pauseContract принимает `string` name → lookup через registry

---

## H13 — Storage Collision After Upgrade / Слот-коллизия после апгрейда

**Закон ломается**: E6 (upgrade authorized) × общая безопасность

**Странное валидное состояние**:
PlatformController v1 хранит:
- slot 0: `globalPause` (bool)
- slot 1: `lastProcessedTronBlock` (uint256)

PlatformController v2 добавляет новую переменную ПЕРЕД `globalPause`:
- slot 0: `newFeatureFlag` (bool)
- slot 1: `globalPause` (bool)
- slot 2: `lastProcessedTronBlock`

После upgrade: `globalPause` читается из slot 1, но там лежит `lastProcessedTronBlock` = 83,370,629 (ненулевое) → globalPause = true. Система немедленно паузируется. ИЛИ наоборот — `lastProcessedTronBlock` обнуляется.

**Расходятся**:
- SUPER_ADMIN: думает просто добавил feature
- Contract: storage сдвинулся → неправильные значения

**Что получено неправильно**: system-wide unintended pause или oracle reset; зависит от storage layout

**Что проверить**: следует ли новая реализация OpenZeppelin storage gap patterns; есть ли storage gap `__gap[50]` в текущей реализации

**Оценка**: Medium — стандартная проблема upgradeable contracts если не используются gaps

---

## H14 — EVM/Substrate Balance Desync / Двойное существование ATLA

**Закон ломается**: X1 (ATLA balance unified)

**Странное валидное состояние**:
User переводит 1000 ATLA на EVM-адрес через Frontier precompile. Substrate balance = 0. EVM balance = 1000 ATLA.

Теперь user хочет стейкать. Staking pallet читает Substrate AccountData. Видит 0 → не может стейкать.
Одновременно: EVM balance 1000 ATLA не считается "bonded" для staking.
User фактически имеет ATLA (в EVM), но не может участвовать в consensus security → funds are inert.

Если UI показывает общий баланс (Substrate + EVM), пользователь видит "1000 ATLA" и думает может стейкать → staking transaction fails.

**Расходятся**:
- UI: показывает 1000 ATLA (суммарно)
- Staking pallet: видит 0 Substrate ATLA
- EVM balance: 1000 ATLA есть, но staking недоступен

**Что получено неправильно**: unexpected lock of funds; confusion about available staking capacity

**Что проверить**: Frontier balance precompile — откуда читается EVM balance; есть ли механизм "recall" EVM → Substrate

**Оценка**: Medium — реально, зависит от UX

---

## H15 — Pool Destroy Racing Rewards / Разрушение пула до клейма

**Закон ломается**: S5 + Pool lifecycle

**Странное валидное состояние**:
Master переводит pool в Destroying state. В этот момент pool имеет unclaimed rewards за 70 эр.
Members пытаются claim в Destroying state. Pallet может запрещать новые claims в Destroying.
Members вынуждены force_withdraw. Force_withdraw возвращает principal, но не pending rewards?
Rewards за 70 эр теряются → treasury.

**Расходятся**:
- Pool members: ожидают principal + rewards
- Pallet: Destroying state может не включать reward distribution
- Master: легитимно разрушает пул

**Что получено неправильно**: members lose accumulated rewards during pool destruction

**Что проверить**: Substrate nomination_pools pallet — поведение claims в Destroying state

**Оценка**: Medium

---

## H16 — Relayer Balance Exhaustion / Тихая смерть оракула

**Закон ломается**: E2 (Oracle = единственный updater) + отсутствие автоматического пополнения

**Странное валидное состояние**:
Oracle EOA `0x3Aa473E3818...` имеет ~111 ATLA. Расход: ~0.018 ATLA/update × ~14400 updates/day = ~252 ATLA/day. Баланс кончается через ~0.44 дня!

СТОП: пересчёт. Fee per update ≈ 0.0000176 ATLA (из данных: ~17.608×10⁻⁶ ETH = 0.0000176 ATLA).
0.0000176 ATLA × 14400 updates/day = ~0.253 ATLA/day.
111 ATLA / 0.253 = ~439 дней ≈ 1.2 года.

Когда баланс = 0: `updateLastProcessedTronBlock` reverts (insufficient gas). lastProcessedTronBlock freezes. Bridge halts. No on-chain alerting. No automatic refund mechanism. Recovery requires: SUPER_ADMIN grants new ORACLE address, new address funded, starts updating.

**Расходятся**:
- PlatformController: lastProcessedTronBlock stale (frozen)
- TRON: продолжает производить блоки
- Bridge users: deposits from TRON stuck unprocessed
- UI: может не показывать что oracle stale

**Что получено неправильно**: bridge halt without alarming; user funds locked in transit

**Оценка**: Medium — это не exploit, но structural reliability issue

---

## H17 — Governance Circular Majority / Самоподдерживающееся большинство

**Закон ломается**: S7 + X2 (governance scope)

**Странное валидное состояние**:
Foundation держит: 140M treasury ATLA + часть 450M team/advisor vesting = потенциально доминирующий voting power при низкой явке.
Total staked для governance: допустим 500M ATLA из 3B total. Foundation контролирует 200M (40%).
Foundation голосует ЗА proposal увеличить validator minimum до 500K ATLA. Малые validators выбиты → validator set shrinks → Foundation-aligned validators доминируют → Foundation получает больше block rewards → больше ATLA → ещё больше voting power.

Каждый шаг: легальный governance vote + Foundation execution.

**Расходятся**:
- Governance: выглядит как community decision
- Power distribution: постепенная концентрация
- Protocol: не нарушает ни один on-chain закон

**Что получено неправильно**: decentralization progressively decreases through legitimate governance

**Оценка**: High (structural) — не требует exploit, только sustained strategy

---

## H18 — Slash Challenge Undefined Who / Кто может защититься?

**Закон ломается**: S6 (slash challenge = UNKNOWN механизм)

**Странное валидное состояние**:
Validator V получает ложный slash (например, из-за equivocation report на основе устаревших данных). 7-дневный challenge window открыт. Но: validator offline (сервер упал, ключ утерян). Нет возможности подать challenge. Day 7: slash применяется. Validator теряет часть/весь stake. Nominators пропорционально теряют.

Если challenge может подать ТОЛЬКО slashed stash: offline validator = no defense.
Если challenge публичный: любой может defence, но нет incentive для чужой защиты.

**Расходятся**:
- Protocol: 7-day window = fair opportunity
- Reality: validator offline = no challenge = unchallenged slash

**Что получено неправильно**: неправильный slash без возможности оспаривания

**Что проверить**: pallet-staking challenge mechanism — кто caller, нужна ли подпись slashed validator

**Оценка**: Medium

---

## H19 — Block Time Change → Emission Spike / Governance + emission

**Закон ломается**: X2 (governance scope) + S1

**Странное валидное состояние**:
Governance proposal: снизить block time с 6 секунд до 3 секунд. Foundation исполняет. Теперь в 36-часовой эре вдвое больше блоков. Reward per block = ~24.112 ATLA (фиксировано). Era reward = blocks_in_era × 24.112. Вдвое больше блоков → вдвое больше emissions per era → 500M ATLA/год вместо 250M.

Каждый шаг валиден: governance approved, Foundation executed, emissions per block unchanged.

**Расходятся**:
- Design intent: 250M ATLA/year
- Actual: 500M ATLA/year
- Token holders: unexpected inflation

**Что получено неправильно**: 2× инфляция через "innocent" block time change

**Что проверить**: привязаны ли emissions к времени (absolute) или к блокам (relative) в pallet-staking

**Оценка**: High — если emissions per block, не per time unit

---

## H20 — Double Oracle Role / Conflicting TRON State

**Закон ломается**: E2 (один ORACLE)

**Странное валидное состояние**:
SUPER_ADMIN выдаёт ORACLE роль двум EOA: Oracle A и Oracle B. TRON форкается (временный split). Oracle A видит fork-A и обновляет block 100 с hash А. Oracle B видит fork-B и пытается обновить block 100 — reverts (BlockNotNewer, 100 ≤ 100). Но Oracle B думает что block 101 существует и обновляет до 101 (из fork-B). Теперь: bridge "знает" block 100 (из fork-A) + 101 (из fork-B) — но эти блоки из разных fork-histories.

**Расходятся**:
- Oracle A: видит TRON fork-A
- Oracle B: видит TRON fork-B
- PlatformController: смешанная history

**Что получено неправильно**: корруптированный TRON block sequence на Atleta side

**Оценка**: Low-Medium — требует TRON fork + dual oracle

---

## H21 — Partial Slash Dust Below Existential Deposit

**Закон ломается**: S2 (slash пропорционален)

**Странное валидное состояние**:
Nominator с minimum stake 10 ATLA номинирует validator.
Level 1 slash = 0.1% = 0.01 ATLA.
Если existential deposit > 0.01 ATLA: slash operation создаёт "dust" ниже existential deposit → account reaped? Или slash не применяется? Или slash округляется вниз → 0 ATLA slash?

Если slash = 0 для dust amounts: nominator с minimum stake не несёт риска Level 1 slash. Incentive: держать minimum stake для участия без meaningful slash exposure.

**Расходятся**:
- Protocol design: все nominators несут proportional risk
- Math: minimum stake holders de facto exempt from Level 1 slash

**Что проверить**: existential deposit value; rounding в slash math

**Оценка**: Low — minor incentive distortion

---

## H22 — Vesting LockPeriod Retroactive Change / Разблокировка раньше срока

**Закон ломается**: E7 (lockPeriod minimum 30 дней)

**Странное валидное состояние**:
User заводит vested position: lockPeriod = 180 дней. SUPER_ADMIN обновляет lockPeriod = 30 дней.
Если vesting contracts читают `lockPeriod` из PlatformController динамически (не сохраняют snapshot при создании): user's 180-day lock внезапно становится 30-day lock. Ранняя разблокировка.

Альтернатива: если вест читает snapshot при создании — кто-то создаёт новые vesting positions с lockPeriod=30 сразу после обновления, ещё до возврата к 180.

**Расходятся**:
- Design: vesting obligations are fixed
- Runtime: lockPeriod is mutable by SUPER_ADMIN

**Что получено неправильно**: early unlock of tokens; violation of vesting schedule

**Что проверить**: как downstream vesting contracts читают lockPeriod — dynamic call vs stored snapshot

**Оценка**: Medium — зависит от vesting contract implementation

---

## H23 — Parachain Collateral Post-Expiry Deadlock

**Закон ломается**: X2 + S7

**Странное валидное состояние**:
Parachain slot истекает через 3 года. Collateral (100K+ ATLA) должна вернуться. Механизм возврата требует governance vote + Foundation execution. Если Foundation не создаёт proposal или не исполняет в разумный срок: collateral остаётся locked. No automatic release.

Parachain operator потерял ключи. Нет кому голосовать за возврат. Collateral dead.

**Расходятся**:
- Operator: ожидает automatic collateral return after 3 years
- Protocol: requires active governance action
- UNKNOWN: есть ли автоматический expiry handler

**Что проверить**: parachain slot expiry logic в relay/IO layer pallet

**Оценка**: Low — parachain не активен на mainnet

---

## H24 — Exit Fee Timing With Pending Slash / Валидатор "выходит" до slash

**Закон ломается**: S4 + S6

**Странное валидное состояние**:
Validator получает slash (Level 3, 10%, pending 7 дней). В тот же день: validator вызывает `chill()` → начинает 21-дневный unbonding. Pays 1 ATLA exit fee.

Если slash применяется к unbonding chunks → validator теряет 10% независимо от chill. 
Если slash применяется только к active bond: момент chill = перевод из active → unbonding. Slash может не найти active bond, только unbonding chunk.

Bonding duration 21d >> slash window 7d: slash применяется пока stake ещё в unbonding. Вопрос точно как pallet обрабатывает slash на unbonding chunks.

**Расходятся**:
- Validator: думает chill защищает от следующего периода
- pallet-staking: slash может всё равно применяться к unbonding

**Оценка**: Medium — интересная timing race, зависит от Substrate implementation

---

## H25 — TRON Block as Proxy Timestamp / Временно́й дрейф

**Закон ломается**: E1 (монотонность как временной proxy)

**Странное валидное состояние**:
Bridge downstream contracts используют `lastProcessedTronBlock` как временну́ю метку (TRON: ~1 block/3 sec). Downstream logic: "если TRON block > X, разрешить claim."

ORACLE опережает реальный TRON на 1000 блоков (network latency, fast oracle). Bridge думает прошло ~50 минут больше реального времени. Claim window открывается раньше → user может claim premature.

**Расходятся**:
- Real TRON time: N
- PlatformController lastProcessedTronBlock: N+1000 (~50 min ahead)
- Claim timing: unlocked 50 min early

**Оценка**: Low — зависит от наличия downstream contracts с time-gated logic

---

## H26 — Nomination Change Race with Slash in Same Era / Момент snapshot

**Закон ломается**: S3 + S2

**Странное валидное состояние**:
Block 1000 of Era X: Nominator N вызывает `nominate([ValidatorB])` (снимает ValidatorA).
Block 1001 of Era X: ValidatorA equivocates. Slash recorded.

Если exposures snapshot происходит в начале эры: N ещё числится как nominator A в начале эры → N несёт slash.
Если snapshot в момент misbehavior: N уже снял nomination (block 1000 < 1001) → N не несёт slash.
Если "effective next era" означает что N всё ещё nominator A в era X → N несёт slash независимо от nomination change.

**Расходятся**:
- N: думает снял nomination = нет риска
- pallet: N ещё official nominator A для era X election

**Что проверить**: когда nomination change effective; когда exposure snapshot taken

**Оценка**: High — фундаментально для risk model nominators

---

## H27 — PlatformController Registry Poisoning / Отравление реестра адресов

**Закон ломается**: E4 (registry as authority source)

**Странное валидное состояние**:
SUPER_ADMIN вызывает `registerContract("StakingRewards", attackerContract)`.
Downstream UI или contracts вызывают `getContract("StakingRewards")` → получают attackerContract.
Users approve tokens для "StakingRewards" (attackerContract) → funds drained.

Или: `registerContract("Treasury", attackerAddr)` → все fee payments идут к attacker.

Реестр полностью контролируется SUPER_ADMIN. Один вызов меняет routing всех dependent components.

**Расходятся**:
- Users: думают "StakingRewards" = official contract
- Registry: теперь указывает на attacker
- Funds: flow to attacker

**Оценка**: Critical — если dependent contracts или UI используют registry без verification

---

## H28 — Pool Triple Disempowerment / Тройное лишение прав

**Закон ломается**: S8 + S2 + S7

**Странное валидное состояние**:
Pool participant P:
1. Теряет governance rights (ATLA в pool = no voting power) — Закон S8
2. Pool Nominator выбирает плохого валидатора → 100% slash — Закон S2
3. P не может голосовать за governance emergency stop — Закон S7 (no on-chain enforcement)
4. P теряет 100% stake И не имел права голоса ни на каком этапе

Каждый шаг: rules работают как designed. Комбинация = worst case для pool participant.

**Расходятся**:
- P: думает участие в pool = участие в network с protections
- Reality: pool member = no governance + full slash risk + no emergency stop

**Оценка**: High — structural vulnerability of pool design

---

## H29 — GRANDPA Stall During BABE Production / Финальность зависает

**Закон ломается**: S10 (validator role fixed per session)

**Странное валидное состояние**:
BABE продолжает производить блоки. GRANDPA требует 2/3 supermajority для finality. Если >1/3 validators offline или не участвуют в GRANDPA: finality stalls. Блоки накапливаются unfinalised (BABE chain grows).

Bridge downstream требует finalized blocks для processing. Finality stuck → bridge stuck.
Meanwhile: users's EVM transactions included in BABE blocks → показывают success в UI.
After GRANDPA resumes and reorgs: included transactions могут быть reversed.

**Расходятся**:
- BABE/EVM: transaction "success"
- GRANDPA/bridge: not finalized → potentially reversed
- UI/Indexer: shows success prematurely

**Оценка**: Medium — известный substrate behavior, вопрос в том насколько это учтено

---

## H30 — Emission per Block vs per Time / Инфляция при изменении block time

**Закон ломается**: S1 + X2 (governance changes block time)

*Дублирует H19 с другим фокусом.*

**Странное валидное состояние**:
Governance снижает block time. Era = fixed number of blocks (не fixed time). 
Реальный вопрос: как `pallet-staking` определяет era length?

Если era_length_blocks = constant (e.g., 21600 blocks):
- При 6s blocktime: era = 21600×6 = 36 часов ✓
- При 3s blocktime: era = 21600×3 = 18 часов → эры укорачиваются
- Rewards per era: constant emissions × blocks = same per era
- But eras/year doubles → 2× annual emissions

Если era_length_time = constant: block count в эре растёт → reward per block falls → no inflation change.

**Что проверить**: определение длины эры в runtime config; `EraLength` parameter type

**Оценка**: High — если era defined in blocks, block time change = inflation change

---

## H31 — EIP-1559 Base Fee Transition Mid-Epoch / Разрыв при смене fee модели

**Закон ломается**: S1 (reward per block) × X2 (governance change)

**Странное валидное состояние**:
Governance approves EIP-1559 transition. Foundation executes mid-era. Before: base fees → validators. After: base fees → burn. Validators in current era earned X from base fees but got credited 0 (already burned). Era rewards calculated on old model but distributed on new model → accounting gap.

**Расходятся**:
- Validators: ожидают base fees за весь era
- New model: base fees burned beginning from activation block
- Accounting: partial era under old rules + partial under new rules

**Оценка**: Low — transition edge case

---

## H32 — Foundation Treasury Allocation vs Governance Vote Deadlock / Круговая зависимость

**Закон ломается**: S7 + S8

**Странное валидное состояние**:
Proposal: вывести 50M ATLA из treasury в community fund. Проходит голосованием.
Foundation должна исполнить. Но Foundation "контролирует" treasury wallet (`0x98de9e...`). Foundation задерживает execution. Оппозиция хочет новый proposal форсировать execution. Но для нового proposal нужен quorum. Большинство ATLA в pools → нет governance rights. Foundation-aligned validators не голосуют. Quorum не достигается.

Lock: governance approved → Foundation not executing → no force mechanism → new vote can't pass quorum.

**Расходятся**:
- On-chain vote: passed
- Execution: blocked by same party that controls execution
- Community: no recourse

**Оценка**: High — structural governance deadlock possible

---

## СВОДНАЯ ТАБЛИЦА ГИПОТЕЗ

| ID | Название | Закон | Оценка | Приоритет для Фазы 7 |
|----|----------|-------|--------|----------------------|
| H01 | TRON Reorg Blindness | E1 | Medium | YES |
| H02 | Oracle Advance Attack | E1+E2 | High | YES |
| H03 | executeBatch Escalation | E4 | High | YES |
| H04 | Instant Upgrade | E6 | Critical | YES |
| H05 | 100% Fee Configuration | E5 | High | YES |
| H06 | Slash Escape Unbonding | S6+S4 | Medium | YES |
| H07 | Pool Reward Expiry | S5+Pool | Medium | YES |
| H08 | Governance Selective Execution | S7 | High | YES |
| H09 | Pool Master Hijack | S8 | High | YES |
| H10 | Era Points Cartel | S11 | Low-Med | NO |
| H11 | Slash After Re-nomination | S3+S2 | Medium | YES |
| H12 | Pause Registry Mismatch | E3 | Medium | YES |
| H13 | Storage Collision After Upgrade | E6 | Medium | YES |
| H14 | EVM/Substrate Balance Desync | X1 | Medium | YES |
| H15 | Pool Destroy Racing Rewards | S5+Pool | Medium | NO |
| H16 | Relayer Balance Exhaustion | E2 | Medium | YES |
| H17 | Governance Circular Majority | S7+X2 | High | YES |
| H18 | Slash Challenge Undefined | S6 | Medium | YES |
| H19 | Block Time → Emission Spike | X2+S1 | High | YES |
| H20 | Dual Oracle Conflict | E2 | Low-Med | NO |
| H21 | Dust Slash Below ExDep | S2 | Low | NO |
| H22 | Vesting LockPeriod Retroactive | E7 | Medium | YES |
| H23 | Parachain Collateral Deadlock | X2+S7 | Low | NO |
| H24 | Exit Fee + Pending Slash | S4+S6 | Medium | YES |
| H25 | TRON Block as Timestamp Proxy | E1 | Low | NO |
| H26 | Nomination Race with Slash | S3+S2 | High | YES |
| H27 | Registry Poisoning | E4 | Critical | YES |
| H28 | Pool Triple Disempowerment | S8+S2+S7 | High | YES |
| H29 | GRANDPA Stall vs BABE | S10 | Medium | YES |
| H30 | Block Time → Inflation | S1+X2 | High | YES |
| H31 | EIP-1559 Transition Gap | S1+X2 | Low | NO |
| H32 | Treasury Governance Deadlock | S7+S8 | High | YES |

**Итого: 32 гипотезы. Приоритет Фазы 7: 22 гипотезы.**

---

*Фаза 3 завершена. Ожидаю отмашку на Фазу 4.*
