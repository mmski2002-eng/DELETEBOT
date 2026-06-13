# ФАЗА 9 — Приоритизация Находок
## Atleta Network — Mainnet Only

Источники: Фазы 1–8. Критерии: Confidence × Reachability × Impact × Actionability (сейчас vs при bridge deploy).

---

## TIER P0 — КРИТИЧНО: ДЕЙСТВОВАТЬ СЕЙЧАС

### P0-01: Одиночный EOA как SUPER_ADMIN без timelock
**Тип:** Structural / Operational  
**Severity:** Critical  
**Confidence:** CONFIRMED (on-chain verified)  
**Source:** S3, E6 (Phase 2), Phase 8 Kill Attempt — не убита

**Факты:**
- `0xB4349Fb7Fe240E24E8c5b2fF5caF4Cc265d38aF7` — EOA, не multisig (is_contract: false)
- SUPER_ADMIN = единственная роль с `upgradeTo()` доступом
- `_authorizeUpgrade`: `onlyRole(SUPER_ADMIN_ROLE)` — без timelock, без multisig
- Upgrade возможен за 1 транзакцию (~12 секунд)

**Threat model:**
- Compromised SUPER_ADMIN key → upgrade к malicious impl → drain всех funds → rollback impl
- Insider (SUPER_ADMIN holder) → silent upgrade → censorship / fund redirect
- Supply chain: devops machine compromise, phishing

**Kill attempt result:** НЕ УБИТА. EOA подтверждён on-chain. Нет code-level mitigations.

**Remediation:**
1. SUPER_ADMIN → Gnosis Safe (3-of-5 минимум)
2. TimelockController (48–72h delay) между Safe и PlatformController
3. Emit alert monitoring на `Upgraded()` event

**Почему P0:** Единственный private key контролирует весь upgrade path. Нет code guarantee. Любой сценарий компрометации = total system compromise.

---

### P0-02: Oracle EOA без резервного механизма и advance limit
**Тип:** Operational + Code Gap  
**Severity:** Critical (Operational) / High (Code)  
**Confidence:** HIGH (code gap probable, key security = unknown)  
**Source:** S2, E2 (Phase 2), Phase 8 Kill Attempt — выжила

**Факты:**
- ORACLE = `0x3Aa473E3818AAB6F5bC103936466e7BCf78e31E2` — одиночный EOA
- Баланс: ~111 ATLA (~439 дней runway при текущей частоте)
- `updateLastProcessedTronBlock` — monotonic, MAX_ADVANCE limit не обнаружен
- 100% mainnet транзакций = oracle updates (по данным Blockscout)

**Threat model:**
- Скомпрометированный ORACLE → `updateLastProcessedTronBlock(99999999)` → bridge watermark навсегда опережает TRON tip → все deposits orphaned
- Реверс невозможен без upgrade (lastProcessedTronBlock не уменьшается)
- Key runway = 439 дней: если не пополнять → oracle замирает (меньший риск, но ещё один SPF)

**Kill attempt result:** Условно выжила. MAX_ADVANCE неизвестен — требует source verification.

**Remediation:**
1. MAX_ADVANCE_PER_CALL = 1000 блоков (или 10x normal era rate) в `updateLastProcessedTronBlock`
2. ORACLE role → multi-oracle с консенсусом (2-of-3)
3. Rate limiting: max N updates per hour
4. Мониторинг: alert если advance > 2× expected rate

**Почему P0:** Единственная точка failure для всего TRON bridge. Advance = невозможно откатить без upgrade.

---

## TIER P1 — ВЫСОКИЙ ПРИОРИТЕТ: АРХИТЕКТУРНЫЕ РИСКИ

### P1-01: executeBatch — неограниченный arbitrary call от PlatformController
**Тип:** Access Control Design  
**Severity:** High (сейчас) / Critical (при bridge deploy)  
**Confidence:** HIGH (function confirmed) / CONDITIONAL (impact depends on downstream)  
**Source:** S1, AS1/DM1 (Phase 6), E4 (Phase 2)

**Факты:**
- `executeBatch(address[], bytes[], bool)` — SUPER_ADMIN вызывает любые contracts с msg.sender = PlatformController
- Нет whitelist targets, нет call validation
- При bridge deploy: если bridge авторизует `platformController address` как trusted caller → SUPER_ADMIN получает все bridge привилегии через executeBatch

**Kill attempt result:** Убита на текущем mainnet (нет downstream). Critical при bridge deploy.

**Remediation:**
1. Target whitelist в executeBatch: `require(approvedTargets[target])`
2. Function selector whitelist per target: `require(allowedSelectors[target][selector])`
3. Downstream contracts: НЕ использовать `msg.sender == platformControllerAddr` — только role-based auth

**Почему P1:** Сейчас — архитектурная мина. При bridge deploy без mitigation — критично.

---

### P1-02: Slash escape через withdraw + transfer (5-era window)
**Тип:** Economic / Protocol  
**Severity:** High  
**Confidence:** MEDIUM (mechanism confirmed в Substrate design; Atleta-specific version requires code verification)  
**Source:** S6, F07-A (Phase 5), Phase 8 Kill Attempt — пересмотрен механизм

