// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {StakingV1} from "./StakingV1.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";
import {Create2Deployer} from "../src/utils/Create2Deployer.sol";

/**
 * @title Create2UpgradeTest
 * @notice Test for CREATE2-based deterministic deployment and upgrade
 * @dev Tests the ability to:
 *      1. Use CREATE2 to deploy implementation contracts at predictable addresses
 *      2. Upgrade to CREATE2-deployed implementations
 *      3. Re-deploy implementations at the same address using CREATE2
 *      4. Verify data preservation across upgrades
 */
contract Create2UpgradeTest is Test {
    ChainConfig private chainConfig;
    TransparentUpgradeableProxy chainConfigProxy;

    Create2Deployer private create2Deployer;

    StakingV1 private stakingV1Impl;
    Staking private stakingV2Impl;
    IStaking private stakingProxy;
    TransparentUpgradeableProxy private stakingProxyContract;

    address admin = address(0x1111111111111111111111111111111111111111);
    address validator = address(0x2);
    address delegator = address(0x3);

    string public constant DESCRIPTION = "Test Validator";
    string public constant PUBLIC_KEY = "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f";
    string public constant PUBLIC_KEY_POP = "0xproof1";
    string public constant BLS_PUBLIC_KEY = "0xblskey1";
    string public constant BLS_PUBLIC_KEY_POP = "0xblspop1";
    string public constant ENDPOINT = "http://test.validator";

    uint256 public constant MIN_POOL_STAKE = 10000000 ether;
    uint256 public constant MIN_VALIDATOR_STAKE = 1 ether;
    uint256 public constant MIN_DELEGATOR_STAKE = 1 ether;

    // Salts for CREATE2 deployment
    bytes32 private constant STAKING_V1_SALT = keccak256("STAKING_V1");
    bytes32 private constant STAKING_V2_SALT = keccak256("STAKING_V2");

    function setUp() public {
        // Deploy CREATE2 Deployer
        create2Deployer = new Create2Deployer();

        // Deploy ChainConfig
        vm.startPrank(admin);
        chainConfig = new ChainConfig();

        address chainConfigImplAddr = address(chainConfig);
        bytes memory chainConfigInitData = abi.encodeWithSelector(ChainConfig.initialize.selector, admin, address(this));
        chainConfigProxy = new TransparentUpgradeableProxy(address(chainConfig), chainConfigInitData);
        chainConfig = ChainConfig(address(chainConfigProxy));

        // Deploy Staking V1 using regular deployment first
        stakingV1Impl = new StakingV1();

        bytes memory stakingInitData =
            abi.encodeWithSelector(StakingV1.initialize.selector, admin, address(chainConfig));
        stakingProxyContract = new TransparentUpgradeableProxy(address(stakingV1Impl), stakingInitData);
        stakingProxy = IStaking(address(stakingProxyContract));

        // Update implementation address for V1
        StakingV1(address(stakingProxyContract)).updateImplAddress(address(stakingV1Impl));

        // Update ChainConfig with staking address
        chainConfig.updateStakingAddress(address(stakingProxyContract));
        StakingV1(address(stakingProxyContract)).updateChainConfigAddress(address(chainConfig));

        vm.stopPrank();

        // Configure ChainConfig with test values
        string[] memory keys = new string[](6);
        string[] memory values = new string[](6);
        keys[0] = "staking.min_staking_pool_value";
        values[0] = vm.toString(MIN_VALIDATOR_STAKE);
        keys[1] = "staking.max_staking_pool_value";
        values[1] = vm.toString(MIN_POOL_STAKE);
        keys[2] = "staking.min_delegator_stake";
        values[2] = vm.toString(MIN_DELEGATOR_STAKE);
        keys[3] = "staking.withdraw_effective_epoch";
        values[3] = "1";
        keys[4] = "staking.delegation_withdraw_effective_epoch";
        values[4] = "1";
        keys[5] = "staking.min_staking_registration_value";
        values[5] = vm.toString(MIN_VALIDATOR_STAKE);

        vm.prank(address(stakingProxyContract));
        chainConfig.setConfig(keys, values);

        // Advance block to make configs effective (required by effectiveBlockNum validation)
        vm.roll(block.number + 1);
    }

    // ==================== CREATE2 Deployment Tests ====================

    function testCreate2_DeployStakingV1() public {
        // Get bytecode of StakingV1
        bytes memory bytecode = type(StakingV1).creationCode;

        // Deploy using CREATE2
        vm.prank(admin);
        address deployedAddress = create2Deployer.deploy(bytecode, STAKING_V1_SALT);

        // Verify deployment
        assertEq(deployedAddress.code.length > 0, true, "Contract should be deployed");

        // Verify we can compute the address correctly
        bytes32 bytecodeHash = create2Deployer.getBytecodeHash(bytecode);
        address predictedAddress =
            create2Deployer.computeAddress(address(create2Deployer), STAKING_V1_SALT, bytecodeHash);
        assertEq(deployedAddress, predictedAddress, "Address should match predicted");
    }

    function testCreate2_DeployStakingV2() public {
        // Get bytecode of Staking V2
        bytes memory bytecode = type(Staking).creationCode;

        // Deploy using CREATE2
        vm.prank(admin);
        address deployedAddress = create2Deployer.deploy(bytecode, STAKING_V2_SALT);

        // Verify deployment
        assertEq(deployedAddress.code.length > 0, true, "Contract should be deployed");

        // Verify we can compute the address correctly
        bytes32 bytecodeHash = create2Deployer.getBytecodeHash(bytecode);
        address predictedAddress =
            create2Deployer.computeAddress(address(create2Deployer), STAKING_V2_SALT, bytecodeHash);
        assertEq(deployedAddress, predictedAddress, "Address should match predicted");
    }

    function testCreate2_RedeploySameAddress() public {
        // Deploy V1 first time
        bytes memory bytecode = type(StakingV1).creationCode;
        vm.prank(admin);
        address deployedAddress1 = create2Deployer.deploy(bytecode, STAKING_V1_SALT);

        // Try to deploy again with same salt (should fail if address already has code)
        vm.prank(admin);
        vm.expectRevert();
        create2Deployer.deploy(bytecode, STAKING_V1_SALT);

        // But with different salt, should succeed
        bytes32 differentSalt = keccak256("DIFFERENT_SALT");
        vm.prank(admin);
        address deployedAddress2 = create2Deployer.deploy(bytecode, differentSalt);

        assertNotEq(deployedAddress1, deployedAddress2, "Addresses should be different with different salts");
    }

    // ==================== CREATE2 Upgrade Tests ====================

    function testCreate2_UpgradeFromV1ToV2() public {
        // Setup V1 state
        vm.prank(validator);
        vm.deal(validator, MIN_VALIDATOR_STAKE);
        bytes32 poolId = stakingProxy.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT
        );

        vm.prank(admin);
        stakingProxy.advanceEpoch();

        uint256 v1Epoch = StakingV1(address(stakingProxyContract)).currentEpoch();
        uint256 v1TotalStake = StakingV1(address(stakingProxyContract)).totalStake();

        // Deploy V2 using CREATE2
        bytes memory v2Bytecode = type(Staking).creationCode;
        vm.prank(admin);
        address v2Create2Address = create2Deployer.deploy(v2Bytecode, STAKING_V2_SALT);

        console.log("V2 deployed at CREATE2 address:", vm.toString(v2Create2Address));

        // Upgrade to CREATE2-deployed V2
        vm.prank(admin);
        Staking(address(stakingProxyContract)).upgradeToAndCall(v2Create2Address, "");

        // Migrate V1 arrays to V2 sets
        vm.prank(admin);
        Staking(address(stakingProxyContract)).migrateV1ToV2();

        // Update implementation address
        vm.prank(admin);

        // Verify data preserved
        uint256 v2Epoch = Staking(address(stakingProxyContract)).currentEpoch();
        uint256 v2TotalStake = Staking(address(stakingProxyContract)).totalStake();
        assertEq(v2Epoch, v1Epoch, "Epoch should be preserved");
        assertEq(v2TotalStake, v1TotalStake, "Total stake should be preserved");

        // Verify validator still active
        assertTrue(stakingProxy.isValidatorActive(poolId), "Validator should still be active");
    }

    function testCreate2_PredictableUpgradeAddresses() public {
        // Predict addresses before deployment
        bytes memory v1Bytecode = type(StakingV1).creationCode;
        bytes memory v2Bytecode = type(Staking).creationCode;

        bytes32 v1BytecodeHash = keccak256(v1Bytecode);
        bytes32 v2BytecodeHash = keccak256(v2Bytecode);

        address predictedV1Address =
            create2Deployer.computeAddress(address(create2Deployer), STAKING_V1_SALT, v1BytecodeHash);
        address predictedV2Address =
            create2Deployer.computeAddress(address(create2Deployer), STAKING_V2_SALT, v2BytecodeHash);

        console.log("Predicted V1 address:", vm.toString(predictedV1Address));
        console.log("Predicted V2 address:", vm.toString(predictedV2Address));

        // Actually deploy
        vm.prank(admin);
        address actualV1Address = create2Deployer.deploy(v1Bytecode, STAKING_V1_SALT);

        vm.prank(admin);
        address actualV2Address = create2Deployer.deploy(v2Bytecode, STAKING_V2_SALT);

        // Verify predictions were correct
        assertEq(actualV1Address, predictedV1Address, "V1 address should match prediction");
        assertEq(actualV2Address, predictedV2Address, "V2 address should match prediction");
    }

    function testCreate2_UpgradeWithDelegation() public {
        // Setup V1 and upgrade to V2 using CREATE2
        vm.prank(validator);
        vm.deal(validator, MIN_VALIDATOR_STAKE);
        bytes32 poolId = stakingProxy.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT
        );

        vm.prank(admin);
        stakingProxy.advanceEpoch();

        // Deploy V2 using CREATE2
        bytes memory v2Bytecode = type(Staking).creationCode;
        vm.prank(admin);
        address v2Create2Address = create2Deployer.deploy(v2Bytecode, STAKING_V2_SALT);

        // Upgrade to CREATE2-deployed V2
        vm.prank(admin);
        Staking(address(stakingProxyContract)).upgradeToAndCall(v2Create2Address, "");
        vm.prank(admin);
        Staking(address(stakingProxyContract)).migrateV1ToV2();

        // Enable delegation
        vm.prank(validator);
        stakingProxy.setDelegationEnabled(poolId, true);
        vm.prank(validator);
        stakingProxy.setCommissionRate(poolId, 1000);

        // Delegate
        uint256 delegateAmount = 10 ether;
        vm.prank(delegator);
        vm.deal(delegator, delegateAmount);
        stakingProxy.delegate{value: delegateAmount}(poolId);

        // Advance epoch to activate delegation
        uint256 nextEpochTime = block.timestamp + 14401;
        vm.warp(nextEpochTime);
        vm.prank(admin);
        stakingProxy.advanceEpoch();

        // Advance another epoch to generate rewards on the active delegation
        nextEpochTime = nextEpochTime + 14401;
        vm.warp(nextEpochTime);
        vm.prank(admin);
        stakingProxy.advanceEpoch();

        // Settle rewards to ensure they're calculated
        vm.prank(delegator);
        Staking(address(stakingProxy)).settleReward(poolId);

        // Check rewards
        uint256 delegatorRewards = stakingProxy.getDelegatorReward(poolId, delegator);
        assertGt(delegatorRewards, 0, "Delegator should have rewards");

        console.log("CREATE2 upgrade successful with delegation rewards:", delegatorRewards);
    }

    function testCreate2_MultipleUpgradesSameImplementation() public {
        // This test demonstrates that with CREATE2, we can always deploy
        // the implementation at the same address if we use the same salt

        // Deploy V2 using CREATE2
        bytes memory v2Bytecode = type(Staking).creationCode;
        vm.prank(admin);
        address v2Address1 = create2Deployer.deploy(v2Bytecode, STAKING_V2_SALT);

        // In a real scenario, if we need to "redeploy" the same implementation
        // (e.g., after a temporary upgrade to V3 and then back to V2),
        // we can use CREATE2 to get the same address

        // The key insight: with CREATE2, the address is deterministic
        // So we can pre-compute where implementations will be deployed
        bytes32 v2BytecodeHash = keccak256(v2Bytecode);
        address predictedV2Address =
            create2Deployer.computeAddress(address(create2Deployer), STAKING_V2_SALT, v2BytecodeHash);

        assertEq(v2Address1, predictedV2Address, "V2 address should be deterministic");
        console.log("V2 can always be deployed at:", vm.toString(v2Address1));
    }

    function testCreate2_DifferentDeployers() public {
        // Test that different deployers result in different addresses
        Create2Deployer deployer2 = new Create2Deployer();

        bytes memory bytecode = type(Staking).creationCode;
        bytes32 bytecodeHash = keccak256(bytecode);

        address addressFromDeployer1 =
            create2Deployer.computeAddress(address(create2Deployer), STAKING_V2_SALT, bytecodeHash);
        address addressFromDeployer2 = create2Deployer.computeAddress(address(deployer2), STAKING_V2_SALT, bytecodeHash);

        assertNotEq(addressFromDeployer1, addressFromDeployer2, "Different deployers should give different addresses");

        console.log("Address from deployer 1:", vm.toString(addressFromDeployer1));
        console.log("Address from deployer 2:", vm.toString(addressFromDeployer2));
    }

    // ==================== Comprehensive E2E Test ====================

    function testE2E_Create2UpgradeFlow() public {
        console.log("=== CREATE2 E2E Test ===");

        // ===== Phase 1: V1 Operations =====
        console.log("\n=== Phase 1: V1 Operations ===");

        vm.prank(validator);
        vm.deal(validator, MIN_VALIDATOR_STAKE);
        bytes32 poolId = stakingProxy.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT
        );
        console.log("V1: Validator registered");

        vm.prank(admin);
        stakingProxy.advanceEpoch();
        console.log("V1: Epoch advanced");

        // ===== Phase 2: CREATE2 Deployment Prediction =====
        console.log("\n=== Phase 2: CREATE2 Deployment Prediction ===");

        bytes memory v2Bytecode = type(Staking).creationCode;
        bytes32 v2BytecodeHash = keccak256(v2Bytecode);
        address predictedV2Address =
            create2Deployer.computeAddress(address(create2Deployer), STAKING_V2_SALT, v2BytecodeHash);

        console.log("Predicted V2 address:", vm.toString(predictedV2Address));

        // ===== Phase 3: CREATE2 Deployment =====
        console.log("\n=== Phase 3: CREATE2 Deployment ===");

        vm.prank(admin);
        address actualV2Address = create2Deployer.deploy(v2Bytecode, STAKING_V2_SALT);

        console.log("Actual V2 address:", vm.toString(actualV2Address));
        assertEq(actualV2Address, predictedV2Address, "Address should match prediction");

        // ===== Phase 4: Upgrade using CREATE2-deployed implementation =====
        console.log("\n=== Phase 4: Upgrade using CREATE2-deployed implementation ===");

        uint256 v1Epoch = StakingV1(address(stakingProxyContract)).currentEpoch();
        uint256 v1TotalStake = StakingV1(address(stakingProxyContract)).totalStake();

        vm.prank(admin);
        Staking(address(stakingProxyContract)).upgradeToAndCall(actualV2Address, "");
        vm.prank(admin);
        Staking(address(stakingProxyContract)).migrateV1ToV2();

        console.log("Upgraded to V2 at CREATE2 address");

        uint256 v2Epoch = Staking(address(stakingProxyContract)).currentEpoch();
        uint256 v2TotalStake = Staking(address(stakingProxyContract)).totalStake();
        assertEq(v2Epoch, v1Epoch, "Epoch preserved");
        assertEq(v2TotalStake, v1TotalStake, "Total stake preserved");

        // ===== Phase 5: V2 Delegation Operations =====
        console.log("\n=== Phase 5: V2 Delegation Operations ===");

        vm.prank(validator);
        stakingProxy.setDelegationEnabled(poolId, true);
        vm.prank(validator);
        stakingProxy.setCommissionRate(poolId, 1000);

        uint256 delegateAmount = 10 ether;
        vm.prank(delegator);
        vm.deal(delegator, delegateAmount);
        stakingProxy.delegate{value: delegateAmount}(poolId);

        console.log("V2: Delegator delegated", delegateAmount);

        // ===== Phase 6: Rewards and Claims =====
        console.log("\n=== Phase 6: Rewards and Claims ===");

        // Advance epoch to activate delegation
        uint256 nextEpochTime = block.timestamp + 14401;
        vm.warp(nextEpochTime);
        vm.prank(admin);
        stakingProxy.advanceEpoch();

        // Advance another epoch to generate rewards
        nextEpochTime = nextEpochTime + 14401;
        vm.warp(nextEpochTime);
        vm.prank(admin);
        stakingProxy.advanceEpoch();

        // Settle rewards to ensure they're calculated
        vm.prank(delegator);
        Staking(address(stakingProxy)).settleReward(poolId);

        uint256 delegatorRewards = stakingProxy.getDelegatorReward(poolId, delegator);
        console.log("V2: Delegator rewards", delegatorRewards);
        assertGt(delegatorRewards, 0, "Should have rewards");

        vm.prank(delegator);
        uint256 claimedAmount = stakingProxy.claimReward(poolId);
        console.log("V2: Claimed rewards", claimedAmount);
        assertEq(claimedAmount, delegatorRewards, "Claimed amount should match");

        console.log("\n=== CREATE2 E2E Test Complete ===");
    }
}
