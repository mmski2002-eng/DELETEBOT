import "../common/constants.tolk";
import "../library/log.tolk";

const LOG_STAKING_DEPLOYED = stringCrc32("StakingDeployed");
const LOG_STAKING_WALLET_ADDRESS_TAKEN = stringCrc32("StakingWalletAddressTaken");
const LOG_STAKED = stringCrc32("Staked");
const LOG_UNSTAKED = stringCrc32("Unstaked");
const LOG_WITHDRAW_FAILED = stringCrc32("WithdrawFailed");
const LOG_WITHDRAW_PROCESSED = stringCrc32("WithdrawProcessed");
const LOG_REWARD_SUPPLIED = stringCrc32("RewardSupplied");
const LOG_STAKED_ALLOCATED = stringCrc32("StakedAllocated");
const LOG_STAKED_DEALLOCATED = stringCrc32("StakedDeallocated");
const LOG_CURRENT_QUOTE_PROVIDED = stringCrc32("CurrentQuoteProvided");
const LOG_COOLDOWN_PERIOD_UPDATED = stringCrc32("CooldownPeriodUpdated");
const LOG_VESTING_PERIOD_UPDATED = stringCrc32("VestingPeriodUpdated");

@inline
fun logStakingDeployed(stakedManager: slice, vestingPeriod: Timestamp, cooldownPeriod: Timestamp, admin: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_STAKING_DEPLOYED)
        .storeSlice(stakedManager)
        .storeUint(vestingPeriod, TIMESTAMP_SIZE)
        .storeUint(cooldownPeriod, TIMESTAMP_SIZE)
        .storeSlice(admin);
    emitLog(LOG_STAKING_DEPLOYED, log);
}

@inline
fun logStakingWalletAddressTaken(jettonMasterAddress: slice, jettonWalletAddress: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_STAKING_WALLET_ADDRESS_TAKEN)
        .storeSlice(jettonMasterAddress)
        .storeSlice(jettonWalletAddress);
    emitLog(LOG_STAKING_WALLET_ADDRESS_TAKEN, log);
}

@inline
fun logStaked(
    mintedShares: coins, 
    stakedAmount: coins, 
    staker: slice, 
    recipient: slice, 
    totalShares: coins, 
    totalStaked: coins, 
    remainingStaked: coins
) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_STAKED)
        .storeCoins(mintedShares)
        .storeCoins(stakedAmount)
        .storeSlice(staker)
        .storeSlice(recipient)
        .storeRef(
            beginCell()
                .storeCoins(totalShares)
                .storeCoins(totalStaked)
                .storeCoins(remainingStaked)
                .endCell()
        );
    emitLog(LOG_STAKED, log);
}

@inline
fun logUnstaked(
    burnShares: coins, 
    unstakedAmount: coins, 
    unstaker: slice, 
    cooldownEnd: Timestamp, 
    totalShares: coins, 
    totalStaked: coins,
    lockedForUnstake: coins
) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_UNSTAKED)
        .storeCoins(burnShares)
        .storeCoins(unstakedAmount)
        .storeSlice(unstaker)
        .storeUint(cooldownEnd, TIMESTAMP_SIZE)
        .storeCoins(totalShares)
        .storeCoins(totalStaked)
        .storeCoins(lockedForUnstake);
    emitLog(LOG_UNSTAKED, log);
}

@inline
fun logWithdrawProcessed(
    withdrawStatus: WithdrawStatus,
    unstaker: slice,
    unstakedAmount: coins,
    recipient: slice,
    remainingStaked: coins,
    lockedForUnstake: coins
) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_WITHDRAW_PROCESSED)
        .storeUint(withdrawStatus, WITHDRAW_STATUS_SIZE)
        .storeSlice(unstaker)
        .storeCoins(unstakedAmount)
        .storeSlice(recipient)
        .storeCoins(remainingStaked)
        .storeCoins(lockedForUnstake);
    emitLog(LOG_WITHDRAW_PROCESSED, log);
}

@inline
fun logRewardSupplied(
    totalStaked: coins,
    remainingStaked: coins,
    vestingReward: coins,
    vestingStart: Timestamp,
    vestingPeriod: Timestamp,
    collateralAsset: cell,
    collateralAmount: coins,
    rewardAmount: coins,
    source: slice,
    custodialWallet: slice
) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_REWARD_SUPPLIED)
        .storeCoins(totalStaked)
        .storeCoins(remainingStaked)
        .storeCoins(vestingReward)
        .storeUint(vestingStart, TIMESTAMP_SIZE)
        .storeUint(vestingPeriod, TIMESTAMP_SIZE)
        .storeRef(
            beginCell()
                .storeRef(collateralAsset)
                .storeCoins(collateralAmount)
                .storeCoins(rewardAmount)
                .storeSlice(source)
                .storeSlice(custodialWallet)
                .endCell()
        );
    emitLog(LOG_REWARD_SUPPLIED, log);
}

@inline
fun logStakedAllocated(stakedManager: slice, stakedAmount: coins, remainingStaked: coins, recipient: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_STAKED_ALLOCATED)
        .storeSlice(stakedManager)
        .storeCoins(stakedAmount)
        .storeCoins(remainingStaked)
        .storeSlice(recipient);
    emitLog(LOG_STAKED_ALLOCATED, log);
}

@inline
fun logStakedDeallocated(stakedManager: slice, stakedAmount: coins, remainingStaked: coins) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_STAKED_DEALLOCATED)
        .storeSlice(stakedManager)
        .storeCoins(stakedAmount)
        .storeCoins(remainingStaked);
    emitLog(LOG_STAKED_DEALLOCATED, log);
}

@inline
fun logCurrentQuoteProvided(totalStaked: coins, totalShares: coins, timestamp: Timestamp, sender: slice, recipient: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_CURRENT_QUOTE_PROVIDED)
        .storeCoins(totalStaked)
        .storeCoins(totalShares)
        .storeUint(timestamp, TIMESTAMP_SIZE)   
        .storeSlice(sender)
        .storeSlice(recipient);
    emitLog(LOG_CURRENT_QUOTE_PROVIDED, log);
}

@inline
fun logCooldownPeriodUpdated(admin: slice, newCooldownPeriod: Timestamp) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_COOLDOWN_PERIOD_UPDATED)
        .storeSlice(admin)
        .storeUint(newCooldownPeriod, TIMESTAMP_SIZE);
    emitLog(LOG_COOLDOWN_PERIOD_UPDATED, log);
}

@inline
fun logVestingPeriodUpdated(admin: slice, newVestingPeriod: Timestamp) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_VESTING_PERIOD_UPDATED)
        .storeSlice(admin)
        .storeUint(newVestingPeriod, TIMESTAMP_SIZE);
    emitLog(LOG_VESTING_PERIOD_UPDATED, log);
}