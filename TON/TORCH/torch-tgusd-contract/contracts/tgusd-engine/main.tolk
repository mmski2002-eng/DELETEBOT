/*
 * @title tgUSD-engine
 * @notice A comprehensive contract for managing tgUSD minting and redemption with collateral assets.
 * @dev This contract:
 * - Accepts stablecoins (USDT, USDC, USDe) as collateral for minting tgUSD.
 * - Directly transfers user-provided collateral to custodial wallets or cross-chain bridge proxy contracts.
 * - Allows users to redeem tgUSD back into collateral assets, subject to a whitelist mechanism and cooldown period.
 * - Deploys a dedicated Redeem Account for each redeemer to record redeem information, allowing users to claim collateral after cooldownEnd.
 * - Supports minting tgUSD to be directly transferred to the tgUSD staking contract as rewards.
 * - Ensures secure and efficient handling of collateralization to maintain the stability of the tgUSD ecosystem.
 */

tolk 0.11

import "@stdlib/tvm-dicts";
import "../library/fee.tolk";
import "../common/constants.tolk";
import "../common/op-codes.tolk";
import "../common/exit-codes.tolk";
import "../common/serdes.tolk";
import "../common/send.tolk";
import "../common/guard.tolk";
import "../common/log.tolk";
import "../common/gas.tolk";
import "../common/refund.tolk";
import "../common/child-contract.tolk";
import "../common/recipient.tolk";
import "../common/types.tolk";
import "storage.tolk";
import "serdes.tolk";
import "guard.tolk";
import "handler.tolk";
import "balance.tolk";
import "log.tolk";
import "gas.tolk";

