// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AfterExecuteHook } from "@gotchipus/sdk/contracts/base/BaseHook.sol";
import { IHook } from "@gotchipus/sdk/contracts/interfaces/IHook.sol";

contract RewardHook is AfterExecuteHook {
    address public rewardToken;
    uint256 public rewardAmount;
    
    mapping(uint256 => uint256) public totalRewards;
    
    event RewardDistributed(uint256 indexed tokenId, address indexed recipient, uint256 amount);

    constructor(address _gotchipus, address _rewardToken, uint256 _rewardAmount) 
        AfterExecuteHook(_gotchipus) 
    {
        rewardToken = _rewardToken;
        rewardAmount = _rewardAmount;
    }

    function _afterExecute(IHook.HookParams calldata params) internal override {
        if (!params.success || rewardAmount == 0) return;

        // Transfer reward token to caller
        (bool success,) = rewardToken.call(
            abi.encodeWithSignature("transfer(address,uint256)", params.caller, rewardAmount)
        );
        
        if (success) {
            totalRewards[params.tokenId] += rewardAmount;
            emit RewardDistributed(params.tokenId, params.caller, rewardAmount);
        }
    }
}