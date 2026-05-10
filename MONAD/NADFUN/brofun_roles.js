const https = require('https');
const crypto = require('crypto');

const RPC = 'https://rpc.monad.xyz';
const PROXY = '0xDF7A89Fc62e5120C4617f143C7AcDDAB0D1Ca7A2';
const OWNER = '0x91d6ddd506a952bb8ccefe0cf3609ebde8c8524d';
const ADMIN = '0x4a03ab0327cef024f6d06ed6ed600f6c911c811f';

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

function keccak256(str) {
  // Use Node crypto for keccak - but node doesn't have keccak natively
  // We'll compute manually via known values or use the ethers approach
  // Actually we need keccak256 - let's use a simple implementation
  return null; // placeholder
}

function fetch4byte(selector) {
  return new Promise((res) => {
    const url = `https://www.4byte.directory/api/v1/signatures/?hex_signature=${selector}`;
    const req = https.get(url, {
      headers: { 'User-Agent': 'Mozilla/5.0' }
    }, (r) => {
      let data = '';
      r.on('data', c => data += c);
      r.on('end', () => {
        try {
          const j = JSON.parse(data);
          const results = j.results || [];
          res(results.map(r => r.text_signature));
        } catch(e) { res([]); }
      });
    });
    req.on('error', () => res([]));
  });
}

async function call(selector, args='', target=PROXY) {
  const r = await rpc('eth_call', [{ to: target, data: selector + args }, 'latest']);
  return r;
}

