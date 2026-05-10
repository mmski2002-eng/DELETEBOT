const fs = require('fs');
const https = require('https');

const RPC = 'https://rpc.monad.xyz';
const PROXY = '0xDF7A89Fc62e5120C4617f143C7AcDDAB0D1Ca7A2';

function rpc(m, p, id=1) {
  return new Promise((res, rej) => {
    const body = JSON.stringify({ jsonrpc:'2.0', method:m, params:p, id });
    const req = https.request(RPC, { method:'POST', headers:{'Content-Type':'application/json','Content-Length':Buffer.byteLength(body)} }, (r) => {
      let d=''; r.on('data',c=>d+=c); r.on('end',()=>{try{res(JSON.parse(d));}catch(e){rej(e);}});
    });
    req.on('error',rej); req.write(body); req.end();
  });
}

const OPS = {
  '00':'STOP','01':'ADD','02':'MUL','03':'SUB','04':'DIV','05':'SDIV',
  '06':'MOD','08':'ADDMOD','0a':'EXP',
  '10':'LT','11':'GT','12':'SLT','13':'SGT','14':'EQ',
  '15':'ISZERO','16':'AND','17':'OR','18':'XOR','19':'NOT',
  '1a':'BYTE','1b':'SHL','1c':'SHR','1d':'SAR',
  '20':'SHA3',
  '30':'ADDRESS','31':'BALANCE','32':'ORIGIN','33':'CALLER',
  '34':'CALLVALUE','35':'CALLDATALOAD','36':'CALLDATASIZE',
  '37':'CALLDATACOPY','38':'CODESIZE','39':'CODECOPY',
  '3b':'EXTCODESIZE','3d':'RETURNDATASIZE','3e':'RETURNDATACOPY',
  '40':'BLOCKHASH','41':'COINBASE','42':'TIMESTAMP','43':'NUMBER',
  '44':'DIFFICULTY','45':'GASLIMIT','46':'CHAINID','47':'SELFBALANCE',
  '50':'POP','51':'MLOAD','52':'MSTORE','53':'MSTORE8',
  '54':'SLOAD','55':'SSTORE','56':'JUMP','57':'JUMPI',
  '58':'PC','59':'MSIZE','5a':'GAS','5b':'JUMPDEST','5f':'PUSH0',
  '80':'DUP1','81':'DUP2','82':'DUP3','83':'DUP4','84':'DUP5',
  '85':'DUP6','86':'DUP7','87':'DUP8','88':'DUP9','89':'DUP10',
  '8a':'DUP11','8b':'DUP12','8c':'DUP13',
  '90':'SWAP1','91':'SWAP2','92':'SWAP3','93':'SWAP4','94':'SWAP5',
  '95':'SWAP6','96':'SWAP7',
  'a0':'LOG0','a1':'LOG1','a2':'LOG2','a3':'LOG3','a4':'LOG4',
  'f0':'CREATE','f1':'CALL','f2':'CALLCODE','f3':'RETURN',
  'f4':'DELEGATECALL','fa':'STATICCALL','fd':'REVERT','fe':'INVALID',
};

function disasm(hex, startByte, maxBytes=200) {
  const out = [];
  let i = startByte * 2;
  let byteCount = 0;
  while (i < hex.length - 1 && byteCount < maxBytes) {
    const op = hex.slice(i, i+2).toLowerCase();
    const pc = i / 2;
    if (op >= '60' && op <= '7f') {
      const n = parseInt(op, 16) - 0x5f;
      const data = hex.slice(i+2, i+2+n*2);
      out.push(`0x${pc.toString(16).padStart(4,'0')}: PUSH${n} 0x${data}`);
      i += 2 + n*2;
      byteCount += 1 + n;
    } else {
      const name = OPS[op] || `0x${op}`;
      out.push(`0x${pc.toString(16).padStart(4,'0')}: ${name}`);
      i += 2;
      byteCount++;
    }
  }
  return out.join('\n');
}

async function main() {
  const code = fs.readFileSync('c:\\DELETEBOT\\MONAD\\NADFUN\\impl_bytecode.hex','utf8').trim();
  console.log('=== KEY FUNCTION BODY DISASSEMBLY ===\n');

  // Disassemble ALL function bodies
  const bodies = [
    { name: '0x02153e29 body', offset: 0x05b3 },
    { name: '0x03c068b8 body', offset: 0x0617 },
    { name: '0x32a73b58 body', offset: 0x09c1 },
    { name: '0x47f0e29b body', offset: 0x0b73 },
    { name: '0x9fda24a4 body', offset: 0x11b0 },
    { name: '0xd0d65411 body', offset: 0x134b },
    { name: '0xd99e1a48 body end + 0x14db', offset: 0x14db },
    { name: 'ecrecover area (0x1b90)', offset: 0x1b90 },
    { name: 'parser 0x1da2', offset: 0x1da2 },
    { name: 'parser 0x1df5', offset: 0x1df5 },
    { name: 'parser 0x1c62', offset: 0x1c62 },
  ];

  for (const b of bodies) {
    console.log(`\n===== ${b.name} @ 0x${b.offset.toString(16)} =====`);
    console.log(disasm(code, b.offset, 120));
  }

  // Special: look for CALLER opcode (msg.sender usage) - important for auth
  console.log('\n=== CALLER opcodes (msg.sender checks) ===');
  for (let i = 0; i < code.length - 2; i += 2) {
    if (code.slice(i, i+2) === '33') {
      console.log(`CALLER at byte 0x${(i/2).toString(16)}`);
    }
  }

  // Find CHAINID opcode
  console.log('\n=== CHAINID opcodes ===');
  let chainIds = [];
  for (let i = 0; i < code.length - 2; i += 2) {
    if (code.slice(i, i+2) === '46') {
      chainIds.push(`0x${(i/2).toString(16)}`);
    }
  }
  console.log('CHAINID at:', chainIds.length ? chainIds.join(', ') : 'NONE FOUND');

  // Look for specific patterns around ecrecover call at 0x1bbd
  console.log('\n=== ecrecover call context (0x1b50 - 0x1bf0) ===');
  console.log(disasm(code, 0x1b50, 200));

  // Look for what's at 0x11b0 (0x9fda24a4 body) - crucial settlement function
  console.log('\n=== 0x9fda24a4 full body (0x11b0 - long) ===');
  console.log(disasm(code, 0x11b0, 300));

  // Look for what's at 0x09c1 (0x32a73b58 body)
  console.log('\n=== 0x32a73b58 full body (0x09c1) ===');
  console.log(disasm(code, 0x09c1, 300));

  // Monad chain ID check
  console.log('\n=== Monad chain ID ===');
  const chainId = await rpc('eth_chainId', []);
  console.log('Monad chainId:', parseInt(chainId.result, 16));
}

main().catch(console.error);
