// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console } from "forge-std/Script.sol";
import { Diamond } from "../src/Diamond.sol";

contract GetInitCode is Script {
    function run() external view {
        address contractOwner = 0xbf4d96de3A49995dDE63aB3d3D10f3fe8EAc090E;
        address diamondCutFacet = 0xfb6CF9f914c76ccDc3Fc722b5c0D3EFa5C4F7DFA; 
        address diamondLoupeFacet = 0xd87AC654aA730ca72681a3Aa29898a8F0ae0dd57; 
        address ownershipFacet = 0x705F094215317bAe890b78d1b374E66caa052c12; 

        string memory artifact = vm.readFile("out/Diamond.sol/Diamond.json");
        bytes memory creationBytecode = vm.parseJsonBytes(artifact, ".bytecode.object");

        bytes memory constructorArgs = abi.encode(contractOwner, diamondCutFacet, diamondLoupeFacet, ownershipFacet);
        bytes memory initCode = bytes.concat(creationBytecode, constructorArgs);

        bytes32 initCodeHash = keccak256(initCode);

        console.log("Init Code:");
        console.logBytes(initCode);
        console.log("Init Code Hash:");
        console.logBytes32(initCodeHash);
    }
}