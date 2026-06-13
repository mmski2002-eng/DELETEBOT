// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

contract DebugCommissionTest is Test {
    ChainConfig private chainConfig;
    TransparentUpgradeableProxy chainConfigProxy;
    Staking private staking;
    TransparentUpgradeableProxy private stakingProxy;
    RuleManager private ruleManager;
    TransparentUpgradeableProxy private ruleManagerProxy;

    address admin = 0x1111111111111111111111111111111111111111;
    address validator = address(0x4);

    uint256 public constant MIN_POOL_STAKE = 10000000 ether;

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

    function testDebugCommission() public {
        vm.prank(validator);
        vm.deal(validator, MIN_POOL_STAKE);
        bytes32 poolId = staking.registerValidator{value: MIN_POOL_STAKE}(
            "Test Validator",
            "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f",
            "0xproof1",
            "0xblskey1",
            "0xblspop1",
            "http://test.validator"
        );

        console.log("Pool ID:", uint256(poolId));
        console.log("Initial commission rate:", staking.getCommissionRate(poolId));

        // Advance epoch to activate validator
        vm.warp(vm.getBlockTimestamp() + 4 hours + 1);
        vm.prank(admin);
        staking.advanceEpoch(new bytes32[](0), new uint256[](0));

        console.log("Epoch after activation:", staking.currentEpoch());
        console.log("Commission rate after activation:", staking.getCommissionRate(poolId));

        // Set new commission rate
        vm.prank(validator);
        staking.setCommissionRate(poolId, 2000);

        console.log("Epoch after setting rate:", staking.currentEpoch());
        console.log("Commission rate immediately after setting:", staking.getCommissionRate(poolId));

        // Advance epochs
        for (uint256 i = 0; i < 10; i++) {
            vm.warp(vm.getBlockTimestamp() + 4 hours + 1);
            vm.prank(admin);
            staking.advanceEpoch(new bytes32[](0), new uint256[](0));
            console.log("Epoch", staking.currentEpoch(), "commission rate:", staking.getCommissionRate(poolId));
        }
    }
}
