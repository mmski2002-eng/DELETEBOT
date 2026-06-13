# ФАЗА 6 — 10 рамок системного злоупотребления
## Atleta Network — Mainnet Only

Для каждой рамки: применима ли, конкретная гипотеза, что нужно увидеть в коде/trace, что убьёт гипотезу.

---

## РАМКА 1: Desynchronization
> Можно ли заставить две части системы честно разойтись во мнении?

**Применима: YES — несколько независимых точек рассинхронизации**

### Гипотеза D1: BABE vs GRANDPA finality split

Atleta использует BABE (block production) + GRANDPA (finality). BABE непрерывно производит блоки. GRANDPA финализирует пачками. Если >1/3 валидаторов офлайн: GRANDPA stalls, BABE продолжает.

**Состояние**: EVM транзакции включены в BABE блоки. Bridge indexer видит `tx_success = true`. Пользователи получают "confirmed" уведомления. GRANDPA finality отстаёт на N блоков. Если GRANDPA resumption вызывает reorg (canonical chain выбирает другую BABE fork): все "confirmed" EVM транзакции в reorged блоках → reversed.

**Что нужно увидеть**: как bridge settlement проверяет finality — по BABE inclusion или GRANDPA stamp? Если BABE: rorg risk. Если GRANDPA: settlement lags during stall.

**Что убьёт**: доказательство что bridge ждёт GRANDPA finality перед settlement; или proof что Atleta's BABE is fork-choice safe enough для bridge purposes.

---

### Гипотеза D2: lastProcessedTronBlock vs реальный TRON tip

**Состояние**: ORACLE обновляет lastProcessedTronBlock. Реальный TRON tip может быть на 100+ блоков впереди (oracle lag) или на 100 блоков позади (если oracle накручивает). Никакой on-chain механизм не синхронизирует эти два числа.

Честный рассинхрон: TRON производит блок каждые 3 секунды. Atleta блок каждые 6 секунд. Если oracle обновляет раз в block Atleta (каждые 6 сек) → 2 TRON блока пропускаются между каждым обновлением. Задержка накапливается при сетевых проблемах.

**Что нужно увидеть**: максимальный lag между реальным TRON tip и lastProcessedTronBlock за исторический период (TRON block explorer vs PlatformController state).

**Что убьёт**: доказательство что oracle всегда в пределах N блоков от реального TRON tip.

---

### Гипотеза D3: Governance on-chain vs Foundation execution state

**Состояние**: Proposal P прошёл голосование (on-chain state = Passed). Foundation ещё не исполнила. Два честных актора:
- Governance participant: "изменение принято"
- Protocol parameters: "изменений нет"
- Оба правы в своих доменах. Нет механизма синхронизации.

**Что нужно увидеть**: список исторических governance proposals + timestamp их execution (или non-execution). Проверить задержки.

**Что убьёт**: доказательство on-chain execution mechanism (timelock, automatic parameter change).

---

**Для каждой D-гипотезы:**
- D1: нужен код bridge settlement finality check
- D2: нужен TRON block explorer comparison + oracle update history  
- D3: нужна governance history с execution timestamps

---

## РАМКА 2: Double Meaning
> Может ли одно действие иметь разный смысл для разных компонентов?

**Применима: YES — критически для PlatformController**

### Гипотеза DM1: `executeBatch` — двойной смысл caller identity

**Состояние**: SUPER_ADMIN (addr X) вызывает `executeBatch([targetContract], [grantRole(ADMIN_ROLE, attackerAddr)])`.

- Для PlatformController: "SUPER_ADMIN выполняет batch" — валидно
- Для targetContract: `msg.sender = address(platformController)` — "PlatformController вызывает меня"
- Если targetContract имеет: `require(msg.sender == platformController, "not authorized")` → доступ предоставлен
- SUPER_ADMIN получает права targetContract через PlatformController proxy

**Один вызов, два смысла**: SUPER_ADMIN action (ограниченная роль) → PlatformController action (привилегированный caller для зависимых контрактов).

