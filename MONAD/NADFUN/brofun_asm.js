const fs = require('fs');
const https = require('https');

const RPC = 'https://rpc.monad.xyz';
const PROXY = '0xDF7A89Fc62e5120C4617f143C7AcDDAB0D1Ca7A2';

function rpc(method, params, id=1) {
  return new Promise((res, rej) => {
    const body = JSON.stringify({ jsonrpc:'2.0', method, params, id });
    const req = https.request(RPC, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) }
    }, (r) => {
      let data = '';
      r.on('data', c => data += c);
      r.on('end', () => { try { res(JSON.parse(data)); } catch(e) { rej(e); } });
    });
    req.on('error', rej);
    req.write(body);
    req.end();
  });
}

// EVM opcodes
const OPS = {
  '00': 'STOP', '01': 'ADD', '02': 'MUL', '03': 'SUB', '04': 'DIV',
  '10': 'LT', '11': 'GT', '12': 'SLT', '13': 'SGT', '14': 'EQ',
  '15': 'ISZERO', '16': 'AND', '17': 'OR', '18': 'XOR', '19': 'NOT',
  '1a': 'BYTE', '1b': 'SHL', '1c': 'SHR', '20': 'SHA3',
  '30': 'ADDRESS', '31': 'BALANCE', '32': 'ORIGIN', '33': 'CALLER',
  '34': 'CALLVALUE', '35': 'CALLDATALOAD', '36': 'CALLDATASIZE',
  '37': 'CALLDATACOPY', '38': 'CODESIZE', '39': 'CODECOPY',
  '3b': 'EXTCODESIZE', '3d': 'RETURNDATASIZE', '3e': 'RETURNDATACOPY',
  '40': 'BLOCKHASH', '41': 'COINBASE', '42': 'TIMESTAMP', '43': 'NUMBER',
  '44': 'DIFFICULTY', '45': 'GASLIMIT', '46': 'CHAINID', '47': 'SELFBALANCE',
  '50': 'POP', '51': 'MLOAD', '52': 'MSTORE', '53': 'MSTORE8',
  '54': 'SLOAD', '55': 'SSTORE', '56': 'JUMP', '57': 'JUMPI',
  '58': 'PC', '59': 'MSIZE', '5b': 'JUMPDEST', '5f': 'PUSH0',
  '80': 'DUP1', '81': 'DUP2', '82': 'DUP3', '83': 'DUP4', '84': 'DUP5',
  '85': 'DUP6', '86': 'DUP7', '87': 'DUP8', '88': 'DUP9', '89': 'DUP10',
  '90': 'SWAP1', '91': 'SWAP2', '92': 'SWAP3', '93': 'SWAP4', '94': 'SWAP5',
  'a0': 'LOG0', 'a1': 'LOG1', 'a2': 'LOG2', 'a3': 'LOG3', 'a4': 'LOG4',
  'f0': 'CREATE', 'f1': 'CALL', 'f2': 'CALLCODE', 'f3': 'RETURN',
  'f4': 'DELEGATECALL', 'fa': 'STATICCALL', 'fd': 'REVERT', 'fe': 'INVALID',
};

function disasm(hex, startByte, maxBytes=150) {
  const out = [];
  let i = startByte * 2;
  let byteCount = 0;
  while (i < hex.length && byteCount < maxBytes) {
    const op = hex.slice(i, i+2).toLowerCase();
    const pc = i / 2;
    if (op >= '60' && op <= '7f') {
      // PUSH1-PUSH32
      const n = parseInt(op, 16) - 0x5f;
      const data = hex.slice(i+2, i+2+n*2);
      out.push(`0x${pc.toString(16).padStart(4,'0')}: PUSH${n} 0x${data}`);
      i += 2 + n*2;
      byteCount += 1 + n;
    } else {
      const name = OPS[op] || `UNK_${op}`;
      out.push(`0x${pc.toString(16).padStart(4,'0')}: ${name}`);
      i += 2;
      byteCount++;
    }
  }
  return out.join('\n');
}

async function pad32uint(n) { return n.toString(16).padStart(64, '0'); }
function p32u(n) { return n.toString(16).padStart(64, '0'); }
function p32a(addr) { return '000000000000000000000000' + addr.slice(2).toLowerCase(); }

async function ethCall(sel, args='', from=null) {
  const callObj = { to: PROXY, data: sel + args };
  if (from) callObj.from = from;
  return await rpc('eth_call', [callObj, 'latest']);
}

