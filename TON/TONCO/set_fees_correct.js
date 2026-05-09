const { beginCell, Address, toNano } = require('@ton/core');

// Правильные опкоды TONCO v3
const POOLV3_SET_FEE = 0x6bdcbeb8;
const NEW_POOL = 'EQBTVxBp0SNUtghiT6sncaP-FgD2omffgwexK0jK9MZErZQ7';

console.log('=== POOLV3_SET_FEE (0x6bdcbeb8) ===');
console.log('Структура: op(32) + query_id(64) + protocolFee(16) + lpFee(16) + currentFee(16)');
console.log('Из SDK: messageSetFees(protocolFee, lpFee, currentFee)');
console.log('');

// TEST 1: Все fees = 0 (без комиссий)
const body1 = beginCell()
    .storeUint(POOLV3_SET_FEE, 32)  // op
    .storeUint(0, 64)               // query_id
    .storeUint(0, 16)               // protocolFee = 0
    .storeUint(0, 16)               // lpFee = 0
    .storeUint(0, 16)               // currentFee = 0
    .endCell();

const boc1 = body1.toBoc().toString('base64');
console.log('TEST 1 - Все fees=0:');
console.log('Body BoC:', boc1);
console.log('Tonkeeper link:');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.1').toString() + '&bin=' + encodeURIComponent(boc1));
console.log('');

// TEST 2: fees как в SDK (30, 30, 30)
const body2 = beginCell()
    .storeUint(POOLV3_SET_FEE, 32)
    .storeUint(0, 64)
    .storeUint(30, 16)              // protocolFee = 30 (0.3%)
    .storeUint(30, 16)              // lpFee = 30 (0.3%)
    .storeUint(30, 16)              // currentFee = 30 (0.3%)
    .endCell();

const boc2 = body2.toBoc().toString('base64');
console.log('TEST 2 - fees=30:');
console.log('Body BoC:', boc2);
console.log('Tonkeeper link:');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.1').toString() + '&bin=' + encodeURIComponent(boc2));
