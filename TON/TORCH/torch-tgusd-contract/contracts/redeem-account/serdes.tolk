import "../common/op-codes.tolk";
import "../common/constants.tolk";
import "../common/types.tolk";

// Parse

@inline
fun parseInstallRedeemAccount(mutate self: slice): (Timestamp, coins, slice, coins) {
    self.loadRef(); // code
    var storageSlice: slice = self.loadRef().beginParse(); // data
    self.loadMaybeRef(); // callback payload

    storageSlice.loadAddress(); // tgUSDEngine
    storageSlice.loadAddress(); // redeemer
    val cooldownEnd: Timestamp = storageSlice.loadUint(TIMESTAMP_SIZE); // cooldownEnd
    storageSlice.loadUint(REDEEM_ACCOUNT_STATUS_SIZE); // status

    var redeemPayloadSlice: slice = storageSlice.loadRef().beginParse();
    redeemPayloadSlice.loadRef(); // redeemAsset
    val redeemAmount: coins = redeemPayloadSlice.loadCoins(); // redeemAmount
    val engineJettonWallet: slice = redeemPayloadSlice.loadAddress(); // engineJettonWallet
    val tgUSDBurnAmount: coins = redeemPayloadSlice.loadCoins(); // tgUSDBurnAmount
    redeemPayloadSlice.assertEndOfSlice();
    storageSlice.assertEndOfSlice();

    return (cooldownEnd, redeemAmount, engineJettonWallet, tgUSDBurnAmount);
}

// Pack

@pure
@inline
fun packPayoutPayload(queryId: QueryId, redeemer: slice, redeemStatus: RedeemStatus, redeemAsset: cell, returnAmount: coins, engineJettonWallet: slice, recipient: slice): cell {
    return beginCell()
        .storeMessageOp(OP_PAYOUT)
        .storeMessageQueryId(queryId)
        .storeSlice(redeemer)
        .storeUint(redeemStatus, REDEEM_STATUS_SIZE)
        .storeRef(
            beginCell()
                .storeRef(redeemAsset)
                .storeCoins(returnAmount)
                .storeSlice(engineJettonWallet)
                .endCell()
        )
        .storeSlice(recipient)

        .endCell();
}