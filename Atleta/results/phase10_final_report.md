# ФИНАЛЬНЫЙ ОТЧЁТ ПО БЕЗОПАСНОСТИ
## Atleta Network — Security Audit
## Mainnet Only | Методология: 10-фазный структурный анализ

---

## EXECUTIVE SUMMARY

Atleta Network — Substrate-based EVM-compatible L1, Chain ID 2340, sports industry focus. Анализ проводился исключительно по mainnet данным. Тестнет не анализировался.

**Общая оценка:** Система содержит **2 критических структурных уязвимости** (P0), **3 высокоприоритетных архитектурных риска** (P1), и **3 условно-критических проблемы** (P4) которые активируются при деплое bridge.

**Главный вывод:** Atleta Network на текущем этапе (bridge "Coming Soon") имеет ограниченную attack surface. Однако централизация ключевых привилегий в одиночных EOA создаёт **single points of failure** уровня total system compromise. Эти риски должны быть устранены **до деплоя bridge contracts**.

---

## КОНТЕКСТ И ОБЛАСТЬ АНАЛИЗА

**Chain:** Atleta Network Mainnet  
**Chain ID:** 2340  
**RPC:** `wss://rpc.mainnet.atleta.network/`  
**Explorer:** `blockscout.atleta.network`  
**Блоков на момент анализа:** ~4,469,075  
**Транзакций:** ~1,144,721  
**Уникальных адресов:** ~7,202  

**Ключевые контракты:**

| Контракт | Адрес | Статус |
|----------|-------|--------|
| PlatformController (proxy) | `0x0E534a16e544752B101cEf8c486e1D7A2f7Fa1cf` | Verified |
| PlatformController (impl) | `0xf42CC99de73Ad7e1f41e462341dC7D53d7290A6F` | Verified |
| SUPER_ADMIN / Deployer EOA | `0xB4349Fb7Fe240E24E8c5b2fF5caF4Cc265d38aF7` | EOA, 684K ATLA |
| ORACLE EOA | `0x3Aa473E3818AAB6F5bC103936466e7BCf78e31E2` | EOA, ~111 ATLA |
| Mystery ERC-20 | `0x18888DFFA40A278C44D2a2cC58f1f6C97C3fD53c` | Unverified |

**Методология:** 10 фаз: System Model → System Laws → Impossible States → Semantic Gaps → Normal Function Abuse → Abuse Frameworks → Attack Stories → Kill Attempts → Prioritization → Final Report.

---

## АРХИТЕКТУРНЫЙ ОБЗОР

**Substrate layer:** BABE block production + GRANDPA finality, NPoS consensus.
- Validators: 256 active / 1000 candidates, stake 75K–7.5M ATLA, unbond 21 дней
- Nominators: min 10 ATLA, unbond 72h, до 16 валидаторов
- Eras: 36h (6 сессий × 6h), slash defer 7 eras (252h)
- Slashing: 4 уровня (0.1% / 1% / 10% / 100%), 7-дневный escrow
- Governance: ATLETAgov pallet, 21-day voting, off-chain execution by BCSports Foundation

**EVM layer (Frontier):**
- PlatformController: UUPS proxy (EIP-1967), Solidity 0.8.30, OZ AccessControl
- Роли: SUPER_ADMIN, SUPPORT_ADMIN, MODERATOR, ORACLE, BURNER
- Pause levels: NONE / TRADING_ONLY / CRITICAL / FULL
- Bridge: TRON↔Atleta через oracle (lastProcessedTronBlock watermark)
- executeBatch: SUPER_ADMIN может вызвать любой контракт с msg.sender = PlatformController

**Token:** 3B ATLA total, 18 decimals, ~4% инфляция, 250M ATLA/год consensus emissions (72 месяца).

---

## НАХОДКИ

### [P0-01] SUPER_ADMIN — одиночный EOA без timelock и multisig

**Severity:** Critical  
**Confidence:** CONFIRMED (on-chain verified)  
**Affected:** PlatformController upgrade path, все privileged functions  

**Root Cause:**
`_authorizeUpgrade` в PlatformController требует только `SUPER_ADMIN_ROLE`. SUPER_ADMIN = EOA `0xB4349Fb7Fe240E24E8c5b2fF5caF4Cc265d38aF7` (подтверждено: is_contract = false, no bytecode). Нет TimelockController. Нет multisig. Нет governance approval requirement.

