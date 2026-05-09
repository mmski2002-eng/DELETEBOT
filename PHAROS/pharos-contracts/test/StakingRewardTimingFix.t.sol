// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/staking/Staking.sol";
import "../src/staking/interfaces/IStaking.sol";
import "../src/chainConfig/ChainConfig.sol";
import "../src/ruleManager/RuleManager.sol";
import "../src/TransparentUpgradeableProxy.sol";

/**
 * @title Tests for Staking Reward Timing Fix
 * @notice Comprehensive tests for the critical delegation reward timing vulnerability fix
 * @dev Tests cover:
 * 1. No premature rewards (user doesn't get rewards for epochs they didn't participate in)
 * 2. Correct rewards after activation
 * 3. Consecutive delegations
 * 4. Compound with pending stake
 * 5. Undelegate with pending stake
 */
contract StakingRewardTimingFixTest is Test {
    ChainConfig public chainConfig;
    TransparentUpgradeableProxy public chainConfigProxy;
    Staking public staking;
    TransparentUpgradeableProxy public stakingProxy;
    RuleManager public ruleManager;
    TransparentUpgradeableProxy public ruleManagerProxy;

    address public admin = address(0x1111111111111111111111111111111111111111);
    address public stakingAddress = address(0x2);
    address public validator = address(0x456);
    address public user1 = address(0x789);
    address public user2 = address(0xabc);

    uint256 constant MIN_VALIDATOR_STAKE = 10_000_000 * 1 ether;
    uint256 constant EPOCH_DURATION = 4 hours; // Match default epoch duration
    uint256 constant PRECISION = 1e18;

    bytes32 validatorPoolId;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy implementations
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

        // Deploy Staking proxy
        bytes memory stakingInitData = abi.encodeWithSelector(Staking.initialize.selector, admin, address(chainConfig));
        stakingProxy = new TransparentUpgradeableProxy(address(staking), stakingInitData);
        staking = Staking(payable(address(stakingProxy)));

        // Update ChainConfig to point to Staking proxy
        chainConfig.updateStakingAddress(address(staking));

        vm.stopPrank();

        // Configure ChainConfig
        string[] memory keys = new string[](5);
        string[] memory values = new string[](5);
        keys[0] = "staking.min_staking_pool_value";
        values[0] = vm.toString(MIN_VALIDATOR_STAKE);
        keys[1] = "staking.max_staking_pool_value";
        values[1] = vm.toString(uint256(100000000 ether));
        keys[2] = "staking.min_delegator_stake";
        values[2] = vm.toString(uint256(1 ether));
        keys[3] = "staking.withdraw_effective_epoch";
        values[3] = "1";
        keys[4] = "staking.min_staking_registration_value";
        values[4] = vm.toString(MIN_VALIDATOR_STAKE);

        vm.prank(address(staking));
        chainConfig.setConfig(keys, values);

        // Advance block to make configs effective
        vm.roll(block.number + 1);

        // Register validator
        vm.deal(validator, MIN_VALIDATOR_STAKE);
        vm.prank(validator);
        validatorPoolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            "Test Validator",
            "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f",
            "0xproof1",
            "0xblskey1",
            "0xblspop1",
            "http://test.validator"
        );

        // Set commission rate to 10%
        vm.prank(validator);
        staking.setCommissionRate(validatorPoolId, 1000);

        // Advance epoch to activate validator
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);

        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = validatorPoolId;
        uint256[] memory fees = new uint256[](1);
        fees[0] = 0;

        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);
    }

    /**
     * @notice Test 1: Verify users don't get premature rewards
     * User delegates in epoch N, should NOT get rewards for epoch N
     */
    function test_NoPrematureReward() public {
        uint256 currentEpoch = staking.currentEpoch();
        console.log("Starting epoch:", currentEpoch);

        // User delegates 1000 ETH in epoch N
        uint256 delegateAmount = 1000 ether;
        vm.deal(user1, delegateAmount);
        vm.prank(user1);
        staking.delegate{value: delegateAmount}(validatorPoolId);

        // Check state after delegation
        IStaking.Delegator memory delegator = staking.getDelegator(validatorPoolId, user1);
        console.log("After delegate:");
        console.log("  stake:", delegator.stake / 1 ether);
        console.log("  pendingStake:", delegator.pendingStake / 1 ether);
        assertEq(delegator.stake, 0, "Stake should be 0 (pending)");
        assertEq(delegator.pendingStake, delegateAmount, "PendingStake should be delegateAmount");

        // Advance epoch N -> N+1
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = validatorPoolId;
        uint256[] memory fees = new uint256[](1);
        fees[0] = 0;

        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);

        console.log("\nAfter first epoch advance:");
        console.log("Current epoch:", staking.currentEpoch());

        // User immediately undelegates (triggers activation)
        vm.prank(user1);
        staking.undelegate(validatorPoolId);

        delegator = staking.getDelegator(validatorPoolId, user1);
        console.log("After undelegate:");
        console.log("  rewards:", delegator.rewards / 1 ether);

        // Critical assertion: User should have NO rewards for epoch N
        // because their stake wasn't in epoch N's snapshot
        assertEq(delegator.rewards, 0, "User should have 0 rewards (didn't participate in epoch N)");
    }

    /**
     * @notice Test 2: Verify correct rewards after activation
     * User delegates in epoch N, should get rewards starting from epoch N+1
     */
    function test_CorrectRewardAfterActivation() public {
        uint256 currentEpoch = staking.currentEpoch();
        console.log("Starting epoch:", currentEpoch);

        // User delegates 1000 ETH in epoch N
        uint256 delegateAmount = 1000 ether;
        vm.deal(user1, delegateAmount);
        vm.prank(user1);
        staking.delegate{value: delegateAmount}(validatorPoolId);

        // Advance epoch N -> N+1 (user's stake activates)
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = validatorPoolId;
        uint256[] memory fees = new uint256[](1);
        fees[0] = 0;

        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);

        console.log("\nAfter activation epoch:");
        console.log("Current epoch:", staking.currentEpoch());

        // Advance epoch N+1 -> N+2 (user earns rewards for epoch N+1)
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);

        console.log("\nAfter reward epoch:");
        console.log("Current epoch:", staking.currentEpoch());

        // Check rewards by calling undelegate (which settles and combines stake+rewards)
        vm.prank(user1);
        (uint256 withdrawalAmount,) = staking.undelegate(validatorPoolId);

        // Withdrawal amount should be principal + rewards
        // User should have rewards for participating in epoch N+1 (epoch 2)
        uint256 expectedMinReward = 1 ether; // Should be at least 1 ETH reward
        assertTrue(withdrawalAmount > delegateAmount + expectedMinReward, "User should have rewards for epoch N+1");

        console.log("Total withdrawal (principal + rewards):", withdrawalAmount / 1 ether);
        console.log("Principal:", delegateAmount / 1 ether);
        console.log("Rewards:", (withdrawalAmount - delegateAmount) / 1 ether);
    }

    /**
     * @notice Test 3: Consecutive delegations with correct reward allocation
     * User delegates 100 ETH in epoch N, then 50 ETH in epoch N+2
     * Verify each stake only gets rewards from when it was activated
     */
    function test_ConsecutiveDelegations() public {
        uint256 currentEpoch = staking.currentEpoch();
        console.log("\n=== Test Consecutive Delegations ===");
        console.log("Starting epoch:", currentEpoch);

        // First delegation: 100 ETH in epoch N
        uint256 firstAmount = 100 ether;
        vm.deal(user1, firstAmount);
        vm.prank(user1);
        staking.delegate{value: firstAmount}(validatorPoolId);

        console.log("\nAfter first delegate (100 ETH):");
        IStaking.Delegator memory delegator = staking.getDelegator(validatorPoolId, user1);
        console.log("  stake:", delegator.stake / 1 ether);
        console.log("  pendingStake:", delegator.pendingStake / 1 ether);

        // Advance epoch N -> N+1 (first stake activates)
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = validatorPoolId;
        uint256[] memory fees = new uint256[](1);
        fees[0] = 0;

        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);

        console.log("\nEpoch N->N+1 (first stake activates):");
        console.log("Current epoch:", staking.currentEpoch());

        // Advance epoch N+1 -> N+2 (first stake earns rewards)
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);

        console.log("\nEpoch N+1->N+2 (first stake earns):");
        console.log("Current epoch:", staking.currentEpoch());

        // Second delegation: 50 ETH in epoch N+2 (also activates first stake if not already)
        uint256 secondAmount = 50 ether;
        vm.deal(user1, secondAmount);
        vm.prank(user1);
        staking.delegate{value: secondAmount}(validatorPoolId);

        console.log("\nAfter second delegate (50 ETH):");
        delegator = staking.getDelegator(validatorPoolId, user1);
        console.log("  stake:", delegator.stake / 1 ether);
        console.log("  pendingStake:", delegator.pendingStake / 1 ether);
        console.log("  rewards:", delegator.rewards / 1 ether);

        // First 100 ETH should be active and have rewards from epoch N+1
        assertEq(delegator.stake, firstAmount, "First stake should be active");
        assertEq(delegator.pendingStake, secondAmount, "Second stake should be pending");
        assertTrue(delegator.rewards > 0, "Should have rewards from first stake");

        // Advance epoch N+2 -> N+3 (second stake activates, both earn)
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);

        console.log("\nEpoch N+2->N+3 (second stake activates):");
        console.log("Current epoch:", staking.currentEpoch());

        // Advance epoch N+3 -> N+4 (both stakes earn)
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);

        console.log("\nEpoch N+3->N+4 (both stakes earn):");
        console.log("Current epoch:", staking.currentEpoch());

        // Undelegate and check total rewards
        uint256 totalPrincipal = firstAmount + secondAmount;
        vm.prank(user1);
        (uint256 withdrawalAmount,) = staking.undelegate(validatorPoolId);

        console.log("\nTotal withdrawal:", withdrawalAmount / 1 ether);
        console.log("Total principal:", totalPrincipal / 1 ether);
        console.log("Rewards earned:", (withdrawalAmount - totalPrincipal) / 1 ether);

        // User should have:
        // - 100 ETH earned rewards for epochs N+1, N+2, N+3
        // - 50 ETH earned rewards for epoch N+3
        assertTrue(withdrawalAmount > totalPrincipal, "Should have accumulated rewards");
    }

    /**
     * @notice Test 4: Compound rewards with pending stake
     * Verify compound works correctly when there's pending stake
     */
    function test_CompoundWithPending() public {
        uint256 currentEpoch = staking.currentEpoch();
        console.log("\n=== Test Compound With Pending ===");
        console.log("Starting epoch:", currentEpoch);

        // Initial delegation
        uint256 initialAmount = 1000 ether;
        vm.deal(user1, initialAmount);
        vm.prank(user1);
        staking.delegate{value: initialAmount}(validatorPoolId);

        // Advance 2 epochs so user has active stake and rewards
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = validatorPoolId;
        uint256[] memory fees = new uint256[](1);
        fees[0] = 0;

        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);

        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);

        console.log("\nAfter earning rewards:");
        console.log("Current epoch:", staking.currentEpoch());

        // Settle reward to activate pending and calculate rewards
        vm.prank(user1);
        staking.settleReward(validatorPoolId);

        uint256 rewardsBefore = staking.getDelegatorReward(validatorPoolId, user1);
        console.log("Rewards before compound:", rewardsBefore / 1 ether);
        assertTrue(rewardsBefore > 0, "Should have rewards");

        // Compound rewards
        vm.prank(user1);
        staking.compoundRewards(validatorPoolId);

        console.log("\nAfter compound:");
        IStaking.Delegator memory delegator = staking.getDelegator(validatorPoolId, user1);
        console.log("  stake:", delegator.stake / 1 ether);
        console.log("  pendingStake:", delegator.pendingStake / 1 ether);
        console.log("  rewards:", delegator.rewards / 1 ether);

        // Rewards should be added as pendingStake
        assertEq(delegator.rewards, 0, "Rewards should be 0 after compound");
        assertEq(delegator.pendingStake, rewardsBefore, "Compounded rewards should be pending");

        // Advance epoch to activate compounded rewards
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);

        console.log("\nAfter compound activation:");
        console.log("Current epoch:", staking.currentEpoch());

        // Trigger activation by interacting
        vm.prank(user1);
        staking.settleReward(validatorPoolId);

        delegator = staking.getDelegator(validatorPoolId, user1);
        console.log("  stake:", delegator.stake / 1 ether);
        console.log("  pendingStake:", delegator.pendingStake / 1 ether);

        // Compounded amount should now be active
        assertEq(delegator.pendingStake, 0, "Pending should be 0 after activation");
        assertEq(delegator.stake, initialAmount + rewardsBefore, "Stake should include compounded rewards");
    }

    /**
     * @notice Test 5: Undelegate with pending stake
     * Verify pending stake is activated before undelegating
     */
    function test_UndelegateWithPending() public {
        uint256 currentEpoch = staking.currentEpoch();
        console.log("\n=== Test Undelegate With Pending ===");
        console.log("Starting epoch:", currentEpoch);

        // Delegate
        uint256 amount = 1000 ether;
        vm.deal(user1, amount);
        vm.prank(user1);
        staking.delegate{value: amount}(validatorPoolId);

        console.log("\nAfter delegate:");
        IStaking.Delegator memory delegator = staking.getDelegator(validatorPoolId, user1);
        console.log("  stake:", delegator.stake / 1 ether);
        console.log("  pendingStake:", delegator.pendingStake / 1 ether);

        // Advance epoch to activation time
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = validatorPoolId;
        uint256[] memory fees = new uint256[](1);
        fees[0] = 0;

        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);

        console.log("\nAfter epoch (activation time):");
        console.log("Current epoch:", staking.currentEpoch());

        // Undelegate should trigger activation
        vm.prank(user1);
        staking.undelegate(validatorPoolId);

        console.log("\nAfter undelegate:");
        delegator = staking.getDelegator(validatorPoolId, user1);
        console.log("  stake:", delegator.stake / 1 ether);
        console.log("  pendingWithdrawStake:", delegator.pendingWithdrawStake / 1 ether);

        // Stake should have been activated before undelegating
        assertEq(delegator.stake, 0, "Stake should be 0 after undelegate");
        assertEq(delegator.pendingWithdrawStake, amount, "Full amount should be pending withdrawal");
    }

    /**
     * @notice Test 6: Multiple users with staggered delegations
     * Verify each user gets correct rewards based on when they delegated
     */
    function test_MultipleUsersStaggeredDelegations() public {
        console.log("\n=== Test Multiple Users Staggered ===");
        uint256 startEpoch = staking.currentEpoch();
        console.log("Starting epoch:", startEpoch);

        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = validatorPoolId;
        uint256[] memory fees = new uint256[](1);
        fees[0] = 0;

        // User1 delegates in epoch N
        uint256 user1Amount = 1000 ether;
        vm.deal(user1, user1Amount);
        vm.prank(user1);
        staking.delegate{value: user1Amount}(validatorPoolId);
        console.log("\nUser1 delegates 1000 ETH in epoch", staking.currentEpoch());

        // Advance epoch N -> N+1
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);
        console.log("Advanced to epoch", staking.currentEpoch());

        // User2 delegates in epoch N+1
        uint256 user2Amount = 2000 ether;
        vm.deal(user2, user2Amount);
        vm.prank(user2);
        staking.delegate{value: user2Amount}(validatorPoolId);
        console.log("\nUser2 delegates 2000 ETH in epoch", staking.currentEpoch());

        // Advance epoch N+1 -> N+2
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);
        console.log("Advanced to epoch", staking.currentEpoch());

        // Advance epoch N+2 -> N+3 (both users earn)
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);
        console.log("Advanced to epoch", staking.currentEpoch());

        // Check rewards (need to settle first to activate pending and calculate rewards)
        vm.prank(user1);
        staking.settleReward(validatorPoolId);
        vm.prank(user2);
        staking.settleReward(validatorPoolId);

        uint256 user1Rewards = staking.getDelegatorReward(validatorPoolId, user1);
        uint256 user2Rewards = staking.getDelegatorReward(validatorPoolId, user2);

        console.log("\nUser1 rewards:", user1Rewards / 1 ether);
        console.log("User2 rewards:", user2Rewards / 1 ether);

        // User1 should have more rewards (participated in more epochs)
        assertTrue(user1Rewards > user2Rewards, "User1 should have more rewards (earlier entry)");
        assertTrue(user2Rewards > 0, "User2 should have some rewards");
    }

    /**
     * @notice Test 7: Historical RPS refcount mechanism
     * Verify historical RPS is saved and cleaned up correctly
     */
    function test_HistoricalRPSRefcount() public {
        console.log("\n=== Test Historical RPS Refcount ===");
        uint256 startEpoch = staking.currentEpoch();
        console.log("Starting epoch:", startEpoch);

        // User1 delegates (reserves slot for epoch N+1)
        uint256 amount = 1000 ether;
        vm.deal(user1, amount);
        vm.prank(user1);
        staking.delegate{value: amount}(validatorPoolId);

        // Check refcount for next epoch
        uint256 nextEpoch = staking.currentEpoch() + 1;
        (uint256 rps, uint256 refcount) = staking.historicalRPS(nextEpoch, validatorPoolId);
        console.log("\nAfter delegate:");
        console.log("  Refcount for epoch", nextEpoch, ":", refcount);
        assertEq(refcount, 1, "Refcount should be 1 after first delegate");

        // User2 also delegates (increments refcount)
        vm.deal(user2, amount);
        vm.prank(user2);
        staking.delegate{value: amount}(validatorPoolId);

        (rps, refcount) = staking.historicalRPS(nextEpoch, validatorPoolId);
        console.log("  Refcount after second delegate:", refcount);
        assertEq(refcount, 2, "Refcount should be 2 after second delegate");

        // Advance epoch (RPS should be saved)
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = validatorPoolId;
        uint256[] memory fees = new uint256[](1);
        fees[0] = 0;

        vm.prank(admin);
        staking.advanceEpoch(poolIds, fees);

        (rps, refcount) = staking.historicalRPS(nextEpoch, validatorPoolId);
        console.log("\nAfter epoch advance:");
        console.log("  RPS for epoch", nextEpoch, ":", rps);
        console.log("  Refcount:", refcount);
        assertTrue(rps > 0, "RPS should be saved");
        assertEq(refcount, 2, "Refcount should still be 2");

        // User1 triggers activation (decrements refcount)
        vm.prank(user1);
        staking.settleReward(validatorPoolId);

        (rps, refcount) = staking.historicalRPS(nextEpoch, validatorPoolId);
        console.log("\nAfter user1 activation:");
        console.log("  Refcount:", refcount);
        assertEq(refcount, 1, "Refcount should be 1 after user1 activation");

        // User2 triggers activation (decrements refcount to 0)
        vm.prank(user2);
        staking.settleReward(validatorPoolId);

        (rps, refcount) = staking.historicalRPS(nextEpoch, validatorPoolId);
        console.log("\nAfter user2 activation:");
        console.log("  Refcount:", refcount);
        assertEq(refcount, 0, "Refcount should be 0 after both activations");
    }
}
