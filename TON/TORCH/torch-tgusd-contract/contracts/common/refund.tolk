import "../common/send.tolk";
import "../common/constants.tolk";

@inline
fun refundByTransfer(
    jettonSender: slice,
    engineJettonWallet: slice,
    jettonAmount: coins,
    sendingValue: coins,
    queryId: int,
    comment: cell
) {
    sendJettonMessage(
        NON_BOUNCEABLE,
        jettonSender,
        jettonSender,
        engineJettonWallet, // tgUSD Engine's jetton wallet or tgUSD Staking's jetton wallet
        jettonAmount,
        sendingValue,
        queryId,
        comment,
        MINIMUM_JETTON_NOTIFICATION_VALUE,
        SEND_MODE_REGULAR
    );
    return ();
}

@inline
fun refundByMint(jettonMaster: slice, sendingValue: coins, from: slice, response: slice, recipient: slice, jettonAmount: coins, queryId: int, comment: cell) {
    sendMintMessage(
        jettonMaster,
        NON_BOUNCEABLE,
        from,
        response, // response
        recipient, // to
        jettonAmount, // mintAmount
        sendingValue,
        queryId,
        MINIMUM_JETTON_NOTIFICATION_VALUE,
        comment,
        SEND_MODE_REGULAR
    );
    return ();
}