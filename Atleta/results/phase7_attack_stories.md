# ФАЗА 7 — Attack Stories
## Atleta Network — Mainnet Only

---

## STORY 1: "The Trusted Messenger"
### executeBatch → PlatformController как universal privilege escalation key

**Name**: The Trusted Messenger

**Broken Assumption**:
Дизайнеры предполагали: роли в downstream contracts изолированы от PlatformController. SUPER_ADMIN имеет полномочия только в PlatformController. Если другой контракт хочет принять SUPER_ADMIN как privileged — он должен явно дать ему роль.

Скрытое: дизайнеры могли использовать `msg.sender == address(platformController)` как "trusted caller" паттерн в bridge/vesting/reward contracts — это стандартная практика при интеграции upgradeable контроллеров.

**Weird State**:
SUPER_ADMIN вызывает `executeBatch([bridgeContract], [abi.encodeWithSignature("grantRole(bytes32,address)", WITHDRAWER_ROLE, attackerAddr)])`. Транзакция проходит. SUPER_ADMIN не имел WITHDRAWER_ROLE в bridgeContract. PlatformController имел. Теперь attacker имеет.

**Why Normal Reasoning Misses It**:
При чтении PlatformController.sol: `executeBatch` выглядит как utility function для batch admin operations. Ни SUPER_ADMIN, ни PlatformController явно не имеют ролей в downstream contracts. Reviewer думает "isolated systems." Не смотрит как downstream contracts авторизуют calls от PlatformController address. Reviewer смотрит на что SUPER_ADMIN *имеет*, а не на что PlatformController address *принимается как*.

**Minimum Required Powers**:
- Доступ к SUPER_ADMIN private key (`0xB4349Fb7Fe240E24E8c5b2fF5caF4Cc265d38aF7`)
- Возможность отправить одну транзакцию

**Execution Shape**:
1. Определить downstream contracts в экосистеме (bridge, vesting, rewards)
2. Для каждого contract: проверить паттерн авторизации — `msg.sender == platformController` или `hasRole(X, msg.sender)` where X granted to platformController
3. Выбрать target function (grantRole, withdraw, mint, etc.)
4. Encode calldata для target function
5. Вызвать `executeBatch([target], [calldata], true)` от SUPER_ADMIN
6. Verify: target contract state изменился

**Components That Disagree**:
- PlatformController: "SUPER_ADMIN выполнил легитимный batch"
- BridgeContract: "PlatformController вызвал меня → доверяю → выполняю"
- Security model: "SUPER_ADMIN не имеет прав в bridge"
- Reality: SUPER_ADMIN де-факто имеет все права любого контракта, доверяющего platformController address

**Expected Divergence**:
- authority: SUPER_ADMIN appears to have limited scope → has unlimited scope over any platformController-trusting contract
- accounting entry: unauthorized role grant not visible as "unauthorized" in logs

**Potential Impact**:
- Unauthorized withdrawal of all bridge funds
- Unauthorized minting of wrapped assets
- Unauthorized role assignments giving attacker persistent access
- Complete bridge draining in single transaction if bridge has drain function

**Evidence Needed**:
- Source code всех downstream contracts (bridge, vesting, reward distributors)
- Паттерн авторизации: grep for `msg.sender == ` and `platformController` in downstream contracts
- Список всех functions в bridge contract accepting platformController as caller
- transaction trace of executeBatch showing msg.sender at target level

**Confidence**: Medium (HIGH if any downstream contract uses address-based auth)

**Reachability**: High (single transaction, known SUPER_ADMIN pattern)

**Impact**: Critical (full fund drain possible)

**Next Test**:
```
// Read all deployed contracts in ecosystem
// For each: decompile or fetch source
// Check: does any function have require(msg.sender == platformControllerAddr)?
// If YES: test via fork simulation
```

**Expected Result If True**:
Fork test: executeBatch targeting bridge's `withdraw(1000e18, attacker)` succeeds. Bridge balance → attacker. No revert.

**Expected Result If False**:
All downstream contracts use `hasRole(ROLE, msg.sender)` with explicitly granted roles. executeBatch to bridge → AccessControlUnauthorizedAccount revert.

---

## STORY 2: "The Frozen River"
### Oracle Advance Attack — вечная заморозка bridge deposits

**Name**: The Frozen River

**Broken Assumption**:
Дизайнеры предполагали: ORACLE key защищён. Единственная функция ORACLE (updateLastProcessedTronBlock) — "безопасная" — она только продвигает число вперёд. Нельзя отозвать средства через неё. Нельзя изменить роли. Что плохого может сделать скомпрометированный ORACLE?

