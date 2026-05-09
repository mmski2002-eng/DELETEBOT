# Анализ находок на соответствие условиям Immunefi Bug Bounty

**Дата:** 2026-05-08
**Программа:** Rhino.fi на Immunefi
**Скоуп:** Smart contracts (EVM + TON)

---

## Сводка соответствия

| # | Находка | Наш Severity | Immunefi Severity | Подходит? | Обоснование |
|---|---|---|---|---|---|
| 1 | `removeFundsNative()` silent fail | Medium | **Medium** | ✅ **ДА** | Silent failure native transfer — соответствует Medium (limited loss, specific conditions) |
| 2 | CEI violation (ETH before ERC20) | Medium | **Medium** | ✅ **ДА** | Reentrancy vector — соответствует Medium (requires authorized caller) |
| 3 | Permit frontrunning | Medium | **Medium** | ✅ **ДА** | Signature exposure — соответствует Medium (requires mempool monitoring) |
| 4 | BridgeVM unchecked ETH | Low | **Low** | ✅ **ДА** | Low severity, но в скоупе — подходит для Low/Informational |
| 5 | TON Bridge reentrancy + mode 128 | Medium | **Medium** | ✅ **ДА** | TON в скоупе, reentrancy — Medium |
| 6 | `transferOwner` zero address | Low | **Low** | ✅ **ДА** | Low severity, access control — подходит |
| 7 | `depositWithId` bypass | Low/Info | **Low/Info** | ✅ **ДА** | Informational — подходит |

---

## Детальный анализ по каждой находке

### Finding #1: `removeFundsNative()` — Silent Failure (Medium)

**Соответствие Immunefi:** ✅ **ПОДХОДИТ**

- **Severity:** Medium — корректно
- **Категория:** Insecure external call / Silent failure
- **Условия Immunefi:** Medium severity для багов, которые могут привести к потере средств при определённых условиях
- **Почему Medium, а не High:** Требуется authorized caller (не любой пользователь)
- **Почему не Critical:** Нет прямого пути к drain средств, только silent failure
- **Ончейн-подтверждение:** ✅ Есть (байткод + verified source)

### Finding #2: `withdrawV2WithNative` — CEI Violation (Medium)

**Соответствие Immunefi:** ✅ **ПОДХОДИТ**

- **Severity:** Medium — корректно
- **Категория:** Checks-Effects-Interactions / Reentrancy
- **Условия Immunefi:** Reentrancy — классический Medium/High в зависимости от контекста
- **Почему Medium:** Требуется authorized caller, нет прямого reentrancy-гана (только ETH -> ERC20)
- **Почему не High:** ReentrancyGuard отсутствует, но функция только для authorized
- **Ончейн-подтверждение:** ✅ Есть (verified source)

### Finding #3: `depositWithPermit` — Frontrunning (Medium)

**Соответствие Immunefi:** ✅ **ПОДХОДИТ**

- **Severity:** Medium — корректно
- **Категория:** Permit/Signature exposure
- **Условия Immunefi:** Signature replay/frontrunning — Medium
- **Почему Medium:** Требуется жертва с активным permit, frontrunning возможен только в mempool
- **Cross-chain replay:** Невозможен (DOMAIN_SEPARATOR разный)
- **Ончейн-подтверждение:** ✅ Есть (verified source + selector в байткоде)

### Finding #4: BridgeVM `withdrawVmFunds` — Unchecked ETH (Low)

**Соответствие Immunefi:** ✅ **ПОДХОДИТ (Low)**

- **Severity:** Low — корректно
- **Категория:** Silent failure
- **Условия Immunefi:** Low severity принимается
- **Ограничение:** BridgeVM не развёрнут на mainnet (storage slot 5 = 0)
- **Ончейн-подтверждение:** ⚠️ Частичное (код есть, VM не развёрнут на mainnet)

### Finding #5: TON Bridge — Reentrancy + Mode 128 (Medium)

**Соответствие Immunefi:** ✅ **ПОДХОДИТ**

- **Severity:** Medium — корректно
- **Категория:** Reentrancy / Griefing
- **Условия Immunefi:** TON в скоупе, reentrancy — Medium
- **Ограничение:** Нельзя подтвердить ончейн (TON не EVM)
- **Ончейн-подтверждение:** ❌ Невозможно (требуется TON sandbox)

### Finding #6: `transferOwner` — Zero Address (Low)

**Соответствие Immunefi:** ✅ **ПОДХОДИТ (Low)**

- **Severity:** Low — корректно
- **Категория:** Access control
- **Условия Immunefi:** Low severity принимается
- **Почему Low:** Требуется owner (мультисиг), маловероятно что мультисиг сделает address(0)
- **Ончейн-подтверждение:** ✅ Есть (verified source + owner() call)

### Finding #7: `depositWithId` — Bypass (Low/Info)

**Соответствие Immunefi:** ✅ **ПОДХОДИТ (Low/Info)**

- **Severity:** Low/Informational — корректно
- **Категория:** Logic bypass
- **Условия Immunefi:** Informational принимается
- **Почему Low/Info:** Нет прямого loss, bypass ограничений на депозиты
- **Ончейн-подтверждение:** ✅ Есть (verified source + storage slot 3)

---

## Рекомендации по submission на Immunefi

### Приоритет submission (от наиболее ценных к наименее):

1. **Finding #1** (Medium) — removeFundsNative silent fail — **самый сильный кандидат**
   - ✅ Ончейн-подтверждение есть
   - ✅ Чёткий контраст с другими функциями
   - ✅ PoC найден
   
2. **Finding #2** (Medium) — CEI violation
   - ✅ Ончейн-подтверждение есть
   - ✅ PeckShield уже фиксили ReentrancyGuard в UserWallet, но не в DVFDepositContract
   
3. **Finding #3** (Medium) — Permit frontrunning
   - ✅ Ончейн-подтверждение есть
   - ⚠️ Могут сказать "known issue" (permit frontrunning известен)
   
4. **Finding #5** (Medium) — TON Bridge
   - ⚠️ Нельзя подтвердить ончейн
   - ⚠️ Требуется TON sandbox
   
5. **Finding #4** (Low) — BridgeVM unchecked ETH
   - ⚠️ VM не развёрнут на mainnet
   
6. **Finding #6** (Low) — transferOwner zero address
   - ⚠️ Очень низкий impact
   
7. **Finding #7** (Low/Info) — depositWithId bypass
   - ⚠️ Informational, низкая награда

### Стратегия submission:

1. **Подавать все 3 Medium находки** (#1, #2, #3) — у каждой есть ончейн-подтверждение
2. **Finding #5** (TON) — подавать отдельно, если есть доступ к TON sandbox
3. **Low/Info находки** (#4, #6, #7) — можно подать как дополнительную информацию или объединить в один submission

### Ключевые аргументы для Immunefi:

- **Finding #1:** "Inconsistent security pattern — all other native transfer functions check return value, removeFundsNative does not. This is a clear deviation from the project's own security standards."
- **Finding #2:** "PeckShield already identified and fixed reentrancy in UserWallet by adding ReentrancyGuard. The same fix was NOT applied to DVFDepositContract despite having the same vulnerability pattern."
- **Finding #3:** "Permit signatures are exposed in mempool. While cross-chain replay is impossible, same-chain frontrunning is trivially executable."
