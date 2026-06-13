# ФАЗА 5 — Злоупотребление нормальными функциями
## Atleta Network — Mainnet Only

Каждая функция — нормальное назначение, параметры вызова, что создаётся даже при failure, и как можно совместить с другой функцией для создания состояния, которого ни одна функция отдельно не предполагала.

---

## F01 — `updateLastProcessedTronBlock(uint256 tronBlock)`

**Нормальное назначение**: Синхронизация Atleta с состоянием TRON blockchain. Оракул сообщает "мы обработали TRON до блока N."

**Кто может вызвать**: только ORACLE role

**Когда может вызвать**: в любой момент, пока новый > текущего

**Что должно уже быть true**: tronBlock > lastProcessedTronBlock

**Что создаёт даже при failure**:
- При `BlockNotNewer`: ничего. Tx fails, nonce consumed, gas spent

**Что меняет on-chain**: `lastProcessedTronBlock` в storage

**Что меняет off-chain**: downstream bridge indexer обновляет watermark

**Какие события emits**: `OracleBlockUpdated(uint256 indexed tronBlock)`

**Кто реагирует**: предположительно bridge contracts + indexer (UNKNOWN точная реализация)

---

**Опасные комбинации:**

**F01-A: updateLastProcessedTronBlock + FULL pause одновременно**
- Пауза останавливает user-facing операции
- НО: updateLastProcessedTronBlock НЕ проверяет pause (это oracle function, не user function)
- Пока bridge паузирован: tronBlock продолжает расти
- Если bridge имеет claim window (например: "claim в течение X блоков от TRON depoist block") — окно истекает во время паузы
- После unpause: claims expired, deposits stuck
- Ни pause, ни oracle update не предполагали этот сценарий по отдельности

**F01-B: updateLastProcessedTronBlock + registerContract("Bridge", newAddr)**
- Оракул обновляет tronBlock → event emitted
- Старый bridge contract слушает события
- Registry перезаписывает "Bridge" → new address
- Новый bridge начинает с lastProcessedTronBlock = текущий (уже advanced)
- Все TRON депозиты ДО переключения: привязаны к старому bridge → lost if old bridge decommissioned
- Ни registerContract, ни oracle update не предполагали orphaned deposits

**F01-C: updateLastProcessedTronBlock + `chill()` валидатора-оракула (если oracle = validator)**
- Если ORACLE key = validator session key (unlikely but possible)
- Validator chills → если session key shared → oracle operations affected?
- NEEDS VERIFICATION: полная независимость ORACLE role от staking state

---

## F02 — `executeBatch(address[] targets, bytes[] data, bool revertOnFail)`

**Нормальное назначение**: Атомарное (или квази-атомарное) выполнение множества admin операций.

**Кто может вызвать**: только SUPER_ADMIN

**Когда может вызвать**: в любой момент (не проверяет pause состояние — NEEDS VERIFICATION)

**Что должно быть true**: lengths(targets) == lengths(data), non-empty

**Что создаёт даже при failure (revertOnFail=false)**:
- Частичное применение изменений. Некоторые targets изменены, некоторые нет.
- Успешная транзакция в receipt. Failure внутри batch невидим без разбора return values.

**Что меняет on-chain**: любые storage в любых target contracts (если они принимают PlatformController как caller)

**Что меняет off-chain**: indexer видит одну успешную tx, не internal call failures

**Какие события emits**: события target contracts (если они emit); нет отдельного BatchExecuted event в PlatformController

**Кто реагирует**: target contracts (их own event listeners)

---

**Опасные комбинации:**

**F02-A: executeBatch + updateTreasuryWallet**
- Batch call 1: `registerContract("Bridge", bridgeAddr)` — легитимно
- Batch call 2: `updateTreasuryWallet(attackerAddr)` — в том же batch
- revertOnFail=true → если call 1 fails, call 2 тоже не выполнится
- revertOnFail=false → call 1 может fail, call 2 выполнится → treasury changed even if other ops failed
- Мониторинг: видит "executeBatch success", не разбирает что внутри

**F02-B: executeBatch + pauseContract (bridge самого себя)**
- executeBatch вызывает pauseContract("Bridge")
- Потом — в том же batch — withdraws funds from bridge (если bridge доверяет PlatformController)
- Bridge паузирован для пользователей, но batch уже выполняется
- Два шага: пауза → drain → всё в одной транзакции

