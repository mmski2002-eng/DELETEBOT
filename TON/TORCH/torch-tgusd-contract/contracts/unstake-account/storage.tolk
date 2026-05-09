import "../common/constants.tolk";

global tgUSDStaking: slice;     // tgUSD Staking contract address that deployed Unstake Account
global unstaker: slice;         // Unstaker's address
global unstakedAmount: coins;   // Amount of tgUSD unstaked that unstaker can withdraw after cooldownEnd
global cooldownEnd: Timestamp;  // Timestamp when unstaked amount can be withdrawn
global availableAmount: coins;  // Amount of tgUSD available for withdrawal immediately (caused by OP_ROLLBACK_WITHDRAW)

@inline
fun loadData() {
    var ds: slice = getContractData().beginParse();
    tgUSDStaking = ds.loadAddress();
    unstaker = ds.loadAddress();
    unstakedAmount = ds.loadCoins();
    cooldownEnd = ds.loadUint(TIMESTAMP_SIZE);
    availableAmount = ds.loadCoins();
    ds.assertEndOfSlice();
}

@inline
fun saveData() {
    setContractData(
        beginCell()
            .storeSlice(tgUSDStaking)
            .storeSlice(unstaker)
            .storeCoins(unstakedAmount)
            .storeUint(cooldownEnd, TIMESTAMP_SIZE)
            .storeCoins(availableAmount)
            .endCell()
    );  
}