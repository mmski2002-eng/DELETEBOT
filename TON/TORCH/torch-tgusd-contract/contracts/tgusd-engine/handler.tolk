import "../common/serdes.tolk";
import "../common/send.tolk";
import "../common/constants.tolk";
import "../common/child-contract.tolk";
import "serdes.tolk";

/**
 * @notice Handles the deposit process by minting tgUSD and transferring collateral.
 * @param tgUSDJettonMaster The tgUSD Jetton Master address to mint tgUSD.
 * @param engineJettonWallet The engine's Jetton wallet address to transfer collateral.
 * @param minter The address of the minter.
 * @param recipient The address to receive the minted tgUSD, if specified, otherwise the minter.
 * @param tgUSDAmount The amount of tgUSD to mint.
 * @param collateralAmount The amount of collateral to transfer.
 * @param custodialWallet The custodial wallet address to receive the collateral.
 * @param queryId The query ID for tracking the transaction.
 * @param sendingValue The total value being sent.
 * @dev 
 * - During a minter deposit, collateral assets are transferred to the custodial wallet, and tgUSD is minted to the minter or recipient if provided.
 */
@inline
fun handleDeposit(
    tgUSDJettonMaster: slice,
    engineJettonWallet: slice,
    minter: slice,
    recipient: slice,
    tgUSDAmount: coins,
    collateralAmount: coins,
    custodialWallet: slice,
    queryId: int,
    sendingValue: coins
) {
    // Mint tgUSD to recipient
    sendMintMessage(
        tgUSDJettonMaster,
        NON_BOUNCEABLE,
        getMyAddress(), // from
        minter,         // response
        recipient,      // to
        tgUSDAmount,    // mintAmount
        MINT_VALUE,
        queryId,
        MINIMUM_JETTON_NOTIFICATION_VALUE,
        packCommentPayload("Mint: tgUSD to recipient"),
        SEND_MODE_REGULAR
    );

    // Send collateral to custodial wallet or proxy contract
    sendJettonMessage(
        NON_BOUNCEABLE,
        custodialWallet,
        minter,
        engineJettonWallet,
        collateralAmount,
        sendingValue - MINT_VALUE,
        queryId,
        packCommentPayload("Transfer: Collateral to Proxy Contract"),
        MINIMUM_JETTON_NOTIFICATION_VALUE,
        SEND_MODE_REGULAR
    );

    return;
}

/**
 * @notice Handles the process of minting tgUSD and transferring rewards to the tgUSD staking contract.
 * @param custodialWallet The custodial wallet address to receive the collateral.
 * @param manager The address managing the operation.
 * @param engineJettonWallet The engine's Jetton wallet address to transfer collateral.
 * @param collateralAmount The amount of collateral to transfer.
 * @param sendingValue The total value being sent.
 * @param tgUSDJettonMaster The tgUSD Jetton Master address to mint tgUSD.
 * @param tgUSDStaking The tgUSD staking contract address to receive the reward (tgUSD).
 * @param collateralAsset The collateral asset cell that provides to mint tgUSD.
 * @param mintedReward The amount of tgUSD to mint as a reward.
 * @param queryId The query ID for tracking the transaction.
 * @dev 
 * - When the protocol mints tgUSD and transfers rewards to the tgUSD staking contract, 
 *   it first mints tgUSD to the staking contract, then transfers the collateral provided during minting to the custodial wallet.
 */
@inline 
fun handleTransferReward(
    custodialWallet: slice,
    manager: slice,
    engineJettonWallet: slice,
    collateralAmount: coins,
    sendingValue: coins,
    tgUSDJettonMaster: slice,
    tgUSDStaking: slice,
    collateralAsset: cell,
    mintedReward: coins,
    queryId: int
) {
    // Send collateral to custodial wallet
    sendJettonMessage(
        NON_BOUNCEABLE,
        custodialWallet,
        manager,
        engineJettonWallet, 
        collateralAmount,
        sendingValue - SUPPLY_REWARD_FP_VALUE - MINT_VALUE,
        queryId,
        packCommentPayload("Transfer: Collateral to Proxy Contract"),
        MINIMUM_JETTON_NOTIFICATION_VALUE,
        SEND_MODE_REGULAR
    );

    // Mint tgUSD to tgUSDStaking
    sendMintMessage(
        tgUSDJettonMaster,
        NON_BOUNCEABLE,
        tgUSDJettonMaster,  // from
        manager,            // response
        tgUSDStaking,       // to
        mintedReward,
        MINT_VALUE + SUPPLY_REWARD_FP_VALUE,
        queryId,
        SUPPLY_REWARD_FP_VALUE,
        packSupplyRewardFp(collateralAsset, collateralAmount, manager, custodialWallet),
        SEND_MODE_REGULAR
    );
    return;
}

