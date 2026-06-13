// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AppStorage, Modifier, GotchipusInfo, MAX_TRAITS_NUM } from "../libraries/LibAppStorage.sol";
import { LibStrings } from "../libraries/LibStrings.sol";

contract MetadataFacet is Modifier {
    function tokenURI(uint256 _tokenId) external view returns (string memory) {
        GotchipusInfo storage _ownedPus = s.ownedGotchipusInfos[s.tokenOwners[_tokenId]][_tokenId];
        if (_ownedPus.status == 0) {
            return LibStrings.strWithUint(string.concat(s.baseUri, "pharos/"), _tokenId);
        }
        return LibStrings.strWithUint(string.concat(s.baseUri, "gotchipus/"), _tokenId);
    }

    function ownedTokenInfo(address _owner, uint256 _tokenId) external view returns (GotchipusInfo memory info_) {
        info_ = s.ownedGotchipusInfos[_owner][_tokenId];
    }

    function getGotchiTraitsIndex(uint256 tokenId) external view returns (uint8[MAX_TRAITS_NUM] memory indexs) {
        indexs = s.allGotchiTraitsIndex[tokenId];
    }

    function getGotchiOrPharosInfo(address owner, uint8 status) external view returns (uint256[] memory tokenIds) {
        uint256[] storage allIds = s.ownerTokens[owner];
        uint256 count;

        unchecked {
            for (uint256 i = 0; i < allIds.length; i++) {
                if (s.ownedGotchipusInfos[owner][allIds[i]].status == status) {
                    count++;
                }
            }
        }

        tokenIds = new uint256[](count);
        uint256 j;

        unchecked {
            for (uint256 i = 0; i < allIds.length; i++) {
                uint256 id = allIds[i];
                if (s.ownedGotchipusInfos[owner][id].status == status) {
                    tokenIds[j++] = id;
                }
            }
        }
    }

    function setBaseURI(string memory _baseURI) external onlyOwner {
        s.baseUri = _baseURI;
    }
}