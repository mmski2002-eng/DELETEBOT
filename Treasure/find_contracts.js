const https = require('https');

function rpcCall(method, params) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ jsonrpc: '2.0', method, params, id: 1 });
    const req = https.request({
      hostname: 'arb1.arbitrum.io',
      path: '/rpc',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': body.length }
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); } catch(e) { resolve(data); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function arbiscanGet(params) {
  return new Promise((resolve, reject) => {
    const query = new URLSearchParams(params).toString();
    // Try the api endpoint with apikey
    const url = `https://api.arbiscan.io/api?${query}&apikey=W6KI9JX7YVV3I8Q8IRHGZCJJ6AH7GPVXQI`;
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); } catch(e) { resolve(data.substring(0, 500)); }
      });
    }).on('error', reject);
  });
}

async function main() {
  // MAGIC token - confirmed deployed
  const MAGIC = "0x539bdE0d7Dbd336b79148AA742883198BBF60342";

  // Let's try getting MAGIC's source code from Arbiscan
  console.log("=== Getting MAGIC source code ===");
  let src = await arbiscanGet({ module: 'contract', action: 'getsourcecode', address: MAGIC });
  console.log(JSON.stringify(src, null, 2).substring(0, 2000));

  // Let's also try using etherscan v2 API format  
  console.log("\n=== Trying v2 API ===");
  let v2result = await new Promise((resolve) => {
    const url = `https://api.arbiscan.io/v2/api?chainid=42161&module=contract&action=getsourcecode&address=${MAGIC}&apikey=W6KI9JX7YVV3I8Q8IRHGZCJJ6AH7GPVXQI`;
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data.substring(0, 500)));
    }).on('error', (e) => resolve('Error: ' + e.message));
  });
  console.log("V2 result:", v2result);
}

main().catch(console.error);