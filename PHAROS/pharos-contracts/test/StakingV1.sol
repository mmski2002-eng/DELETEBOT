// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    ERC2771ContextUpgradeable,
    ContextUpgradeable
} from "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {StakingStorageV1} from "../src/staking/interfaces/StakingStorageV1.sol";
import {IChainConfig} from "../src/chainConfig/interfaces/IChainConfig.sol";
import {IStaking} from "../src/staking/interfaces/IStaking.sol";

/**
 * @title StakingV1
 * @notice First version of Staking contract without delegation functionality
 * @dev This is a simplified version for testing upgrade path from V1 to V2
 */
contract StakingV1 is
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC2771ContextUpgradeable,
    StakingStorageV1
{
    event DomainUpdate(
        bytes32 indexed poolId,
        string description,
        string publicKey,
        string blsPublicKey,
        string endpoint,
        uint64 effectiveBlockNum,
        uint8 status
    );

    event EpochChange(
        uint256 indexed epochNumber,
        uint256 indexed blockNumber,
        uint256 timestamp,
        uint256 totalStake,
        bytes32[] activeValidators
    );

    event ValidatorReward(
        bytes32 indexed poolId,
        address indexed owner,
        uint256 indexed epochNumber,
        uint256 blockNumber,
        uint256 baseReward,
        uint256 feeReward,
        uint256 totalReward
    );

    event ValidatorWithdrawStake(
        bytes32 indexed poolId,
        uint256 indexed epochNumber,
        uint256 indexed blockNumber,
        uint256 totalStake,
        uint256 withdrawStake
    );

    event ImplAddressUpdated(address oldImplAddress, address newImplAddress);

    event ChainConfigUpdate(address newChainConfigAddress);

    event ErrorOccurred(uint256 indexed epochNumber, uint256 indexed blockNumber, uint256 errorCode, bytes errorData);

    event BalanceReceived(
        uint256 indexed epochNumber,
        uint256 indexed blockNumber,
        address indexed sender,
        uint256 amount,
        uint256 totalBalance
    );

    event InflationRateAdjusted(uint256 oldRate, uint256 newRate, uint256 timestamp);
    event TotalSupplyIncreased(uint256 indexed epochNumber, uint256 amount, uint256 newTotalSupply);
    event StakeAdded(address indexed delegator, bytes32 indexed poolId, uint256 amount);
    event ValidatorRegistered(address indexed validator, bytes32 indexed poolId, uint256 amount);
    event ValidatorUpdated(bytes32 indexed poolId);
    event ValidatorOwnerUpdated(bytes32 indexed poolId, address indexed oldOwner, address indexed newOwner);
    event ValidatorExitRequested(bytes32 indexed poolId);

    uint256 public constant INITIAL_TOTAL_SUPPLY = 1000000000 ether;
    uint256 public constant INITIAL_INFLATION_RATE = 9125;
    uint256 private constant INFLATION_RATE_DENOMINATOR = 100000;
    uint256 private constant DEFAULT_EPOCH_DURATION = 4 hours;
    uint256 private constant YEAR_IN_SECONDS = 365 days;
    uint256 public constant MIN_INFLATION_RATE = 2391;
    uint256 public constant INFLATION_ADJUSTMENT_RATE = 80000;
    uint256 public constant INFLATION_ADJUSTMENT_INTERVAL = 365 days;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC2771ContextUpgradeable(address(0)) {
        _disableInitializers();
        implAddress = address(this);
    }

    function initialize(address adminAddress_, address chainConfigAddress_) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        cfg = IChainConfig(chainConfigAddress_);
        _grantRole(DEFAULT_ADMIN_ROLE, adminAddress_);

        totalSupply = INITIAL_TOTAL_SUPPLY;
        currentInflationRate = INITIAL_INFLATION_RATE;
        lastInflationAdjustmentTime = block.timestamp;
        lastInflationTotalSupplySnapshot = INITIAL_TOTAL_SUPPLY;
        implAddress = address(this);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function getImplAddress() external view returns (address) {
        return implAddress;
    }

    function updateImplAddress(address _newImplementationAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldImplAddress = implAddress;
        implAddress = _newImplementationAddress;
        emit ImplAddressUpdated(oldImplAddress, implAddress);
    }

    function _checkProxy() internal view virtual override {
        if (address(this) == implAddress || ERC1967Utils.getImplementation() != implAddress) {
            revert UUPSUnauthorizedCallContext();
        }
    }

    function _checkNotDelegated() internal view virtual override {
        if (address(this) != implAddress) {
            revert UUPSUnauthorizedCallContext();
        }
    }

    function _msgSender()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (uint256)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }

    function getEpochDurationMs() internal view returns (uint256) {
        string memory key = "chain.epoch_duration";
        string memory value = getChainCfg(key);
        if (Strings.equal(value, "")) {
            return DEFAULT_EPOCH_DURATION * 1000;
        }
        uint256 duration = uint256(Strings.parseUint(value));
        return duration == 0 ? DEFAULT_EPOCH_DURATION * 1000 : duration;
    }

    function getEpochDuration() internal view returns (uint256) {
        uint256 durationMs = getEpochDurationMs();
        uint256 durationSec = durationMs / 1000;
        if (durationSec == 0) {
            durationSec = 1;
        }
        return durationSec;
    }

    function calculateEpochReward() internal view returns (uint256) {
        if (lastInflationTotalSupplySnapshot == 0 || currentInflationRate == 0) {
            return 0;
        }

        uint256 annualReward = (lastInflationTotalSupplySnapshot * currentInflationRate) / INFLATION_RATE_DENOMINATOR;
        uint256 epochDuration = getEpochDuration();
        uint256 epochReward = annualReward * epochDuration / YEAR_IN_SECONDS;
        return epochReward;
    }

    function adjustInflationRate() internal {
        if (block.timestamp - lastInflationAdjustmentTime < INFLATION_ADJUSTMENT_INTERVAL) {
            return;
        }

        uint256 oldRate = currentInflationRate;
        currentInflationRate = (currentInflationRate * INFLATION_ADJUSTMENT_RATE) / INFLATION_RATE_DENOMINATOR;
        if (currentInflationRate < MIN_INFLATION_RATE) {
            currentInflationRate = MIN_INFLATION_RATE;
        }

        lastInflationAdjustmentTime = block.timestamp;
        lastInflationTotalSupplySnapshot = totalSupply;

        emit InflationRateAdjusted(oldRate, currentInflationRate, block.timestamp);
    }

    function updateChainConfigAddress(address chainConfigAddress_) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        require(chainConfigAddress_ != address(0), "The new chain config contract address can't be the zero address");
        cfg = IChainConfig(chainConfigAddress_);
        emit ChainConfigUpdate(chainConfigAddress_);
    }

    function version() external pure virtual returns (uint256) {
        return 1;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function hexStringToBytes(string memory str) internal pure returns (bytes memory) {
        bytes memory strBytes = bytes(str);

        if (strBytes.length >= 2 && strBytes[0] == "0" && strBytes[1] == "x") {
            strBytes = sliceBytes(strBytes, 2, strBytes.length);
        }

        require(strBytes.length % 2 == 0, "Invalid hex string length");

        bytes memory result = new bytes(strBytes.length / 2);

        for (uint256 i = 0; i < strBytes.length / 2; i++) {
            result[i] = bytes1(_fromHexChar(strBytes[2 * i]) * 16 + _fromHexChar(strBytes[2 * i + 1]));
        }

        return result;
    }

    function sliceBytes(bytes memory data, uint256 start, uint256 end) internal pure returns (bytes memory) {
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = data[i];
        }
        return result;
    }

    function _fromHexChar(bytes1 c) internal pure returns (uint8) {
        uint8 charCode = uint8(c);
        if (charCode >= 48 && charCode <= 57) {
            return charCode - 48;
        } else if (charCode >= 97 && charCode <= 102) {
            return charCode - 87;
        } else if (charCode >= 65 && charCode <= 70) {
            return charCode - 55;
        } else {
            revert("Invalid hex character");
        }
    }

    function isArrayContains(bytes32[] memory array, bytes32 element) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) {
                return true;
            }
        }
        return false;
    }

    function isArrayLengthWithinLimit(uint256 _arrayLength) internal pure returns (bool) {
        if (_arrayLength > MAX_QUEUE_LENGTH) {
            return false;
        }
        return true;
    }

    function isValidatorActive(bytes32 _poolId) external view whenNotPaused returns (bool) {
        return isArrayContains(activePoolIds, _poolId);
    }

    function isValidatorPendingAdd(bytes32 _poolId) external view whenNotPaused returns (bool) {
        return isArrayContains(pendingAddPoolIds, _poolId);
    }

    function isValidatorPendingUpdate(bytes32 _poolId) external view whenNotPaused returns (bool) {
        return isArrayContains(pendingUpdatePoolIds, _poolId);
    }

    function isValidatorPendingExit(bytes32 _poolId) external view whenNotPaused returns (bool) {
        return isArrayContains(pendingExitPoolIds, _poolId);
    }

    function unionArrays(bytes32[] memory _poolId1, bytes32[] memory _poolId2) public pure returns (bytes32[] memory) {
        bytes32[] memory tempUnion = new bytes32[](_poolId1.length + _poolId2.length);
        uint256 totalCount = 0;

        for (uint256 i = 0; i < _poolId1.length; i++) {
            bytes32 poolId = _poolId1[i];
            tempUnion[totalCount] = poolId;
            totalCount++;
        }

        for (uint256 i = 0; i < _poolId2.length; i++) {
            bytes32 poolId = _poolId2[i];
            if (!isArrayContains(tempUnion, poolId)) {
                tempUnion[totalCount] = poolId;
                totalCount++;
            }
        }

        bytes32[] memory result = new bytes32[](totalCount);
        for (uint256 i = 0; i < totalCount; i++) {
            result[i] = tempUnion[i];
        }

        return result;
    }

    function registerValidator(
        string memory _description,
        string memory _publicKey,
        string memory _publicKeyPop,
        string memory _blsPublicKey,
        string memory _blsPublicKeyPop,
        string memory _endpoint
    ) external payable whenNotPaused nonReentrant returns (bytes32) {
        uint256 minValidatorStake = getMinValidatorStake();
        uint256 maxValidatorStake = getMaxValidatorStake();
        require(msg.value >= minValidatorStake, "Insufficient stake");
        require(msg.value <= maxValidatorStake, "Stake too large");

        require(isArrayLengthWithinLimit(pendingAddPoolIds.length), "pendingAddPool exceeds limit");

        bytes memory publicKeyBytes = hexStringToBytes(_publicKey);
        bytes32 poolId = bytes32(sha256((abi.encodePacked(publicKeyBytes))));

        require(!this.isValidatorPendingAdd(poolId), "Validator is pending register");
        require(!this.isValidatorPendingExit(poolId), "Validator is pending exit");
        require(validators[poolId].status == 0, "Validator already registered");

        require(pendingWithdrawStakes[_msgSender()] == 0, "Must complete previous withdrawal first");

        Validator memory validator = validators[poolId];
        validator.description = _description;
        validator.publicKey = _publicKey;
        validator.publicKeyPop = _publicKeyPop;
        validator.blsPublicKey = _blsPublicKey;
        validator.blsPublicKeyPop = _blsPublicKeyPop;
        validator.endpoint = _endpoint;
        validator.status = 0;
        validator.poolId = poolId;
        validator.totalStake += msg.value;
        validator.owner = _msgSender();
        validator.stakeSnapshot = 0;

        validators[poolId] = validator;

        pendingAddPoolIds.push(poolId);

        emit ValidatorRegistered(_msgSender(), poolId, validator.totalStake);
        return poolId;
    }

    function updateValidator(bytes32 _poolId, string memory _description, string memory _endpoint)
        external
        whenNotPaused
    {
        require(validators[_poolId].poolId != 0, "Validator does not exist");
        require(validators[_poolId].owner == _msgSender(), "Caller is not the validator owner");
        require(
            this.isValidatorActive(_poolId) || this.isValidatorPendingAdd(_poolId),
            "Validator is not in an updatable state"
        );
        require(isArrayLengthWithinLimit(pendingUpdatePoolIds.length), "pendingUpdatePool exceeds limit");

        require(!this.isValidatorPendingUpdate(_poolId), "Validator is pending update");

        validators[_poolId].description = _description;
        validators[_poolId].endpoint = _endpoint;

        if (!this.isValidatorPendingAdd(_poolId)) {
            pendingUpdatePoolIds.push(_poolId);
        }

        emit ValidatorUpdated(_poolId);
    }

    // place holder
    function nominateOwner(bytes32 _poolId, address _newOwner) external whenNotPaused {}

    // place holder
    function acceptOwnership(bytes32 _poolId) external whenNotPaused {}

    function updateValidatorOwner(bytes32 _poolId, address _newOwner) external whenNotPaused {
        require(validators[_poolId].poolId != 0, "Validator does not exist");
        require(validators[_poolId].owner == _msgSender(), "Caller is not the validator owner");
        require(
            this.isValidatorActive(_poolId) || this.isValidatorPendingAdd(_poolId),
            "Validator is not in an updatable state"
        );
        require(isArrayLengthWithinLimit(pendingUpdatePoolIds.length), "pendingUpdatePool exceeds limit");

        require(!this.isValidatorPendingUpdate(_poolId), "Validator is pending update");
        require(_newOwner != address(0), "New owner address cannot be zero");

        address oldOwner = validators[_poolId].owner;
        validators[_poolId].owner = _newOwner;

        if (!this.isValidatorPendingAdd(_poolId)) {
            pendingUpdatePoolIds.push(_poolId);
        }

        emit ValidatorOwnerUpdated(_poolId, oldOwner, _newOwner);
    }

    function exitValidator(bytes32 _poolId) external whenNotPaused nonReentrant {
        require(validators[_poolId].poolId != 0, "Validator does not exist");
        require(this.isValidatorActive(_poolId) || this.isValidatorPendingAdd(_poolId), "Validator status invalid");
        require(!this.isValidatorPendingExit(_poolId), "Validator is pending exit");
        require(validators[_poolId].owner == _msgSender(), "Caller is not the validator owner");
        require(isArrayLengthWithinLimit(pendingExitPoolIds.length), "pendingExitPool exceeds limit");

        if (this.isValidatorPendingAdd(_poolId)) {
            for (uint256 i = 0; i < pendingAddPoolIds.length; i++) {
                if (pendingAddPoolIds[i] == _poolId) {
                    pendingAddPoolIds[i] = pendingAddPoolIds[pendingAddPoolIds.length - 1];
                    pendingAddPoolIds.pop();
                    break;
                }
            }
        }

        uint256 ownerStake = validators[_poolId].totalStake;
        validators[_poolId].totalStake = 0;
        validators[_poolId].pendingWithdrawStake = ownerStake;
        validators[_poolId].pendingWithdrawWindow = getWithdrawEffectiveWindow();

        pendingWithdrawStakes[_msgSender()] = ownerStake;

        pendingExitPoolIds.push(_poolId);
        emit ValidatorExitRequested(_poolId);
    }

    function addStake(bytes32 _poolId) external payable whenNotPaused nonReentrant {
        require(validators[_poolId].poolId != 0, "Validator does not exist");
        require(this.isValidatorActive(_poolId) || this.isValidatorPendingAdd(_poolId), "Validator status invalid");

        uint256 minDelegatorStake = getMinDelegatorStake();
        require(msg.value >= minDelegatorStake, "Insufficient stake");

        uint256 maxValidatorStake = getMaxValidatorStake();
        require(validators[_poolId].totalStake + msg.value <= maxValidatorStake, "Pool stake limit exceeded");

        validators[_poolId].totalStake = validators[_poolId].totalStake + msg.value;

        emit StakeAdded(_msgSender(), _poolId, msg.value);
    }

    function advanceEpoch() external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32[] memory _poolIds = new bytes32[](0);
        uint256[] memory _priorityFees = new uint256[](0);
        _advanceEpoch(_poolIds, _priorityFees);
    }

    function advanceEpoch(bytes32[] memory _poolIds, uint256[] memory _priorityFees)
        external
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _advanceEpoch(_poolIds, _priorityFees);
    }

    function _advanceEpoch(bytes32[] memory _poolIds, uint256[] memory _priorityFees) internal {
        require(_poolIds.length == _priorityFees.length, "PoolId Fees not match");

        rewardValidators(_poolIds, _priorityFees);

        _processPendingAdditions();
        _processPendingExits();
        _processPendingUpdates();
        _processWithdrawals();

        _updateEpoch();

        emit EpochChange(currentEpoch, block.number, block.timestamp, totalStake, activePoolIds);
    }

    function _processPendingAdditions() internal {
        uint256 minValidatorStake = getMinValidatorStake();
        uint256 pendingIndex = 0;
        while (pendingIndex < pendingAddPoolIds.length) {
            bytes32 poolId = pendingAddPoolIds[pendingIndex];
            if (validators[poolId].totalStake >= minValidatorStake) {
                activePoolIds.push(poolId);
                validators[poolId].status = 1;
                pendingAddPoolIds[pendingIndex] = pendingAddPoolIds[pendingAddPoolIds.length - 1];
                pendingAddPoolIds.pop();
                _emitDomainUpdate(poolId);
            } else {
                ++pendingIndex;
            }
        }
    }

    function _processPendingExits() internal {
        uint256 i = 0;
        while (i < pendingExitPoolIds.length) {
            bytes32 poolId = pendingExitPoolIds[i];
            _removeFromActiveIfNeeded(poolId);

            // Note: Don't remove from pendingExitPoolIds here
            // Let _processWithdrawals handle the window countdown first
            i++;
        }
    }

    function _removeFromActiveIfNeeded(bytes32 poolId) internal {
        if (validators[poolId].totalStake < MIN_POOL_STAKE) {
            uint256 activeLength = activePoolIds.length;
            for (uint256 j = 0; j < activeLength; j++) {
                if (activePoolIds[j] == poolId) {
                    activePoolIds[j] = activePoolIds[activePoolIds.length - 1];
                    activePoolIds.pop();
                    validators[poolId].status = 0;

                    emit DomainUpdate(
                        poolId,
                        validators[poolId].description,
                        validators[poolId].publicKey,
                        validators[poolId].blsPublicKey,
                        validators[poolId].endpoint,
                        uint64(block.number + 1),
                        validators[poolId].status
                    );
                    break;
                }
            }
        }
    }

    function _processPendingUpdates() internal {
        uint256 updateLength = pendingUpdatePoolIds.length;
        for (uint256 i = 0; i < updateLength; i++) {
            bytes32 poolId = pendingUpdatePoolIds[i];
            _updateDomainIfActive(poolId);
        }
        delete pendingUpdatePoolIds;
    }

    function _updateDomainIfActive(bytes32 poolId) internal {
        uint256 activeLength = activePoolIds.length;
        for (uint256 j = 0; j < activeLength; j++) {
            if (activePoolIds[j] == poolId) {
                emit DomainUpdate(
                    poolId,
                    validators[poolId].description,
                    validators[poolId].publicKey,
                    validators[poolId].blsPublicKey,
                    validators[poolId].endpoint,
                    uint64(block.number + 1),
                    validators[poolId].status
                );
                break;
            }
        }
    }

    function _processWithdrawals() internal {
        for (uint256 i = 0; i < pendingExitPoolIds.length; i++) {
            bytes32 poolId = pendingExitPoolIds[i];
            if (validators[poolId].pendingWithdrawWindow > 0) {
                validators[poolId].pendingWithdrawWindow--;
            }
        }
    }

    function _updateEpoch() internal {
        setChainEpochBlock();
        updateTotalStake();
        adjustInflationRate();
        currentEpoch++;
    }

    function _emitDomainUpdate(bytes32 poolId) internal {
        emit DomainUpdate(
            poolId,
            validators[poolId].description,
            validators[poolId].publicKey,
            validators[poolId].blsPublicKey,
            validators[poolId].endpoint,
            uint64(block.number + 1),
            validators[poolId].status
        );
    }

    function updateTotalStake() internal {
        totalStake = 0;
        uint256 length = activePoolIds.length;
        for (uint256 i = 0; i < length; i++) {
            bytes32 poolId = activePoolIds[i];
            validators[poolId].stakeSnapshot = validators[poolId].totalStake;
            totalStake += validators[poolId].totalStake;
        }
    }

    function setChainEpochBlock() internal {
        string[] memory keys = new string[](2);
        string[] memory values = new string[](2);

        string memory epochNumKey = "chain.epoch_start_block";
        string memory epochNumValue = Strings.toString(block.number);
        keys[0] = epochNumKey;
        values[0] = epochNumValue;

        string memory epochTimeKey = "chain.epoch_start_timestamp";
        string memory epochTimeValue = Strings.toString(block.timestamp);
        keys[1] = epochTimeKey;
        values[1] = epochTimeValue;

        cfg.setConfig(keys, values);
    }

    function getActiveValidators() external view whenNotPaused returns (bytes32[] memory) {
        return activePoolIds;
    }

    function getPoolDelegators(bytes32 _poolId) external view whenNotPaused returns (address[] memory) {
        revert("getPoolDelegators not supported in V1");
    }

    function getPendingAddValidators() external view whenNotPaused returns (bytes32[] memory) {
        return pendingAddPoolIds;
    }

    function getPendingExitValidators() external view whenNotPaused returns (bytes32[] memory) {
        return pendingExitPoolIds;
    }

    function getPendingUpdateValidators() external view whenNotPaused returns (bytes32[] memory) {
        return pendingUpdatePoolIds;
    }

    function slashValidator(bytes32 _poolId) external whenNotPaused {
        // To be implemented
    }

    function withdrawStake(bytes32 _poolId, uint256 _withdrawStake) external whenNotPaused nonReentrant {
        require(validators[_poolId].poolId != 0, "Validator does not exist");
        require(validators[_poolId].owner == _msgSender(), "Caller is not the validator owner");
        require(!this.isValidatorPendingExit(_poolId), "Validator is pending exit");
        require(isArrayLengthWithinLimit(pendingExitPoolIds.length), "pendingExitPool exceeds limit");

        require(validators[_poolId].totalStake >= _withdrawStake, "Insufficient stake");

        validators[_poolId].totalStake -= _withdrawStake;
        validators[_poolId].pendingWithdrawStake = _withdrawStake;
        validators[_poolId].pendingWithdrawWindow = getWithdrawEffectiveWindow();

        pendingWithdrawStakes[_msgSender()] = _withdrawStake;
        pendingExitPoolIds.push(_poolId);
    }

    function claimStake(bytes32 _poolId) external nonReentrant {
        require(validators[_poolId].poolId != 0, "Validator does not exist");
        require(validators[_poolId].owner == msg.sender, "Caller is not the validator owner");
        require(validators[_poolId].pendingWithdrawWindow == 0, "Withdraw window not passed");

        uint256 amount = pendingWithdrawStakes[msg.sender];
        require(amount > 0, "No withdrawable stake");

        pendingWithdrawStakes[msg.sender] = 0;
        validators[_poolId].pendingWithdrawStake = 0;

        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        emit StakeClaimed(msg.sender, amount);
    }

    function getMinValidatorStake() internal view returns (uint256) {
        string memory key = "staking.min_staking_pool_value";
        string memory value = getChainCfg(key);
        if (Strings.equal(value, "")) {
            return MIN_POOL_STAKE;
        }
        return uint256(Strings.parseUint(value));
    }

    function getMaxValidatorStake() internal view returns (uint256) {
        string memory key = "staking.max_staking_pool_value";
        string memory value = getChainCfg(key);
        if (Strings.equal(value, "")) {
            return MAX_POOL_STAKE;
        }
        return uint256(Strings.parseUint(value));
    }

    function enablePosReward() internal view returns (bool) {
        string memory key = "chain.enable_pos_staking";
        string memory value = getChainCfg(key);
        if (Strings.equal(value, "true") || Strings.equal(value, "True") || Strings.equal(value, "")) {
            return true;
        }

        if (Strings.equal(value, "false") || Strings.equal(value, "False")) {
            return false;
        }

        return true;
    }

    function settleReward(bytes32 _poolId) external whenNotPaused {
        // V1 doesn't have delegation rewards, this is a no-op for compatibility
    }

    event StakeClaimed(address indexed user, uint256 amount);

    function getMinDelegatorStake() internal view returns (uint256) {
        string memory key = "staking.min_delegator_stake";
        string memory value = getChainCfg(key);
        if (Strings.equal(value, "")) {
            return MIN_DELEGATOR_STAKE;
        }

        return uint256(Strings.parseUint(value));
    }

    function getWithdrawEffectiveWindow() internal view returns (uint8) {
        string memory key = "staking.withdraw_effective_epoch";
        string memory value = getChainCfg(key);
        return uint8(Strings.parseUint(value));
    }

    function getChainCfg(string memory key) internal view returns (string memory) {
        return cfg.getConfig(key);
    }

    function increaseTotalSupply(uint256 amount) internal {
        totalSupply += amount;
        emit TotalSupplyIncreased(currentEpoch, amount, totalSupply);
    }

    function getValidatorRewards(bytes32[] memory _poolIds)
        internal
        view
        returns (uint256[] memory rewards, uint256 totalBaseReward)
    {
        uint256 epochReward = calculateEpochReward();
        rewards = new uint256[](_poolIds.length);

        if (epochReward == 0 || totalStake == 0) {
            return (rewards, 0);
        }

        for (uint256 i = 0; i < _poolIds.length; i++) {
            bytes32 poolId = _poolIds[i];
            if (this.isValidatorActive(poolId)) {
                uint256 stake = validators[poolId].stakeSnapshot;
                if (stake > 0) {
                    uint256 reward = (epochReward * stake) / totalStake;
                    rewards[i] = reward;
                    totalBaseReward += reward;
                }
            }
        }

        return (rewards, totalBaseReward);
    }

    function rewardValidators(bytes32[] memory _poolIds, uint256[] memory _priorityFees) internal {
        if (!enablePosReward()) {
            return;
        }

        bytes32[] memory totalPoolIds = unionArrays(_poolIds, activePoolIds);

        (uint256[] memory validatorRewards, uint256 totalBaseReward) = getValidatorRewards(totalPoolIds);
        for (uint256 i = 0; i < totalPoolIds.length; i++) {
            bytes32 poolId = totalPoolIds[i];
            uint256 baseReward = validatorRewards[i];
            uint256 feeReward = 0;
            if (i < _priorityFees.length) {
                feeReward = _priorityFees[i];
            }

            uint256 totalReward = baseReward + feeReward;
            address owner = validators[poolId].owner;

            // In V1, rewards go directly to pendingWithdrawStakes
            if (totalReward > 0) {
                pendingWithdrawStakes[owner] += totalReward;
            }

            emit ValidatorReward(poolId, owner, currentEpoch, block.number, baseReward, feeReward, totalReward);
        }

        if (totalBaseReward > 0) {
            increaseTotalSupply(totalBaseReward);
        }
    }

    // V1 doesn't have delegation functions
    // These are stubs for interface compatibility
    function delegate(bytes32) external payable {
        revert("Delegation not supported in V1");
    }

    function undelegate(bytes32) external pure returns (uint256, uint256) {
        revert("Delegation not supported in V1");
    }

    function claimReward(bytes32) external pure returns (uint256) {
        revert("Delegation not supported in V1");
    }

    function compoundRewards(bytes32) external pure {
        revert("Delegation not supported in V1");
    }

    function setCommissionRate(bytes32, uint256) external pure {
        revert("Delegation not supported in V1");
    }

    function setDelegationEnabled(bytes32, bool) external pure {
        revert("Delegation not supported in V1");
    }

    function setDelegationApprover(bytes32, address) external pure {
        revert("Delegation not supported in V1");
    }

    function delegateWithApproval(bytes32, bytes calldata) external payable {
        revert("Delegation not supported in V1");
    }

    function getDelegationApprovalNonce(bytes32, address) external pure returns (uint256) {
        revert("Delegation not supported in V1");
    }

    function getDelegationApprover(bytes32) external pure returns (address) {
        revert("Delegation not supported in V1");
    }

    function getDelegator(bytes32, address) external pure returns (IStaking.Delegator memory) {
        revert("Delegation not supported in V1");
    }

    function getDelegatorReward(bytes32, address) external pure returns (uint256) {
        revert("Delegation not supported in V1");
    }

    function getCommissionRate(bytes32) external pure returns (uint256) {
        revert("Delegation not supported in V1");
    }

    // ==================== Extended Query Interfaces ====================
    // V1 doesn't have delegation, so these return empty/default values for compatibility

    function getValidator(bytes32 _poolId) external view returns (Validator memory validator) {
        return validators[_poolId];
    }

    function getAllValidators() external view returns (bytes32[] memory poolIds) {
        // Combine active, pending add, and pending exit validators
        bytes32[] memory tempPoolIds =
            new bytes32[](activePoolIds.length + pendingAddPoolIds.length + pendingExitPoolIds.length);
        uint256 count = 0;

        // Add active validators
        for (uint256 i = 0; i < activePoolIds.length; i++) {
            tempPoolIds[count] = activePoolIds[i];
            count++;
        }

        // Add pending add validators
        for (uint256 i = 0; i < pendingAddPoolIds.length; i++) {
            bytes32 poolId = pendingAddPoolIds[i];
            if (!isArrayContains(tempPoolIds, poolId)) {
                tempPoolIds[count] = poolId;
                count++;
            }
        }

        // Add pending exit validators
        for (uint256 i = 0; i < pendingExitPoolIds.length; i++) {
            bytes32 poolId = pendingExitPoolIds[i];
            if (!isArrayContains(tempPoolIds, poolId)) {
                tempPoolIds[count] = poolId;
                count++;
            }
        }

        // Create result array with exact size
        poolIds = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            poolIds[i] = tempPoolIds[i];
        }
    }

    function getValidatorCounts()
        external
        view
        returns (uint256 activeCount, uint256 inactiveCount, uint256 pendingExitCount)
    {
        activeCount = activePoolIds.length;
        inactiveCount = pendingAddPoolIds.length;
        pendingExitCount = pendingExitPoolIds.length;
    }

    function getBlockchainInfo()
        external
        view
        returns (uint256 currentEpoch_, uint256 currentBlock_, uint256 totalStake_)
    {
        return (currentEpoch, block.number, totalStake);
    }

    function getUserTotalInfo(address)
        external
        pure
        returns (uint256 totalStake_, uint256 totalRewards_, uint256 totalClaimed_)
    {
        // V1 doesn't have delegation, return 0 for all
        return (0, 0, 0);
    }

    function getUserValidators(address)
        external
        pure
        returns (bytes32[] memory poolIds, uint256[] memory stakes, uint256[] memory rewards)
    {
        // V1 doesn't have delegation, return empty arrays
        poolIds = new bytes32[](0);
        stakes = new uint256[](0);
        rewards = new uint256[](0);
    }

    function getUserPendingUndelegations(address)
        external
        pure
        returns (IStaking.PendingUndelegation[] memory undelegations)
    {
        // V1 doesn't have delegation, return empty array
        undelegations = new IStaking.PendingUndelegation[](0);
    }

    function getValidatorApr(bytes32 _poolId)
        external
        view
        returns (
            uint256 /*apr*/
        )
    {
        require(validators[_poolId].poolId != 0, "Validator does not exist");

        if (totalStake == 0 || validators[_poolId].stakeSnapshot == 0) {
            return 0;
        }

        // Calculate APR based on current inflation rate and validator's share of total stake
        uint256 inflationRate = currentInflationRate; // basis points (e.g., 9125 = 9.125%)
        uint256 validatorShare = (validators[_poolId].stakeSnapshot * 100) / totalStake; // percentage
        uint256 apr = (inflationRate * validatorShare) / 100; // scale to basis points

        return apr;
    }

    function getActiveValidatorCount() external view returns (uint256) {
        return activePoolIds.length;
    }

    function getTotalDelegatorCount() external pure returns (uint256) {
        // V1 doesn't have delegation, return 0
        return 0;
    }
}
