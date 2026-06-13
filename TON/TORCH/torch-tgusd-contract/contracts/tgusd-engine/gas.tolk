import "@stdlib/gas-payments.tolk"
import "../common/gas.tolk";
import "../common/constants.tolk";

const ENGINE_TOP_UP_GAS = 23209;        // 0.0092836 TON
const DEPOSIT_GAS = 21466;              // 0.0085864 TON
const REQUEST_REDEEM_GAS = 25848;       // 0.0103392 TON
const CLAIM_FAILED_GAS = 14035;         // 0.005614 TON
const TRANSFER_REWARD_GAS = 16555;      // 0.006622 TON
const DUPLICATED_REDEEM_GAS = 15649;    // 0.0062596 TON
const ADD_COLLATERAL_GAS = 16067;       // 0.0064268 TON
const CANCEL_REDEEM_GAS = 6912;         // 0.0027648 TON
const FORCE_CLAIM_GAS = 7186;           // 0.0028744 TON
const REMOVE_COLLATERAL_GAS = 17712;    // 0.0070848 TON

// Redeem account
const REDEEM_ACCOUNT_BITS = 10527;
const REDEEM_ACCOUNT_CELLS = 16;

@inline
fun computeInitRedeemAccountFee(): int {
    return calculateMessageFeeWithoutLumpPrice(
        WORKCHAIN,
        REDEEM_ACCOUNT_BITS,
        REDEEM_ACCOUNT_CELLS
    );
}

@inline
fun computeTopUpFee(jettonAssetSize: int): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, ENGINE_TOP_UP_GAS) + computeStorageFee();
    val totalFee: int = PROVIDE_WALLET_ADDRESS_VALUE * jettonAssetSize + gasConsume;

    return (totalFee, gasConsume);
}

@inline
fun computeDepositFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, DEPOSIT_GAS) + computeStorageFee() + LOG_FEE;
    // fwdFee: Transfer to custodial wallet: (OP_TRANSFER + OP_INTERNAL_TRANSFER)
    val totalFee: int = fwdFee * 2 + computeJettonTransferFee() + gasConsume + MINT_VALUE + MINIMUM_JETTON_NOTIFICATION_VALUE * 2;
    return (totalFee, gasConsume);
}

@inline
fun computeClaimFailedFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, CLAIM_FAILED_GAS) + computeStorageFee();
    // fwdFee: OP_ROLLBACK_CLAIM + OP_COMMENT
    val totalFee: int = fwdFee * 2 + gasConsume + calculateGasFee(WORKCHAIN, ROLLBACK_CLAIM_GAS);
    return (totalFee, gasConsume);
}

@inline
fun computeDuplicatedRedeemFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, DUPLICATED_REDEEM_GAS) + computeStorageFee();
    // fwdFee: Refund: (OP_TRANSFER + OP_INTERNAL_TRANSFER)
    val totalFee: int = fwdFee * 2 + computeJettonTransferFee() + gasConsume;
    return (totalFee, gasConsume);
}

@inline
fun computePayoutFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, PAYOUT_GAS) + computeStorageFee();
    // fwdFee: Payout: (OP_TRANSFER + OP_INTERNAL_TRANSFER)
    val totalFee: int = fwdFee * 2 + computeJettonTransferFee() + gasConsume + CLAIM_SUCCESS_VALUE + MINIMUM_JETTON_NOTIFICATION_VALUE;
    return (totalFee, gasConsume);
}

@inline
fun computeRequestRedeemFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, REQUEST_REDEEM_GAS) + computeStorageFee() + LOG_FEE;
    val totalFee: int = fwdFee * 1 + gasConsume + computeInitRedeemAccountFee() + DEPLOY_REDEEM_ACCOUNT_VALUE;
    return (totalFee, gasConsume);
}

@inline
fun computeTransferRewardFpFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, TRANSFER_REWARD_GAS) + computeStorageFee();
    // fwdFee: OP_TRANSFER + OP_INTERNAL_TRANSFER
    val totalFee: int = fwdFee * 2 + computeJettonTransferFee() + gasConsume + MINT_VALUE + SUPPLY_REWARD_FP_VALUE + MINIMUM_JETTON_NOTIFICATION_VALUE;
    return (totalFee, gasConsume);
}

@inline
fun computeAddCollateralFee(): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, ADD_COLLATERAL_GAS) + computeStorageFee();
    val totalFee: int = gasConsume + PROVIDE_WALLET_ADDRESS_VALUE;
    return (totalFee, gasConsume);
}

@inline
fun computeCancelRedeemFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, CANCEL_REDEEM_GAS) + computeStorageFee();
    // fwdFee: OP_CANCEL_REDEEM_INTERNAL + OP_PAYOUT + OP_TRANSFER + OP_INTERNAL_TRANSFER
    val totalFee: int = 
        fwdFee * 4 + 
        computeJettonTransferFee() + 
        gasConsume + 
        computeStorageFee() + // We use engine storage for estimating redeem account storage fee
        calculateGasFee(WORKCHAIN, PAYOUT_GAS) +
        calculateGasFee(WORKCHAIN, CANCEL_REDEEM_INTERNAL_GAS);
    return (totalFee, gasConsume);
}

@inline
fun computeForceClaimFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, FORCE_CLAIM_GAS) + computeStorageFee();
    // fwdFee: OP_CLAIM + OP_PAYOUT + OP_TRANSFER + OP_INTERNAL_TRANSFER
    val totalFee: int = 
        fwdFee * 4 + 
        computeJettonTransferFee() + 
        calculateGasFee(WORKCHAIN, CLAIM_GAS) +
        calculateGasFee(WORKCHAIN, PAYOUT_GAS) +
        computeStorageFee() +
        gasConsume + 
        CLAIM_SUCCESS_VALUE;
    return (totalFee, gasConsume);
}

@inline
fun computeRemoveCollateralFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, REMOVE_COLLATERAL_GAS) + computeStorageFee();
    // fwdFee: OP_TRANSFER + OP_INTERNAL_TRANSFER
    val totalFee: int = fwdFee * 2 + computeJettonTransferFee() + gasConsume + TRANSFER_REMAINING_COLLATERAL_VALUE;
    return (totalFee, gasConsume);
}
