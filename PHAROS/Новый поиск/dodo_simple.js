const https = require('https');

function rpc(method, params) {
  return new Promise(function(resolve, reject) {
    var d = JSON.stringify({ jsonrpc: '2.0', method: method, params: params, id: 1 });
    var req = https.request('https://rpc.pharos.xyz', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      timeout: 20000
    }, function(res) {
      var body = '';
      res.on('data', function(c) { body += c; });
      res.on('end', function() {
        try { resolve(JSON.parse(body)); } catch(e) { reject(e); }
      });
    });
    req.on('error', reject);
    req.on('timeout', function() { req.destroy(); reject(new Error('timeout')); });
    req.write(d);
    req.end();
  });
}

function sleep(ms) {
  return new Promise(function(r) { setTimeout(r, ms); });
}

async function analyzeTx(hash, label) {
  console.log('=== Analyzing ' + label + ' ===');
  console.log('Hash: ' + hash);
  
  var txR = await rpc('eth_getTransactionByHash', [hash]);
  var rcptR = await rpc('eth_getTransactionReceipt', [hash]);
  
  var tx = txR.result;
  var rcpt = rcptR.result;
  
  if (!tx || !rcpt) {
    console.log('ERROR: could not fetch tx/receipt');
    return;
  }
  
  var status = rcpt.status === '0x1' ? 'SUCCESS' : 'FAILED';
  var blockNum = parseInt(tx.blockNumber, 16);
  var blockR = await rpc('eth_getBlockByNumber', ['0x' + blockNum.toString(16), false]);
  var blockTS = parseInt(blockR.result.timestamp, 16);
  var from = tx.from;
  var val = parseInt(tx.value || '0', 16);
  var gasUsed = parseInt(rcpt.gasUsed || '0', 16);
  
  console.log('Block: ' + blockNum + ' TS: ' + blockTS);
  console.log('From: ' + from);
  console.log('Status: ' + status + ' Value: ' + val + ' Gas: ' + gasUsed);
  
  var DODO = '0xa5ca5fbe34e444f366b373170541ec6902b0f75c';
  
  // Find OrderHistory event
  var ohEvent = null;
  for (var i = 0; i < (rcpt.logs || []).length; i++) {
    var l = rcpt.logs[i];
    if (l.address.toLowerCase() === DODO.toLowerCase() &&
        l.topics[0] === '0x92ceb067a9883c85aba061e46b9edf505a0d6e81927c4b966ebed543a5221787') {
      ohEvent = l;
    }
  }
  
  var ohFromToken = '';
  var ohToToken = '';
  var ohSender = '';
  var ohFromAmount = '0';
  var ohReturnAmount = '0';
  
  if (ohEvent) {
    var d = ohEvent.data;
    ohFromToken = '0x' + d.substring(24, 64).replace(/^0+/, '0x').replace(/^0x$/, '0x0');
    // Proper address extraction
    ohFromToken = '0x' + d.substring(24, 64);
    ohToToken = '0x' + d.substring(88, 128);
    ohSender = '0x' + d.substring(152, 192);
    ohFromAmount = d.substring(192, 256);
    ohReturnAmount = d.substring(256, 320);
    
    console.log('OrderHistory found:');
    console.log('  fromToken: ' + ohFromToken);
    console.log('  toToken: ' + ohToToken);
    console.log('  sender: ' + ohSender);
    console.log('  fromAmount hex: ' + ohFromAmount);
    console.log('  returnAmount hex: ' + ohReturnAmount);
    console.log('  fromAmount dec: ' + BigInt('0x' + ohFromAmount).toString());
    console.log('  returnAmount dec: ' + BigInt('0x' + ohReturnAmount).toString());
  }
  
  // Find all token transfers
  console.log('\nToken transfers:');
  var outputTransfers = [];
  var poolDeposits = [];
  var wprosEvents = [];
  
  for (var i = 0; i < (rcpt.logs || []).length; i++) {
    var l = rcpt.logs[i];
    var sig = l.topics[0];
    
    if (sig === '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef') {
      var f = '0x' + l.topics[1].substring(26);
      var t = '0x' + l.topics[2].substring(26);
      var amt = l.data.substring(0, 66);
      console.log('  Transfer: ' + l.address + ' ' + f + ' -> ' + t + ' ' + BigInt(amt).toString());
      
      // Track if this is output to sender
      if (t.toLowerCase() === from.toLowerCase() && 
          l.address.toLowerCase() === ohToToken.toLowerCase()) {
        outputTransfers.push({ from: f, to: t, amount: BigInt(amt), token: l.address });
      }
    }
    
    if (sig === '0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c') {
      var depTo = '0x' + l.topics[1].substring(26);
      var depAmt = l.data.substring(0, 66);
      console.log('  WPROS Deposit: ' + l.address + ' to ' + depTo + ' ' + BigInt(depAmt).toString());
      wprosEvents.push({ token: l.address, to: depTo, amount: BigInt(depAmt) });
    }
    
    if (sig === '0xe1884be1c2022db3fc4a44a9bff2f31ef67a5e772802e67eb175965819e75286') {
      console.log('  WPROS Withdrawal: ' + l.address + ' data=' + l.data.substring(0,66));
    }
    
    // PositiveSlippage
    if (sig === '0xd820290de56f193465e6c0b6140e6bedce58ba0d54229b2a57fd4b60d285297c') {
      console.log('  PositiveSlippage: data=' + l.data);
    }
  }
  
  // Now reconcile
  console.log('\n=== RECONCILIATION ===');
  
  var ohReturnDec = BigInt('0x' + ohReturnAmount);
  var totalOutput = BigInt(0);
  for (var i = 0; i < outputTransfers.length; i++) {
    totalOutput = totalOutput + outputTransfers[i].amount;
  }
  
  console.log('OrderHistory.returnAmount: ' + ohReturnDec.toString());
  console.log('Total output transfers to sender: ' + totalOutput.toString());
  console.log('Match: ' + (ohReturnDec === totalOutput));
  
  // Check minReturnAmount from calldata
  if (tx.input && tx.input.length > 300) {
    var inputData = tx.input.substring(10);
    // Try mixSwap layout first
    if (tx.input.substring(0, 10) === '0xff84aafa') {
      var fromToken = '0x' + inputData.substring(24, 64);
      var toToken = '0x' + inputData.substring(88, 128);
      var fromTokenAmount = BigInt('0x' + inputData.substring(128, 192));
      var expReturnAmount = BigInt('0x' + inputData.substring(192, 256));
      var minReturnAmount = BigInt('0x' + inputData.substring(256, 320));
      var deadline = parseInt(inputData.substring(352*2, 352*2+64), 16);
      
      console.log('\nCalldata (mixSwap):');
      console.log('  fromToken: ' + fromToken);
      console.log('  toToken: ' + toToken);
      console.log('  fromTokenAmount: ' + fromTokenAmount.toString());
      console.log('  expReturnAmount: ' + expReturnAmount.toString());
      console.log('  minReturnAmount: ' + minReturnAmount.toString());
      console.log('  deadline: ' + deadline + ' (valid: ' + (blockTS < deadline) + ')');
      console.log('  OH.returnAmount vs expReturnAmount: ' + (ohReturnDec === expReturnAmount));
      console.log('  Output vs minReturnAmount: ' + (totalOutput >= minReturnAmount));
    }
  }
  
  // Check fee flow
  var feeReceiver = '0x903cf528c0c54ecb99991a69e0e095589917a0ce';
  console.log('\nFee receiver check:');
  for (var i = 0; i < (rcpt.logs || []).length; i++) {
    var l = rcpt.logs[i];
    if (l.topics[0] === '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef') {
      var f = '0x' + l.topics[1].substring(26);
      var t = '0x' + l.topics[2].substring(26);
      var amt = BigInt(l.data.substring(0, 66));
      if (t.toLowerCase() === feeReceiver.toLowerCase()) {
        console.log('  Fee transfer: ' + l.address + ' from ' + f + ' ' + amt.toString());
      }
    }
  }
  
  console.log('\n');
  await sleep(500);
}

