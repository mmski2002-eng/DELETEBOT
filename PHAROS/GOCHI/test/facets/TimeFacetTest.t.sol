// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../utils/DiamondFixture.sol";
import { ALICE } from "../utils/Constants.sol";
import { TimeFacet } from "../../src/facets/TimeFacet.sol";
import { LibTime } from "../../src/libraries/LibTime.sol";

contract TimeFacetTest is DiamondFixture {
    TimeFacet internal tf;

    function setUp() public override {
        super.setUp();
        tf = TimeFacet(address(diamond));
    }

    function testGetWeatherDefault() public view {
        LibTime.Weather w = tf.getWeather(0);
        assertEq(uint8(w), uint8(LibTime.Weather.UNKNOWN));
    }

    function testGetWeatherMultipleTimezones() public view {
        for (uint8 i; i < 24; i++) {
            LibTime.Weather w = tf.getWeather(i);
            assertEq(uint8(w), uint8(LibTime.Weather.UNKNOWN));
        }
    }

    function testUpdateWeatherSingle() public {
        uint8[] memory tz = new uint8[](1);
        LibTime.Weather[] memory conds = new LibTime.Weather[](1);
        tz[0] = 0;
        conds[0] = LibTime.Weather.CLEAR;

        tf.updateWeather(tz, conds);

        assertEq(uint8(tf.getWeather(0)), uint8(LibTime.Weather.CLEAR));
    }

    function testUpdateWeatherMultiple() public {
        uint8[] memory tz = new uint8[](3);
        LibTime.Weather[] memory conds = new LibTime.Weather[](3);
        tz[0] = 0;
        tz[1] = 8;
        tz[2] = 12;
        conds[0] = LibTime.Weather.CLEAR;
        conds[1] = LibTime.Weather.HEAVY_RAIN;
        conds[2] = LibTime.Weather.LIGHT_SNOW;

        tf.updateWeather(tz, conds);

        assertEq(uint8(tf.getWeather(0)), uint8(LibTime.Weather.CLEAR));
        assertEq(uint8(tf.getWeather(8)), uint8(LibTime.Weather.HEAVY_RAIN));
        assertEq(uint8(tf.getWeather(12)), uint8(LibTime.Weather.LIGHT_SNOW));
    }

    function testUpdateWeatherOverwrite() public {
        uint8[] memory tz = new uint8[](1);
        LibTime.Weather[] memory conds = new LibTime.Weather[](1);
        tz[0] = 5;
        conds[0] = LibTime.Weather.FOG;
        tf.updateWeather(tz, conds);

        conds[0] = LibTime.Weather.TORNADO;
        tf.updateWeather(tz, conds);

        assertEq(uint8(tf.getWeather(5)), uint8(LibTime.Weather.TORNADO));
    }

    function testUpdateWeatherOnlyOwner() public {
        uint8[] memory tz = new uint8[](1);
        LibTime.Weather[] memory conds = new LibTime.Weather[](1);
        tz[0] = 0;
        conds[0] = LibTime.Weather.CLEAR;

        vm.prank(ALICE);
        vm.expectRevert();
        tf.updateWeather(tz, conds);
    }

    function testUpdateWeatherDoesNotAffectOtherTimezones() public {
        uint8[] memory tz = new uint8[](1);
        LibTime.Weather[] memory conds = new LibTime.Weather[](1);
        tz[0] = 3;
        conds[0] = LibTime.Weather.HAILSTORM;
        tf.updateWeather(tz, conds);

        // timezone 4 should still be UNKNOWN
        assertEq(uint8(tf.getWeather(4)), uint8(LibTime.Weather.UNKNOWN));
    }

    function testFuzz_UpdateAndGetWeather(uint8 timezone, uint8 rawWeather) public {
        rawWeather = uint8(bound(uint256(rawWeather), 0, uint256(type(LibTime.Weather).max)));

        uint8[] memory tz = new uint8[](1);
        LibTime.Weather[] memory conds = new LibTime.Weather[](1);
        tz[0] = timezone;
        conds[0] = LibTime.Weather(rawWeather);

        tf.updateWeather(tz, conds);
        assertEq(uint8(tf.getWeather(timezone)), rawWeather);
    }
}
