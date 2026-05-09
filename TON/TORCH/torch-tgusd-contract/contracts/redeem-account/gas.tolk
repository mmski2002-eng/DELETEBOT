import "@stdlib/gas-payments.tolk"
import "../common/gas.tolk";
import "../common/constants.tolk";

const REDEEM_AGAIN_INSTALL_GAS = 8503; // 0.0034012 TON

@inline
fun computeClaimFee(fwdFee: int): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, CLAIM_GAS) + computeStorageFee();
    // fwdFee: OP_PAYOUT + OP_TRANSFER + OP_INTERNAL_TRANSFER + OP_CLAIM_SUCCESS
    // We use RedeemAccount's storage fee for estimating tgUSD Engine's storage fee
    val totalFee: int = fwdFee * 4 + gasConsume + computeJettonTransferFee() + CLAIM_SUCCESS_VALUE + computeStorageFee() + calculateGasFee(WORKCHAIN, PAYOUT_GAS);

    return (totalFee, gasConsume);
}

@inline
fun computeRefundDuplicatedRedeemFee(fwdFee: int): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, REDEEM_AGAIN_INSTALL_GAS) + computeStorageFee();
    // fwdFee: OP_PAYOUT + OP_TRANSFER + OP_INTERNAL_TRANSFER
    // We use RedeemAccount's storage fee for estimating tgUSD Engine's storage fee
    val totalFee: int = fwdFee * 3 + gasConsume + computeJettonTransferFee() + computeStorageFee() + calculateGasFee(WORKCHAIN, PAYOUT_GAS);

    return (totalFee, gasConsume);
}

@inline
fun computeRollbackClaimFee(fwdFee: int): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, ROLLBACK_CLAIM_GAS) + computeStorageFee();
    // fwdFee: Send comment to redeemer
    val totalFee: int = fwdFee * 1 + gasConsume;

    return (totalFee, gasConsume);
}

@inline
fun computeCancelRedeemFee(fwdFee: int): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, CANCEL_REDEEM_INTERNAL_GAS) + computeStorageFee();
    // fwdFee: OP_PAYOUT + OP_TRANSFER + OP_INTERNAL_TRANSFER
    val totalFee: int = fwdFee * 3 + gasConsume + computeJettonTransferFee() + computeStorageFee() + calculateGasFee(WORKCHAIN, PAYOUT_GAS);
    return (totalFee, gasConsume);
}