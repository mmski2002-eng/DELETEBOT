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

// Decode hex string to ASCII
function hexToAscii(hex) {
  if (!hex || hex === '0x') return 'N/A';
  // Remove 0x and leading zeros/offset
  let data = hex.slice(2);
  // First 32 bytes might be an offset for strings
  if (data.length > 128) {
    // Try to parse as ABI-encoded string (offset + length + data)
    let offset = parseInt(data.slice(0, 64), 16) * 2;
    let len = parseInt(data.slice(offset, offset + 64), 16) * 2;
    let str = data.slice(offset + 64, offset + 64 + len);
    let result = '';
    for (let i = 0; i < str.length; i += 2) {
      result += String.fromCharCode(parseInt(str.slice(i, i+2), 16));
    }
    return result;
  }
  let result = '';
  for (let i = 0; i < data.length; i += 2) {
    let code = parseInt(data.slice(i, i+2), 16);
    if (code > 0) result += String.fromCharCode(code);
  }
  return result;
}

async function getContractName(addr) {
  let nameHex = await rpcCall('eth_call', [{ to: addr, data: '0x06fdde03' }, 'latest']);
  let name = hexToAscii(nameHex.result || '');
  if (name && name !== 'N/A' && name.length > 1 && name.length < 100) return name;
  
  // Try symbol
  let symHex = await rpcCall('eth_call', [{ to: addr, data: '0x95d89b41' }, 'latest']);
  let sym = hexToAscii(symHex.result || '');
  if (sym && sym !== 'N/A' && sym.length > 1 && sym.length < 50) return sym;
  
  return null;
}

async function main() {
  const MAGIC = "0x539bdE0d7Dbd336b79148AA742883198BBF60342";
  const LEGION = "0xfE8c1ac365bA6780AEc5a985D989b327C27670A1";
  const ATLAS = "0xA0A89db1C899c49F98E6326b764BAFcf167fC2CE";

  // Try eth_getLogs with smaller block range (10k blocks)
  let latestBlock = await rpcCall('eth_blockNumber', []);
  let blockNum = parseInt(latestBlock.result, 16);
  
  const transferTopic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";
  
  // Try small ranges
  for (let end = blockNum; end > blockNum - 100000; end -= 10000) {
    let start = end - 10000;
    let fromBlock = '0x' + start.toString(16);
    let toBlock = '0x' + end.toString(16);
    
    let logs = await rpcCall('eth_getLogs', [{
      address: MAGIC,
      fromBlock,
      toBlock,
      topics: [transferTopic],
    }]);
    
    if (logs && logs.result && logs.result.length > 0) {
      let addresses = new Set();
      for (let log of logs.result) {
        let from = '0x' + log.topics[1].slice(26);
        let to = '0x' + log.topics[2].slice(26);
        addresses.add(from);
        addresses.add(to);
      }
      
      // Check which are contracts
      for (let addr of addresses) {
        if (addr === '0x0000000000000000000000000000000000000000') continue;
        let code = await rpcCall('eth_getCode', [addr, 'latest']);
        if (code.result && code.result !== '0x' && code.result.length > 10) {
          let name = await getContractName(addr);
          console.log(`Contract: ${addr} | Name: ${name || 'N/A'} | CodeLen: ${code.result.length}`);
        }
      }
      
      // Found some logs, stop after first range with results
      console.log(`Found ${logs.result.length} logs in blocks ${start}-${end}`);
      break;
    }
  }
  
  // Also specifically check AtlasMine interface functions
  console.log("\n=== AtlasMine specific checks ===");
  
  // Try owner()
  let owner = await rpcCall('eth_call', [{ to: ATLAS, data: '0x8da5cb5b' }, 'latest']);
  console.log("AtlasMine owner:", owner.result);
  
  // Try various known function selectors
  const selectors = {
    'totalSupply()': '0x18160ddd',
    'balanceOf(address)': '0x70a08231' + '000000000000000000000000' + MAGIC.slice(2),
    'ownerOf(uint256)': '0x6352211e' + '0000000000000000000000000000000000000000000000000000000000000001',
    'tokenURI(uint256)': '0xc87b56dd' + '0000000000000000000000000000000000000000000000000000000000000001',
    'paused()': '0x5c975abb',
    'stakingToken()': '0x72f702f3',
    'rewardToken()': '0xf7c618c9',
    'getReward()': '0x3d18b912',
    'earned(address)': '0x008cc262' + '000000000000000000000000' + MAGIC.slice(2),
  };
  
  for (let [sig, data] of Object.entries(selectors)) {
    let result = await rpcCall('eth_call', [{ to: ATLAS, data }, 'latest']);
    console.log(`AtlasMine.${sig}: ${result.result ? result.result.substring(0, 100) : result.error?.message || 'N/A'}`);
  }
}

main().catch(console.error);