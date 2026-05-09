// Common op codes
const OP_TOP_UP = 0xd372158c;
const OP_COMMENT = 0;
const OP_RESET_GAS = stringCrc32("ResetGas");
const OP_CHANGE_ADMIN = 0x6501f354;
const OP_CLAIM_ADMIN = 0xfb88e119;
const OP_UPGRADE_CONTRACT = 0x2508d66a;
const OP_HALT = stringCrc32("Halt");
const OP_UNHALT = stringCrc32("Unhalt");
const OP_CALL_TO_JETTON_MASTER = stringCrc32("CallToJettonMaster");
const OP_CALL_TO = 0x235caf52;
const OP_CHANGE_JETTON_MASTER_ADMIN = stringCrc32("ChangeJettonMasterAdmin");
const OP_UPGRADE_JETTON_MASTER = stringCrc32("UpgradeJettonMaster");
const OP_CHANGE_JETTON_MASTER_CONTENT = stringCrc32("ChangeJettonMasterContent");

// TGUSD Engine op codes
const OP_DEPOSIT_FP = stringCrc32("DepositFP");
const OP_UPDATE_REDEEM_WHITELIST_ROOT = stringCrc32("UpdateRedeemWhitelistRoot");
const OP_REQUEST_REDEEM = stringCrc32("RequestRedeem");
const OP_EXTRA_BURN_INFO = stringCrc32("ExtraBurnInfo");
const OP_REPAY_FP = stringCrc32("RepayFP");
const OP_CLAIM = stringCrc32("Claim");
const OP_PAYOUT = stringCrc32("Payout");
const OP_ROLLBACK_CLAIM = stringCrc32("RollbackClaim");
const OP_CLAIM_SUCCESS = stringCrc32("ClaimSuccess");
const OP_ADD_CUSTODIAL_WALLET = stringCrc32("AddCustodialWallet");
const OP_REMOVE_CUSTODIAL_WALLET = stringCrc32("RemoveCustodialWallet");
const OP_UPDATE_REDEEM_ACCOUNT_CODE = stringCrc32("UpdateRedeemAccountCode");
const OP_ADD_COLLATERAL_ASSET = stringCrc32("AddCollateralAsset");
const OP_REMOVE_COLLATERAL_ASSET = stringCrc32("RemoveCollateralAsset");
const OP_UPGRADE_REDEEM_ACCOUNT = stringCrc32("UpgradeRedeemAccount");
const OP_CANCEL_REDEEM = stringCrc32("CancelRedeem");
const OP_CANCEL_REDEEM_INTERNAL = stringCrc32("CancelRedeemInternal");
const OP_FORCE_CLAIM = stringCrc32("ForceClaim");
const OP_UPDATE_SIGNER_KEY = stringCrc32("UpdateSignerKey");

// TGUSD Staking op codes
const OP_STAKE_FP = stringCrc32("StakeFP");
const OP_REQUEST_UNSTAKE_FP = stringCrc32("RequestUnstakeFP");
const OP_TRANSFER_REWARD_FP = stringCrc32("TransferRewardFP");
const OP_ALLOCATE_STAKED = stringCrc32("AllocateStaked");
const OP_DEALLOCATE_STAKED_FP = stringCrc32("DeallocateStakedFP");
const OP_PROVIDE_CURRENT_QUOTE = stringCrc32("ProvideCurrentQuote");
const OP_TAKE_CURRENT_QUOTE = stringCrc32("TakeCurrentQuote");
const OP_UPDATE_UNSTAKE_ACCOUNT_CODE = stringCrc32("UpdateUnstakeAccountCode");
const OP_UPDATE_COOLDOWN_PERIOD = stringCrc32("UpdateCooldownPeriod");
const OP_UPDATE_VESTING_PERIOD = stringCrc32("UpdateVestingPeriod");
const OP_UPGRADE_UNSTAKE_ACCOUNT = stringCrc32("UpgradeUnstakeAccount");
const OP_FORCE_WITHDRAW = stringCrc32("ForceWithdraw");

// Base contract opcodes
const OP_INSTALL = stringCrc32("Install");

// Unstake Account op codes
const OP_WITHDRAW = stringCrc32("Withdraw");
const OP_WITHDRAW_INTERNAL = stringCrc32("WithdrawInternal");
const OP_ROLLBACK_WITHDRAW = stringCrc32("RollbackWithdraw");
const OP_SUPPLY_REWARD_FP = stringCrc32("SupplyRewardFP");

// Jetton opcodes
const OP_TRANSFER_NOTIFICATION = 0x7362d09c;
const OP_INTERNAL_TRANSFER = 0x178d4519;
const OP_TRANSFER = 0xf8a7ea5;
const OP_EXCESSES = 0xd53276db;
const OP_MINT = 0x642b7d07;
const OP_PROVIDE_WALLET_ADDRESS = 0x2c76b973;
const OP_TAKE_WALLET_ADDRESS = 0xd1735400;
const OP_CHANGE_METADATA_URI = 0xcb862902;

