/**
 * Быстрая проверка балансов через toncenter REST API
 * С принудительным закрытием keep-alive
 */
const https = require('https');
const http = require('http');

function apiGet(path) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      'https://testnet.toncenter.com/api/v2' + path,
      { method: 'GET', timeout: 8000, headers: { 'Connection': 'close' } },
      (res) => {
        let d = '';
        res.on('data', c => d += c);
        res.on('end', () => {
          try { resolve(JSON.parse(d)); }
          catch(e) { reject(new Error('Parse: '+e.message)); }
        });
      }
    );
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    req.end();
  });
}

function fmt(n) { return (Number(n||0)/1e9).toFixed(6); }

async function checkOne(label, addr) {
  console.log(`\n=== ${label} ===`);
  try {
    const r = await apiGet('/getAddressInformation?address='+encodeURIComponent(addr));
    const info = r.result || {};
    console.log(`  Balance: ${fmt(info.balance)} TON, State: ${info.state || '?'}`);
    
    await new Promise(ok => setTimeout(ok, 400));
    const tx = await apiGet('/getTransactions?address='+encodeURIComponent(addr)+'&limit=3');
    for (const t of (tx.result||[])) {
      const h = t.hash || t.transaction_id?.hash || '?';
      const lt = t.lt || t.transaction_id?.lt || '?';
      const v = t.in_msg?.value || '0';
      console.log(`  TX: ${h.substring(0,20)} lt=${lt} in=${fmt(v)}`);
    }
  } catch(e) {
    console.log(`  ERROR: ${e.message}`);
  }
}

async function main() {
  console.log('=== Post-Mortem: Bounced NFT Loss PoC ===');
  await checkOne('Auditor',  'kQBcQeVDhlytSlreZCE0lQBDDuwqzJU0XSZT4Ylq2Yoai2su');
  await checkOne('Attacker', 'kQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuFwc');
  await checkOne('Sale',     'kQAnRrVu0AO3_sJvN0x3nzq-wobo1yE4bwjLNhZbhCphPJ6o');
  console.log('\nExplorer: https://testnet.tonscan.org/address/kQAnRrVu0AO3_sJvN0x3nzq-wobo1yE4bwjLNhZbhCphPJ6o');
  console.log('=== DONE ===');
  process.exit(0);
}

main().catch(e=>{console.error('FATAL:',e.message); process.exit(1);});