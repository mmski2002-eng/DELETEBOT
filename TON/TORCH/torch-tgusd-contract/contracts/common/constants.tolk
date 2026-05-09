// Configuration
const WORKCHAIN = 0;                        // basechain
const MAX_COOLDOWN_PERIOD = 90 * 86400;     // 90 days
const MAX_VESTING_PERIOD = 30 * 86400;      // 30 days

// Data Size
const ADDRESS_SIZE = 267;
const SIGNER_KEY_SIZE = 256;
const MERKLE_ROOT_SIZE = 256;
const CONTRACT_PROOF_SIZE = 256;            // Key storage hash size is 256 bits
const SIGNATURE_SIZE = 512;
const ORDER_TYPE_SIZE = 2;
const TIMESTAMP_SIZE = 32;
const ASSET_PREFIX_SIZE = 4;
const EXOTIC_CELL_TYPE_SIZE = 8;            // Exotic cell type size is 8 bits
const MERKLE_PROOF_TYPE = 3;                // 3 means merkle proof type in exotic cell
const REDEEM_ACCOUNT_STATUS_SIZE = 4;       // Redeem account status size is 4 bits
const CLAIM_STATUS_SIZE = 2;                // Claim status size is 2 bits
const WITHDRAW_STATUS_SIZE = 2;             // Withdraw error status size is 2 bits
const REDEEM_STATUS_SIZE = 2;               // Redeem status size is 2 bits

// Send Value
const PROVIDE_WALLET_ADDRESS_VALUE = ton("0.04");   
const NO_FOWARD_TON = 0;
const MINIMUM_JETTON_NOTIFICATION_VALUE = 1;
const MINT_VALUE = ton("0.06");                     
const DEPLOY_REDEEM_ACCOUNT_VALUE = ton("0.06");   // 6.5 Years
const DEPLOY_UNSTAKE_ACCOUNT_VALUE = ton("0.035"); // 6.5 Years
const LOG_FEE = ton("0.01");                  
const SUPPLY_REWARD_FP_VALUE = ton("0.03");       
const PROVIDE_CURRENT_QUOTE_VALUE = ton("0.03"); 
const ALLOCATE_STAKED_VALUE = ton("0.05"); 
const CLAIM_SUCCESS_VALUE = ton("0.02"); 
const CALL_TO_JETTON_MASTER_VALUE = ton("0.3");
const TRANSFER_REMAINING_COLLATERAL_VALUE = ton("0.06");
const CHANGE_JETTON_MASTER_CONTENT_VALUE = ton("0.03");

// Asset Types
const TON_PREFIX = 0;
const JETTON_PREFIX = 1;
const NOT_SUPPORTED_ASSET = -1;
const NOT_EXTRA_CURRENCY = -1;
const NOT_JETTON_ASSET = "";

// Redeem Account Status
const REDEEM_AVAILABLE = 0;
const REDEEM_PENDING = 1;
const REDEEM_PROCESSING = 2;

// Order Types
const ORDER_TYPE_MINT = 0;
const ORDER_TYPE_REDEEM = 1;

// Redeem Status (Redeem Process)
const REDEEM_SUCCESS = 0;
const REDEEM_DUPLICATED = 1;
const REDEEM_CANCELED = 2;

// Claim Status (Log status)
const CLAIM_SUCCESS = 0;
const CLAIM_BUT_NOT_ENOUGH_COLLATERAL = 1;
const CLAIM_HALTED = 2;

// Withdraw Status (Log status)
const WITHDRAW_SUCCESS = 0;
const WITHDRAW_BUT_HALTED = 1;
const WITHDRAW_BUT_NOT_ENOUGH_STAKED = 2;

// Minimum Storage TON
const MINIMUM_ENGINE_STORAGE_TON = ton("0.1");      // 2 Years
const MINIMUM_STAKING_STORAGE_TON = ton("0.08");    // 2 Years 
