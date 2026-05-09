const t = require('./nft-contracts/node_modules/@ton/ton');
console.log('WalletContractV4:', typeof t.WalletContractV4);
console.log('TonClient:', typeof t.TonClient);
console.log('internal:', typeof t.internal);
console.log('toNano:', typeof t.toNano);
console.log('Address:', typeof t.Address);
console.log('Cell:', typeof t.Cell);
console.log('beginCell:', typeof t.beginCell);
console.log('contractAddress:', typeof t.contractAddress);
console.log('SendMode:', typeof t.SendMode);

const c = require('./nft-contracts/node_modules/@ton/crypto');
console.log('mnemonicToWalletKey:', typeof c.mnemonicToWalletKey);