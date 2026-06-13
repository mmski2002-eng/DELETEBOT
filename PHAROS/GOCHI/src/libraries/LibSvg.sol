// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { LibAppStorage, AppStorage, SvgLayer } from "./LibAppStorage.sol";
import { LibStrings } from "./LibStrings.sol";

library LibSvg {
    uint256 internal constant MAX_SIZE = 24_576;
    bytes32 internal constant SVG_TYPE_PHAROS = "gotchipus-pharos";
    bytes32 internal constant SVG_TYPE_BG = "gotchipus-bg";
    bytes32 internal constant SVG_TYPE_BODY = "gotchipus-body";
    bytes32 internal constant SVG_TYPE_HAND = "gotchipus-hand";
    bytes32 internal constant SVG_TYPE_CLOTHES = "gotchipus-clothes";
    bytes32 internal constant SVG_TYPE_FACE = "gotchipus-face";
    bytes32 internal constant SVG_TYPE_MOUTH = "gotchipus-mouth";
    bytes32 internal constant SVG_TYPE_EYE = "gotchipus-eye";
    bytes32 internal constant SVG_TYPE_HEAD = "gotchipus-head";
    
    event StoreSvg(SvgItem[] items);
    event UpdateSvg(SvgItem[] items);

    struct SvgItem {
        bytes32 svgType;
        uint256 size;
    }

    function getWearableTypeIndex(bytes32 wearableType) internal pure returns (uint256) {
        if (wearableType == SVG_TYPE_BODY) {
            return 1;
        } else if (wearableType == SVG_TYPE_CLOTHES) {
            return 2;
        } else if (wearableType == SVG_TYPE_HAND) {
            return 3;
        } else if (wearableType == SVG_TYPE_EYE) {
            return 4;
        } else if (wearableType == SVG_TYPE_FACE) {
            return 5;
        } else if (wearableType == SVG_TYPE_MOUTH) {
            return 6;
        } else if (wearableType == SVG_TYPE_HEAD) {
            return 7;
        } else {
            return 0;
        }
    }

    function getWearableTypeByIndex(uint8 index) internal pure returns (bytes32) {
        if (index == 1) {
            return SVG_TYPE_BODY;
        } else if (index == 2) {
            return SVG_TYPE_CLOTHES;
        } else if (index == 3) {
            return SVG_TYPE_HAND;
        } else if (index == 4) {
            return SVG_TYPE_EYE;
        } else if (index == 5) {
            return SVG_TYPE_FACE;
        } else if (index == 6) {
            return SVG_TYPE_MOUTH;
        } else if (index == 7) {
            return SVG_TYPE_HEAD;
        } else {
            return SVG_TYPE_BG;
        }
    }

    function readSvg(address svgContract) internal view returns (bytes memory svg) {
        assembly {
            let size := extcodesize(svgContract)
            if iszero(size) {
                mstore(0x00, 0x20)
                mstore(0x20, 18)
                mstore(0x40, "LibSvg: empty code")
                revert(0x00, 0x52)
            }

            svg := mload(0x40)
            mstore(svg, size)
            extcodecopy(svgContract, add(svg, 32), 0, size)
            mstore(0x40, add(add(svg, 32), add(add(size, 31), not(31))))
        }
    }

    function sliceSvg(bytes32 svgType, uint256 id) internal view returns (bytes memory svg) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        SvgLayer[] storage svgLayers = s.svgLayers[svgType];
        svg = sliceSvg(svgLayers, id);
    }

    function sliceSvg(SvgLayer[] storage svgLayers, uint256 id) internal view returns (bytes memory svg) {
        SvgLayer storage svgLayer = svgLayers[id];
        address svgContract = svgLayer.svgLayerContract;
        uint256 offset = svgLayer.offset;
        uint256 size = svgLayer.size;

        assembly {
            svg := mload(0x40)
            mstore(svg, size)
            let dataPtr := add(svg, 32)
            extcodecopy(svgContract, dataPtr, offset, size)
            mstore(0x40, add(dataPtr, and(add(size, 31), not(31))))
        }
    }

    function storeSvgInContract(bytes memory svg) internal returns (address svgContract) {
        assembly {
            let len := mload(svg)
            if iszero(lt(len, MAX_SIZE)) {
                mstore(0x00, 0x20)
                mstore(0x20, 30)
                mstore(0x40, "LibSvg: Exceeded contract size")
                revert(0x00, 0x5e)
            }

            let total := add(len, 14)
            let code := mload(0x40)
            mstore(0x40, add(code, and(and(total, 0x1f), not(0x1f))))

            /**
             * push 14 bytes header
             * 0: 61 LL HH      PUSH2 len
             * 3: 60 0e         PUSH1 0x0e (runtime offset)
             * 5: 60 00         PUSH1 0x00 (mem pos)
             * 7: 39            CODECOPY
             * 8: 61 LL HH      PUSH2 len
             * 11: 60 00        PUSH1 0x00
             * 13: f3           RETURN
             */
            // PUSH2 len
            mstore8(code, 0x61)                     // 0
            mstore8(add(code, 1), shr(8, len))      // 1: len high
            mstore8(add(code, 2), and(len, 0xff))   // 2: len low
            // PUSH1 0x0e
            mstore8(add(code, 3), 0x60)
            mstore8(add(code, 4), 0x0e)
            // PUSH1 0x00
            mstore8(add(code, 5), 0x60)
            mstore8(add(code, 6), 0x00)
            // CODECOPY
            mstore8(add(code, 7), 0x39)
            // PUSH2 len
            mstore8(add(code, 8), 0x61)
            mstore8(add(code, 9), shr(8, len))
            mstore8(add(code, 10), and(len, 0xff))
            // PUSH1 0x00
            mstore8(add(code, 11), 0x60)
            mstore8(add(code, 12), 0x00)
            // RETURN
            mstore8(add(code, 13), 0xf3)

            let src := add(svg, 32)
            let dst := add(code, 14)
            for { let off := 0 } lt(off, len) { off := add(off, 32)} {
                mstore(add(dst, off), mload(add(src, off)))
            }
            
            svgContract := create(0, code, total)
            if iszero(svgContract) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }

    function storeSvg(bytes calldata svg, SvgItem[] calldata svgItems) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        address svgContract = storeSvgInContract(svg);
        uint256 offset;
        
        for (uint256 i = 0; i < svgItems.length; i++) {
            SvgItem calldata item = svgItems[i];
            s.svgLayers[item.svgType].push(SvgLayer(svgContract, uint16(offset), uint16(item.size)));
            offset += item.size;
        }
        emit StoreSvg(svgItems);
    }

    function updateSvg(bytes calldata svg, SvgItem[] calldata svgItems) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        address svgContract = storeSvgInContract(svg);
        uint256 offset;

        for (uint256 i = 0; i < svgItems.length; i++) {
            SvgItem calldata item = svgItems[i];
            s.svgLayers[item.svgType].push(SvgLayer(svgContract, uint16(offset), uint16(item.size)));
            offset += item.size;
        }
        emit UpdateSvg(svgItems);
    }
}