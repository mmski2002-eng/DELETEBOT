import "../common/exit-codes.tolk";
import "../common/op-codes.tolk";
import "../common/constants.tolk";
/**
 * @notice Ensures the jetton wallet is the tgUSD jetton wallet for the staking contract.
 * @param self The address of the jetton wallet to check.
 * @param tgUSDJettonWallet The tgUSD jetton wallet address for the staking contract.
 * @dev 
 * - Used during user staking, admin reward transfers, or when the staked manager deallocates tgUSD assets, to verify the jetton wallet is the correct one for the staking contract.
 * - Reverts with ERROR_NOT_SUPPORTED_JETTON_WALLET if the wallet is not supported.
 */
@inline
fun requiretgUSDStakingJettonWallet(self: slice, tgUSDJettonWallet: slice) {
    assert(self.isSliceBitsEqual(tgUSDJettonWallet), ERROR_NOT_SUPPORTED_JETTON_WALLET);
}

/**
 * @notice Ensures the jetton sender is either the tgUSD Jetton Master or the admin.
 * @param self The address of the sender to check.
 * @param tgUSDJettonMaster The tgUSD Jetton Master address.
 * @param admin The admin address.
 * @dev
 * - Used when the staking contract receives rewards to verify that the Jetton Sender is either the tgUSD Engine or the admin.
 * - Reverts with ERROR_NOT_TGUSD_JETTON_MASTER_OR_ADMIN if the sender is neither.
 */
@inline
fun requiretgUSDJettonMasterOrAdmin(self: slice, tgUSDJettonMaster: slice, admin: slice) {
    assert(self.isSliceBitsEqual(tgUSDJettonMaster) || self.isSliceBitsEqual(admin), ERROR_NOT_TGUSD_JETTON_MASTER_OR_ADMIN);
}

/**
 * @notice Ensures the caller is either the admin or the staked manager.
 * @param self The address of the caller to check.
 * @param admin The admin address.
 * @param stakedManager The staked manager address.
 * @dev 
 * - Used when OP_ALLOCATE_STAKED is called to verify that only the admin or staked manager can transfer tgUSD from the staking contract to the yield aggregator contract to earn returns. 
 * - Reverts with ERROR_NOT_SUPPORTED_ADMIN_OR_STAKED_MANAGER if the caller is neither.
 */
@inline
fun requireAdminOrStakedManager(self: slice, admin: slice, stakedManager: slice) {
    assert(self.isSliceBitsEqual(admin) || self.isSliceBitsEqual(stakedManager), ERROR_NOT_SUPPORTED_ADMIN_OR_STAKED_MANAGER);
}

/**
 * @notice Ensures the share obtained after staking is positive.
 * @param share The amount of share to check.
 * @dev 
 * - Used to verify that the share received by a user after staking is greater than zero. 
 * - Reverts with ERROR_INVALID_SHARE if the share is not positive.
 */
@inline
fun requirePositiveShare(share: coins) {
    assert(share > 0, ERROR_INVALID_SHARE);
}

/**
 * @notice Ensures the unstaked amount obtained after burning shares is positive.
 * @param unstakedAmount The amount of unstaked coins to check.
 * @dev 
 * - Used to verify that the unstaked amount received by a user after burning shares is greater than zero. 
 * - Reverts with ERROR_INVALID_UNSTAKED_AMOUNT if the unstaked amount is not positive.
 */
@inline
fun requirePositiveUnstakedAmount(unstakedAmount: coins) {
    assert(unstakedAmount > 0, ERROR_INVALID_UNSTAKED_AMOUNT);
}

/**
 * @notice Ensures the caller is the stgUSD Jetton Master.
 * @param self The address of the caller to check.
 * @param stgUSDJettonMaster The stgUSD Jetton Master address.
 * @dev 
 * - Used when a user burns shares, triggering stgUSD to send OP_EXTRA_BURN_INFO to the tgUSD staking contract to provide information about the unstake. 
 * - Reverts with ERROR_NOT_SUPPORTED_JETTON_MASTER if the caller is not the stgUSD Jetton Master.
 */
@inline
fun requirestgUSDJettonMaster(self: slice, stgUSDJettonMaster: slice) {
    assert(self.isSliceBitsEqual(stgUSDJettonMaster), ERROR_NOT_SUPPORTED_JETTON_MASTER);
}

/**
 * @notice Ensures the caller is the user's Unstake Account.
 * @param self The address of the caller to check.
 * @param unstakeAccount The expected Unstake Account address.
 * @dev 
 * - Used when the Unstake Account sends OP_WITHDRAW_INTERNAL to the staking contract, staking contract should verify that the source is the user's unstake account. 
 * - Reverts with ERROR_NOT_UNSTAKE_ACCOUNT if the caller is not the expected Unstake Account.
 */
