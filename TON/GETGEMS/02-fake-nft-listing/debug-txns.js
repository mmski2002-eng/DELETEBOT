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
  const NFT_RAW  = '0:EEB32F2ED153E0C9A11D04FAD99EAC5780DD9099E4CA8288C9E699DB4DB90B72';
  const SALE_RAW = '0:4A589C812A154873C54283FAA58AE30AE3D56687BC905BC3910C5E4CA5B965E6';
  const ATK_RAW  = '0:af3c0927c294fd6bd752080b45fd175187660cb41b9a1d1a14876874a25c9539';

  console.log('=== NFT transactions ===');
  const nftTxs = await get(`https://testnet.tonapi.io/v2/blockchain/accounts/${NFT_RAW}/transactions?limit=10`);
  if (nftTxs.transactions) {
    nftTxs.transactions.forEach(t => {
      const cp = t.description?.compute_phase;
      const ap = t.description?.action_phase;
      console.log(`  hash:${t.hash?.slice(0,10)} op:${t.in_msg?.op_code} bounced:${t.in_msg?.bounced} exit:${cp?.exit_code} action_ok:${ap?.success} outs:${t.out_msgs?.length}`);
    });
  } else {
    console.log(JSON.stringify(nftTxs).slice(0, 300));
  }

  console.log('\n=== Sale transactions ===');
  const saleTxs = await get(`https://testnet.tonapi.io/v2/blockchain/accounts/${SALE_RAW}/transactions?limit=10`);
  if (saleTxs.transactions) {
    saleTxs.transactions.forEach(t => {
      const cp = t.description?.compute_phase;
      const ap = t.description?.action_phase;
      console.log(`  hash:${t.hash?.slice(0,10)} op:${t.in_msg?.op_code} bounced:${t.in_msg?.bounced} exit:${cp?.exit_code} action_ok:${ap?.success} outs:${t.out_msgs?.length}`);
    });
  } else {
    console.log(JSON.stringify(saleTxs).slice(0, 300));
  }

  console.log('\n=== Attacker recent transactions ===');
  const atkTxs = await get(`https://testnet.tonapi.io/v2/blockchain/accounts/${ATK_RAW}/transactions?limit=10`);
  if (atkTxs.transactions) {
    atkTxs.transactions.forEach(t => {
      const cp = t.description?.compute_phase;
      console.log(`  hash:${t.hash?.slice(0,10)} op:${t.in_msg?.op_code} exit:${cp?.exit_code} outs:${t.out_msgs?.length}`);
      (t.out_msgs || []).forEach(m => {
        if (m.destination) console.log(`    -> ${m.destination.address?.slice(0,20)} op:${m.op_code}`);
      });
    });
  } else {
    console.log(JSON.stringify(atkTxs).slice(0, 300));
  }
}

main().catch(console.error);