**F02-C: executeBatch(revertOnFail=false) + идемпотентные vs non-идемпотентные calls**
- Batch: [grantRole(ORACLE, addr1), updateFee(500), grantRole(ORACLE, addr2), setSomethingInvalid]
- setSomethingInvalid fails, revertOnFail=false → три предыдущих applied
- SUPER_ADMIN ожидал: либо всё, либо ничего
- Reality: три изменения применены, одно нет
- Inconsistent role state

**F02-D: executeBatch как arbitrary call to non-registered contracts**
- registerContract не требуется перед executeBatch
- SUPER_ADMIN может вызвать любой contract через executeBatch (targets = любой адрес)
- Если contract принимает msg.sender == platformController как privileged → escalation
- Не только registered contracts — ЛЮБОЙ contract в экосистеме

---

## F03 — `pauseAll() / pauseFull() / unpauseAll()`

**Нормальное назначение**: Emergency stop всех платформенных операций.

**Кто может вызвать**: только SUPER_ADMIN

**Когда может вызвать**: в любой момент

**Что должно быть true**: ничего специфического

**Что создаёт даже при failure**: ничего (revert = no state change)

**Что меняет on-chain**: `currentPauseLevel` / `globalPause`

**Что меняет off-chain**: UI должен читать и отображать pause state (UNKNOWN задержка)

**Какие события emits**: UNKNOWN — нет информации о pause events в текущей ABI

**Кто реагирует**: bridge contracts (если проверяют pause), UI

---

**Опасные комбинации:**

**F03-A: pauseAll + upgradeTo**
- Pause: пользователи думают "система защищена, средства в безопасности"
- Во время паузы: SUPER_ADMIN делает upgradeTo(maliciousImpl)
- Пауза как cover для незаметного upgrade
- После unpause: новый код работает, пользователи не знают
- Паузы часто мониторятся. Upgrade во время паузы может казаться "maintenance"

**F03-B: pauseContract("Bridge") + updateLastProcessedTronBlock во время паузы**
- Bridge паузирован: юзеры не могут claim
- Oracle продолжает: tronBlock растёт
- Claim window (if exists): expires during pause
- Unpause: claim window passed → deposits stuck
- Нет ни одного нарушения правил. Пауза "защитила" пользователей но лишила их права claim.

**F03-C: unpause без check кто паузировал**
- Если SUPER_ADMIN A паузирует, SUPER_ADMIN B (если их несколько) анпаузирует
- Нет multi-sig requirement на unpause
- Emergency pause может быть снята другим SUPER_ADMIN немедленно
- NEEDS VERIFICATION: сколько SUPER_ADMIN адресов сейчас?

**F03-D: FULL EVM pause ≠ Substrate staking pause**
- pauseFull(): EVM layer остановлен
- Substrate pallets: работают независимо (разные runtime modules)
- Staking rewards: продолжают начисляться
- Validators: продолжают производить блоки
- Users: думают "всё паузировано" → продолжают bond/nominate транзакции в Substrate
- Semantic gap между двумя слоями системы

---

## F04 — `updateTreasuryWallet(address newTreasury)`

**Нормальное назначение**: Обновить адрес для получения platform fees.

**Кто может вызвать**: только SUPER_ADMIN

**Когда может вызвать**: в любой момент (нет timelock)

**Что должно быть true**: newTreasury != address(0)

**Что создаёт даже при failure**: ничего

**Что меняет on-chain**: `treasuryWallet` storage variable

**Что меняет off-chain**: все future fee flows меняют destination

**Какие события emits**: UNKNOWN (нет информации о TreasuryUpdated event)

**Кто реагирует**: downstream contracts читающие `treasuryWallet`

---

**Опасные комбинации:**

**F04-A: updateTreasuryWallet + updatePlatformFee в одном block**
- Block N: updateTreasuryWallet(attackerAddr)
- Block N: updatePlatformFee(10000) — 100%
- Pending bridge operations (deposited before block N): settle after block N
- Settlement: 100% fee → attackerAddr
- Users: все ATLA locked в bridge → redirect to attacker
- Два отдельных valid admin operations → combined catastrophe

**F04-B: updateTreasuryWallet + pause → drain cover**
- Pause (emergency cover)
- updateTreasuryWallet(attacker)
- Unpause
- All fee income flowing to attacker until someone notices
- No time-lock, no governance approval, no notification

