const fs = require('fs');
const { Cell, Address } = require('@ton/core');

// Read data from a separate file
const dataBase64 = fs.readFileSync(__dirname + '/pool_data.b64', 'utf8').trim();
const cells = Cell.fromBase64(dataBase64);
// fromBase64 returns an array
const c = cells;

const s = c.beginParse();

console.log('=== POOL DATA (c4) ===\n');

// router_address
const routerAddr = s.loadAddress();
console.log('router_address:', routerAddr.toString());

// lp_fee (8 bits)
const lpFee = s.loadUint(8);
console.log('lp_fee:', lpFee);

// protocol_fee (8 bits)
const protocolFee = s.loadUint(8);
console.log('protocol_fee:', protocolFee);

// ref_fee (8 bits)
const refFee = s.loadUint(8);
console.log('ref_fee:', refFee);

// token0_address
const token0 = s.loadAddress();
console.log('token0_address:', token0.toString());

// token1_address
const token1 = s.loadAddress();
console.log('token1_address:', token1.toString());

// total_supply_lp
const totalSupply = s.loadCoins();
console.log('total_supply_lp:', totalSupply.toString());

// ref cell with collected fees, reserves, protocol_fee_address
const refCell = s.loadRef();
const rs = refCell.beginParse();
console.log('\n--- Second cell (collected fees, reserves, protocol_fee_address) ---');
const collected0 = rs.loadCoins();
const collected1 = rs.loadCoins();
const protocolFeeAddr = rs.loadAddress();
const reserve0 = rs.loadCoins();
const reserve1 = rs.loadCoins();
console.log('collected_token0_protocol_fee:', collected0.toString());
console.log('collected_token1_protocol_fee:', collected1.toString());
console.log('protocol_fee_address:', protocolFeeAddr.toString());
console.log('reserve0:', reserve0.toString());
console.log('reserve1:', reserve1.toString());

// jetton_lp_wallet_code ref
const lpWalletCode = s.loadRef();
console.log('\njetton_lp_wallet_code bits:', lpWalletCode.bits.length, 'refs:', lpWalletCode.refs.length);

// lp_account_code ref
const lpAccountCode = s.loadRef();
console.log('lp_account_code bits:', lpAccountCode.bits.length, 'refs:', lpAccountCode.refs.length);

console.log('\nremaining bits:', s.remainingBits, 'refs:', s.remainingRefs);

