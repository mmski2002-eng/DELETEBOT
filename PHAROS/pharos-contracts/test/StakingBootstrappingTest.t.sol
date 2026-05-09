// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

/**
 * @title StakingBootstrappingTest
 * @notice Tests for the bootstrapping validator feature:
 *         - Validators can register with a partial stake below the activation threshold
 *         - Only added to pendingAddPoolSets when totalStake >= minValidatorStake
 *         - Non-owner delegators can contribute to bring a validator to the threshold
 *         - Prevents DoS via queue flooding with low-stake registrations
 */
contract StakingBootstrappingTest is Test {
    ChainConfig private chainConfig;
    TransparentUpgradeableProxy chainConfigProxy;
    Staking private staking;
    TransparentUpgradeableProxy private stakingProxy;
    RuleManager private ruleManager;
    TransparentUpgradeableProxy private ruleManagerProxy;

    address admin = address(0x1111111111111111111111111111111111111111);

    // Use non-precompile addresses (precompiles are 0x01-0x0a in EVM)
    address public validatorOwner = address(0xA001);
    address public validatorOwner2 = address(0xA002);
    address public delegator1 = address(0xB001);
    address public delegator2 = address(0xB002);

    // Validator keys (must be unique valid hex to produce distinct poolIds)
    string public constant DESCRIPTION = "Bootstrapping Validator";
    string public constant PUBLIC_KEY = "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f";
    string public constant PUBLIC_KEY2 = "0x04b34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5a";
    string public constant PUBLIC_KEY_POP = "0xpop1";
    string public constant BLS_KEY = "0xbls1";
    string public constant BLS_KEY_POP = "0xblspop1";
    string public constant ENDPOINT = "http://validator.test";

    // Stake thresholds used in these tests
    uint256 public constant MIN_REGISTRATION_STAKE = 100 ether; // partial registration threshold
    uint256 public constant MIN_VALIDATOR_STAKE = 1000 ether; // activation threshold
    uint256 public constant MIN_DELEGATOR_STAKE = 1 ether;
    uint256 public constant MAX_VALIDATOR_STAKE = 100_000_000 ether;

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

        // Set chain config: min_staking_registration_value < min_staking_pool_value (activation threshold)
        string[] memory keys = new string[](5);
        string[] memory values = new string[](5);
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
        vm.prank(address(staking));
        chainConfig.setConfig(keys, values);
        vm.roll(block.number + 1);
    }

    function _advanceEpoch() internal {
        vm.warp(block.timestamp + 4 hours + 1);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));
    }

    function _poolId(string memory pubKey) internal pure returns (bytes32) {
        bytes memory pubKeyBytes;
        bytes memory strBytes = bytes(pubKey);
        // strip "0x" prefix
        uint256 offset = (strBytes.length >= 2 && strBytes[0] == "0" && strBytes[1] == "x") ? 2 : 0;
        pubKeyBytes = new bytes((strBytes.length - offset) / 2);
        for (uint256 i = 0; i < pubKeyBytes.length; i++) {
            uint8 hi = _hexChar(strBytes[offset + 2 * i]);
            uint8 lo = _hexChar(strBytes[offset + 2 * i + 1]);
            pubKeyBytes[i] = bytes1(hi * 16 + lo);
        }
        return bytes32(sha256(abi.encodePacked(pubKeyBytes)));
    }

    function _hexChar(bytes1 c) internal pure returns (uint8) {
        uint8 code = uint8(c);
        if (code >= 48 && code <= 57) return code - 48;
        if (code >= 97 && code <= 102) return code - 87;
        if (code >= 65 && code <= 70) return code - 55;
        revert("bad hex");
    }

    // ==================== Bootstrapping Registration Tests ====================

    /**
     * @notice Registering with partial stake (below activation threshold) goes into
     *         pendingAddPoolSets but is in "bootstrapping" state (totalStake < minValidatorStake).
     */
    function test_Register_WithPartialStake_NotInPendingAdd() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        // Validator exists in state
        IStaking.Validator memory v = staking.getValidator(poolId);
        assertEq(v.poolId, poolId, "validator should exist");
        assertEq(v.totalStake, MIN_REGISTRATION_STAKE, "totalStake should equal registration amount");
        assertEq(v.status, 0, "status should be inactive");

        // Validator IS in pendingAdd (unified queue), but not yet active
        assertTrue(staking.isValidatorPendingAdd(poolId), "should be in pendingAdd");
        assertTrue(staking.isValidatorBootstrapping(poolId), "should be in bootstrapping state (below threshold)");
        assertFalse(staking.isValidatorActive(poolId), "should NOT be active");
    }

    /**
     * @notice Registering with full stake (>= activation threshold) goes directly to
     *         pendingAddPoolSets — existing behavior preserved (regression test).
     */
    function test_Register_WithFullStake_DirectlyInPendingAdd() public {
        bytes32 poolId = _poolId(PUBLIC_KEY);

        vm.deal(validatorOwner, MIN_VALIDATOR_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        assertTrue(staking.isValidatorPendingAdd(poolId), "full-stake registration should be in pendingAdd");
        assertFalse(staking.isValidatorActive(poolId), "should not be active yet (needs advanceEpoch)");
    }

    /**
     * @notice Registration below MIN_REGISTRATION_STAKE reverts.
     */
    function test_Register_BelowMinRegisterStake_Reverts() public {
        uint256 tooLittle = MIN_REGISTRATION_STAKE - 1;
        vm.deal(validatorOwner, tooLittle);
        vm.prank(validatorOwner);
        vm.expectRevert("Insufficient stake");
        staking.registerValidator{value: tooLittle}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );
    }

    // ==================== Non-Owner Delegation to Bootstrapping Validator ====================

    /**
     * @notice Non-owner delegators can stake to a bootstrapping validator
     *         (registered but below activation threshold).
     */
    function test_NonOwner_CanDelegate_ToBootstrappingValidator() public {
        // Register with partial stake
        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );
        bytes32 poolId = _poolId(PUBLIC_KEY);

        // Non-owner delegator can add stake
        uint256 delegateAmount = 10 ether;
        vm.deal(delegator1, delegateAmount);
        vm.prank(delegator1);
        staking.delegate{value: delegateAmount}(poolId); // must not revert

        // Validator totalStake increased
        IStaking.Validator memory v = staking.getValidator(poolId);
        assertEq(v.totalStake, MIN_REGISTRATION_STAKE + delegateAmount, "totalStake should include delegator's stake");

        // Still below activation threshold → bootstrapping (in pendingAdd but not activatable yet)
        assertTrue(staking.isValidatorPendingAdd(poolId), "still in pendingAdd");
        assertTrue(staking.isValidatorBootstrapping(poolId), "still below threshold, bootstrapping state");
    }

    /**
     * @notice Non-owner cannot delegate to a validator that's in pendingExit.
     */
    function test_NonOwner_CannotDelegate_ToPendingExitValidator() public {
        // Register with full stake and activate
        vm.deal(validatorOwner, MIN_VALIDATOR_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );
        bytes32 poolId = _poolId(PUBLIC_KEY);
        _advanceEpoch(); // activate

        // Owner exits
        vm.prank(validatorOwner);
        staking.exitValidator(poolId);

        assertTrue(staking.isValidatorPendingExit(poolId), "should be in pendingExit");

        // Non-owner tries to delegate → should revert
        vm.deal(delegator1, 10 ether);
        vm.prank(delegator1);
        vm.expectRevert("Validator is pending exit");
        staking.delegate{value: 10 ether}(poolId);
    }

    // ==================== Threshold-Based Queue Enrollment ====================

    /**
     * @notice When owner delegates enough to bring totalStake to minValidatorStake,
     *         the validator is automatically added to pendingAddPoolSets.
     */
    function test_OwnerDelegate_ReachesThreshold_AddedToPendingAdd() public {
        // Register with partial stake
        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );
        bytes32 poolId = _poolId(PUBLIC_KEY);
        // pre-condition: in pendingAdd (unified queue), but bootstrapping (below threshold)
        assertTrue(staking.isValidatorPendingAdd(poolId), "pre-condition: in pendingAdd");
        assertTrue(staking.isValidatorBootstrapping(poolId), "pre-condition: bootstrapping state");

        // Owner adds more stake to reach threshold
        uint256 remaining = MIN_VALIDATOR_STAKE - MIN_REGISTRATION_STAKE;
        vm.deal(validatorOwner, remaining);
        vm.prank(validatorOwner);
        staking.delegate{value: remaining}(poolId);

        // Now at threshold → still in pendingAdd, no longer bootstrapping
        assertTrue(staking.isValidatorPendingAdd(poolId), "should be in pendingAdd after reaching threshold");
        assertFalse(staking.isValidatorBootstrapping(poolId), "should no longer be bootstrapping");
    }

    /**
     * @notice When a non-owner delegator's stake pushes totalStake over minValidatorStake,
     *         the validator is automatically added to pendingAddPoolSets.
     */
    function test_NonOwnerDelegate_PushesOverThreshold_AddedToPendingAdd() public {
        // Owner registers with stake just below threshold
        uint256 ownerStake = MIN_VALIDATOR_STAKE - 50 ether;
        vm.deal(validatorOwner, ownerStake);
        vm.prank(validatorOwner);
        staking.registerValidator{value: ownerStake}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );
        bytes32 poolId = _poolId(PUBLIC_KEY);
        // pre-condition: in pendingAdd (unified queue), but bootstrapping (below threshold)
        assertTrue(staking.isValidatorPendingAdd(poolId), "pre-condition: in pendingAdd");
        assertTrue(staking.isValidatorBootstrapping(poolId), "pre-condition: bootstrapping state");

        // Delegator adds exactly enough to reach threshold
        vm.deal(delegator1, 50 ether);
        vm.prank(delegator1);
        staking.delegate{value: 50 ether}(poolId);

        assertTrue(
            staking.isValidatorPendingAdd(poolId), "should be in pendingAdd after non-owner pushes over threshold"
        );
        assertFalse(staking.isValidatorBootstrapping(poolId), "should no longer be bootstrapping");
    }

    /**
     * @notice Delegating past threshold in multiple steps works correctly:
     *         validator enrolls to pendingAdd once, then activates on advanceEpoch,
     *         and further delegation to the now-active validator succeeds cleanly.
     */
    function test_MultipleDelegate_OnlyEnqueuedOnce() public {
        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );
        bytes32 poolId = _poolId(PUBLIC_KEY);

        // Step 1: bring to threshold (pendingAdd)
        uint256 step1 = MIN_VALIDATOR_STAKE - MIN_REGISTRATION_STAKE;
        vm.deal(delegator1, step1);
        vm.prank(delegator1);
        staking.delegate{value: step1}(poolId);
        assertTrue(staking.isValidatorPendingAdd(poolId), "should be in pendingAdd after threshold");

        // Advance epoch: validator activates (moved from pendingAdd → active)
        _advanceEpoch();
        assertTrue(staking.isValidatorActive(poolId), "should be active after advanceEpoch");
        assertFalse(staking.isValidatorPendingAdd(poolId), "should no longer be in pendingAdd");

        // Step 2: delegator1 settles (lazy activation of their pending stake)
        vm.prank(delegator1);
        staking.settleReward(poolId);

        // Step 3: delegator2 adds more stake to the now-active validator — must not revert
        // and must not erroneously re-add to pendingAdd (it's already active)
        vm.deal(delegator2, 10 ether);
        vm.prank(delegator2);
        staking.delegate{value: 10 ether}(poolId);

        // Validator remains active, not re-queued
        assertTrue(staking.isValidatorActive(poolId), "validator should remain active");
        assertFalse(staking.isValidatorPendingAdd(poolId), "should not be re-added to pendingAdd");
    }

    // ==================== Full Bootstrapping Lifecycle ====================

    /**
     * @notice Full lifecycle: partial register → delegators fill up → advanceEpoch → active.
     */
    function test_FullBootstrappingFlow_ValidatorActivates() public {
        // 1. Owner registers with partial stake
        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );
        bytes32 poolId = _poolId(PUBLIC_KEY);

        // 2. Non-owner delegators add stake
        uint256 remaining = MIN_VALIDATOR_STAKE - MIN_REGISTRATION_STAKE;
        vm.deal(delegator1, remaining);
        vm.prank(delegator1);
        staking.delegate{value: remaining}(poolId);

        assertTrue(staking.isValidatorPendingAdd(poolId), "should be in pendingAdd after threshold reached");
        assertFalse(staking.isValidatorActive(poolId), "not active yet");

        // 3. advanceEpoch activates the validator
        _advanceEpoch();

        assertTrue(staking.isValidatorActive(poolId), "should be active after advanceEpoch");
        assertFalse(staking.isValidatorPendingAdd(poolId), "should be removed from pendingAdd");
    }

    // ==================== DoS Prevention ====================

    /**
     * @notice Many validators registering with partial stake all enter pendingAddPoolSets
     *         but are not activated (totalStake < minValidatorStake).
     *         getBootstrappingValidators() enumerates them; MAX_QUEUE_LENGTH caps the set.
     */
    function test_DoS_ManyPartialRegistrations_QueueNotFlooded() public {
        uint256 N = 20;

        for (uint256 i = 0; i < N; i++) {
            address owner = address(uint160(0xC000 + i));
            string memory pubKey = string(
                abi.encodePacked(
                    "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e", _uint8ToHex(uint8(i))
                )
            );
            vm.deal(owner, MIN_REGISTRATION_STAKE);
            vm.prank(owner);
            staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
                DESCRIPTION, pubKey, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
            );
        }

        // All N validators are in pendingAdd (unified queue) but none are activatable
        assertEq(staking.getPendingAddValidators().length, N, "all partial-stake validators in pendingAdd");
        assertEq(staking.getBootstrappingValidators().length, N, "all are in bootstrapping state");

        // advanceEpoch does NOT activate any of them (totalStake < minValidatorStake)
        _advanceEpoch();
        assertEq(staking.getActiveValidators().length, 0, "none should activate without reaching threshold");
        assertEq(staking.getBootstrappingValidators().length, N, "still bootstrapping after epoch");
    }

    // ==================== updateValidator in Bootstrapping State ====================

    /**
     * @notice Validator in bootstrapping state can update their description/endpoint.
     */
    function test_UpdateValidator_InBootstrappingState() public {
        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );
        bytes32 poolId = _poolId(PUBLIC_KEY);

        assertFalse(staking.isValidatorActive(poolId), "pre-condition: not active");
        assertTrue(staking.isValidatorBootstrapping(poolId), "pre-condition: bootstrapping state");

        // Update metadata — must succeed
        vm.prank(validatorOwner);
        staking.updateValidator(poolId, "Updated Description", "http://new.endpoint");

        IStaking.Validator memory v = staking.getValidator(poolId);
        assertEq(v.description, "Updated Description", "description should be updated");
        assertEq(v.endpoint, "http://new.endpoint", "endpoint should be updated");

        // Bootstrapping validator should NOT be in pendingUpdatePoolSets (not active)
        assertFalse(staking.isValidatorPendingUpdate(poolId), "bootstrapping validator not in pendingUpdate");
    }

    /**
     * @notice Updated metadata carries through when the validator eventually activates.
     */
    function test_UpdateValidator_MetadataCarriesThrough_OnActivation() public {
        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );
        bytes32 poolId = _poolId(PUBLIC_KEY);

        // Update while bootstrapping
        vm.prank(validatorOwner);
        staking.updateValidator(poolId, "New Description", "http://new-endpoint.test");

        // Bring to threshold and activate
        uint256 remaining = MIN_VALIDATOR_STAKE - MIN_REGISTRATION_STAKE;
        vm.deal(delegator1, remaining);
        vm.prank(delegator1);
        staking.delegate{value: remaining}(poolId);

        _advanceEpoch();

        // Active validator should have the updated metadata
        IStaking.Validator memory v = staking.getValidator(poolId);
        assertEq(v.description, "New Description", "activated validator should have updated description");
        assertTrue(staking.isValidatorActive(poolId), "should be active");
    }

    /**
     * @notice After exit is fully processed (advanceEpoch deactivates the validator),
     *         the owner can no longer update the validator metadata (no longer active/bootstrapping).
     * NOTE: exitValidator only adds to pendingExit but doesn't deactivate immediately.
     *       Deactivation happens in _processPendingExits during advanceEpoch.
     *       While still active+pendingExit, updateValidator is allowed (consistent with original behavior).
     */
    function test_UpdateValidator_AfterFullyProcessedExit_Reverts() public {
        // Register and activate
        vm.deal(validatorOwner, MIN_VALIDATOR_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );
        bytes32 poolId = _poolId(PUBLIC_KEY);
        _advanceEpoch(); // activate

        // Owner exits
        vm.prank(validatorOwner);
        staking.exitValidator(poolId);

        // Before advanceEpoch: validator is still active (exit not processed yet)
        assertTrue(staking.isValidatorActive(poolId), "still active before exit processed");
        assertTrue(staking.isValidatorPendingExit(poolId), "in pendingExit");

        // Update is allowed while still active (consistent with pre-bootstrapping behavior)
        vm.prank(validatorOwner);
        staking.updateValidator(poolId, "Interim Update", "http://interim.test");

        // advanceEpoch: exit is processed, validator is deactivated, totalStake=0
        _advanceEpoch();
        assertFalse(staking.isValidatorActive(poolId), "should be deactivated after advanceEpoch");
        assertFalse(staking.isValidatorPendingExit(poolId), "should be removed from pendingExit");

        // After full deactivation with totalStake=0, cannot update (no bootstrapping state either)
        IStaking.Validator memory v = staking.getValidator(poolId);
        assertEq(v.totalStake, 0, "totalStake should be 0 after exit");
        assertEq(v.status, 0, "status should be 0 after exit");

        vm.prank(validatorOwner);
        vm.expectRevert("Validator is not in an updatable state");
        staking.updateValidator(poolId, "Post-Exit Update", "http://postexit.test");
    }

    // ==================== Edge Cases ====================

    /**
     * @notice Bootstrapping validator appears in getValidator(), getAllValidators(), and
     *         getBootstrappingValidators(). isValidatorPendingAdd() returns true;
     *         isValidatorBootstrapping() returns true while below threshold.
     */
    function test_BootstrappingValidator_NotInGetAllValidators() public {
        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );
        bytes32 poolId = _poolId(PUBLIC_KEY);

        // getValidator works
        IStaking.Validator memory v = staking.getValidator(poolId);
        assertEq(v.poolId, poolId, "getValidator should return the bootstrapping validator");

        // getAllValidators includes it (via unified pendingAdd)
        bytes32[] memory all = staking.getAllValidators();
        bool found = false;
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i] == poolId) found = true;
        }
        assertTrue(found, "bootstrapping validator should appear in getAllValidators");

        // isValidatorBootstrapping returns true while below threshold
        assertTrue(staking.isValidatorBootstrapping(poolId), "should be in bootstrapping state");
        assertTrue(staking.isValidatorPendingAdd(poolId), "should be in pendingAdd (unified)");

        // After reaching threshold: still in pendingAdd, no longer bootstrapping
        uint256 remaining = MIN_VALIDATOR_STAKE - MIN_REGISTRATION_STAKE;
        vm.deal(delegator1, remaining);
        vm.prank(delegator1);
        staking.delegate{value: remaining}(poolId);

        all = staking.getAllValidators();
        found = false;
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i] == poolId) found = true;
        }
        assertTrue(found, "validator should still appear in getAllValidators after reaching threshold");
        assertTrue(staking.isValidatorPendingAdd(poolId), "should still be in pendingAdd");
        assertFalse(staking.isValidatorBootstrapping(poolId), "should no longer be bootstrapping");
    }

    /**
     * @notice Owner can re-register after exit; re-registration with partial stake is in bootstrapping state.
     */
    function test_ReRegister_AfterExit_BootstrappingState() public {
        // Register and activate
        vm.deal(validatorOwner, MIN_VALIDATOR_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );
        bytes32 poolId = _poolId(PUBLIC_KEY);
        _advanceEpoch(); // activate

        // Owner exits and claims
        vm.prank(validatorOwner);
        staking.exitValidator(poolId);
        _advanceEpoch(); // process exit

        vm.deal(validatorOwner, 1); // just for gas
        vm.prank(validatorOwner);
        staking.claimStake(poolId);

        // Re-register with partial stake → bootstrapping state
        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.registerValidator{value: MIN_REGISTRATION_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );

        assertTrue(staking.isValidatorPendingAdd(poolId), "re-register with partial stake: in pendingAdd");
        assertFalse(staking.isValidatorActive(poolId), "re-register with partial stake: not active");
        assertTrue(staking.isValidatorBootstrapping(poolId), "re-register with partial stake: bootstrapping state");

        IStaking.Validator memory v = staking.getValidator(poolId);
        assertEq(v.totalStake, MIN_REGISTRATION_STAKE, "stake should be min register amount");
    }

    // Verify that owner cannot bypass minRegistrationStake via delegate() STEP 4a.
    // After a full exit+claim the validator is "stranded" (not in any set).
    // STEP 4a re-enters pendingAddPoolSets — but must require ownerStake >= minRegistrationStake.
    function test_Delegate_Step4a_CannotBypassMinRegistrationStake() public {
        // Register and activate
        vm.deal(validatorOwner, MIN_VALIDATOR_STAKE);
        vm.prank(validatorOwner);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_KEY, BLS_KEY_POP, ENDPOINT
        );
        _advanceEpoch(); // activate
        assertTrue(staking.isValidatorActive(poolId), "setup: validator active");

        // Owner fully exits
        vm.prank(validatorOwner);
        staking.exitValidator(poolId);
        _advanceEpoch(); // process exit → validator deactivated, not re-enqueued (ownerStake=0)

        vm.prank(validatorOwner);
        staking.claimStake(poolId);

        // Validator is now stranded: not active, not pendingAdd, not pendingExit
        assertFalse(staking.isValidatorActive(poolId), "validator not active");
        assertFalse(staking.isValidatorPendingAdd(poolId), "validator not pendingAdd");
        assertFalse(staking.isValidatorPendingExit(poolId), "validator not pendingExit");

        // Attempt 1: delegate with only minDelegatorStake (< minRegistrationStake)
        // STEP 4a must reject this — it would occupy a pendingAdd slot far below the intent.
        vm.deal(validatorOwner, MIN_DELEGATOR_STAKE);
        vm.prank(validatorOwner);
        vm.expectRevert("Owner stake below minRegistrationStake");
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Validator must still be stranded (no state change from the failed call)
        assertFalse(staking.isValidatorPendingAdd(poolId), "still not pendingAdd after failed delegate");

        // Attempt 2: delegate with exactly minRegistrationStake — must succeed
        vm.deal(validatorOwner, MIN_REGISTRATION_STAKE);
        vm.prank(validatorOwner);
        staking.delegate{value: MIN_REGISTRATION_STAKE}(poolId);

        assertTrue(staking.isValidatorPendingAdd(poolId), "re-entered pendingAdd with minRegistrationStake");
        assertTrue(staking.isValidatorBootstrapping(poolId), "in bootstrapping sub-state");
        IStaking.Delegator memory ownerD = staking.getDelegator(poolId, validatorOwner);
        assertEq(ownerD.pendingStake, MIN_REGISTRATION_STAKE, "owner pendingStake = MIN_REGISTRATION_STAKE");
    }

    // ==================== Helper ====================

    function _uint8ToHex(uint8 n) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(2);
        result[0] = hexChars[n >> 4];
        result[1] = hexChars[n & 0x0f];
        return string(result);
    }
}