**Факты:**
- Slash defer: 7 eras × 36h = 252h ≈ 10.5 дней
- Nominator unbond: 2 eras × 36h = 72h ≈ 3 дня
- Window: T+72h (withdraw) → T+252h (slash applied) = 5 eras для transfer
- Если nominator переводит ATLA на другой account в этом window → slash = 0 на опустевший account

**Kill attempt result:** Частично выжила. Механизм = unbond → withdraw → transfer, не unbond-only.

**Remediation:**
1. Slash к unlocking chunks + free balance после unbond: Substrate это делает, но только на SAME account. Transfer — code не блокирует.
2. Option A: увеличить BondingDuration (>SlashDeferDuration). Нереалистично (SlashDeferDuration = 252h уже большой).
3. Option B: ввести slash claim на любой account куда переведены средства в 7-дневном window (слишком complex).
4. Option C: принять как known tradeoff; документировать; добавить UI warning.

**Почему P1:** Broken incentive alignment. Sophisticated nominators escape slashes, naive — нет. Долгосрочный: централизация staking к тем кто мониторит.

---

### P1-03: Governance — off-chain execution без enforcement
**Тип:** Governance Design  
**Severity:** High  
**Confidence:** CONFIRMED (задокументировано)  
**Source:** S5, S7 (Phase 2), GAP-5.1 (Phase 4)

**Факты:**
- ATLETAgov pallet: voting on-chain, execution = BCSports Foundation off-chain
- Нет on-chain enforcement, нет timelock execution
- Foundation имеет effective voting power ≈ 20-40% (treasury + team vesting)
- Документация: "outcomes are implemented/executed by the BCSports Foundation"

**Kill attempt result:** Реклассифицирована. Задокументированный дизайн, не code bug. Governance risk.

**Remediation (рекомендательно):**
1. Для критических параметров (emission rate, fee caps): Governor + on-chain execution через TimelockController
2. Публичный execution log с timestamps: proposal → execution delay reasoning
3. Установить max delay: Passed proposal должен быть исполнен в X дней или получить публичное veto с обоснованием

**Почему P1:** Доверие к системе строится на governance. Если Foundation воспринимается как veto power → validator/nominator exit risk.

---

## TIER P2 — СРЕДНИЙ ПРИОРИТЕТ: ТРЕБУЮТ ВЕРИФИКАЦИИ

### P2-01: TRON reorg blindness — нет механизма откатить processed block
**Тип:** Bridge Design  
**Severity:** High (при bridge deploy)  
**Confidence:** MEDIUM (архитектурная проблема; мейннет TRON редко реоргизует)  
**Source:** CV1 (Phase 6), H01 (Phase 3), GAP-8.2 (Phase 4)

**Факты:**
- `lastProcessedTronBlock` = monotonic watermark без reorg detection
- TRON block → Atleta settlement: если TRON реорганизуется после settlement → double-mint или lost-burn возможны
- Нет `cancelSettlement` / `rollbackBlock` функции

**Remediation:**
1. Минимальный confirmation threshold: обрабатывать TRON блок только после N подтверждений (N ≥ 20)
2. Challenge period: settlement = pending в течение reorg window, finalized после
3. Oracle должен отправлять TRON block hash + parent hash для cross-verification

**Почему P2:** TRON реоргует редко, но при bridge с высоким volume — реальный риск.

---

### P2-02: Nomination timing — unexplained slash exposure при смене nominations
**Тип:** UX / Documentation  
**Severity:** Medium  
**Confidence:** HIGH (Substrate behavior confirmed)  
**Source:** S8 (Phase 7), Phase 8 — убита как exploit, выжила как UX risk

**Факты:**
- Номинации effective с СЛЕДУЮЩЕЙ эры (~36h задержка)
- Slash при смене nominations в текущей эре: старые номинации ещё активны для slash purposes
- UI: обычно не предупреждает об остаточном exposure

**Remediation:**
1. UI: показывать "Текущий slash exposure: [A, B, C] | Новые номинации (с эры N+1): [B, C, D]"
2. Документация: явный warning о era-delayed semantics
3. Cooldown warning: "После смены nominations остаётся X часов slash risk для убранных валидаторов"

**Почему P2:** Не exploit, но реальная пользовательская потеря средств из-за UX gap.

---

### P2-03: Pool Master (root) единоличный контроль над pool lifecycle
**Тип:** Nomination Pool Governance  
**Severity:** Medium  
**Confidence:** HIGH (Substrate pools design)  
**Source:** H09, H28 (Phase 3), GAP-11.2 (Phase 4)

**Факты:**
- Pool root (Master) может: изменить все роли, заморозить pool, изменить commission
- Pool members: no recourse если root hostile
- 512 pools на mainnet потенциально

**Remediation:**
1. Документация: pool selection requires trust in pool root
2. UI: показывать pool root address; warning если root = единственный EOA (не multisig)
3. Protections: commission change notice period (Substrate поддерживает)

