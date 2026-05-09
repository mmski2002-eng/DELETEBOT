// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {IStaking} from "./IStaking.sol";
import {IChainConfig} from "../../chainConfig/interfaces/IChainConfig.sol";

/**
 * @title Storage for Staking
 * @notice For future upgrades, do not change StakingStorageV1. Create a new
 * contract which implements StakingStorageV1
 */
abstract contract StakingStorageV1 is IStaking {
    mapping(bytes32 poolId => Validator validator) public validators;
    bytes32[] public activePoolIds;
    bytes32[] public pendingAddPoolIds;
    bytes32[] public pendingUpdatePoolIds;
    bytes32[] public pendingExitPoolIds;

    uint256 public constant MIN_DELEGATOR_STAKE = 1 ether;
    uint256 public constant MIN_REGISTRATION_STAKE = 100 ether;
    uint256 public constant MIN_POOL_STAKE = 1000000 ether;
    uint256 public constant MAX_POOL_STAKE = 50000000 ether;
    uint256 public constant MAX_QUEUE_LENGTH = 1000;

    uint256 public currentEpoch;
    uint256 public totalStake;

    IChainConfig public cfg;

    mapping(address delegator => uint256 pendingStake) public pendingWithdrawStakes;

    uint256 public totalSupply;
    uint256 public currentInflationRate;
    uint256 public lastInflationAdjustmentTime;
    uint256 public lastInflationTotalSupplySnapshot;

    // @deprecated Kept for storage layout compatibility. Use ERC1967Utils.getImplementation() instead.
    address internal implAddress;
}
