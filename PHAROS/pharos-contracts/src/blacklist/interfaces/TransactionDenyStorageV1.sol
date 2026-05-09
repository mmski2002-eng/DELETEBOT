// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {ITransactionDeny} from "./ITransactionDeny.sol";

/**
 * @title Storage for TransactionDeny
 * @notice For future upgrades, do not change TransactionDenyStorageV1. Create a new
 * contract which implements TransactionDenyStorageV1
 */
abstract contract TransactionDenyStorageV1 is ITransactionDeny {
    mapping(address account => bool isBlacklisted) _blacklisted;
    address[] _blacklistedAddresses;
}
