import "../common/constants.tolk";
import "../common/types.tolk";

global tgUSDJettonMaster: slice;        // tgUSD Jetton Master to mint tgUSD and forward OP_EXTRA_BURN_INFO to tgUSD Engine
global tgUSDStaking: slice;             // tgUSD Staking Contract to receive tgUSD rewards minted by tgUSD Engine
global signerKey: SignerKey;            // Signer key to authorize mint and redeem Order payload
global isHalt: bool;                    // Whether the contract is halted
global redeemWhitelistRoot: MerkleRoot; // Merkle root of redeem whitelist
global custodialWalletsDict: dict;      // Dictionary of supported custodial wallets that will receive collateral. Key: custodial wallet address, Value: coins (Right now is not used)
global admin: slice;                    // Current admin address (Multi-sig wallet)
global nextAdmin: slice;                // Next admin address
global jettonMastersDict: dict;         // Dictionary of supported Jetton Masters. Key: Jetton Master address, Value: Engine's Jetton Wallet address
global jettonWalletsBalDict: dict;      // Dictionary of Jetton balances. Key: Engine's Jetton Wallet address, Value: Jetton balance for Engine's Jetton Wallet
global redeemAccountCode: cell;         // Redeem Account code
global baseCode: cell;                  // Base code

@inline
fun loadData() {
    var ds: slice = getContractData().beginParse();
    tgUSDJettonMaster = ds.loadAddress();
    tgUSDStaking = ds.loadAddress();
    isHalt = ds.loadBool();
    redeemWhitelistRoot = ds.loadUint(MERKLE_ROOT_SIZE);
    custodialWalletsDict = ds.loadDict();

    var adminInfoSlice: slice = ds.loadRef().beginParse();
    admin = adminInfoSlice.loadAddress();
    nextAdmin = adminInfoSlice.loadAddress();
    signerKey = adminInfoSlice.loadUint(SIGNER_KEY_SIZE);
    adminInfoSlice.assertEndOfSlice();

    var jettonInfoSlice: slice = ds.loadRef().beginParse();
    jettonMastersDict = jettonInfoSlice.loadDict();
    jettonWalletsBalDict = jettonInfoSlice.loadDict();
    jettonInfoSlice.assertEndOfSlice();

    var contractsCodeSlice: slice = ds.loadRef().beginParse();
    baseCode = contractsCodeSlice.loadRef();
    redeemAccountCode = contractsCodeSlice.loadRef();
    contractsCodeSlice.assertEndOfSlice();
    ds.assertEndOfSlice();
}

@inline
fun saveData() {
    setContractData(
        beginCell()
            .storeSlice(tgUSDJettonMaster)
            .storeSlice(tgUSDStaking)
            .storeBool(isHalt)
            .storeUint(redeemWhitelistRoot, MERKLE_ROOT_SIZE)
            .storeDict(custodialWalletsDict)
            .storeRef(
                beginCell()
                    .storeSlice(admin)
                    .storeSlice(nextAdmin)
                    .storeUint(signerKey, SIGNER_KEY_SIZE)
                    .endCell()
            )
            .storeRef(
                beginCell()
                    .storeDict(jettonMastersDict)
                    .storeDict(jettonWalletsBalDict)
                    .endCell()
            )
            .storeRef(
                beginCell()
                    .storeRef(baseCode)
                    .storeRef(redeemAccountCode)
                    .endCell()
            )
            .endCell()
    );
}