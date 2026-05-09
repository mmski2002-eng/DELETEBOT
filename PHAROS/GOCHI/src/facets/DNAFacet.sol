// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Modifier, DNAData } from "../libraries/LibAppStorage.sol";
import { LibDna } from "../libraries/LibDna.sol";

contract DNAFacet is Modifier {
    function setRuleVersion(uint8 _ruleVersion) external onlyOwner {
        s.dnaRuleVersion = _ruleVersion;
        emit LibDna.SetRuleVersion(_ruleVersion);
    }

    function ruleVersion() external view returns (uint8) {
        return s.dnaRuleVersion;
    }

    function tokenGeneSeed(uint256 gotchipusTokenId) external view returns (DNAData memory dna) {
        dna = s.ownedGotchipusInfos[s.tokenOwners[gotchipusTokenId]][gotchipusTokenId].dna;
    }

    function getGene(uint256 gotchipusTokenId, uint256 index) external view returns (uint256) {
        return LibDna.getGene(gotchipusTokenId, index);
    }
}   