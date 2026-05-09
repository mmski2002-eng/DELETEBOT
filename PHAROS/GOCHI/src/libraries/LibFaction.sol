// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { LibGotchiConstants } from "./LibGotchiConstants.sol";
import { GotchipusInfo, FactionCore, AppStorage, LibAppStorage } from "./LibAppStorage.sol";

library LibFaction {
    enum GotchiFaction {
        COMBAT,
        DEFENSE,
        TECHNOLOGY
    }

    enum GotchiAttributes {
        // combat
        FLAME,
        STORM,
        SHADOW,
        // defense
        ICE,
        EARTH,
        LIGHT,
        // technology
        LIGHTNING,
        WATER,
        VOID
    }

    /**
     * 
     * Faction Bonuses:
     * Combat: Strength: +15%, Agility: +8%
     * Defense: Defense: +15%, Vitality: +8%
     * Technology: mind: +15%, Luck: +8%
     */
    function initializeFaction(address sender, uint256 tokenId, uint256 randomSeed, uint8 rarity) internal returns (uint8) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        GotchipusInfo storage info = s.ownedGotchipusInfos[sender][tokenId];
        
        uint256 randomFactionValue = randomSeed % 10000;
        uint256 randomAttributeValue = randomSeed % 3;
        uint256 baseMastery = randomSeed % 2;
        uint8 faction;
        uint8 attr;
        
        if (randomFactionValue < LibGotchiConstants.COMBAT_WEIGHT) {
            faction = 0;
            attr = uint8(randomAttributeValue);
        } else if (randomFactionValue < LibGotchiConstants.COMBAT_WEIGHT + LibGotchiConstants.DEFENSE_WEIGHT) {
            faction = 1;
            attr = uint8(3 + randomAttributeValue);
        } else {
            faction = 2;
            attr = uint8(6 + randomAttributeValue);
        }

        info.faction = FactionCore({
            primaryFaction: faction,
            dominantAttr: attr,
            factionPurity: 100,
            attributeMastery: uint8(baseMastery) + rarity
        });

        return faction;
    }

    function getFactionName(uint8 faction_) internal pure returns (string memory) {
        require(LibGotchiConstants.FACTION_COUNT > faction_, "LibFaction: Invalid faction name");
        if (faction_ == 0) return "COMBAT";
        if (faction_ == 1) return "DEFENSE";
        if (faction_ == 2) return "TECHNOLOGY";
        return "Unknown";
    }

    function getAttributesName(uint8 attr_) internal pure returns (string memory) {
        require(LibGotchiConstants.ATTRIBUTE_COUNT > attr_, "LibFaction: Invalid attribute name");
        if (attr_ == 0) return "FLAME";
        if (attr_ == 1) return "STORM";
        if (attr_ == 2) return "SHADOW";
        if (attr_ == 3) return "ICE";
        if (attr_ == 4) return "EARTH";
        if (attr_ == 5) return "LIGHT";
        if (attr_ == 6) return "LIGHTNING";
        if (attr_ == 7) return "WATER";
        if (attr_ == 8) return "VOID";
        return "Unknown";
    }
}