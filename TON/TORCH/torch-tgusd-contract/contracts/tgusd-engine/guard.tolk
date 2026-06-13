import "../common/exit-codes.tolk";
import "../common/constants.tolk";
import "../common/types.tolk";

/**
 * @notice Verifies if the sender is a supported Jetton Master.
 * @param self The address to verify.
 * @param jettonMastersDict Dictionary of supported Jetton Masters.
 * @dev 
 * - Used when a Jetton Master sends OP_TAKE_WALLET_ADDRESS to ensure the sender is authorized.
 * - Reverts with ERROR_NOT_SUPPORTED_JETTON_MASTER if not supported.
 */
@inline
fun requireSupportedJettonMaster(self: slice, jettonMastersDict: dict) {
    val (_, isKeyExist: bool) = jettonMastersDict.sDictGet(ADDRESS_SIZE, self);
    assert(isKeyExist, ERROR_NOT_SUPPORTED_JETTON_MASTER);
}

/**
 * @notice Verifies if the sender is the expected minter.
 * @param self The address to verify.
 * @param minter The expected minter address.
 * @dev 
 * - Used during user deposit to ensure the collateral provider matches the order's minter.
 * - Reverts with ERROR_NOT_MINTER if the addresses do not match.
 */
@inline
fun requireMinter(self: slice, minter: slice) {
    assert(self.isSliceBitsEqual(minter), ERROR_NOT_MINTER);
}

/**
 * @notice Verifies if the sender is the expected redeemer.
 * @param self The address to verify.
 * @param redeemer The expected redeemer address.
 * @dev 
 * - Used during user redemption to ensure the tgUSD burner matches the order's redeemer.
 * - Reverts with ERROR_NOT_REDEEMER if the addresses do not match.
 */
@inline
fun requireRedeemer(self: slice, redeemer: slice) {
    assert(self.isSliceBitsEqual(redeemer), ERROR_NOT_REDEEMER);
}

/**
 * @notice Verifies the order type matches the expected type.
 * @param orderType The actual order type.
 * @param expectedOrderType The expected order type.
 * @dev 
 * - Used to ensure order type is mint during deposit and redeem during redemption.
 * - Reverts with ERROR_INVALID_ORDER_TYPE if mismatched.
 */
@inline
fun requireOrderType(orderType: OrderType, expectedOrderType: OrderType) {
    assert(orderType == expectedOrderType, ERROR_INVALID_ORDER_TYPE);
}

/**
 * @notice Ensures the provided address is a supported Jetton Wallet.
 * @param self The address to check.
 * @param jettonWalletsBalDict The dictionary containing supported Jetton Wallets.
 * @dev 
 * - Used when Engine receives a OP_TRANSFER_NOTIFICATION (It can come from any jetton wallet).
 * - Reverts with ERROR_NOT_SUPPORTED_JETTON_WALLET if the address is not supported.
 */
@inline
fun requireSupportedJettonWallet(self: slice, jettonWalletsBalDict: dict) {
    val (_, isKeyExist: bool) = jettonWalletsBalDict.sDictGet(ADDRESS_SIZE, self);
    assert(isKeyExist, ERROR_NOT_SUPPORTED_JETTON_WALLET);
}

/**
 * @notice Verifies the address is a supported Custodial Wallet.
 * @param self The address to check.
 * @param custodialWalletsDict Dictionary of supported Custodial Wallets.
 * @dev 
 * - Used to validate the custodial wallet in Order before transferring collateral.
 * - Reverts with ERROR_NOT_SUPPORTED_CUSTODIAL_WALLET if unsupported.
 */
@inline
fun requireCustodialWallet(self: slice, custodialWalletsDict: dict) {
    val (_, isKeyExist: bool) = custodialWalletsDict.sDictGet(ADDRESS_SIZE, self);
    assert(isKeyExist, ERROR_NOT_SUPPORTED_CUSTODIAL_WALLET);
}

/**
 * @notice Verifies the collateral asset is valid and supported.
 * @param assetPrefix The type of the asset.
 * @param jettonMasterAddress The address of the Jetton Master.
 * @param jettonMastersDict Dictionary of supported Jetton Masters.
 * @param ctxSender The context sender address, if applicable.
 * @dev 
 * - Used during deposit, redeem, reward transfer, or collateral removal to check asset existence.
 * - If ctxSender is provided, ensures it matches the engine jetton wallet for the collateral.
 * - Reverts with ERROR_NOT_SUPPORTED_JETTON_MASTER or ERROR_WRONG_COLLATERAL if invalid.
 */