async function main() {
  console.log('DODO FeeRouteProxy Analysis\n');
  console.log('Contract: 0xa5ca5fbe34e444f366b373170541ec6902b0f75c\n');
  
  // Phase 1: Contract baseline
  var DODO = '0xa5ca5fbe34e444f366b373170541ec6902b0f75c';
  
  console.log('=== PHASE 1: CONTRACT BASELINE ===');
  try {
    var ownerR = await rpc('eth_call', [{ to: DODO, data: '0x8da5cb5b' }, 'latest']);
    console.log('owner(): ' + ownerR.result);
  } catch(e) { console.log('owner() error: ' + e.message); }
  
  try {
    var feeRateR = await rpc('eth_call', [{ to: DODO, data: '0x1c4f09f6' }, 'latest']);
    console.log('routeFeeRate(): ' + feeRateR.result);
  } catch(e) { console.log('routeFeeRate() error: ' + e.message); }
  
  try {
    var feeRecR = await rpc('eth_call', [{ to: DODO, data: '0x0a0d1c3a' }, 'latest']);
    console.log('routeFeeReceiver(): ' + feeRecR.result);
  } catch(e) { console.log('routeFeeReceiver() error: ' + e.message); }
  
  try {
    var wethR = await rpc('eth_call', [{ to: DODO, data: '0x4c02e2af' }, 'latest']);
    console.log('_WETH_(): ' + wethR.result);
  } catch(e) { console.log('_WETH_() error: ' + e.message); }
  
  try {
    var daproxyR = await rpc('eth_call', [{ to: DODO, data: '0xc2649e63' }, 'latest']);
    console.log('_DODO_APPROVE_PROXY_(): ' + daproxyR.result);
  } catch(e) { console.log('_DODO_APPROVE_PROXY_() error: ' + e.message); }
  
  // Storage slots
  try {
    var slot0 = await rpc('eth_getStorageAt', [DODO, '0x0', 'latest']);
    console.log('Storage[0]: ' + slot0.result);
  } catch(e) {}
  
  try {
    var slot4 = await rpc('eth_getStorageAt', [DODO, '0x4', 'latest']);
    console.log('Storage[4] (feeRate?): ' + slot4.result + ' = ' + (slot4.result ? parseInt(slot4.result, 16) : ''));
  } catch(e) {}
  
  try {
    var slot5 = await rpc('eth_getStorageAt', [DODO, '0x5', 'latest']);
    console.log('Storage[5] (feeReceiver?): ' + slot5.result);
  } catch(e) {}
  
  console.log('\n');
  
  // Phase 2-5: Analyze the 2 known transactions
  await analyzeTx('0xdbe7b075e43bc11eafb89c2778858ddfcf7d7c3b832f4e92e1dabbc101b5ef98', 'TX1 (Known native PROS->USDC)');
  await analyzeTx('0x3de490eec96536f9f1cdcf59ccca1914413fa00b0350eb6741a3443bc14b327f', 'TX2 (Known native PROS->USDC)');
  
  // Now try to find 3 more diverse txs via eth_getLogs
  console.log('=== FINDING 3 MORE TXS ===');
  var OH_TOPIC = '0x92ceb067a9883c85aba061e46b9edf505a0d6e81927c4b966ebed543a5221787';
  
  var ranges = [
    [7205000, 7205200],
    [7203000, 7203200],
    [7202000, 7202200]
  ];
  
  var foundHashes = new Set();
  foundHashes.add('0xdbe7b075e43bc11eafb89c2778858ddfcf7d7c3b832f4e92e1dabbc101b5ef98');
  foundHashes.add('0x3de490eec96536f9f1cdcf59ccca1914413fa00b0350eb6741a3443bc14b327f');
  
  var newHashes = [];
  for (var r = 0; r < ranges.length; r++) {
    var range = ranges[r];
    try {
      var logsR = await rpc('eth_getLogs', [{
        address: DODO,
        topics: [OH_TOPIC],
        fromBlock: '0x' + range[0].toString(16),
        toBlock: '0x' + range[1].toString(16)
      }]);
      if (logsR.result && logsR.result.length > 0) {
        console.log('Range ' + range[0] + '-' + range[1] + ': ' + logsR.result.length + ' logs');
        for (var i = 0; i < logsR.result.length; i++) {
          var h = logsR.result[i].transactionHash;
          if (!foundHashes.has(h)) {
            foundHashes.add(h);
            newHashes.push(h);
          }
        }
      } else {
        console.log('Range ' + range[0] + '-' + range[1] + ': 0 logs or error');
      }
    } catch(e) {
      console.log('Range ' + range[0] + '-' + range[1] + ': error ' + e.message);
    }
    await sleep(200);
  }
  
  console.log('New hashes found: ' + newHashes.length);
  
  for (var i = 0; i < Math.min(3, newHashes.length); i++) {
    await analyzeTx(newHashes[i], 'TX' + (i+3) + ' (New)');
  }
  
  console.log('=== COMPLETE ===');
}

main().catch(function(e) { console.error('FATAL: ' + e.message); });