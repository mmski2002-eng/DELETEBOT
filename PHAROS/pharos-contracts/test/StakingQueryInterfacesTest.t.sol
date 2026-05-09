// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

/**
 * @title StakingQueryInterfacesTest
 * @notice Unit tests for extended query interfaces
 */
contract StakingQueryInterfacesTest is Test {
    ChainConfig private chainConfig;
    TransparentUpgradeableProxy chainConfigProxy;
    Staking private staking;
    TransparentUpgradeableProxy private stakingProxy;
    RuleManager private ruleManager;
    TransparentUpgradeableProxy private ruleManagerProxy;
    address admin = address(0x1111111111111111111111111111111111111111);
    address stakingAddress = address(0x2);
    address intrinsicAddress = admin;

    address public validator1 = address(0x4);
    address public validator2 = address(0x5);
    address public validator3 = address(0x6);
    address public delegator1 = address(0x7);
    address public delegator2 = address(0x8);
    address public delegator3 = address(0x9);

    string public constant DESCRIPTION = "Test Validator";
    string public constant DESCRIPTION2 = "Test Validator 2";
    string public constant DESCRIPTION3 = "Test Validator 3";
    string public constant PUBLIC_KEY1 = "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f";
    string public constant PUBLIC_KEY2 = "0x04b34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5a";
    string public constant PUBLIC_KEY3 = "0x04c34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5b";
    string public constant PUBLIC_KEY_POP = "0xproof1";
    string public constant BLS_PUBLIC_KEY = "0xblskey1";
    string public constant BLS_PUBLIC_KEY_POP = "0xblspop1";
    string public constant ENDPOINT1 = "http://test.validator1";
    string public constant ENDPOINT2 = "http://test.validator2";
    string public constant ENDPOINT3 = "http://test.validator3";

    uint256 public constant MIN_VALIDATOR_STAKE = 1 ether;
    uint256 public constant MIN_DELEGATOR_STAKE = 1 ether;

    function setUp() public {
        vm.startPrank(admin);
        chainConfig = new ChainConfig();
        ruleManager = new RuleManager();
        staking = new Staking();

        // Deploy ChainConfig proxy first (with temporary staking address)
        bytes memory chainConfigInitData =
            abi.encodeWithSelector(ChainConfig.initialize.selector, admin, address(staking));
        chainConfigProxy = new TransparentUpgradeableProxy(address(chainConfig), chainConfigInitData);
        chainConfig = ChainConfig(address(chainConfigProxy));

        // Deploy RuleManager proxy
        bytes memory ruleManagerInitData = abi.encodeWithSelector(RuleManager.initialize.selector, admin, 1000);
        ruleManagerProxy = new TransparentUpgradeableProxy(address(ruleManager), ruleManagerInitData);
        ruleManager = RuleManager(address(ruleManagerProxy));

        // Deploy Staking proxy with chainConfig proxy address
        bytes memory stakingInitData = abi.encodeWithSelector(Staking.initialize.selector, admin, address(chainConfig));
        stakingProxy = new TransparentUpgradeableProxy(address(staking), stakingInitData);
        staking = Staking(payable(address(stakingProxy)));

        // Now update ChainConfig to point to the Staking proxy address
        chainConfig.updateStakingAddress(address(staking));

        vm.stopPrank();

        // Configure ChainConfig with test values
        string[] memory keys = new string[](6);
        string[] memory values = new string[](6);
        keys[0] = "staking.min_staking_pool_value";
        values[0] = vm.toString(MIN_VALIDATOR_STAKE);
        keys[1] = "staking.max_staking_pool_value";
        values[1] = vm.toString(uint256(100000000 ether));
        keys[2] = "staking.min_delegator_stake";
        values[2] = vm.toString(MIN_DELEGATOR_STAKE);
        keys[3] = "staking.withdraw_effective_epoch";
        values[3] = "1";
        keys[4] = "staking.delegation_withdraw_effective_epoch";
        values[4] = "1";
        keys[5] = "staking.min_staking_registration_value";
        values[5] = vm.toString(MIN_VALIDATOR_STAKE);

        vm.prank(address(staking));
        chainConfig.setConfig(keys, values);

        // Advance block to make configs effective (required by effectiveBlockNum validation)
        vm.roll(block.number + 1);
    }

    function advanceEpoch() public {
        // Advance block.number to ensure new config checkpoints are properly indexed
        vm.roll(block.number + 1);
        // Advance time by epoch duration
        vm.warp(block.timestamp + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch();
    }

    // ==================== Test getValidator ====================

    function test_GetValidator_ActiveValidator() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        IStaking.Validator memory validator = staking.getValidator(poolId);

        assertEq(validator.poolId, poolId, "Pool ID should match");
        assertEq(validator.description, DESCRIPTION, "Description should match");
        assertEq(validator.publicKey, PUBLIC_KEY1, "Public key should match");
        assertEq(validator.status, 1, "Status should be active (1)");
        assertEq(validator.totalStake, MIN_VALIDATOR_STAKE, "Total stake should match");
        assertEq(validator.owner, validator1, "Owner should match");
    }

    function test_GetValidator_NonExistentValidator() public view {
        bytes32 fakePoolId = bytes32(uint256(1));

        IStaking.Validator memory validator = staking.getValidator(fakePoolId);

        assertEq(validator.poolId, bytes32(0), "Non-existent validator should return zero pool ID");
    }

    // ==================== Test getAllValidators ====================

    function test_GetAllValidators_MixedStates() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        vm.prank(validator2);
        vm.deal(validator2, MIN_VALIDATOR_STAKE);
        bytes32 poolId2 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION2, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        advanceEpoch();

        bytes32[] memory allValidators = staking.getAllValidators();

        assertEq(allValidators.length, 2, "Should have 2 validators");

        // Check that both poolIds are in the result
        bool found1 = false;
        bool found2 = false;
        for (uint256 i = 0; i < allValidators.length; i++) {
            if (allValidators[i] == poolId1) found1 = true;
            if (allValidators[i] == poolId2) found2 = true;
        }
        assertTrue(found1, "First validator should be in the list");
        assertTrue(found2, "Second validator should be in the list");
    }

    function test_GetAllValidators_WithExitingValidator() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        vm.prank(validator1);
        staking.exitValidator(poolId1);

        bytes32[] memory allValidators = staking.getAllValidators();

        assertEq(allValidators.length, 1, "Should have 1 validator (pending exit)");
        assertEq(allValidators[0], poolId1, "Validator should match");
    }

    // ==================== Test getValidatorCounts ====================

    function test_GetValidatorCounts_InitialState() public view {
        (uint256 activeCount, uint256 inactiveCount, uint256 pendingExitCount) = staking.getValidatorCounts();

        assertEq(activeCount, 0, "Active count should be 0");
        assertEq(inactiveCount, 0, "Inactive count should be 0");
        assertEq(pendingExitCount, 0, "Pending exit count should be 0");
    }

    function test_GetValidatorCounts_MixedStates() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        vm.prank(validator2);
        vm.deal(validator2, MIN_VALIDATOR_STAKE);
        bytes32 poolId2 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION2, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        advanceEpoch();

        vm.prank(validator3);
        vm.deal(validator3, MIN_VALIDATOR_STAKE);
        bytes32 poolId3 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION3, PUBLIC_KEY3, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT3
        );

        advanceEpoch();

        vm.prank(validator3);
        staking.exitValidator(poolId3);

        // Verify validators 1 and 2 are active, and 3 is pending exit
        // Note: poolId3 remains in active set until epoch advance processes the exit
        assertTrue(staking.isValidatorActive(poolId1), "Validator 1 should be active");
        assertTrue(staking.isValidatorActive(poolId2), "Validator 2 should be active");
        assertTrue(staking.isValidatorActive(poolId3), "Validator 3 should still be active until epoch advance");
        assertTrue(staking.isValidatorPendingExit(poolId3), "Validator 3 should be pending exit");

        (uint256 activeCount, uint256 inactiveCount, uint256 pendingExitCount) = staking.getValidatorCounts();

        // All 3 validators are still active (exit not yet processed by epoch advance)
        assertEq(activeCount, 3, "Active count should be 3 (exit not yet processed)");
        assertEq(inactiveCount, 0, "Inactive count should be 0");
        assertEq(pendingExitCount, 1, "Pending exit count should be 1");

        // Advance epoch to process the exit
        advanceEpoch();

        // Now poolId3 should be removed from active set
        (activeCount, inactiveCount, pendingExitCount) = staking.getValidatorCounts();

        assertEq(activeCount, 2, "Active count should be 2 after epoch advance");
        assertEq(inactiveCount, 0, "Inactive count should be 0");
        assertEq(pendingExitCount, 0, "Pending exit count should be 0 (pool removed)");
    }

    // ==================== Test getBlockchainInfo ====================

    function test_GetBlockchainInfo_InitialState() public view {
        (uint256 currentEpoch, uint256 currentBlock, uint256 totalStake) = staking.getBlockchainInfo();

        assertEq(currentEpoch, 0, "Initial epoch should be 0");
        assertEq(currentBlock, block.number, "Block number should match");
        assertEq(totalStake, 0, "Total stake should be 0");
    }

    function test_GetBlockchainInfo_AfterValidatorActivation() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        (uint256 currentEpoch, uint256 currentBlock, uint256 totalStake) = staking.getBlockchainInfo();

        assertEq(currentEpoch, 1, "Epoch should be 1 after advance");
        assertEq(currentBlock, block.number, "Block number should match");
        assertEq(totalStake, MIN_VALIDATOR_STAKE, "Total stake should match validator stake");

        // Verify the validator is actually active
        assertTrue(staking.isValidatorActive(poolId), "Validator should be active");
    }

    // ==================== Test getUserTotalInfo ====================

    function test_GetUserTotalInfo_ValidatorOwner() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        // Verify the validator is active
        assertTrue(staking.isValidatorActive(poolId), "Validator should be active");

        (uint256 totalStake, uint256 totalRewards, uint256 totalClaimed) = staking.getUserTotalInfo(validator1);

        assertEq(totalStake, MIN_VALIDATOR_STAKE, "Total stake should match");
        assertEq(totalRewards, 0, "Rewards should be 0 initially");
        assertEq(totalClaimed, 0, "Claimed should be 0");
    }

    function test_GetUserTotalInfo_DelegatorWithRewards() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Advance epoch to activate pending stake
        advanceEpoch();

        // Trigger lazy activation
        vm.prank(delegator1);
        staking.settleReward(poolId);

        (uint256 totalStake, uint256 totalRewards, uint256 totalClaimed) = staking.getUserTotalInfo(delegator1);

        assertEq(totalStake, MIN_DELEGATOR_STAKE, "Total stake should match");
        assertEq(totalRewards, 0, "Rewards should be 0 initially");
        assertEq(totalClaimed, 0, "Claimed should be 0");
    }

    function test_GetUserTotalInfo_MultipleValidators() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        vm.prank(validator2);
        vm.deal(validator2, MIN_VALIDATOR_STAKE);
        bytes32 poolId2 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION2, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        advanceEpoch();

        vm.startPrank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE * 2);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId2);
        vm.stopPrank();

        // Advance epoch to activate pending stakes
        advanceEpoch();

        // Trigger lazy activation for both pools
        vm.startPrank(delegator1);
        staking.settleReward(poolId1);
        staking.settleReward(poolId2);
        vm.stopPrank();

        (uint256 totalStake, uint256 totalRewards, uint256 totalClaimed) = staking.getUserTotalInfo(delegator1);

        assertEq(totalStake, MIN_DELEGATOR_STAKE * 2, "Total stake should sum across validators");
        assertEq(totalRewards, 0, "Rewards should be 0 initially");
        assertEq(totalClaimed, 0, "Claimed should be 0");
    }

    // ==================== Test getUserValidators ====================

    function test_GetUserValidators_SingleValidator() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        (bytes32[] memory poolIds, uint256[] memory stakes, uint256[] memory rewards) =
            staking.getUserValidators(validator1);

        assertEq(poolIds.length, 1, "Should have 1 validator");
        assertEq(poolIds[0], poolId, "Pool ID should match");
        assertEq(stakes[0], MIN_VALIDATOR_STAKE, "Stake should match");
        assertEq(rewards[0], 0, "Rewards should be 0");
    }

    function test_GetUserValidators_MultipleValidators() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        vm.prank(validator2);
        vm.deal(validator2, MIN_VALIDATOR_STAKE);
        bytes32 poolId2 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION2, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        advanceEpoch();

        // Verify both validators are active
        assertTrue(staking.isValidatorActive(poolId1), "Validator 1 should be active");
        assertTrue(staking.isValidatorActive(poolId2), "Validator 2 should be active");
        assertEq(staking.getActiveValidatorCount(), 2, "Should have 2 active validators");

        vm.startPrank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE * 2);

        // Delegate to both validators
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId2);
        vm.stopPrank();

        // Advance epoch to activate pending stakes
        advanceEpoch();

        // Trigger lazy activation for both pools
        vm.startPrank(delegator1);
        staking.settleReward(poolId1);
        staking.settleReward(poolId2);
        vm.stopPrank();

        // Check stake was recorded in pool1
        assertEq(staking.getDelegator(poolId1, delegator1).stake, MIN_DELEGATOR_STAKE, "Stake in pool1 should match");

        // Check stake was recorded in pool2
        assertEq(staking.getDelegator(poolId2, delegator1).stake, MIN_DELEGATOR_STAKE, "Stake in pool2 should match");

        // Check both stakes are recorded
        (uint256 totalStake2,,) = staking.getUserTotalInfo(delegator1);
        assertEq(totalStake2, MIN_DELEGATOR_STAKE * 2, "Should have stake in both validators");

        (bytes32[] memory poolIds, uint256[] memory stakes, uint256[] memory rewards) =
            staking.getUserValidators(delegator1);

        assertEq(poolIds.length, 2, "Should have 2 validators");
        assertEq(stakes[0] + stakes[1], MIN_DELEGATOR_STAKE * 2, "Total stakes should match");
        assertEq(rewards[0] + rewards[1], 0, "Total rewards should be 0 initially");
    }

    function test_GetUserValidators_NoStakes() public view {
        (bytes32[] memory poolIds, uint256[] memory stakes, uint256[] memory rewards) =
            staking.getUserValidators(delegator1);

        assertEq(poolIds.length, 0, "Should have 0 validators");
        assertEq(stakes.length, 0, "Should have 0 stakes");
        assertEq(rewards.length, 0, "Should have 0 rewards");
    }

    // ==================== Test getUserPendingUndelegations ====================

    function test_GetUserPendingUndelegations_SingleUndelegation() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Advance epoch to activate the pending stake
        advanceEpoch();

        // Trigger lazy activation by calling settleReward
        vm.prank(delegator1);
        staking.settleReward(poolId);

        // Now undelegate the active stake
        vm.prank(delegator1);
        (uint256 amount, uint256 unlockEpoch) = staking.undelegate(poolId);

        (IStaking.PendingUndelegation[] memory undelegations) = staking.getUserPendingUndelegations(delegator1);

        assertEq(undelegations.length, 1, "Should have 1 pending undelegation");
        assertEq(undelegations[0].poolId, poolId, "Pool ID should match");
        assertEq(undelegations[0].amount, amount, "Amount should match");
        assertEq(undelegations[0].unlockEpoch, unlockEpoch, "Unlock epoch should match");
        assertFalse(undelegations[0].processed, "Should not be processed yet");
    }

    function test_GetUserPendingUndelegations_MultipleUndelegations() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        vm.prank(validator2);
        vm.deal(validator2, MIN_VALIDATOR_STAKE);
        bytes32 poolId2 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION2, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        advanceEpoch();

        vm.startPrank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE * 2);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId2);
        vm.stopPrank();

        // Advance epoch to activate pending stakes
        advanceEpoch();

        // Trigger lazy activation and undelegate
        vm.startPrank(delegator1);
        staking.settleReward(poolId1);
        staking.settleReward(poolId2);
        staking.undelegate(poolId1);
        staking.undelegate(poolId2);
        vm.stopPrank();

        (IStaking.PendingUndelegation[] memory undelegations) = staking.getUserPendingUndelegations(delegator1);

        assertEq(undelegations.length, 2, "Should have 2 pending undelegations");
    }

    function test_GetUserPendingUndelegations_NoUndelegations() public view {
        (IStaking.PendingUndelegation[] memory undelegations) = staking.getUserPendingUndelegations(delegator1);

        assertEq(undelegations.length, 0, "Should have 0 pending undelegations");
    }

    // ==================== Test getValidatorAPR ====================

    function test_GetValidatorAPR_NonExistentValidator() public {
        bytes32 fakePoolId = bytes32(uint256(1));

        vm.expectRevert("Validator does not exist");
        staking.getValidatorApr(fakePoolId);
    }

    function test_GetValidatorAPR_ActiveValidator() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        uint256 apr = staking.getValidatorApr(poolId);

        assertTrue(apr > 0, "APR should be greater than 0 for active validator");
    }

    function test_GetValidatorAPR_EqualStakeValidators() public {
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        vm.prank(validator2);
        vm.deal(validator2, MIN_VALIDATOR_STAKE);
        bytes32 poolId2 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION2, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        advanceEpoch();

        uint256 apr1 = staking.getValidatorApr(poolId1);
        uint256 apr2 = staking.getValidatorApr(poolId2);

        assertEq(apr1, apr2, "APR should be equal for validators with equal stake");
    }
}
