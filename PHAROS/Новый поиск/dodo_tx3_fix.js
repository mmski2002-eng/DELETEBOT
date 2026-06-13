const https = require('https');

function rpc(method, params) {
  return new Promise(function(resolve, reject) {
    var d = JSON.stringify({ jsonrpc: '2.0', method: method, params: params, id: 1 });
    var req = https.request('https://rpc.pharos.xyz', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      timeout: 30000
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

async function main() {
  var DODO = '0xa5ca5fbe34e444f366b373170541ec6902b0f75c';
  var sender = '0x94f75629191ad4a74bd2f0d95031dbf01bd2d75e';
  var hash = '0xef0732c98096c42fdd9c357d380006324cc06810d4dda02fc79566cd82ad0bc4';
  
  console.log('TX3: USDC->native PROS');
  console.log('Fetching debug trace...\n');
  
  var traceR = await rpc('debug_traceTransaction', [hash, {
    tracer: 'callTracer',
    tracerConfig: { onlyTopCall: false }
  }]);
  
  if (traceR.result) {
    console.log(JSON.stringify(traceR.result, null, 2));
  } else {
    console.log('debug_trace not available, trying eth_getBalance before/after...');
    
    var rcptR = await rpc('eth_getTransactionReceipt', [hash]);
    var rcpt = rcptR.result;
    var blockNum = parseInt(rcpt.blockNumber, 16);
    
    console.log('Block:', blockNum);
    
    var before = await rpc('eth_getBalance', [sender, '0x' + (blockNum - 1).toString(16)]);
    var after = await rpc('eth_getBalance', [sender, '0x' + blockNum.toString(16)]);
    
    console.log('Sender native balance before:', BigInt(before.result));
    console.log('Sender native balance after:', BigInt(after.result));
    console.log('Delta:', BigInt(after.result) - BigInt(before.result));
    
    // The sender should have received native minus gas cost
    var txR = await rpc('eth_getTransactionByHash', [hash]);
    var tx = txR.result;
    var gasUsed = BigInt(rcpt.gasUsed);
    var gasPrice = BigInt(tx.gasPrice);
    var gasCost = gasUsed * gasPrice;
    
    console.log('Gas used:', gasUsed);
    console.log('Gas price:', gasPrice);
    console.log('Gas cost:', gasCost);
    
    var rawDelta = BigInt(after.result) - BigInt(before.result);
    var adjustedDelta = rawDelta + gasCost; // add back gas since sender paid it
    console.log('Adjusted delta (received native):', adjustedDelta);
    
    // OH.returnAmount = 4256092215980029952
    console.log('\nOH.returnAmount:', 4256092215980029952n);
    console.log('Match:', adjustedDelta === 4256092215980029952n);
    
    // Also check: pool->DODO WPROS flow
    var allLogs = rcpt.logs;
    console.log('\nAll logs:');
    for (var i = 0; i < allLogs.length; i++) {
      var l = allLogs[i];
      var sig = l.topics[0];
      if (sig === '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef') {
        var f = '0x' + l.topics[1].substring(26).toLowerCase();
        var t = '0x' + l.topics[2].substring(26).toLowerCase();
        var amt = BigInt(l.data.substring(0, 66));
        console.log('Transfer: ' + l.address + ' ' + f + ' -> ' + t + ' ' + amt);
      }
      if (sig === '0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c') {
        console.log('Deposit: ' + l.address + ' ' + BigInt(l.data.substring(0, 66)));
      }
      if (sig === '0xe1884be1c2022db3fc4a44a9bff2f31ef67a5e772802e67eb175965819e75286') {
        console.log('Withdrawal: ' + l.address + ' ' + BigInt(l.data.substring(0, 66)));
      }
    }
  }
}

main().catch(function(e) { console.error('FATAL:', e.message); });