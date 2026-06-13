# ФАЗА 4 — Семантические разрывы
## Atleta Network — Mainnet Only

Для каждого важного действия — сравнение 5 уровней смысла:
1. Human meaning
2. Contract meaning
3. Backend / indexer meaning
4. Next component meaning
5. Economic meaning

---

## ДЕЙСТВИЕ 1: `updateLastProcessedTronBlock(N)`

**Human meaning**:
"Все транзакции TRON вплоть до блока N обработаны и финализированы. Можно выпускать соответствующие активы на стороне Atleta."

**Contract meaning**:
`lastProcessedTronBlock` становится N. Единственная проверка: N > current. Контракт НЕ проверяет:
- Что блок N реально существует на TRON
- Что все транзакции из блоков 1..N были обработаны
- Что N соответствует finalised TRON-блоку (не просто confirmed)

**Backend / indexer meaning**:
UNKNOWN. Возможно: indexer использует lastProcessedTronBlock как watermark для fetch TRON events. Если indexer независимо читает TRON RPC — может иметь своё представление о "последнем блоке". Если читает из контракта — следует за оракулом.

**Next component meaning (bridge contracts)**:
UNKNOWN (bridge "Coming Soon"). Предположительно: bridge checks `lastProcessedTronBlock >= tronBlockOfDeposit` перед release funds. Если это единственная проверка — H02 (Oracle Advance Attack) полностью реализуем.

**Economic meaning**:
Определяет какие TRON-депозиты могут быть claimed на Atleta. Все депозиты из блоков > lastProcessedTronBlock = не доступны к claim.

---

### Разрывы:

**[GAP-1.1] Одно слово "processed", разный смысл**:
- Human: "обработано" = "все транзакции проверены и включены"
- Contract: "processed" = "мы видели этот block number, больше ничего"
- Можно увеличить: да — advance block без actual processing
- Ведёт к расхождению: funds locked (TRON deposits after gap unreachable)
- Кто заметит первым: пользователи с failed bridge claims
- Кто не заметит: PlatformController (не знает о TRON transactions, только о числе)
- Минимальный тест: сравнить lastProcessedTronBlock с реальным TRON block count через TRON API

**[GAP-1.2] Одинаковый block number, разная семантика finality**:
- TRON DPoS: блок "confirmed" ≠ "finalized" (могут быть reorgs)
- Oracle: не различает confirmed vs finalized — просто число
- Atleta: считает всё до N "safe"
- Можно увеличить: да — оракул обновляет до confirmed-only блока, затем TRON reorg
- Ведёт к: processed deposits that never happened on canonical TRON chain

---

## ДЕЙСТВИЕ 2: `nominate([validator_list])`

**Human meaning**:
"Я выбрал этих валидаторов. Мой стейк теперь поддерживает их. Я несу их риски и получаю их награды."

**Contract meaning**:
Pallet-staking записывает новый список nominated validators. Effective: следующая эра. Текущая эра: старые nominations активны. Slash exposure snapshot: берётся при election в начале каждой эры (NEEDS VERIFICATION — точный момент snapshot).

**Backend / indexer meaning**:
UNKNOWN. Возможно: indexer сразу показывает новые nominations. Пользователь видит "вы номинируете [A, B, C]" хотя эффект — только со следующей эры.

**Next component meaning (pallet-election)**:
Election algorithm (Phragmén) читает nominations в момент election (начало новой эры). Все nominations, поданные до этого момента, учитываются. Nominations, поданные после — нет.

**Economic meaning**:
Slash risk и reward distribution определяются nominations, EFFECTIVE в начале эры. Если slash происходит в текущей эре — применяются СТАРЫЕ nominations, не новые.

---

### Разрывы:

**[GAP-2.1] "Я номинирую" ≠ "мой стейк с этими валидаторами"**:
- 36-часовая задержка между действием и эффектом
- Кто заметит первым: nominator, проверив era-level attribution
- Кто не заметит: UI (вероятно сразу показывает новые nominations)
- Минимальный тест: nominate в середине эры, проверить slash exposure в оставшейся части эры

**[GAP-2.2] Одинаковый пользователь, разная authority в разных эрах**:
- Nominator N в эре X: exposure к ValidatorA
- Nominator N в эре X+1: exposure к ValidatorB
- Если slash за эру X применяется на неделе X+1: N уже "не номинирует" A, но в эре X номинировал
- КЛЮЧЕВОЙ ВОПРОС: берёт ли slash snapshot начала эры (эра X) или момента применения (week X+1)?