**Что нужно увидеть**: все downstream contracts и как они авторизуют PlatformController. Функции с `msg.sender == platformControllerAddress`.

**Что убьёт**: если downstream contracts не используют address-based check, только role-based (OZ AccessControl) — тогда escalation невозможна через этот путь.

---

### Гипотеза DM2: `pauseContract("name")` — двойной смысл после re-registration

**Состояние**: 
- `pauseContract("Bridge")` → contractPauses[0xBridgeOld] = true
- `registerContract("Bridge", 0xBridgeNew)` 
- `isPaused(0xBridgeNew)` → false (не в contractPauses)
- `isPaused(0xBridgeOld)` → true (в contractPauses, но устарело)

Для SUPER_ADMIN: "Bridge паузирован."
Для 0xBridgeNew: "Я не паузирован."
Один и тот же "Bridge" — два разных состояния.

**Что нужно увидеть**: точный код `pauseContract` (принимает string → lookup → stores address или string?). Если stores address: re-registration invalidates pause.

**Что убьёт**: если pauseContract stores string key (не address) → re-registration doesn't affect pause lookup; string key stays paused.

---

### Гипотеза DM3: `updatePlatformFee(10000)` — разный смысл для admin vs user

Для SUPER_ADMIN при вызове: "устанавливаю максимально допустимое значение" (edge case testing?)
Для contract: `platformFee = 10000; // valid ✓`
Для user с pending bridge operation: "я теряю 100% своих средств"

Никакого события типа `FeeChangedToMax(warning=true)`. Нет grace period. Нет on-chain protest механизма.

**Что нужно увидеть**: downstream contracts — применяют ли platformFee к pending operations или только к новым.

**Что убьёт**: если fee applies только к operations CREATED after fee change (snapshot при create, не при settle).

---

## РАМКА 3: Lifecycle Confusion
> Можно ли использовать объект в неправильной фазе его жизни?

**Применима: YES — несколько lifecycle-sensitive objects**

### Гипотеза LC1: Slash в escrow (pending) vs "clean" validator для bridge purposes

**Состояние**: ValidatorA получает Level 4 slash (pending, 7-day window). До применения slash:
- pallet-staking: validator.is_active = true (slash не применён)
- pallet-offences: pending slash record exists
- Bridge/downstream: если проверяет `is_validator_active(ValidatorA)` → true

Если bridge принимает подписи валидаторов для bridge transactions (мультисиг схема): ValidatorA с pending 100% slash ещё может подписывать bridge operations как "active validator". Bridge не знает о pending slash.

**Что нужно увидеть**: использует ли bridge validator signatures/attestations; проверяет ли bridge pallet-offences на pending slashes.

**Что убьёт**: bridge не использует validator signatures; или bridge checks pallet-offences.

---

### Гипотеза LC2: Pool в Destroying state принимает join

**Состояние**: Master вызывает `set_state(Destroying)`. В mempool уже находится `pool_join(pool_id, amount)` от нового участника. Оба транзакции в одном блоке, порядок важен:
- Если Destroying сначала: join → revert (pool destroying)
- Если join сначала: член присоединяется → потом pool destroying → член немедленно force_unbonded → теряет pending rewards от вступления

В Substrate: порядок транзакций в блоке определяется priority/nonce. Если join и set_state от разных авторов — порядок непредсказуем.

**Что нужно увидеть**: pallet-nomination-pools обработка concurrent state transitions.

**Что убьёт**: если pool_join проверяет state перед accept и Destroying → immediate revert.

---

### Гипотеза LC3: Governance proposal в Voting → Foundation executes before vote ends

**Состояние**: Proposal P в Voting state (21 дней). Foundation решает исполнить до окончания голосования (технически нет on-chain enforcement против early execution). Половина голосов ещё не подана. Foundation исполняет при текущем (50% support) тогда как финальный результат мог быть 30% (fail).

Early execution using partial vote = lifecycle confusion: proposal используется в фазе Voting как if в фазе Passed.

