// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AppStorage, Modifier, GotchipusInfo, EquipWearableType, MAX_BODY_NUM } from "../libraries/LibAppStorage.sol";
import { LibERC721 } from "../libraries/LibERC721.sol";
import { LibGotchiConstants } from "../libraries/LibGotchiConstants.sol";
import { LibTransferHelper } from "../libraries/LibTransferHelper.sol";
import { LibDna } from "../libraries/LibDna.sol";
import { LibSvg } from "../libraries/LibSvg.sol";
import { LibAttributes } from "../libraries/LibAttributes.sol";
import { LibFaction } from "../libraries/LibFaction.sol";
import { LibStrings } from "../libraries/LibStrings.sol";
import { LibGotchiRarity } from "../libraries/LibGotchiRarity.sol";
import { IERC6551Registry } from "../interfaces/IERC6551Registry.sol";
import { IWearableFacet } from "../WearableDiamond/interfaces/IWearableFacet.sol";

contract MintFacet is Modifier {
    event Summon(uint256 indexed tokenId);
    event WhitelistUpdated(address indexed account, bool indexed isWhitelisted);

    struct SummonArgs {
        uint256 gotchipusTokenId;
        string gotchiName;
        address collateralToken;
        uint256 stakeAmount;
        uint8 utc;
        bytes story;
        uint256 preIndex;
    }

    function mint(uint256 amount) external payable pharosMintIsPaused {
        require(amount != 0 && amount <= LibGotchiConstants.MAX_PER_MINT, "Invalid amount");
        bool isWhitelist = s.isWhitelist[msg.sender];

        if (isWhitelist) {
            uint256 tokenId = s.nextTokenId;
            require(tokenId + 1 <= LibGotchiConstants.MAX_TOTAL_SUPPLY, "MAX TOTAL SUPPLY");
            s.nextTokenId++;

            LibERC721._mint(msg.sender, tokenId);
        } else {
            require(msg.value >= amount * LibGotchiConstants.PHAROS_PRICE, "Invalid value");
            require(s.allTokens.length + amount <= LibGotchiConstants.MAX_TOTAL_SUPPLY, "MAX TOTAL SUPPLY");

            for (uint256 i = 0; i < amount; i++) {
                uint256 tokenId = s.nextTokenId++;
                LibERC721._mint(msg.sender, tokenId);
            }
        }
    }

    function summonGotchipus(SummonArgs calldata _args) external payable onlyGotchipusOwner(_args.gotchipusTokenId) {
        require(s.accountOwnedByTokenId[_args.gotchipusTokenId] == address(0), "GotchipusFacet: already summon");
        
        bytes32 salt = keccak256(abi.encode(block.chainid, _args.gotchipusTokenId, address(this)));
        address account = IERC6551Registry(s.erc6551Registry).createAccount(
            s.erc6551Implementation,
            salt,
            block.chainid,
            address(this),
            _args.gotchipusTokenId
        );

        if (_args.collateralToken == address(0)) {
            LibTransferHelper.safeTransferETH(account, _args.stakeAmount);
        } else {
            LibTransferHelper.safeTransferFrom(_args.collateralToken, msg.sender, account, _args.stakeAmount);
        }

        uint256 randomDna = LibDna.getRandomGene(salt);
        GotchipusInfo storage _ownedPus = s.ownedGotchipusInfos[msg.sender][_args.gotchipusTokenId];
        _ownedPus.dna.geneSeed = randomDna;
        _ownedPus.dna.ruleVersion = s.dnaRuleVersion;
        _ownedPus.dna.generation = 0;
        _ownedPus.name = _args.gotchiName;
        _ownedPus.uri = LibStrings.strWithUint(string.concat(s.baseUri, "gotchipus/"), _args.gotchipusTokenId);
        _ownedPus.story = _args.story;
        _ownedPus.collateral = _args.collateralToken;
        _ownedPus.birthTime = uint32(block.timestamp);
        _ownedPus.timezone = _args.utc;
        
        uint256 randomSeed = LibGotchiRarity.getRandomSeed(msg.sender, randomDna);
        uint8 rarity = LibGotchiRarity.calculateRarity(msg.sender, randomSeed, _args.collateralToken, _args.stakeAmount);
        _ownedPus.dna.rarity = rarity;

        uint256 pityCount = s.summonPityCount[msg.sender];
        bool isPityTriggered = pityCount >= 15 && rarity > 0;

        if (rarity == 0) {
            s.summonPityCount[msg.sender] = pityCount + 1;
        } else if (isPityTriggered) {
            s.summonPityCount[msg.sender] = pityCount + 1;
        } else {
            s.summonPityCount[msg.sender] = 0;
        }
        
        LibAttributes.initializeAttribute(msg.sender, _args.gotchipusTokenId, rarity, _args.collateralToken, _args.stakeAmount);
        LibFaction.initializeFaction(msg.sender, _args.gotchipusTokenId, randomSeed, rarity);

        _ownedPus.singer = msg.sender;
        _ownedPus.status = 1;
        
        s.accountOwnedByTokenId[_args.gotchipusTokenId] = account;
                
        uint256 packed = LibDna.computePacked(_args.gotchipusTokenId);
        LibDna.setPacked(_args.gotchipusTokenId, packed);

        randomTraitsIndex(_args.gotchipusTokenId, account, _args.preIndex);

        emit Summon(_args.gotchipusTokenId);
    }

    function addWhitelist(address[] calldata _whitelists, bool[] calldata _isWhitelists) external onlyOwner {
        for (uint256 i = 0; i < _whitelists.length; i++) {
            s.isWhitelist[_whitelists[i]] = _isWhitelists[i];
            emit WhitelistUpdated(_whitelists[i], _isWhitelists[i]);
        }
    }

    function paused(bool _paused) external onlyOwner {
        s.isPaused = _paused;
    }

    function setSalt(uint256 newSalt) external onlyOwner {
        s.globalSalt = newSalt;
    }
    
    function withdrawETH() external onlyOwner {
        LibTransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }

    function randomTraitsIndex(uint256 tokenId, address account, uint256 preIndex) private {
        bytes32 seed = keccak256(abi.encodePacked(
            tokenId,
            account,
            msg.sender,
            s.globalSalt,
            preIndex
        ));

        for (uint256 i = 0; i < MAX_BODY_NUM; i++) {
            bytes32 svgType;
            if (i == 0) {
                svgType = LibSvg.SVG_TYPE_BG;
            } else if (i == 1) {
                svgType = LibSvg.SVG_TYPE_BODY;
            } else if (i == 2) {
                svgType = LibSvg.SVG_TYPE_EYE;
            }

            uint256 wtIndex = LibSvg.getWearableTypeIndex(svgType);

            uint8 count = s.countWearablesByType[svgType];
            seed = keccak256(abi.encodePacked(seed, i));
            uint8 index = uint8(uint256(seed) % uint256(count));
            uint256 wearabelId = s.idByWearableType[svgType][index];

            s.gotchiTraitsIndex[tokenId][uint8(wtIndex)] = index;
            s.allGotchiTraitsIndex[tokenId][wtIndex] = index;
            s.allOwnerEquipWearableType[account][wtIndex] = EquipWearableType({
                wearableType: svgType,
                wearableId: wearabelId,
                equiped: true
            });

            s.isOwnerEquipWearable[account][svgType] = true;
            s.ownerWearableBalances[account][wearabelId] += 1;
            emit IWearableFacet.TransferSingle(account, address(0), account, wearabelId, 1);
        }
    }
}