@inline
fun requireUnstakeAccount(self: slice, unstakeAccount: slice) {
    assert(self.isSliceBitsEqual(unstakeAccount), ERROR_NOT_UNSTAKE_ACCOUNT);
}

/**
 * @notice Ensures there is enough staked tgUSD available for allocation.
 * @param remainingStaked The total amount of staked tgUSD available.
 * @param stakedAmount The amount of tgUSD intended for allocation.
 * @dev 
 * - Used when the admin allocates staked tgUSD to a yield aggregator contract to verify that the transfer amount does not exceed the actual staked amount held by the contract. 
 * - Additionally, it ensures that tgUSD already marked for withdrawal by users (awaiting cooldownEnd) is not included in the allocation.
 * - Reverts with ERROR_NOT_ENOUGH_STAKED if there is insufficient staked tgUSD.
 */
@inline
fun requireEnoughStaked(remainingStaked: coins, stakedAmount: coins) {
    assert(remainingStaked >= stakedAmount, ERROR_NOT_ENOUGH_STAKED);
}

/**
 * @notice Ensures the total shares are positive before allowing an unstake operation.
 * @param totalShares The total amount of shares to check.
 * @dev 
 * - Used when a user attempts to unstake to verify that there are staked shares available. If totalShares is not positive, it indicates there are no staked shares to be unstaked.
 * - This situation should not happen, because the user should not be able to burn shares if there are no shares.
 * - Reverts with ERROR_INVALID_SHARE if totalShares is zero or negative.
 */
@inline
fun requirePositiveTotalShares(totalShares: coins) {
    assert(totalShares > 0, ERROR_INVALID_SHARE);
}

/**
 * @notice Ensures the provided oldValue and newValue are different.
 * @param oldValue The old value to check.
 * @param newValue The new value to check.
 * @dev 
 * - Used to verify the validity of values before performing operations. 
 * - Reverts with ERROR_SAME_VALUE if the values are the same.
 */
@inline
fun requireDifferentTimestamp(oldValue: Timestamp, newValue: Timestamp) {
    assert(oldValue != newValue, ERROR_SAME_VALUE);
}


/**
 * @notice Ensures the vesting is not active.
 * @param unvestedAmount The amount of unvested tgUSD.
 * @dev 
 * - Used to verify that the vesting is not active before updating the vesting period.
 * - If the `vestingPeriod` is changed during vesting, it will affect the reward distribution rate. Therefore, modification is prohibited.
 * - Reverts with ERROR_VESTING_ACTIVE if the vesting is active.
 */
@inline
fun requireVestingNotActive(unvestedAmount: coins) {
    assert(unvestedAmount == 0, ERROR_VESTING_ACTIVE);
}

/**
* @notice Ensures the tgUSD and stgUSD Jetton Wallets are not already taken to prevent double top up.
* @param tgUSDJettonWallet The staking's tgUSD Jetton Wallet to check.
* @param stgUSDJettonWallet The staking's stgUSD Jetton Wallet to check.
* @dev 
* - Reverts with ERROR_ALREADY_TOP_UP if the address already exists.
    */
@inline
fun requireJettonMasterAddressNotTaken(tgUSDJettonWallet: slice, stgUSDJettonWallet: slice) {
    assert(tgUSDJettonWallet.addressIsNone(), ERROR_ALREADY_TOP_UP);
    assert(stgUSDJettonWallet.addressIsNone(), ERROR_ALREADY_TOP_UP);
}

/**
 * @notice Ensures the cooldown period is not greater than the maximum cooldown period.
 * @param cooldownPeriod The cooldown period to check.
 * @dev 
 * - Used to verify that the cooldown period is not greater than the maximum cooldown period.
 * - Reverts with ERROR_COOLDOWN_PERIOD_TOO_LONG if the cooldown period is greater than the maximum cooldown period.
 */
@inline
fun requireCooldownPeriodNotTooLong(cooldownPeriod: Timestamp) {
    assert(cooldownPeriod <= MAX_COOLDOWN_PERIOD, ERROR_COOLDOWN_PERIOD_TOO_LONG);
}


/**
 * @notice Ensures the vesting period is not greater than the maximum vesting period.
 * @param vestingPeriod The vesting period to check.
 * @dev 
 * - Used to verify that the vesting period is not greater than the maximum vesting period.
 * - Reverts with ERROR_VESTING_PERIOD_TOO_LONG if the vesting period is greater than the maximum vesting period.
 */
@inline
fun requireVestingPeriodNotTooLong(vestingPeriod: Timestamp) {
    assert(vestingPeriod <= MAX_VESTING_PERIOD, ERROR_VESTING_PERIOD_TOO_LONG);
}
