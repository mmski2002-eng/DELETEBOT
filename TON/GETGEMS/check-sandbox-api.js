const sb = require('./nft-contracts/node_modules/@ton/sandbox');
console.log('=== Blockchain ===');
console.log(Object.getOwnPropertyNames(sb.Blockchain.prototype).join('\n'));
console.log('');
console.log('=== TreasuryContract ===');
console.log(Object.getOwnPropertyNames(sb.TreasuryContract.prototype).join('\n'));
console.log('');
console.log('=== SmartContract ===');
console.log(Object.getOwnPropertyNames(sb.SmartContract.prototype).join('\n'));