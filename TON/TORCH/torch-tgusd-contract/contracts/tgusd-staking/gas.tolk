import "@stdlib/gas-payments.tolk"
import "../common/gas.tolk";
import "../common/constants.tolk";

const STAKING_TOP_UP_GAS = 18168;           // 0.0072672 TON
const STAKE_GAS = 18659;                    // 0.0074636 TON
const UNSTAKE_GAS = 24246;                  // 0.0096984 TON
const WITHDRAW_FAILED_GAS = 14021;          // 0.0056084 TON
const ALLOCATE_STAKED_GAS = 17612;          // 0.0062448 TON
const PROVIDE_CURRENT_QUOTE_GAS = 14083;    // 0.0056332 TON
const FORCE_WITHDRAW_GAS = 8027;            // 0.0032108 TON

// Unstake account
const UNSTAKE_ACCOUNT_BITS = 6305;
const UNSTAKE_ACCOUNT_CELLS = 10;

@inline
fun computeInitUnstakeAccountFee(): int {
    return calculateMessageFeeWithoutLumpPrice(
        WORKCHAIN,
        UNSTAKE_ACCOUNT_BITS,
        UNSTAKE_ACCOUNT_CELLS
    );
}

@inline
fun computeTopUpFee(): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, STAKING_TOP_UP_GAS) + computeStorageFee();
    // 2 jetton masters (tgUSD and stgUSD)
    val totalFee: int = PROVIDE_WALLET_ADDRESS_VALUE * 2 + gasConsume;

    return (totalFee, gasConsume);
}

@inline
fun computeStakeFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, STAKE_GAS) + computeStorageFee() + LOG_FEE;
    // fwdFee: Transfer stgUSD to recipient: (OP_TRANSFER + OP_INTERNAL_TRANSFER)
    val totalFee: int = fwdFee * 2 + computeJettonTransferFee() + gasConsume + MINT_VALUE + MINIMUM_JETTON_NOTIFICATION_VALUE;

    return (totalFee, gasConsume);
}

@inline
fun computeUnstakeFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, UNSTAKE_GAS) + computeStorageFee() + LOG_FEE;
    val totalFee: int = fwdFee * 1 + gasConsume + computeInitUnstakeAccountFee() + DEPLOY_UNSTAKE_ACCOUNT_VALUE;

    return (totalFee, gasConsume);
}

@inline
fun computeWithdrawFailedFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, WITHDRAW_FAILED_GAS) + computeStorageFee();
    // fwdFee: OP_ROLLBACK_WITHDRAW + OP_COMMENT
    val totalFee: int = fwdFee * 2 + gasConsume + calculateGasFee(WORKCHAIN, ROLLBACK_WITHDRAW_GAS);

    return (totalFee, gasConsume);
}

@inline
fun computeWithdrawInternalFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, WITHDRAW_INTERNAL_GAS) + computeStorageFee();
    // fwdFee: OP_TRANSFER + OP_INTERNAL_TRANSFER
    val totalFee: int = fwdFee * 2 + computeJettonTransferFee() + gasConsume + MINIMUM_JETTON_NOTIFICATION_VALUE;

    return (totalFee, gasConsume);
}

@inline
fun computeAllocateStakedFee(fwdFee: coins, hasCustomPayload: bool): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, ALLOCATE_STAKED_GAS) + computeStorageFee();
    // fwdFee: OP_TRANSFER + OP_INTERNAL_TRANSFER
    val totalFee: int = fwdFee * 2 + computeJettonTransferFee() + (hasCustomPayload ? ALLOCATE_STAKED_VALUE : (MINIMUM_JETTON_NOTIFICATION_VALUE as coins)) + gasConsume;

    return (totalFee, gasConsume);
}

@inline
fun computeProvideCurrentQuoteFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, PROVIDE_CURRENT_QUOTE_GAS) + computeStorageFee() + PROVIDE_CURRENT_QUOTE_VALUE;
    val totalFee: int = fwdFee + gasConsume;
    return (totalFee, gasConsume);
}

@inline
fun computeForceWithdrawFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, FORCE_WITHDRAW_GAS) + computeStorageFee();
    // fwdFee: OP_WITHDRAW + OP_WITHDRAW_INTERNAL + OP_TRANSFER + OP_INTERNAL_TRANSFER
    val totalFee: int = fwdFee * 4 + computeJettonTransferFee() + gasConsume + computeStorageFee();

    return (totalFee, gasConsume);
}