**[GAP-2.3] Одно и то же "nomination" — разный смысл для validator и backend**:
- Validator: "у меня X nominators = X * stake backing"
- Backend: может считать по последнему nomination call (не по effective era)
- Economic: rewards calculated on effective nominations only

---

## ДЕЙСТВИЕ 3: `unbond(amount)`

**Human meaning**:
"Я начинаю выводить стейк. Через 72 часа (nominator) / 21 день (validator) смогу забрать ATLA."

**Contract meaning**:
Pallet-staking создаёт unbonding chunk: {amount, era_of_unlock}. Active bonded уменьшается. Сумма ещё подвержена slash (NEEDS VERIFICATION — применяется ли slash к unbonding chunks).

**Backend / indexer meaning**:
UNKNOWN. Indexer показывает "unbonding" статус. Баланс в UI может отображаться как "unlocking" отдельно.

**Next component meaning (pallet-staking after 72h)**:
`withdraw_unbonded` вызов разблокирует сумму, если deadline прошёл. До этого: средства недоступны.

**Economic meaning**:
Средства выведены из staking => не получают rewards. Но: ещё могут быть slashed (если validator, которому приписаны, получает slash). Nominator платит "cost of exit" = missed rewards за 72h.

---

### Разрывы:

**[GAP-3.1] Одинаковый unbond, разная защита от slash**:
- Nominator понимает: "я вышел, моего риска нет"
- Pallet: unbonding chunks потенциально slashable до withdraw_unbonded
- Если slash применяется к unbonding: выход не помогает до полного withdraw
- Если не применяется: выход за 72h = escape window из 7-day slash window

**[GAP-3.2] Одинаковое "выведено", разный смысл для validator vs nominator**:
- Nominator unbonds: 72 часа → возможно escape slash window (7 дней)
- Validator unbonds: 21 день → никакого escape (21d >> 7d window)
- Human: один и тот же "unbond" механизм
- Contract: одинаковый вызов, радикально разные последствия

**[GAP-3.3] Одинаковый баланс, разный владелец с точки зрения системы**:
- During unbonding: номинально "мои" средства
- Staking: не считает для rewards
- Slash: может или не может применять
- UI: "unlocking: 1000 ATLA" — чьи они на самом деле?

---

## ДЕЙСТВИЕ 4: Slash event (misbehavior detected)

**Human meaning**:
"Валидатор наказан. Он и его номинаторы теряют средства. Это уже произошло."

**Contract meaning (при обнаружении)**:
Slash record создан в offences pallet. 7-дневный deferred window начат. Stake НЕ уменьшен. Контракт только фиксирует pending slash.

**Contract meaning (через 7 дней)**:
Slash применён: bonded stake уменьшен, slash amount → treasury. Nominators получают пропорциональный slash.

**Backend / indexer meaning**:
Indexer видит slash event (момент обнаружения). UNKNOWN: индексирует ли как "slash completed" или "slash pending". Если "completed" — баланс показывается неправильно 7 дней.

**Next component meaning (UI)**:
UI, вероятно, показывает "validator slashed" немедленно. Пользователи видят предупреждение. Но баланс nominators ещё не уменьшен. 7 дней inconsistency.

**Economic meaning**:
Реальная потеря средств — через 7 дней. До этого: psychological impact, UI warnings, но нет actual loss. Nominator может unbond за это время (72h << 7d).

---

### Разрывы:

**[GAP-4.1] Одинаковое событие "slash", разные последствия по времени**:
- UI/Human: "слэш произошёл" = немедленно
- Contract state: stake reduction = через 7 дней
- Challenge: возможен только в это 7-дневное окно
- Потенциал: номинатор видит "slashed" в UI, паникует, unbonds → выходит до применения slash

**[GAP-4.2] Одинаковый "challenge window" — разная доступность**:
- Online validator: может подать challenge (7 дней)
- Offline validator: не может (ключи недоступны)
- Human understanding: "challenge window = fair protection"
- Reality: protection exists only for online actors

**[GAP-4.3] Одинаковый slash amount — разный реальный impact для разных nominators**:
- All nominators get proportional slash
- Nominator с minimum stake (10 ATLA): 0.1% = 0.01 ATLA (dust)
- Nominator с 1M ATLA: 0.1% = 1000 ATLA (significant)
- Same % — radically different economic meaning