---

## TIER P3 — НИЗКИЙ ПРИОРИТЕТ / INFORMATIONAL

### P3-01: Mystery ERC-20 — неверифицированный контракт, 20B supply, 1 holder
**Тип:** Ecosystem Risk  
**Severity:** Low (сейчас) / Unknown  
**Address:** `0x18888DFFA40A278C44D2a2cC58f1f6C97C3fD53c`  
**Source:** Phase 1 on-chain discovery

**Факты:**
- 20,000,000,000 supply, 7 decimals, 1 holder, unverified bytecode
- Потенциально: pre-deploy test; или scam token; или unreleased bridge token

**Action:** Verify что это, публично раскрыть или удалить с explorer.

---

### P3-02: Reward expiry — 84 eras cap без explicit UI warning
**Тип:** UX / Economic  
**Severity:** Low  
**Source:** S10 (Phase 2), Phase 1 system model

**Факты:** Награды сгорают если не клеймить > 84 eras (~3024h = ~126 дней). UI может не предупреждать.

**Action:** UI reminder при приближении к expiry window.

---

### P3-03: Era in blocks — не фиксировано, зависит от block time
**Тип:** Economic Design  
**Severity:** Low  
**Source:** H19 (Phase 3)

**Факты:** Если block time увеличивается (congestion, BABE issues) → реальное время эры растёт → reward distribution замедляется. Inflation schedule в токенах/блок может дрейфовать.

---

## TIER P4 — PRE-DEPLOY: КРИТИЧНО ПРИ BRIDGE ЗАПУСКЕ

### P4-01: Bridge fee architecture — необходима верификация стороны применения
**При deploy проверить:**
- Fee применяется на TRON стороне или Atleta?
- Snapshot fee at deposit или at settlement?
- Max fee cap в bridge settlement logic?
**Если Atleta-side + no snapshot:** P4-01 → P0 (Two Treasury Keys attack becomes live)

### P4-02: Bridge claim window + oracle pause behavior
**При deploy проверить:**
- Есть ли time-sensitive claim window?
- Имеет ли `updateLastProcessedTronBlock` `whenNotPaused` modifier?
- TRON-side: есть ли auto-refund при Atleta timeout?
**Если claim window + oracle продолжает во время pause:** P4-02 → P1

### P4-03: Downstream contract authorization pattern
**При deploy проверить:**
- Bridge contract авторизует calls: `msg.sender == platformController` или `hasRole(X, msg.sender)`?
- Если address-based → executeBatch → full privilege escalation → P4-03 → P0 (Critical)

---

## ИТОГОВЫЙ РЕЕСТР НАХОДОК

| ID | Название | Tier | Severity | Confidence | Actionable |
|----|----------|------|----------|-----------|------------|
| P0-01 | SUPER_ADMIN = 1 EOA, no timelock | P0 | Critical | CONFIRMED | Сейчас |
| P0-02 | Oracle EOA, no max advance limit | P0 | Critical | HIGH | Сейчас |
| P1-01 | executeBatch: arbitrary call, no whitelist | P1 | High→Critical | HIGH | Сейчас + bridge |
| P1-02 | Slash escape: withdraw+transfer в 5-era window | P1 | High | MEDIUM | Сейчас |
| P1-03 | Governance: off-chain execution, no enforcement | P1 | High | CONFIRMED | Сейчас |
| P2-01 | TRON reorg blindness | P2 | High | MEDIUM | Bridge design |
| P2-02 | Nomination timing UX gap | P2 | Medium | HIGH | UX/docs |
| P2-03 | Pool root single point of control | P2 | Medium | HIGH | Docs/UI |
| P3-01 | Mystery ERC-20 unverified | P3 | Low | — | Investigate |
| P3-02 | Reward expiry: no UI warning | P3 | Low | HIGH | UX |
| P3-03 | Era duration drift | P3 | Low | LOW | Monitor |
| P4-01 | Bridge fee: side of application unknown | P4 | Critical (conditional) | — | At bridge deploy |
| P4-02 | Pause + claim window interaction | P4 | High (conditional) | — | At bridge deploy |
| P4-03 | Bridge downstream auth pattern | P4 | Critical (conditional) | — | At bridge deploy |

---

## КРИТИЧЕСКИЙ ПУТЬ (топ-3 для немедленных действий)

```
1. P0-01: SUPER_ADMIN EOA → Gnosis Safe + TimelockController
   Усилие: Medium | Срок: до bridge deploy
   
2. P0-02: Oracle EOA → добавить MAX_ADVANCE_PER_CALL + multi-oracle
   Усилие: Low (code) + Medium (ops) | Срок: до bridge deploy
   
3. P1-01: executeBatch → target whitelist + function selector whitelist
   Усилие: Low (code) | Срок: до bridge deploy
```

Всё остальное может идти параллельно с меньшим приоритетом.

---

*Фаза 9 завершена. Жду отмашку на Фазу 10.*
