// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../utils/DiamondFixture.sol";
import { ALICE } from "../utils/Constants.sol";
import { IMintFacet } from "../../src/interfaces/IMintFacet.sol";
import { IERC6551Facet } from "../../src/interfaces/IERC6551Facet.sol";
import { IERC6551Account } from "../../src/interfaces/IERC6551Account.sol";
import { ERC6551Facet } from "../../src/facets/ERC6551Facet.sol";
import { SecurityFacet } from "../../src/facets/SecurityFacet.sol";
import { SecurityOption, Session, TransferLimitConfig } from "../../src/libraries/LibSecurity.sol";
import { IHook } from "../../src/interfaces/IHook.sol";
import { MockERC20 } from "../utils/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ETHReceiver {
    receive() external payable {}
}

contract ERC6551FacetTest is DiamondFixture {
    address internal BOB = address(0xB0B);

    ERC6551Facet internal ef;
    SecurityFacet internal sf;
    uint256 constant TOKEN_ID = 0;
    address internal tba;
    address[] internal EMPTY_LIST;

    function setUp() public override {
        super.setUp();
        ef = ERC6551Facet(address(diamond));
        sf = SecurityFacet(address(diamond));
        vm.deal(ALICE, 500 ether);
        vm.deal(BOB, 500 ether);

        tba = _summonGotchipus(TOKEN_ID);
    }

    function testAccountReturnsCorrectAddress() public view {
        address acc = IERC6551Facet(address(diamond)).account(TOKEN_ID);
        assertEq(acc, tba);
        assertTrue(acc != address(0));
    }

    function testAccountUnsummonedReturnsZero() public view {
        address acc = IERC6551Facet(address(diamond)).account(1);
        assertEq(acc, address(0));
    }

    function testAccountOwnerIsAlice() public view {
        IERC6551Account acc = IERC6551Account(payable(tba));
        assertEq(acc.owner(), ALICE);
    }

    function testAccountHasBalance() public view {
        assertEq(tba.balance, 0.1 ether);
    }

    function testExecuteAccountWithoutSessionReverts() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.prank(ALICE);
        vm.expectRevert();
        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0.01 ether,
            IHook(address(0)),
            ""
        );
    }

    function testExecuteAccountWithSession() public {
        ETHReceiver receiver = new ETHReceiver();

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

    function testExecuteAccountInvalidAccountReverts() public {
        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        vm.expectRevert("ERC6551Facet: Invalid account");
        ef.executeAccount(
            address(0),
            TOKEN_ID,
            address(1),
            0,
            IHook(address(0)),
            ""
        );
        vm.stopPrank();
    }

    function testExecuteAccountInvalidToReverts() public {
        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        vm.expectRevert("ERC6551Facet: Invalid to");
        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(0),
            0,
            IHook(address(0)),
            ""
        );
        vm.stopPrank();
    }

    function testExecuteAccountNonOwnerReverts() public {
        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only gotchi owner or paymaster");
        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(1),
            0,
            IHook(address(0)),
            ""
        );
    }

    function testExecuteAccountExpiredSessionReverts() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        vm.stopPrank();

        skip(1 hours + 1);

        vm.prank(ALICE);
        vm.expectRevert(); // SessionExpired
        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0,
            IHook(address(0)),
            ""
        );
    }

    function testExecuteAccountRevokedSessionReverts() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        sf.revokeSession(TOKEN_ID, ALICE);
        vm.stopPrank();

        vm.prank(ALICE);
        vm.expectRevert(); // SessionNotActive
        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0,
            IHook(address(0)),
            ""
        );
    }

    function testBlockInfiniteApproval() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        sf.setOption(TOKEN_ID, SecurityOption.BlockInfiniteApproval, true);

        bytes memory approveData = abi.encodeWithSelector(
            0x095ea7b3,
            address(receiver),
            type(uint256).max
        );

        vm.expectRevert(); // InfiniteApprovalBlocked
        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0,
            IHook(address(0)),
            approveData
        );
        vm.stopPrank();
    }

    function testAllowFiniteApproval() public {
        MockERC20 token = new MockERC20("Test Token", "TT");
        token.mint(tba, 10000 ether);

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        sf.setOption(TOKEN_ID, SecurityOption.BlockInfiniteApproval, true);

        bytes memory approveData = abi.encodeWithSelector(
            IERC20.approve.selector,
            BOB,
            1000 ether
        );

        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(token),
            0,
            IHook(address(0)),
            approveData
        );
        vm.stopPrank();

        assertEq(token.allowance(tba, BOB), 1000 ether);
    }

    function testFiniteApprovalLimitsTransferFrom() public {
        MockERC20 token = new MockERC20("Test Token", "TT");
        token.mint(tba, 10000 ether);
        address CAROL = address(0xCA201);

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        sf.setOption(TOKEN_ID, SecurityOption.BlockInfiniteApproval, true);

        bytes memory approveData = abi.encodeWithSelector(
            IERC20.approve.selector,
            BOB,
            1000 ether
        );
        ef.executeAccount(tba, TOKEN_ID, address(token), 0, IHook(address(0)), approveData);
        vm.stopPrank();

        vm.prank(BOB);
        token.transferFrom(tba, CAROL, 600 ether);
        assertEq(token.balanceOf(CAROL), 600 ether);
        assertEq(token.allowance(tba, BOB), 400 ether);

        vm.prank(BOB);
        vm.expectRevert();
        token.transferFrom(tba, CAROL, 401 ether);

        vm.prank(BOB);
        token.transferFrom(tba, CAROL, 400 ether);
        assertEq(token.balanceOf(CAROL), 1000 ether);
        assertEq(token.allowance(tba, BOB), 0);
    }

    function testRestrictTargetBlacklistMode() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        sf.setOption(TOKEN_ID, SecurityOption.RestrictTarget, true);
        sf.addTargetBlacklist(TOKEN_ID, address(receiver));

        vm.expectRevert(); // TargetNotAllowed
        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0.01 ether,
            IHook(address(0)),
            ""
        );
        vm.stopPrank();
    }

    function testRestrictTargetBlacklistAllowed() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        sf.setOption(TOKEN_ID, SecurityOption.RestrictTarget, true);

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

    function testSessionPerTxLimitExceeded() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        // maxPerTx = 0.01 ether
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0.01 ether, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        vm.expectRevert(); // SingleTxLimitExceeded
        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            0.02 ether,
            IHook(address(0)),
            ""
        );
        vm.stopPrank();
    }

    function testSessionPerTxLimitAllowed() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0.05 ether, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

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

    function testSessionTotalLimitExceeded() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        // maxPerSession = 0.02 ether
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0.02 ether, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);

        // 1. 0.01 OK
        ef.executeAccount(tba, TOKEN_ID, address(receiver), 0.01 ether, IHook(address(0)), "");
        // 2. 0.01 OK (total 0.02)
        ef.executeAccount(tba, TOKEN_ID, address(receiver), 0.01 ether, IHook(address(0)), "");

        // 3. 0.01 → limited
        vm.expectRevert(); // SessionValueExceeded
        ef.executeAccount(tba, TOKEN_ID, address(receiver), 0.01 ether, IHook(address(0)), "");
        vm.stopPrank();
    }

    function testGlobalSingleTxLimitExceeded() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        sf.setOption(TOKEN_ID, SecurityOption.SingleTxLimit, true);

        vm.expectRevert(); // SingleTxLimitExceeded
        ef.executeAccount(tba, TOKEN_ID, address(receiver), 0.02 ether, IHook(address(0)), "");
        vm.stopPrank();
    }

    function testGlobalSingleTxLimitAllowed() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        sf.setOption(TOKEN_ID, SecurityOption.SingleTxLimit, true);
        sf.setTransferLimit(TOKEN_ID, 0, 0.05 ether);

        ef.executeAccount(tba, TOKEN_ID, address(receiver), 0.01 ether, IHook(address(0)), "");
        vm.stopPrank();

        assertEq(address(receiver).balance, 0.01 ether);
    }

    function testDailyTransferLimitExceeded() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 days, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        sf.setOption(TOKEN_ID, SecurityOption.DailyTransferLimit, true);
        sf.setTransferLimit(TOKEN_ID, 0.02 ether, 0);

        ef.executeAccount(tba, TOKEN_ID, address(receiver), 0.01 ether, IHook(address(0)), "");
        ef.executeAccount(tba, TOKEN_ID, address(receiver), 0.01 ether, IHook(address(0)), "");
        vm.expectRevert(); // DailyLimitExceeded
        ef.executeAccount(tba, TOKEN_ID, address(receiver), 0.01 ether, IHook(address(0)), "");
        vm.stopPrank();
    }

    function testDailyTransferLimitResetsAfter24Hours() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 2 days, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        sf.setOption(TOKEN_ID, SecurityOption.DailyTransferLimit, true);
        sf.setTransferLimit(TOKEN_ID, 0.02 ether, 0);

        ef.executeAccount(tba, TOKEN_ID, address(receiver), 0.02 ether, IHook(address(0)), "");

        vm.expectRevert();
        ef.executeAccount(tba, TOKEN_ID, address(receiver), 0.01 ether, IHook(address(0)), "");

        skip(1 days);
        ef.executeAccount(tba, TOKEN_ID, address(receiver), 0.02 ether, IHook(address(0)), "");
        vm.stopPrank();

        assertEq(address(receiver).balance, 0.04 ether);
    }

    function testGetTransferLimitAfterSet() public {
        vm.prank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 days, 0, 0, 5 ether, 1 ether, 0, false, EMPTY_LIST, EMPTY_LIST);
        TransferLimitConfig memory cfg = sf.getTransferLimit(TOKEN_ID);
        assertEq(cfg.dailyLimit, 5 ether);
        assertEq(cfg.singleTxLimit, 1 ether);
    }

    function testMultipleSessionHolders() public {
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        sf.createSession(TOKEN_ID, BOB, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        vm.stopPrank();

        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only gotchi owner or paymaster");
        ef.executeAccount(tba, TOKEN_ID, address(receiver), 0, IHook(address(0)), "");
    }

    function testFuzz_SessionCreationAndQuery(
        uint32 dur, 
        uint256 maxTx, 
        uint256 maxSes,
        uint256 dailyLimit,
        uint256 singleTxLimit
    ) public {
        dur = uint32(bound(uint256(dur), 1, type(uint32).max / 2));

        vm.prank(ALICE);
        sf.createSession(TOKEN_ID, BOB, dur, maxTx, maxSes, dailyLimit, singleTxLimit, 0, false, EMPTY_LIST, EMPTY_LIST);

        Session memory ses = sf.getSession(TOKEN_ID, BOB);
        assertTrue(ses.active);
        assertEq(ses.maxValuePerTx, maxTx);
        assertEq(ses.maxValuePerSession, maxSes);
        assertEq(ses.expiresAt, uint32(block.timestamp) + dur);
    }

    function testFuzz_ExecuteWithinLimit(uint256 amount) public {
        amount = uint256(bound(uint256(amount), 1, 0.05 ether));
        ETHReceiver receiver = new ETHReceiver();

        vm.startPrank(ALICE);
        sf.createSession(TOKEN_ID, ALICE, 1 hours, 0, 0, 0, 0, 0, false, EMPTY_LIST, EMPTY_LIST);
        ef.executeAccount(
            tba,
            TOKEN_ID,
            address(receiver),
            amount,
            IHook(address(0)),
            ""
        );
        vm.stopPrank();

        assertEq(address(receiver).balance, amount);
    }
}