**Что нужно увидеть**: нет ли on-chain minimum для Foundation execution timing.

**Что убьёт**: если Foundation policy = wait full 21 days (social contract, not on-chain enforceable).

---

## РАМКА 4: Conservation Violation
> Может ли value появиться в одном месте, не исчезнув в другом?

**Применима: CRITICALLY YES — для TRON bridge**

### Гипотеза CV1: TRON Reorg → Double ATLA Mint

**Состояние**:
1. User deposits 1000 USDT на TRON side (TRON block 83,000,000)
2. Oracle обновляет lastProcessedTronBlock до ≥83,000,000
3. Bridge settles: минтит/выпускает 1000 аналог-USDT на Atleta side
4. TRON reorg: блок 83,000,000 исчезает → deposit tx не существует в canonical TRON
5. Oracle НЕ МОЖЕТ откатить lastProcessedTronBlock (монотонный закон)
6. Atleta side: 1000 аналог-USDT уже выпущено и в обращении
7. TRON side: deposits в reorged block возможно повторены в canonical block → повторный deposit
8. Oracle обрабатывает canonical block → bridge settles снова → 2000 аналог-USDT выпущено

TRON-side collateral: 1000 USDT (single canonical deposit)
Atleta-side tokens: 2000 (double mint)

Conservation violated: 2000 > 1000.

**Что нужно увидеть**: TRON finality guarantee (TRON DPoS: SuperRepresentatives finalize; NEEDS VERIFICATION на реорг-защиту); bridge dedup механизм (уникальный identifier TRON tx hash?).

**Что убьёт**: если bridge использует TRON tx hash как unique key (dedup), повторный deposit с тем же hash невозможен. Но reorged block создаёт НОВЫЙ tx hash → bypass dedup.

---

### Гипотеза CV2: executeBatch creates state without source

**Состояние**: Если downstream bridge contract доверяет PlatformController → SUPER_ADMIN через executeBatch может вызвать mint/credit function напрямую. Tokens created without corresponding TRON-side lock.

Conservation: ATLA/tokens mint на Atleta side без депозита на TRON side.

**Что нужно увидеть**: bridge mint function — требует ли oracle proof или только caller authorization?

**Что убьёт**: если mint требует cryptographic proof от TRON (merkle proof, etc.), не только caller check.

---

## РАМКА 5: Authority Substitution
> Может ли слабая authority быть принята как сильная?

**Применима: YES — критически для executeBatch pattern**

### Гипотеза AS1: PlatformController address = Universal Admin Key

**Состояние**: В экосистеме может существовать паттерн: `require(msg.sender == IPlatformController.getAddress() || hasRole(ADMIN, msg.sender))`.

Или проще: downstream contract deployed с hardcoded `platformController` address = trusted admin.

Тогда:
- SUPER_ADMIN прямо: ограниченная роль в downstream contract
- SUPER_ADMIN через executeBatch: msg.sender = platformController = unlimited admin в downstream contract

Слабая authority (SUPER_ADMIN, не имеющий ADMIN role в downstream) → принята как сильная (platformController trusted address).

**Что нужно увидеть**: source code всех downstream contracts; паттерн авторизации по address vs role.

**Что убьёт**: все downstream contracts используют только OZ AccessControl с granular roles; ни один не проверяет `msg.sender == platformControllerAddress`.

---

### Гипотеза AS2: ORACLE EOA с украденным ключом = partial bridge control

**Состояние**: ORACLE role = только `updateLastProcessedTronBlock`. Кажется: ограниченная power.

Но: ORACLE может advance tronBlock до любого значения. Bridge downstream: если использует `lastProcessedTronBlock` как authority для "this deposit is valid to settle" → скомпрометированный ORACLE может:
1. Skip specific deposits (advance past them without settlement)
2. Allow settlement of deposits from blocks that don't exist on canonical TRON

Weak authority (update a number) → substituted as strong authority (control which deposits are valid).

**Что нужно увидеть**: как bridge contract validates individual deposits using lastProcessedTronBlock.

