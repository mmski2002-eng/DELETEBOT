// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../utils/DiamondFixture.sol";
import { ALICE } from "../utils/Constants.sol";
import { IMintFacet } from "../../src/interfaces/IMintFacet.sol";
import { IGotchipusFacet } from "../../src/interfaces/IGotchipusFacet.sol";
import { MetadataFacet } from "../../src/facets/MetadataFacet.sol";
import { GotchipusInfo, MAX_TRAITS_NUM } from "../../src/libraries/LibAppStorage.sol";

contract MetadataFacetTest is DiamondFixture {
    address internal BOB = address(0xB0B);

    MetadataFacet internal meta;
    IMintFacet internal mf;
    IGotchipusFacet internal gf;
    uint256 constant TOKEN_ID = 0;

    function setUp() public override {
        super.setUp();
        meta = MetadataFacet(address(diamond));
        mf = IMintFacet(address(diamond));
        gf = IGotchipusFacet(address(diamond));
        vm.deal(ALICE, 200 ether);
        vm.deal(BOB, 200 ether);
    }

    function testTokenURIPharos() public {
        vm.prank(ALICE);
        mf.mint{value: 0.04 ether}(1);

        string memory uri = meta.tokenURI(TOKEN_ID);
        assertEq(uri, "https://app.gotchipus.com/metadata/pharos/0");
    }

    function testTokenURIGotchipus() public {
        _summonGotchipus(TOKEN_ID);
        string memory uri = meta.tokenURI(TOKEN_ID);
        assertEq(uri, "https://app.gotchipus.com/metadata/gotchipus/0");
    }

    function testTokenURIMultipleTokens() public {
        vm.startPrank(ALICE);
        mf.mint{value: 0.12 ether}(3);
        vm.stopPrank();

        assertEq(meta.tokenURI(0), "https://app.gotchipus.com/metadata/pharos/0");
        assertEq(meta.tokenURI(1), "https://app.gotchipus.com/metadata/pharos/1");
        assertEq(meta.tokenURI(2), "https://app.gotchipus.com/metadata/pharos/2");
    }

    function testSetBaseURI() public {
        meta.setBaseURI("https://app.gotchipus.com/");
        vm.prank(ALICE);
        mf.mint{value: 0.04 ether}(1);
        assertEq(meta.tokenURI(TOKEN_ID), "https://app.gotchipus.com/pharos/0");
    }

    function testSetBaseURIOnlyOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        meta.setBaseURI("https://app.gotchipus.com/");
    }

    function testOwnedTokenInfoBeforeSummon() public {
        vm.prank(ALICE);
        mf.mint{value: 0.04 ether}(1);

        GotchipusInfo memory info = meta.ownedTokenInfo(ALICE, TOKEN_ID);
        assertEq(info.status, 0);
    }

    function testOwnedTokenInfoAfterSummon() public {
        _summonGotchipus(TOKEN_ID);
        GotchipusInfo memory info = meta.ownedTokenInfo(ALICE, TOKEN_ID);
        assertEq(info.status, 1);
        assertEq(keccak256(bytes(info.name)), keccak256(bytes("Gotchi No.1")));
        assertGt(info.birthTime, 0);
        assertTrue(info.dna.geneSeed != 0);
    }

    function testOwnedTokenInfoNonExistentOwner() public {
        _summonGotchipus(TOKEN_ID);
        GotchipusInfo memory info = meta.ownedTokenInfo(BOB, TOKEN_ID);
        assertEq(info.status, 0);
    }

    function testGetGotchiOrPharosInfoPharosOnly() public {
        vm.prank(ALICE);
        mf.mint{value: 0.12 ether}(3);

        uint256[] memory pharosIds = meta.getGotchiOrPharosInfo(ALICE, 0);
        assertEq(pharosIds.length, 3);
    }

    function testGetGotchiOrPharosInfoMixed() public {
        _summonGotchipus(TOKEN_ID);

        uint256[] memory gotchiIds = meta.getGotchiOrPharosInfo(ALICE, 1);
        assertEq(gotchiIds.length, 1);
        assertEq(gotchiIds[0], TOKEN_ID);

        uint256[] memory pharosIds = meta.getGotchiOrPharosInfo(ALICE, 0);
        assertEq(pharosIds.length, 9);
    }

    function testGetGotchiOrPharosInfoEmpty() public view {
        uint256[] memory ids = meta.getGotchiOrPharosInfo(ALICE, 0);
        assertEq(ids.length, 0);
    }

    function testGetGotchiTraitsIndexDefault() public {
        _summonGotchipus(TOKEN_ID);
        uint8[MAX_TRAITS_NUM] memory idx = meta.getGotchiTraitsIndex(TOKEN_ID);
        assertEq(idx.length, MAX_TRAITS_NUM);
    }

    function testFuzz_SetBaseURI(string calldata baseUri) public {
        meta.setBaseURI(baseUri);
        vm.prank(ALICE);
        mf.mint{value: 0.04 ether}(1);
        string memory uri = meta.tokenURI(TOKEN_ID);
        assertTrue(bytes(uri).length > 0);
    }
}
