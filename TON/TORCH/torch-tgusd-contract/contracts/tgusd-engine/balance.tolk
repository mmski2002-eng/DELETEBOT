import "../common/exit-codes.tolk";
import "../common/constants.tolk";
import "serdes.tolk";
import "guard.tolk";

/**
 * @notice Gets the balance of a jetton wallet.
 * @param jettonWalletsBalDict The dictionary containing jetton wallet balances.
 * @param jettonWalletAddress The address of the jetton wallet to get the balance of.
 * @return The balance of the jetton wallet.
 * @dev 
 * - Returns 0 if the jetton wallet is not found in the dictionary.
 */
@pure
@inline
fun getJettonBalance(jettonWalletsBalDict: dict, jettonWalletAddress: slice?): coins {
    // Get old balance from jettonWalletsBalDict
    var (oldBalance: slice?, isKeyExist: bool) = jettonWalletsBalDict.sDictGet(ADDRESS_SIZE, jettonWalletAddress!);

    // Should check key is exist in jettonWalletsBalDict before calling this function, otherwise it will return 0
    return isKeyExist ? oldBalance!.loadCoins() : ton("0");
}

/**
 * @notice Checks if the jetton wallet has enough balance to pay for the amount.
 * @param amount The amount to check.
 * @param jettonWalletAddress The address of the jetton wallet to check.
 * @param jettonWalletsBalDict The dictionary containing jetton wallet balances.
 * @return (bool, coins) Tuple containing a boolean indicating if the balance is enough to pay and the balance itself.
 */
 @pure
@inline
fun hasEnoughJettonBalance(amount: coins, jettonWalletAddress: slice, jettonWalletsBalDict: dict): (bool, coins) {
    // Get jetton wallet balance
    var jettonWalletBalance: coins = getJettonBalance(jettonWalletsBalDict, jettonWalletAddress!);

    return (jettonWalletBalance >= amount, jettonWalletBalance);
}

