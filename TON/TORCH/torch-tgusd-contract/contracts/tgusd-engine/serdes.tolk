import "../common/constants.tolk";
import "../library/merkle.tolk";
import "../library/address.tolk";
import "../common/op-codes.tolk";

// Parse

@inline
fun convertAddressesCellToTuple(nestedAddress: cell): tuple {
    var depth: int = nestedAddress.getCellDepth() + 1;
    var addressesSlice: slice = nestedAddress.beginParse();
    var addressesTuple: tuple = createEmptyTuple(); 
    
    repeat (depth) {
        while (!addressesSlice.isEndOfSliceBits()) {
            addressesTuple.tuplePush(addressesSlice.loadAddress());
        }

        if (!addressesSlice.isEndOfSliceRefs()) {
            addressesSlice = addressesSlice.loadRef().beginParse();
        }
    }

    addressesSlice.assertEndOfSlice();
    return addressesTuple;
}

@inline
fun parseTopUp(mutate self: slice): (slice, slice, tuple, dict, SignerKey, MerkleRoot, cell, cell) {
    var tgUSDInfoSlice: slice = self.loadRef().beginParse();
    val tgUSDJettonMaster: slice = tgUSDInfoSlice.loadAddress();
    val tgUSDStaking: slice = tgUSDInfoSlice.loadAddress();
    tgUSDInfoSlice.assertEndOfSlice();

    val nestedJettonMasters: cell = self.loadRef();
    val custodialWallets: dict = self.loadDict();
    val signerKey: SignerKey = self.loadUint(SIGNER_KEY_SIZE);
    val redeemWhitelistRoot: MerkleRoot = self.loadUint(MERKLE_ROOT_SIZE);

    var contractsCodeSlice: slice = self.loadRef().beginParse();
    val baseCode: cell = contractsCodeSlice.loadRef();
    val redeemAccountCode: cell = contractsCodeSlice.loadRef();
    contractsCodeSlice.assertEndOfSlice();

    self.assertEndOfSlice();
    return (tgUSDJettonMaster, tgUSDStaking, convertAddressesCellToTuple(nestedJettonMasters), custodialWallets, signerKey, redeemWhitelistRoot, baseCode, redeemAccountCode);
}

@inline
fun parseDepositFp(mutate self: slice): (slice, OrderHash, slice, OrderType, Timestamp, slice, cell, coins, coins, slice, Timestamp) {
    val signature: slice = self.loadBits(SIGNATURE_SIZE);
    val order: cell = self.loadRef();
    val orderHash: OrderHash = order.cellHash();
    val recipient: slice = self.loadAddress();
    self.assertEndOfSlice();

    // Parse order
    val (orderType: OrderType, expiration: Timestamp, user: slice, collateralAsset: cell, collateralAmount: coins, tgUSDAmount: coins, custodialWallet: slice, cooldownEnd: Timestamp) = parseOrder(order);

    return (signature, orderHash, recipient, orderType, expiration, user, collateralAsset, collateralAmount, tgUSDAmount, custodialWallet, cooldownEnd);
}

@inline
fun parseRequestRedeem(mutate self: slice): (slice, OrderHash, OrderType, Timestamp, slice, cell, coins, coins, slice, Timestamp, slice, bool) {
    val signature: slice = self.loadBits(SIGNATURE_SIZE);
    val order: cell = self.loadRef();
    val orderHash: OrderHash = order.cellHash();
    val exoticCell: cell = self.loadRef();
    self.assertEndOfSlice();

    // Parse order
    val (orderType: OrderType, expiration: Timestamp, user: slice, collateralAsset: cell, collateralAmount: coins, tgUSDAmount: coins, custodialWallet: slice, cooldownEnd: Timestamp) = parseOrder(order);

    // Parse exoticCell to get redeemWhitelistProof
    var (redeemWhitelistProof: slice, isExotic: bool) = exoticCell.beginParseExotic();
    
    return (signature, orderHash, orderType, expiration, user, collateralAsset, collateralAmount, tgUSDAmount, custodialWallet, cooldownEnd, redeemWhitelistProof, isExotic);
}

@inline
fun parseOrder(order: cell): (OrderType, Timestamp, slice, cell, coins, coins, slice, Timestamp) {
    var orderSlice: slice = order.beginParse();
    val orderType: OrderType = orderSlice.loadUint(ORDER_TYPE_SIZE);
    val expiration: Timestamp = orderSlice.loadUint(TIMESTAMP_SIZE);
    val user: slice = orderSlice.loadAddress();
    val orderInfo: cell = orderSlice.loadRef();
    val (collateralAsset: cell, collateralAmount: coins, tgUSDAmount: coins) = parseOrderInfo(orderInfo);

    // Only MintOrderType has custodialWallet
    val custodialWallet: slice = orderSlice.loadAddress();

    // Only RedeemOrderType has cooldownEnd
    val cooldownEnd: Timestamp = orderSlice.loadUint(TIMESTAMP_SIZE);

    orderSlice.assertEndOfSlice();
    return (orderType, expiration, user, collateralAsset, collateralAmount, tgUSDAmount, custodialWallet, cooldownEnd);
}

@inline
fun parseOrderInfo(orderInfo: cell): (cell, coins, coins) {
    var orderInfoSlice: slice = orderInfo.beginParse();
    val collateralAsset: cell = orderInfoSlice.loadRef();
    val collateralAmount: coins = orderInfoSlice.loadCoins();
    val tgUSDAmount: coins = orderInfoSlice.loadCoins();

    orderInfoSlice.assertEndOfSlice();
    return (collateralAsset, collateralAmount, tgUSDAmount);
}