@inline
fun routeInternal(ctxSender: slice, ctxValue: int, ctxFwdFee: int, ctxBody: slice) {
    val op: Opcode = ctxBody.loadMessageOp();
    val queryId: QueryId = ctxBody.loadMessageQueryId();

    if (op == OP_TRANSFER_NOTIFICATION) {
        // ctxSender should be in jettonWalletsDict
        ctxSender.requireSupportedJettonWallet(jettonWalletsBalDict);

        // Parse jetton notification message
        var (jettonAmount: coins, jettonSender: slice, forwardPayload: slice) = ctxBody.parseJettonNotification();

        // jettonAmount should be positive
        requirePositiveJettonAmount(jettonAmount);

        // Get op-code in forward payload 
        val forwardPayloadOp: Opcode = forwardPayload.loadMessageOp();

        if (forwardPayloadOp == OP_DEPOSIT_FP) {
            // If contract is halted, refund collateral with jettonAmount to jettonSender
            if (isHalt) {
                // Make sure the fee is enough to refund
                val (totalFee: coins, gasConsume: coins) = computeRefundFee(ctxFwdFee);
                assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
                val sendingValue: coins = ctxValue - gasConsume;

                // Refund collateral with jettonAmount to jettonSender (ctxSender is engineJettonWallet)
                refundByTransfer(jettonSender, ctxSender, jettonAmount, sendingValue, queryId, packCommentPayload("Refund: Contract is halted"));
                commitContractDataAndActions();
                throw ERROR_CONTRACT_HALTED;
            }

            // Parse DepositFp message body
            var (
                signature: slice, 
                orderHash: OrderHash, 
                recipient: slice, 
                orderType: OrderType, 
                expiration: Timestamp, 
                minter: slice, 
                collateralAsset: cell, 
                collateralAmount: coins, 
                tgUSDAmount: coins, 
                custodialWallet: slice, 
                _
            ) = forwardPayload.parseDepositFp();

            // Ensure valid order signature
            requireValidOrder(orderHash, signature, signerKey);

            // minter should be jettonSender
            jettonSender.requireMinter(minter);

            // CollateralAmount should be same as jettonAmount
            requireExpectedAmount(collateralAmount, jettonAmount);

            // if expiration < now(), refund jettonAmount to minter
            if (expiration < now()) {
                // Make sure the fee is enough to refund
                val (totalFee: coins, gasConsume: coins) = computeRefundFee(ctxFwdFee);
                assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
                val sendingValue: coins = ctxValue - gasConsume;

                // Refund jetton to minter
                refundByTransfer(jettonSender, ctxSender, jettonAmount, sendingValue, queryId, packCommentPayload("Refund: Order expired"));
                commitContractDataAndActions();
                throw ERROR_ORDER_EXPIRED;
            }

            // orderType should be ORDER_TYPE_MINT
            requireOrderType(orderType, ORDER_TYPE_MINT);

            // Parse collateral asset
            val (assetPrefix: AssetPrefix, jettonMasterAddress: slice, _) = parseAsset(collateralAsset);

            // Collateral asset type should be JETTON_PREFIX, jettonMasterAddress should be in jettonMastersDict and ctxSender should be correct jetton wallet address
            requireCollateralAsset(assetPrefix, jettonMasterAddress, jettonMastersDict, ctxSender);

            // Custodial wallet should be in custodialWalletsDict
            custodialWallet.requireCustodialWallet(custodialWalletsDict);

            // Right now, only stablecoins are supported as collateral assets, and we mint 1:1 tgUSD
            // If in the future, we support other assets as collateral assets, we need to add more checks here (Ex: max mint per block, etc.)
            requireExpectedAmount(tgUSDAmount, jettonAmount);

            // Check sending value is enough to cover the fee
            val (totalFee: coins, gasConsume: coins) = computeDepositFee(ctxFwdFee);
            assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
            val sendingValue: coins = ctxValue - gasConsume;

            // Check if there is a recipient; if not, set it to the minter.
            recipient = getRecipient(recipient, minter);

            // Handle deposit (mint tgUSD to recipient and send collateral to custodial wallet)
            handleDeposit(
                tgUSDJettonMaster,
                ctxSender,
                minter,
                recipient,
                tgUSDAmount,
                collateralAmount,
                custodialWallet,
                queryId,
                sendingValue
            );

            // Emit log
            logDeposited(minter, collateralAsset, collateralAmount, tgUSDAmount, custodialWallet, recipient);
            return;
        }

        if (forwardPayloadOp == OP_TRANSFER_REWARD_FP) {
            // jettonSender should be custodial wallet or admin
            jettonSender.requireCustodialWalletOrAdmin(custodialWalletsDict, admin);

            // If contract is halted, refund jettonAmount to jettonSender
            if (isHalt) {
                // Make sure the fee is enough to refund
                val (totalFee: coins, gasConsume: coins) = computeRefundFee(ctxFwdFee);
                assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
                val sendingValue: coins = ctxValue - gasConsume;

                // Refund jetton to jettonSender
                refundByTransfer(jettonSender, ctxSender, jettonAmount, sendingValue, queryId, packCommentPayload("Refund: Contract is halted"));
                commitContractDataAndActions();
                throw ERROR_CONTRACT_HALTED;
            }

            // Parse TransferRewardFp message body
            val (collateralAsset: cell, collateralAmount: coins, mintedReward: coins, custodialWallet: slice) = forwardPayload.parseTransferRewardFp();

            // Parse collateral asset
            val (assetPrefix: AssetPrefix, jettonMasterAddress: slice, _) = parseAsset(collateralAsset);

            // Collateral asset type should be JETTON_PREFIX, jettonMasterAddress should be in jettonMastersDict and ctxSender should be correct jetton wallet address
            requireCollateralAsset(assetPrefix, jettonMasterAddress, jettonMastersDict, ctxSender);

            // Custodial wallet should be in custodialWalletsDict
            custodialWallet.requireCustodialWallet(custodialWalletsDict);

            // CollateralAmount should be same as jettonAmount
            requireExpectedAmount(collateralAmount, jettonAmount);

            // Right now, only stablecoins are supported as collateral assets, and we mint 1:1 tgUSD
            // If in the future, we support other assets as collateral assets, we need to add more checks here (Ex: max mint per block, etc.)
            requireExpectedAmount(mintedReward, jettonAmount);

            // Check sending value is enough to cover the fee
            val (totalFee: coins, gasConsume: coins) = computeTransferRewardFpFee(ctxFwdFee);
            assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
            val sendingValue: coins = ctxValue - gasConsume;

            handleTransferReward(
                custodialWallet,
                jettonSender,
                ctxSender, // engineJettonWallet
                collateralAmount,
                sendingValue,
                tgUSDJettonMaster,
                tgUSDStaking,
                collateralAsset,
                mintedReward,
                queryId
            );
            return;
        }

        if (forwardPayloadOp == OP_REPAY_FP) {
            // Get old balance from jettonWalletsBalDict
            val oldBalance: coins = getJettonBalance(jettonWalletsBalDict, ctxSender);

            // Update jettonWalletsBalDict
            jettonWalletsBalDict.sDictSet(ADDRESS_SIZE, ctxSender, packBalance(oldBalance + jettonAmount));
            
            // Emit log
            logRepaid(ctxSender, jettonAmount, jettonWalletsBalDict, jettonSender);

            saveData();
            return;
        }

        throw ERROR_WRONG_OP;
    }

    if (op == OP_PAYOUT) {
        // Parse Payout message body
        val (redeemer: slice, redeemStatus: RedeemStatus, redeemAsset: cell, returnAmount: coins, engineJettonWallet: slice, recipient: slice) = ctxBody.parsePayout();

        // ctxSender should be RedeemAccount
        val (_, redeemAccountAddress: slice) = getChildContract(getMyAddress(), packRedeemAccountProof(getMyAddress(), redeemer, redeemAsset), baseCode);
        ctxSender.requireRedeemAccount(redeemAccountAddress);

        // If redeem status is not success, it is duplicated or cancelled redeem -> refund
        if (redeemStatus != REDEEM_SUCCESS) {
            // Make sure the fee is enough to refund
            val (totalFee: coins, gasConsume: coins) = computeDuplicatedRedeemFee(ctxFwdFee);
            assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
            val sendingValue: coins = ctxValue - gasConsume;

            // Refund jetton to redeemer
            val (response: slice, comment: cell, exitCode: int) = 
                redeemStatus == REDEEM_DUPLICATED ? 
                (redeemer, packCommentPayload("Refund: Duplicated redeem"), ERROR_DUPLICATED_REDEEM) : 
                (admin, packCommentPayload("Refund: Cancelled redeem"), ERROR_CANCELED_REDEEM);
            refundByMint(tgUSDJettonMaster, sendingValue, getMyAddress(), response, redeemer, returnAmount, queryId, comment);
            logRefundRedeem(redeemStatus, redeemer, redeemAsset, returnAmount, recipient);
            commitContractDataAndActions();
            throw exitCode;
        }

        // Check tgUSD Engine's redeemAsset jetton wallet balance is enough or not
        val (isEnough: bool, oldBalance: coins) = hasEnoughJettonBalance(returnAmount, engineJettonWallet!, jettonWalletsBalDict);

        // Rollback if jetton wallet balance is not enough or contract is halted
        if (!isEnough || isHalt) {
            // Make sure the fee is enough to rollback claim
            val (totalFee: coins, gasConsume: coins) = computeClaimFailedFee(ctxFwdFee);
            assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
            val sendingValue: coins = ctxValue - gasConsume;

            // Send OP_ROLLBACK_CLAIM to RedeemAccount
            sendSimpleMessage(NON_BOUNCEABLE, redeemAccountAddress, sendingValue, packRollbackClaim(queryId), SEND_MODE_REGULAR);

            // Emit log
            logClaimProcessed(isHalt ? CLAIM_HALTED : CLAIM_BUT_NOT_ENOUGH_COLLATERAL, redeemer, redeemAsset, returnAmount, recipient, jettonWalletsBalDict);
            commitContractDataAndActions();
            throw (isHalt ? ERROR_CONTRACT_HALTED : ERROR_NOT_ENOUGH_JETTON_BALANCE);
        }

        // Update jettonWalletsBalDict
        jettonWalletsBalDict.sDictSet(ADDRESS_SIZE, engineJettonWallet, packBalance(oldBalance - returnAmount));

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computePayoutFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Handle payout (Send asset to recipient and send OP_CLAIM_SUCCESS to RedeemAccount)
        handlePayout(recipient, redeemer, engineJettonWallet, returnAmount, sendingValue, redeemAccountAddress, queryId);

        // Emit log
        logClaimProcessed(CLAIM_SUCCESS, redeemer, redeemAsset, returnAmount, recipient, jettonWalletsBalDict);

        saveData();
        return;
    }

    if (op == OP_EXTRA_BURN_INFO) {
        // Only tgUSD Jetton Master can send OP_REQUEST_REDEEM
        ctxSender.requiretgUSDJettonMaster(tgUSDJettonMaster);

        // Parse extra burn info message body
        var (
            jettonSender: slice,
            jettonAmount: coins,
            customPayload: slice
        ) = ctxBody.parseExtraBurnInfo();

        // jettonAmount should be positive
        requirePositiveJettonAmount(jettonAmount);

        // Get op-code in custom payload 
        val customPayloadOp: Opcode = customPayload.loadMessageOp();

        if (customPayloadOp == OP_REQUEST_REDEEM) {
            // If contract is halted, refund jettonAmount to jettonSender by minting tgUSD
            if (isHalt) {
                // Make sure the fee is enough to refund
                val (totalFee: coins, gasConsume: coins) = computeRefundFee(ctxFwdFee);
                assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
                val sendingValue: coins = ctxValue - gasConsume;

                // Refund jetton to redeemer
                refundByMint(tgUSDJettonMaster, sendingValue, getMyAddress(), jettonSender, jettonSender, jettonAmount, queryId, packCommentPayload("Refund: Contract is halted"));
                commitContractDataAndActions();
                throw ERROR_CONTRACT_HALTED;
            }

            // Parse RequestRedeem message body
            var (
                signature: slice, 
                orderHash: OrderHash, 
                orderType: OrderType, 
                expiration: Timestamp, 
                redeemer: slice, 
                collateralAsset: cell, 
                collateralAmount: coins, 
                tgUSDAmount: coins, 
                custodialWallet: slice, 
                cooldownEnd: Timestamp, 
                redeemWhitelistProof: slice, 
                isExotic: bool
            ) = customPayload.parseRequestRedeem();
            
            // Ensure valid order signature
            requireValidOrder(orderHash, signature, signerKey);

            // redeemer should be jettonSender
            jettonSender.requireRedeemer(redeemer);

            // orderType should be ORDER_TYPE_REDEEM
            requireOrderType(orderType, ORDER_TYPE_REDEEM);

            // Parse collateral asset (recipient will get this collateral asset after completing redeem)
            val (assetPrefix: AssetPrefix, jettonMasterAddress: slice, _) = parseAsset(collateralAsset);

            // Collateral asset type should be JETTON_PREFIX and jettonMasterAddress should be in jettonMastersDict
            requireCollateralAsset(assetPrefix, jettonMasterAddress, jettonMastersDict, null);

            // tgUSDAmount should be same as jettonAmount (burn amount)
            requireExpectedAmount(tgUSDAmount, jettonAmount);

            // if expiration < now(), refund jettonAmount to redeemer
            if (expiration < now()) {
                // Make sure the fee is enough to refund
                val (totalFee: coins, gasConsume: coins) = computeRefundFee(ctxFwdFee);
                assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
                val sendingValue: coins = ctxValue - gasConsume;

                // Refund jetton to redeemer
                refundByMint(tgUSDJettonMaster, sendingValue, getMyAddress(), jettonSender, jettonSender, jettonAmount, queryId, packCommentPayload("Refund: Order is expired"));
                commitContractDataAndActions();
                throw ERROR_ORDER_EXPIRED;
            }

            // Verify merkle proof is exotic cell, cell type is merkle proof and merkle root is identical to distributor's merkle root
            requireValidMerkleProof(mutate redeemWhitelistProof, isExotic, redeemWhitelistRoot);

            // Load dict from redeemWhitelistProof
            val redeemWhitelistDict: cell = redeemWhitelistProof.loadRef();

            // redeemer should be in redeemWhitelistDict otherwise refund (If redeemer is not in redeemWhitelistDict, TVM will throw exit-code 9 directly)
            try {
                val (_, isKeyExist: bool) = redeemWhitelistDict.sDictGet(ADDRESS_SIZE, redeemer);
                
                // We still need to check isKeyExist so that TVM will compile redeemWhitelistDict.sDictGet()
                assert(isKeyExist, ERROR_NOT_IN_REDEEM_WHITELIST);
            } catch {
                // Make sure the fee is enough to refund
                val (totalFee: coins, gasConsume: coins) = computeRefundFee(ctxFwdFee);
                assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
                val sendingValue: coins = ctxValue - gasConsume;
                
                // Refund jetton to redeemer
                refundByMint(tgUSDJettonMaster, sendingValue, getMyAddress(), jettonSender, jettonSender, jettonAmount, queryId, packCommentPayload("Refund: Redeemer is not in redeem whitelist"));
                commitContractDataAndActions();
                throw ERROR_NOT_IN_REDEEM_WHITELIST;
            }

            // Get engineJettonWallet for this collateral asset (We already checked that collateral asset is in jettonMastersDict)
            val (engineJettonWallet: slice?, _) = jettonMastersDict.sDictGet(ADDRESS_SIZE, jettonMasterAddress);

            // Right now, only stablecoins are supported as collateral assets, and we mint 1:1 tgUSD
            // If in the future, we support other assets as collateral assets, we need to add more checks here (Ex: max mint per block, etc.)
            requireExpectedAmount(collateralAmount, tgUSDAmount);
            
            // Check sending value is enough to cover the fee
            val (totalFee: coins, gasConsume: coins) = computeRequestRedeemFee(ctxFwdFee);
            assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
            val sendingValue: coins = ctxValue - gasConsume;

            // Deploy RedeemAccount for this redeemer and record the redeem information
            handleRequestRedeem(
                queryId,
                sendingValue,
                getMyAddress(),
                engineJettonWallet!,
                redeemer,
                cooldownEnd,
                collateralAsset,
                collateralAmount,
                tgUSDAmount,
                redeemAccountCode,
                baseCode
            );

            // Emit log
            logRedeemRequested(redeemer, collateralAsset, collateralAmount, tgUSDAmount, cooldownEnd);
            return;
        }

        throw ERROR_WRONG_OP;
    }

    if (op == OP_UPDATE_REDEEM_WHITELIST_ROOT) {
        // Only admin can update redeem whitelist root
        ctxSender.requireAdmin(admin);

        // Parse update redeem whitelist root data
        val newRedeemWhitelistRoot: MerkleRoot = ctxBody.parseUpdateRedeemWhitelistRoot();

        // New redeem whitelist root should be different from old one
        requireDifferentRedeemWhitelistRoot(redeemWhitelistRoot, newRedeemWhitelistRoot);

        // Update redeem whitelist root
        redeemWhitelistRoot = newRedeemWhitelistRoot;

        // Emit log
        logRedeemWhitelistRootUpdated(newRedeemWhitelistRoot, admin);

        saveData();
        return;
    }

    if (op == OP_CANCEL_REDEEM) {
        // Only admin can cancel redeem
        ctxSender.requireAdmin(admin);

        // Parse cancel redeem message body
        val redeemAccountAddress: slice = ctxBody.loadAddress();

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeCancelRedeemFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Send OP_CANCEL_REDEEM_INTERNAL to RedeemAccount
        sendSimpleMessage(NON_BOUNCEABLE, redeemAccountAddress, sendingValue, packCancelRedeemInternal(queryId), SEND_MODE_REGULAR);
        return;
    }

    if (op == OP_FORCE_CLAIM) {
        // Only admin can force claim
        ctxSender.requireAdmin(admin);

        // Parse force claim message body
        val redeemAccountAddress: slice = ctxBody.loadAddress();

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeForceClaimFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Send OP_CLAIM to RedeemAccount
        sendSimpleMessage(NON_BOUNCEABLE, redeemAccountAddress, sendingValue, packClaim(queryId), SEND_MODE_REGULAR);
        return;
    }

    if (op == OP_RESET_GAS) {
        // Only admin can reset gas
        ctxSender.requireAdmin(admin);

        // Parse reset gas message body
        var recipient: slice = ctxBody.loadAddress();

        // Check if there is a recipient; if not, set it to the admin.
        recipient = getRecipient(recipient, admin);

        // Reserve minimal TON to pay for storage fee (If balance is less than MINIMUM_ENGINE_STORAGE_TON, it will throw error)
        reserveToncoinsOnBalance(MINIMUM_ENGINE_STORAGE_TON, RESERVE_MODE_AT_MOST);

        // Transfer all balance to admin except for the minimal balance + distributable
        sendSimpleMessage(NON_BOUNCEABLE, recipient, 0, packCommentPayload("Reset Gas"), SEND_MODE_CARRY_ALL_BALANCE);
        return;
    }

    if (op == OP_ADD_COLLATERAL_ASSET) {
        // Only admin can add collateral
        ctxSender.requireAdmin(admin);

        // Parse add collateral message body
        val newCollateral: cell = ctxBody.loadRef();

        // Parse collateral asset 
        val (assetPrefix: AssetPrefix, jettonMasterAddress: slice, _) = parseAsset(newCollateral);

        // Collateral asset type should be JETTON_PREFIX and jettonMasterAddress should not be in jettonMastersDict
        requireCollateralAssetNotExists(assetPrefix, jettonMasterAddress, jettonMastersDict);

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeAddCollateralFee();
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Right now, we only support JETTON_PREFIX
        val msgBody: cell = packProvideWalletAddress(queryId, getMyAddress(), false);
        sendSimpleMessage(NON_BOUNCEABLE, jettonMasterAddress, sendingValue, msgBody, SEND_MODE_REGULAR);

        // Set jettonMasterAddress to the jettonMastersDict, key is jettonMasterAddress and value is addressNone (It will be set in OP_TAKE_WALLET_ADDRESS)
        jettonMastersDict.sDictSet(ADDRESS_SIZE, jettonMasterAddress, createAddressNone());

        // Emit log
        logCollateralAdded(newCollateral, admin);

        saveData();
        return;
    }

    if (op == OP_REMOVE_COLLATERAL_ASSET) {
        // ! Better to cancel all redeem requests before removing collateral

        // Only admin can remove collateral
        ctxSender.requireAdmin(admin);

        // Parse remove collateral message body
        val removedCollateral: cell = ctxBody.loadRef();

        // Parse collateral asset 
        val (assetPrefix: AssetPrefix, jettonMasterAddress: slice, _) = parseAsset(removedCollateral);

        // Check collateral asset is in jettonMastersDict
        requireCollateralAsset(assetPrefix, jettonMasterAddress, jettonMastersDict, null);

        // Get jettonWalletAddress from jettonMastersDict
        val (jettonWalletAddress: slice?, _) = jettonMastersDict.sDictGet(ADDRESS_SIZE, jettonMasterAddress);

        // If collateral asset's balance is not 0, transfer remaining amount to admin
        val balance: coins = getJettonBalance(jettonWalletsBalDict, jettonWalletAddress);
        if (balance != 0) { 
            // Check fee is enough to transfer remaining collateral to admin
            val (totalFee: coins, gasConsume: coins) = computeRemoveCollateralFee(ctxFwdFee);
            assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
            val sendingValue: coins = ctxValue - gasConsume;

            // Transfer remaining collateral to admin
            sendJettonMessage(
                NON_BOUNCEABLE,
                admin,
                admin,
                jettonWalletAddress!, 
                balance,
                sendingValue,
                queryId,
                packCommentPayload("Transfer: Remaining collateral to admin"),
                MINIMUM_JETTON_NOTIFICATION_VALUE,
                SEND_MODE_REGULAR
            );
        }

        // Remove collateral asset from jettonWalletsBalDict
        jettonWalletsBalDict.sDictDelete(ADDRESS_SIZE, jettonWalletAddress!);

        // Remove collateral asset from jettonMastersDict
        jettonMastersDict.sDictDelete(ADDRESS_SIZE, jettonMasterAddress);

        // Emit log
        logCollateralRemoved(removedCollateral, admin);

        saveData();
        return;
    }

    if (op == OP_ADD_CUSTODIAL_WALLET) {
        // Only admin can add custodial wallet
        ctxSender.requireAdmin(admin);

        // Parse add custodial wallet message body
        val newCustodialWallet: slice = ctxBody.loadAddress();

        // Check custodial wallet is not in custodialWalletsDict
        requireCustodialWalletNotExists(newCustodialWallet, custodialWalletsDict);

        // Add new custodial wallet
        custodialWalletsDict.sDictSet(ADDRESS_SIZE, newCustodialWallet, packBalance(0));
        
        // Emit log
        logCustodialWalletAdded(newCustodialWallet, admin);

        saveData();
        return;
    }

    if (op == OP_REMOVE_CUSTODIAL_WALLET) {
        // Only admin can remove custodial wallet
        ctxSender.requireAdmin(admin);

        // Parse remove custodial wallet message body
        val removedCustodialWallet: slice = ctxBody.loadAddress();

        // Check custodial wallet is in custodialWalletsDict
        requireCustodialWalletExists(removedCustodialWallet, custodialWalletsDict);

        // Remove custodial wallet
        custodialWalletsDict.sDictDelete(ADDRESS_SIZE, removedCustodialWallet);

        // Emit log
        logCustodialWalletRemoved(removedCustodialWallet, admin);

        saveData();
        return;
    }

    if (op == OP_UPDATE_REDEEM_ACCOUNT_CODE) {
        // Only admin can update redeem account code
        ctxSender.requireAdmin(admin);

        // Parse update redeem account code message body
        val newRedeemAccountCode: cell = ctxBody.loadRef();

        // Validate if new redeem account code is not the same as the old one
        requireNotIdenticalCell(newRedeemAccountCode, redeemAccountCode);

        // Update redeem account code
        redeemAccountCode = newRedeemAccountCode;

        saveData();
        return;
    }

    if (op == OP_HALT) {
        // Only admin can halt
        ctxSender.requireAdmin(admin);

        // Contract should not be halted
        requireContractNotHalted(isHalt);

        // Halt the contract
        isHalt = true;

        // Emit log
        logContractHalted(admin);

        saveData();
        return;
    }

    if (op == OP_UNHALT) {
        // Only admin can unhalt
        ctxSender.requireAdmin(admin);

        // Contract should be halted
        requireContractHalted(isHalt);

        // Unhalt the contract
        isHalt = false;

        // Emit log
        logContractUnhalted(admin);

        saveData();
        return;
    }

    if (op == OP_CHANGE_ADMIN) {
        // Only admin can change admin
        ctxSender.requireAdmin(admin);

        // Parse change admin message body
        val nextAdminAddress: slice = ctxBody.loadAddress();

        // nextAdmin should be different from admin
        requireDifferentAdmin(admin, nextAdminAddress);

        // Update admin
        nextAdmin = nextAdminAddress;

        saveData();
        return;
    }

    if (op == OP_CLAIM_ADMIN) {
        ctxBody.assertEndOfSlice();

        // Only next admin can claim admin
        ctxSender.requireNextAdmin(nextAdmin);

        // Emit log
        logAdminChanged(nextAdmin, admin);

        // Update admin
        admin = nextAdmin;
        nextAdmin = createAddressNone();

        saveData();
        return;
    }

    if (op == OP_CHANGE_JETTON_MASTER_ADMIN) {
        // Only admin can change jetton master admin
        ctxSender.requireAdmin(admin);

        // Parse change jetton master admin message body
        val newJettonMasterAdmin: slice = ctxBody.loadAddress();

        // Pack OP_CHANGE_JETTON_MASTER_ADMIN message body
        val msgBody: cell = packChangeJettonMasterAdmin(queryId, newJettonMasterAdmin);
        sendSimpleMessage(NON_BOUNCEABLE, tgUSDJettonMaster, 0, msgBody, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        return;
    }

    if (op == OP_CALL_TO_JETTON_MASTER) {
        // Only admin can call to jetton master
        ctxSender.requireAdmin(admin);

        // Parse call to jetton master message body
        val (to, tonAmount, masterMsg) = ctxBody.parseCallToJettonMaster();

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeCallToJettonMasterFee();
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Pack OP_CALL_TO_JETTON_MASTER message body
        val msgBody: cell = packCallToJettonMaster(queryId, to, tonAmount, masterMsg);
        sendSimpleMessage(NON_BOUNCEABLE, tgUSDJettonMaster, sendingValue, msgBody, SEND_MODE_REGULAR);
        return;
    }

    if (op == OP_UPGRADE_CONTRACT) {
        // Only admin can upgrade contract
        ctxSender.requireAdmin(admin);

        // Parse update contract message body
        val (newData: cell?, newCode: cell?) = ctxBody.parseUpgradeContract();

        // Validate at least one of newCode or newData is not null, or this upgrade in meaningless
        assert(newCode != null || newData != null, ERROR_INVALID_UPGRADE);

        // Set new code and data if provided
        if (newCode != null) {
            // Validate if new code is not the same as the old code
            requireNotIdenticalCell(newCode, getContractCode());

            setContractCodePostponed(newCode);
        }
        if (newData != null) {
            // Validate if new data is not the same as the old data
            requireNotIdenticalCell(newData, getContractData());

            setContractData(newData);
        }
        return;
    }

    if (op == OP_UPGRADE_REDEEM_ACCOUNT) {
        // Only admin can upgrade redeem account
        ctxSender.requireAdmin(admin);

        // Parse upgrade redeem account message body
        val (redeemAccount: slice, data: cell?) = ctxBody.parseUpgradeChildContract();

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeUpgradNextContractFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Pack OP_UPGRADE message body
        val msgBody: cell = packUpgrade(queryId, data, redeemAccountCode);
        sendSimpleMessage(NON_BOUNCEABLE, redeemAccount, sendingValue, msgBody, SEND_MODE_REGULAR);

        saveData();
        return;
    }

    if (op == OP_UPGRADE_JETTON_MASTER) {
        // Only admin can upgrade jetton master
        ctxSender.requireAdmin(admin);

        // Parse upgrade jetton master message body
        val (newData: cell, newCode: cell) = ctxBody.parseUpgradeJettonMaster();

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeUpgradNextContractFee(ctxFwdFee);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Pack OP_UPGRADE message body
        val msgBody: cell = packJettonMasterUpgrade(queryId, newData, newCode);
        sendSimpleMessage(NON_BOUNCEABLE, tgUSDJettonMaster, sendingValue, msgBody, SEND_MODE_REGULAR);

        saveData();
        return;
    }

    if (op == OP_CHANGE_JETTON_MASTER_CONTENT) {
        // Only admin can change jetton master content
        ctxSender.requireAdmin(admin);

        // Check sending value is enough to cover the fee
        val (totalFee: coins, gasConsume: coins) = computeChangeJettonMasterContentFee();
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);
        val sendingValue: coins = ctxValue - gasConsume;

        // Parse change jetton master content message body
        val msgBody: cell = packChangeJettonMasterContent(queryId, ctxBody);
        sendSimpleMessage(NON_BOUNCEABLE, tgUSDJettonMaster, sendingValue, msgBody, SEND_MODE_REGULAR);
        return;
    }

    if (op == OP_UPDATE_SIGNER_KEY) {
        // Only admin can update signer key
        ctxSender.requireAdmin(admin);

        // Parse update signer key message body
        val newSignerKey: SignerKey = ctxBody.loadUint(SIGNER_KEY_SIZE);

        // Check new signer key is not the same as the old one
        requireDifferentSignerKey(newSignerKey, signerKey);

        // Update signer key
        signerKey = newSignerKey;

        // Emit log
        logSignerKeyUpdated(newSignerKey, admin);

        saveData();
        return;
    }

    if (op == OP_TOP_UP) {
        // Only admin can TopUp
        ctxSender.requireAdmin(admin);

        // Parse top up message body
        var jettonMasterTuple: tuple = createEmptyTuple();
        (tgUSDJettonMaster, tgUSDStaking, jettonMasterTuple, custodialWalletsDict, signerKey, redeemWhitelistRoot, baseCode, redeemAccountCode) = ctxBody.parseTopUp();

        // Check fee is enough
        val jettonMasterSize: int = jettonMasterTuple.tupleSize();
        val (totalFee: coins, gasConsume: coins) = computeTopUpFee(jettonMasterSize);
        assert(ctxValue >= totalFee, ERROR_NOT_ENOUGH_FEE);

        // Get all jetton wallets by sending OP_PROVIDE_WALLET_ADDRESS to all jetton masters
        var index: int = 0;
        while (index < jettonMasterSize) {
            var jettonMasterAddress: slice = jettonMasterTuple.tupleAt(index);
            index += 1;

            // Check jettonMasterAddress is not in jettonMastersDict or it means double top up
            jettonMasterAddress.requireJettonMasterAddressNotTaken(jettonMastersDict);

            // Send OP_PROVIDE_WALLET_ADDRESS to jettonMaster
            val msgBody: cell = packProvideWalletAddress(queryId, getMyAddress(), false);
            sendSimpleMessage(NON_BOUNCEABLE, jettonMasterAddress, PROVIDE_WALLET_ADDRESS_VALUE, msgBody, SEND_MODE_REGULAR);

            // Set jettonMasterAddress to the jettonMastersDict, key is jettonMasterAddress and value is addressNone (It will be set in OP_TAKE_WALLET_ADDRESS)
            jettonMastersDict.sDictSet(ADDRESS_SIZE, jettonMasterAddress, createAddressNone());
        }

        // Emit log
        logEngineDeployed(signerKey, redeemWhitelistRoot, custodialWalletsDict, admin);
        
        saveData();
        return;
    }

    if (op == OP_TAKE_WALLET_ADDRESS) {
        // ctxSender should be in jettonMastersDict
        ctxSender.requireSupportedJettonMaster(jettonMastersDict);

        // Parse message to get jetton wallet address
        val jettonWalletAddress: slice = ctxBody.parseTakeWalletAddress();

        // Set jettonWalletAddress to the jettonWalletsBalDict, key is jettonWalletAddress and value is the balance of this asset, with an initial value of 0
        jettonWalletsBalDict.sDictSet(ADDRESS_SIZE, jettonWalletAddress, packBalance(0));
        
        // Set jettonWalletAddress to jettonMastersDict, key is ctxSender(Jetton Master) and value is jettonWalletAddress
        jettonMastersDict.sDictSet(ADDRESS_SIZE, ctxSender, jettonWalletAddress);

        // Emit log (ctxSender is jetton master)
        logEngineWalletAddressTaken(ctxSender, jettonWalletAddress, jettonWalletsBalDict);

        saveData();
        return;
    }

    throw ERROR_WRONG_OP;
}

fun onInternalMessage(myBalance: int, msgValue: int, msgFull: cell, msgBody: slice) {
    if (msgBody.isEndOfSlice()) { // ignore all empty messages
        return;
    }

    var cs: slice = msgFull.beginParse();
    val flags = cs.loadMessageFlags();
    if (isMessageBounced(flags)) { // ignore all bounced messages
        return;
    }

    // Get the context of the incoming message
    val (ctxSender: slice, ctxFwdFee: int) = cs.getCtx(WORKCHAIN); 

    // Load data from storage
    loadData();

    // Route the message to the appropriate handler
    routeInternal(ctxSender, msgValue, ctxFwdFee, msgBody);
}

get redeemAccount(redeemer: slice, redeemAsset: cell): slice {
    loadData();
    
    // Pack RedeemAccount Proof and get RedeemAccount Address
    val tgUSDEngine = getMyAddress();
    val redeemAccountProof: ContractProof = packRedeemAccountProof(tgUSDEngine, redeemer, redeemAsset);
    val (_, redeemAccountAddress: slice) = getChildContract(tgUSDEngine, redeemAccountProof, baseCode);

    return redeemAccountAddress;
}
