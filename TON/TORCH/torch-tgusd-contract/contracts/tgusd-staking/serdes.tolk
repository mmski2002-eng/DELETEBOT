import "../common/constants.tolk";
import "../common/op-codes.tolk";

// Parse

@inline
fun parseStake(mutate self: slice): slice {
    val recipient: slice = self.loadAddress();
    self.assertEndOfSlice();
    return recipient;
}

@inline
fun parseWithdrawInternal(mutate self: slice): (slice, coins, slice) {
    val unstaker: slice = self.loadAddress();
    val unstakedAmount: coins = self.loadCoins();
    val recipient: slice = self.loadAddress();
    self.assertEndOfSlice();
    return (unstaker, unstakedAmount, recipient);
}

@inline
fun parseSupplyRewardFp(mutate self: slice): (cell, coins, slice, slice) {
    val collateralAsset: cell = self.loadRef(); // collateralAsset is the collateral asset that generated the reward
    val collateralAmount: coins = self.loadCoins(); // collateralAmount is the amount of collateral that generated the reward
    val source: slice = self.loadAddress(); // source can be admin/custodial wallets in tgUSD Engine. If refund triggered, will refund to source.
    val custodialWallet: slice = self.loadAddress(); // The collateral that generated the reward was transferred to this custodial wallet
    self.assertEndOfSlice();
    return (collateralAsset, collateralAmount, source, custodialWallet);
}

@inline
fun parseAllocateStaked(mutate self: slice): (coins, slice, cell?) {
    val stakedAmount: coins = self.loadCoins();
    val recipient: slice = self.loadAddress();
    val customPayload: cell? = self.loadMaybeRef();
    self.assertEndOfSlice();
    return (stakedAmount, recipient, customPayload);
}

@inline
fun parseProvideCurrentQuote(mutate self: slice): (slice, cell?) {
    val recipient: slice = self.loadAddress();
    val customPayload: cell? = self.loadMaybeRef();
    self.assertEndOfSlice();
    return (recipient, customPayload);
}

@inline
fun parseTopUp(mutate self: slice): (slice, slice, Timestamp, Timestamp, cell, cell) {
    val stgUSDJettonMaster: slice = self.loadAddress();
    val stakedManager: slice = self.loadAddress();
    val vestingPeriod: Timestamp = self.loadUint(TIMESTAMP_SIZE);
    val cooldownPeriod: Timestamp = self.loadUint(TIMESTAMP_SIZE);
    val baseCode: cell = self.loadRef();
    val unstakeAccountCode: cell = self.loadRef();
    self.assertEndOfSlice();
    return (stgUSDJettonMaster, stakedManager, vestingPeriod, cooldownPeriod, baseCode, unstakeAccountCode);
}

// Pack

@pure
@inline
fun packUnstakeAccountProof(tgUSDStaking: slice, unstaker: slice): ContractProof {
    return beginCell()
        .storeSlice(tgUSDStaking)
        .storeSlice(unstaker)
        .endCell()
        .cellHash();
}

@pure
@inline
fun packUnstakeAccountStorage(
    tgUSDStaking: slice,
    unstaker: slice,
    unstakedAmount: coins,
    cooldownEnd: Timestamp
): cell {
    return beginCell()
        .storeSlice(tgUSDStaking)
        .storeSlice(unstaker)
        .storeCoins(unstakedAmount)
        .storeUint(cooldownEnd, TIMESTAMP_SIZE)
        .storeCoins(0) // availableAmount
        .endCell();
}

@pure
@inline
fun packRollbackWithdraw(queryId: QueryId, unstakedAmount: coins): cell {
    return beginCell()
        .storeMessageOp(OP_ROLLBACK_WITHDRAW)
        .storeMessageQueryId(queryId)
        .storeCoins(unstakedAmount)
        .endCell();
}

@pure
@inline
fun packTakeCurrentQuote(queryId: QueryId, totalStakedAmountWithoutUnvested: coins, totalShares: coins, timestamp: Timestamp, customPayload: cell?): cell {
    return beginCell()
        .storeMessageOp(OP_TAKE_CURRENT_QUOTE)
        .storeMessageQueryId(queryId)
        .storeCoins(totalStakedAmountWithoutUnvested)
        .storeCoins(totalShares)
        .storeUint(timestamp, TIMESTAMP_SIZE)
        .storeMaybeRef(customPayload)
        .endCell();
}

@pure
@inline
fun packWithdraw(queryId: QueryId): cell {
    return beginCell()
        .storeMessageOp(OP_WITHDRAW)
        .storeMessageQueryId(queryId)
        .storeSlice(createAddressNone())
        .endCell();
}
