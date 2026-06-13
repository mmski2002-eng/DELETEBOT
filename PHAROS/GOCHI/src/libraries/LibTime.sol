// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { LibAppStorage, AppStorage } from "./LibAppStorage.sol";

library LibTime {
    enum Weather {
        UNKNOWN,
        CLEAR,
        PARTLY_CLOUDY,
        OVERCAST,
        SHOWERS,
        LIGHT_RAIN,
        MODERATE_RAIN,
        HEAVY_RAIN,
        RAINSTORM,
        DRIZZLE,
        THUNDER_SHOWER,
        THUNDERSTORM,
        HAILSTORM,
        LIGHT_SNOW,
        MODERATE_SNOW,
        HEAVY_SNOW,
        SNOW_SHOWERS,
        BLIZZARD,
        SLEET,
        FREEZING_RAIN,
        HAIL,
        FOG,
        MIST,
        HAZE,
        DUST_STORM,
        SMOKE,
        BREEZE,
        WINDY,
        SQUALL,
        TORNADO,
        TYPHOON,
        HEATWAVE,
        COLDWAVE
    }

    event WeatherUpdated(uint8[] indexed timezones, Weather[] conditions);

    function getCurrentHour(uint32 _worldTime, uint8 _createTimeHour) internal view returns (uint8) {
        uint256 elapsedTime = block.timestamp - uint256(_worldTime);
        uint256 secondsInDay = elapsedTime % 1 days;
        uint256 hoursFromMidnight = secondsInDay / 1 hours;
        uint256 currentHour = (_createTimeHour + hoursFromMidnight) % 24;

        return uint8(currentHour);
    }

    function updateWeather(uint8[] calldata timezones, Weather[] calldata conds) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        for (uint256 i = 0; i < conds.length; i++) {
            s.weatherByTimezone[timezones[i]] = conds[i];
        }
        emit WeatherUpdated(timezones, conds);
    }
}