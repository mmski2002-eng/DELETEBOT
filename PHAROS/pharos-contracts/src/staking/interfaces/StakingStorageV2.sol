// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {StakingStorageV1} from "./StakingStorageV1.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title Storage for Staking
 * @notice For future upgrades, do not change StakingStorageV1. Create a new
 * contract which implements StakingStorageV1
 */
abstract contract StakingStorageV2 is StakingStorageV1 {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    uint256 public constant DEFAULT_WITHDRAW_WINDOW = 84; // Default to 84 epochs
    uint256 public constant COMMISSION_SCALE = 10000;
    uint256 public constant PRECISION = 1e27;
    uint256 public constant DEFAULT_COMMISSION_RATE = 1000;
    uint256 public constant MAX_COMMISSION_RATE = 2000; // Maximum 20% commission rate to prevent exploitative rates

    mapping(bytes32 poolId => mapping(address delegator => Delegator info)) public delegators;
    mapping(bytes32 poolId => mapping(address delegator => bool isWhitelisted)) public validatorWhitelists;
    mapping(bytes32 poolId => uint256 rewardPerShare) public accumulatedRewardPerShares;
    mapping(bytes32 poolId => uint256 commissionRate) public commissionRates;
    mapping(bytes32 poolId => bool delegationEnabled) public delegationEnabledMapping;
    mapping(bytes32 poolId => uint256 delegatorCount) public delegatorCounts;

    PendingUndelegation[] public pendingUndelegations;

    // Sets to manage pool IDs instead of arrays in the StakingStorageV1
    EnumerableSet.Bytes32Set internal activePoolSets;
    EnumerableSet.Bytes32Set internal pendingAddPoolSets;
    EnumerableSet.Bytes32Set internal pendingUpdatePoolSets;
    EnumerableSet.Bytes32Set internal pendingExitPoolSets;

    // Migration flag to track V1 to V2 data migration status
    bool public v1ToV2Migrated;

    // for slot compatible
    uint256 lastEpochStartTime;
}