@inline
fun requireCollateralAsset(assetPrefix: int, jettonMasterAddress: slice, jettonMastersDict: dict, ctxSender: slice?) {
    requireJettonAssetType(assetPrefix);
    val (jettonWalletAddress: slice?, isKeyExist: bool) = jettonMastersDict.sDictGet(ADDRESS_SIZE, jettonMasterAddress);
    assert(isKeyExist, ERROR_NOT_SUPPORTED_JETTON_MASTER);
    if (ctxSender != null) {
        assert(jettonWalletAddress!.isSliceBitsEqual(ctxSender!), ERROR_WRONG_COLLATERAL);
    }
}

/**
 * @notice Ensures the collateral asset does not already exist.
 * @param assetPrefix The type of the asset.
 * @param jettonMasterAddress The address of the Jetton Master.
 * @param jettonMastersDict Dictionary of supported Jetton Masters.
 * @dev 
 * - Used when removing supported collateral to ensure the Engine contract supports the asset.
 * - Reverts with ERROR_COLLATERAL_ALREADY_EXISTS if the asset already exists.
 */
@inline
fun requireCollateralAssetNotExists(assetPrefix: int, jettonMasterAddress: slice, jettonMastersDict: dict) {
    requireJettonAssetType(assetPrefix);
    val (_, isKeyExist: bool) = jettonMastersDict.sDictGet(ADDRESS_SIZE, jettonMasterAddress);
    assert(!isKeyExist, ERROR_COLLATERAL_ALREADY_EXISTS);
}

/**
 * @notice Ensures the asset type is a valid Jetton asset type.
 * @param assetPrefix The type of the asset.
 * @dev 
 * - Reverts with ERROR_INVALID_ASSET_TYPE if the asset type is invalid.
 */
@inline
fun requireJettonAssetType(assetPrefix: int) {
    assert(assetPrefix == JETTON_PREFIX, ERROR_INVALID_ASSET_TYPE);
}

/**
 * @notice Ensures the expected amount matches the received amount.
 * @param expectedAmount The expected amount.
 * @param receivedAmount The received amount.
 * @dev 
 * - Reverts with ERROR_AMOUNT_MISMATCH if the amounts do not match.
 */
@inline
fun requireExpectedAmount(expectedAmount: int, receivedAmount: int) {
    assert(expectedAmount == receivedAmount, ERROR_AMOUNT_MISMATCH);
}

/**
 * @notice Ensures the new redeem whitelist root is different from the current one.
 * @param redeemWhitelistRoot The current redeem whitelist root.
 * @param newRedeemWhitelistRoot The new redeem whitelist root.
 * @dev 
 * - Used when updating the redeem whitelist root.
 * - Reverts with ERROR_SAME_REDEEM_WHITELIST_ROOT if the roots are identical.
 */
@inline
fun requireDifferentRedeemWhitelistRoot(redeemWhitelistRoot: MerkleRoot, newRedeemWhitelistRoot: MerkleRoot) {
    assert(redeemWhitelistRoot != newRedeemWhitelistRoot, ERROR_SAME_REDEEM_WHITELIST_ROOT);
}

/**
 * @notice Verifies the address is the tgUSD Jetton Master.
 * @param self The address to check.
 * @param tgUSDJettonMaster The tgUSD Jetton Master address.
 * @dev 
 * - Used during a user's redeem request when TFUSD is burned, and the tgUSD Jetton Master sends OP_EXTRA_BURN_INFO to the Engine contract.
 * - Reverts with ERROR_NOT_SUPPORTED_JETTON_MASTER if the address is not the tgUSD Jetton Master.
 */
@inline
fun requiretgUSDJettonMaster(self: slice, tgUSDJettonMaster: slice) {
    assert(self.isSliceBitsEqual(tgUSDJettonMaster), ERROR_NOT_SUPPORTED_JETTON_MASTER);
}

/**
 * @notice Verifies the address is either a Custodial Wallet or the admin.
 * @param self The address to check.
 * @param custodialWalletsDict Dictionary of Custodial Wallets.
 * @param admin The admin address.
 * @dev 
 * - Used during mint and supply reward operations via the Engine contract, ensuring only the admin or a custodial wallet can perform these actions.
 * - Reverts with ERROR_NOT_CUSTODIAL_WALLET_OR_ADMIN if the address is neither.
 */
@inline
fun requireCustodialWalletOrAdmin(self: slice, custodialWalletsDict: dict, admin: slice) {
    val (_, isKeyExist: bool) = custodialWalletsDict.sDictGet(ADDRESS_SIZE, self);
    assert(isKeyExist || self.isSliceBitsEqual(admin), ERROR_NOT_CUSTODIAL_WALLET_OR_ADMIN);
}

/**
 * @notice Verifies the address is the expected Redeem Account.
 * @param self The address to check.
 * @param redeemAccount The expected Redeem Account address.
 * @dev 
 * - Used when the Redeem Account sends OP_PAYOUT to the Engine contract, ensuring the address is correct for transferring collateral to the redeemer or handling duplicate redemption by returning tgUSD.
 * - Reverts with ERROR_NOT_REDEEM_ACCOUNT if the address is not the expected Redeem Account.
 */
