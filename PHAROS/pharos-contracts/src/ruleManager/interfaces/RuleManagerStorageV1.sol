// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {IRuleManager} from "./IRuleManager.sol";

/**
 * @title Storage for RuleManager
 * @notice For future upgrades, do not change RuleManagerStorageV1. Create a new
 * contract which implements RuleManagerStorageV1
 */
abstract contract RuleManagerStorageV1 is IRuleManager {
    // slot 0
    mapping(uint64 ruleId => InferRule rule) rules_;
    // slot 1
    mapping(address contractAddress => uint64[] ruleIds) contractRules_;
    // slot 2
    uint64[] activeIds_;
    // slot 3
    uint64[] waitProveRules_;
    // slot 4
    uint64[] successRules_;

    // slot 5
    uint64 nextId_;
    uint32 proveThreshold_; // Number of verified transactions required for rule from IN_PROVING to PROVING_SUCCESS

    // @deprecated Kept for storage layout compatibility. Use ERC1967Utils.getImplementation() instead.
    address private __deprecated_implAddress;
}
