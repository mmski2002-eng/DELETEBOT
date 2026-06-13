const { beginCell, Address, toNano } = require('@ton/core');

const POOLV3_INIT = 0x441c39ed;
const YOUR_WALLET = 'UQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuLpT';
const NEW_POOL = 'EQBTVxBp0SNUtghiT6sncaP-FgD2omffgwexK0jK9MZErZQ7';

// Имитируем сообщение роутера при создании пула
// fees = 0, без minterCell
const body = beginCell()
    .storeUint(POOLV3_INIT, 32)
    .storeUint(0, 64)
    .storeUint(1, 1)  // is_from_admin = true
    .storeUint(1, 1)  // has_admin = true
    .storeAddress(Address.parse(YOUR_WALLET))
    .storeUint(0, 1)  // has_controller = false
    .storeUint(0, 1)  // has_tickSpacing = false
    .storeUint(0, 1)  // has_sqrtPriceX96 = false
    .storeUint(0, 1)  // has_activate_pool = false
    .storeUint(0, 16)  // protocolFee = 0 (как в роутере)
    .storeUint(0, 16)  // lpFee = 0 (как в роутере)
    .storeUint(0, 16)  // currentFee = 0 (как в роутере)
    .storeRef(beginCell().endCell())  // nftContentPacked = пустой
    .storeRef(beginCell().endCell())  // nftItemContentPacked = пустой
    .endCell();

const boc = body.toBoc().toString('base64');
console.log('Body BoC:', boc);
console.log('');
console.log('Ссылка для Tonkeeper:');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.15').toString() + '&bin=' + encodeURIComponent(boc));
