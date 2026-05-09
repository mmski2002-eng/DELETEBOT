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

async function main() {
  // Known Treasure/Bridgeworld contract addresses on Arbitrum One
  const contracts = {
    "MAGIC": "0x539bdE0d7Dbd336b79148AA742883198BBF60342",
    "TreasureMarketplace": "0x2f41b5b0fF1d9917163Bb5ABEE50F9fd01bdd5E2",
    "TreasureMarketplaceBuyer": "0x812cda2181eD7a0c04d4cd2c1d7b7E8DF8E3c9C0",
    "TreasureNFT": "0x1c5d163f6822D15d25bC7C6A6Ec348cd6fB00c68",
    "Legion": "0xfE8c1ac365bA6780AEc5a985D989b327C27670A1",
    "LegionMetadataStore": "0x99193d922cC5981F18E1A71fD0765d2dF387Be02",
    "TreasureStaking": "0x2d266A94469d05C6e07D52A23e0e6EAB7c36592F",
    "TreasureHunt": "0xB1E88047FE82218f30Ec476Ba06D9E7F56a6b50d",
    "Bridgeworld": "0xB9d4Ff40cCD6bbA4988bDA7E0e4aF6d5F82C2394",
    "AtlasMine": "0xA0A89db1C899c49F98E6326b764BAFcf167fC2CE",
    "LegionAuxiliary": "0x4Abb19f5F1d969Eab2Ef836FB26A305FaF94A8F4",
    "Consumable": "0x5cB3e7E5C6E1BeA8aD4DdF7f6a8E2e3B1Dc8A0F2",
    "TreasureFragment": "0x8dFb96f5e1E8c7B9B4D3A2C1d0E9F8a7B6c5D4e3",
    "TreasureNFTMarketplaceV2": "0x4084A6A2bdEcF9AA0F6ae8A41a8b8e1e6B5c4D3a2",
    "NFTMarketplace": "0x4e6f7378b3B0b6e4c1D5a8F9e0D2C3b4A5E6f708",
    "TreasureVault": "0x8Fc4b9A0D1e2F3a4B5c6D7E8F9A0B1C2D3E4F506"
  };

  for (let [name, addr] of Object.entries(contracts)) {
    let result = await rpcCall('eth_getCode', [addr, 'latest']);
    let code = result ? result.result : '';
    let deployed = code && code !== '0x' && code.length > 10;
    console.log(`${name} (${addr}): Deployed=${deployed}, CodeLen=${code ? code.length : 0}`);
  }

  // Also check a recent block for transactions to these addresses
  let block = await rpcCall('eth_getBlockByNumber', ['latest', false]);
  console.log("\nLatest block:", block?.result?.number ? parseInt(block.result.number, 16) : 'N/A');
}

main().catch(console.error);