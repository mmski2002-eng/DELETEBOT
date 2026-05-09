// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

/**
 * @title StakingOutOfOrderTest
 * @notice Tests multi-delegator × multi-validator out-of-order undelegation and claim scenarios.
 *         Exercises the pendingUndelegations global flat array, swap-and-pop cleanup in
 *         _processDelegatorWithdrawals, userUndelegationIndices tracking, and sentinel
 *         invalidation to ensure correctness regardless of claim ordering.
 */
contract StakingOutOfOrderTest is Test {
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
    address public delegator1 = address(0x1001);
    address public delegator2 = address(0x1002);
    address public delegator3 = address(0x1003);
    address public delegator4 = address(0x1004);

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

    bytes32 public poolId1;
    bytes32 public poolId2;
    bytes32 public poolId3;

    function setUp() public {
        vm.startPrank(admin);
        chainConfig = new ChainConfig();
        ruleManager = new RuleManager();
        staking = new Staking();

        // Deploy ChainConfig proxy
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

        // Update ChainConfig to point to the Staking proxy
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
        values[4] = "2";
        keys[5] = "staking.min_staking_registration_value";
        values[5] = vm.toString(MIN_VALIDATOR_STAKE);

        vm.prank(address(staking));
        chainConfig.setConfig(keys, values);

        // Advance block to make configs effective
        vm.roll(block.number + 1);

        // Register 3 validators
        vm.deal(validator1, 100 ether);
        vm.prank(validator1);
        poolId1 = staking.registerValidator{value: 5 ether}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        vm.deal(validator2, 100 ether);
        vm.prank(validator2);
        poolId2 = staking.registerValidator{value: 5 ether}(
            DESCRIPTION, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        vm.deal(validator3, 100 ether);
        vm.prank(validator3);
        poolId3 = staking.registerValidator{value: 5 ether}(
            DESCRIPTION, PUBLIC_KEY3, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT3
        );

        // Activate all 3 validators
        advanceEpoch();

        // Fund delegators
        vm.deal(delegator1, 100 ether);
        vm.deal(delegator2, 100 ether);
        vm.deal(delegator3, 100 ether);
        vm.deal(delegator4, 100 ether);
    }

    function advanceEpoch() public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 4 hours + 1);
        vm.prank(admin);
        staking.advanceEpoch();
    }

    // ==================== Test 1: Two Delegators One Pool, Second Claims First ====================

    function test_OutOfOrder_TwoDelegatorsOnePool_SecondClaimsFirst() public {
        uint256 d1Amount = 2 ether;
        uint256 d2Amount = 3 ether;

        // Both delegators delegate to pool1
        vm.prank(delegator1);
        staking.delegate{value: d1Amount}(poolId1);
        vm.prank(delegator2);
        staking.delegate{value: d2Amount}(poolId1);

        // Advance epoch to activate pending stakes
        advanceEpoch();

        // delegator1 undelegates first, then delegator2
        vm.prank(delegator1);
        staking.undelegate(poolId1);
        vm.prank(delegator2);
        staking.undelegate(poolId1);

        // delegation_withdraw_effective_epoch = 2, so advance 2 epochs past unlock
        advanceEpoch(); // epoch +1
        advanceEpoch(); // epoch +2 — both now unlocked

        uint256 pendingCountBefore = staking.getPendingUndelegationCount();
        assertEq(pendingCountBefore, 2, "Should have 2 pending undelegations");

        // delegator2 claims FIRST (out of order)
        uint256 d2BalBefore = delegator2.balance;
        vm.prank(delegator2);
        staking.claimStake(poolId1);
        uint256 d2Received = delegator2.balance - d2BalBefore;
        assertEq(d2Received, d2Amount, "delegator2 should receive correct amount");

        // delegator1 claims SECOND
        uint256 d1BalBefore = delegator1.balance;
        vm.prank(delegator1);
        staking.claimStake(poolId1);
        uint256 d1Received = delegator1.balance - d1BalBefore;
        assertEq(d1Received, d1Amount, "delegator1 should receive correct amount");

        // Verify delegator states are clean
        IStaking.Delegator memory d1 = staking.getDelegator(poolId1, delegator1);
        assertEq(d1.stake, 0, "delegator1 stake should be 0");
        assertEq(d1.pendingWithdrawStake, 0, "delegator1 pendingWithdrawStake should be 0");
        assertFalse(d1.isPendingUndelegate, "delegator1 should not be pending undelegate");

        IStaking.Delegator memory d2 = staking.getDelegator(poolId1, delegator2);
        assertEq(d2.stake, 0, "delegator2 stake should be 0");
        assertEq(d2.pendingWithdrawStake, 0, "delegator2 pendingWithdrawStake should be 0");
        assertFalse(d2.isPendingUndelegate, "delegator2 should not be pending undelegate");

        // Advance epoch to trigger _processDelegatorWithdrawals cleanup
        advanceEpoch();

        uint256 pendingCountAfter = staking.getPendingUndelegationCount();
        assertEq(pendingCountAfter, 0, "pendingUndelegations should be cleaned up after epoch advance");
    }

    // ==================== Test 2: One Delegator Two Pools, Claim Second First ====================

    function test_OutOfOrder_OneDelegatorTwoPools_ClaimSecondFirst() public {
        uint256 amountPool1 = 2 ether;
        uint256 amountPool2 = 3 ether;

        // delegator1 delegates to pool1 and pool2
        vm.prank(delegator1);
        staking.delegate{value: amountPool1}(poolId1);
        vm.prank(delegator1);
        staking.delegate{value: amountPool2}(poolId2);

        // Advance epoch to activate
        advanceEpoch();

        // Undelegate from pool1 first, then pool2
        vm.prank(delegator1);
        staking.undelegate(poolId1);
        vm.prank(delegator1);
        staking.undelegate(poolId2);

        // Advance 2 epochs past unlock (delegation_withdraw_effective_epoch = 2)
        advanceEpoch();
        advanceEpoch();

        // Claim pool2 FIRST (out of order)
        uint256 balBefore2 = delegator1.balance;
        vm.prank(delegator1);
        staking.claimStake(poolId2);
        uint256 received2 = delegator1.balance - balBefore2;
        assertEq(received2, amountPool2, "Should receive correct pool2 amount");

        // Claim pool1 SECOND
        uint256 balBefore1 = delegator1.balance;
        vm.prank(delegator1);
        staking.claimStake(poolId1);
        uint256 received1 = delegator1.balance - balBefore1;
        assertEq(received1, amountPool1, "Should receive correct pool1 amount");

        // Verify delegator state is clean for both pools
        IStaking.Delegator memory d1p1 = staking.getDelegator(poolId1, delegator1);
        assertEq(d1p1.stake, 0);
        assertEq(d1p1.pendingWithdrawStake, 0);
        assertFalse(d1p1.isPendingUndelegate);

        IStaking.Delegator memory d1p2 = staking.getDelegator(poolId2, delegator1);
        assertEq(d1p2.stake, 0);
        assertEq(d1p2.pendingWithdrawStake, 0);
        assertFalse(d1p2.isPendingUndelegate);

        // Verify validator totalStake decreased correctly (only validator owner stake remains)
        IStaking.Validator memory v1 = staking.getValidator(poolId1);
        assertEq(v1.totalStake, 5 ether, "pool1 totalStake should be validator owner stake only");
        IStaking.Validator memory v2 = staking.getValidator(poolId2);
        assertEq(v2.totalStake, 5 ether, "pool2 totalStake should be validator owner stake only");

        // Cleanup
        advanceEpoch();
        assertEq(staking.getPendingUndelegationCount(), 0, "All pending undelegations should be cleaned up");
    }

    // ==================== Test 3: Three Delegators Two Pools, Interleaved Claims ====================

    function test_OutOfOrder_ThreeDelegatorsTwoPools_InterleavedClaims() public {
        uint256 d1Amount = 2 ether;
        uint256 d2Amount = 3 ether;
        uint256 d3Amount = 4 ether;

        // delegator1 -> pool1, delegator2 -> pool1, delegator3 -> pool2
        vm.prank(delegator1);
        staking.delegate{value: d1Amount}(poolId1);
        vm.prank(delegator2);
        staking.delegate{value: d2Amount}(poolId1);
        vm.prank(delegator3);
        staking.delegate{value: d3Amount}(poolId2);

        // Advance epoch to activate
        advanceEpoch();

        // All three undelegate
        vm.prank(delegator1);
        staking.undelegate(poolId1);
        vm.prank(delegator2);
        staking.undelegate(poolId1);
        vm.prank(delegator3);
        staking.undelegate(poolId2);

        assertEq(staking.getPendingUndelegationCount(), 3, "Should have 3 pending undelegations");

        // Advance 2 epochs past unlock
        advanceEpoch();
        advanceEpoch();

        // Claim in interleaved order: delegator3(pool2), delegator1(pool1), delegator2(pool1)
        uint256 d3BalBefore = delegator3.balance;
        vm.prank(delegator3);
        staking.claimStake(poolId2);
        assertEq(delegator3.balance - d3BalBefore, d3Amount, "delegator3 should receive correct amount");

        uint256 d1BalBefore = delegator1.balance;
        vm.prank(delegator1);
        staking.claimStake(poolId1);
        assertEq(delegator1.balance - d1BalBefore, d1Amount, "delegator1 should receive correct amount");

        uint256 d2BalBefore = delegator2.balance;
        vm.prank(delegator2);
        staking.claimStake(poolId1);
        assertEq(delegator2.balance - d2BalBefore, d2Amount, "delegator2 should receive correct amount");

        // Verify all delegator states are clean
        IStaking.Delegator memory d1 = staking.getDelegator(poolId1, delegator1);
        assertFalse(d1.isPendingUndelegate);
        assertEq(d1.pendingWithdrawStake, 0);

        IStaking.Delegator memory d2 = staking.getDelegator(poolId1, delegator2);
        assertFalse(d2.isPendingUndelegate);
        assertEq(d2.pendingWithdrawStake, 0);

        IStaking.Delegator memory d3 = staking.getDelegator(poolId2, delegator3);
        assertFalse(d3.isPendingUndelegate);
        assertEq(d3.pendingWithdrawStake, 0);

        // Verify validator totalStake
        IStaking.Validator memory v1 = staking.getValidator(poolId1);
        assertEq(v1.totalStake, 5 ether, "pool1 should have only validator owner stake");
        IStaking.Validator memory v2 = staking.getValidator(poolId2);
        assertEq(v2.totalStake, 5 ether, "pool2 should have only validator owner stake");

        // Cleanup epoch
        advanceEpoch();
        assertEq(staking.getPendingUndelegationCount(), 0, "All pending undelegations cleaned up");
    }

    // ==================== Test 4: Swap-And-Pop Consistency After Cleanup ====================

    function test_SwapAndPop_ConsistencyAfterCleanup() public {
        // Create 5 delegator addresses
        address[5] memory delegators;
        for (uint256 i = 0; i < 5; i++) {
            delegators[i] = address(uint160(0x100 + i));
            vm.deal(delegators[i], 10 ether);
        }

        uint256 stakeAmount = 1 ether;

        // All 5 delegate to pool1
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(delegators[i]);
            staking.delegate{value: stakeAmount}(poolId1);
        }

        // Advance epoch to activate
        advanceEpoch();

        // All 5 undelegate
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(delegators[i]);
            staking.undelegate(poolId1);
        }

        assertEq(staking.getPendingUndelegationCount(), 5, "Should have 5 pending undelegations");

        // Advance 2 epochs past unlock
        advanceEpoch();
        advanceEpoch();

        // Claim in REVERSE order (delegator5 first, delegator1 last)
        for (uint256 i = 5; i > 0; i--) {
            uint256 balBefore = delegators[i - 1].balance;
            vm.prank(delegators[i - 1]);
            staking.claimStake(poolId1);
            uint256 received = delegators[i - 1].balance - balBefore;
            assertEq(
                received, stakeAmount, string.concat("delegator", vm.toString(i), " should receive correct amount")
            );
        }

        // Advance epoch to trigger _processDelegatorWithdrawals cleanup
        advanceEpoch();

        // Verify pendingUndelegations array is properly cleaned up
        uint256 pendingCount = staking.getPendingUndelegationCount();
        assertEq(pendingCount, 0, "pendingUndelegations should be fully cleaned up after epoch advance");

        // Verify all delegator states are clean
        for (uint256 i = 0; i < 5; i++) {
            IStaking.Delegator memory d = staking.getDelegator(poolId1, delegators[i]);
            assertEq(d.stake, 0, "stake should be 0");
            assertEq(d.pendingWithdrawStake, 0, "pendingWithdrawStake should be 0");
            assertFalse(d.isPendingUndelegate, "should not be pending undelegate");
        }
    }

    // ==================== Test 5: Mixed Unlock Epochs (Validator vs Delegator Windows) ====================

    function test_OutOfOrder_MixedUnlockEpochs() public {
        // validator1 owner uses withdraw_effective_epoch = 1
        // delegator2 uses delegation_withdraw_effective_epoch = 2

        uint256 d2Amount = 2 ether;

        // delegator2 delegates to pool1
        vm.prank(delegator2);
        staking.delegate{value: d2Amount}(poolId1);

        // Advance epoch to activate delegator2's pending stake
        advanceEpoch();

        // validator1 does partial withdrawStake (uses validator window = 1 epoch)
        vm.prank(validator1);
        staking.withdrawStake(poolId1, 1 ether);

        // delegator2 undelegates (uses delegator window = 2 epochs)
        vm.prank(delegator2);
        staking.undelegate(poolId1);

        assertEq(staking.getPendingUndelegationCount(), 2, "Should have 2 pending undelegations");

        // Advance 1 epoch: validator1 can claim (window=1) but delegator2 cannot (window=2)
        advanceEpoch();

        // validator1 claims successfully
        uint256 v1BalBefore = validator1.balance;
        vm.prank(validator1);
        staking.claimStake(poolId1);
        uint256 v1Received = validator1.balance - v1BalBefore;
        assertEq(v1Received, 1 ether, "validator1 should receive 1 ether");

        // delegator2 cannot claim yet — should revert
        vm.prank(delegator2);
        vm.expectRevert("No withdrawable stake");
        staking.claimStake(poolId1);

        // Advance 1 more epoch: now delegator2 can claim (total 2 epochs passed)
        advanceEpoch();

        uint256 d2BalBefore = delegator2.balance;
        vm.prank(delegator2);
        staking.claimStake(poolId1);
        uint256 d2Received = delegator2.balance - d2BalBefore;
        assertEq(d2Received, d2Amount, "delegator2 should receive correct amount");

        // Verify states
        IStaking.Delegator memory v1Del = staking.getDelegator(poolId1, validator1);
        assertFalse(v1Del.isPendingUndelegate, "validator1 should not be pending undelegate");
        assertEq(v1Del.pendingWithdrawStake, 0, "validator1 pendingWithdrawStake should be 0");

        IStaking.Delegator memory d2Del = staking.getDelegator(poolId1, delegator2);
        assertFalse(d2Del.isPendingUndelegate, "delegator2 should not be pending undelegate");
        assertEq(d2Del.pendingWithdrawStake, 0, "delegator2 pendingWithdrawStake should be 0");

        // Cleanup
        advanceEpoch();
        assertEq(staking.getPendingUndelegationCount(), 0, "All pending undelegations cleaned up");
    }

    // ==================== Test 6: Claim Then New Delegation ====================

    function test_OutOfOrder_ClaimThenNewDelegation() public {
        uint256 firstAmount = 2 ether;
        uint256 secondAmount = 3 ether;

        // delegator1 delegates to pool1
        vm.prank(delegator1);
        staking.delegate{value: firstAmount}(poolId1);

        // Advance epoch to activate
        advanceEpoch();

        // Undelegate
        vm.prank(delegator1);
        staking.undelegate(poolId1);

        // Advance 2 epochs past unlock
        advanceEpoch();
        advanceEpoch();

        // Claim
        uint256 balBefore = delegator1.balance;
        vm.prank(delegator1);
        staking.claimStake(poolId1);
        uint256 received = delegator1.balance - balBefore;
        assertEq(received, firstAmount, "Should receive first delegation amount");

        // Advance epoch for cleanup
        advanceEpoch();
        assertEq(staking.getPendingUndelegationCount(), 0, "Old undelegation should be cleaned up");

        // Verify delegator state is fully clean
        IStaking.Delegator memory dBefore = staking.getDelegator(poolId1, delegator1);
        assertEq(dBefore.stake, 0, "stake should be 0 before re-delegation");
        assertEq(dBefore.pendingWithdrawStake, 0, "pendingWithdrawStake should be 0");
        assertFalse(dBefore.isPendingUndelegate, "should not be pending undelegate");

        // delegator1 delegates again to pool1
        vm.prank(delegator1);
        staking.delegate{value: secondAmount}(poolId1);

        // Advance epoch to activate new delegation
        advanceEpoch();

        // Trigger lazy activation via settleReward before checking stake
        vm.prank(delegator1);
        staking.settleReward(poolId1);

        // Verify delegator1 has correct new stake
        IStaking.Delegator memory dAfter = staking.getDelegator(poolId1, delegator1);
        assertEq(dAfter.stake, secondAmount, "Should have new stake amount");
        assertEq(dAfter.pendingStake, 0, "pendingStake should be 0 after activation");
        assertFalse(dAfter.isPendingUndelegate, "should not be pending undelegate");

        // Verify validator totalStake includes new delegation
        IStaking.Validator memory v = staking.getValidator(poolId1);
        assertEq(v.totalStake, 5 ether + secondAmount, "totalStake should include new delegation");
    }

    // ==================== Test 7: Multi-Pool Swap-And-Pop Index Consistency ====================

    function test_MultiPool_SwapAndPop_IndexConsistency() public {
        uint256 amount1 = 1 ether;
        uint256 amount2 = 2 ether;
        uint256 amount3 = 3 ether;

        // delegator1 delegates to pool1, pool2, pool3
        vm.prank(delegator1);
        staking.delegate{value: amount1}(poolId1);
        vm.prank(delegator1);
        staking.delegate{value: amount2}(poolId2);
        vm.prank(delegator1);
        staking.delegate{value: amount3}(poolId3);

        // Advance epoch to activate all
        advanceEpoch();

        // Undelegate from all three pools (creates 3 entries in pendingUndelegations)
        vm.prank(delegator1);
        staking.undelegate(poolId1);
        vm.prank(delegator1);
        staking.undelegate(poolId2);
        vm.prank(delegator1);
        staking.undelegate(poolId3);

        assertEq(staking.getPendingUndelegationCount(), 3, "Should have 3 pending undelegations");

        // Advance 2 epochs past unlock
        advanceEpoch();
        advanceEpoch();

        // Claim pool2 FIRST (middle entry — swap-and-pop may move entries)
        uint256 balBefore2 = delegator1.balance;
        vm.prank(delegator1);
        staking.claimStake(poolId2);
        assertEq(delegator1.balance - balBefore2, amount2, "Should receive pool2 amount");

        // Advance epoch to trigger cleanup (swap-and-pop moves entries around)
        advanceEpoch();

        // Claim pool1 and pool3 after cleanup
        uint256 balBefore1 = delegator1.balance;
        vm.prank(delegator1);
        staking.claimStake(poolId1);
        assertEq(delegator1.balance - balBefore1, amount1, "Should receive pool1 amount");

        uint256 balBefore3 = delegator1.balance;
        vm.prank(delegator1);
        staking.claimStake(poolId3);
        assertEq(delegator1.balance - balBefore3, amount3, "Should receive pool3 amount");

        // Verify all delegator states are clean
        IStaking.Delegator memory dp1 = staking.getDelegator(poolId1, delegator1);
        assertEq(dp1.stake, 0);
        assertEq(dp1.pendingWithdrawStake, 0);
        assertFalse(dp1.isPendingUndelegate);

        IStaking.Delegator memory dp2 = staking.getDelegator(poolId2, delegator1);
        assertEq(dp2.stake, 0);
        assertEq(dp2.pendingWithdrawStake, 0);
        assertFalse(dp2.isPendingUndelegate);

        IStaking.Delegator memory dp3 = staking.getDelegator(poolId3, delegator1);
        assertEq(dp3.stake, 0);
        assertEq(dp3.pendingWithdrawStake, 0);
        assertFalse(dp3.isPendingUndelegate);

        // Final cleanup
        advanceEpoch();
        assertEq(staking.getPendingUndelegationCount(), 0, "All pending undelegations should be cleaned up");

        // Verify validator totalStakes are correct (only owner stakes remain)
        assertEq(staking.getValidator(poolId1).totalStake, 5 ether, "pool1 totalStake correct");
        assertEq(staking.getValidator(poolId2).totalStake, 5 ether, "pool2 totalStake correct");
        assertEq(staking.getValidator(poolId3).totalStake, 5 ether, "pool3 totalStake correct");
    }

    // ==================== Test 8: Large Scale Many Delegators Many Claims ====================

    function test_LargeScale_ManyDelegatorsManyClaims() public {
        uint256 numDelegators = 10;
        uint256 stakeAmount = 1 ether;

        // Create 10 delegator addresses
        address[10] memory dels;
        for (uint256 i = 0; i < numDelegators; i++) {
            dels[i] = address(uint160(0x200 + i));
            vm.deal(dels[i], 10 ether);
        }

        // All 10 delegate to pool1
        for (uint256 i = 0; i < numDelegators; i++) {
            vm.prank(dels[i]);
            staking.delegate{value: stakeAmount}(poolId1);
        }

        // Advance epoch to activate
        advanceEpoch();

        // All 10 undelegate
        for (uint256 i = 0; i < numDelegators; i++) {
            vm.prank(dels[i]);
            staking.undelegate(poolId1);
        }

        assertEq(staking.getPendingUndelegationCount(), numDelegators, "Should have 10 pending undelegations");

        // Advance 2 epochs past unlock
        advanceEpoch();
        advanceEpoch();

        // Claim in random-ish order: 5, 3, 8, 1, 10, 2, 7, 4, 9, 6 (1-indexed)
        uint256[10] memory claimOrder = [uint256(4), 2, 7, 0, 9, 1, 6, 3, 8, 5];

        // Claim first 5, then advance epoch for partial cleanup, then claim remaining 5
        for (uint256 i = 0; i < 5; i++) {
            uint256 idx = claimOrder[i];
            uint256 balBefore = dels[idx].balance;
            vm.prank(dels[idx]);
            staking.claimStake(poolId1);
            uint256 received = dels[idx].balance - balBefore;
            assertEq(received, stakeAmount, "Should receive correct amount");
        }

        // Advance epoch between some claims to trigger partial cleanup
        advanceEpoch();

        uint256 pendingAfterPartial = staking.getPendingUndelegationCount();
        assertTrue(pendingAfterPartial < numDelegators, "Pending count should decrease after partial cleanup");

        // Claim remaining 5
        for (uint256 i = 5; i < 10; i++) {
            uint256 idx = claimOrder[i];
            uint256 balBefore = dels[idx].balance;
            vm.prank(dels[idx]);
            staking.claimStake(poolId1);
            uint256 received = dels[idx].balance - balBefore;
            assertEq(received, stakeAmount, "Should receive correct amount");
        }

        // Final cleanup epoch
        advanceEpoch();
        assertEq(staking.getPendingUndelegationCount(), 0, "All pending undelegations should be cleaned up");

        // Verify all 10 delegator states are clean
        for (uint256 i = 0; i < numDelegators; i++) {
            IStaking.Delegator memory d = staking.getDelegator(poolId1, dels[i]);
            assertEq(d.stake, 0, "stake should be 0");
            assertEq(d.pendingWithdrawStake, 0, "pendingWithdrawStake should be 0");
            assertFalse(d.isPendingUndelegate, "should not be pending undelegate");
        }

        // Verify validator totalStake is correct (only owner stake remains)
        IStaking.Validator memory v = staking.getValidator(poolId1);
        assertEq(v.totalStake, 5 ether, "pool1 totalStake should be validator owner stake only");
    }
}