Скрытое: lastProcessedTronBlock — это watermark доступности. Advance его до 99,999,999 = навсегда пропустить все TRON-транзакции из реального диапазона.

**Weird State**:
lastProcessedTronBlock = 99,999,999. Реальный TRON tip ≈ 83,400,000. Bridge считает "все TRON-блоки до 99M обработаны." Новые TRON deposits (в блоках 83.4M–99M): bridge отказывает в settlement ("block already processed, no new deposits expected in range"). 16.6 миллионов TRON-блоков = ~578 дней TRON-активности — навсегда заморожены.

**Why Normal Reasoning Misses It**:
`updateLastProcessedTronBlock` выглядит как maintenance function. "Продвигает синхронизацию." Reviewer думает: "attacker может только УСКОРИТЬ синхронизацию — это не опасно." Не замечает что "синхронизирован с будущим" = "отказывает в обработке настоящего." Advance past reality = permanent blind spot.

**Minimum Required Powers**:
- Доступ к ORACLE EOA private key (`0x3Aa473E3818AAB6F5bC103936466e7BCf78e31E2`)
- Одна транзакция (~0.0000176 ATLA gas)
- Публичное знание oracle address (известен из on-chain activity)

**Execution Shape**:
1. Скомпрометировать ORACLE private key (phishing, key theft, supply chain)
2. Отправить: `updateLastProcessedTronBlock(99999999)` от ORACLE address
3. Tx проходит: проверка `99999999 > currentValue` ✓; `BlockNotNewer` не triggered
4. Emit: `OracleBlockUpdated(99999999)`
5. Bridge downstream: все pending TRON deposits fail settlement
6. Нет механизма отката

**Components That Disagree**:
- PlatformController: lastProcessedTronBlock = 99,999,999 (legitimate oracle update)
- TRON chain: tip ≈ 83,400,000 (16.6M blocks behind oracle claim)
- Bridge logic: "range 83.4M–99M already processed → reject new deposits from this range"
- Users with TRON deposits: "my deposit in block 83,400,100 should be claimable"
- Bridge: "block 83,400,100 < lastProcessedTronBlock, already handled" (or: orphan gap)

**Expected Divergence**:
- settlement status: user expects "pending" → bridge sees "already past window"
- balance: user deposited TRON assets → never receives Atleta assets
- refund eligibility: UNKNOWN if TRON-side has refund; possibly permanent loss

**Potential Impact**:
- 100% of in-flight TRON deposits at time of attack: unprocessable
- All future TRON deposits until bridge manually reset: unprocessable
- Recovery: SUPER_ADMIN must revoke ORACLE role from attacker, grant to new EOA, but lastProcessedTronBlock CANNOT be decreased
- Permanent damage: all TRON blocks 83.4M–99M forever skipped

**Evidence Needed**:
- Bridge contract source: how does it use lastProcessedTronBlock for deposit validation?
- Does bridge check: `depositTronBlock <= lastProcessedTronBlock` (exposure) or `depositTronBlock == lastProcessedTronBlock +1 ` (strict)?
- Is there a max_advance_per_call limit in updateLastProcessedTronBlock? (По ABI — нет)
- ORACLE key security: hot wallet, hardware wallet, MPC?

**Confidence**: High (oracle function confirmed, no advance limit confirmed)

**Reachability**: Medium (requires ORACLE key compromise)

**Impact**: High (bridge halt, user fund lock)

**Next Test**:
```javascript
// Read-only fork test:
const platformController = await ethers.getContractAt("PlatformController", PROXY_ADDR);
const current = await platformController.lastProcessedTronBlock();
// Simulate from oracle address:
await impersonateAccount(ORACLE_ADDR);
await platformController.connect(oracle).updateLastProcessedTronBlock(99999999);
const after = await platformController.lastProcessedTronBlock();
assert(after == 99999999); // Should pass
```

**Expected Result If True**:
Fork test: updateLastProcessedTronBlock(99999999) succeeds. No revert. lastProcessedTronBlock = 99999999. No max advance check triggered.

**Expected Result If False**:
Transaction reverts with custom error (e.g., `AdvanceTooLarge` or similar). Max advance limit enforced.

---

## STORY 3: "The Invisible Hand"
### SUPER_ADMIN instant upgrade without timelock or governance

**Name**: The Invisible Hand

**Broken Assumption**:
Дизайнеры (или пользователи) предполагали: изменение кода PlatformController требует социального/governance процесса. Upgrade = community-visible event. Есть implicit expectation что код "stable" после deployment.

