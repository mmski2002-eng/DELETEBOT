# CLAUDE.md

## Pre-Audit Checklist (MANDATORY)

Before analyzing ANY contract:

1. Find the bug bounty program page first
2. Note exact in-scope repo / version / commit
3. Verify deployed contract matches the repo (check Etherscan/Tonscan)
4. Only then fetch and analyze code

Never analyze code from wrong repo/version — wasted effort.

### GetGems-specific (MANDATORY)

GetGems analysis MUST use the contract version whose compiled code-hash matches deployed mainnet bytecode.
Verify hash match before any analysis — never trust repo default branch is current.
Steps:
1. Get code hash of a real deployed sale contract via tonapi.io or tonviewer
2. Identify which repo version/tag compiles to that hash
3. Only analyze that exact version — flag explicitly if match cannot be confirmed

---

## General Rules

* Be concise, precise, and technical.
* Do not explain basic concepts unless explicitly asked.
* Do not summarize entire files unless necessary.
* Never analyze the whole repository blindly.
* **Language: always respond in Russian. Never switch to Ukrainian.**

---

## Code Analysis Strategy

When reviewing smart contracts:

1. Identify the attack surface first.
2. Focus on critical flows:

   * deposits
   * withdrawals
   * liquidation
   * mint/burn
   * price/oracle usage
   * access control
3. Trace full call paths instead of isolated functions.
4. Only load relevant code sections.

--- рш

## Security Review Focus

Always check for:

### Access Control

* missing `onlyOwner` / role checks
* incorrect role hierarchy
* privilege escalation paths

### Reentrancy

* external calls before state updates
* missing reentrancy guards

### Validation

* missing input validation
* unsafe assumptions
* unchecked return values

### Arithmetic / Precision

* rounding issues
* division before multiplication
* precision loss in DeFi math

### Token Handling

* unsafe `transfer` / `transferFrom`
* non-standard ERC20 behavior
* missing return value checks

### Oracle / Price Logic

* stale prices
* manipulable sources
* missing sanity checks

### Liquidation / Accounting

* incorrect debt accounting
* exploitable liquidation conditions
* share price manipulation

### Upgradeability

* unprotected upgrade functions
* storage collisions

---

## Output Format (MANDATORY)

When you find an issue, respond in this format:

* Title:
* Severity: (Low / Medium / High / Critical)
* Affected Function:
* Root Cause:
* Attack Path (step-by-step):
* Impact:
* Proof of Concept idea:
* Assumptions:
* Confidence Level:

Do NOT write vague explanations.

---

## Interaction Rules

* Ask for specific files or functions if context is missing.
* Prefer targeted questions over broad analysis.
* If unsure — say what additional data is needed.

---

## Efficiency Rules

* Avoid repeating code already shown.
* Avoid loading entire files if a function is enough.
* Prefer summaries over raw logs.
* Ignore irrelevant logs, comments, and boilerplate.

---

## Example Requests (Use This Style)

* "Find all functions that interact with user funds"
* "Trace deposit -> withdraw flow"
* "Check for reentrancy in withdrawal logic"
* "Find all external calls before state updates"
* "Analyze oracle usage and manipulation risks"

---

## Priority Mindset

Always think:

1. Can funds be stolen?
2. Can state be corrupted?
3. Can privileges be escalated?
4. Can accounting be manipulated?

Focus only on high-impact vulnerabilities first.

Always assume the code is vulnerable until proven otherwise.
Think like an attacker, not a developer.

---

## PoC Standards (MANDATORY)

PoC must EXECUTE contract bytecode (get-methods or message flow in Sandbox).
Mathematical simulation of a formula is NOT a valid PoC — it assumes the conclusion.
Never downgrade a fork-PoC to a calculation and call it "sufficient".

Accepted evidence:
- `blockchain.runGetMethod` on compiled real contract code → raw TVM stack output
- Message flow in Sandbox with mock dependencies → transaction receipts
- Isolated function wrapper compiled from real source via func-js → TVM result

NOT accepted:
- JS/Python arithmetic reproducing the formula
- "The math shows X" without TVM execution
- Simulation of conditions not in contract code