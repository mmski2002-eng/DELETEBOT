// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { Diamond } from "../src/Diamond.sol";
import { InitDiamond } from "../src/InitDiamond.sol";
import { DiamondCutFacet } from "../src/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../src/facets/DiamondLoupeFacet.sol";
import { GotchipusFacet } from "../src/facets/GotchipusFacet.sol";
import { OwnershipFacet } from "../src/facets/OwnershipFacet.sol";
import { AttributesFacet } from "../src/facets/AttributesFacet.sol";
import { DNAFacet } from "../src/facets/DNAFacet.sol";
import { HooksFacet } from "../src/facets/HooksFacet.sol";
import { IDiamondCut } from "../src/interfaces/IDiamondCut.sol";
import { TraitsOffset } from "../src/libraries/LibAppStorage.sol";
import { ERC6551Registry } from "../src/ERC6551Registry.sol";
import { ERC6551Account } from "../src/ERC6551Account.sol";
import { ERC6551Facet } from "../src/facets/ERC6551Facet.sol";
import { SvgFacet } from "../src/facets/SvgFacet.sol";
import { PaymasterFacet } from "../src/facets/PaymasterFacet.sol";
import { LibSvg } from "../src/libraries/LibSvg.sol";
import { FacetSelectors } from "../test/utils/FacetSelectors.sol";
import { TimeFacet } from "../src/facets/TimeFacet.sol";
import { MintFacet } from "../src/facets/MintFacet.sol";
import { MetadataFacet } from "../src/facets/MetadataFacet.sol";
import { GotchiWearableFacet } from "../src/facets/GotchiWearableFacet.sol";

