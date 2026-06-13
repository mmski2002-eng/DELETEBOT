// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

/**
 * @title StakingSwapAndPopVulnTest
 * @notice Tests for C-01: _processDelegatorWithdrawals swap-and-pop stale index vulnerability
 */
contract StakingSwapAndPopVulnTest is Test {
    ChainConfig private chainConfig;
    TransparentUpgradeableProxy chainConfigProxy;
    Staking private staking;
    TransparentUpgradeableProxy private stakingProxy;
    RuleManager private ruleManager;
    TransparentUpgradeableProxy private ruleManagerProxy;

    address admin = address(0x1111111111111111111111111111111111111111);

    address public validatorV1 = address(0x1001);
    address public validatorV2 = address(0x1002);

    address public delegatorD = address(0x2001); // attacker
    address public delegatorE = address(0x2002); // victim

    string public constant PUB_KEY_V1 = "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f";
    string public constant PUB_KEY_V2 = "0x04b34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5a";
    string public constant PUBLIC_KEY_POP = "0xproof1";
    string public constant BLS_PUBLIC_KEY = "0xblskey1";
    string public constant BLS_PUBLIC_KEY_POP = "0xblspop1";
    string public constant ENDPOINT = "http://test.validator";
    string public constant DESCRIPTION = "Test Validator";

    uint256 public constant MIN_VALIDATOR_STAKE = 1 ether;
    uint256 public constant MAX_POOL_STAKE = 10000000 ether;
    uint256 public constant MIN_DELEGATOR_STAKE = 1 ether;

    bytes32 poolIdV1;
    bytes32 poolIdV2;

    function setUp() public {
        vm.startPrank(admin);
        chainConfig = new ChainConfig();
        ruleManager = new RuleManager();
        staking = new Staking();

        bytes memory chainConfigInitData =
            abi.encodeWithSelector(ChainConfig.initialize.selector, admin, address(staking));
        chainConfigProxy = new TransparentUpgradeableProxy(address(chainConfig), chainConfigInitData);
        chainConfig = ChainConfig(address(chainConfigProxy));

        bytes memory ruleManagerInitData = abi.encodeWithSelector(RuleManager.initialize.selector, admin, 1000);
        ruleManagerProxy = new TransparentUpgradeableProxy(address(ruleManager), ruleManagerInitData);
        ruleManager = RuleManager(address(ruleManagerProxy));

        bytes memory stakingInitData = abi.encodeWithSelector(Staking.initialize.selector, admin, address(chainConfig));
        stakingProxy = new TransparentUpgradeableProxy(address(staking), stakingInitData);
        staking = Staking(payable(address(stakingProxy)));

        chainConfig.updateStakingAddress(address(staking));
        vm.stopPrank();

        string[] memory keys = new string[](6);
        string[] memory values = new string[](6);
        keys[0] = "staking.min_staking_pool_value";
        values[0] = vm.toString(MIN_VALIDATOR_STAKE);
        keys[1] = "staking.max_staking_pool_value";
        values[1] = vm.toString(MAX_POOL_STAKE);
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
        vm.roll(block.number + 1);
    }

    function advanceEpoch() public {
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + 4 hours + 1);
        vm.prank(admin);
        staking.advanceEpoch();
    }

    function registerAndActivateValidator(address owner, string memory pubKey, uint256 stake)
        internal
        returns (bytes32)
    {
        vm.deal(owner, stake);
        vm.prank(owner);
        bytes32 poolId = staking.registerValidator{value: stake}(
            DESCRIPTION, pubKey, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT
        );
        advanceEpoch();
        return poolId;
    }

    /// @notice settleReward to activate pendingStake, then undelegate
    function settleAndUndelegate(address user, bytes32 poolId) internal {
        vm.prank(user);
        staking.settleReward(poolId);
        vm.prank(user);
        staking.undelegate(poolId);
    }

    // =========================================================================
    //  Test 1 (Audit's original scenario):
    //  Same delegator D has two undelegations (P1, P2).
    //  Swap-and-pop after claiming one creates duplicate index to same slot.
    //  Verify "processed" flag prevents double-claim in single call.
    // =========================================================================
    function testAuditOriginal_ProcessedFlagPreventsDoubleClaim() public {
        poolIdV1 = registerAndActivateValidator(validatorV1, PUB_KEY_V1, MIN_VALIDATOR_STAKE);
        poolIdV2 = registerAndActivateValidator(validatorV2, PUB_KEY_V2, MIN_VALIDATOR_STAKE);

        vm.deal(delegatorD, 10 ether);
        vm.prank(delegatorD);
        staking.delegate{value: 2 ether}(poolIdV1);
        vm.prank(delegatorD);
        staking.delegate{value: 2 ether}(poolIdV2);
        advanceEpoch(); // activate

        settleAndUndelegate(delegatorD, poolIdV1); // index 0
        settleAndUndelegate(delegatorD, poolIdV2); // index 1

        uint256 dIdx0 = staking.userUndelegationIndices(delegatorD, 0);
        uint256 dIdx1 = staking.userUndelegationIndices(delegatorD, 1);
        console.log("D.userIndices = [%d, %d]", dIdx0, dIdx1);

        advanceEpoch(); // unlock

        // D claims P1 only (A processed, B still pending)
        vm.prank(delegatorD);
        staking.claimStake(poolIdV1);
        (,,,,, bool aProc,,) = staking.pendingUndelegations(dIdx0);
        assertTrue(aProc, "A should be processed");

        // swap-and-pop: B moves to A's slot, both D.userIndices point to same slot
        advanceEpoch();

        // D claims P2 - should succeed exactly once
        uint256 balBefore = delegatorD.balance;
        vm.prank(delegatorD);
        staking.claimStake(poolIdV2);
        assertGt(delegatorD.balance - balBefore, 0, "D should claim P2");

        // No double-claim possible (processed flag)
        vm.prank(delegatorD);
        vm.expectRevert("No withdrawable stake");
        staking.claimStake(poolIdV2);

        console.log("PASS: processed flag prevents same-delegator double-claim");
    }

    // =========================================================================
    //  Test 2 (Fix verification: stale index is cleaned up via SENTINEL):
    //  D and E both undelegate in the same epoch. After D claims D-P2 (global idx 1),
    //  _processDelegatorWithdrawals must:
    //    (a) set D.userIndices[1] = type(uint256).max (SENTINEL — invalidated)
    //    (b) update E.userIndices[0] from 2 → 1 (E's entry moved by swap-and-pop)
    //  Then E can still claim their funds.
    // =========================================================================
    function testStaleIndex_IsCleanedUpBySentinel() public {
        poolIdV1 = registerAndActivateValidator(validatorV1, PUB_KEY_V1, MIN_VALIDATOR_STAKE);
        poolIdV2 = registerAndActivateValidator(validatorV2, PUB_KEY_V2, MIN_VALIDATOR_STAKE);

        // D and E both delegate, activated in same epoch
        vm.deal(delegatorD, 10 ether);
        vm.deal(delegatorE, 10 ether);
        vm.prank(delegatorD);
        staking.delegate{value: 2 ether}(poolIdV1);
        vm.prank(delegatorD);
        staking.delegate{value: 2 ether}(poolIdV2);
        vm.prank(delegatorE);
        staking.delegate{value: 2 ether}(poolIdV2);
        advanceEpoch(); // activate all

        // All three undelegate in same epoch:
        // pendingUndelegations: [D-P1(0), D-P2(1), E-P2(2)]
        settleAndUndelegate(delegatorD, poolIdV1);
        settleAndUndelegate(delegatorD, poolIdV2);
        settleAndUndelegate(delegatorE, poolIdV2);

        uint256 dGlobalIdx0 = staking.userUndelegationIndices(delegatorD, 0);
        uint256 dGlobalIdx1 = staking.userUndelegationIndices(delegatorD, 1);
        uint256 eGlobalIdx = staking.userUndelegationIndices(delegatorE, 0);
        assertEq(dGlobalIdx0, 0, "D-P1 at global slot 0");
        assertEq(dGlobalIdx1, 1, "D-P2 at global slot 1");
        assertEq(eGlobalIdx, 2, "E-P2 at global slot 2");

        advanceEpoch(); // unlock

        // D claims P2 only (P1 unclaimed → head stays 0)
        vm.prank(delegatorD);
        staking.claimStake(poolIdV2);
        assertEq(staking.userUndelegationHead(delegatorD), 0, "Head should be 0");

        // Verify D-P2 (slot 1) is marked processed; E-P2 (slot 2) is still pending
        (address d1Who,,,,, bool d1Proc,,) = staking.pendingUndelegations(dGlobalIdx1);
        assertEq(d1Who, delegatorD, "Slot 1 is D");
        assertTrue(d1Proc, "D's P2 entry is processed");
        (address eWho,,,,, bool eProc,,) = staking.pendingUndelegations(eGlobalIdx);
        assertEq(eWho, delegatorE, "Slot 2 is E");
        assertFalse(eProc, "E's entry NOT processed yet");

        // advanceEpoch triggers _processDelegatorWithdrawals:
        //   swap-and-pop removes D-P2(idx=1, processed):
        //     → D.userIndices[1] set to type(uint256).max (SENTINEL)
        //     → E-P2 moved from slot 2 → slot 1; E.userIndices[0] updated to 1
        advanceEpoch();

        console.log("=== After swap-and-pop (fix verification) ===");
        assertEq(staking.getPendingUndelegationCount(), 2, "One processed entry removed");

        // (a) D's stale index must be SENTINEL (not pointing to any real entry)
        uint256 dIdx1AfterCleanup = staking.userUndelegationIndices(delegatorD, 1);
        assertEq(dIdx1AfterCleanup, type(uint256).max, "FIX: D's processed index set to SENTINEL");

        // (b) E's index must be updated to 1 (where E's entry now lives after swap)
        uint256 eIdxAfterSwap = staking.userUndelegationIndices(delegatorE, 0);
        assertEq(eIdxAfterSwap, 1, "FIX: E's index updated to new position after swap");

        // Verify the entry at slot 1 is now E's (not D's)
        (address slotOwner,,,,, bool slotProc,,) = staking.pendingUndelegations(1);
        assertEq(slotOwner, delegatorE, "FIX: slot 1 now contains E's entry");
        assertFalse(slotProc, "FIX: E's entry is still unprocessed");

        // E can successfully claim their funds (exploit is prevented)
        uint256 eBalBefore = delegatorE.balance;
        vm.prank(delegatorE);
        staking.claimStake(poolIdV2);
        assertGt(delegatorE.balance - eBalBefore, 0, "FIX: E can claim their funds");

        console.log("PASS: stale index cleaned to SENTINEL, E's index updated, E can claim");
    }

    // =========================================================================
    //  Test 3 (Fix verification: cross-user exploit is prevented):
    //  D attempts to exploit the stale index to claim E's undelegation funds.
    //  The fix (delegator ownership check in claimStake) must:
    //    (a) prevent D from marking E's entry as processed
    //    (b) allow E to claim their own funds normally
    // =========================================================================
    function testCrossUserExploit_IsPrevented() public {
        poolIdV1 = registerAndActivateValidator(validatorV1, PUB_KEY_V1, MIN_VALIDATOR_STAKE);
        poolIdV2 = registerAndActivateValidator(validatorV2, PUB_KEY_V2, MIN_VALIDATOR_STAKE);

        // Phase 1: Same setup as the original exploit scenario
        vm.deal(delegatorD, 20 ether);
        vm.deal(delegatorE, 10 ether);
        vm.prank(delegatorD);
        staking.delegate{value: 2 ether}(poolIdV1);
        vm.prank(delegatorD);
        staking.delegate{value: 2 ether}(poolIdV2);
        vm.prank(delegatorE);
        staking.delegate{value: 2 ether}(poolIdV2);
        advanceEpoch(); // activate all

        settleAndUndelegate(delegatorD, poolIdV1); // global idx 0
        settleAndUndelegate(delegatorD, poolIdV2); // global idx 1
        settleAndUndelegate(delegatorE, poolIdV2); // global idx 2

        uint256 dGlobalIdx1Before = staking.userUndelegationIndices(delegatorD, 1);
        assertEq(dGlobalIdx1Before, 1, "D-P2 initially at slot 1");

        advanceEpoch(); // unlock

        // D claims P2 only (head stays 0, D-P2 at slot 1 marked processed)
        vm.prank(delegatorD);
        staking.claimStake(poolIdV2);

        // advanceEpoch triggers cleanup: D-P2(slot 1) removed via swap-and-pop,
        // E-P2 moves from slot 2 → slot 1; D.userIndices[1] set to SENTINEL
        advanceEpoch();

        // Verify D's index[1] is SENTINEL (stale index cleaned)
        uint256 dIdx1Sentinel = staking.userUndelegationIndices(delegatorD, 1);
        assertEq(dIdx1Sentinel, type(uint256).max, "FIX: D's stale index = SENTINEL after cleanup");

        // E's entry is now at slot 1
        (address slotOwner,, uint256 eAmount,,,,,) = staking.pendingUndelegations(1);
        assertEq(slotOwner, delegatorE, "E's entry moved to slot 1");

        // Phase 2: D re-enters pool and undelegates (to get isPendingUndelegate=true)
        vm.prank(delegatorD);
        staking.delegate{value: 5 ether}(poolIdV2);
        advanceEpoch(); // activate
        settleAndUndelegate(delegatorD, poolIdV2);

        IStaking.Delegator memory dInfo = staking.getDelegator(poolIdV2, delegatorD);
        assertTrue(dInfo.isPendingUndelegate, "D has pending undelegate");
        uint256 dPending = dInfo.pendingWithdrawStake;
        assertTrue(dPending > eAmount, "D's pending > E's amount (precondition)");

        advanceEpoch(); // unlock D's new undelegation

        // Phase 3: D tries to claim — the delegator ownership check (pending.delegator != msg.sender)
        // must skip E's entry (SENTINEL index) and only process D's own entry
        uint256 dBalBefore = delegatorD.balance;
        vm.prank(delegatorD);
        staking.claimStake(poolIdV2);
        uint256 dReceived = delegatorD.balance - dBalBefore;

        // D only received their own stake (5 ether), not E's 2 ether
        assertEq(dReceived, 5 ether, "FIX: D claims only their own stake");

        // E's entry must NOT have been processed by D
        (,,,,, bool eNowProc,,) = staking.pendingUndelegations(1);
        assertFalse(eNowProc, "FIX: E's entry is NOT processed by D");

        // E can still claim their own funds
        advanceEpoch(); // ensure E's unlock epoch reached
        uint256 eBalBefore = delegatorE.balance;
        vm.prank(delegatorE);
        staking.claimStake(poolIdV2);
        assertGt(delegatorE.balance - eBalBefore, 0, "FIX: E can claim their own funds");

        console.log("PASS: cross-user exploit prevented, E recovered %d wei", eAmount);
        console.log("D received only their own %d wei stake, not E's funds", dReceived);
    }
}
