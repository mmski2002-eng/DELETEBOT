//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/utils/Create2.sol";

contract GotchipusCreate2Factory {
    address public latestDeployAddress;
    mapping (bytes32 => address) deployAddress;

    function deployToken(bytes32 salt, bytes calldata initializationCode) 
        external 
        returns (address) 
    {
        latestDeployAddress = Create2.deploy(
            0,
            salt,
            initializationCode
        );

        deployAddress[salt] = latestDeployAddress;
        return latestDeployAddress;
    }

    function computeTokenAddress(bytes32 salt, bytes32 bytecodeHash) 
        public 
        view 
        returns (address) 
    {
        return Create2.computeAddress(
            salt,
            bytecodeHash
        );
    }
}