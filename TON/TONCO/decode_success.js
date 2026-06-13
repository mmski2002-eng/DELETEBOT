const { Cell, Slice, Address, beginCell } = require('@ton/core');

// Полный hex body успешной транзакции роутера
const bodyHex = 'b5ee9c72010102010052000297441c39ed0000000000000000e00579e0493e14a7eb5eba90415a2fe8ba8c3b376580cd71c09a3690b531a5f225c0000000000000000000000000000000000000000000000009c449c449c46001010000b4971fe4';

const bodyCell = Cell.fromHex(bodyHex);
const slice = bodyCell.beginParse();

console.log('Total bits:', slice.remainingBits);
console.log('Total refs:', slice.remainingRefs);

const op = slice.loadUint(32);
console.log('OP:', '0x' + op.toString(16));

const qid = slice.loadUint(64);
console.log('Query ID:', '0x' + qid.toString(16));

const isFromAdmin = slice.loadBit();
console.log('is_from_admin:', isFromAdmin);

const hasAdmin = slice.loadBit();
console.log('has_admin:', hasAdmin);

const admin = slice.loadAddress();
console.log('Admin:', admin.toString());

const hasController = slice.loadBit();
console.log('has_controller:', hasController);

const hasTickSpacing = slice.loadBit();
console.log('has_tickSpacing:', hasTickSpacing);

const hasSqrtPriceX96 = slice.loadBit();
console.log('has_sqrtPriceX96:', hasSqrtPriceX96);

const hasActivatePool = slice.loadBit();
console.log('has_activate_pool:', hasActivatePool);

console.log('\nПосле основных полей:');
console.log('bits left:', slice.remainingBits);
console.log('refs left:', slice.remainingRefs);

const protocolFee = slice.loadUint(16);
const lpFee = slice.loadUint(16);
const currentFee = slice.loadUint(16);
console.log('\nfees: protocolFee=' + protocolFee + ', lpFee=' + lpFee + ', currentFee=' + currentFee);

console.log('\nПосле fees:');
console.log('bits left:', slice.remainingBits);
console.log('refs left:', slice.remainingRefs);

// Два обязательных рефа
const ref1 = slice.loadRef();
console.log('\nRef1 (nftContentPacked) bits:', ref1.bits.length, 'refs:', ref1.refs.length);

const ref2 = slice.loadRef();
console.log('Ref2 (nftItemContentPacked) bits:', ref2.bits.length, 'refs:', ref2.refs.length);

console.log('\nПосле двух рефов:');
console.log('bits left:', slice.remainingBits);
console.log('refs left:', slice.remainingRefs);

// Есть ещё ref?
if (slice.remainingRefs > 0) {
    const ref3 = slice.loadRef();
    console.log('\nRef3 (ЕСТЬ! возможно minterCell) bits:', ref3.bits.length, 'refs:', ref3.refs.length);
    // Декодируем minterCell
    const minterSlice = ref3.beginParse();
    console.log('minterCell bits:', minterSlice.remainingBits);
    console.log('minterCell refs:', minterSlice.remainingRefs);
    
    if (minterSlice.remainingBits >= 2) {
        const hasMinter = minterSlice.loadBit();
        console.log('has_minter:', hasMinter);
        if (hasMinter) {
            const minterAddr = minterSlice.loadAddress();
            console.log('minter address:', minterAddr.toString());
        }
    }
}
