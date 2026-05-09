// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IERC721Receiver } from "../interfaces/IERC721Receiver.sol";
import { LibMeta } from "./LibMeta.sol";
import { LibAppStorage, AppStorage, GotchipusInfo } from "./LibAppStorage.sol";

library LibERC721 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    bytes4 internal constant ERC721_RECEIVED = 0x150b7a02;

    function _exists(uint256 _tokenId) internal view returns (bool) {
        return LibAppStorage.diamondStorage().tokenOwners[_tokenId] != address(0);
    }

    function _isApprovedOrOwner(address _spender, uint256 _tokenId) internal view returns (bool) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        require(_exists(_tokenId), "LibERC721: Token does not exist");
        address owner = s.tokenOwners[_tokenId];
        return (
            _spender == owner ||
            _spender == s.tokenApprovals[_tokenId] ||
            s.operatorApprovals[owner][_spender]
        );
    }

    function _mint(address _to, uint256 _tokenId) internal {
        require(_to != address(0), "LibERC721: mint to zero address");
        require(!_exists(_tokenId), "LibERC721: token already minted");

        AppStorage storage s = LibAppStorage.diamondStorage();

        _addTokenToAllTokensEnumeration(_tokenId);
        _addTokenToOwnerEnumeration(_to, _tokenId);
        
        s.balances[_to] += 1;
        s.tokenOwners[_tokenId] = _to;

        emit Transfer(address(0), _to, _tokenId);
    }

    function _burn(uint256 _tokenId) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        address owner = s.tokenOwners[_tokenId];
        require(_exists(_tokenId), "LibERC721: token doesn't exist");

        _approve(address(0), _tokenId);
        _removeTokenFromOwnerEnumeration(owner, _tokenId);
        _removeTokenFromAllTokensEnumeration(_tokenId);

        s.balances[owner] -= 1;
        delete s.tokenOwners[_tokenId];
        delete s.ownedGotchipusInfos[owner][_tokenId];


        emit Transfer(owner, address(0), _tokenId);

    }

    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        require(s.tokenOwners[_tokenId] == _from, "LibERC721: transfer from incorrect owner");
        require(_to != address(0), "LibERC721: transfer to the zero address");
        require(!s.ownedGotchipusInfos[_from][_tokenId].locked, "LibERC721: token is locked");

        _approve(address(0), _tokenId);

        _removeTokenFromOwnerEnumeration(_from, _tokenId);
        _addTokenToOwnerEnumeration(_to, _tokenId);

        s.balances[_from] -= 1;
        s.balances[_to] += 1;
        s.tokenOwners[_tokenId] = _to;

        GotchipusInfo memory tokenInfo = s.ownedGotchipusInfos[_from][_tokenId];
        s.ownedGotchipusInfos[_to][_tokenId] = tokenInfo;
        delete s.ownedGotchipusInfos[_from][_tokenId];

        emit Transfer(_from, _to, _tokenId);
    }

    function _approve(address _to, uint256 _tokenId) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        s.tokenApprovals[_tokenId] = _to;
        address owner = s.tokenOwners[_tokenId];
        if (owner != address(0)) {
            emit Approval(owner, _to, _tokenId);
        }
    }

    function _checkOnERC721Received(address _from, address _to, uint256 _tokenId, bytes memory _data) internal returns (bool) {
        if (_to.code.length == 0) {
            return true;
        }

        try IERC721Receiver(_to).onERC721Received(LibMeta.msgSender(), _from, _tokenId, _data) returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch (bytes memory reason) {
            if (reason.length == 0) {
                revert("LibERC721: transfer to non-ERC721Receiver");
            } else {
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }
        }
    }

    function _addTokenToOwnerEnumeration(address _to, uint256 _tokenId) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        uint256 length = s.ownerTokens[_to].length;
        s.ownerTokens[_to].push(_tokenId);
        s.ownedTokensIndex[_tokenId] = length;
    }

    function _removeTokenFromOwnerEnumeration(address _from, uint256 _tokenId) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        uint256 lastTokenIndex = s.ownerTokens[_from].length - 1;
        uint256 tokenIndex = s.ownedTokensIndex[_tokenId];

        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = s.ownerTokens[_from][lastTokenIndex];
            s.ownerTokens[_from][tokenIndex] = lastTokenId;
            s.ownedTokensIndex[lastTokenId] = tokenIndex;
        }

        s.ownerTokens[_from].pop();
    }

    function _addTokenToAllTokensEnumeration(uint256 _tokenId) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        s.allTokensIndex[_tokenId] = s.allTokens.length;
        s.allTokens.push(_tokenId);
    }

    function _removeTokenFromAllTokensEnumeration(uint256 _tokenId) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        uint256 lastTokenIndex = s.allTokens.length - 1;
        uint256 tokenIndex = s.allTokensIndex[_tokenId];

        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = s.allTokens[lastTokenIndex];
            s.allTokens[tokenIndex] = lastTokenId;
            s.allTokensIndex[lastTokenId] = tokenIndex;
        }

        s.allTokens.pop();
    }

    function _setTokenURI(uint256 _tokenId, string memory uri) internal {
        require(_exists(_tokenId), "LibERC721Metadata: URI set of nonexistent token");
        LibAppStorage.diamondStorage().tokenURIs[_tokenId] = uri;
    }
}