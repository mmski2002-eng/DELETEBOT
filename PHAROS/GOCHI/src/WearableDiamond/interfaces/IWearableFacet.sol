// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IWearableFacet {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values);
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);
    event URI(string value, uint256 indexed id);

    function balanceOf(address owner, uint256 tokenId) external view returns (uint256 bn);
    function balanceOfBatch(address[] calldata owners, uint256[] calldata tokenIds) external view returns (uint256[] memory bns);
    function uri(uint256 tokenId) external view returns (string memory);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function setApprovalForAll(address operator, bool approved) external;
    function setBaseURI(string memory baseUri) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, uint256 value, bytes calldata data) external;
    function safeBatchTransferFrom(address from, address to, uint256[] calldata tokenIds, uint256[] calldata values, bytes calldata data) external;
}