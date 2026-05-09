import "../common/constants.tolk";

global tgUSDEngine: slice;          // tgUSD Engine's address that deployed this contract
global redeemer: slice;             // Redeemer's address
global cooldownEnd: Timestamp;      // Cooldown end timestamp. Redeemer can claim collateral after cooldownEnd
global status: RedeemAccountStatus; // Redempt status (0: Available, 1: Pending, 2: Processing)
global tgUSDBurnAmount: coins;      // Amount of tgUSD burned to retrieve collateral
global redeemAsset: cell;           // Redempt asset
global redeemAmount: coins;         // Redempt amount
global engineJettonWallet: slice;   // tgUSD Engine's jetton wallet address that used to transfer collateral to redeemer

@inline
fun loadData() {
    var ds: slice = getContractData().beginParse();
    tgUSDEngine = ds.loadAddress();
    redeemer = ds.loadAddress();
    cooldownEnd = ds.loadUint(TIMESTAMP_SIZE);
    status = ds.loadUint(REDEEM_ACCOUNT_STATUS_SIZE);
    var redeemPayloadSlice: slice = ds.loadRef().beginParse();
    redeemAsset = redeemPayloadSlice.loadRef();
    redeemAmount = redeemPayloadSlice.loadCoins();
    engineJettonWallet = redeemPayloadSlice.loadAddress();
    tgUSDBurnAmount = redeemPayloadSlice.loadCoins();
    redeemPayloadSlice.assertEndOfSlice();
    ds.assertEndOfSlice();
}

@inline
fun saveData() {
    setContractData(
        beginCell()
            .storeSlice(tgUSDEngine)
            .storeSlice(redeemer)
            .storeUint(cooldownEnd, TIMESTAMP_SIZE)
            .storeUint(status, REDEEM_ACCOUNT_STATUS_SIZE)
            .storeRef(
                beginCell()
                    .storeRef(redeemAsset)
                    .storeCoins(redeemAmount)
                    .storeSlice(engineJettonWallet)
                    .storeCoins(tgUSDBurnAmount)
                    .endCell()
            )
            .endCell()
    );
}