// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import { Diamond } from "../../src/Diamond.sol";
import { InitDiamond } from "../../src/InitDiamond.sol";
import { DiamondCutFacet } from "../../src/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../src/facets/DiamondLoupeFacet.sol";
import { GotchipusFacet } from "../../src/facets/GotchipusFacet.sol";
import { OwnershipFacet } from "../../src/facets/OwnershipFacet.sol";
import { AttributesFacet } from "../../src/facets/AttributesFacet.sol";
import { DNAFacet } from "../../src/facets/DNAFacet.sol";
import { HooksFacet } from "../../src/facets/HooksFacet.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { TraitsOffset, WearableInfo } from "../../src/libraries/LibAppStorage.sol";
import { ERC6551Registry } from "../../src/ERC6551Registry.sol";
import { ERC6551Account } from "../../src/ERC6551Account.sol";
import { ERC6551Facet } from "../../src/facets/ERC6551Facet.sol";
import { LibSvg } from "../../src/libraries/LibSvg.sol";
import { FacetSelectors } from "./FacetSelectors.sol";
import { GotchiWearableFacet } from "../../src/facets/GotchiWearableFacet.sol";
import { SvgFacet } from "../../src/facets/SvgFacet.sol";
import { ALICE } from "./Constants.sol";
import { TimeFacet } from "../../src/facets/TimeFacet.sol";
import { MintFacet } from "../../src/facets/MintFacet.sol";
import { MetadataFacet } from "../../src/facets/MetadataFacet.sol";
import { PaymasterFacet } from "../../src/facets/PaymasterFacet.sol";
import { WearableDiamond } from "../../src/WearableDiamond/WearableDiamond.sol";
import { WearableFacet } from "../../src/WearableDiamond/facets/WearableFacet.sol";
import { LibStrings } from "../../src/libraries/LibStrings.sol";
import { SecurityFacet } from "../../src/facets/SecurityFacet.sol";
import { IMintFacet } from "../../src/interfaces/IMintFacet.sol";
import { IERC6551Facet } from "../../src/interfaces/IERC6551Facet.sol";
import { IERC6551Account } from "../../src/interfaces/IERC6551Account.sol";