**F04-C: updateTreasuryWallet + slashing treasury**
- Substrate slash → treasury (Substrate treasury address)
- EVM bridge fee → treasuryWallet (PlatformController variable)
- Two separate treasury addresses
- If attacker controls EVM treasury but not Substrate treasury: split drain

---

## F05 — `registerContract(string name, address addr)`

**Нормальное назначение**: Поддерживать актуальный registry адресов platform contracts.

**Кто может вызвать**: только SUPER_ADMIN

**Когда может вызвать**: в любой момент

**Что должно быть true**: name непустое, addr != address(0)

**Что создаёт даже при failure**: ничего

**Что меняет on-chain**: `contracts[name]` storage

**Что меняет off-chain**: все consumers читающие registry → redirect

**Какие события emits**: UNKNOWN (нет ContractRegistered event info)

**Кто реагирует**: все contracts и UI, динамически читающие getContract(name)

---

**Опасные комбинации:**

**F05-A: registerContract + pauseContract (разные address)**
- registerContract("Bridge", newBridgeAddr) — обновление на новый деплой
- Ранее: pauseContract("Bridge") сохранил pause для oldBridgeAddr
- contractPauses[oldBridgeAddr] = true
- contractPauses[newBridgeAddr] = false (не паузировался)
- getContract("Bridge") → newBridgeAddr → not paused
- Emergency pause применялась к старому адресу, новый работает без pause
- Unpause забытый: oldBridgeAddr remains "paused" forever (irrelevant, unused)

**F05-B: registerContract("Bridge", EOA)**
- Зарегистрировать EOA как "Bridge"
- Downstream contract вызывает getContract("Bridge") → EOA addr
- Call к EOA: не revert (fallback?), просто ничего не происходит
- Bridge operation: silently fails (success TX, no effect)
- Deposits locked with no recourse

**F05-C: registerContract twice, rapidly**
- registerContract("Bridge", addr1) — block N
- registerContract("Bridge", addr2) — block N+1
- Any operation reading registry between N and N+1: uses addr1
- Any operation after N+1: uses addr2
- Split state for concurrent operations

---

## F06 — `upgradeTo(address newImplementation)` (UUPS)

**Нормальное назначение**: Обновление implementation контракта для bug fixes и новых features.

**Кто может вызвать**: только SUPER_ADMIN (через `_authorizeUpgrade`)

**Когда может вызвать**: в любой момент

**Что должно быть true**: newImplementation — валидный UUPS contract (proxiableUUID check)

**Что создаёт даже при failure**: ничего (revert)

**Что меняет on-chain**: EIP-1967 implementation slot (bytes32)

**Что меняет off-chain**: ABI может измениться; indexer events могут desync

**Какие события emits**: `Upgraded(address indexed implementation)` (OpenZeppelin стандарт)

**Кто реагирует**: monitoring services, Blockscout (меняет ABI для decoding)

---

**Опасные комбинации:**

**F06-A: upgrade + storage layout shift**
- V1: [globalPause(bool), contractPauses(mapping), contracts(mapping), platformFee(uint), lockPeriod(uint), treasuryWallet(address), lastProcessedTronBlock(uint), currentPauseLevel(enum)]
- V2 (bad): добавлена переменная ПЕРЕД lastProcessedTronBlock без storage gap
- После upgrade: lastProcessedTronBlock читается из сдвинутого slot
- Оракул обновляет не тот slot → lastProcessedTronBlock never advances → bridge stuck
- ИЛИ: slot, где раньше был lockPeriod (uint) → теперь читается как lastProcessedTronBlock → bridge прыгает на strange value

**F06-B: upgrade во время active bridge operations**
- User A deposited TRON-side funds, ожидает settlement (T=0)
- SUPER_ADMIN upgrades implementation (T=1)
- Settlement logic изменилась (новая formula, новые checks)
- User A's pending deposit: settled по новым правилам, не тем что действовали при deposit
- Retroactive rule change on in-flight operations

**F06-C: upgrade + event signature change**
- V1 emits: `OracleBlockUpdated(uint256 indexed tronBlock)`
- V2 emits: `OracleBlockUpdated(uint256 tronBlock, address indexed oracle)` (different signature, different topic0)
- Indexer listening for V1 event signature: misses all V2 events
- Bridge indexer: thinks oracle stopped updating → alerts fire → panic
- V2: actually working fine, indexer just deaf to new events