**Что убьёт**: если bridge has separate per-deposit proof mechanism (TRON tx hash + merkle proof) independent of lastProcessedTronBlock.

---

### Гипотеза AS3: Pool Nominator role без личного stake = zero-risk authority

**Состояние**: Pool Nominator role can be assigned to account with 0 personal stake in pool. Pool Nominator decides which validators pool's ATLA backs. If Nominator has no skin in game → Nominator's authority over slash risk is unlimited for members, zero for themselves.

Weak authority (Nominator role, no stake) → substituted as strong authority (control over all members' slash exposure).

**Что нужно увидеть**: pallet-nomination-pools — требует ли Nominator role holder иметь bonded stake in pool.

**Что убьёт**: если Nominator = always has proportional stake in pool (implied by pool membership).

---

## РАМКА 6: Path Substitution
> Может ли необычный валидный путь достичь состояния, обычно доступного только через intended path?

**Применима: YES — для treasury, bridge routing, governance outcomes**

### Гипотеза PS1: Treasury redirect без governance

**Intended path**: governance proposal → community vote → Foundation execution → treasury address changed.

**Substituted path**: SUPER_ADMIN вызывает `updateTreasuryWallet(newAddr)` напрямую. Одна транзакция. Нет голосования, нет задержки, нет уведомления.

Одинаковое конечное состояние: treasury points to new address.
Разная required authority: governance (high) vs SUPER_ADMIN (low, relative to governance legitimacy).

**Что нужно увидеть**: подтверждение что `updateTreasuryWallet` не проверяет governance approval. По ABI — нет такой проверки.

**Что убьёт**: если SUPER_ADMIN === governance multisig (одно и то же). Но SUPER_ADMIN = EOA, не multisig.

---

### Гипотеза PS2: Validator set manipulation через governance block-time change

**Intended path для изменения validator set**: governance proposal изменить `minValidatorStake`; Foundation executes; validators below threshold forced to chill.

**Substituted path**: governance proposal снизить block time → eras shorter → elections more frequent → validator set reshuffled faster. Если параллельно: slash большинства малых validators в один момент (coordinated slashing reports by large validators = cartel) → validator set collateral damage during reshuffle.

Не прямая атака на validator set, а через "innocent" block time change + natural slash dynamics.

**Что нужно увидеть**: governance parameter scope definition для block_time changes.

**Что убьёт**: если governance can't change block time (blocked per documentation). Need to verify exact scope.

---

### Гипотеза PS3: Pool destroy → redirect unclaimed rewards to treasury (альтернативный путь к treasury funding)

**Intended path для treasury funding**: slash → escrow → treasury; или governance vote на treasury allocation.

**Substituted path**: Master создаёт pool → members join → pool earns rewards → Master destroys pool перед reward claim → rewards → treasury.

Альтернативный, полностью легальный способ перевести stake-earner rewards в treasury через lifecycle manipulation. Если Master = Foundation-aligned actor → Foundation effectively harvests pool rewards via destruction.

**Что нужно увидеть**: где идут unclaimed pool rewards при destroy; pallet-nomination-pools behavior in Destroying state.

**Что убьёт**: если members can always claim before destroy; или Destroying state requires all rewards distributed before completion.

---

## РАМКА 7: Failure Harvesting
> Может ли failure/refund/timeout/cancellation создать полезное состояние?

**Применима: YES — особенно для bridge failures**

### Гипотеза FH1: Failed bridge claim → permanent TRON asset lock (no refund path)

**Состояние**: User deposits 10,000 USDT на TRON side. Oracle advance attack (H02): lastProcessedTronBlock skips their deposit block. Claim attempt on Atleta: fails (bridge doesn't recognize deposit as within processed range, or their block was "processed" but without actual settlement).

Bridge failure = no on-chain refund mechanism on TRON side (TRON can't know Atleta rejected).
Result: 10,000 USDT permanently locked in TRON bridge contract.

**Failed settlement = useful state for attacker**: если атакующий контролирует оракул → может выборочно skip конкурентов' deposits → lock their funds.

**Что нужно увидеть**: TRON-side bridge contract — есть ли refund/timeout mechanism для failed Atleta settlements?

**Что убьёт**: TRON-side bridge has timeout: if no settlement proof within X blocks → automatic refund.

---

### Гипотеза FH2: Failed executeBatch call creates partial privileged state

**Состояние**: `executeBatch([grantRole, transfer, revokeRole], [...], revertOnFail=false)`.
- grantRole: SUCCESS → attacker has role
- transfer: FAILS → no funds moved
- revokeRole: SUCCESS → original admin loses role

revertOnFail=false: attacker gained role, admin lost role, no funds moved. "Successful" tx with two-thirds of intended effect.

SUPER_ADMIN думал: если transfer fails → whole batch reverts. Неверно при revertOnFail=false.

**Что нужно увидеть**: SUPER_ADMIN's intended semantics when using revertOnFail. Is there ever a case where false is intentional?

**Что убьёт**: SUPER_ADMIN всегда использует revertOnFail=true для role management; false только для non-critical multicalls.

---

### Гипотеза FH3: Expired rewards → forced treasury accumulation → governance leverage

**Состояние**: Large nominator intentionally lets rewards expire (84 eras) → treasury grows. Treasury allocation controlled by governance. Foundation controls execution. Foundation + large treasury = Foundation can propose generous treasury distributions to allies post-accumulation.

"Failure" to claim = useful state for Foundation (treasury growth → governance leverage).

**Что нужно увидеть**: treasury growth rate from unclaimed rewards historically (NEEDS explorer data).

**Что убьёт**: if treasury distribution requires supermajority that Foundation can't control alone.

---

## РАМКА 8: Observer Exploit
> Можно ли обмануть наблюдателя легче, чем сам контракт?

**Применима: YES — для indexer, UI, и bridge monitoring**

### Гипотеза OE1: Fake oracle "health" signal

**Состояние**: OracleBlockUpdated events выглядят как "bridge is healthy and synchronized." Observer (monitoring dashboard, user UI) проверяет: есть ли события → да → "oracle active."

Attacker (compromised ORACLE key): отправляет updateLastProcessedTronBlock с быстрым advance. Events продолжают поступать. Observer: "all good, oracle updating."

Reality: oracle отравлен, TRON blocks skipped, bridge deposits will fail.

Наблюдатель обманут дешевле чем контракт: event emission = trivial (one tx). Contract: accepts any valid advance. User UI: sees event = assumes correctness.

**Что нужно увидеть**: есть ли monitoring с max_advance_per_update alerting; проверяет ли кто-нибудь что lastProcessedTronBlock не обгоняет real TRON tip.

**Что убьёт**: off-chain monitoring сравнивающий lastProcessedTronBlock с TRON RPC tip; alerts при >N block advance в одном update.

---

### Гипотеза OE2: Indexer shows "success" for BABE-included but GRANDPA-unfinalized tx

**Состояние**: Bridge indexer слушает EVM events на Atleta. BABE включает tx в block B. Event emitted. Indexer записывает "settled". UI показывает "Success ✓."

GRANDPA finalizes slightly different chain (fork choice), block B reorged. Event reversed. Indexer (если не handles reorgs): still shows "success".

Наблюдатель (indexer/UI) обманут честным BABE-production, которое GRANDPA потом отверг.

**Что нужно увидеть**: bridge indexer reorg handling; subscription type (best_block vs finalized_block).

**Что убьёт**: indexer subscribes to `finalized_head` not `best_head`; all events are finality-gated.

---

### Гипотеза OE3: pauseContract не emits visible event → UI стале

**Состояние**: SUPER_ADMIN вызывает `pauseContract("Bridge")`. Contract state changes. Если нет pause-specific event (или event не indexed): UI кэшированное состояние = "bridge operational." Пользователи продолжают deposits зная что bridge работает. Deposits во время паузы: stuck.

Observer (UI): deceived by absence of event rather than presence of fake event.

**Что нужно увидеть**: PlatformController — emits ли pause events? ABI не содержит явного Paused event в доступной информации.

**Что убьёт**: pauseContract emits `ContractPaused(name, address, timestamp)` event, indexed by bridge monitoring.

---

## РАМКА 9: Economic Inversion
> Могут ли стимулы заставить честного участника сделать действие, выгодное атакующему?

**Применима: YES — для pool dynamics и validator economics**

### Гипотеза EI1: Pool Nominator без stake = zero cost для высокорискованной номинации

**Состояние**: Pool Master assigns Nominator role to external account with 0 stake in pool.

Nominator's incentive: pick validators that PAY Nominator off-chain for nominations. Validator selection becomes a market: validators bribe pool nominators.

Validators winning these bribes: may be highest-bidding, not most reliable. → systematic selection of unreliable validators → systematic slash risk for pool members.

Честный Nominator (no stake) действует рационально в своих интересах (max off-chain bribes) → catastrophic for pool members. No protocol rule violated.

**Что нужно увидеть**: pallet pool role assignment constraints.

**Что убьёт**: Nominator must have stake in pool (NEEDS VERIFICATION).

---

### Гипотеза EI2: Validator commission race to 0 → under-provisioned nodes → degraded performance

**Состояние**: Validator competition для привлечения nominators: снижают commission. Race to 0% commission. Validators earn only era points (block rewards), no commission income.

At 0% commission: validator infrastructure costs covered only by emissions. If emissions < infrastructure cost: rational validators go offline OR cut corners (cheaper hardware, less redundancy).

Honest validators, rationally cutting costs = network degradation = more unresponsiveness flags = more slashing = worse for nominators.

Economic inversion: low commission (attractive to nominators) → degraded validator performance → slash risk for same nominators.

**Что нужно увидеть**: current commission distribution across active validators.

**Что убьёт**: минимальная комиссия enforced (нет такого ограничения по документации).

---

### Гипотеза EI3: payout_stakers public call + era expiry = rational free-riding

**Состояние**: payout_stakers is PUBLIC call. Anyone pays gas, everyone gets rewards. Nash equilibrium: each nominator waits for someone else to call payout_stakers (free-rider problem). If everyone waits → no one calls → era expires → treasury.

Rational delay (wait for someone else to pay gas) → collective loss (all rewards expired).

Честные номинаторы, рационально экономящие gas → потеря своих rewards. Attacker can exploit: if attacker knows all nominators are lazy → delay reward claims → mass treasury transfer → if attacker controls Foundation → indirect benefit.

**Что нужно увидеть**: исторические данные по reward claim timing vs expiry.

**Что убьёт**: если кто-то always calls payout_stakers (бот/service). Но кто платит за этот сервис и кто его контролирует?

---

## РАМКА 10: Boundary Collapse
> Могут ли два домена, которые должны быть раздельными, разделить ID/state/proof/cache/config/nonce?

**Применима: YES — для name registry и address spaces**

### Гипотеза BC1: Registry name case sensitivity collapse

**Состояние**: PlatformController registry: `mapping(string => address)`.

SUPER_ADMIN регистрирует: `registerContract("Bridge", 0xBridgeAddr)`.
Bridge contract ищет: `platformController.getContract("bridge")` (lowercase b).

Solidity string comparison: `keccak256("Bridge") != keccak256("bridge")`. Returns address(0).

Bridge downstream: читает address(0) как treasury. Calls to address(0): в EVM → blackhole (no revert в receive). Fees burned, not received by treasury. Silent accounting failure.

**Что нужно увидеть**: exact string keys used in registerContract calls; getContract calls in bridge contract code.

**Что убьёт**: если bridge и PlatformController используют identically-cased constant strings (e.g., `bytes32 constant BRIDGE_KEY = "Bridge"`).

---

### Гипотеза BC2: TRON tx hash namespace collision with Atleta tx hash

**Состояние**: если bridge dedup mechanism использует tx hash как unique identifier: TRON tx hashes (TronHash) и Atleta tx hashes оба в одном mapping без chain prefix.

Theoretical: TRON tx hash = 0xABCD... accidentally equals Atleta internal tx hash in same mapping.
TronHash 0xABCD... processed → marked as seen.
Atleta-generated hash 0xABCD... → incorrectly marked as "already processed TRON deposit."

**Probability**: collision unlikely if TRON and Atleta hashes in separate namespaces. But NEEDS VERIFICATION that bridge stores TRON hashes with domain prefix.

**Что нужно увидеть**: bridge contract storage layout for processed deposit tracking.

**Что убьёт**: separate namespace per chain (e.g., `mapping(bytes32 => mapping(uint32 => bool)) processedByChainAndHash`).

---

### Гипотеза BC3: Substrate AccountId ↔ EVM H160 — граница коллапса при edge case

**Состояние**: Frontier maps Substrate AccountId (32 bytes) to EVM H160 (20 bytes). Mapping: H160 = first 20 bytes of blake2(AccountId) или direct truncation?

If mapping is NOT injective (two different Substrate accounts map to same H160): two users share one EVM address. One users EVM balance = both users' combined Substrate balances.

EVM transfer from shared H160: drains both users' funds.

**Что нужно увидеть**: Frontier H160 derivation function in Atleta's implementation. Is it collision-resistant?

**Что убьёт**: если H160 = first 20 bytes of AccountId (SS58 decoded) → unique AccountIds → unique H160s (no collision if AccountIds are different). Standard Frontier behavior is collision-resistant.

---

### Гипотеза BC4: Pool ID ↔ Pool Stash Account namespace

**Состояние**: Nomination pool creates a system-generated "pool stash account" (deterministic from pool_id). Two pools with different pool_ids → different stash accounts. No collision expected.

BUT: если pool_id counter can overflow (u32 = 4B pools max) → wraps → new pool_id = old pool_id → same stash account → state collapse.

At 512 pool max: не достигнет overflow. But if max_pools governance parameter changed to unlimited → eventual overflow possible over very long timeframe.

**Что нужно увидеть**: pallet-nomination-pools pool_id type and overflow protection.

**Что убьёт**: if pool_id is u32 with explicit max 4B and wrapping protection (saturating arithmetic or explicit check).

---

## СВОДНАЯ МАТРИЦА РАМОК

| Рамка | Применима | Сильнейшая гипотеза | Severity | Нужно для подтверждения |
|-------|-----------|---------------------|----------|------------------------|
| 1 Desync | YES | D1: BABE vs GRANDPA bridge finality | High | Bridge finality check code |
| 2 Double Meaning | YES | DM1: executeBatch caller identity | Critical | Downstream contract auth code |
| 3 Lifecycle Confusion | YES | LC1: Pending slash vs bridge validator check | High | Bridge validator check code |
| 4 Conservation | YES | CV1: TRON reorg → double mint | Critical | TRON finality + bridge dedup |
| 5 Authority Subst | YES | AS1: PlatformController = universal key | Critical | Downstream contract patterns |
| 6 Path Subst | YES | PS1: Treasury change without governance | High | updateTreasuryWallet access check |
| 7 Failure Harvest | YES | FH1: Failed bridge → permanent lock | High | TRON-side refund mechanism |
| 8 Observer Exploit | YES | OE1: Fake oracle health signal | High | Oracle monitoring implementation |
| 9 Economic Inversion | YES | EI1: Pool Nominator zero-stake bribes | Medium | Pool role stake requirement |
| 10 Boundary Collapse | YES | BC1: Registry case sensitivity | Medium | String keys in source code |

**Все 10 рамок применимы. Ни одна не отклонена.**

**Топ-3 для немедленной проверки:**
1. **AS1 / DM1** (executeBatch → PlatformController authority): требует downstream contract code
2. **CV1** (TRON reorg → double mint): требует TRON finality docs + bridge dedup code  
3. **FH1** (failed bridge → permanent lock): требует TRON-side bridge contract

---

*Фаза 6 завершена. Ожидаю отмашку на Фазу 7.*
