NOTE: smart contract interaction diagrams can be found at [/misc/pics](/misc/pics)

# Storm Trade TON contracts

Welcome to the Storm Trade repository! This repository contains the smart contract code for the first perpetual futures decentralized exchange (DEX) protocol on the TON blockchain. Storm Trade allows users to trade futures contracts with no expiration date, providing a unique trading experience compared to traditional futures exchanges. The platform's aim is to provide a secure, transparent, and efficient trading environment for its users.

This repository contains the smart contract code for Storm Trade written in FunС programming language, as well as the tests and scripts written in Typescript.

## Architecture overview

Hackaton protocol smart contracts system consists of three key components:

- `Position manager`. Sharded smart contract. It contains the latest long and/or short position and orders for a specific trader. It provides its data every time a request is sent to the vAMM contract, which implies a change in trader position data. Afrer every `provide_position` request contract locks it data, waiting for vAMM's response to prevent double spending or data inconsistency caused by asynchronous TON architecture. Contract unlocks it's state after `unlock_position` or `update_position` vAMM's messages.
- `vAMM`. Handles all the exchange operations with corresponding handler, position data and oracle price

### vAMM main handlers:

- `increase_position`: This function allows users to open a new position or increase their opened position in a perpetual futures contract by buying more of the underlying asset. Takes `amount`, `direction`, `leverage`, `min_base_asset_amount`, previous `position_ref` and last oracle `price_ref`.

- `add_margin`: This function allows users to add more collateral to their open position in order to increase their margin and reduce the risk of liquidation. This function allows users to open a new position or increase their opened position in a perpetual futures contract by buying more of the underlying asset. Takes `amount`, previous `position_ref` and last oracle `price_ref`.

- `close_position`: This function allows users to close their open position in a perpetual futures contract by selling the underlying asset. Takes `_size`, `_minQuoteAssetAmount`, flag `_addToMargin`, previous `position_ref` and last oracle `price_ref`.

- `remove_margin`: This function allows users to withdraw excess collateral from their open position. Takes `_amount`, previous `position_ref` and last oracle `price_ref`.

- `pay_funding`: This function allows users to pay the funding rate for holding a perpetual futures position. Perpetual futures contracts typically have a funding rate that is paid periodically to ensure that the price of the futures contract stays in line with the underlying asset. Takes last oracle `price_ref`.

- `liquidate`: : This function allows the exchange to automatically liquidate a user's open position if it becomes under-collateralized. Can be called by anyone. Takes `to_liquidate_address`, previous `position_ref` and the last oracle `price_ref`.

## Layout

This project was bootstraped using [Blueprint](https://github.com/ton-community/Blueprint) 💙

- `contracts` - contains the source code of all the smart contracts of the project and their dependencies.
- `wrappers` - contains the wrapper classes (implementing `Contract` from ton-core) for the contracts, including any [de]serialization primitives and compilation functions.
- `tests` - tests for the contracts.
- `scripts` - contains scripts used by the project, mainly the deployment scripts.

## How to use

- Clone this repo
- Run `yarn install`

### Testing

Run tests:

```sh
yarn test
```

Tests are writen with [@ton-community/sandbox](https://github.com/ton-community/sandbox).

# License

MIT
