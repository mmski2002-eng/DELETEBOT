// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { GotchipusFacet } from "../../src/facets/GotchipusFacet.sol";
import { AttributesFacet } from "../../src/facets/AttributesFacet.sol";
import { DNAFacet } from "../../src/facets/DNAFacet.sol";
import { HooksFacet } from "../../src/facets/HooksFacet.sol";
import { ERC6551Facet } from "../../src/facets/ERC6551Facet.sol";
import { GotchiWearableFacet } from "../../src/facets/GotchiWearableFacet.sol";
import { SvgFacet } from "../../src/facets/SvgFacet.sol";
import { PaymasterFacet } from "../../src/facets/PaymasterFacet.sol";
import { TimeFacet } from "../../src/facets/TimeFacet.sol";
import { MintFacet } from "../../src/facets/MintFacet.sol";
import { MetadataFacet } from "../../src/facets/MetadataFacet.sol";
import { SecurityFacet } from "../../src/facets/SecurityFacet.sol";

library FacetSelectors {
    function getSelectors(string memory facetName) internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors;

        if (keccak256(abi.encodePacked(facetName)) == keccak256(abi.encodePacked("GotchipusFacet"))) {
            selectors = new bytes4[](16);
            selectors[0] = GotchipusFacet.balanceOf.selector;
            selectors[1] = GotchipusFacet.ownerOf.selector;
            selectors[2] = GotchipusFacet.totalSupply.selector;
            selectors[3] = GotchipusFacet.tokenByIndex.selector;
            selectors[4] = GotchipusFacet.tokenOfOwnerByIndex.selector;
            selectors[5] = GotchipusFacet.allTokensOfOwner.selector;
            selectors[6] = GotchipusFacet.name.selector;
            selectors[7] = GotchipusFacet.symbol.selector;
            selectors[8] = GotchipusFacet.getApproved.selector;
            selectors[9] = GotchipusFacet.isApprovedForAll.selector;
            selectors[10] = bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"));
            selectors[11] = bytes4(keccak256("safeTransferFrom(address,address,uint256)"));
            selectors[12] = GotchipusFacet.transferFrom.selector;
            selectors[13] = GotchipusFacet.approve.selector;
            selectors[14] = GotchipusFacet.setApprovalForAll.selector;
            selectors[15] = GotchipusFacet.burn.selector;
        } else if (keccak256(abi.encodePacked(facetName)) == keccak256(abi.encodePacked("MintFacet"))) {
            selectors = new bytes4[](6);
            selectors[0] = MintFacet.mint.selector;
            selectors[1] = MintFacet.summonGotchipus.selector;
            selectors[2] = MintFacet.withdrawETH.selector;
            selectors[3] = MintFacet.addWhitelist.selector;
            selectors[4] = MintFacet.paused.selector;
            selectors[5] = MintFacet.setSalt.selector;
        } else if (keccak256(abi.encodePacked(facetName)) == keccak256(abi.encodePacked("MetadataFacet"))) {
            selectors = new bytes4[](5);
            selectors[0] = MetadataFacet.tokenURI.selector;
            selectors[1] = MetadataFacet.setBaseURI.selector;
            selectors[2] = MetadataFacet.ownedTokenInfo.selector;
            selectors[3] = MetadataFacet.getGotchiTraitsIndex.selector;
            selectors[4] = MetadataFacet.getGotchiOrPharosInfo.selector;
        } else if (keccak256(abi.encodePacked(facetName)) == keccak256(abi.encodePacked("AttributesFacet"))) {
            selectors = new bytes4[](6);
            selectors[0] = AttributesFacet.pet.selector;
            selectors[1] = AttributesFacet.setName.selector;
            selectors[2] = AttributesFacet.getLastPetTime.selector;
            selectors[3] = AttributesFacet.getTokenName.selector;
            selectors[4] = AttributesFacet.getAttributes.selector;
            selectors[5] = AttributesFacet.getSoul.selector;
        } else if (keccak256(abi.encodePacked(facetName)) == keccak256(abi.encodePacked("DNAFacet"))) {
            selectors = new bytes4[](4);
            selectors[0] = DNAFacet.getGene.selector;
            selectors[1] = DNAFacet.ruleVersion.selector;
            selectors[2] = DNAFacet.setRuleVersion.selector;
            selectors[3] = DNAFacet.tokenGeneSeed.selector;
        } else if (keccak256(abi.encodePacked(facetName)) == keccak256(abi.encodePacked("HooksFacet"))) {
            selectors = new bytes4[](9);
            selectors[0] = HooksFacet.addHook.selector;
            selectors[1] = HooksFacet.addHookToEvents.selector;
            selectors[2] = HooksFacet.removeHook.selector;
            selectors[3] = HooksFacet.removeHookCompletely.selector;
            selectors[4] = HooksFacet.setHookApproval.selector;
            selectors[5] = HooksFacet.getHooks.selector;
            selectors[6] = HooksFacet.getActiveHooks.selector;
            selectors[7] = HooksFacet.isHookValid.selector;
            selectors[8] = HooksFacet.getHookCount.selector;
        } else if (keccak256(abi.encodePacked(facetName)) == keccak256(abi.encodePacked("ERC6551Facet"))) {
            selectors = new bytes4[](2);
            selectors[0] = ERC6551Facet.account.selector;
            selectors[1] = ERC6551Facet.executeAccount.selector;
        } else if (keccak256(abi.encodePacked(facetName)) == keccak256(abi.encodePacked("GotchiWearableFacet"))) {
            selectors = new bytes4[](31);
            selectors[0] = GotchiWearableFacet.wearableBalanceOf.selector;
            selectors[1] = GotchiWearableFacet.wearableBalanceOfBatch.selector;
            selectors[2] = GotchiWearableFacet.wearableUri.selector;
            selectors[3] = GotchiWearableFacet.getWearableInfo.selector;
            selectors[4] = GotchiWearableFacet.getAllEquipWearableType.selector;
            selectors[5] = GotchiWearableFacet.getWearableDiamond.selector;
            selectors[6] = GotchiWearableFacet.setWearableUri.selector;
            selectors[7] = GotchiWearableFacet.setWearableBaseURI.selector;
            selectors[8] = GotchiWearableFacet.setWearableApprovalForAll.selector;
            selectors[9] = GotchiWearableFacet.wearableSafeTransferFrom.selector;
            selectors[10] = GotchiWearableFacet.wearableSafeBatchTransferFrom.selector;
            selectors[11] = GotchiWearableFacet.createWearable.selector;
            selectors[12] = GotchiWearableFacet.createBatchWearable.selector;
            selectors[13] = GotchiWearableFacet.setWearableDiamond.selector;
            selectors[14] = GotchiWearableFacet.equipWearable.selector;
            selectors[15] = GotchiWearableFacet.batchEquipWearable.selector;
            selectors[16] = GotchiWearableFacet.unequipWearable.selector;
            selectors[17] = GotchiWearableFacet.batchUnequipWearable.selector;
            selectors[18] = GotchiWearableFacet.mintWearable.selector;
            selectors[19] = GotchiWearableFacet.claimWearable.selector;
            selectors[20] = GotchiWearableFacet.updateWearable.selector;
            selectors[21] = GotchiWearableFacet.updateBatchWearable.selector;
            selectors[22] = GotchiWearableFacet.getCountWearablesByType.selector;
            selectors[23] = GotchiWearableFacet.setCountWearablesByType.selector;
            selectors[24] = GotchiWearableFacet.getNextTokenId.selector;
            selectors[25] = GotchiWearableFacet.setNextTokenId.selector;
            selectors[26] = GotchiWearableFacet.getIdByWearableType.selector;
            selectors[27] = GotchiWearableFacet.getRandomTraitsIndex.selector;
            selectors[28] = GotchiWearableFacet.batchMintWearable.selector;
            selectors[29] = GotchiWearableFacet.deleteWearable.selector;
            selectors[30] = GotchiWearableFacet.deleteBatchWearable.selector;
        } else if (keccak256(abi.encodePacked(facetName)) == keccak256(abi.encodePacked("SvgFacet"))) {
            selectors = new bytes4[](6);
            selectors[0] = SvgFacet.getGotchipusSvg.selector;
            selectors[1] = SvgFacet.getSvg.selector;
            selectors[2] = SvgFacet.getSliceSvgs.selector;
            selectors[3] = SvgFacet.getSliceSvg.selector;
            selectors[4] = SvgFacet.storeSvg.selector;
            selectors[5] = SvgFacet.updateSvg.selector;
        } else if (keccak256(abi.encodePacked(facetName)) == keccak256(abi.encodePacked("PaymasterFacet"))) {
            selectors = new bytes4[](5);
            selectors[0] = PaymasterFacet.getNonce.selector;
            selectors[1] = PaymasterFacet.isExecutedTx.selector;
            selectors[2] = PaymasterFacet.isPaymaster.selector;
            selectors[3] = PaymasterFacet.addPaymaster.selector;
            selectors[4] = PaymasterFacet.execute.selector;
        } else if (keccak256(abi.encodePacked(facetName)) == keccak256(abi.encodePacked("TimeFacet"))) {
            selectors = new bytes4[](2);
            selectors[0] = TimeFacet.getWeather.selector;
            selectors[1] = TimeFacet.updateWeather.selector;
        } else if (keccak256(abi.encodePacked(facetName)) == keccak256(abi.encodePacked("SecurityFacet"))) {
            selectors = new bytes4[](19);
            selectors[0] = SecurityFacet.buildOptions.selector;
            selectors[1] = SecurityFacet.isEnabled.selector;
            selectors[2] = SecurityFacet.getSession.selector;
            selectors[3] = SecurityFacet.getEnabledOptions.selector;
            selectors[4] = SecurityFacet.getTransferLimit.selector;
            selectors[5] = SecurityFacet.getWhitelistMode.selector;
            selectors[6] = SecurityFacet.isTargetWhitelist.selector;
            selectors[7] = SecurityFacet.isTargetBlacklist.selector;
            selectors[8] = SecurityFacet.allTargetWhitelists.selector;
            selectors[9] = SecurityFacet.allTargetBlacklists.selector;
            selectors[10] = SecurityFacet.setOption.selector;
            selectors[11] = SecurityFacet.setPolicy.selector;
            selectors[12] = SecurityFacet.createSession.selector;
            selectors[13] = SecurityFacet.revokeSession.selector;
            selectors[14] = SecurityFacet.addTargetWhitelist.selector;
            selectors[15] = SecurityFacet.removeTargetWhitelist.selector;
            selectors[16] = SecurityFacet.addTargetBlacklist.selector;
            selectors[17] = SecurityFacet.removeTargetBlacklist.selector;
            selectors[18] = SecurityFacet.setTransferLimit.selector;
        }

        return selectors;
    }
}