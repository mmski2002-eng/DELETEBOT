const { beginCell, Address, toNano } = require('@ton/core');

const POOLV3_INIT = 0x441c39ed;
const IMPOSSIBLE_FEE = 10001;
const YOUR_WALLET = 'UQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuLpT';
const NEW_POOL = 'EQBTVxBp0SNUtghiT6sncaP-FgD2omffgwexK0jK9MZErZQ7';

// POOLV3_INIT с is_from_admin=1, admin = наш кошелек
const body = beginCell()
    .storeUint(POOLV3_INIT, 32)
    .storeUint(0, 64)
    .storeUint(1, 1)  // is_from_admin = 1
    .storeUint(1, 1)  // has_admin = true
    .storeAddress(Address.parse(YOUR_WALLET))  // admin
    .storeUint(0, 1)  // has_controller = false
    .storeUint(0, 1)  // has_tickSpacing = false
    .storeUint(0, 24)
    .storeUint(0, 1)  // has_sqrtPriceX96 = false
    .storeUint(0, 160)
    .storeUint(0, 1)  // has_activate_pool = false
    .storeUint(0, 1)
    .storeUint(IMPOSSIBLE_FEE, 16)  // protocolFee
    .storeUint(IMPOSSIBLE_FEE, 16)  // lpFee
    .storeUint(IMPOSSIBLE_FEE, 16)  // currentFee
    .storeRef(beginCell().endCell())  // nftContentPacked
    .storeRef(beginCell().endCell())  // nftItemContentPacked
    .endCell();

const boc = body.toBoc().toString('base64');
console.log('Body BoC:', boc);
console.log('');
console.log('Ссылка для Tonkeeper:');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.15').toString() + '&bin=' + encodeURIComponent(boc));
