// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/console.sol";
import "../utils/DiamondFixture.sol";
import { ALICE } from "../utils/Constants.sol";
import { IERC721Metadata } from "../../src/interfaces/IERC721Metadata.sol";
import { IERC6551Account } from "../../src/interfaces/IERC6551Account.sol";
import { IMintFacet } from "../../src/interfaces/IMintFacet.sol";
import { IGotchipusFacet } from "../../src/interfaces/IGotchipusFacet.sol";
import { AttributesFacet } from "../../src/facets/AttributesFacet.sol";

contract GotchipusFacetTest is DiamondFixture {

    function testGetName() public view {
        string memory name = IERC721Metadata(address(diamond)).name();
        assertEq(name, "Gotchipus");
    }

    function testMint() public {
        vm.deal(ALICE, 100 ether);
        vm.prank(ALICE);
        _doMint(10);

        IGotchipusFacet gotchi = IGotchipusFacet(address(diamond));
        for (uint256 i = 0; i < 10; i++) {
            assertEq(gotchi.ownerOf(i), ALICE);
        }
        assertEq(gotchi.totalSupply(), 10);
        assertEq(gotchi.balanceOf(ALICE), 10);
    }

    function testWhitelistMint() public {
        address[] memory whitelists = new address[](1);
        whitelists[0] = address(2);
        bool[] memory bools = new bool[](1);
        bools[0] = true;
        IMintFacet(address(diamond)).addWhitelist(whitelists, bools);

        vm.prank(address(2));
        IMintFacet(address(diamond)).mint(1);

        assertEq(IGotchipusFacet(address(diamond)).balanceOf(address(2)), 1);
    }

    function testSummonGotchipus() public {
        address tba = _summonGotchipus(0);

        IERC6551Account account = IERC6551Account(payable(tba));
        assertEq(account.owner(), ALICE);
        assertEq(tba.balance, 0.1 ether);
    }

    function testPetAfterSummon() public {
        vm.warp(1 days);
        _summonGotchipus(0);

        vm.startPrank(ALICE);
        AttributesFacet attr = AttributesFacet(address(diamond));
        uint256 ts = block.timestamp;
        for (uint256 i = 0; i < 100; i++) {
            ts += 1 days;
            vm.warp(ts);
            attr.pet(0);
        }
        vm.stopPrank();
    }
}