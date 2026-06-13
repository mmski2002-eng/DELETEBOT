// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

library LibBytes {
    function bytesToBytes32(bytes memory _bytes1, bytes memory _bytes2) internal pure returns (bytes32 result_) {
        bytes memory theBytes = abi.encodePacked(_bytes1, _bytes2);
        require(theBytes.length <= 32, "LibBytes: bytes array greater than 32");
        assembly {
            result_ := mload(add(theBytes, 32))
        }
    }
}