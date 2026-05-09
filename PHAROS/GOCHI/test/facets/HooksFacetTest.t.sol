// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../utils/DiamondFixture.sol";
import { ALICE } from "../utils/Constants.sol";
import { IMintFacet } from "../../src/interfaces/IMintFacet.sol";
import { HooksFacet } from "../../src/facets/HooksFacet.sol";
import { ERC6551Facet } from "../../src/facets/ERC6551Facet.sol";
import { SecurityFacet } from "../../src/facets/SecurityFacet.sol";
import { IHook } from "../../src/interfaces/IHook.sol";

contract MockBeforeHook is IHook {
    bytes4 public constant HOOK_SUCCESS = bytes4(keccak256("HOOK_SUCCESS"));
    uint256 public callCount;

    function getHookPermissions() external pure override returns (Permissions memory) {
        return Permissions({ beforeExecute: true, afterExecute: false });
    }

    function beforeExecute(HookParams calldata) external override returns (bytes4) {
        callCount++;
        return HOOK_SUCCESS;
    }

    function afterExecute(HookParams calldata) external pure override returns (bytes4) {
        revert("not implemented");
    }
}

contract MockAfterHook is IHook {
    bytes4 public constant HOOK_SUCCESS = bytes4(keccak256("HOOK_SUCCESS"));
    uint256 public callCount;

    function getHookPermissions() external pure override returns (Permissions memory) {
        return Permissions({ beforeExecute: false, afterExecute: true });
    }

    function beforeExecute(HookParams calldata) external pure override returns (bytes4) {
        revert("not implemented");
    }

    function afterExecute(HookParams calldata) external override returns (bytes4) {
        callCount++;
        return HOOK_SUCCESS;
    }
}

contract MockFullHook is IHook {
    bytes4 public constant HOOK_SUCCESS = bytes4(keccak256("HOOK_SUCCESS"));
    uint256 public beforeCount;
    uint256 public afterCount;

    function getHookPermissions() external pure override returns (Permissions memory) {
        return Permissions({ beforeExecute: true, afterExecute: true });
    }

    function beforeExecute(HookParams calldata) external override returns (bytes4) {
        beforeCount++;
        return HOOK_SUCCESS;
    }

    function afterExecute(HookParams calldata) external override returns (bytes4) {
        afterCount++;
        return HOOK_SUCCESS;
    }
}

contract MockBadMagicHook is IHook {
    function getHookPermissions() external pure override returns (Permissions memory) {
        return Permissions({ beforeExecute: true, afterExecute: false });
    }

    function beforeExecute(HookParams calldata) external pure override returns (bytes4) {
        return bytes4(0xdeadbeef); // wrong magic
    }

    function afterExecute(HookParams calldata) external pure override returns (bytes4) {
        return bytes4(0xdeadbeef);
    }
}

contract MockRevertingHook is IHook {
    function getHookPermissions() external pure override returns (Permissions memory) {
        return Permissions({ beforeExecute: true, afterExecute: true });
    }

    function beforeExecute(HookParams calldata) external pure override returns (bytes4) {
        revert("Hook execution blocked");
    }

    function afterExecute(HookParams calldata) external pure override returns (bytes4) {
        revert("Hook execution blocked");
    }
}

contract MockNoPermissionsHook is IHook {
    function getHookPermissions() external pure override returns (Permissions memory) {
        return Permissions({ beforeExecute: false, afterExecute: false });
    }

    function beforeExecute(HookParams calldata) external pure override returns (bytes4) {
        return bytes4(keccak256("HOOK_SUCCESS"));
    }

    function afterExecute(HookParams calldata) external pure override returns (bytes4) {
        return bytes4(keccak256("HOOK_SUCCESS"));
    }
}

contract HookTestReceiver {
    receive() external payable {}
}

