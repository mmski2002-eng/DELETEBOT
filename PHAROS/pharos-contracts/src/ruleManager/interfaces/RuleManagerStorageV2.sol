// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {RuleManagerStorageV1} from "./RuleManagerStorageV1.sol";

/**
 * @title Storage for RuleManager V2
 * @notice Adds indexed position mappings for O(1) rule removal and lookups
 * @dev This storage version adds:
 * - Position index mappings for O(1) removal from arrays (swap-and-pop pattern)
 * - Fast existence check mapping for O(1) rule existence verification
 * These enable O(1) operations instead of O(n) for delRule, updateRule, and checkExist
 */
abstract contract RuleManagerStorageV2 is RuleManagerStorageV1 {
    // Position mappings for O(1) removal from arrays using swap-and-pop
    // ruleId => index position in the respective array
    mapping(uint64 ruleId => uint256 index) public ruleIndexInActiveIds_;
    mapping(uint64 ruleId => uint256 index) public ruleIndexInWaitProve_;
    mapping(uint64 ruleId => uint256 index) public ruleIndexInSuccess_;
    mapping(uint64 ruleId => uint256 index) public ruleIndexInContract_;

    // Fast existence check mapping for O(1) rule verification
    // contractAddress => selector => metahash => exists
    mapping(address contractAddress => mapping(bytes4 selector => mapping(bytes32 metahash => bool))) public
        ruleExists_;
}
