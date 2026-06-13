# System Contracts

Smart contract system for managing blockchain configuration, rules, access control, and staking functionality.

## Overview

This repository contains core system contracts built with Solidity and Foundry, providing:

- **ChainConfig** - Blockchain configuration management
- **RuleManager** - Rule governance and enforcement
- **TransactionDeny** - Transaction blacklist control
- **Staking** - Proof-of-stake mechanism implementation

## Requirements

- [Foundry](https://getfoundry.sh/) installed
- Solidity 0.8.22

## Installation

```bash
forge install
```

## Usage

### Build

Compile all contracts with IR-based optimization:

```bash
make build
# or
forge build --via-ir --extra-output storageLayout
```

### Test

Run the full test suite:

```bash
make test
# or
forge test --via-ir -vvv
```

### Format

Format all Solidity files:

```bash
make fmt
# or
forge fmt
```

## Project Structure

```
src/
├── chainConfig/          # Chain configuration contracts
├── ruleManager/          # Rule management contracts
├── blacklist/            # Transaction denylist contracts
├── staking/              # Staking mechanism contracts
└── TransparentUpgradeableProxy.sol
```

## Configuration

See `foundry.toml` for build settings and compiler options.

## License

MIT
