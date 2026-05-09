import "../common/constants.tolk";

global admin: slice;                // Current admin address (Multi-sig wallet)
global nextAdmin: slice;            // Next admin address
global stakedManager: slice;        // Staked manager address that can allocate and deallocate tgUSD to the yield aggregator contract
global isHalt: bool;                // Whether the contract is halted
global cooldownPeriod: Timestamp;   // Cooldown period before withdrawal is allowed
global vestingStart: Timestamp;     // Vesting start time
global totalStaked: coins;          // Total amount of tgUSD staked, including user stakes and rewards
global totalShares: coins;          // Total amount of shares issued by the staking contract
global vestingReward: coins;        // Total amount of rewards that will be vested
global vestingPeriod: Timestamp;    // Vesting period
global remainingStaked: coins;      // The remaining amount of tgUSD that can be unstaked/allocated
global lockedForUnstake: coins;     // Total amount of tgUSD that is locked for unstake
global tgUSDJettonMaster: slice;    // tgUSD Jetton Master address to verify the reward source
global stgUSDJettonMaster: slice;   // stgUSD Jetton Master address to mint shares and verify the unstake source
global tgUSDJettonWallet: slice;    // tgUSD Jetton wallet address 
global stgUSDJettonWallet: slice;   // stgUSD Jetton wallet address
global unstakeAccountCode: cell;    // Unstake Account code
global baseCode: cell;              // Base code

@inline
fun loadData() {
    var ds: slice = getContractData().beginParse();
    admin = ds.loadAddress();
    nextAdmin = ds.loadAddress();
    stakedManager = ds.loadAddress();
    isHalt = ds.loadBool();
    cooldownPeriod = ds.loadUint(TIMESTAMP_SIZE);

    var stakeInfoSlice: slice = ds.loadRef().beginParse();
    totalStaked = stakeInfoSlice.loadCoins();
    totalShares = stakeInfoSlice.loadCoins();
    remainingStaked = stakeInfoSlice.loadCoins();
    vestingReward = stakeInfoSlice.loadCoins();
    vestingPeriod = stakeInfoSlice.loadUint(TIMESTAMP_SIZE);
    vestingStart = stakeInfoSlice.loadUint(TIMESTAMP_SIZE);
    lockedForUnstake = stakeInfoSlice.loadCoins();
    stakeInfoSlice.assertEndOfSlice();

    var jettonMastersInfoSlice: slice = ds.loadRef().beginParse();
    tgUSDJettonMaster = jettonMastersInfoSlice.loadAddress();
    stgUSDJettonMaster = jettonMastersInfoSlice.loadAddress();
    jettonMastersInfoSlice.assertEndOfSlice();

    var jettonWalletsInfoSlice: slice = ds.loadRef().beginParse();
    tgUSDJettonWallet = jettonWalletsInfoSlice.loadAddress();
    stgUSDJettonWallet = jettonWalletsInfoSlice.loadAddress();
    jettonWalletsInfoSlice.assertEndOfSlice();

    var contractsCodeSlice: slice = ds.loadRef().beginParse();
    baseCode = contractsCodeSlice.loadRef();
    unstakeAccountCode = contractsCodeSlice.loadRef();
    contractsCodeSlice.assertEndOfSlice();
    ds.assertEndOfSlice();
}

@inline
fun saveData() {
    setContractData(
        beginCell()
            .storeSlice(admin)
            .storeSlice(nextAdmin)
            .storeSlice(stakedManager)
            .storeBool(isHalt)
            .storeUint(cooldownPeriod, TIMESTAMP_SIZE)
            .storeRef(
                beginCell()
                    .storeCoins(totalStaked)
                    .storeCoins(totalShares)
                    .storeCoins(remainingStaked)
                    .storeCoins(vestingReward)
                    .storeUint(vestingPeriod, TIMESTAMP_SIZE)
                    .storeUint(vestingStart, TIMESTAMP_SIZE)
                    .storeCoins(lockedForUnstake)
                    .endCell()
            )
            .storeRef(
                beginCell()
                    .storeSlice(tgUSDJettonMaster)
                    .storeSlice(stgUSDJettonMaster)
                    .endCell()
            )
            .storeRef(
                beginCell()
                    .storeSlice(tgUSDJettonWallet)
                    .storeSlice(stgUSDJettonWallet)
                    .endCell()
            )
            .storeRef(
                beginCell()
                    .storeRef(baseCode)
                    .storeRef(unstakeAccountCode)
                    .endCell()
            )
            .endCell()
    );  
}