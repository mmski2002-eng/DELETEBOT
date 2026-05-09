# 🔴 Camp Network — Critical Security PoC

## Vulnerability: `IpRoyaltyVault.updateVaultBalance()` Missing Access Control

### Overview

**Severity**: 🔴 CRITICAL  
**CVSS Score**: 9.3 (AV:N/AC:L/PR:N/UI:N/S:C/C:N/I:H/A:H)  
**Contract**: `IpRoyaltyVault`  
**Address**: [`0xb27092564b5434f68706753f9C0ADDC49Ca71dC5`](https://basecamp.cloud.blockscout.com/address/0xb27092564b5434f68706753f9C0ADDC49Ca71dC5)  
**Vulnerable Function**: `updateVaultBalance(address,uint256)`

### The Bug

```solidity
// NO access control modifier! Anyone can call this.
function updateVaultBalance(address token, uint256 amount) external {
    // "In production, you'd want more sophisticated access control"
    if (amount == 0) revert ZeroAmount();
    _revenueTokens.add(token);
    _vaultAccBalances[token] += amount;
}
```

### Exploit Vectors

| # | Attack | Impact |
|---|--------|--------|
| 1 | **Balance Inflation** | Corrupt revenue accounting, DoS on claims |
| 2 | **Gas Griefing** | Permanent freeze of all royalty tokens |
| 3 | **Front-Running** | Marketplace accounting corruption |

### Usage

#### 1. Local Test (Hardhat) ✅ Recommended

```bash
cd CAMP

# Install dependencies (if not done yet)
npm install

# Run all tests
npx hardhat test

# Run with verbose output
npx hardhat test --verbose

# Run a specific test
npx hardhat test --grep "FULL EXPLOIT"
```

#### 2. Local Test (Foundry)

> ⚠️ Requires Foundry installation: https://book.getfoundry.sh/getting-started/installation

```bash
cd CAMP

# Run all tests
forge test -vvv

# Run a specific test
forge test --match-test test_FullExploitScenario -vvv

# Run with gas report
forge test --gas-report
```

#### 3. Test Against Real Network

```bash
# Requires RPC access to Camp Network
npx hardhat test --network campNetwork
```

Or with Foundry:
```bash
forge test --fork-url https://rpc.basecamp.t.raas.gelato.cloud -vvv
```

#### 4. Deploy the Exploit

```bash
# Deploy PoC_Exploit contract to Camp Network using Hardhat
npx hardhat run scripts/deploy.js --network campNetwork
```

### Real On-Chain Evidence

Check the vault's actual state on Camp Network:

```bash
# Check current tracked ETH balance
cast call 0xb27092564b5434f68706753f9C0ADDC49Ca71dC5 \
    "vaultAccBalance(address)(uint256)" \
    0x0000000000000000000000000000000000000000 \
    --rpc-url https://rpc.basecamp.t.raas.gelato.cloud

# Check how many revenue tokens are tracked
cast call 0xb27092564b5434f68706753f9C0ADDC49Ca71dC5 \
    "getRevenueTokens()(address[])" \
    --rpc-url https://rpc.basecamp.t.raas.gelato.cloud

# Check via Hardhat console
npx hardhat console --network campNetwork
> const vault = await ethers.getContractAt("IIpRoyaltyVault", "0xb27092564b5434f68706753f9C0ADDC49Ca71dC5")
> const balance = await vault.vaultAccBalance("0x0000000000000000000000000000000000000000")
> console.log(ethers.formatEther(balance))
```

### Project Structure

```
CAMP/
├── hardhat.config.js          # Hardhat configuration
├── foundry.toml               # Foundry configuration
├── package.json               # Node.js dependencies
├── README.md                  # This file
├── SECURITY_REPORT.md         # Full security audit report
├── contracts/
│   ├── IpRoyaltyVault.sol     # Interface for the vulnerable contract
│   ├── MockRoyaltyVault.sol   # Mock vault for local Hardhat testing
│   └── PoC_Exploit.sol        # Exploit implementation
├── src/
│   ├── IpRoyaltyVault.sol     # Interface (also used by Foundry)
│   └── PoC_Exploit.sol        # Exploit (also used by Foundry)
├── test/
│   ├── PoC_Test.t.sol         # Foundry test suite
│   └── PoC_Test.js            # Hardhat test suite ✅
└── scripts/
    └── deploy.js              # Deployment script
```

### Timeline

| Date | Event |
|------|-------|
| 2025-07-05 | Vulnerability discovered during code audit |
| 2025-07-05 | PoC created |
| — | Reported to Camp Network team |

### Disclaimer

This PoC is for **educational and security research purposes only**. 
Do not use against any deployed contracts without explicit authorization.