**Attack Path:**
1. Компрометация SUPER_ADMIN private key (phishing / machine compromise / insider)
2. Deploy malicious implementation contract (любой UUPS-compatible bytecode)
3. `upgradeTo(maliciousImpl)` — 1 транзакция, ~12 секунд
4. Вызов любой функции через malicious impl → drain / censorship / state corruption
5. Опционально: `upgradeTo(originalImpl)` → сокрытие следов

**Impact:**  
Полный контроль над PlatformController. Redirect всех bridge funds. Arbitrary state manipulation. Permanent system compromise.

**Proof of Concept:**
```bash
# Verify EOA status:
cast code 0xB4349Fb7Fe240E24E8c5b2fF5caF4Cc265d38aF7 --rpc-url https://rpc.mainnet.atleta.network
# Returns: 0x (no bytecode = EOA confirmed)

# Fork simulation:
# 1. anvil --fork-url https://rpc.mainnet.atleta.network
# 2. cast send 0x0E534a... "upgradeTo(address)" <maliciousImpl> --from 0xB4349...
# → No revert. Upgrade succeeds instantly.
```

**Remediation:**
```
1. Migrate SUPER_ADMIN role to Gnosis Safe (3-of-5 minimum signers)
2. Deploy TimelockController (min 48h delay) as executor
3. Grant SUPER_ADMIN_ROLE to TimelockController address
4. Revoke SUPER_ADMIN_ROLE from current EOA
5. Add on-chain monitoring: alert on Upgraded() event
```

**Assumptions:** EOA is confirmed non-multisig. No TimelockController found in ecosystem.  
**Confidence Level:** CRITICAL / CONFIRMED

---

### [P0-02] ORACLE EOA — одиночная точка отказа, отсутствие advance limit

**Severity:** Critical  
**Confidence:** HIGH (key type confirmed, MAX_ADVANCE requires source verification)  
**Affected:** TRON↔Atleta bridge watermark, всё bridge settlement  

**Root Cause:**
ORACLE = одиночный EOA `0x3Aa473E3818AAB6F5bC103936466e7BCf78e31E2`. Функция `updateLastProcessedTronBlock(uint256)` принимает новое значение без проверки максимально допустимого advance. Watermark monotonic — уменьшение невозможно без upgrade. Runway: ~439 дней при текущей частоте (~0.25 ATLA/день).

**Attack Path:**
1. Компрометация ORACLE private key (hot wallet pattern: частые малые транзакции)
2. Вызов: `updateLastProcessedTronBlock(99999999)`
3. Emit: `OracleBlockUpdated(99999999)` — выглядит как нормальный oracle update
4. lastProcessedTronBlock = 99,999,999; реальный TRON tip ≈ 83,400,000
5. Bridge settlement: все deposits в блоках 83.4M–99M → orphaned (range "already processed" или "beyond tip")
6. Recovery: невозможна без emergency upgrade (reset function не существует)
7. Параллельно: SUPER_ADMIN revokes ORACLE role, но damage permanent — watermark не откатить

**Impact:**  
Permanent freeze всего TRON bridge. Все in-flight deposits: unclaimable. Future deposits: no settlement возможен пока lastProcessedTronBlock > TRON tip (~578 дней TRON-активности).

**Proof of Concept:**
```javascript
// Fork test (anvil):
const oracle = await impersonateAccount("0x3Aa473E3818AAB6F5bC103936466e7BCf78e31E2");
await platformController.connect(oracle).updateLastProcessedTronBlock(99999999);
const watermark = await platformController.lastProcessedTronBlock();
console.log(watermark); // 99999999 — no revert if no MAX_ADVANCE check
```

**Remediation:**
```solidity
// Add to updateLastProcessedTronBlock:
uint256 constant MAX_ADVANCE_PER_UPDATE = 10_000; // ~1000x normal rate

function updateLastProcessedTronBlock(uint256 newBlock) external onlyRole(ORACLE_ROLE) {
    require(newBlock > lastProcessedTronBlock, "BlockNotNewer");
    require(newBlock - lastProcessedTronBlock <= MAX_ADVANCE_PER_UPDATE, "AdvanceTooLarge"); // ADD THIS
    lastProcessedTronBlock = newBlock;
    emit OracleBlockUpdated(newBlock);
}
```
```
Operational:
- Migrate ORACLE role to multi-oracle system (2-of-3 consensus)
- Hardware wallet или MPC key management
- Alert: если advance > 2x expected rate per session
- Ensure ORACLE balance monitored: refill before expiry
```