Скрытое: UUPS upgrade, SUPER_ADMIN = 1 EOA, 0 timelock, 0 governance approval. Код может измениться за 12 секунд (2 блока: upgrade tx + confirmation).

**Weird State**:
PlatformController proxy (`0x0E534a...`) указывает на malicious implementation. Proxy address не изменился. Users, hardcoded-доверяющие этому address, взаимодействуют с новым кодом. Upgraded(0xMalicious) event emitted — но кто мониторит?

maliciousImpl переопределяет `updateLastProcessedTronBlock` чтобы: принимать вызов от любого (не только ORACLE) И transfer balance к msg.sender. Теперь каждый кто вызывает "oracle update" получает весь ETH/ATLA баланс контракта.

**Why Normal Reasoning Misses It**:
Reviewer смотрит на current implementation (verified, clean code). Думает: "вот что контракт делает." Не думает о том что implementation = upgradeable. Deployed bytecode ≠ permanent. "Upgraded" event существует но reviewer смотрит на state, не на upgrade history. UUPS implementation slot не видна в Blockscout UI как warning.

**Minimum Required Powers**:
- SUPER_ADMIN private key (`0xB4349Fb7Fe240E24E8c5b2fF5caF4Cc265d38aF7`)
- Deploy malicious implementation contract (требует ATLA для gas)
- Одна транзакция upgradeTo()

**Execution Shape**:
1. Deploy maliciousImpl (любой Solidity contract с proxiableUUID selector) — block N
2. `upgradeTo(maliciousImpl)` от SUPER_ADMIN — block N+1
3. Emit: `Upgraded(maliciousImpl)` — заметит только активный monitoring
4. Любой последующий вызов → malicious code
5. Опционально: вызвать любую function для drain/state corruption
6. Опционально: upgradeTo(originalImpl) для "rollback" и сокрытия следов

**Components That Disagree**:
- Proxy address (`0x0E534a...`): тот же — users доверяют
- Implementation: полностью другой — users не знают
- Blockscout: показывает implementation = maliciousImpl (только если indexed)
- UI: может кэшировать старый ABI → decode fails → "unknown function" → не alarming

**Expected Divergence**:
- balance: funds in contract → attacker after malicious call
- authority: all privileged functions → now callable by anyone (if malicious impl removes modifiers)
- accounting entry: Upgraded() event in logs but no alert

**Potential Impact**:
- Полный drain всех funds под управлением PlatformController
- Permanent corruption bridge routing
- Role system reset (новый impl = новые rules)
- Historical: если attacker rollback → forensic analysis сложнее

**Evidence Needed**:
- Подтверждение что `0xB4349...` НЕ является multisig/timelock controller
  → `is_contract: false` ✓ (already confirmed: EOA)
- Подтверждение отсутствия timelock: нет TimelockController contract в ecosystem
- Проверить `_authorizeUpgrade` в текущей implementation: требует только `SUPER_ADMIN` role
- История upgrades: был ли уже один upgrade? (текущая impl vs deployed impl different?)

**Confidence**: High (EOA SUPER_ADMIN confirmed, no timelock found)

**Reachability**: Low-Medium (requires SUPER_ADMIN key compromise OR insider)

**Impact**: Critical (total system takeover)

**Next Test**:
```bash
# Check if any TimelockController exists in ecosystem
# Search Blockscout for TimelockController contract deployments
curl https://blockscout.atleta.network/api/v2/smart-contracts?q=TimelockController

# Check current implementation vs initial deployment
# Read EIP-1967 slot of proxy:
cast storage 0x0E534a16e544752B101cEf8c486e1D7A2f7Fa1cf \
  0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
```

**Expected Result If True**:
No TimelockController found. Implementation slot = current impl address. No governance approval required for upgrade. Simulation: `upgradeTo(mockImpl)` from `0xB4349...` succeeds immediately.

**Expected Result If False**:
TimelockController exists as SUPER_ADMIN with enforced delay. upgradeTo queued, not immediate.

---

## STORY 4: "Dead Deposit"
### Паузирование bridge + TRON claim window expiry

**Name**: Dead Deposit

**Broken Assumption**:
Дизайнеры предполагали: pause защищает пользователей. Emergency pause = "стоп, разбираемся." Пользователи в безопасности пока система паузирована. Их pending deposits защищены.

Скрытое: oracle продолжает обновлять lastProcessedTronBlock ДАЖЕ во время EVM pause (oracle update не проверяет pause state). Если bridge имеет claim window (например: "claim в течение 72h от TRON deposit block"), то clock идёт пока bridge паузирован.

