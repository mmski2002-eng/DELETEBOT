const { Cell, Address } = require('@ton/core');

const dataHex = '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';
const c = Cell.fromHex(dataHex);
const s = c.beginParse();

console.log('=== POOL DATA (c4) ===');
console.log('');

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
console.log('');
console.log('--- Second cell ---');
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
console.log('');
console.log('jetton_lp_wallet_code bits:', lpWalletCode.bits.length, 'refs:', lpWalletCode.refs.length);

// lp_account_code ref
const lpAccountCode = s.loadRef();
console.log('lp_account_code bits:', lpAccountCode.bits.length, 'refs:', lpAccountCode.refs.length);

// what's left?
console.log('');
console.log('remaining bits:', s.remainingBits, 'refs:', s.remainingRefs);
