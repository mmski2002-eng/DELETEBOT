// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Modifier, GotchipusInfo } from "../libraries/LibAppStorage.sol";
import { LibSecurity, SecurityOption, Session, TransferLimitConfig } from "../libraries/LibSecurity.sol";

contract SecurityFacet is Modifier {
    function buildOptions(
        bool blockInfiniteApproval,
        bool dailyTransferLimit,
        bool singleTxLimit,
        bool restrictTarget
    ) external pure returns (uint256) {
        return LibSecurity.buildOptions(blockInfiniteApproval, dailyTransferLimit, singleTxLimit, restrictTarget);
    }

    function isEnabled(uint256 tokenId, SecurityOption option) external view returns (bool) {
        return LibSecurity.isEnabled(tokenId, option);
    }

    function getSession(uint256 tokenId, address holder) external view returns (Session memory ses) {
        ses = s.sessions[tokenId][holder];
    }

    function getEnabledOptions(uint256 tokenId) external view returns (uint256) {
        return s.gotchiPolicy[tokenId].enabledOptions;
    }

    function getTransferLimit(uint256 tokenId) external view returns (TransferLimitConfig memory limit) {
        limit = s.gotchiPolicy[tokenId].transferLimit;
    }

    function getWhitelistMode(uint256 tokenId) external view returns (bool) {
        return s.gotchiPolicy[tokenId].whitelistMode;
    }

    function isTargetWhitelist(uint256 tokenId, address target) external view returns (bool) {
        return s.gotchiPolicy[tokenId].isWhitelist[target];
    }

    function isTargetBlacklist(uint256 tokenId, address target) external view returns (bool) {
        return s.gotchiPolicy[tokenId].isBlacklist[target];
    }

    function allTargetWhitelists(uint256 tokenId) external view returns (address[] memory tw) {
        tw = s.gotchiPolicy[tokenId].targetWhitelists;
    }

    function allTargetBlacklists(uint256 tokenId) external view returns (address[] memory tb) {
        tb = s.gotchiPolicy[tokenId].targetBlacklists;
    }

    function setOption(uint256 tokenId, SecurityOption option, bool on) external onlyGotchipusOwner(tokenId) {
        LibSecurity.setOption(tokenId, option, on);
    }

    function setPolicy(uint256 tokenId, uint256 newEnabledOptions) external onlyGotchipusOwner(tokenId) {
        LibSecurity.setPolicy(tokenId, newEnabledOptions);
    }

    function setTransferLimit(uint256 tokenId, uint256 dailyLimit, uint256 singleTxLimit) external onlyGotchipusOwner(tokenId) {
        LibSecurity.setTransferLimit(tokenId, dailyLimit, singleTxLimit);
    }

    function createSession(
        uint256 tokenId,
        address holder,
        uint32 duration,
        uint256 maxPerTx,
        uint256 maxPerSession,
        uint256 dailyLimit,
        uint256 singleTxLimit,
        uint256 enabledOptions,
        bool    whitelistMode,
        address[] calldata whitelist,
        address[] calldata blacklist
    ) external onlyGotchipusOwner(tokenId) {
        LibSecurity.createSession(
            tokenId, holder, duration, maxPerTx, maxPerSession,
            dailyLimit, singleTxLimit, enabledOptions, whitelistMode,
            whitelist, blacklist
        );
    }

    function revokeSession(uint256 tokenId, address holder) external onlyGotchipusOwner(tokenId) {
        LibSecurity.revokeSession(tokenId, holder);
    }

    function addTargetWhitelist(uint256 tokenId, address target) external onlyGotchipusOwner(tokenId) {
        LibSecurity.addTargetWhitelist(tokenId, target);
    }

    function removeTargetWhitelist(uint256 tokenId, address target) external onlyGotchipusOwner(tokenId) {
        LibSecurity.removeTargetWhitelist(tokenId, target);
    }

    function addTargetBlacklist(uint256 tokenId, address target) external onlyGotchipusOwner(tokenId) {
        LibSecurity.addTargetBlacklist(tokenId, target);
    }

    function removeTargetBlacklist(uint256 tokenId, address target) external onlyGotchipusOwner(tokenId) {
        LibSecurity.removeTargetBlacklist(tokenId, target);
    }
}