/*
 * @title unstaker-account
 * @notice A child contract deployed when an unstaker initiates an unstake request, used to record unstake info.
 * @dev This contract:
 * - Records unstake details, including tgUSD amount (principal + staking rewards),  and the requirement to wait until cooldownEnd to withdraw tgUSD.
 * - Allows only the unstaker or tgUSD staking contract to call OP_WITHDRAW to claim tgUSD.
 * - tgUSD staking contract can bypass cooldownEnd when calling OP_WITHDRAW.
 * - If the unstaker re-initiates an unstake during the cooldown, cooldownEnd resets and unstakeAmount accumulates.
 * - If OP_WITHDRAW is called after cooldownEnd but no funds are available (e.g., paused or insufficient balance), OP_ROLLBACK_WITHDRAW is triggered. 
 *   The amount is recorded as availableAmount and can be withdrawn later without waiting once conditions are restored.
 */

tolk 0.11

import "../common/exit-codes.tolk";
import "../common/constants.tolk";
import "../common/op-codes.tolk";
import "../common/guard.tolk";
import "../common/send.tolk";
import "../common/serdes.tolk";
import "../common/recipient.tolk";
import "../common/types.tolk";
import "../library/fee.tolk";
import "storage.tolk";
import "guard.tolk";
import "serdes.tolk";
import "gas.tolk";

@inline
fun routeInternal(ctxSender: slice, ctxValue: int, ctxFwdFee: int, ctxBody: slice) {
    val op: Opcode = ctxBody.loadMessageOp();
    val queryId: QueryId = ctxBody.loadMessageQueryId();

    if (op == OP_WITHDRAW) {
        // Only Unstaker can withdraw
        ctxSender.requireUnstakerOrStaking(unstaker, tgUSDStaking);

        // Get the recipient
        val recipient: slice = ctxBody.loadAddress();

        // Check if cooldownEnd is passed (If ctxSender is tgUSDStaking, then don't wait for cooldownEnd)
        val passCooldownOrNot: bool = now() >= cooldownEnd || ctxSender.isSliceBitsEqual(tgUSDStaking);

        // Calculate total unstaked amount
        val totalUnstakedAmount: coins = availableAmount + (passCooldownOrNot ? unstakedAmount : ton("0"));

        // Only can withdraw when unstakedAmount + availableAmount > 0
        requirePositiveWithdraw(totalUnstakedAmount);

        // Make sure sending value is enough to withdraw
        val (totalFee: coins, gasConsume: coins) = computeWithdrawFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Pack withdraw internal payload (Check if there is a recipient; if not, set it to the unstaker.)
        val withdrawInternalPayload: cell = packWithdrawInternal(queryId, unstaker, totalUnstakedAmount, getRecipient(recipient, unstaker));

        // Send OP_WITHDRAW_INTERNAL to tgUSD Staking
        sendSimpleMessage(NON_BOUNCEABLE, tgUSDStaking, sendingValue, withdrawInternalPayload, SEND_MODE_REGULAR);   

        // Update the cooldownEnd and unstakedAmount (Only when cooldownEnd is passed, Otherwise, this OP_WITHDRAW only withdraw availableAmount)
        if (passCooldownOrNot) {
            cooldownEnd = 0;
            unstakedAmount = 0;
        }

        // No mater what kind of situation, after withdraw availableAmount should be 0
        availableAmount = 0;

        saveData();
        return;
    }   

    if (op == OP_ROLLBACK_WITHDRAW) {
        // Only tgUSD Staking can rollback withdraw
        ctxSender.requiretgUSDStaking(tgUSDStaking);

        // Parse Rollback Withdraw message body
        val rollbackUnstakedAmount = ctxBody.loadCoins();
        
        // Make sure the fee is enough to rollback withdraw
        val (totalFee: coins, gasConsume: coins) = computeRollbackWithdrawFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: int = ctxValue - gasConsume;

        // Send remaining ton to unstaker
        sendSimpleMessage(NON_BOUNCEABLE, unstaker, sendingValue, packComment("Your assets are secure. Please contact Torch Finance support for assistance."), SEND_MODE_REGULAR);

        // Update availableAmount
        availableAmount = availableAmount + rollbackUnstakedAmount;

        saveData();
        return;
    }

    if (op == OP_INSTALL) {
        // Only tgUSD Staking can install
        ctxSender.requiretgUSDStaking(tgUSDStaking);

        // Get additional unstake amount to refund
        val (additionalUnstakedAmount, newCooldownEnd) = ctxBody.parseInstallUnstakeAccount();

        // If now >= cooldownEnd, add unstakedAmount to availableAmount (Because unstakedAmount is already waiting for cooldownEnd, we don't need to wait for cooldownEnd again)
        if (now() >= cooldownEnd) {
            availableAmount = availableAmount + unstakedAmount;
            unstakedAmount = 0;
        }

        // Update the cooldown end
        cooldownEnd = newCooldownEnd;

        // Update total amounts
        unstakedAmount = unstakedAmount + additionalUnstakedAmount;
    
        saveData();
        return;
    }

    if (op == OP_UPGRADE_CONTRACT) {
        // Only tgUSD Staking can upgrade
        ctxSender.requiretgUSDStaking(tgUSDStaking);

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