@inline
fun parseAsset(asset: cell): (AssetPrefix, slice, int) {
    // asset must be JETTON for now
    var assetSlice: slice = asset.beginParse();
    val assetPrefix: AssetPrefix = assetSlice.loadUint(ASSET_PREFIX_SIZE);

    match (assetPrefix) {
        TON_PREFIX => {
            assetSlice.assertEndOfSlice();
            return (TON_PREFIX, NOT_JETTON_ASSET, NOT_EXTRA_CURRENCY);
        }
        JETTON_PREFIX => {
            val jettonWallet: slice = assetSlice.loadAddress();
            assetSlice.assertEndOfSlice();
            return (JETTON_PREFIX, jettonWallet, NOT_EXTRA_CURRENCY);
        }
        else => {
            return (NOT_SUPPORTED_ASSET, NOT_JETTON_ASSET, NOT_EXTRA_CURRENCY);
        }
    }
}

@inline
fun parseUpdateRedeemWhitelistRoot(mutate self: slice): MerkleRoot {
    val redeemWhitelistRoot: MerkleRoot = self.loadUint(MERKLE_ROOT_SIZE);
    self.assertEndOfSlice();
    return redeemWhitelistRoot;
}

@inline
fun parsePayout(mutate self: slice): (slice, RedeemStatus, cell, coins, slice, slice) {
    val redeemer: slice = self.loadAddress();
    val redeemStatus: RedeemStatus = self.loadUint(REDEEM_STATUS_SIZE);
    var payoutInfoSlice: slice = self.loadRef().beginParse();

    // Asset and amount depend on redeemStatus:
    // - REDEEM_SUCCESS: returnAmount = redeemAmount
    // - REDEEM_DUPLICATED or REDEEM_CANCELED: returnAmount = tgUSDBurnAmount
    val redeemAsset: cell = payoutInfoSlice.loadRef(); 
    val returnAmount: coins = payoutInfoSlice.loadCoins();

    // Engine's redeemAsset jetton wallet address
    val engineJettonWallet: slice = payoutInfoSlice.loadAddress();
    payoutInfoSlice.assertEndOfSlice();
    val recipient: slice = self.loadAddress();
    self.assertEndOfSlice();
    return (redeemer, redeemStatus, redeemAsset, returnAmount, engineJettonWallet, recipient);
}

@inline
fun parseTransferRewardFp(mutate self: slice): (cell, coins, coins, slice) {
    val collateralAsset: cell = self.loadRef();
    val collateralAmount: coins = self.loadCoins();
    val tgUSDAmount: coins = self.loadCoins();
    val custodialWallet: slice = self.loadAddress();
    self.assertEndOfSlice();
    return (collateralAsset, collateralAmount, tgUSDAmount, custodialWallet);
}

// Pack

@pure
@inline
fun packRedeemAccountProof(tgUSDEngine: slice, redeemer: slice, redeemAsset: cell): ContractProof {
    return beginCell()
        .storeSlice(tgUSDEngine)
        .storeSlice(redeemer)
        .storeRef(redeemAsset)
        .endCell()
        .cellHash();
}

@pure
@inline
fun packRedeemAccountStorage(
    tgUSDEngine: slice, 
    jettonWalletAddress: slice,
    redeemer: slice, 
    cooldownEnd: Timestamp, 
    redeemAsset: cell, 
    redeemAmount: coins,
    tgUSDBurnAmount: coins,
    redeemAccountCode: cell
): cell {
    val storage: cell = beginCell()
        .storeSlice(tgUSDEngine)
        .storeSlice(redeemer)
        .storeUint(cooldownEnd, TIMESTAMP_SIZE)
        .storeUint(REDEEM_PENDING, REDEEM_ACCOUNT_STATUS_SIZE)
        .storeRef(
            beginCell()
                .storeRef(redeemAsset)
                .storeCoins(redeemAmount)
                .storeSlice(jettonWalletAddress)
                .storeCoins(tgUSDBurnAmount)
                .endCell()
        )
        .endCell();

    return storage;
}

@pure
@inline
fun packRollbackClaim(queryId: QueryId): cell {
    return beginCell()
        .storeMessageOp(OP_ROLLBACK_CLAIM)
        .storeMessageQueryId(queryId)
        .endCell();
}

@pure
@inline
fun packClaimSuccess(queryId: QueryId): cell {
    return beginCell()
        .storeMessageOp(OP_CLAIM_SUCCESS)
        .storeMessageQueryId(queryId)
        .endCell();
}

@pure
@inline
fun packSupplyRewardFp(collateralAsset: cell, collateralAmount: coins, source: slice, custodialWallet: slice): cell {
    return beginCell()
        .storeMessageOp(OP_SUPPLY_REWARD_FP)
        .storeRef(collateralAsset)
        .storeCoins(collateralAmount)
        .storeSlice(source)
        .storeSlice(custodialWallet)
        .endCell();
}

@pure
@inline
fun packCancelRedeemInternal(queryId: QueryId): cell {
    return beginCell()
        .storeMessageOp(OP_CANCEL_REDEEM_INTERNAL)
        .storeMessageQueryId(queryId)
        .endCell();
}

@pure
@inline
fun packClaim(queryId: QueryId): cell {
    return beginCell()
        .storeMessageOp(OP_CLAIM)
        .storeMessageQueryId(queryId)
        .storeSlice(createAddressNone())
        .endCell();
}

@pure
@inline
fun packBalance(amount: int): slice {
    return beginCell().storeCoins(amount).endCell().beginParse();
}

@pure
@inline
fun packOrderInfo(collateralAsset: cell, collateralAmount: coins, tgUSDAmount: coins): cell {
    return beginCell()
        .storeRef(collateralAsset)
        .storeCoins(collateralAmount)
        .storeCoins(tgUSDAmount)
        .endCell();
}