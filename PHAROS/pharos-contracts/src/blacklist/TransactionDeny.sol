// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {TransactionDenyStorageV2} from "./interfaces/TransactionDenyStorageV2.sol";

contract TransactionDeny is UUPSUpgradeable, PausableUpgradeable, Ownable2StepUpgradeable, TransactionDenyStorageV2 {
    event BlacklistUpdated(address indexed account, bool isBlacklisted);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address adminAddress_) external initializer {
        require(adminAddress_ != address(0), "Admin address is zero");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        _transferOwnership(adminAddress_);
    }

    /**
     * @notice Upgrade the contract
     * This function is required by OpenZeppelin's UUPSUpgradeable
     *
     * @param newImplementation                  new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    /**
     * @notice Migrate V1 data to V2 by populating blacklistIndex_ for existing addresses
     * @dev Must be called once after upgrading from V1 to V2
     * This function populates the blacklistIndex_ mapping for all existing blacklisted addresses
     * to enable O(1) removal. Can only be called once.
     */
    function migrateV1ToV2() external onlyOwner {
        require(!v1ToV2Migrated, "Migration already completed");

        uint256 length = _blacklistedAddresses.length;
        for (uint256 i = 0; i < length; ++i) {
            address account = _blacklistedAddresses[i];
            blacklistIndex_[account] = i;
        }

        v1ToV2Migrated = true;
    }

    /**
     * @dev Pauses the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    function _removeFromArray(address account) internal {
        // O(1) removal using index mapping and swap-and-pop pattern
        uint256 idx = blacklistIndex_[account];
        uint256 lastIdx = _blacklistedAddresses.length - 1;

        // Defensive check: verify the index is correct (handles unmigrated V1 data)
        require(_blacklistedAddresses[idx] == account, "Index mismatch, run migrateV1ToV2");

        if (idx != lastIdx) {
            address movedAccount = _blacklistedAddresses[lastIdx];
            _blacklistedAddresses[idx] = movedAccount;
            blacklistIndex_[movedAccount] = idx;
        }

        _blacklistedAddresses.pop();
        delete blacklistIndex_[account];
    }

    function isBlacklisted(address account) external view override returns (bool) {
        return _blacklisted[account];
    }

    function addBlacklistedAddresses(address[] memory accounts) external override whenNotPaused onlyOwner {
        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[i];
            if (!_blacklisted[account]) {
                _blacklisted[account] = true;
                // Track index for O(1) removal
                blacklistIndex_[account] = _blacklistedAddresses.length;
                _blacklistedAddresses.push(account);
                emit BlacklistUpdated(account, true);
            }
        }
    }

    function removeBlacklistedAddresses(address[] memory accounts) external override whenNotPaused onlyOwner {
        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[i];
            if (_blacklisted[account]) {
                _blacklisted[account] = false;
                _removeFromArray(account);
                emit BlacklistUpdated(account, false);
            }
        }
    }

    function getBlacklistedAddresses() external view override returns (address[] memory) {
        return _blacklistedAddresses;
    }
}
