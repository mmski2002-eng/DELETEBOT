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

function parseOH(data) {
  // data is "0x" + abi-encoded (fromToken, toToken, sender, fromAmount, returnAmount)
  // Each slot: 32 bytes = 64 hex chars
  // After "0x": index 2 onwards
  // Slot 0 (fromToken addr): indices 26-65
  // Slot 1 (toToken addr): indices 90-129
  // Slot 2 (sender addr): indices 154-193
  // Slot 3 (fromAmount): indices 194-257
  // Slot 4 (returnAmount): indices 258-321
  return {
    fromToken: '0x' + data.substring(26, 66).toLowerCase(),
    toToken: '0x' + data.substring(90, 130).toLowerCase(),
    sender: '0x' + data.substring(154, 194).toLowerCase(),
    fromAmount: BigInt('0x' + data.substring(194, 258)),
    returnAmount: BigInt('0x' + data.substring(258, 322))
  };
}

function findTransfers(logs, from, to, token) {
  var results = [];
  for (var i = 0; i < (logs || []).length; i++) {
    var l = logs[i];
    if (l.topics[0] === '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef') {
      var f = '0x' + l.topics[1].substring(26).toLowerCase();
      var t = '0x' + l.topics[2].substring(26).toLowerCase();
      var tokenAddr = l.address.toLowerCase();
      if (token && tokenAddr !== token.toLowerCase()) continue;
      if (from && f !== from.toLowerCase()) continue;
      if (to && t !== to.toLowerCase()) continue;
      results.push({ token: l.address, from: f, to: t, amount: BigInt(l.data.substring(0, 66)) });
    }
  }
  return results;
}

function findDeposits(logs, to) {
  var results = [];
  for (var i = 0; i < (logs || []).length; i++) {
    var l = logs[i];
    if (l.topics[0] === '0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c') {
      var t = '0x' + l.topics[1].substring(26).toLowerCase();
      if (to && t !== to.toLowerCase()) continue;
      results.push({ token: l.address, to: t, amount: BigInt(l.data.substring(0, 66)) });
    }
  }
  return results;
}

function findWithdraws(logs, from) {
  var results = [];
  for (var i = 0; i < (logs || []).length; i++) {
    var l = logs[i];
    if (l.topics[0] === '0xe1884be1c2022db3fc4a44a9bff2f31ef67a5e772802e67eb175965819e75286') {
      var f = '0x' + l.topics[1].substring(26).toLowerCase();
      if (from && f !== from.toLowerCase()) continue;
      results.push({ token: l.address, from: f, amount: BigInt(l.data.substring(0, 66)) });
    }
  }
  return results;
}