contract Deploy is Script {
    struct Deployment {
        Diamond diamond;
        InitDiamond initDiamond;
        DiamondCutFacet diamondCutFacet;
        DiamondLoupeFacet diamondLoupeFacet;
        GotchipusFacet gotchipusFacet;
        OwnershipFacet ownershipFacet;
        AttributesFacet attributesFacet;
        DNAFacet dnaFacet;
        HooksFacet hooksFacet;
        ERC6551Account erc6551Account;
        ERC6551Registry erc6551Registry;
        ERC6551Facet erc6551Facet;
        SvgFacet svgFacet;
        PaymasterFacet paymasterFacet;
        TimeFacet timeFacet;
        MintFacet mintFacet;
        MetadataFacet metadataFacet;
        GotchiWearableFacet gotchiWearableFacet;
    }

    function run() external returns (Deployment memory) {
        return deploy();
    }

    /** 
     * Pharos testnet
     * create2Factory: 0x000000f2529CaFE47f13BC4d674e343A97A870c1
     * diamond: 0x000000007B5758541e9d94a487B83e11Cd052437, 
     * ERC6551Registry: 0x000000E7C8746fdB64D791f6bb387889c5291454
     * ERC6551Account: 0xb98aA33B8a0C6Ca0fb5667DC2601032Bff92D7B3
     * 
     * Test diamond
     * 0x8606b31a4e182735B283cA3339726d4130fCC5Ed
     */

    function deploy() public returns (Deployment memory) {
        vm.startBroadcast();
        
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();
        InitDiamond initDiamond = new InitDiamond();
        GotchipusFacet gotchipusFacet = new GotchipusFacet();
        AttributesFacet attributesFacet = new AttributesFacet();
        DNAFacet dnaFacet = new DNAFacet();
        HooksFacet hooksFacet = new HooksFacet();
        ERC6551Account erc6551Account = ERC6551Account(payable(0xb98aA33B8a0C6Ca0fb5667DC2601032Bff92D7B3));
        ERC6551Registry erc6551Registry = ERC6551Registry(0x000000E7C8746fdB64D791f6bb387889c5291454);
        ERC6551Facet erc6551Facet = new ERC6551Facet();
        SvgFacet svgFacet = new SvgFacet();
        PaymasterFacet paymasterFacet = new PaymasterFacet();
        TimeFacet timeFacet = new TimeFacet();
        MintFacet mintFacet = new MintFacet();
        MetadataFacet metadataFacet = new MetadataFacet();
        GotchiWearableFacet gotchiWearableFacet = new GotchiWearableFacet();

        Diamond diamond = new Diamond(msg.sender, address(diamondCutFacet), address(diamondLoupeFacet), address(ownershipFacet));

        // DiamondCutFacet diamondCutFacet = DiamondCutFacet(0xDeD276F88612f95d675aaEe3694ABB18a66F8951);
        // DiamondLoupeFacet diamondLoupeFacet = DiamondLoupeFacet(0x24ded15aed0CCe141EAf98BF15bC8843D7285a62);
        // OwnershipFacet ownershipFacet = OwnershipFacet(0x966d7AB2A5B4A1d74271eDD6974d79D2f52d759a);
        // Diamond diamond = Diamond(payable(0x000000007B5758541e9d94a487B83e11Cd052437));

        IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](11);
        facetCuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(erc6551Facet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: FacetSelectors.getSelectors("ERC6551Facet")
        });
        facetCuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(hooksFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: FacetSelectors.getSelectors("HooksFacet")
        });
        facetCuts[2] = IDiamondCut.FacetCut({
            facetAddress: address(gotchipusFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: FacetSelectors.getSelectors("GotchipusFacet")
        });
        facetCuts[3] = IDiamondCut.FacetCut({
            facetAddress: address(attributesFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: FacetSelectors.getSelectors("AttributesFacet")
        });        
        facetCuts[4] = IDiamondCut.FacetCut({
            facetAddress: address(dnaFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: FacetSelectors.getSelectors("DNAFacet")
        });
        facetCuts[5] = IDiamondCut.FacetCut({
            facetAddress: address(svgFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: FacetSelectors.getSelectors("SvgFacet")
        });
        facetCuts[6] = IDiamondCut.FacetCut({
            facetAddress: address(paymasterFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: FacetSelectors.getSelectors("PaymasterFacet")
        });
        facetCuts[7] = IDiamondCut.FacetCut({
            facetAddress: address(timeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: FacetSelectors.getSelectors("TimeFacet")
        });
        facetCuts[8] = IDiamondCut.FacetCut({
            facetAddress: address(mintFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: FacetSelectors.getSelectors("MintFacet")
        });
        facetCuts[9] = IDiamondCut.FacetCut({
            facetAddress: address(metadataFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: FacetSelectors.getSelectors("MetadataFacet")
        });
        facetCuts[10] = IDiamondCut.FacetCut({
            facetAddress: address(gotchiWearableFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: FacetSelectors.getSelectors("GotchiWearableFacet")
        });

        bytes32[8] memory svgTypes;
        svgTypes[0] = LibSvg.SVG_TYPE_BG;
        svgTypes[1] = LibSvg.SVG_TYPE_BODY;
        svgTypes[2] = LibSvg.SVG_TYPE_CLOTHES;
        svgTypes[3] = LibSvg.SVG_TYPE_HAND;
        svgTypes[4] = LibSvg.SVG_TYPE_EYE;
        svgTypes[5] = LibSvg.SVG_TYPE_FACE;
        svgTypes[6] = LibSvg.SVG_TYPE_MOUTH;
        svgTypes[7] = LibSvg.SVG_TYPE_HEAD;
        
        InitDiamond.Args memory initArgs = InitDiamond.Args({
            name: "Gotchipus",
            symbol: "GOTCHI",
            baseUri: "https://app.gotchipus.com/metadata/",
            createUtcHour: 0,
            traitsOffset: getTraitsOffset(),
            erc6551Registry: address(erc6551Registry),
            erc6551AccountImplementation: address(erc6551Account),
            svgTypes: svgTypes,
            salt: 46785146710873639958810097543422045518556785791473492795158444787863316856832
        });
        bytes memory initCalldata = abi.encodeWithSelector(InitDiamond.init.selector, initArgs);

        IDiamondCut(address(diamond)).diamondCut(facetCuts, address(initDiamond), initCalldata);

        GotchiWearableFacet(address(diamond)).setWearableDiamond(address(0x22646d4E832132E93F2dEF9Ea875Aa5329B7feF4));

        vm.stopBroadcast();
        
        return Deployment({
            diamond: diamond,
            initDiamond: initDiamond,
            diamondCutFacet: diamondCutFacet,
            diamondLoupeFacet: diamondLoupeFacet,
            gotchipusFacet: gotchipusFacet,
            ownershipFacet: ownershipFacet,
            attributesFacet: attributesFacet,
            dnaFacet: dnaFacet,
            hooksFacet: hooksFacet,
            erc6551Account: erc6551Account,
            erc6551Registry: erc6551Registry,
            erc6551Facet: erc6551Facet,
            svgFacet: svgFacet,
            paymasterFacet: paymasterFacet,
            timeFacet: timeFacet,
            mintFacet: mintFacet,
            metadataFacet: metadataFacet,
            gotchiWearableFacet: gotchiWearableFacet
        });
    }

    function getTraitsOffset() internal pure returns (TraitsOffset[] memory) {
        uint256 traitsNumber = 26;
        TraitsOffset[] memory traitsOffset = new TraitsOffset[](traitsNumber);
        uint8[26] memory widths = [uint8(3), 1, 4, 4, 1, 4, 1, 4, 1, 4, 4, 1, 4, 4, 1, 4, 4, 1, 4, 4, 4, 4, 4, 4, 4, 4];
        uint8 offset = 0;

        for (uint256 i = 0; i < traitsNumber; i++) {
            traitsOffset[i] = TraitsOffset({
                offset: offset,
                width: widths[i]
            });
            offset += widths[i];
        }

        return traitsOffset;
    }
}