---

## ДЕЙСТВИЕ 5: Governance vote passes (on-chain)

**Human meaning**:
"Сообщество решило. Это изменение будет реализовано."

**Contract meaning**:
Vote count ≥ threshold в ATLETAgov pallet. Proposal state = Passed. Contrac записывает результат.

**Foundation meaning**:
Получает сигнал. Оценивает технически и юридически. Решает когда и как исполнять.

**Next component meaning (protocol runtime)**:
НИЧЕГО не меняется автоматически. Никакого on-chain execution trigger.

**Economic meaning**:
Если Foundation исполняет → экономические параметры меняются. Если не исполняет → vote результат = dead letter. Voters потратили ATLA на collateral зря.

---

### Разрывы:

**[GAP-5.1] "Vote passed" ≠ "change implemented"**:
- Largest semantic gap в системе
- Один и тот же успех (proposal passed), разные последствия:
  - On-chain: state = Passed ✓
  - Protocol: unchanged
  - Users: expect implementation
  - Foundation: "will implement when ready"
- Можно увеличить: да — delay execution indefinitely
- Ведёт к: governance capture without exploit

**[GAP-5.2] Одинаковое "право голоса", разные категории holders**:
- Solo staker: голосует напрямую
- Pool participant: НЕ голосует (нет governance rights)
- Validator: голосует (stash bonded)
- Foundation: голосует (massive stake)
- Same token, radically different voting power allocation

**[GAP-5.3] Одинаковое "governance approved" — разная authority**:
- Human: "governance = community authority"
- Foundation: "governance = advisory input, we execute"
- The same approval means different things to different actors

---

## ДЕЙСТВИЕ 6: `updatePlatformFee(bps)`

**Human meaning**:
"Комиссия платформы изменилась с X% до Y%."

**Contract meaning**:
`platformFee` storage variable обновлён. Max check: bps ≤ 10,000. Emit event. Все будущие operations используют новое значение.

**Backend / indexer meaning**:
UNKNOWN. Indexer видит fee change event. Может не пересчитывать pending operations.

**Next component meaning (bridge contracts)**:
Все последующие вызовы берут platformFee из PlatformController. Pending (unprocessed) bridge operations — если fee проверяется в момент settlement (не в момент deposit): более поздний settlement применяет новую fee.

**Economic meaning**:
Если fee увеличивается между deposit и settlement: пользователь получает меньше чем ожидал при deposit. Если fee = 10,000 (100%): пользователь получает 0.

---

### Разрывы:

**[GAP-6.1] Одинаковый deposit — разный net amount при изменении fee**:
- User deposits 1000 ATLA на TRON side at fee = 1%
- Fee изменяется до 50% перед settlement
- User expects: 990 ATLA; receives: 500 ATLA
- Кто первым заметит: user after settlement
- Кто не заметит: contract (all valid per rules)

**[GAP-6.2] 100% fee — технически "valid"**:
- Human: fee = 100% → theft
- Contract: fee = 10,000 bps ≤ 10,000 → valid ✓
- This IS the biggest semantic gap in fee system

**[GAP-6.3] "Platform fee" — одно слово, разный scope**:
- Is it applied per-operation? Per-asset? Per-user? Per-day?
- UNKNOWN — no downstream contract to check against
- Human assumes fee is small and predictable
- Contract stores single global value, all operations affected

---

## ДЕЙСТВИЕ 7: `executeBatch([targets], [data], revertOnFail)`

**Human meaning**:
"Admin выполняет несколько операций как одну атомарную транзакцию."

**Contract meaning**:
Loop over targets. Call each with data. If revertOnFail=true: revert all on first failure. If revertOnFail=false: continue on failure, return success array. msg.sender для каждого target call = address(PlatformController).

**Target contract meaning**:
Видит `msg.sender = PlatformController`. Если target checks `msg.sender == platformController` → accepts as authorized. Target НЕ видит original SUPER_ADMIN caller.

**Backend / indexer meaning**:
Видит одну транзакцию `executeBatch`. Internal calls к targets могут не индексироваться как отдельные events (если indexer не обрабатывает internal calls). Partial failures при revertOnFail=false могут быть невидимы.

**Economic meaning**:
Всё что PlatformController может вызвать — SUPER_ADMIN может вызвать. Если любой target contract доверяет PlatformController address → SUPER_ADMIN inherits that trust transitively.

---

### Разрывы:

