const https = require('https');

function rpc(method, params) {
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
    req.setTimeout(15000, () => { req.destroy(); reject(new Error('timeout')); });
    req.write(d);
    req.end();
  });
}

async function getBalance(token, holder, blockHex) {
  if (token === '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee') {
    const r = await rpc('eth_getBalance', [holder, blockHex]);
    return BigInt(r.result);
  }
  const data = '0x70a08231000000000000000000000000' + holder.slice(2);
  const r = await rpc('eth_call', [{ to: token, data }, blockHex]);
  return BigInt(r.result);
}

async function main() {
  const DODO = '0xa5ca5fbe34e444f366b373170541ec6902b0f75c';
  const WPROS = '0x52c48d4213107b20bc583832b0d951fb9ca8f0b0';
  const USDC = '0xc879c018db60520f4355c26ed1a6d572cdac1815';
  
  // Get 5 diverse txs. We have 2 known. Let's find 3 more.
  // Scan specific blocks near known activity
  const curBnR = await rpc('eth_blockNumber', []);
  const cur = parseInt(curBnR.result, 16);
  console.log('Current block:', cur);
  
  // Scan for DODO txs in recent blocks
  const candidateHashes = [];
  // Start from current block, go back up to 500 blocks
  for (let b = cur; b > cur - 500 && candidateHashes.length < 20; b--) {
    try {
      const blk = await rpc('eth_getBlockByNumber', ['0x' + b.toString(16), true]);
      if (!blk.result) continue;
      for (const tx of (blk.result.transactions || [])) {
        if (tx.to && tx.to.toLowerCase() === DODO.toLowerCase()) {
          candidateHashes.push(tx.hash);
        }
      }
    } catch(e) {}
  }
  
  console.log('Found', candidateHashes.length, 'DODO txs in last 500 blocks');
  
  // Also known txs
  const allHashes = [
    '0xdbe7b075e43bc11eafb89c2778858ddfcf7d7c3b832f4e92e1dabbc101b5ef98',
    '0x3de490eec96536f9f1cdcf59ccca1914413fa00b0350eb6741a3443bc14b327f',
    ...candidateHashes
  ];
  
  // Deduplicate
  const uniqueHashes = [...new Set(allHashes)];
  console.log('Unique hashes:', uniqueHashes.length);
  
  // Fetch details for first 10
  const txDetails = [];
  for (const hash of uniqueHashes.slice(0, 10)) {
    try {
      const [txR, rcptR] = await Promise.all([
        rpc('eth_getTransactionByHash', [hash]),
        rpc('eth_getTransactionReceipt', [hash])
      ]);
      const tx = txR.result;
      const rcpt = rcptR.result;
      if (!tx || !rcpt) continue;
      
      const status = rcpt.status === '0x1' ? 'SUCCESS' : 'FAILED';
      const selector = tx.input ? tx.input.slice(0, 10) : '0x';
      let method = selector;
      if (selector === '0xff84aafa') method = 'mixSwap';
      else if (selector === '0xbc74f9ff') method = 'externalSwap';
      else if (selector === '0xb1dc7df9') method = 'dodoMutliSwap';
      
      const ohLog = rcpt.logs?.find(l => 
        l.address.toLowerCase() === DODO.toLowerCase() &&
        l.topics[0] === '0x92ceb067a9883c85aba061e46b9edf505a0d6e81927c4b966ebed543a5221787'
      );
      
      const psLog = rcpt.logs?.find(l =>
        l.address.toLowerCase() === DODO.toLowerCase() &&
        l.topics[0] === '0xd820290de56f193465e6c0b6140e6bedce58ba0d54229b2a57fd4b60d285297c'
      );
      
      txDetails.push({
        hash,
        block: parseInt(tx.blockNumber, 16),
        status,
        from: tx.from,
        method,
        value: parseInt(tx.value || '0', 16),
        gasUsed: parseInt(rcpt.gasUsed || '0', 16),
        logCount: rcpt.logs?.length || 0,
        hasOH: !!ohLog,
        hasPS: !!psLog,
        ohData: ohLog?.data,
        psData: psLog?.data,
        logs: rcpt.logs,
        input: tx.input
      });
      console.log(`  Got ${hash.slice(0,10)}: ${status} ${method} OH:${!!ohLog} PS:${!!psLog}`);
    } catch(e) {
      console.log(`  Error for ${hash.slice(0,10)}: ${e.message}`);
    }
  }
  
  // Select 5 diverse:
  // 1. native->token (TX1)
  // 2. token->native 
  // 3. token->token
  // 4. multi-hop
  // 5. with PositiveSlippage or failed
  
  console.log('\n=== CANDIDATE SELECTION ===');
  for (const t of txDetails) {
    console.log(`${t.hash.slice(0,10)} b:${t.block} ${t.status} ${t.method} OH:${t.hasOH} PS:${t.hasPS} logs:${t.logCount} val:${t.value}`);
  }
  
  // Pick our 5
  const selected = [];
  const used = new Set();
  
  // 1. From known - native->token 
  const tx1 = txDetails.find(t => t.hash === '0xdbe7b075e43bc11eafb89c2778858ddfcf7d7c3b832f4e92e1dabbc101b5ef98');
  if (tx1) { selected.push({ ...tx1, note: 'Known: native PROS->USDC' }); used.add(tx1.hash); }
  
  // 2. From known - native->token  
  const tx2 = txDetails.find(t => t.hash === '0x3de490eec96536f9f1cdcf59ccca1914413fa00b0350eb6741a3443bc14b327f');
  if (tx2) { selected.push({ ...tx2, note: 'Known: native PROS->USDC' }); used.add(tx2.hash); }
  
  // 3-5: pick from newly discovered
  for (const t of txDetails) {
    if (used.has(t.hash)) continue;
    if (selected.length >= 5) break;
    if (t.hasOH && t.status === 'SUCCESS') {
      // Check route type
      if (t.input && t.input.length > 200) {
        selected.push({ ...t, note: 'New discovery' });
        used.add(t.hash);
      }
    }
  }
  
  // Also pick a failed if available
  const failed = txDetails.find(t => !used.has(t.hash) && t.status === 'FAILED');
  if (failed && selected.length < 6) {
    selected.push({ ...failed, note: 'FAILED control' });
    used.add(failed.hash);
  }
  
  console.log(`\nSelected ${selected.length} txs for full analysis`);
  
  // Now for each selected tx, do full reconciliation
  console.log('\n=== PHASE 3: CALLDATA DECODE ===');
  for (const s of selected) {
    console.log(`\n--- ${s.hash} ---`);
    console.log(`Block: ${s.block} Status: ${s.status} Method: ${s.method} Note: ${s.note}`);
    
    if (s.method === 'mixSwap' && s.input) {
      // Decode mixSwap calldata
      const data = s.input.slice(10); // remove selector
      // Parameters:
      // address fromToken (offset 0)
      // address toToken (offset 32)
      // uint256 fromTokenAmount (offset 64)
      // uint256 expReturnAmount (offset 96)
      // uint256 minReturnAmount (offset 128)
      // address[] mixAdapters (offset 160 - dynamic array offset)
      // address[] mixPairs (offset 192)
      // address[] assetTo (offset 224)
      // uint256 directions (offset 256)
      // bytes[] moreInfos (offset 288)
      // bytes feeData (offset 320)
      // uint256 deadline (offset 352)
      
      const fromToken = '0x' + data.slice(24, 64);
      const toToken = '0x' + data.slice(88, 128);
      const fromTokenAmount = BigInt('0x' + data.slice(128, 192));
      const expReturnAmount = BigInt('0x' + data.slice(192, 256));
      const minReturnAmount = BigInt('0x' + data.slice(256, 320));
      
      // deadline at offset 352-384
      const deadlineOffset = 352 * 2; // each byte = 2 hex chars
      const deadline = parseInt(data.slice(deadlineOffset, deadlineOffset + 64), 16);
      
      // Get block timestamp
      const blk = await rpc('eth_getBlockByNumber', ['0x' + s.block.toString(16), false]);
      const blockTimestamp = parseInt(blk.result.timestamp, 16);
      
      // Parse adapters array - offset at byte 160
      const adaptersOffsetHex = data.slice(160 * 2, 160 * 2 + 64);
      const adaptersOffset = parseInt(adaptersOffsetHex, 16) * 2;
      const adaptersLen = parseInt(data.slice(adaptersOffset, adaptersOffset + 64), 16);
      const adapters = [];
      for (let i = 0; i < adaptersLen && i < 10; i++) {
        adapters.push('0x' + data.slice(adaptersOffset + 64 + i * 64 + 24, adaptersOffset + 64 + (i + 1) * 64));
      }
      
      // assetTo array
      const assetToOffsetHex = data.slice(224 * 2, 224 * 2 + 64);
      const assetToOffset = parseInt(assetToOffsetHex, 16) * 2;
      const assetToLen = parseInt(data.slice(assetToOffset, assetToOffset + 64), 16);
      const assetTo = [];
      for (let i = 0; i < assetToLen && i < 10; i++) {
        assetTo.push('0x' + data.slice(assetToOffset + 64 + i * 64 + 24, assetToOffset + 64 + (i + 1) * 64));
      }
      
      // Parse OrderHistory
      let ohFromToken = '', ohToToken = '', ohSender = '', ohFromAmount = BigInt(0), ohReturnAmount = BigInt(0);
      if (s.ohData) {
        ohFromToken = '0x' + s.ohData.slice(24, 64);
        ohToToken = '0x' + s.ohData.slice(88, 128);
        ohSender = '0x' + s.ohData.slice(152, 192);
        ohFromAmount = BigInt('0x' + s.ohData.slice(192, 256));
        ohReturnAmount = BigInt('0x' + s.ohData.slice(256, 320));
      }
      
      // PositiveSlippage
      let psToken = '', psAmount = BigInt(0);
      if (s.psData) {
        psToken = '0x' + s.psData.slice(24, 64);
        psAmount = BigInt('0x' + s.psData.slice(64, 128));
      }
      
      // Token transfers from logs
      const transfers = [];
      const tokenEvents = new Set();
      for (const log of (s.logs || [])) {
        const sig = log.topics[0];
        if (sig === '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef' ||
            sig === '0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c') {
          const fromA = '0x' + log.topics[1].slice(26);
          const toA = '0x' + log.topics[2].slice(26);
          const amount = BigInt(log.data.slice(0, 66));
          transfers.push({
            token: log.address,
            from: fromA,
            to: toA,
            amount,
            isDeposit: sig === '0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c'
          });
          tokenEvents.add(log.address);
        }
      }
      
      console.log('fromToken:', fromToken);
      console.log('toToken:', toToken);
      console.log('fromTokenAmount:', fromTokenAmount.toString());
      console.log('expReturnAmount:', expReturnAmount.toString());
      console.log('minReturnAmount:', minReturnAmount.toString());
      console.log('deadline:', deadline);
      console.log('block.timestamp:', blockTimestamp);
      console.log('deadline valid:', blockTimestamp < deadline);
      console.log('adapters:', adapters);
      console.log('assetTo:', assetTo);
      console.log('');
      console.log('OrderHistory.fromToken:', ohFromToken);
      console.log('OrderHistory.toToken:', ohToToken);
      console.log('OrderHistory.sender:', ohSender);
      console.log('OrderHistory.fromAmount:', ohFromAmount.toString());
      console.log('OrderHistory.returnAmount:', ohReturnAmount.toString());
      console.log('PositiveSlippage.token:', psToken, 'amount:', psAmount.toString());
      console.log('');
      console.log('Key transfers:');
      for (const t of transfers) {
        console.log(`  ${t.token.slice(0,10)} ${t.from.slice(0,10)}->${t.to.slice(0,10)} ${t.amount}`);
      }
      
      // Token balance deltas
      console.log('\n=== BALANCE DELTAS ===');
      const prevBlock = '0x' + (s.block - 1).toString(16);
      const curBlock = '0x' + s.block.toString(16);
      
      // Sender balances
      const sender = s.from;
      // Check native balance delta for sender
      const nativeBefore = await getBalance('0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', sender, prevBlock);
      const nativeAfter = await getBalance('0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', sender, curBlock);
      const nativeDelta = nativeAfter - nativeBefore + BigInt(s.value) + BigInt(s.gasUsed) * BigInt(10e9); // approximate gas cost
      console.log(`Sender native: before=${nativeBefore} after=${nativeAfter} delta_adj=${nativeDelta}`);
      
      // Output token - check recipient (usually sender or assetTo last addr)
      const recipient = assetTo[assetTo.length - 1] || sender;
      for (const ttoken of tokenEvents) {
        if (ttoken === '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee') continue;
        try {
          const tokBefore = await getBalance(ttoken, recipient, prevBlock);
          const tokAfter = await getBalance(ttoken, recipient, curBlock);
          console.log(`Recipient ${recipient.slice(0,10)} ${ttoken.slice(0,10)}: before=${tokBefore} after=${tokAfter} delta=${tokAfter - tokBefore}`);
        } catch(e) {
          console.log(`  Balance check error for ${ttoken}: ${e.message}`);
        }
      }
    }
  }
}

main().catch(e => { console.error('FATAL:', e.message); });