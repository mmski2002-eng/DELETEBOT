/*
 * @title redeem-account
 * @notice A child contract deployed when a redeemer initiates a redeem request, used to record the user's redeem information.
 * @dev This contract:
 * - Records details of the redeem process, including the burning of tgUSD to retrieve collateral, the asset and amount of collateral, and the requirement to wait until cooldownEnd to claim the collateral.
 * - Allows only the redeemer or tgUSD Engine to call OP_CLAIM to retrieve the collateral.
 * - tgUSD Engine can bypass cooldownEnd when calling OP_CLAIM.
 * - Ensures a redeemer can only have one active redeem for the same collateral asset at a time; duplicate redeems trigger a refund.
 * - If OP_CLAIM is called after cooldownEnd but no funds are available (e.g., paused or insufficient balance), OP_ROLLBACK_CLAIM is triggered. 
 * - The redeem account’s status is set to `REDEEM_PENDING`, allowing the user to re-initiate the claim without waiting once conditions are restored.
 */

tolk 0.11

import "../library/fee.tolk";
import "../common/constants.tolk";
import "../common/op-codes.tolk";
import "../common/exit-codes.tolk";
import "../common/send.tolk";
import "../common/guard.tolk";
import "../common/serdes.tolk";
import "../common/recipient.tolk";
import "storage.tolk";
import "guard.tolk";
import "serdes.tolk";
import "gas.tolk";

@inline
fun routeInternal(ctxSender: slice, ctxValue: int, ctxFwdFee: int, ctxBody: slice) {
    val op: Opcode = ctxBody.loadMessageOp();
    val queryId: QueryId = ctxBody.loadMessageQueryId();

    if (op == OP_CLAIM) {
        // Only redeemer or tgUSD Engine can claim
        ctxSender.requireRedeemerOrEngine(redeemer, tgUSDEngine);

        // status must be REDEEM_PENDING
        requireStatusPending(status);

        // Redeemer can only claim after cooldownEnd, But if the claim is from tgUSD Engine, it can bypass the cooldownEnd
        if (ctxSender.isSliceBitsEqual(redeemer)) {
            requireAfterCooldown(cooldownEnd);
        }

        // Get recipient if it is none, use redeemer as recipient
        var recipient: slice = ctxBody.loadAddress();

        // Make sure the fee is enough to claim
        val (totalFee: coins, gasConsume: coins) = computeClaimFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: int = ctxValue - gasConsume;

        // Send OP_PAYOUT to tgUSD Engine
        val payoutPayload: cell = packPayoutPayload(
            queryId, 
            redeemer, 
            REDEEM_SUCCESS,
            redeemAsset, 
            redeemAmount, 
            engineJettonWallet, 
            getRecipient(recipient, redeemer) // Check if there is a recipient; if not, set it to the redeemer.
        );

        // Send OP_PAYOUT to tgUSD Engine
        sendSimpleMessage(NON_BOUNCEABLE, tgUSDEngine, sendingValue, payoutPayload, SEND_MODE_REGULAR);   

        // Set RedeemAccount status to REDEEM_PROCESSING
        status = REDEEM_PROCESSING;

        saveData();
        return;
    }

    if (op == OP_CLAIM_SUCCESS) {
        // Only tgUSD Engine can claim success
        ctxSender.requiretgUSDEngine(tgUSDEngine);

        // status must be REDEEM_PROCESSING
        requireStatusProcessing(status);

        // Set RedeemAccount status to REDEEM_AVAILABLE
        status = REDEEM_AVAILABLE;

        // Reset cooldownEnd, redeemAmount and tgUSDBurnAmount to 0
        cooldownEnd = 0;
        redeemAmount = 0;
        tgUSDBurnAmount = 0;

        saveData();
        return;
    }

    if (op == OP_ROLLBACK_CLAIM) {
        // Only tgUSD Engine can rollback claim
        ctxSender.requiretgUSDEngine(tgUSDEngine);

        // status must be REDEEM_PROCESSING
        requireStatusProcessing(status);

        // Make sure the fee is enough to rollback claim
        val (totalFee: coins, gasConsume: coins) = computeRollbackClaimFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: int = ctxValue - gasConsume;

        // Send remaining ton to redeemer
        sendSimpleMessage(NON_BOUNCEABLE, redeemer, sendingValue, beginCell().storeMessageOp(OP_COMMENT).storeSlice("Contact Torch Finance for help").endCell(), SEND_MODE_REGULAR);

        // Set RedeemAccount status to REDEEM_PENDING
        status = REDEEM_PENDING;
        
        saveData();
        return;
    }

    if (op == OP_INSTALL) {
        // Only tgUSD Engine can install
        ctxSender.requiretgUSDEngine(tgUSDEngine);

        // Parse install redeem account message body
        (cooldownEnd, redeemAmount, engineJettonWallet, tgUSDBurnAmount) = ctxBody.parseInstallRedeemAccount();

        // If status is not REDEEM_AVAILABLE, it means that it's a duplicate redeem -> Refund
        if (status != REDEEM_AVAILABLE) {
            // Pack Payout message body
            val payoutPayload: cell = packPayoutPayload(queryId, redeemer, REDEEM_DUPLICATED, redeemAsset, tgUSDBurnAmount, createAddressNone(), createAddressNone());

            // Make sure the fee is enough to refund
            val (totalFee: coins, gasConsume: coins) = computeRefundDuplicatedRedeemFee(ctxFwdFee);
            assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
            val sendingValue: int = ctxValue - gasConsume;

            // Send OP_PAYOUT to tgUSD Engine
            sendSimpleMessage(NON_BOUNCEABLE, tgUSDEngine, sendingValue, payoutPayload, SEND_MODE_REGULAR);
            return;
        }

        // If status is REDEEM_AVAILABLE, it means that it's a new redeem -> Set status to REDEEM_PENDING
        // Other variables are set after parsing the install message body
        status = REDEEM_PENDING;

        saveData();
        return;
    }

    if (op == OP_CANCEL_REDEEM_INTERNAL) {
        // Only tgUSD Engine can cancel redeem
        ctxSender.requiretgUSDEngine(tgUSDEngine);

        // status must be REDEEM_PENDING
        requireStatusPending(status);

        // Pack Payout message body
        val payoutPayload: cell = packPayoutPayload(queryId, redeemer, REDEEM_CANCELED, redeemAsset, tgUSDBurnAmount, createAddressNone(), createAddressNone());

        // Make sure the fee is enough to refund
        val (totalFee: coins, gasConsume: coins) = computeCancelRedeemFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: int = ctxValue - gasConsume;

        // Send OP_PAYOUT to tgUSD Engine
        sendSimpleMessage(NON_BOUNCEABLE, tgUSDEngine, sendingValue, payoutPayload, SEND_MODE_REGULAR);

        // Set RedeemAccount status to REDEEM_AVAILABLE
        status = REDEEM_AVAILABLE;

        // Reset cooldownEnd, redeemAmount and tgUSDBurnAmount to 0
        cooldownEnd = 0;
        redeemAmount = 0;
        tgUSDBurnAmount = 0;

        saveData();
        return;
    }

    if (op == OP_UPGRADE_CONTRACT) {
        // Only tgUSD Engine can install
        ctxSender.requiretgUSDEngine(tgUSDEngine);

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