@inline
fun requireRedeemAccount(self: slice, redeemAccount: slice) {
    assert(self.isSliceBitsEqual(redeemAccount), ERROR_NOT_REDEEM_ACCOUNT);
}

/**
 * @notice Verifies a Merkle proof.
 * @param merkleProof The Merkle proof slice.
 * @param isExotic Indicates if the proof is an exotic cell.
 * @param merkleRoot The expected Merkle root.
 * @dev 
 * - Used when redeemer requests redemption and provides a Merkle proof.
 * - Reverts with ERROR_NOT_EXOTIC_CELL, ERROR_NOT_MERKLE_PROOF, or ERROR_INCORRECT_MERKLE_ROOT if invalid.
 */
@inline 
fun requireValidMerkleProof(mutate merkleProof: slice, isExotic: bool, merkleRoot: int) {
    // Verify if merkle proof is exotic cell 
    assert(isExotic, ERROR_NOT_EXOTIC_CELL);

    // Verify if cell type is merkle proof type
    assert(merkleProof.loadUint(EXOTIC_CELL_TYPE_SIZE) == MERKLE_PROOF_TYPE, ERROR_NOT_MERKLE_PROOF);

    // Verify merkle root is identical to the one in the distributor
    assert(merkleProof.loadUint(MERKLE_ROOT_SIZE) == merkleRoot, ERROR_INCORRECT_MERKLE_ROOT);
}

/**
 * @notice Verifies the order signature is valid.
 * @param orderHash The hash of the order.
 * @param signature The signature to verify.
 * @param signerKey The key of the signer.
 * @dev 
 * - Used during mint or redeem operations to validate the off-chain signed payload, which includes the amount of tgUSD or collateral to be received.
 * - Reverts with ERROR_INVALID_SIGNATURE if the signature is invalid.
 */
@inline
fun requireValidOrder(orderHash: int, signature: slice, signerKey: int) {
    assert(isSignatureValid(orderHash, signature, signerKey), ERROR_INVALID_SIGNATURE);
}

/**
 * @notice Ensures the Custodial Wallet does not already exist.
 * @param custodialWallet The Custodial Wallet address.
 * @param custodialWalletsDict The dictionary containing Custodial Wallets.
 * @dev 
 * - Used when adding a new custodial wallet to ensure it doesn't already exist.
 * - Reverts with ERROR_CUSTODIAL_WALLET_ALREADY_EXISTS if the wallet already exists.
 */
@inline
fun requireCustodialWalletNotExists(custodialWallet: slice, custodialWalletsDict: dict) {
    val (_, isKeyExist: bool) = custodialWalletsDict.sDictGet(ADDRESS_SIZE, custodialWallet);
    assert(!isKeyExist, ERROR_CUSTODIAL_WALLET_ALREADY_EXISTS);
}

/**
 * @notice Ensures the Custodial Wallet exists.
 * @param custodialWallet The Custodial Wallet address.
 * @param custodialWalletsDict The dictionary containing Custodial Wallets.
 * @dev 
 * - Used when removing a custodial wallet to ensure it exists in the dictionary.
 * - Reverts with ERROR_NOT_SUPPORTED_CUSTODIAL_WALLET if the wallet does not exist.
 */
@inline
fun requireCustodialWalletExists(custodialWallet: slice, custodialWalletsDict: dict) {
    val (_, isKeyExist: bool) = custodialWalletsDict.sDictGet(ADDRESS_SIZE, custodialWallet);
    assert(isKeyExist, ERROR_NOT_SUPPORTED_CUSTODIAL_WALLET);
}

/**
 * @notice Ensures the Jetton Master Address is not already taken.
 * @param jettonMasterAddress The Jetton Master Address to check.
 * @param jettonMastersDict The dictionary containing Jetton Master Addresses.
 * @dev 
 * - Used when adding a new Jetton Master Address to ensure it doesn't already exist.
 * - Reverts with ERROR_ALREADY_TOP_UP if the address already exists.
 */
@inline
fun requireJettonMasterAddressNotTaken(jettonMasterAddress: slice, jettonMastersDict: dict) {
    val (_, isKeyExist: bool) = jettonMastersDict.sDictGet(ADDRESS_SIZE, jettonMasterAddress);
    assert(!isKeyExist, ERROR_ALREADY_TOP_UP);
}


/**
 * @notice Ensures the new signer key is not the same as the old one.
 * @param newSignerKey The new signer key.
 * @param oldSignerKey The old signer key.
 * @dev 
 * - Used when updating the signer key.
 * - Reverts with ERROR_SAME_SIGNER_KEY if the new signer key is the same as the old one.
 */
@inline
fun requireDifferentSignerKey(newSignerKey: SignerKey, oldSignerKey: SignerKey) {
    assert(newSignerKey != oldSignerKey, ERROR_SAME_SIGNER_KEY);
}
