// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/staking/Staking.sol";
import "../src/staking/interfaces/IStaking.sol";
import "../src/chainConfig/ChainConfig.sol";
import "../src/ruleManager/RuleManager.sol";
import "../src/TransparentUpgradeableProxy.sol";

/**
 * @title StakingDelegateMergeTest
 * @notice Tests for the addStake → delegate() migration (commit 77bfc44c)
 *
 * Coverage:
 *   Risk 1A – Owner delegate() on pendingExit validator (enough stake → validator recovers)
 *   Risk 1B – Owner delegate() on pendingExit validator (insufficient stake → validator deactivated,
 *              but owner's funds remain recoverable via exitValidator)
 *   Risk 2  – accumulatedRewardPerShare catch-up correctness when isNewDelegator path sets it to 0
 *   Bonus   – Confirm the path that creates the Risk-1 state is reachable
 */
contract StakingDelegateMergeTest is Test {
    ChainConfig public chainConfig;
    TransparentUpgradeableProxy public chainConfigProxy;
    Staking public staking;
    TransparentUpgradeableProxy public stakingProxy;
    RuleManager public ruleManager;
    TransparentUpgradeableProxy public ruleManagerProxy;

    address public admin = address(0x1111111111111111111111111111111111111111);
    address public owner = address(0xAAA1);
    address public delegator = address(0xBBB1);

    uint256 constant MIN_STAKE = 10_000_000 ether;
    uint256 constant EPOCH_DURATION = 4 hours;

    bytes32 poolId;

    // ─── helpers ────────────────────────────────────────────────────────────

    function _advanceEpoch() internal {
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        bytes32[] memory ids = new bytes32[](1);
        uint256[] memory fees = new uint256[](1);
        ids[0] = poolId;
        fees[0] = 0;
        vm.prank(admin);
        staking.advanceEpoch(ids, fees);
    }

    function _advanceEpochWithFee(uint256 fee) internal {
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + EPOCH_DURATION);
        bytes32[] memory ids = new bytes32[](1);
        uint256[] memory fees = new uint256[](1);
        ids[0] = poolId;
        fees[0] = fee;
        vm.prank(admin);
        vm.deal(address(staking), address(staking).balance + fee);
        staking.advanceEpoch(ids, fees);
    }

    // Activate a delegator's pending stake (lazy activation requires explicit settleReward)
    function _activateDelegator(address who) internal {
        vm.prank(who);
        staking.settleReward(poolId);
    }

    // ─── setUp ──────────────────────────────────────────────────────────────

    function setUp() public {
        vm.startPrank(admin);

        chainConfig = new ChainConfig();
        ruleManager = new RuleManager();
        staking = new Staking();

        bytes memory ccData = abi.encodeWithSelector(ChainConfig.initialize.selector, admin, address(staking));
        chainConfigProxy = new TransparentUpgradeableProxy(address(chainConfig), ccData);
        chainConfig = ChainConfig(address(chainConfigProxy));

        bytes memory rmData = abi.encodeWithSelector(RuleManager.initialize.selector, admin, 1000);
        ruleManagerProxy = new TransparentUpgradeableProxy(address(ruleManager), rmData);
        ruleManager = RuleManager(address(ruleManagerProxy));

        bytes memory stData = abi.encodeWithSelector(Staking.initialize.selector, admin, address(chainConfig));
        stakingProxy = new TransparentUpgradeableProxy(address(staking), stData);
        staking = Staking(payable(address(stakingProxy)));

        chainConfig.updateStakingAddress(address(staking));
        vm.stopPrank();

        // Configure chain params
        string[] memory keys = new string[](5);
        string[] memory values = new string[](5);
        keys[0] = "staking.min_staking_pool_value";
        values[0] = vm.toString(MIN_STAKE);
        keys[1] = "staking.max_staking_pool_value";
        values[1] = vm.toString(uint256(100_000_000 ether));
        keys[2] = "staking.min_delegator_stake";
        values[2] = vm.toString(uint256(1 ether));
        keys[3] = "staking.withdraw_effective_epoch";
        values[3] = "1";
        keys[4] = "staking.delegation_withdraw_effective_epoch";
        values[4] = "1";
        vm.prank(address(staking));
        chainConfig.setConfig(keys, values);
        vm.roll(block.number + 1);

        // Register and activate validator
        vm.deal(owner, 100_000_000 ether);
        vm.deal(delegator, 100_000_000 ether);
        vm.prank(owner);
        poolId = staking.registerValidator{value: MIN_STAKE}(
            "Test Validator",
            "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f",
            "0xproof1",
            "0xblskey1",
            "0xblspop1",
            "http://test.validator"
        );
        _advanceEpoch();
        assertTrue(staking.isValidatorActive(poolId), "validator not active after setup");
    }

    // ─── Reach the Risk-1 precondition ───────────────────────────────────────
    //
    // After this helper:
    //   • validator is in pendingExitPoolSets  (triggered by delegator undelegate)
    //   • owner.isPendingUndelegate == false   (claimStake done)
    //   • owner.stake = MIN_STAKE / 2          (post partial-withdrawal claim)
    //   • totalStake  = MIN_STAKE / 2          (delegator stake gone)
    //
    function _reachPendingExitWithOwnerCanDelegate() internal {
        uint256 half = MIN_STAKE / 2;

        // Step 1: delegator joins (totalStake = MIN_STAKE + half)
        vm.prank(delegator);
        staking.delegate{value: half}(poolId);
        _advanceEpoch();
        // Lazy activation: delegator.pendingStake → .stake
        _activateDelegator(delegator);

        IStaking.Delegator memory d = staking.getDelegator(poolId, delegator);
        assertEq(d.stake, half, "delegator stake after epoch");

        // Step 2: owner does partial withdrawStake (owner.stake: MIN → half, totalStake: 15M → 10M)
        vm.prank(owner);
        staking.withdrawStake(poolId, half);

        // Partial withdrawal keeps totalStake at MIN_STAKE (not below), so pendingExit is NOT triggered.
        // Only a full exit (ownerStake == 0) or a below-min withdrawal triggers pendingExit.
        assertFalse(staking.isValidatorPendingExit(poolId), "pendingExit NOT set for above-min partial withdrawal");
        {
            IStaking.Delegator memory ownerD = staking.getDelegator(poolId, owner);
            assertTrue(ownerD.isPendingUndelegate, "isPendingUndelegate true after withdrawStake");
        }

        // Step 3: advanceEpoch — validator stays active (totalStake == MIN, pendingExit was never set)
        _advanceEpoch();
        assertFalse(staking.isValidatorPendingExit(poolId), "pendingExit still not set after advanceEpoch");
        assertTrue(staking.isValidatorActive(poolId), "validator still active");

        // Step 4: owner claims → isPendingUndelegate = false
        vm.prank(owner);
        staking.claimStake(poolId);
        {
            IStaking.Delegator memory ownerD = staking.getDelegator(poolId, owner);
            assertFalse(ownerD.isPendingUndelegate, "isPendingUndelegate false after claim");
            assertEq(ownerD.stake, half, "owner.stake = half after claim");
        }

        // Step 5: delegator undelegates → totalStake = half < MIN → pendingExitPoolSets.add
        vm.prank(delegator);
        staking.undelegate(poolId);

        assertTrue(staking.isValidatorPendingExit(poolId), "pendingExit via delegator undelegate");
        {
            IStaking.Delegator memory ownerD = staking.getDelegator(poolId, owner);
            assertFalse(ownerD.isPendingUndelegate, "owner.isPendingUndelegate still false");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Bonus: Confirm the Risk-1 precondition is reachable
    // ═══════════════════════════════════════════════════════════════════════
    function test_Risk1_PreconditionIsReachable() public {
        _reachPendingExitWithOwnerCanDelegate();

        assertTrue(staking.isValidatorPendingExit(poolId), "PRECONDITION: pendingExitPoolSets");
        IStaking.Delegator memory ownerD = staking.getDelegator(poolId, owner);
        assertFalse(ownerD.isPendingUndelegate, "PRECONDITION: owner.isPendingUndelegate == false");
        assertGt(ownerD.stake, 0, "PRECONDITION: owner has active stake");
        assertLt(ownerD.stake, MIN_STAKE, "PRECONDITION: owner.stake < MIN");

        IStaking.Validator memory v = staking.getValidator(poolId);
        assertLt(v.totalStake, MIN_STAKE, "PRECONDITION: totalStake < MIN");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Risk 1A — Owner adds ENOUGH stake; validator recovers from pendingExit
    // ═══════════════════════════════════════════════════════════════════════
    function test_Risk1A_OwnerDelegateOnPendingExit_ValidatorRecovers() public {
        _reachPendingExitWithOwnerCanDelegate();

        uint256 half = MIN_STAKE / 2;
        // Need to bring totalStake (= half) back to at least MIN
        uint256 toAdd = MIN_STAKE - half;

        // Owner delegates enough to recover
        vm.prank(owner);
        staking.delegate{value: toAdd}(poolId);

        // totalStake updated immediately in delegate()
        {
            IStaking.Validator memory v = staking.getValidator(poolId);
            assertEq(v.totalStake, MIN_STAKE, "totalStake = MIN after delegate");
        }
        // Stake is pending (not yet active)
        {
            IStaking.Delegator memory ownerD = staking.getDelegator(poolId, owner);
            assertEq(ownerD.stake, half, "owner.stake still half (not activated)");
            assertEq(ownerD.pendingStake, toAdd, "owner.pendingStake = toAdd");
        }

        // advanceEpoch: ownerHasStake = true (stake = half), totalStake = MIN → stay active
        _advanceEpoch();

        assertFalse(
            staking.isValidatorPendingExit(poolId), "pendingExit cleared after epoch (ownerHasStake, totalStake >= MIN)"
        );
        assertTrue(staking.isValidatorActive(poolId), "validator must remain active");

        // Trigger lazy activation
        _activateDelegator(owner);

        IStaking.Delegator memory ownerFinal = staking.getDelegator(poolId, owner);
        assertEq(ownerFinal.pendingStake, 0, "pendingStake activated");
        assertEq(ownerFinal.stake, MIN_STAKE, "owner.stake = half + toAdd = MIN");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Risk 1B — Owner adds INSUFFICIENT stake; validator deactivates.
    //           Verify pendingStake still activates lazily and funds are recoverable.
    // ═══════════════════════════════════════════════════════════════════════
    function test_Risk1B_OwnerDelegateOnPendingExit_ValidatorDeactivated_FundsRecoverable() public {
        _reachPendingExitWithOwnerCanDelegate();

        uint256 half = MIN_STAKE / 2;
        uint256 smallAdd = 1 ether; // totalStake stays below MIN

        vm.prank(owner);
        staking.delegate{value: smallAdd}(poolId);

        {
            IStaking.Validator memory v = staking.getValidator(poolId);
            assertLt(v.totalStake, MIN_STAKE, "totalStake still < MIN");
        }
        {
            IStaking.Delegator memory ownerD = staking.getDelegator(poolId, owner);
            assertEq(ownerD.pendingStake, smallAdd, "owner.pendingStake = smallAdd");
        }

        // advanceEpoch: totalStake < MIN → _removeFromActiveIfNeeded deactivates validator
        _advanceEpoch();

        assertFalse(staking.isValidatorPendingExit(poolId), "pendingExitPoolSets cleaned after deactivation");
        assertFalse(staking.isValidatorActive(poolId), "validator must be INACTIVE");

        // pendingStake persists (not automatically refunded)
        {
            IStaking.Delegator memory ownerD = staking.getDelegator(poolId, owner);
            assertEq(ownerD.pendingStake, smallAdd, "pendingStake persists despite validator deactivation");
        }

        // Lazy activation fires anyway (contract doesn't check validator status in _tryActivatePending)
        _activateDelegator(owner);

        {
            IStaking.Delegator memory ownerD = staking.getDelegator(poolId, owner);
            assertEq(ownerD.pendingStake, 0, "pendingStake activates even for inactive validator");
            assertEq(ownerD.stake, half + smallAdd, "owner.stake = half + smallAdd");
            assertFalse(ownerD.isPendingUndelegate, "owner.isPendingUndelegate must be false");
        }

        // Funds are fully recoverable via withdrawStake (exitValidator requires active/pendingAdd,
        // but for a deactivated validator, withdrawStake() works without that check)
        uint256 ownerStake = half + smallAdd;
        uint256 balanceBefore = owner.balance;

        vm.prank(owner);
        staking.withdrawStake(poolId, ownerStake);

        {
            IStaking.Delegator memory ownerD = staking.getDelegator(poolId, owner);
            assertTrue(ownerD.isPendingUndelegate, "isPendingUndelegate set after withdrawStake");
            assertEq(ownerD.stake, 0, "stake cleared after withdrawStake");
        }

        // Advance past unlock window, then claim
        _advanceEpoch();
        _advanceEpoch();

        vm.prank(owner);
        staking.claimStake(poolId);

        // Owner receives back their principal (half + smallAdd)
        IStaking.Delegator memory ownerClaimed = staking.getDelegator(poolId, owner);
        assertFalse(ownerClaimed.isPendingUndelegate, "fully claimed");
        assertGt(owner.balance, balanceBefore, "owner balance increased after claim (principal returned)");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Risk 2 — Catch-up reward correctness for isNewDelegator path
    //
    // When owner re-delegates after a full exit+claim (stake == 0), the new
    // delegator record has accumulatedRewardPerShare = 0.
    //
    // Invariants verified:
    //   A. catch-up rewards > 0  (activation did produce rewards)
    //   B. accumulatedRewardPerShare after activation == current contract RPS (not 0)
    //   C. rewards == (currentRPS - entryRPS) * stake / CONTRACT_PRECISION
    //      (i.e. NOT over-rewarded from pre-delegation RPS)
    // ═══════════════════════════════════════════════════════════════════════
    function test_Risk2_RewardCatchUp_CorrectAfterNewDelegatorPath() public {
        uint256 CONTRACT_PRECISION = staking.PRECISION(); // 1e27
        uint256 rewardFee = 10_000 ether;

        // Epoch 2: distribute rewards while owner's original stake is active
        _advanceEpochWithFee(rewardFee);

        uint256 rpsAfterEpoch2 = staking.accumulatedRewardPerShares(poolId);
        assertGt(rpsAfterEpoch2, 0, "RPS > 0 after reward epoch");

        // Owner fully exits (stake → 0)
        vm.prank(owner);
        staking.exitValidator(poolId);

        // Epoch 3: process exit, validator deactivates
        _advanceEpoch();
        assertFalse(staking.isValidatorActive(poolId), "validator inactive");

        vm.prank(owner);
        staking.claimStake(poolId);

        {
            IStaking.Delegator memory ownerD = staking.getDelegator(poolId, owner);
            assertEq(ownerD.stake, 0, "owner.stake = 0 after claim");
            assertFalse(ownerD.isPendingUndelegate, "isPendingUndelegate false");
        }

        // Owner re-delegates via delegate() — isNewDelegator path
        uint256 reStakeAmount = MIN_STAKE;
        vm.prank(owner);
        staking.delegate{value: reStakeAmount}(poolId);

        {
            IStaking.Delegator memory ownerD = staking.getDelegator(poolId, owner);
            assertEq(ownerD.pendingStake, reStakeAmount, "pendingStake = reStakeAmount");
            // isNewDelegator: accumulatedRewardPerShare is reset to 0
            assertEq(ownerD.accumulatedRewardPerShare, 0, "accumulatedRewardPerShare = 0 for isNewDelegator path");
        }
        assertTrue(staking.isValidatorPendingAdd(poolId), "re-added to pendingAddPoolSets");

        // Record RPS at the moment the historical entry will be saved
        // (recorded in the NEXT advanceEpoch STEP 2, AFTER rewards for that epoch but BEFORE activation)
        // → captures accumulatedRewardPerShares[poolId] at epoch transition time

        // Epoch 4: activate pending addition; historicalRPS[4] is recorded in STEP 2
        _advanceEpoch();
        assertTrue(staking.isValidatorActive(poolId), "validator re-activated");

        // Record the entry-point RPS that _activatePendingStake will use
        // This equals historicalRPS[activationEpoch][poolId].rps.
        // We can reconstruct it by capturing the contract's RPS *after* rewards in epoch 4's advanceEpoch
        // Since epoch 4 had fee = 0 and was the activation epoch, the entryRPS = RPS before epoch 5 rewards.
        uint256 rpsBeforeEpoch5 = staking.accumulatedRewardPerShares(poolId);

        // Epoch 5: distribute rewards AFTER activation — owner should catch-up from epoch-4 entry
        _advanceEpochWithFee(rewardFee);
        uint256 rpsAfterEpoch5 = staking.accumulatedRewardPerShares(poolId);
        assertGt(rpsAfterEpoch5, rpsBeforeEpoch5, "RPS increased after epoch 5 reward");

        // Capture rewards BEFORE settleReward to isolate the catch-up delta.
        // At this point, rewards already include:
        //   • commission from epoch 2→3 (added directly by rewardValidators while validator was exiting)
        //   • commission from epoch 4→5 (added directly by rewardValidators after re-activation)
        IStaking.Delegator memory ownerBeforeSettle = staking.getDelegator(poolId, owner);
        uint256 rewardsBefore = ownerBeforeSettle.rewards;

        // Trigger activation + catch-up via settleReward
        vm.prank(owner);
        staking.settleReward(poolId);

        IStaking.Delegator memory ownerFinal = staking.getDelegator(poolId, owner);
        assertEq(ownerFinal.pendingStake, 0, "pendingStake activated");
        assertEq(ownerFinal.stake, reStakeAmount, "stake = reStakeAmount");

        // Isolate the catch-up amount added by _activatePendingStake
        uint256 catchUpActual = ownerFinal.rewards - rewardsBefore;

        // ── Invariant A: catch-up rewards > 0 ──────────────────────────────
        assertGt(catchUpActual, 0, "A: catch-up reward must be positive");

        // ── Invariant B: accumulatedRewardPerShare aligned to current RPS ──
        assertEq(
            ownerFinal.accumulatedRewardPerShare,
            rpsAfterEpoch5,
            "B: accumulatedRewardPerShare must equal current RPS after activation"
        );

        // ── Invariant C: catch-up == (currentRPS - entryRPS) * stake / PRECISION ─
        // entryRPS = historicalRPS[activationEpoch].rps = rpsBeforeEpoch5
        // (rpsBeforeEpoch5 reflects RPS AFTER epoch 2→3 rewards, NOT 0,
        //  because the validator was still active during that epoch's reward distribution)
        uint256 rpsDelta = rpsAfterEpoch5 - rpsBeforeEpoch5;
        uint256 expectedCatchUp = (rpsDelta * reStakeAmount) / CONTRACT_PRECISION;

        assertEq(catchUpActual, expectedCatchUp, "C: catch-up must match (currentRPS - entryRPS) * stake / PRECISION");

        // ── Invariant C': no over-reward from using epoch-0 RPS as entry ───
        // If accumulatedRewardPerShare = 0 were used as entry (the bug scenario), reward would be:
        uint256 overReward = (rpsAfterEpoch5 * reStakeAmount) / CONTRACT_PRECISION;
        // Since rpsBeforeEpoch5 > 0, overReward > expectedCatchUp > catchUpActual
        assertLt(
            catchUpActual, overReward, "C': catch-up must be less than if entry RPS were 0 (no retroactive credit)"
        );
    }
}