async function analyzeTx(hash, label) {
  console.log('\n' + '='.repeat(80));
  console.log(label + ': ' + hash);
  
  var txR = await rpc('eth_getTransactionByHash', [hash]);
  var rcptR = await rpc('eth_getTransactionReceipt', [hash]);
  var tx = txR.result;
  var rcpt = rcptR.result;
  
  if (!tx) { console.log('ERROR: tx not found'); return; }
  
  var status = rcpt.status === '0x1' ? 'SUCCESS' : 'FAILED';
  var blockNum = parseInt(tx.blockNumber, 16);
  var blockR = await rpc('eth_getBlockByNumber', ['0x' + blockNum.toString(16), false]);
  var blockTS = parseInt(blockR.result.timestamp, 16);
  var from = tx.from.toLowerCase();
  var val = BigInt(tx.value || '0');
  var gasUsed = parseInt(rcpt.gasUsed || '0', 16);
  var DODO = '0xa5ca5fbe34e444f366b373170541ec6902b0f75c';
  var FEE_REC = '0x903cf528c0c54ecb99991a69e0e095589917a0ce';
  var WPROS = '0x52c48d4213107b20bc583832b0d951fb9ca8f0b0';
  var USDC = '0xc879c018db60520f4355c26ed1a6d572cdac1815';
  
  console.log('Block: ' + blockNum + ' TS: ' + blockTS + ' Status: ' + status + ' Gas: ' + gasUsed);
  console.log('From: ' + from + ' Value: ' + val.toString());
  
  // Parse calldata
  var input = tx.input || '';
  var selector = input.substring(0, 10);
  var method = 'unknown';
  var calldecode = {};
  
  if (selector === '0xff84aafa') {
    method = 'mixSwap';
    var data = input.substring(10);
    // Slot offsets from 0: fromToken(0), toToken(32), fromTokenAmount(64), expReturnAmount(96), minReturnAmount(128)
    calldecode.fromToken = '0x' + data.substring(24, 64).toLowerCase();
    calldecode.toToken = '0x' + data.substring(88, 128).toLowerCase();
    calldecode.fromTokenAmount = BigInt('0x' + data.substring(128, 192));
    calldecode.expReturnAmount = BigInt('0x' + data.substring(192, 256));
    calldecode.minReturnAmount = BigInt('0x' + data.substring(256, 320));
    calldecode.deadline = parseInt(data.substring(352 * 2 + 2, 352 * 2 + 66), 16);
  } else if (selector === '0xbc74f9ff') {
    method = 'externalSwap';
  } else if (selector === '0xb1dc7df9') {
    method = 'dodoMutliSwap';
  }
  
  // Parse OrderHistory
  var ohLog = null;
  for (var i = 0; i < (rcpt.logs || []).length; i++) {
    if (rcpt.logs[i].address.toLowerCase() === DODO &&
        rcpt.logs[i].topics[0] === '0x92ceb067a9883c85aba061e46b9edf505a0d6e81927c4b966ebed543a5221787') {
      ohLog = rcpt.logs[i];
    }
  }
  
  var oh = null;
  if (ohLog) {
    oh = parseOH(ohLog.data);
  }
  
  // PositiveSlippage
  var ps = null;
  for (var i = 0; i < (rcpt.logs || []).length; i++) {
    if (rcpt.logs[i].address.toLowerCase() === DODO &&
        rcpt.logs[i].topics[0] === '0xd820290de56f193465e6c0b6140e6bedce58ba0d54229b2a57fd4b60d285297c') {
      var pd = rcpt.logs[i].data;
      ps = {
        token: '0x' + pd.substring(26, 66).toLowerCase(),
        amount: BigInt('0x' + pd.substring(66, 130))
      };
    }
  }
  
  // Transfers
  var wprosDeposits = findDeposits(rcpt.logs, DODO);
  var wprosWithdraws = findWithdraws(rcpt.logs, DODO);
  var outputXfers = findTransfers(rcpt.logs, DODO, from, calldecode.toToken);
  var feeXfers = findTransfers(rcpt.logs, DODO, FEE_REC);
  var poolOutputs = findTransfers(rcpt.logs, null, DODO, calldecode.toToken);
  var inputXfers = findTransfers(rcpt.logs, from, DODO, calldecode.fromToken);
  
  console.log('\n--- Calldata ---');
  console.log('Method: ' + method);
  console.log('fromToken: ' + calldecode.fromToken);
  console.log('toToken: ' + calldecode.toToken);
  console.log('fromTokenAmount: ' + calldecode.fromTokenAmount);
  console.log('expReturnAmount: ' + calldecode.expReturnAmount);
  console.log('minReturnAmount: ' + calldecode.minReturnAmount);
  console.log('deadline: ' + calldecode.deadline + ' (blockTS=' + blockTS + ', valid=' + (blockTS < calldecode.deadline) + ')');
  console.log('msg.value: ' + val);
  
  console.log('\n--- OrderHistory Event ---');
  if (oh) {
    console.log('fromToken: ' + oh.fromToken);
    console.log('toToken: ' + oh.toToken);
    console.log('sender: ' + oh.sender);
    console.log('fromAmount: ' + oh.fromAmount);
    console.log('returnAmount: ' + oh.returnAmount);
  } else {
    console.log('NOT FOUND');
  }
  
  console.log('\n--- PositiveSlippage ---');
  if (ps) {
    console.log('token: ' + ps.token + ' amount: ' + ps.amount);
  } else {
    console.log('NOT FOUND');
  }
  
  console.log('\n--- Token Flows ---');
  for (var i = 0; i < wprosDeposits.length; i++) {
    var d = wprosDeposits[i];
    console.log('WPROS Deposit: ' + d.token + ' amt=' + d.amount);
  }
  for (var i = 0; i < wprosWithdraws.length; i++) {
    var w = wprosWithdraws[i];
    console.log('WPROS Withdraw: ' + w.token + ' amt=' + w.amount);
  }
  for (var i = 0; i < inputXfers.length; i++) {
    console.log('Input: ' + inputXfers[i].token.substring(0,10) + ' ' + inputXfers[i].from.substring(0,10) + '->' + inputXfers[i].to.substring(0,10) + ' ' + inputXfers[i].amount);
  }
  for (var i = 0; i < poolOutputs.length; i++) {
    console.log('Pool->DODO: ' + poolOutputs[i].token.substring(0,10) + ' ' + poolOutputs[i].amount);
  }
  
  var totalFee = BigInt(0);
  for (var i = 0; i < feeXfers.length; i++) {
    totalFee = totalFee + feeXfers[i].amount;
    console.log('Fee: ' + feeXfers[i].token.substring(0,10) + ' ' + feeXfers[i].amount);
  }
  
  var totalOutput = BigInt(0);
  for (var i = 0; i < outputXfers.length; i++) {
    totalOutput = totalOutput + outputXfers[i].amount;
    console.log('Output: ' + outputXfers[i].token.substring(0,10) + ' DODO->sender=' + outputXfers[i].amount);
  }
  
  // Native output check
  var nativeOutput = BigInt(0);
  for (var i = 0; i < (rcpt.logs || []).length; i++) {
    // Check for WPROS withdrawal to sender - sender receives native
    var l = rcpt.logs[i];
    if (l.topics[0] === '0xe1884be1c2022db3fc4a44a9bff2f31ef67a5e772802e67eb175965819e75286' ||
        l.topics[0] === '0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65') {
      var wf = '0x' + l.topics[1].substring(26).toLowerCase();
      var wt = l.topics.length > 2 ? '0x' + l.topics[2].substring(26).toLowerCase() : '';
      var wamt = BigInt(l.data.substring(0, 66));
      console.log('Native Withdraw: from=' + wf + ' to=' + wt + ' amt=' + wamt);
      if (wt === from) nativeOutput = nativeOutput + wamt;
    }
  }
  
  console.log('\n=== RECONCILIATION ===');
  
  // Check OH.fromAmount vs actual input
  var ohFromAmountOk = false;
  if (oh && calldecode.fromToken === '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee') {
    var totalDeposit = BigInt(0);
    for (var i = 0; i < wprosDeposits.length; i++) totalDeposit = totalDeposit + wprosDeposits[i].amount;
    ohFromAmountOk = oh.fromAmount === totalDeposit || oh.fromAmount === calldecode.fromTokenAmount;
    console.log('OH.fromAmount check: OH=' + oh.fromAmount + ' WPROS_deposit=' + totalDeposit + ' calldata_fromAmount=' + calldecode.fromTokenAmount + ' OK=' + ohFromAmountOk);
  } else if (oh) {
    var totalInput = BigInt(0);
    for (var i = 0; i < inputXfers.length; i++) totalInput = totalInput + inputXfers[i].amount;
    ohFromAmountOk = oh.fromAmount === totalInput;
    console.log('OH.fromAmount check: OH=' + oh.fromAmount + ' TransferIn=' + totalInput + ' OK=' + ohFromAmountOk);
  }
  
  // Check if output matches
  var effectiveOutput = totalOutput + nativeOutput;
  var ohReturnAmountOk = oh ? (oh.returnAmount === effectiveOutput) : null;
  console.log('Output check: OH.returnAmount=' + (oh ? oh.returnAmount : 'N/A') + 
              ' TotalOutput=' + totalOutput + ' NativeOutput=' + nativeOutput + ' Effective=' + effectiveOutput +
              ' Match=' + ohReturnAmountOk);
  
  // expReturnAmount vs actual
  var expVsActual = calldecode.expReturnAmount === effectiveOutput;
  console.log('expReturnAmount vs effective output: exp=' + calldecode.expReturnAmount + ' actual=' + effectiveOutput + ' match=' + expVsActual);
  
  // minReturnAmount respected?
  var minOk = effectiveOutput >= calldecode.minReturnAmount;
  console.log('minReturnAmount check: actual=' + effectiveOutput + ' min=' + calldecode.minReturnAmount + ' respect=' + minOk);
  
  // Fee reconciliation
  var poolTotal = BigInt(0);
  for (var i = 0; i < poolOutputs.length; i++) poolTotal = poolTotal + poolOutputs[i].amount;
  var poolMinusFee = poolTotal - totalFee;
  console.log('Fee flow: pool->DODO=' + poolTotal + ' fee=' + totalFee + ' implied_user_output=' + poolMinusFee + ' actual_output=' + effectiveOutput + ' match=' + (poolMinusFee === effectiveOutput));
  
  // OH.toToken vs actual output token
  var outputToken = calldecode.toToken;
  var actualOutputToken = totalOutput > 0 ? USDC : (nativeOutput > 0 ? '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' : (wprosDeposits.length > 0 && effectiveOutput === BigInt(0) ? 'N/A' : WPROS));
  console.log('Output token: calldata=' + outputToken + ' actual_token=' + actualOutputToken);
  
  // OH.toToken match
  if (oh) {
    var ohTokenMatch = oh.toToken === outputToken || oh.toToken === actualOutputToken;
    console.log('OH.toToken match: OH=' + oh.toToken + ' calldata_toToken=' + outputToken + ' match=' + ohTokenMatch);
  }
  
  await sleep(300);
}

