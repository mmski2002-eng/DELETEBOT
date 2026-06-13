const { Cell, Slice, Address } = require('@ton/core');

// Body от роутера к пулу при создании (0x441c39ed)
// b5ee9c72010102010052000297441c39ed0000000000000000e00579e0493e14a7eb5eba90415a2fe8ba8c3b376580cd71c09a3690b531a5f225c0000000000000000000000000000000000000000000000009c449c449c46001010000
const bodyHex = 'b5ee9c72010102010052000297441c39ed0000000000000000e00579e0493e14a7eb5eba90415a2fe8ba8c3b376580cd71c09a3690b531a5f225c0000000000000000000000000000000000000000000000009c449c449c46001010000';

const bodyCell = Cell.fromHex(bodyHex);
const slice = bodyCell.beginParse();

console.log('Total bits:', slice.remainingBits);
console.log('Total refs:', slice.remainingRefs);

const op = slice.loadUint(32);
console.log('OP:', '0x' + op.toString(16));

const queryId = slice.loadUint(64);
console.log('Query ID:', queryId.toString(16));

const isFromAdmin = slice.loadBit();
console.log('is_from_admin:', isFromAdmin);

const hasAdmin = slice.loadBit();
console.log('has_admin:', hasAdmin);

if (hasAdmin) {
    const admin = slice.loadAddress();
    console.log('Admin:', admin.toString());
}

const hasController = slice.loadBit();
console.log('has_controller:', hasController);

const hasTickSpacing = slice.loadBit();
console.log('has_tickSpacing:', hasTickSpacing);

if (hasTickSpacing) {
    const tickSpacing = slice.loadUint(24);
    console.log('tickSpacing:', tickSpacing);
}

const hasSqrtPriceX96 = slice.loadBit();
console.log('has_sqrtPriceX96:', hasSqrtPriceX96);

if (hasSqrtPriceX96) {
    const sqrtPriceX96 = slice.loadUint(160);
    console.log('sqrtPriceX96:', sqrtPriceX96.toString());
}

const hasActivatePool = slice.loadBit();
console.log('has_activate_pool:', hasActivatePool);

if (hasActivatePool) {
    const activatePool = slice.loadBit();
    console.log('activate_pool:', activatePool);
}

// Пробуем прочитать fees
console.log('Remaining bits:', slice.remainingBits);

// Сравним с нашим сообщением
console.log('\n=== Наше сообщение (attack) ===');
const ourBodyHex = 'b5ee9c72010102010052000297441c39ed0000000000000000e00579e0493e14a7eb5eba90415a2fe8ba8c3b376580cd71c09a3690b531a5f225c0000000000000000000000000000000000000000000000009c449c449c46001010000';
const ourCell = Cell.fromHex(ourBodyHex.replace('b5ee9c720101020100520002974', ''));
console.log('Our body hex same as router?', bodyHex === ourBodyHex);