**F06-D: upgrade + pause + upgrade (ping-pong)**
- V1: deployed and operational
- SUPER_ADMIN upgrades to V2 (fix)
- Bug discovered in V2: SUPER_ADMIN pauses
- SUPER_ADMIN upgrades back to V1 (rollback)
- But V1 storage has been written by V2 during its operation period
- V1 reads its slots: values set by V2 → corruption if V2 modified shared slots differently

---

## F07 — Substrate: `unbond(value)` + `withdraw_unbonded(num_slashing_spans)`

**Нормальное назначение**: Начать вывод stake и завершить его после периода ожидания.

**Кто может вызвать**: stash или controller account (NEEDS VERIFICATION)

**Когда**: unbond → в любой момент; withdraw_unbonded → после era_of_unlock

**Что должно быть true**: active bonded ≥ value; unbonding chunks не превышают MaxUnlockingChunks

**Что создаёт даже при failure**:
- unbond при insufficient funds: revert
- withdraw_unbonded если слишком рано: chunks остаются locked, 0 withdrawn

**Что меняет on-chain**: ledger.active уменьшается; ledger.unlocking добавляется chunk

**Что меняет off-chain**: indexer показывает "unlocking" status

**Какие события emits**: `Unbonded(account, value)`, `Withdrawn(account, value)`

**Кто реагирует**: UI, taxing software, validators monitoring

---

**Опасные комбинации:**

**F07-A: unbond timing vs slash window (детально)**
- T=0: ValidatorA equivocates. Slash recorded (Level 4, 100% pending).
- T=0+1h: Nominator sees onchain event. Calls `unbond(full_stake)`.
- T=0+72h: Nominator calls `withdraw_unbonded`. Получает ATLA назад.
- T=0+7d: Slash tries to apply. Stake = 0 (withdrawn).

КРИТИЧНО: В Substrate `pallet-staking`, slash применяется к `StakingLedger::active` amount.
Если `active` = 0 после withdraw_unbonded → slash = 0 ATLA actually taken.
Slash still recorded as "applied" but amount = 0 (or minimum dust).

**F07-B: unbond + bond_extra в том же блоке (rebonding loop)**
- bond_extra: добавить к активному bond
- unbond: создать unbonding chunk
- Если unbond chunk era_of_unlock прошёл И rebonded: withdraw_unbonded может не работать корректно (num_slashing_spans параметр)
- MaxUnlockingChunks: если достигнут лимит → unbond reverts
- Attack: кто-то может flood чужой account unbonding chunks? Нет — только stash/controller может unbond своё

**F07-C: unbond + set_payee изменение**
- Nominator unbonds (ATLA в unlocking state)
- Меняет payee destination (set_payee)
- withdraw_unbonded: ATLA идёт куда? К stash (независимо от payee) или к payee?
- Rewards: идут к payee. Withdrawn unbonded: идёт к stash (free balance). Разные destinations.

---

## F08 — Substrate: `payout_stakers(validator_stash, era)`

**Нормальное назначение**: Клеймить staking rewards для конкретного валидатора и всех его номинаторов за конкретную эру.

**Кто может вызвать**: ЛЮБОЙ account (public call)

**Когда**: era <= current - 1 AND era >= current - HistoryDepth (84 эры)

**Что должно быть true**: validator должен иметь era points; era не должна быть уже claimed

**Что создаёт даже при failure**: ничего (revert если уже claimed или era expired)

**Что меняет on-chain**: balances всех nominators + validator (по payee setting); era marked as claimed

**Что меняет off-chain**: indexer видит reward events

**Какие события emits**: `Reward(stash, amount)` для каждого получателя

**Кто реагирует**: UI, tax tools, restaking automation

---

**Опасные комбинации:**

**F08-A: payout_stakers (public) + set_payee(Account(attackerAddr))**
- Legitimate: nominator sets payee = Account(attackerAddr) by mistake (UI confusion)
- Anyone calls payout_stakers(validatorStash, era)
- Rewards forced to attackerAddr
- Nominator обнаружит только после потери rewards
- Public call = no authorization required; payee misconfiguration = reward loss

**F08-B: payout_stakers + era expiry race**
- Era 84 from validator's last unclaimed era approaching
- Nominator неактивен
- Era expires: payout_stakers reverts
- Anyone could have claimed (public call!) but didn't
- Rewards → treasury
- Design assumes SOMEONE will claim: no guarantee who or when

