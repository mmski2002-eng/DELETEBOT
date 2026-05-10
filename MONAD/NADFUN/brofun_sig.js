const https = require('https');

const RPC = 'https://rpc.monad.xyz';
const PROXY = '0xDF7A89Fc62e5120C4617f143C7AcDDAB0D1Ca7A2';
const PLAYER1 = '0x5ba865cf3652eba213631d7e0e2d7294bb6be781';

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

function fetch4byte(selector) {
  return new Promise((res) => {
    const req = https.get(`https://www.4byte.directory/api/v1/signatures/?hex_signature=${selector}`, {
      headers: { 'User-Agent': 'Mozilla/5.0' }
    }, (r) => {
      let data = '';
      r.on('data', c => data += c);
      r.on('end', () => { try { res(JSON.parse(data).results?.map(r => r.text_signature) || []); } catch(e) { res([]); } });
    });
    req.on('error', () => res([]));
  });
}

async function ethCall(sel, args='', from=null) {
  const callObj = { to: PROXY, data: sel + args };
  if (from) callObj.from = from;
  return await rpc('eth_call', [callObj, 'latest']);
}

function pad32uint(n) { return n.toString(16).padStart(64, '0'); }
function pad32addr(addr) { return '000000000000000000000000' + addr.slice(2).toLowerCase(); }

