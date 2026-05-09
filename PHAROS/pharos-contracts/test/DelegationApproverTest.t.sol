// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainConfig} from "../src/chainConfig/ChainConfig.sol";
import {RuleManager} from "../src/ruleManager/RuleManager.sol";
import {Staking} from "../src/staking/Staking.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract DelegationApproverTest is Test {
    ChainConfig private chainConfig;
    TransparentUpgradeableProxy chainConfigProxy;
    Staking private staking;
    TransparentUpgradeableProxy private stakingProxy;
    RuleManager private ruleManager;
    TransparentUpgradeableProxy private ruleManagerProxy;

    address admin = address(0x0);
    address intrinsicAddress = 0x1111111111111111111111111111111111111111;

    address public validatorOwner = address(0x4);
    address public delegator1 = address(0x5);
    address public stranger = address(0x6);

    // Approver key pair (use vm.sign with this private key)
    uint256 public approverPrivateKey = 0xA11CE;
    address public approver;

    // Second approver for key rotation tests
    uint256 public approver2PrivateKey = 0xB0B;
    address public approver2;

    string public constant DESCRIPTION = "Test Validator";
    string public constant PUBLIC_KEY = "0x04a34d6aef32a6a5a4389f68f9a7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f";
    string public constant PUBLIC_KEY_POP = "0xproof1";
    string public constant BLS_PUBLIC_KEY = "0xblskey1";
    string public constant BLS_PUBLIC_KEY_POP = "0xblspop1";
    string public constant ENDPOINT = "http://test.validator";

    uint256 public constant MIN_POOL_STAKE = 10000000 ether;
    uint256 public constant MIN_VALIDATOR_STAKE = 1 ether;
    uint256 public constant MIN_DELEGATOR_STAKE = 1 ether;

    // EIP-712 constants (must match Staking.sol)
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant DELEGATION_APPROVAL_TYPEHASH =
        keccak256("DelegationApproval(bytes32 poolId,address delegator,uint256 nonce)");

    function setUp() public {
        approver = vm.addr(approverPrivateKey);
        approver2 = vm.addr(approver2PrivateKey);

        admin = intrinsicAddress;
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
        values[1] = vm.toString(MIN_POOL_STAKE);
        keys[2] = "staking.min_delegator_stake";
        values[2] = vm.toString(MIN_DELEGATOR_STAKE);
        keys[3] = "staking.withdraw_effective_epoch";
        values[3] = "1";
        keys[4] = "staking.min_staking_registration_value";
        values[4] = vm.toString(MIN_VALIDATOR_STAKE);

        vm.prank(address(staking));
        chainConfig.setConfig(keys, values);
        vm.roll(block.number + 1);
    }

    // ========== Helpers ==========

    function registerAndActivateValidator(address _validator, uint256 _stake) public returns (bytes32) {
        vm.prank(_validator);
        vm.deal(_validator, _stake);
        bytes32 poolId = staking.registerValidator{value: _stake}(
            DESCRIPTION, PUBLIC_KEY, PUBLIC_KEY_POP, BLS_PUBLIC_KEY, BLS_PUBLIC_KEY_POP, ENDPOINT
        );
        advanceEpoch();
        return poolId;
    }

    function advanceEpoch() public {
        vm.roll(block.number + 1);
        uint256 epochDuration = 4 hours;
        vm.warp(vm.getBlockTimestamp() + epochDuration + 1);
        vm.prank(admin);
        staking.advanceEpoch();
    }

    function _buildDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("PharosStaking")),
                keccak256(bytes("1")),
                block.chainid,
                address(staking)
            )
        );
    }

    function _signApproval(uint256 _privateKey, bytes32 _poolId, address _delegator, uint256 _nonce)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(DELEGATION_APPROVAL_TYPEHASH, _poolId, _delegator, _nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _buildDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // ========== Tests: delegate() with approver=0 (open mode) ==========

    function testDelegate_OpenMode_Succeeds() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        // approver is address(0) by default → open delegation
        assertEq(staking.getDelegationApprover(poolId), address(0));

        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        advanceEpoch();
        vm.prank(delegator1);
        staking.settleReward(poolId);

        IStaking.Delegator memory d = staking.getDelegator(poolId, delegator1);
        assertEq(d.stake, MIN_DELEGATOR_STAKE);
    }

    function testDelegateWithApproval_OpenMode_Reverts() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        bytes memory sig = _signApproval(approverPrivateKey, poolId, delegator1, 0);

        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        vm.expectRevert("Approval mode not enabled");
        staking.delegateWithApproval{value: MIN_DELEGATOR_STAKE}(poolId, sig);
    }

    // ========== Tests: delegate() with approver!=0 (approval mode) ==========

    function testDelegate_ApprovalMode_Reverts() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        // Owner sets approver
        vm.prank(validatorOwner);
        staking.setDelegationApprover(poolId, approver);

        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        vm.expectRevert("Approval required: use delegateWithApproval");
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);
    }

    // ========== Tests: delegateWithApproval() ==========

    function testDelegateWithApproval_ValidSignature_Succeeds() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        vm.prank(validatorOwner);
        staking.setDelegationApprover(poolId, approver);

        // Check initial nonce is 0
        assertEq(staking.getDelegationApprovalNonce(poolId, delegator1), 0);

        bytes memory sig = _signApproval(approverPrivateKey, poolId, delegator1, 0);

        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        staking.delegateWithApproval{value: MIN_DELEGATOR_STAKE}(poolId, sig);

        // Nonce should be incremented
        assertEq(staking.getDelegationApprovalNonce(poolId, delegator1), 1);
    }

    function testDelegateWithApproval_ReplayAttack_Reverts() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        vm.prank(validatorOwner);
        staking.setDelegationApprover(poolId, approver);

        bytes memory sig = _signApproval(approverPrivateKey, poolId, delegator1, 0);

        // First delegation succeeds
        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE * 2);
        staking.delegateWithApproval{value: MIN_DELEGATOR_STAKE}(poolId, sig);

        // Replay with same signature (nonce is now 1, sig was for nonce 0)
        vm.prank(delegator1);
        vm.expectRevert("Invalid approval signature");
        staking.delegateWithApproval{value: MIN_DELEGATOR_STAKE}(poolId, sig);
    }

    function testDelegateWithApproval_WrongSigner_Reverts() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        vm.prank(validatorOwner);
        staking.setDelegationApprover(poolId, approver);

        // Sign with wrong key (approver2 instead of approver)
        bytes memory wrongSig = _signApproval(approver2PrivateKey, poolId, delegator1, 0);

        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        vm.expectRevert("Invalid approval signature");
        staking.delegateWithApproval{value: MIN_DELEGATOR_STAKE}(poolId, wrongSig);
    }

    function testDelegateWithApproval_SecondDelegation_NewNonce() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        vm.prank(validatorOwner);
        staking.setDelegationApprover(poolId, approver);

        // First delegation with nonce 0
        bytes memory sig0 = _signApproval(approverPrivateKey, poolId, delegator1, 0);
        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE * 3);
        staking.delegateWithApproval{value: MIN_DELEGATOR_STAKE}(poolId, sig0);
        assertEq(staking.getDelegationApprovalNonce(poolId, delegator1), 1);

        // Advance epoch to activate the first pending stake
        advanceEpoch();

        // Second delegation with nonce 1
        bytes memory sig1 = _signApproval(approverPrivateKey, poolId, delegator1, 1);
        vm.prank(delegator1);
        staking.delegateWithApproval{value: MIN_DELEGATOR_STAKE}(poolId, sig1);
        assertEq(staking.getDelegationApprovalNonce(poolId, delegator1), 2);
    }

    // ========== Tests: setDelegationApprover() access control ==========

    function testSetDelegationApprover_ByOwner_Succeeds() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        vm.expectEmit(true, true, false, true);
        emit IStaking.DelegationApproverChanged(poolId, approver);

        vm.prank(validatorOwner);
        staking.setDelegationApprover(poolId, approver);

        assertEq(staking.getDelegationApprover(poolId), approver);
    }

    function testSetDelegationApprover_ByCurrentApprover_Succeeds() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        // Owner sets initial approver
        vm.prank(validatorOwner);
        staking.setDelegationApprover(poolId, approver);

        // Current approver rotates to approver2
        vm.prank(approver);
        staking.setDelegationApprover(poolId, approver2);

        assertEq(staking.getDelegationApprover(poolId), approver2);
    }

    function testSetDelegationApprover_ByStranger_Reverts() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        vm.prank(stranger);
        vm.expectRevert("Not authorized: must be owner or current approver");
        staking.setDelegationApprover(poolId, approver);
    }

    function testSetDelegationApprover_NonExistentValidator_Reverts() public {
        bytes32 fakePoolId = bytes32(uint256(0xdead));

        vm.prank(validatorOwner);
        vm.expectRevert("Validator does not exist");
        staking.setDelegationApprover(fakePoolId, approver);
    }

    // ========== Tests: Restore open mode ==========

    function testSetDelegationApprover_RestoreOpenMode() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        // Set approver (approval mode)
        vm.prank(validatorOwner);
        staking.setDelegationApprover(poolId, approver);
        assertEq(staking.getDelegationApprover(poolId), approver);

        // delegate() should fail now
        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE * 2);
        vm.expectRevert("Approval required: use delegateWithApproval");
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);

        // Owner clears approver back to address(0) (open mode)
        vm.prank(validatorOwner);
        staking.setDelegationApprover(poolId, address(0));
        assertEq(staking.getDelegationApprover(poolId), address(0));

        // delegate() should work again
        vm.prank(delegator1);
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);
    }

    // ========== Tests: Custom approver (non-owner) signature ==========

    function testDelegateWithApproval_CustomApprover_NotOwner() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        // Owner sets a separate KYC service as approver (not the owner)
        vm.prank(validatorOwner);
        staking.setDelegationApprover(poolId, approver);

        // Approver signs the delegation
        bytes memory sig = _signApproval(approverPrivateKey, poolId, delegator1, 0);

        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        staking.delegateWithApproval{value: MIN_DELEGATOR_STAKE}(poolId, sig);

        advanceEpoch();
        vm.prank(delegator1);
        staking.settleReward(poolId);

        IStaking.Delegator memory d = staking.getDelegator(poolId, delegator1);
        assertEq(d.stake, MIN_DELEGATOR_STAKE);
    }

    // ========== Tests: Delegation disabled (master kill switch) ==========

    function testDelegate_DelegationDisabled_Reverts() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        vm.prank(validatorOwner);
        staking.setDelegationEnabled(poolId, false);

        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        vm.expectRevert("Delegation disabled");
        staking.delegate{value: MIN_DELEGATOR_STAKE}(poolId);
    }

    function testDelegateWithApproval_DelegationDisabled_Reverts() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        // Set approver
        vm.prank(validatorOwner);
        staking.setDelegationApprover(poolId, approver);

        // Disable delegation
        vm.prank(validatorOwner);
        staking.setDelegationEnabled(poolId, false);

        bytes memory sig = _signApproval(approverPrivateKey, poolId, delegator1, 0);

        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        vm.expectRevert("Delegation disabled");
        staking.delegateWithApproval{value: MIN_DELEGATOR_STAKE}(poolId, sig);
    }

    // ========== Tests: Key rotation invalidates old signatures ==========

    function testDelegateWithApproval_AfterKeyRotation_OldSigFails() public {
        bytes32 poolId = registerAndActivateValidator(validatorOwner, MIN_VALIDATOR_STAKE);

        vm.prank(validatorOwner);
        staking.setDelegationApprover(poolId, approver);

        // Sign with old approver
        bytes memory oldSig = _signApproval(approverPrivateKey, poolId, delegator1, 0);

        // Rotate to new approver
        vm.prank(approver);
        staking.setDelegationApprover(poolId, approver2);

        // Old signature should fail (wrong signer)
        vm.prank(delegator1);
        vm.deal(delegator1, MIN_DELEGATOR_STAKE);
        vm.expectRevert("Invalid approval signature");
        staking.delegateWithApproval{value: MIN_DELEGATOR_STAKE}(poolId, oldSig);

        // New approver signature should work
        bytes memory newSig = _signApproval(approver2PrivateKey, poolId, delegator1, 0);
        vm.prank(delegator1);
        staking.delegateWithApproval{value: MIN_DELEGATOR_STAKE}(poolId, newSig);
    }
}
