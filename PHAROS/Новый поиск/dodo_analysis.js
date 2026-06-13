const https = require('https');

function rpcCall(method, params) {
  const d = JSON.stringify({ jsonrpc: '2.0', method, params, id: 1 });
  return new Promise((resolve, reject) => {
    const req = https.request('https://rpc.pharos.xyz', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, res => {
      let body = '';
      res.on('data', c => body += c);
      res.on('end', () => {
        try { resolve(JSON.parse(body)); } catch(e) { reject(e); }
      });
    });
    req.on('error', reject);
    req.write(d);
    req.end();
  });
}

async function main() {
  const DODO = '0xa5ca5fbe34e444f366b373170541ec6902b0f75c';
  const WPROS = '0x52c48d4213107b20bc583832b0d951fb9ca8f0b0';
  const DODO_APPROVE = '0x2afc65289c3c285b2c060a2971e5afbbad81f12a';
  
  console.log('=== PHASE 1: CONTRACT BASELINE ===');
  
  // Read storage slots - DODO proxy
  // Slot for owner: typically _OWNER_ slot in DODO is 0x0 or standard Ownable
  // Slot for _WETH_: looking at DODO source patterns, usually a public variable
  // Slot for routeFeeRate: need to check layout
  // Slot for routeFeeReceiver: after feeRate
  
  // Let's read common predictable slots + try getStorageAt on known key slots
  const storageSlots = [
    '0x0',  // Often owner or implementation in proxies
    '0x1',  // Next 
    '0x2',
    '0x3',
    '0x4',
    '0x5',
    '0x6',
    '0x7',
    '0x8',
    '0x9',
  ];
  
  console.log('Storage reads for DODO proxy:');
  for (const slot of storageSlots) {
    const r = await rpcCall('eth_getStorageAt', [DODO, slot, '0x6decec']); // Use known block
    const val = r.result;
    if (val && val !== '0x0000000000000000000000000000000000000000000000000000000000000000') {
      console.log(`  Slot ${slot}: ${val}`);
    }
  }
  
  // Read via eth_call - try public view functions
  console.log('\nPublic reads via eth_call:');
  
  // routeFeeRate() call - signature: 0x1c4f09f6
  try {
    const r1 = await rpcCall('eth_call', [{ to: DODO, data: '0x1c4f09f6' }, '0x6decec']);
    if (r1.result) console.log('  routeFeeRate():', r1.result, '=', parseInt(r1.result, 16));
  } catch(e) {}
  
  // routeFeeReceiver() - signature: 0x0a0d1c3a  
  try {
    const r2 = await rpcCall('eth_call', [{ to: DODO, data: '0x0a0d1c3a' }, '0x6decec']);
    if (r2.result) console.log('  routeFeeReceiver():', r2.result);
  } catch(e) {}
  
  // _WETH_() - signature: 0xe64b334b
  try {
    const r3 = await rpcCall('eth_call', [{ to: DODO, data: '0xe64b334b' }, '0x6decec']);
    if (r3.result) console.log('  _WETH_():', r3.result);
  } catch(e) {}
  
  // _DODO_APPROVE_PROXY_() - signature: 0xc2649e63
  try {
    const r4 = await rpcCall('eth_call', [{ to: DODO, data: '0xc2649e63' }, '0x6decec']);
    if (r4.result) console.log('  _DODO_APPROVE_PROXY_():', r4.result);
  } catch(e) {}
  
  // totalWeight() - need signature guess... let's try common ones
  // isWhiteListedContract(address) - signature: 0x9a32bb66
  // Let's check if adapter 0x4fd44181839d24e7c8f4d1b9288379109ec25fae is whitelisted
  try {
    const r5 = await rpcCall('eth_call', [{ to: DODO, data: '0x9a32bb660000000000000000000000004fd44181839d24e7c8f4d1b9288379109ec25fae' }, '0x6decec']);
    if (r5.result) console.log('  isWhiteListed(adapter):', r5.result);
  } catch(e) {}

  // isApproveWhiteListedContract - signature: guess 0x0e6f6468 or similar
  // owner() - signature: 0x8da5cb5b
  try {
    const r6 = await rpcCall('eth_call', [{ to: DODO, data: '0x8da5cb5b' }, '0x6decec']);
    if (r6.result) console.log('  owner():', r6.result);
  } catch(e) {}
  
  // Let me now get the full bytecode to understand proxy pattern
  const code = await rpcCall('eth_getCode', [DODO, '0x6decec']);
  console.log('\nBytecode length:', code.result ? code.result.length - 2 : 0, 'bytes');
  console.log('First 200 chars:', code.result ? code.result.slice(0, 200) : 'N/A');
  
  // Check if there's an implementation slot
  // EIP-1967: 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
  const implSlot = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc';
  const implR = await rpcCall('eth_getStorageAt', [DODO, implSlot, '0x6decec']);
  console.log('EIP-1967 implementation slot:', implR.result);

  console.log('\n=== PHASE 2: TRANSACTION DISCOVERY ===');
  
  // We have 2 known txs. Let's find 3 more diverse ones.
  // Check blocks around 0x6decec (7204588) and 0x6dea8a (7203466)
  // Look for txns where DODO proxy emitted OrderHistory
  
  const allTxs = [
    { hash: '0xdbe7b075e43bc11eafb89c2778858ddfcf7d7c3b832f4e92e1dabbc101b5ef98', note: 'Known: native PROS->USDC, mixSwap' },
    { hash: '0x3de490eec96536f9f1cdcf59ccca1914413fa00b0350eb6741a3443bc14b327f', note: 'Known: native PROS->USDC, mixSwap' }
  ];
  
  // Search for OrderHistory in blocks around 7204588 +/- 200
  const knownBlock = 7204588;
  for (let blockRange of [
    [knownBlock - 5, knownBlock + 5],
    [7203466 - 5, 7203466 + 5],
    [7204898 - 50, 7204898]  // recent
  ]) {
    for (let b = blockRange[0]; b <= blockRange[1]; b++) {
      const block = await rpcCall('eth_getBlockByNumber', ['0x' + b.toString(16), true]);
      if (!block.result) continue;
      const txs = (block.result.transactions || []).filter(tx => 
        tx.to && tx.to.toLowerCase() === DODO.toLowerCase()
      );
      for (const tx of txs) {
        if (!allTxs.find(t => t.hash === tx.hash)) {
          allTxs.push({ hash: tx.hash, note: `Block ${b}, ${tx.input.slice(0,10)}` });
        }
      }
    }
    await new Promise(r => setTimeout(r, 100));
  }
  
  console.log(`\nTotal candidate txs: ${allTxs.length}`);
  
  // Fetch all receipts
  const results = [];
  for (let i = 0; i < allTxs.length; i++) {
    const tx = allTxs[i];
    const [txData, rcptData] = await Promise.all([
      rpcCall('eth_getTransactionByHash', [tx.hash]),
      rpcCall('eth_getTransactionReceipt', [tx.hash])
    ]);
    const td = txData.result;
    const rd = rcptData.result;
    if (!rd) continue;
    
    const status = rd.status === '0x1' ? 'SUCCESS' : 'FAILED';
    const input = td.input || '';
    const from = td.from || '';
    const value = parseInt(td.value || '0', 16);
    const block = parseInt(td.blockNumber || '0', 16);
    const blockTS = rd.logs?.[0]?.blockTimestamp ? parseInt(rd.logs[0].blockTimestamp, 16) : null;
    
    const selector = input.slice(0, 10);
    let method = selector;
    if (selector === '0xff84aafa') method = 'mixSwap';
    else if (selector === '0xbc74f9ff') method = 'externalSwap';
    else if (selector === '0xb1dc7df9') method = 'dodoMutliSwap';
    
    const ohLog = rd.logs?.find(l => 
      l.address.toLowerCase() === DODO.toLowerCase() &&
      l.topics[0] === '0x92ceb067a9883c85aba061e46b9edf505a0d6e81927c4b966ebed543a5221787'
    );
    
    const psLog = rd.logs?.find(l =>
      l.address.toLowerCase() === DODO.toLowerCase() &&
      l.topics[0] === '0xd820290de56f193465e6c0b6140e6bedce58ba0d54229b2a57fd4b60d285297c'
    );
    
    // Parse OrderHistory data
    let ohFromToken = '', ohToToken = '', ohSender = '', ohFromAmount = '', ohReturnAmount = '';
    if (ohLog) {
      ohFromToken = '0x' + ohLog.data.slice(24, 64);
      ohToToken = '0x' + ohLog.data.slice(88, 128);
      ohSender = '0x' + ohLog.data.slice(152, 192);
      ohFromAmount = BigInt('0x' + ohLog.data.slice(192, 256));
      ohReturnAmount = BigInt('0x' + ohLog.data.slice(256, 320));
    }
    
    // Parse token transfers
    const transfers = [];
    for (const log of rd.logs || []) {
      if (log.topics.length === 3 && 
          (log.topics[0] === '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef' ||
           log.topics[0] === '0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c')) {
        const token = log.address;
        const fromAddr = '0x' + log.topics[1].slice(26);
        const toAddr = '0x' + log.topics[2].slice(26);
        const amount = BigInt('0x' + log.data.slice(0, 66));
        transfers.push({ token, from: fromAddr, to: toAddr, amount, isDeposit: log.topics[0] === '0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c' });
      }
    }
    
    results.push({
      hash: tx.hash,
      block,
      blockTS,
      status,
      from,
      method,
      value,
      gasUsed: parseInt(rd.gasUsed || '0', 16),
      logCount: rd.logs?.length || 0,
      hasOH: !!ohLog,
      hasPS: !!psLog,
      ohFromToken,
      ohToToken,
      ohSender,
      ohFromAmount,
      ohReturnAmount,
      psToken: psLog ? '0x' + psLog.data.slice(24, 64) : '',
      psAmount: psLog ? parseInt(psLog.data.slice(64, 128), 16) : 0,
      transfers,
      input
    });
  }
  
  console.log('\n=== TRANSACTION SUMMARY ===');
  for (const r of results) {
    console.log(`\nTx: ${r.hash}`);
    console.log(`  Block: ${r.block} TS: ${r.blockTS} Status: ${r.status}`);
    console.log(`  Method: ${r.method} From: ${r.from}`);
    console.log(`  Value: ${r.value} (${(r.value/1e18).toFixed(4)} PROS)`);
    console.log(`  Gas: ${r.gasUsed} Logs: ${r.logCount}`);
    console.log(`  OrderHistory: ${r.hasOH}`);
    console.log(`    fromToken: ${r.ohFromToken}`);
    console.log(`    toToken: ${r.ohToToken}`);
    console.log(`    sender: ${r.ohSender}`);
    console.log(`    fromAmount: ${r.ohFromAmount}`);
    console.log(`    returnAmount: ${r.ohReturnAmount}`);
    console.log(`  PositiveSlippage: ${r.hasPS} token=${r.psToken} amount=${r.psAmount}`);
    console.log(`  Transfers:`);
    for (const t of r.transfers) {
      console.log(`    ${t.isDeposit?'DEPOSIT':'XFER'} ${t.token.slice(0,10)} ${t.from.slice(0,10)} -> ${t.to.slice(0,10)} ${t.amount}`);
    }
  }
}

main().catch(e => { console.error(e); });