**[GAP-7.1] Одинаковый вызов — разная authority в зависимости от caller**:
- Direct call от SUPER_ADMIN к bridgeContract: require(hasRole(ADMIN, msg.sender)) → fail (SUPER_ADMIN не имеет ADMIN в bridge)
- executeBatch от SUPER_ADMIN: msg.sender = PlatformController → if bridge checks msg.sender == platformController → SUCCESS
- Same action, different authorization outcome

**[GAP-7.2] revertOnFail=false — "success" транзакция с partial failure**:
- Human: executeBatch вернул success → всё выполнено
- Contract: некоторые calls failed, revertOnFail=false, продолжили, вернули partial success array
- Backend: одна successful tx, но не все операции выполнены
- State: inconsistent (часть changes applied, часть нет)
- Кто заметит: только тот, кто проверит return values array

**[GAP-7.3] "Batch" → атомарность assumed, не enforced при revertOnFail=false**:
- SUPER_ADMIN думает: "или всё, или ничего"
- Contract: при revertOnFail=false → возможно "и то, и это частично"

---

## ДЕЙСТВИЕ 8: `pauseContract("name")` → `isPaused(address)` в downstream

**Human meaning**:
"Контракт X остановлен. Никто не может выполнять операции через него."

**Contract meaning (PlatformController)**:
`contractPauses[getContract("name")] = true`. Хранит `mapping(address => bool)`.

**Bridge contract meaning (при проверке)**:
Предположительно: `require(!platformController.isPaused(address(this)))`. Читает contractPauses[address(this)].

**Gap scenario**:
PlatformController хранит pause для адреса `getContract("name")` в момент pauseContract вызова. Но если between pause и check: SUPER_ADMIN вызывает `registerContract("name", newAddress)`, то `getContract("name")` теперь возвращает другой адрес. isPaused(oldBridgeAddress) = true. isPaused(newAddress) = false. Если bridge теперь деплоен на newAddress → не знает что должен быть паузирован.

**Economic meaning**:
Emergency pause — ключевой механизм защиты пользователей. Если не работает → funds at risk during emergencies.

---

### Разрывы:

**[GAP-8.1] Одинаковое "paused" — разный поиск адреса**:
- pauseContract сохраняет pause для address-at-time-of-call
- Если registry изменился → pause applied to old address, new address unpaused
- Минимальный тест: pauseContract → registerContract (same name, new addr) → check isPaused(new addr)

**[GAP-8.2] Одинаковый FULL pause — разные слои системы**:
- FULL EVM pause: PlatformController.currentPauseLevel = FULL
- Substrate staking: продолжает работать (другой runtime module)
- Users: думают "система остановлена", продолжают стейкать
- Economic: staking rewards continue flowing even during FULL EVM pause

**[GAP-8.3] Одинаковое "pauseAll" vs "pauseContract" — разная семантика**:
- pauseAll: устанавливает глобальный флаг
- pauseContract: паузирует конкретный контракт по address
- Downstream contract может проверять ОДНО, не другое
- If bridge checks `globalPause` but SUPER_ADMIN used pauseContract: bridge not paused

---

## ДЕЙСТВИЕ 9: `registerContract("name", address)`

**Human meaning**:
"Мы регистрируем официальный адрес контракта X. Все обращения к X будут по этому адресу."

**Contract meaning**:
`contracts["name"] = address`. Мгновенно. Без проверки что address — реальный контракт. Без timelock. Без event с обоими (old и new) addresses.

**Backend / indexer meaning**:
UNKNOWN. Может кэшировать старый mapping. Может читать динамически.

**Next component meaning**:
Все последующие `getContract("name")` → new address. Все текущие interactions — если они hardcoded old address → не затронуты. Если динамически читают registry → немедленно переключаются.

**Economic meaning**:
Все будущие fee payments, withdrawals, deposits через "name" → new address. Если new address = attacker → instant redirect of all future funds.

---

### Разрывы:

**[GAP-9.1] Одинаковое "зарегистрированный контракт" — разное для существующих vs новых interactions**:
- Existing operations: могут использовать hardcoded old address
- New operations: используют new registry entry
- Split routing: same name, different actual targets

**[GAP-9.2] registerContract не верифицирует что address — контракт**:
- Can register EOA address as "Bridge"
- If downstream calls to "Bridge" fail silently (no revert): funds lost
- Human: "registered official bridge" → EOA registered by mistake

