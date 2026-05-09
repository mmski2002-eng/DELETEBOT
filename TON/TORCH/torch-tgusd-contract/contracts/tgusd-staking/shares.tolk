/**
 * @notice Converts a staked amount of tgUSD to shares.
 * @param totalShares The total amount of shares issued by the staking contract.
 * @param totalStaked The total amount of tgUSD staked, including user stakes and rewards.
 * @param unvestedAmount The amount of rewards not yet vested.
 * @param stakeAmount The amount of tgUSD being staked.
 * @return coins The equivalent amount of shares for the staked tgUSD.
 * @dev 
 * - If this is the first time staking (totalStaked is zero), the stakeAmount is directly returned as shares.
 * - Otherwise, the stakeAmount is converted to shares based on the current totalShares and adjusted totalStaked (subtracting unvestedAmount).
 */
@inline 
fun convertToShares(totalShares: coins, totalStaked: coins, unvestedAmount: coins, stakeAmount: coins): coins {
    // First Time Staking
    if (totalStaked == 0) {
        return stakeAmount;
    }

    // Convert stakeAmount to shares
    return mulDivFloor(stakeAmount, totalShares, (totalStaked - unvestedAmount));
}

/**
 * @notice Converts shares back to a staked amount of tgUSD.
 * @param totalShares The total amount of shares issued by the staking contract.
 * @param totalStaked The total amount of tgUSD staked, including user stakes and rewards.
 * @param unvestedAmount The amount of rewards not yet vested.
 * @param shares The amount of shares being converted.
 * @return coins The equivalent amount of tgUSD for the given shares.
 * @dev 
 * - Converts shares to a staked amount based on the current totalShares and adjusted totalStaked (subtracting unvestedAmount).
 */
@inline
fun convertToStaked(totalShares: coins, totalStaked: coins, unvestedAmount: coins, shares: coins): coins {
    // If shares are equal to total shares (Last one unstaked), return the total staked amount + unvested amount
    if (shares == totalShares) {
        return totalStaked - unvestedAmount;
    }

    // Convert shares to stakedAmount
    return mulDivFloor(shares, (totalStaked - unvestedAmount), totalShares);
}
