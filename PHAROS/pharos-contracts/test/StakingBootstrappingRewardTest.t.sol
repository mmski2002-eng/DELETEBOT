// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

/**
 * @title StakingBootstrappingRewardTest
 * @notice Tests for reward distribution and activation flow in the bootstrapping model.
 *
 * Strategy:
 * - Two-tier stake model: MIN_REGISTRATION_STAKE (10 ETH) < MIN_VALIDATOR_STAKE (100 ETH)
 * - epoch_duration = 1 second (1000 ms) so inflation per epoch is tiny (~2.9 ETH)
 * - PRIORITY_FEE = 10_000 ETH dominates inflation by ~3500x, making rewards nearly
 *   pure fee-based and assertions with 2% tolerance are accurate
 * - All "direct validator" tests use MIN_VALIDATOR_STAKE in one step
 * - All "delegation scenario" tests use MIN_REGISTRATION_STAKE + delegate to activate
 */
contract StakingBootstrappingRewardTest is Test {
    ChainConfig private chainConfig;
    TransparentUpgradeableProxy chainConfigProxy;
    Staking private staking;
    TransparentUpgradeableProxy private stakingProxy;
    RuleManager private ruleManager;
    TransparentUpgradeableProxy private ruleManagerProxy;

    address admin = address(0x1111111111111111111111111111111111111111);

    address public validatorOwner = address(0xA100);
    address public validatorOwner2 = address(0xA200);
    address public delegator1 = address(0xB100);
    address public delegator2 = address(0xB200);
    address public delegator3 = address(0xB300);

    string public constant DESCRIPTION = "Reward Test Validator";
    string public constant PUBLIC_KEY = "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f";
    string public constant PUBLIC_KEY2 = "0x04b34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5a";
    string public constant PUBLIC_KEY_POP = "0xpop1";
    string public constant BLS_KEY = "0xbls1";
    string public constant BLS_KEY_POP = "0xblspop1";
    string public constant ENDPOINT = "http://validator.test";

    uint256 public constant MIN_REGISTRATION_STAKE = 10 ether; // partial registration threshold
    uint256 public constant MIN_VALIDATOR_STAKE = 100 ether; // activation threshold
    uint256 public constant MIN_DELEGATOR_STAKE = 1 ether;
    uint256 public constant MAX_VALIDATOR_STAKE = 10_000_000 ether;
    uint256 public constant COMMISSION_SCALE = 10000;
    uint256 public constant PRECISION = 1e27;
    uint256 public constant DEFAULT_COMMISSION = 1000; // 10%

    // Large fee to dominate inflation (~3500x larger than per-epoch inflation with epoch_duration=1000ms)
    uint256 public constant PRIORITY_FEE = 10_000 ether;

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

        // epoch_duration = 1000 ms (1 second): minimises inflation per epoch (~2.9 ETH vs 10000 ETH fee)
        string[] memory keys = new string[](7);
        string[] memory values = new string[](7);
        keys[0] = "staking.min_staking_pool_value";
        values[0] = vm.toString(MIN_VALIDATOR_STAKE);
        keys[1] = "staking.max_staking_pool_value";
        values[1] = vm.toString(MAX_VALIDATOR_STAKE);
        keys[2] = "staking.min_delegator_stake";
        values[2] = vm.toString(MIN_DELEGATOR_STAKE);
        keys[3] = "staking.withdraw_effective_epoch";
        values[3] = "1";
        keys[4] = "staking.min_staking_registration_value";
        values[4] = vm.toString(MIN_REGISTRATION_STAKE);
        keys[5] = "chain.epoch_duration";
        values[5] = "1000"; // 1 second in ms
        keys[6] = "staking.delegation_withdraw_effective_epoch";
        values[6] = "1";

        vm.prank(address(staking));
        chainConfig.setConfig(keys, values);
        vm.roll(block.number + 1);
    }

    // ==================== Helpers ====================

    /// @dev Advance epoch AND distribute a priority fee for the given pool.
    ///      Ensures the staking contract has enough ETH for any future principal transfers.
    function _advanceEpochWithFee(bytes32 poolId, uint256 fee) internal {
        vm.warp(block.timestamp + 2); // > 1 second epoch duration
        vm.roll(block.number + 1); // Advance block number to keep config effective
        vm.prank(admin);
        bytes32[] memory poolIds = new bytes32[](1);
        uint256[] memory fees = new uint256[](1);
        poolIds[0] = poolId;
        fees[0] = fee;
        staking.advanceEpoch(poolIds, fees);
    }

    function _advanceEpoch() internal {
        vm.warp(block.timestamp + 2);
        vm.roll(block.number + 1); // Advance block number to keep config effective
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));
    }

    function _poolId(string memory pubKey) internal pure returns (bytes32) {
        bytes memory strBytes = bytes(pubKey);
        uint256 offset = (strBytes.length >= 2 && strBytes[0] == "0" && strBytes[1] == "x") ? 2 : 0;
        bytes memory pk = new bytes((strBytes.length - offset) / 2);
        for (uint256 i = 0; i < pk.length; i++) {
            pk[i] = bytes1(_hexChar(strBytes[offset + 2 * i]) * 16 + _hexChar(strBytes[offset + 2 * i + 1]));
        }
        return bytes32(sha256(abi.encodePacked(pk)));
    }

    function _hexChar(bytes1 c) internal pure returns (uint8) {
        uint8 code = uint8(c);
        if (code >= 48 && code <= 57) return code - 48;
        if (code >= 97 && code <= 102) return code - 87;
        if (code >= 65 && code <= 70) return code - 55;
        revert("bad hex");
    }

    // ==================== Group 1: Activation Flow ====================

    /**
     * @notice Full bootstrapping activation flow:
     *         Owner registers partial stake -> delegator pushes to threshold -> pendingAdd -> active
     */
    function test_ActivationFlow_BootstrappingToActive() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        // 1. Register with partial stake (bootstrapping — below activation threshold)
        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        assertTrue(staking.isValidatorPendingAdd(poolId), "should be in pendingAdd (bootstrapping state)");
        assertTrue(staking.isValidatorBootstrapping(poolId), "should be in bootstrapping state (below threshold)");
        assertFalse(staking.isValidatorActive(poolId), "should NOT be active");
        assertEq(staking.getValidator(poolId).totalStake, MIN_REGISTRATION_STAKE);

        // 2. Delegator adds stake to reach activation threshold exactly
        uint256 remaining = MIN_VALIDATOR_STAKE - MIN_REGISTRATION_STAKE; // 90 ether
        vm.deal(delegator1, remaining);
        vm.prank(delegator1);
        staking.delegate{value: remaining}(poolId);

        assertTrue(staking.isValidatorPendingAdd(poolId), "should enter pendingAdd once threshold met");
        assertFalse(staking.isValidatorActive(poolId), "should NOT be active yet");

        // 3. advanceEpoch activates the validator
        _advanceEpoch();

        assertTrue(staking.isValidatorActive(poolId), "should be active after epoch");
        assertFalse(staking.isValidatorPendingAdd(poolId), "should leave pendingAdd");
        assertEq(staking.getValidator(poolId).status, 1, "status = 1 (active)");
    }

    /**
     * @notice Direct registration with full stake bypasses bootstrapping (one-step activation).
     */
    function test_ActivationFlow_DirectRegistrationOneStep() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        vm.deal(validatorOwner, MIN_VALIDATOR_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        assertTrue(staking.isValidatorPendingAdd(poolId), "full-stake registration: in pendingAdd");
        _advanceEpoch();
        assertTrue(staking.isValidatorActive(poolId), "should be active after epoch");
    }

    /**
     * @notice Multiple delegators contribute during bootstrapping.
     *         All pending stakes activate correctly when the validator activates.
     */
    function test_ActivationFlow_MultipleBootstrappingDelegators() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE); // 10 ether
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        // D1 adds 40 ether (still below threshold: 10+40 = 50 < 100)
        vm.deal(delegator1, 40 ether);
        vm.prank(delegator1);
        staking.delegate{value: 40 ether}(poolId);
        assertTrue(staking.isValidatorBootstrapping(poolId), "still below threshold, bootstrapping");

        // D2 adds 50 ether: total = 10+40+50 = 100 = threshold
        vm.deal(delegator2, 50 ether);
        vm.prank(delegator2);
        staking.delegate{value: 50 ether}(poolId);
        assertTrue(staking.isValidatorPendingAdd(poolId), "threshold reached: in pendingAdd");

        _advanceEpoch();
        assertTrue(staking.isValidatorActive(poolId), "should be active");

        // Trigger lazy activation for both delegators
        vm.prank(delegator1);
        staking.settleReward(poolId);
        vm.prank(delegator2);
        staking.settleReward(poolId);

        assertEq(staking.getDelegator(poolId, delegator1).stake, 40 ether, "d1 activated");
        assertEq(staking.getDelegator(poolId, delegator2).stake, 50 ether, "d2 activated");

        // Owner's stake was set directly in registerValidator (not pending)
        assertEq(staking.getDelegator(poolId, validatorOwner).stake, MIN_REGISTRATION_STAKE, "owner active");
    }

    // ==================== Group 2: Reward Distribution ====================

    /**
     * @notice Reward distribution proportionality with bootstrapping flow.
     *         Commission = 10% (default). Owner stake = 10 ETH, D1 stake = 90 ETH, total = 100 ETH.
     *
     * Expected (fee only, ignoring ~0.03% inflation):
     *   commission  = 10% * fee = 0.1 * fee     (to owner)
     *   delPool     = 90% * fee = 0.9 * fee
     *   ownerDel    = (10/100) * delPool = 0.09 * fee
     *   ownerTotal  = 0.10 + 0.09 = 0.19 * fee
     *   d1Reward    = (90/100) * delPool = 0.81 * fee
     */
    function test_Reward_BootstrappingValidatorPriorityFee() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE); // 10 ether
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        uint256 d1Stake = MIN_VALIDATOR_STAKE - MIN_REGISTRATION_STAKE; // 90 ether
        vm.deal(delegator1, d1Stake);
        vm.prank(delegator1);
        staking.delegate{value: d1Stake}(poolId);

        _advanceEpoch(); // activate

        vm.prank(delegator1); // activate d1 pending stake
        staking.settleReward(poolId);

        // Distribute fee
        _advanceEpochWithFee(poolId, PRIORITY_FEE);

        vm.prank(validatorOwner);
        staking.settleReward(poolId);
        vm.prank(delegator1);
        staking.settleReward(poolId);

        uint256 ownerRewards = staking.getDelegator(poolId, validatorOwner).rewards;
        uint256 d1Rewards = staking.getDelegator(poolId, delegator1).rewards;
        uint256 totalDistributed = ownerRewards + d1Rewards;

        // Conservation: sum equals fee (plus tiny inflation, within 2%)
        assertApproxEqRel(
            totalDistributed, PRIORITY_FEE, 0.02e18, "total rewards should approximately equal priority fee"
        );

        // Proportionality: owner gets ~19%, d1 gets ~81% of total
        // Use integer ratio to avoid floating point: ownerRewards * 100 / total ~= 19
        uint256 ownerPct = (ownerRewards * 100) / totalDistributed;
        assertApproxEqAbs(ownerPct, 19, 2, "owner should receive ~19% of total reward");
    }

    /**
     * @notice Delegator who staked BEFORE activation gets catch-up rewards from the activation epoch.
     *         Delegator who staked AFTER activation only earns from their own entry.
     */
    function test_Reward_CatchUpForBootstrappingDelegator() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        // D1 delegates to reach threshold (enters pending at epoch 0, activates at epoch 1)
        uint256 d1Stake = MIN_VALIDATOR_STAKE - MIN_REGISTRATION_STAKE; // 90 ether
        vm.deal(delegator1, d1Stake);
        vm.prank(delegator1);
        staking.delegate{value: d1Stake}(poolId);

        // Epoch 1: validator activates. rewardValidators runs but validator was pendingAdd (not active),
        // so no fee is distributed here. Snapshot after: 100 ETH.
        _advanceEpochWithFee(poolId, PRIORITY_FEE);

        // D1 activates (catch-up = 0: no rewards were earned before this activation epoch)
        vm.prank(delegator1);
        staking.settleReward(poolId);

        // D2 now delegates to the ACTIVE validator (pending at epoch 1, activates at epoch 2)
        vm.deal(delegator2, 50 ether);
        vm.prank(delegator2);
        staking.delegate{value: 50 ether}(poolId);

        // Epoch 2: first real fee epoch. Snapshot = 100 ETH (D2 pending, not in snapshot yet).
        // Owner and D1 earn. D2's stake enters the snapshot for epoch 3.
        _advanceEpochWithFee(poolId, PRIORITY_FEE);
        vm.prank(delegator2); // D2 activates; catch-up = 0
        staking.settleReward(poolId);

        // Epoch 3: second real fee epoch. Snapshot = 150 ETH (D2 now included).
        // All three earn proportional rewards.
        _advanceEpochWithFee(poolId, PRIORITY_FEE);

        vm.prank(delegator2); // D2 earns epoch 3 rewards
        staking.settleReward(poolId);
        vm.prank(validatorOwner);
        staking.settleReward(poolId);
        vm.prank(delegator1);
        staking.settleReward(poolId);

        uint256 ownerRewards = staking.getDelegator(poolId, validatorOwner).rewards;
        uint256 d1Rewards = staking.getDelegator(poolId, delegator1).rewards;
        uint256 d2Rewards = staking.getDelegator(poolId, delegator2).rewards;

        // D1 was active for epoch 2 AND epoch 3 (two real fee epochs, snapshot 100 + 150 ETH).
        // D2 only earns epoch 3 (first epoch where D2 is in the 150 ETH snapshot).
        // Since d1Stake (90 ETH) > d2Stake (50 ETH), D1 always earns more per epoch:
        assertTrue(d1Rewards > d2Rewards, "d1 (active since epoch 2) should have more than d2 (epoch 3 only)");
        assertTrue(d2Rewards > 0, "d2 earns in epoch 3 (first epoch where D2 is in the snapshot)");
        assertTrue(ownerRewards > 0, "owner should have rewards");

        // Total rewards ≈ 2 * PRIORITY_FEE (epoch 2 and epoch 3 each distribute one fee)
        uint256 total = ownerRewards + d1Rewards + d2Rewards;
        assertApproxEqRel(total, 2 * PRIORITY_FEE, 0.02e18, "total ~= 2 fee epochs");
    }

    /**
     * @notice Three delegators with equal stake activating at different epochs.
     *         Earlier activation => more accumulated rewards (proportional to active epochs).
     *
     * Epoch timing:
     *   Epoch 1: validator activates (no fee, snapshot 100 ETH)
     *   Epoch 2: fee, snapshot 100 ETH (D1 pending)  → D1 activates after
     *   Epoch 3: fee, snapshot 150 ETH (D2 pending)  → D2 activates after
     *   Epoch 4: fee, snapshot 200 ETH (D3 pending)  → D3 activates after
     *   Epoch 5: fee, snapshot 250 ETH (all active)  → D3 earns first reward here
     */
    function test_Reward_ThreeDelegatorsStaggeredActivation() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        // Validator activates directly (one-step: full stake)
        vm.deal(validatorOwner, MIN_VALIDATOR_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        _advanceEpoch(); // epoch 1: validator activates (ownerStake = 100 ETH snapshot)

        uint256 dStake = 50 ether;

        // D1 delegates at epoch 1 (activates at epoch 2)
        vm.deal(delegator1, dStake);
        vm.prank(delegator1);
        staking.delegate{value: dStake}(poolId);

        // Epoch 2: fee distributed to owner only (D1 pending, snapshot = 100 ETH)
        _advanceEpochWithFee(poolId, PRIORITY_FEE);
        vm.prank(delegator1); // D1 activates; catch-up = 0
        staking.settleReward(poolId);

        // D2 delegates at epoch 2 (activates at epoch 3)
        vm.deal(delegator2, dStake);
        vm.prank(delegator2);
        staking.delegate{value: dStake}(poolId);

        // Epoch 3: fee distributed to owner + D1 (snapshot = 150 ETH, D2 pending)
        _advanceEpochWithFee(poolId, PRIORITY_FEE);
        vm.prank(delegator2); // D2 activates; catch-up = 0
        staking.settleReward(poolId);

        // D3 delegates at epoch 3 (activates at epoch 4)
        vm.deal(delegator3, dStake);
        vm.prank(delegator3);
        staking.delegate{value: dStake}(poolId);

        // Epoch 4: fee distributed to owner + D1 + D2 (snapshot = 200 ETH, D3 pending)
        _advanceEpochWithFee(poolId, PRIORITY_FEE);
        vm.prank(delegator3); // D3 activates; catch-up = 0
        staking.settleReward(poolId);

        // Epoch 5: fee distributed to all (snapshot = 250 ETH, all active)
        // This is the first epoch where D3's stake is included in the snapshot.
        _advanceEpochWithFee(poolId, PRIORITY_FEE);

        // Settle everyone
        vm.prank(delegator3); // D3 earns epoch 5 reward
        staking.settleReward(poolId);
        vm.prank(validatorOwner);
        staking.settleReward(poolId);
        vm.prank(delegator1);
        staking.settleReward(poolId);
        vm.prank(delegator2);
        staking.settleReward(poolId);

        uint256 d1Rewards = staking.getDelegator(poolId, delegator1).rewards;
        uint256 d2Rewards = staking.getDelegator(poolId, delegator2).rewards;
        uint256 d3Rewards = staking.getDelegator(poolId, delegator3).rewards;

        // D1 was active from epoch 2 onwards (earns epoch 3, 4, 5)
        // D2 was active from epoch 3 onwards (earns epoch 4, 5)
        // D3 active from epoch 4 onwards (earns epoch 5 only)
        // With equal stake amounts and growing snapshot: d1Rewards > d2Rewards > d3Rewards
        assertTrue(d1Rewards > d2Rewards, "d1 (active longer) should earn more than d2");
        assertTrue(d2Rewards > d3Rewards, "d2 (active longer) should earn more than d3");
        assertTrue(d3Rewards > 0, "d3 earns from epoch 5 (first epoch D3 is in the snapshot)");
    }

    // ==================== Group 3: Commission ====================

    /**
     * @notice Commission rate change takes effect after DEFAULT_COMMISSION_RATE_DELAY = 10 epochs.
     *
     * Timing: setCommissionRate at epoch N -> effectiveEpoch = N+10.
     * STEP 3d of advanceEpoch writes the new rate when currentEpoch == effectiveEpoch.
     * STEP 1 (rewardValidators) in THAT epoch still uses the old rate.
     * New rate first applies in STEP 1 of epoch N+11's advanceEpoch.
     * Therefore: loop 11 epochs BEFORE distributing with new rate.
     */
    function test_Commission_RateChangeAppliedAfterDelay() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        vm.deal(validatorOwner, MIN_VALIDATOR_STAKE); // 100 ether
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        uint256 d1Stake = 100 ether;
        vm.deal(delegator1, d1Stake);
        vm.prank(delegator1);
        staking.delegate{value: d1Stake}(poolId);

        _advanceEpoch(); // activate validator (epoch 0 -> 1)
        vm.prank(delegator1); // activate d1
        staking.settleReward(poolId);

        // --- Epoch with OLD rate (10%) ---
        _advanceEpochWithFee(poolId, PRIORITY_FEE); // epoch 1 -> 2
        vm.prank(validatorOwner);
        staking.settleReward(poolId);
        vm.prank(delegator1);
        staking.settleReward(poolId);

        // Snapshot rewards after old-rate epoch
        uint256 ownerAfterOld = staking.getDelegator(poolId, validatorOwner).rewards;
        uint256 d1AfterOld = staking.getDelegator(poolId, delegator1).rewards;

        // Request 20% commission at currentEpoch = 2 -> effectiveEpoch = 2 + 10 = 12
        vm.prank(validatorOwner);
        staking.setCommissionRate(poolId, 2000);

        // Advance exactly 11 epochs so that:
        //   - Epoch 12 triggers STEP 3d (writes 2000)
        //   - After 11th iteration: commissionRates[poolId] = 2000
        for (uint256 i = 0; i < 11; i++) {
            _advanceEpoch();
        }
        // currentEpoch = 13 now; new rate is stored
        assertEq(staking.getCommissionRate(poolId), 2000, "commission rate should be 20% now");

        // Snapshot again (inflation from 11 epochs is included)
        vm.prank(validatorOwner);
        staking.settleReward(poolId);
        vm.prank(delegator1);
        staking.settleReward(poolId);
        uint256 ownerPreNew = staking.getDelegator(poolId, validatorOwner).rewards;
        uint256 d1PreNew = staking.getDelegator(poolId, delegator1).rewards;

        // --- Epoch with NEW rate (20%) ---
        _advanceEpochWithFee(poolId, PRIORITY_FEE); // epoch 13 -> 14 (STEP 1 uses 2000)
        vm.prank(validatorOwner);
        staking.settleReward(poolId);
        vm.prank(delegator1);
        staking.settleReward(poolId);

        // Incremental reward from the new-rate epoch only
        uint256 ownerEarnedNewRate = staking.getDelegator(poolId, validatorOwner).rewards - ownerPreNew;
        uint256 d1EarnedNewRate = staking.getDelegator(poolId, delegator1).rewards - d1PreNew;
        uint256 d1EarnedOldRate = d1AfterOld; // first fee epoch, old rate

        // Old rate: commission 10%, delegationPool 90%. Stake split 50/50.
        // d1 old rate reward = 90% * fee * (100/200) = 45% of fee = 4500 ETH
        // New rate: commission 20%, delegationPool 80%. Stake split 50/50.
        // d1 new rate reward = 80% * fee * (100/200) = 40% of fee = 4000 ETH
        assertTrue(ownerEarnedNewRate > (ownerAfterOld), "owner should earn more per epoch with 20% commission vs 10%");
        assertTrue(d1EarnedNewRate < d1EarnedOldRate, "delegator should earn less per epoch with higher commission");

        // Verify approximate proportions with 2% tolerance
        // owner new: commission = 20% + 40% delegation = 60% of total (owner+d1 only)
        // d1 new: 40% of total
        uint256 newTotal = ownerEarnedNewRate + d1EarnedNewRate;
        assertApproxEqRel(newTotal, PRIORITY_FEE, 0.02e18, "new rate epoch total ~= fee");
        uint256 ownerPctNew = (ownerEarnedNewRate * 100) / newTotal;
        assertApproxEqAbs(ownerPctNew, 60, 3, "owner ~60% of reward with 20% commission");
    }

    // ==================== Group 4: Owner delegate scenario ====================

    /**
     * @notice Owner registers with partial stake, then delegates MORE to reach threshold.
     *         Both initial and additional stake earn rewards after activation.
     */
    function test_OwnerDelegate_AdditionalStakeEarnsReward() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE); // 10 ether
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        // Owner delegates remaining to reach threshold
        uint256 ownerExtra = MIN_VALIDATOR_STAKE - MIN_REGISTRATION_STAKE; // 90 ether
        vm.deal(validatorOwner, ownerExtra);
        vm.prank(validatorOwner);
        staking.delegate{value: ownerExtra}(poolId);

        assertTrue(staking.isValidatorPendingAdd(poolId), "threshold reached");

        _advanceEpoch(); // activate

        // Trigger lazy activation of owner's extra pending stake
        vm.prank(validatorOwner);
        staking.settleReward(poolId);

        IStaking.Delegator memory ownerInfo = staking.getDelegator(poolId, validatorOwner);
        assertEq(ownerInfo.stake, MIN_VALIDATOR_STAKE, "owner total active stake = MIN_REGISTRATION + extra");
        assertEq(ownerInfo.pendingStake, 0, "all pending stake should be cleared");

        // Owner holds 100% of stake -> should receive 100% of reward
        _advanceEpochWithFee(poolId, PRIORITY_FEE);
        vm.prank(validatorOwner);
        staking.settleReward(poolId);

        ownerInfo = staking.getDelegator(poolId, validatorOwner);
        // 100% commission + 100% delegation (minus commission taken back = same)
        assertApproxEqRel(
            ownerInfo.rewards, PRIORITY_FEE, 0.02e18, "owner (sole participant) should receive ~100% of fee"
        );
    }

    /**
     * @notice Full lifecycle: bootstrapping registration -> delegation -> activation
     *         -> reward accumulation -> undelegation -> principal claim.
     */
    function test_Lifecycle_DelegatorWithdrawAfterBootstrapping() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        uint256 d1Stake = MIN_VALIDATOR_STAKE - MIN_REGISTRATION_STAKE; // 90 ether
        vm.deal(delegator1, d1Stake);
        vm.prank(delegator1);
        staking.delegate{value: d1Stake}(poolId);

        _advanceEpoch(); // activate
        vm.prank(delegator1);
        staking.settleReward(poolId);

        // Earn rewards over 2 epochs
        _advanceEpochWithFee(poolId, PRIORITY_FEE);
        _advanceEpochWithFee(poolId, PRIORITY_FEE);
        vm.prank(delegator1);
        staking.settleReward(poolId);

        uint256 d1Rewards = staking.getDelegator(poolId, delegator1).rewards;
        assertTrue(d1Rewards > 0, "delegator1 should have accumulated rewards");

        // Undelegate
        vm.prank(delegator1);
        (uint256 undelegateAmount,) = staking.undelegate(poolId);

        // undelegateAmount = stake + rewards
        assertApproxEqAbs(undelegateAmount, d1Stake + d1Rewards, 1, "undelegate = stake + rewards");

        // Advance through withdraw window
        _advanceEpoch();

        // Claim principal (rewards are minted via CoinMinted event, not transferred from balance)
        vm.deal(address(staking), d1Stake); // ensure contract has ETH for principal
        uint256 balBefore = delegator1.balance;
        vm.prank(delegator1);
        staking.claimStake(poolId);
        uint256 principalReceived = delegator1.balance - balBefore;

        assertApproxEqAbs(principalReceived, d1Stake, 1, "principal returned = original delegation");

        IStaking.Delegator memory d1Final = staking.getDelegator(poolId, delegator1);
        assertFalse(d1Final.isPendingUndelegate, "should clear pending after claim");
    }

    // ==================== Group 5: Edge Cases ====================

    /**
     * @notice A bootstrapping validator (not in active set) does NOT receive rewards.
     *         Rewards start accumulating only AFTER activation.
     */
    function test_NoRewardBeforeActivation() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        // Fee is passed but this validator is NOT in active set
        _advanceEpochWithFee(poolId, PRIORITY_FEE);
        vm.prank(validatorOwner);
        staking.settleReward(poolId);

        IStaking.Delegator memory ownerInfo = staking.getDelegator(poolId, validatorOwner);
        assertEq(ownerInfo.rewards, 0, "bootstrapping validator earns NO rewards");
    }

    /**
     * @notice exitValidator works for a bootstrapping validator (it's in pendingAdd).
     *         withdrawStake is also available for partial exit.
     */
    function test_BootstrappingOwnerCanWithdrawViaWithdrawStake() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        // exitValidator: bootstrapping validator IS in pendingAdd, so exitValidator succeeds
        assertTrue(staking.isValidatorPendingAdd(poolId), "bootstrapping validator is in pendingAdd");
        vm.prank(validatorOwner);
        staking.exitValidator(poolId); // should succeed (isActive || isPendingAdd)

        IStaking.Delegator memory ownerInfo = staking.getDelegator(poolId, validatorOwner);
        assertTrue(ownerInfo.isPendingUndelegate, "owner in pendingUndelegate after exitValidator");
        assertEq(ownerInfo.pendingWithdrawStake, MIN_REGISTRATION_STAKE);
    }

    /**
     * @notice Two validators bootstrap simultaneously.
     *         Only the one reaching the threshold enters pendingAdd and activates.
     */
    function test_TwoValidators_IndependentBootstrappingState() public {
        bytes32 pool1 = _poolId(PUBLIC_KEY);
        bytes32 pool2 = _poolId(PUBLIC_KEY2);

        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        vm.deal(validatorOwner2, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner2);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY2, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, "http://v2.test"
        );

        // Only pool1 receives enough delegation to cross the threshold
        uint256 remaining = MIN_VALIDATOR_STAKE - MIN_REGISTRATION_STAKE;
        vm.deal(delegator1, remaining);
        vm.prank(delegator1);
        staking.delegate{value: remaining}(pool1);

        assertTrue(staking.isValidatorPendingAdd(pool1), "pool1 in pendingAdd after threshold");
        assertTrue(staking.isValidatorPendingAdd(pool2), "pool2 also in pendingAdd (bootstrapping)");
        assertTrue(staking.isValidatorBootstrapping(pool2), "pool2 still bootstrapping (below threshold)");

        _advanceEpoch();

        assertTrue(staking.isValidatorActive(pool1), "pool1 activates");
        assertFalse(staking.isValidatorActive(pool2), "pool2 stays inactive");
    }

    /**
     * @notice Total rewards distributed to all parties must equal the fee (within 2% for inflation).
     *         Verifies the reward conservation invariant across 3 epochs.
     */
    function test_RewardConservation_TotalEqualsFee() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE); // 10 ether
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        vm.deal(delegator1, 40 ether);
        vm.prank(delegator1);
        staking.delegate{value: 40 ether}(poolId);

        vm.deal(delegator2, 50 ether);
        vm.prank(delegator2);
        staking.delegate{value: 50 ether}(poolId);

        _advanceEpoch(); // activate
        vm.prank(delegator1);
        staking.settleReward(poolId);
        vm.prank(delegator2);
        staking.settleReward(poolId);

        // Distribute fee for 3 epochs
        for (uint256 i = 0; i < 3; i++) {
            _advanceEpochWithFee(poolId, PRIORITY_FEE);
        }

        vm.prank(validatorOwner);
        staking.settleReward(poolId);
        vm.prank(delegator1);
        staking.settleReward(poolId);
        vm.prank(delegator2);
        staking.settleReward(poolId);

        uint256 total = staking.getDelegator(poolId, validatorOwner).rewards
            + staking.getDelegator(poolId, delegator1).rewards + staking.getDelegator(poolId, delegator2).rewards;

        // 3 fee epochs: total ~= 3 * PRIORITY_FEE (with tiny inflation overhead, <= 2%)
        assertApproxEqRel(total, 3 * PRIORITY_FEE, 0.02e18, "total rewards ~= 3 fee epochs");
    }
}
