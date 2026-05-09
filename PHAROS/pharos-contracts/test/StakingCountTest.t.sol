// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {Staking} from "../src/staking/Staking.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

/**
 * @title StakingCountTest
 * @notice Unit tests for getActiveValidatorCount and getTotalDelegatorCount functions
 */
contract StakingCountTest is Test {
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

    // ==================== Test getActiveValidatorCount ====================

    function test_GetActiveValidatorCount_SingleValidator() public {
        // Register a validator
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        // Before epoch advance, count should be 0 (validator is pending)
        uint256 countBefore = staking.getActiveValidatorCount();
        assertEq(countBefore, 0, "Active validator count should be 0 before epoch advance");

        // Advance epoch to activate validator
        advanceEpoch();

        // After epoch advance, count should be 1
        uint256 countAfter = staking.getActiveValidatorCount();
        assertEq(countAfter, 1, "Active validator count should be 1 after epoch advance");
    }

    function test_GetActiveValidatorCount_MultipleValidators() public {
        // Register three validators
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        vm.prank(validator2);
        vm.deal(validator2, MIN_VALIDATOR_STAKE);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        vm.prank(validator3);
        vm.deal(validator3, MIN_VALIDATOR_STAKE);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY3, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT3
        );

        // Advance epoch to activate all validators
        advanceEpoch();

        // Count should be 3
        uint256 count = staking.getActiveValidatorCount();
        assertEq(count, 3, "Active validator count should be 3");
    }

    function test_GetActiveValidatorCount_AfterValidatorExit() public {
        // Register two validators
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        vm.prank(validator2);
        vm.deal(validator2, MIN_VALIDATOR_STAKE);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        advanceEpoch();

        // Count should be 2
        assertEq(staking.getActiveValidatorCount(), 2, "Active validator count should be 2");

        // Exit first validator - pool remains active until all stake is withdrawn
        vm.prank(validator1);
        staking.exitValidator(poolId1);

        // Count should still be 2 (pool stays active until all delegators withdraw)
        assertEq(staking.getActiveValidatorCount(), 2, "Active validator count should still be 2 after exit");

        // Advance epoch to process exit (owner stake already zeroed, so pool removed)
        advanceEpoch();

        // Count should now be 1 (validator removed after epoch advance)
        assertEq(staking.getActiveValidatorCount(), 1, "Active validator count should be 1 after epoch advance");
    }

    function test_GetTotalDelegatorCount_ValidatorOwnerOnly() public {
        // Register a validator (validator owner becomes a delegator)
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        // Before epoch advance, count should be 0 (validator is pending)
        uint256 countBefore = staking.getTotalDelegatorCount();
        assertEq(countBefore, 0, "Delegator count should be 0 before epoch advance");

        // Advance epoch to activate validator
        advanceEpoch();

        // After epoch advance, count should be 1 (validator owner is counted as delegator)
        uint256 countAfter = staking.getTotalDelegatorCount();
        assertEq(countAfter, 1, "Delegator count should be 1 (validator owner)");
    }

    function test_GetTotalDelegatorCount_WithExternalDelegators() public {
        // Register a validator
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        // Initial count: 1 (validator owner)
        assertEq(staking.getTotalDelegatorCount(), 1, "Delegator count should be 1 initially");

        // Add first external delegator
        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Count should be 2
        assertEq(staking.getTotalDelegatorCount(), 2, "Delegator count should be 2");

        // Add second external delegator
        vm.prank(delegator2);
        vm.deal(delegator2, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Count should be 3
        assertEq(staking.getTotalDelegatorCount(), 3, "Delegator count should be 3");
    }

    function test_GetTotalDelegatorCount_MultipleValidators() public {
        // Register two validators
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        vm.prank(validator2);
        vm.deal(validator2, MIN_VALIDATOR_STAKE);
        bytes32 poolId2 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        advanceEpoch();

        // Initial count: 2 (both validator owners)
        assertEq(staking.getTotalDelegatorCount(), 2, "Delegator count should be 2");

        // Add delegators to first pool
        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId1);

        vm.prank(delegator2);
        vm.deal(delegator2, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId1);

        // Count should be 4
        assertEq(staking.getTotalDelegatorCount(), 4, "Delegator count should be 4");

        // Add delegator to second pool
        vm.prank(delegator3);
        vm.deal(delegator3, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId2);

        // Count should be 5
        assertEq(staking.getTotalDelegatorCount(), 5, "Delegator count should be 5");
    }

    function test_GetTotalDelegatorCount_AfterUndelegate() public {
        // Register a validator
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        // Add two external delegators
        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        vm.prank(delegator2);
        vm.deal(delegator2, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Advance epoch to activate pending stakes
        advanceEpoch();

        // Count should be 3 (validator owner + 2 delegators)
        assertEq(staking.getTotalDelegatorCount(), 3, "Delegator count should be 3");

        // First delegator undelegates
        vm.prank(delegator1);
        staking.undelegate(poolId);

        // Count should be 2
        assertEq(staking.getTotalDelegatorCount(), 2, "Delegator count should be 2 after undelegate");

        // Second delegator undelegates
        vm.prank(delegator2);
        staking.undelegate(poolId);

        // Count should be 1 (only validator owner remains)
        assertEq(staking.getTotalDelegatorCount(), 1, "Delegator count should be 1");
    }

    function test_GetTotalDelegatorCount_AfterValidatorExit() public {
        // Register a validator
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        // Add an external delegator
        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Count should be 2 (validator owner + 1 delegator)
        assertEq(staking.getTotalDelegatorCount(), 2, "Delegator count should be 2");

        // Validator exits - owner's stake is withdrawn, but pool stays active
        vm.prank(validator1);
        staking.exitValidator(poolId);

        // Count should be 1 (only external delegator remains, owner's stake withdrawn)
        assertEq(staking.getTotalDelegatorCount(), 1, "Delegator count should be 1 after validator exit");

        // Advance epoch to process exit (pool removed as owner's stake is zero)
        advanceEpoch();

        // Count should be 0 (pool no longer active)
        assertEq(staking.getTotalDelegatorCount(), 0, "Delegator count should be 0 after epoch advance");
    }

    function test_GetTotalDelegatorCount_ReDelegate() public {
        // Register a validator
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        // Initial count: 1 (validator owner)
        assertEq(staking.getTotalDelegatorCount(), 1, "Delegator count should be 1 initially");

        // Add a delegator
        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Count should be 2
        assertEq(staking.getTotalDelegatorCount(), 2, "Delegator count should be 2");

        // Advance epoch to activate first delegation before delegating again
        advanceEpoch();

        // Same delegator delegates again (adds more stake)
        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Count should still be 2 (no new delegator)
        assertEq(staking.getTotalDelegatorCount(), 2, "Delegator count should still be 2");
    }

    function test_GetTotalDelegatorCount_OnlyActiveValidators() public {
        // Register first validator
        vm.prank(validator1);
        vm.deal(validator1, MIN_VALIDATOR_STAKE);
        bytes32 poolId1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        // Advance epoch to activate first validator
        advanceEpoch();

        // Count should be 1 (only validator1 is active)
        assertEq(staking.getActiveValidatorCount(), 1, "Active validator count should be 1");
        assertEq(staking.getTotalDelegatorCount(), 1, "Delegator count should be 1");

        // Register second validator
        vm.prank(validator2);
        vm.deal(validator2, MIN_VALIDATOR_STAKE);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        // Second validator is pending, count should still be 1
        assertEq(staking.getActiveValidatorCount(), 1, "Active validator count should still be 1");
        assertEq(staking.getTotalDelegatorCount(), 1, "Delegator count should still be 1");

        // Advance epoch again to activate second validator
        advanceEpoch();

        // Count should be 2 (both validators are active)
        assertEq(staking.getActiveValidatorCount(), 2, "Active validator count should be 2");
        assertEq(staking.getTotalDelegatorCount(), 2, "Delegator count should be 2");

        // Add delegator to first pool
        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId1);

        // Count should be 3
        assertEq(staking.getTotalDelegatorCount(), 3, "Delegator count should be 3");
    }

    // ==================== Tests for withdrawStake vulnerability fix ====================

    function test_WithdrawStake_SequentialWithdrawalsAfterClaim() public {
        // Verifies that a validator can make multiple partial withdrawals by claiming
        // between each withdrawal. Partial withdrawals that keep totalStake >= min do NOT
        // add to pendingExitPoolIds — DoS protection is enforced via isPendingUndelegate.

        // Register a validator with larger stake
        vm.prank(validator1);
        vm.deal(validator1, 5 ether);
        bytes32 poolId = staking.registerValidator{value: 5 ether}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        // Get pending exit validators count before withdraw
        bytes32[] memory pendingBefore = staking.getPendingExitValidators();
        uint256 pendingCountBefore = pendingBefore.length;

        // First partial withdraw (5→4 ether, stays above min=1 ether)
        vm.prank(validator1);
        staking.withdrawStake(poolId, 1 ether);

        // Above-min partial withdrawal: pendingExit NOT set, isPendingUndelegate=true
        bytes32[] memory pendingAfterFirst = staking.getPendingExitValidators();
        assertEq(
            pendingAfterFirst.length,
            pendingCountBefore,
            "pendingExitPoolIds should NOT increase for above-min partial withdrawal"
        );
        assertFalse(staking.isValidatorPendingExit(poolId), "poolId should NOT be in pendingExitPoolIds");

        // Second partial withdraw should fail because isPendingUndelegate=true (DoS protection)
        vm.prank(validator1);
        vm.expectRevert("Already pending undelegate");
        staking.withdrawStake(poolId, 1 ether);

        // pendingExitPoolIds count unchanged after failed attempt
        bytes32[] memory pendingAfterFailed = staking.getPendingExitValidators();
        assertEq(
            pendingAfterFailed.length,
            pendingAfterFirst.length,
            "pendingExitPoolIds should not increase on failed withdraw"
        );

        // Advance epoch to make withdrawal claimable
        advanceEpoch();

        // Claim the first withdrawal
        vm.prank(validator1);
        staking.claimStake(poolId);

        // Advance epoch again
        advanceEpoch();

        // poolId was never in pendingExitPoolIds, remains absent
        bytes32[] memory pendingAfterClaim = staking.getPendingExitValidators();
        bool poolIdStillPending = false;
        for (uint256 i = 0; i < pendingAfterClaim.length; i++) {
            if (pendingAfterClaim[i] == poolId) {
                poolIdStillPending = true;
                break;
            }
        }
        assertFalse(poolIdStillPending, "poolId should not be in pendingExitPoolIds (was never added)");

        // Now second withdrawal should succeed (isPendingUndelegate is false after claim)
        vm.prank(validator1);
        staking.withdrawStake(poolId, 1 ether);

        // Still above min (3 ether > 1 ether): pendingExit still NOT set
        bytes32[] memory pendingAfterSecond = staking.getPendingExitValidators();
        assertEq(
            pendingAfterSecond.length,
            pendingCountBefore,
            "pendingExitPoolIds should still not increase for above-min partial withdrawal"
        );
        assertFalse(staking.isValidatorPendingExit(poolId), "poolId should still NOT be in pendingExitPoolIds");
    }

    function test_WithdrawStake_CannotExhaustPendingExitPoolIds() public {
        // Verifies that a malicious validator cannot exhaust the pendingExitPoolIds array.
        // With partial withdrawals above min, only isPendingUndelegate blocks subsequent
        // attempts — pendingExitPoolIds itself is never modified.

        // Register a validator with large stake
        vm.prank(validator1);
        vm.deal(validator1, 1000 ether);
        bytes32 poolId = staking.registerValidator{value: 1000 ether}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        // Get initial pending exit count
        bytes32[] memory pendingBefore = staking.getPendingExitValidators();
        uint256 initialPendingCount = pendingBefore.length;

        // First withdraw should succeed
        vm.prank(validator1);
        staking.withdrawStake(poolId, 1 wei);

        // Subsequent withdrawals should fail because isPendingUndelegate=true
        uint256 numAttempts = 100;
        for (uint256 i = 0; i < numAttempts; i++) {
            vm.prank(validator1);
            vm.expectRevert("Already pending undelegate");
            staking.withdrawStake(poolId, 1 wei);
        }

        // pendingExitPoolIds did NOT increase at all (above-min partial withdrawal)
        bytes32[] memory pendingAfter = staking.getPendingExitValidators();
        assertEq(
            pendingAfter.length,
            initialPendingCount,
            "pendingExitPoolIds should only increase by 1 despite many withdraw attempts"
        );
    }

    function test_WithdrawStake_PendingExitPoolIdsCleanupAfterClaim() public {
        // Verifies that pendingExitPoolIds is cleaned up in advanceEpoch after a full exit.
        // A full withdrawal (ownerStake → 0) triggers pendingExit; after advanceEpoch
        // the validator is deactivated and removed from pendingExitPoolIds.
        vm.prank(validator1);
        vm.deal(validator1, 5 ether);
        bytes32 poolId = staking.registerValidator{value: 5 ether}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        advanceEpoch();

        // Full withdrawal: ownerStake → 0 → triggers pendingExit
        vm.prank(validator1);
        staking.withdrawStake(poolId, 5 ether);

        // Verify poolId is in pendingExitPoolIds
        assertTrue(
            staking.isValidatorPendingExit(poolId), "poolId should be in pendingExitPoolIds after full withdrawal"
        );

        // Advance epoch — _processPendingExits deactivates the validator and removes from pendingExit
        advanceEpoch();

        // The poolId should be removed from pendingExitPoolIds after cleanup
        bytes32[] memory pendingAfterAdvance = staking.getPendingExitValidators();
        bool poolIdStillInPending = false;
        for (uint256 i = 0; i < pendingAfterAdvance.length; i++) {
            if (pendingAfterAdvance[i] == poolId) {
                poolIdStillInPending = true;
                break;
            }
        }

        assertFalse(poolIdStillInPending, "poolId should be removed from pendingExitPoolIds after cleanup");
    }

    function test_WithdrawStake_MultipleValidatorsCannotBlockEachOther() public {
        // Verifies that multiple validators can all withdraw independently without blocking
        // each other. Partial withdrawals above min do NOT add to pendingExitPoolIds;
        // DoS protection is per-validator via isPendingUndelegate.

        // Register three validators
        vm.prank(validator1);
        vm.deal(validator1, 5 ether);
        bytes32 poolId1 = staking.registerValidator{value: 5 ether}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        vm.prank(validator2);
        vm.deal(validator2, 5 ether);
        bytes32 poolId2 = staking.registerValidator{value: 5 ether}(
            DESCRIPTION, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        vm.prank(validator3);
        vm.deal(validator3, 5 ether);
        bytes32 poolId3 = staking.registerValidator{value: 5 ether}(
            DESCRIPTION, PUBLIC_KEY3, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT3
        );

        advanceEpoch();

        // Get initial pending exit count
        bytes32[] memory pendingBefore = staking.getPendingExitValidators();
        uint256 initialPendingCount = pendingBefore.length;

        // All three validators perform partial withdraws (5→4 ether each, stays above min=1 ether)
        vm.prank(validator1);
        staking.withdrawStake(poolId1, 1 ether);

        vm.prank(validator2);
        staking.withdrawStake(poolId2, 1 ether);

        vm.prank(validator3);
        staking.withdrawStake(poolId3, 1 ether);

        bytes32[] memory pendingAfter = staking.getPendingExitValidators();

        // Above-min partial withdrawals: none of the three should be in pendingExitPoolIds
        uint256 unexpectedCount = 0;
        for (uint256 i = 0; i < pendingAfter.length; i++) {
            if (pendingAfter[i] == poolId1 || pendingAfter[i] == poolId2 || pendingAfter[i] == poolId3) {
                unexpectedCount++;
            }
        }

        assertEq(unexpectedCount, 0, "No pendingExit for above-min partial withdrawals");
        assertEq(pendingAfter.length, initialPendingCount, "pendingExitPoolIds should not increase");

        // Each validator's second withdrawal is blocked by their own isPendingUndelegate (not by others)
        vm.prank(validator1);
        vm.expectRevert("Already pending undelegate");
        staking.withdrawStake(poolId1, 1 ether);

        vm.prank(validator2);
        vm.expectRevert("Already pending undelegate");
        staking.withdrawStake(poolId2, 1 ether);

        vm.prank(validator3);
        vm.expectRevert("Already pending undelegate");
        staking.withdrawStake(poolId3, 1 ether);

        // pendingExitPoolIds still unchanged after failed attempts
        bytes32[] memory pendingAfterFailed = staking.getPendingExitValidators();
        assertEq(
            pendingAfterFailed.length,
            pendingAfter.length,
            "pendingExitPoolIds should not increase after failed withdraw attempts"
        );
    }
}
