const https = require('https');

function rpc(method, params) {
  const d = JSON.stringify({ jsonrpc: '2.0', method, params, id: 1 });
  return new Promise((resolve, reject) => {
    const req = https.request('https://rpc.pharos.xyz', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      timeout: 20000
    }, res => {
      let body = '';
      res.on('data', c => body += c);
      res.on('end', () => { try { resolve(JSON.parse(body)); } catch(e) { reject(e); } });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    req.write(d);
    req.end();
  });
}

async function main() {
  const DODO = '0xa5ca5fbe34e444f366b373170541ec6902b0f75c';
  const OH_TOPIC = '0x92ceb067a9883c85aba061e46b9edf505a0d6e81927c4b966ebed543a5221787';
  
  // Known blocks from discovery
  // TX1 at 7204588, TX2 at 7203466
  
  const ranges = [
    [7204500, 7205000],  // around TX1
    [7203400, 7204000],  // around TX2  
    [7204000, 7204500],  // between TX2 and TX1
    [7203000, 7203400],  // before TX2
    [7198000, 7199000],  // older
  ];
  
  const ohLogs = [];
  for (const [from, to] of ranges) {
    try {
      const r = await rpc('eth_getLogs', [{
        address: DODO,
        topics: [OH_TOPIC],
        fromBlock: '0x' + from.toString(16),
        toBlock: '0x' + to.toString(16)
      }]);
      if (r.result && r.result.length > 0) {
        console.log(`Range ${from}-${to}: ${r.result.length} OrderHistory logs`);
        ohLogs.push(...r.result.map(l => ({ ...l, blockDec: parseInt(l.blockNumber, 16) })));
      }
    } catch(e) {
      console.log(`Range ${from}-${to}: error - ${e.message}`);
    }
  }
  
  // Deduplicate by tx hash
  const uniqueTxs = new Map();
  for (const log of ohLogs) {
    if (!uniqueTxs.has(log.transactionHash)) {
      uniqueTxs.set(log.transactionHash, log);
    }
  }
  
  console.log(`\nUnique DODO swap txs with OrderHistory: ${uniqueTxs.size}`);
  
  // Get receipt for each
  const txList = [];
  for (const [hash, log] of uniqueTxs) {
    try {
      const [txR, rcptR] = await Promise.all([
        rpc('eth_getTransactionByHash', [hash]),
        rpc('eth_getTransactionReceipt', [hash])
      ]);
      const tx = txR.result;
      const rcpt = rcptR.result;
      if (!tx || !rcpt) continue;
      
      const status = rcpt.status === '0x1' ? 'SUCCESS' : 'FAILED';
      const selector = (tx.input || '').slice(0, 10);
      
      // Parse OrderHistory from the event data
      const data = log.data;
      const ohFromToken = '0x' + data.slice(24, 64);
      const ohToToken = '0x' + data.slice(88, 128);
      const ohSender = '0x' + data.slice(152, 192);
      const ohFromAmount = BigInt('0x' + data.slice(192, 256));
      const ohReturnAmount = BigInt('0x' + data.slice(256, 320));
      
      // Find the last USDC transfer to sender (output)
      let finalTransferToSender = BigInt(0);
      let feeTransferToReceiver = BigInt(0);
      let poolOutputToDodo = BigInt(0);
      const feeReceiver = '0x903cf528c0c54ecb99991a69e0e095589917a0ce';
      
      for (const l of (rcpt.logs || [])) {
        if (l.topics[0] === '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef') {
          const fromA = '0x' + l.topics[1].slice(26).toLowerCase();
          const toA = '0x' + l.topics[2].slice(26).toLowerCase();
          const amount = BigInt(l.data.slice(0, 66));
          
          // USDC transfer DODO->sender
          if (l.address.toLowerCase() === ohToToken.toLowerCase() && 
              fromA === DODO.toLowerCase() && 
              toA === tx.from.toLowerCase()) {
            finalTransferToSender = amount;
          }
          // USDC transfer pool->DODO
          if (l.address.toLowerCase() === ohToToken.toLowerCase() && 
              toA === DODO.toLowerCase() &&
              fromA !== '0x0000000000000000000000000000000000000000') {
            poolOutputToDodo = amount;
          }
          // Fee transfer DODO->feeReceiver
          if (l.address.toLowerCase() === ohToToken.toLowerCase() && 
              fromA === DODO.toLowerCase() &&
              toA === feeReceiver.toLowerCase()) {
            feeTransferToReceiver = amount;
          }
        }
      }
      
      const fromIsNative = ohFromToken.toLowerCase() === '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
      const toIsNative = ohToToken.toLowerCase() === '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
      let routeType = 'token->token';
      if (fromIsNative && !toIsNative) routeType = 'native->token';
      else if (!fromIsNative && toIsNative) routeType = 'token->native';
      
      // Get WPROS deposit amount
      let wprosDeposit = BigInt(0);
      for (const l of (rcpt.logs || [])) {
        if (l.topics[0] === '0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c') {
          wprosDeposit = BigInt(l.data.slice(0, 66));
        }
      }
      
      let method = selector;
      if (selector === '0xff84aafa') method = 'mixSwap';
      else if (selector === '0xbc74f9ff') method = 'externalSwap';
      else if (selector === '0xb1dc7df9') method = 'dodoMutliSwap';
      
      // Check if OH.returnAmount matches final transfer
      const match = ohReturnAmount === finalTransferToSender;
      const poolAfterFee = poolOutputToDodo - feeTransferToReceiver;
      
      txList.push({
        hash: hash.slice(0, 12),
        fullHash: hash,
        block: log.blockDec,
        status,
        from: tx.from.slice(0, 10),
        method,
        routeType,
        wprosDeposit: wprosDeposit.toString(),
        ohFromToken: ohFromToken.slice(0, 10),
        ohToToken: ohToToken.slice(0, 10),
        ohFromAmount: ohFromAmount.toString(),
        ohReturnAmount: ohReturnAmount.toString(),
        finalTransfer: finalTransferToSender.toString(),
        match,
        poolOutput: poolOutputToDodo.toString(),
        fee: feeTransferToReceiver.toString(),
        poolAfterFee: poolAfterFee.toString(),
        logCount: rcpt.logs?.length || 0
      });
    } catch(e) {
      console.log(`Error for ${hash.slice(0,10)}: ${e.message}`);
    }
  }
  
  console.log('\n=== RESULTS ===');
  for (const t of txList) {
    console.log(`\n${t.hash} b:${t.block} ${t.status} ${t.method} ${t.routeType}`);
    console.log(`  OH.returnAmount:  ${t.ohReturnAmount}`);
    console.log(`  Actual xfer:      ${t.finalTransfer}`);
    console.log(`  Match: ${t.match}`);
    console.log(`  Pool->DODO: ${t.poolOutput}  Fee: ${t.fee}  PoolAfterFee: ${t.poolAfterFee}`);
    console.log(`  OH.fromAmount: ${t.ohFromAmount}  WPROS deposit: ${t.wprosDeposit}`);
  }
}

main().catch(e => { console.error('FATAL:', e); });