**Weird State**:
Bridge паузирован. Oracle обновляет TRON blocks каждые 6 секунд. 72-часовое claim window истекает. Bridge анпаузирован. Deposit: claim reverts ("claim window expired"). TRON assets: locked в TRON bridge contract без возможности refund.

Никакого взлома. Пауза "защитила" пользователей лишив их права claim.

**Why Normal Reasoning Misses It**:
"Pause = safe" — интуитивно верно. Reviewer проверяет: bridge operations paused ✓. Не думает о: oracle continues ✓; time-sensitive claims fail silently ✓. Два честных механизма (pause + oracle) создают harmful interaction.

**Minimum Required Powers**:
- Обычный пользователь с TRON deposit
- SUPER_ADMIN делает паузу (любая причина: bug, security incident)
- Достаточно времени паузы (>claim window duration)

**Execution Shape**:
1. User deposits 10,000 USDT на TRON at block 83,400,000
2. Oracle обрабатывает: lastProcessedTronBlock reaches 83,400,000
3. SUPER_ADMIN паузирует bridge (emergency или maintenance)
4. Oracle: продолжает обновлять lastProcessedTronBlock (не останавливается из-за pause)
5. 72h+ проходит в paused state; claim window expires
6. SUPER_ADMIN unpause
7. User calls bridge claim → revert: "claim window expired"
8. TRON-side: нет automatic refund → 10,000 USDT permanently locked

**Components That Disagree**:
- User: "я был защищён паузой, мой deposit safe"
- Bridge: "claim window expired during pause, deposit invalid"
- Oracle: "синхронизация продолжалась непрерывно"
- PlatformController: "pause was legitimate emergency action"

**Expected Divergence**:
- refund eligibility: user believes eligible → bridge says window closed
- settlement status: user deposited → bridge sees expired claim
- balance: 10,000 USDT locked on TRON with no Atleta equivalent

**Potential Impact**:
- Loss of all in-flight deposits with time-sensitive claim windows during any pause period
- Longer pauses = more users affected proportionally
- Could be exploited intentionally: SUPER_ADMIN паузирует именно тогда когда крупный deposit в transit

**Evidence Needed**:
- Bridge contract source: есть ли claim window? Как считается?
- Does `updateLastProcessedTronBlock` check `globalPause` or `currentPauseLevel`?
- Function body of oracle update: is there `whenNotPaused` modifier?
- TRON-side bridge: is there automatic refund on Atleta timeout?

**Confidence**: Medium (requires bridge claim window to exist; currently UNKNOWN)

**Reachability**: High (no special powers needed, any pause triggers it)

**Impact**: High (if claim window exists and oracle continues during pause)

**Next Test**:
```solidity
// Fork test:
// 1. Deploy mock bridge with 72h claim window
// 2. Simulate user deposit
// 3. pauseAll() from SUPER_ADMIN
// 4. advance time 73h (evm_increaseTime)
// 5. oracle continues updating lastProcessedTronBlock
// 6. unpause()
// 7. user calls claimDeposit() → expect revert("ClaimWindowExpired")
```

**Expected Result If True**:
claimDeposit() reverts. Oracle continued during pause (no whenNotPaused on oracle). User's TRON deposit unclaimable.

**Expected Result If False**:
Either: bridge has no time-sensitive claim window; OR oracle stops during pause; OR TRON-side provides automatic refund.

---

## STORY 5: "The Loyal Executioner"
### Governance selective execution — Foundation как veto power

**Name**: The Loyal Executioner

**Broken Assumption**:
Дизайнеры предполагали: governance = on-chain binding decisions. Community voted → community decided → outcome implemented. Это фундаментальный контракт с участниками.

Скрытое: "outcomes are implemented/executed by the BCSports Foundation" (прямая цитата документации). Никакого on-chain enforcement. Foundation = single arbiter of which votes "count."

**Weird State**:
Proposal A (снизить emissions): прошёл 65% голосов. Foundation: исполняет немедленно.
Proposal B (вывести 100M ATLA из treasury в community): прошёл 51% голосов. Foundation: "технически сложно, требует дополнительного аудита" — задержка бесконечная.
Proposal C (ограничить Foundation полномочия): прошёл 60% голосов. Foundation: "противоречит regulatory requirements" — не исполняет.

On-chain: все три Passed. Reality: только один исполнен. Participants не имеют recourse.

**Why Normal Reasoning Misses It**:
Reviewer смотрит на ATLETAgov pallet — есть on-chain voting ✓. Думает: "governance существует." Не проверяет: есть ли on-chain execution trigger? Нет. Все governance decisions = Foundation permission-gated. Reviewers привыкли к on-chain execution (Governor contracts на EVM). Substrate governance может быть on-chain-executed тоже. Atleta's: нет.