**[GAP-9.3] Одинаковый event "ContractRegistered" — не содержит old address**:
- UNKNOWN если event содержит old address
- If no: monitoring systems can't detect re-registration (old vs new)
- Attacker registration = looks same as legitimate registration in logs

---

## ДЕЙСТВИЕ 10: Era reward claim (Substrate)

**Human meaning**:
"Я получаю заработанные награды за мою работу/стейк."

**Contract meaning**:
`pallet_staking::payout_stakers(validator, era)`. Rewards рассчитываются на основе era points, validator commission, nominator stake. Marked as claimed. Cannot claim twice for same era.

**Pool member meaning**:
Pool накапливает rewards. Member должен вызвать pool-specific claim. Claim от pallet_staking на пул-уровне ≠ распределение участникам.

**Backend / indexer meaning**:
UNKNOWN. Может показывать "pending rewards" без учёта истекших эр.

**Economic meaning**:
Unclaimed rewards за эру E expire после E+84. Treasury получает unclaimed. Compound effect: активные claimers получают больше (через restaking).

---

### Разрывы:

**[GAP-10.1] "Earned rewards" ≠ "auto-received rewards"**:
- Human: "я заработал → получу автоматически"
- Contract: требует активный payout_stakers call per era
- Economic gap: passive participants lose to expiry

**[GAP-10.2] Pool rewards vs member rewards — два разных claim механизма**:
- Pool earns rewards from staking (pool-level claim)
- Pool member earns share (member-level claim)
- Both must happen. If pool-level claim expires → all member rewards lost
- Member can't bypass pool to claim directly

**[GAP-10.3] Одинаковая "клеймленная" эра — разный смысл для solo vs pool**:
- Solo nominator claims era X → done
- Pool member: pool must claim era X, THEN member claims from pool
- Two-step process both with expiry risk

---

## ДЕЙСТВИЕ 11: `upgradeTo(newImpl)` (UUPS)

**Human meaning**:
"Контракт обновлён для исправления багов или добавления функций."

**Contract meaning**:
EIP-1967 implementation slot обновлён. Все будущие calls к proxy → new implementation. Существующий storage: неизменён (но может быть misinterpreted если layout сдвинулся).

**User meaning**:
"Тот же адрес контракта" = "тот же код". Нет.

**Backend / indexer meaning**:
ABI может измениться. Indexed events могут изменить signature. Старые event logs с новым ABI = некорректная интерпретация.

**Economic meaning**:
Все funds под контролем proxy теперь под новым кодом. Если новый код malicious → instant drain. Если layout сдвинулся → data corruption.

---

### Разрывы:

**[GAP-11.1] Одинаковый адрес — разный код**:
- Users bookmark 0x0E534a... как "safe bridge"
- After upgrade: код полностью другой, address тот же
- No user notification required, no timelock

**[GAP-11.2] Одинаковый storage slot — разная переменная**:
- Implementation A: slot 1 = lastProcessedTronBlock
- Implementation B: slot 1 = newVariable (storage layout changed)
- lastProcessedTronBlock now reads from wrong slot
- Oracle updates wrong value; bridge reads corrupted data

**[GAP-11.3] "Authorized upgrade" — разная trust assumption**:
- SUPER_ADMIN: "I have technical right to upgrade"
- Users: "upgrade requires community governance approval"
- Protocol: any upgrade is valid if SUPER_ADMIN signs
- No on-chain governance required for upgrade

---

## ДЕЙСТВИЕ 12: Substrate ↔ EVM ATLA transfer (Frontier)

**Human meaning**:
"Переношу ATLA между EVM-адресом и Substrate-адресом. Это одни и те же средства."

**Contract meaning**:
Frontier precompile: списывает с AccountData (Substrate), кредитует EVM account (H160). Или обратно. Атомарно в рамках одного блока.

**Staking pallet meaning**:
Читает только Substrate AccountData. Если ATLA перемещено в EVM: staking pallet видит уменьшенный баланс. Нельзя стейкать EVM-ATLA напрямую.

**EVM dApp meaning**:
Видит EVM balance (H160). Может использовать EVM-ATLA в смарт-контрактах. Не знает о Substrate staking.

**Economic meaning**:
ATLA в EVM не приносит staking rewards. ATLA в Substrate — приносит (если bonded). Перемещение в EVM = добровольный отказ от staking yield.

---

### Разрывы:

