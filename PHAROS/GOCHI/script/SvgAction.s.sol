// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { Diamond } from "../src/Diamond.sol";
import { GetSvgBytes } from "../test/utils/GetSvgBytes.sol";
import { ISvgFacet } from "../src/interfaces/ISvgFacet.sol";
import { LibSvg } from "../src/libraries/LibSvg.sol";

contract SvgAction is Script {
    function run() external {
        action();
    }

    function _storeSvg(ISvgFacet svgFacet) internal {
        // string[9] memory bgs = GetSvgBytes.getBgBytes();
        // string[9] memory bodys = GetSvgBytes.getBodyBytes();
        // string[9] memory eyes = GetSvgBytes.getEyeBytes();
        // string[9] memory hands = GetSvgBytes.getHandBytes();
        // string[9] memory heads = GetSvgBytes.getHeadBytes();
        string[9] memory clothess = GetSvgBytes.getClothesBytes();
        
        // LibSvg.SvgItem[] memory bgItems = new LibSvg.SvgItem[](1);
        // LibSvg.SvgItem[] memory bodyItems = new LibSvg.SvgItem[](1);
        // LibSvg.SvgItem[] memory eyeItems = new LibSvg.SvgItem[](1);
        // LibSvg.SvgItem[] memory handItems = new LibSvg.SvgItem[](1);
        // LibSvg.SvgItem[] memory headItems = new LibSvg.SvgItem[](1);
        LibSvg.SvgItem[] memory clothesItems = new LibSvg.SvgItem[](1);

        // We need to create a separate contract for each trait to avoid exceeding the contract size limit.
        for (uint8 i = 0; i < 9; i++) {
            // store background svg
            // bytes memory bgSvg= bytes(bgs[i]);
            // bgItems[0] = LibSvg.SvgItem({
            //     svgType: LibSvg.SVG_TYPE_BG,
            //     size: bgSvg.length
            // });
            // svgFacet.storeSvg(bgSvg, bgItems);

            // store body svg
            // bytes memory bodySvg = bytes(bodys[i]);
            // bodyItems[0] = LibSvg.SvgItem({
            //     svgType: LibSvg.SVG_TYPE_BODY,
            //     size: bodySvg.length
            // });
            // svgFacet.storeSvg(bodySvg, bodyItems);

            // // store eye svg
            // bytes memory eyeSvg = bytes(eyes[i]);
            // eyeItems[0] = LibSvg.SvgItem({
            //     svgType: LibSvg.SVG_TYPE_EYE,
            //     size: eyeSvg.length
            // });
            // svgFacet.storeSvg(eyeSvg, eyeItems);

            // // store hand svg
            // bytes memory handSvg = bytes(hands[i]);
            // handItems[0] = LibSvg.SvgItem({
            //     svgType: LibSvg.SVG_TYPE_HAND,
            //     size: handSvg.length
            // });
            // svgFacet.storeSvg(handSvg, handItems);

            // // store head svg
            // bytes memory headSvg = bytes(heads[i]);
            // headItems[0] = LibSvg.SvgItem({
            //     svgType: LibSvg.SVG_TYPE_HEAD,
            //     size: headSvg.length
            // });
            // svgFacet.storeSvg(headSvg, headItems);

            // // store clothes svg
            bytes memory clothesSvg = bytes(clothess[i]);
            clothesItems[0] = LibSvg.SvgItem({
                svgType: LibSvg.SVG_TYPE_CLOTHES,
                size: clothesSvg.length
            });
            svgFacet.storeSvg(clothesSvg, clothesItems);
        }
    }

    function action() public {
        vm.startBroadcast();

        Diamond diamond = Diamond(payable(0x0000000038f050528452D6Da1E7AACFA7B3Ec0a8));
        ISvgFacet svgFacet = ISvgFacet(address(diamond));

        _storeSvg(svgFacet);

        vm.stopBroadcast();
    }

}