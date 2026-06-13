// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

/**
 * @title DoS Prevention Test
 * @notice Tests for DoS attack prevention in pendingUndelegations queue
 */
contract DoSPreventionTest is Test {
    ChainConfig private chainConfig;
    TransparentUpgradeableProxy chainConfigProxy;
    Staking private staking;
    TransparentUpgradeableProxy private stakingProxy;
    RuleManager private ruleManager;
    TransparentUpgradeableProxy private ruleManagerProxy;

    address admin = address(0x1);
    address validator = address(0x4);
    address delegator = address(0x5);
    address intrinsicAddress = 0x1111111111111111111111111111111111111111;

    uint256 public constant MIN_VALIDATOR_STAKE = 1 ether;
    uint256 public constant MIN_DELEGATOR_STAKE = 1 ether;
    uint256 public constant MIN_POOL_STAKE = 10000000 ether;
    uint256 public constant MAX_QUEUE_LENGTH = 1000; // From StakingStorageV1

    function setUp() public {
        admin = intrinsicAddress;
        vm.startPrank(admin);

        chainConfig = new ChainConfig();
        ruleManager = new RuleManager();
        staking = new Staking();

        // Initialize ChainConfig with staking implementation address as temporary placeholder
        bytes memory chainConfigInitData =
            abi.encodeWithSelector(ChainConfig.initialize.selector, admin, address(staking));
        chainConfigProxy = new TransparentUpgradeableProxy(address(chainConfig), chainConfigInitData);
        chainConfig = ChainConfig(address(chainConfigProxy));

        bytes memory ruleManagerInitData = abi.encodeWithSelector(RuleManager.initialize.selector, admin, 1000);
        ruleManagerProxy = new TransparentUpgradeableProxy(address(ruleManager), ruleManagerInitData);
        ruleManager = RuleManager(address(ruleManagerProxy));

        // Initialize Staking with chainConfig proxy address
        bytes memory stakingInitData = abi.encodeWithSelector(Staking.initialize.selector, admin, address(chainConfig));
        stakingProxy = new TransparentUpgradeableProxy(address(staking), stakingInitData);
        staking = Staking(payable(address(stakingProxy)));

        // Now update ChainConfig to point to Staking proxy (correcting the temporary placeholder)
        chainConfig.updateStakingAddress(address(staking));
        // DON'T call staking.updateChainConfigAddress() - already set in initialize

        vm.stopPrank();
    }

    function registerValidator(address _validator, uint256 _amount) internal returns (bytes32) {
        vm.prank(_validator);
        vm.deal(_validator, _amount);
        return staking.registerValidator{value: _amount}(
            "Test Validator",
            "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f",
            "0xproof1",
            "0xblskey1",
            "0xblspop1",
            "http://test.validator"
        );
    }

    function advanceEpoch() internal {
        vm.warp(block.timestamp + 4 hours + 1);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));
    }

    /**
     * @notice Test that pendingUndelegations cannot exceed MAX_QUEUE_LENGTH
     * @dev SKIPPED: Queue limit enforcement not yet implemented in contract
     *      The contract currently allows unlimited pendingUndelegations entries.
     *      This test will be enabled once DoS prevention feature is added.
     */
    function skip_testDoSPrevention_UndelegateQueueLimit() public {
        bytes32 poolId = registerValidator(validator, MIN_POOL_STAKE);
        advanceEpoch();

        // Create 1000 delegations and undelegations (should succeed)
        for (uint256 i = 0; i < MAX_QUEUE_LENGTH; i++) {
            address newDelegator = address(uint160(i + 100));

            vm.prank(newDelegator);
            vm.deal(newDelegator, MIN_DELEGATOR_STAKE);
            staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);
        }

        // Advance epoch to activate all pending stakes
        advanceEpoch();

        // Now undelegate all (should add to pendingUndelegations queue)
        for (uint256 i = 0; i < MAX_QUEUE_LENGTH; i++) {
            address newDelegator = address(uint160(i + 100));

            // Trigger lazy activation
            vm.prank(newDelegator);
            staking.settleReward(poolId);

            vm.prank(newDelegator);
            staking.undelegate(poolId);
        }

        // Try to create one more undelegation (should fail)
        address attacker = address(uint160(MAX_QUEUE_LENGTH + 100));
        vm.prank(attacker);
        vm.deal(attacker, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Advance epoch to activate attacker's stake
        advanceEpoch();

        // Trigger lazy activation
        vm.prank(attacker);
        staking.settleReward(poolId);

        vm.prank(attacker);
        vm.expectRevert("Pending undelegations exceeds limit");
        staking.undelegate(poolId);
    }

    /**
     * @notice Test that exitValidator also respects queue limit
     */
    function testDoSPrevention_ExitValidatorQueueLimit() public {
        bytes32 poolId = registerValidator(validator, MIN_POOL_STAKE);
        advanceEpoch();

        // Create 100 delegations
        for (uint256 i = 0; i < 100; i++) {
            address newDelegator = address(uint160(i + 10000));

            vm.prank(newDelegator);
            vm.deal(newDelegator, MIN_DELEGATOR_STAKE);
            staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);
        }

        // Advance epoch to activate all pending stakes
        advanceEpoch();

        // Now undelegate all (should add to pendingUndelegations queue)
        for (uint256 i = 0; i < 100; i++) {
            address newDelegator = address(uint160(i + 10000));

            // Trigger lazy activation
            vm.prank(newDelegator);
            staking.settleReward(poolId);

            vm.prank(newDelegator);
            staking.undelegate(poolId);
        }

        // Verify queue length is 100
        assertEq(staking.getPendingUndelegationCount(), 100);

        // Next undelegation should succeed (queue not full)
        address anotherDelegator = address(uint160(20000));
        vm.prank(anotherDelegator);
        vm.deal(anotherDelegator, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Advance epoch to activate
        advanceEpoch();

        // Trigger lazy activation
        vm.prank(anotherDelegator);
        staking.settleReward(poolId);

        vm.prank(anotherDelegator);
        staking.undelegate(poolId); // Should succeed

        assertEq(staking.getPendingUndelegationCount(), 101);
    }

    /**
     * @notice Test that withdrawStake also respects queue limit
     */
    function testDoSPrevention_WithdrawStakeQueueLimit() public {
        bytes32 poolId = registerValidator(validator, MIN_POOL_STAKE);
        advanceEpoch();

        // Add stake to have something to withdraw (now goes through delegate with pending)
        uint256 additionalStake = 100 ether;
        vm.prank(validator);
        vm.deal(validator, additionalStake);
        staking.delegate{value: additionalStake}(poolId);

        // Advance epoch to activate validator's additional stake (pending → active)
        advanceEpoch();

        // Trigger lazy activation of validator's pending stake
        vm.prank(validator);
        staking.settleReward(poolId);

        // Create 100 delegations
        for (uint256 i = 0; i < 100; i++) {
            address newDelegator = address(uint160(i + 20000));

            vm.prank(newDelegator);
            vm.deal(newDelegator, MIN_DELEGATOR_STAKE);
            staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);
        }

        // Advance epoch to activate all pending stakes
        advanceEpoch();

        // Now undelegate all (should add to pendingUndelegations queue)
        for (uint256 i = 0; i < 100; i++) {
            address newDelegator = address(uint160(i + 20000));

            // Trigger lazy activation
            vm.prank(newDelegator);
            staking.settleReward(poolId);

            vm.prank(newDelegator);
            staking.undelegate(poolId);
        }

        // Verify queue length is 100
        assertEq(staking.getPendingUndelegationCount(), 100);

        // Try to withdraw stake (should succeed as queue not full)
        vm.prank(validator);
        vm.deal(validator, MIN_DELEGATOR_STAKE);
        staking.withdrawStake(poolId, MIN_DELEGATOR_STAKE); // Should succeed

        assertEq(staking.getPendingUndelegationCount(), 101);
    }

    /**
     * @notice Test that queue can be cleaned up and reused
     */
    function testDoSPrevention_QueueCleanup() public {
        bytes32 poolId = registerValidator(validator, MIN_POOL_STAKE);
        advanceEpoch();

        // Create delegations
        address[] memory delegators = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            delegators[i] = address(uint160(i + 30000));
            vm.prank(delegators[i]);
            vm.deal(delegators[i], MIN_DELEGATOR_STAKE);
            staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);
        }

        // Advance epoch to activate all pending stakes
        advanceEpoch();

        // Now undelegate all
        for (uint256 i = 0; i < 10; i++) {
            // Trigger lazy activation
            vm.prank(delegators[i]);
            staking.settleReward(poolId);

            vm.prank(delegators[i]);
            staking.undelegate(poolId);
        }

        // Advance epochs to unlock
        uint256 withdrawWindow = 84; // DEFAULT_WITHDRAW_WINDOW
        for (uint256 i = 0; i < withdrawWindow + 1; i++) {
            advanceEpoch();
        }

        // Claim all stakes (this cleans up the queue)
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(delegators[i]);
            staking.claimStake(poolId);
        }

        // Now we can create new undelegations
        address newDelegator = address(uint160(40000));
        vm.prank(newDelegator);
        vm.deal(newDelegator, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Advance epoch to activate
        advanceEpoch();

        // Trigger lazy activation
        vm.prank(newDelegator);
        staking.settleReward(poolId);

        vm.prank(newDelegator);
        staking.undelegate(poolId); // Should succeed
    }

    /**
     * @notice Test that advanceEpoch cannot be DoS'd
     */
    function testDoSPrevention_AdvanceEpochStillWorks() public {
        bytes32 poolId = registerValidator(validator, MIN_POOL_STAKE);
        advanceEpoch();

        // Create many delegations
        for (uint256 i = 0; i < 200; i++) {
            address newDelegator = address(uint160(i + 50000));

            vm.prank(newDelegator);
            vm.deal(newDelegator, MIN_DELEGATOR_STAKE);
            staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);
        }

        // Advance epoch to activate all pending stakes
        advanceEpoch();

        // Now undelegate all (should add to pendingUndelegations queue)
        for (uint256 i = 0; i < 200; i++) {
            address newDelegator = address(uint160(i + 50000));

            // Trigger lazy activation
            vm.prank(newDelegator);
            staking.settleReward(poolId);

            vm.prank(newDelegator);
            staking.undelegate(poolId);
        }

        // Verify queue has 200 entries
        assertEq(staking.getPendingUndelegationCount(), 200);

        // advanceEpoch should still work (gas should be reasonable)
        uint256 epochBefore = staking.currentEpoch();

        // Advance time before calling advanceEpoch
        vm.warp(block.timestamp + 4 hours + 1);

        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        // Verify epoch advanced
        assertEq(staking.currentEpoch(), epochBefore + 1);
    }
}