**Assumptions:** MAX_ADVANCE limit не найден в ABI / доступных описаниях. Требует верификации полного source.  
**Confidence Level:** HIGH / Code gap highly probable

---

### [P1-01] executeBatch — произвольные вызовы без whitelist targets

**Severity:** High (сейчас) → Critical (при bridge deploy)  
**Confidence:** HIGH (function confirmed, impact conditional on downstream auth)  
**Affected:** PlatformController.executeBatch, все future downstream contracts  

**Root Cause:**
`executeBatch(address[] targets, bytes[] data, bool requireSuccess)` выполняет произвольные вызовы с `msg.sender = address(PlatformController)`. Нет проверки: target whitelist, function selector whitelist, value limits.

Если downstream contracts (bridge, vesting, rewards) авторизуют вызовы через `msg.sender == platformControllerAddr` — SUPER_ADMIN получает все их привилегии через executeBatch без явного grant.

**Attack Path:**
```
SUPER_ADMIN → executeBatch(
    [bridgeContract],
    [abi.encodeWithSignature("grantRole(bytes32,address)", WITHDRAWER_ROLE, attackerAddr)],
    true
)
→ bridge.grantRole() с msg.sender = platformController
→ если bridge авторизует platformController address → роль выдана
→ attacker имеет WITHDRAWER_ROLE в bridge
```

**Impact:**  
Полный контроль над bridge funds через двухшаговую эскалацию привилегий.

**Remediation:**
```solidity
// Option A: target whitelist
mapping(address => bool) public approvedBatchTargets;

function executeBatch(...) external onlyRole(SUPER_ADMIN_ROLE) {
    for (uint i = 0; i < targets.length; i++) {
        require(approvedBatchTargets[targets[i]], "TargetNotApproved");
        // ...
    }
}

// Option B: selector whitelist per target
mapping(address => mapping(bytes4 => bool)) public approvedSelectors;
```
```
Architectural: downstream contracts должны использовать hasRole(ROLE, msg.sender),
NOT msg.sender == platformControllerAddr.
PlatformController address НЕ должен получать roles в downstream contracts.
```

**Confidence Level:** HIGH (code pattern confirmed; impact requires downstream audit)

---

### [P1-02] Slash escape через unbond → withdraw → transfer (5-era window)

**Severity:** High  
**Confidence:** MEDIUM (mechanism follows Substrate design; Atleta-specific slash implementation requires runtime source verification)  
**Affected:** pallet-staking, NPoS slash incentive model  

**Root Cause:**
- Slash defer: 7 eras × 36h = 252h
- Nominator unbond: 2 eras × 36h = 72h → withdraw_unbonded() available
- После withdrawal: ATLA переходят в free balance
- Slash применяется к current account state — если средства переведены на другой account до slash application → `T::Currency::slash(emptyAccount, amount)` = 0

**Attack Path:**
1. Nominator N мониторит on-chain slash/offence events (публично видны)
2. Замечает `OffenceReported(ValidatorA, severity=100%)` — block T
3. Вызывает `unbond(fullStake)` — block T+1
4. Ждёт 72h (2 eras) → `withdraw_unbonded()` — ATLA теперь free balance
5. Вызывает `transfer(safeAddr, balance)` — до era T+7 (до slash application)
6. Era T+7: slash applied to original account → balance = 0 → slash amount = 0
7. N сохраняет 100% stake на safeAddr

**Impact:**  
Broken incentive alignment: sophisticated nominators (bots/whales) escape slashes, naive — нет. Long-term: staking power концентрируется у тех кто мониторит on-chain events.

**Remediation:**
```
Полное устранение: сложно без изменения Substrate runtime.
Практические меры:
1. Увеличить UI прозрачность: показывать slash exposure для pending период
2. Документировать known tradeoff публично
3. Рассмотреть slash freeze: запрет transfer во время slash escrow window
   (требует custom pallet-staking modification)
```

**Confidence Level:** MEDIUM / Mechanism follows Substrate design, transfer = key step

---

### [P1-03] Governance — off-chain execution без on-chain enforcement

**Severity:** High  
**Confidence:** CONFIRMED (задокументировано)  
**Affected:** ATLETAgov pallet, treasury, all governance-controlled parameters  

**Root Cause:**
ATLETAgov пишет decisions on-chain. Execution — "implemented by BCSports Foundation" off-chain. Нет TimelockController-executor. Нет on-chain enforcement. Foundation имеет effective veto.

