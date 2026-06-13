// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ChainConfigStorageV1} from "./interfaces/ChainConfigStorageV1.sol";

contract ChainConfig is UUPSUpgradeable, PausableUpgradeable, AccessControlUpgradeable, ChainConfigStorageV1 {
    event PendingConfigAdded(uint64 indexed blockNum, string key, string value);
    event ConfigUpdate(uint64 indexed blockNum, uint64 indexed effectiveBlockNum, Config[] kvs);
    event StakingUpdate(address indexed oldStakingAddress, address indexed newStakingAddress);

    modifier onlyAdminOrStaking() {
        _onlyAdminOrStaking();
        _;
    }

    modifier onlyStaking() {
        _onlyStaking();
        _;
    }

    function _onlyAdminOrStaking() internal view {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) || _msgSender() == stakingAddress,
            "Caller is not admin or staking contract"
        );
    }

    function _onlyStaking() internal view {
        require(_msgSender() == stakingAddress, "msg sender is not the staking address");
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // No longer needed - using ERC1967Utils.getImplementation() instead
    }

    function initialize(address adminAddress_, address stakingAddress_) external initializer {
        require(adminAddress_ != address(0), "Admin address cannot be zero");
        require(stakingAddress_ != address(0), "Staking address cannot be zero");
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        stakingAddress = stakingAddress_;
        _grantRole(DEFAULT_ADMIN_ROLE, adminAddress_);
    }

    /**
     * @notice Upgrade the contract
     * This function is required by OpenZeppelin's UUPSUpgradeable
     *
     * @param newImplementation                  new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // We are overriding the function that relies on the UUPS __self mechanism
    // because we directly hardcode the deployed code into storage during the genesis block creation,
    // rendering __self unusable in this context.
    // The `implAddress` variable is used to hold the current address of the implementation logic.
    // It replaces the 'address private immutable __self = address(this);' variable
    // And modify the relevant modifiers accordingly
    function getImplAddress() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    function _checkProxy() internal view virtual override {
        address implementation = ERC1967Utils.getImplementation();
        if (
            address(this) == implementation // Must be called through delegatecall
                || implementation == address(0) // Must be called through an active proxy
        ) {
            revert UUPSUnauthorizedCallContext();
        }
    }

    function _checkNotDelegated() internal view virtual override {
        // This function should only be callable directly on the implementation contract (not through proxy delegatecall)
        // When called directly on implementation: address(this) == implementation address
        // When called through proxy (delegatecall): address(this) == proxy address != implementation address
        // We want to REJECT calls from delegatecall and ALLOW direct calls
        address implementation = ERC1967Utils.getImplementation();
        // If we're being called through delegatecall (proxy address != implementation address), reject
        if (address(this) != implementation && implementation != address(0)) {
            revert UUPSUnauthorizedCallContext();
        }
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external onlyAdminOrStaking {
        _setRoleAdmin(role, adminRole);
    }

    function updateStakingAddress(address stakingAddress_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakingAddress_ != address(0), "The new staking contract address can't be the zero address");
        require(stakingAddress_ != stakingAddress, "New staking address is the same as the current address");
        address oldStakingAddress = stakingAddress;
        stakingAddress = stakingAddress_;
        emit StakingUpdate(oldStakingAddress, stakingAddress_);
    }

    /**
     * @dev Pauses the contract
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function getConfig(string memory key) external view override returns (string memory) {
        if (configCps.length != 0) {
            // Search backwards through checkpoints to find the latest value for this key
            // Start from the most recent checkpoint and work backwards
            for (uint256 i = configCps.length - 1; i >= 0; i--) {
                // Only check checkpoints that are already effective
                if (block.number >= configCps[i].effectiveBlockNum) {
                    for (uint256 j = 0; j < configCps[i].configs.length; ++j) {
                        Config memory conf = configCps[i].configs[j];
                        bytes32 confHash = keccak256(abi.encodePacked(conf.key));
                        if (keccak256(abi.encodePacked(key)) == confHash) {
                            return conf.value;
                        }
                    }
                }
                // If we reach checkpoint 0, break the loop
                if (i == 0) break;
            }
        }
        return "";
    }

    function getConfigs() external view override returns (Config[] memory) {
        if (configCps.length != 0) {
            // Find the latest active checkpoint (where effectiveBlockNum has been reached)
            uint256 activeCpIndex = configCps.length - 1;

            // Check if the latest checkpoint's effective block has been reached
            // If not, search backwards for the latest active checkpoint
            while (activeCpIndex > 0 && block.number < configCps[activeCpIndex].effectiveBlockNum) {
                activeCpIndex--;
            }

            // Verify the effective block has been reached for the selected checkpoint
            if (block.number >= configCps[activeCpIndex].effectiveBlockNum) {
                return configCps[activeCpIndex].configs;
            }
        }
        Config[] memory configs;
        return configs;
    }

    function addPendingConfig(string[] memory keys, string[] memory values)
        public
        override
        whenNotPaused
        onlyAdminOrStaking
    {
        require(keys.length == values.length, "KVs length are not match");

        for (uint256 i = 0; i < keys.length; ++i) {
            bytes32 confHash = keccak256(abi.encodePacked(keys[i]));
            bool newKv = true;
            for (uint256 j = 0; j < pendingActiveConfigs.length; ++j) {
                // override existing keys
                if (confHash == keccak256(abi.encodePacked(pendingActiveConfigs[j].key))) {
                    pendingActiveConfigs[j].value = values[i];
                    newKv = false;
                    emit PendingConfigAdded(
                        uint64(block.number), pendingActiveConfigs[j].key, pendingActiveConfigs[j].value
                    );
                    break;
                }
            }

            if (newKv) {
                pendingActiveConfigs.push(Config({key: keys[i], value: values[i]}));
                emit PendingConfigAdded(uint64(block.number), keys[i], values[i]);
            }
        }
    }

    function getPendingConfigs() external view override returns (Config[] memory) {
        return pendingActiveConfigs;
    }

    function setConfig(string[] memory keys, string[] memory values) external override whenNotPaused onlyStaking {
        require(keys.length == values.length, "KVs length are not match");
        if (configCps.length == MAX_CONFIGCP_VERSIONS) {
            delete configCps[0];
            for (uint256 i = 1; i < configCps.length; ++i) {
                configCps[i - 1] = configCps[i];
            }
            configCps.pop();
        }

        uint256 oldConfigCpsNumber = configCps.length;

        ConfigCheckpoint storage cfgCp = configCps.push();
        cfgCp.blockNum = uint64(block.number);
        cfgCp.effectiveBlockNum = uint64(block.number + 1);

        // merge these kvs with pending pendingActiveConfigs
        addPendingConfig(keys, values);
        if (oldConfigCpsNumber != 0) {
            for (uint256 i = 0; i < configCps[configCps.length - 2].configs.length; ++i) {
                Config memory conf = configCps[configCps.length - 2].configs[i];
                bool found = false;
                bytes32 confHash = keccak256(abi.encodePacked(conf.key));
                for (uint256 j = 0; j < pendingActiveConfigs.length; ++j) {
                    if (confHash == keccak256(abi.encodePacked(pendingActiveConfigs[j].key))) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    cfgCp.configs.push(Config({key: conf.key, value: conf.value}));
                }
            }
        }

        for (uint256 i = 0; i < pendingActiveConfigs.length; ++i) {
            cfgCp.configs.push(Config({key: pendingActiveConfigs[i].key, value: pendingActiveConfigs[i].value}));
        }
        emit ConfigUpdate(uint64(block.number), uint64(block.number + 1), pendingActiveConfigs);

        delete pendingActiveConfigs;
    }
}
