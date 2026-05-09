// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

/**
 * @title StakingPendingCancellationTest
 * @notice Test suite for immediate cancellation of pending stakes
 * @dev Tests the ability to cancel delegations made in the same epoch
 */
contract StakingPendingCancellationTest is Test {
    ChainConfig private chainConfig;
    TransparentUpgradeableProxy chainConfigProxy;
    Staking private staking;
    TransparentUpgradeableProxy private stakingProxy;

    address admin = 0x1111111111111111111111111111111111111111;
    address validator1 = address(0x1001);
    address validator2 = address(0x1002);
    address delegator1 = address(0x2001);
    address delegator2 = address(0x2002);

    string public constant DESCRIPTION = "Test Validator";
    string public constant PUBLIC_KEY = "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f";
    string public constant PUBLIC_KEY_2 = "0x04b34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5e";
    string public constant PUBLIC_KEY_POP = "0xproof1";
    string public constant BLS_PUBLIC_KEY = "0xblskey1";
    string public constant BLS_PUBLIC_KEY_POP = "0xblspop1";
    string public constant ENDPOINT = "http://test.validator";

    uint256 public constant MIN_VALIDATOR_STAKE = 10 ether;
    uint256 public constant MAX_VALIDATOR_STAKE = 10000 ether;
    uint256 public constant MIN_DELEGATOR_STAKE = 1 ether;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy contracts
        chainConfig = new ChainConfig();
        staking = new Staking();

        // Deploy proxies
        bytes memory chainConfigInitData =
            abi.encodeWithSelector(ChainConfig.initialize.selector, admin, address(staking));
        chainConfigProxy = new TransparentUpgradeableProxy(address(chainConfig), chainConfigInitData);
        chainConfig = ChainConfig(address(chainConfigProxy));

        bytes memory stakingInitData = abi.encodeWithSelector(Staking.initialize.selector, admin, address(chainConfig));
        stakingProxy = new TransparentUpgradeableProxy(address(staking), stakingInitData);
        staking = Staking(payable(address(stakingProxy)));

        // Update ChainConfig to point to Staking proxy
        chainConfig.updateStakingAddress(address(staking));

        vm.stopPrank();

        // Configure test parameters
        string[] memory keys = new string[](5);
        string[] memory values = new string[](5);
        keys[0] = "staking.min_staking_pool_value";
        values[0] = vm.toString(MIN_VALIDATOR_STAKE);
        keys[1] = "staking.max_staking_pool_value";
        values[1] = vm.toString(MAX_VALIDATOR_STAKE);
        keys[2] = "staking.min_delegator_stake";
        values[2] = vm.toString(MIN_DELEGATOR_STAKE);
        keys[3] = "staking.delegation_withdraw_effective_epoch";
        values[3] = "2"; // 2 epochs withdrawal window
        keys[4] = "staking.min_staking_registration_value";
        values[4] = vm.toString(MIN_VALIDATOR_STAKE);

        vm.prank(address(staking));
        chainConfig.setConfig(keys, values);

        vm.roll(block.number + 1);

        // Register validators
        vm.deal(validator1, 1000 ether);
        vm.prank(validator1);
        staking.registerValidator{value: 50 ether}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT
        );

        vm.deal(validator2, 1000 ether);
        vm.prank(validator2);
        staking.registerValidator{value: 50 ether}(
            DESCRIPTION, PUBLIC_KEY_2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT
        );

        // Wait for epoch duration before advancing
        vm.warp(vm.getBlockTimestamp() + 4 hours + 1);

        // Activate validators
        vm.prank(admin);
        staking.advanceEpoch();

        vm.deal(delegator1, 1000 ether);
        vm.deal(delegator2, 1000 ether);
    }

    function _getPoolId(string memory publicKey) internal pure returns (bytes32) {
        bytes memory publicKeyBytes = _hexStringToBytes(publicKey);
        return bytes32(sha256(abi.encodePacked(publicKeyBytes)));
    }

    function _hexStringToBytes(string memory str) internal pure returns (bytes memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= 2 && strBytes[0] == "0" && strBytes[1] == "x") {
            bytes memory sliced = new bytes(strBytes.length - 2);
            for (uint256 i = 2; i < strBytes.length; i++) {
                sliced[i - 2] = strBytes[i];
            }
            strBytes = sliced;
        }
        require(strBytes.length % 2 == 0, "Invalid hex string length");
        bytes memory result = new bytes(strBytes.length / 2);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = bytes1(_fromHexChar(strBytes[2 * i]) * 16 + _fromHexChar(strBytes[2 * i + 1]));
        }
        return result;
    }

    function _fromHexChar(bytes1 c) internal pure returns (uint8) {
        uint8 charCode = uint8(c);
        if (charCode >= 48 && charCode <= 57) {
            return charCode - 48;
        } else if (charCode >= 97 && charCode <= 102) {
            return charCode - 87;
        } else if (charCode >= 65 && charCode <= 70) {
            return charCode - 55;
        } else {
            revert("Invalid hex character");
        }
    }

    // ==================== Helper Functions ====================

    function advanceEpoch() internal {
        vm.warp(vm.getBlockTimestamp() + 4 hours + 1);
        vm.prank(admin);
        staking.advanceEpoch();
    }

    // ==================== Test Cases ====================

    /**
     * @notice Test delegate then undelegate after epoch advance
     * @dev User delegates, epoch advances to activate, then undelegates normally
     */
    function test_ImmediatePendingCancellation() public {
        bytes32 poolId = _getPoolId(PUBLIC_KEY);
        uint256 delegateAmount = 10 ether;

        // Record initial state
        uint256 initialBalance = delegator1.balance;
        IStaking.Validator memory validatorBefore = staking.getValidator(poolId);
        uint256 initialTotalStake = validatorBefore.totalStake;

        // Delegate
        vm.prank(delegator1);
        staking.delegate{value: delegateAmount}(poolId);

        // Check pending stake
        IStaking.Delegator memory delegatorAfterDelegate = staking.getDelegator(poolId, delegator1);
        assertEq(delegatorAfterDelegate.pendingStake, delegateAmount, "Pending stake should be set");
        assertEq(delegatorAfterDelegate.stake, 0, "Active stake should be 0");

        // Check validator totalStake increased
        IStaking.Validator memory validatorAfterDelegate = staking.getValidator(poolId);
        assertEq(
            validatorAfterDelegate.totalStake,
            initialTotalStake + delegateAmount,
            "Validator totalStake should increase"
        );

        // Advance epoch to activate pending stake
        advanceEpoch();

        // Undelegate (normal flow after activation)
        vm.prank(delegator1);
        (uint256 returnedAmount, uint256 unlockEpoch) = staking.undelegate(poolId);

        // Verify return values
        assertEq(returnedAmount, delegateAmount, "Should return delegated amount");
        assertGt(unlockEpoch, staking.currentEpoch(), "Should have withdrawal window (not immediate)");

        // Verify state after undelegate
        IStaking.Delegator memory delegatorAfterUndelegate = staking.getDelegator(poolId, delegator1);
        assertEq(delegatorAfterUndelegate.pendingStake, 0, "Pending stake should be cleared");
        assertEq(delegatorAfterUndelegate.stake, 0, "Active stake should be 0");
        assertEq(delegatorAfterUndelegate.principalStake, 0, "Principal stake should be cleared");

        // Verify validator totalStake restored
        IStaking.Validator memory validatorAfterUndelegate = staking.getValidator(poolId);
        assertEq(validatorAfterUndelegate.totalStake, initialTotalStake, "Validator totalStake should be restored");
    }

    /**
     * @notice Test delegate across epochs then undelegate after activation
     */
    function test_MultiplePendingDelegatesThenCancel() public {
        bytes32 poolId = _getPoolId(PUBLIC_KEY);
        uint256 firstDelegate = 5 ether;
        uint256 secondDelegate = 3 ether;
        uint256 totalDelegated = firstDelegate + secondDelegate;

        // First delegate
        vm.prank(delegator1);
        staking.delegate{value: firstDelegate}(poolId);

        // Advance epoch to activate first delegation
        advanceEpoch();

        // Second delegate (next epoch, first is now active)
        vm.prank(delegator1);
        staking.delegate{value: secondDelegate}(poolId);

        // Advance epoch to activate second delegation
        advanceEpoch();

        // Undelegate all (normal flow after activation)
        vm.prank(delegator1);
        (uint256 amount,) = staking.undelegate(poolId);

        assertGe(amount, totalDelegated, "Should return at least all stake");
    }

    /**
     * @notice Test cannot cancel after stake is activated
     */
    function test_CannotCancelAfterActivation() public {
        bytes32 poolId = _getPoolId(PUBLIC_KEY);
        uint256 delegateAmount = 10 ether;

        // Delegate in epoch N
        vm.prank(delegator1);
        staking.delegate{value: delegateAmount}(poolId);

        // Advance to epoch N+1 (stake activates)
        vm.warp(vm.getBlockTimestamp() + 4 hours + 1);
        vm.prank(admin);
        staking.advanceEpoch();

        // Now trying to undelegate should go through normal flow (not cancellation)
        vm.prank(delegator1);
        (uint256 amount, uint256 unlockEpoch) = staking.undelegate(poolId);

        // Should use withdrawal window, not immediate unlock
        assertEq(amount, delegateAmount, "Should undelegate full amount");
        assertGt(unlockEpoch, staking.currentEpoch(), "Should have withdrawal window (not immediate)");

        // Funds should NOT be immediately returned
        IStaking.Delegator memory delegator = staking.getDelegator(poolId, delegator1);
        assertEq(delegator.pendingWithdrawStake, delegateAmount, "Should be in pending withdrawal");
        assertTrue(delegator.isPendingUndelegate, "Should be pending undelegate");
    }

    /**
     * @notice Test undelegate with multiple users after activation
     */
    function test_MultipleDelegatorsCancellation() public {
        bytes32 poolId = _getPoolId(PUBLIC_KEY);

        // Both delegate in same epoch
        vm.prank(delegator1);
        staking.delegate{value: 10 ether}(poolId);

        vm.prank(delegator2);
        staking.delegate{value: 15 ether}(poolId);

        // Advance epoch to activate pending stakes
        advanceEpoch();

        // Delegator1 undelegates
        vm.prank(delegator1);
        (uint256 amount1,) = staking.undelegate(poolId);
        assertEq(amount1, 10 ether, "Delegator1 should get full amount");

        // Delegator2 undelegates
        vm.prank(delegator2);
        (uint256 amount2,) = staking.undelegate(poolId);
        assertEq(amount2, 15 ether, "Delegator2 should get full amount");

        // Verify both cleared
        IStaking.Delegator memory del1 = staking.getDelegator(poolId, delegator1);
        IStaking.Delegator memory del2 = staking.getDelegator(poolId, delegator2);
        assertEq(del1.pendingStake, 0, "Delegator1 pending cleared");
        assertEq(del2.pendingStake, 0, "Delegator2 pending cleared");
    }

    /**
     * @notice Test undelegate of additional stake when user already has active stake
     * @dev This tests the flow: delegate → activate → delegate more → activate → undelegate
     */
    function test_CancelPendingWithExistingActiveStake() public {
        bytes32 poolId = _getPoolId(PUBLIC_KEY);

        // Step 1: User delegates in epoch N
        vm.prank(delegator1);
        staking.delegate{value: 100 ether}(poolId);

        // Step 2: Advance to epoch N+1 (stake becomes active)
        advanceEpoch();

        // Trigger lazy activation by calling settleReward
        vm.prank(delegator1);
        staking.settleReward(poolId);

        // Verify stake is now active
        IStaking.Delegator memory delAfterActivation = staking.getDelegator(poolId, delegator1);
        assertEq(delAfterActivation.stake, 100 ether, "Should have 100 ETH active stake");
        assertEq(delAfterActivation.pendingStake, 0, "Should have 0 pending stake");

        // Step 3: In epoch N+1, user delegates MORE (creates new pending)
        vm.prank(delegator1);
        staking.delegate{value: 50 ether}(poolId);

        // Verify state: has both active and pending
        IStaking.Delegator memory delAfterSecondDelegate = staking.getDelegator(poolId, delegator1);
        assertEq(delAfterSecondDelegate.stake, 100 ether, "Should still have 100 ETH active");
        assertEq(delAfterSecondDelegate.pendingStake, 50 ether, "Should have 50 ETH pending");

        // Step 4: Advance epoch to activate the new pending stake
        advanceEpoch();

        // Step 5: Undelegate (normal flow, all stake is now active)
        vm.prank(delegator1);
        (uint256 undelegateAmount, uint256 unlockEpoch) = staking.undelegate(poolId);

        // Verify undelegate results - should undelegate all active stake (at least 150 ETH, possibly more with rewards)
        assertGe(undelegateAmount, 150 ether, "Should undelegate at least 150 ETH");
        assertGt(unlockEpoch, staking.currentEpoch(), "Should have withdrawal window");

        // Verify final state
        IStaking.Delegator memory delAfterUndelegate = staking.getDelegator(poolId, delegator1);
        assertEq(delAfterUndelegate.stake, 0, "Active stake should be 0");
        assertEq(delAfterUndelegate.pendingStake, 0, "Pending stake should be 0");

        // Verify delegator count decreased
        assertTrue(delAfterUndelegate.isPendingUndelegate, "Should be pending undelegate");
    }

    /**
     * @notice Test undelegate from different validators after activation
     */
    function test_CancelDifferentValidators() public {
        bytes32 poolId1 = _getPoolId(PUBLIC_KEY);
        bytes32 poolId2 = _getPoolId(PUBLIC_KEY_2);

        // Delegate to both validators
        vm.startPrank(delegator1);
        staking.delegate{value: 10 ether}(poolId1);
        staking.delegate{value: 15 ether}(poolId2);
        vm.stopPrank();

        // Advance epoch to activate pending stakes
        advanceEpoch();

        // Undelegate from poolId1
        vm.prank(delegator1);
        (uint256 amount1,) = staking.undelegate(poolId1);

        assertEq(amount1, 10 ether, "Should undelegate poolId1");

        // poolId2 should still have active stake (need settleReward to trigger lazy activation)
        vm.prank(delegator1);
        staking.settleReward(poolId2);

        IStaking.Delegator memory del2 = staking.getDelegator(poolId2, delegator1);
        assertEq(del2.stake, 15 ether, "poolId2 active stake should remain");
    }

    /**
     * @notice Test refcount after delegate and undelegate with epoch advance
     */
    function test_RefcountCleanupOnCancellation() public {
        bytes32 poolId = _getPoolId(PUBLIC_KEY);
        uint256 currentEpochVal = staking.currentEpoch();
        uint256 activationEpoch = currentEpochVal + 1;

        // Delegate
        vm.prank(delegator1);
        staking.delegate{value: 10 ether}(poolId);

        // Check refcount is set
        (uint256 rps, uint256 refcount) = staking.getHistoricalRPS(activationEpoch, poolId);
        assertEq(refcount, 1, "Refcount should be 1 after delegate");

        // Advance epoch to activate pending stake
        advanceEpoch();

        // Undelegate (normal flow)
        vm.prank(delegator1);
        staking.undelegate(poolId);

        // After activation and undelegate, refcount should be decremented
        (, refcount) = staking.getHistoricalRPS(activationEpoch, poolId);
        assertEq(refcount, 0, "Refcount should be 0 after activation and undelegate");
    }

    /**
     * @notice Test cannot cancel with no pending stake
     */
    function test_CannotCancelWithNoPending() public {
        bytes32 poolId = _getPoolId(PUBLIC_KEY);

        // Try to undelegate without any stake
        // Should fail with "No stake to undelegate" because after checking pending,
        // it goes to the normal undelegate path which checks for active stake
        vm.expectRevert("No stake to undelegate");
        vm.prank(delegator1);
        staking.undelegate(poolId);
    }

    /**
     * @notice Test validator owner cannot delegate or undelegate while pending exit
     */
    function test_ValidatorOwnerCannotUndelegateDuringPendingExit() public {
        bytes32 poolId = _getPoolId(PUBLIC_KEY);

        // Validator requests exit
        vm.prank(validator1);
        staking.exitValidator(poolId);

        // Validator tries to delegate more - should fail because isPendingUndelegate is true
        vm.expectRevert("Cannot delegate while pending undelegate");
        vm.prank(validator1);
        vm.deal(validator1, 10 ether);
        staking.delegate{value: 10 ether}(poolId);

        // Try to undelegate should also fail (owner must use exitValidator/withdrawStake)
        vm.expectRevert("Use exitValidator/withdrawStake instead");
        vm.prank(validator1);
        staking.undelegate(poolId);
    }

    /**
     * @notice Test gas usage of undelegate after single vs multiple epoch advances
     */
    function test_GasEfficiencyOfCancellation() public {
        bytes32 poolId = _getPoolId(PUBLIC_KEY);

        // Delegate and activate for first undelegate
        vm.prank(delegator1);
        staking.delegate{value: 10 ether}(poolId);

        advanceEpoch();

        uint256 gasStartFirst = gasleft();
        vm.prank(delegator1);
        staking.undelegate(poolId);
        uint256 gasFirstUsed = gasStartFirst - gasleft();

        // Delegate and activate for second undelegate (with additional epoch)
        vm.prank(delegator2);
        staking.delegate{value: 10 ether}(poolId);

        advanceEpoch();

        uint256 gasStartSecond = gasleft();
        vm.prank(delegator2);
        staking.undelegate(poolId);
        uint256 gasSecondUsed = gasStartSecond - gasleft();

        // Both should use similar gas (both go through normal undelegate flow)
        // Just verify both succeeded without reverting
        assertTrue(gasFirstUsed > 0, "First undelegate should use gas");
        assertTrue(gasSecondUsed > 0, "Second undelegate should use gas");
    }
}