**Conflict of Interest Path:**
```
Proposal A: снизить Foundation вознаграждение → Passed → Foundation delays indefinitely
Proposal B: вывести treasury к community → Passed → "technical review required" → never executed
Counter-proposal by Foundation-aligned validators → Passed → executed immediately
```

On-chain: все proposals имеют status "Passed." Reality: selective execution.

**Impact:**  
Governance legitimacy риск. Treasury capture. Progressive power concentration.

**Remediation:**
```
Critical path:
1. Для параметров с on-chain effect (fees, emission rate):
   → Governor contract + TimelockController + on-chain execution
2. Публичный SLA: Passed proposal исполняется в 7 дней или Foundation публикует
   обоснование задержки с timeline
3. Foundation voting power disclosure: публичная аттестация ATLA holdings
```

**Confidence Level:** CONFIRMED / Documented design, not speculation

---

### [P2-01] TRON reorg blindness — нет protection от double-settlement

**Severity:** High (при bridge activate)  
**Confidence:** MEDIUM  
**Affected:** Bridge settlement, conservation invariant  

**Root Cause:**
Oracle обновляет lastProcessedTronBlock на основе TRON block numbers. Нет block hash verification. Если TRON реорганизуется после oracle report → транзакция "processed" может перестать существовать в TRON canonical chain. Atleta-side: settlement complete. TRON-side: deposit orphaned или reverted.

**Impact:**  
Double-mint (при reorg + re-settlement) или lost funds (settlement on Atleta, no deposit on TRON).

**Remediation:**
```
1. Minimum TRON confirmation threshold: N ≥ 20 блоков перед oracle report
2. Oracle включает TRON block hash в attestation
3. On-chain verification: store и verify parent_hash chain
4. Challenge window: settlement finalized только после reorg-safe period
```

---

### [P2-02] Nomination timing — slash exposure при смене nominations

**Severity:** Medium  
**Confidence:** HIGH (Substrate design)  
**Affected:** Nominators, UI/UX  

**Root Cause:**
Nomination changes effective с СЛЕДУЮЩЕЙ эры (~36h). Если slash происходит в текущей эре — старые nominations ещё активны для slash purposes. UI обычно не отображает это различие.

**Impact:**  
Пользователь видит "убрал валидатора" → теряет stake за него в той же эре.

**Remediation:**
```
UI: показывать dual state:
"Активный exposure (до эры N+1): [A, B, C]"
"Новые nominations (с эры N+1): [B, C, D]"
Документация: явный warning о era-delayed semantics
```

---

### [P2-03] Pool root — полный единоличный контроль без member recourse

**Severity:** Medium  
**Confidence:** HIGH (Substrate pools design)  
**Affected:** Nomination pools, pool members  

**Root Cause:**
Pool root (Master) может изменить commission, заменить все роли, заморозить pool. Pool members не имеют mechanism против hostile root кроме unbonding (с задержкой).

**Remediation:**
```
UI: показывать pool root address + is_multisig indicator
Документация: "выбор pool = доверие root address"
Consider: commission change notice period enforcement
```

---

## УСЛОВНЫЕ НАХОДКИ (при деплое bridge)

### [P4-01] Bridge fee architecture — неизвестная сторона применения

**Если fee применяется Atleta-side + нет snapshot at deposit time:**  
→ SUPER_ADMIN может redirect 100% любого deposit через `updatePlatformFee(10000)` + `updateTreasuryWallet(attackerAddr)` в одном блоке.  
**Severity при подтверждении:** Critical  
**Verify при bridge deploy:** Какой контракт берёт fee? TRON-side или Atleta-side? Snapshot?

### [P4-02] Bridge pause + claim window interaction

**Если bridge имеет time-sensitive claim window + oracle продолжает обновляться во время pause:**  
→ Emergency pause → deposits expiry → permanent fund lock без exploit.  
**Severity при подтверждении:** High  
**Verify при bridge deploy:** Есть ли claim window? `whenNotPaused` на oracle update?

### [P4-03] Downstream contract authorization pattern

**Если downstream contracts используют `msg.sender == platformControllerAddr` для auth:**  
→ executeBatch = full privilege escalation в bridge/vesting/rewards.  
**Severity при подтверждении:** Critical  
**Verify при bridge deploy:** Auth pattern каждого контракта в экосистеме.

---

## МАТРИЦА РИСКОВ

