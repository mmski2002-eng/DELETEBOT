// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { DiamondCutFacet } from "../src/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../src/facets/DiamondLoupeFacet.sol";
import { OwnershipFacet } from "../src/facets/OwnershipFacet.sol";

contract DiamondDeploy is Script {
    struct Deployment {
        DiamondCutFacet diamondCutFacet;
        DiamondLoupeFacet diamondLoupeFacet;
        OwnershipFacet ownershipFacet;
    }

    function run() external returns (Deployment memory) {
        return deploy();
    }

    function deploy() public returns (Deployment memory) {
        vm.startBroadcast();
        
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();

        vm.stopBroadcast();
        
        return Deployment({
            diamondCutFacet: diamondCutFacet,
            diamondLoupeFacet: diamondLoupeFacet,
            ownershipFacet: ownershipFacet
        });
    }

}