async function main() {
  const code = fs.readFileSync('c:\\DELETEBOT\\MONAD\\NADFUN\\impl_bytecode.hex', 'utf8').trim();
  console.log('Bytecode size:', code.length/2, 'bytes\n');

  // Disassemble key unknown functions
  const targets = [
    { name: '0x02153e29 (createGame?)', offset: 0x1e1 },
    { name: '0x03c068b8 (settle?)', offset: 0x203 },
    { name: '0x0c4c8d89 (claimReward?)', offset: 0x23f },
    { name: '0x14346d07', offset: 0x2cd },
    { name: '0x278d1a3e', offset: 0x387 },
    { name: '0x32a73b58', offset: 0x3ca },
    { name: '0x47f0e29b', offset: 0x416 },
    { name: '0x9fda24a4', offset: 0x506 },
    { name: '0xd0d65411', offset: 0x526 },
    { name: '0xd99e1a48', offset: 0x546 },
  ];

  for (const t of targets) {
    console.log(`\n=== ${t.name} @ 0x${t.offset.toString(16)} ===`);
    console.log(disasm(code, t.offset, 80));
  }

  // Look for ecrecover (STATICCALL to addr 0x01)
  console.log('\n\n=== ecrecover occurrences (STATICCALL pattern) ===');
  // Find all STATICCALL opcodes (0xfa)
  let staticcallCount = 0;
  for (let i = 0; i < code.length - 2; i += 2) {
    if (code.slice(i, i+2) === 'fa') {
      console.log(`STATICCALL at byte 0x${(i/2).toString(16)}`);
      // Show context 10 bytes before
      console.log('  Context:', disasm(code, Math.max(0, i/2-15), 30));
      staticcallCount++;
    }
  }
  if (staticcallCount === 0) console.log('No STATICCALL found - uses CALL for ecrecover?');

  // Find all CALL opcodes (0xf1)
  console.log('\n=== CALL opcodes (ecrecover/external) ===');
  for (let i = 0; i < code.length - 2; i += 2) {
    if (code.slice(i, i+2) === 'f1') {
      console.log(`CALL at byte 0x${(i/2).toString(16)}`);
    }
  }

  // Find SHA3 (keccak256) usage
  console.log('\n=== SHA3/keccak256 opcodes ===');
  let sha3s = [];
  for (let i = 0; i < code.length - 2; i += 2) {
    if (code.slice(i, i+2) === '20') {
      sha3s.push(`0x${(i/2).toString(16)}`);
    }
  }
  console.log('SHA3 at:', sha3s.join(', '));

  // Find CALLVALUE (payable functions check msg.value)
  console.log('\n=== CALLVALUE occurrences (payable functions) ===');
  for (let i = 0; i < code.length - 2; i += 2) {
    if (code.slice(i, i+2) === '34') {
      console.log(`CALLVALUE at byte 0x${(i/2).toString(16)}`);
    }
  }

  // Find SSTORE (storage writes - important for game state)
  console.log('\n=== SSTORE occurrences (state writes) ===');
  for (let i = 0; i < code.length - 2; i += 2) {
    if (code.slice(i, i+2) === '55') {
      console.log(`SSTORE at byte 0x${(i/2).toString(16)}`);
    }
  }

  // Look for LOG events (event emissions)
  console.log('\n=== LOG opcodes (events) ===');
  for (let i = 0; i < code.length - 2; i += 2) {
    const op = code.slice(i, i+2);
    if (['a0','a1','a2','a3','a4'].includes(op)) {
      console.log(`LOG${parseInt(op,16)-0xa0} at byte 0x${(i/2).toString(16)}`);
    }
  }

  // Find TIMESTAMP (for signature expiry)
  console.log('\n=== TIMESTAMP occurrences ===');
  for (let i = 0; i < code.length - 2; i += 2) {
    if (code.slice(i, i+2) === '42') {
      console.log(`TIMESTAMP at byte 0x${(i/2).toString(16)}`);
    }
  }

  // Now try calling unknown functions with payable value
  console.log('\n\n=== Payable probe (with 1 wei) ===');
  const unknowns = ['0x02153e29', '0x03c068b8', '0x0c4c8d89', '0x9fda24a4', '0xd0d65411', '0xd99e1a48', '0x47f0e29b', '0x32a73b58', '0x278d1a3e', '0x14346d07'];
  for (const sel of unknowns) {
    const r = await rpc('eth_call', [{ to: PROXY, data: sel, value: '0xde0b6b3a7640000' }, 'latest']); // 1 MON
    if (r.error?.message !== 'execution reverted') {
      console.log(`${sel} payable: ${r.error?.message || r.result}`);
    } else {
      console.log(`${sel} payable: reverts`);
    }
  }

  // Map storage layout for games mapping
  console.log('\n=== Game storage slot mapping ===');
  // For OZ proxy + UUPS: storage starts after _initialized, _initializing, gap...
  // Typical OZ UUPS layout at high slots. The games mapping is likely at slot 2 or 3 (after string at slot 1)
  // Let's compute keccak256(gameId . mappingSlot) for slots 2-6 and check
  const { createHash } = require('crypto');
  // We can't compute keccak256 with Node's built-in crypto (it uses SHA-256 not Keccak)
  // But we can try storage slots directly for game 1 across multiple mapping slots
  console.log('Trying to find games mapping slot...');

  // The game data we know: game[1].player = 0x5ba865cf...
  // Check slots around where OZ stores game data
  // OZ UUPS Initializable gap: slots 0-49 are reserved
  // But this contract has data at slot 0 (gameCounter) and slot 1 (string)
  // So it might NOT use OZ gap
  // The games mapping would be at slot 2 (right after gameCounter and name)
  // But we need keccak256 to compute the actual slot

  // Alternative: scan all storage slots from 0 to 100 to find non-zero
  console.log('Non-zero storage slots 0-50:');
  for (let i = 0; i <= 50; i++) {
    const slot = '0x' + i.toString(16).padStart(64, '0');
    const r = await rpc('eth_getStorageAt', [PROXY, slot, 'latest']);
    if (r.result !== '0x0000000000000000000000000000000000000000000000000000000000000000') {
      console.log(`slot[${i}] (0x${i.toString(16)}): ${r.result}`);
    }
  }
}

main().catch(console.error);