**F08-C: payout_stakers для slashed validator**
- ValidatorA slashed in era X
- Era X still claimable if within 84 eras
- payout_stakers(validatorA, era_X): 
  - Slash applied to stake → reduced stake basis for era X calculation?
  - Or era X rewards calculated pre-slash?
- NEEDS VERIFICATION: slash reduces era X rewards or only future stake?

**F08-D: pool payout vs individual payout collision**
- Pool members can't call payout_stakers directly for pooled stake
- Pool has separate bond → separate era accounting
- If BOTH: individual nominator AND pool nominator, same underlying validator → payout_stakers called by non-pool actor for pool's validator still works?
- Pool rewards separate mechanism, but pool's stake IS counted in era points

---

## F09 — Substrate: `nominate([targets])` + nomination pool `pool_nominate([targets])`

**Нормальное назначение**: 
- `nominate`: solo nominator выбирает validators
- `pool_nominate`: Pool's Nominator role выбирает validators для всего пула

**Кто может вызвать**:
- `nominate`: любой bonded account
- `pool_nominate`: Pool Nominator role address

**Что создаёт даже при failure**: ничего (revert если not bonded)

**Что меняет on-chain**: nominations list; effective next era

**Какие события emits**: UNKNOWN (may emit Nominato or similar)

---

**Опасные комбинации:**

**F09-A: pool_nominate → high-commission validator → slash**
- Pool Nominator (может быть отдельный от Creator аккаунт) выбирает validator с commission=100%
- Pool members: stake active, nominally earning, но 100% commission → 0 rewards to pool
- Pool members не могут change nominator role → stuck
- Slash: если этот validator equivocates → 100% slash pool stake

**F09-B: nominate + validator chill race**
- Nominator выбирает ValidatorA
- ValidatorA calls chill() перед следующей era election
- Election: ValidatorA not in candidate set → nominator's vote wasted
- Nominator earns 0 (не allocated to any active validator)
- Nominator's 10 ATLA: bonded, not earning, not slashable (no active validator)
- NEEDS VERIFICATION: nominator allocated elsewhere automatically?

**F09-C: pool_nominate change during pending slash**
- ValidatorA pending slash (7-day window)
- Pool Nominator changes nominations to ValidatorB (next era)
- Slash applies to pool stake (still attributed to ValidatorA for era X)
- Pool: stake reduced from ValidatorA slash; now nominates ValidatorB
- All members suffer slash from validator they're no longer nominatinga

---

## F10 — Substrate: `set_payee(RewardDestination)`

**Нормальное назначение**: Настроить куда идут staking rewards: Staked (restake), Stash (free balance), Controller, или Account(addr).

**Кто может вызвать**: stash или controller

**Когда**: в любой момент

**Что должно быть true**: account bonded

**Что создаёт даже при failure**: ничего

**Что меняет on-chain**: payee preference

**Какие события emits**: UNKNOWN

---

**Опасные комбинации:**

**F10-A: set_payee(Account(addr)) + account becomes malicious**
- Validator настраивает rewards → controller account
- Controller key compromised
- Attacker не может unstake (stash key required for unbond NEEDS VERIFICATION)
- Но: все будущие rewards идут к attacker через compromised controller/payee setting
- Validator теряет ongoing rewards but not principal

**F10-B: set_payee(Staked) + nominator pool participant**
- Pool participant не может set_payee (pool manages stake)
- If somehow possible: restaked rewards into pool → increases pool share → disproportionate reward
- NEEDS VERIFICATION: can pool members set individual payee?

**F10-C: set_payee change timing with era boundary**
- Изменение payee в блоке N
- Era boundary в блоке N+1
- payout_stakers для эры X (до boundary): rewards идут к новому payee
- Вопрос: payee snapshot при era end или при payout call?
- If at payout call: changing payee AFTER era ended affects how that era's rewards paid

---

## F11 — Nomination Pool: `pool_create` + `pool_set_state(Destroying)` + `pool_unbond`

**Нормальное назначение**: Создать пул → использовать → уничтожить при необходимости.

**Кто может вызвать**:
- create: любой (min 1 ATLA)
- set_state(Destroying): Master/root role
- pool_unbond: любой member при Destroying state, или admin for force_unbond

**Что создаёт даже при failure**:
- pool_create: pool object exists, Creator bonded
- set_state(Destroying): pool в destroying state независимо от pending rewards

