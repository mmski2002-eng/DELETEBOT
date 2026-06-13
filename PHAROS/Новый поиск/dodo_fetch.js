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
  // Get receipt for the known sample tx
  const r1 = await rpcCall('eth_getTransactionReceipt', ['0xdbe7b075e43bc11eafb89c2778858ddfcf7d7c3b832f4e92e1dabbc101b5ef98'], 1);
  console.log('=== RECEIPT TX1 ===');
  console.log(JSON.stringify(r1, null, 2));

  // Get the second sample tx
  const r2 = await rpcCall('eth_getTransactionByHash', ['0x3de490eec96536f9f1cdcf59ccca1914413fa00b0350eb6741a3443bc14b327f'], 2);
  console.log('\n=== TX2 ===');
  console.log(JSON.stringify(r2, null, 2));

  const r3 = await rpcCall('eth_getTransactionReceipt', ['0x3de490eec96536f9f1cdcf59ccca1914413fa00b0350eb6741a3443bc14b327f'], 3);
  console.log('\n=== RECEIPT TX2 ===');
  console.log(JSON.stringify(r3, null, 2));

  // Find more DODO txs via logs
  const r4 = await rpcCall('eth_getLogs', [{
    address: '0xa5ca5fbe34e444f366b373170541ec6902b0f75c',
    topics: ['0x92ceb067a9883c85aba061e46b9edf505a0d6e81927c4b966ebed543a5221787'],
    fromBlock: '0x6d0000',
    toBlock: 'latest'
  }], 4);
  console.log('\n=== ORDERHISTORY LOGS ===');
  console.log(JSON.stringify(r4, null, 2));
}

main().catch(console.error);