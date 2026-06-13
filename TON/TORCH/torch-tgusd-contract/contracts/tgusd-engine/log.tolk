import "../common/constants.tolk";
import "../common/log.tolk";
import "../common/types.tolk";
import "../common/types.tolk";
import "../library/log.tolk";
import "serdes.tolk";

const LOG_ENGINE_DEPLOYED = stringCrc32("EngineDeployed");
const LOG_ENGINE_WALLET_ADDRESS_TAKEN = stringCrc32("EngineWalletAddressTaken");
const LOG_DEPOSITED = stringCrc32("Deposited");
const LOG_REDEEM_WHITELIST_ROOT_UPDATED = stringCrc32("RedeemWhitelistRootUpdated");
const LOG_REDEEM_REQUESTED = stringCrc32("RedeemRequested");
const LOG_REPAID = stringCrc32("Repaid");
const LOG_CLAIM_PROCESSED = stringCrc32("ClaimProcessed");
const LOG_NOT_ENOUGH_TO_CLAIM = stringCrc32("NotEnoughToClaim");
const LOG_CONTRACT_HALTED = stringCrc32("ContractHalted");
const LOG_TRANSFERRED_REWARD = stringCrc32("TransferredReward");
const LOG_CUSTODIAL_WALLET_ADDED = stringCrc32("CustodialWalletAdded");
const LOG_CUSTODIAL_WALLET_REMOVED = stringCrc32("CustodialWalletRemoved");
const LOG_COLLATERAL_ADDED = stringCrc32("CollateralAdded");
const LOG_COLLATERAL_REMOVED = stringCrc32("CollateralRemoved");
const LOG_REDEEM_DUPLICATED = stringCrc32("RedeemDuplicated");
const LOG_REDEEM_CANCELED = stringCrc32("RedeemCanceled");
const LOG_SIGNER_KEY_UPDATED = stringCrc32("SignerKeyUpdated");

@inline
fun logEngineDeployed(signerKey: SignerKey, redeemWhitelistRoot: MerkleRoot, custodialWalletsDict: dict, admin: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_ENGINE_DEPLOYED)
        .storeUint(signerKey, SIGNER_KEY_SIZE)
        .storeUint(redeemWhitelistRoot, MERKLE_ROOT_SIZE)
        .storeDict(custodialWalletsDict)
        .storeSlice(admin);
    emitLog(LOG_ENGINE_DEPLOYED, log);
}

@inline
fun logEngineWalletAddressTaken(jettonMasterAddress: slice, jettonWalletAddress: slice, jettonWalletsBalDict: dict) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_ENGINE_WALLET_ADDRESS_TAKEN)
        .storeSlice(jettonMasterAddress)
        .storeSlice(jettonWalletAddress)
        .storeDict(jettonWalletsBalDict);
    emitLog(LOG_ENGINE_WALLET_ADDRESS_TAKEN, log);
}

@inline
fun logDeposited(minter: slice, collateralAsset: cell, collateralAmount: coins, tgUSDAmount: coins, custodialWallet: slice, recipient: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_DEPOSITED)
        .storeSlice(minter)
        .storeRef(packOrderInfo(collateralAsset, collateralAmount, tgUSDAmount))
        .storeSlice(custodialWallet)
        .storeSlice(recipient);
    emitLog(LOG_DEPOSITED, log);
}

@inline
fun logRedeemWhitelistRootUpdated(redeemWhitelistRoot: MerkleRoot, admin: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_REDEEM_WHITELIST_ROOT_UPDATED)
        .storeUint(redeemWhitelistRoot, MERKLE_ROOT_SIZE)
        .storeSlice(admin);
    emitLog(LOG_REDEEM_WHITELIST_ROOT_UPDATED, log);
}

@inline
fun logRedeemRequested(redeemer: slice, collateralAsset: cell, collateralAmount: coins, tgUSDAmount: coins, cooldownEnd: Timestamp) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_REDEEM_REQUESTED)
        .storeSlice(redeemer)
        .storeRef(packOrderInfo(collateralAsset, collateralAmount, tgUSDAmount))
        .storeUint(cooldownEnd, TIMESTAMP_SIZE);
    emitLog(LOG_REDEEM_REQUESTED, log);
}

@inline
fun logRepaid(engineJettonWallet: slice, repaidAmount: coins, jettonWalletsBalDict: dict, source: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_REPAID)
        .storeSlice(engineJettonWallet)
        .storeCoins(repaidAmount)
        .storeDict(jettonWalletsBalDict)
        .storeSlice(source);
    emitLog(LOG_REPAID, log);
}

@inline
fun logClaimProcessed(claimStatus: ClaimStatus, redeemer: slice, asset: cell, amount: coins, recipient: slice, jettonWalletsBalDict: dict) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_CLAIM_PROCESSED)
        .storeUint(claimStatus, CLAIM_STATUS_SIZE)
        .storeSlice(redeemer)
        .storeRef(asset)
        .storeCoins(amount)
        .storeSlice(recipient)
        .storeDict(jettonWalletsBalDict);
    emitLog(LOG_CLAIM_PROCESSED, log);
}

@inline
fun logRefundRedeem(redeemStatus: RedeemStatus, redeemer: slice, asset: cell, returnAmount: coins, recipient: slice) {
    if (redeemStatus == REDEEM_DUPLICATED) {
        logRedeemDuplicated(redeemer, asset, returnAmount, recipient);
    } else {
        logRedeemCancelled(redeemer, asset, returnAmount, recipient);
    }
}

@inline
fun logRedeemDuplicated(redeemer: slice, asset: cell, returnAmount: coins, recipient: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_REDEEM_DUPLICATED)
        .storeSlice(redeemer)
        .storeRef(asset)
        .storeCoins(returnAmount)
        .storeSlice(recipient);
    emitLog(LOG_REDEEM_DUPLICATED, log);
}

@inline
fun logRedeemCancelled(redeemer: slice, asset: cell, redeemAmount: coins, recipient: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_REDEEM_CANCELED)
        .storeSlice(redeemer)
        .storeRef(asset)
        .storeCoins(redeemAmount)
        .storeSlice(recipient);
    emitLog(LOG_REDEEM_CANCELED, log);
}

@inline
fun logCustodialWalletAdded(newCustodialWallet: slice, admin: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_CUSTODIAL_WALLET_ADDED)
        .storeSlice(newCustodialWallet)
        .storeSlice(admin);
    emitLog(LOG_CUSTODIAL_WALLET_ADDED, log);
}

@inline
fun logCustodialWalletRemoved(removedCustodialWallet: slice, admin: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_CUSTODIAL_WALLET_REMOVED)
        .storeSlice(removedCustodialWallet)
        .storeSlice(admin);
    emitLog(LOG_CUSTODIAL_WALLET_REMOVED, log);
}

@inline
fun logCollateralAdded(newCollateral: cell, admin: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_COLLATERAL_ADDED)
        .storeRef(newCollateral)
        .storeSlice(admin);
    emitLog(LOG_COLLATERAL_ADDED, log);
}

@inline
fun logCollateralRemoved(removedCollateral: cell, admin: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_COLLATERAL_REMOVED)
        .storeRef(removedCollateral)
        .storeSlice(admin);
    emitLog(LOG_COLLATERAL_REMOVED, log);
}   

@inline
fun logSignerKeyUpdated(newSignerKey: SignerKey, admin: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_SIGNER_KEY_UPDATED)
        .storeUint(newSignerKey, SIGNER_KEY_SIZE)
        .storeSlice(admin);
    emitLog(LOG_SIGNER_KEY_UPDATED, log);
}