import "../library/message.tolk";
import "op-codes.tolk";
import "constants.tolk";

/*
 * @notice Send a deploy message to a receiver with a given value and body.
 * @param bounceFlag - The bounce flag for the message, usually NON_BOUNCEABLE.
 * @param to - The receiver of the message.
 * @param value - The attached TON amount for the message.
 * @param body - The body of the message.
 * @param stateInit - The state init (code and data) for the message.
 * @param mode - The mode of the message, usually SEND_MODE_REGULAR.
*/
@inline
fun sendDeployMessage(bounceFlag: int, to: slice, value: int, body: cell, stateInit: cell, mode: int) {
    val msg = beginCell()
        .storeUint(bounceFlag, 6)
        .storeSlice(to)
        .storeCoins(value)
        .storeStateInitAndBody(stateInit, body)
        .endCell();
    sendMessage(msg, mode);
}

/*
 * @notice Send a simple message to a receiver with a given value and body.
 * @param bounceFlag - The bounce flag for the message.
 * @param receiver - The receiver of the message.
 * @param value - The attached TON amount for the message.
 * @param body - The body of the message.
 * @param mode - The mode of the message.
 * @warning This function is used by `sendJettonMessage`, any modification may break the functionality for Jetton Transfer
*/
@inline
fun sendSimpleMessage(bounceFlag: int, receiver: slice, value: int, body: cell, mode: int) {
    val msg = beginCell()
        .storeUint(bounceFlag, 6)
        .storeSlice(receiver)
        .storeCoins(value)
        .storeOnlyBodyRef(body)
        .endCell();
    sendMessage(msg, mode);
}

/*
 * @notice Send a Jetton transfer message to a receiver with a given value and body.
 * @param bounceFlag - The bounce flag for the message.
 * @param receiver - The receiver of the message.
 * @param destination - The destination will receive the excess TON.
 * @param jettonWallet - The jetton wallet to that receives OP_TRANSFER.
 * @param jettonAmount - The amount of jetton to transfer.
 * @param value - The attached TON amount for the message.
 * @param queryId The query ID for tracking the transaction.
 * @param forwardTonAmount - The TON amount to forward to the receiver in OP_TRANSFER_NOTIFICATION.
 * @param forwardPayload - The forwardPayload for the OP_TRANSFER_NOTIFICATION.
 * @param mode - The mode of the message.
*/
@inline
fun sendJettonMessage(
    bounceFlag: int,
    receiver: slice,
    destination: slice,
    jettonWallet: slice,
    jettonAmount: int,
    value: int,
    queryId: int,
    forwardPayload: cell,
    fowardTON: int, 
    mode: int
) {
    // pack jetton transfer message to jetton wallet
    val msg = beginCell()
        .storeMessageOp(OP_TRANSFER)
        .storeMessageQueryId(queryId)
        .storeCoins(jettonAmount)
        .storeSlice(receiver)
        .storeSlice(destination)
        .storeUint(0, 1)
        .storeCoins(fowardTON)
        .storeMaybeRef(forwardPayload)
        .endCell();

    // send simple message to jetton wallet
    sendSimpleMessage(bounceFlag, jettonWallet, value, msg, mode);
}

/*
 * @notice Send a mint message to a jetton master with a given value and body.
 * @param jettonMaster - The jetton master to send the message to.
 * @param bounceFlag - The bounce flag for the message.
 * @param from - The sender of the message.
 * @param response - The response address will receive the excess TON.
 * @param receiver - The receiver of tgUSD.
 * @param mintAmount - The amount of tgUSD to mint.
 * @param value - The attached TON amount for the message.
 * @param queryId The query ID for tracking the transaction.
 * @param forwardTonAmount - The TON amount to forward to the receiver in OP_TRANSFER_NOTIFICATION.
 * @param forwardPayload - The forwardPayload for the OP_TRANSFER_NOTIFICATION.
 * @param mode - The mode of the message.
 */
@inline
fun sendMintMessage(
    jettonMaster: slice,
    bounceFlag: int,
    from: slice,
    response: slice,
    receiver: slice,
    mintAmount: int,
    value: int,
    queryId: int,
    forwardTonAmount: int,
    forwardPayload: cell,
    mode: int
) {
    // pack internal transfer message
    var internalTransferMsg = beginCell()
        .storeMessageOp(OP_INTERNAL_TRANSFER)
        .storeMessageQueryId(queryId)
        .storeCoins(mintAmount)
        .storeSlice(from)
        .storeSlice(response)
        .storeCoins(forwardTonAmount)
        .storeMaybeRef(forwardPayload)
        .endCell();

    // pack mint message
    val msg = beginCell()
        .storeMessageOp(OP_MINT)
        .storeMessageQueryId(queryId)
        .storeSlice(receiver) // to
        .storeCoins(value) // Sending TON value
        .storeRef(internalTransferMsg)
        .endCell();

    // send simple message to jetton master
    sendSimpleMessage(bounceFlag, jettonMaster, value, msg, mode);
}