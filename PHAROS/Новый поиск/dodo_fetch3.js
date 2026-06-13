const https = require('https');

function rpcCall(method, params) {
  const d = JSON.stringify({ jsonrpc: '2.0', method, params, id: Math.floor(Math.random()*100000) });
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

async function getTxnsInBlock(blockNum) {
  const r = await rpcCall('eth_getBlockByNumber', ['0x' + blockNum.toString(16), true]);
  if (!r.result) return [];
  const txs = r.result.transactions || [];
  return txs.filter(tx => tx.to && tx.to.toLowerCase() === '0xa5ca5fbe34e444f366b373170541ec6902b0f75c'.toLowerCase());
}

async function getTxAndReceipt(txHash) {
  const [tx, rcpt] = await Promise.all([
    rpcCall('eth_getTransactionByHash', [txHash]),
    rpcCall('eth_getTransactionReceipt', [txHash])
  ]);
  return { tx: tx.result, rcpt: rcpt.result };
}

async function main() {
  // First, let's use the known explorer API to find all DODO txs
  const socialScanTxs = [];
  
  // Try to get txs via explorer API
  const { execSync } = require('child_process');
  try {
    // Use curl to get recent transactions to DODO contract
    const result = execSync(
      'curl -s "https://api.socialscan.io/pharos-mainnet/v1/addresses/0xa5ca5fbe34e444f366b373170541ec6902b0f75c/transactions?limit=20" 2>nul',
      { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 }
    );
    console.log('Explorer response:', result.slice(0, 500));
    if (result) {
      const data = JSON.parse(result);
      if (data.items) {
        for (const item of data.items) {
          socialScanTxs.push(item.hash || item.transactionHash);
        }
      }
    }
  } catch(e) {
    console.log('Explorer API error:', e.message);
  }
  
  // Known sample txs
  const knownTxs = [
    '0xdbe7b075e43bc11eafb89c2778858ddfcf7d7c3b832f4e92e1dabbc101b5ef98',
    '0x3de490eec96536f9f1cdcf59ccca1914413fa00b0350eb6741a3443bc14b327f'
  ];
  
  // Scan recent blocks for DODO txs
  const curBn = await rpcCall('eth_blockNumber', []);
  const cur = parseInt(curBn.result, 16);
  console.log('Current block:', cur);
  
  const foundHashes = new Set(knownTxs);
  const allHashes = [...knownTxs];
  
  // Scan blocks backward
  for (let b = cur; b > cur - 500 && allHashes.length < 20; b--) {
    const txs = await getTxnsInBlock(b);
    for (const tx of txs) {
      if (!foundHashes.has(tx.hash) && tx.input && tx.input.startsWith('0xff84aafa')) {
        foundHashes.add(tx.hash);
        allHashes.push(tx.hash);
      }
    }
    if (txs.length > 0) console.log(`Block ${b}: ${txs.length} DODO txs`);
    await new Promise(r => setTimeout(r, 50));
  }
  
  // Also scan for non-mixSwap txs
  for (let b = cur; b > cur - 1000 && allHashes.length < 25; b--) {
    const txs = await getTxnsInBlock(b);
    for (const tx of txs) {
      if (!foundHashes.has(tx.hash) && tx.input && !tx.input.startsWith('0xff84aafa')) {
        foundHashes.add(tx.hash);
        allHashes.push(tx.hash);
      }
    }
    await new Promise(r => setTimeout(r, 30));
  }
  
  console.log(`\nTotal unique DODO txs found: ${allHashes.length}`);
  
  // Classify all
  const results = [];
  for (const txh of allHashes.slice(0, 20)) {
    const { tx, rcpt } = await getTxAndReceipt(txh);
    if (!rcpt) continue;
    
    const status = rcpt.status === '0x1' ? 'success' : rcpt.status === '0x0' ? 'failed' : 'unknown';
    const input = tx.input || '';
    const from = tx.from || '';
    const value = parseInt(tx.value || '0', 16);
    const block = parseInt(tx.blockNumber || '0', 16);
    const blockTimestamp = rcpt.logs?.[0]?.blockTimestamp ? parseInt(rcpt.logs[0].blockTimestamp, 16) : null;
    
    const selector = input.slice(0, 10);
    let method = selector;
    if (selector === '0xff84aafa') method = 'mixSwap';
    else if (selector === '0xbc74f9ff') method = 'externalSwap';
    else if (selector === '0xb1dc7df9') method = 'dodoMutliSwap';
    
    const orderHistoryLog = rcpt.logs?.find(l => 
      l.address.toLowerCase() === '0xa5ca5fbe34e444f366b373170541ec6902b0f75c'.toLowerCase() &&
      l.topics[0] === '0x92ceb067a9883c85aba061e46b9edf505a0d6e81927c4b966ebed543a5221787'
    );
    
    const positiveSlippageLog = rcpt.logs?.find(l =>
      l.address.toLowerCase() === '0xa5ca5fbe34e444f366b373170541ec6902b0f75c'.toLowerCase() &&
      l.topics[0] === '0xd820290de56f193465e6c0b6140e6bedce58ba0d54229b2a57fd4b60d285297c'
    );
    
    results.push({
      hash: txh,
      block,
      blockTimestamp,
      status,
      from,
      method,
      value,
      gasUsed: parseInt(rcpt.gasUsed || '0', 16),
      logCount: rcpt.logs?.length || 0,
      hasOH: !!orderHistoryLog,
      hasPS: !!positiveSlippageLog,
      ohData: orderHistoryLog?.data,
      psData: positiveSlippageLog?.data,
      input
    });
  }
  
  // Print summary
  console.log('\n=== ALL DODO TRANSACTIONS ===');
  for (const r of results) {
    console.log(`\nTx: ${r.hash}`);
    console.log(`  Block: ${r.block}  TS: ${r.blockTimestamp}  Status: ${r.status}`);
    console.log(`  Method: ${r.method}  From: ${r.from}`);
    console.log(`  Value: ${r.value}  Gas: ${r.gasUsed}  Logs: ${r.logCount}`);
    console.log(`  OrderHistory: ${r.hasOH}  PositiveSlippage: ${r.hasPS}`);
    if (r.hasOH) console.log(`  OH data: ${r.ohData}`);
    if (r.hasPS) console.log(`  PS data: ${r.psData}`);
  }
}

main().catch(e => { console.error('FATAL:', e.message); console.error(e.stack); });