**Что меняет on-chain**: pool state, member ledgers

**Что меняет off-chain**: UI показывает pool в Destroying state

**Какие события emits**: UNKNOWN (pool state change events)

---

**Опасные комбинации:**

**F11-A: pool_create(low_commission=0) → attract members → pool_nominate(bad_validator) → destroy**
- Создать пул с 0% commission (attractive)
- Привлечь максимум участников (до 512 пулов, неограниченно членов?)
- Pool Nominator (отдельный от Creator) номинирует слэшируемый валидатор
- Level 4 slash (100%) → все участники теряют всё
- Master: set_state(Destroying)
- Creator уходит с reputation damage, no criminal liability

**F11-B: reward timing in Destroying state**
- Pool earns rewards for eras 1-70
- Master: set_state(Destroying) at era 71
- Members: try to claim rewards in Destroying state
- SUBSTRATE pallet-nomination-pools: в Destroying state члены могут unbond но reward claim может быть ограничен
- If pending pool-level payout not triggered before destroy: rewards → treasury
- All 70 eras of rewards lost

**F11-C: concurrent pool operations race**
- Member A: pool_unbond (начинает выход)
- Simultaneously: pool gets slashed (pending 7 days)
- Member A's unbonding chunk: slashable (7d window > 72h unbonding?)
- Or: Member A withdraws after 72h → before 7-day slash applies → escapes
- Same H06 scenario but at pool level

---

## F12 — EVM: `bond` (Substrate) → использование в EVM dApp

**Нормальное назначение**: Bonding ATLA для staking (Substrate). EVM dApps используют EVM ATLA.

**Кто может вызвать**: любой holder

**Что создаёт даже при failure**: ничего в reverse

**Что меняет on-chain**: AccountData.misc_frozen (bonded) увеличивается

**Опасные комбинации:**

**F12-A: bond + EVM transfer из незамороженного баланса**
- Account имеет 1000 ATLA Substrate free
- bond(500): misc_frozen = 500, usable_balance = 500
- EVM call: transfer(500 ATLA через Frontier)
- Frontier читает usable_balance (не total): 500 доступно → transfer проходит
- Теперь: bonded = 500, EVM = 500, Substrate free = 0
- Total ATLA: 1000 ✓ (нет double-spend)
- НО: если slash applied to bonded (500) → slash reduces bonded portion only
- EVM portion (500): не подвержена slash
- Nominator effectively hedged: 50% in staking (slashable), 50% in EVM (safe)

**F12-B: bond_extra из EVM-side ATLA**
- User имеет ATLA только в EVM (H160 balance)
- Пытается bond_extra → Substrate call → reads Substrate free balance (0)
- Reverts: "insufficient funds"
- User confused: "у меня есть ATLA" (видит EVM balance) → "не могу стейкать"
- Must first move EVM → Substrate via Frontier precompile (if supported)
- NEEDS VERIFICATION: есть ли withdraw_from_evm precompile?

---

## F13 — Governance: `propose` + `vote` + Foundation execution delay

**Нормальное назначение**: Децентрализованное управление параметрами протокола.

**Кто может вызвать**:
- propose: staker с bonded ATLA (≥10 ATLA, NEEDS VERIFICATION)
- vote: any bonded ATLA holder

**Что создаёт даже при failure**:
- propose: если quorum не достигнут → proposal expires; collateral может не возвращаться? (UNKNOWN)

**Что меняет on-chain**: proposal state machine

**Что меняет off-chain**: Foundation action required

---

**Опасные комбинации:**

**F13-A: propose(block_time_reduction) + vote + execute → emission spike**
- Proposal: снизить block time вдвое
- Vote: passes (Foundation + large stakers support)
- Foundation executes (legitimate governance outcome)
- Side effect: если era = N blocks (not N seconds) → eras twice as frequent → 2× annual emissions
- Each step legitimate; combined = unintended inflation
- Proposer не обязательно понимает emission implication

**F13-B: propose(validator_min_increase) + pending slash race**
- Proposal: raise validator minimum от 75K до 500K ATLA
- 21-day voting + pending execution
- During 21 days: validator with 80K stake (just above old min) gets slashed
- If Foundation delays execution: validator still valid during delay
- Immediate execution: validator forced to chill (below new min) OR add stake within grace period (UNKNOWN grace period)

