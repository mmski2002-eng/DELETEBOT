// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/console.sol";
import "../utils/DiamondFixture.sol";
import { ALICE, MAX_TOTAL_SUPPLY } from "../utils/Constants.sol";
import { IGotchipusFacet } from "../../src/interfaces/IGotchipusFacet.sol";
import { ISvgFacet } from "../../src/interfaces/ISvgFacet.sol";
import { LibSvg } from "../../src/libraries/LibSvg.sol";
import { GetSvgBytes } from "../utils/GetSvgBytes.sol";
import { IMintFacet } from "../../src/interfaces/IMintFacet.sol";
import { IMetadataFacet } from "../../src/interfaces/IMetadataFacet.sol";

contract SvgFacetTest is DiamondFixture {

    function _storeSvg(ISvgFacet svgFacet) internal {
        string[9] memory bgs = GetSvgBytes.getBgBytes();
        string[9] memory bodys = GetSvgBytes.getBodyBytes();
        string[9] memory eyes = GetSvgBytes.getEyeBytes();
        string[9] memory hands = GetSvgBytes.getHandBytes();
        string[9] memory heads = GetSvgBytes.getHeadBytes();
        string[9] memory clothess = GetSvgBytes.getClothesBytes();
        
        LibSvg.SvgItem[] memory bgItems = new LibSvg.SvgItem[](1);
        LibSvg.SvgItem[] memory bodyItems = new LibSvg.SvgItem[](1);
        LibSvg.SvgItem[] memory eyeItems = new LibSvg.SvgItem[](1);
        LibSvg.SvgItem[] memory handItems = new LibSvg.SvgItem[](1);
        LibSvg.SvgItem[] memory headItems = new LibSvg.SvgItem[](1);
        LibSvg.SvgItem[] memory clothesItems = new LibSvg.SvgItem[](1);

        // We need to create a separate contract for each trait to avoid exceeding the contract size limit.
        for (uint8 i = 0; i < 9; i++) {
            // store background svg
            bytes memory bgSvg= bytes(bgs[i]);
            bgItems[0] = LibSvg.SvgItem({
                svgType: LibSvg.SVG_TYPE_BG,
                size: bgSvg.length
            });
            svgFacet.storeSvg(bgSvg, bgItems);

            // store body svg
            bytes memory bodySvg = bytes(bodys[i]);
            bodyItems[0] = LibSvg.SvgItem({
                svgType: LibSvg.SVG_TYPE_BODY,
                size: bodySvg.length
            });
            svgFacet.storeSvg(bodySvg, bodyItems);

            // store eye svg
            bytes memory eyeSvg = bytes(eyes[i]);
            eyeItems[0] = LibSvg.SvgItem({
                svgType: LibSvg.SVG_TYPE_EYE,
                size: eyeSvg.length
            });
            svgFacet.storeSvg(eyeSvg, eyeItems);

            // store hand svg
            bytes memory handSvg = bytes(hands[i]);
            handItems[0] = LibSvg.SvgItem({
                svgType: LibSvg.SVG_TYPE_HAND,
                size: handSvg.length
            });
            svgFacet.storeSvg(handSvg, handItems);

            // store head svg
            bytes memory headSvg = bytes(heads[i]);
            headItems[0] = LibSvg.SvgItem({
                svgType: LibSvg.SVG_TYPE_HEAD,
                size: headSvg.length
            });
            svgFacet.storeSvg(headSvg, headItems);

            // store clothes svg
            bytes memory clothesSvg = bytes(clothess[i]);
            clothesItems[0] = LibSvg.SvgItem({
                svgType: LibSvg.SVG_TYPE_CLOTHES,
                size: clothesSvg.length
            });
            svgFacet.storeSvg(clothesSvg, clothesItems);
        }
    }

    function testStoreSvg() public {
        vm.startPrank(address(this));
        vm.deal(ALICE, 100 ether);
        _doMint(10);

        ISvgFacet svgFacet = ISvgFacet(address(diamond));

        _storeSvg(svgFacet);

        LibSvg.SvgItem[] memory pharosItems = new LibSvg.SvgItem[](1);
        pharosItems[0] = LibSvg.SvgItem({
            svgType: "pharos",
            size: 6
        });
        svgFacet.storeSvg("pharos", pharosItems);

        bytes32[] memory types = new bytes32[](3);
        uint8[] memory lens = new uint8[](3);
        types[0] = LibSvg.SVG_TYPE_BG;
        types[1] = LibSvg.SVG_TYPE_BODY;
        types[2] = LibSvg.SVG_TYPE_EYE;
        lens[0] = 9;
        lens[1] = 9;
        lens[2] = 9;
        GotchiWearableFacet(address(diamond)).setCountWearablesByType(types, lens);

        IMintFacet.SummonArgs memory args = IMintFacet.SummonArgs({
            gotchipusTokenId: 0,
            gotchiName: "Gotchi No.1",
            collateralToken: address(0),
            stakeAmount: 0.1 ether,
            utc: 0,
            story: "I'm Gotchi",
            preIndex: 0
        });

        IMintFacet(address(diamond)).summonGotchipus{value: 0.1 ether}(args);
        
        uint8[8] memory indexs = IMetadataFacet(address(diamond)).getGotchiTraitsIndex(0);
        for (uint256 i = 0; i < indexs.length; i++) {
            console.log("indexs[%s] = %s", i, indexs[i]);
        }

        string memory uri = svgFacet.getGotchipusSvg(0);
        assertTrue(bytes(uri).length > 0, "SVG should not be empty");

        vm.stopPrank();
    }
}
