const https = require('https');

const RPC = 'https://rpc.monad.xyz';
const PROXY = '0xDF7A89Fc62e5120C4617f143C7AcDDAB0D1Ca7A2';
const IMPL = '0x5e3c429f1ea90f06bae5c6de46eef94fd2cdfbc4';

function rpc(method, params, id=1) {
  return new Promise((res, rej) => {
    const body = JSON.stringify({ jsonrpc:'2.0', method, params, id });
    const req = https.request(RPC, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) }
    }, (r) => {
      let data = '';
      r.on('data', c => data += c);
      r.on('end', () => res(JSON.parse(data)));
    });
    req.on('error', rej);
    req.write(body);
    req.end();
  });
}

function extractSelectors(bytecode) {
  const hex = bytecode.slice(2);
  const selectors = new Set();
  // PUSH4 opcode = 0x63
  for (let i = 0; i < hex.length - 10; i += 2) {
    if (hex[i] === '6' && hex[i+1] === '3') {
      const sel = '0x' + hex.slice(i+2, i+10);
      selectors.add(sel);
    }
  }
  return [...selectors];
}

async function main() {
  console.log('=== BRO.FUN RECON ===\n');

  // 1. Proxy balance
  const balRes = await rpc('eth_getBalance', [PROXY, 'latest']);
  const balWei = BigInt(balRes.result);
  const balMON = Number(balWei) / 1e18;
  console.log(`Proxy balance: ${balMON.toFixed(4)} MON`);

  // 2. Implementation balance
  const implBalRes = await rpc('eth_getBalance', [IMPL, 'latest']);
  console.log(`Impl balance: ${(Number(BigInt(implBalRes.result)) / 1e18).toFixed(4)} MON`);

  // 3. Implementation bytecode + selectors
  const codeRes = await rpc('eth_getCode', [IMPL, 'latest'], 2);
  const code = codeRes.result;
  console.log(`\nImpl bytecode size: ${code.length/2} bytes`);
  const sels = extractSelectors(code);
  console.log(`\nFunction selectors found (${sels.length}):`);
  sels.forEach(s => console.log(' ', s));

  // 4. Admin slot (ERC1967)
  const adminSlot = '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103';
  const adminRes = await rpc('eth_getStorageAt', [PROXY, adminSlot, 'latest'], 3);
  console.log(`\nProxy admin slot: ${adminRes.result}`);

  // 5. Recent block
  const blockRes = await rpc('eth_blockNumber', [], 4);
  const currentBlock = parseInt(blockRes.result, 16);
  console.log(`\nCurrent block: ${currentBlock}`);

  // 6. Recent logs - last 200 blocks
  const fromBlock = '0x' + (currentBlock - 200).toString(16);
  const logsRes = await rpc('eth_getLogs', [{
    address: PROXY,
    fromBlock,
    toBlock: 'latest'
  }], 5);
  const logs = logsRes.result || [];
  console.log(`\nRecent logs (last 200 blocks): ${logs.length}`);
  logs.slice(0, 10).forEach(l => {
    console.log(JSON.stringify({ tx: l.transactionHash, topics: l.topics, data: l.data.slice(0,66) }));
  });

  // 7. Get a recent tx to this contract
  const txRes = await rpc('eth_getLogs', [{
    address: PROXY,
    fromBlock: '0x' + (currentBlock - 5000).toString(16),
    toBlock: 'latest'
  }], 6);
  const allLogs = txRes.result || [];
  console.log(`\nTotal logs (last 5000 blocks): ${allLogs.length}`);

  // Show unique event topics
  const topics = new Set();
  allLogs.forEach(l => { if (l.topics[0]) topics.add(l.topics[0]); });
  console.log('\nUnique event signatures:');
  topics.forEach(t => console.log(' ', t));
}

main().catch(console.error);