async function main() {
  console.log('=== ROLE & SELECTOR ANALYSIS ===\n');

  // 1. Known AccessControl selectors
  console.log('--- AccessControl checks ---');

  // hasRole(bytes32,address) = 0x91d1c2e9
  // Check if owner has DEFAULT_ADMIN_ROLE (0x00...00)
  const defaultAdminRole = '0000000000000000000000000000000000000000000000000000000000000000';
  const ownerPadded = '000000000000000000000000' + OWNER.slice(2);

  const hasRoleOwner = await call('0x91d1c2e9', defaultAdminRole + ownerPadded);
  console.log('hasRole(DEFAULT_ADMIN, owner):', hasRoleOwner.result);

  const adminPadded = '000000000000000000000000' + ADMIN.slice(2);
  const hasRoleAdmin = await call('0x91d1c2e9', defaultAdminRole + adminPadded);
  console.log('hasRole(DEFAULT_ADMIN, admin):', hasRoleAdmin.result);

  // getRoleAdmin(bytes32) = 0x248a9ca3
  const roleAdmin = await call('0x248a9ca3', defaultAdminRole);
  console.log('getRoleAdmin(DEFAULT_ADMIN):', roleAdmin.result);

  // 2. Look up selectors via 4byte.directory
  console.log('\n--- 4byte selector lookup ---');
  const sels = [
    '0xd0d65411', '0xd99e1a48', '0xf62d1888', '0x91da2b3d', '0x9fda24a4',
    '0x70480275', '0x744bfe61', '0x7bfe7a43', '0x6e2d05a5', '0x1785f53c',
    '0x278d1a3e', '0x2e0be39a', '0x32a73b58', '0x3893c500', '0x1b31abda',
    '0x24d7806c', '0x02153e29', '0x03c068b8', '0x0a959f20', '0x0c4c8d89',
    '0x117a5b90', '0x14346d07', '0x565b3480', '0x0819bdcd', '0x0813eb43',
    '0x014f6fe5', '0x04a4fb41', '0x26052d97', '0x37d7bbf5', '0x038f9ba5',
    '0x1e9acf17', '0x877c74cb', '0x91268860', '0x3ffe5d2d', '0xea8e4eb5',
    '0x7d4e2731', '0xf097ad14', '0x39cff220', '0x47f0e29b', '0x6e2d05a5',
    '0x21eed1cd', '0x118cdaa7', '0xf7c071fd', '0x3ee5aeb5', '0x1afcd79f',
    '0x7484bb57', '0x1e4fbdf7', '0x6b60901b', '0x4e487b71'
  ];

  for (const sel of sels) {
    const matches = await fetch4byte(sel);
    if (matches.length > 0) {
      console.log(`${sel}: ${matches.join(' | ')}`);
    }
  }

  // 3. Check recent transactions TO proxy address via block scanning
  console.log('\n--- Block range transaction scan ---');
  const blockRes = await rpc('eth_blockNumber', []);
  const current = parseInt(blockRes.result, 16);
  console.log('Current block:', current);

  // Try getting a specific transaction to understand contract interaction
  // Get a block and check if any tx goes to proxy
  const scanBlocks = [current, current-1, current-2, current-10, current-100];
  for (const bn of scanBlocks) {
    const block = await rpc('eth_getBlockByNumber', ['0x' + bn.toString(16), true]);
    const txs = (block.result?.transactions || []).filter(tx =>
      tx.to && tx.to.toLowerCase() === PROXY.toLowerCase()
    );
    if (txs.length > 0) {
      console.log(`Block ${bn}: ${txs.length} tx to proxy`);
      txs.forEach(tx => console.log('  TX:', tx.hash, 'data:', tx.input.slice(0,10)));
    }
  }

  // 4. Try calling with uint256 argument (e.g., gameId=1)
  console.log('\n--- Selector probe with args ---');
  const arg1 = '0000000000000000000000000000000000000000000000000000000000000001';
  const arg0 = '0000000000000000000000000000000000000000000000000000000000000000';

  const toProbe = [
    '0xd0d65411', '0xd99e1a48', '0xf62d1888', '0x9fda24a4',
    '0x70480275', '0x744bfe61', '0x47f0e29b', '0x1785f53c',
    '0x278d1a3e', '0x32a73b58', '0x1b31abda', '0x24d7806c',
    '0x02153e29', '0x03c068b8', '0x0c4c8d89', '0x117a5b90', '0x14346d07'
  ];

  for (const sel of toProbe) {
    const r = await call(sel, arg1);
    if (r.result && r.result !== '0x') {
      console.log(`${sel}(1): ${r.result.slice(0,130)}`);
    } else if (r.error?.message !== 'execution reverted') {
      console.log(`${sel}(1): ERROR - ${r.error?.message}`);
    }
  }

  // 5. Check total supply / game pool values
  console.log('\n--- Game state ---');
  // totalSupply() = 0x18160ddd
  const ts = await call('0x18160ddd');
  console.log('totalSupply():', ts.result);

  // paused() = 0x5c975abb
  const paused = await call('0x5c975abb');
  console.log('paused():', paused.result);

  // balanceOf(owner) = 0x70a08231
  const balOf = await call('0x70a08231', ownerPadded);
  console.log('balanceOf(owner):', balOf.result);

  // 6. Try role-protected functions with address args
  console.log('\n--- Role assignments for key addresses ---');
  // Known role hashes returned by contract
  const roleHashes = [
    '7ba92e458574d93459ebcfd4a171eeed4c4184fc5272ec464f39b835ea16f452', // 0x7bfe7a43
    '9027f60b1b6eda53f7456933f9e037819687f28a1f333810b9adb7db5ec490ae', // 0x6e2d05a5
    '8dd6bf3357a5e82210d278eec1b32777746ceabc18c6f34c3c44ad66886da60c', // 0x39cff220
    'fb05764e625a4f2e11e8bfe93ed4e09504fcfc3f50277804700c5765ddf65ed8', // 0x3893c500
    '91f534f679b058b9205d339923a0a14a68c0ec2da059808b66b647613d364885', // 0x0a959f20
  ];

  for (const roleHash of roleHashes) {
    for (const [name, addr] of [['owner', OWNER], ['admin', ADMIN]]) {
      const addrPadded = '000000000000000000000000' + addr.slice(2);
      const r = await call('0x91d1c2e9', roleHash + addrPadded);
      if (r.result === '0x0000000000000000000000000000000000000000000000000000000000000001') {
        console.log(`Role 0x${roleHash.slice(0,8)}... → ${name} (${addr})`);
      }
    }
  }
}

main().catch(console.error);
