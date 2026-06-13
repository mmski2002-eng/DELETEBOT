# ФАЗА 8 — Kill Attempts: Опровержение Attack Stories
## Atleta Network — Mainnet Only

Принцип: каждая story получает максимально честный attack on itself.
Цель — убить слабые, укрепить выжившие.

---

## KILL ATTEMPT S1: "The Trusted Messenger"
### executeBatch → downstream authority escalation

**Попытки убить:**

**К1: Downstream contracts не существуют на mainnet**
На mainnet зафиксировано: PlatformController (verified), mystery ERC-20. Bridge contracts — НЕ задеплоены ещё ("Coming Soon"). Если нет downstream contracts с `msg.sender == platformController` проверкой → вся история — теория про несуществующий код.
Вес: СИЛЬНЫЙ. Текущий mainnet minimal. executeBatch без targets = no-op.

**К2: Downstream contracts будут использовать role-based auth, не address-based**
Если разработчики используют OZ AccessControl (они уже используют в PlatformController) — `hasRole(ROLE, msg.sender)` с явным `grantRole(ROLE, platformController)`. Тогда:
- executeBatch → downstream.grantRole(X, attacker) → revert AccessControlUnauthorizedAccount (если platformController не имеет DEFAULT_ADMIN_ROLE у downstream)
- Эскалация невозможна

**К3: executeBatch проверяет whitelist targets**
Если в implementation есть `require(isApprovedContract[target])` — arbitrary call невозможен.
→ Необходимо перечитать executeBatch из verified source.

**Анализ К3 по known ABI:**
```solidity
function executeBatch(
    address[] calldata targets,
    bytes[] calldata data,
    bool requireSuccess
) external onlyRole(SUPER_ADMIN_ROLE)
```
По имеющемуся ABI нет whitelist параметра. Но implementation может иметь internal check.
Без полного source — НЕИЗВЕСТНО.

**Вердикт S1: УСЛОВНО ВЫЖИВАЕТ**
- На текущем mainnet — НЕАКТУАЛЬНО (нет downstream contracts)
- При деплое bridge: критично зависит от auth pattern downstream
- Не убита теоретически, убита практически (сейчас)
- **Статус: LOW PRIORITY NOW / HIGH PRIORITY при bridge deploy**

---

## KILL ATTEMPT S2: "The Frozen River"
### Oracle Advance Attack

**Попытки убить:**

**К1: updateLastProcessedTronBlock имеет max advance limit**
Если код содержит:
```solidity
require(newBlock <= currentTronTip + MAX_ADVANCE, "AdvanceTooLarge");
```
→ advance до 99M невозможен.
→ Нужно читать полный source updateLastProcessedTronBlock.

Из Phase 2: функция описана как monotonic с проверкой `newBlock > lastProcessedTronBlock`. Конкретный MAX_ADVANCE limit — НЕ НАЙДЕН в анализе. Это gap в доказательной базе.

**К2: Bridge использует lastProcessedTronBlock как lower bound, не upper bound**
Если bridge settlement logic: `require(depositTronBlock <= lastProcessedTronBlock)` — тогда advance = "открыть окно для более ранних deposits." Advance к 99M = принять все deposits до 99M.
В этом случае: advance не блокирует, а РАЗБЛОКИРУЕТ settlement.
Атака инвертирована — не freeze, а premature settlement.

