// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {RuleManagerStorageV2} from "./interfaces/RuleManagerStorageV2.sol";

contract RuleManager is UUPSUpgradeable, PausableUpgradeable, AccessControlUpgradeable, RuleManagerStorageV2 {
    event RuleAdded(
        address indexed from_,
        uint64 indexed id_,
        address indexed contract_,
        uint32 type_,
        uint32 proveThreshold_,
        RuleState state_,
        bytes4 selctor_,
        bytes32 metahash_,
        bytes code_
    );

    event RuleUpdated(
        address indexed from_,
        uint64 indexed id_,
        address indexed contract_,
        uint32 type_,
        uint32 proveThreshold_,
        RuleState state_,
        bytes4 selctor_,
        bytes32 metahash_,
        bytes code_
    );

    event RuleDeleted(address indexed from_, uint64 indexed id_);

    event ProvingResultUpdated(address indexed from_, uint64[] successIds_, uint64[] failIds_);

    event RuleInProving(uint64[] ids_);

    event RuleInUse(uint64[] ids_);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // No longer needed - using ERC1967Utils.getImplementation() instead
    }

    function initialize(address adminAddress_, uint32 _proveThreshold) external initializer {
        require(adminAddress_ != address(0), "Admin address cannot be zero");
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        nextId_ = 1;
        proveThreshold_ = _proveThreshold;
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

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
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

    function checkExist(address _addr, bytes4 _selector, bytes32 _metahash) private view returns (bool) {
        require(_addr != address(0) || _metahash != bytes32(0), "InferRule address AND metahash is 0.");
        // Use O(1) mapping lookup instead of O(n) iteration
        return ruleExists_[_addr][_selector][_metahash];
    }

    function checkExist(uint64 _id) private view returns (bool) {
        return rules_[_id].id_ == _id;
    }

    function addRule(uint32 _type, address _addr, bytes4 _selector, bytes32 _metahash, bytes calldata _code)
        external
        override
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint64)
    {
        require(!checkExist(_addr, _selector, _metahash), "InferRule already exist");

        // Validate rule parameters for integrity
        require(_addr != address(0), "Contract address cannot be zero");
        require(_selector != bytes4(0), "Selector cannot be zero");
        require(_code.length > 0, "Code cannot be empty");
        // Require metahash to be non-zero to ensure rule identity
        require(_metahash != bytes32(0), "Metahash cannot be zero");

        // Verify the contract address has deployed code to ensure it points to a valid contract
        // This is a basic integrity check to prevent registration of rules for non-existent contracts
        require(_addr.code.length > 0, "Contract address has no deployed code");

        uint64 _id = nextId_++;

        rules_[_id] = InferRule({
            id_: _id,
            selctor_: _selector,
            contract_: _addr,
            metahash_: _metahash,
            adder_: _msgSender(),
            type_: _type,
            state_: RuleState.INIT,
            code_: _code
        });

        // Track indices for O(1) removal using swap-and-pop pattern
        ruleIndexInActiveIds_[_id] = activeIds_.length;
        activeIds_.push(_id);

        ruleIndexInContract_[_id] = contractRules_[_addr].length;
        contractRules_[_addr].push(_id);

        ruleIndexInWaitProve_[_id] = waitProveRules_.length;
        waitProveRules_.push(_id);

        // Set fast existence check flag
        ruleExists_[_addr][_selector][_metahash] = true;

        emit RuleAdded(_msgSender(), _id, _addr, _type, proveThreshold_, RuleState.INIT, _selector, _metahash, _code);
        return _id;
    }

    function updateRule(uint64 _id, uint32 _type, bytes calldata _code)
        external
        override
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint64)
    {
        require(checkExist(_id), "InferRule not exist");

        InferRule storage rule = rules_[_id];
        // Make code field immutable to preserve rule integrity
        // The code must match the existing code to ensure the rule's core identity remains consistent
        require(
            keccak256(rule.code_) == keccak256(_code),
            "Cannot update rule code - code is immutable to preserve rule integrity"
        );

        rule.type_ = _type;
        rule.state_ = RuleState.UPDATED;

        // O(1) check and add to waitProveRules_ using index mapping
        bool inWaitProve = ruleIndexInWaitProve_[_id] > 0 || (waitProveRules_.length > 0 && waitProveRules_[0] == _id);
        if (!inWaitProve) {
            ruleIndexInWaitProve_[_id] = waitProveRules_.length;
            waitProveRules_.push(_id);
        }

        // O(1) removal from successRules_ using index mapping
        if (ruleIndexInSuccess_[_id] > 0 || (successRules_.length > 0 && successRules_[0] == _id)) {
            uint256 successIdx = ruleIndexInSuccess_[_id];
            uint256 lastIdx = successRules_.length - 1;
            if (successIdx != lastIdx) {
                uint64 movedRuleId = successRules_[lastIdx];
                successRules_[successIdx] = movedRuleId;
                ruleIndexInSuccess_[movedRuleId] = successIdx;
            }
            successRules_.pop();
            delete ruleIndexInSuccess_[_id];
        }

        emit RuleUpdated(
            _msgSender(),
            _id,
            rule.contract_,
            _type,
            proveThreshold_,
            rule.state_,
            rule.selctor_,
            rule.metahash_,
            rule.code_
        );
        return _id;
    }

    function delRule(uint64 _id) external override whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        require(checkExist(_id), "InferRule not exist");

        InferRule memory rule = rules_[_id];
        address contractAddr = rule.contract_;
        uint64[] storage contractIds = contractRules_[contractAddr];

        // O(1) removal from contractRules_ using index mapping
        uint256 contractIdx = ruleIndexInContract_[_id];
        uint256 lastIdx = contractIds.length - 1;
        if (contractIdx != lastIdx) {
            uint64 movedRuleId = contractIds[lastIdx];
            contractIds[contractIdx] = movedRuleId;
            ruleIndexInContract_[movedRuleId] = contractIdx;
        }
        contractIds.pop();
        if (contractIds.length == 0) {
            delete contractRules_[contractAddr];
        }
        delete ruleIndexInContract_[_id];

        // O(1) removal from activeIds_ using index mapping
        uint256 activeIdx = ruleIndexInActiveIds_[_id];
        lastIdx = activeIds_.length - 1;
        if (activeIdx != lastIdx) {
            uint64 movedRuleId = activeIds_[lastIdx];
            activeIds_[activeIdx] = movedRuleId;
            ruleIndexInActiveIds_[movedRuleId] = activeIdx;
        }
        activeIds_.pop();
        delete ruleIndexInActiveIds_[_id];

        // O(1) removal from waitProveRules_ using index mapping (if present)
        if (ruleIndexInWaitProve_[_id] > 0 || (waitProveRules_.length > 0 && waitProveRules_[0] == _id)) {
            uint256 waitIdx = ruleIndexInWaitProve_[_id];
            lastIdx = waitProveRules_.length - 1;
            if (waitIdx != lastIdx) {
                uint64 movedRuleId = waitProveRules_[lastIdx];
                waitProveRules_[waitIdx] = movedRuleId;
                ruleIndexInWaitProve_[movedRuleId] = waitIdx;
            }
            waitProveRules_.pop();
        }
        delete ruleIndexInWaitProve_[_id];

        // O(1) removal from successRules_ using index mapping (if present)
        if (ruleIndexInSuccess_[_id] > 0 || (successRules_.length > 0 && successRules_[0] == _id)) {
            uint256 successIdx = ruleIndexInSuccess_[_id];
            lastIdx = successRules_.length - 1;
            if (successIdx != lastIdx) {
                uint64 movedRuleId = successRules_[lastIdx];
                successRules_[successIdx] = movedRuleId;
                ruleIndexInSuccess_[movedRuleId] = successIdx;
            }
            successRules_.pop();
        }
        delete ruleIndexInSuccess_[_id];

        // Clear fast existence check flag
        ruleExists_[contractAddr][rule.selctor_][rule.metahash_] = false;

        delete rules_[_id];
        emit RuleDeleted(_msgSender(), _id);
    }

    // return all register rules
    function getAllRules() external view override returns (InferRule[] memory) {
        uint256 count = activeIds_.length;
        InferRule[] memory allRules = new InferRule[](count);
        uint64 index = 0;

        for (uint256 i = 0; i < count; ++i) {
            uint64 id = activeIds_[i];
            if (rules_[id].id_ != 0) {
                allRules[index] = rules_[id];
                index++;
            }
        }

        return allRules;
    }

    // return next_id_
    function getNextId() external view override returns (uint64) {
        return nextId_;
    }

    // return spec contract register rules
    function getContractRules(address _addr) external view override returns (InferRule[] memory) {
        uint64[] storage ids = contractRules_[_addr];
        InferRule[] memory contractSpecificRules = new InferRule[](ids.length);

        for (uint256 i = 0; i < ids.length; ++i) {
            contractSpecificRules[i] = rules_[ids[i]];
        }
        return contractSpecificRules;
    }

    function updateProvingResult(uint64[] calldata _successIds, uint64[] calldata _failIds)
        external
        override
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // Update success rule state
        for (uint256 i = 0; i < _successIds.length; ++i) {
            uint64 id = _successIds[i];
            require(checkExist(id), "InferRule not exist");

            InferRule storage rule = rules_[id];
            require(rule.state_ == RuleState.IN_PROVING, "Invalid state transition");
            rule.state_ = RuleState.PROVING_SUCCESS;

            // add to success list, and will change to IN_USE next epoch
            successRules_.push(id);
        }

        // update fails rule state
        for (uint256 i = 0; i < _failIds.length; ++i) {
            uint64 id = _failIds[i];
            require(checkExist(id), "InferRule not exist");

            InferRule storage rule = rules_[id];
            require(rule.state_ == RuleState.IN_PROVING, "Invalid state transition");
            rule.state_ = RuleState.PROVING_FAILURE;
        }

        emit ProvingResultUpdated(_msgSender(), _successIds, _failIds);
    }

    function advanceEpoch() external override whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        uint64[] memory waitProveIds = new uint64[](waitProveRules_.length);
        uint256 count = 0;
        for (uint256 i = 0; i < waitProveRules_.length; ++i) {
            uint64 id = waitProveRules_[i];
            InferRule storage rule = rules_[id];
            if (rule.state_ == RuleState.INIT || rule.state_ == RuleState.UPDATED) {
                rule.state_ = RuleState.IN_PROVING;
                waitProveIds[count] = id;
                count++;
            }
        }

        if (count > 0) {
            uint64[] memory provingIds = new uint64[](count);
            for (uint256 j = 0; j < count; ++j) {
                provingIds[j] = waitProveIds[j];
            }
            emit RuleInProving(provingIds);
        }

        // Clear waitProveRules_ and reset index mappings
        for (uint256 i = 0; i < waitProveRules_.length; ++i) {
            delete ruleIndexInWaitProve_[waitProveRules_[i]];
        }
        delete waitProveRules_;

        if (successRules_.length > 0) {
            for (uint256 i = 0; i < successRules_.length; ++i) {
                uint64 id = successRules_[i];
                InferRule storage rule = rules_[id];
                if (rule.state_ == RuleState.PROVING_SUCCESS) {
                    rule.state_ = RuleState.IN_USE;
                }
            }
            emit RuleInUse(successRules_);
        }

        // Clear successRules_ and reset index mappings
        for (uint256 i = 0; i < successRules_.length; ++i) {
            delete ruleIndexInSuccess_[successRules_[i]];
        }
        delete successRules_;
    }
}
