const https = require('https');

function rpcCall(method, params, id) {
  const d = JSON.stringify({ jsonrpc: '2.0', method, params, id });
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
  // Get current block
  const bn = await rpcCall('eth_blockNumber', [], 0);
  const cur = parseInt(bn.result, 16);
  console.log('Current block:', cur);
  
  // Search OrderHistory in batches of 800 blocks going backward
  const found = new Set();
  const txHashes = [];
  
  for (let end = cur; end > cur - 50000; end -= 800) {
    const from = end - 799;
    if (txHashes.length >= 30) break;
    try {
      const r = await rpcCall('eth_getLogs', [{
        address: '0xa5ca5fbe34e444f366b373170541ec6902b0f75c',
        topics: ['0x92ceb067a9883c85aba061e46b9edf505a0d6e81927c4b966ebed543a5221787'],
        fromBlock: '0x' + from.toString(16),
        toBlock: '0x' + end.toString(16)
      }], id);
      if (r.result && r.result.length > 0) {
        for (const log of r.result) {
          if (!found.has(log.transactionHash)) {
            found.add(log.transactionHash);
            txHashes.push(log.transactionHash);
          }
        }
        console.log(`Blocks ${from}-${end}: found ${r.result.length} logs, total unique: ${txHashes.length}`);
      }
    } catch(e) {
      console.log(`Error at ${from}-${end}:`, e.message);
    }
    await new Promise(r => setTimeout(r, 100));
  }

  console.log('\n=== FOUND TXS ===');
  console.log(txHashes.slice(0, 20).join('\n'));

  // Now get receipt + tx for each to classify
  const results = [];
  for (const txh of txHashes.slice(0, 15)) {
    const [rcpt, tx] = await Promise.all([
      rpcCall('eth_getTransactionReceipt', [txh], 1),
      rpcCall('eth_getTransactionByHash', [txh], 2)
    ]);
    const status = rcpt.result?.status === '0x1' ? 'success' : rcpt.result?.status === '0x0' ? 'failed' : 'unknown';
    const input = tx.result?.input || '';
    const from = tx.result?.from || '';
    const value = tx.result?.value || '0x0';
    const block = parseInt(tx.result?.blockNumber || '0x0', 16);
    
    // Classify route type from calldata
    const selector = input.slice(0, 10);
    let method = 'unknown';
    if (selector === '0xff84aafa') method = 'mixSwap'; // bytes4(keccak256("mixSwap(address,address,uint256,uint256,uint256,address[],address[],address[],uint256,bytes[],bytes,uint256)")) 
    else if (selector === '0xbc74f9ff') method = 'externalSwap';
    else if (selector === '0xb1dc7df9') method = 'dodoMutliSwap';
    else if (selector === '0x0d4eec8f') method = '_WETH_';
    
    // Check for OrderHistory log
    const orderHistoryLog = rcpt.result?.logs?.find(l => 
      l.address.toLowerCase() === '0xa5ca5fbe34e444f366b373170541ec6902b0f75c'.toLowerCase() &&
      l.topics[0] === '0x92ceb067a9883c85aba061e46b9edf505a0d6e81927c4b966ebed543a5221787'
    );
    
    // Check for PositiveSlippage
    const positiveSlippageLog = rcpt.result?.logs?.find(l =>
      l.address.toLowerCase() === '0xa5ca5fbe34e444f366b373170541ec6902b0f75c'.toLowerCase() &&
      l.topics[0] === '0xd820290de56f193465e6c0b6140e6bedce58ba0d54229b2a57fd4b60d285297c'
    );

    // Extract fromToken/toToken from calldata for mixSwap
    let fromToken = '', toToken = '';
    if (method === 'mixSwap' && input.length >= 0x1c0) {
      // first param at offset 0x44
      fromToken = '0x' + input.slice(0x44 + 24, 0x44 + 64);
      toToken = '0x' + input.slice(0x64 + 24, 0x64 + 64);
    }
    
    const rt = fromToken.toLowerCase() === '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' ? 'native' : 'token';
    const rt2 = toToken.toLowerCase() === '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' ? 'native' : 'token';
    const routeType = `${rt}->${rt2}`;
    
    const logCount = rcpt.result?.logs?.length || 0;
    
    results.push({
      txh: txh.slice(0, 10),
      txHash: txh,
      block,
      status,
      from: from.slice(0, 10),
      method,
      routeType,
      hasOrderHistory: !!orderHistoryLog,
      hasPositiveSlippage: !!positiveSlippageLog,
      logCount,
      value,
      orderHistoryData: orderHistoryLog?.data
    });
  }
  
  console.log('\n=== SUMMARY ===');
  for (const r of results) {
    console.log(`${r.txh} b:${r.block} ${r.status} ${r.method} ${r.routeType} OH:${r.hasOrderHistory} PS:${r.hasPositiveSlippage} logs:${r.logCount} val:${r.value} from:${r.from}`);
  }
}

main().catch(console.error);