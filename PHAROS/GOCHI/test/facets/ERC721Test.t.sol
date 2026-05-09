// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../utils/DiamondFixture.sol";
import { ALICE, ZERO_ADDRESS } from "../utils/Constants.sol";
import { IMintFacet } from "../../src/interfaces/IMintFacet.sol";
import { IGotchipusFacet } from "../../src/interfaces/IGotchipusFacet.sol";
import { GotchipusFacet } from "../../src/facets/GotchipusFacet.sol";
import { MetadataFacet } from "../../src/facets/MetadataFacet.sol";
import { GotchipusInfo } from "../../src/libraries/LibAppStorage.sol";
import { IERC721Metadata } from "../../src/interfaces/IERC721Metadata.sol";
import { IERC721Receiver } from "../../src/interfaces/IERC721Receiver.sol";
import { IERC721 } from "../../src/interfaces/IERC721.sol";
import { IERC721Enumerable } from "../../src/interfaces/IERC721Enumerable.sol";

contract ERC721ReceiverMock is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract NonReceiverMock {}

contract BadReceiverMock is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return bytes4(0xdeadbeef);
    }
}

contract ERC721Test is DiamondFixture {
    address internal BOB = address(0xB0B);
    address internal CAROL = address(0xCA201);

    IGotchipusFacet internal gf;
    GotchipusFacet internal raw;

    function setUp() public override {
        super.setUp();
        gf = IGotchipusFacet(address(diamond));
        raw = GotchipusFacet(address(diamond));
        vm.deal(ALICE, 200 ether);
        vm.deal(BOB, 200 ether);
        vm.deal(CAROL, 200 ether);
    }

    function testName() public view {
        assertEq(IERC721Metadata(address(diamond)).name(), "Gotchipus");
    }

    function testSymbol() public view {
        assertEq(IERC721Metadata(address(diamond)).symbol(), "GOTCHI");
    }

    function testSupportsInterfaceERC165() public view {
        assertTrue(raw.supportsInterface(0x01ffc9a7));
    }

    function testBalanceOfZeroAddressReverts() public {
        vm.expectRevert("GotchipusFacet: owner is zero address");
        gf.balanceOf(address(0));
    }

    function testBalanceOfNoTokens() public view {
        assertEq(gf.balanceOf(ALICE), 0);
    }

    function testOwnerOfNonexistentReverts() public {
        vm.expectRevert("GotchipusFacet: owner is zero address");
        gf.ownerOf(999);
    }

    function testTotalSupplyInitial() public view {
        assertEq(gf.totalSupply(), 0);
    }

    function testTokenByIndex() public {
        _mintAs(ALICE, 3);
        assertEq(gf.tokenByIndex(0), 0);
        assertEq(gf.tokenByIndex(1), 1);
        assertEq(gf.tokenByIndex(2), 2);
    }

    function testTokenByIndexOutOfBounds() public {
        _mintAs(ALICE, 1);
        vm.expectRevert("GotchipusFacet: ERC721 out of bounds index");
        gf.tokenByIndex(1);
    }

    function testTokenOfOwnerByIndex() public {
        _mintAs(ALICE, 3);
        assertEq(gf.tokenOfOwnerByIndex(ALICE, 0), 0);
        assertEq(gf.tokenOfOwnerByIndex(ALICE, 1), 1);
        assertEq(gf.tokenOfOwnerByIndex(ALICE, 2), 2);
    }

    function testTokenOfOwnerByIndexOutOfBounds() public {
        _mintAs(ALICE, 1);
        vm.expectRevert("GotchipusFacet: ERC721 out of bounds index");
        gf.tokenOfOwnerByIndex(ALICE, 1);
    }

    function testAllTokensOfOwner() public {
        _mintAs(ALICE, 5);
        uint256[] memory tokens = gf.allTokensOfOwner(ALICE);
        assertEq(tokens.length, 5);
    }

    function testTransferFrom() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        gf.transferFrom(ALICE, BOB, 0);
        assertEq(gf.ownerOf(0), BOB);
        assertEq(gf.balanceOf(ALICE), 0);
        assertEq(gf.balanceOf(BOB), 1);
    }

    function testTransferFromNotOwnerReverts() public {
        _mintAs(ALICE, 1);
        vm.prank(BOB);
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        gf.transferFrom(ALICE, BOB, 0);
    }

    function testTransferFromToZeroReverts() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        vm.expectRevert("LibERC721: transfer to the zero address");
        gf.transferFrom(ALICE, address(0), 0);
    }

    function testTransferFromWrongFromReverts() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        vm.expectRevert("LibERC721: transfer from incorrect owner");
        gf.transferFrom(BOB, CAROL, 0);
    }

    function testTransferClearsApproval() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        gf.approve(BOB, 0);
        assertEq(gf.getApproved(0), BOB);

        vm.prank(ALICE);
        gf.transferFrom(ALICE, CAROL, 0);
        assertEq(gf.getApproved(0), address(0));
    }

    function testTransferCopiesGotchipusInfo() public {
        _summonGotchipus(0);

        MetadataFacet meta = MetadataFacet(address(diamond));
        GotchipusInfo memory infoBefore = meta.ownedTokenInfo(ALICE, 0);

        vm.prank(ALICE);
        gf.transferFrom(ALICE, BOB, 0);

        GotchipusInfo memory infoAfter = meta.ownedTokenInfo(BOB, 0);
        assertEq(infoAfter.status, infoBefore.status);
        assertEq(keccak256(bytes(infoAfter.name)), keccak256(bytes(infoBefore.name)));

        GotchipusInfo memory infoOld = meta.ownedTokenInfo(ALICE, 0);
        assertEq(infoOld.status, 0);
    }

    function testTransferUpdatesEnumeration() public {
        _mintAs(ALICE, 3);
        vm.prank(ALICE);
        gf.transferFrom(ALICE, BOB, 1);

        assertEq(gf.balanceOf(ALICE), 2);
        assertEq(gf.balanceOf(BOB), 1);
        assertEq(gf.allTokensOfOwner(BOB).length, 1);
        assertEq(gf.allTokensOfOwner(ALICE).length, 2);
        assertEq(gf.totalSupply(), 3);
    }

    function testSafeTransferToEOA() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        gf.safeTransferFrom(ALICE, BOB, 0);
        assertEq(gf.ownerOf(0), BOB);
    }

    function testSafeTransferToReceiver() public {
        ERC721ReceiverMock receiver = new ERC721ReceiverMock();
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        gf.safeTransferFrom(ALICE, address(receiver), 0);
        assertEq(gf.ownerOf(0), address(receiver));
    }

    function testSafeTransferToNonReceiverReverts() public {
        NonReceiverMock nonReceiver = new NonReceiverMock();
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        vm.expectRevert();
        gf.safeTransferFrom(ALICE, address(nonReceiver), 0);
    }

    function testSafeTransferToBadReceiverReverts() public {
        BadReceiverMock badReceiver = new BadReceiverMock();
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        vm.expectRevert("ERC721: transfer to non ERC721Receiver implementer");
        gf.safeTransferFrom(ALICE, address(badReceiver), 0);
    }

    function testApprove() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        gf.approve(BOB, 0);
        assertEq(gf.getApproved(0), BOB);
    }

    function testApproveToCurrentOwnerReverts() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        vm.expectRevert("ERC721: approval to current owner");
        gf.approve(ALICE, 0);
    }

    function testApproveByNonOwnerReverts() public {
        _mintAs(ALICE, 1);
        vm.prank(BOB);
        vm.expectRevert("ERC721: approve caller is not owner nor approved for all");
        gf.approve(BOB, 0);
    }

    function testApprovedCanTransfer() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        gf.approve(BOB, 0);

        vm.prank(BOB);
        gf.transferFrom(ALICE, CAROL, 0);
        assertEq(gf.ownerOf(0), CAROL);
    }

    function testGetApprovedNonexistent() public {
        _mintAs(ALICE, 1);
        assertEq(gf.getApproved(0), address(0));
    }

    function testGetApprovedInvalidTokenReverts() public {
        vm.expectRevert("ERC721: tokenId is invalid");
        gf.getApproved(999);
    }

    function testSetApprovalForAll() public {
        vm.prank(ALICE);
        gf.setApprovalForAll(BOB, true);
        assertTrue(gf.isApprovedForAll(ALICE, BOB));
    }

    function testSetApprovalForAllToSelfReverts() public {
        vm.prank(ALICE);
        vm.expectRevert("ERC721: approve to caller");
        gf.setApprovalForAll(ALICE, true);
    }

    function testSetApprovalForAllRevoke() public {
        vm.startPrank(ALICE);
        gf.setApprovalForAll(BOB, true);
        gf.setApprovalForAll(BOB, false);
        vm.stopPrank();
        assertFalse(gf.isApprovedForAll(ALICE, BOB));
    }

    function testOperatorCanTransfer() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        gf.setApprovalForAll(BOB, true);

        vm.prank(BOB);
        gf.transferFrom(ALICE, CAROL, 0);
        assertEq(gf.ownerOf(0), CAROL);
    }

    function testOperatorCanApprove() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        gf.setApprovalForAll(BOB, true);

        vm.prank(BOB);
        gf.approve(CAROL, 0);
        assertEq(gf.getApproved(0), CAROL);
    }

    function testBurn() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        gf.burn(0);

        assertEq(gf.totalSupply(), 0);
        assertEq(gf.balanceOf(ALICE), 0);
        vm.expectRevert("GotchipusFacet: owner is zero address");
        gf.ownerOf(0);
    }

    function testBurnByApproved() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        gf.approve(BOB, 0);

        vm.prank(BOB);
        gf.burn(0);
        assertEq(gf.totalSupply(), 0);
    }

    function testBurnByOperator() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        gf.setApprovalForAll(BOB, true);

        vm.prank(BOB);
        gf.burn(0);
        assertEq(gf.totalSupply(), 0);
    }

    function testBurnByNonOwnerReverts() public {
        _mintAs(ALICE, 1);
        vm.prank(BOB);
        vm.expectRevert("ERC721: caller is not owner nor approved");
        gf.burn(0);
    }

    function testBurnUpdatesEnumeration() public {
        _mintAs(ALICE, 3);

        vm.prank(ALICE);
        gf.burn(1);

        assertEq(gf.totalSupply(), 2);
        assertEq(gf.balanceOf(ALICE), 2);
        assertEq(gf.allTokensOfOwner(ALICE).length, 2);
    }

    function testBurnClearsGotchipusInfo() public {
        _summonGotchipus(0);

        vm.prank(ALICE);
        gf.burn(0);

        MetadataFacet meta = MetadataFacet(address(diamond));
        GotchipusInfo memory info = meta.ownedTokenInfo(ALICE, 0);
        assertEq(info.status, 0);
        assertEq(bytes(info.name).length, 0);
    }

    function testFuzz_MintAndCheckOwner(uint8 rawAmt) public {
        uint256 amount = bound(uint256(rawAmt), 1, 30);
        _mintAs(ALICE, amount);
        for (uint256 i; i < amount; i++) {
            assertEq(gf.ownerOf(i), ALICE);
        }
        assertEq(gf.totalSupply(), amount);
    }

    function testFuzz_TransferMultiple(uint8 rawAmt) public {
        uint256 amount = bound(uint256(rawAmt), 1, 10);
        _mintAs(ALICE, amount);

        vm.startPrank(ALICE);
        for (uint256 i; i < amount; i++) {
            gf.transferFrom(ALICE, BOB, i);
        }
        vm.stopPrank();

        assertEq(gf.balanceOf(ALICE), 0);
        assertEq(gf.balanceOf(BOB), amount);
    }

    function testFuzz_BurnAll(uint8 rawAmt) public {
        uint256 amount = bound(uint256(rawAmt), 1, 10);
        _mintAs(ALICE, amount);

        vm.startPrank(ALICE);
        for (uint256 i; i < amount; i++) {
            gf.burn(i);
        }
        vm.stopPrank();

        assertEq(gf.totalSupply(), 0);
        assertEq(gf.balanceOf(ALICE), 0);
    }

    function _mintAs(address who, uint256 amount) internal {
        vm.deal(who, 200 ether);
        vm.prank(who);
        IMintFacet(address(diamond)).mint{value: amount * 0.04 ether}(amount);
    }
}