contract HooksFacetTest is DiamondFixture {
    address internal BOB = address(0xB0B);

    HooksFacet internal hf;
    ERC6551Facet internal ef;
    SecurityFacet internal sf;
    uint256 constant TOKEN_ID = 0;
    address internal tba;
    address[] internal EMPTY_LIST;

    MockBeforeHook internal beforeHook;
    MockAfterHook internal afterHook;
    MockFullHook internal fullHook;
    MockBadMagicHook internal badMagicHook;
    MockRevertingHook internal revertingHook;
    MockNoPermissionsHook internal noPermsHook;

    function setUp() public override {
        super.setUp();
        hf = HooksFacet(address(diamond));
        ef = ERC6551Facet(address(diamond));
        sf = SecurityFacet(address(diamond));
        vm.deal(ALICE, 500 ether);
        vm.deal(BOB, 500 ether);

        tba = _summonGotchipus(TOKEN_ID);

        beforeHook = new MockBeforeHook();
        afterHook = new MockAfterHook();
        fullHook = new MockFullHook();
        badMagicHook = new MockBadMagicHook();
        revertingHook = new MockRevertingHook();
        noPermsHook = new MockNoPermissionsHook();
    }

    function testAddBeforeHook() public {
        vm.prank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), 1);
        assertTrue(hf.isHookValid(TOKEN_ID, address(beforeHook)));
    }

    function testAddAfterHook() public {
        vm.prank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.AfterExecute, IHook(address(afterHook)));

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.AfterExecute), 1);
        assertTrue(hf.isHookValid(TOKEN_ID, address(afterHook)));
    }

    function testAddHookEmitsEvent() public {
        vm.prank(ALICE);
        vm.expectEmit(true, true, true, false, address(diamond));
        emit HooksFacet.HookAdded(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, address(beforeHook));
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
    }

    function testAddHookOnlyOwner() public {
        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
    }

    function testAddHookZeroAddressReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(HooksFacet.InvalidHookAddress.selector);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(0)));
    }

    function testAddHookDuplicateReverts() public {
        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));

        vm.expectRevert(
            abi.encodeWithSelector(HooksFacet.HookAlreadyExists.selector, TOKEN_ID, address(beforeHook))
        );
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        vm.stopPrank();
    }

    function testAddHookWrongEventTypeReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                HooksFacet.HookDoesNotSupportEvent.selector,
                address(beforeHook),
                IHook.GotchiEvent.AfterExecute
            )
        );
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.AfterExecute, IHook(address(beforeHook)));
    }

    function testAddMultipleHooksSameEvent() public {
        MockBeforeHook hook2 = new MockBeforeHook();

        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(hook2)));
        vm.stopPrank();

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), 2);
    }

    function testAddHookToEventsBothEvents() public {
        vm.prank(ALICE);
        hf.addHookToEvents(TOKEN_ID, IHook(address(fullHook)), true, true);

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), 1);
        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.AfterExecute), 1);
        assertTrue(hf.isHookValid(TOKEN_ID, address(fullHook)));
    }

    function testAddHookToEventsBeforeOnly() public {
        vm.prank(ALICE);
        hf.addHookToEvents(TOKEN_ID, IHook(address(fullHook)), true, false);

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), 1);
        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.AfterExecute), 0);
    }

    function testAddHookToEventsAfterOnly() public {
        vm.prank(ALICE);
        hf.addHookToEvents(TOKEN_ID, IHook(address(fullHook)), false, true);

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), 0);
        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.AfterExecute), 1);
    }

    function testAddHookToEventsZeroAddressReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(HooksFacet.InvalidHookAddress.selector);
        hf.addHookToEvents(TOKEN_ID, IHook(address(0)), true, true);
    }

    function testAddHookToEventsDuplicateReverts() public {
        vm.startPrank(ALICE);
        hf.addHookToEvents(TOKEN_ID, IHook(address(fullHook)), true, true);

        vm.expectRevert(
            abi.encodeWithSelector(HooksFacet.HookAlreadyExists.selector, TOKEN_ID, address(fullHook))
        );
        hf.addHookToEvents(TOKEN_ID, IHook(address(fullHook)), true, false);
        vm.stopPrank();
    }

    function testAddHookToEventsWrongPermissionReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                HooksFacet.HookDoesNotSupportEvent.selector,
                address(beforeHook),
                IHook.GotchiEvent.AfterExecute
            )
        );
        hf.addHookToEvents(TOKEN_ID, IHook(address(beforeHook)), false, true);
    }

    function testAddHookToEventsOnlyOwner() public {
        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        hf.addHookToEvents(TOKEN_ID, IHook(address(fullHook)), true, true);
    }

    function testRemoveHook() public {
        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        hf.removeHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        vm.stopPrank();

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), 0);
        assertFalse(hf.isHookValid(TOKEN_ID, address(beforeHook)));
    }

    function testRemoveHookEmitsEvent() public {
        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));

        vm.expectEmit(true, true, true, false, address(diamond));
        emit HooksFacet.HookRemoved(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, address(beforeHook));
        hf.removeHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        vm.stopPrank();
    }

    function testRemoveHookNotFoundReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(HooksFacet.HookNotFound.selector, TOKEN_ID, address(beforeHook))
        );
        hf.removeHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
    }

    function testRemoveHookOnlyOwner() public {
        vm.prank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));

        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        hf.removeHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
    }

    function testRemoveHookFromOneEventKeepsValidInOther() public {
        vm.startPrank(ALICE);
        hf.addHookToEvents(TOKEN_ID, IHook(address(fullHook)), true, true);

        hf.removeHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(fullHook)));
        vm.stopPrank();

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), 0);
        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.AfterExecute), 1);
        assertTrue(hf.isHookValid(TOKEN_ID, address(fullHook)));
    }

    function testRemoveHookSwapAndPop() public {
        MockBeforeHook hook2 = new MockBeforeHook();
        MockBeforeHook hook3 = new MockBeforeHook();

        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(hook2)));
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(hook3)));

        hf.removeHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(hook2)));
        vm.stopPrank();

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), 2);
        address[] memory hooks = hf.getHooks(TOKEN_ID, IHook.GotchiEvent.BeforeExecute);
        assertEq(hooks[0], address(beforeHook));
        assertEq(hooks[1], address(hook3));
    }

    function testRemoveHookCompletely() public {
        vm.startPrank(ALICE);
        hf.addHookToEvents(TOKEN_ID, IHook(address(fullHook)), true, true);
        hf.removeHookCompletely(TOKEN_ID, IHook(address(fullHook)));
        vm.stopPrank();

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), 0);
        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.AfterExecute), 0);
        assertFalse(hf.isHookValid(TOKEN_ID, address(fullHook)));
    }

    function testRemoveHookCompletelyNotRegisteredReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(HooksFacet.HookNotFound.selector, TOKEN_ID, address(fullHook))
        );
        hf.removeHookCompletely(TOKEN_ID, IHook(address(fullHook)));
    }

    function testRemoveHookCompletelyOnlyOwner() public {
        vm.prank(ALICE);
        hf.addHookToEvents(TOKEN_ID, IHook(address(fullHook)), true, true);

        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        hf.removeHookCompletely(TOKEN_ID, IHook(address(fullHook)));
    }

    function testRemoveHookCompletelyForSingleEventHook() public {
        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        hf.removeHookCompletely(TOKEN_ID, IHook(address(beforeHook)));
        vm.stopPrank();

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), 0);
        assertFalse(hf.isHookValid(TOKEN_ID, address(beforeHook)));
    }

    function testSetHookApprovalDisable() public {
        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        hf.setHookApproval(TOKEN_ID, IHook(address(beforeHook)), false);
        vm.stopPrank();

        assertFalse(hf.isHookValid(TOKEN_ID, address(beforeHook)));
    }

    function testSetHookApprovalReEnable() public {
        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        hf.setHookApproval(TOKEN_ID, IHook(address(beforeHook)), false);
        hf.setHookApproval(TOKEN_ID, IHook(address(beforeHook)), true);
        vm.stopPrank();

        assertTrue(hf.isHookValid(TOKEN_ID, address(beforeHook)));
    }

    function testSetHookApprovalEmitsEvent() public {
        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));

        vm.expectEmit(true, true, false, true, address(diamond));
        emit HooksFacet.HookApprovalChanged(TOKEN_ID, address(beforeHook), false);
        hf.setHookApproval(TOKEN_ID, IHook(address(beforeHook)), false);
        vm.stopPrank();
    }

    function testSetHookApprovalDisableUnregisteredReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(HooksFacet.HookNotFound.selector, TOKEN_ID, address(beforeHook))
        );
        hf.setHookApproval(TOKEN_ID, IHook(address(beforeHook)), false);
    }

    function testSetHookApprovalTrueForUnregisteredReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(HooksFacet.HookNotFound.selector, TOKEN_ID, address(beforeHook))
        );
        hf.setHookApproval(TOKEN_ID, IHook(address(beforeHook)), true);
    }

    function testSetHookApprovalOnlyOwner() public {
        vm.prank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));

        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        hf.setHookApproval(TOKEN_ID, IHook(address(beforeHook)), false);
    }

    function testGetHooksEmpty() public view {
        address[] memory hooks = hf.getHooks(TOKEN_ID, IHook.GotchiEvent.BeforeExecute);
        assertEq(hooks.length, 0);
    }

    function testGetHooksReturnsList() public {
        MockBeforeHook hook2 = new MockBeforeHook();
        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(hook2)));
        vm.stopPrank();

        address[] memory hooks = hf.getHooks(TOKEN_ID, IHook.GotchiEvent.BeforeExecute);
        assertEq(hooks.length, 2);
        assertEq(hooks[0], address(beforeHook));
        assertEq(hooks[1], address(hook2));
    }

    function testGetActiveHooksFiltersDisabled() public {
        MockBeforeHook hook2 = new MockBeforeHook();
        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(hook2)));
        hf.setHookApproval(TOKEN_ID, IHook(address(beforeHook)), false);
        vm.stopPrank();

        address[] memory active = hf.getActiveHooks(TOKEN_ID, IHook.GotchiEvent.BeforeExecute);
        assertEq(active.length, 1);
        assertEq(active[0], address(hook2));
    }

    function testGetActiveHooksAllDisabled() public {
        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        hf.setHookApproval(TOKEN_ID, IHook(address(beforeHook)), false);
        vm.stopPrank();

        address[] memory active = hf.getActiveHooks(TOKEN_ID, IHook.GotchiEvent.BeforeExecute);
        assertEq(active.length, 0);
    }

    function testIsHookValidDefault() public view {
        assertFalse(hf.isHookValid(TOKEN_ID, address(beforeHook)));
    }

    function testGetHookCountEmpty() public view {
        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), 0);
        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.AfterExecute), 0);
    }

    function testExecuteWithBeforeOnlyHook() public {
        HookTestReceiver receiver = new HookTestReceiver();

        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0.01 ether,
            IHook(address(beforeHook)),
            ""
        );
        vm.stopPrank();

        assertEq(address(receiver).balance, 0.01 ether);
        assertEq(beforeHook.callCount(), 1);
    }

    function testExecuteWithAfterOnlyHook() public {
        HookTestReceiver receiver = new HookTestReceiver();

        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.AfterExecute, IHook(address(afterHook)));
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0.01 ether,
            IHook(address(afterHook)),
            ""
        );
        vm.stopPrank();

        assertEq(address(receiver).balance, 0.01 ether);
        assertEq(afterHook.callCount(), 1);
    }

    function testExecuteWithFullHook() public {
        HookTestReceiver receiver = new HookTestReceiver();

        vm.startPrank(ALICE);
        hf.addHookToEvents(TOKEN_ID, IHook(address(fullHook)), true, true);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0.01 ether,
            IHook(address(fullHook)),
            ""
        );
        vm.stopPrank();

        assertEq(fullHook.beforeCount(), 1);
        assertEq(fullHook.afterCount(), 1);
    }

    function testExecuteWithZeroHookSkipsHookExecution() public {
        HookTestReceiver receiver = new HookTestReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0.01 ether,
            IHook(address(0)),
            ""
        );
        vm.stopPrank();

        assertEq(address(receiver).balance, 0.01 ether);
    }

    function testExecuteWithUnregisteredHookReverts() public {
        HookTestReceiver receiver = new HookTestReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        vm.expectRevert();
        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0.01 ether,
            IHook(address(beforeHook)),
            ""
        );
        vm.stopPrank();
    }

    function testExecuteWithRevertingHookReverts() public {
        HookTestReceiver receiver = new HookTestReceiver();

        vm.startPrank(ALICE);
        hf.addHookToEvents(TOKEN_ID, IHook(address(revertingHook)), true, true);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        vm.expectRevert(); // HookCallFailed
        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0.01 ether,
            IHook(address(revertingHook)),
            ""
        );
        vm.stopPrank();
    }

    function testExecuteWithBadMagicHookReverts() public {
        HookTestReceiver receiver = new HookTestReceiver();

        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(badMagicHook)));
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        vm.expectRevert(); // InvalidHookResponse
        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0.01 ether,
            IHook(address(badMagicHook)),
            ""
        );
        vm.stopPrank();
    }

    function testExecuteWithDisabledHookReverts() public {
        HookTestReceiver receiver = new HookTestReceiver();

        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        hf.setHookApproval(TOKEN_ID, IHook(address(beforeHook)), false);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        vm.expectRevert(); // HookNotFound (isValidHook = false)
        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0.01 ether,
            IHook(address(beforeHook)),
            ""
        );
        vm.stopPrank();
    }

    function testHookIsolationBetweenTokens() public {
        // address tba2 = _summonGotchipus(1);

        vm.startPrank(ALICE);
        hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(beforeHook)));
        vm.stopPrank();

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), 1);
        assertEq(hf.getHookCount(1, IHook.GotchiEvent.BeforeExecute), 0);
        assertTrue(hf.isHookValid(TOKEN_ID, address(beforeHook)));
        assertFalse(hf.isHookValid(1, address(beforeHook)));
    }

    function testFuzz_AddAndRemoveMultipleHooks(uint8 count) public {
        count = uint8(bound(uint256(count), 1, 10));

        MockBeforeHook[] memory hooks = new MockBeforeHook[](count);
        vm.startPrank(ALICE);
        for (uint256 i; i < count; i++) {
            hooks[i] = new MockBeforeHook();
            hf.addHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(hooks[i])));
        }
        vm.stopPrank();

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), count);

        vm.startPrank(ALICE);
        for (uint256 i = count; i > 0; i--) {
            hf.removeHook(TOKEN_ID, IHook.GotchiEvent.BeforeExecute, IHook(address(hooks[i - 1])));
        }
        vm.stopPrank();

        assertEq(hf.getHookCount(TOKEN_ID, IHook.GotchiEvent.BeforeExecute), 0);
    }
}
