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

function hexToAscii(hex) {
  if (!hex || hex === '0x' || hex === '0x0000000000000000000000000000000000000000000000000000000000000000') return '';
  let data = hex.slice(2);
  if (data.length >= 128) {
    let offset = parseInt(data.slice(0, 64), 16) * 2;
    if (offset < data.length && offset >= 0) {
      let len = parseInt(data.slice(offset, offset + 64), 16) * 2;
      let str = data.slice(offset + 64, offset + 64 + len);
      let result = '';
      for (let i = 0; i < str.length; i += 2) {
        result += String.fromCharCode(parseInt(str.slice(i, i+2), 16));
      }
      return result;
    }
  }
  let result = '';
  for (let i = 0; i < data.length; i += 2) {
    let code = parseInt(data.slice(i, i+2), 16);
    if (code >= 32 && code < 127) result += String.fromCharCode(code);
  }
  return result;
}

async function identifyContract(addr) {
  const sigs = [
    ['name()', '0x06fdde03'],
    ['symbol()', '0x95d89b41'],
    ['owner()', '0x8da5cb5b'],
    ['paused()', '0x5c975abb'],
    ['totalSupply()', '0x18160ddd'],
    ['implementation()', '0x5c60da1b'],
    ['governor()', '0x0c340a3d'],
    ['stakingToken()', '0x72f702f3'],
    ['rewardsToken()', '0xf7c618c9'],
    ['totalStaked()', '0x917cb3e6'],
    ['treasure()', '0xe520fc7e'],
    ['magic()', '0x6b8ff89a'],
    ['nft()', '0x47e7ef24'],
    ['legion()', '0x22bf9ad5'],
  ];
  
  let info = {};
  for (let [sig, data] of sigs) {
    let result = await rpcCall('eth_call', [{ to: addr, data }, 'latest']);
    if (result.result && result.result !== '0x' && result.result !== '0x0000000000000000000000000000000000000000000000000000000000000000') {
      // Check if it's an address (exactly 32 bytes, starts with zeros)
      if (result.result.length === 66 && result.result.startsWith('0x000000000000000000000000')) {
        info[sig] = '0x' + result.result.slice(26);
      } else {
        let ascii = hexToAscii(result.result);
        info[sig] = ascii || result.result.substring(0, 50);
      }
    }
  }
  return info;
}

async function main() {
  // Large contracts found in MAGIC interactions
  const targets = [
    "0x1106db7165a8d4a8559b441ecdee14a5d5070dbc",
    "0xc24781775bd229d17f39f893f4045a07b2cdf301",
    "0xc8988dc23cd5b14191f8772f04daab7078b3cada",
    "0x59d72ddb29da32847a4665d08ffc8464a7185fae",
    "0xa93b88e2de4901c99d9a1b9fb56d1b2e10b2b6a7",
    "0x09ad820aac5779683b481c4674208a4e1b024afa",
    "0x3e21153ed7697b645ed1c7147720719487113314",
    "0x0d89dfde29bb0ed61f3eb2f9a6be6d0c705cbd52",
    "0xb92fe925dc43a0ecde6c8b1a2709c170ec4fff4f",
    "0x6b0f850f25c72278c50715928d81750a87dc015c",
    "0xdb6f1920a889355780af7570773609bd8cb1f498",
    // Try known Treasure addresses from docs
    "0x2f41b5b0fF1d9917163Bb5ABEE50F9fd01bdd5E2", // Marketplace v1?
    "0x812cda2181eD7a0c04d4cd2c1d7b7E8DF8E3c9C0", // Marketplace v2?
    "0x13a65B9eB15b52f1C4203442Ac4bE38615eF9209", // Known Trove address
    "0x1c5d163f6822D15d25bC7C6A6Ec348cd6fB00c68", // TreasureNFT?
  ];

  for (let addr of targets) {
    let info = await identifyContract(addr);
    if (Object.keys(info).length > 0) {
      console.log(`\n${addr}:`);
      for (let [k, v] of Object.entries(info)) {
        console.log(`  ${k} = ${v}`);
      }
    }
  }
  
  // Also look for Legion Transfer events to find Bridgeworld contracts
  console.log("\n\n=== Legion recent transfers ===");
  const LEGION = "0xfE8c1ac365bA6780AEc5a985D989b327C27670A1";
  const transferTopic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";
  let latestBlock = await rpcCall('eth_blockNumber', []);
  let blockNum = parseInt(latestBlock.result, 16);
  
  let logs = await rpcCall('eth_getLogs', [{
    address: LEGION,
    fromBlock: '0x' + (blockNum - 50000).toString(16),
    toBlock: 'latest',
    topics: [transferTopic],
  }]);
  
  if (logs && logs.result && logs.result.length > 0) {
    let addresses = new Set();
    for (let log of logs.result.slice(0, 50)) {
      let from = '0x' + log.topics[1].slice(26);
      let to = '0x' + log.topics[2].slice(26);
      addresses.add(from);
      addresses.add(to);
    }
    
    console.log(`Found ${addresses.size} unique addresses`);
    for (let addr of addresses) {
      if (addr === '0x0000000000000000000000000000000000000000') continue;
      let code = await rpcCall('eth_getCode', [addr, 'latest']);
      if (code.result && code.result !== '0x' && code.result.length > 10) {
        let info = await identifyContract(addr);
        console.log(`Contract: ${addr} | Info: ${JSON.stringify(info)}`);
      }
    }
  }
}

main().catch(console.error);