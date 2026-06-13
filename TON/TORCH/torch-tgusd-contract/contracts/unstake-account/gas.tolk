import "@stdlib/gas-payments.tolk"
import "../common/gas.tolk";
import "../common/constants.tolk";

const WITHDRAW_GAS = 7074; // 0.0028296 TON

@inline
fun computeWithdrawFee(fwdFee: int): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, WITHDRAW_GAS) + computeStorageFee();
    // fwdFee: OP_WIHTDRAW_INTERNAL + OP_TRANSFER + OP_INTERNAL_TRANSFER
    // We use UnstakeAccount's storage fee for estimating tgUSD Engine's storage fee
    val totalFee: int = fwdFee * 3 + gasConsume + computeJettonTransferFee() + computeStorageFee() + calculateGasFee(WORKCHAIN, WITHDRAW_INTERNAL_GAS);

    return (totalFee, gasConsume);
}

@inline
fun computeRollbackWithdrawFee(fwdFee: int): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, ROLLBACK_WITHDRAW_GAS) + computeStorageFee();
    // fwdFee: Send comment to unstaker
    val totalFee: int = fwdFee * 1 + gasConsume;

    return (totalFee, gasConsume);
}