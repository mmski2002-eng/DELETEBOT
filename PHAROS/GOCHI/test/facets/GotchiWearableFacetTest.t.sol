// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../utils/DiamondFixture.sol";
import { ALICE } from "../utils/Constants.sol";
import { IMintFacet } from "../../src/interfaces/IMintFacet.sol";
import { GotchiWearableFacet } from "../../src/facets/GotchiWearableFacet.sol";
import { WearableInfo, EquipWearableType, MAX_TRAITS_NUM } from "../../src/libraries/LibAppStorage.sol";
import { LibSvg } from "../../src/libraries/LibSvg.sol";
import { WearableFacet } from "../../src/WearableDiamond/facets/WearableFacet.sol";

contract GotchiWearableFacetTest is DiamondFixture {
    address internal BOB = address(0xB0B);

    GotchiWearableFacet internal wf;
    uint256 constant TOKEN_ID = 0;
    address internal tba;
    address internal wd; // wearable diamond address

    uint256 constant HEAD_WEARABLE_ID = 46; // "Aviator Hat" - HEAD type

    function setUp() public override {
        super.setUp();
        wf = GotchiWearableFacet(address(diamond));
        vm.deal(ALICE, 500 ether);
        vm.deal(BOB, 500 ether);
        tba = _summonGotchipus(TOKEN_ID);
        wd = wf.getWearableDiamond();
        vm.deal(wd, 100 ether);
    }

    function testWearableBalanceOfInitialZero() public view {
        assertEq(wf.wearableBalanceOf(ALICE, HEAD_WEARABLE_ID), 0);
    }

    function testWearableBalanceOfAfterMint() public {
        _mintWearableToAlice(HEAD_WEARABLE_ID, 3);
        assertEq(wf.wearableBalanceOf(ALICE, HEAD_WEARABLE_ID), 3);
    }

    function testWearableBalanceOfBatch() public view {
        address[] memory owners = new address[](2);
        uint256[] memory tokenIds = new uint256[](2);
        owners[0] = ALICE;
        owners[1] = BOB;
        tokenIds[0] = 0;
        tokenIds[1] = 1;

        uint256[] memory balances = wf.wearableBalanceOfBatch(owners, tokenIds);
        assertEq(balances.length, 2);
    }

    function testWearableBalanceOfBatchLengthMismatchReverts() public {
        address[] memory owners = new address[](2);
        uint256[] memory tokenIds = new uint256[](1);
        owners[0] = ALICE;
        owners[1] = BOB;
        tokenIds[0] = 0;

        vm.expectRevert("ERC1155: owners and tokenIds length mismatch");
        wf.wearableBalanceOfBatch(owners, tokenIds);
    }

    function testWearableUri() public view {
        string memory uri = wf.wearableUri(0);
        assertTrue(bytes(uri).length > 0);
    }

    function testGetWearableInfo() public view {
        WearableInfo memory info = wf.getWearableInfo(0);
        assertEq(keccak256(bytes(info.name)), keccak256(bytes("Beach Lighthouse")));
    }

    function testGetWearableInfoNonExistent() public view {
        WearableInfo memory info = wf.getWearableInfo(999);
        assertEq(bytes(info.name).length, 0);
    }

    function testCreateWearable() public {
        uint256 nextId = wf.getNextTokenId();

        wf.createWearable(
            "https://wearable.gotchipus.com/wearable/85",
            WearableInfo("Test Hat", "A test hat", "Tester", "gotchipus-head", 85)
        );

        WearableInfo memory info = wf.getWearableInfo(nextId);
        assertEq(keccak256(bytes(info.name)), keccak256(bytes("Test Hat")));
    }

    function testCreateWearableOnlyOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        wf.createWearable(
            "https://wearable.gotchipus.com/wearable/85",
            WearableInfo("Test", "test", "tester", "gotchipus-head", 85)
        );
    }

    function testCreateWearableIncrementsNextTokenId() public {
        uint256 before_ = wf.getNextTokenId();
        wf.createWearable(
            "uri",
            WearableInfo("A", "b", "c", "gotchipus-head", uint8(before_))
        );
        assertEq(wf.getNextTokenId(), before_ + 1);
    }

    function testEquipWearable() public {
        _mintWearableToAlice(HEAD_WEARABLE_ID, 1);

        vm.prank(ALICE);
        wf.equipWearable(TOKEN_ID, HEAD_WEARABLE_ID, "gotchipus-head");

        assertEq(wf.wearableBalanceOf(ALICE, HEAD_WEARABLE_ID), 0);
        assertEq(wf.wearableBalanceOf(tba, HEAD_WEARABLE_ID), 1);
    }

    function testEquipWearableOnlyOwner() public {
        _mintWearableToAlice(HEAD_WEARABLE_ID, 1);

        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        wf.equipWearable(TOKEN_ID, HEAD_WEARABLE_ID, "gotchipus-head");
    }

    function testEquipWearableInsufficientBalanceReverts() public {
        vm.prank(ALICE);
        vm.expectRevert("WearableFacet: Insufficient balance");
        wf.equipWearable(TOKEN_ID, HEAD_WEARABLE_ID, "gotchipus-head");
    }

    function testEquipWearableReplacesOld() public {
        uint256 wearableId2 = 47;
        _mintWearableToAlice(HEAD_WEARABLE_ID, 1);
        _mintWearableToAlice(wearableId2, 1);

        vm.startPrank(ALICE);
        wf.equipWearable(TOKEN_ID, HEAD_WEARABLE_ID, "gotchipus-head");
        wf.equipWearable(TOKEN_ID, wearableId2, "gotchipus-head");
        vm.stopPrank();

        assertEq(wf.wearableBalanceOf(ALICE, HEAD_WEARABLE_ID), 1);
        assertEq(wf.wearableBalanceOf(tba, wearableId2), 1);
        assertEq(wf.wearableBalanceOf(ALICE, wearableId2), 0);
    }

    function testUnequipWearable() public {
        _mintWearableToAlice(HEAD_WEARABLE_ID, 1);
        vm.startPrank(ALICE);
        wf.equipWearable(TOKEN_ID, HEAD_WEARABLE_ID, "gotchipus-head");
        wf.unequipWearable(TOKEN_ID, HEAD_WEARABLE_ID, "gotchipus-head");
        vm.stopPrank();

        assertEq(wf.wearableBalanceOf(ALICE, HEAD_WEARABLE_ID), 1);
        assertEq(wf.wearableBalanceOf(tba, HEAD_WEARABLE_ID), 0);
    }

    function testUnequipWearableNotEquippedReverts() public {
        vm.prank(ALICE);
        vm.expectRevert("WearableFacet: already unequip");
        wf.unequipWearable(TOKEN_ID, HEAD_WEARABLE_ID, "gotchipus-head");
    }

    function testUnequipWearableOnlyOwner() public {
        _mintWearableToAlice(HEAD_WEARABLE_ID, 1);
        vm.prank(ALICE);
        wf.equipWearable(TOKEN_ID, HEAD_WEARABLE_ID, "gotchipus-head");

        vm.prank(BOB);
        vm.expectRevert("LibAppStorage: Only token owner");
        wf.unequipWearable(TOKEN_ID, HEAD_WEARABLE_ID, "gotchipus-head");
    }

    function testBatchEquipWearable() public {
        uint256 headId = 46;
        uint256 clothesId = 63;
        _mintWearableToAlice(headId, 1);
        _mintWearableToAlice(clothesId, 1);

        uint256[] memory ids = new uint256[](2);
        bytes32[] memory types = new bytes32[](2);
        ids[0] = headId;
        ids[1] = clothesId;
        types[0] = "gotchipus-head";
        types[1] = "gotchipus-clothes";

        vm.prank(ALICE);
        wf.batchEquipWearable(TOKEN_ID, ids, types);

        assertEq(wf.wearableBalanceOf(tba, headId), 1);
        assertEq(wf.wearableBalanceOf(tba, clothesId), 1);
    }

    function testBatchEquipLengthMismatchReverts() public {
        uint256[] memory ids = new uint256[](2);
        bytes32[] memory types = new bytes32[](1);
        ids[0] = 46;
        ids[1] = 63;
        types[0] = "gotchipus-head";

        vm.prank(ALICE);
        vm.expectRevert("WearableFacet: Invalid length");
        wf.batchEquipWearable(TOKEN_ID, ids, types);
    }

    function testBatchUnequipWearable() public {
        uint256 headId = 46;
        uint256 clothesId = 63;
        _mintWearableToAlice(headId, 1);
        _mintWearableToAlice(clothesId, 1);

        uint256[] memory ids = new uint256[](2);
        bytes32[] memory types = new bytes32[](2);
        ids[0] = headId;
        ids[1] = clothesId;
        types[0] = "gotchipus-head";
        types[1] = "gotchipus-clothes";

        vm.startPrank(ALICE);
        wf.batchEquipWearable(TOKEN_ID, ids, types);
        wf.batchUnequipWearable(TOKEN_ID, ids, types);
        vm.stopPrank();

        assertEq(wf.wearableBalanceOf(ALICE, headId), 1);
        assertEq(wf.wearableBalanceOf(ALICE, clothesId), 1);
    }

    function testGetAllEquipWearableTypeAfterSummon() public view {
        EquipWearableType[MAX_TRAITS_NUM] memory ew = wf.getAllEquipWearableType(TOKEN_ID);
        uint256 equippedCount;
        for (uint256 i; i < MAX_TRAITS_NUM; i++) {
            if (ew[i].equiped) equippedCount++;
        }
        assertEq(equippedCount, 3);
    }

    function testGetAllEquipWearableTypeAfterManualEquip() public {
        _mintWearableToAlice(HEAD_WEARABLE_ID, 1);
        vm.prank(ALICE);
        wf.equipWearable(TOKEN_ID, HEAD_WEARABLE_ID, "gotchipus-head");

        EquipWearableType[MAX_TRAITS_NUM] memory ew = wf.getAllEquipWearableType(TOKEN_ID);
        uint256 equippedCount;
        for (uint256 i; i < MAX_TRAITS_NUM; i++) {
            if (ew[i].equiped) equippedCount++;
        }
        assertEq(equippedCount, 4);
    }

    function testGetWearableDiamond() public view {
        assertTrue(wd != address(0));
    }

    function testSetWearableDiamond() public {
        address newWd = address(0x123);
        wf.setWearableDiamond(newWd);
        assertEq(wf.getWearableDiamond(), newWd);
    }

    function testSetWearableDiamondOnlyOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        wf.setWearableDiamond(address(0x123));
    }

    function testGetCountWearablesByType() public view {
        uint256 headCount = wf.getCountWearablesByType("gotchipus-head");
        assertEq(headCount, 17);
    }

    function testGetNextTokenId() public view {
        assertEq(wf.getNextTokenId(), 85);
    }

    function testSetCountWearablesByType() public {
        bytes32[] memory types = new bytes32[](1);
        uint8[] memory lens = new uint8[](1);
        types[0] = "gotchipus-head";
        lens[0] = 5;

        wf.setCountWearablesByType(types, lens);
        assertEq(wf.getCountWearablesByType("gotchipus-head"), 5);
    }

    function testSetNextTokenId() public {
        wf.setNextTokenId(100);
        assertEq(wf.getNextTokenId(), 100);
    }

    function testMintWearable() public {
        vm.prank(wd);
        wf.mintWearable{value: 0.001 ether}(ALICE, HEAD_WEARABLE_ID, 1);
        assertEq(wf.wearableBalanceOf(ALICE, HEAD_WEARABLE_ID), 1);
    }

    function testMintWearableOnlyWearableDiamond() public {
        vm.prank(ALICE);
        vm.expectRevert("LibAppStorage: Only wearable diamond");
        wf.mintWearable{value: 0.001 ether}(ALICE, HEAD_WEARABLE_ID, 1);
    }

    function testMintWearableInvalidValueReverts() public {
        vm.prank(wd);
        vm.expectRevert("WearableFacet: Invalid value");
        wf.mintWearable{value: 0.002 ether}(ALICE, HEAD_WEARABLE_ID, 1);
    }

    function testMintWearableAccumulatesBalance() public {
        vm.prank(wd);
        wf.mintWearable{value: 0.001 ether}(ALICE, HEAD_WEARABLE_ID, 1);
        vm.prank(wd);
        wf.mintWearable{value: 0.001 ether}(ALICE, HEAD_WEARABLE_ID, 1);
        assertEq(wf.wearableBalanceOf(ALICE, HEAD_WEARABLE_ID), 2);
    }

    function testBatchMintWearableAccumulatesBalance() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = HEAD_WEARABLE_ID;
        amounts[0] = 3;

        vm.prank(wd);
        wf.batchMintWearable{value: 0.003 ether}(ALICE, ids, amounts);
        assertEq(wf.wearableBalanceOf(ALICE, HEAD_WEARABLE_ID), 3);

        vm.prank(wd);
        wf.batchMintWearable{value: 0.003 ether}(ALICE, ids, amounts);
        assertEq(wf.wearableBalanceOf(ALICE, HEAD_WEARABLE_ID), 6);
    }

    function testBatchMintWearablePriceByTotalAmount() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;
        amounts[0] = 100;
        amounts[1] = 100;

        vm.prank(wd);
        wf.batchMintWearable{value: 0.2 ether}(ALICE, ids, amounts);
        assertEq(wf.wearableBalanceOf(ALICE, 0), 100);
        assertEq(wf.wearableBalanceOf(ALICE, 1), 100);
    }

    function testBatchMintWearableOldPriceReverts() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;
        amounts[0] = 100;
        amounts[1] = 100;

        vm.prank(wd);
        vm.expectRevert("WearableFacet: Invalid value");
        wf.batchMintWearable{value: 0.002 ether}(ALICE, ids, amounts);
    }

    function testClaimWearableSuccess() public {
        vm.prank(wd);
        wf.claimWearable(ALICE);
    }

    function testClaimWearableDoubleClaim() public {
        vm.prank(wd);
        wf.claimWearable(ALICE);

        vm.prank(wd);
        vm.expectRevert("WearableFacet: already claimed");
        wf.claimWearable(ALICE);
    }

    function _mintWearableToAlice(uint256 wearableTokenId, uint256 amount) internal {
        vm.prank(wd);
        wf.mintWearable{value: amount * 0.001 ether}(ALICE, wearableTokenId, amount);
    }
}
