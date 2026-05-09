// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Modifier } from "../libraries/LibAppStorage.sol";
import { LibTime } from "../libraries/LibTime.sol";

contract TimeFacet is Modifier {
    function getWeather(uint8 timezone) external view returns (LibTime.Weather) {
        return s.weatherByTimezone[timezone];
    }

    function updateWeather(uint8[] calldata timezones, LibTime.Weather[] calldata conds) external onlyOwner {
        LibTime.updateWeather(timezones, conds);
    }
}