**Minimum Required Powers**:
- Foundation (BCSports) — уже является actor в системе
- Никаких exploit действий — только inaction
- Или: любой крупный staker с достаточным ATLA для dominant voting position

**Execution Shape**:
1. Observe: Foundation holds 140M treasury + team vesting ≈ 20-40% effective voting power
2. Submit proposal beneficial to Foundation (emit more rewards for validators = Foundation-aligned)
3. Vote passes with Foundation support
4. Foundation executes promptly
5. Submit proposal limiting Foundation power (treasury to community fund)
6. Vote passes with community majority
7. Foundation: delays indefinitely citing "technical review"
8. Foundation submits counter-proposal to return funds to "Foundation operations"
9. Foundation-aligned validators vote yes; passes
10. Foundation executes immediately

**Components That Disagree**:
- On-chain governance pallet: both proposals = Passed
- Foundation: selectively executes based on own interests
- Community: believes voted outcome = implemented outcome
- Protocol: no enforcement mechanism exists

**Expected Divergence**:
- authority: community believes they govern → Foundation governs
- settlement status: proposal Passed ≠ proposal Executed
- accounting entry: treasury outflows to Foundation-preferred destinations despite community votes

**Potential Impact**:
- Governance legitimacy destruction
- Treasury captured by Foundation-aligned parties
- Long-term: progressive power concentration until community exits (validator/nominator flight)
- Short-term: specific proposals blocked that would limit Foundation power

**Evidence Needed**:
- История governance proposals + execution status + delays
- Foundation's current ATLA voting power (total staked ATLA under Foundation control)
- On-chain execution mechanism: is there ANY timelock/executor contract?
- Documentation quote: "outcomes are implemented/executed by the BCSports Foundation" — это не ambiguous

**Confidence**: High (documented off-chain execution, confirmed)

**Reachability**: High (no exploit needed; existing power structure)

**Impact**: High (systemic, affects all governance outcomes)

**Next Test**:
```
// Read-only: governance history
// Query ATLETAgov pallet via RPC:
// wss://rpc.mainnet.atleta.network/
// state_getStorage(governance pallet prefix) → list all proposals
// Check: Passed proposals → match with any on-chain parameter changes
// If proposals passed but parameters unchanged → confirmed selective execution
```

**Expected Result If True**:
Governance history shows multiple Passed proposals with no corresponding on-chain parameter changes. Foundation statements acknowledge "pending implementation."

**Expected Result If False**:
All Passed proposals have corresponding on-chain execution transactions. Timeline reasonable.

---

## STORY 6: "The Phantom Nominator"
### Номинатор убегает от 100% slash за 72 часа

**Name**: The Phantom Nominator

**Broken Assumption**:
Дизайнеры предполагали: slash incentive alignment — номинаторы несут риск за выбранных валидаторов. Это стимулирует тщательный выбор. 7-дневный escrow = достаточно времени для применения slash ко всем stakeholders.

Скрытое: номинаторы могут unbond за 72 часа. Если slash application (день 7) > unbond completion (72 hours) → номинатор выходит до применения. Если slash применяется только к `active` bond, а не к `unlocking` chunks — escape полный.

**Weird State**:
ValidatorA получает Level 4 slash (100%). Nominator N:
- Hour 0: видит slash event on-chain
- Hour 1: вызывает unbond(fullStake) → stake в unlocking state
- Hour 72: withdraw_unbonded() → ATLA свободны
- Day 7: slash применяется → active bond = 0 → slash amount = 0

Nominator N: теряет 0. ValidatorA: теряет 100%. Асимметрия полная.

**Why Normal Reasoning Misses It**:
Reviewer читает: "nominators share validator's slash proportionally." ✓ True in principle.
Reviewer читает: "unbonding period: 72 hours." ✓ True.
Reviewer читает: "slash deferred 7 days." ✓ True.
72h < 7d — arithmetic obvious in hindsight. But reviewer не объединяет три факта в одну attack path. Happy path: нет slash → unbonding irrelevant для slash analysis.

**Minimum Required Powers**:
- Обычный номинатор
- Мониторинг on-chain slash events (публично видны)
- Возможность вызвать unbond + withdraw в течение 72h после slash event

