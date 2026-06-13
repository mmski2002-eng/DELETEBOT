const {Cell} = require('@ton/core');

// Тело из успешного POOLV3_INIT роутера
const routerHex = 'b5ee9c72010102010052000297441c39ed0000000000000000e00579e0493e14a7eb5eba90415a2fe8ba8c3b376580cd71c09a3690b531a5f225c0000000000000000000000000000000000000000000000009c449c449c46001010000b4971fe4';

const body = Cell.fromHex(routerHex);
const s = body.beginParse();

console.log('=== РОУТЕР: POOLV3_INIT ===');
console.log('Total bits:', s.remainingBits);
console.log('Total refs:', s.remainingRefs);
console.log('');

const op = s.loadUint(32);
console.log('1. op:', '0x'+op.toString(16), op === 0x441c39ed ? '(POOLV3_INIT!)' : '???');

const qid = s.loadUint(64);
console.log('2. query_id:', qid);

const isFromAdmin = s.loadBit();
console.log('3. is_from_admin:', isFromAdmin);

const hasAdmin = s.loadBit();
console.log('4. has_admin:', hasAdmin);
if (hasAdmin) {
    console.log('   admin:', s.loadAddress().toString());
}

const hasController = s.loadBit();
console.log('5. has_controller:', hasController);
if (hasController) {
    console.log('   controller:', s.loadAddress().toString());
}

const hasTickSpacing = s.loadBit();
console.log('6. has_tickSpacing:', hasTickSpacing);
const tickSpacing = hasTickSpacing ? s.loadUint(24) : '(skip 24 bits?)';
if (!hasTickSpacing) {
    // даже если false, может читать 24 бита? Нет, в SDK:
    // .storeUint(opts.tickSpacing ?? 0, 24) - всегда записывает 24 бита
    s.loadUint(24); // пропускаем 24 бита
    console.log('   tickSpacing (skipped 24):', '0');
}

const hasSqrtPriceX96 = s.loadBit();
console.log('7. has_sqrtPriceX96:', hasSqrtPriceX96);
if (hasSqrtPriceX96) {
    console.log('   sqrtPriceX96:', s.loadUintBig(160).toString());
} else {
    s.loadUintBig(160); // пропускаем 160 бит
    console.log('   sqrtPriceX96 (skipped 160):', '0');
}

const hasActivatePool = s.loadBit();
console.log('8. has_activate_pool:', hasActivatePool);
const activatePool = s.loadBit();
console.log('9. activate_pool:', activatePool);

console.log('');
console.log('--- AFTER HEADER (bits left:', s.remainingBits, 'refs:', s.remainingRefs, ') ---');

const protocolFee = s.loadUint(16);
console.log('10. protocolFee:', protocolFee);

const lpFee = s.loadUint(16);
console.log('11. lpFee:', lpFee);

const currentFee = s.loadUint(16);
console.log('12. currentFee:', currentFee);

console.log('');
console.log('--- AFTER FEES (bits left:', s.remainingBits, 'refs:', s.remainingRefs, ') ---');

const ref1 = s.loadRef();
console.log('13. ref1 (nftContentPacked) bits:', ref1.bits.length, 'refs:', ref1.refs.length);

const ref2 = s.loadRef();
console.log('14. ref2 (nftItemContentPacked) bits:', ref2.bits.length, 'refs:', ref2.refs.length);

console.log('');
console.log('--- AFTER TWO REFS (bits left:', s.remainingBits, 'refs:', s.remainingRefs, ') ---');

// Это storeMaybeRef(minterCell): 1 бит (has_minter) + если есть, ref
if (s.remainingBits > 0) {
    const hasMinter = s.loadBit();
    console.log('15. has_minter (maybe ref):', hasMinter);
    if (hasMinter && s.remainingRefs > 0) {
        const minterRef = s.loadRef();
        console.log('    minterCell bits:', minterRef.bits.length, 'refs:', minterRef.refs.length);
        const ms = minterRef.beginParse();
        console.log('    minter0:', ms.loadAddress().toString());
        console.log('    minter1:', ms.loadAddress().toString());
    }
}

console.log('');
console.log('FINALLY left - bits:', s.remainingBits, 'refs:', s.remainingRefs);
