const https = require('https');

function get(url) {
  return new Promise((res, rej) => {
    https.get(url, { headers: { 'Accept': 'application/json' } }, r => {
      let d = '';
      r.on('data', c => d += c);
      r.on('end', () => {
        try { res(JSON.parse(d)); } catch(e) { res({ _raw: d }); }
      });
    }).on('error', rej);
  });
}

async function main() {
  // 1. Check auditor collection items for sale data
  console.log('=== Auditor collection items ===');
  const col = await get('https://testnet.tonapi.io/v2/nfts/collections/0:665807b02b8322a502cdbb921fa17164f91789bcc85098e3e5184dcccae4d026/items?limit=20');
  if (col.nft_items) {
    col.nft_items.forEach(n => {
      const sale = n.sale;
      if (sale) {
        console.log('NFT:', n.address);
        console.log('  sale.address:', sale.address);
        console.log('  sale.market.address:', sale.market?.address);
        console.log('  sale.market.name:', sale.market?.name);
      }
    });
    console.log('Total items:', col.nft_items.length);
  } else {
    console.log(JSON.stringify(col).slice(0, 200));
  }

  // 2. Check the suspected address
  console.log('\n=== Suspected marketplace: 0:20e1497... ===');
  const acc = await get('https://testnet.tonapi.io/v2/accounts/0:20e1497334f5859244b28afca721b99bc4ca6015613ce43bb21f342fe9b4e5a7');
  console.log(JSON.stringify(acc, null, 2));

  // 3. Check MARKETPLACE_FEE_ADDRESS from our scripts
  console.log('\n=== Fee address EQDDuxx7... ===');
  const fee = await get('https://testnet.tonapi.io/v2/accounts/0:0cebb9c7b6b6dcd775184f396b4b081e9e065686bb38a6c01a7e28dcb1d1fa4e');
  console.log(JSON.stringify(fee, null, 2));

  // 4. Search for any sale contracts in recent blockchain events
  console.log('\n=== Recent NFT sales on testnet ===');
  const sales = await get('https://testnet.tonapi.io/v2/nfts?collection=&limit=50&offset=0&is_on_sale=true');
  if (sales.nft_items) {
    const seen = new Set();
    sales.nft_items.forEach(n => {
      if (n.sale?.market?.address) {
        seen.add(n.sale.market.address);
      }
    });
    console.log('Marketplace addresses found:', [...seen]);
    if (sales.nft_items[0]?.sale) {
      console.log('First sale:', JSON.stringify(sales.nft_items[0].sale, null, 2));
    }
  } else {
    console.log(JSON.stringify(sales).slice(0, 300));
  }
}

main().catch(console.error);