**F13-C: governance proposal + PlatformController upgrade**
- Proposal: change emission rate
- Voting: 21 days in progress
- SUPER_ADMIN upgrades PlatformController (no governance required)
- Upgrade changes how `platformFee` is calculated
- Proposal passes and Foundation implements "old" parameter change
- But new code interprets the parameter differently
- Same governance decision → different economic outcome under new code

---

## F14 — `chill()` — добровольный выход валидатора

**Нормальное назначение**: Валидатор останавливает участие в consensus. Начинает unbonding (21 days).

**Кто может вызвать**: stash or controller (NEEDS VERIFICATION)

**Когда**: в любой момент

**Что должно быть true**: must be validator or nominator

**Что создаёт даже при failure**: ничего

**Что меняет on-chain**: validator preferences cleared; unbonding scheduled

**Exit fee**: 1 ATLA (NEEDS VERIFICATION: где enforced?)

---

**Опасные комбинации:**

**F14-A: chill + pending slash (timing attack)**
- ValidatorA получает Level 4 slash (100%, pending 7 days)
- ValidatorA вызывает chill() + начинает unbonding (21 дней)
- Day 7: slash applies to... what?
  - If slash applies to `active` bond: active = 75K (still bonded, just chilling)
  - Slash applied correctly
  - If slash applies only to validators NOT to chilling: escape? (unlikely)
- BUT: nominators of ValidatorA also slashed
- chill() protects ValidatorA from FUTURE slashes (no longer active validator)
- Existing slash: still applies

**F14-B: chill + exit fee ambiguity**
- Exit fee = 1 ATLA. Where is this enforced?
- If enforced in pallet-staking: automatic deduction from bond
- If enforced off-chain / by UI: can skip by calling pallet directly
- If not enforced at all now (UNKNOWN): validators exit for free
- NEEDS VERIFICATION: locate `ExitFee` or similar in pallet-staking config

**F14-C: chill → validator slot freed → election within same era**
- ValidatorA chills mid-era. Slot freed.
- Does candidate validator immediately fill slot? Or waits for next era?
- If mid-era replacement: new validator joins with partial era → partial rewards
- If waits: 1 of 256 slots empty for remainder of era → slightly reduced network capacity

---

## СВОДНАЯ ТАБЛИЦА ОПАСНЫХ КОМБИНАЦИЙ

| Комбинация | Функции | Что создаётся | Severity |
|------------|---------|---------------|----------|
| F01-A | oracle + pause | Claim window expires during pause | High |
| F01-B | oracle + registerContract | Orphaned deposits на old bridge | High |
| F02-A | executeBatch + updateTreasury | Partial treasury redirect in batch | High |
| F02-B | executeBatch + pauseContract | Drain под cover паузы | Critical |
| F02-D | executeBatch → any contract | Arbitrary authority via PlatformController | Critical |
| F03-A | pause + upgrade | Malicious upgrade behind pause cover | Critical |
| F03-B | pauseContract + oracle | Claims expire during pause | High |
| F03-D | FULL pause vs Substrate | Users think all stopped; staking continues | Medium |
| F04-A | treasury + 100% fee | All bridge funds → attacker in 2 txs | Critical |
| F04-B | treasury + pause | Change treasury during "emergency protection" | Critical |
| F05-A | registerContract + pauseContract | New contract unpaused while old paused | High |
| F05-B | registerContract EOA | Silent bridge failure | High |
| F06-A | upgrade + storage shift | Oracle frozen or corrupted value | High |
| F06-B | upgrade + in-flight operations | Retroactive rule change | High |
| F07-A | unbond 72h + 7d slash | Nominator escapes 100% slash | High |
| F08-A | public payout + payee misconfig | Rewards to wrong address | High |
| F08-B | payout_stakers + expiry | No one claims → treasury | Medium |
| F09-A | pool_nominate + commission 100% | Pool earns 0, still slashable | High |
| F09-B | nominate + validator chill | Nominations wasted, 0 rewards | Medium |
| F11-A | pool creation + slash | Pool as rug vehicle | High |
| F11-B | pool destroy + unclaimed rewards | 70 eras rewards → treasury | Medium |
| F12-A | bond + EVM split | Hedge against slash via EVM side | Medium |
| F13-A | governance block time + emissions | 2× inflation via "innocent" proposal | High |
| F14-A | chill + pending slash | Chill doesn't prevent existing slash | Medium |

---

*Фаза 5 завершена. Ожидаю отмашку на Фазу 6.*
