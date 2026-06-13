import "@stdlib/tvm-dicts";
import "../common/exit-codes.tolk";
import "../common/constants.tolk";

/**
 * @notice Ensures the caller is the admin before performing admin-specific operations.
 * @param self The address of the caller.
 * @param admin The admin address.
 * @dev 
 * - Used to verify admin privileges before executing operations such as updating the admin or contract code. 
 * - Reverts with ERROR_NOT_ADMIN if the caller is not the admin.
 */
@inline
fun requireAdmin(self: slice, admin: slice) {
    assert(self.isSliceBitsEqual(admin), ERROR_NOT_ADMIN);
}

/**
 * @notice Ensures the caller is the designated next admin during a two-step admin transfer process.
 * @param self The address of the caller.
 * @param nextAdmin The address designated as the next admin.
 * @dev 
 * - Used in a two-step admin transfer process where only the nextAdmin can claim the role of admin. 
 * - Reverts with ERROR_NOT_NEXT_ADMIN if the caller is not the designated next admin.
 */
@inline
fun requireNextAdmin(self: slice, nextAdmin: slice) {
    assert(self.isSliceBitsEqual(nextAdmin), ERROR_NOT_NEXT_ADMIN);
}

/**
 * @notice Ensures the provided jettonAmount is positive.
 * @param jettonAmount The amount to check. (Received from OP_TRANSFER_NOTIFICATION)
 * @dev 
 * - Used to verify the validity of amounts before performing operations. 
 * - Reverts with ERROR_NON_POSITIVE_JETTON_AMOUNT if the amount is not positive.
 */
@inline
fun requirePositiveJettonAmount(jettonAmount: int) {
    assert(jettonAmount > 0, ERROR_NON_POSITIVE_JETTON_AMOUNT);
}

/**
 * @notice Ensures the provided admin and nextAdmin are different.
 * @param admin The current admin address.
 * @param nextAdmin The next admin address.
 * @dev 
 * - Used to verify the validity of admin addresses before performing OP_CHANGE_ADMIN. 
 * - Reverts with ERROR_SAME_ADMIN if the admin and nextAdmin are the same.
 */
@inline
fun requireDifferentAdmin(admin: slice, nextAdmin: slice) {
    assert(!admin.isSliceBitsEqual(nextAdmin), ERROR_SAME_ADMIN);
}

/**
 * @notice Ensures the new contract code is different from the existing code before updating.
 * @param newCell The new contract code cell.
 * @param oldCell The existing contract code cell.
 * @dev 
 * - Used to verify that the new contract code is not identical to the old code before performing an update. Reverts with ERROR_IDENTICAL_CELL if the codes are identical.
 */
@inline
fun requireNotIdenticalCell(newCell: cell, oldCell: cell) {
    assert(newCell.cellHash() != oldCell.cellHash(), ERROR_IDENTICAL_CELL);
}

/**
 * @notice Ensures the contract is not halted before performing operations.
 * @param isHalt The current halt status.
 * @dev 
 * - Used to verify the contract is not halted before performing operations. 
 * - Reverts with ERROR_CONTRACT_HALTED if the contract is halted.
 */
@inline
fun requireContractNotHalted(isHalt: bool) {
    assert(!isHalt, ERROR_CONTRACT_HALTED);
}

/**
 * @notice Ensures the contract is in a halted state before attempting to unhalt it.
 * @param isHalt A boolean indicating whether the contract is currently halted.
 * @dev 
 * - Used to verify that the contract is indeed halted before performing operations to unhalt it. Reverts with ERROR_CONTRACT_NOT_HALTED if the contract is not halted.
 */
@inline
fun requireContractHalted(isHalt: bool) {
    assert(isHalt, ERROR_CONTRACT_NOT_HALTED);
}