// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {IChainConfig} from "./IChainConfig.sol";

/**
 * @title Storage for ChainConfig
 * @notice For future upgrades, do not change ChainConfigStorageV1. Create a new
 * contract which implements ChainConfigStorageV1
 */
abstract contract ChainConfigStorageV1 is IChainConfig {
    address public stakingAddress;
    ConfigCheckpoint[] configCps;
    uint256 public constant MAX_CONFIGCP_VERSIONS = 3;
    Config[] pendingActiveConfigs;

    // @deprecated Kept for storage layout compatibility. Use ERC1967Utils.getImplementation() instead.
    address private __deprecated_implAddress;
}
