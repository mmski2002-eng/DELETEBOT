import "../common/op-codes.tolk";
import "../common/constants.tolk";

// Parse

@inline
fun parseInstallUnstakeAccount(mutate self: slice): (coins, Timestamp) {
    self.loadRef(); // code
    var storageSlice: slice = self.loadRef().beginParse(); // data
    self.loadMaybeRef(); // callback payload

    storageSlice.loadAddress(); // tgUSDStaking
    storageSlice.loadAddress(); // unstaker
    val unstakedAmount: coins = storageSlice.loadCoins(); // unstakedAmount
    val cooldownEnd: Timestamp = storageSlice.loadUint(TIMESTAMP_SIZE);
    storageSlice.loadCoins(); // availableAmount
    storageSlice.assertEndOfSlice();

    return (unstakedAmount, cooldownEnd);
}

// Pack

@pure
@inline
fun packWithdrawInternal(queryId: QueryId, unstaker: slice, unstakedAmount: coins, recipient: slice): cell {
    return beginCell()
        .storeMessageOp(OP_WITHDRAW_INTERNAL)
        .storeMessageQueryId(queryId)
        .storeSlice(unstaker)
        .storeCoins(unstakedAmount)
        .storeSlice(recipient)
        .endCell();
}