abstract contract DiamondFixture is Test {
    Diamond public diamond;
    InitDiamond public initDiamond;
    DiamondCutFacet public cutFacet;
    DiamondLoupeFacet public loupeFacet;
    GotchipusFacet public gotchipusFacet;
    OwnershipFacet public ownershipFacet;
    AttributesFacet public attributesFacet;
    DNAFacet public dnaFacet;
    HooksFacet public hooksFacet;
    ERC6551Facet public erc6551Facet;
    ERC6551Account public erc6551Account;
    ERC6551Registry public erc6551Registry;
    GotchiWearableFacet public gotchiWearableFacet;
    SvgFacet public svgFacet;
    PaymasterFacet public paymasterFacet;
    TimeFacet public timeFacet;
    MintFacet public mintFacet;
    MetadataFacet public metadataFacet;
    SecurityFacet public securityFacet;

    bytes32 public constant BG_BYTES32 = "gotchipus-bg";
    bytes32 public constant BODY_BYTES32 = "gotchipus-body";
    bytes32 public constant EYE_BYTES32 = "gotchipus-eye";
    bytes32 public constant HAND_BYTES32 = "gotchipus-hand";
    bytes32 public constant FACE_BYTES32 = "gotchipus-face";
    bytes32 public constant MOUTH_BYTES32 = "gotchipus-mouth";
    bytes32 public constant HEAD_BYTES32 = "gotchipus-head";
    bytes32 public constant CLOTHES_BYTES32 = "gotchipus-clothes";
    
    address internal owner = address(this);
    uint256 internal price = 0.04 ether;

    function _doMint(uint256 amount) internal {
        vm.deal(ALICE, 100 ether);
        IMintFacet gotchi = IMintFacet(address(diamond));
        uint256 payValue = amount * price;
        gotchi.mint{value: payValue}(amount);
    }

    function _summonGotchipus(uint256 tokenId) internal returns (address tbaAddress) {
        vm.deal(ALICE, 100 ether);
        vm.startPrank(ALICE);
        _doMint(10);

        IMintFacet.SummonArgs memory args = IMintFacet.SummonArgs({
            gotchipusTokenId: tokenId,
            gotchiName: "Gotchi No.1",
            collateralToken: address(0),
            stakeAmount: 0.1 ether,
            utc: 0,
            story: "I'm Gotchi",
            preIndex: 0
        });

        IMintFacet(address(diamond)).summonGotchipus{value: 0.1 ether}(args);
        vm.stopPrank(); 

        tbaAddress = IERC6551Facet(address(diamond)).account(tokenId);
    }

    function setUp() public virtual {
        cutFacet = new DiamondCutFacet();
        loupeFacet = new DiamondLoupeFacet();
        ownershipFacet = new OwnershipFacet();
        initDiamond = new InitDiamond();
        gotchipusFacet = new GotchipusFacet();
        attributesFacet = new AttributesFacet();
        dnaFacet = new DNAFacet();
        hooksFacet = new HooksFacet();
        erc6551Facet = new ERC6551Facet();
        erc6551Account = new ERC6551Account();
        erc6551Registry = new ERC6551Registry();
        gotchiWearableFacet = new GotchiWearableFacet();
        svgFacet = new SvgFacet();
        paymasterFacet = new PaymasterFacet();
        timeFacet = new TimeFacet();
        mintFacet = new MintFacet();
        metadataFacet = new MetadataFacet();
        securityFacet = new SecurityFacet();

        diamond = new Diamond(owner, address(cutFacet), address(loupeFacet), address(ownershipFacet));

        IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](12);
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
        facetCuts[11] = IDiamondCut.FacetCut({
            facetAddress: address(securityFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: FacetSelectors.getSelectors("SecurityFacet")
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

        // wearable
        DiamondCutFacet wearabeDiamondCutFacet = new DiamondCutFacet();
        DiamondLoupeFacet wearableDiamondLoupeFacet = new DiamondLoupeFacet();
        OwnershipFacet wearableOwnershipFacet = new OwnershipFacet();
        WearableFacet wearableFacet = new WearableFacet();

        WearableDiamond wearableDiamond = new WearableDiamond(owner, address(wearabeDiamondCutFacet), address(wearableDiamondLoupeFacet), address(wearableOwnershipFacet));

        bytes4[] memory wearableFacetFunctions = new bytes4[](10);
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

        IDiamondCut.FacetCut[] memory wearableFacetCuts = new IDiamondCut.FacetCut[](1);
        wearableFacetCuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(wearableFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: wearableFacetFunctions
        });

        IDiamondCut(address(wearableDiamond)).diamondCut(wearableFacetCuts, address(0), "");
        GotchiWearableFacet(address(diamond)).setWearableDiamond(address(wearableDiamond));

        WearableInfo[] memory infos = new WearableInfo[](85);
        // Backgrounds (0-15) - sorted alphabetically
        infos[0] = WearableInfo("Beach Lighthouse", "Coastal lighthouses became humanity's last hope.", "Gotchipus Team", BG_BYTES32, 0);
        infos[1] = WearableInfo("Big Ben", "London's iconic clock tower.", "Gotchipus Team", BG_BYTES32, 1);
        infos[2] = WearableInfo("Burj Khalifa", "The pinnacle of modern civilization.", "Gotchipus Team", BG_BYTES32, 2);
        infos[3] = WearableInfo("Christ The Redeemer", "A sacred symbol of guardians, embodying sacrifice and redemption.", "Gotchipus Team", BG_BYTES32, 3);
        infos[4] = WearableInfo("Diamond Head Mountain", "Volcanic power lies within, representing nature's wild force.", "Gotchipus Team", BG_BYTES32, 4);
        infos[5] = WearableInfo("Eiffel Tower", "A glorious symbol of human civilization.", "Gotchipus Team", BG_BYTES32, 5);
        infos[6] = WearableInfo("Grand Palace", "A symbol of sovereignty, a place of supreme glory.", "Gotchipus Team", BG_BYTES32, 6);
        infos[7] = WearableInfo("Green", "The primal color of the deep sea, representing life and hope.", "Gotchipus Team", BG_BYTES32, 7);
        infos[8] = WearableInfo("Hollywood Sign", "A symbol of dreams and glory.", "Gotchipus Team", BG_BYTES32, 8);
        infos[9] = WearableInfo("Oriental Pearl Tower", "The brilliant light of the East, representing civilization reborn.", "Gotchipus Team", BG_BYTES32, 9);
        infos[10] = WearableInfo("Pure Gold", "Eternal value, immortal brilliance.", "Gotchipus Team", BG_BYTES32, 10);
        infos[11] = WearableInfo("Pyramids of Egypt", "Ancient wisdom, eternal mysteries.", "Gotchipus Team", BG_BYTES32, 11);
        infos[12] = WearableInfo("Red", "The warning color of the abyss, also the flame of resistance.", "Gotchipus Team", BG_BYTES32, 12);
        infos[13] = WearableInfo("St. Basil's Cathedral", "The pinnacle of art, a solemn sanctuary of faith.", "Gotchipus Team", BG_BYTES32, 13);
        infos[14] = WearableInfo("Statue of Liberty", "An eternal symbol of freedom and hope.", "Gotchipus Team", BG_BYTES32, 14);
        infos[15] = WearableInfo("Tokyo Tower", "A perfect fusion of modern and traditional.", "Gotchipus Team", BG_BYTES32, 15);
        
        // Bodies (16-23) - sorted alphabetically
        infos[16] = WearableInfo("Aqua Spirit", "Like the purest currents in the deep sea.", "Gotchipus Team", BODY_BYTES32, 16);
        infos[17] = WearableInfo("Blazing Flame", "Flames erupting from the abyss fissure.", "Gotchipus Team", BODY_BYTES32, 17);
        infos[18] = WearableInfo("Candy Pink", "A color symbolizing innocence and hope.", "Gotchipus Team", BODY_BYTES32, 18);
        infos[19] = WearableInfo("Crystal", "A crystalline form from the deep sea, representing purity and resilience.", "Gotchipus Team", BODY_BYTES32, 19);
        infos[20] = WearableInfo("Deep Sea", "The color closest to the abyss, the existence that best understands it.", "Gotchipus Team", BODY_BYTES32, 20);
        infos[21] = WearableInfo("Golden Glow", "The radiance of Pharos lighthouse infused into Gotchipus.", "Gotchipus Team", BODY_BYTES32, 21);
        infos[22] = WearableInfo("Ink Shadow", "Like the darkest existence in the abyss.", "Gotchipus Team", BODY_BYTES32, 22);
        infos[23] = WearableInfo("Orca Wrap", "The mark of the ocean's mightiest predator.", "Gotchipus Team", BODY_BYTES32, 23);
        
        // Eyes (24-31) - sorted alphabetically
        infos[24] = WearableInfo("Bitcoin Eyes", "A symbol of decentralization, the wisdom of blockchain.", "Gotchipus Team", EYE_BYTES32, 24);
        infos[25] = WearableInfo("Curved Smiling Closed Eyes", "Optimistic attitude, the power of a smile.", "Gotchipus Team", EYE_BYTES32, 25);
        infos[26] = WearableInfo("Dogecoin Logo Eyes", "Symbol of community, the power of friendship.", "Gotchipus Team", EYE_BYTES32, 26);
        infos[27] = WearableInfo("Dollar Sign Eyes", "Symbol of wealth, pillar of economy.", "Gotchipus Team", EYE_BYTES32, 27);
        infos[28] = WearableInfo("Normal", "The purest origin, the truest self.", "Gotchipus Team", EYE_BYTES32, 28);
        infos[29] = WearableInfo("Pharos Logo Eyes", "Symbol of the lighthouse, emblem of light.", "Gotchipus Team", EYE_BYTES32, 29);
        infos[30] = WearableInfo("Single Eye", "Ancient wisdom, mysterious insight.", "Gotchipus Team", EYE_BYTES32, 30);
        infos[31] = WearableInfo("Yellow Lightning Eyes", "Thunder's power, swift assault.", "Gotchipus Team", EYE_BYTES32, 31);
        
        // Hands (32-45) - sorted alphabetically
        infos[32] = WearableInfo("Drink Bottle", "Essential for survival, source of life.", "Gotchipus Team", HAND_BYTES32, 32);
        infos[33] = WearableInfo("Fire", "Unquenchable flame of resistance.", "Gotchipus Team", HAND_BYTES32, 33);
        infos[34] = WearableInfo("Gold Coin Pouch", "Symbol of wealth, economic foundation.", "Gotchipus Team", HAND_BYTES32, 34);
        infos[35] = WearableInfo("Ink Bottle", "Secrets of the abyss, vessel of knowledge.", "Gotchipus Team", HAND_BYTES32, 35);
        infos[36] = WearableInfo("Lighthouse Model", "Miniature of Pharos, symbol of hope.", "Gotchipus Team", HAND_BYTES32, 36);
        infos[37] = WearableInfo("Lightning", "Power of thunder, representative of divine wrath.", "Gotchipus Team", HAND_BYTES32, 37);
        infos[38] = WearableInfo("Magic Potion Bottle", "Mysterious elixir, source of miracles.", "Gotchipus Team", HAND_BYTES32, 38);
        infos[39] = WearableInfo("Magic Scroll", "Ancient knowledge, secret wisdom.", "Gotchipus Team", HAND_BYTES32, 39);
        infos[40] = WearableInfo("Magic Wand", "Medium for casting, tool of magic.", "Gotchipus Team", HAND_BYTES32, 40);
        infos[41] = WearableInfo("Miner's Pickaxe", "Tool for extraction, source of resources.", "Gotchipus Team", HAND_BYTES32, 41);
        infos[42] = WearableInfo("Pharos Coin", "Memorial of the lighthouse, token of light.", "Gotchipus Team", HAND_BYTES32, 42);
        infos[43] = WearableInfo("Sea Urchin", "Creature of the deep, source of toxins.", "Gotchipus Team", HAND_BYTES32, 43);
        infos[44] = WearableInfo("Spray Paint Can", "Tool of art, symbol of resistance.", "Gotchipus Team", HAND_BYTES32, 44);
        infos[45] = WearableInfo("Trident", "Weapon of the sea god, symbol of the ocean.", "Gotchipus Team", HAND_BYTES32, 45);
        
        // Heads (46-62) - sorted alphabetically
        infos[46] = WearableInfo("Aviator Hat", "Dream of flight, conquest of the sky.", "Gotchipus Team", HEAD_BYTES32, 46);
        infos[47] = WearableInfo("Captain Hat", "Leader of ships, symbol of commanders.", "Gotchipus Team", HEAD_BYTES32, 47);
        infos[48] = WearableInfo("Cowboy Hat", "Freedom of the wilderness, pioneering spirit.", "Gotchipus Team", HEAD_BYTES32, 48);
        infos[49] = WearableInfo("Crocodile Hat", "Predator's dignity, symbol of danger.", "Gotchipus Team", HEAD_BYTES32, 49);
        infos[50] = WearableInfo("Crown", "Symbol of sovereignty, supreme glory.", "Gotchipus Team", HEAD_BYTES32, 50);
        infos[51] = WearableInfo("Dogecoin Hat", "Spirit of community, symbol of friendliness.", "Gotchipus Team", HEAD_BYTES32, 51);
        infos[52] = WearableInfo("Frog Hat", "Leaping flexibility, adaptability.", "Gotchipus Team", HEAD_BYTES32, 52);
        infos[53] = WearableInfo("Miner Helmet", "Courage to extract, hard work.", "Gotchipus Team", HEAD_BYTES32, 53);
        infos[54] = WearableInfo("Orca Hat (Full)", "Complete symbol of the ocean's overlord, peerless power.", "Gotchipus Team", HEAD_BYTES32, 54);
        infos[55] = WearableInfo("Panda Hat", "Symbol of peace, adorable protector.", "Gotchipus Team", HEAD_BYTES32, 55);
        infos[56] = WearableInfo("Pirate Bandana", "Adventure on the seas, free spirit.", "Gotchipus Team", HEAD_BYTES32, 56);
        infos[57] = WearableInfo("Polar Bear Hat", "Resilience in cold, guardian of the poles.", "Gotchipus Team", HEAD_BYTES32, 57);
        infos[58] = WearableInfo("Sea Lion Hat", "Ocean's agility, art of balance.", "Gotchipus Team", HEAD_BYTES32, 58);
        infos[59] = WearableInfo("Shark Hat", "Ocean's hunter, ruthless killer.", "Gotchipus Team", HEAD_BYTES32, 59);
        infos[60] = WearableInfo("Straw Hat", "Mark of laborers, yearning for pastoral life.", "Gotchipus Team", HEAD_BYTES32, 60);
        infos[61] = WearableInfo("Unicorn Hat", "Symbol of fantasy, existence of magic.", "Gotchipus Team", HEAD_BYTES32, 61);
        infos[62] = WearableInfo("Wizard Hat", "Symbol of magic, ancient wisdom.", "Gotchipus Team", HEAD_BYTES32, 62);
        
        // Clothes (63-71) - sorted alphabetically
        infos[63] = WearableInfo("Camouflage Outfit", "Battlefield camouflage, the art of hunting.", "Gotchipus Team", CLOTHES_BYTES32, 63);
        infos[64] = WearableInfo("Cloak", "Mysterious concealment, hidden power.", "Gotchipus Team", CLOTHES_BYTES32, 64);
        infos[65] = WearableInfo("Explorer Jacket", "The mark of adventurers, the courage of pioneers.", "Gotchipus Team", CLOTHES_BYTES32, 65);
        infos[66] = WearableInfo("Golden Robe", "The sacred robe of Pharos Temple.", "Gotchipus Team", CLOTHES_BYTES32, 66);
        infos[67] = WearableInfo("Knight Armor", "The glory of medieval times, the strongest defense.", "Gotchipus Team", CLOTHES_BYTES32, 67);
        infos[68] = WearableInfo("Miner Outfit", "The courage to venture deep into mines.", "Gotchipus Team", CLOTHES_BYTES32, 68);
        infos[69] = WearableInfo("Royal Cape", "A symbol of sovereignty, supreme glory.", "Gotchipus Team", CLOTHES_BYTES32, 69);
        infos[70] = WearableInfo("Tactical Vest", "Equipment for modern warfare, perfect fusion.", "Gotchipus Team", CLOTHES_BYTES32, 70);
        infos[71] = WearableInfo("Wizard Robe", "A symbol of magic, inheritor of ancient wisdom.", "Gotchipus Team", CLOTHES_BYTES32, 71);
        
        // Faces (72-78) - sorted alphabetically
        infos[72] = WearableInfo("Diving Goggles", "Essential tool for deep sea exploration.", "Gotchipus Team", FACE_BYTES32, 72);
        infos[73] = WearableInfo("Gas Mask", "Defense against pollution and toxins.", "Gotchipus Team", FACE_BYTES32, 73);
        infos[74] = WearableInfo("Iron Man Mask", "Pinnacle of technology, power of machinery.", "Gotchipus Team", FACE_BYTES32, 74);
        infos[75] = WearableInfo("LED GOTCHI", "Emblem of Gotchipus, identity of guardians.", "Gotchipus Team", FACE_BYTES32, 75);
        infos[76] = WearableInfo("LED GMOTCHI", "Glowing wisdom, digital future.", "Gotchipus Team", FACE_BYTES32, 76);
        infos[77] = WearableInfo("LED PHAROS", "Radiance of Pharos, glory of the lighthouse.", "Gotchipus Team", FACE_BYTES32, 77);
        infos[78] = WearableInfo("Tactical Face Mask", "Battlefield protection, professional equipment.", "Gotchipus Team", FACE_BYTES32, 78);
        
        // Mouths (79-84) - sorted alphabetically
        infos[79] = WearableInfo("Biting a Golden Key", "Key to unlocking secrets, tool to reveal truth.", "Gotchipus Team", MOUTH_BYTES32, 79);
        infos[80] = WearableInfo("Eating a Fish", "Food of the ocean, instinct for survival.", "Gotchipus Team", MOUTH_BYTES32, 80);
        infos[81] = WearableInfo("Eating a Starfish", "Creature of the deep, experience of adventure.", "Gotchipus Team", MOUTH_BYTES32, 81);
        infos[82] = WearableInfo("HODL Tape", "Symbol of persistence, power of belief.", "Gotchipus Team", MOUTH_BYTES32, 82);
        infos[83] = WearableInfo("Hidden", "Mysterious concealment, covert existence.", "Gotchipus Team", MOUTH_BYTES32, 83);
        infos[84] = WearableInfo("Smile", "Optimistic attitude, symbol of hope.", "Gotchipus Team", MOUTH_BYTES32, 84);

        address facet = address(diamond);

        uint256 total = 85;
        uint256 batchSize = 15; 

        for (uint256 start = 0; start < total; start += batchSize) {
            uint256 end = start + batchSize;
            if (end > total) end = total;

            uint256 len = end - start;

            string[] memory urisPart = new string[](len);
            WearableInfo[] memory infosPart = new WearableInfo[](len);

            for (uint256 i = 0; i < len; i++) {
                uint256 idx = start + i;
                urisPart[i] = LibStrings.strWithUint("https://app.gotchipus.com/wearable/metadata/", idx);
                infosPart[i] = infos[idx];
            }

            GotchiWearableFacet(facet).createBatchWearable(urisPart, infosPart);
        }
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
