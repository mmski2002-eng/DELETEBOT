const https = require('https');

function arbiscanGet(params) {
  return new Promise((resolve, reject) => {
    const query = new URLSearchParams(params).toString();
    const url = `https://api.arbiscan.io/api?${query}`;
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); } catch(e) { resolve(data); }
      });
    }).on('error', reject);
  });
}

async function main() {
  // 1. Get MAGIC token source code
  const magic = "0x539bdE0d7Dbd336b79148AA742883198BBF60342";
  let src = await arbiscanGet({ module: 'contract', action: 'getsourcecode', address: magic, apikey: 'W6KI9JX7YVV3I8Q8IRHGZCJJ6AH7GPVXQI' });
  console.log("=== MAGIC Source ===");
  console.log(JSON.stringify(src, null, 2).substring(0, 3000));
}

main().catch(console.error);