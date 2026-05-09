import "@stdlib/gas-payments.tolk"
import "../library/fee.tolk";
import "../common/constants.tolk";

// Gas cost for jetton transfer
const SEND_TRANSFER_GAS = 9255;
const RECEIVE_TRANSFER_GAS = 10355;

// tgUSD
const REFUND_GAS = 14665;                       // 0.005866 TON
const CLAIM_GAS = 8969;                         // 0.0035876 TON
const PAYOUT_GAS = 22911;                       // 0.0091644 TON
const WITHDRAW_INTERNAL_GAS = 18617;            // 0.0074468 TON
const ROLLBACK_WITHDRAW_GAS = 5741;             // 0.0022964 TON
const ROLLBACK_CLAIM_GAS = 6956;                // 0.0027824 TON
const CANCEL_REDEEM_INTERNAL_GAS = 9528;        // 0.0038112 TON

const ASK_UPGRADE_CHILD_CONTRACT_GAS = 13397;   // 0.0053588 TON
const UPGRADE_CHILD_CONTRACT_GAS = 4192;        // 0.0016768 TON

const CALL_TO_JETTON_MASTER_GAS = 8860;         // 0.003544 TON
const CHANGE_JETTON_MASTER_CONTENT_GAS = 10000; // 0.004 TON

/**
 * @notice Computes the total storage fee of contract.
 * @dev 
 * - This function calculates the sum of paid and due storage payments.
 * - Ensure that the contract's balance is greater than the storage fee to prevent it from getting frozen.
 * @return The total storage fee as an integer.
 */
@inline
fun computeStorageFee(): int {
    return getMyStoragePaidPayment() + getMyStorageDuePayment();
}

@inline
fun computeJettonTransferFee(): coins {
    return calculateGasFee(WORKCHAIN, SEND_TRANSFER_GAS + RECEIVE_TRANSFER_GAS);
}

@inline
fun computeRefundFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, REFUND_GAS) + computeStorageFee();
    // fwdFee: Refund: (OP_TRANSFER + OP_INTERNAL_TRANSFER)
    val totalFee: int = fwdFee * 2 + computeJettonTransferFee() + gasConsume + MINIMUM_JETTON_NOTIFICATION_VALUE;
    return (totalFee, gasConsume);
}

@inline
fun computeUpgradNextContractFee(fwdFee: coins): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, ASK_UPGRADE_CHILD_CONTRACT_GAS) + computeStorageFee();
    // fwdFee: Upgrade
    // We use Parrent contract's storage fee to estimate the child contract's storage fee
    val totalFee: int = fwdFee * 1 + gasConsume + computeStorageFee() + calculateGasFee(WORKCHAIN, UPGRADE_CHILD_CONTRACT_GAS);
    return (totalFee, gasConsume);
}

@inline
fun computeCallToJettonMasterFee(): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, CALL_TO_JETTON_MASTER_GAS) + computeStorageFee();
    val totalFee: int = gasConsume + CALL_TO_JETTON_MASTER_VALUE;
    return (totalFee, gasConsume);
}

@inline
fun computeChangeJettonMasterContentFee(): (coins, coins) {
    val gasConsume: int = calculateGasFee(WORKCHAIN, CHANGE_JETTON_MASTER_CONTENT_GAS) + computeStorageFee();
    val totalFee: int = gasConsume + CHANGE_JETTON_MASTER_CONTENT_VALUE;
    return (totalFee, gasConsume);
}