async function main() {
  console.log('DODO FeeRouteProxy OrderHistory vs Settlement Audit');
  console.log('Contract: 0xa5ca5fbe34e444f366b373170541ec6902b0f75c');
  console.log('Pharos Mainnet chainId=1672');
  
  // TXs to analyze - the 5 from the previous run
  var txs = [
    { hash: '0xdbe7b075e43bc11eafb89c2778858ddfcf7d7c3b832f4e92e1dabbc101b5ef98', label: 'TX1: native PROS->USDC' },
    { hash: '0x3de490eec96536f9f1cdcf59ccca1914413fa00b0350eb6741a3443bc14b327f', label: 'TX2: native PROS->USDC' },
    { hash: '0xef0732c98096c42fdd9c357d380006324cc06810d4dda02fc79566cd82ad0bc4', label: 'TX3: USDC->native PROS (token->native)' },
    { hash: '0xe3055db417accb13895d99c51d1ff3582b36b95650460e3bb63f2131ab39668b', label: 'TX4: native PROS->USDC' },
    { hash: '0x77a3ac99a5192ca2e924a13561eecb083edc5e94d7e1fd93439c9f9a60dc46de', label: 'TX5: native PROS->USDC' }
  ];
  
  for (var i = 0; i < txs.length; i++) {
    await analyzeTx(txs[i].hash, txs[i].label);
  }
  
  console.log('\n' + '='.repeat(80));
  console.log('FINAL VERDICT');
  console.log('='.repeat(80));
}

main().catch(function(e) { console.error('FATAL: ' + e.message); });