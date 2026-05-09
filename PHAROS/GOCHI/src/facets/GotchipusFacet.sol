// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AppStorage, Modifier, GotchipusInfo, MAX_TRAITS_NUM } from "../libraries/LibAppStorage.sol";
import { IERC721Enumerable } from "../interfaces/IERC721Enumerable.sol";
import { IERC721 } from "../interfaces/IERC721.sol";
import { LibMeta } from "../libraries/LibMeta.sol";
import { LibERC721 } from "../libraries/LibERC721.sol";

contract GotchipusFacet is Modifier {

    function balanceOf(address _owner) external view returns (uint256) {
        require(_owner != address(0), "GotchipusFacet: owner is zero address");
        return s.balances[_owner];
    }

    function ownerOf(uint256 _tokenId) external view returns (address owner) {
        owner = s.tokenOwners[_tokenId];
        require(owner != address(0), "GotchipusFacet: owner is zero address");
    }

    function totalSupply() external view returns (uint256) {
        return s.allTokens.length;
    }

    function tokenByIndex(uint256 _index) external view returns (uint256) {
        require(_index < s.allTokens.length, "GotchipusFacet: ERC721 out of bounds index");
        return s.allTokens[_index];
    }

    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256) {
        require(_index < s.balances[_owner], "GotchipusFacet: ERC721 out of bounds index");
        return s.ownerTokens[_owner][_index];
    }

    function allTokensOfOwner(address _owner) external view returns (uint256[] memory) {
        return s.ownerTokens[_owner];
    }

    function name() external view returns (string memory) {
        return s.name;
    }

    function symbol() external view returns (string memory) {
        return s.symbol;
    }

    function getApproved(uint256 _tokenId) external view returns (address) {
        require(_tokenId < s.allTokens.length, "ERC721: tokenId is invalid");
        return s.tokenApprovals[_tokenId];
    }

    function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
        return s.operatorApprovals[_owner][_operator];
    }
    
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IERC721Enumerable).interfaceId ||
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == 0x01ffc9a7; // ERC165
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes calldata _data) external {
        require(LibERC721._isApprovedOrOwner(LibMeta.msgSender(), _tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(_from, _to, _tokenId, _data);
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external {
        require(LibERC721._isApprovedOrOwner(LibMeta.msgSender(), _tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(_from, _to, _tokenId, "");
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) external {
        require(LibERC721._isApprovedOrOwner(LibMeta.msgSender(), _tokenId), "ERC721: transfer caller is not owner nor approved");
        LibERC721._transfer(_from, _to, _tokenId);
    }

    function approve(address _to, uint256 _tokenId) external {
        address owner = s.tokenOwners[_tokenId];
        require(owner != address(0), "ERC721: owner query for nonexistent token");
        require(_to != owner, "ERC721: approval to current owner");
        require(
            LibMeta.msgSender() == owner || s.operatorApprovals[owner][LibMeta.msgSender()],
            "ERC721: approve caller is not owner nor approved for all"
        );
        LibERC721._approve(_to, _tokenId);
    }

    function setApprovalForAll(address _operator, bool _approved) external {
        require(_operator != LibMeta.msgSender(), "ERC721: approve to caller");
        s.operatorApprovals[LibMeta.msgSender()][_operator] = _approved;
        emit LibERC721.ApprovalForAll(LibMeta.msgSender(), _operator, _approved);
    } 

    function burn(uint256 tokenId) external {
        require(LibERC721._isApprovedOrOwner(LibMeta.msgSender(), tokenId), 
                "ERC721: caller is not owner nor approved");
        LibERC721._burn(tokenId);
    }

    function _safeTransfer(address _from, address _to, uint256 _tokenId, bytes memory _data) internal {
        LibERC721._transfer(_from, _to, _tokenId);
        require(LibERC721._checkOnERC721Received(_from, _to, _tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }
}