// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { GotchipusInfo, MAX_TRAITS_NUM } from "../libraries/LibAppStorage.sol";

interface IMetadataFacet {
    function tokenURI(uint256 _tokenId) external view returns (string memory);

    function ownedTokenInfo(address _owner, uint256 _tokenId) external view returns (GotchipusInfo memory info_);

    function getGotchiTraitsIndex(uint256 tokenId) external view returns (uint8[MAX_TRAITS_NUM] memory indexs);

    function getGotchiOrPharosInfo(address owner, uint8 status) external view returns (uint256[] memory tokenIds);

    function setBaseURI(string memory _baseURI) external;
}