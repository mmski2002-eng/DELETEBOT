// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {Staking} from "../src/staking/Staking.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

/**
 * @title StakingAtomicityTest
 * @notice Tests atomicity constraints of the Staking contract — operations blocked
 *         when pendingStake or isPendingUndelegate are non-zero, and operations
 *         that remain allowed regardless.
 */
contract StakingAtomicityTest is Test {
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
    address public delegator1 = address(0x7);
    address public delegator2 = address(0x8);

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

    bytes32 public pool1;
    bytes32 public pool2;

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
        values[4] = "2";
        keys[5] = "staking.min_staking_registration_value";
        values[5] = vm.toString(MIN_VALIDATOR_STAKE);

        vm.prank(address(staking));
        chainConfig.setConfig(keys, values);

        // Advance block to make configs effective
        vm.roll(block.number + 1);

        // Register 2 validators
        vm.prank(validator1);
        vm.deal(validator1, 10 ether);
        pool1 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );

        vm.prank(validator2);
        vm.deal(validator2, 10 ether);
        pool2 = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT2
        );

        // Advance epoch to activate validators
        advanceEpoch();

        // Fund delegators
        vm.deal(delegator1, 100 ether);
        vm.deal(delegator2, 100 ether);
    }

    function advanceEpoch() public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch();
    }

    // =========================================================================
    // Category 1: pendingStake blocks operations
    // =========================================================================

    /// @notice Delegating again in the same epoch reverts because pendingStake > 0
    function test_Atomicity_DelegateBlockedByPendingStake() public {
        // delegator1 delegates to pool1 — creates pendingStake
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);

        // Same epoch: delegate again to pool1 → revert
        vm.prank(delegator1);
        vm.expectRevert("Cannot delegate while pending stake exists");
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);

        // Same epoch: delegate to pool2 → also revert (pendingStake checked after settleReward per-pool,
        // but the delegator's pendingStake on pool1 is non-zero; pool2 is a different pool so it should succeed
        // unless the check is per-pool). Let's verify pool2 works since it's a separate delegator record.
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool2);
        // pool2 delegation succeeds because pendingStake is per-pool
    }

    /// @notice Undelegate reverts when delegator has pendingStake on the same pool
    function test_Atomicity_UndelegateBlockedByPendingStake() public {
        // delegator1 delegates to pool1, advance epoch to activate
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);
        advanceEpoch();

        // delegator1 delegates again to pool1 — creates new pendingStake
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);

        // Try to undelegate pool1 → revert
        vm.prank(delegator1);
        vm.expectRevert("delegator has pending stake, not allowed to undelegate");
        staking.undelegate(pool1);

        // After advancing epoch (pendingStake activates), undelegate should succeed
        advanceEpoch();
        vm.prank(delegator1);
        staking.undelegate(pool1);
    }

    /// @notice compoundRewards reverts when delegator has pendingStake
    function test_Atomicity_CompoundBlockedByPendingStake() public {
        // delegator1 delegates to pool1, advance epoch to activate
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);
        advanceEpoch();

        // Advance another epoch to generate rewards (rewards distributed during advanceEpoch)
        advanceEpoch();

        // delegator1 delegates again — creates pendingStake
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);

        // Try to compound → revert
        vm.prank(delegator1);
        vm.expectRevert("Cannot compound while pending stake exist");
        staking.compoundRewards(pool1);
    }

    /// @notice exitValidator reverts when owner has pendingStake
    function test_Atomicity_ExitValidatorBlockedByPendingStake() public {
        // validator1 delegates more stake to own pool — creates pendingStake
        vm.prank(validator1);
        staking.delegate{value: MIN_VALIDATOR_STAKE}(pool1);

        // Try exitValidator → revert
        vm.prank(validator1);
        vm.expectRevert("owner has pending stake, not allowed to exit");
        staking.exitValidator(pool1);

        // After advancing epoch (pendingStake activates), exitValidator should succeed
        advanceEpoch();
        vm.prank(validator1);
        staking.exitValidator(pool1);
    }

    /// @notice withdrawStake reverts when owner has pendingStake that hasn't matured yet.
    ///         After epoch advance, settleReward inside withdrawStake activates the pending
    ///         stake automatically, so withdrawStake succeeds without manual settle.
    function test_Atomicity_WithdrawStakeBlockedByPendingStake() public {
        // validator1 delegates more stake to own pool — creates pendingStake
        vm.prank(validator1);
        staking.delegate{value: 2 ether}(pool1);

        // Try withdrawStake in same epoch → revert (pendingStake not yet matured, settleReward can't activate it)
        vm.prank(validator1);
        vm.expectRevert("owner has pending stake, not allowed to withdraw");
        staking.withdrawStake(pool1, 1 ether);

        // Advance epoch so pending can be activated by settleReward
        advanceEpoch();

        // Now withdrawStake succeeds — settleReward inside activates the matured pendingStake first
        vm.prank(validator1);
        staking.withdrawStake(pool1, 1 ether);
    }

    // =========================================================================
    // Category 2: isPendingUndelegate blocks operations
    // =========================================================================

    /// @notice delegate reverts when delegator has isPendingUndelegate=true
    function test_Atomicity_DelegateBlockedByPendingUndelegate() public {
        // delegator1 delegates to pool1, advance epoch to activate, then undelegate
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);
        advanceEpoch();

        vm.prank(delegator1);
        staking.undelegate(pool1);
        // isPendingUndelegate is now true for delegator1 on pool1

        // Try to delegate to pool1 → revert
        vm.prank(delegator1);
        vm.expectRevert("Cannot delegate while pending undelegate");
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);

        // Try to delegate to pool2 → should succeed (isPendingUndelegate is per-pool)
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool2);
    }

    /// @notice compoundRewards reverts when isPendingUndelegate=true
    function test_Atomicity_CompoundBlockedByPendingUndelegate() public {
        // validator1 adds more stake so partial withdraw is possible
        vm.prank(validator1);
        staking.delegate{value: 4 ether}(pool1);
        advanceEpoch(); // activate the additional stake

        // Advance epoch to generate commission rewards for validator1
        advanceEpoch();

        // Must settle to activate any remaining pending state before withdrawStake
        vm.prank(validator1);
        staking.settleReward(pool1);

        // validator1 does partial withdrawStake — sets isPendingUndelegate=true
        vm.prank(validator1);
        staking.withdrawStake(pool1, 1 ether);

        // Try compound → revert
        vm.prank(validator1);
        vm.expectRevert("Cannot compound while pending undelegate");
        staking.compoundRewards(pool1);
    }

    /// @notice exitValidator reverts when owner has isPendingUndelegate=true
    function test_Atomicity_ExitValidatorBlockedByPendingUndelegate() public {
        // Add more stake so partial withdraw is possible
        vm.prank(validator1);
        staking.delegate{value: 4 ether}(pool1);
        advanceEpoch();

        // Must settle to activate pending stake before withdrawStake
        // (withdrawStake checks pendingStake BEFORE settleReward)
        vm.prank(validator1);
        staking.settleReward(pool1);

        // validator1 does partial withdrawStake — sets isPendingUndelegate=true
        vm.prank(validator1);
        staking.withdrawStake(pool1, 1 ether);

        // Try exitValidator → revert (validator already has isPendingUndelegate=true from withdrawStake;
        // partial withdrawal above min does NOT add to pendingExitPoolSets, so the block comes from
        // the isPendingUndelegate guard inside exitValidator)
        vm.prank(validator1);
        vm.expectRevert("Already pending undelegate");
        staking.exitValidator(pool1);
    }

    /// @notice withdrawStake reverts when owner already has isPendingUndelegate=true
    function test_Atomicity_WithdrawStakeBlockedByPendingUndelegate() public {
        // Add more stake so partial withdraw is possible
        vm.prank(validator1);
        staking.delegate{value: 4 ether}(pool1);
        advanceEpoch();

        // Must settle to activate pending stake before withdrawStake
        vm.prank(validator1);
        staking.settleReward(pool1);

        // First partial withdraw — sets isPendingUndelegate=true
        vm.prank(validator1);
        staking.withdrawStake(pool1, 1 ether);

        // Second partial withdraw → revert
        vm.prank(validator1);
        vm.expectRevert("Already pending undelegate");
        staking.withdrawStake(pool1, 1 ether);
    }

    // =========================================================================
    // Category 3: Operations that are NOT blocked
    // =========================================================================

    /// @notice claimReward succeeds even when pendingStake > 0
    function test_Atomicity_ClaimRewardAllowedDuringPendingStake() public {
        // delegator1 delegates to pool1, advance epoch to activate
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);
        advanceEpoch();

        // Advance another epoch to generate rewards
        advanceEpoch();

        // delegator1 delegates again — creates pendingStake
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);

        // claimReward should succeed despite pendingStake > 0
        vm.prank(delegator1);
        uint256 reward = staking.claimReward(pool1);
        assertGt(reward, 0, "Should have claimed some rewards");
    }

    /// @notice settleReward succeeds even when pendingStake > 0
    function test_Atomicity_SettleRewardAllowedDuringPendingStake() public {
        // delegator1 delegates to pool1 — creates pendingStake
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);

        // settleReward should succeed (no revert)
        vm.prank(delegator1);
        staking.settleReward(pool1);
    }

    /// @notice claimStake works normally (requires isPendingUndelegate=true)
    function test_Atomicity_ClaimStakeAllowedDuringPendingUndelegate() public {
        // delegator1 delegates, advance, undelegate
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);
        advanceEpoch();

        vm.prank(delegator1);
        staking.undelegate(pool1);

        // Advance past unlock window (delegation_withdraw_effective_epoch = 2)
        advanceEpoch();
        advanceEpoch();

        // claimStake should succeed
        vm.prank(delegator1);
        staking.claimStake(pool1);
    }

    // =========================================================================
    // Category 4: State recovery after claim
    // =========================================================================

    /// @notice After claimStake, isPendingUndelegate is cleared and delegate works again
    function test_Atomicity_DelegateAllowedAfterClaimStake() public {
        // delegator1 delegates, advance, undelegate
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);
        advanceEpoch();

        vm.prank(delegator1);
        staking.undelegate(pool1);

        // Advance past unlock window (delegation_withdraw_effective_epoch = 2)
        advanceEpoch();
        advanceEpoch();

        // Claim stake — clears isPendingUndelegate
        vm.prank(delegator1);
        staking.claimStake(pool1);

        // Now delegate again — should succeed
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);
    }

    /// @notice After pendingStake activates (epoch advance), delegate works again
    function test_Atomicity_DelegateAllowedAfterPendingActivated() public {
        // delegator1 delegates — creates pendingStake
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);

        // Advance epoch — pendingStake activates via lazy activation in settleReward
        advanceEpoch();

        // delegator1 delegates again — should succeed (pendingStake == 0 after settleReward)
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(pool1);
    }

    /// @notice Owner delegate blocked by isPendingUndelegate after exitValidator
    function test_Atomicity_OwnerDelegateBlockedByPendingUndelegate() public {
        // validator1 exits — sets isPendingUndelegate=true for owner
        vm.prank(validator1);
        staking.exitValidator(pool1);

        // validator1 tries to delegate to own pool → revert
        vm.prank(validator1);
        vm.expectRevert("Cannot delegate while pending undelegate");
        staking.delegate{value: MIN_VALIDATOR_STAKE}(pool1);

        // Advance past unlock window (withdraw_effective_epoch = 1) and claim
        advanceEpoch();

        vm.prank(validator1);
        staking.claimStake(pool1);

        // After claiming, delegate should succeed (re-registration needed for exited validator)
        // Since the validator exited, we need to re-register to delegate
        vm.prank(validator1);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY1, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT1
        );
    }
}
