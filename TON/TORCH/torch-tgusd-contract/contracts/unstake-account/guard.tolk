import "../common/exit-codes.tolk";
    
/**
 * @notice Ensures the caller is the tgUSD Staking contract.
 * @param self The address of the caller to check.
 * @param tgUSDStaking The tgUSD Staking contract address.
 * @dev 
 * - Used when the Staking contract sends OP_INSTALL, OP_UPGRADE_CONTRACT, or OP_ROLLBACK_WITHDRAW to verify that the source is the staking contract. 
 * - Reverts with ERROR_NOT_TGUSD_STAKING if the caller is not the staking contract.
 */
@inline
fun requiretgUSDStaking(self: slice, tgUSDStaking: slice) {
    assert(self.isSliceBitsEqual(tgUSDStaking), ERROR_NOT_TGUSD_STAKING);
}

/**
 * @notice Ensures the caller is either the Unstaker or the Staking contract.
 * @param self The address of the caller to check.
 * @param unstaker The address of the Unstaker.
 * @param staking The address of the Staking contract.
 * @dev 
 * - Used to verify that only the Unstaker or the Staking contract can call OP_WITHDRAW on the Unstake Account. 
 * - Reverts with ERROR_NOT_UNSTAKER_OR_STAKING if the caller is neither.
 */
@inline
fun requireUnstakerOrStaking(self: slice, unstaker: slice, staking: slice) {
    assert(self.isSliceBitsEqual(unstaker) || self.isSliceBitsEqual(staking), ERROR_NOT_UNSTAKER_OR_STAKING);
}

/**
 * @notice Ensures the total amount available for withdrawal is positive.
 * @param totalUnstakedAmount The total amount available for withdrawal, including unstakedAmount after cooldownEnd and availableAmount.
 * @dev 
 * - Used to verify that the sum of unstakedAmount (available after cooldownEnd) and availableAmount (immediately available if OP_ROLLBACK_WITHDRAW is triggered) is greater than zero before allowing a withdrawal. 
 * - Reverts with ERROR_NOT_POSITIVE_WITHDRAW if the total amount is not positive.
 */
@inline
fun requirePositiveWithdraw(totalUnstakedAmount: coins) {
    assert(totalUnstakedAmount > 0, ERROR_NOT_POSITIVE_WITHDRAW);
}
