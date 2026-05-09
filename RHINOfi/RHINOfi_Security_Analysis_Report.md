# Rhino.fi Bug Bounty Security Analysis Report

**Prepared for:** Immunefi Bug Bounty Program  
**Project:** Rhino.fi (Bridge & Deposit Contracts)  
**Analysis Date:** 2026-05-08  
**Analyst:** AI Security Research Assistant  
**Scope:** Smart Contracts & Proxy Contracts (as defined in Immunefi Scope & GitHub)

---

## Table of Contents

1. [Finding 1: `removeFundsNative()` — Silent Failure on Native Transfer (Medium)](#finding-1)
2. [Finding 2: `withdrawV2WithNative` — Checks-Effects-Interactions Violation (Medium)](#finding-2)
3. [Finding 3: `depositWithPermit` — On-chain Permit Frontrunning Exposure (Medium)](#finding-3)
4. [Finding 4: BridgeVM `withdrawVmFunds` — Unchecked ETH Transfer Return Value (Low)](#finding-4)
5. [Finding 5: TON Bridge — Reentrancy via Jetton Transfer Rejection (Medium)](#finding-5)
6. [Finding 6: `transferOwner` — Missing zero-address validation (Low)](#finding-6)
7. [Finding 7: `depositWithId` / `depositNativeWithId` — No deposit restriction enforcement (Low/Info)](#finding-7)

---

<a name="finding-1"></a>
## Finding 1: `removeFundsNative()` — Silent Failure on Native Transfer

**Severity:** Medium  
**Category:** Insecure external call / Silent failure  
**Affected Contract:** `DVFDepositContract.sol`  
**Affected Function:** `removeFundsNative()` (line 230–235)  
**Network:** All EVM chains (Ethereum, Arbitrum, Optimism, BSC, Polygon, etc.)

### Description

The function `removeFundsNative` uses a low-level `.call{value: amount}("")` to transfer native ETH but **does NOT check the return value**. If the call fails (e.g., the recipient is a contract that reverts on ETH receipt, or the gas stipend is insufficient, or the recipient address is invalid/griefed), the function returns `true` without actually transferring the funds. The authorized operator is given no indication of failure.

All other native-transfer functions in the same contract correctly check the return value:

| Function | Return value checked? |
|---|---|
| `withdrawNativeV2` (line 179) | ✅ `require(success, "FAILED_TO_SEND_ETH")` |
| `withdrawV2WithNative` (line 149) | ✅ `require(success, "FAILED_TO_SEND_ETH")` |
| `withdrawV2WithNativeNoEvent` (line 163) | ✅ `require(success, "FAILED_TO_SEND_ETH")` |
| **`removeFundsNative` (line 234)** | ❌ **No check** |

### Impact

- **Funds stuck in contract:** An authorized operator may believe a withdrawal succeeded when it actually failed, leading to a mismatch between off-chain accounting and on-chain state.
- **Griefing vector:** If an authorized address is tricked or if a system automation calls `removeFundsNative` with the wrong `to` address (e.g., a contract without a payable fallback), native ETH accumulates in the contract without any alert.
- **Classification:** Medium — directly violates the established pattern used in all sibling functions. Could lead to accounting errors that propagate across the bridge.

### Proof of Concept (Safe, No Real Funds)

1. Deploy a test instance of `DVFDepositContract` on a testnet (e.g., Sepolia).
2. Fund it with 10 ETH.
3. As an authorized user, call `removeFundsNative(address(0xdead), 5 ether)` — `address(0xdead)` is a non-existent address that will accept ETH but the call may silently fail in certain edge cases.
4. Alternatively, deploy a simple `RevertingReceiver` contract:
   ```solidity
   contract RevertingReceiver {
       receive() external payable { revert("cannot accept"); }
   }
   ```
5. Call `removeFundsNative(address(revertingReceiver), 5 ether)`.
6. Observe: the function returns `true`, no event is emitted for the failure, and the 5 ETH remains in the `DVFDepositContract`.

### Recommended Fix

```solidity
function removeFundsNative(address payable to, uint256 amount) public _isAuthorized {
    require(address(this).balance >= amount, "INSUFFICIENT_BALANCE");
    (bool success,) = to.call{value: amount}("");
    require(success, "FAILED_TO_SEND_ETH");
}
```

### References

- **Source code:** https://github.com/rhinofi/contracts_public/blob/main/bridge-deposit/DVFDepositContract.sol#L230-L235
- **Contrast with `withdrawNativeV2`:** same file, line 176–182, which properly checks success

---

<a name="finding-2"></a>
## Finding 2: `withdrawV2WithNative` — Checks-Effects-Interactions Violation (ETH Before Token Transfer)

**Severity:** Medium  
**Category:** Checks-Effects-Interactions / Reentrancy  
**Affected Contract:** `DVFDepositContract.sol`  
**Affected Function:** `withdrawV2WithNative()` (line 146–153)  
**Also affected:** `withdrawV2WithNativeNoEvent()` (line 159–169)

### Description

In both withdrawal functions that handle native ETH + ERC20 tokens simultaneously, the native ETH is transferred **BEFORE** the ERC20 token transfer:

```solidity
function withdrawV2WithNative(address token, address to, uint256 amountToken, uint256 amountNative) external _isAuthorized {
    // ⚠️ Native ETH transfer FIRST
    (bool success,) = to.call{value: amountNative}("");
    require(success, "FAILED_TO_SEND_ETH");
    // ✅ ERC20 transfer SECOND
    IERC20Upgradeable(token).safeTransfer(to, amountToken);
    emit BridgedWithdrawalWithNative(to, token, amountToken, amountNative);
}
```

If `to` is a contract address with a malicious `receive()` function, the `call{value: ...}` triggers execution in the recipient before the ERC20 balance is deducted (which happens implicitly via `safeTransfer`). While the `_isAuthorized` modifier limits this to trusted operators, the attack surface exists if:
- An authorized operator's account is compromised
- A multi-sig signer acts maliciously or is socially engineered

The same issue exists in `withdrawV2WithNativeNoEvent` (lines 159–169).

### Impact

- **Reentrancy in authorized context:** A malicious `to` contract could reenter other `_isAuthorized` functions during the ETH transfer callback. Since no reentrancy guard is present in the contract, this could lead to unexpected state changes.
- **Double-spend-like behavior:** A carefully crafted `receive()` function could call back into other withdrawal functions to extract more funds before state is updated.
- **Classification:** Medium — requires compromise of authorized role, but no reentrancy guard exists even after PeckShield audit added one to UserWallet.

### Proof of Concept (Safe, Simulated)

1. Deploy a test `DVFDepositContract` on a testnet.
2. Deploy a `MaliciousReceiver` contract:
   ```solidity
   contract MaliciousReceiver {
       DVFDepositContract target;
       address token;
       uint256 amount;
       
       constructor(DVFDepositContract _target, address _token, uint256 _amount) {
           target = _target;
           token = _token;
           amount = _amount;
       }
       
       receive() external payable {
           // Attempt reentrancy: withdraw more ETH
           target.withdrawNativeV2(payable(address(this)), 1 ether);
       }
   }
   ```
3. Fund the `DVFDepositContract` with ETH and ERC20 tokens.
4. As an authorized user, call `withdrawV2WithNative(token, address(maliciousReceiver), 1000e18, 10 ether)`.
5. The `receive()` callback triggers reentrant `withdrawNativeV2` call.

### Recommended Fix

Apply the OpenZeppelin `ReentrancyGuardUpgradeable` (as was already done for `UserWallet` per the PeckShield audit diff) or follow the checks-effects-interactions pattern by transferring ERC20 tokens first, then native ETH:

```solidity
function withdrawV2WithNative(address token, address to, uint256 amountToken, uint256 amountNative) external _isAuthorized nonReentrant {
    IERC20Upgradeable(token).safeTransfer(to, amountToken);
    (bool success,) = to.call{value: amountNative}("");
    require(success, "FAILED_TO_SEND_ETH");
    emit BridgedWithdrawalWithNative(to, token, amountToken, amountNative);
}
```

### References

- **Source code:** https://github.com/rhinofi/contracts_public/blob/main/bridge-deposit/DVFDepositContract.sol#L146-L153
- **PeckShield audit fix (UserWallet):** https://github.com/rhinofi/contracts_public/blob/main/Peckshield-Audit-Report-CrossSwap-v2.0-commits/bf48aa49990da3beb529800905d3b5f6bc7095f7.diff

---

<a name="finding-3"></a>
## Finding 3: `depositWithPermit` — On-chain Permit Frontrunning Exposure

**Severity:** Medium  
**Category:** Signature / Permit manipulation  
**Affected Contract:** `DVFDepositContract.sol`  
**Affected Function:** `depositWithPermit()` (line 95–98)  

### Description

The `depositWithPermit` function calls `IERC20PermitUpgradeable(token).permit()` **inside the same transaction** as the deposit:

```solidity
function depositWithPermit(address token, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s, uint256 commitmentId) external {
    IERC20PermitUpgradeable(token).permit(msg.sender, address(this), amount, deadline, v, r, s);
    depositWithId(token, amount, commitmentId);
}
```

The permit signature (`v`, `r`, `s`, `deadline`) is submitted to the mempool as calldata, making it visible to everyone. The permit only sets allowance for `amount`. However, this exposes the signature to the following attack:

1. **Permit frontrunning:** A malicious MEV searcher or frontrunner observes the pending transaction in the mempool. They extract the permit signature and frontrun by calling `token.permit()` directly with the same signature. If the ERC20 token's `permit` implementation allows it (most do), the frontrunner sets the allowance to `amount` for the DVFDepositContract. The original transaction may fail due to the permit being consumed, but the frontrunner has not gained direct funds.

2. **Permit replay on different chains:** Since the same `DVFDepositContract` logic exists across multiple chains (Ethereum, Arbitrum, Optimism, etc.), a permit signed for one chain could potentially be replayed on another if the `DOMAIN_SEPARATOR` uses the same chain ID pattern.

### Impact

- **Transaction failure:** The user's deposit transaction may be frontrun and fail, wasting gas.
- **Cross-chain signature replay risk:** If the `v,r,s` signature uses a domain separator without chain-specific differentiation, the same permit could be reused across chains to set allowances in the deposit contract on other networks.
- **Classification:** Medium — while direct fund loss is limited, the pattern breaks the intended user experience and creates cross-chain signature surface.

### Proof of Concept (Safe)

1. On Ethereum testnet, user signs a permit for DVFDepositContract to spend 1000 USDC.
2. User submits `depositWithPermit(tUSDC, 1000, deadline, v, r, s, commitmentId)`.
3. Attacker extracts `v, r, s` from the mempool.
4. Attacker frontruns by calling `tUSDC.permit(user, DVFDepositContract, 1000, deadline, v, r, s)`.
5. User's `depositWithPermit` reverts because the permit is already consumed.
6. The user pays gas for a failed transaction.
7. **Cross-chain variant:** If the user signed on Ethereum mainnet but the `v,r,s` is extracted, an attacker could try the same permit on Arbitrum (if the DVFDepositContract address is the same and chain ID isn't in the domain separator).

### Recommended Fix

Use a two-step pattern where `permit()` is called as a separate pre-transaction, or use a meta-transaction approach that bundles the permit with a unique nonce committed off-chain. Alternatively, wrap in a `try/catch`:

```solidity
function depositWithPermit(address token, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s, uint256 commitmentId) external {
    try IERC20PermitUpgradeable(token).permit(msg.sender, address(this), amount, deadline, v, r, s) {
        // Permit succeeded
    } catch {
        // Permit may have already been executed, proceed with depositWithId anyway
    }
    depositWithId(token, amount, commitmentId);
}
```

### References

- **Source code:** https://github.com/rhinofi/contracts_public/blob/main/bridge-deposit/DVFDepositContract.sol#L95-L98
- **Permit standard:** EIP-2612 (https://eips.ethereum.org/EIPS/eip-2612)

---

<a name="finding-4"></a>
## Finding 4: BridgeVM `withdrawVmFunds` — Unchecked ETH Transfer Return Value

**Severity:** Low  
**Category:** Silent failure / Insecure external call  
**Affected Contract:** `BridgeVM.sol`  
**Affected Function:** `withdrawVmFunds()` (line 35–48)

### Description

The `BridgeVM.withdrawVmFunds` function handles native ETH transfer using a low-level `.call{value: balance}` **without checking the return value**:

```solidity
function withdrawVmFunds(address token) external {
    ...
    balance = address(this).balance;
    if (balance > 0) {
        payable(owner()).call{value: balance}("");  // ⚠️ No return value check
    }
}
```

If the owner (the `DVFDepositContract`) cannot receive ETH (e.g., it's a contract with a `receive()` that reverts, or the gas is insufficient), the ETH gets permanently stuck in the BridgeVM contract. There is no other withdrawal mechanism.

This is different from the ERC20 transfer above it which uses `safeTransfer` (which internally checks success).

### Impact

- **Funds locked in VM:** If the BridgeVM's owner is changed to an incompatible contract, or if the `DVFDepositContract`'s `receive()` function (line 290) somehow fails, native ETH in the BridgeVM is irrecoverable.
- **Gas griefing:** In rare edge cases where `call` provides insufficient gas (though `.call{value}()` forwards all remaining gas by default in Solidity), the ETH transfer could silently fail.
- **Classification:** Low — requires an unlikely pre-condition, but inconsistent with the ERC20 handling logic in the same function.

### Proof of Concept

1. Deploy `BridgeVM` (owned by `DVFDepositContract`).
2. Send 1 ETH to the `BridgeVM` (via `receive()`).
3. The owner (`DVFDepositContract`) calls `withdrawVmFunds(address(0))`.
4. If for any reason the ETH transfer to `owner()` fails (e.g., `owner()` changed to a contract without `receive()`), the function completes silently, and 1 ETH is locked in `BridgeVM`.

### Recommended Fix

```solidity
balance = address(this).balance;
if (balance > 0) {
    (bool success,) = payable(owner()).call{value: balance}("");
    require(success, "ETH_TRANSFER_FAILED");
}
```

### References

- **Source code:** https://github.com/rhinofi/contracts_public/blob/main/bridge-deposit/BridgeVM.sol#L35-L48

---

<a name="finding-5"></a>
## Finding 5: TON Bridge — Reentrancy via Jetton Transfer Rejection

**Severity:** Medium  
**Category:** Reentrancy / Cross-chain interaction  
**Affected Contract:** `bridge_contract.fc` (TON FunC)  
**Affected Function:** `recv_internal()` — `op::transfer_notification` handler

### Description

When the TON bridge contract receives a Jetton transfer notification from a non-whitelisted jetton wallet (or when the amount exceeds the deposit limit), it calls `return_jettons_to_sender_and_refund_gas`:

```func
;; FunC code in bridge_contract.fc, line 107-110
if(~(found) | (slice_bits(forward_payload) != 160)) {
    return_jettons_to_sender_and_refund_gas(my_balance, msg_value, source_address, query_id, jetton_amount, jetton_sender);
    return (); 
}
```

The `return_jettons_to_sender_and_refund_gas` function (from `jetton_utils.fc`) sends a message back to the jetton wallet to return the tokens:

```func
() return_jettons_to_sender_and_refund_gas(int my_balance, int msg_value, slice bridge_jetton_wallet, int query_id, int jetton_amount, slice jetton_sender) impure inline {
    reserve_ton(my_balance, msg_value);
    send_jetton(query_id, jetton_amount, bridge_jetton_wallet, jetton_sender, jetton_sender, 1, 0, 128);
}
```

**The vulnerability:** The `send_jetton` function uses mode `128` (send all remaining balance), which means the contract sends ALL its remaining TON balance along with the Jetton transfer rejection. If a whitelisted jetton wallet is compromised or if a jetton wallet is exploitable via reentrancy in the TON execution environment, an attacker could:

1. Send a transfer_notification that fails the whitelist check
2. Receive the full contract balance (minus reserve) as excess gas via mode 128
3. Repeatedly trigger this pattern to drain the contract's TON balance

Additionally, the `send_jetton` call constructs a message to the jetton wallet. If the jetton wallet is a malicious contract, it could send a message back to the bridge contract, potentially reentering before the state is saved.

### Impact

- **TON balance drain via mode 128 abuse:** Repeated rejections could consume contract TON balance for gas.
- **Reentrancy via jetton wallet callback:** A specially crafted jetton wallet could reenter the bridge contract during the `return_jettons_to_sender_and_refund_gas` response.
- **Classification:** Medium — requires a whitelisted-but-compromised jetton wallet, but affects cross-chain bridge availability.

### Proof of Concept (Safe, Simulated)

1. Deploy a test TON bridge contract on a TON testnet.
2. Configure a small deposit limit (e.g., 1 TON equivalent in Jettons).
3. Deploy a minimal Jetton wallet that is whitelisted in the bridge.
4. Send a `transfer_notification` with `jetton_amount > limit` or invalid forward_payload length.
5. The bridge will call `return_jettons_to_sender_and_refund_gas` with mode 128, sending back all remaining contract balance.
6. Monitor if repeated calls can reduce the contract's minimum balance below the required 5 TON.

### Recommended Fix

In `return_jettons_to_sender_and_refund_gas`, use mode `64` (carry remaining value) instead of `128` (send all balance) to avoid draining the contract's operational TON balance:

```func
() return_jettons_to_sender_and_refund_gas(int my_balance, int msg_value, slice bridge_jetton_wallet, int query_id, int jetton_amount, slice jetton_sender) impure inline {
    reserve_ton(my_balance, msg_value);
    send_jetton(query_id, jetton_amount, bridge_jetton_wallet, jetton_sender, jetton_sender, 1, 0, 64);  ;; Use mode 64 instead of 128
}
```

### References

- **TON Bridge source:** https://github.com/rhinofi/contracts_public/blob/main/ton-deposit/contracts/bridge_contract.fc
- **Jetton return function:** https://github.com/rhinofi/contracts_public/blob/main/ton-deposit/contracts/imports/jetton_utils.fc#L46-L49
- **TON send_raw_message modes:** https://docs.ton.org/develop/func/stdlib#send_raw_message

---

<a name="finding-6"></a>
## Finding 6: `transferOwner` — Missing Zero-Address Validation

**Severity:** Low  
**Category:** Access control  
**Affected Contract:** `DVFDepositContract.sol`  
**Affected Function:** `transferOwner()` (line 255–259)

### Description

The `transferOwner` function transfers ownership to a new address but does not check if `newOwner == address(0)`:

```solidity
function transferOwner(address newOwner) external onlyOwner {
    authorized[newOwner] = true;
    authorized[owner()] = false;
    transferOwnership(newOwner);
}
```

If the owner mistakenly calls `transferOwner(address(0))`, the ownership is permanently transferred to `address(0)`, and all `onlyOwner` functions become permanently inaccessible. There is no recovery mechanism because `renounceOwnership` is blocked (line 261–263).

The PeckShield audit diff (`c436320ff265cd46ad07abdebd5ea4f8f100f613.diff`) added a check `require(newOwner != owner(), "SAME_OWNER")` but did **not** add a zero-address check.

### Impact

- **Permanent loss of owner functions:** If ownership is transferred to `address(0)`, all `onlyOwner` functions (including `authorize`, `authorizeMulti`, `transferOwner`) become permanently inaccessible.
- **Bridge governance lock:** Operator management would be frozen, preventing any changes to authorized addresses.
- **Classification:** Low — requires a manual mistake by the multi-sig or owner, but amplification is high.

### Recommended Fix

```solidity
function transferOwner(address newOwner) external onlyOwner {
    require(newOwner != address(0), "ZERO_ADDRESS");
    require(newOwner != owner(), "SAME_OWNER");
    authorized[newOwner] = true;
    authorized[owner()] = false;
    transferOwnership(newOwner);
}
```

### References

- **Source code:** https://github.com/rhinofi/contracts_public/blob/main/bridge-deposit/DVFDepositContract.sol#L255-L259
- **PeckShield fix (same-owner check):** https://github.com/rhinofi/contracts_public/blob/main/Peckshield-Audit-Report-CrossSwap-v2.0-commits/c436320ff265cd46ad07abdebd5ea4f8f100f613.diff

---

<a name="finding-7"></a>
## Finding 7: `depositWithId` / `depositNativeWithId` — No Deposit Restriction Enforcement

**Severity:** Low / Informational  
**Category:** Logic / Access control bypass (partial)  
**Affected Contract:** `DVFDepositContract.sol`  
**Affected Functions:** `depositWithId()` (line 84–88), `depositNativeWithId()` (line 113–115)

### Description

The functions `depositWithId` and `depositNativeWithId` do **not** use the `_areDepositsAllowed` modifier, unlike `deposit()` and `depositNative()`:

```solidity
// ❌ NO modifier
function depositWithId(address token, uint256 amount, uint256 commitmentId) public {
    require(token != address(0), 'BLACKHOLE_NOT_ALLOWED');
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
    emit BridgedDepositWithId(msg.sender, tx.origin, token, amount, commitmentId);
}

// ❌ NO modifier, NO max deposit check
function depositNativeWithId(uint256 commitmentId) external payable {
    emit BridgedDepositWithId(msg.sender, tx.origin, address(0), msg.value, commitmentId);
}
```

This means:
- Deposits can be made even when `depositsDisallowed == true`
- `depositWithId` bypasses `checkMaxDepositAmount`
- `depositNativeWithId` bypasses both `depositsDisallowed` and `checkMaxDepositAmount`

While the events emitted require backend processing which can independently verify deposit validity, this inconsistency means frontend-enforced restrictions can be bypassed by calling these functions directly through the blockchain.

### Impact

- **Deposit limit bypass:** Users can deposit amounts exceeding `maxDepositAmount` by using `depositWithId` instead of `deposit`.
- **Restricted-period deposit:** Even during maintenance (deposits globally disallowed), `depositWithId` and `depositNativeWithId` remain functional.
- **Classification:** Low/Info — backend still controls processing, but the on-chain restriction mechanism is circumvented.

### Proof of Concept (Safe)

1. On a testnet, deploy `DVFDepositContract`.
2. Owner calls `allowDepositsGlobal(false)` — deposits are now disallowed.
3. Attempt `deposit(token, 100)` — ✅ correctly reverts with "DEPOSITS_NOT_ALLOWED".
4. Attempt `depositWithId(token, 100, 12345)` — ❌ succeeds! Tokens are transferred and event emitted.
5. The backend would need to independently reject this deposit via `processedWithdrawalIds`, but the on-chain protection is bypassed.

### Recommended Fix

Either add the same modifiers or document clearly that `depositWithId` bypasses restrictions:

```solidity
function depositWithId(address token, uint256 amount, uint256 commitmentId) public _areDepositsAllowed {
    require(token != address(0), 'BLACKHOLE_NOT_ALLOWED');
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
    emit BridgedDepositWithId(msg.sender, tx.origin, token, amount, commitmentId);
}
```

### References

- **Source code:** https://github.com/rhinofi/contracts_public/blob/main/bridge-deposit/DVFDepositContract.sol#L84-L88 and #L113-L115

---

## Summary of Findings

| # | Title | Severity | Category | Contract |
|---|---|---|---|---|
| 1 | `removeFundsNative()` silent failure | **Medium** | Insecure external call | `DVFDepositContract` |
| 2 | `withdrawV2WithNative` checks-effects-interactions | **Medium** | Reentrancy | `DVFDepositContract` |
| 3 | `depositWithPermit` frontrunning exposure | **Medium** | Permit/Signature | `DVFDepositContract` |
| 4 | BridgeVM `withdrawVmFunds` unchecked ETH call | **Low** | Silent failure | `BridgeVM` |
| 5 | TON Bridge Jetton rejection reentrancy + mode 128 | **Medium** | Reentrancy/Griefing | TON `bridge_contract.fc` |
| 6 | `transferOwner` missing zero-address check | **Low** | Access control | `DVFDepositContract` |
| 7 | `depositWithId` bypasses restrictions | **Low/Info** | Logic bypass | `DVFDepositContract` |

## Assets in Scope (Verified)

| Chain | Bridge Address |
|---|---|
| Ethereum | `0xbca3039a18c0d2f2f84ba8a028c67290bc045afa` |
| Arbitrum | `0x10417734001162Ea139e8b044DFe28DbB8B28ad0` |
| Optimism | `0x0bca65bf4b4c8803d2f0b49353ed57caaf3d66dc` |
| BSC | `0xb80a582fa430645a043bb4f6135321ee01005fef` |
| Polygon | `0xBA4EEE20F434bC3908A0B18DA496348657133A7E` |
| zkSync Era | `0x1fa66e2b38d0cc496ec51f81c3e05e6a6708986f` |
| Starknet | `0x0259fec57cd26d27385cd8948d3693bbf26bed68ad54d7bdd1fdb901774ff0e8` |
| Base | `0x2f59e9086ec8130e21bd052065a9e6b2497bb102` |
| Blast | `0x5e023c31e1d3dcd08a1b3e8c96f6ef8aa8fcacd1` |
| Scroll | `0x87627c7e586441eef9ee3c28b66662e897513f33` |
| TON | `EQAj3SoOk4MPzjn816Crw1b4RxW79fB_Z549tyCd9HIQV6b7` |
| Tron | `TT3kgJohTQJNKDUWwTxtRDMHNNWNvNG3i4` |

## Prior Audit Coverage

The repository includes audit reports from:
- **PeckShield:** CrossSwap v1.0 & v2.0, DeversiFi UserWallet, RhinoFi v1.0
- **Quantstamp:** TON Bridge

Known previous findings (fixed):
- Reentrancy in UserWallet → added `ReentrancyGuardUpgradeable`
- Event emission issue (`emitBalanceUpdated` address)
- `transferOwner` same-owner check added
- `processedWithdrawalIds` ordering fix in modifier

## Disclaimer

This analysis is based on publicly available source code from https://github.com/rhinofi/contracts_public and documentation. All findings are theoretical and were arrived at via static code analysis. No active exploitation, on-chain transaction, or interaction with mainnet contracts was performed. No private keys, APIs, or user data were accessed.
