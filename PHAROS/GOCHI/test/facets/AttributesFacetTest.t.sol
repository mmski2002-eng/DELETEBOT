// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../utils/DiamondFixture.sol";
import { ALICE } from "../utils/Constants.sol";
import { IMintFacet } from "../../src/interfaces/IMintFacet.sol";
import { IGotchipusFacet } from "../../src/interfaces/IGotchipusFacet.sol";
import { AttributesFacet } from "../../src/facets/AttributesFacet.sol";
import { MetadataFacet } from "../../src/facets/MetadataFacet.sol";
import { GotchipusInfo } from "../../src/libraries/LibAppStorage.sol";

contract AttributesFacetTest is DiamondFixture {
    address internal BOB = address(0xB0B);

    AttributesFacet internal attr;
    MetadataFacet internal meta;
    uint256 constant TOKEN_ID = 0;

    function setUp() public override {
        super.setUp();
        attr = AttributesFacet(address(diamond));
        meta = MetadataFacet(address(diamond));
        vm.deal(ALICE, 200 ether);
        vm.deal(BOB, 200 ether);
        vm.warp(1 days + 1);
    }

    function testPetSuccess() public {
        _summonGotchipus(TOKEN_ID);
        vm.prank(ALICE);
        attr.pet(TOKEN_ID);
        assertEq(attr.getLastPetTime(TOKEN_ID), uint32(block.timestamp));
    }

    function testPetEmitsEvent() public {
        _summonGotchipus(TOKEN_ID);
        vm.prank(ALICE);
        vm.expectEmit(true, false, false, false, address(diamond));
        emit AttributesFacet.Pet(TOKEN_ID);
        attr.pet(TOKEN_ID);
    }

    function testPetOnlyOwner() public {
        _summonGotchipus(TOKEN_ID);
        vm.prank(BOB);
        vm.expectRevert("not owner");
        attr.pet(TOKEN_ID);
    }

    function testPetCooldownReverts() public {
        _summonGotchipus(TOKEN_ID);
        vm.startPrank(ALICE);
        attr.pet(TOKEN_ID);
        vm.expectRevert("gotchipus already pet");
        attr.pet(TOKEN_ID);
        vm.stopPrank();
    }

    function testPetCooldownExact1DayPasses() public {
        _summonGotchipus(TOKEN_ID);
        vm.startPrank(ALICE);
        attr.pet(TOKEN_ID);
        skip(1 days);
        attr.pet(TOKEN_ID);
        vm.stopPrank();
    }

    function testPetCooldownJustUnder1DayFails() public {
        _summonGotchipus(TOKEN_ID);
        vm.startPrank(ALICE);
        attr.pet(TOKEN_ID);
        skip(1 days - 1);
        vm.expectRevert("gotchipus already pet");
        attr.pet(TOKEN_ID);
        vm.stopPrank();
    }

    function testPetMultipleDays() public {
        _summonGotchipus(TOKEN_ID);
        vm.startPrank(ALICE);
        for (uint256 i; i < 10; i++) {
            attr.pet(TOKEN_ID);
            skip(1 days);
        }
        vm.stopPrank();
        assertEq(attr.getLastPetTime(TOKEN_ID), uint32(block.timestamp - 1 days));
    }

    function testPetIncreasesExp() public {
        _summonGotchipus(TOKEN_ID);
        GotchipusInfo memory before = meta.ownedTokenInfo(ALICE, TOKEN_ID);

        vm.prank(ALICE);
        attr.pet(TOKEN_ID);

        GotchipusInfo memory after_ = meta.ownedTokenInfo(ALICE, TOKEN_ID);
        assertEq(after_.leveling.currentExp, before.leveling.currentExp + 20);
        assertEq(after_.leveling.totalExp, before.leveling.totalExp + 20);
    }

    function testPetIncreasesStates() public {
        _summonGotchipus(TOKEN_ID);
        GotchipusInfo memory before = meta.ownedTokenInfo(ALICE, TOKEN_ID);

        vm.prank(ALICE);
        attr.pet(TOKEN_ID);

        GotchipusInfo memory after_ = meta.ownedTokenInfo(ALICE, TOKEN_ID);
        assertGe(after_.states.health, before.states.health);
        assertGe(after_.states.energy, before.states.energy);
        assertGe(after_.states.morale, before.states.morale);
        assertGe(after_.states.focus, before.states.focus);
    }

    function testPetStatesClampAt255() public {
        _summonGotchipus(TOKEN_ID);
        vm.startPrank(ALICE);
        for (uint256 i; i < 20; i++) {
            attr.pet(TOKEN_ID);
            skip(1 days);
        }
        vm.stopPrank();

        GotchipusInfo memory info = meta.ownedTokenInfo(ALICE, TOKEN_ID);
        assertLe(info.states.health, 255);
        assertLe(info.states.energy, 255);
        assertLe(info.states.morale, 255);
        assertLe(info.states.focus, 255);
    }

    function testPetAccumulatesExpCorrectly() public {
        _summonGotchipus(TOKEN_ID);
        vm.startPrank(ALICE);
        uint256 petCount = 5;
        for (uint256 i; i < petCount; i++) {
            attr.pet(TOKEN_ID);
            skip(1 days);
        }
        vm.stopPrank();

        GotchipusInfo memory info = meta.ownedTokenInfo(ALICE, TOKEN_ID);
        assertEq(info.leveling.currentExp, uint32(petCount * 20));
        assertEq(info.leveling.totalExp, uint32(petCount * 20));
    }

    function testSetName() public {
        _summonGotchipus(TOKEN_ID);
        vm.prank(ALICE);
        attr.setName("NewName", TOKEN_ID);
        assertEq(attr.getTokenName(TOKEN_ID), "NewName");
    }

    function testSetNameEmitsEvent() public {
        _summonGotchipus(TOKEN_ID);
        vm.prank(ALICE);
        vm.expectEmit(false, false, false, false, address(diamond));
        emit AttributesFacet.SetName("MyGotchi");
        attr.setName("MyGotchi", TOKEN_ID);
    }

    function testSetNameOnlyOwner() public {
        _summonGotchipus(TOKEN_ID);
        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        attr.setName("Hack", TOKEN_ID);
    }

    function testSetNameOverwrite() public {
        _summonGotchipus(TOKEN_ID);
        vm.startPrank(ALICE);
        attr.setName("First", TOKEN_ID);
        assertEq(attr.getTokenName(TOKEN_ID), "First");
        attr.setName("Second", TOKEN_ID);
        assertEq(attr.getTokenName(TOKEN_ID), "Second");
        vm.stopPrank();
    }

    function testSetNameEmptyString() public {
        _summonGotchipus(TOKEN_ID);
        vm.prank(ALICE);
        attr.setName("", TOKEN_ID);
        assertEq(attr.getTokenName(TOKEN_ID), "");
    }

    function testSummonSetsInitialName() public {
        _summonGotchipus(TOKEN_ID);
        assertEq(attr.getTokenName(TOKEN_ID), "Gotchi No.1");
    }

    function testGetAttributesAfterSummon() public {
        _summonGotchipus(TOKEN_ID);
        uint32[6] memory vals = attr.getAttributes(TOKEN_ID);
        for (uint256 i; i < 6; i++) {
            assertGe(vals[i], 1200);
        }
    }

    function testGetAttributesConsistency() public {
        _summonGotchipus(TOKEN_ID);
        uint32[6] memory a = attr.getAttributes(TOKEN_ID);
        uint32[6] memory b = attr.getAttributes(TOKEN_ID);
        for (uint256 i; i < 6; i++) {
            assertEq(a[i], b[i]);
        }
    }

    function testGetAttributesBeforeSummon() public {
        vm.prank(ALICE);
        IMintFacet(address(diamond)).mint{value: 0.04 ether}(1);
        uint32[6] memory vals = attr.getAttributes(TOKEN_ID);
        for (uint256 i; i < 6; i++) {
            assertEq(vals[i], 0);
        }
    }

    function testGetSoulAfterSummon() public {
        _summonGotchipus(TOKEN_ID);
        uint32 soul = attr.getSoul(TOKEN_ID);
        assertGt(soul, 0);
    }

    function testGetSoulBeforeSummon() public {
        vm.prank(ALICE);
        IMintFacet(address(diamond)).mint{value: 0.04 ether}(1);
        uint32 soul = attr.getSoul(TOKEN_ID);
        assertEq(soul, 0);
    }

    function testGetLastPetTimeInitialZero() public {
        _summonGotchipus(TOKEN_ID);
        assertEq(attr.getLastPetTime(TOKEN_ID), 0);
    }

    function testGetLastPetTimeUpdates() public {
        _summonGotchipus(TOKEN_ID);
        uint256 ts = block.timestamp;
        vm.prank(ALICE);
        attr.pet(TOKEN_ID);
        assertEq(attr.getLastPetTime(TOKEN_ID), uint32(ts));
    }

    function testFuzz_PetWithVariousTimeskips(uint32 skipTime) public {
        skipTime = uint32(bound(uint256(skipTime), 1 days, 365 days));
        _summonGotchipus(TOKEN_ID);

        vm.startPrank(ALICE);
        attr.pet(TOKEN_ID);
        skip(skipTime);
        attr.pet(TOKEN_ID);
        vm.stopPrank();
    }

    function testFuzz_SetNameAnyString(string calldata name_) public {
        _summonGotchipus(TOKEN_ID);
        vm.prank(ALICE);
        attr.setName(name_, TOKEN_ID);
        assertEq(attr.getTokenName(TOKEN_ID), name_);
    }
}
