/*
 * @title tgUSD-staking
 * @notice A comprehensive contract for managing tgUSD staking.
 * @dev This contract:
 * - Allows users to stake tgUSD and receive stgUSD in return.
 * - Facilitates periodic reward transfers to the staking contract by the protocol, with rewards vested to stakers.
 * - Deploys a dedicated Unstake Account for each user to record unstake information, allowing users to withdraw tgUSD after cooldownEnd.
 * - Enables unstakers to withdraw tgUSD after the cooldownEnd period.
 */

tolk 0.11

import "../common/exit-codes.tolk";
import "../common/constants.tolk";
import "../common/op-codes.tolk";
import "../common/guard.tolk";
import "../common/serdes.tolk";
import "../common/send.tolk";
import "../common/log.tolk";
import "../common/gas.tolk";
import "../common/refund.tolk";
import "../common/child-contract.tolk";
import "../common/recipient.tolk";
import "../library/fee.tolk";
import "storage.tolk";
import "gas.tolk";
import "guard.tolk";
import "log.tolk";
import "serdes.tolk";
import "handler.tolk";
import "vest.tolk";

@inline
fun routeInternal(ctxSender: slice, ctxValue: int, ctxFwdFee: int, ctxBody: slice) {
    val op: Opcode = ctxBody.loadMessageOp();
    val queryId: QueryId = ctxBody.loadMessageQueryId();

    if (op == OP_TRANSFER_NOTIFICATION) {
        // Only tgUSD Staking's Jetton Wallet can send OP_TRANSFER_NOTIFICATION
        ctxSender.requiretgUSDStakingJettonWallet(tgUSDJettonWallet);

        // Parse jetton notification message
        var (jettonAmount: coins, jettonSender: slice, forwardPayload: slice) = ctxBody.parseJettonNotification();

        // jettonAmount should be positive
        requirePositiveJettonAmount(jettonAmount);

        // Get op-code in forward payload 
        val forwardPayloadOp: Opcode = forwardPayload.loadMessageOp();

        if (forwardPayloadOp == OP_STAKE_FP) {

            // If contract is halted, refund tgUSD to jettonSender
            if (isHalt) {
                // Make sure the fee is enough to refund
                val (totalFee: coins, gasConsume: coins) = computeRefundFee(ctxFwdFee);
                assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
                val sendingValue: coins = ctxValue - gasConsume;

                // Refund jetton to jettonSender
                refundByTransfer(jettonSender, ctxSender, jettonAmount, sendingValue, queryId, packCommentPayload("Refund: Contract is halted"));
                commitContractDataAndActions();
                throw ERROR_CONTRACT_HALTED;
            }   

            // Parse stake message body
            var recipient: slice = forwardPayload.parseStake();

            // Check if there is a recipient; if not, set it to the staker.
            recipient = getRecipient(recipient, jettonSender);

            // Check sending value is enough to cover the fee
            val (totalFee: coins, gasConsume: coins) = computeStakeFee(ctxFwdFee);
            assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
            val sendingValue: coins = ctxValue - gasConsume;

            // Stake tgUSD
            // Calculate unvested amount (When calculating shares, we need to subtract the unvested amount from the total stakedAmount)
            val unvestedAmount: coins = getUnvestedAmount(vestingStart, vestingPeriod, vestingReward);
            val mintedShares: coins = handleStake(stgUSDJettonMaster, queryId, totalShares, totalStaked, unvestedAmount, jettonSender, recipient, jettonAmount, sendingValue);

            // Update staking pool state: shares, staked and remainingStaked
            totalShares += mintedShares;
            totalStaked += jettonAmount;
            remainingStaked += jettonAmount;

            // Emit log
            logStaked(mintedShares, jettonAmount, jettonSender, recipient, totalShares, totalStaked, remainingStaked);

            saveData();
            return;
        }

        if (forwardPayloadOp == OP_DEALLOCATE_STAKED_FP) {
            // Deallocate staked
            remainingStaked += jettonAmount;

            // Emit log
            logStakedDeallocated(jettonSender, jettonAmount, remainingStaked);

            saveData();
            return;
        }

        if (forwardPayloadOp == OP_SUPPLY_REWARD_FP) {
            // Jetton sender can only be tgUSD Jetton Master or admin
            jettonSender.requiretgUSDJettonMasterOrAdmin(tgUSDJettonMaster, admin);

            // Parse supply reward fp message body
            val (collateralAsset: cell, collateralAmount: coins, source: slice, custodialWallet: slice) = forwardPayload.parseSupplyRewardFp();

            // Refund if contract is halted
            if (isHalt) {
                // Make sure the fee is enough to refund
                val (totalFee: coins, gasConsume: coins) = computeRefundFee(ctxFwdFee);
                assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
                val sendingValue: coins = ctxValue - gasConsume;

                // Refund jetton to source (admin or custodial wallets in tgUSD Engine)
                refundByTransfer(source, tgUSDJettonWallet, jettonAmount, sendingValue, queryId, packCommentPayload("Refund: Contract is halted"));
                commitContractDataAndActions();
                throw ERROR_CONTRACT_HALTED;
            }

            // Update totalStaked
            totalStaked += jettonAmount;

            // Combine current unvested amount with new reward
            vestingReward = getUnvestedAmount(vestingStart, vestingPeriod, vestingReward) + jettonAmount;

            // Update last distribution timestamp to now()
            vestingStart = now();

            // Update remainingStaked
            remainingStaked += jettonAmount;

            // Emit log
            logRewardSupplied(totalStaked, remainingStaked, vestingReward, vestingStart, vestingPeriod, collateralAsset, collateralAmount, jettonAmount, source, custodialWallet);

            saveData();
            return;
        }
        throw ERROR_WRONG_OP;
    }

    if (op == OP_ALLOCATE_STAKED) {
        // Only admin or staked manager can allocate staked
        ctxSender.requireAdminOrStakedManager(admin, stakedManager);

        // Parse allocate staked message body
        var (stakedAmount: coins, recipient: slice, customPayload: cell?) = ctxBody.parseAllocateStaked();

        // remainingStaked should >= stakedAmount
        requireEnoughStaked(remainingStaked, stakedAmount);

        // (remainingStaked - stakedAmount) should be >= lockedForUnstake
        requireEnoughStaked(remainingStaked - stakedAmount, lockedForUnstake);

        // Check sending value is enough to cover the fee
        val hasCustomPayload: bool = customPayload != null;
        val (totalFee: coins, gasConsume: coins) = computeAllocateStakedFee(ctxFwdFee, hasCustomPayload);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Check if there is a recipient; if not, set it to the ctxSender (admin or stakedManager).
        recipient = getRecipient(recipient, ctxSender);

        val (forwardPayload: cell, forwardTON: coins) = hasCustomPayload ? 
            (customPayload!, sendingValue - ALLOCATE_STAKED_VALUE) : 
            (packCommentPayload("Transfer: Staked to recipient"), MINIMUM_JETTON_NOTIFICATION_VALUE);

        // Transfer tgUSD to recipient
        sendJettonMessage(
            NON_BOUNCEABLE,
            recipient,
            ctxSender,
            tgUSDJettonWallet,
            stakedAmount,
            sendingValue,
            queryId,
            forwardPayload,
            forwardTON,
            SEND_MODE_REGULAR
        );

        // Update remainingStaked
        remainingStaked -= stakedAmount;

        // Emit log
        logStakedAllocated(ctxSender, stakedAmount, remainingStaked, recipient);

        saveData();
        return;
    }

    if (op == OP_WITHDRAW_INTERNAL) {
        // Parse withdraw internal message body
        val (unstaker: slice, unstakedAmount: coins, recipient: slice) = ctxBody.parseWithdrawInternal();

        // ctxSender should be UnstakeAccount
        val (_, unstakeAccountAddress: slice) = getChildContract(getMyAddress(), packUnstakeAccountProof(getMyAddress(), unstaker), baseCode);
        ctxSender.requireUnstakeAccount(unstakeAccountAddress);

        // Check remainingStaked is enough to cover the unstake amount or contract is halted
        if (remainingStaked < unstakedAmount || isHalt) {
            // Make sure the fee is enough to rollback withdraw
            val (totalFee: coins, gasConsume: coins) = computeWithdrawFailedFee(ctxFwdFee);
            assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
            val sendingValue: coins = ctxValue - gasConsume;

            // Send OP_ROLLBACK_UNSTAKE to UnstakeAccount
            sendSimpleMessage(NON_BOUNCEABLE, unstakeAccountAddress, sendingValue, packRollbackWithdraw(queryId, unstakedAmount), SEND_MODE_REGULAR);

            // Emit log
            logWithdrawProcessed(isHalt ? WITHDRAW_BUT_HALTED : WITHDRAW_BUT_NOT_ENOUGH_STAKED, unstaker, unstakedAmount, recipient, remainingStaked, lockedForUnstake);
            commitContractDataAndActions();
            throw (isHalt ? ERROR_CONTRACT_HALTED : ERROR_NOT_ENOUGH_STAKED);
        }

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeWithdrawInternalFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Send tgUSD to recipient
        sendJettonMessage(
            NON_BOUNCEABLE,
            recipient,
            unstaker,
            tgUSDJettonWallet,
            unstakedAmount,
            sendingValue,
            queryId,
            packCommentPayload("Transfer: tgUSD to recipient"),
            MINIMUM_JETTON_NOTIFICATION_VALUE,
            SEND_MODE_REGULAR
        );

        // Update remainingStaked and lockedForUnstake
        remainingStaked -= unstakedAmount;
        lockedForUnstake -= unstakedAmount;

        // Emit log
        logWithdrawProcessed(WITHDRAW_SUCCESS, unstaker, unstakedAmount, recipient, remainingStaked, lockedForUnstake);

        saveData();
        return;
    }

    if (op == OP_EXTRA_BURN_INFO) {
        // Only stgUSD Jetton Master can send OP_EXTRA_BURN_INFO
        ctxSender.requirestgUSDJettonMaster(stgUSDJettonMaster);

        // Parse extra burn info message body
        var (
            unstaker: slice,
            jettonAmount: coins,
            customPayload: slice
        ) = ctxBody.parseExtraBurnInfo();

        // jettonAmount should be positive
        requirePositiveJettonAmount(jettonAmount);

        // Get op-code in custom payload 
        val customPayloadOp: Opcode = customPayload.loadMessageOp();

        if (customPayloadOp == OP_REQUEST_UNSTAKE_FP) {
            // If contract is halted, refund jettonAmount to jettonSender by minting stgUSD
            if (isHalt) {
                // Make sure the fee is enough to refund
                val (totalFee: coins, gasConsume: coins) = computeRefundFee(ctxFwdFee);
                assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
                val sendingValue: coins = ctxValue - gasConsume;

                // Refund jetton to unstaker
                refundByMint(stgUSDJettonMaster, sendingValue, getMyAddress(), unstaker, unstaker, jettonAmount, queryId, packCommentPayload("Refund: Contract is halted"));
                commitContractDataAndActions();
                throw ERROR_CONTRACT_HALTED;
            }

            // totalShares should be positive
            requirePositiveTotalShares(totalShares);

            // Check sending value is enough to cover the fee
            val (totalFee: coins, gasConsume: coins) = computeUnstakeFee(ctxFwdFee);
            assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
            val sendingValue: coins = ctxValue - gasConsume;

            // Unstake tgUSD
            // Calculate unvested amount (When calculating unstakedAmount, we need to subtract the unvested amount from the total unstakedAmount)
            val unvestedAmount: coins = getUnvestedAmount(vestingStart, vestingPeriod, vestingReward);
            val (unstakedAmount: coins, cooldownEnd: Timestamp) = handleUnstake(
                getMyAddress(),
                queryId,
                totalShares,
                totalStaked,
                unvestedAmount,
                unstaker,
                jettonAmount,
                sendingValue,
                baseCode,
                unstakeAccountCode,
                cooldownPeriod
            );

            // Update shares, staked and lockedForUnstake
            totalShares -= jettonAmount;
            totalStaked -= unstakedAmount;
            lockedForUnstake += unstakedAmount;
            
            // Emit log
            logUnstaked(jettonAmount, unstakedAmount, unstaker, cooldownEnd, totalShares, totalStaked, lockedForUnstake);

            saveData();
            return;
        }

        throw ERROR_WRONG_OP;
    }

    if (op == OP_PROVIDE_CURRENT_QUOTE) {
        // Parse provide current quote message body
        val (recipient: slice, customPayload: cell?) = ctxBody.parseProvideCurrentQuote();

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeProvideCurrentQuoteFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Pack OP_TAKE_CURRENT_QUOTE message body
        val totalStakedAmountWithoutUnvested: coins = totalStaked - getUnvestedAmount(vestingStart, vestingPeriod, vestingReward);
        val timestamp: Timestamp = now();
        val msgBody: cell = packTakeCurrentQuote(queryId, totalStakedAmountWithoutUnvested, totalShares, timestamp, customPayload);

        // Send OP_TAKE_CURRENT_QUOTE to recipient
        sendSimpleMessage(NON_BOUNCEABLE, recipient, sendingValue, msgBody, SEND_MODE_REGULAR);

        // Emit log
        logCurrentQuoteProvided(totalStakedAmountWithoutUnvested, totalShares, timestamp, ctxSender, recipient);
        
        saveData();
        return;
    }

    if (op == OP_RESET_GAS) {
        // Only admin can reset gas
        ctxSender.requireAdmin(admin);

        // Parse reset gas message body
        var recipient: slice = ctxBody.loadAddress();

        // Check if there is a recipient; if not, set it to the admin.
        recipient = getRecipient(recipient, admin);

        // Reserve minimal TON to pay for storage fee (If balance is less than MINIMUM_ENGINE_STORAGE_TON, it will throw error)
        reserveToncoinsOnBalance(MINIMUM_ENGINE_STORAGE_TON, RESERVE_MODE_AT_MOST);

        // Transfer all balance to admin except for the minimal balance + distributable
        sendSimpleMessage(NON_BOUNCEABLE, recipient, 0, packCommentPayload("Reset Gas"), SEND_MODE_CARRY_ALL_BALANCE);
        return;
    }

    if (op == OP_UPDATE_COOLDOWN_PERIOD) {
        // Only admin can update cooldown period
        ctxSender.requireAdmin(admin);

        // Parse update cooldown period message body
        val newCooldownPeriod: Timestamp = ctxBody.loadUint(TIMESTAMP_SIZE);

        // Check new cooldown period is different from old one
        requireDifferentTimestamp(cooldownPeriod, newCooldownPeriod);

        // Check new cooldown period is not greater than the maximum cooldown period
        requireCooldownPeriodNotTooLong(newCooldownPeriod);

        // Update cooldown period
        cooldownPeriod = newCooldownPeriod;

        // Emit log
        logCooldownPeriodUpdated(admin, newCooldownPeriod);

        saveData();
        return;
    }

    if (op == OP_UPDATE_VESTING_PERIOD) {
        // Only admin can update cooldown period
        ctxSender.requireAdmin(admin);

        // Can't update vesting period when vesting is active
        requireVestingNotActive(getUnvestedAmount(vestingStart, vestingPeriod, vestingReward));

        // Parse update cooldown period message body
        val newVestingPeriod: Timestamp = ctxBody.loadUint(TIMESTAMP_SIZE);

        // Check new vesting period is different from old one
        requireDifferentTimestamp(vestingPeriod, newVestingPeriod);

        // Check new vesting period is not greater than the maximum vesting period
        requireVestingPeriodNotTooLong(newVestingPeriod);

        // Update vesting period and vesting reward
        vestingPeriod = newVestingPeriod;
        vestingReward = 0;

        // Emit log
        logVestingPeriodUpdated(admin, newVestingPeriod);

        saveData();
        return;
    }

    if (op == OP_UPDATE_UNSTAKE_ACCOUNT_CODE) {
        // Only admin can update unstake account code
        ctxSender.requireAdmin(admin);

        // Parse update unstake account code message body
        val newUnstakeAccountCode: cell = ctxBody.loadRef();

        // Validate if new unstake account code is not the same as the old one
        requireNotIdenticalCell(newUnstakeAccountCode, unstakeAccountCode);

        // Update unstake account code
        unstakeAccountCode = newUnstakeAccountCode;

        saveData();
        return;
    }

    if (op == OP_FORCE_WITHDRAW) {
        // Only admin can force withdraw
        ctxSender.requireAdmin(admin);

        // Parse force withdraw message body
        val unstakeAccount: slice = ctxBody.loadAddress();

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeForceWithdrawFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Send OP_FORCE_WITHDRAW to UnstakeAccount
        sendSimpleMessage(NON_BOUNCEABLE, unstakeAccount, sendingValue, packWithdraw(queryId), SEND_MODE_REGULAR);
        return;
    }

    if (op == OP_HALT) {
        // Only admin can halt
        ctxSender.requireAdmin(admin);

        // Contract should not be halted
        requireContractNotHalted(isHalt);

        // Halt the contract
        isHalt = true;

        // Emit log
        logContractHalted(admin);

        saveData();
        return;
    }

    if (op == OP_UNHALT) {
        // Only admin can unhalt
        ctxSender.requireAdmin(admin);

        // Contract should be halted
        requireContractHalted(isHalt);

        // Unhalt the contract
        isHalt = false;

        // Emit log
        logContractUnhalted(admin);

        saveData();
        return;
    }

    if (op == OP_CHANGE_ADMIN) {
        // Only admin can change admin
        ctxSender.requireAdmin(admin);

        // Parse change admin message body
        val nextAdminAddress: slice = ctxBody.loadAddress();

        // nextAdmin should be different from admin
        requireDifferentAdmin(admin, nextAdminAddress);

        // Update admin
        nextAdmin = nextAdminAddress;

        saveData();
        return;
    }

    if (op == OP_CLAIM_ADMIN) {
        ctxBody.assertEndOfSlice();

        // Only next admin can claim admin
        ctxSender.requireNextAdmin(nextAdmin);

        // Emit log
        logAdminChanged(nextAdmin, admin);

        // Update admin
        admin = nextAdmin;
        nextAdmin = createAddressNone();

        saveData();
        return;
    }

    if (op == OP_CALL_TO_JETTON_MASTER) {
        // Only admin can call to jetton master
        ctxSender.requireAdmin(admin);

        // Parse call to jetton master message body
        val (to, tonAmount, masterMsg) = ctxBody.parseCallToJettonMaster();

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeCallToJettonMasterFee();
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Pack OP_CALL_TO_JETTON_MASTER message body
        val msgBody: cell = packCallToJettonMaster(queryId, to, tonAmount, masterMsg);
        sendSimpleMessage(NON_BOUNCEABLE, stgUSDJettonMaster, sendingValue, msgBody, SEND_MODE_REGULAR);
        return;
    }

    if (op == OP_CHANGE_JETTON_MASTER_ADMIN) {
        // Only admin can change jetton master admin
        ctxSender.requireAdmin(admin);

        // Parse change jetton master admin message body
        val newJettonMasterAdmin: slice = ctxBody.loadAddress();

        // Pack OP_CHANGE_JETTON_MASTER_ADMIN message body
        val msgBody: cell = packChangeJettonMasterAdmin(queryId, newJettonMasterAdmin);
        sendSimpleMessage(NON_BOUNCEABLE, stgUSDJettonMaster, 0, msgBody, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        return;
    }

    if (op == OP_UPGRADE_CONTRACT) {
        // Only admin can upgrade contract
        ctxSender.requireAdmin(admin);

        // Parse update contract message body
        val (newData: cell?, newCode: cell?) = ctxBody.parseUpgradeContract();

        // Validate at least one of newCode or newData is not null, or this upgrade in meaningless
        assert(newCode != null || newData != null, ERROR_INVALID_UPGRADE);

        // Set new code and data if provided
        if (newCode != null) {
            // Validate if new code is not the same as the old code
            requireNotIdenticalCell(newCode, getContractCode());

            setContractCodePostponed(newCode);
        }
        if (newData != null) {
            // Validate if new data is not the same as the old data
            requireNotIdenticalCell(newData, getContractData());

            setContractData(newData);
        }

        return;
    }

    if (op == OP_UPGRADE_UNSTAKE_ACCOUNT) {
        // Only admin can upgrade unstake account
        ctxSender.requireAdmin(admin);

        // Parse upgrade unstake account message body
        val (unstakeAccount: slice, data: cell?) = ctxBody.parseUpgradeChildContract();

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeUpgradNextContractFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Pack OP_UPGRADE message body
        val msgBody: cell = packUpgrade(queryId, data, unstakeAccountCode);
        sendSimpleMessage(NON_BOUNCEABLE, unstakeAccount, sendingValue, msgBody, SEND_MODE_REGULAR);

        saveData();
        return;
    }

    if (op == OP_UPGRADE_JETTON_MASTER) {
        // Only admin can upgrade jetton master
        ctxSender.requireAdmin(admin);

        // Parse upgrade jetton master message body
        val (newData: cell, newCode: cell) = ctxBody.parseUpgradeJettonMaster();

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeUpgradNextContractFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Pack OP_UPGRADE message body
        val msgBody: cell = packJettonMasterUpgrade(queryId, newData, newCode);
        sendSimpleMessage(NON_BOUNCEABLE, stgUSDJettonMaster, sendingValue, msgBody, SEND_MODE_REGULAR);

        saveData();
        return;
    }

    if (op == OP_CHANGE_JETTON_MASTER_CONTENT) {
        // Only admin can change jetton master content
        ctxSender.requireAdmin(admin);

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeChangeJettonMasterContentFee();
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Parse change jetton master content message body
        val msgBody: cell = packChangeJettonMasterContent(queryId, ctxBody);
        sendSimpleMessage(NON_BOUNCEABLE, stgUSDJettonMaster, sendingValue, msgBody, SEND_MODE_REGULAR);
        return;
    }

    if (op == OP_TOP_UP) {
        // Only admin can TopUp
        ctxSender.requireAdmin(admin);

        // tgUSDJettonWallet and stgUSDJettonWallet should be address none or it means double top up
        requireJettonMasterAddressNotTaken(tgUSDJettonWallet, stgUSDJettonWallet);

        // Parse top up message body
        (stgUSDJettonMaster, stakedManager, vestingPeriod, cooldownPeriod, baseCode, unstakeAccountCode) = ctxBody.parseTopUp();

        // Check fee is enough to compute top up
        val (totalFee: coins, gasConsume: coins) = computeTopUpFee();
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        
        // Send OP_PROVIDE_WALLET_ADDRESS to tgUSD Jetton Master and stgUSD Jetton Master
        val msgBody: cell = packProvideWalletAddress(queryId, getMyAddress(), false);
        sendSimpleMessage(NON_BOUNCEABLE, tgUSDJettonMaster, PROVIDE_WALLET_ADDRESS_VALUE, msgBody, SEND_MODE_REGULAR);
        sendSimpleMessage(NON_BOUNCEABLE, stgUSDJettonMaster, PROVIDE_WALLET_ADDRESS_VALUE, msgBody, SEND_MODE_REGULAR);

        // Emit log
        logStakingDeployed(stakedManager, vestingPeriod, cooldownPeriod, admin);

        saveData();
        return;
    }

    if (op == OP_TAKE_WALLET_ADDRESS) {
        // Parse message to get jetton wallet address
        val jettonWalletAddress: slice = ctxBody.parseTakeWalletAddress();

        // Set jettonWalletAddress based on the jetton master address (tgUSD or stgUSD), if the jetton master address is not supported, throw error
        if (ctxSender.isSliceBitsEqual(tgUSDJettonMaster)) {
            tgUSDJettonWallet = jettonWalletAddress;
        } else if (ctxSender.isSliceBitsEqual(stgUSDJettonMaster)) {
            stgUSDJettonWallet = jettonWalletAddress;
        } else {
            throw ERROR_NOT_SUPPORTED_JETTON_MASTER;
        }

        // Emit log
        logStakingWalletAddressTaken(ctxSender, jettonWalletAddress);

        saveData();
        return;
    }

    throw ERROR_WRONG_OP;
}

fun onInternalMessage(myBalance: int, msgValue: int, msgFull: cell, msgBody: slice) {
    if (msgBody.isEndOfSlice()) { // ignore all empty messages
        return;
    }

    var cs: slice = msgFull.beginParse();
    val flags = cs.loadMessageFlags();
    if (isMessageBounced(flags)) { // ignore all bounced messages
        return;
    }

    // Get the context of the incoming message
    val (ctxSender: slice, ctxFwdFee: int) = cs.getCtx(WORKCHAIN); 

    // Load data from storage
    loadData();

    // Route the message to the appropriate handler
    routeInternal(ctxSender, msgValue, ctxFwdFee, msgBody);
}

// Getters

get conversionRatio(): (int, int) {
    loadData();
    return (totalStaked - getUnvestedAmount(vestingStart, vestingPeriod, vestingReward), totalShares);
}

get unstakeAccount(unstaker: slice): slice {
    loadData();
    
    // Pack UnstakeAccount Proof and get UnstakeAccount Address
    val tgUSDStaking = getMyAddress();
    val unstakeAccountProof: ContractProof = packUnstakeAccountProof(tgUSDStaking, unstaker);
    val (_, unstakeAccountAddress: slice) = getChildContract(tgUSDStaking, unstakeAccountProof, baseCode);

    return unstakeAccountAddress;
}