/**
 * @notice Handles the request to redeem by deploying a dedicated Redeem Account for the redeemer.
 * @param queryId The query ID for tracking the transaction.
 * @param tgUSDEngine The tgUSD engine address.
 * @param engineJettonWallet The address of the engine's jetton wallet to transfer the collateral.
 * @param redeemer The address of the redeemer.
 * @param cooldownEnd The timestamp when the cooldown period ends.
 * @param redeemAsset The asset to be redeemed.
 * @param redeemAmount The amount of the asset to redeem.
 * @param tgUSDBurnAmount The amount of tgUSD to be burned to redeem the collateral.
 * @param redeemAccountCode The code for the Redeem Account.
 * @param baseCode The base code for the contract.
 * @dev 
 * - When a redeemer initiates a redeem, a dedicated Redeem Account is deployed to record the redeem information. 
 *   After the cooldownEnd, the redeemer can claim the collateral.
 */
@inline
fun handleRequestRedeem(
    queryId: int,
    sendingValue: coins,
    tgUSDEngine: slice,
    engineJettonWallet: slice,
    redeemer: slice,
    cooldownEnd: Timestamp,
    redeemAsset: cell,
    redeemAmount: coins,
    tgUSDBurnAmount: coins,
    redeemAccountCode: cell,
    baseCode: cell
) {
    // Pack RedeemAccount Proof and get RedeemAccount Address
    val redeemAccountProof: ContractProof = packRedeemAccountProof(tgUSDEngine, redeemer, redeemAsset);
    val (stateInit: cell, redeemAccountAddress: slice) = getChildContract(tgUSDEngine, redeemAccountProof, baseCode);

    // Pack RedeemAccount Storage
    val storage: cell = packRedeemAccountStorage(tgUSDEngine, engineJettonWallet, redeemer, cooldownEnd, redeemAsset, redeemAmount, tgUSDBurnAmount, redeemAccountCode);

    // Deploy redeem account with `install` message
    val installMessage: cell = packInstall(queryId, redeemAccountCode, storage, null);

    // Send install message to RedeemAccount
    sendDeployMessage(NON_BOUNCEABLE, redeemAccountAddress, DEPLOY_REDEEM_ACCOUNT_VALUE, installMessage, stateInit, SEND_MODE_REGULAR);
    
    // Send comment to tell redeemer request redeem successfully
    sendSimpleMessage(NON_BOUNCEABLE, redeemer, sendingValue - DEPLOY_REDEEM_ACCOUNT_VALUE, packComment("Redeem is in progress."), SEND_MODE_REGULAR);
    return;
}

/**
 * @notice Handles the payout process by sending the asset to the recipient and sending OP_CLAIM_SUCCESS to the RedeemAccount.
 * @param recipient The address of the recipient who will receive the asset.
 * @param redeemer The address of the redeemer who initiated the payout and will receive EXCESS TON.
 * @param engineJettonWallet The address of the engine's jetton wallet to transfer the collateral.
 * @param amount The amount of the asset to send.
 * @param sendingValue The total value being sent.
 * @param redeemAccountAddress The address of the RedeemAccount to receive OP_CLAIM_SUCCESS.
 * @param queryId The query ID for tracking the transaction.
 * @dev 
 * - When a redeemer claims their collateral, the asset is sent to the recipient and OP_CLAIM_SUCCESS is sent to the RedeemAccount.
 */
@inline
fun handlePayout(
    recipient: slice,
    redeemer: slice,
    engineJettonWallet: slice,
    amount: coins,
    sendingValue: coins,
    redeemAccountAddress: slice,
    queryId: int
) {
    // Send asset to recipient
    sendJettonMessage(
        NON_BOUNCEABLE,
        recipient,
        redeemer,
        engineJettonWallet, 
        amount,
        sendingValue - CLAIM_SUCCESS_VALUE,
        queryId,
        packCommentPayload("Transfer: Collateral to recipient"),
        MINIMUM_JETTON_NOTIFICATION_VALUE,
        SEND_MODE_REGULAR
    );

    // Send OP_CLAIM_SUCCESS to RedeemAccount
    sendSimpleMessage(NON_BOUNCEABLE, redeemAccountAddress, CLAIM_SUCCESS_VALUE, packClaimSuccess(queryId), SEND_MODE_REGULAR);
    return;
}