// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AppStorage, LibAppStorage, TraitsOffset } from "../libraries/LibAppStorage.sol";
import { LibGotchiConstants } from "../libraries/LibGotchiConstants.sol";


library LibDna {
    event SetRuleVersion(uint8 indexed ruleVersion);

    function getRandomGene(bytes32 seed) internal pure returns (uint256) {
        return uint256(seed);
    }

    function getGene(uint256 gotchipusTokenId, uint256 index) internal view returns (uint256) {
        require(index < LibGotchiConstants.TOTAL_GENES, "Invalid gene index");

        AppStorage storage s = LibAppStorage.diamondStorage();
        uint256 geneSeed = s.ownedGotchipusInfos[s.tokenOwners[gotchipusTokenId]][gotchipusTokenId].dna.geneSeed;
        uint256 segment = index / 1000;
        uint256 offset = index % 1000;

        bytes32 subSeed = keccak256(abi.encodePacked(geneSeed, segment));
        for (uint256 i=0; i < offset; i++) {
            subSeed = keccak256(abi.encodePacked(subSeed));
        }
        
        return uint256(subSeed) % 10;
    }

    /**
     * Genes Traits
     * G0 Element
     * G1 Global Mutation 
     * G2 Mutation Traits
     * G3 Skin Color
     * G4 Skin Mutation
     * G5 Skin Traits
     * G6 Head Mutation
     * G7 Head Traits
     * G8 Left Eye Mutation
     * G9 Left Eye Traits
     * G10 Left Eye Color
     * G11 Right Eye Mutation
     * G12 Right Eye Traits
     * G13 Right Eye Color
     * G14 Left Hand Mutation
     * G15 Left Hand Traits
     * G16 Left Hand Color
     * G17 Right Hand Mutation
     * G18 Right Hand Traits
     * G19 Right Hand Color
     * G20 Tentacle 1 Traits
     * G21 Tentacle 1 Color
     * G22 Tentacle 2 Traits
     * G23 Tentacle 2 Color
     * G24 Tentacle 3 Traits
     * G25 Tentacle 3 Color
     */
    function computePacked(uint256 gotchipusTokenId) internal view returns (uint256 packed) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        uint256 len = s.traitsOffset.length;

        for (uint256 i = 0; i < len; i++) {
            uint256 val = getGene(gotchipusTokenId, i);
            uint256 offset = s.traitsOffset[i].offset;
            uint256 width = s.traitsOffset[i].width;

            assembly {
                let mask := sub(shl(width, 1), 1)
                let masked := and(val, mask)
                let shifted := shl(offset, masked)
                packed := or(packed, shifted)
            }
        }
    }

    function unpackTraits(uint256 gotchipusTokenId) internal view returns (uint256[] memory traitsIndex) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        uint256 len = s.traitsOffset.length;
        traitsIndex = new uint256[](len);
        uint256 packed = s.tokenTraitsPacked[gotchipusTokenId];
        TraitsOffset[] storage traitsOffset = s.traitsOffset;

        assembly {
            let dataPtr := add(traitsIndex, 0x20)
            let arrSlot := traitsOffset.slot
            mstore(0x0, arrSlot)
            let base := keccak256(0x0, 0x20)

            for { let i := 0} lt(i, len) { i := add(i, 1) } {
                let elemSlot := add(base, i)
                let raw := sload(elemSlot)
                let offset := and(raw, 0xffff)
                let width := and(shr(16, raw), 0xff)

                let mask := sub(shl(width, 1), 1)
                let val := and(shr(offset, packed), mask)
                mstore(add(dataPtr, mul(i, 0x20)), val)
            }
        }
    }

    function setPacked(uint256 gotchipusTokenId, uint256 packed) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        s.tokenTraitsPacked[gotchipusTokenId] = packed;
    }
}