**[GAP-12.1] Одинаковый актив — разная функциональность**:
- Substrate ATLA: stakeable, governance-eligible
- EVM ATLA: usable in EVM dApps, not directly stakeable
- Same coin, different capabilities

**[GAP-12.2] Одинаковый баланс в UI — разные источники**:
- UI может показывать: "баланс: 1500 ATLA"
- Источник 1: Substrate AccountData = 500 ATLA (stakeable)
- Источник 2: EVM H160 balance = 1000 ATLA (EVM-only)
- User thinks: "у меня 1500, могу стейкать 1500"
- Reality: can stake only 500

**[GAP-12.3] Одинаковая транзакция "transfer" — разный контекст**:
- EVM transfer: moves H160 balance
- Substrate transfer: moves AccountData balance
- Cross-transfer (Frontier): converts between the two
- Same user action "transfer", three different on-chain results

---

## СВОДНАЯ ТАБЛИЦА РАЗРЫВОВ

| Gap ID | Тип разрыва | Действие | Severity | Ведёт к гипотезе |
|--------|-------------|----------|----------|-----------------|
| GAP-1.1 | same word, different meaning | updateTronBlock | High | H01, H02 |
| GAP-1.2 | same number, different finality | updateTronBlock | High | H01 |
| GAP-2.1 | same action, delayed effect | nominate | High | H11, H26 |
| GAP-2.2 | same user, different era exposure | nominate | High | H26 |
| GAP-3.1 | same unbond, different slash protection | unbond | High | H06, H24 |
| GAP-3.2 | same mechanism, different timeframes | unbond | High | H06 |
| GAP-4.1 | same event, different timing | slash | High | H06, H18 |
| GAP-4.2 | same window, different accessibility | challenge | Medium | H18 |
| GAP-5.1 | same success, different outcome | governance vote | Critical | H08, H32 |
| GAP-5.2 | same token, different voting power | governance | High | H17, H28 |
| GAP-6.1 | same deposit, different net amount | fee change | High | H05 |
| GAP-6.2 | 100% fee = technically valid | fee config | Critical | H05 |
| GAP-7.1 | same action, different authority | executeBatch | Critical | H03 |
| GAP-7.2 | success tx + partial failure | executeBatch | High | H03 |
| GAP-8.1 | same "paused", different lookup | pause | High | H12 |
| GAP-8.2 | same pause level, different layers | FULL pause | Medium | — |
| GAP-9.1 | same name, different address | registerContract | Critical | H27 |
| GAP-9.2 | registered ≠ valid contract | registerContract | High | H27 |
| GAP-10.1 | earned ≠ auto-received | reward claim | Medium | H07 |
| GAP-10.2 | pool claim ≠ member claim | pool rewards | Medium | H07, H15 |
| GAP-11.1 | same address, different code | upgrade | Critical | H04 |
| GAP-11.2 | same slot, different variable | upgrade | High | H13 |
| GAP-11.3 | same "authorized" — different trust | upgrade | Critical | H04 |
| GAP-12.1 | same asset, different capability | ATLA transfer | Medium | H14 |
| GAP-12.2 | same balance shown, different usability | UI balance | Medium | H14 |

---

## КРИТИЧЕСКИЕ ПАТТЕРНЫ

### Паттерн A: "Admin action = user harm с нулевым нарушением правил"
- updatePlatformFee(10000) ← valid
- registerContract("Bridge", attackerAddr) ← valid  
- upgradeTo(maliciousImpl) ← valid
- executeBatch + role escalation ← valid
Все 4 действия: SUPER_ADMIN-only, on-chain enforced, but catastrophically harmful for users.

### Паттерн B: "Governance vote = advisory, not binding"
- Vote passes on-chain
- Foundation decides whether/when/how to execute
- No force mechanism
- No timelock enforcement
- Same "democratic decision" = potentially dead letter

### Паттерн C: "Слэш — плавающий по времени"
- Detection ≠ Application (7-day gap)
- Application ≠ User awareness (no push)
- Nominator can exit in 72h gap
- Validator cannot exit in 21d gap
- Same slash event, radically different consequences per role

### Паттерн D: "TRON block number ≠ TRON state"
- lastProcessedTronBlock — только число
- Не верифицирует actual TRON transactions
- Не защищён от reorg
- Не защищён от malicious advance
- Oracle = trust anchor with no on-chain verification

---

*Фаза 4 завершена. Ожидаю отмашку на Фазу 5.*
