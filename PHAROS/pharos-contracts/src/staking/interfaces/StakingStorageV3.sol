// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {StakingStorageV2} from "./StakingStorageV2.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title Storage for Staking V3
 * @notice Adds indexed mappings for O(1) user undelegation lookups and fixes delegation reward timing
 * @dev This storage version adds:
 * - userUndelegationIndices: Maps delegator to array of indices in pendingUndelegations
 * - userUndelegationHead: Tracks current read position for each user
 * - undelegationReverseIndex: Maps global pendingUndelegations index to position in userUndelegationIndices
 * These enable O(k) lookups for claimStake and O(n) cleanup in _processDelegatorWithdrawals
 * where k = number of user's undelegations, instead of O(n×k)
 *
 * - historicalRPS: Records accumulatedRewardPerShare at each epoch boundary
 * - pendingActivationEpoch: Tracks when each delegator's pending stake will activate
 * These fix the critical delegation reward timing vulnerability where users would receive
 * rewards for epochs where their stake wasn't in the snapshot
 */
abstract contract StakingStorageV3 is StakingStorageV2 {
    // Index mapping for O(1) user lookup in pendingUndelegations
    // delegator => array of indices in pendingUndelegations
    mapping(address delegator => uint256[] undelegationIndices) public userUndelegationIndices;

    // Helper mapping to track current position in array for skipping processed entries
    // delegator => current read position (head pointer)
    mapping(address delegator => uint256 headPosition) public userUndelegationHead;

    // Reverse index mapping for O(1) index updates during cleanup
    // global pendingUndelegations index => position in userUndelegationIndices[user]
    // Example: undelegationReverseIndex[5] = 2 means pendingUndelegations[5] is at userUndelegationIndices[user][2]
    mapping(uint256 globalIndex => uint256 positionInUserArray) public undelegationReverseIndex;

    /**
     * @notice Historical RPS data for a specific epoch and pool
     * @dev Used to set correct entry point for newly activated stakes
     */
    struct EpochRPS {
        uint256 rps; // accumulatedRewardPerShare at this epoch's start
        uint256 refcount; // Number of delegators waiting to activate at this epoch
    }

    /**
     * @notice Mapping from epoch to poolId to historical RPS data
     * @dev Only stores entries with refcount > 0 to save gas
     * Format: epoch => poolId => EpochRPS
     */
    mapping(uint256 epoch => mapping(bytes32 poolId => EpochRPS)) public historicalRPS;

    /**
     * @notice Set of pool IDs that need RPS recording at next epoch boundary
     * @dev Used to optimize _advanceEpoch by only iterating pools with new pending stakes
     * instead of all active pools. Cleared after each epoch.
     */
    EnumerableSet.Bytes32Set internal poolsNeedingRPSRecord;

    /**
     * @notice Tracks when each delegator's pending stake will activate
     * @dev Maps poolId => delegator => activation epoch
     * Used in conjunction with Delegator.pendingStake to implement delayed activation
     */
    mapping(bytes32 poolId => mapping(address delegator => uint256 activationEpoch)) public pendingActivationEpoch;
    mapping(bytes32 poolId => EnumerableSet.AddressSet) internal poolDelegators;

    /**
     * @notice Pending commission rate change request
     * @dev Stores the new rate and the epoch at which it becomes effective
     */
    struct PendingCommissionRate {
        uint256 newRate;
        uint256 effectiveEpoch; // 0 means no pending change
    }

    /**
     * @notice Delay in epochs before a commission rate change takes effect
     */
    uint256 public constant DEFAULT_COMMISSION_RATE_DELAY = 10;

    /**
     * @notice Pending commission rate changes per pool
     * @dev Maps poolId => pending commission rate change
     */
    mapping(bytes32 poolId => PendingCommissionRate) public pendingCommissionRates;

    /**
     * @notice Set of pool IDs with pending commission rate changes
     */
    EnumerableSet.Bytes32Set internal pendingCommissionRatePools;
}
