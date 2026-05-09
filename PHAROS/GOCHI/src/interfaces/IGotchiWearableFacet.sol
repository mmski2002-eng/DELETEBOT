// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { WearableInfo, EquipWearableType } from "../libraries/LibAppStorage.sol";

interface IGotchiWearableFacet {
    event AddWearable(address indexed wearable);
    event WearableURI(uint256 indexed tokenId, string indexed wearableUri);

    function wearableBalanceOf(address owner, uint256 tokenId) external view returns (uint256 bn);
    function wearableBalanceOfBatch(address[] calldata owners, uint256[] calldata tokenIds) external view returns (uint256[] memory);
    function wearableUri(uint256 tokenId) external view returns (string memory);
    function getWearableInfo(uint256 tokenId) external view returns (WearableInfo memory info_);
    function getAllEquipWearableType(uint256 gotchiTokenId) external view returns (EquipWearableType[] memory ew_);
    function setWearableUri(uint256 tokenId, string memory tokenUri) external;
    function setWearableBaseURI(string memory baseUri) external;
    function setWearableApprovalForAll(address owner, address operator, bool approved) external;
    function wearableSafeTransferFrom(
        address operator, 
        address from, 
        address to, 
        uint256 tokenId, 
        uint256 value, 
        bytes calldata data
    ) external;
    function wearableSafeBatchTransferFrom(
        address operator,
        address from, 
        address to, 
        uint256[] calldata tokenIds, 
        uint256[] calldata values, 
        bytes calldata data
    ) external;
    function createWearable(string calldata tokenUri, WearableInfo calldata info) external;
    function createBatchWearable(string[] calldata tokenUris, WearableInfo[] calldata infos) external;
    function setWearableDiamond(address wearable) external;
    function equipWearable(uint256 gotchiTokenId, uint256 wearableTokenId) external;
    function simpleEquipWearable(uint256 gotchiTokenId, uint256 wearableTokenId, bytes32 wearableType) external;
    function claimWearable() external;
}