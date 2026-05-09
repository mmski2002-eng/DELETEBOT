// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {StakingStorageV3} from "./StakingStorageV3.sol";

/**
 * @title Storage for Staking V4
 * @notice Adds delegation approver mechanism
 * @dev This storage version adds:
 * - delegationApprover: per-pool approver address controlling delegation access
 *   address(0) = open delegation (anyone can delegate)
 *   non-zero   = must present a valid EIP-712 DelegationApproval signature from this address
 * - delegationApprovalNonces: per-(pool, delegator) nonce for EIP-712 replay prevention
 *   incremented on each successful delegateWithApproval() call
 *
 * This replaces the previous validatorWhitelists mechanism with a more flexible,
 * gas-efficient off-chain approval flow compatible with KYC scenarios.
 */
abstract contract StakingStorageV4 is StakingStorageV3 {
    /**
     * @notice Delegation approver address per pool
     * @dev address(0) = open mode (anyone may delegate via delegate())
     *      non-zero   = approval mode (must use delegateWithApproval() with approver's EIP-712 sig)
     * Settable by validator owner or the current approver (for key rotation).
     */
    mapping(bytes32 poolId => address approver) public delegationApprover;

    /**
     * @notice Per-delegator nonce for delegation approval signatures
     * @dev Incremented after each successful delegateWithApproval() call.
     * Approver must include the current nonce when signing; prevents signature replay.
     */
    mapping(bytes32 poolId => mapping(address delegator => uint256 nonce)) public delegationApprovalNonces;
}
