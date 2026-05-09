// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { WearableDiamond } from "../src/WearableDiamond/WearableDiamond.sol";
import { DiamondCutFacet } from "../src/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../src/facets/DiamondLoupeFacet.sol";
import { OwnershipFacet } from "../src/facets/OwnershipFacet.sol";
import { WearableFacet } from "../src/WearableDiamond/facets/WearableFacet.sol";
import { IDiamondCut } from "../src/interfaces/IDiamondCut.sol";
import { Diamond } from "../src/Diamond.sol";
import { GotchiWearableFacet } from "../src/facets/GotchiWearableFacet.sol";
import { FacetSelectors } from "../test/utils/FacetSelectors.sol";
import { WearableInfo } from "../src/libraries/LibAppStorage.sol";
import { LibStrings } from "../src/libraries/LibStrings.sol";

contract WearableDeploy is Script {

    struct Deployment {
        DiamondCutFacet diamondCutFacet;
        DiamondLoupeFacet diamondLoupeFacet;
        OwnershipFacet ownershipFacet;
        WearableFacet wearableFacet;
        WearableDiamond wearableDiamond;
        GotchiWearableFacet gotchiWearableFacet;
    }

    function run() external returns (Deployment memory) {
        return deploy();
    }

    /**
     * wearableDiamond 0x22646d4E832132E93F2dEF9Ea875Aa5329B7feF4
     */

    function deploy() public returns (Deployment memory) {
        vm.startBroadcast();

        // DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        // DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();
        // OwnershipFacet ownershipFacet = new OwnershipFacet();
        WearableFacet wearableFacet = new WearableFacet();

        // WearableDiamond wearableDiamond = new WearableDiamond(msg.sender, address(diamondCutFacet), address(diamondLoupeFacet), address(ownershipFacet));

        bytes4[] memory wearableFacetFunctions = new bytes4[](12);
        wearableFacetFunctions[0] = WearableFacet.name.selector;
        wearableFacetFunctions[1] = WearableFacet.symbol.selector;
        wearableFacetFunctions[2] = WearableFacet.balanceOf.selector;
        wearableFacetFunctions[3] = WearableFacet.balanceOfBatch.selector;
        wearableFacetFunctions[4] = WearableFacet.uri.selector;
        wearableFacetFunctions[5] = WearableFacet.isApprovedForAll.selector;
        wearableFacetFunctions[6] = WearableFacet.setApprovalForAll.selector;
        wearableFacetFunctions[7] = WearableFacet.setBaseURI.selector;
        wearableFacetFunctions[8] = WearableFacet.safeTransferFrom.selector;
        wearableFacetFunctions[9] = WearableFacet.safeBatchTransferFrom.selector;
        wearableFacetFunctions[10] = WearableFacet.mintWearable.selector;
        wearableFacetFunctions[11] = WearableFacet.claimWearable.selector;

        IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](1);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = WearableFacet.batchMintWearable.selector;

        facetCuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(wearableFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });

        WearableDiamond wearableDiamond = WearableDiamond(payable(0x22646d4E832132E93F2dEF9Ea875Aa5329B7feF4));
        IDiamondCut(address(wearableDiamond)).diamondCut(facetCuts, address(0), "");

        // gotchi diamond action
        // Diamond gotchiDiamond = Diamond(payable(0x000000007B5758541e9d94a487B83e11Cd052437));
        // GotchiWearableFacet gotchiWearableFacet = new GotchiWearableFacet();

        // IDiamondCut.FacetCut[] memory gotchiFacetCuts = new IDiamondCut.FacetCut[](1);

        // gotchiFacetCuts[0] = IDiamondCut.FacetCut({
        //     facetAddress: address(gotchiWearableFacet),
        //     action: IDiamondCut.FacetCutAction.Add,
        //     functionSelectors: FacetSelectors.getSelectors("GotchiWearableFacet")
        // });

        // IDiamondCut(address(gotchiDiamond)).diamondCut(gotchiFacetCuts, address(0), "");
        // GotchiWearableFacet(address(gotchiDiamond)).setWearableDiamond(address(wearableDiamond));

        vm.stopBroadcast();

        return Deployment({
            diamondCutFacet: DiamondCutFacet(address(0)),
            diamondLoupeFacet: DiamondLoupeFacet(address(0)),
            ownershipFacet: OwnershipFacet(address(0)),
            wearableFacet: wearableFacet,
            wearableDiamond: wearableDiamond,
            gotchiWearableFacet: GotchiWearableFacet(address(0))
        });
    }
}