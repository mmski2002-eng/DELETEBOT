const https = require('https');

const RPC = 'https://rpc.monad.xyz';
const PROXY = '0xDF7A89Fc62e5120C4617f143C7AcDDAB0D1Ca7A2';
const IMPL = '0x5e3c429f1ea90f06bae5c6de46eef94fd2cdfbc4';
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

// Known 4byte selectors
const KNOWN = {
  '0x8da5cb5b': 'owner()',
  '0xf2fde38b': 'transferOwnership(address)',
  '0x715018a6': 'renounceOwnership()',
  '0xf92ee8a9': 'initialize()',
  '0x1e4fbdf7': 'setBool / unknown',
  '0x4e487b71': 'Panic(uint256) [internal]',
  '0x278d1a3e': 'unknown',
  '0x52d1902d': 'proxiableUUID()',
  '0x4f1ef286': 'upgradeToAndCall(address,bytes)',
  '0x3659cfe6': 'upgradeTo(address)',
  '0x02153e29': 'unknown',
  '0x91da2b3d': 'unknown',
  '0x9fda24a4': 'unknown',
  '0x70480275': 'unknown',
  '0x744bfe61': 'unknown',
  '0x7bfe7a43': 'unknown',
  '0x6e2d05a5': 'unknown',
  '0xd0d65411': 'unknown',
  '0xd99e1a48': 'unknown',
  '0xf62d1888': 'unknown',
};

async function callView(selector, target=PROXY) {
  const res = await rpc('eth_call', [{ to: target, data: selector }, 'latest']);
  return res.result;
}

async function main() {
  console.log('=== BRO.FUN DEEP RECON ===\n');

  // 1. Call known view functions
  console.log('--- View function calls ---');

  // owner()
  try {
    const owner = await callView('0x8da5cb5b');
    console.log('owner():', owner ? '0x' + owner.slice(26) : 'null');
  } catch(e) { console.log('owner(): ERROR', e.message); }

  // initialize() - check if callable (no-auth)
  try {
    const init = await rpc('eth_call', [{ to: PROXY, data: '0xf92ee8a9' }, 'latest']);
    console.log('initialize() call result:', init.result, init.error?.message);
  } catch(e) {}

  // proxiableUUID()
  try {
    const uuid = await callView('0x52d1902d');
    console.log('proxiableUUID():', uuid);
  } catch(e) {}

  // 2. Try to read custom storage slots for game state
  console.log('\n--- Storage slots ---');
  const slots = [
    ['slot 0', '0x0000000000000000000000000000000000000000000000000000000000000000'],
    ['slot 1', '0x0000000000000000000000000000000000000000000000000000000000000001'],
    ['slot 2', '0x0000000000000000000000000000000000000000000000000000000000000002'],
    ['slot 3', '0x0000000000000000000000000000000000000000000000000000000000000003'],
    ['slot 4', '0x0000000000000000000000000000000000000000000000000000000000000004'],
    ['slot 5', '0x0000000000000000000000000000000000000000000000000000000000000005'],
    ['paused flag', '0x0000000000000000000000000000000000000000000000000000000000000010'],
  ];
  for (const [name, slot] of slots) {
    const r = await rpc('eth_getStorageAt', [PROXY, slot, 'latest']);
    if (r.result !== '0x0000000000000000000000000000000000000000000000000000000000000000') {
      console.log(`${name}: ${r.result}`);
    }
  }

  // 3. Get transactions to proxy via trace_filter (if available)
  console.log('\n--- Recent TX to proxy ---');
  const blockRes = await rpc('eth_blockNumber', []);
  const currentBlock = parseInt(blockRes.result, 16);
  console.log('Current block:', currentBlock);

  // Try wider log range - 50000 blocks
  const fromBlock = '0x' + Math.max(0, currentBlock - 50000).toString(16);
  const logsWide = await rpc('eth_getLogs', [{
    address: PROXY,
    fromBlock,
    toBlock: 'latest'
  }]);
  const logs = logsWide.result || [];
  console.log(`Logs (last 50k blocks): ${logs.length}`);
  if (logs.length > 0) {
    const topics = new Set();
    logs.forEach(l => { if (l.topics[0]) topics.add(l.topics[0]); });
    console.log('Event topics:');
    topics.forEach(t => console.log(' ', t));
    logs.slice(0,5).forEach(l => console.log(JSON.stringify(l)));
  }

  // 4. Get impl code and print full hex for selector extraction
  const codeRes = await rpc('eth_getCode', [IMPL, 'latest'], 99);
  const code = codeRes.result.slice(2); // remove 0x

  // Extract PUSH4 selectors properly (must be followed by typical dispatch pattern)
  const realSels = new Set();
  for (let i = 0; i < code.length - 10; i += 2) {
    const byte = code.slice(i, i+2);
    if (byte === '63') {
      const sel = code.slice(i+2, i+10);
      // Skip ASCII-like strings (common string bytes)
      const b0 = parseInt(sel.slice(0,2), 16);
      const b1 = parseInt(sel.slice(2,4), 16);
      // Function selectors rarely start with 0x60-0x7f range for all bytes
      realSels.add('0x' + sel);
    }
  }

  console.log('\n--- All PUSH4 values in impl ---');
  console.log([...realSels].join('\n'));

  // 5. Check if admin has any recent activity
  console.log('\n--- Admin account info ---');
  const adminBal = await rpc('eth_getBalance', [ADMIN, 'latest']);
  const adminNonce = await rpc('eth_getTransactionCount', [ADMIN, 'latest']);
  console.log('Admin balance:', Number(BigInt(adminBal.result)) / 1e18, 'MON');
  console.log('Admin nonce:', parseInt(adminNonce.result, 16));

  // 6. Try calling unknown selectors to see what they return
  console.log('\n--- Unknown selector probing ---');
  const testSels = [
    '0xd0d65411', '0xd99e1a48', '0xf62d1888', '0x91da2b3d', '0x9fda24a4',
    '0x70480275', '0x744bfe61', '0x7bfe7a43', '0x6e2d05a5', '0x39cff220',
    '0x47f0e29b', '0x1785f53c', '0x278d1a3e', '0x2e0be39a', '0x32a73b58',
    '0x3893c500', '0x1b31abda', '0x24d7806c', '0x02153e29', '0x03c068b8',
    '0x0a959f20', '0x0c4c8d89', '0x117a5b90', '0x14346d07'
  ];
  for (const sel of testSels) {
    const r = await rpc('eth_call', [{ to: PROXY, data: sel }, 'latest']);
    if (r.result && r.result !== '0x' && r.result !== '0x0000000000000000000000000000000000000000000000000000000000000000') {
      console.log(`${sel}: ${r.result.slice(0,130)}`);
    } else if (r.error) {
      console.log(`${sel}: REVERT - ${r.error.message || r.error.data}`);
    } else {
      console.log(`${sel}: ${r.result}`);
    }
  }
}

main().catch(console.error);
