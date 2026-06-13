// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {StakingStorageV4} from "./interfaces/StakingStorageV4.sol";
import {IChainConfig} from "../chainConfig/interfaces/IChainConfig.sol";

contract Staking is
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    StakingStorageV4
{
    // Using statements for EnumerableSet
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

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

    event DelegatorWithdrawClaimed(
        address indexed delegator, bytes32 indexed poolId, uint256 amount, uint256 indexed epochNumber
    );

    event ValidatorRegistered(address indexed validator, bytes32 indexed poolId, uint256 amount);
    event ValidatorUpdated(bytes32 indexed poolId);
    event ValidatorExitRequested(bytes32 indexed poolId);

    event ChainConfigUpdate(address indexed oldChainConfigAddress, address indexed newChainConfigAddress);

    event ErrorOccurred(
        uint256 indexed epochNumber,
        uint256 indexed blockNumber,
        uint256 errorCode,
        address recipient,
        uint256 amount,
        uint256 balance
    );

    event InflationRateAdjusted(uint256 oldRate, uint256 newRate, uint256 timestamp);
    event TotalSupplyIncreased(uint256 indexed epochNumber, uint256 amount, uint256 newTotalSupply);
    event StakeClaimed(address indexed user, uint256 amount);

    error EpochNotCompleted(uint256 lastEpochStart, uint256 epochDuration, uint256 currentTime);

    uint256 public constant INITIAL_TOTAL_SUPPLY = 1000000000 ether;
    uint256 public constant INITIAL_INFLATION_RATE = 9125; // 9.125% annualized inflation expressed in basis points
    uint256 private constant INFLATION_RATE_DENOMINATOR = 100000;
    uint256 private constant DEFAULT_EPOCH_DURATION = 4 hours;
    uint256 private constant YEAR_IN_SECONDS = 365 days;
    uint256 public constant MIN_INFLATION_RATE = 2391;
    uint256 public constant INFLATION_ADJUSTMENT_RATE = 80000;
    uint256 public constant INFLATION_ADJUSTMENT_INTERVAL = 365 days;

    /// @dev EIP-712 type hash for the domain separator
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev EIP-712 type hash for DelegationApproval struct
    bytes32 private constant DELEGATION_APPROVAL_TYPEHASH =
        keccak256("DelegationApproval(bytes32 poolId,address delegator,uint256 nonce)");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // No longer needed - using ERC1967Utils.getImplementation() instead
    }

    function initialize(address adminAddress_, address chainConfigAddress_) external initializer {
        require(adminAddress_ != address(0), "Admin address cannot be zero");
        require(chainConfigAddress_ != address(0), "ChainConfig address cannot be zero");
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        cfg = IChainConfig(chainConfigAddress_);
        _grantRole(DEFAULT_ADMIN_ROLE, adminAddress_);

        totalSupply = INITIAL_TOTAL_SUPPLY;
        currentInflationRate = INITIAL_INFLATION_RATE;
        lastInflationAdjustmentTime = block.timestamp;
        lastInflationTotalSupplySnapshot = INITIAL_TOTAL_SUPPLY;
        lastEpochStartTime = block.timestamp;
    }

    /**
     * @notice Upgrade the contract
     * This function is required by OpenZeppelin's UUPSUpgradeable
     *
     * @param newImplementation                  new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * @notice Migration function to migrate data from V1 arrays to V2 sets
     * @dev This function should be called during upgrade from V1 to V2 via upgradeToAndCall
     *      It copies data from the old arrays to the new EnumerableSet structures
     *      Can only be called once to prevent duplicate migrations
     */
    function migrateV1ToV2() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!v1ToV2Migrated, "Migration already completed");

        // Migrate activePoolIds -> activePoolSets
        for (uint256 i = 0; i < activePoolIds.length; ++i) {
            bytes32 poolId = activePoolIds[i];
            if (!activePoolSets.contains(poolId)) {
                activePoolSets.add(poolId);
            }
        }

        // Migrate pendingAddPoolIds -> pendingAddPoolSets
        for (uint256 i = 0; i < pendingAddPoolIds.length; ++i) {
            bytes32 poolId = pendingAddPoolIds[i];
            if (!pendingAddPoolSets.contains(poolId)) {
                pendingAddPoolSets.add(poolId);
            }
        }

        // Migrate pendingUpdatePoolIds -> pendingUpdatePoolSets
        for (uint256 i = 0; i < pendingUpdatePoolIds.length; ++i) {
            bytes32 poolId = pendingUpdatePoolIds[i];
            if (!pendingUpdatePoolSets.contains(poolId)) {
                pendingUpdatePoolSets.add(poolId);
            }
        }

        // Migrate pendingExitPoolIds -> pendingExitPoolSets
        for (uint256 i = 0; i < pendingExitPoolIds.length; ++i) {
            bytes32 poolId = pendingExitPoolIds[i];
            if (!pendingExitPoolSets.contains(poolId)) {
                pendingExitPoolSets.add(poolId);
            }
        }

        bytes32[] memory allPoolIds = getAllValidators();
        for (uint256 i = 0; i < allPoolIds.length; i++) {
            bytes32 poolId = allPoolIds[i];
            address owner = validators[poolId].owner;

            // Check if validator owner is already a delegator
            Delegator storage ownerDelegator = delegators[poolId][owner];
            if (ownerDelegator.stake == 0 && validators[poolId].totalStake > 0) {
                // Initialize validator owner as a delegator with their stake
                // Use the validator's totalStake as the owner's initial stake
                ownerDelegator.principalStake = validators[poolId].totalStake;
                ownerDelegator.stake = validators[poolId].totalStake;
                ownerDelegator.accumulatedRewardPerShare = accumulatedRewardPerShares[poolId];
                delegatorCounts[poolId]++;
                poolDelegators[poolId].add(owner);
            }
        }

        // Clear the old arrays to free storage and prevent issues
        delete activePoolIds;
        delete pendingAddPoolIds;
        delete pendingUpdatePoolIds;
        delete pendingExitPoolIds;

        // Set migration flag to prevent duplicate migrations
        v1ToV2Migrated = true;
    }

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

    function getEpochDurationMs() internal view returns (uint256) {
        string memory key = "chain.epoch_duration";
        string memory value = getChainCfg(key);
        if (Strings.equal(value, "")) {
            return DEFAULT_EPOCH_DURATION * 1000; // ms
        }
        uint256 duration = uint256(Strings.parseUint(value));
        // Reject configurations with duration < 1000ms (1 second) to avoid rounding issues
        // If duration is 0 or less than 1000ms, use the default value
        if (duration == 0 || duration < 1000) {
            return DEFAULT_EPOCH_DURATION * 1000;
        }
        return duration;
    }

    function getEpochDuration() internal view returns (uint256) {
        uint256 durationMs = getEpochDurationMs();
        // Safe to divide by 1000 since getEpochDurationMs() ensures duration >= 1000ms
        uint256 durationSec = durationMs / 1000;
        if (durationSec == 0) {
            durationSec = 1; // at lease 1s
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
        if (!enablePosReward()) {
            // The time during which the PoS reward is disabled is excluded from the inflation adjustment window
            // refresh lastInflationAdjustmentTime
            lastInflationAdjustmentTime = block.timestamp;
            return;
        }

        if (block.timestamp - lastInflationAdjustmentTime < INFLATION_ADJUSTMENT_INTERVAL) {
            return;
        }

        // Early return if inflation rate is already at minimum
        if (currentInflationRate == MIN_INFLATION_RATE) {
            return;
        }

        uint256 oldRate = currentInflationRate;
        currentInflationRate = (currentInflationRate * INFLATION_ADJUSTMENT_RATE) / INFLATION_RATE_DENOMINATOR;
        if (currentInflationRate < MIN_INFLATION_RATE) {
            currentInflationRate = MIN_INFLATION_RATE;
        }

        lastInflationAdjustmentTime = block.timestamp;
        lastInflationTotalSupplySnapshot = totalSupply;

        // Only update snapshots if rate actually changed
        if (currentInflationRate != oldRate) {
            lastInflationAdjustmentTime = block.timestamp;
            lastInflationTotalSupplySnapshot = totalSupply;
            emit InflationRateAdjusted(oldRate, currentInflationRate, block.timestamp);
        }
    }

    function updateChainConfigAddress(address chainConfigAddress_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(chainConfigAddress_ != address(0), "The new chain config contract address can't be the zero address");
        require(chainConfigAddress_ != address(cfg), "New chain config address is the same as the current address");
        address oldChainConfigAddress = address(cfg);
        cfg = IChainConfig(chainConfigAddress_);
        emit ChainConfigUpdate(oldChainConfigAddress, chainConfigAddress_);
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

    function hexStringToBytes(string memory str) internal pure returns (bytes memory) {
        bytes memory strBytes = bytes(str);

        // Check and strip the '0x' prefix if it exists
        if (strBytes.length >= 2 && strBytes[0] == "0" && strBytes[1] == "x") {
            strBytes = sliceBytes(strBytes, 2, strBytes.length);
        }

        require(strBytes.length % 2 == 0, "Invalid hex string length");

        bytes memory result = new bytes(strBytes.length / 2);

        for (uint256 i = 0; i < result.length; ++i) {
            result[i] = bytes1(_fromHexChar(strBytes[2 * i]) * 16 + _fromHexChar(strBytes[2 * i + 1]));
        }

        return result;
    }

    function sliceBytes(bytes memory data, uint256 start, uint256 end) internal pure returns (bytes memory) {
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; ++i) {
            result[i - start] = data[i];
        }
        return result;
    }

    function _fromHexChar(bytes1 c) internal pure returns (uint8) {
        uint8 charCode = uint8(c);
        if (charCode >= 48 && charCode <= 57) {
            return charCode - 48; // '0'-'9'
        } else if (charCode >= 97 && charCode <= 102) {
            return charCode - 87; // 'a'-'f'
        } else if (charCode >= 65 && charCode <= 70) {
            return charCode - 55; // 'A'-'F'
        } else {
            revert("Invalid hex character");
        }
    }

    function isArrayContains(bytes32[] memory array, bytes32 element) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; ++i) {
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

    function isValidatorActive(bytes32 _poolId) public view override whenNotPaused returns (bool) {
        return activePoolSets.contains(_poolId);
    }

    function isValidatorPendingAdd(bytes32 _poolId) public view override whenNotPaused returns (bool) {
        return pendingAddPoolSets.contains(_poolId);
    }

    function isValidatorPendingUpdate(bytes32 _poolId) public view override whenNotPaused returns (bool) {
        return pendingUpdatePoolSets.contains(_poolId);
    }

    function isValidatorPendingExit(bytes32 _poolId) public view override whenNotPaused returns (bool) {
        return pendingExitPoolSets.contains(_poolId);
    }

    function unionArrays(bytes32[] memory _poolId1, bytes32[] memory _poolId2) public pure returns (bytes32[] memory) {
        // First, count how many unique elements from _poolId2 are not in _poolId1
        uint256 totalCount = _poolId1.length;
        for (uint256 i = 0; i < _poolId2.length; ++i) {
            bytes32 poolId = _poolId2[i];
            if (!isArrayContains(_poolId1, poolId)) {
                totalCount++;
            }
        }

        // Allocate result with exact size needed
        bytes32[] memory result = new bytes32[](totalCount);

        // Copy elements from _poolId1
        for (uint256 i = 0; i < _poolId1.length; ++i) {
            result[i] = _poolId1[i];
        }

        // Add unique elements from _poolId2
        uint256 index = _poolId1.length;
        for (uint256 i = 0; i < _poolId2.length; ++i) {
            bytes32 poolId = _poolId2[i];
            if (!isArrayContains(_poolId1, poolId)) {
                result[index] = poolId;
                index++;
            }
        }

        return result;
    }

    function _transferTo(address recipient, uint256 amount) internal {
        if (amount > address(this).balance) {
            uint256 errorCode = 1;
            emit ErrorOccurred(currentEpoch, block.number, errorCode, recipient, amount, address(this).balance);
            revert("Insufficient contract balance for transfer");
        }

        (bool success,) = recipient.call{value: amount}("");

        if (!success) {
            uint256 errorCode = 2;
            emit ErrorOccurred(currentEpoch, block.number, errorCode, recipient, amount, address(this).balance);
            revert("Transfer failed");
        }
    }

    function registerValidator(
        string memory _description,
        string memory _publicKey,
        string memory _publicKeyPop,
        string memory _blsPublicKey,
        string memory _blsPublicKeyPop,
        string memory _endpoint
    ) external payable override whenNotPaused nonReentrant returns (bytes32) {
        uint256 minRegisterStake = getMinRegistrationStake();
        uint256 maxValidatorStake = getMaxValidatorStake();
        // Require at least the minimum register stake (may be less than the activation threshold)
        require(msg.value >= minRegisterStake, "Insufficient stake");
        require(msg.value <= maxValidatorStake, "Stake too large");

        // Fail-fast check: if the pending-add queue is already full, registering now would be
        // pointless — the validator could never enter the queue even after reaching the stake
        // threshold. Checking here avoids wasted effort from owner and delegators.
        require(isArrayLengthWithinLimit(pendingAddPoolSets.length()), "pendingAddPool exceeds limit");

        bytes memory publicKeyBytes = hexStringToBytes(_publicKey);
        bytes32 poolId = bytes32(sha256((abi.encodePacked(publicKeyBytes))));

        if (validators[poolId].poolId != 0) {
            require(
                validators[poolId].owner == _msgSender(), "PoolId registered by another address: cannot re-register"
            );
            require(
                validators[poolId].status == 0 && validators[poolId].pendingWithdrawStake == 0,
                "Validator has pending withdraw or active status: cannot re-register"
            );
        }

        require(!isValidatorPendingAdd(poolId), "Validator is pending register");
        require(!isValidatorPendingExit(poolId), "Validator is pending exit");
        require(validators[poolId].status == 0, "Validator already registered");

        // Ensure previous withdrawal is completed before re-registration
        Delegator storage prevOwnerDelegator = delegators[poolId][_msgSender()];
        require(!prevOwnerDelegator.isPendingUndelegate, "Must complete previous withdrawal first");

        // keep the `pendingWithdrawStake`, `pendingWithdrawWindow` as the value
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
        commissionRates[poolId] = DEFAULT_COMMISSION_RATE;
        delegationEnabledMapping[poolId] = true;

        // Initialize validator owner as a delegator to participate in delegation rewards
        // This is similar to the logic in delegate(), but without adding to totalStake again
        Delegator storage ownerDelegator = delegators[poolId][_msgSender()];
        _updateDelegatorReward(poolId, _msgSender());

        if (ownerDelegator.stake == 0) {
            // First time staking for this validator
            ownerDelegator.principalStake = msg.value;
            ownerDelegator.accumulatedRewardPerShare = accumulatedRewardPerShares[poolId];
            delegatorCounts[poolId]++;
        } else {
            // Re-registering after exit, accumulate the stake
            ownerDelegator.principalStake += msg.value;
        }
        ownerDelegator.stake += msg.value;

        EnumerableSet.AddressSet storage poolDelegator = poolDelegators[poolId];
        poolDelegator.add(_msgSender());

        // All validators (including those below activation threshold) enter pendingAddPoolSets.
        // _processPendingAdditions only activates those with totalStake >= minValidatorStake;
        // others stay in the queue until delegations push them over the threshold.
        pendingAddPoolSets.add(poolId);

        emit ValidatorRegistered(_msgSender(), poolId, validator.totalStake);
        return poolId;
    }

    function updateValidator(bytes32 _poolId, string memory _description, string memory _endpoint)
        external
        override
        whenNotPaused
    {
        require(validators[_poolId].poolId != 0, "Validator does not exist");
        require(validators[_poolId].owner == _msgSender(), "Caller is not the validator owner");
        // Allow update for active, pendingAdd (includes bootstrapping), validators (not exiting)
        require(isValidatorActive(_poolId) || isValidatorPendingAdd(_poolId), "Validator is not in an updatable state");

        // owner has changed after call update, only update once during one epoch
        require(!isValidatorPendingUpdate(_poolId), "Validator is pending update");

        validators[_poolId].description = _description;
        validators[_poolId].endpoint = _endpoint;

        if (!isValidatorPendingAdd(_poolId) && isValidatorActive(_poolId)) {
            // Active validator: track update for consensus propagation via DomainUpdate event
            // deal 'add' action first in advanceEpoch, no need to update again
            require(isArrayLengthWithinLimit(pendingUpdatePoolSets.length()), "pendingUpdatePool exceeds limit");
            pendingUpdatePoolSets.add(_poolId);
        }
        // For pendingAdd or bootstrapping validators, the metadata is stored directly.
        // It will be propagated when the validator is activated via _processPendingAdditions → _emitDomainUpdate.

        emit ValidatorUpdated(_poolId);
    }

    // place holder — not yet implemented
    function nominateOwner(bytes32 _poolId, address _newOwner) external whenNotPaused {
        revert("Not implemented");
    }

    // place holder — not yet implemented
    function acceptOwnership(bytes32 _poolId) external whenNotPaused {
        revert("Not implemented");
    }

    function exitValidator(bytes32 _poolId) external override whenNotPaused nonReentrant {
        require(validators[_poolId].poolId != 0, "Validator does not exist");
        require(isValidatorActive(_poolId) || isValidatorPendingAdd(_poolId), "Validator status invalid");
        require(!isValidatorPendingExit(_poolId), "Validator is pending exit");
        require(validators[_poolId].owner == _msgSender(), "Caller is not the validator owner");
        require(isArrayLengthWithinLimit(pendingExitPoolSets.length()), "pendingExitPool exceeds limit");

        // remove from pending add queue
        if (isValidatorPendingAdd(_poolId)) {
            pendingAddPoolSets.remove(_poolId);
        }

        // Trigger owner's delegator withdrawal using validator's longer window
        // Other delegators' stakes remain, they can undelegate themselves
        Delegator storage ownerDelegator = delegators[_poolId][_msgSender()];
        require(ownerDelegator.stake > 0, "No stake to withdraw");
        require(!ownerDelegator.isPendingUndelegate, "Already pending undelegate");

        settleReward(_poolId);
        require(ownerDelegator.pendingStake == 0, "owner has pending stake, not allowed to exit");
        uint256 ownerStake = ownerDelegator.stake; // Save before clearing
        uint256 totalAmount = ownerStake + ownerDelegator.rewards;

        // Calculate principal vs rewards
        uint256 principalAmount = ownerDelegator.principalStake;
        uint256 rewardAmount = totalAmount > principalAmount ? totalAmount - principalAmount : 0;

        ownerDelegator.pendingWithdrawStake = totalAmount;
        ownerDelegator.stake = 0;
        ownerDelegator.rewards = 0;
        ownerDelegator.principalStake = 0;
        ownerDelegator.isPendingUndelegate = true;

        // Decrease delegator count since owner's stake is now 0
        delegatorCounts[_poolId]--;

        // Use validator's withdraw window (longer than delegator's)
        uint8 withdrawWindow = getWithdrawEffectiveWindow();
        ownerDelegator.pendingWithdrawWindow = withdrawWindow;

        uint256 unlockEpoch = currentEpoch + withdrawWindow;

        // Store index before pushing
        uint256 undelegationIndex = pendingUndelegations.length;

        pendingUndelegations.push(
            PendingUndelegation({
                delegator: _msgSender(),
                poolId: _poolId,
                amount: totalAmount,
                unlockEpoch: unlockEpoch,
                pendingWithdrawWindow: withdrawWindow,
                processed: false,
                principalAmount: principalAmount,
                rewardAmount: rewardAmount
            })
        );

        // Track index for O(1) user lookup in claimStake
        userUndelegationIndices[_msgSender()].push(undelegationIndex);

        // Record reverse index for O(1) updates during cleanup
        uint256 positionInUserArray = userUndelegationIndices[_msgSender()].length - 1;
        undelegationReverseIndex[undelegationIndex] = positionInUserArray;

        // Update validator state - only subtract owner's stake, other delegators remain
        validators[_poolId].totalStake -= ownerStake;
        validators[_poolId].pendingWithdrawStake = 0; // No longer use validator's pending withdraw
        validators[_poolId].pendingWithdrawWindow = withdrawWindow; // Cast to uint8 for compatibility

        pendingExitPoolSets.add(_poolId);
        emit ValidatorExitRequested(_poolId);
        emit StakeUndelegated(_msgSender(), _poolId, totalAmount, unlockEpoch);
    }

    // addStake removed: use delegate() instead. Owner bypasses delegation/whitelist checks.

    function advanceEpoch() external override whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32[] memory _poolIds = new bytes32[](0);
        uint256[] memory _priorityFees = new uint256[](0);
        _advanceEpoch(_poolIds, _priorityFees);
    }

    function advanceEpoch(bytes32[] memory _poolIds, uint256[] memory _priorityFees)
        external
        override
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _advanceEpoch(_poolIds, _priorityFees);
    }

    function _advanceEpoch(bytes32[] memory _poolIds, uint256[] memory _priorityFees) internal {
        require(_poolIds.length == _priorityFees.length, "PoolId Fees not match");

        uint256 epochDuration = getEpochDuration();
        uint256 requiredTime = lastEpochStartTime + epochDuration;
        if (block.timestamp < requiredTime) {
            revert EpochNotCompleted(lastEpochStartTime, epochDuration, block.timestamp);
        }
        lastEpochStartTime = block.timestamp;

        // STEP 1: Distribute rewards based on current snapshot
        rewardValidators(_poolIds, _priorityFees);

        // STEP 2: Save current RPS as entry point for next epoch's pending stakes
        // This must happen AFTER rewardValidators (RPS updated) and BEFORE updateTotalStake
        uint256 nextEpoch = currentEpoch + 1;
        uint256 length = poolsNeedingRPSRecord.length();
        for (uint256 i = 0; i < length; ++i) {
            bytes32 poolId = poolsNeedingRPSRecord.at(i);
            historicalRPS[nextEpoch][poolId].rps = accumulatedRewardPerShares[poolId];
        }
        poolsNeedingRPSRecord.clear();

        // STEP 3: Process pending operations
        _processPendingAdditions();
        _processPendingExits();
        _processPendingUpdates();
        _processPendingCommissionRates();
        _processWithdrawals();

        // STEP 4: Update epoch and snapshot
        _updateEpoch();

        // Emit epoch change with count instead of full array to avoid unbounded memory copy
        bytes32[] memory poolSet = activePoolSets.values();
        emit EpochChange(currentEpoch, block.number, block.timestamp, totalStake, poolSet);
    }

    function _processPendingAdditions() internal {
        uint256 minValidatorStake = getMinValidatorStake();
        bytes32[] memory toActivate = new bytes32[](pendingAddPoolSets.length());

        // First, collect all poolIds that meet the stake requirement
        uint256 count = 0;
        uint256 length = pendingAddPoolSets.length();
        for (uint256 i = 0; i < length; ++i) {
            bytes32 poolId = pendingAddPoolSets.at(i);
            if (validators[poolId].totalStake >= minValidatorStake) {
                toActivate[count] = poolId;
                count++;
            }
        }

        // Then activate them and remove from pending
        for (uint256 i = 0; i < count; ++i) {
            bytes32 poolId = toActivate[i];
            activePoolSets.add(poolId);
            validators[poolId].status = 1;
            pendingAddPoolSets.remove(poolId);
            _emitDomainUpdate(poolId);
        }
    }

    function _processPendingExits() internal {
        // First pass: collect all poolIds to process
        uint256 minValidatorStake = getMinValidatorStake();
        uint256 length = pendingExitPoolSets.length();
        bytes32[] memory toProcess = new bytes32[](length);
        uint256 count = 0;

        for (uint256 i = 0; i < length; ++i) {
            bytes32 poolId = pendingExitPoolSets.at(i);
            _removeFromActiveIfNeeded(poolId);
            toProcess[count] = poolId;
            count++;
        }

        // Second pass: remove poolIds that meet removal criteria
        for (uint256 i = 0; i < count; ++i) {
            bytes32 poolId = toProcess[i];

            // Determine if we should clean up this entry from pendingExitPoolSets
            bool shouldRemove = false;

            // Always remove if validator is inactive (removed from active)
            if (validators[poolId].status == 0) {
                shouldRemove = true;
            }
            // Remove if total stake dropped below minimum (e.g., all delegators left)
            else if (validators[poolId].totalStake < minValidatorStake) {
                shouldRemove = true;
            }
            // For active validators, check if owner has remaining stake (partial withdrawal scenario)
            else {
                address owner = validators[poolId].owner;
                Delegator storage ownerDelegator = delegators[poolId][owner];
                // If owner has remaining stake (still active), remove from pendingExitPoolSets
                // The pending claim is handled separately through the claimStake mechanism
                if (ownerDelegator.stake > 0) {
                    shouldRemove = true;
                }
            }

            if (shouldRemove) {
                pendingExitPoolSets.remove(poolId);
                // Re-enqueue non-active validators that still have viable owner stake.
                // The owner must retain at least minRegistrationStake; otherwise the validator
                // has no minimum skin-in-game and is not visible in any set.
                if (validators[poolId].status == 0) {
                    address owner = validators[poolId].owner;
                    uint256 ownerStake = delegators[poolId][owner].stake;
                    if (ownerStake >= getMinRegistrationStake()) {
                        // Re-enqueue into pendingAddPoolSets regardless of current totalStake.
                        // _processPendingAdditions will activate when totalStake reaches threshold;
                        // until then the validator is in "bootstrapping" state within pendingAdd.
                        pendingAddPoolSets.add(poolId);
                    }
                }
                // Note: Don't clean up pendingUpdatePoolSets here as the validator might re-register
                // Cleanup will happen in claimStake when owner completes withdrawal
            }
        }
    }

    function _removeFromActiveIfNeeded(bytes32 poolId) internal {
        // Check if owner has any remaining stake
        address owner = validators[poolId].owner;
        Delegator storage ownerDelegator = delegators[poolId][owner];
        bool ownerHasStake = ownerDelegator.stake > 0;

        // Remove from active if:
        // 1. Total stake below minimum, OR
        // 2. Owner has no stake (fully exited), even if total stake >= minimum (due to delegators)
        uint256 minValidatorStake = getMinValidatorStake();
        if ((validators[poolId].totalStake < minValidatorStake || !ownerHasStake) && activePoolSets.contains(poolId)) {
            activePoolSets.remove(poolId);
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
        }
    }

    function _processPendingUpdates() internal {
        // First pass: collect all poolIds to process
        uint256 length = pendingUpdatePoolSets.length();
        bytes32[] memory toRemove = new bytes32[](length);
        uint256 count = 0;

        for (uint256 i = 0; i < length; ++i) {
            bytes32 poolId = pendingUpdatePoolSets.at(i);
            // Only remove from pending if the update was successfully processed (validator was active)
            if (_updateDomainIfActive(poolId)) {
                toRemove[count] = poolId;
                count++;
            }
            // If validator was not active, keep it in pending updates for future processing
            // This prevents state desynchronization between contract and consensus layer
            // and ensures updates aren't lost for validators who might re-register
        }

        // Second pass: remove poolIds that were successfully processed
        for (uint256 i = 0; i < count; ++i) {
            bytes32 poolId = toRemove[i];
            pendingUpdatePoolSets.remove(poolId);
        }
    }

    /**
     * @notice Apply pending commission rate changes that have reached their effective epoch
     */
    function _processPendingCommissionRates() internal {
        uint256 length = pendingCommissionRatePools.length();
        bytes32[] memory toRemove = new bytes32[](length);
        uint256 count = 0;

        for (uint256 i = 0; i < length; ++i) {
            bytes32 poolId = pendingCommissionRatePools.at(i);
            PendingCommissionRate storage pending = pendingCommissionRates[poolId];

            if (pending.effectiveEpoch > 0 && currentEpoch >= pending.effectiveEpoch) {
                uint256 oldRate = commissionRates[poolId];
                commissionRates[poolId] = pending.newRate;
                emit CommissionRateChanged(poolId, oldRate, pending.newRate);

                delete pendingCommissionRates[poolId];
                toRemove[count] = poolId;
                count++;
            }
        }

        for (uint256 i = 0; i < count; ++i) {
            pendingCommissionRatePools.remove(toRemove[i]);
        }
    }

    function _updateDomainIfActive(bytes32 poolId) internal returns (bool) {
        if (activePoolSets.contains(poolId)) {
            emit DomainUpdate(
                poolId,
                validators[poolId].description,
                validators[poolId].publicKey,
                validators[poolId].blsPublicKey,
                validators[poolId].endpoint,
                uint64(block.number + 1),
                validators[poolId].status
            );
            return true; // Successfully processed
        }
        return false; // Not active, not processed
    }

    function _processWithdrawals() internal {
        // Validator withdrawals are now handled through delegator mechanism (lazy)
        // No longer auto-process validator.pendingWithdrawStake
        // Just cleanup processed delegator withdrawals
        _processDelegatorWithdrawals();
    }

    function _processDelegatorWithdrawals() internal {
        // Cleanup processed entries only
        // No need to decrement pendingWithdrawWindow as we check unlockEpoch directly in claimStake()
        uint256 i = 0;
        while (i < pendingUndelegations.length) {
            if (pendingUndelegations[i].processed) {
                uint256 lastIndex = pendingUndelegations.length - 1;

                // Invalidate the processed entry's index in the original delegator's array
                // This prevents double-claim when the same delegator has multiple undelegations
                // Mark as invalid by setting to max value (will be skipped in claimStake due to out-of-bounds)
                address processedDelegator = pendingUndelegations[i].delegator;
                uint256 processedPositionInUserArray = undelegationReverseIndex[i];
                userUndelegationIndices[processedDelegator][processedPositionInUserArray] = type(uint256).max;
                delete undelegationReverseIndex[i];

                // If not removing the last element, update index for the moved element
                if (i != lastIndex) {
                    // Move last element to position i
                    pendingUndelegations[i] = pendingUndelegations[lastIndex];

                    // Update the index mapping for the delegator who owns the moved element
                    address movedDelegator = pendingUndelegations[i].delegator;
                    uint256[] storage userIndices = userUndelegationIndices[movedDelegator];

                    uint256 positionInUserArray = undelegationReverseIndex[lastIndex];
                    userIndices[positionInUserArray] = i;

                    // Update reverse index: lastIndex moved to i
                    undelegationReverseIndex[i] = positionInUserArray;

                    // Delete old reverse index entry
                    delete undelegationReverseIndex[lastIndex];
                }

                // Remove the last element
                pendingUndelegations.pop();
                continue;
            }
            i++;
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
        uint256 length = activePoolSets.length();
        for (uint256 i = 0; i < length; ++i) {
            bytes32 poolId = activePoolSets.at(i);
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

    function getActiveValidators() external view override whenNotPaused returns (bytes32[] memory) {
        return activePoolSets.values();
    }

    function getPoolDelegators(bytes32 _poolId) external view override whenNotPaused returns (address[] memory) {
        return poolDelegators[_poolId].values();
    }

    function getPendingAddValidators() external view override whenNotPaused returns (bytes32[] memory) {
        return pendingAddPoolSets.values();
    }

    function getPendingExitValidators() external view override whenNotPaused returns (bytes32[] memory) {
        return pendingExitPoolSets.values();
    }

    function getPendingUpdateValidators() external view override returns (bytes32[] memory) {
        return pendingUpdatePoolSets.values();
    }

    // Function to slash misbehaving validators (to be implemented)
    function slashValidator(bytes32 _poolId) external override whenNotPaused {
        // Implement slashing logic
    }

    function withdrawStake(bytes32 _poolId, uint256 _withdrawStake) external override whenNotPaused nonReentrant {
        require(validators[_poolId].poolId != 0, "Validator does not exist");
        require(validators[_poolId].owner == _msgSender(), "Caller is not the validator owner");
        require(_withdrawStake > 0, "Withdrawal amount must be greater than zero");

        // Owner can only withdraw their own stake, not other delegators'
        Delegator storage ownerDelegator = delegators[_poolId][_msgSender()];

        // Check if owner has a pending undelegation (from previous withdraw or exit)
        // They cannot start a new withdrawal until the previous one is claimed
        require(!ownerDelegator.isPendingUndelegate, "Already pending undelegate");

        require(!isValidatorPendingExit(_poolId), "Validator is pending exit");
        require(isArrayLengthWithinLimit(pendingExitPoolSets.length()), "pendingExitPool exceeds limit");

        // Settle first to activate any matured pendingStake, then check
        settleReward(_poolId);
        require(ownerDelegator.pendingStake == 0, "owner has pending stake, not allowed to withdraw");
        uint256 ownerStake = ownerDelegator.stake;
        require(ownerStake >= _withdrawStake, "Insufficient owner stake");
        require(validators[_poolId].totalStake >= _withdrawStake, "Insufficient total stake");

        // Owner must either withdraw everything or keep at least minRegistrationStake.
        // This prevents occupying a validator slot at negligible cost after a partial withdrawal.
        uint256 remainingOwnerStake = ownerStake - _withdrawStake;
        require(
            remainingOwnerStake == 0 || remainingOwnerStake >= getMinRegistrationStake(),
            "Must withdraw all or maintain minRegistrationStake"
        );

        // Calculate how much of the withdrawal is principal vs rewards
        uint256 withdrawRatio = (_withdrawStake * PRECISION) / ownerStake;
        uint256 principalAmount = (ownerDelegator.principalStake * withdrawRatio) / PRECISION;
        uint256 withdrawStakeOnly = _withdrawStake;

        // If there are accumulated rewards, proportionally withdraw them too
        uint256 rewardAmount = 0;
        uint256 totalAmount = ownerStake + ownerDelegator.rewards;
        uint256 totalReward =
            totalAmount > ownerDelegator.principalStake ? totalAmount - ownerDelegator.principalStake : 0;
        // Calculate rewardToMint based on totalReward (includes compounded rewards in stake)
        uint256 rewardToMint = (totalReward * withdrawRatio) / PRECISION;
        if (ownerDelegator.rewards > 0) {
            rewardAmount = (ownerDelegator.rewards * withdrawRatio) / PRECISION;
            ownerDelegator.rewards -= rewardAmount;
        }

        uint256 totalWithdrawAmount = withdrawStakeOnly + rewardAmount;

        ownerDelegator.stake -= withdrawStakeOnly;
        ownerDelegator.principalStake -= principalAmount;
        ownerDelegator.pendingWithdrawStake += totalWithdrawAmount;
        ownerDelegator.isPendingUndelegate = true;

        // Decrease delegator count if owner's stake is now 0
        if (ownerDelegator.stake == 0) {
            delegatorCounts[_poolId]--;
        }

        // Use validator's withdraw window
        uint8 withdrawWindow = getWithdrawEffectiveWindow();
        ownerDelegator.pendingWithdrawWindow = withdrawWindow;
        uint256 unlockEpoch = currentEpoch + withdrawWindow;

        // Store index before pushing
        uint256 undelegationIndex = pendingUndelegations.length;

        pendingUndelegations.push(
            PendingUndelegation({
                delegator: _msgSender(),
                poolId: _poolId,
                amount: totalWithdrawAmount,
                unlockEpoch: unlockEpoch,
                pendingWithdrawWindow: withdrawWindow,
                processed: false,
                principalAmount: principalAmount,
                rewardAmount: rewardToMint
            })
        );

        // Track index for O(1) user lookup in claimStake
        userUndelegationIndices[_msgSender()].push(undelegationIndex);

        // Record reverse index for O(1) updates during cleanup
        uint256 positionInUserArray = userUndelegationIndices[_msgSender()].length - 1;
        undelegationReverseIndex[undelegationIndex] = positionInUserArray;

        validators[_poolId].totalStake -= _withdrawStake;
        validators[_poolId].pendingWithdrawStake = 0; // No longer use validator's pending withdraw
        validators[_poolId].pendingWithdrawWindow = withdrawWindow; // Cast to uint8 for compatibility

        // Remove from pendingAdd when totalStake reaches zero (no viable stake left).
        if (validators[_poolId].totalStake == 0) {
            pendingAddPoolSets.remove(_poolId);
        }
        // If the owner fully exits (stake → 0) but non-owner delegators still have stake,
        // the owner no longer meets the minimum skin-in-game requirement. Remove from
        // pendingAdd so the validator doesn't linger as an ownerless bootstrapping entry.
        else if (ownerDelegator.stake == 0 && isValidatorPendingAdd(_poolId)) {
            pendingAddPoolSets.remove(_poolId);
        }

        // Add to pendingExit only when exit is genuinely needed:
        //   - Owner fully exited (stake == 0): cleanup regardless of validator state.
        //   - Active validator dropped below activation threshold: must signal consensus layer.
        // Active validators doing a partial withdrawal that keeps them healthy
        // (totalStake >= min, ownerStake >= minRegistrationStake) do NOT enter pendingExit —
        // there is no need for consensus notification and no state cleanup required.
        // Non-active validators (pendingAdd / bootstrapping) where owner retains stake also
        // stay in pendingAddPoolSets without entering pendingExit.
        if (
            ownerDelegator.stake == 0
                || (isValidatorActive(_poolId) && validators[_poolId].totalStake < getMinValidatorStake())
        ) {
            pendingExitPoolSets.add(_poolId);
            emit ValidatorExitRequested(_poolId);
        }

        emit StakeUndelegated(_msgSender(), _poolId, totalWithdrawAmount, unlockEpoch);
    }

    function getMinValidatorStake() internal view returns (uint256) {
        string memory key = "staking.min_staking_pool_value";
        string memory value = getChainCfg(key);
        if (Strings.equal(value, "")) {
            return MIN_POOL_STAKE;
        }
        return uint256(Strings.parseUint(value));
    }

    function getMinRegistrationStake() internal view returns (uint256) {
        string memory key = "staking.min_staking_registration_value";
        string memory value = getChainCfg(key);
        if (Strings.equal(value, "")) {
            return MIN_REGISTRATION_STAKE;
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

    function getCommissionRateDelay() internal view returns (uint256) {
        string memory key = "staking.commission_rate_delay";
        string memory value = getChainCfg(key);
        if (Strings.equal(value, "")) {
            return DEFAULT_COMMISSION_RATE_DELAY;
        }
        return uint256(Strings.parseUint(value));
    }

    function enablePosReward() internal view returns (bool) {
        string memory key = "chain.enable_pos_staking";
        string memory value = getChainCfg(key);
        if (Strings.equal(value, "true") || Strings.equal(value, "True") || Strings.equal(value, "")) {
            return true; // default enable
        }

        if (Strings.equal(value, "false") || Strings.equal(value, "False")) {
            return false;
        }

        // default enable
        return true;
    }

    function claimStake(bytes32 _poolId) external nonReentrant {
        uint256 totalClaimed = 0;

        // Use indexed mapping for O(k) lookup instead of O(n) where k = user's undelegations
        uint256[] memory indices = userUndelegationIndices[msg.sender];
        uint256 head = userUndelegationHead[msg.sender];

        // Iterate only through this user's undelegations starting from head position
        for (uint256 i = head; i < indices.length; ++i) {
            uint256 idx = indices[i];

            // Skip invalidated indices (marked as max value during cleanup)
            if (idx == type(uint256).max || idx >= pendingUndelegations.length) {
                continue;
            }

            PendingUndelegation storage pending = pendingUndelegations[idx];

            // Skip if processed, wrong pool, or not yet unlocked
            if (pending.processed || pending.poolId != _poolId) {
                continue;
            }

            // Additional safety check: verify this entry actually belongs to the caller
            // This prevents claiming entries that were swapped from other delegators
            if (pending.delegator != msg.sender) {
                continue;
            }

            // Check if unlocked - break early since entries are ordered by time
            if (currentEpoch < pending.unlockEpoch) {
                break;
            }

            Delegator storage delegator = delegators[_poolId][msg.sender];

            // Verify the delegator state is consistent
            if (delegator.isPendingUndelegate && delegator.pendingWithdrawStake >= pending.amount) {
                // Transfer principal from contract balance
                if (pending.principalAmount > 0) {
                    _transferTo(msg.sender, pending.principalAmount);
                }

                delegator.pendingWithdrawStake -= pending.amount;

                if (delegator.pendingWithdrawStake == 0) {
                    delegator.isPendingUndelegate = false;
                    delegator.pendingWithdrawWindow = 0;
                }

                // Emit CoinMinted for rewards that need to be minted by client
                if (pending.rewardAmount > 0) {
                    emit CoinMinted(msg.sender, 1, pending.rewardAmount);
                }

                pending.processed = true;
                totalClaimed += pending.amount;
                EnumerableSet.AddressSet storage poolDelegator = poolDelegators[_poolId];
                if (delegator.stake == 0 && !delegator.isPendingUndelegate) {
                    poolDelegator.remove(msg.sender);
                }
                emit DelegatorWithdrawClaimed(msg.sender, _poolId, pending.amount, currentEpoch);
            }
        }

        // Update head to skip processed entries (can't use i from loop as it may have early break)
        uint256 newHead = head;
        for (uint256 i = head; i < indices.length; ++i) {
            uint256 idx = indices[i];
            // Skip invalidated indices or out-of-bounds
            if (idx == type(uint256).max || idx >= pendingUndelegations.length) {
                newHead = i + 1;
                continue;
            }
            // Skip entries that don't belong to this user (swapped from others)
            // Do NOT advance head past these — they will be cleaned up by _processDelegatorWithdrawals
            if (pendingUndelegations[idx].delegator != msg.sender) {
                continue; // Stop advancing head; valid user entries may follow
            }
            if (!pendingUndelegations[idx].processed) {
                break; // Found first unprocessed entry
            }
            newHead = i + 1;
        }
        userUndelegationHead[msg.sender] = newHead;

        require(totalClaimed > 0, "No withdrawable stake");
        emit StakeClaimed(msg.sender, totalClaimed);

        // Clean up orphaned pending updates after validator owner completes withdrawal
        // This prevents accumulation of orphaned entries when validators never re-register
        if (validators[_poolId].poolId != 0 && validators[_poolId].owner == msg.sender) {
            _cleanupOrphanedPendingUpdate(_poolId);
        }
    }

    /// @notice Clean up orphaned pending updates for validators who won't re-register
    /// @param poolId The validator's pool ID
    function _cleanupOrphanedPendingUpdate(bytes32 poolId) internal {
        // Only clean up if:
        // 1. Validator exists
        // 2. Not in pendingAddPoolSets (not waiting to be activated)
        // 3. Not in pendingExitPoolSets (not in the middle of exiting)
        // 4. Not in activePoolSets (not currently active)
        // 5. Total stake below MIN_POOL_STAKE (can't be activated)
        // 6. Status is 0 (inactive)
        bool isInPendingAdd = pendingAddPoolSets.contains(poolId);
        bool isInPendingExit = pendingExitPoolSets.contains(poolId);
        bool isActive = activePoolSets.contains(poolId);
        bool isBelowMinStake = validators[poolId].totalStake < getMinValidatorStake();
        bool isInactive = validators[poolId].status == 0;

        if (!isInPendingAdd && !isInPendingExit && !isActive && isBelowMinStake && isInactive) {
            if (pendingUpdatePoolSets.contains(poolId)) {
                pendingUpdatePoolSets.remove(poolId);
            }
        }
    }

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
        uint256 window;
        if (Strings.equal(value, "")) {
            // Use default value if configuration is not set
            window = DEFAULT_WITHDRAW_WINDOW;
        } else {
            window = Strings.parseUint(value);
        }

        // Ensure window is non-zero to prevent immediate withdrawal
        require(window > 0, "Withdraw window must be greater than 0");

        // Use SafeCast to prevent silent truncation
        uint8 windowUint8 = SafeCast.toUint8(window);

        return windowUint8;
    }

    function getChainCfg(string memory key) internal view returns (string memory) {
        return cfg.getConfig(key);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256(bytes("PharosStaking")), keccak256(bytes("1")), block.chainid, address(this)
            )
        );
    }

    function _computeApprovalDigest(bytes32 _poolId, address _delegator, uint256 _nonce)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparator(),
                keccak256(abi.encode(DELEGATION_APPROVAL_TYPEHASH, _poolId, _delegator, _nonce))
            )
        );
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

        if (epochReward == 0 || totalStake == 0) {
            return (new uint256[](0), 0);
        }

        rewards = new uint256[](_poolIds.length);

        for (uint256 i = 0; i < _poolIds.length; ++i) {
            bytes32 poolId = _poolIds[i];
            if (isValidatorActive(poolId)) {
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

        bytes32[] memory totalPoolIds = unionArrays(_poolIds, activePoolSets.values());

        (uint256[] memory validatorRewards, uint256 totalBaseReward) = getValidatorRewards(totalPoolIds);
        for (uint256 i = 0; i < totalPoolIds.length; ++i) {
            bytes32 poolId = totalPoolIds[i];
            uint256 baseReward = validatorRewards.length > 0 ? validatorRewards[i] : 0;
            uint256 feeReward = 0;
            // Only distribute priority fees to active validators
            // Bootstrapping validators (not in active set) should not receive any rewards
            if (i < _priorityFees.length && isValidatorActive(poolId)) {
                feeReward = _priorityFees[i];
            }

            uint256 totalReward = baseReward + feeReward;
            address owner = validators[poolId].owner;
            if (totalReward > 0) {
                uint256 commission = (totalReward * commissionRates[poolId]) / COMMISSION_SCALE;
                uint256 delegationReward = totalReward - commission;

                // Skip reward distribution if stakeSnapshot is zero (prevents division by zero)
                // This can happen for non-active validators that have priority fees but no stake
                if (validators[poolId].stakeSnapshot > 0) {
                    uint256 rewardPerShare = (delegationReward * PRECISION) / validators[poolId].stakeSnapshot;
                    accumulatedRewardPerShares[poolId] += rewardPerShare;
                }
                // Always credit commission to validator owner, even if stakeSnapshot is zero
                delegators[poolId][owner].rewards += commission;
            }

            emit ValidatorReward(poolId, owner, currentEpoch, block.number, baseReward, feeReward, totalReward);
        }

        if (totalBaseReward > 0) {
            increaseTotalSupply(totalBaseReward);
        }
    }

    function settleReward(bytes32 _poolId) public override whenNotPaused {
        _settleRewardFor(_poolId, _msgSender());
    }

    function _settleRewardFor(bytes32 _poolId, address _delegator) internal {
        // STEP 1: Try to activate pending stake (lazy activation)
        _tryActivatePending(_poolId, _delegator);

        // STEP 2: Settle rewards for active stake
        _updateDelegatorReward(_poolId, _delegator);
    }

    function _tryActivatePending(bytes32 _poolId, address _delegator) internal {
        Delegator storage delegator = delegators[_poolId][_delegator];

        // Early return if nothing to activate
        if (delegator.pendingStake == 0) {
            return;
        }

        uint256 activationEpoch = pendingActivationEpoch[_poolId][_delegator];

        // Early return if not yet time to activate
        if (currentEpoch < activationEpoch) {
            return;
        }

        // Conditions met, proceed with activation
        _activatePendingStake(_poolId, _delegator);
    }

    function delegate(bytes32 _poolId) external payable override whenNotPaused nonReentrant {
        // Owner always bypasses delegation enabled and approver checks
        bool isOwner = (validators[_poolId].owner == _msgSender());
        if (!isOwner) {
            require(delegationEnabledMapping[_poolId], "Delegation disabled");
            require(delegationApprover[_poolId] == address(0), "Approval required: use delegateWithApproval");
        }
        _delegate(_poolId);
    }

    function delegateWithApproval(bytes32 _poolId, bytes calldata _signature)
        external
        payable
        override
        whenNotPaused
        nonReentrant
    {
        require(delegationEnabledMapping[_poolId], "Delegation disabled");
        address approver = delegationApprover[_poolId];
        require(approver != address(0), "Approval mode not enabled");

        uint256 nonce = delegationApprovalNonces[_poolId][_msgSender()];
        bytes32 digest = _computeApprovalDigest(_poolId, _msgSender(), nonce);
        require(ECDSA.recover(digest, _signature) == approver, "Invalid approval signature");

        delegationApprovalNonces[_poolId][_msgSender()] = nonce + 1;
        _delegate(_poolId);
    }

    function _delegate(bytes32 _poolId) internal {
        Validator storage validator = validators[_poolId];
        require(validator.poolId != 0, "Validator does not exist");

        bool isOwner = (validator.owner == _msgSender());

        if (!isOwner) {
            // Non-owner delegators can stake to active or pendingAdd validators.
            // pendingAdd covers both activation-ready and bootstrapping validators
            // (those below threshold but seeking delegations to activate).
            require(!isValidatorPendingExit(_poolId), "Validator is pending exit");
            require(isValidatorActive(_poolId) || isValidatorPendingAdd(_poolId), "Validator status invalid");
        }
        // Owner: no upfront status check here; the isPendingUndelegate guard below handles the
        // common case (exitValidator sets isPendingUndelegate=true on the owner).

        uint256 maxValidatorStake = getMaxValidatorStake();
        uint256 currentStake = validator.totalStake;

        // If already at max, reject additional stake
        require(currentStake < maxValidatorStake, "Pool stake already at maximum");

        uint256 minDelegatorStake = getMinDelegatorStake();

        // Calculate how much we can actually add (up to max)
        uint256 remainingSpace = maxValidatorStake - currentStake;
        uint256 amountToAdd = msg.value;

        // If msg.value would exceed max, cap it and refund the excess
        if (msg.value > remainingSpace) {
            amountToAdd = remainingSpace;
        }

        // Require at least minDelegatorStake, unless adding exact remaining amount
        require(amountToAdd >= minDelegatorStake || amountToAdd == remainingSpace, "Insufficient stake");

        // Refund any excess ETH
        if (msg.value > amountToAdd) {
            _transferTo(_msgSender(), msg.value - amountToAdd);
        }

        Delegator storage delegator = delegators[_poolId][_msgSender()];

        // Ensure no conflicting pending state
        require(!delegator.isPendingUndelegate, "Cannot delegate while pending undelegate");

        // STEP 1-2: Activate pending stake (if ready) and settle rewards
        settleReward(_poolId);

        // After settleReward, pendingStake may have been activated; check again
        require(delegator.pendingStake == 0, "Cannot delegate while pending stake exists");

        // STEP 3: Add new stake as pending (will activate next epoch)
        bool isNewDelegator = (delegator.stake == 0 && delegator.pendingStake == 0);

        if (isNewDelegator) {
            // New delegator: will be initialized when pending activates
            delegator.accumulatedRewardPerShare = 0; // Will be set properly at activation
            delegatorCounts[_poolId]++;
        }

        bool isNewPending = (delegator.pendingStake == 0);

        delegator.pendingStake += amountToAdd;
        delegator.principalStake += amountToAdd;
        pendingActivationEpoch[_poolId][_msgSender()] = currentEpoch + 1;

        // STEP 4: Update validator totalStake (for next epoch's snapshot)
        validator.totalStake = currentStake + amountToAdd;

        // STEP 4a: Re-enter pendingAdd if the validator has left all sets (e.g. owner
        // re-delegates after a full exit+claim). Active and pendingAdd validators are
        // already in their correct sets; non-owner delegators can only reach active or
        // pendingAdd validators via the require check above, so this only fires for the
        // owner re-staking to a "stranded" (set-less) validator.
        if (!isValidatorActive(_poolId) && !isValidatorPendingAdd(_poolId) && !isValidatorPendingExit(_poolId)) {
            // Guard: owner must commit at least minRegistrationStake to re-enter pendingAdd.
            // STEP 4a is only reachable by the owner (non-owners are blocked by the status
            // check above). Use validator.owner explicitly for clarity.
            Delegator storage ownerDelegator = delegators[_poolId][validator.owner];
            require(
                ownerDelegator.stake + ownerDelegator.pendingStake >= getMinRegistrationStake(),
                "Owner stake below minRegistrationStake"
            );
            require(isArrayLengthWithinLimit(pendingAddPoolSets.length()), "pendingAddPool exceeds limit");
            pendingAddPoolSets.add(_poolId);
        }

        // STEP 5: Reserve historical RPS slot (increment refcount)
        if (isNewPending) {
            historicalRPS[currentEpoch + 1][_poolId].refcount++;
            poolsNeedingRPSRecord.add(_poolId);
        }
        EnumerableSet.AddressSet storage poolDelegator = poolDelegators[_poolId];
        if (!poolDelegator.contains(_msgSender())) {
            poolDelegator.add(_msgSender());
        }
        emit StakeDelegated(_msgSender(), _poolId, amountToAdd, currentEpoch + 1);
    }

    function undelegate(bytes32 _poolId)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 amount, uint256 unlockEpoch)
    {
        Validator storage validator = validators[_poolId];
        require(validator.poolId != 0, "Validator does not exist");
        Delegator storage delegator = delegators[_poolId][_msgSender()];

        settleReward(_poolId);

        require(delegator.pendingStake == 0, "delegator has pending stake, not allowed to undelegate");

        // Prevent validator owner from using both undelegate and exitValidator
        require(validator.owner != _msgSender(), "Use exitValidator/withdrawStake instead");

        // Check after activation
        require(delegator.stake > 0, "No stake to undelegate");
        require(!delegator.isPendingUndelegate, "Already pending undelegate");

        uint256 totalAmount = delegator.stake + delegator.rewards;

        // Calculate principal (real deposits) vs rewards
        uint256 principalAmount = delegator.principalStake;
        uint256 rewardAmount = totalAmount > principalAmount ? totalAmount - principalAmount : 0;

        uint256 stakeBeforeUndelegate = delegator.stake;

        delegator.pendingWithdrawStake = totalAmount;
        uint256 withdrawWindow = getDelegationWithdrawWindow();
        delegator.pendingWithdrawWindow = withdrawWindow;
        delegator.isPendingUndelegate = true;
        delegator.stake = 0;
        delegator.rewards = 0;
        delegator.principalStake = 0; // Clear real deposit tracking

        // Decrease delegator count since stake is now 0
        delegatorCounts[_poolId]--;

        // Update validator.totalStake by the actual stake amount
        validator.totalStake -= stakeBeforeUndelegate;

        // Remove from pending add queue if total stake reaches zero (no viable stake left)
        if (validators[_poolId].totalStake == 0) {
            pendingAddPoolSets.remove(_poolId);
        }

        // Add to pending exit if total stake falls below minimum (for active validators)
        // This ensures the consensus layer is notified via DomainUpdate event
        if (isValidatorActive(_poolId) && validators[_poolId].totalStake < getMinValidatorStake()) {
            require(isArrayLengthWithinLimit(pendingExitPoolSets.length()), "pendingExitPool exceeds limit");
            pendingExitPoolSets.add(_poolId);
            emit ValidatorExitRequested(_poolId);
        }

        unlockEpoch = currentEpoch + withdrawWindow;
        amount = totalAmount;

        // Store index before pushing
        uint256 undelegationIndex = pendingUndelegations.length;

        pendingUndelegations.push(
            PendingUndelegation({
                delegator: _msgSender(),
                poolId: _poolId,
                amount: amount,
                unlockEpoch: unlockEpoch,
                pendingWithdrawWindow: withdrawWindow,
                processed: false,
                principalAmount: principalAmount,
                rewardAmount: rewardAmount
            })
        );

        // Track index for O(1) user lookup in claimStake
        userUndelegationIndices[_msgSender()].push(undelegationIndex);

        // Record reverse index for O(1) updates during cleanup
        uint256 positionInUserArray = userUndelegationIndices[_msgSender()].length - 1;
        undelegationReverseIndex[undelegationIndex] = positionInUserArray;

        emit StakeUndelegated(_msgSender(), _poolId, amount, unlockEpoch);
        return (amount, unlockEpoch);
    }

    function claimReward(bytes32 _poolId) external override whenNotPaused nonReentrant returns (uint256) {
        Delegator storage delegator = delegators[_poolId][_msgSender()];

        settleReward(_poolId);
        uint256 amount = delegator.rewards;
        require(amount > 0, "No rewards to claim");

        delegator.rewards = 0;
        delegator.totalRewardsClaimed += amount;

        emit RewardClaimed(_msgSender(), _poolId, amount);
        emit CoinMinted(_msgSender(), 1, amount);

        return amount;
    }

    function compoundRewards(bytes32 _poolId) external override whenNotPaused nonReentrant {
        Validator storage validator = validators[_poolId];
        require(validator.poolId != 0, "Validator does not exist");
        Delegator storage delegator = delegators[_poolId][_msgSender()];

        // STEP 1-2: Activate pending stake (if ready) and settle rewards
        settleReward(_poolId);
        require(delegator.rewards > 0, "No rewards to compound");
        require(!delegator.isPendingUndelegate, "Cannot compound while pending undelegate");
        require(delegator.pendingStake == 0, "Cannot compound while pending stake exist");

        uint256 amount = delegator.rewards;
        delegator.rewards = 0;

        // STEP 3: Add rewards as pending stake (will activate next epoch)
        bool isNewPending = (delegator.pendingStake == 0);

        delegator.pendingStake += amount;
        // NOTE: We do NOT update principalStake here. Compounded rewards are virtual tokens
        // that increase stake but are not real deposits. principalStake tracks only actual deposits.
        pendingActivationEpoch[_poolId][_msgSender()] = currentEpoch + 1;

        // STEP 4: Update validator totalStake (for next epoch's snapshot)
        validator.totalStake += amount;

        // STEP 5: Reserve historical RPS slot (increment refcount if needed)
        if (isNewPending) {
            historicalRPS[currentEpoch + 1][_poolId].refcount++;
            poolsNeedingRPSRecord.add(_poolId);
        }

        emit RewardsCompounded(_msgSender(), _poolId, amount);
    }

    function setCommissionRate(bytes32 _poolId, uint256 _newRate) external override whenNotPaused {
        Validator memory validator = validators[_poolId];
        require(validator.poolId != 0, "Validator does not exist");
        require(validator.owner == _msgSender(), "Not validator owner");
        require(_newRate <= MAX_COMMISSION_RATE, "Rate exceeds maximum allowed");
        require(pendingCommissionRates[_poolId].effectiveEpoch == 0, "Already has pending change");

        uint256 effectiveEpoch = currentEpoch + getCommissionRateDelay();
        pendingCommissionRates[_poolId] = PendingCommissionRate({newRate: _newRate, effectiveEpoch: effectiveEpoch});
        pendingCommissionRatePools.add(_poolId);

        emit CommissionRateChangeRequested(_poolId, commissionRates[_poolId], _newRate, effectiveEpoch);
    }

    function setDelegationEnabled(bytes32 _poolId, bool _enabled) external override whenNotPaused {
        Validator memory validator = validators[_poolId];
        require(validator.poolId != 0, "Validator does not exist");
        require(validator.owner == _msgSender(), "Not validator owner");
        delegationEnabledMapping[_poolId] = _enabled;
    }

    function setDelegationApprover(bytes32 _poolId, address _approver) external override whenNotPaused {
        require(validators[_poolId].poolId != 0, "Validator does not exist");
        address owner = validators[_poolId].owner;
        address currentApprover = delegationApprover[_poolId];
        require(
            _msgSender() == owner || _msgSender() == currentApprover,
            "Not authorized: must be owner or current approver"
        );
        // Only owner can clear approver (set to address(0)) to prevent approver from
        // unilaterally disabling KYC/approval mode
        if (_approver == address(0)) {
            require(_msgSender() == owner, "Only owner can clear approver");
        }
        delegationApprover[_poolId] = _approver;
        emit DelegationApproverChanged(_poolId, _approver);
    }

    function getDelegationApprovalNonce(bytes32 _poolId, address _delegator) external view override returns (uint256) {
        return delegationApprovalNonces[_poolId][_delegator];
    }

    function getDelegationApprover(bytes32 _poolId) external view override returns (address) {
        return delegationApprover[_poolId];
    }

    function getDelegator(bytes32 _poolId, address _delegator) external view override returns (Delegator memory) {
        return delegators[_poolId][_delegator];
    }

    function getPendingStakeInfo(bytes32 _poolId, address _delegator)
        external
        view
        returns (uint256 pendingAmount, uint256 activationEpoch, bool canActivateNow)
    {
        Delegator memory delegator = delegators[_poolId][_delegator];
        pendingAmount = delegator.pendingStake;
        activationEpoch = pendingActivationEpoch[_poolId][_delegator];
        canActivateNow = (pendingAmount > 0 && currentEpoch >= activationEpoch);
    }

    function hasPendingActivation(bytes32 _poolId, address _delegator) external view returns (bool) {
        Delegator memory delegator = delegators[_poolId][_delegator];
        if (delegator.pendingStake == 0) return false;
        return currentEpoch >= pendingActivationEpoch[_poolId][_delegator];
    }

    function getHistoricalRPS(uint256 _epoch, bytes32 _poolId) external view returns (uint256 rps, uint256 refcount) {
        EpochRPS memory data = historicalRPS[_epoch][_poolId];
        return (data.rps, data.refcount);
    }

    function getHistoricalRPSBatch(uint256 _epoch, bytes32[] calldata _poolIds)
        external
        view
        returns (uint256[] memory rpsValues, uint256[] memory refcounts)
    {
        uint256 length = _poolIds.length;
        rpsValues = new uint256[](length);
        refcounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            EpochRPS memory data = historicalRPS[_epoch][_poolIds[i]];
            rpsValues[i] = data.rps;
            refcounts[i] = data.refcount;
        }
    }

    function getDelegatorReward(bytes32 _poolId, address _delegator) public view override returns (uint256) {
        Delegator memory delegator = delegators[_poolId][_delegator];

        uint256 currentRps = accumulatedRewardPerShares[_poolId];
        uint256 lastRps = delegator.accumulatedRewardPerShare;

        uint256 unclaimed = delegator.rewards;
        if (currentRps > lastRps && delegator.stake > 0) {
            uint256 delta = currentRps - lastRps;
            unclaimed += (delta * delegator.stake) / PRECISION;
        }

        return unclaimed;
    }

    // ==================== Extended Query Interfaces ====================

    function getValidator(bytes32 _poolId) external view override returns (Validator memory validator) {
        return validators[_poolId];
    }

    function getAllValidators() public view override returns (bytes32[] memory poolIds) {
        // Combine active, pending add, and pending exit validators using Sets
        bytes32[] memory activePools = activePoolSets.values();
        bytes32[] memory pendingAddPools = pendingAddPoolSets.values();
        bytes32[] memory pendingExitPools = pendingExitPoolSets.values();

        // First, count unique elements
        uint256 count = activePools.length;
        for (uint256 i = 0; i < pendingAddPools.length; ++i) {
            bytes32 poolId = pendingAddPools[i];
            if (!activePoolSets.contains(poolId) && !pendingExitPoolSets.contains(poolId)) {
                count++;
            }
        }
        for (uint256 i = 0; i < pendingExitPools.length; ++i) {
            bytes32 poolId = pendingExitPools[i];
            if (!activePoolSets.contains(poolId) && !pendingAddPoolSets.contains(poolId)) {
                count++;
            }
        }

        // Allocate result with exact size
        poolIds = new bytes32[](count);
        uint256 index = 0;

        // Add active validators (no duplicates possible within a set)
        for (uint256 i = 0; i < activePools.length; ++i) {
            poolIds[index] = activePools[i];
            index++;
        }

        // Add pending add validators (O(1) duplicate check using contains())
        for (uint256 i = 0; i < pendingAddPools.length; ++i) {
            bytes32 poolId = pendingAddPools[i];
            // Use O(1) contains() from EnumerableSet instead of O(n) isArrayContains
            if (!activePoolSets.contains(poolId) && !pendingExitPoolSets.contains(poolId)) {
                poolIds[index] = poolId;
                index++;
            }
        }

        // Add pending exit validators (O(1) duplicate check)
        for (uint256 i = 0; i < pendingExitPools.length; ++i) {
            bytes32 poolId = pendingExitPools[i];
            if (!activePoolSets.contains(poolId) && !pendingAddPoolSets.contains(poolId)) {
                poolIds[index] = poolId;
                index++;
            }
        }
    }

    function getValidatorCounts()
        external
        view
        override
        returns (uint256 activeCount, uint256 inactiveCount, uint256 pendingExitCount)
    {
        activeCount = activePoolSets.length();
        inactiveCount = pendingAddPoolSets.length();
        pendingExitCount = pendingExitPoolSets.length();
    }

    /// @notice Returns validators in bootstrapping state (in pendingAdd but below activation threshold).
    /// @dev These validators are seeking delegations to reach minValidatorStake and activate.
    function getBootstrappingValidators() external view whenNotPaused returns (bytes32[] memory) {
        uint256 minValidatorStake = getMinValidatorStake();
        bytes32[] memory pending = pendingAddPoolSets.values();
        uint256 count = 0;
        for (uint256 i = 0; i < pending.length; ++i) {
            if (validators[pending[i]].totalStake < minValidatorStake) count++;
        }
        bytes32[] memory result = new bytes32[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < pending.length; ++i) {
            if (validators[pending[i]].totalStake < minValidatorStake) {
                result[idx++] = pending[i];
            }
        }
        return result;
    }

    /// @notice Returns true if the validator is in bootstrapping state
    ///         (in pendingAdd but totalStake below activation threshold).
    function isValidatorBootstrapping(bytes32 _poolId) public view whenNotPaused returns (bool) {
        return isValidatorPendingAdd(_poolId) && validators[_poolId].totalStake < getMinValidatorStake();
    }

    function getBlockchainInfo()
        external
        view
        override
        returns (uint256 currentEpoch_, uint256 currentBlock_, uint256 totalStake_)
    {
        return (currentEpoch, block.number, totalStake);
    }

    function getUserTotalInfo(address _delegator)
        external
        view
        override
        returns (uint256 totalStake_, uint256 totalRewards_, uint256 totalClaimed_)
    {
        bytes32[] memory activePools = activePoolSets.values();
        for (uint256 i = 0; i < activePools.length; ++i) {
            bytes32 poolId = activePools[i];
            Delegator memory delegator = delegators[poolId][_delegator];

            if (delegator.stake > 0 || delegator.rewards > 0) {
                totalStake_ += delegator.stake;
                totalRewards_ += getDelegatorReward(poolId, _delegator);
                totalClaimed_ += delegator.totalRewardsClaimed;
            }
        }
    }

    function getUserValidators(address _delegator)
        external
        view
        override
        returns (bytes32[] memory poolIds, uint256[] memory stakes, uint256[] memory rewards)
    {
        bytes32[] memory activePools = activePoolSets.values();

        // First count how many validators the user has stakes in
        uint256 count = 0;
        for (uint256 i = 0; i < activePools.length; ++i) {
            bytes32 poolId = activePools[i];
            Delegator memory delegator = delegators[poolId][_delegator];
            if (delegator.stake > 0 || delegator.rewards > 0) {
                count++;
            }
        }

        // Allocate arrays
        poolIds = new bytes32[](count);
        stakes = new uint256[](count);
        rewards = new uint256[](count);

        // Fill arrays
        uint256 index = 0;
        for (uint256 i = 0; i < activePools.length; ++i) {
            bytes32 poolId = activePools[i];
            Delegator memory delegator = delegators[poolId][_delegator];
            if (delegator.stake > 0 || delegator.rewards > 0) {
                poolIds[index] = poolId;
                stakes[index] = delegator.stake;
                rewards[index] = getDelegatorReward(poolId, _delegator);
                index++;
            }
        }
    }

    function getUserPendingUndelegations(address _delegator)
        external
        view
        override
        returns (PendingUndelegation[] memory undelegations)
    {
        // Use indexed mapping for O(k) lookup instead of O(2n) double iteration
        uint256[] memory indices = userUndelegationIndices[_delegator];
        uint256 head = userUndelegationHead[_delegator];

        // Count valid entries (unprocessed) starting from head
        // Skip invalidated indices and entries belonging to other delegators
        uint256 count = 0;
        for (uint256 i = head; i < indices.length; ++i) {
            uint256 idx = indices[i];
            if (idx == type(uint256).max || idx >= pendingUndelegations.length) {
                continue;
            }
            PendingUndelegation storage pending = pendingUndelegations[idx];
            if (pending.delegator != _delegator) {
                continue;
            }
            if (!pending.processed) {
                count++;
            }
        }

        // Allocate array
        undelegations = new PendingUndelegation[](count);

        // Fill array
        uint256 writeIdx = 0;
        for (uint256 i = head; i < indices.length; ++i) {
            uint256 idx = indices[i];
            if (idx == type(uint256).max || idx >= pendingUndelegations.length) {
                continue;
            }
            PendingUndelegation storage pending = pendingUndelegations[idx];
            if (pending.delegator != _delegator) {
                continue;
            }
            if (!pending.processed) {
                undelegations[writeIdx] = pending;
                writeIdx++;
            }
        }
    }

    function getValidatorApr(bytes32 _poolId) external view override returns (uint256 apr) {
        require(validators[_poolId].poolId != 0, "Validator does not exist");

        if (totalStake == 0 || validators[_poolId].stakeSnapshot == 0) {
            return 0;
        }

        // Calculate APR based on current inflation rate and validator's share of total stake
        // APR = (inflation_rate * validator_stake_share) / total_supply * 100
        uint256 inflationRate = currentInflationRate; // basis points (e.g., 9125 = 9.125%)
        uint256 validatorShare = (validators[_poolId].stakeSnapshot * 100) / totalStake; // percentage
        apr = (inflationRate * validatorShare) / 100; // scale to basis points

        return apr;
    }

    function getCommissionRate(bytes32 _poolId) external view override returns (uint256) {
        return commissionRates[_poolId];
    }

    function _updateDelegatorReward(bytes32 _poolId, address _delegator) internal {
        Delegator storage delegator = delegators[_poolId][_delegator];

        uint256 currentRps = accumulatedRewardPerShares[_poolId];
        uint256 lastRps = delegator.accumulatedRewardPerShare;

        // Only calculate and update if:
        // 1. RPS has increased (rewards have been distributed)
        // 2. Delegator has active stake (stake > 0)
        //
        // The stake > 0 check is critical for _activatePendingStake's correctness.
        // See _activatePendingStake documentation for why.
        if (currentRps > lastRps && delegator.stake > 0) {
            uint256 delta = currentRps - lastRps;
            uint256 reward = (delta * delegator.stake) / PRECISION;
            delegator.rewards += reward;
            delegator.accumulatedRewardPerShare = currentRps;
        }
    }

    function _activatePendingStake(bytes32 _poolId, address _delegator) internal {
        Delegator storage delegator = delegators[_poolId][_delegator];

        // Nothing to activate (should have been checked by _tryActivatePending)
        if (delegator.pendingStake == 0) {
            return;
        }

        uint256 activationEpoch = pendingActivationEpoch[_poolId][_delegator];

        // Not yet time to activate (should have been checked by _tryActivatePending)
        if (currentEpoch < activationEpoch) {
            return;
        }

        uint256 activatingAmount = delegator.pendingStake;

        // STEP 1: Settle rewards for existing active stake (if any)
        _updateDelegatorReward(_poolId, _delegator);

        // STEP 2: Activate the pending stake
        delegator.stake += activatingAmount;
        delegator.pendingStake = 0;

        // STEP 3: Calculate "catch-up" rewards for the newly activated stake
        uint256 entryRPS = historicalRPS[activationEpoch][_poolId].rps;
        uint256 currentRPS = accumulatedRewardPerShares[_poolId];

        if (currentRPS > entryRPS) {
            uint256 delta = currentRPS - entryRPS;
            uint256 catchUpReward = (delta * activatingAmount) / PRECISION;
            delegator.rewards += catchUpReward;
        }

        // STEP 4: Update unified tracking point
        delegator.accumulatedRewardPerShare = currentRPS;

        if (historicalRPS[activationEpoch][_poolId].refcount > 0) {
            historicalRPS[activationEpoch][_poolId].refcount--;
        }

        // Clear activation epoch mapping
        delete pendingActivationEpoch[_poolId][_delegator];
    }

    function getDelegationWithdrawWindow() internal view returns (uint256) {
        string memory key = "staking.delegation_withdraw_effective_epoch";
        string memory value = cfg.getConfig(key);
        uint256 window;
        if (Strings.equal(value, "")) {
            // Use default value if configuration is not set or not yet effective
            window = DEFAULT_WITHDRAW_WINDOW;
        } else {
            window = Strings.parseUint(value);
        }

        // Ensure window is non-zero to prevent immediate withdrawal
        require(window > 0, "Delegation withdraw window must be greater than 0");

        return window;
    }

    function getDelegatorPendingWithdraw(bytes32 _poolId, address _delegator)
        external
        view
        returns (uint256 pendingAmount, uint256 remainingWindow, bool isPending, uint256 unlockEpoch)
    {
        Delegator memory delegator = delegators[_poolId][_delegator];
        pendingAmount = delegator.pendingWithdrawStake;
        isPending = delegator.isPendingUndelegate;

        if (!isPending) {
            return (0, 0, false, 0);
        }

        // Find the first valid entry from head for this pool
        uint256[] storage indices = userUndelegationIndices[_delegator];
        uint256 head = userUndelegationHead[_delegator];

        for (uint256 i = head; i < indices.length; ++i) {
            if (indices[i] == type(uint256).max) {
                continue;
            }
            PendingUndelegation storage pending = pendingUndelegations[indices[i]];
            if (pending.processed || pending.poolId != _poolId || pending.delegator != _delegator) {
                continue;
            }
            unlockEpoch = pending.unlockEpoch;
            remainingWindow = unlockEpoch > currentEpoch ? unlockEpoch - currentEpoch : 0;
            return (pendingAmount, remainingWindow, isPending, unlockEpoch);
        }

        return (pendingAmount, 0, isPending, 0);
    }

    function getPendingUndelegationCount() external view returns (uint256) {
        return pendingUndelegations.length;
    }

    function getActiveValidatorCount() external view override returns (uint256) {
        return activePoolSets.length();
    }

    function getTotalDelegatorCount() external view override returns (uint256) {
        uint256 totalCount = 0;
        uint256 length = activePoolSets.length();
        for (uint256 i = 0; i < length; ++i) {
            bytes32 poolId = activePoolSets.at(i);
            totalCount += delegatorCounts[poolId];
        }
        return totalCount;
    }
}
