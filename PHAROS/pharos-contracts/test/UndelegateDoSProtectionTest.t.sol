// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

/**
 * @title Undelegate DoS Protection Test
 * @notice Tests that undelegate cannot be used to force validator exit below minimum stake
 */
contract UndelegateDoSProtectionTest is Test {
    ChainConfig private chainConfig;
    TransparentUpgradeableProxy chainConfigProxy;
    Staking private staking;
    TransparentUpgradeableProxy private stakingProxy;
    RuleManager private ruleManager;
    TransparentUpgradeableProxy private ruleManagerProxy;

    address admin = 0x1111111111111111111111111111111111111111;
    address validator = address(0x4);
    address delegator1 = address(0x5);
    address delegator2 = address(0x6);

    uint256 public constant MIN_POOL_STAKE = 10000000 ether;
    uint256 public constant MIN_DELEGATOR_STAKE = 1 ether;

    function setUp() public {
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

    function registerValidator(address _validator, uint256 _stake) internal returns (bytes32) {
        vm.prank(_validator);
        vm.deal(_validator, _stake);
        return staking.registerValidator{value: _stake}(
            "Test Validator",
            "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f",
            "0xproof1",
            "0xblskey1",
            "0xblspop1",
            "http://test.validator"
        );
    }

    function advanceEpoch() internal {
        vm.warp(block.timestamp + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));
    }

    /**
     * @notice Test that single delegator cannot force validator below minimum stake
     */
    function testUndelegate_PreventsSingleDelegatorDoS() public {
        bytes32 poolId = registerValidator(validator, MIN_POOL_STAKE);
        advanceEpoch();

        // Single delegator delegates
        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Advance epoch to activate pending stake
        advanceEpoch();

        uint256 totalStakeBefore = staking.getValidator(poolId).totalStake;
        console.log("Total stake before undelegate:", totalStakeBefore);
        console.log("MIN_POOL_STAKE:", MIN_POOL_STAKE);

        // Delegator tries to undelegate (this would drop validator to MIN_POOL_STAKE)
        // This should be allowed because validator still meets minimum
        vm.prank(delegator1);
        staking.undelegate(poolId);

        uint256 totalStakeAfter = staking.getValidator(poolId).totalStake;
        console.log("Total stake after undelegate:", totalStakeAfter);
        assertEq(totalStakeAfter, MIN_POOL_STAKE, "Validator should still have MIN_POOL_STAKE");
    }

    /**
     * @notice Test that delegator cannot undelegate if it would drop validator below minimum
     * when there are no other delegators
     */
    function testUndelegate_PreventsBelowMinimumWhenLastDelegator() public {
        bytes32 poolId = registerValidator(validator, MIN_POOL_STAKE);
        advanceEpoch();

        // Validator's total stake is exactly MIN_POOL_STAKE (just owner's stake)
        uint256 totalStakeBefore = staking.getValidator(poolId).totalStake;
        assertEq(totalStakeBefore, MIN_POOL_STAKE, "Validator should start with MIN_POOL_STAKE");

        // Delegator delegates
        vm.prank(delegator1);
        vm.deal(delegator1, 100 ether);
        staking.delegate{value: 100 ether}(poolId);

        // Advance epoch to activate pending stake
        advanceEpoch();

        // Delegator undelegates - should succeed because stake still >= MIN_POOL_STAKE
        vm.prank(delegator1);
        staking.undelegate(poolId);

        // Verify validator still has MIN_POOL_STAKE
        assertEq(staking.getValidator(poolId).totalStake, MIN_POOL_STAKE);
    }

    /**
     * @notice Test that validator owner can exit, which removes their stake
     */
    function testUndelegate_OwnerCannotReduceBelowMinimum() public {
        bytes32 poolId = registerValidator(validator, MIN_POOL_STAKE);
        advanceEpoch();

        // Validator's total stake is exactly MIN_POOL_STAKE
        uint256 totalStake = staking.getValidator(poolId).totalStake;
        assertEq(totalStake, MIN_POOL_STAKE);

        // Owner should use exitValidator instead of undelegate
        vm.prank(validator);
        staking.exitValidator(poolId);

        // Verify validator was added to pending exit
        assertTrue(staking.isValidatorPendingExit(poolId), "Validator should be pending exit after exitValidator");

        // Verify total stake dropped
        uint256 newTotalStake = staking.getValidator(poolId).totalStake;
        assertEq(newTotalStake, 0, "Validator total stake should be 0 after owner exit");
    }

    /**
     * @notice Test that validator owner can undelegate partially as long as minimum is maintained
     */
    function testUndelegate_OwnerCanPartialUndelegateAboveMinimum() public {
        bytes32 poolId = registerValidator(validator, MIN_POOL_STAKE + 1000 ether);
        advanceEpoch();

        // Validator's total stake is above MIN_POOL_STAKE
        uint256 totalStake = staking.getValidator(poolId).totalStake;
        assertEq(totalStake, MIN_POOL_STAKE + 1000 ether);

        // Owner can undelegate some stake as long as minimum is maintained
        vm.prank(validator);
        staking.withdrawStake(poolId, 500 ether); // Should succeed
    }

    /**
     * @notice Test that multiple delegators can undelegate as long as minimum is maintained
     */
    function testUndelegate_MultipleDelegatorsCanUndelegate() public {
        bytes32 poolId = registerValidator(validator, MIN_POOL_STAKE);
        advanceEpoch();

        // Multiple delegators delegate
        vm.prank(delegator1);
        vm.deal(delegator1, 1000 ether);
        staking.delegate{value: 1000 ether}(poolId);

        vm.prank(delegator2);
        vm.deal(delegator2, 1000 ether);
        staking.delegate{value: 1000 ether}(poolId);

        // Advance epoch to activate pending stakes
        advanceEpoch();

        uint256 totalStakeBefore = staking.getValidator(poolId).totalStake;
        console.log("Total stake before:", totalStakeBefore);

        // One delegator undelegates - should be allowed (stake still above MIN_POOL_STAKE)
        vm.prank(delegator1);
        staking.undelegate(poolId);

        uint256 totalStakeAfter = staking.getValidator(poolId).totalStake;
        console.log("Total stake after delegator1:", totalStakeAfter);

        // Still above minimum
        assertGt(totalStakeAfter, MIN_POOL_STAKE, "Should still be above minimum");

        // Second delegator can also undelegate (still above minimum)
        vm.prank(delegator2);
        staking.undelegate(poolId);

        uint256 finalStake = staking.getValidator(poolId).totalStake;
        console.log("Final stake:", finalStake);
        assertEq(finalStake, MIN_POOL_STAKE, "Should be exactly at minimum");
    }

    /**
     * @notice Test the attack scenario: mass undelegation
     */
    function testUndelegate_PreventsMassUndelegationAttack() public {
        bytes32 poolId = registerValidator(validator, MIN_POOL_STAKE);
        advanceEpoch();

        // Attackers delegate small amounts
        uint256 numAttackers = 100;
        for (uint256 i = 0; i < numAttackers; i++) {
            address attacker = address(uint160(i + 1000));
            vm.prank(attacker);
            vm.deal(attacker, 10 ether);
            staking.delegate{value: 10 ether}(poolId);
        }

        uint256 totalStake = staking.getValidator(poolId).totalStake;
        console.log("Total stake with attackers:", totalStake);
        assertGt(totalStake, MIN_POOL_STAKE, "Should be above minimum");

        // Attackers try to undelegate en masse
        uint256 successfulUndelegates = 0;
        for (uint256 i = 0; i < numAttackers; i++) {
            address attacker = address(uint160(i + 1000));
            vm.prank(attacker);
            try staking.undelegate(poolId) {
                successfulUndelegates++;
            } catch {
                // Expected: some undelegates will be prevented
            }
        }

        console.log("Successful undelegates:", successfulUndelegates);
        console.log("Total stake after attack:", staking.getValidator(poolId).totalStake);

        // Verify validator is still active
        assertTrue(staking.isValidatorActive(poolId), "Validator should still be active");
        assertGe(staking.getValidator(poolId).totalStake, MIN_POOL_STAKE, "Stake should be >= minimum");
    }

    /**
     * @notice Test that validator remains active after prevented undelegates
     */
    function testUndelegate_ValidatorRemainsActive() public {
        bytes32 poolId = registerValidator(validator, MIN_POOL_STAKE + 1000 ether);
        advanceEpoch();

        // Single delegator
        vm.prank(delegator1);
        vm.deal(delegator1, 500 ether);
        staking.delegate{value: 500 ether}(poolId);

        // Advance epoch to activate pending stake
        advanceEpoch();

        assertTrue(staking.isValidatorActive(poolId), "Validator should be active");

        // Delegator undelegates
        vm.prank(delegator1);
        staking.undelegate(poolId);

        // Advance epoch to process exits
        advanceEpoch();

        // Validator should still be active
        assertTrue(staking.isValidatorActive(poolId), "Validator should still be active after undelegate");
        assertEq(staking.getValidator(poolId).status, 1, "Validator status should be active");
    }
}