```
IMPACT
  ^
C |  [P0-02]  [P0-01]  [P4-01*] [P4-03*]
  |           [P1-01]
H |  [P2-01]  [P1-02]  [P1-03]  [P4-02*]
  |
M |  [P2-02]  [P2-03]
  |
L |  [P3-01]  [P3-02]  [P3-03]
  +------------------------------------> REACHABILITY
      Low      Medium    High

* При bridge deploy
```

---

## ПРИОРИТЕТНЫЙ ПЛАН ДЕЙСТВИЙ

### Фаза 1 — До Bridge Deploy (ОБЯЗАТЕЛЬНО)

| Приоритет | Действие | Срок |
|-----------|----------|------|
| 1 | SUPER_ADMIN EOA → Gnosis Safe (3-of-5) + TimelockController (48h) | Немедленно |
| 2 | ORACLE → max_advance_per_call limit в коде + multi-oracle архитектура | Немедленно |
| 3 | executeBatch → target whitelist + selector whitelist | До bridge deploy |
| 4 | Аудит downstream contracts на auth pattern | До bridge deploy |

### Фаза 2 — При Bridge Deploy (ОБЯЗАТЕЛЬНО)

| Приоритет | Действие |
|-----------|----------|
| 5 | Верифицировать: fee side (TRON vs Atleta), snapshot, max fee cap |
| 6 | Верифицировать: claim window existence + oracle pause behavior |
| 7 | Bridge contract: role-based auth (не address-based) |
| 8 | TRON confirmation threshold ≥ 20 блоков |

### Фаза 3 — Ongoing Improvements

| Приоритет | Действие |
|-----------|----------|
| 9 | Governance: on-chain execution для критических параметров |
| 10 | UI: nomination timing warning, dual exposure display |
| 11 | UI: pool root disclosure |
| 12 | Mystery ERC-20 `0x18888D...`: identify и публично раскрыть |

---

## КЛЮЧЕВЫЕ МЕТРИКИ БЕЗОПАСНОСТИ

| Метрика | Текущее | Целевое |
|---------|---------|---------|
| SUPER_ADMIN signers | 1 (EOA) | ≥3 (multisig) |
| ORACLE redundancy | 1 EOA | ≥2 (multi-oracle) |
| Upgrade timelock | 0 секунд | ≥48 часов |
| Bridge confirmation threshold | Unknown | ≥20 TRON блоков |
| On-chain governance execution | 0% | 100% для on-chain parameters |
| executeBatch target whitelist | No | Yes |

---

## ОТКРЫТЫЕ ВОПРОСЫ

Для полного закрытия аудита необходимо:

1. **Полный source** `updateLastProcessedTronBlock` — есть ли MAX_ADVANCE limit?
2. **Bridge architecture** — fee application side (TRON vs Atleta)?
3. **ORACLE key security** — hot wallet / hardware / MPC?
4. **Mystery ERC-20** `0x18888D...` — что это, кому принадлежит?
5. **Governance history** — были ли Passed proposals не исполнены?
6. **Bridge claim window** — существует ли? Какой duration?
7. **Downstream contracts** — auth pattern для PlatformController caller?

---

## ЗАКЛЮЧЕНИЕ

Atleta Network демонстрирует **грамотную техническую базу** (Substrate + Frontier, OpenZeppelin, verified contracts) с **критическими операционными слабостями** в управлении ключами.

**Главный риск:** Не сложный exploit — а компрометация одного private key. SUPER_ADMIN EOA = ключ от всей системы. Одна скомпрометированная машина, один phishing, один insider — total system compromise.

**Bridge deploy без исправления P0-01 и P0-02 — недопустим.**

Система готова к аудиту bridge contracts как только они будут задеплоены. P4 находки должны быть верифицированы до открытия bridge для публичного использования.

---

*Аудит завершён. Фазы 1–10 выполнены.*  
*Результаты: `C:\DELETEBOT\Atleta\results\`*

| Файл | Фаза |
|------|------|
| phase1_system_model.md | Системная модель |
| phase2_system_laws.md | Законы системы (20 законов) |
| phase3_impossible_valid_states.md | Невозможные состояния (32 гипотезы) |
| phase4_semantic_gaps.md | Семантические разрывы (25 gaps) |
| phase5_normal_function_abuse.md | Злоупотребление функциями (14 функций, 24 комбинации) |
| phase6_abuse_frameworks.md | Фреймворки злоупотреблений (10 frameworks) |
| phase7_attack_stories.md | Attack stories (8 историй) |
| phase8_kill_attempts.md | Попытки опровержения |
| phase9_prioritization.md | Приоритизация (14 находок) |
| phase10_final_report.md | Финальный отчёт |
