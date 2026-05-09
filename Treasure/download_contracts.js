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
        try { resolve(JSON.parse(data)); } catch(e) { resolve({ raw: data.substring(0, 1000) }); }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    req.write(body);
    req.end();
  });
}

function httpGet(url) {
  return new Promise((resolve) => {
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' } }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({ statusCode: res.statusCode, headers: res.headers, data: data.substring(0, 5000) });
      });
    }).on('error', (e) => resolve({ error: e.message }));
  });
}

async function main() {
  // Try using etherscan's V2 api.arbiscan.io format properly
  // Format from docs: https://api.arbiscan.io/v2/api?chainid=42161&module=contract&action=getsourcecode&address=...
  
  const MAGIC = "0x539bdE0d7Dbd336b79148AA742883198BBF60342";
  
  // Try different URL formats
  const urls = [
    `https://api.arbiscan.io/api?module=contract&action=getsourcecode&address=${MAGIC}&apikey=W6KI9JX7YVV3I8Q8IRHGZCJJ6AH7GPVXQI`,
    `https://api.arbiscan.io/api?module=contract&action=getabi&address=${MAGIC}&apikey=W6KI9JX7YVV3I8Q8IRHGZCJJ6AH7GPVXQI`,
    `https://arbiscan.io/address/${MAGIC}#code`,
  ];
  
  for (let url of urls) {
    console.log(`\n=== Fetching: ${url.substring(0, 100)}...`);
    let result = await httpGet(url);
    console.log(`Status: ${result.statusCode}, Data: ${result.data.substring(0, 1500)}`);
  }

  // Try to use the RPC to get storage slots that might contain known addresses
  // MAGIC: check for minter/owner storage
  console.log("\n=== MAGIC storage exploration ===");
  
  // Common storage slots for OpenZeppelin/Ownable
  // owner slot: typically 0
  let ownerSlot = await rpcCall('eth_getStorageAt', [MAGIC, '0x0', 'latest']);
  console.log(`Storage[0] (owner?): ${ownerSlot.result}`);
  
  // Try to find known Treasure contracts via NFT transfer events
  console.log("\n=== Searching for NFT contracts interacting with Legion holders ===");
  const LEGION = "0xfE8c1ac365bA6780AEc5a985D989b327C27670A1";
  
  // Get a recent block
  let block = await rpcCall('eth_blockNumber', []);
  let blockNum = parseInt(block.result, 16);
  
  // Get Legion Transfer events in smaller range
  let legionLogs = await rpcCall('eth_getLogs', [{
    address: LEGION,
    fromBlock: '0x' + (blockNum - 200000).toString(16),
    toBlock: 'latest',
    topics: ['0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'],
  }]);
  
  if (legionLogs && legionLogs.result && legionLogs.result.length > 0) {
    console.log(`Found ${legionLogs.result.length} Legion transfer events`);
    
    // Get unique addresses
    let addrs = new Set();
    for (let log of legionLogs.result.slice(0, 100)) {
      addrs.add('0x' + log.topics[1].slice(26));
      addrs.add('0x' + log.topics[2].slice(26));
    }
    
    // Check which are contracts
    for (let addr of addrs) {
      if (addr === '0x0000000000000000000000000000000000000000') continue;
      let code = await rpcCall('eth_getCode', [addr, 'latest']);
      if (code.result && code.result !== '0x' && code.result.length > 20) {
        // Check name
        let nameHex = await rpcCall('eth_call', [{ to: addr, data: '0x06fdde03' }, 'latest']);
        let symbolHex = await rpcCall('eth_call', [{ to: addr, data: '0x95d89b41' }, 'latest']);
        
        let name = '';
        if (nameHex.result && nameHex.result.length > 130) {
          let data = nameHex.result.slice(2);
          let offset = parseInt(data.slice(0, 64), 16) * 2;
          let len = parseInt(data.slice(offset, offset + 64), 16) * 2;
          let str = data.slice(offset + 64, offset + 64 + len);
          for (let i = 0; i < str.length; i += 2) name += String.fromCharCode(parseInt(str.slice(i, i+2), 16));
        }
        
        let symbol = '';
        if (symbolHex.result && symbolHex.result.length > 130) {
          let data = symbolHex.result.slice(2);
          let offset = parseInt(data.slice(0, 64), 16) * 2;
          let len = parseInt(data.slice(offset, offset + 64), 16) * 2;
          let str = data.slice(offset + 64, offset + 64 + len);
          for (let i = 0; i < str.length; i += 2) symbol += String.fromCharCode(parseInt(str.slice(i, i+2), 16));
        }
        
        console.log(`Contract: ${addr} | Name: ${name} | Symbol: ${symbol} | CodeLen: ${code.result.length}`);
      }
    }
  }
}

main().catch(console.error);