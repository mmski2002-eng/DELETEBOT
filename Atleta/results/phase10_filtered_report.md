# ОТФИЛЬТРОВАННЫЙ РЕЕСТР НАХОДОК
## Atleta Network — только находки без требований к компрометации доверенных сторон

**Правило фильтрации:** Если эксплуатация требует злого умысла или утечки ключа у: admin / owner / governance / oracle-оператора / deployer / честного большинства валидаторов — находка **невалидна** как уязвимость (centralization risk, не баг).

---

## ОТФИЛЬТРОВАНО (невалидны по правилу)

| ID | Название | Причина отклонения |
|----|----------|-------------------|
| P0-01 | SUPER_ADMIN EOA без timelock | Требует компрометации admin/upgrader → доверенный |
| P0-02 | Oracle advance attack | Требует компрометации oracle-оператора → доверенный |
| P1-01 | executeBatch arbitrary call | Требует злого умысла SUPER_ADMIN → доверенный |
| P1-03 | Governance selective execution | Требует злого умысла Foundation/governance → доверенный |
| P4-01 | 100% fee + treasury redirect | Требует злого умысла SUPER_ADMIN → доверенный |
| P4-03 | Downstream auth pattern (executeBatch escalation) | Требует злого умысла SUPER_ADMIN → доверенный |

---

## ВЫЖИВШИЕ НАХОДКИ

### [F-01] Slash escape через unbond → withdraw → transfer
**Severity:** High  
**Confidence:** Medium  
**Требует ли доверенную сторону:** Нет. Атакует обычный номинатор (adversarial participant).

**Суть:**  
Slash отложен на 7 eras (252h). Номинатор unbonds → через 72h (2 eras) вызывает withdraw_unbonded() → переводит ATLA на другой account → к эре применения slash (252h) исходный account пуст → slash = 0.

**Механизм:**  
`unbond()` → `withdraw_unbonded()` (T+72h) → `transfer(safeAddr, balance)` (до T+252h) → slash applied at T+252h → account balance = 0.

**Affected:** pallet-staking, NPoS slash incentive alignment  
**Impact:** Sophisticated nominators систематически избегают slash; naive — нет. Incentive model сломан для мониторящих участников.

**Remediation:**
```
Верифицировать в runtime slashing.rs:
- Применяется ли slash к free balance после withdraw_unbonded?
- Если нет → slash_defer_duration должен быть ≤ bonding_duration (сейчас наоборот)

Вариант: ввести slash lien на аккаунт (запрет transfer) на период slash escrow.
Или: slash рассчитывается от exposure snapshot (stored amount), применяется как debt
независимо от текущего баланса.
```

---

### [F-02] Pause + oracle clock → expiry in-flight deposits (при bridge deploy)
**Severity:** High (conditional)  
**Confidence:** Medium  
**Требует ли доверенную сторону:** Нет. Оба актора (admin, oracle) действуют честно и корректно.

**Суть:**  
Admin честно паузирует bridge (emergency). Oracle честно продолжает обновлять lastProcessedTronBlock (следует протоколу). Если bridge settlement имеет time-sensitive claim window привязанную к oracle watermark или block.timestamp — claim window истекает во время pause. User получает 0, хотя deposit валиден.

**Interaction:**
```
User deposits TRON at block T
Admin pauses bridge (legitimate emergency action)
Oracle continues advancing lastProcessedTronBlock
Claim window expires (bridge's own timer)
Admin unpauses
User calls claim → revert: ClaimWindowExpired
TRON-side: no automatic refund
→ User funds permanently locked
```

**Условие активации:**  
Bridge contract должен иметь time-sensitive claim window. Требует верификации при деплое.

**Remediation:**
```
1. whenNotPaused на updateLastProcessedTronBlock — oracle не обновляет watermark во время pause
   (timer не идёт пока bridge стоит)
2. Или: claim window считается от block.timestamp когда bridge был unpaused, не от deposit time
3. TRON-side: auto-refund mechanism при timeout
```

---

### [F-03] TRON reorg blindness — нет защиты от double-settlement (при bridge deploy)
**Severity:** High (conditional)  
**Confidence:** Medium  
**Требует ли доверенную сторону:** Нет. TRON network может реорганизоваться независимо от oracle behavior. Oracle действует честно, просто TRON canonical chain меняется.

