import "../common/op-codes.tolk";
import "../common/exit-codes.tolk";
import "../common/constants.tolk";

// Parse

@inline 
fun parseTakeWalletAddress(mutate self: slice): slice {
    val walletAddress: slice = self.loadAddress();
    self.skipMaybeRef(); // skip `includeAddress`
    
    self.assertEndOfSlice();
    return walletAddress;
}

@inline
fun parseJettonNotification(mutate self: slice): (coins, slice, slice) {
    val jettonAmount: coins = self.loadCoins();
    val jettonSender: slice = self.loadAddress();
    val forwardPayload: cell? = self.loadMaybeRef();
    // Forward payload is required in our all cases
    assert(forwardPayload != null, ERROR_FORWARD_PAYLOAD_NULL);

    self.assertEndOfSlice();
    return (jettonAmount, jettonSender, forwardPayload!.beginParse());
}

@inline
fun parseExtraBurnInfo(mutate self: slice): (slice, coins, slice) { 
    val fromAddress: slice = self.loadAddress();
    val burnAmount: coins = self.loadCoins();
    val customPayload: cell? = self.loadMaybeRef();
    assert(customPayload != null, ERROR_CUSTOM_PAYLOAD_NULL);

    self.assertEndOfSlice();
    return (fromAddress, burnAmount, customPayload!.beginParse());
}

@inline
fun parseUpgradeContract(mutate self: slice): (cell?, cell?) {
    val newData: cell? = self.loadMaybeRef();
    val newCode: cell? = self.loadMaybeRef();
    self.assertEndOfSlice();
    return (newData, newCode);
}

@inline
fun parseUpgradeChildContract(mutate self: slice): (slice, cell?) {
    val childContract: slice = self.loadAddress();
    val newData: cell? = self.loadMaybeRef();
    self.assertEndOfSlice();
    return (childContract, newData);
}

@inline
fun parseCallToJettonMaster(mutate self: slice): (slice, coins, cell) {
    val to: slice = self.loadAddress();
    val tonAmount: coins = self.loadCoins();
    val masterMsg: cell = self.loadRef();
    self.assertEndOfSlice();
    return (to, tonAmount, masterMsg);
}

@inline
fun parseUpgradeJettonMaster(mutate self: slice): (cell, cell) {
    val newData: cell = self.loadRef();
    val newCode: cell = self.loadRef();
    self.assertEndOfSlice();
    return (newData, newCode);
}

// Pack 

@pure
@inline
fun packProvideWalletAddress(queryId: int, ownerAddress: slice, includeAddress: bool): cell {
    return beginCell()
        .storeMessageOp(OP_PROVIDE_WALLET_ADDRESS)
        .storeMessageQueryId(queryId)
        .storeSlice(ownerAddress)
        .storeBool(includeAddress)
        .endCell();
}

@pure
@inline
fun packCommentPayload(comment: slice): cell {
    return beginCell()
        .storeSlice(comment)
        .endCell();
}

@pure
@inline
fun packBaseContractInit(deployer: slice, proof: int): cell {
    return beginCell()
    .storeSlice(deployer)
    .storeUint(proof, CONTRACT_PROOF_SIZE)
    .endCell();
}

/*
 * @notice Packs an install message for deploying a contract by baseContract
 * @param queryId The unique query identifier
 * @param newCode The new code to be updated
 * @param newData The new data to be updated
 * @param callbackPayload After deploying contract, it will send callbackPayload to assigned address
 * @return A cell containing the install message
*/
@pure
@inline
fun packInstall(queryId: int, newCode: cell, newData: cell, callbackPayload: cell?): cell {
    return beginCell()
        .storeMessageOp(OP_INSTALL)
        .storeMessageQueryId(queryId)
        .storeRef(newCode)
        .storeRef(newData)
        .storeMaybeRef(callbackPayload)
        .endCell();
}


@pure
@inline
fun packUpgrade(queryId: int, newData: cell?, newCode: cell?): cell {
    return beginCell()
        .storeMessageOp(OP_UPGRADE_CONTRACT)
        .storeMessageQueryId(queryId)
        .storeMaybeRef(newData)
        .storeMaybeRef(newCode)
        .endCell();
}

@pure
@inline
fun packJettonMasterUpgrade(queryId: int, newData: cell, newCode: cell): cell {
    return beginCell()
        .storeMessageOp(OP_UPGRADE_CONTRACT)
        .storeMessageQueryId(queryId)
        .storeRef(newData)
        .storeRef(newCode)
        .endCell();
}

@pure
@inline
fun packCallToJettonMaster(queryId: int, to: slice, tonAmount: coins, masterMsg: cell): cell {
    return beginCell()
        .storeMessageOp(OP_CALL_TO)
        .storeMessageQueryId(queryId)
        .storeSlice(to)
        .storeCoins(tonAmount)
        .storeRef(masterMsg)
        .endCell();
}

@pure
@inline
fun packChangeJettonMasterAdmin(queryId: int, newJettonMasterAdmin: slice): cell {
    return beginCell()
        .storeMessageOp(OP_CHANGE_ADMIN)
        .storeMessageQueryId(queryId)
        .storeSlice(newJettonMasterAdmin)
        .endCell();
}

@pure
@inline
fun packComment(comment: slice): cell {
    return beginCell()
        .storeMessageOp(OP_COMMENT)
        .storeSlice(comment)
        .endCell();
}

@pure
@inline
fun packChangeJettonMasterContent(queryId: int, newContent: slice): cell {
    return beginCell()
        .storeMessageOp(OP_CHANGE_METADATA_URI)
        .storeMessageQueryId(queryId)
        .storeSlice(newContent)
        .endCell();
}