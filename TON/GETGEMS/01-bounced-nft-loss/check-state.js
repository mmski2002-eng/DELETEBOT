/**
 * Проверка состояния кошельков и контракта продажи после PoC
 * Использует REST API Toncenter (не JSON-RPC)
 */
const https = require('https');

function api(path) {
  return new Promise((resolve, reject) => {
    const url = 'https://testnet.toncenter.com/api/v2' + path;
    https.get(url, { timeout: 10000 }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error('Parse error: ' + e.message + ' raw: ' + data.substring(0, 200))); }
      });
    }).on('error', reject).on('timeout', function() { this.destroy(); reject(new Error('timeout')); });
  });
}

function formatTON(nano) {
  return (Number(nano || 0) / 1e9).toFixed(6);
}

async function checkAddress(label, addr) {
  try {
    const info = await api('/getAddressInformation?address=' + encodeURIComponent(addr));
    const r = info.result || {};
    console.log(`[${label}] ${addr}`);
    console.log(`  balance: ${formatTON(r.balance)} TON`);
    console.log(`  state: ${r.state || '?'}`);
    console.log(`  code: ${r.code ? 'YES (' + r.code.length + ' B)' : 'NO (uninitialized)'}`);

    // Transactions
    try {
      const tx = await api('/getTransactions?address=' + encodeURIComponent(addr) + '&limit=3&archival=false');
      const list = tx.result || [];
      if (list.length === 0) {
        console.log('  transactions: 0');
      }
      for (const t of list) {
        const hash = t.hash || (t.transaction_id ? t.transaction_id.hash : '?');
        const lt = t.lt || (t.transaction_id ? t.transaction_id.lt : '?');
        console.log(`  tx: ${hash} | lt=${lt}`);
      }
    } catch (e) {
      console.log(`  transactions: error (${e.message})`);
    }
    console.log('');
    return { balance: BigInt(r.balance || '0'), state: r.state, code: r.code || '' };
  } catch (e) {
    console.log(`[${label}] ERROR: ${e.message}\n`);
    return { balance: 0n, state: 'error', code: '' };
  }
}

async function main() {
  console.log('=== PoC #1: Bounced NFT Loss — State Check ===');
  console.log('Time:', new Date().toISOString());
  console.log('');

  // Селекторы из seed
  const auditorAddr = 'kQBcQeVDhlytSlreZCE0lQBDDuwqzJU0XSZT4Ylq2Yoai2su';
  const attackerAddr = 'kQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuFwc';
  const saleAddr = 'kQBa5r-JfunfwejA5CM7mNXVnSM63qqx9ULhz5CdGCgIBUWw';

  const auditor = await checkAddress('Auditor', auditorAddr);
  const attacker = await checkAddress('Attacker', attackerAddr);
  const sale = await checkAddress('Sale Contract', saleAddr);

  console.log('=== SUMMARY ===');
  console.log(`Auditor balance:  ${formatTON(auditor.balance)} TON (state: ${auditor.state})`);
  console.log(`Attacker balance: ${formatTON(attacker.balance)} TON (state: ${attacker.state})`);
  console.log(`Sale balance:     ${formatTON(sale.balance)} TON (state: ${sale.state})`);

  if (sale.code) {
    console.log('');
    console.log('⭐ Sale contract IS DEPLOYED on testnet!');
    console.log(`Explorer: https://testnet.tonscan.org/address/${saleAddr}`);
  } else {
    console.log('');
    console.log('⚠️ Sale contract NOT YET deployed.');
  }

  process.exit(0);
}

main().catch(e => { console.error('FATAL:', e.message); process.exit(1); });