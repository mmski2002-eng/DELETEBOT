// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { GotchipusInfo, GotchipusCore, SoulCore, AppStorage, LibAppStorage } from "./LibAppStorage.sol";
import { LibGotchiConstants } from "./LibGotchiConstants.sol";
import { LibExperience } from "./LibExperience.sol";
import { LibSoul } from "./LibSoul.sol";
import { LibDynamicStates } from "../libraries/LibDynamicStates.sol";

library LibAttributes {

    function initializeAttribute(address sender, uint256 tokenId, uint8 rarity, address stakeToken, uint256 stakeAmount) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        GotchipusInfo storage info = s.ownedGotchipusInfos[sender][tokenId];
        
        uint32 strength;
        uint32 defense;
        uint32 mind;
        uint32 vitality;
        uint32 agility;
        uint32 luck;

        if (rarity == 0) {
            (strength, defense, mind, vitality, agility, luck) = (1200, 1200, 1200, 1200, 1200, 1200);
        } else if (rarity == 1) {
            (strength, defense, mind, vitality, agility, luck) = (1500, 1500, 1500, 1500, 1500, 1500);
        } else if (rarity == 2) {
            (strength, defense, mind, vitality, agility, luck) = (1800, 1800, 1800, 1800, 1800, 1800);
        } else if (rarity == 3) {
            (strength, defense, mind, vitality, agility, luck) = (2200, 2200, 2200, 2200, 2200, 2200);
        }

        info.core = GotchipusCore({
            strength: strength,
            defense: defense,
            mind: mind,
            vitality: vitality,
            agility: agility,
            luck: luck,
            soul: LibSoul.initializeSoul(stakeToken, stakeAmount)
        });

        info.states = LibDynamicStates.initializeStates(vitality);
    }

    function calculateAttribute(address sender, uint256 tokenId) internal view returns (uint32[6] memory) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        GotchipusInfo storage info = s.ownedGotchipusInfos[sender][tokenId];
        uint32 strength = info.core.strength;
        uint32 defense = info.core.defense;
        uint32 mind = info.core.mind;
        uint32 vitality = info.core.vitality;
        uint32 agility = info.core.agility;
        uint32 luck = info.core.luck;

        return [strength, defense, mind, vitality, agility, luck];
    }

    function addClampedUint8(uint8 value, uint8 amount) internal pure returns (uint8) {
        unchecked {
            uint256 v = uint256(value) + uint256(amount);
            if (v > type(uint8).max) return type(uint8).max;
            return uint8(v);
        }
    }

    function addClampedUint32(uint32 value, uint32 amount) internal pure returns (uint32) {
        unchecked {
            uint256 v = uint256(value) + uint256(amount);
            if (v > type(uint32).max) return type(uint32).max;
            return uint32(v);
        }
    }
}