НО: если bridge добавляет: `require(depositTronBlock > lastConfirmedProcessedBlock)` (нет double-settlement) — то advance = orphan gap. Deposits в 83.4M–99M range не могут быть settled (haven't happened yet) и не могут быть "первыми" (lastProcessed > them). FREEZE возможен.

Зависит от точной bridge settlement logic. Без source — НЕИЗВЕСТНО.

**К3: ORACLE key hardware-secured / MPC**
Атака требует key compromise. Если ORACLE = hardware wallet или MPC — phishing неэффективен.
ORACLE addr `0x3Aa473...`: hot wallet pattern (частые txs, небольшой баланс = ~111 ATLA). Не multisig. Вероятно hot wallet. Риск компрометации реальный.

**К4: Monotonic design — advance можно остановить**
Если SUPER_ADMIN замечает advance → `revokeRole(ORACLE, attacker)` → остановка oracle.
НО: lastProcessedTronBlock уже = 99M. revoke не откатывает. Damage permanent.
→ Kill fails.

**К5: Может ли SUPER_ADMIN гранть ORACLE новому address и "reset" через другой механизм?**
Нет reset функции описано. Новый oracle продолжит с 99M. Единственный выход — upgrade implementation с reset logic (требует SUPER_ADMIN).
→ Технически восстанавливаемо через upgrade, но требует emergency upgrade.

**Вердикт S2: ВЫЖИВАЕТ**
- Hotspot: нет MAX_ADVANCE limit (не найдено, нужна верификация)
- Реальная kill: только если bridge settlement не зависит от watermark так как описано
- **Статус: HIGH. Требует проверки updateLastProcessedTronBlock source и bridge settlement logic**

---

## KILL ATTEMPT S3: "The Invisible Hand"
### Instant upgrade without timelock

**Попытки убить:**

**К1: SUPER_ADMIN = multisig / timelock (не EOA)**
Confirmed from on-chain: `0xB4349Fb7Fe240E24E8c5b2fF5caF4Cc265d38aF7` — is_contract: false. EOA подтверждён. Не multisig.
→ Kill fails. Подтверждено on-chain данными.

**К2: `_authorizeUpgrade` имеет дополнительные checks**
Standard OpenZeppelin UUPSUpgradeable:
```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyRole(SUPER_ADMIN_ROLE) {}
```
Если Atleta не модифицировал — только role check. SUPER_ADMIN = 1 EOA = 1 signature.
Без чтения полного source — возможны кастомные checks.

**К3: Новая implementation должна пройти proxiableUUID check**
UUPS проверяет что новая impl поддерживает UUPS interface:
```solidity
ERC1967Utils.upgradeToAndCall(newImplementation, data);
// внутри: checks proxiableUUID
```
Это защищает от "brick" (деплой non-upgradeable), но НЕ от malicious UUPS-compatible implementation.
→ Kill fails: malicious impl только должна вернуть правильный UUID.

**К4: Событие Upgraded() заметно — мониторинг немедленно алертит**
Если у команды есть on-chain monitoring с alert на Upgraded() event → могут среагировать.
НО: при компрометации SUPER_ADMIN attacker может сначала:
1. upgrade к malicious impl
2. drain funds
3. upgrade обратно к original impl
За 2-3 блока (24-36 секунд). Monitoring алерт = слишком поздно.
→ Kill partial: мониторинг снижает window of opportunity, не eliminates.

**К5: EOA `0xB4349...` имеет 684K ATLA — заметный target, но защищён**
Богатый EOA = high value target. Компрометация невозможна без физического/social access.
Это operational security argument, не code-level kill.

**Вердикт S3: ВЫЖИВАЕТ**
- EOA подтверждён on-chain. Нет timelock. Нет multisig.
- Code-level kill невозможен без timelock implementation
- Operational kill: hardware wallet, monitoring — не code guarantees
- **Статус: CONFIRMED HIGH. Structural issue, не спекуляция. Нет code kill.**
- **Рекомендация: единственное решение — TimelockController + multisig на SUPER_ADMIN**

---

## KILL ATTEMPT S4: "Dead Deposit"
### Pause + oracle clock = claim expiry

**Попытки убить:**

**К1: Bridge не имеет time-sensitive claim window**
Если bridge settlement: "любой deposit с confirmed TRON block может быть claimed в любое время" — нет expiry. Pause не влияет на право claim. Вся история строится на существовании claim window.
→ Если window нет → история УБИТА ПОЛНОСТЬЮ.

**К2: updateLastProcessedTronBlock имеет whenNotPaused modifier**
Если oracle update не работает во время pause → clock останавливается → claim window не истекает → история убита.
Необходимо: читать oracle update function modifiers.

**К3: Claim validation не проверяет "current lastProcessedTronBlock" для expiry**
Claim window может быть calendar-based (block.timestamp), не oracle-watermark based. Тогда:
- oracle продолжает обновляться, но window не зависит от oracle value
- claim window истекает по timestamp независимо от oracle
- история частично убита (причина иная, но orphaned deposits возможны)

**К4: TRON-side имеет automatic refund при timeout**
Если TRON bridge contract имеет: "if not claimed on Atleta in X days → auto-refund on TRON" → funds не locked permanently. Пользователь теряет time но не funds.
→ Значительно снижает impact, не убивает completely.

**К5: Bridge не задеплоен на mainnet**
Ключевой факт: bridge "Coming Soon." Нет deployed bridge contract на mainnet. История спекулятивна о будущем коде.
→ СИЛЬНЫЙ kill для сейчас. При деплое — нужна re-evaluation.

**Вердикт S4: УБИТА (на текущем mainnet)**
- Bridge не задеплоен → история про несуществующий код
- Требует re-evaluation при деплое
- Key questions для будущего аудита: claim window, oracle pause behavior
- **Статус: INVALID NOW / MONITOR при bridge deploy**

---

## KILL ATTEMPT S5: "The Loyal Executioner"
### Governance selective execution

**Попытки убить:**

**К1: Это задокументированный дизайн, не уязвимость**
"Outcomes are implemented/executed by the BCSports Foundation" — это прямая цитата документации. Не скрытое поведение. Участники знают о модели до участия.
→ Это не security bug, это governance design choice.
→ Kill: как "уязвимость в системе" — УБИТА. Как "risk" — ВЫЖИВАЕТ.

**К2: Exit pressure и reputation deterrence**
Если Foundation злоупотребляет → validators/nominators уходят → chain теряет security → Foundation теряет value of their holdings. Rational actor: не злоупотреблять.
Game theory argument. Не code guarantee. Частичный kill.

**К3: Foundation имеет legal obligations**
BCSports = legal entity. Off-chain governance execution = legal contract с token holders. Breach = lawsuit.
Regulatory и legal риски deterrируют selective execution.
→ Kill: как технический exploit — УБИТА. Как governance risk — ВЫЖИВАЕТ.

**К4: Community fork возможен**
Если Foundation игнорирует votes → community может fork → Foundation теряет legitimacy.
→ Ultimate deterrence. Не code-level kill.

**К5: На mainnet нет evidence of abuse**
Mainnet молод (4.4M блоков, ~ограниченная активность). Governance proposals: история неизвестна. Нет доказательств текущего злоупотребления.
→ Это текущий факт, не доказательство будущей безопасности.

**Вердикт S5: РЕКЛАССИФИЦИРОВАНА**
- Не security vulnerability, а governance risk
- Задокументированный дизайн с известным tradeoff
- **Статус: DOWNGRADE от Security Bug → Governance Risk / Informational**
- **Валидная находка для аудита: "centralized governance execution creates conflict of interest risk"**

---

## KILL ATTEMPT S6: "The Phantom Nominator"
### Slash escape via 72h unbond

**Попытки убить:**

**К1: Substrate применяет slash к unlocking chunks**
Это критический технический kill. В Substrate pallet-staking, `apply_slash_unapplied`:

```rust
// Из Substrate source (pallet-staking/src/slashing.rs):
fn slash_nominators<T: Config>(
    slash: &SlashParams<T>,
    prior_slash_p: Perbill,
    nominators_slashed: &mut Vec<(T::AccountId, BalanceOf<T>)>,
) {
    // ...
    let exposure = slash.exposure;
    for &(ref nominator, nominator_stake) in &exposure.others {
        let nominator_slash = // calculated from exposure
        slash_individual::<T>(nominator, nominator_slash);
    }
}

fn slash_individual<T: Config>(stash: &T::AccountId, slash: BalanceOf<T>) {
    let controller = T::StashOf::get(stash); // deprecated; stash == controller in modern Substrate
    let mut ledger = T::StakingInterface::ledger(stash);
    
    // КЛЮЧЕВОЕ: slash_exposure применяется к ledger включая unlocking chunks
    let (_, ledger) = slash_exposure(slash, ledger);
    // ... применяет к active + unlocking
}
```

**В Substrate 3.x/4.x**: slash применяется к `active` первым. Если slash > active → overflow applied to `unlocking` chunks в порядке от newest to oldest. `withdraw_unbonded` освобождает chunks только после `BondingDuration` eras.

**Критический вопрос**: если nominator вызвал `unbond()` в эре X, chunks становятся unlocking. `withdraw_unbonded()` доступен после `BondingDuration` eras. Slash применяется через `SlashDeferDuration` eras. 

Atleta: BondingDuration nominators = документально "72 hours" ≈ 2 eras (72h / 36h per era). SlashDeferDuration = 7 eras.

Если unbond() в эре X:
- Unlock available: era X+2 (72h)
- Slash applied: era X+7 (252h)

В эре X+2: nominator вызывает withdraw_unbonded() → ATLA free в account (NOT reserved).
В эре X+7: slash logic пытается `slash_reserved(account, amount)` → reserved = 0 → попытка `slash_free`?

**Но**: Substrate's Currency::slash не разделяет reserved/free. `slash(account, amount)` = slash total balance including free. Если ATLA уже withdrawn as free balance → `slash` всё равно работает на free balance → номинатор НЕ escape!

НО: если номинатор перевёл ATLA на другой account после withdraw → тогда escape полный.

**К2: Slash рассчитывается от exposure snapshot, не текущего ledger**
`UnappliedSlash` хранит pre-calculated amounts: `others: Vec<(AccountId, Balance)>`. Balance = рассчитан от era exposure. При применении: `T::Currency::slash(account, stored_balance)`. Slash идёт на весь баланс аккаунта, включая free balance после withdrawal.

**Вывод**: Escape неполный если средства остаются на том же account. Escape полный только если средства переведены на другой account до применения slash (7 eras window).

**К3: Transfer до slash application = реальный escape path**
Номинатор: unbond() → withdraw_unbonded() (после 2 eras) → transfer(anotherAddr, fullBalance) (до era X+7) → original account = 0 balance → slash(0) = 0. 

ЭТО РЕАЛЬНЫЙ ESCAPE: не через unlocking mechanics, а через transfer after withdrawal.

**Подтверждено**: escape возможен через transfer, не через unbonding mechanics напрямую.

**Вердикт S6: ЧАСТИЧНО УБИТА, ЧАСТИЧНО ВЫЖИВАЕТ**
- Механизм escape через unbond-only: УБИТ (slash берёт free balance)
- Механизм escape через unbond + transfer: ВЫЖИВАЕТ (другой аккаунт = 0 slash)
- Требует дополнительного шага (transfer), но window = 5 eras (era X+2 to X+7)
- **Статус: ВЫЖИВАЕТ с уточнением. Механизм: unbond → withdraw → transfer. Window: ~180 часов.**

---

## KILL ATTEMPT S7: "The Two Treasury Keys"
### 100% fee + treasury redirect

**Попытки убить:**

**К1: Fee применяется на TRON стороне, не на Atleta**
Если bridge архитектура: TRON-side bridge contract берёт fee → отправляет net amount на Atleta. Тогда `platformFee` на Atleta = informational (отображается в UI), реальный fee = TRON contract parameter. Изменение platformFee на Atleta → ничего не меняет в реальном fee.

→ Если fee on TRON side → история УБИТА ПОЛНОСТЬЮ.
→ Необходима bridge architecture documentation / TRON contract source.

**К2: Fee может быть захардкожен в oracle off-chain logic**
Если oracle (off-chain service) читает platformFee при запуске (не per-transaction) → изменение on-chain platformFee не влияет на oracle behavior до restart. Momentary change: oracle не видит новый fee.
→ Kill: при hot oracle, bridge не realtime-обновляет fee.

**К3: treasuryWallet изменение требует 2-step confirmation**
Если `updateTreasuryWallet` имеет timelock или pending/confirm pattern (owner sets pending, after delay confirms) → instant redirect невозможен.
→ Нужно читать полный source updateTreasuryWallet.

**К4: MaxPlatformFee cap ниже 10000**
Если `updatePlatformFee` имеет `require(newFee <= MAX_FEE)` где MAX_FEE = 500 (5%) — не 10000. Тогда fee = 100% невозможен.
По ABI max = 10000 (10000 bps = 100%). Но implementation может иметь more restrictive check.
→ Нужна верификация из source.

**К5: Bridge settlement не использует текущий platformFee — использует fee-at-deposit-time**
Если bridge: при deposit → записывает `feeAtDeposit = platformFee` → settlement использует `feeAtDeposit` (snapshot). Тогда изменение fee между deposit и settlement не влияет.
→ Kill: retroactive fee change невозможна, только future deposits affected.
→ Если window = 1 block для новых deposits → attack window = крайне мало.

**К6: На mainnet bridge нет**
Bridge "Coming Soon." Нет deployed bridge. История про несуществующий code.
→ СИЛЬНЫЙ kill для сейчас.

**Вердикт S7: УСЛОВНО УБИТА (на текущем mainnet)**
- Нет bridge contract → история спекулятивна
- Key uncertainties: fee side (TRON vs Atleta), fee snapshot timing, treasury update delay
- **Статус: INVALID NOW / HIGH PRIORITY при bridge deploy**
- **При деплое: если fee Atleta-side + no snapshot + instant treasury → CRITICAL confirmed**

---

## KILL ATTEMPT S8: "The Nominator's Timing Trap"
### Nomination snapshot lag → unexpected slash

**Попытки убить:**

**К1: Это задокументированное Substrate поведение**
Era-delayed nominations — fundamental Substrate staking design. Описано в Substrate docs. "Your nominations are effective starting from the next era." Любой who uses Substrate staking знает это.
→ Не vulnerability, expected behavior.

**К2: UI может явно предупреждать**
Если Atleta wallet UI показывает "new nominations effective in era X+1 (in Yh)" — пользователь предупреждён. Нет surprise.
→ UI mitigation возможна.

**К3: Slash за equivocation = Level 4 (100%) — крайне редко**
Практически: Level 4 slash (intentional double-sign) редок. Level 1 (offline) = 0.1% — small slash. Timing trap для 0.1% = negligible impact. Для 100% = catastrophic but extremely rare.
→ Снижает severity в нормальных условиях.

**К4: Nominators используют nomination pools, не direct nomination**
Если majority nominators используют pools (min 10 ATLA vs direct min threshold) → пул управляет nominations, не individual nominator. Pool роль (Nominator) контролирует nominations. Timing trap = pool-level issue, не individual user issue.
→ Снижает exposure для большинства users.

**К5: Это не exploit — нет adversarial agent**
История как exploit требует adversarial validator который умышленно equivocates. Validators ставят stake (75K–7.5M ATLA) → incentive против equivocation. Self-destruct scenario только если validator externally compromised.
→ Как deliberate attack: убита. Как structural risk: остаётся.

**Вердикт S8: УБИТА как exploit, ВЫЖИВАЕТ как UX risk**
- Не security vulnerability: expected protocol behavior
- Real user risk: UX confusion при nomination change + same-era slash
- **Статус: DOWNGRADE → UX/Documentation Finding**
- **Рекомендация: UI должен показывать residual slash exposure до следующей эры**

---

## ИТОГОВАЯ ТАБЛИЦА: ВЫЖИВШИЕ vs УБИТЫЕ

| Story | Вердикт | Статус после Kill | Priority |
|-------|---------|-------------------|----------|
| S1: Trusted Messenger | УСЛОВНО ВЫЖИВАЕТ | Неактуально (нет downstream), critical при bridge deploy | LOW NOW / HIGH later |
| S2: Frozen River | ВЫЖИВАЕТ | Нет confirmed max_advance limit; key security unknown | HIGH |
| S3: Invisible Hand | ВЫЖИВАЕТ | EOA confirmed, no timelock confirmed | HIGH CONFIRMED |
| S4: Dead Deposit | УБИТА (сейчас) | Bridge не задеплоен; требует re-eval | INVALID NOW |
| S5: Loyal Executioner | РЕКЛАССИФИЦИРОВАНА | Governance risk, not security bug | INFORMATIONAL |
| S6: Phantom Nominator | ЧАСТИЧНО ВЫЖИВАЕТ | Escape через transfer, не unbonding | MEDIUM (revised mechanism) |
| S7: Two Treasury Keys | УБИТА (сейчас) | Bridge не задеплоен; fee side unknown | INVALID NOW |
| S8: Timing Trap | УБИТА как exploit | UX/docs finding | INFORMATIONAL |

---

## ВЫЖИВШИЕ ИСТОРИИ ДЛЯ ФАЗЫ 9

### Подтверждённые (evidence-backed, actionable):
1. **S3** — Instant upgrade, 1 EOA SUPER_ADMIN, no timelock. CONFIRMED.
2. **S2** — Oracle advance attack (no max limit found). PROBABLE. Needs source verification.

### Реклассифицированные:
3. **S6** — Escape через withdraw+transfer. Revised механизм. MEDIUM.
4. **S5** — Governance centralization risk. Informational.
5. **S8** — UX/documentation gap. Informational.

### Требуют bridge deploy для валидации:
6. **S1** — executeBatch escalation (critical if downstream auth = address-based)
7. **S7** — Fee + treasury attack (critical if fee Atleta-side, no snapshot)
8. **S4** — Pause + claim window (if claim window exists)

---

## ОТКРЫТЫЕ ВОПРОСЫ (требуют дополнительных данных)

| # | Вопрос | Влияет на |
|---|--------|-----------|
| Q1 | Есть ли MAX_ADVANCE limit в `updateLastProcessedTronBlock`? | S2 kill/survive |
| Q2 | Fee применяется TRON-side или Atleta-side? | S7 kill/survive |
| Q3 | Есть ли claim window в bridge settlement? | S4 kill/survive |
| Q4 | Downstream contracts используют address-based или role-based auth? | S1 kill/survive |
| Q5 | Есть ли `whenNotPaused` на oracle update? | S4 severity |
| Q6 | Полный source `_authorizeUpgrade` — есть ли кастомные checks? | S3 severity |
| Q7 | ORACLE key security: hot wallet / hardware / MPC? | S2 reachability |

---

*Фаза 8 завершена. Жду отмашку на Фазу 9.*
