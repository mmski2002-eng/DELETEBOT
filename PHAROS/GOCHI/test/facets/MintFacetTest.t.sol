// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../utils/DiamondFixture.sol";
import { ALICE, ZERO_ADDRESS } from "../utils/Constants.sol";
import { IMintFacet } from "../../src/interfaces/IMintFacet.sol";
import { IGotchipusFacet } from "../../src/interfaces/IGotchipusFacet.sol";
import { IERC6551Facet } from "../../src/interfaces/IERC6551Facet.sol";
import { IERC6551Account } from "../../src/interfaces/IERC6551Account.sol";
import { MetadataFacet } from "../../src/facets/MetadataFacet.sol";
import { GotchipusInfo } from "../../src/libraries/LibAppStorage.sol";
import { LibGotchiConstants } from "../../src/libraries/LibGotchiConstants.sol";

contract MintFacetTest is DiamondFixture {
    address internal BOB = address(0xB0B);
    address internal CAROL = address(0xCA201);

    IMintFacet internal mf;
    IGotchipusFacet internal gf;

    function setUp() public override {
        super.setUp();
        mf = IMintFacet(address(diamond));
        gf = IGotchipusFacet(address(diamond));
        vm.deal(ALICE, 200 ether);
        vm.deal(BOB, 200 ether);
        vm.deal(CAROL, 200 ether);
    }

    function testMintSingle() public {
        vm.prank(ALICE);
        mf.mint{value: 0.04 ether}(1);
        assertEq(gf.totalSupply(), 1);
        assertEq(gf.ownerOf(0), ALICE);
        assertEq(gf.balanceOf(ALICE), 1);
    }

    function testMintMultiple() public {
        vm.prank(ALICE);
        mf.mint{value: 0.4 ether}(10);
        assertEq(gf.totalSupply(), 10);
        assertEq(gf.balanceOf(ALICE), 10);
        for (uint256 i; i < 10; i++) {
            assertEq(gf.ownerOf(i), ALICE);
        }
    }

    function testMintMaxPerTx() public {
        // MAX_PER_MINT = 30
        vm.prank(ALICE);
        mf.mint{value: 30 * 0.04 ether}(30);
        assertEq(gf.totalSupply(), 30);
    }

    function testMintAmountZeroReverts() public {
        vm.prank(ALICE);
        vm.expectRevert("Invalid amount");
        mf.mint{value: 0}(0);
    }

    function testMintExceedsMaxPerMintReverts() public {
        vm.prank(ALICE);
        vm.expectRevert("Invalid amount");
        mf.mint{value: 31 * 0.04 ether}(31);
    }

    function testMintTokenIdsIncrement() public {
        vm.startPrank(ALICE);
        mf.mint{value: 0.04 ether}(1);
        mf.mint{value: 0.08 ether}(2);
        vm.stopPrank();
        assertEq(gf.ownerOf(0), ALICE);
        assertEq(gf.ownerOf(1), ALICE);
        assertEq(gf.ownerOf(2), ALICE);
        assertEq(gf.totalSupply(), 3);
    }

    function testMintMultipleUsers() public {
        vm.prank(ALICE);
        mf.mint{value: 0.04 ether}(1);
        vm.prank(BOB);
        mf.mint{value: 0.04 ether}(1);
        assertEq(gf.ownerOf(0), ALICE);
        assertEq(gf.ownerOf(1), BOB);
    }

    function testMintZeroPaymentReverts() public {
        vm.prank(ALICE);
        vm.expectRevert("Invalid value");
        mf.mint{value: 0}(1);
    }

    function testMintOverpaymentAllowed() public {
        vm.prank(ALICE);
        mf.mint{value: 0.05 ether}(1);
        assertEq(gf.balanceOf(ALICE), 1);
    }

    function testWhitelistMintFree() public {
        _addWhitelist(ALICE);
        vm.prank(ALICE);
        mf.mint(1);
        assertEq(gf.balanceOf(ALICE), 1);
    }

    function testWhitelistMintIgnoresAmount() public {
        _addWhitelist(ALICE);
        vm.prank(ALICE);
        mf.mint(10);
        assertEq(gf.balanceOf(ALICE), 1, "Whitelist only mints 1 regardless of amount");
    }

    function testWhitelistCanBeRevoked() public {
        address[] memory addrs = new address[](1);
        addrs[0] = ALICE;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        mf.addWhitelist(addrs, flags);

        flags[0] = false;
        mf.addWhitelist(addrs, flags);

        vm.prank(ALICE);
        mf.mint{value: 0.04 ether}(1);
        assertEq(gf.balanceOf(ALICE), 1);
    }

    function testAddWhitelistOnlyOwner() public {
        address[] memory addrs = new address[](1);
        addrs[0] = BOB;
        bool[] memory flags = new bool[](1);
        flags[0] = true;

        vm.prank(ALICE);
        vm.expectRevert();
        mf.addWhitelist(addrs, flags);
    }

    function testPausedMintReverts() public {
        mf.paused(true);
        vm.prank(ALICE);
        vm.expectRevert("LibAppStorage: mint paused");
        mf.mint{value: 0.04 ether}(1);
    }

    function testUnpauseRestoresMint() public {
        mf.paused(true);
        mf.paused(false);
        vm.prank(ALICE);
        mf.mint{value: 0.04 ether}(1);
        assertEq(gf.totalSupply(), 1);
    }

    function testPausedOnlyOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        mf.paused(true);
    }

    function testSummonCreatesAccount() public {
        address tba = _summonGotchipus(0);
        assertTrue(tba != address(0));
        assertEq(IERC6551Facet(address(diamond)).account(0), tba);
    }

    function testSummonFundsAccount() public {
        address tba = _summonGotchipus(0);
        assertEq(tba.balance, 0.1 ether);
    }

    function testSummonAccountOwner() public {
        address tba = _summonGotchipus(0);
        assertEq(IERC6551Account(payable(tba)).owner(), ALICE);
    }

    function testSummonInitializesGotchipusInfo() public {
        _summonGotchipus(0);
        MetadataFacet meta = MetadataFacet(address(diamond));
        GotchipusInfo memory info = meta.ownedTokenInfo(ALICE, 0);

        assertEq(info.status, 1);
        assertEq(keccak256(bytes(info.name)), keccak256(bytes("Gotchi No.1")));
        assertGt(info.birthTime, 0);
        assertTrue(info.dna.geneSeed != 0);
        assertGt(info.core.strength, 0);
    }

    function testSummonSetsAttributes() public {
        _summonGotchipus(0);
        MetadataFacet meta = MetadataFacet(address(diamond));
        GotchipusInfo memory info = meta.ownedTokenInfo(ALICE, 0);

        assertTrue(info.core.strength >= 1200);
        assertTrue(info.core.defense >= 1200);
        assertTrue(info.core.mind >= 1200);
        assertTrue(info.core.vitality >= 1200);
        assertTrue(info.core.agility >= 1200);
        assertTrue(info.core.luck >= 1200);
    }

    function testSummonSetsFaction() public {
        _summonGotchipus(0);
        MetadataFacet meta = MetadataFacet(address(diamond));
        GotchipusInfo memory info = meta.ownedTokenInfo(ALICE, 0);

        assertTrue(info.faction.primaryFaction <= 2);
        assertEq(info.faction.factionPurity, 100);
    }

    function testDoubleSummonReverts() public {
        _summonGotchipus(0);

        vm.startPrank(ALICE);
        IMintFacet.SummonArgs memory args = IMintFacet.SummonArgs({
            gotchipusTokenId: 0,
            gotchiName: "Dup",
            collateralToken: address(0),
            stakeAmount: 0.01 ether,
            utc: 0,
            story: "dup",
            preIndex: 0
        });
        vm.expectRevert("GotchipusFacet: already summon");
        mf.summonGotchipus{value: 0.01 ether}(args);
        vm.stopPrank();
    }

    function testSummonNonOwnerReverts() public {
        vm.prank(ALICE);
        mf.mint{value: 0.04 ether}(1);

        IMintFacet.SummonArgs memory args = IMintFacet.SummonArgs({
            gotchipusTokenId: 0,
            gotchiName: "Stolen",
            collateralToken: address(0),
            stakeAmount: 0.01 ether,
            utc: 0,
            story: "steal",
            preIndex: 0
        });
        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        mf.summonGotchipus{value: 0.01 ether}(args);
    }

    function testSummonMultipleTokens() public {
        vm.deal(ALICE, 500 ether);
        vm.startPrank(ALICE);
        mf.mint{value: 5 * 0.04 ether}(5);

        for (uint256 i; i < 5; i++) {
            IMintFacet.SummonArgs memory args = IMintFacet.SummonArgs({
                gotchipusTokenId: i,
                gotchiName: "Gotchi",
                collateralToken: address(0),
                stakeAmount: 0.1 ether,
                utc: 0,
                story: "multi",
                preIndex: i
            });
            mf.summonGotchipus{value: 0.1 ether}(args);
        }
        vm.stopPrank();

        for (uint256 i; i < 5; i++) {
            address acc = IERC6551Facet(address(diamond)).account(i);
            assertTrue(acc != address(0));
        }
    }

    function testWithdrawETH() public {
        vm.prank(ALICE);
        mf.mint{value: 1.2 ether}(30);

        uint256 diamondBal = address(diamond).balance;
        assertTrue(diamondBal > 0, "Diamond should have ETH");

        vm.expectRevert("LibTransferHelper::safeTransferETH: ETH transfer failed");
        mf.withdrawETH();
    }

    function testWithdrawETHOnlyOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        mf.withdrawETH();
    }

    function testSetSalt() public {
        mf.setSalt(42);
    }

    function testSetSaltOnlyOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        mf.setSalt(42);
    }

    function testFuzz_MintValidAmount(uint8 rawAmt) public {
        uint256 amount = bound(uint256(rawAmt), 1, 30);
        uint256 payment = amount * 0.04 ether;

        vm.prank(ALICE);
        mf.mint{value: payment}(amount);
        assertEq(gf.totalSupply(), amount);
        assertEq(gf.balanceOf(ALICE), amount);
    }

    function testFuzz_MintUnderpaymentReverts(uint256 underpay) public {
        underpay = bound(underpay, 0, 0.04 ether - 1);
        vm.prank(ALICE);
        vm.expectRevert("Invalid value");
        mf.mint{value: underpay}(1);
    }

    function _addWhitelist(address who) internal {
        address[] memory addrs = new address[](1);
        addrs[0] = who;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        mf.addWhitelist(addrs, flags);
    }
}
