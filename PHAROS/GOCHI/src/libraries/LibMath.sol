// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;


library LibMath {
    function min(uint256 a, uint256 b) internal pure returns (uint256 z) {
        z = a > b ? b : a;
    }
}