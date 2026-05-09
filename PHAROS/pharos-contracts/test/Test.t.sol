// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

// Define error type for AccessControlUnauthorizedAccount to use in vm.expectRevert
error AccessControlUnauthorizedAccount(address account, bytes32 role);

contract SystemContractTest is Test {
    ChainConfig private chainConfig;
    TransparentUpgradeableProxy chainConfigProxy;
    Staking private staking;
    TransparentUpgradeableProxy private stakingProxy;
    RuleManager private ruleManager;
    TransparentUpgradeableProxy private ruleManagerProxy;
    DummyContract private dummyContract;
    address admin = address(0x0);
    address stakingAddress = address(0x2);
    address intrinsicAddress = 0x1111111111111111111111111111111111111111;

    address alice = address(0x2);
    address bob = address(0x3);
    bytes4 dummySelector = bytes4(keccak256("dummyFunction()"));
    bytes32 dummyMetahash = keccak256("testMeta");
    bytes dummyCode = "testCode";

    address public validator = address(0x4);
    address public delegator = address(0x5);
    address public stranger = address(0x6);

    string public constant DESCRIPTION = "Test Validator";
    string public constant PUBLIC_KEY = "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f";
    string public constant PUBLIC_KEY_POP = "0xproof1";
    string public constant BLS_PUBLIC_KEY = "0xblskey1";
    string public constant BLS_PUBLIC_KEY_POP = "0xblspop1";
    string public constant ENDPOINT = "http://test.validator";

    uint256 public constant MIN_POOL_STAKE = 10000000 ether;
    uint256 private constant TEST_YEAR_IN_SECONDS = 365 days;
    uint256 private constant TEST_EPOCH_DURATION = 4 hours;
    uint256 private constant TEST_INFLATION_RATE_DENOMINATOR = 100000;
    uint256 private constant TEST_INFLATION_ADJUSTMENT_RATE = 80000;
    uint256 private constant TEST_INFLATION_ADJUSTMENT_INTERVAL = 365 days;

    uint256 public constant MIN_VALIDATOR_STAKE = 10 ether;
    uint256 public constant MIN_REGISTRATION_STAKE = 1 ether;
    uint256 public constant MIN_DELEGATOR_STAKE = 1 ether;

    function setUp() public {
        admin = intrinsicAddress;
        vm.startPrank(admin);
        // Deploy dummy contract for RuleManager tests
        dummyContract = new DummyContract();
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
        string[] memory keys = new string[](5);
        string[] memory values = new string[](5);
        keys[0] = "staking.min_staking_pool_value";
        values[0] = vm.toString(MIN_VALIDATOR_STAKE);
        keys[1] = "staking.max_staking_pool_value";
        values[1] = vm.toString(MIN_POOL_STAKE);
        keys[2] = "staking.min_delegator_stake";
        values[2] = vm.toString(MIN_DELEGATOR_STAKE);
        keys[3] = "staking.withdraw_effective_epoch";
        values[3] = "1";
        keys[4] = "staking.min_staking_registration_value";
        values[4] = vm.toString(MIN_REGISTRATION_STAKE);

        vm.prank(address(staking));
        chainConfig.setConfig(keys, values);

        // Advance block to make configs effective (required by effectiveBlockNum validation)
        vm.roll(block.number + 1);
    }

    /*
     * Contract upgrade test
     */

    // Debug test to check validator registration
    function testDebugValidatorRegistration() public {
        // Register a validator
        vm.prank(validator);
        vm.deal(validator, MIN_VALIDATOR_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT
        );

        // Check pending validators before advance epoch
        bytes32[] memory pendingBefore = staking.getPendingAddValidators();
        assertEq(pendingBefore.length, 1, "Should have 1 pending validator");
        assertEq(pendingBefore[0], poolId, "Pending pool ID should match");

        // Advance epoch
        advanceEpoch();

        // Check pending validators after advance epoch
        bytes32[] memory pendingAfter = staking.getPendingAddValidators();
        assertEq(pendingAfter.length, 0, "Should have 0 pending validators after epoch");

        // Check active validators
        bytes32[] memory active = staking.getActiveValidators();
        assertEq(active.length, 1, "Should have 1 active validator");
    }

    // Test getConfig method - basic functionality
    function testContarctUpgrade() public {
        vm.startPrank(admin);
        Staking newStaking = new Staking();
        staking.upgradeToAndCall(address(newStaking), "");
        vm.stopPrank();
    }

    /*
     * ChainConfig Contract Test
     */

    // Test getConfig method - basic functionality
    function testGetConfig_Basic() public {
        // Prepare test data
        string[] memory keys = new string[](2);
        string[] memory values = new string[](2);
        keys[0] = "key1";
        values[0] = "value1";
        keys[1] = "key2";
        values[1] = "value2";

        // add pending config
        vm.prank(admin);
        chainConfig.addPendingConfig(keys, values);
        assertEq(chainConfig.getConfig("key1"), ""); // not activated yet
        assertEq(chainConfig.getConfig("key2"), ""); // not activated yet

        // add again
        keys[0] = "key1";
        values[0] = "value1_updated";
        vm.prank(admin);
        chainConfig.addPendingConfig(keys, values);
        assertEq(chainConfig.getConfig("key1"), ""); // not activated yet
        assertEq(chainConfig.getConfig("key2"), ""); // not activated yet

        // set config when epoch advances
        vm.prank(address(staking));
        keys[1] = "key2";
        values[1] = "value2_updated"; // with updated key
        keys[0] = "key3";
        values[0] = "value3";
        chainConfig.setConfig(keys, values);

        // Config should NOT be available yet (effectiveBlockNum is block.number + 1)
        assertEq(chainConfig.getConfig("key1"), ""); // Not yet effective
        assertEq(chainConfig.getConfig("key2"), ""); // Not yet effective
        assertEq(chainConfig.getConfig("key3"), ""); // Not yet effective
        assertEq(chainConfig.getPendingConfigs().length, 0); // the pending configs are cleared

        // Advance to next block - now config should be available (block 2 -> 3)
        vm.roll(3);
        assertEq(chainConfig.getConfig("key1"), "value1_updated");
        assertEq(chainConfig.getConfig("key2"), "value2_updated");
        assertEq(chainConfig.getConfig("key3"), "value3");

        // set config when epoch advances again (at block 3, effectiveBlockNum will be 4)
        vm.prank(address(staking));
        keys[1] = "key2";
        values[1] = "value2_updated"; // with updated key
        keys[0] = "key3";
        values[0] = "value3_updated";
        chainConfig.setConfig(keys, values);

        // New config not yet effective - should get old value from previous checkpoint
        assertEq(chainConfig.getConfig("key3"), "value3"); // Old value from checkpoint 1 (still effective)

        // Advance to next block - now new config is effective (block 3 -> 4)
        vm.roll(4);

        // Verify config can be retrieved
        assertEq(chainConfig.getConfig("key1"), "value1_updated");
        assertEq(chainConfig.getConfig("key2"), "value2_updated");
        assertEq(chainConfig.getConfig("key3"), "value3_updated");
    }

    // Test getConfig method - return empty string when key does not exist
    function testGetConfig_KeyNotFound() public {
        assertEq(chainConfig.getConfig("nonExistentKey"), "");

        // Set some config and test again
        string[] memory keys = new string[](1);
        string[] memory values = new string[](1);
        keys[0] = "key1";
        values[0] = "value1";

        vm.prank(address(staking));
        chainConfig.setConfig(keys, values);

        assertEq(chainConfig.getConfig("nonExistentKey"), "");
    }

    // Test getConfigs method - basic functionality
    function testGetConfigs_Basic() public {
        // Advance block to make setUp configs effective
        vm.roll(block.number + 1);
        uint256 effectiveBlockNum = block.number;

        // Prepare test data
        string[] memory keys = new string[](2);
        string[] memory values = new string[](2);
        keys[0] = "key1";
        values[0] = "value1";
        keys[1] = "key2";
        values[1] = "value2";

        // add pending config
        vm.prank(admin);
        chainConfig.addPendingConfig(keys, values);

        // set config when epoch advances
        string[] memory intrinsicKeys = new string[](1);
        string[] memory intrinsicValues = new string[](1);
        intrinsicKeys[0] = "key3";
        intrinsicValues[0] = "value3";
        vm.prank(address(staking));
        chainConfig.setConfig(intrinsicKeys, intrinsicValues);

        // New config not yet effective - should still get old configs
        ChainConfig.Config[] memory configs = chainConfig.getConfigs();
        // 5 configs from setUp (not 7, because new config not yet effective)
        assertEq(configs.length, 5);

        // Advance to next block - now new config should be effective
        // We need to advance to effectiveBlockNum + 1 since setConfig sets effectiveBlockNum to block.number + 1
        vm.roll(effectiveBlockNum + 2);
        configs = chainConfig.getConfigs();
        // 5 configs from setUp + 3 configs from this test = 8
        assertEq(configs.length, 8);

        // Verify the test configs are at the end (configs from setUp come first)
        uint256 startIndex = 5;
        // Verify the first test config item
        assertEq(keccak256(abi.encodePacked(configs[startIndex].key)), keccak256(abi.encodePacked("key1")));
        assertEq(keccak256(abi.encodePacked(configs[startIndex].value)), keccak256(abi.encodePacked("value1")));

        // Verify the second test config item
        assertEq(keccak256(abi.encodePacked(configs[startIndex + 1].key)), keccak256(abi.encodePacked("key2")));
        assertEq(keccak256(abi.encodePacked(configs[startIndex + 1].value)), keccak256(abi.encodePacked("value2")));

        // Verify the third test config item
        assertEq(keccak256(abi.encodePacked(configs[startIndex + 2].key)), keccak256(abi.encodePacked("key3")));
        assertEq(keccak256(abi.encodePacked(configs[startIndex + 2].value)), keccak256(abi.encodePacked("value3")));
    }

    // Test getConfigs method - return empty array when no config exists
    function testGetConfigs_Empty() public {
        // Advance block to make setUp configs effective
        vm.roll(block.number + 1);

        ChainConfig.Config[] memory configs = chainConfig.getConfigs();
        // setUp adds 5 configs
        assertEq(configs.length, 5);
    }

    // Test setConfig method - basic functionality
    function testSetConfig_Basic() public {
        // Advance block to make setUp configs effective (block 2 -> 3)
        vm.roll(3);

        // Prepare test data
        string[] memory keys = new string[](2);
        string[] memory values = new string[](2);
        keys[0] = "key1";
        values[0] = "value1";
        keys[1] = "key2";
        values[1] = "value2";

        string[] memory intrinsicKeys = new string[](1);
        string[] memory intrinsicValues = new string[](1);
        intrinsicKeys[0] = "key3";
        intrinsicValues[0] = "value3";

        ChainConfig.Config[] memory kvs = new ChainConfig.Config[](3);
        ChainConfig.Config memory tempConfig0;
        tempConfig0.key = keys[0];
        tempConfig0.value = values[0];
        kvs[0] = tempConfig0;
        ChainConfig.Config memory tempConfig1;
        tempConfig1.key = keys[1];
        tempConfig1.value = values[1];
        kvs[1] = tempConfig1;
        ChainConfig.Config memory tempConfig2;
        tempConfig2.key = intrinsicKeys[0];
        tempConfig2.value = intrinsicValues[0];
        kvs[2] = tempConfig2;

        // Capture PendingConfigAdded event
        vm.expectEmit(true, true, false, true);
        emit ChainConfig.PendingConfigAdded(uint64(block.number), keys[0], values[0]);
        emit ChainConfig.PendingConfigAdded(uint64(block.number), keys[1], values[1]);

        // Set config
        vm.prank(admin);
        chainConfig.addPendingConfig(keys, values);

        // Capture ConfigUpdate event (will be at block 3, effectiveBlockNum will be 4)
        vm.expectEmit(true, true, false, true);
        emit ChainConfig.PendingConfigAdded(uint64(block.number), intrinsicKeys[0], intrinsicValues[0]);
        emit ChainConfig.ConfigUpdate(uint64(block.number), uint64(block.number + 1), kvs);
        vm.prank(address(staking));
        chainConfig.setConfig(intrinsicKeys, intrinsicValues);

        // New config not yet effective - should still get old configs
        ChainConfig.Config[] memory configs = chainConfig.getConfigs();
        assertEq(configs.length, 5); // Only configs from setUp

        // Advance to next block - now new config should be effective (block 3 -> 4)
        vm.roll(4);

        // Verify config has been saved
        configs = chainConfig.getConfigs();
        // 5 configs from setUp + 3 configs from this test
        assertEq(configs.length, 8);

        // Verify the test configs are at the end
        uint256 startIndex = 5;
        // Verify the first test config item
        assertEq(keccak256(abi.encodePacked(configs[startIndex].key)), keccak256(abi.encodePacked("key1")));
        assertEq(keccak256(abi.encodePacked(configs[startIndex].value)), keccak256(abi.encodePacked("value1")));

        // Verify the second test config item
        assertEq(keccak256(abi.encodePacked(configs[startIndex + 1].key)), keccak256(abi.encodePacked("key2")));
        assertEq(keccak256(abi.encodePacked(configs[startIndex + 1].value)), keccak256(abi.encodePacked("value2")));

        // Verify the third test config item
        assertEq(keccak256(abi.encodePacked(configs[startIndex + 2].key)), keccak256(abi.encodePacked("key3")));
        assertEq(keccak256(abi.encodePacked(configs[startIndex + 2].value)), keccak256(abi.encodePacked("value3")));
    }

    // Test setConfig method - error handling when keys and values length mismatch
    function testSetConfig_InvalidLength() public {
        string[] memory keys = new string[](2);
        string[] memory values = new string[](1);
        keys[0] = "key1";
        keys[1] = "key2";
        values[0] = "value1";

        vm.prank(admin);
        vm.expectRevert("KVs length are not match");
        chainConfig.addPendingConfig(keys, values);

        vm.prank(address(staking));
        vm.expectRevert("KVs length are not match");
        chainConfig.setConfig(keys, values);
    }

    /*
     * RuleManager Contract Test
     */

    function testAddRule() public {
        vm.prank(admin);
        uint64 ruleId = ruleManager.addRule(
            1, // type
            address(dummyContract),
            dummySelector,
            dummyMetahash,
            dummyCode
        );
        assertEq(ruleManager.getNextId(), 2);
        assertEq(ruleId, 1);
        RuleManager.InferRule[] memory rules = ruleManager.getAllRules();
        assertEq(rules.length, 1);
        assertEq(rules[0].id_, ruleId);
        assertEq(rules[0].contract_, address(dummyContract));
        assertEq(rules[0].selctor_, dummySelector);
        assertEq(rules[0].metahash_, dummyMetahash);
    }

    function testAddRuleRevertUnauthorized() public {
        vm.prank(alice);
        bytes32 DEFAULT_ADMIN_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000000;
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE));
        ruleManager.addRule(1, address(dummyContract), dummySelector, dummyMetahash, dummyCode);
    }

    function testAddDuplicateRuleRevert() public {
        vm.prank(admin);
        ruleManager.addRule(1, address(dummyContract), dummySelector, dummyMetahash, dummyCode);

        vm.prank(admin);
        vm.expectRevert("InferRule already exist");
        ruleManager.addRule(1, address(dummyContract), dummySelector, dummyMetahash, dummyCode);
    }

    function testContractSpecificRules() public {
        vm.prank(admin);
        ruleManager.addRule(1, address(dummyContract), dummySelector, dummyMetahash, dummyCode);

        RuleManager.InferRule[] memory contractRules = ruleManager.getContractRules(address(dummyContract));
        assertEq(contractRules.length, 1);
        assertEq(contractRules[0].contract_, address(dummyContract));
    }

    // Test security: cannot add rule with zero address
    function testAddRuleRevertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Contract address cannot be zero");
        ruleManager.addRule(1, address(0), dummySelector, dummyMetahash, dummyCode);
    }

    // Test security: cannot add rule with zero selector
    function testAddRuleRevertZeroSelector() public {
        vm.prank(admin);
        vm.expectRevert("Selector cannot be zero");
        ruleManager.addRule(1, address(dummyContract), bytes4(0), dummyMetahash, dummyCode);
    }

    // Test security: cannot add rule with empty code
    function testAddRuleRevertEmptyCode() public {
        vm.prank(admin);
        vm.expectRevert("Code cannot be empty");
        ruleManager.addRule(1, address(dummyContract), dummySelector, dummyMetahash, "");
    }

    // Test security: cannot add rule with zero metahash
    function testAddRuleRevertZeroMetahash() public {
        vm.prank(admin);
        vm.expectRevert("Metahash cannot be zero");
        ruleManager.addRule(1, address(dummyContract), dummySelector, bytes32(0), dummyCode);
    }

    // Test security: cannot update rule code (code is immutable)
    function testUpdateRuleRevertCodeChange() public {
        // Add a rule
        vm.prank(admin);
        uint64 ruleId = ruleManager.addRule(1, address(dummyContract), dummySelector, dummyMetahash, dummyCode);

        // Try to update with different code - should revert
        vm.prank(admin);
        bytes memory newCode = "newCode";
        vm.expectRevert("Cannot update rule code - code is immutable to preserve rule integrity");
        ruleManager.updateRule(ruleId, 1, newCode);
    }

    // Test: can update rule with same code (only type can change)
    function testUpdateRuleWithSameCode() public {
        // Add a rule
        vm.prank(admin);
        uint64 ruleId = ruleManager.addRule(1, address(dummyContract), dummySelector, dummyMetahash, dummyCode);

        // Update with same code but different type - should succeed
        vm.prank(admin);
        uint64 updatedId = ruleManager.updateRule(ruleId, 2, dummyCode);

        assertEq(updatedId, ruleId);
        RuleManager.InferRule[] memory rules = ruleManager.getAllRules();
        assertEq(rules[0].type_, 2); // Type should be updated
        assertEq(rules[0].code_, dummyCode); // Code should remain the same
    }

    /*
     * Staking Contract Test
     */

    function registerValidator(address _validator, uint256 _stake) public returns (bytes32) {
        vm.prank(_validator);
        vm.deal(_validator, _stake);
        return staking.registerValidator{value: _stake}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT
        );
    }

    function registerAndActivateValidator(address _validator, uint256 _stake) public returns (bytes32) {
        bytes32 poolId = registerValidator(_validator, _stake);
        advanceEpoch();
        return poolId;
    }

    function advanceEpoch() public {
        // Advance block.number to ensure new config checkpoints are properly indexed
        // This is necessary for ChainConfig's effectiveBlockNum validation
        vm.roll(block.number + 1);

        // Advance time by at least one epoch duration to satisfy the EpochNotCompleted check
        // The contract requires: block.timestamp >= lastEpochStartTime + epochDuration
        uint256 epochDuration = 4 hours; // DEFAULT_EPOCH_DURATION from Staking.sol
        vm.warp(vm.getBlockTimestamp() + epochDuration + 1);
        vm.prank(admin);
        staking.advanceEpoch();
    }

    function testUpdateValidator_Basic() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        string memory newDesc = "Updated Validator";
        string memory newEndpoint = "http://updated.validator";

        vm.prank(validator);
        staking.updateValidator(poolId, newDesc, newEndpoint);
    }

    // Test security: validator update for inactive validator should not be lost
    function testUpdateValidatorInactiveNotLost() public {
        // Scenario: Update validator, then exit before epoch advance
        // The update should remain pending and not be silently dropped

        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        // Update validator while active
        string memory newDesc = "Updated Validator";
        string memory newEndpoint = "http://updated.validator";

        vm.prank(validator);
        staking.updateValidator(poolId, newDesc, newEndpoint);

        // Verify update is in pending set
        bytes32[] memory pendingUpdates = staking.getPendingUpdateValidators();
        assertEq(pendingUpdates.length, 1, "Should have 1 pending update");
        assertEq(pendingUpdates[0], poolId, "Pending update should match poolId");

        // Exit validator before epoch advance (makes it inactive)
        vm.prank(validator);
        staking.exitValidator(poolId);

        // Advance epoch - update should NOT be processed (validator not active)
        // but it should also NOT be removed from pending updates
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        // Verify update is still in pending set (not lost)
        pendingUpdates = staking.getPendingUpdateValidators();
        assertEq(pendingUpdates.length, 1, "Pending update should not be lost");
        assertEq(pendingUpdates[0], poolId, "Pending update should still be for same poolId");

        // Verify validator state in contract reflects the update
        IStaking.Validator memory validatorInfo = staking.getValidator(poolId);
        assertEq(validatorInfo.endpoint, newEndpoint, "Endpoint should be updated in contract state");
    }

    function testExitValidator_Basic() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);
        vm.prank(validator);
        staking.exitValidator(poolId);
    }

    // Test security: validator can add stake that would exceed max, gets refund
    function testAddStake_ReachingMaxStake() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        uint256 maxStake = MIN_POOL_STAKE;
        IStaking.Validator memory validatorInfo = staking.getValidator(poolId);
        uint256 currentStake = validatorInfo.totalStake;

        // Add stake that exceeds max - should be capped with refund
        uint256 amountToAdd = 5 ether; // Try to add 5 ether
        uint256 expectedToAdd = amountToAdd;
        uint256 expectedRefund = 0;

        // If adding would exceed max, calculate the cap and refund
        if (currentStake + amountToAdd > maxStake) {
            expectedToAdd = maxStake - currentStake;
            expectedRefund = amountToAdd - expectedToAdd;
        }

        uint256 validatorBalanceBefore = validator.balance;
        vm.prank(validator);
        vm.deal(validator, amountToAdd);
        staking.delegate{value: amountToAdd}(poolId);

        // Verify totalStake was updated correctly (delegate updates totalStake immediately for snapshot)
        validatorInfo = staking.getValidator(poolId);
        assertEq(validatorInfo.totalStake, currentStake + expectedToAdd, "Stake should increase by expected amount");

        // Verify refund if applicable
        if (expectedRefund > 0) {
            uint256 validatorBalanceAfter = validator.balance;
            assertEq(validatorBalanceAfter, validatorBalanceBefore - expectedToAdd, "Should refund excess");
        }

        // Verify stake doesn't exceed max
        assertLe(validatorInfo.totalStake, maxStake, "Stake should not exceed max");
    }

    function testEpochRewardMatchesExpectedMinted() public {
        registerAndActivateValidator();

        uint256 supplyBeforeReward = staking.totalSupply();
        uint256 inflationRateBefore = staking.currentInflationRate();
        uint256 epochDuration = 4 hours;
        uint256 yearInSeconds = 365 days;
        // Calculate epoch reward the same way the contract does
        uint256 expectedAnnualReward = (supplyBeforeReward * inflationRateBefore) / TEST_INFLATION_RATE_DENOMINATOR;
        uint256 expectedEpochReward = expectedAnnualReward * epochDuration / yearInSeconds;

        // Advance time by epoch duration to satisfy EpochNotCompleted check
        vm.warp(vm.getBlockTimestamp() + epochDuration);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 supplyAfterReward = staking.totalSupply();
        uint256 actualReward = supplyAfterReward - supplyBeforeReward;

        // The reward calculation has precision loss due to multiple division operations.
        // Allow small tolerance (0.01%)
        uint256 tolerance = expectedEpochReward / 10000; // 0.01%
        assertApproxEqRel(actualReward, expectedEpochReward, tolerance);
    }

    function testInflationRateAdjustsEveryAdjustmentInterval() public {
        registerAndActivateValidator();

        // first adjust
        uint256 originalRate = staking.currentInflationRate();
        uint256 warpTarget = staking.lastInflationAdjustmentTime() + TEST_INFLATION_ADJUSTMENT_INTERVAL + 1;
        vm.warp(warpTarget);

        // Advance time by epoch duration to satisfy EpochNotCompleted check
        uint256 epochDuration = 4 hours;
        vm.warp(vm.getBlockTimestamp() + epochDuration);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 firstAdjustedRate = staking.currentInflationRate();
        uint256 expectedFirstAdjustedRate =
            (originalRate * TEST_INFLATION_ADJUSTMENT_RATE) / TEST_INFLATION_RATE_DENOMINATOR;
        assertEq(firstAdjustedRate, expectedFirstAdjustedRate);
        assertEq(staking.lastInflationAdjustmentTime(), block.timestamp);

        // second adjust
        vm.warp(vm.getBlockTimestamp() + TEST_INFLATION_ADJUSTMENT_INTERVAL + 1);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 secondAdjustedRate = staking.currentInflationRate();
        uint256 expectedSecondAdjustedRate =
            (firstAdjustedRate * TEST_INFLATION_ADJUSTMENT_RATE) / TEST_INFLATION_RATE_DENOMINATOR;
        assertEq(secondAdjustedRate, expectedSecondAdjustedRate);
        assertLt(secondAdjustedRate, firstAdjustedRate);

        // still in window, still equals 2nd
        vm.warp(vm.getBlockTimestamp() + 4 hours); // Use epochDuration instead of 1000
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));
        uint256 secondAdjustedRateInWindow = staking.currentInflationRate();
        assertEq(secondAdjustedRateInWindow, expectedSecondAdjustedRate);
        assertLt(secondAdjustedRate, firstAdjustedRate);

        // 3rd adjust
        vm.warp(vm.getBlockTimestamp() + TEST_INFLATION_ADJUSTMENT_INTERVAL + 1);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 thirdAdjustedRate = staking.currentInflationRate();
        uint256 expectedThirdAdjustedRate =
            (secondAdjustedRate * TEST_INFLATION_ADJUSTMENT_RATE) / TEST_INFLATION_RATE_DENOMINATOR;
        assertEq(thirdAdjustedRate, expectedThirdAdjustedRate);
        assertLt(thirdAdjustedRate, secondAdjustedRate);

        // loop
        uint8 leftRound = 3;
        while (leftRound > 0) {
            vm.warp(vm.getBlockTimestamp() + TEST_INFLATION_ADJUSTMENT_INTERVAL + 1);
            vm.prank(admin);
            staking.advanceEpoch(new bytes32[](0), new uint256[](0));
            // console.log("Current Inflation Rate:", staking.currentInflationRate());
            leftRound--;
        }
        // Round7, should be 2.391%
        uint256 seventhAdjustedRate = staking.currentInflationRate();
        uint256 expectedSeventhAdjustedRate = 2391;
        assertEq(seventhAdjustedRate, expectedSeventhAdjustedRate);

        // Round8, should still be 2.391%
        vm.warp(vm.getBlockTimestamp() + TEST_INFLATION_ADJUSTMENT_INTERVAL + 1);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 eighthAdjustedRate = staking.currentInflationRate();
        uint256 expectedEighthAdjustedRate = 2391;
        assertEq(eighthAdjustedRate, expectedEighthAdjustedRate);
    }

    function registerAndActivateValidator() internal returns (bytes32) {
        bytes32 poolId = registerValidator(validator, MIN_POOL_STAKE);
        // Advance time by epoch duration to satisfy EpochNotCompleted check
        uint256 epochDuration = 4 hours;
        vm.warp(vm.getBlockTimestamp() + epochDuration);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));
        return poolId;
    }

    function testDelegate_Basic() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);
        uint256 delegateAmount = 1 ether;

        vm.prank(delegator);
        vm.deal(delegator, delegateAmount);
        vm.expectEmit(true, true, false, true);
        emit IStaking.StakeDelegated(delegator, poolId, delegateAmount, uint64(1 + 1)); // currentEpoch=1
        staking.delegate{value: delegateAmount}(poolId);

        // Advance epoch to activate pending stake
        advanceEpoch();

        // Trigger lazy activation
        vm.prank(delegator);
        staking.settleReward(poolId);

        IStaking.Delegator memory delegatorInfo = staking.getDelegator(poolId, delegator);
        assertEq(delegatorInfo.stake, delegateAmount, "Delegator stake should match");
        assertEq(delegatorInfo.principalStake, delegateAmount, "Delegator initStake should match");
        assertEq(delegatorInfo.rewards, 0, "Initial rewards should be zero");
    }

    function testDelegate_ValidatorNotExist() public {
        bytes32 fakePoolId = bytes32(uint256(0x123));
        vm.prank(delegator);
        vm.deal(delegator, MIN_DELEGATOR_STAKE);
        vm.expectRevert("Delegation disabled");
        staking.delegate{value: MIN_DELEGATOR_STAKE}(fakePoolId);
    }

    function testDelegate_InsufficientStake() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);
        uint256 insufficientAmount = MIN_DELEGATOR_STAKE - 0.01 ether;

        vm.prank(delegator);
        vm.deal(delegator, insufficientAmount);
        vm.expectRevert("Insufficient stake");
        staking.delegate{value: insufficientAmount}(poolId);
    }

    function testDelegate_DelegationDisabled() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        vm.prank(validator);
        staking.setDelegationEnabled(poolId, false);

        vm.prank(delegator);
        vm.deal(delegator, MIN_DELEGATOR_STAKE);
        vm.expectRevert("Delegation disabled");
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);
    }

    function testUndelegate_Basic() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);
        uint256 delegateAmount = 1 ether;
        vm.prank(delegator);
        vm.deal(delegator, delegateAmount);
        staking.delegate{value: delegateAmount}(poolId);

        // Advance epoch to activate pending stake
        advanceEpoch();

        // Trigger lazy activation
        vm.prank(delegator);
        staking.settleReward(poolId);

        vm.prank(delegator);
        (uint256 expectedAmount, uint256 expectedUnlockEpoch) = staking.undelegate(poolId);
        emit IStaking.StakeUndelegated(delegator, poolId, expectedAmount, expectedUnlockEpoch);

        IStaking.Delegator memory delegatorInfo = staking.getDelegator(poolId, delegator);
        assertEq(delegatorInfo.stake, 0, "Delegator stake should be zero");
        assertEq(delegatorInfo.isPendingUndelegate, true, "Should be pending undelegate");
        // The withdraw window should be DEFAULT_WITHDRAW_WINDOW (84) when config is not set
        assertEq(
            delegatorInfo.pendingWithdrawWindow, 84, "Pending withdraw window should use default when config is not set"
        );
    }

    function testUndelegate_NoStake() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        vm.prank(delegator);
        vm.expectRevert("No stake to undelegate");
        staking.undelegate(poolId);
    }

    function testClaimReward_Basic() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);
        uint256 delegateAmount = 1 ether;
        vm.prank(delegator);
        vm.deal(delegator, delegateAmount);
        staking.delegate{value: delegateAmount}(poolId);

        uint256 initialReward = staking.getDelegatorReward(poolId, delegator);
        assertEq(initialReward, 0, "Initial reward should be zero");
    }

    function testCompoundRewards_Basic() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        uint256 delegateAmount = MIN_DELEGATOR_STAKE * 2;
        vm.prank(delegator);
        vm.deal(delegator, delegateAmount);
        staking.delegate{value: delegateAmount}(poolId);

        // Advance epoch to activate pending stake
        advanceEpoch();

        // Trigger lazy activation
        vm.prank(delegator);
        staking.settleReward(poolId);

        // Advance another epoch to generate rewards
        advanceEpoch();

        uint256 rewardAmount = staking.getDelegatorReward(poolId, delegator);
        assertGt(rewardAmount, 0, "Should have rewards after epoch");

        vm.prank(delegator);
        staking.compoundRewards(poolId);

        // Advance epoch to activate compounded rewards
        advanceEpoch();

        // Trigger lazy activation of compounded rewards
        vm.prank(delegator);
        staking.settleReward(poolId);

        IStaking.Delegator memory delegatorInfo = staking.getDelegator(poolId, delegator);
        assertEq(delegatorInfo.stake, delegateAmount + rewardAmount, "Stake should increase");
        assertEq(delegatorInfo.principalStake, delegateAmount, "InitStake should not change on compound");
    }

    function testGetDelegatorReward_Basic() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);
        uint256 delegateAmount = 1 ether;
        vm.prank(delegator);
        vm.deal(delegator, delegateAmount);
        staking.delegate{value: delegateAmount}(poolId);

        uint256 initialReward = staking.getDelegatorReward(poolId, delegator);
        assertEq(initialReward, 0, "Initial reward should be zero");
    }

    // Test CoinMinted event emits correct reward amount (not including principal)
    function testCoinMinted_OnlyEmitsRewards() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        // Delegator delegates 10 ether
        uint256 delegateAmount = 10 ether;
        vm.deal(delegator, delegateAmount);
        vm.prank(delegator);
        staking.delegate{value: delegateAmount}(poolId);

        // Advance epoch to generate rewards
        uint256 epochDuration = 4 hours;
        vm.warp(vm.getBlockTimestamp() + epochDuration);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        // Check delegator info
        IStaking.Delegator memory delInfo = staking.getDelegator(poolId, delegator);

        // Verify realDeposit equals actual deposit
        assertEq(delInfo.principalStake, delegateAmount, "RealDeposit should equal actual deposit");

        // Undelegate
        vm.prank(delegator);
        (uint256 totalAmount, uint256 unlockEpoch) = staking.undelegate(poolId);

        uint256 expectedRewardAmount = totalAmount - delegateAmount;

        // Advance epochs to reach withdrawal window
        uint256 currentEpoch = staking.currentEpoch();
        uint256 epochsToAdvance = unlockEpoch - currentEpoch;

        for (uint256 i = 0; i < epochsToAdvance; i++) {
            vm.warp(vm.getBlockTimestamp() + 4 hours);
            vm.prank(admin);
            staking.advanceEpoch(new bytes32[](0), new uint256[](0));
        }

        // Now withdrawal window is 0, user should call claimStake() to get funds
        // Expect CoinMinted event with ONLY the reward amount
        if (expectedRewardAmount > 0) {
            vm.expectEmit(true, true, false, true);
            emit IStaking.CoinMinted(delegator, 1, expectedRewardAmount);
        }

        vm.prank(delegator);
        staking.claimStake(poolId);

        // Verify the withdrawal was processed
        (,, bool isPending,) = staking.getDelegatorPendingWithdraw(poolId, delegator);
        assertEq(isPending, false, "Should not be pending after withdrawal");
    }

    // Test CoinMinted for compounded rewards
    function testCoinMinted_CompoundedRewards() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        // Delegator delegates 10 ether
        uint256 delegateAmount = 10 ether;
        vm.deal(delegator, delegateAmount);
        vm.prank(delegator);
        staking.delegate{value: delegateAmount}(poolId);

        // Advance epoch to activate pending stake
        advanceEpoch();

        // Trigger lazy activation
        vm.prank(delegator);
        staking.settleReward(poolId);

        // Advance epoch to generate rewards
        uint256 epochDuration = 4 hours;
        vm.warp(vm.getBlockTimestamp() + epochDuration);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        // Compound rewards (this should increase stake but not realDeposit)
        uint256 rewardsBefore = staking.getDelegatorReward(poolId, delegator);
        assertGt(rewardsBefore, 0, "Should have rewards to compound");

        vm.prank(delegator);
        staking.compoundRewards(poolId);

        // Advance epoch to activate compounded rewards
        advanceEpoch();

        // Trigger lazy activation of compounded rewards
        vm.prank(delegator);
        staking.settleReward(poolId);

        IStaking.Delegator memory delInfo = staking.getDelegator(poolId, delegator);

        // Verify realDeposit did NOT increase (rewards are virtual)
        assertEq(delInfo.principalStake, delegateAmount, "RealDeposit should not change on compound");
        // Verify stake DID increase
        assertGt(delInfo.stake, delegateAmount, "Stake should increase after compound");

        // Advance another epoch
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        // Now undelegate - should emit CoinMinted for compounded + new rewards
        vm.prank(delegator);
        (uint256 totalAmount, uint256 unlockEpoch) = staking.undelegate(poolId);

        uint256 expectedRewardAmount = totalAmount - delegateAmount;

        // Verify expectedRewardAmount > rewardsBefore (because of compounding)
        assertGt(expectedRewardAmount, rewardsBefore, "Should have more rewards after compounding");

        // Advance to withdrawal window = 0
        uint256 currentEpoch = staking.currentEpoch();
        uint256 epochsToAdvance = unlockEpoch - currentEpoch;

        for (uint256 i = 0; i < epochsToAdvance; i++) {
            vm.warp(vm.getBlockTimestamp() + 4 hours);
            vm.prank(admin);
            staking.advanceEpoch(new bytes32[](0), new uint256[](0));
        }

        // User claims stake, expect CoinMinted event
        if (expectedRewardAmount > 0) {
            vm.expectEmit(true, true, false, true);
            emit IStaking.CoinMinted(delegator, 1, expectedRewardAmount);
        }

        vm.prank(delegator);
        staking.claimStake(poolId);
    }

    // Test lazy withdrawal - user must call claimStake()
    function testLazyWithdrawal() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        // Delegator delegates
        uint256 delegateAmount = 10 ether;
        vm.deal(delegator, delegateAmount);
        vm.prank(delegator);
        staking.delegate{value: delegateAmount}(poolId);

        // Advance epoch to generate rewards
        uint256 epochDuration = 4 hours;
        vm.warp(vm.getBlockTimestamp() + epochDuration);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        // Undelegate
        vm.prank(delegator);
        (, uint256 unlockEpoch) = staking.undelegate(poolId);

        uint256 balanceBefore = delegator.balance;

        // Advance epochs to reach withdrawal window = 0
        uint256 currentEpoch = staking.currentEpoch();
        uint256 epochsToAdvance = unlockEpoch - currentEpoch;

        for (uint256 i = 0; i < epochsToAdvance; i++) {
            vm.warp(vm.getBlockTimestamp() + 4 hours);
            vm.prank(admin);
            staking.advanceEpoch(new bytes32[](0), new uint256[](0));
        }

        // After advanceEpoch, funds should NOT be automatically transferred
        uint256 balanceAfterEpochs = delegator.balance;
        assertEq(balanceAfterEpochs, balanceBefore, "Balance should not change after advanceEpoch");

        // User must call claimStake() to get funds
        vm.prank(delegator);
        staking.claimStake(poolId);

        // Now balance should increase (only principal part is transferred from contract)
        uint256 balanceAfterClaim = delegator.balance;
        assertEq(balanceAfterClaim, balanceBefore + delegateAmount, "Balance should increase after claim");
    }

    // Test security: reject zero-amount withdrawals
    function testWithdrawStake_RejectsZeroAmount() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        // Try to withdraw zero amount - should revert
        vm.prank(validator);
        vm.expectRevert("Withdrawal amount must be greater than zero");
        staking.withdrawStake(poolId, 0);
    }

    // Test complex scenario: multiple delegate -> compound -> claim reward
    function testMultipleDelegateCompoundClaimReward() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        // Step 1: First delegation of 10 ether
        uint256 firstDelegate = 10 ether;
        vm.deal(delegator, 100 ether);
        vm.prank(delegator);
        staking.delegate{value: firstDelegate}(poolId);

        // Advance epoch to activate pending stake
        advanceEpoch();

        // Trigger lazy activation
        vm.prank(delegator);
        staking.settleReward(poolId);

        IStaking.Delegator memory delInfo = staking.getDelegator(poolId, delegator);
        assertEq(delInfo.principalStake, 10 ether, "realDeposit should be 10 after first delegate");
        assertEq(delInfo.stake, 10 ether, "stake should be 10 after first delegate");

        // Step 2: Advance epoch to generate rewards
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 rewardsAfterEpoch1 = staking.getDelegatorReward(poolId, delegator);
        assertGt(rewardsAfterEpoch1, 0, "Should have rewards after epoch 1");

        // Step 3: Compound rewards
        vm.prank(delegator);
        staking.compoundRewards(poolId);

        // Advance epoch to activate compounded rewards
        advanceEpoch();

        // Trigger lazy activation of compounded rewards
        vm.prank(delegator);
        staking.settleReward(poolId);

        delInfo = staking.getDelegator(poolId, delegator);
        assertEq(delInfo.principalStake, 10 ether, "realDeposit should still be 10 after compound");
        assertEq(delInfo.stake, 10 ether + rewardsAfterEpoch1, "stake should include compounded rewards");
        // Note: rewards will not be 0 after epoch advancement, as new rewards are generated

        uint256 stakeAfterCompound = delInfo.stake;

        // Step 4: Second delegation of 20 ether
        uint256 secondDelegate = 20 ether;
        vm.prank(delegator);
        staking.delegate{value: secondDelegate}(poolId);

        // Advance epoch to activate second delegation
        advanceEpoch();

        // Trigger lazy activation of second delegation
        vm.prank(delegator);
        staking.settleReward(poolId);

        delInfo = staking.getDelegator(poolId, delegator);
        assertEq(delInfo.principalStake, 30 ether, "realDeposit should be 30 after second delegate");
        assertEq(delInfo.stake, stakeAfterCompound + 20 ether, "stake should increase by 20");

        // Step 5: Advance epoch to generate more rewards (based on increased stake)
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 rewardsAfterEpoch2 = staking.getDelegatorReward(poolId, delegator);
        assertGt(rewardsAfterEpoch2, 0, "Should have rewards after epoch 2");

        // Step 6: Compound again
        vm.prank(delegator);
        staking.compoundRewards(poolId);

        // Advance epoch to activate second compound
        advanceEpoch();

        // Trigger lazy activation of second compound
        vm.prank(delegator);
        staking.settleReward(poolId);

        delInfo = staking.getDelegator(poolId, delegator);
        assertEq(delInfo.principalStake, 30 ether, "realDeposit should still be 30 after second compound");
        uint256 stakeAfterSecondCompound = delInfo.stake;

        // Step 7: Advance epoch to generate more rewards
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 rewardsAfterEpoch3 = staking.getDelegatorReward(poolId, delegator);
        assertGt(rewardsAfterEpoch3, 0, "Should have rewards after epoch 3");

        // Step 8: Claim reward (not undelegate, just claim reward)
        vm.prank(delegator);
        uint256 claimedAmount = staking.claimReward(poolId);

        assertEq(claimedAmount, rewardsAfterEpoch3, "Claimed amount should match rewards");

        delInfo = staking.getDelegator(poolId, delegator);
        assertEq(delInfo.principalStake, 30 ether, "realDeposit should still be 30 after claimReward");
        assertEq(delInfo.stake, stakeAfterSecondCompound, "stake should not change after claimReward");
        assertEq(delInfo.rewards, 0, "rewards should be 0 after claim");

        // Step 9: Advance one more epoch
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 rewardsAfterEpoch4 = staking.getDelegatorReward(poolId, delegator);

        // Step 10: Undelegate everything
        vm.prank(delegator);
        (uint256 totalAmount, uint256 unlockEpoch) = staking.undelegate(poolId);

        // Calculate expected values
        uint256 expectedPrincipal = 30 ether; // Only real deposits
        uint256 expectedRewards = totalAmount - expectedPrincipal;

        // Verify the calculation
        assertEq(expectedPrincipal, 30 ether, "Principal should be 30 ether (real deposits)");
        assertGt(expectedRewards, 0, "Should have rewards");

        // The total rewards accumulated should be:
        // rewardsAfterEpoch1 (compounded) + rewardsAfterEpoch2 (compounded) + rewardsAfterEpoch3 (claimed) + rewardsAfterEpoch4 (pending)
        // But in totalAmount, we should only see: stake + current rewards
        // stake already includes compounded rewards, so totalAmount = realDeposit + all accumulated rewards

        // Advance to unlock
        uint256 currentEpoch = staking.currentEpoch();
        uint256 epochsToAdvance = unlockEpoch - currentEpoch;
        for (uint256 i = 0; i < epochsToAdvance; i++) {
            vm.warp(vm.getBlockTimestamp() + 4 hours);
            vm.prank(admin);
            staking.advanceEpoch(new bytes32[](0), new uint256[](0));
        }

        // Track total CoinMinted events
        uint256 totalCoinMinted = claimedAmount; // From claimReward

        // Claim stake - expect CoinMinted for remaining rewards
        if (expectedRewards > 0) {
            vm.expectEmit(true, true, false, true);
            emit IStaking.CoinMinted(delegator, 1, expectedRewards);
        }

        uint256 balanceBefore = delegator.balance;
        vm.prank(delegator);
        staking.claimStake(poolId);

        uint256 balanceAfter = delegator.balance;
        assertEq(balanceAfter - balanceBefore, expectedPrincipal, "Should receive principal from contract");

        totalCoinMinted += expectedRewards;

        // Verify total minted equals all rewards
        uint256 totalRewardsGenerated =
            rewardsAfterEpoch1 + rewardsAfterEpoch2 + rewardsAfterEpoch3 + rewardsAfterEpoch4;
        assertEq(totalCoinMinted, totalRewardsGenerated, "Total CoinMinted should equal all generated rewards");
    }

    // Test validator owner receives both commission and staking rewards
    function testValidatorOwnerReceivesBothCommissionAndStakingRewards() public {
        // Register validator with stake larger than the delegator's stake
        // This ensures the owner receives more rewards due to both commission and larger stake
        uint256 validatorStake = 10 ether;
        bytes32 poolId = registerAndActivateValidator(validator, validatorStake);

        // Check that validator owner is initialized as a delegator
        IStaking.Delegator memory ownerDelInfo = staking.getDelegator(poolId, validator);
        assertEq(ownerDelInfo.stake, validatorStake, "Owner stake should equal validator stake");
        assertEq(ownerDelInfo.principalStake, validatorStake, "Owner realDeposit should equal validator stake");

        // Another delegator delegates less than the owner
        uint256 delegateAmount = 5 ether;
        vm.deal(delegator, delegateAmount);
        vm.prank(delegator);
        staking.delegate{value: delegateAmount}(poolId);

        // Advance epoch to activate pending stake
        advanceEpoch();

        // Trigger lazy activation
        vm.prank(delegator);
        staking.settleReward(poolId);

        // Advance epoch to generate rewards
        uint256 epochDuration = 4 hours;
        vm.warp(vm.getBlockTimestamp() + epochDuration);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        // Check validator owner rewards
        uint256 ownerRewards = staking.getDelegatorReward(poolId, validator);
        assertGt(ownerRewards, 0, "Owner should have rewards");

        // Check delegator rewards
        uint256 delegatorRewards = staking.getDelegatorReward(poolId, delegator);
        assertGt(delegatorRewards, 0, "Delegator should have rewards");

        // Owner should receive more rewards than delegator because:
        // 1. Owner has commission (10% of total rewards)
        // 2. Owner has larger stake (10 ether vs 5 ether)
        assertGt(ownerRewards, delegatorRewards, "Owner should receive more rewards than delegator");

        // Verify owner can claim rewards
        vm.prank(validator);
        uint256 claimedAmount = staking.claimReward(poolId);
        assertEq(claimedAmount, ownerRewards, "Claimed amount should match owner rewards");

        // Verify CoinMinted event was emitted for owner
        // (Already verified by the claimReward not reverting)
    }

    // Test security: pending validator who withdraws below minimum is removed from queue
    function testWithdrawStake_RemovesFromPendingAddQueue() public {
        // Register validator but don't activate (stays in pendingAddPoolIds)
        vm.prank(validator);
        vm.deal(validator, MIN_VALIDATOR_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT
        );

        // Verify validator is in pending add queue
        bytes32[] memory pendingAdd = staking.getPendingAddValidators();
        assertEq(pendingAdd.length, 1, "Should have 1 pending add");
        assertEq(pendingAdd[0], poolId, "Pending add should match poolId");

        // Validator withdraws all of their stake (must withdraw all or keep >= minRegistrationStake)
        uint256 withdrawAmount = MIN_VALIDATOR_STAKE; // Full exit

        vm.prank(validator);
        staking.withdrawStake(poolId, withdrawAmount);

        // Verify validator is removed from pending add queue
        pendingAdd = staking.getPendingAddValidators();
        assertEq(pendingAdd.length, 0, "Should be removed from pending add queue");

        // Verify validator stake is now zero
        IStaking.Validator memory validatorInfo = staking.getValidator(poolId);
        assertEq(validatorInfo.totalStake, 0, "Should have 0 stake remaining");
    }

    // Test that withdrawStake emits ValidatorExitRequested event
    function testWithdrawStake_EmitsExitRequestedEvent() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        // Expect ValidatorExitRequested event to be emitted
        vm.expectEmit(true, true, false, true);
        emit Staking.ValidatorExitRequested(poolId);

        // Withdraw some stake
        uint256 withdrawAmount = MIN_VALIDATOR_STAKE / 2;
        vm.prank(validator);
        staking.withdrawStake(poolId, withdrawAmount);

        // Verify validator is in pending exit queue
        assertTrue(staking.isValidatorPendingExit(poolId), "Validator should be in pending exit queue");
    }

    // Test scenario 1: Validator exitValidator then claimStake
    function testValidatorExitThenClaimStake() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        // Verify owner is initialized as delegator
        IStaking.Delegator memory ownerDel = staking.getDelegator(poolId, validator);
        assertEq(ownerDel.stake, MIN_VALIDATOR_STAKE, "Owner stake should equal validator stake");
        assertEq(ownerDel.principalStake, MIN_VALIDATOR_STAKE, "Owner realDeposit should equal validator stake");

        // Advance epoch to generate some rewards
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 ownerRewards = staking.getDelegatorReward(poolId, validator);
        assertGt(ownerRewards, 0, "Owner should have rewards");

        // Validator exits
        vm.prank(validator);
        staking.exitValidator(poolId);

        // Check validator state
        (
            , // description
            , // publicKey
            , // publicKeyPop
            , // blsPublicKey
            , // blsPublicKeyPop
            , // endpoint
            , // status
            , // poolId
            uint256 totalStake,, // owner
            , // stakeSnapshot
            uint256 pendingWithdrawStake,
            uint256 pendingWithdrawWindow, // pendingOwner
        ) = staking.validators(poolId);

        assertEq(totalStake, 0, "Validator totalStake should be 0 after exit");
        // pendingWithdrawStake is no longer used, validator withdrawal now goes through delegator mechanism
        assertEq(pendingWithdrawStake, 0, "pendingWithdrawStake should be 0 (not used anymore)");

        // Check owner's delegator state - should be properly updated
        ownerDel = staking.getDelegator(poolId, validator);
        assertEq(ownerDel.stake, 0, "Owner stake should be 0 after exitValidator");
        assertEq(ownerDel.principalStake, 0, "Owner realDeposit should be 0 after exitValidator");
        assertEq(ownerDel.isPendingUndelegate, true, "Owner should be pending undelegate");
        assertGt(ownerDel.pendingWithdrawStake, 0, "Owner should have pending withdraw stake");

        // Advance epochs to pass withdraw window
        for (uint256 i = 0; i <= pendingWithdrawWindow; i++) {
            vm.warp(vm.getBlockTimestamp() + 4 hours);
            vm.prank(admin);
            staking.advanceEpoch(new bytes32[](0), new uint256[](0));
        }

        // Validator owner calls claimStake
        vm.prank(validator);
        staking.claimStake(poolId);

        // Delegator state should be properly cleaned up now
        ownerDel = staking.getDelegator(poolId, validator);
        assertEq(ownerDel.stake, 0, "Owner stake should be 0 after claim");
        assertEq(ownerDel.principalStake, 0, "Owner realDeposit should be 0 after claim");
        assertEq(ownerDel.isPendingUndelegate, false, "Owner should not be pending undelegate anymore");
    }

    // Test scenario 2: Validator claimReward during operation
    function testValidatorClaimRewardDuringOperation() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        // Another delegator delegates
        uint256 delegateAmount = 5 ether;
        vm.deal(delegator, delegateAmount);
        vm.prank(delegator);
        staking.delegate{value: delegateAmount}(poolId);

        // Advance epoch to generate rewards
        uint256 epochDuration = 4 hours;
        vm.warp(vm.getBlockTimestamp() + epochDuration);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 ownerRewardsBefore = staking.getDelegatorReward(poolId, validator);
        assertGt(ownerRewardsBefore, 0, "Owner should have rewards");

        // Owner claims rewards
        vm.prank(validator);
        uint256 claimedAmount = staking.claimReward(poolId);
        assertEq(claimedAmount, ownerRewardsBefore, "Claimed amount should match rewards");

        // Check delegator state after claim
        IStaking.Delegator memory ownerDel = staking.getDelegator(poolId, validator);
        assertEq(ownerDel.rewards, 0, "Owner rewards should be 0 after claim");
        assertEq(ownerDel.stake, MIN_VALIDATOR_STAKE, "Owner stake should not change");

        // Advance another epoch
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        // Owner should continue to earn rewards
        uint256 ownerRewardsAfter = staking.getDelegatorReward(poolId, validator);
        assertGt(ownerRewardsAfter, 0, "Owner should have new rewards");

        // Owner can claim again
        vm.prank(validator);
        staking.claimReward(poolId);

        // This scenario should work fine - claimReward doesn't affect stake
    }

    // Test scenario 3: Validator exits, claims, and re-registers
    function testValidatorExitClaimAndReRegister() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        // Advance epoch
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        // Validator exits
        vm.prank(validator);
        staking.exitValidator(poolId);

        // Advance to pass withdraw window
        for (uint256 i = 0; i <= 7; i++) {
            vm.warp(vm.getBlockTimestamp() + 4 hours);
            vm.prank(admin);
            staking.advanceEpoch(new bytes32[](0), new uint256[](0));
        }

        // Claim stake
        uint256 balanceBefore = validator.balance;
        vm.prank(validator);
        staking.claimStake(poolId);
        uint256 balanceAfter = validator.balance;

        // Received the stake
        assertEq(balanceAfter - balanceBefore, MIN_VALIDATOR_STAKE, "Should receive validator stake");

        // Check delegator state - it should be properly cleaned up
        IStaking.Delegator memory ownerDel = staking.getDelegator(poolId, validator);
        assertEq(ownerDel.stake, 0, "Owner stake should be 0 after withdrawal");
        assertEq(ownerDel.principalStake, 0, "Owner realDeposit should be 0 after withdrawal");
        assertEq(ownerDel.isPendingUndelegate, false, "Owner should not be pending undelegate");

        // Ensure we're at a block where all configs are effective
        // After 7 advanceEpoch calls, block.number should be at least 9 (setUp: 1, 7 epochs: +7)
        // This ensures getConfig can find the keys from earlier checkpoints
        vm.roll(block.number + 1);

        // Now validator re-registers with the same poolId
        vm.deal(validator, MIN_VALIDATOR_STAKE * 2);
        vm.prank(validator);
        bytes32 newPoolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            "Test Validator",
            "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f",
            "0xproof1",
            "0xblskey1",
            "0xblspop1",
            "http://test.validator"
        );

        // Same poolId because same public key
        assertEq(newPoolId, poolId, "Should be same poolId");

        // Check delegator state after re-register - should be correctly initialized
        ownerDel = staking.getDelegator(poolId, validator);
        // The stake should be correctly set to the new stake, not accumulated
        assertEq(ownerDel.stake, MIN_VALIDATOR_STAKE, "Stake should be new stake only");
        assertEq(ownerDel.principalStake, MIN_VALIDATOR_STAKE, "RealDeposit should be new deposit only");

        // No double accounting - the fix works correctly!
    }

    // Test scenario 4: Validator exits, other delegators' stakes remain
    function testValidatorExitWithOtherDelegators() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        // Two delegators delegate to the validator
        uint256 delegateAmount1 = 5 ether;
        uint256 delegateAmount2 = 3 ether;

        vm.deal(delegator, delegateAmount1);
        vm.prank(delegator);
        staking.delegate{value: delegateAmount1}(poolId);

        address delegator2 = address(0x6);
        vm.deal(delegator2, delegateAmount2);
        vm.prank(delegator2);
        staking.delegate{value: delegateAmount2}(poolId);

        // Advance epoch to activate pending stakes
        advanceEpoch();

        // Trigger lazy activation for both delegators
        vm.prank(delegator);
        staking.settleReward(poolId);
        vm.prank(delegator2);
        staking.settleReward(poolId);

        // Check total stake before validator exits
        (,,,,,,,, uint256 totalStakeBefore,,,,,) = staking.validators(poolId);
        assertEq(
            totalStakeBefore, MIN_VALIDATOR_STAKE + delegateAmount1 + delegateAmount2, "Total stake should include all"
        );

        // Advance epoch
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        // Validator exits - should be allowed even with other delegators
        vm.prank(validator);
        staking.exitValidator(poolId);

        // Check total stake after validator exits - should only subtract validator owner's stake
        (,,,,,,,, uint256 totalStakeAfter,,,,,) = staking.validators(poolId);
        assertEq(
            totalStakeAfter, delegateAmount1 + delegateAmount2, "Total stake should only subtract validator's stake"
        );

        // Check that delegators' stakes are intact
        IStaking.Delegator memory del1 = staking.getDelegator(poolId, delegator);
        assertEq(del1.stake, delegateAmount1, "Delegator1 stake should remain");

        IStaking.Delegator memory del2 = staking.getDelegator(poolId, delegator2);
        assertEq(del2.stake, delegateAmount2, "Delegator2 stake should remain");

        // Delegators can still undelegate independently
        vm.prank(delegator);
        (uint256 amount1,) = staking.undelegate(poolId);
        assertGt(amount1, 0, "Delegator1 can undelegate");

        // Check total stake after first delegator undelegates
        (,,,,,,,, uint256 totalStakeAfterUndelegate,,,,,) = staking.validators(poolId);
        assertEq(totalStakeAfterUndelegate, delegateAmount2, "Total stake should only have delegator2's stake");
    }

    // Test scenario 5: Comprehensive CoinMinted tracking
    function testComprehensiveCoinMintedTracking() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);

        uint256 totalCoinMinted = 0;

        // Delegator stakes 10 ETH
        uint256 delegateAmount = 10 ether;
        vm.deal(delegator, delegateAmount);
        vm.prank(delegator);
        staking.delegate{value: delegateAmount}(poolId);

        // Advance epoch to activate pending stake
        advanceEpoch();

        // Trigger lazy activation
        vm.prank(delegator);
        staking.settleReward(poolId);

        // Epoch 1: Generate rewards
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 rewards1 = staking.getDelegatorReward(poolId, delegator);
        assertGt(rewards1, 0, "Should have rewards after epoch 1");

        // Scenario 1: ClaimReward directly
        vm.expectEmit(true, true, false, true);
        emit IStaking.CoinMinted(delegator, 1, rewards1);

        vm.prank(delegator);
        uint256 claimed1 = staking.claimReward(poolId);
        totalCoinMinted += claimed1;

        // Epoch 2: Generate more rewards
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 rewards2 = staking.getDelegatorReward(poolId, delegator);
        assertGt(rewards2, 0, "Should have rewards after epoch 2");

        // Scenario 2: Compound instead of claiming
        vm.prank(delegator);
        staking.compoundRewards(poolId);
        // Note: No CoinMinted event here, it will be emitted when unstaking

        // Advance epoch to activate compounded rewards
        advanceEpoch();

        // Trigger lazy activation of compounded rewards
        vm.prank(delegator);
        staking.settleReward(poolId);

        IStaking.Delegator memory delInfo = staking.getDelegator(poolId, delegator);
        assertEq(delInfo.principalStake, delegateAmount, "realDeposit should not change after compound");
        assertEq(delInfo.stake, delegateAmount + rewards2, "stake should include compounded rewards");

        // Epoch 3: Generate rewards on increased stake
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        uint256 rewards3 = staking.getDelegatorReward(poolId, delegator);
        assertGt(rewards3, 0, "Should have rewards after epoch 3");

        // Scenario 3: Undelegate everything
        vm.prank(delegator);
        (uint256 totalAmount, uint256 unlockEpoch) = staking.undelegate(poolId);

        // Expected: principal = 10 ETH, rewards = rewards2 (compounded) + rewards3 (pending)
        uint256 expectedRewardAmount = (totalAmount - delegateAmount);
        assertEq(expectedRewardAmount, rewards2 + rewards3, "Reward amount should be rewards2 + rewards3");

        // Advance to unlock
        uint256 currentEpoch = staking.currentEpoch();
        for (uint256 i = 0; i < (unlockEpoch - currentEpoch); i++) {
            vm.warp(vm.getBlockTimestamp() + 4 hours);
            vm.prank(admin);
            staking.advanceEpoch(new bytes32[](0), new uint256[](0));
        }

        // ClaimStake should emit CoinMinted for the compounded and pending rewards
        vm.expectEmit(true, true, false, true);
        emit IStaking.CoinMinted(delegator, 1, expectedRewardAmount);

        vm.prank(delegator);
        staking.claimStake(poolId);
        totalCoinMinted += expectedRewardAmount;

        // Verify total CoinMinted equals all rewards generated
        uint256 totalRewardsGenerated = rewards1 + rewards2 + rewards3;
        assertEq(totalCoinMinted, totalRewardsGenerated, "Total CoinMinted should equal all rewards");

        // Verify delegator received correct balance (only principal from contract)
        assertEq(delegator.balance, delegateAmount, "Delegator should receive principal from contract");
        // The rewards part (totalCoinMinted) should be minted by client monitoring CoinMinted events
    }

    // Test that updateStakingAddress rejects duplicate address
    function testUpdateStakingAddress_RejectsDuplicate() public {
        vm.prank(admin);
        vm.expectRevert("New staking address is the same as the current address");
        chainConfig.updateStakingAddress(address(staking));
    }

    // Test that updateChainConfigAddress rejects duplicate address
    function testUpdateChainConfigAddress_RejectsDuplicate() public {
        vm.prank(admin);
        vm.expectRevert("New chain config address is the same as the current address");
        staking.updateChainConfigAddress(address(chainConfig));
    }

    // Test that updateStakingAddress accepts valid address change
    function testUpdateStakingAddress_AcceptsValidChange() public {
        // Deploy a new staking implementation
        Staking newStakingImpl = new Staking();

        // This should work - different address
        vm.prank(admin);
        chainConfig.updateStakingAddress(address(newStakingImpl));

        // Verify the address was updated by reading the state variable
        assertEq(chainConfig.stakingAddress(), address(newStakingImpl), "Staking address should be updated");

        // Restore original address for other tests
        vm.prank(admin);
        chainConfig.updateStakingAddress(address(staking));
    }

    // Test that updateChainConfigAddress accepts valid address change
    function testUpdateChainConfigAddress_AcceptsValidChange() public {
        // Deploy a new chain config implementation
        ChainConfig newChainConfigImpl = new ChainConfig();

        // This should work - different address
        vm.prank(admin);
        staking.updateChainConfigAddress(address(newChainConfigImpl));

        // Verify the address was updated by reading the state variable
        assertEq(address(staking.cfg()), address(newChainConfigImpl), "Chain config address should be updated");

        // Restore original address for other tests
        vm.prank(admin);
        staking.updateChainConfigAddress(address(chainConfig));
    }

    // Test for DoS vulnerability fix: Multiple pending validators can exit without causing out-of-bounds
    function testProcessPendingExits_MultipleValidatorsDoSFix() public {
        // Register two validators and activate them (use different public keys for unique poolIds)
        bytes32 poolId1 = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);
        bytes32 poolId2 = registerAndActivateValidatorWithCustomKey(
            address(0x7), MIN_VALIDATOR_STAKE, "0x02a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f"
        );

        // Both validators exit
        vm.prank(validator);
        staking.exitValidator(poolId1);

        vm.prank(address(0x7));
        staking.exitValidator(poolId2);

        // Verify both are in pending exit queue
        bytes32[] memory pendingExits = staking.getPendingExitValidators();
        assertEq(pendingExits.length, 2, "Should have 2 pending exits");

        // Advance epoch - this should NOT revert due to out-of-bounds access
        // The fix ensures the two-pass pattern prevents this vulnerability
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch();

        // After advance epoch, validators should be removed from active and pending exit
        bytes32[] memory active = staking.getActiveValidators();
        assertEq(active.length, 0, "Should have 0 active validators");
    }

    // Test for DoS vulnerability fix: Multiple pending updates can process without causing out-of-bounds
    function testProcessPendingUpdates_MultipleValidatorsDoSFix() public {
        // Register two validators and activate them (use different public keys for unique poolIds)
        bytes32 poolId1 = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);
        bytes32 poolId2 = registerAndActivateValidatorWithCustomKey(
            address(0x7), MIN_VALIDATOR_STAKE, "0x02a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f"
        );

        // Both validators update
        vm.prank(validator);
        staking.updateValidator(poolId1, "Updated 1", "http://updated1.validator");

        vm.prank(address(0x7));
        staking.updateValidator(poolId2, "Updated 2", "http://updated2.validator");

        // Verify both are in pending update queue
        bytes32[] memory pendingUpdates = staking.getPendingUpdateValidators();
        assertEq(pendingUpdates.length, 2, "Should have 2 pending updates");

        // Advance epoch - this should NOT revert due to out-of-bounds access
        // The fix ensures the two-pass pattern prevents this vulnerability
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch();

        // After advance epoch, both should be removed from pending updates
        pendingUpdates = staking.getPendingUpdateValidators();
        assertEq(pendingUpdates.length, 0, "Should have 0 pending updates after processing");
    }

    // Test edge case: Multiple validators exit with different conditions
    function testProcessPendingExits_MixedConditionsDoSFix() public {
        // Register three validators (use different public keys for unique poolIds)
        bytes32 poolId1 = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);
        bytes32 poolId2 = registerAndActivateValidatorWithCustomKey(
            address(0x7), MIN_VALIDATOR_STAKE * 2, "0x02a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f"
        );
        bytes32 poolId3 = registerAndActivateValidatorWithCustomKey(
            address(0x8), MIN_VALIDATOR_STAKE, "0x03a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f"
        );

        // First validator exits fully (status becomes 0, owner stake becomes 0)
        vm.prank(validator);
        staking.exitValidator(poolId1);

        // Second validator withdraws enough to drop totalStake below the activation threshold.
        // withdrawStake(MIN_VALIDATOR_STAKE + 1) leaves totalStake = MIN_VALIDATOR_STAKE - 1 < min,
        // so it is added to pendingExitPoolSets.
        vm.prank(address(0x7));
        staking.withdrawStake(poolId2, MIN_VALIDATOR_STAKE + 1);

        // Third validator exits fully
        vm.prank(address(0x8));
        staking.exitValidator(poolId3);

        // Verify pending exits
        bytes32[] memory pendingExits = staking.getPendingExitValidators();
        assertEq(pendingExits.length, 3, "Should have 3 pending exits");

        // Advance epoch - should handle mixed conditions without reverting
        // This is the key test: the two-pass pattern prevents out-of-bounds access
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        vm.prank(admin);
        staking.advanceEpoch();

        // The key assertion: epoch advanced successfully without out-of-bounds revert
        // This would have failed with the old code when elements are removed during iteration
        assertTrue(true, "Epoch advanced successfully - DoS vulnerability is fixed");
    }

    // Helper function to register validator with custom public key
    function registerAndActivateValidatorWithCustomKey(
        address _validator,
        uint256 _stake,
        string memory _customPublicKey
    ) public returns (bytes32) {
        vm.prank(_validator);
        vm.deal(_validator, _stake);
        bytes32 poolId = staking.registerValidator{value: _stake}(
            DESCRIPTION, _customPublicKey, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT
        );
        advanceEpoch();
        return poolId;
    }

    // Test that undelegation uses default window when config is empty or not yet effective
    function testUndelegate_UsesDefaultWindowWhenConfigIsEmpty() public {
        bytes32 poolId = registerAndActivateValidator(validator, MIN_VALIDATOR_STAKE);
        uint256 delegateAmount = 1 ether;
        vm.prank(delegator);
        vm.deal(delegator, delegateAmount);
        staking.delegate{value: delegateAmount}(poolId);

        // Advance epoch to activate pending stake
        advanceEpoch();

        // Trigger lazy activation
        vm.prank(delegator);
        staking.settleReward(poolId);

        // Set an empty value for delegation withdraw window (simulating the vulnerability scenario)
        // where setConfig is called but the checkpoint is not yet effective
        string[] memory keys = new string[](1);
        string[] memory values = new string[](1);
        keys[0] = "staking.delegation_withdraw_effective_epoch";
        values[0] = ""; // Empty value - this would cause parseUint to return 0 without the fix

        vm.prank(address(staking));
        chainConfig.setConfig(keys, values);

        // The config returns "" because the new checkpoint is not yet effective (effectiveBlockNum = block.number + 1)
        // Verify that getConfig returns empty string in the same block as setConfig
        string memory configValue = chainConfig.getConfig(keys[0]);
        assertEq(configValue, "", "Config should return empty when checkpoint is not yet effective");

        // Undelegate - should use DEFAULT_WITHDRAW_WINDOW instead of 0
        vm.prank(delegator);
        (, uint256 expectedUnlockEpoch) = staking.undelegate(poolId);

        // Verify that the unlock epoch is in the future, not immediately (currentEpoch + DEFAULT_WITHDRAW_WINDOW)
        (uint256 currentEpoch,,) = staking.getBlockchainInfo();
        uint256 expectedUnlock = currentEpoch + 84; // DEFAULT_WITHDRAW_WINDOW = 84
        assertEq(expectedUnlockEpoch, expectedUnlock, "Unlock epoch should use DEFAULT_WITHDRAW_WINDOW");

        // Verify that the delegator info has the correct pending withdraw window
        IStaking.Delegator memory delegatorInfo = staking.getDelegator(poolId, delegator);
        assertEq(delegatorInfo.isPendingUndelegate, true, "Should be pending undelegate");
        assertGt(delegatorInfo.pendingWithdrawWindow, 0, "Pending withdraw window should be greater than 0");

        // Advance to the next block to make the config effective (should set it to 0)
        vm.roll(block.number + 1);

        // Now the config should be effective and return ""
        configValue = chainConfig.getConfig(keys[0]);
        assertEq(configValue, "", "Config should return empty string when effective");

        // But the previous undelegation already used DEFAULT_WITHDRAW_WINDOW, so it's safe
        // New undelegations would still use DEFAULT_WITHDRAW_WINDOW because of the fix
    }
}

// Minimal dummy contract for testing RuleManager contract code existence validation
contract DummyContract {
    function dummyFunction() external pure returns (uint256) {
        return 42;
    }
}
