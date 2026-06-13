// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { GotchipusInfo, SoulCore, AppStorage, LibAppStorage } from "./LibAppStorage.sol";
import { LibGotchiConstants } from "./LibGotchiConstants.sol";

library LibSoul {
    enum SoulState {
        DORMANT,
        CRITICAL,
        LOW,
        NORMAL,
        FULL
    }

    function initializeSoul(address stakeToken, uint256 stakeAmount) internal view returns (SoulCore memory sc) {
        uint256 rawSoul;
        if (stakeToken == address(0)) {
            rawSoul = stakeAmount * LibGotchiConstants.PHRS_TO_SOUL / 10**18;
        } else if (stakeToken == LibGotchiConstants.USDC) {
            rawSoul = stakeAmount * LibGotchiConstants.USDC_TO_SOUL / 10**6;
        } else if (stakeToken == LibGotchiConstants.USDT) {
            rawSoul = stakeAmount * LibGotchiConstants.USDT_TO_SOUL / 10**6;
        } else if (stakeToken == LibGotchiConstants.WETH) {
            rawSoul = stakeAmount * LibGotchiConstants.WETH_TO_SOUL / 10**18;
        } else if (stakeToken == LibGotchiConstants.WBTC) {
            rawSoul = stakeAmount * LibGotchiConstants.WBTC_TO_SOUL / 10**18;
        }

        uint32 soul = rawSoul > type(uint32).max ? type(uint32).max : uint32(rawSoul);

        sc = SoulCore({
            balance: soul,
            maxSoulCapacity: soul,
            lastSoulUpdate: uint32(block.timestamp),
            dormantSince: 4
        });
    }
    
    function getSoulStateName(uint8 state) internal pure returns (string memory) {
        if (state == 0) return "Dormant";
        if (state == 1) return "Critical";
        if (state == 2) return "Low";
        if (state == 3) return "Normal";
        if (state == 4) return "Full";
        return "Unknown";
    }
}