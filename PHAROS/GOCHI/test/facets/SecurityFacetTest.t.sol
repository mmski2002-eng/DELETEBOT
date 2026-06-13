// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../utils/DiamondFixture.sol";
import { ALICE } from "../utils/Constants.sol";
import { SecurityFacet } from "../../src/facets/SecurityFacet.sol";
import { LibSecurity, SecurityOption, Session, TransferLimitConfig } from "../../src/libraries/LibSecurity.sol";

contract SecurityFacetTest is DiamondFixture {
    address internal BOB = address(0xB0B);
    address internal CAROL = address(0xCA201);
    address internal TARGET1 = address(0x1111);
    address internal TARGET2 = address(0x2222);
    address internal TARGET3 = address(0x3333);

    address[] internal EMPTY_LIST;
    address[] internal WHITELIST_TARGETS;
    address[] internal BLACKLIST_TARGETS;

    SecurityFacet internal sf;
    uint256 constant TOKEN_ID = 0;

    function setUp() public override {
        super.setUp();
        sf = SecurityFacet(address(diamond));
        vm.deal(ALICE, 200 ether);
        _summonGotchipus(TOKEN_ID);
    }

    function testBuildOptionsNone() public view {
        uint256 opts = sf.buildOptions(false, false, false, false);
        assertEq(opts, 0);
    }

    function testBuildOptionsAll() public view {
        uint256 opts = sf.buildOptions(true, true, true, true);
        // bit 0 + bit 1 + bit 2 + bit 3 = 0b1111 = 15
        assertEq(opts, 15);
    }

    function testBuildOptionsSingle() public view {
        assertEq(sf.buildOptions(true, false, false, false), 1);  // bit 0
        assertEq(sf.buildOptions(false, true, false, false), 2);  // bit 1
        assertEq(sf.buildOptions(false, false, true, false), 4);  // bit 2
        assertEq(sf.buildOptions(false, false, false, true), 8);  // bit 3
    }

    function testSetOptionEnable() public {
        vm.prank(ALICE);
        sf.setOption(TOKEN_ID, SecurityOption.BlockInfiniteApproval, true);
        assertTrue(sf.isEnabled(TOKEN_ID, SecurityOption.BlockInfiniteApproval));
    }

    function testSetOptionDisable() public {
        vm.startPrank(ALICE);
        sf.setOption(TOKEN_ID, SecurityOption.BlockInfiniteApproval, true);
        sf.setOption(TOKEN_ID, SecurityOption.BlockInfiniteApproval, false);
        vm.stopPrank();
        assertFalse(sf.isEnabled(TOKEN_ID, SecurityOption.BlockInfiniteApproval));
    }

    function testSetOptionMultiple() public {
        vm.startPrank(ALICE);
        sf.setOption(TOKEN_ID, SecurityOption.BlockInfiniteApproval, true);
        sf.setOption(TOKEN_ID, SecurityOption.DailyTransferLimit, true);
        sf.setOption(TOKEN_ID, SecurityOption.SingleTxLimit, true);
        sf.setOption(TOKEN_ID, SecurityOption.RestrictTarget, true);
        vm.stopPrank();

        assertTrue(sf.isEnabled(TOKEN_ID, SecurityOption.BlockInfiniteApproval));
        assertTrue(sf.isEnabled(TOKEN_ID, SecurityOption.DailyTransferLimit));
        assertTrue(sf.isEnabled(TOKEN_ID, SecurityOption.SingleTxLimit));
        assertTrue(sf.isEnabled(TOKEN_ID, SecurityOption.RestrictTarget));
    }

    function testSetOptionIndependent() public {
        vm.startPrank(ALICE);
        sf.setOption(TOKEN_ID, SecurityOption.BlockInfiniteApproval, true);
        sf.setOption(TOKEN_ID, SecurityOption.DailyTransferLimit, true);
        sf.setOption(TOKEN_ID, SecurityOption.BlockInfiniteApproval, false);
        vm.stopPrank();

        assertFalse(sf.isEnabled(TOKEN_ID, SecurityOption.BlockInfiniteApproval));
        assertTrue(sf.isEnabled(TOKEN_ID, SecurityOption.DailyTransferLimit));
    }

    function testSetOptionOnlyOwner() public {
        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        sf.setOption(TOKEN_ID, SecurityOption.BlockInfiniteApproval, true);
    }

    function testSetPolicyBatch() public {
        uint256 opts = sf.buildOptions(true, true, false, false);
        vm.prank(ALICE);
        sf.setPolicy(TOKEN_ID, opts);
        assertEq(sf.getEnabledOptions(TOKEN_ID), opts);
        assertTrue(sf.isEnabled(TOKEN_ID, SecurityOption.BlockInfiniteApproval));
        assertTrue(sf.isEnabled(TOKEN_ID, SecurityOption.DailyTransferLimit));
        assertFalse(sf.isEnabled(TOKEN_ID, SecurityOption.SingleTxLimit));
    }

    function testSetPolicyOverwrite() public {
        vm.startPrank(ALICE);
        sf.setPolicy(TOKEN_ID, 15); // all on
        sf.setPolicy(TOKEN_ID, 0);  // all off
        vm.stopPrank();
        assertEq(sf.getEnabledOptions(TOKEN_ID), 0);
    }

    function testSetPolicyOnlyOwner() public {
        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        sf.setPolicy(TOKEN_ID, 15);
    }

    function testCreateSession() public {
        vm.prank(ALICE);
        sf.createSession(TOKEN_ID, BOB, 1 hours, 1 ether, 10 ether, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        Session memory ses = sf.getSession(TOKEN_ID, BOB);
        assertTrue(ses.active);
        assertEq(ses.expiresAt, uint32(block.timestamp) + 1 hours);
        assertEq(ses.maxValuePerTx, 1 ether);
        assertEq(ses.maxValuePerSession, 10 ether);
        assertEq(ses.usedValue, 0);
    }

    function testCreateSessionZeroAddressReverts() public {
        vm.prank(ALICE);
        vm.expectRevert("LibSecurity: zero address");
        sf.createSession(TOKEN_ID, address(0), 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
    }

    function testCreateSessionZeroDurationReverts() public {
        vm.prank(ALICE);
        vm.expectRevert("LibSecurity: zero duration");
        sf.createSession(TOKEN_ID, BOB, 0, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
    }

    function testCreateSessionOverwrite() public {
        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, BOB, 1 hours, 1 ether, 10 ether, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        sf.createSession(TOKEN_ID, BOB, 2 hours, 2 ether, 20 ether, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        vm.stopPrank();

        Session memory ses = sf.getSession(TOKEN_ID, BOB);
        assertEq(ses.maxValuePerTx, 2 ether);
        assertEq(ses.maxValuePerSession, 20 ether);
        assertEq(ses.usedValue, 0); // reset
    }

    function testCreateSessionOnlyOwner() public {
        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        sf.createSession(TOKEN_ID, BOB, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
    }

    function testRevokeSession() public {
        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, BOB, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        sf.revokeSession(TOKEN_ID, BOB);
        vm.stopPrank();

        Session memory ses = sf.getSession(TOKEN_ID, BOB);
        assertFalse(ses.active);
    }

    function testRevokeSessionOnlyOwner() public {
        vm.prank(ALICE);
        sf.createSession(TOKEN_ID, BOB, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        sf.revokeSession(TOKEN_ID, BOB);
    }

    function testCreateSessionUnlimited() public {
        vm.prank(ALICE);
        sf.createSession(TOKEN_ID, BOB, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        Session memory ses = sf.getSession(TOKEN_ID, BOB);
        assertEq(ses.maxValuePerTx, 0);
        assertEq(ses.maxValuePerSession, 0);
    }

    function testAddTargetWhitelist() public {
        vm.prank(ALICE);
        sf.addTargetWhitelist(TOKEN_ID, TARGET1);
        assertTrue(sf.isTargetWhitelist(TOKEN_ID, TARGET1));
    }

    function testAddMultipleWhitelists() public {
        vm.startPrank(ALICE);
        sf.addTargetWhitelist(TOKEN_ID, TARGET1);
        sf.addTargetWhitelist(TOKEN_ID, TARGET2);
        sf.addTargetWhitelist(TOKEN_ID, TARGET3);
        vm.stopPrank();

        assertTrue(sf.isTargetWhitelist(TOKEN_ID, TARGET1));
        assertTrue(sf.isTargetWhitelist(TOKEN_ID, TARGET2));
        assertTrue(sf.isTargetWhitelist(TOKEN_ID, TARGET3));

        address[] memory all = sf.allTargetWhitelists(TOKEN_ID);
        assertEq(all.length, 3);
    }

    function testAddDuplicateWhitelistReverts() public {
        vm.startPrank(ALICE);
        sf.addTargetWhitelist(TOKEN_ID, TARGET1);
        vm.expectRevert("already whitelisted");
        sf.addTargetWhitelist(TOKEN_ID, TARGET1);
        vm.stopPrank();
    }

    function testRemoveTargetWhitelist() public {
        vm.startPrank(ALICE);
        sf.addTargetWhitelist(TOKEN_ID, TARGET1);
        sf.removeTargetWhitelist(TOKEN_ID, TARGET1);
        vm.stopPrank();

        assertFalse(sf.isTargetWhitelist(TOKEN_ID, TARGET1));
        address[] memory all = sf.allTargetWhitelists(TOKEN_ID);
        assertEq(all.length, 0);
    }

    function testRemoveNonexistentWhitelistReverts() public {
        vm.prank(ALICE);
        vm.expectRevert("not exists");
        sf.removeTargetWhitelist(TOKEN_ID, TARGET1);
    }

    function testRemoveWhitelistMiddle() public {
        vm.startPrank(ALICE);
        sf.addTargetWhitelist(TOKEN_ID, TARGET1);
        sf.addTargetWhitelist(TOKEN_ID, TARGET2);
        sf.addTargetWhitelist(TOKEN_ID, TARGET3);
        sf.removeTargetWhitelist(TOKEN_ID, TARGET2);
        vm.stopPrank();

        assertFalse(sf.isTargetWhitelist(TOKEN_ID, TARGET2));
        assertTrue(sf.isTargetWhitelist(TOKEN_ID, TARGET1));
        assertTrue(sf.isTargetWhitelist(TOKEN_ID, TARGET3));

        address[] memory all = sf.allTargetWhitelists(TOKEN_ID);
        assertEq(all.length, 2);
    }

    function testAddWhitelistOnlyOwner() public {
        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        sf.addTargetWhitelist(TOKEN_ID, TARGET1);
    }

    function testRemoveWhitelistOnlyOwner() public {
        vm.prank(ALICE);
        sf.addTargetWhitelist(TOKEN_ID, TARGET1);

        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        sf.removeTargetWhitelist(TOKEN_ID, TARGET1);
    }

    function testAddTargetBlacklist() public {
        vm.prank(ALICE);
        sf.addTargetBlacklist(TOKEN_ID, TARGET1);
        assertTrue(sf.isTargetBlacklist(TOKEN_ID, TARGET1));
    }

    function testAddMultipleBlacklists() public {
        vm.startPrank(ALICE);
        sf.addTargetBlacklist(TOKEN_ID, TARGET1);
        sf.addTargetBlacklist(TOKEN_ID, TARGET2);
        vm.stopPrank();

        address[] memory all = sf.allTargetBlacklists(TOKEN_ID);
        assertEq(all.length, 2);
    }

    function testAddDuplicateBlacklistReverts() public {
        vm.startPrank(ALICE);
        sf.addTargetBlacklist(TOKEN_ID, TARGET1);
        vm.expectRevert("already blacklisted");
        sf.addTargetBlacklist(TOKEN_ID, TARGET1);
        vm.stopPrank();
    }

    function testRemoveTargetBlacklist() public {
        vm.startPrank(ALICE);
        sf.addTargetBlacklist(TOKEN_ID, TARGET1);
        sf.removeTargetBlacklist(TOKEN_ID, TARGET1);
        vm.stopPrank();

        assertFalse(sf.isTargetBlacklist(TOKEN_ID, TARGET1));
        assertEq(sf.allTargetBlacklists(TOKEN_ID).length, 0);
    }

    function testRemoveNonexistentBlacklistReverts() public {
        vm.prank(ALICE);
        vm.expectRevert("not exists");
        sf.removeTargetBlacklist(TOKEN_ID, TARGET1);
    }

    function testRemoveBlacklistMiddle() public {
        vm.startPrank(ALICE);
        sf.addTargetBlacklist(TOKEN_ID, TARGET1);
        sf.addTargetBlacklist(TOKEN_ID, TARGET2);
        sf.addTargetBlacklist(TOKEN_ID, TARGET3);
        sf.removeTargetBlacklist(TOKEN_ID, TARGET2);
        vm.stopPrank();

        assertFalse(sf.isTargetBlacklist(TOKEN_ID, TARGET2));
        assertTrue(sf.isTargetBlacklist(TOKEN_ID, TARGET1));
        assertTrue(sf.isTargetBlacklist(TOKEN_ID, TARGET3));
        assertEq(sf.allTargetBlacklists(TOKEN_ID).length, 2);
    }

    function testAddBlacklistOnlyOwner() public {
        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        sf.addTargetBlacklist(TOKEN_ID, TARGET1);
    }

    function testWhitelistModeDefaultFalse() public view {
        assertFalse(sf.getWhitelistMode(TOKEN_ID));
    }

    function testGetTransferLimitDefault() public view {
        TransferLimitConfig memory cfg = sf.getTransferLimit(TOKEN_ID);
        assertEq(cfg.dailyLimit, 0);
        assertEq(cfg.singleTxLimit, 0);
        assertEq(cfg.usedToday, 0);
    }

    function testPoliciesIsolatedPerToken() public {
        // summon token 1
        vm.deal(ALICE, 500 ether);
        vm.startPrank(ALICE);
        IMintFacet(address(diamond)).summonGotchipus{value: 0.1 ether}(
            IMintFacet.SummonArgs({
                gotchipusTokenId: 1,
                gotchiName: "G2",
                collateralToken: address(0),
                stakeAmount: 0.1 ether,
                utc: 0,
                story: "g2",
                preIndex: 0
            })
        );

        sf.setOption(0, SecurityOption.BlockInfiniteApproval, true);
        vm.stopPrank();

        assertTrue(sf.isEnabled(0, SecurityOption.BlockInfiniteApproval));
        assertFalse(sf.isEnabled(1, SecurityOption.BlockInfiniteApproval));
    }

    function testFuzz_AddRemoveWhitelist(uint8 count) public {
        count = uint8(bound(uint256(count), 1, 20));
        vm.startPrank(ALICE);
        address[] memory targets = new address[](count);
        for (uint256 i; i < count; i++) {
            targets[i] = address(uint160(0x10000 + i));
            sf.addTargetWhitelist(TOKEN_ID, targets[i]);
        }
        assertEq(sf.allTargetWhitelists(TOKEN_ID).length, count);

        for (uint256 i; i < count; i++) {
            sf.removeTargetWhitelist(TOKEN_ID, targets[i]);
        }
        assertEq(sf.allTargetWhitelists(TOKEN_ID).length, 0);
        vm.stopPrank();
    }

    function testFuzz_SessionDuration(uint32 dur) public {
        dur = uint32(bound(uint256(dur), 1, type(uint32).max / 2));
        vm.prank(ALICE);
        sf.createSession(TOKEN_ID, BOB, dur, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        Session memory ses = sf.getSession(TOKEN_ID, BOB);
        assertEq(ses.expiresAt, uint32(block.timestamp) + dur);
        assertTrue(ses.active);
    }

    function testCreateSessionWithWhitelist() public {
        address[] memory wl = new address[](3);
        wl[0] = TARGET1;
        wl[1] = TARGET2;
        wl[2] = TARGET3;

        uint256 opts = sf.buildOptions(true, false, false, true); // blockInfinite + restrictTarget

        vm.prank(ALICE);
        sf.createSession(TOKEN_ID, BOB, 1 hours, 1 ether, 10 ether, 0, 0, opts, true, wl, EMPTY_LIST);

        Session memory ses = sf.getSession(TOKEN_ID, BOB);
        assertTrue(ses.active);
        assertEq(ses.maxValuePerTx, 1 ether);

        assertTrue(sf.isEnabled(TOKEN_ID, SecurityOption.BlockInfiniteApproval));
        assertTrue(sf.isEnabled(TOKEN_ID, SecurityOption.RestrictTarget));
        assertTrue(sf.getWhitelistMode(TOKEN_ID));
        assertTrue(sf.isTargetWhitelist(TOKEN_ID, TARGET1));
        assertTrue(sf.isTargetWhitelist(TOKEN_ID, TARGET2));
        assertTrue(sf.isTargetWhitelist(TOKEN_ID, TARGET3));
        assertEq(sf.allTargetWhitelists(TOKEN_ID).length, 3);
    }

    function testCreateSessionWithBlacklist() public {
        address[] memory bl = new address[](2);
        bl[0] = TARGET1;
        bl[1] = TARGET2;

        uint256 opts = sf.buildOptions(false, true, true, true); // daily + singleTx + restrictTarget

        vm.prank(ALICE);
        sf.createSession(TOKEN_ID, BOB, 2 hours, 0, 0, 5 ether, 1 ether, opts, false, EMPTY_LIST, bl);

        Session memory ses = sf.getSession(TOKEN_ID, BOB);
        assertTrue(ses.active);

        assertTrue(sf.isEnabled(TOKEN_ID, SecurityOption.DailyTransferLimit));
        assertTrue(sf.isEnabled(TOKEN_ID, SecurityOption.SingleTxLimit));
        assertTrue(sf.isEnabled(TOKEN_ID, SecurityOption.RestrictTarget));
        assertFalse(sf.getWhitelistMode(TOKEN_ID));
        assertTrue(sf.isTargetBlacklist(TOKEN_ID, TARGET1));
        assertTrue(sf.isTargetBlacklist(TOKEN_ID, TARGET2));
        assertEq(sf.allTargetBlacklists(TOKEN_ID).length, 2);

        TransferLimitConfig memory cfg = sf.getTransferLimit(TOKEN_ID);
        assertEq(cfg.dailyLimit, 5 ether);
        assertEq(cfg.singleTxLimit, 1 ether);
    }

    function testCreateSessionWhitelistBlacklistConflictReverts() public {
        address[] memory wl = new address[](1);
        wl[0] = TARGET1;
        address[] memory bl = new address[](1);
        bl[0] = TARGET2;

        vm.prank(ALICE);
        vm.expectRevert(LibSecurity.WhitelistBlacklistConflict.selector);
        sf.createSession(TOKEN_ID, BOB, 1 hours, 0, 0, 0, 0, 0, false, wl, bl);
    }

    function testCreateSessionListModeMismatchReverts() public {
        address[] memory bl = new address[](1);
        bl[0] = TARGET1;

        vm.prank(ALICE);
        vm.expectRevert(LibSecurity.ListModeMismatch.selector);
        sf.createSession(TOKEN_ID, BOB, 1 hours, 0, 0, 0, 0, 0, true, EMPTY_LIST, bl);
    }

    function testCreateSessionWhitelistModeMismatchReverts() public {
        address[] memory wl = new address[](1);
        wl[0] = TARGET1;

        vm.prank(ALICE);
        vm.expectRevert(LibSecurity.ListModeMismatch.selector);
        sf.createSession(TOKEN_ID, BOB, 1 hours, 0, 0, 0, 0, 0, false, wl, EMPTY_LIST);
    }

    function testCreateSessionDuplicateWhitelistSkips() public {
        address[] memory wl = new address[](3);
        wl[0] = TARGET1;
        wl[1] = TARGET1;
        wl[2] = TARGET2;

        vm.prank(ALICE);
        sf.createSession(TOKEN_ID, BOB, 1 hours, 0, 0, 0, 0, 0, true, wl, EMPTY_LIST);

        assertEq(sf.allTargetWhitelists(TOKEN_ID).length, 2);
        assertTrue(sf.isTargetWhitelist(TOKEN_ID, TARGET1));
        assertTrue(sf.isTargetWhitelist(TOKEN_ID, TARGET2));
    }

    function testFuzz_BuildOptionsRoundTrip(
        bool a, bool b, bool c, bool d
    ) public view {
        uint256 opts = sf.buildOptions(a, b, c, d);
        uint256 expected;
        if (a) expected |= 1;
        if (b) expected |= 2;
        if (c) expected |= 4;
        if (d) expected |= 8;
        assertEq(opts, expected);
    }
}
