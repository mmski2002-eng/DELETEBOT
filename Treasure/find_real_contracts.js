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
        try { resolve(JSON.parse(data)); } catch(e) { resolve({ raw: data.substring(0, 500) }); }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    req.write(body);
    req.end();
  });
}

async function main() {
  const MAGIC = "0x539bdE0d7Dbd336b79148AA742883198BBF60342";
  const LEGION = "0xfE8c1ac365bA6780AEc5a985D989b327C27670A1";
  const ATLAS = "0xA0A89db1C899c49F98E6326b764BAFcf167fC2CE";

  const transferTopic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";

  // Get recent Transfer events FROM MAGIC (to find treasury/staking/marketplace)
  let latestBlock = await rpcCall('eth_blockNumber', []);
  let blockNum = parseInt(latestBlock.result, 16);
  let fromBlock = '0x' + Math.max(0, blockNum - 500000).toString(16); // last ~500k blocks

  console.log(`Searching blocks ${parseInt(fromBlock,16)} to ${blockNum}`);

  // Find Transfer events involving MAGIC
  // Filter: Transfer from known users to contracts (to find deposit/staking/marketplace)
  let logs = await rpcCall('eth_getLogs', [{
    address: MAGIC,
    fromBlock: fromBlock,
    toBlock: 'latest',
    topics: [transferTopic],
  }]);

  if (logs && logs.result && logs.result.length > 0) {
    // Collect unique addresses that interact with MAGIC
    let addresses = new Set();
    for (let log of logs.result.slice(0, 100)) {
      let from = '0x' + log.topics[1].slice(26);
      let to = '0x' + log.topics[2].slice(26);
      addresses.add(from);
      addresses.add(to);
    }
    
    console.log(`\nFound ${addresses.size} unique addresses in recent MAGIC transfers`);
    
    // Check which of these are contracts (have code)
    let contracts = [];
    for (let addr of addresses) {
      if (addr === '0x0000000000000000000000000000000000000000') continue;
      let code = await rpcCall('eth_getCode', [addr, 'latest']);
      if (code.result && code.result !== '0x' && code.result.length > 10) {
        contracts.push({ addr, codeLen: code.result.length });
      }
    }
    
    console.log(`\n=== Contract addresses interacting with MAGIC ===`);
    contracts.sort((a,b) => b.codeLen - a.codeLen);
    for (let c of contracts) {
      console.log(`${c.addr} (codeLen=${c.codeLen})`);
    }
  } else {
    console.log("No logs returned or error:", JSON.stringify(logs).substring(0, 500));
  }

  // Also try to read MAGIC symbol/name via eth_call
  console.log("\n=== Reading MAGIC token info ===");
  const symbolCall = await rpcCall('eth_call', [{
    to: MAGIC,
    data: '0x95d89b41' // symbol()
  }, 'latest']);
  console.log("Symbol:", symbolCall.result);

  const nameCall = await rpcCall('eth_call', [{
    to: MAGIC,
    data: '0x06fdde03' // name()
  }, 'latest']);
  console.log("Name hex:", nameCall.result);

  // Try to get Legion name/symbol
  console.log("\n=== Reading Legion info ===");
  const legionName = await rpcCall('eth_call', [{
    to: LEGION,
    data: '0x06fdde03' // name()
  }, 'latest']);
  console.log("Legion name hex:", legionName.result);

  const legionSymbol = await rpcCall('eth_call', [{
    to: LEGION,
    data: '0x95d89b41' // symbol()
  }, 'latest']);
  console.log("Legion symbol hex:", legionSymbol.result);

  const legionTotalSupply = await rpcCall('eth_call', [{
    to: LEGION,
    data: '0x18160ddd' // totalSupply()
  }, 'latest']);
  console.log("Legion totalSupply:", legionTotalSupply.result ? parseInt(legionTotalSupply.result, 16) : 'N/A');

  // Try to get AtlasMine name
  console.log("\n=== Reading AtlasMine info ===");
  const atlasName = await rpcCall('eth_call', [{
    to: ATLAS,
    data: '0x06fdde03' // name()
  }, 'latest']);
  console.log("AtlasMine name hex:", atlasName.result);
  
  const atlasTotalSupply = await rpcCall('eth_call', [{
    to: ATLAS,
    data: '0x18160ddd' // totalSupply()
  }, 'latest']);
  console.log("AtlasMine totalSupply:", atlasTotalSupply.result ? parseInt(atlasTotalSupply.result, 16) : 'N/A');
}

main().catch(console.error);