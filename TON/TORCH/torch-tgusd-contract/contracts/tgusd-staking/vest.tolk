/**
 * @notice Calculates the unvested reward amount based on the elapsed time since vesting began.
 * @param vestingStart The timestamp when vesting started.
 * @param vestingPeriod The total duration of the vesting period.
 * @param vestingReward The total amount of reward to be vested.
 * @return coins The amount of reward that is still unvested.
 * @dev 
 * - If the time since vesting started is greater than or equal to the vesting period, it means there is no ongoing vesting reward.
 * - Otherwise, calculates the remaining vesting period and proportionally computes the unvested amount based on the vesting reward.
 */
@pure
@inline
fun getUnvestedAmount(vestingStart: Timestamp, vestingPeriod: Timestamp, vestingReward: coins): coins {
    val timeSinceVestingStart = now() - vestingStart;
    if (timeSinceVestingStart >= vestingPeriod) {
        return 0;
    }
    
    val remainingVestingPeriod = vestingPeriod - timeSinceVestingStart;
    return mulDivFloor(remainingVestingPeriod, vestingReward, vestingPeriod);
}