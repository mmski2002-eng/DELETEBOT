// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

/**
 * @title StakingDivisionByZeroTest
 * @notice Test for division by zero vulnerability in rewardValidators function
 * @dev Tests the scenario where a non-active validator with stakeSnapshot=0
 *      receives a priority fee, causing division by zero at line 1154
 */
contract StakingDivisionByZeroTest is Test {
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

    string public constant DESCRIPTION = "Test Validator";
    string public constant PUBLIC_KEY1 = "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f";
    string public constant PUBLIC_KEY2 = "0x04b34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5a";
    string public constant PUBLIC_KEY_POP = "0xproof1";
    string public constant BLS_PUBLIC_KEY = "0xblskey1";
    string public constant BLS_PUBLIC_KEY_POP = "0xblspop1";
    string public constant ENDPOINT1 = "http://test.validator1";
    string public constant ENDPOINT2 = "http://test.validator2";

    uint256 public constant MIN_VALIDATOR_STAKE = 1 ether;
    uint256 public constant MIN_DELEGATOR_STAKE = 1 ether;

    function setUp() public {
        vm.startPrank(admin);
        chainConfig = new ChainConfig();
        ruleManager = new RuleManager();
        staking = new Staking();

        address chainConfigImplAddr = address(chainConfig);
        address ruleManagerImplAddr = address(ruleManager);
        address stakingImplAddr = address(staking);

        bytes memory chainConfigInitData =
            abi.encodeWithSelector(ChainConfig.initialize.selector, admin, address(staking));
        chainConfigProxy = new TransparentUpgradeableProxy(address(chainConfig), chainConfigInitData);
        chainConfig = ChainConfig(address(chainConfigProxy));

        bytes memory ruleManagerInitData = abi.encodeWithSelector(RuleManager.initialize.selector, admin, 1000);
        ruleManagerProxy = new TransparentUpgradeableProxy(address(ruleManager), ruleManagerInitData);
        ruleManager = RuleManager(address(ruleManagerProxy));

        bytes memory stakingInitData = abi.encodeWithSelector(Staking.initialize.selector, admin, chainConfigImplAddr);
        stakingProxy = new TransparentUpgradeableProxy(address(staking), stakingInitData);
        staking = Staking(payable(address(stakingProxy)));

        chainConfig.updateStakingAddress(address(staking));
        staking.updateChainConfigAddress(address(chainConfig));

        vm.stopPrank();

        // Configure ChainConfig with test values
        string[] memory keys = new string[](5);
        string[] memory values = new string[](5);
        keys[0] = "staking.min_staking_pool_value";
        values[0] = vm.toString(MIN_VALIDATOR_STAKE);
        keys[1] = "staking.max_staking_pool_value";
        values[1] = vm.toString(uint256(100000000 ether));
        keys[2] = "staking.min_delegator_stake";
        values[2] = vm.toString(MIN_DELEGATOR_STAKE);
        keys[3] = "staking.withdraw_effective_epoch";
        values[3] = "1";
        keys[4] = "staking.min_staking_registration_value";
        values[4] = vm.toString(MIN_VALIDATOR_STAKE);

        vm.prank(address(staking));
        chainConfig.setConfig(keys, values);

        // Advance block to make configs effective
        vm.roll(block.number + 1);
    }

    function advanceEpoch() public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch();
    }

    /**
     * @notice Test that passing a non-active validator with a priority fee does NOT revert.
     * @dev With the bootstrapping guard (isValidatorActive check), priority fees are silently
     *      ignored for non-active validators — no division by zero, no commission credited.
     */
    function testDivisionByZero_NonActiveValidatorWithPriorityFee() public {
        // Step 1: Register and activate validator1
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        // Activate validator1
        advanceEpoch();

        // Verify validator1 is active and has stakeSnapshot > 0
        IStaking.Validator memory val1 = staking.getValidator(poolId1);
        assertTrue(val1.status == 1, "Validator1 should be active");
        assertTrue(val1.stakeSnapshot > 0, "Validator1 should have stakeSnapshot > 0");

        // Step 2: Register validator2 (don't advance epoch, so it stays pending)
        vm.prank(validator2);
        vm.deal(validator2, MIN_VALIDATOR_STAKE);
        bytes32 poolId2 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        // Verify validator2 is NOT active and has stakeSnapshot = 0
        IStaking.Validator memory val2 = staking.getValidator(poolId2);
        assertTrue(val2.status == 0, "Validator2 should NOT be active");
        assertEq(val2.stakeSnapshot, 0, "Validator2 should have stakeSnapshot = 0");

        // Step 3: Advance time for epoch
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 4 hours);

        // Step 4: Call advanceEpoch with validator2's poolId and a priority fee.
        // With the isValidatorActive guard, the fee is skipped for non-active validators.
        // This should NOT revert (no division by zero).
        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = poolId2;
        uint256[] memory priorityFees = new uint256[](1);
        priorityFees[0] = 1 ether; // Non-zero priority fee

        vm.prank(admin);
        staking.advanceEpoch(poolIds, priorityFees); // Must not revert

        // Validator2 is non-active: priority fee is NOT distributed, no commission credited.
        IStaking.Delegator memory delegatorAfter = staking.getDelegator(poolId2, validator2);
        assertEq(delegatorAfter.rewards, 0, "Validator2 should receive no rewards while non-active");
    }

    /**
     * @notice Confirm that the guard prevents any fee from reaching a non-active validator.
     */
    function testFixDivisionByZero_NonActiveValidatorWithPriorityFee() public {
        // Register and activate validator1
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        // Activate validator1
        advanceEpoch();

        // Register validator2 (don't advance epoch, so it stays pending)
        vm.prank(validator2);
        vm.deal(validator2, MIN_VALIDATOR_STAKE);
        bytes32 poolId2 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        // Verify validator2 is NOT active and has stakeSnapshot = 0
        IStaking.Validator memory val2 = staking.getValidator(poolId2);
        assertTrue(val2.status == 0, "Validator2 should NOT be active");
        assertEq(val2.stakeSnapshot, 0, "Validator2 should have stakeSnapshot = 0");

        IStaking.Delegator memory delegatorBefore = staking.getDelegator(poolId2, validator2);

        // Advance time for epoch
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 4 hours);

        // Call advanceEpoch with validator2's poolId and a priority fee.
        // Should succeed (no revert) and distribute NO fee to validator2.
        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = poolId2;
        uint256[] memory priorityFees = new uint256[](1);
        priorityFees[0] = 1 ether;

        vm.prank(admin);
        staking.advanceEpoch(poolIds, priorityFees); // Should succeed after fix

        // Non-active validator receives zero commission — fee is silently dropped.
        IStaking.Delegator memory delegatorAfter = staking.getDelegator(poolId2, validator2);
        assertEq(
            delegatorAfter.rewards - delegatorBefore.rewards,
            0,
            "Validator2 should not receive commission while pending activation"
        );
    }

    /**
     * @notice Test that reward distribution works correctly for active validators
     * @dev This is a positive test to show the expected behavior
     */
    function testRewardDistribution_ActiveValidatorWithPriorityFee() public {
        // Register and activate validator1
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        // Activate validator1
        advanceEpoch();

        // Advance time for next epoch
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 4 hours);

        // Call advanceEpoch with validator1's poolId and a priority fee
        // This should work because validator1 is active and has stakeSnapshot > 0
        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = poolId1;
        uint256[] memory priorityFees = new uint256[](1);
        priorityFees[0] = 1 ether;

        vm.prank(admin);
        staking.advanceEpoch(poolIds, priorityFees); // Should succeed

        // Verify epoch advanced
        (uint256 currentEpoch, uint256 currentBlock,) = staking.getBlockchainInfo();
        assertGt(currentEpoch, 0, "Epoch should have advanced");
        assertEq(currentBlock, block.number, "Block should match");
    }

    /**
     * @notice Test that calling advanceEpoch with empty arrays works fine
     */
    function testAdvanceEpoch_EmptyArrays() public {
        // Register and activate validator1
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        // Advance time for next epoch
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 4 hours);

        // Call advanceEpoch with empty arrays
        bytes32[] memory poolIds = new bytes32[](0);
        uint256[] memory priorityFees = new uint256[](0);

        vm.prank(admin);
        staking.advanceEpoch(poolIds, priorityFees); // Should succeed
    }

    /**
     * @notice Test with both active and non-active validators receiving priority fees.
     * @dev Validator1 (active) earns rewards; Validator2 (pending) receives nothing.
     *      The call must not revert regardless of the non-active validator in the fee array.
     */
    function testDivisionByZero_MixedValidatorsWithPriorityFee() public {
        // Register and activate validator1
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        // Activate validator1
        advanceEpoch();

        // Register validator2 (don't advance epoch)
        vm.prank(validator2);
        vm.deal(validator2, MIN_VALIDATOR_STAKE);
        bytes32 poolId2 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        // Advance time for next epoch
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 4 hours);

        // Call advanceEpoch with BOTH validators, including priority fees for both.
        // validator1 should earn rewards; validator2 (non-active) should be silently skipped.
        bytes32[] memory poolIds = new bytes32[](2);
        poolIds[0] = poolId1;
        poolIds[1] = poolId2;
        uint256[] memory priorityFees = new uint256[](2);
        priorityFees[0] = 0.5 ether;
        priorityFees[1] = 0.5 ether;

        // Get reward balances before
        IStaking.Delegator memory delegator1Before = staking.getDelegator(poolId1, validator1);
        IStaking.Delegator memory delegator2Before = staking.getDelegator(poolId2, validator2);

        // After the fix, this should succeed (not revert)
        vm.prank(admin);
        staking.advanceEpoch(poolIds, priorityFees);

        // Validator1 (active) should have received rewards (inflation + priority fee)
        IStaking.Delegator memory delegator1After = staking.getDelegator(poolId1, validator1);
        IStaking.Delegator memory delegator2After = staking.getDelegator(poolId2, validator2);

        assertGt(delegator1After.rewards, delegator1Before.rewards, "Validator1 should have received rewards");

        // Validator2 (non-active) receives no priority fee commission
        assertEq(
            delegator2After.rewards,
            delegator2Before.rewards,
            "Validator2 should not receive priority fee commission while non-active"
        );
    }
}
