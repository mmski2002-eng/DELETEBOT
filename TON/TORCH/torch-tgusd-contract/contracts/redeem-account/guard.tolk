import "../common/exit-codes.tolk";
import "../common/constants.tolk";

/**
 * @notice Ensures the caller is either the redeemer or the tgUSD Engine.
 * @param self The address of the caller.
 * @param redeemer The address of the redeemer.
 * @param tgUSDEngine The address of the tgUSD Engine.
 * @dev 
 * - Used to verify that only the redeemer or the engine can call OP_CLAIM. 
 * - Reverts with ERROR_NOT_REDEEMER_OR_ENGINE if the caller is neither.
 */
@inline
fun requireRedeemerOrEngine(self: slice, redeemer: slice, tgUSDEngine: slice) {
    assert(self.isSliceBitsEqual(redeemer) || self.isSliceBitsEqual(tgUSDEngine), ERROR_NOT_REDEEMER_OR_ENGINE);
}

/**
 * @notice Ensures the caller is the tgUSD Engine.
 * @param self The address of the caller.
 * @param tgUSDEngine The address of the tgUSD Engine.
 * @dev 
 * - Used to verify that only the tgUSD Engine can call OP_ROLLBACK_CLAIM, OP_CANCEL_REDEEM_INTERNAL, OP_CLAIM_SUCCESS, OP_INSTALL and OP_UPGRADE. 
 * - Reverts with ERROR_NOT_TGUSD_ENGINE if the caller is not the engine.
 */
@inline
fun requiretgUSDEngine(self: slice, tgUSDEngine: slice) {
    assert(self.isSliceBitsEqual(tgUSDEngine), ERROR_NOT_TGUSD_ENGINE);
}

/**
 * @notice Ensures the redeem status is pending before allowing OP_CLAIM.
 * @param status The current status of the redeem process.
 * @dev 
 * - Used to verify that OP_CLAIM can only be called when the status is REDEEM_PENDING. 
 * - Reverts with ERROR_WRONG_REDEEM_STATUS if the status is not pending.
 */
@inline
fun requireStatusPending(status: RedeemAccountStatus) {
    assert(status == REDEEM_PENDING, ERROR_WRONG_REDEEM_STATUS);
}

/**
 * @notice Ensures the redeem status is processing before allowing OP_CLAIM_SUCCESS or OP_ROLLBACK_CLAIM.
 * @param status The current status of the redeem process.
 * @dev 
 * - Used to verify that OP_CLAIM_SUCCESS and OP_ROLLBACK_CLAIM can only be called when the status is REDEEM_PROCESSING. 
 * - Reverts with ERROR_WRONG_REDEEM_STATUS if the status is not processing.
 */
@inline
fun requireStatusProcessing(status: RedeemAccountStatus) {
    assert(status == REDEEM_PROCESSING, ERROR_WRONG_REDEEM_STATUS);
}

/**
 * @notice Ensures the cooldown period has passed before allowing OP_CLAIM.
 * @param cooldownEnd The timestamp when the cooldown period ends.
 * @dev 
 * - Used to verify that OP_CLAIM can only be called after the cooldown period has passed.
 * - If caller is tgUSD Engine, cooldownEnd is ignored.
 * - Reverts with ERROR_COOLDOWN_NOT_PASSED if the cooldown period has not passed.
 */
@inline
fun requireAfterCooldown(cooldownEnd: Timestamp) {
    assert(cooldownEnd <= now(), ERROR_COOLDOWN_NOT_PASSED);
}