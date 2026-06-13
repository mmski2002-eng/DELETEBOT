const https = require('https');

function get(url) {
  return new Promise((res, rej) => {
    https.get(url, { headers: { Accept: 'application/json' } }, r => {
      let d = '';
      r.on('data', c => d += c);
      r.on('end', () => { try { res(JSON.parse(d)); } catch(e) { res({ _raw: d }); } });
    }).on('error', rej);
  });
}

async function main() {
  const ATK = '0:af3c0927c294fd6bd752080b45fd175187660cb41b9a1d1a14876874a25c9539';

  // Get attacker wallet transactions
  console.log('=== Attacker txs ===');
  const txs = await get(`https://testnet.tonapi.io/v2/blockchain/accounts/${ATK}/transactions?limit=30`);
  console.log('total:', txs.transactions?.length, 'raw:', Object.keys(txs));
  if (txs.transactions) {
    txs.transactions.slice(0, 15).forEach(t => {
      const outs = (t.out_msgs || []).map(m => `${m.destination?.address?.slice(0,16) || '?'} init=${!!m.init}`);
      console.log(`  hash:${t.hash?.slice(0,12)} op:${t.in_msg?.op_code} out:[${outs.join(', ')}]`);
    });
  }

  // Check attacker NFTs
  console.log('\n=== Attacker NFTs ===');
  const nfts = await get(`https://testnet.tonapi.io/v2/accounts/${ATK}/nfts?limit=20`);
  if (nfts.nft_items) {
    nfts.nft_items.forEach(n => {
      console.log('nft:', n.address, 'sale:', n.sale?.address || 'none');
      if (n.sale) console.log('  market:', n.sale.market?.address);
    });
  } else {
    console.log(JSON.stringify(nfts).slice(0, 300));
  }

  // Check if any of the attacker's deployed contracts are sale contracts
  console.log('\n=== GetGems testnet marketplace ===');
  const mp = await get('https://testnet.tonapi.io/v2/accounts/0:59a76b59f5651940ff0080bda050791d2507bef0dc8070592c9f72fb75c67160');
  console.log(JSON.stringify(mp, null, 2));

  // Try to find fixed price sales by looking at collection items
  // Use a known GetGems testnet collection
  console.log('\n=== Scanning collections for fixed price sales ===');
  const cols = await get('https://testnet.tonapi.io/v2/nfts/collections?limit=20');
  if (cols.nft_collections) {
    for (const c of cols.nft_collections.slice(0, 5)) {
      const items = await get(`https://testnet.tonapi.io/v2/nfts/collections/${c.address}/items?limit=10`);
      if (items.nft_items) {
        const withSale = items.nft_items.filter(n => n.sale);
        if (withSale.length > 0) {
          console.log('Collection:', c.address, 'name:', c.metadata?.name);
          withSale.forEach(n => {
            console.log('  nft:', n.address);
            console.log('  sale type (tonapi interface):', JSON.stringify(n.sale).slice(0, 200));
          });
        }
      }
    }
  } else {
    console.log(JSON.stringify(cols).slice(0, 300));
  }
}

main().catch(console.error);
