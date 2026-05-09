// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { LibGotchiConstants } from "./LibGotchiConstants.sol";
import { GotchipusInfo, AppStorage, LibAppStorage } from "./LibAppStorage.sol";

library LibExperience {

    function sqrt(uint32 x) internal pure returns (uint32 y) {
        if (x == 0) return 0;

        uint32 z = (x + 1) / 2;
        y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) /2;
        }
    }

    function power15(uint32 x) internal pure returns (uint32) {
        if (x == 0) return 0;
        if (x == 1) return 1;

        uint32 base = sqrt(x);
        uint32 baseSquared = base * base;

        if (baseSquared == x) {
            return x * base;
        }

        uint32 nextBase = base + 1;
        uint32 nextSquared = nextBase * nextBase;

        if (x < nextSquared) {
            uint256 basePower15 = baseSquared * base;
            uint256 nextPower15 = nextSquared * nextBase;

            uint256 ratio = ((x - baseSquared) * LibGotchiConstants.PRECISION) / (nextSquared - baseSquared);
            uint256 interpolated = basePower15 + ((nextPower15 - basePower15) * ratio) / LibGotchiConstants.PRECISION;
            
            return uint32(interpolated);
        }

        return x * base;
    }

    function calculateRequiredExp(uint16 level) internal pure returns (uint32) {
        require(level <= LibGotchiConstants.MAX_LEVEL, "LibExperience: Invalid level");

        if (level == 1) return 0;

        // XP = (OFFSET + STEP * level)^1.5
        uint32 base = LibGotchiConstants.BASE_OFFSET + LibGotchiConstants.EXP_STEP * level;
        uint32 result = power15(base);
        return result;
    }

    function calculateLevelFromExp(uint32 currentExp) internal pure returns (uint16) {
        if (currentExp == 0) return 1;
        
        uint32 accumulatedExp = 0;
        
        for (uint16 level = 2; level <= LibGotchiConstants.MAX_LEVEL; level++) {
            uint32 requiredExp = calculateRequiredExp(level);
            
            if (accumulatedExp + requiredExp > currentExp) {
                return level - 1;
            }
            
            accumulatedExp += requiredExp;
        }
        
        return LibGotchiConstants.MAX_LEVEL;
    }

    /**
     * Calculates total attribute points based on level and rarity.
     * Includes:
     * - Base Points:
     * Levels 1–20: +3 per level  
     * Levels 21–50: +2 per level  
     * Levels 51–100: +1 per level  
     * Levels 101+: +1 per 2 levels
     * - Rarity Bonus (every 10 levels):
     * common: +0, rare: +1, epic: +2, legendary: +3
     * - Milestone Bonus:
     * Every 25 levels: +5  
     * Every 50 levels: +10 
     * Every 100 levels: +20
     */
    function calculateSkillPoints(uint8 rarity, uint16 level) internal pure returns (uint16 point) {
        if (level <= 20) {
            point += 3;
        } else if (level <= 50) {
            point += 2;
        } else if (level <= 100) {
            point += 1;
        } else if (level % 2 == 0) {
            point += 1;
        }

        if (level % 100 == 0) {
            point += 20;
        } else if (level % 50 == 0) {
            point += 10;
        } else if (level % 25 == 0) {
            point += 5;
        } else if (level % 10 == 0) {
            if (rarity == 1) {
                point += 1;
            } else if (rarity == 2) {
                point += 2;
            } else if (rarity == 3) {
                point += 3;
            }
        }
    }


    function getExperience(address sender, uint256 tokenId) internal view returns (uint32[2] memory exp_) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        GotchipusInfo storage info = s.ownedGotchipusInfos[sender][tokenId];
        exp_ = [info.leveling.currentExp, info.leveling.totalExp];
    }
}