async function main() {
  console.log('=== SIGNATURE & GAME FLOW ANALYSIS ===\n');

  // 1. Is PLAYER1 a contract or EOA?
  const code1 = await rpc('eth_getCode', [PLAYER1, 'latest']);
  const bal1 = await rpc('eth_getBalance', [PLAYER1, 'latest']);
  const nonce1 = await rpc('eth_getTransactionCount', [PLAYER1, 'latest']);
  console.log('PLAYER1 is contract:', code1.result !== '0x' && code1.result.length > 4);
  console.log('PLAYER1 balance:', Number(BigInt(bal1.result)) / 1e18, 'MON');
  console.log('PLAYER1 nonce:', parseInt(nonce1.result, 16));
  if (code1.result && code1.result.length > 4) {
    console.log('PLAYER1 code size:', code1.result.length / 2, 'bytes');
  }

  // 2. Decode game struct more carefully
  console.log('\n--- Game struct decode ---');
  for (let i = 1; i <= 15; i++) {
    const r = await ethCall('0x1b31abda', pad32uint(i));
    if (r.result && r.result !== '0x') {
      const hex = r.result.slice(2);
      const player = '0x' + hex.slice(24, 64);
      const status = parseInt(hex.slice(64, 128), 16);
      const hash1 = '0x' + hex.slice(128, 192);
      const hash2 = '0x' + hex.slice(192, 256);
      console.log(`game[${i}]: player=${player} status=${status} h1=${hash1.slice(0,18)}... h2=${hash2.slice(0,18)}...`);
    }
  }

  // 3. gameCounter and recent game IDs
  const gcR = await ethCall('0x2e0be39a');
  const gameCount = parseInt(gcR.result, 16);
  console.log('\ngameCounter:', gameCount);

  console.log('\n--- Recent game IDs ---');
  for (const gid of [gameCount, gameCount-1, gameCount-2, gameCount-5, gameCount-10, gameCount-100, gameCount-1000]) {
    const r = await ethCall('0x1b31abda', pad32uint(gid));
    if (r.result && r.result !== '0x') {
      const hex = r.result.slice(2);
      const player = '0x' + hex.slice(24, 64);
      const status = parseInt(hex.slice(64, 128), 16);
      if (player !== '0x0000000000000000000000000000000000000000') {
        console.log(`game[${gid}]: player=${player} status=${status}`);
      } else {
        console.log(`game[${gid}]: empty`);
      }
    } else {
      console.log(`game[${gid}]: empty/revert`);
    }
  }

  // 4. Look for settle/claim/bet/throw functions via 4byte
  console.log('\n--- 4byte for remaining unknown selectors ---');
  const unknowns = [
    '0xd0d65411', '0xd99e1a48', '0x9fda24a4', '0x47f0e29b',
    '0x278d1a3e', '0x32a73b58', '0x3893c500', '0x02153e29',
    '0x03c068b8', '0x0a959f20', '0x0c4c8d89', '0x14346d07',
    '0x565b3480', '0x0813eb43', '0x014f6fe5', '0x04a4fb41',
    '0x26052d97', '0x37d7bbf5', '0x038f9ba5', '0x1e9acf17',
    '0x877c74cb', '0x91268860', '0x3ffe5d2d', '0x7d4e2731',
    '0xf097ad14', '0x39cff220', '0x21eed1cd', '0xf7c071fd',
    '0x1afcd79f', '0x7484bb57', '0x6b60901b', '0x7bfe7a43',
    '0x6e2d05a5', '0x7484bb57', '0xf62d1888'
  ];
  for (const sel of unknowns) {
    const matches = await fetch4byte(sel);
    if (matches.length > 0) {
      console.log(`${sel}: ${matches.join(' | ')}`);
    }
  }

  // 5. Try probing with (address, uint) args for settle-like functions
  console.log('\n--- settle/claim selector probing ---');
  const gameId1 = pad32uint(1);
  const player1Pad = pad32addr(PLAYER1);

  // Common settle patterns: settleGame(uint256, bool), settleGame(uint256, address, bytes)
  // Try with (gameId, winner=true/false)
  for (const sel of ['0x9fda24a4', '0xd0d65411', '0x32a73b58', '0x03c068b8', '0x14346d07', '0x04a4fb41']) {
    // (uint256, bool=true)
    const r1 = await ethCall(sel, gameId1 + '0000000000000000000000000000000000000000000000000000000000000001');
    // (uint256, bool=false)
    const r2 = await ethCall(sel, gameId1 + '0000000000000000000000000000000000000000000000000000000000000000');
    // (uint256, address)
    const r3 = await ethCall(sel, gameId1 + player1Pad);
    for (const [label, r] of [['(gid,true)', r1], ['(gid,false)', r2], ['(gid,addr)', r3]]) {
      if (r.result && r.result !== '0x' && !r.error) {
        console.log(`${sel}${label}: ${r.result.slice(0,130)}`);
      } else if (r.error && r.error.message !== 'execution reverted') {
        console.log(`${sel}${label}: ${r.error.message}`);
      }
    }
  }

  // 6. Check signer address storage - likely in storage
  console.log('\n--- Signer slot scan ---');
  for (let i = 0; i <= 20; i++) {
    const slot = '0x' + i.toString(16).padStart(64, '0');
    const r = await rpc('eth_getStorageAt', [PROXY, slot, 'latest']);
    const val = r.result;
    if (val !== '0x0000000000000000000000000000000000000000000000000000000000000000') {
      // Check if it looks like an address (20 bytes in upper 12 bytes zero)
      const isAddr = val.slice(2, 26) === '000000000000000000000000';
      const asAddr = '0x' + val.slice(26);
      console.log(`slot[${i}]: ${val}${isAddr ? ` (addr: ${asAddr})` : ''}`);
    }
  }

  // 7. Try calling with signature-like args (bytes)
  console.log('\n--- Signature-based call probing ---');
  // Try common patterns for signed settlement:
  // claim(uint256 gameId, uint256 amount, bytes sig)
  // settle(uint256 gameId, bool win, uint256 expiry, bytes sig)

  // Construct a dummy 65-byte signature
  const dummySig = '41'.repeat(65).padEnd(128, '0'); // r, s, v dummy
  const sigOffset = '0000000000000000000000000000000000000000000000000000000000000060'; // offset to sig
  const sigLen = '0000000000000000000000000000000000000000000000000000000000000041'; // 65 bytes
  const sigData = sigOffset + gameId1 + dummySig;

  for (const sel of ['0x9fda24a4', '0xd0d65411', '0x32a73b58', '0x1b31abda', '0x26052d97', '0x37d7bbf5']) {
    const r = await ethCall(sel, sigData);
    if (r.error && r.error.message !== 'execution reverted') {
      console.log(`${sel} w/sig args: ${r.error.message}`);
    } else if (r.result && r.result !== '0x') {
      console.log(`${sel} w/sig args: ${r.result.slice(0,80)}`);
    }
  }

  // 8. Get transaction that created game #1 - find the tx hash from event or trace
  console.log('\n--- Transaction history check ---');
  // Get PLAYER1 nonce/history
  const p1Nonce = await rpc('eth_getTransactionCount', [PLAYER1, 'latest']);
  console.log('PLAYER1 total txs sent:', parseInt(p1Nonce.result, 16));

  // Check logs from very beginning
  const logsFrom0 = await rpc('eth_getLogs', [{
    address: PROXY,
    fromBlock: '0x0',
    toBlock: '0x100000' // first ~1M blocks
  }]);
  console.log('Logs from genesis to block 1M:', logsFrom0.result?.length ?? logsFrom0.error?.message);
}

main().catch(console.error);
