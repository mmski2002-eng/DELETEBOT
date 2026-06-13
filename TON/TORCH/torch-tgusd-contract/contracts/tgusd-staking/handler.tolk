import "../common/send.tolk";
import "../common/constants.tolk";
import "../common/serdes.tolk";
import "../common/child-contract.tolk";
import "shares.tolk";
import "guard.tolk";
import "serdes.tolk";

/**
 * @notice Handles the staking process by converting the staked amount to shares and minting stgUSD.
 * @param stgUSDJettonMaster The stgUSD Jetton Master address to mint stgUSD.
 * @param queryId The query ID for tracking the transaction.
 * @param totalShares The total amount of shares issued by the staking contract.
 * @param totalStaked The total amount of tgUSD staked, including user stakes and rewards.
 * @param unvestedAmount The amount of rewards not yet vested.
 * @param staker The address of the staker.
 * @param recipient The address to receive the minted stgUSD.
 * @param jettonAmount The amount of tgUSD being staked.
 * @param sendingValue The total value being sent.
 * @return coins The amount of shares minted.
 * @dev 
 * - During user staking, the current totalStaked and totalShares are used for calculations. 
 * - Note that totalStaked includes both user staked amounts and protocol rewards. 
 * - Since rewards are vested, totalStaked must be adjusted by subtracting unvestedAmount to get the correct value. 
 * - After calculations, the shares are minted to the user.
 */
@inline
fun handleStake(
    stgUSDJettonMaster: slice, 
    queryId: int, 
    totalShares: coins, 
    totalStaked: coins, 
    unvestedAmount: coins, 
    staker: slice, 
    recipient: slice, 
    jettonAmount: coins, 
    sendingValue: coins
): coins {
    // Convert stakeAmount to shares
    val mintedShares: coins = convertToShares(totalShares, totalStaked, unvestedAmount, jettonAmount);

    // shares should be positive
    requirePositiveShare(mintedShares);

    // Mint stgUSD (mintedShares) to recipient
    sendMintMessage(
        stgUSDJettonMaster,
        NON_BOUNCEABLE,
        getMyAddress(), // from
        staker, // response
        recipient, // to
        mintedShares, // mintAmount
        sendingValue,
        queryId,
        MINIMUM_JETTON_NOTIFICATION_VALUE,
        packCommentPayload("Mint: stgUSD tokens"),
        SEND_MODE_REGULAR
    );
    return mintedShares;
}

/**
 * @notice Handles the unstaking process by converting shares to the unstaked amount and deploying an Unstake Account for record unstake information.
 * @param tgUSDStaking The tgUSD staking contract address to calculate the UnstakeAccount address.
 * @param queryId The query ID for tracking the transaction.
 * @param totalShares The total amount of shares issued by the staking contract.
 * @param totalStaked The total amount of tgUSD staked, including user stakes and rewards.
 * @param unvestedAmount The amount of rewards not yet vested.
 * @param unstaker The address of the unstaker.
 * @param shares The amount of shares being burned.
 * @param sendingValue The total value being sent.
 * @param baseCode The base code for the contract.
 * @param unstakeAccountCode The code for the Unstake Account.
 * @param cooldownPeriod The cooldown period before withdrawal is allowed.
 * @return (coins, Timestamp) The amount of tgUSD unstaked and the cooldown end time.
 * @dev 
 * - During user unstaking, the current totalStaked and totalShares are used for calculations.
 * - Note that totalStaked includes both user staked amounts and protocol rewards.
 * - Since rewards are vested, totalStaked must be adjusted by subtracting unvestedAmount to get the correct value.
 * - After calculations, an Unstake Account is deployed to manage the cooldown period before the user can withdraw their unstakedAmount of tgUSD.
 */
@inline
fun handleUnstake(
    tgUSDStaking: slice,
    queryId: int,
    totalShares: coins,
    totalStaked: coins,
    unvestedAmount: coins,
    unstaker: slice,
    shares: coins,
    sendingValue: coins,
    baseCode: cell,
    unstakeAccountCode: cell,
    cooldownPeriod: Timestamp
): (coins, Timestamp) {
    // Convert shares to unstakedAmount
    val unstakedAmount: coins = convertToStaked(totalShares, totalStaked, unvestedAmount, shares);

    // unstakedAmount should be positive
    requirePositiveUnstakedAmount(unstakedAmount);

    // Pack UnstakeAccount Proof and get UnstakeAccount Address
    val unstakeAccountProof: ContractProof = packUnstakeAccountProof(tgUSDStaking, unstaker);
    val (stateInit, unstakeAccountAddress) = getChildContract(tgUSDStaking, unstakeAccountProof, baseCode);

    // Pack UnstakeAccount Storage
    val cooldownEnd: Timestamp = now() + cooldownPeriod;
    val storage: cell = packUnstakeAccountStorage(tgUSDStaking, unstaker, unstakedAmount, cooldownEnd);

    // Deploy unstake account with `install` message
    val installMessage: cell = packInstall(queryId, unstakeAccountCode, storage, null);

    // Send install message to UnstakeAccount
    sendDeployMessage(NON_BOUNCEABLE, unstakeAccountAddress, DEPLOY_UNSTAKE_ACCOUNT_VALUE, installMessage, stateInit, SEND_MODE_REGULAR);

    // Send comment to tell unstaker unstake successfully and withdraw after cooldown period
    sendSimpleMessage(NON_BOUNCEABLE, unstaker, sendingValue - DEPLOY_UNSTAKE_ACCOUNT_VALUE, packComment("Request unstake successfully, withdraw after cooldown end"), SEND_MODE_REGULAR);
    return (unstakedAmount, cooldownEnd);
}