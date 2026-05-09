const { beginCell, Address, toNano } = require('@ton/core');

const SET_FEES = 0x355423e5;
const NEW_POOL = 'EQBTVxBp0SNUtghiT6sncaP-FgD2omffgwexK0jK9MZErZQ7';

// Пробуем 3 варианта:
console.log('=== TEST 1: set_fees с любого кошелька (изменить fees) ===');
console.log('Структура: op(32) + query_id(64) + lp_fee(8) + protocol_fee(8) + ref_fee(8) + protocol_fee_address(267)');

const body1 = beginCell()
    .storeUint(SET_FEES, 32)     // op
    .storeUint(0, 64)            // query_id
    .storeUint(30, 8)            // new_lp_fee = 30 (0.3%)
    .storeUint(10, 8)            // new_protocol_fee = 10 (0.1%)
    .storeUint(0, 8)             // new_ref_fee = 0
    .storeAddress(Address.parse('EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c'))  // HOLE_ADDRESS (none)
    .endCell();

const boc1 = body1.toBoc().toString('base64');
console.log('Body BoC:', boc1);
console.log('Tonkeeper link (from ANY wallet):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.1').toString() + '&bin=' + encodeURIComponent(boc1));

console.log('');
console.log('=== TEST 2: Minimal set_fees (все fees = 0, address = HOLE) ===');

const body2 = beginCell()
    .storeUint(SET_FEES, 32)
    .storeUint(0, 64)
    .storeUint(0, 8)             // new_lp_fee = 0
    .storeUint(0, 8)             // new_protocol_fee = 0
    .storeUint(0, 8)             // new_ref_fee = 0
    .storeAddress(Address.parse('EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c'))
    .endCell();

const boc2 = body2.toBoc().toString('base64');
console.log('Body BoC:', boc2);
console.log('Tonkeeper link:');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.1').toString() + '&bin=' + encodeURIComponent(boc2));
