// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AppStorage, LibAppStorage, AccountSecurityPolicy } from "./LibAppStorage.sol";

struct TransferLimitConfig {
    uint256 dailyLimit;     // 0 = unlimited
    uint256 singleTxLimit;  // 0 = unlimited
    uint256 usedToday;
    uint32 lastResetTime;
}

struct Session {
    uint32 expiresAt;          // 0 Uninitialized
    uint256 maxValuePerTx;      // 0 = unlimited
    uint256 maxValuePerSession; // 0 = unlimited
    uint256 usedValue;
    bool active;
}

enum SecurityOption {
    BlockInfiniteApproval,
    DailyTransferLimit,
    SingleTxLimit,
    RestrictTarget
}

library LibSecurity {
    event SecurityOptionToggled(address indexed account, SecurityOption option, bool enabled);
    event SecurityPolicyUpdated(address indexed account, uint256 newOptions);
    event SessionCreated(uint256 indexed tokenId, address indexed holder, uint32 expiresAt);
    event SessionRevoked(uint256 indexed tokenId, address indexed holder);
    event AddWhitelist(uint256 indexed tokenId, address indexed target);
    event RemoveWhitelist(uint256 indexed tokenId, address indexed target);
    event AddBlacklist(uint256 indexed tokenId, address indexed target);
    event RemoveBlacklist(uint256 indexed tokenId, address indexed target);
    event AddTransferLimit(uint256 indexed tokenId, uint256 indexed dailyLimit, uint256 indexed singleTxLimit);

    error InfiniteApprovalBlocked();
    error DailyLimitExceeded(uint256 remaining, uint256 requested);
    error SingleTxLimitExceeded(uint256 limit, uint256 requested);
    error TargetNotAllowed(address target);
    error SessionValueExceeded(uint256 remaining, uint256 requested);
    error SessionExpired(address holder, uint32 expiredAt);
    error SessionNotActive(address holder);

    function isEnabled(uint256 tokenId, SecurityOption option) internal view returns (bool) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        return s.gotchiPolicy[tokenId].enabledOptions & (1 << uint256(option)) != 0;
    }

    function setOption(uint256 tokenId, SecurityOption option, bool on) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();

        if (on) {
            s.gotchiPolicy[tokenId].enabledOptions |= (1 << uint256(option));
        } else {
            s.gotchiPolicy[tokenId].enabledOptions &= ~(1 << uint256(option));
        }

        emit SecurityOptionToggled(msg.sender, option, on);
    }

    function setPolicy(uint256 tokenId, uint256 newEnabledOptions) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        s.gotchiPolicy[tokenId].enabledOptions = newEnabledOptions;

        emit SecurityPolicyUpdated(msg.sender, newEnabledOptions);
    }

    function setTransferLimit(uint256 tokenId, uint256 _dailyLimit, uint256 _singleTxLimit) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        s.gotchiPolicy[tokenId].transferLimit.dailyLimit = _dailyLimit;
        s.gotchiPolicy[tokenId].transferLimit.singleTxLimit = _singleTxLimit;

        emit AddTransferLimit(tokenId, _dailyLimit, _singleTxLimit);
    }

    function buildOptions(
        bool blockInfiniteApproval,
        bool dailyTransferLimit,
        bool singleTxLimit,
        bool restrictTarget
    ) internal pure returns (uint256 options) {
        if (blockInfiniteApproval) options |= (1 << uint256(SecurityOption.BlockInfiniteApproval));
        if (dailyTransferLimit) options |= (1 << uint256(SecurityOption.DailyTransferLimit));
        if (singleTxLimit) options |= (1 << uint256(SecurityOption.SingleTxLimit));
        if (restrictTarget) options |= (1 << uint256(SecurityOption.RestrictTarget));
    }
    
    error WhitelistBlacklistConflict();
    error ListModeMismatch();
    error ListTooLong(uint256 length, uint256 max);

    uint256 internal constant MAX_LIST_LENGTH = 50;

    function createSession(
        uint256 tokenId,
        address holder,
        uint32  duration,
        uint256 maxPerTx,
        uint256 maxPerSession,
        uint256 dailyLimit,
        uint256 singleTxLimit,
        uint256 enabledOptions,
        bool    whitelistMode,
        address[] calldata whitelist,
        address[] calldata blacklist
    ) internal {
        require(holder != address(0), "LibSecurity: zero address");
        require(duration > 0, "LibSecurity: zero duration");
        if (whitelist.length > 0 && blacklist.length > 0) revert WhitelistBlacklistConflict();
        if (whitelistMode && blacklist.length > 0) revert ListModeMismatch();
        if (!whitelistMode && whitelist.length > 0) revert ListModeMismatch();
        if (whitelist.length > MAX_LIST_LENGTH) revert ListTooLong(whitelist.length, MAX_LIST_LENGTH);
        if (blacklist.length > MAX_LIST_LENGTH) revert ListTooLong(blacklist.length, MAX_LIST_LENGTH);

        AppStorage storage s = LibAppStorage.diamondStorage();

        uint32 expiresAt = uint32(block.timestamp) + duration;

        s.sessions[tokenId][holder] = Session({
            expiresAt: expiresAt,
            maxValuePerTx: maxPerTx,
            maxValuePerSession: maxPerSession,
            usedValue: 0,
            active: true
        });

        if (dailyLimit != 0 || singleTxLimit != 0) {
            s.gotchiPolicy[tokenId].transferLimit.dailyLimit = dailyLimit;
            s.gotchiPolicy[tokenId].transferLimit.singleTxLimit = singleTxLimit;
            emit AddTransferLimit(tokenId, dailyLimit, singleTxLimit);
        }

        if (enabledOptions != 0) {
            s.gotchiPolicy[tokenId].enabledOptions = enabledOptions;
            emit SecurityPolicyUpdated(msg.sender, enabledOptions);
        }

        if (whitelist.length > 0 || blacklist.length > 0) {
            s.gotchiPolicy[tokenId].whitelistMode = whitelistMode;
        }

        for (uint256 i; i < whitelist.length; ++i) {
            _addWhitelistUnchecked(tokenId, whitelist[i]);
        }

        for (uint256 i; i < blacklist.length; ++i) {
            _addBlacklistUnchecked(tokenId, blacklist[i]);
        }

        emit SessionCreated(tokenId, holder, expiresAt);
    }

    function revokeSession(uint256 tokenId, address holder) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        s.sessions[tokenId][holder].active = false;

        emit SessionRevoked(tokenId, holder);
    }

    function checkAndConsumeSession(
        uint256 tokenId,
        address caller,
        uint256 value
    ) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        Session memory ses = s.sessions[tokenId][caller];

        if (!ses.active)
            revert SessionNotActive(caller);

        if (uint32(block.timestamp) >= ses.expiresAt)
            revert SessionExpired(caller, ses.expiresAt);

        if (value == 0) return;

        if (ses.maxValuePerTx != 0 && value > ses.maxValuePerTx)
            revert SingleTxLimitExceeded(ses.maxValuePerTx, value);

        if (ses.maxValuePerSession != 0) {
            uint256 remaining = ses.maxValuePerSession > ses.usedValue
                ? ses.maxValuePerSession - ses.usedValue
                : 0;
            if (value > remaining)
                revert SessionValueExceeded(remaining, value);
        }

        s.sessions[tokenId][caller].usedValue += value;
    }

    function validateExecution(
        uint256 tokenId,
        address caller,
        address to,
        uint256 value,
        bytes calldata data
    ) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();

        checkAndConsumeSession(tokenId, caller, value);

        if (isEnabled(tokenId, SecurityOption.BlockInfiniteApproval)) {
            if (_isApproveCall(data)) {
                uint256 approveAmount = _extractApproveAmount(data);
                if (approveAmount == type(uint256).max) revert InfiniteApprovalBlocked();
            }
        }

        if (isEnabled(tokenId, SecurityOption.RestrictTarget)) {
            _validateTarget(tokenId, to);
        }

        if (value > 0 && isEnabled(tokenId, SecurityOption.SingleTxLimit)) {
            if (value > s.gotchiPolicy[tokenId].transferLimit.singleTxLimit)
                revert SingleTxLimitExceeded(s.gotchiPolicy[tokenId].transferLimit.singleTxLimit, value);
        }

        if (value > 0 && isEnabled(tokenId, SecurityOption.DailyTransferLimit)) {
            _checkAndConsumeDailyLimit(tokenId, value);
        }
    }

    function _validateTarget(uint256 tokenId, address target) private view {
        AppStorage storage s = LibAppStorage.diamondStorage();

        if (s.gotchiPolicy[tokenId].whitelistMode) {
            if (!s.gotchiPolicy[tokenId].isWhitelist[target]) revert TargetNotAllowed(target);
        } else {
            if (s.gotchiPolicy[tokenId].isBlacklist[target])  revert TargetNotAllowed(target);
        }
    }

    function _checkAndConsumeDailyLimit(uint256 tokenId, uint256 value) private {
        AppStorage storage s = LibAppStorage.diamondStorage();
        TransferLimitConfig storage cfg = s.gotchiPolicy[tokenId].transferLimit;

        if (uint256(block.timestamp) >= uint256(cfg.lastResetTime) + 1 days) {
            cfg.usedToday = 0;
            cfg.lastResetTime = uint32(block.timestamp);
        }

        uint256 remaining = cfg.dailyLimit > cfg.usedToday
            ? cfg.dailyLimit - cfg.usedToday
            : 0;

        if (value > remaining) revert DailyLimitExceeded(remaining, value);
        s.gotchiPolicy[tokenId].transferLimit.usedToday += value;
    }

    function _isApproveCall(bytes calldata data) private pure returns (bool) {
        if (data.length < 68) return false;
        return bytes4(data[:4]) == 0x095ea7b3;
    }

    function _extractApproveAmount(bytes calldata data) private pure returns (uint256 amount) {
        assembly {
            amount := calldataload(add(data.offset, 36))
        }
    }

    function addTargetWhitelist(uint256 tokenId, address target) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        AccountSecurityPolicy storage policy = s.gotchiPolicy[tokenId];

        require(!policy.isWhitelist[target], "already whitelisted");
        require(!policy.isBlacklist[target], "target is blacklisted");

        policy.isWhitelist[target] = true;
        policy.whitelistIndex[target] = policy.targetWhitelists.length;
        policy.targetWhitelists.push(target);

        emit AddWhitelist(tokenId, target);
    }

    function removeTargetWhitelist(uint256 tokenId, address target) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        AccountSecurityPolicy storage policy = s.gotchiPolicy[tokenId];
        
        require(policy.isWhitelist[target], "not exists");

        uint256 targetIndex = policy.whitelistIndex[target];
        uint256 len = policy.targetWhitelists.length;
        address lastTarget = policy.targetWhitelists[len-1];
        
        policy.targetWhitelists[targetIndex] = lastTarget;
        policy.whitelistIndex[lastTarget] = targetIndex;
        policy.targetWhitelists.pop();
        delete policy.whitelistIndex[target];
        policy.isWhitelist[target] = false;

        emit RemoveWhitelist(tokenId, target);
    }

    function addTargetBlacklist(uint256 tokenId, address target) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        AccountSecurityPolicy storage policy = s.gotchiPolicy[tokenId];

        require(!policy.isBlacklist[target], "already blacklisted");
        require(!policy.isWhitelist[target], "target is whitelisted");

        policy.isBlacklist[target] = true;
        policy.blacklistIndex[target] = policy.targetBlacklists.length;
        policy.targetBlacklists.push(target);

        emit AddBlacklist(tokenId, target);
    }

    function _addWhitelistUnchecked(uint256 tokenId, address target) private {
        AppStorage storage s = LibAppStorage.diamondStorage();
        AccountSecurityPolicy storage policy = s.gotchiPolicy[tokenId];

        if (policy.isWhitelist[target]) return;
        require(!policy.isBlacklist[target], "target is blacklisted");

        policy.isWhitelist[target] = true;
        policy.whitelistIndex[target] = policy.targetWhitelists.length;
        policy.targetWhitelists.push(target);

        emit AddWhitelist(tokenId, target);
    }

    function _addBlacklistUnchecked(uint256 tokenId, address target) private {
        AppStorage storage s = LibAppStorage.diamondStorage();
        AccountSecurityPolicy storage policy = s.gotchiPolicy[tokenId];

        if (policy.isBlacklist[target]) return;
        require(!policy.isWhitelist[target], "target is whitelisted");

        policy.isBlacklist[target] = true;
        policy.blacklistIndex[target] = policy.targetBlacklists.length;
        policy.targetBlacklists.push(target);

        emit AddBlacklist(tokenId, target);
    }

    function removeTargetBlacklist(uint256 tokenId, address target) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        AccountSecurityPolicy storage policy = s.gotchiPolicy[tokenId];

        require(policy.isBlacklist[target], "not exists");

        uint256 targetIndex = policy.blacklistIndex[target];
        uint256 len = policy.targetBlacklists.length;
        address lastTarget = policy.targetBlacklists[len-1];

        policy.targetBlacklists[targetIndex] = lastTarget;
        policy.blacklistIndex[lastTarget] = targetIndex;
        policy.targetBlacklists.pop();
        delete policy.blacklistIndex[target];
        policy.isBlacklist[target] = false;

        emit RemoveBlacklist(tokenId, target);
    }
}
