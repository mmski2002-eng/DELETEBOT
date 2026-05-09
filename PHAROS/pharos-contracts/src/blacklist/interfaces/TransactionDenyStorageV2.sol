// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {TransactionDenyStorageV1} from "./TransactionDenyStorageV1.sol";

/**
 * @title Storage for TransactionDeny V2
 * @notice Adds indexed position mapping for O(1) blacklist address removal
 * @dev This storage version adds:
 * - blacklistIndex_: Maps address to its index position in _blacklistedAddresses array
 * This enables O(1) removal using swap-and-pop instead of O(n) linear search
 */
abstract contract TransactionDenyStorageV2 is TransactionDenyStorageV1 {
    // Position mapping for O(1) removal from _blacklistedAddresses array
    // address => index position in _blacklistedAddresses
    mapping(address account => uint256 index) public blacklistIndex_;

    // Flag to prevent duplicate V1 to V2 migrations
    bool public v1ToV2Migrated;
}
