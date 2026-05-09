const https = require('https');

function rpcCall(method, params) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ jsonrpc: '2.0', method, params, id: 1 });
    const options = {
      hostname: 'arb1.arbitrum.io',
      path: '/rpc',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
      timeout: 30000
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); } catch(e) { resolve({ error: data }); }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    req.write(body);
    req.end();
  });
}

async function fetchAbi(address) {
  // Try a few known API endpoints
  const urls = [
    `https://api.arbiscan.io/api?module=contract&action=getabi&address=${address}&apikey=W6KI9JX7YVV3I8Q8IRHGZCJJ6AH7GPVXQI`,
    `https://api.arbiscan.io/api?module=contract&action=getsourcecode&address=${address}&apikey=W6KI9JX7YVV3I8Q8IRHGZCJJ6AH7GPVXQI`,
  ];

  for (let url of urls) {
    const result = await new Promise((resolve) => {
      https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          try { 
            const parsed = JSON.parse(data);
            resolve(parsed);
          } catch(e) { 
            resolve(data.substring(0, 300)); 
          }
        });
      }).on('error', (e) => resolve('Error: ' + e.message));
    });
    if (result.status === '1') return result;
    if (typeof result === 'object' && result.message && !result.message.includes('deprecated')) {
      return result;
    }
  }
  return null;
}

async function getTxHistory(address) {
  // Use eth_getLogs to find Transfer events involving MAGIC
  const MAGIC = "0x539bdE0d7Dbd336b79148AA742883198BBF60342";
  const transferTopic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";
  
  // Get latest block first
  let latestBlock = await rpcCall('eth_blockNumber', []);
  let blockNum = parseInt(latestBlock.result, 16);
  
  // Search for Transfer from/to known Treasure addresses in recent blocks
  // We'll do a broader search: get transactions to known addresses
  console.log(`Latest block: ${blockNum}`);
  
  // Try to get ABI for MAGIC
  console.log("\n=== Trying to get MAGIC ABI/Source ===");
  let abiResult = await fetchAbi(MAGIC);
  console.log(JSON.stringify(abiResult).substring(0, 2000));
  
  // Try to get ABI for Legion
  console.log("\n=== Trying to get Legion ABI/Source ===");
  let legionResult = await fetchAbi("0xfE8c1ac365bA6780AEc5a985D989b327C27670A1");
  console.log(JSON.stringify(legionResult).substring(0, 2000));

  // Try to get ABI for AtlasMine
  console.log("\n=== Trying to get AtlasMine ABI/Source ===");
  let atlasResult = await fetchAbi("0xA0A89db1C899c49F98E6326b764BAFcf167fC2CE");
  console.log(JSON.stringify(atlasResult).substring(0, 2000));
}

getTxHistory().catch(console.error);