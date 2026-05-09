# 🔴 Security Audit Report: Camp Network Ecosystem

**Date**: 2025  
**Chain**: Camp Network (Chain ID: `123420001114`) — Ethereum L2  
**Native Token**: **CAMP** (NOT ETH!)  
**RPC**: `https://rpc.basecamp.t.raas.gelato.cloud`  
**Explorer**: `https://basecamp.cloud.blockscout.com/`

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Critical Vulnerability #1: `updateVaultBalance()` Missing Access Control](#critical-vulnerability-1-updatevaultbalance-missing-access-control)
3. [Critical Vulnerability #2: `_update()` Unbounded Gas Loop — Permanent DoS](#critical-vulnerability-2-_update-unbounded-gas-loop--permanent-dos)
4. [High Vulnerability #3: `buyAccess()` Without Reentrancy Guard](#high-vulnerability-3-buyaccess-without-reentrancy-guard)
5. [Medium Vulnerability #4: `resolveDispute()` Fund Loss Risk](#medium-vulnerability-4-resolvedispute-fund-loss-risk)
6. [Medium Vulnerability #5: CampPoint Decimal Mismatch](#medium-vulnerability-5-camppoint-decimal-mismatch)
7. [Observed Contract Inventory](#observed-contract-inventory)
8. [Recommended Fixes](#recommended-fixes)

---

## Executive Summary

A security analysis of the Camp Network ecosystem smart contracts revealed **2 critical**, **1 high**, and **2 medium** severity vulnerabilities. The most severe finding is a complete absence of access control on `IpRoyaltyVault.updateVaultBalance()`, which can be exploited by any external caller to permanently freeze all royalty token transfers and/or manipulate revenue claims across the entire ecosystem.

> ⚠️ **Important note:** At the time of analysis (2025) the vulnerable contracts hold NO funds. `IpRoyaltyVault` balance = **0 CAMP**, Marketplace balance = **0 CAMP**. However, the CrustySwap bridge holds **~456.7 CAMP** bridged from Ethereum. Vulnerabilities pose a critical threat once funds enter the contracts.

> ⚠️ **Terminology:** "CAMP" is the native token of Camp Network (NOT Ethereum's ETH).

### Severity Distribution

| Severity | Count |
|----------|-------|
| 🔴 Critical | 2 |
| 🟠 High | 1 |
| 🟡 Medium | 2 |
| 🟢 Low | 0 |

---

## Critical Vulnerability #1: `updateVaultBalance()` Missing Access Control

### Location

- **Contract**: `IpRoyaltyVault`
- **Address**: [`0xb27092564b5434f68706753f9C0ADDC49Ca71dC5`](https://basecamp.cloud.blockscout.com/address/0xb27092564b5434f68706753f9C0ADDC49Ca71dC5)
- **File**: `src/royalty/IpRoyaltyVault.sol`
- **Function**: `updateVaultBalance(address token, uint256 amount)`

### ✅ On-Chain Verified

An `eth_call` test confirmed the function is **truly public**: calling `updateVaultBalance(zero, 1)` from a random address (`0x00...01`) **DID NOT REVERT**. Any external account can call this function.

> 📊 **Current state:** Vault is empty — `vaultAccBalance(address(0)) = 0 CAMP`, contract balance = **0 CAMP**, revenue tokens tracked = **0**. The vulnerability exists but there's nothing to exploit.

### Vulnerable Code

```solidity
/// @inheritdoc IIpRoyaltyVault
function updateVaultBalance(address token, uint256 amount) external {
    // Only allow updates from the IpNFT contract or Marketplace
    // In production, you'd want more sophisticated access control
    if (amount == 0) revert ZeroAmount();

    _revenueTokens.add(token);
    _vaultAccBalances[token] += amount;

    emit RevenueTokenAddedToVault(token, amount);
}
```

### Description

The function has **NO access control modifier whatsoever**. Anyone — any external account or contract — can call it. The comment within the code explicitly acknowledges this but no fix was ever implemented.

### Exploit Scenarios

#### Scenario A: Revenue Claim DoS (Balance Inflation)

1. Attacker calls `updateVaultBalance(address(0), 100_000 ether)` — the zero address represents native CAMP
2. `_vaultAccBalances[address(0)]` is now inflated to 100,000 CAMP that **do not exist** in the vault
3. When a legitimate royalty token holder calls `claimRevenue()`, the contract computes:
   ```
   pendingScaled = accBalance * userBalance - debt
   ```
4. The result is inflated far beyond the vault's actual CAMP balance
5. `SafeTransferLib.safeTransferETH(claimer, pending)` tries to transfer non-existent CAMP
6. **Transaction reverts** — legitimate users cannot claim their revenue

#### Scenario B: Marketplace Front-Running

1. A user submits a `buyAccess()` transaction to the Marketplace
2. The attacker **front-runs** this by calling `updateVaultBalance(paymentToken, LARGE_AMOUNT)`
3. When `_distributeRoyalty()` in the Marketplace subsequently calls `vault.updateVaultBalance(paymentToken, REAL_AMOUNT)`, the tracked balance becomes:
   ```
   _vaultAccBalances[token] = INFLATED_AMOUNT + REAL_AMOUNT
   ```
4. All subsequent `claimRevenue()` calls compute incorrect amounts until the accounting is entirely corrupted

---

## Critical Vulnerability #2: `_update()` Unbounded Gas Loop — Permanent DoS

### Location

- **Contract**: `IpRoyaltyVault`
- **File**: `src/royalty/IpRoyaltyVault.sol`
- **Function**: `_update(address from, address to, uint256 amount)`

### Vulnerable Code

```solidity
function _update(address from, address to, uint256 amount) internal override {
    // Handle minting (from == address(0))
    if (from == address(0)) {
        super._update(from, to, amount);
        return;
    }

    // Prevent transfers to self
    if (from == to) revert SameFromToAddress();

    uint256 balanceOfFrom = balanceOf(from);
    uint256 balanceOfTo = balanceOf(to);

    // Update debt for ALL revenue tokens
    address[] memory tokens = _revenueTokens.values();
    for (uint256 i = 0; i < tokens.length; i++) {
        address token = tokens[i];
        // ... SLOAD, arithmetic, SSTORE for EACH token ...
    }

    super._update(from, to, amount);
}
```

### Description

This function is an ERC-20 hook called on **every transfer of royalty tokens**. It iterates over the **entire** `_revenueTokens` set. Since `updateVaultBalance()` (Vulnerability #1) has no access control, an attacker can:

1. Call `updateVaultBalance(fakeToken1, 1)`, `updateVaultBalance(fakeToken2, 1)`, ... with **hundreds or thousands** of fake token addresses
2. Each call adds the fake token to `_revenueTokens` via `EnumerableSet.add()`
3. Now every transfer of royalty tokens must iterate over all fake tokens, each iteration requiring:
   - An SLOAD of `_vaultAccBalances[fakeToken]`
   - An SLOAD of `_claimerRevenueDebt[fakeToken][from]`
   - An SLOAD of `_claimerRevenueDebt[fakeToken][to]`
   - Arithmetic
   - SSTORE operations
4. With **~200+** tokens, the gas cost exceeds the block gas limit

### Impact

**Permanent Denial of Service.** Royalty tokens become **non-transferrable**:
- No selling on secondary markets
- No gifting
- No moving to other wallets
- The royalty vault is effectively dead

---

## High Vulnerability #3: `buyAccess()` Without Reentrancy Guard

### Location

- **Contract**: `Marketplace`
- **Address**: `0x7C969ea45cdA884902102212DDF14f2A33988208`
- **File**: `src/Marketplace.sol`
- **Function**: `buyAccess()`

### Detail

```solidity
function buyAccess(
    address buyer,
    uint256 tokenId,
    uint256 expectedPrice,
    uint32 expectedDuration,
    address expectedPaymentToken,
    uint16 expectedProtocolFeeBps,
    uint16 expectedAppFeeBps
) external payable whenNotPaused {
    // ... checks ...
    
    // State updated before external calls (good practice)
    subscriptionExpiry[tokenId][buyer] = newExpiry;
    
    // Then external calls happen via:
    _routeNativePayment(tokenId, totalRoyaltyAmount, protocolFee, appFee, appTreasury);
    // OR
    _routeTokenPayment(tokenId, terms.paymentToken, totalRoyaltyAmount, protocolFee, appFee, appTreasury);
}
```

Both `_routeNativePayment()` and `_routeTokenPayment()` eventually call `_distributeRoyalty()` which makes an external call to the royalty vault's `updateVaultBalance()`. While the current vault implementation is trusted, future upgrades or factory-deployed vaults could introduce reentrancy.

### Recommendation

Add `ReentrancyGuardUpgradeable` and the `nonReentrant` modifier.

---

## Medium Vulnerability #4: `resolveDispute()` Fund Loss Risk

### Location

- **Contract**: `DisputeModule`
- **Address**: `0xC228F3928DbeEAa45C4FFEbfB2739De6C2133F8B`
- **File**: `src/modules/DisputeModule.sol`

### Detail

```solidity
function resolveDispute(uint256 id) external {
    // ...
    if (judgement) {
        // Dispute won - return bond to initiator
        SafeTransferLib.safeTransfer(address(disputeToken), dispute.initiator, dispute.bondAmount);
    } else {
        uint256 invalidDisputeReward = dispute.bondAmount - dispute.protocolFeeAmount;
        // Sends reward to IP owner - but if the NFT was burned...
        SafeTransferLib.safeTransfer(address(disputeToken), 
            ipToken.ownerOf(dispute.targetId), invalidDisputeReward);
        SafeTransferLib.safeTransfer(address(disputeToken), msg.sender, dispute.protocolFeeAmount);
    }
}
```

If the IP NFT was transferred or burned during the dispute process:
- `ipToken.ownerOf(dispute.targetId)` will revert (per ERC-721 standard)
- The entire `resolveDispute()` call reverts
- The protocol fee gets stuck

---

## Medium Vulnerability #5: CampPoint Decimal Mismatch

### Location

- **Token 1**: `0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537` — **0 decimals**
- **Token 2**: `0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF` — **18 decimals**

Both use the symbol **`CP`** and name **"CampPoint"** but have incompatible decimal configurations. Any contract or frontend assuming 18 decimals will compute incorrect amounts for the 0-decimal token.

### 🚨 Key finding: These are ERC-1967 proxies with different implementations!

Both tokens are **ERC-1967 upgradeable proxies** (UUPS), NOT plain ERC-20 contracts:

| Property | CP#1 (0-dec) | CP#2 (18-dec) |
|----------|-------------|--------------|
| Proxy address | `0x52DE...B537` | `0xa5C6...40BF` |
| **Implementation** | **`0xac14d9896b0115a078bfb58a14f0fae85983daca`** | **`0xb478c35e230e6b808f4dc2464f44e3e6dcc3c809`** |
| Implementation code size | 21,394 bytes | 20,148 bytes |
| Identical code? | ❌ **NO** — different! | ❌ **NO** — different! |

### 🔴 Critical risk: UUPS upgradeToAndCall

Both implementations contain selector **`0x4f1ef286`** — `upgradeToAndCall(address,bytes)`:

Anyone with `UPGRADER_ROLE` or `DEFAULT_ADMIN_ROLE` can:
1. Call `upgradeToAndCall(newContract, data)`
2. Replace the implementation with arbitrary code
3. Mint unlimited tokens
4. Drain liquidity via the bridge (456.7 CAMP)

### ⚠️ Known limitations

- `hasRole()` — **works** (can check individual addresses)
- `getRoleMember()` — **REVERTS** (not exposed through proxy)
- `owner()` — **REVERTS** (uses AccessControl, not Ownable)
- `mint()` is currently **protected** (requires a role)
- Who holds `MINTER_ROLE` or `DEFAULT_ADMIN_ROLE`: **UNKNOWN**

---

## Observed Contract Inventory

### Core Infrastructure

| Contract | Address | TXs | Status |
|----------|---------|-----|--------|
| Marketplace (v1) | `0x7C969ea45cdA884902102212DDF14f2A33988208` | Some | Active |
| Marketplace (v2) | `0x81BeB79b977cAd2B1d06aFC62b4aABB7611107b4` | 0 | Unused |
| IpNFT (primary) | `0xC4a35ce77b090cb511CEb5622D9A41f9A722e4E4` | — | Active |
| IpRoyaltyVault | `0xb27092564b5434f68706753f9C0ADDC49Ca71dC5` | — | 🛑 VULNERABLE |
| IpRoyaltyVaultFactory | `0xaed623AF25128f3FC39cA855441BC4d9Dbf1AaBB` | — | Active |
| IpRoyaltyVaultFactory | `0x92c29a571CeAC162E9e644EB19B8546317FB2058` | — | Active |
| DisputeModule | `0xC228F3928DbeEAa45C4FFEbfB2739De6C2133F8B` | — | Active |
| AppRegistry | `0x6D7CcaD812A8d7e6898f88350c3c88D9A4f4a176` | — | Active |

### Oracle (Stork/Pyth)

| Contract | Address | Status |
|----------|---------|--------|
| UpgradeableStork | `0x716A7d69eaEEB5A38EC504ad2E4e0Ac02cEAa64C` | 0 TX |
| UpgradeableStork | `0x6e498b02C0036235c8164A502b0eECC7660BD889` | — |
| UpgradeableStork | `0xD8771b6aFD111e83591Db4074F13a08a802F179a` | — |
| UpgradeableStork | `0xbB4105F349072B15e300f3dAeB701EF986ae5372` | — |
| PermissionRegistry | `0x555441aF60c1111660c64c4Ec962b7219275fd94` | — |

### Bridge

| Contract | Address | Status |
|----------|---------|--------|
| CrustySwap | `0x12C3E3B84B75ca4a9388de696621ac5F2Ae36953` | Active |

### Game Contracts

| Contract | Address | Balance |
|----------|---------|---------|
| TicTacToe | `0x7B75f64BFa5BFc9fB45c4b95d0b25A9c8c045356` | 0 |
| GameRoom | `0x41bC74bA2AD289EC615743C1Eea82977427A798B` | 0.5 CAMP |
| GameRoom | `0x88a029A09f3037dA191fbE90E917257B8C5fE29b` | 0.5 CAMP |
| GameRoom | `0x065355AC879A3f4F85C5dd89aA255F8Dd07822B6` | 0.5 CAMP |
| GameRoom | `0x5eddEa35aeDDbc3fccF390B3D4F8D4775bF22FD5` | 1.0 CAMP |
| GameRoom | `0x22E5A26E21Eaac16F4D452392d7D7c1fAa8E0F67` | 1.0 CAMP |

### Tokens

| Token | Address | Decimals | Type |
|-------|---------|----------|------|
| CampPoint #1 | `0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537` | 0 | 🔷 ERC-1967 proxy (UUPS) |
| CampPoint #2 | `0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF` | 18 | 🔷 ERC-1967 proxy (UUPS) |
| wCAMP | `0x1aE9c40eCd2DD6ad5858E5430A556d7aff28A44b` | 18 | ERC-20 |
| WETH | `0xC42BAA20e3a159cF7A8aDFA924648C2a2d59E062` | 18 | ERC-20 |
| WBTC | `0x587aF234D373C752a6F6E9eD6c4Ce871e7528BCF` | 18 | ERC-20 |
| MUSDC | `0x71002dbf6cC7A885cE6563682932370c056aAca9` | 6 | ERC-20 |
| sxUSDC | `0xe9a9aFfb353c2daE8453d041bc849ae5946B996b` | — | ERC-20 |

---

## Recommended Fixes

### 🔴 Critical Fix: Add Access Control to `updateVaultBalance()`

```diff
+ address public authorizedCaller;
+ error UnauthorizedCaller();

+ modifier onlyAuthorized() {
+     if (msg.sender != authorizedCaller && msg.sender != OwnableUpgradeable.owner()) {
+         revert UnauthorizedCaller();
+     }
+     _;
+ }

  function updateVaultBalance(
      address token, 
      uint256 amount
- ) external {
+ ) external onlyAuthorized {
      if (amount == 0) revert ZeroAmount();
      _revenueTokens.add(token);
      _vaultAccBalances[token] += amount;
      emit RevenueTokenAddedToVault(token, amount);
  }
```

### 🔴 Critical Fix: Add Revenue Token Count Limit

```diff
+ uint256 public constant MAX_REVENUE_TOKENS = 50;

  function updateVaultBalance(address token, uint256 amount) 
      external onlyAuthorized 
  {
      if (amount == 0) revert ZeroAmount();
+     if (_revenueTokens.length() >= MAX_REVENUE_TOKENS && !_revenueTokens.contains(token)) {
+         revert TooManyRevenueTokens();
+     }
      _revenueTokens.add(token);
      _vaultAccBalances[token] += amount;
      emit RevenueTokenAddedToVault(token, amount);
  }
```

### 🟠 Fix: Add Reentrancy Guard to Marketplace

```diff
+ import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

  contract Marketplace is
      UUPSUpgradeable,
      RoyaltyModule,
      OwnableUpgradeable,
-     PausableUpgradeable
+     PausableUpgradeable,
+     ReentrancyGuardUpgradeable
  {
      // ...
      function buyAccess(...)
-         external payable whenNotPaused {
+         external payable whenNotPaused nonReentrant {
```

### 🟡 Fix: Snapshot Dispute Target Owner

```diff
  function resolveDispute(uint256 id) external {
      Dispute memory dispute = disputes[id];
+     address targetOwner = ipToken.ownerOf(dispute.targetId);
      // ...
      SafeTransferLib.safeTransfer(address(disputeToken),
-         ipToken.ownerOf(dispute.targetId),
+         targetOwner,
          invalidDisputeReward);
  }
```

---

*Report generated by autonomous AI security analysis of on-chain verified source code, with on-chain verification of key findings.*

---

**🌐 Русская версия:** [`SECURITY_REPORT_RU.md`](SECURITY_REPORT_RU.md)
