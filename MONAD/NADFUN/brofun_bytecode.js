const https = require('https');

const RPC = 'https://rpc.monad.xyz';
const IMPL = '0x5e3c429f1ea90f06bae5c6de46eef94fd2cdfbc4';
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

function pad32uint(n) { return n.toString(16).padStart(64, '0'); }
function pad32addr(addr) { return '000000000000000000000000' + addr.slice(2).toLowerCase(); }

async function ethCall(sel, args='', from=null) {
  const callObj = { to: PROXY, data: sel + args };
  if (from) callObj.from = from;
  return await rpc('eth_call', [callObj, 'latest']);
}

async function main() {
  console.log('=== BYTECODE DISPATCH TABLE ANALYSIS ===\n');

  // Get full implementation bytecode
  const codeRes = await rpc('eth_getCode', [IMPL, 'latest']);
  const code = codeRes.result.slice(2);

  // Parse dispatch table: find all PUSH4 + EQ + PUSH2/PUSH3 + JUMPI patterns
  // Opcode: 63=PUSH4, 14=EQ, 57=JUMPI, 56=JUMP, 61=PUSH2, 62=PUSH3
  const dispatch = [];
  for (let i = 0; i < code.length - 20; i += 2) {
    const byte = code.slice(i, i+2);
    if (byte === '63') { // PUSH4
      const sel = '0x' + code.slice(i+2, i+10);
      // Look for EQ (0x14) within next 4 bytes
      const next = code.slice(i+10, i+30);
      const eqPos = next.indexOf('14');
      if (eqPos !== -1 && eqPos < 10) {
        // Look for PUSH2 (0x61) + JUMPI (0x57) pattern after EQ
        const afterEq = code.slice(i+10+eqPos+2, i+10+eqPos+30);
        if (afterEq.startsWith('61') || afterEq.startsWith('62')) {
          const destLen = afterEq.startsWith('61') ? 4 : 6;
          const dest = parseInt(afterEq.slice(2, 2+destLen), 16);
          dispatch.push({ sel, dest, offset: i/2 });
        }
      }
    }
  }

  console.log('Dispatch table entries:', dispatch.length);
  dispatch.forEach(d => console.log(`  ${d.sel} → jump 0x${d.dest.toString(16)} (offset ${d.offset})`));

  // Save full bytecode to file for offline analysis
  const fs = require('fs');
  fs.writeFileSync('c:\\DELETEBOT\\MONAD\\NADFUN\\impl_bytecode.hex', code);
  console.log('\nBytecode saved to impl_bytecode.hex');

  // Now brute-force probe ALL unknown selectors with various arg patterns
  console.log('\n=== BRUTE FORCE SELECTOR PROBING ===\n');

  const unknownSels = [
    '0xd0d65411', '0xd99e1a48', '0x9fda24a4', '0x47f0e29b',
    '0x278d1a3e', '0x32a73b58', '0x1b31abda', '0x02153e29',
    '0x03c068b8', '0x0c4c8d89', '0x14346d07', '0x565b3480',
    '0x0813eb43', '0x014f6fe5', '0x04a4fb41', '0x26052d97',
    '0x37d7bbf5', '0x038f9ba5', '0x1e9acf17', '0x877c74cb',
    '0x91268860', '0x3ffe5d2d', '0x7d4e2731', '0xf097ad14',
    '0x7484bb57', '0x21eed1cd', '0xf7c071fd', '0x1afcd79f',
    '0x6b60901b'
  ];

  // Test arg combinations
  const testArgs = [
    ['no-args', ''],
    ['uint256(0)', pad32uint(0)],
    ['uint256(1)', pad32uint(1)],
    ['uint256(519686)', pad32uint(519686)], // recent game
    ['address(proxy)', pad32addr(PROXY)],
    ['bool(true)', pad32uint(1)],
    // payable test args - uint+uint
    ['(uint,uint)', pad32uint(1) + pad32uint(100)],
    // (address, uint)
    ['(addr,uint)', pad32addr(PROXY) + pad32uint(1)],
  ];

  for (const sel of unknownSels) {
    let found = false;
    for (const [label, args] of testArgs) {
      const r = await ethCall(sel, args);
      if (r.result && r.result !== '0x' && r.result !== '0x' + '0'.repeat(64)) {
        console.log(`${sel}(${label}): ${r.result.slice(0,128)}`);
        found = true;
        break;
      } else if (r.error && !['execution reverted', 'invalid opcode'].includes(r.error.message)) {
        console.log(`${sel}(${label}): ERROR=${r.error.message}`);
        found = true;
        break;
      }
    }
    if (!found) {
      // Try a payable call (with value)
      const r = await rpc('eth_call', [{ to: PROXY, data: sel, value: '0x1' }, 'latest']);
      if (r.result && r.result !== '0x') {
        console.log(`${sel}(payable+noargs): ${r.result.slice(0,128)}`);
      }
    }
  }

  // Check game struct for recent high game IDs more carefully
  console.log('\n=== RECENT GAME DETAILS ===\n');
  const gameIds = [519686, 519685, 519684, 519683, 519682, 519681, 519680, 519679, 519678];
  for (const gid of gameIds) {
    const r = await ethCall('0x1b31abda', pad32uint(gid));
    if (r.result && r.result !== '0x') {
      const hex = r.result.slice(2);
      const player = '0x' + hex.slice(24, 64);
      const status = parseInt(hex.slice(64, 128), 16);
      const h1 = hex.slice(128, 192);
      const h2 = hex.slice(192, 256);
      if (player !== '0x'.padEnd(42, '0')) {
        console.log(`game[${gid}]: player=${player} status=${status}`);
        console.log(`  h1=0x${h1}`);
        console.log(`  h2=0x${h2}`);
      }
    }
  }

  // Check if there's a bet amount stored per game - look at game struct more carefully
  // Perhaps the struct is larger than 4 fields
  console.log('\n=== EXTENDED GAME STRUCT ===\n');
  const r = await ethCall('0x1b31abda', pad32uint(519684));
  console.log('Full game[519684] response:', r.result);
  console.log('Length:', r.result ? r.result.length : 0, 'chars =', r.result ? (r.result.length-2)/64 : 0, 'words');
}

main().catch(console.error);