**Суть:**  
Oracle честно докладывает TRON block N → settlement на Atleta выполнен. TRON реорганизуется — deposit transaction исчезает из canonical chain. Atleta: settlement confirmed. TRON: deposit never happened.

**Impact при подтверждении:** Double-mint или lost funds — в зависимости от направления bridge.

**Remediation:**
```
1. Minimum confirmation depth: обрабатывать TRON блоки только после N ≥ 20 подтверждений
2. Oracle attestation включает TRON block hash + parent_hash chain
3. Challenge period: settlement finalized только после reorg-safe window
```

---

### [F-04] Nomination timing — slash exposure при смене nominations в текущей эре
**Severity:** Medium  
**Confidence:** High (Substrate confirmed behavior)  
**Требует ли доверенную сторону:** Нет. Slash может происходить случайно (validator offline, bug). Пользователь теряет средства из-за UX gap, не из-за злого умысла.

**Суть:**  
Смена nominations effective с СЛЕДУЮЩЕЙ эры. Если slash в текущей эре — старые nominations активны для slash. UI не предупреждает о residual exposure.

**Impact:** Пользователь убрал валидатора из UI → уверен что защищён → теряет stake.

**Remediation:**
```
UI: dual state display:
"Slash exposure ДО эры N+1: [A, B, C]"
"Nominations С эры N+1: [B, C, D]"
Документация: явный warning
```

---

### [F-05] Pool root — полный контроль над members без protocol-level protection
**Severity:** Medium  
**Confidence:** High  
**Требует ли доверенную сторону:** Нет. Pool root — обычный пользователь (не system admin). Members, присоединившиеся к pool, не получают от протокола защиты от hostile pool root.

**Суть:**  
Pool root может изменить commission до 100%, заменить все роли, заморозить pool. Members вынуждены ждать unbonding (с задержкой) как единственный recourse.

**Примечание:** Pool root ≠ protocol admin. Это пользователь, которому другие пользователи доверяют. Протокол не гарантирует защиту от hostile root.

**Remediation:**
```
UI: pool root address + is_multisig indicator
Документация: "join pool = trust pool root"
Commission change: enforce notice period (Substrate поддерживает max_commission_change_rate)
```

---

### [F-06] Mystery ERC-20 — неверифицированный контракт, 20B supply, 1 holder
**Severity:** Low / Informational  
**Confidence:** —  
**Address:** `0x18888DFFA40A278C44D2a2cC58f1f6C97C3fD53c`

**Суть:**  
Контракт задеплоен на mainnet, не верифицирован на Blockscout, 1 holder, 20B supply с 7 decimals. Непонятно: pre-deploy bridge token, scam, internal test?

**Action:** Идентифицировать публично. Если test — отозвать или задокументировать. Если bridge token — верифицировать source.

---

### [F-07] Reward expiry — нет UI warning до expiry window
**Severity:** Low  
**Confidence:** High  

**Суть:** Награды сгорают после 84 eras (~126 дней). UI не предупреждает о приближении deadline.

**Remediation:** Reminder при ≤ 14 eras до expiry.

---

## ИТОГОВЫЙ РЕЕСТР ВАЛИДНЫХ НАХОДОК

| ID | Название | Severity | Условие | Доверенная сторона? |
|----|----------|----------|---------|-------------------|
| F-01 | Slash escape (withdraw+transfer) | High | Сейчас | Нет |
| F-02 | Pause + oracle clock → deposit expiry | High | Bridge deploy | Нет |
| F-03 | TRON reorg blindness | High | Bridge deploy | Нет |
| F-04 | Nomination timing UX gap | Medium | Сейчас | Нет |
| F-05 | Pool root hostile actions | Medium | Сейчас | Нет (user, not admin) |
| F-06 | Mystery ERC-20 unverified | Low | Investigate | — |
| F-07 | Reward expiry no warning | Low | Сейчас | Нет |

**Отфильтровано (centralization risk):** P0-01, P0-02, P1-01, P1-03, P4-01, P4-03

---

*Примечание по отфильтрованным:* P0-01 (EOA admin) и P0-02 (single oracle) остаются centralization risks — реальные операционные слабости, но не security bugs в модели с честными операторами. Рекомендуются к устранению в рамках security hardening, не в рамках bug bounty.