**Execution Shape**:
1. Nominator N номинирует ValidatorA (зная или не зная о риске)
2. ValidatorA equivocates (Level 4, 100% slash) или случайно offline (Level 1)
3. N видит `OffenceReported` или `SlashReported` event on-chain (block explorer или monitoring)
4. N немедленно вызывает `unbond(totalBond)` → stake = unlocking
5. N ждёт 72h → `withdraw_unbonded()` → ATLA free
6. Day 7: slash logic пытается применить к N → проверяет `ledger.active` → 0 → slash amount = 0
7. N сохраняет 100% stake; ValidatorA теряет 100%

**КРИТИЧНО**: шаг 6 зависит от того применяется ли slash к `ledger.unlocking` chunks или только к `ledger.active`.

**Components That Disagree**:
- Protocol design intent: "nominators share slash risk"
- pallet-staking execution: если slash только на active bond → nominator escaped
- ValidatorA: 100% slash applied
- Nominator N: 0% slash applied (escaped)
- Incentive alignment: broken

**Expected Divergence**:
- debt: validator loses 100%; nominator loses 0%
- incentive alignment: nominators no longer bear validator risk if monitoring
- fee: remaining slash amount (nominator's share) → treasury gets 0 instead of proportional amount

**Potential Impact**:
- Systematic: sophisticated nominators (bots, whales) monitor and escape slashes
- Naive nominators (majority): bear full proportional slash
- Market effect: incentivizes sophisticated monitoring infrastructure → centralizes staking to sophisticated actors
- Validator: loses support from escaped nominators (lower backing) without corresponding slash distribution

**Evidence Needed**:
- `pallet-staking/src/slashing.rs`: функция slash_nominators — проверяет `ledger.active` или `ledger.active + sum(ledger.unlocking)`?
- Substrate canonical: в Substrate 4.x slash применяется к active bond. Unlocking chunks: ДА, могут быть slashed если slash_defer_duration > unbonding period — NEEDS VERIFICATION
- Atleta config: `SlashDeferDuration` = 7 eras (7×36h = 252h = ~10.5 days); `BondingDuration` (unbonding) = 3 eras (3×36h = 108h = 4.5 days for nominators)

СТОП — важная коррекция: документация говорит "72 часа / 3 дня" для nominators. Если `BondingDuration` = 3 eras и era = 36h → 3×36h = 108h = 4.5 дней. Это БОЛЬШЕ 7 дней? Нет: slash defer = 7 eras = 7×36h = 252h = 10.5 дней. Unbonding = 3 eras = 108h = 4.5 дней. 4.5 < 10.5. ESCAPE ещё возможен.

Но: в Substrate, slash applied to unlocking chunks if they haven't yet completed unbonding. Если unlocking chunk ещё в progress (не withdrawn) → slash может применяться к ним тоже.

Ключевой вопрос: применяет ли Atleta's pallet-staking slash к unlocking chunks В ДОПОЛНЕНИЕ к active?

**Confidence**: Medium (depends on slashing.rs implementation)

**Reachability**: High (any nominator with monitoring bot)

**Impact**: High (if escape works: broken incentive model for entire staking system)

**Next Test**:
```rust
// Read Atleta's runtime/src/lib.rs for:
// type SlashDeferDuration = ConstU32<N>; // how many eras?
// type BondingDuration = ConstU32<M>; // nominator unbonding eras?
// Then check pallet-staking version: does it slash unlocking chunks?

// Fork test:
// 1. Setup validator with nominators
// 2. Report equivocation → slash deferred
// 3. Nominator calls unbond() immediately
// 4. Advance time past unbonding duration
// 5. Nominator calls withdraw_unbonded()
// 6. Advance to slash application block
// 7. Check: nominator stake slashed or not?
```

**Expected Result If True**:
Nominator's stake returned fully. Slash applied to active bond (0 after withdrawal). Treasury gets validator's slash, nominator's portion = 0.

**Expected Result If False**:
Nominator's unlocking chunks slashed. withdraw_unbonded returns reduced amount.

---

## STORY 7: "The Two Treasury Keys"
### Platform fee 100% + Treasury redirect = двухшаговое ограбление

**Name**: The Two Treasury Keys

**Broken Assumption**:
Дизайнеры предполагали: platform fee — это малая комиссия. Изменения treasury — administrative. Оба параметра существуют для нормальной работы платформы, не как attack vectors. Их независимость = independence of concerns.

Скрытое: combined, они представляют полный контроль над bridge fee income без каких-либо ограничений. Fee = 100% (valid). Treasury = attacker (valid). One block. All bridge fees → attacker.

**Weird State**:
Блок N: `updatePlatformFee(10000)` — fee = 100%.
Блок N: `updateTreasuryWallet(attackerAddr)` — treasury = attacker.
Следующий bridge operation: пользователь депонирует 10,000 USDT эквивалент. Bridge берёт fee: 10,000 × 100% = 10,000. Получатель fee: attackerAddr. Пользователь получает: 0.
Нарушений нет. Оба параметра в пределах onchain constraints.

**Why Normal Reasoning Misses It**:
Reviewer читает `updatePlatformFee`: "max 10,000 bps" — думает protection. Reviewer читает `updateTreasuryWallet`: "only SUPER_ADMIN" — thinks admin privilege only. Не думает о их composition. Каждая функция отдельно — legitimate admin control. Вместе — complete fund redirection. Two keys, one lock.

**Minimum Required Powers**:
- SUPER_ADMIN private key
- 2 транзакции (или 1 executeBatch)
- Знание когда крупный bridge deposit in-flight

**Execution Shape**:
1. Monitor bridge for large incoming deposits (public mempool или TRON explorer)
2. При обнаружении крупного pending deposit:
   - `updateTreasuryWallet(attackerAddr)` — block N
   - `updatePlatformFee(10000)` — block N (same block via executeBatch)
3. Large deposit settles: 100% fee → attackerAddr
4. Immediately after:
   - `updatePlatformFee(previousValue)` — restore to normal
   - `updateTreasuryWallet(originalTreasury)` — restore treasury
5. Attacker: received 100% of user's deposit
6. On-chain: two fee/treasury changes, brief window, looks like misconfiguration

**Components That Disagree**:
- User: "bridge charges small fee, I'll receive ~99% of my deposit"
- Contract: "fee = 100% per current platformFee; treasury = attackerAddr per current treasuryWallet"
- Transaction: valid, no revert
- Audit trail: fee and treasury were legitimately updated and restored

**Expected Divergence**:
- balance: user receives 0 instead of ~10,000
- fee: 100% taken instead of expected 1-2%
- ownership: funds in attackerAddr instead of user's Atleta address
- accounting entry: fee payment looks normal (fee collected → treasury), just treasury ≠ expected

**Potential Impact**:
- 100% theft of any bridge deposit in attack window
- Window can be targeted: monitor for whales, execute during their settlement
- Reversibility: attacker restores parameters → looks like glitch
- Forensics: need to correlate treasury change timestamps with deposit settlements

**Evidence Needed**:
- Current platformFee value: `platformController.platformFee()` via RPC
- Downstream bridge: reads `platformController.platformFee()` dynamically (not cached at deploy)?
- Does bridge apply fee at deposit time or settlement time? If settlement: fee change between deposit and settlement = retroactive
- Event logs: does PlatformController emit TreasuryUpdated / FeeUpdated? With old+new values?

**Confidence**: High (both functions confirmed, no protection confirmed)

**Reachability**: Low-Medium (requires SUPER_ADMIN compromise OR insider)

**Impact**: Critical (100% of any targeted deposit)

**Next Test**:
```javascript
// Via RPC to wss://rpc.mainnet.atleta.network:
// eth_call to platformController.platformFee() → current value
// eth_call to platformController.treasuryWallet() → current address

// Fork test:
// updatePlatformFee(10000) → success?
// updateTreasuryWallet(attacker) → success?  
// simulate bridge settlement → verify 100% goes to attacker
```

**Expected Result If True**:
Both calls succeed. Bridge settlement sends 100% of deposit to attackerAddr. User receives 0.

**Expected Result If False**:
Either: platformFee capped at lower value by downstream contract sanity check; OR bridge applies fee based on snapshot at deposit time, not settlement time.

---

## STORY 8: "The Nominator's Timing Trap"
### Nomination snapshot timing — slash applies to already-changed nominations

**Name**: The Nominator's Timing Trap

**Broken Assumption**:
Дизайнеры предполагали: nominations change → следующая эра. Поэтому slash exposure определяется nominations effective at era start. If nominator changed nominations in current era → old nominations still active for THIS era → old slash exposure. Это ожидаемо.

Скрытое: Пользователь не понимает этой задержки. UI показывает "вы номинируете [B, C, D]" — но для текущей эры ещё активны [A, B, C]. ValidatorA получает slash. Пользователь теряет долю несмотря на "смену" nominations.

**Weird State**:
Эра X, блок 100: Nominator N вызывает `nominate([B, C, D])` — убирает A.
Эра X, блок 200: ValidatorA equivocates → Level 4 slash.
Эра X election snapshot (начало эры X): N номинировал [A, B, C].
Slash применяется к exposure snapshot эры X: N ещё числится как nominator A.
N теряет долю slash за ValidatorA — хотя UI показывает что N уже убрал A.

**Why Normal Reasoning Misses It**:
User: "я снял A из nominations, всё." UI: "[B, C, D] ✓." Both correct — for next era. Neither communicates "you still bear A's risk for current era." UX assumes confirmation = safety. Protocol assumes users understand era-delayed semantics. Gap: nobody informs user of residual risk.

**Minimum Required Powers**:
- Обычный номинатор (жертва)
- ValidatorA equivocates (может быть случайным или намеренным)
- Нет специальных прав для атаки — это UX/timing structural issue

**Execution Shape (как exploit)**:
Если ValidatorA контролируется adversary:
1. ValidatorA умышленно equivocates в момент когда nomination changes pending
2. Targeting: выбирает момент когда крупные nominators только что сменили nominations
3. Ещё числятся в snapshot эры X → slash применяется
4. Крупные nominators теряют stake несмотря на "ушли" из ValidatorA
5. ValidatorA потерял stake, но также harvested nominator stake losses

Как structural issue (без adversary):
1. Обычный slash на ValidatorA
2. Nominator N, не понимающий era semantics, теряет stake который думал убрал
3. Повторяется масштабно при плохих UI/UX сигналах

**Components That Disagree**:
- UI: "ваши активные nominations: [B, C, D]"
- pallet-staking election: "effective nominations для эры X: [A, B, C]"
- Slash logic: "N exposed to A для эры X → slash applied"
- User: "я убрал A, я в безопасности"

**Expected Divergence**:
- debt: nominator теряет stake за validator которого "убрал"
- UI status: показывает new nominations, не предупреждает о residual risk
- refund eligibility: slash applied correctly по протоколу, нет refund

**Potential Impact**:
- Structural: все nominators с pending nomination changes → residual slash exposure
- UX confusion: mass slash event → "я же убрал этого валидатора!" → community panic, loss of trust
- Deliberate targeting: если adversary контролирует validator → может time slash для maximum nominator damage

**Evidence Needed**:
- Точный момент exposure snapshot в pallet-staking: `era_start_block` или `per_block`?
- UI: показывает ли UI warning "old nominations still active until next era"?
- Подтверждение что nomination change effective только с `next_era`: `Nominations<T>::insert(who, targets)` + era boundary check

**Confidence**: High (Substrate staking semantics: era-delayed nominations confirmed by design)

**Reachability**: High (occurs whenever nominator changes nominations and slash follows in same era)

**Impact**: Medium-High (structural UX issue → real fund loss)

**Next Test**:
```
// Read-only via Substrate RPC:
wss://rpc.mainnet.atleta.network/
// system_chain → confirm mainnet
// state_getStorage(nominators_prefix, accountId) → current nominations
// state_getStorage(erasStakers_prefix, era, validator) → check if old nominator still in snapshot

// Simulate on fork:
// 1. Nominator nominates [A, B]
// 2. Era starts
// 3. Nominator calls nominate([B]) -- removes A
// 4. Report A for equivocation in same era
// 5. Check: is nominator's stake included in slash for A?
```

**Expected Result If True**:
Nominator's stake included in slash for validator A, despite calling nominate([B]) in same era. Nominator loses proportional share.

**Expected Result If False**:
Nomination change effective immediately for slash purposes (not era-delayed for slash exposure). Nominator not slashed for A.

---

## СВОДНАЯ ТАБЛИЦА ATTACK STORIES

| Story | Название | Confidence | Reachability | Impact | Следующий шаг |
|-------|----------|-----------|--------------|--------|---------------|
| S1 | The Trusted Messenger | Medium→High | High | Critical | Downstream contracts source |
| S2 | The Frozen River | High | Medium | High | oracle max_advance check |
| S3 | The Invisible Hand | High | Low-Med | Critical | TimelockController search |
| S4 | Dead Deposit | Medium | High | High | Bridge claim window source |
| S5 | The Loyal Executioner | High | High | High | Governance execution history |
| S6 | The Phantom Nominator | Medium | High | High | slashing.rs unlocking chunks |
| S7 | The Two Treasury Keys | High | Low-Med | Critical | bridge fee application timing |
| S8 | The Nominator's Timing Trap | High | High | Med-High | erasStakers snapshot timing |

**Приоритет для Фазы 8 (опровержение):**
1. S1 (executeBatch authority) — Critical если подтверждена
2. S7 (100% fee + treasury) — Critical, requires only SUPER_ADMIN
3. S3 (instant upgrade) — Critical, EOA confirmed
4. S6 (slash escape) — High, affects staking incentive model
5. S8 (nomination timing) — High, structural and reachable

---

*Фаза 7 завершена. Ожидаю отмашку на Фазу 8.*
