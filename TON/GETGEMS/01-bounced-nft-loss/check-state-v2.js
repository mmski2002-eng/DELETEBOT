/**
 * v2: Проверка с правильным парсингом toncenter REST API
 * + показывает детали транзакций
 */
const https = require('https');

function api(path) {
  return new Promise((resolve, reject) => {
    https.get('https://testnet.toncenter.com/api/v2' + path, { timeout: 10000 }, (res) => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        try { resolve(JSON.parse(d)); }
        catch(e) { reject(new Error('Parse: ' + e.message)); }
      });
    }).on('error', reject).on('timeout', function() { this.destroy(); reject(new Error('timeout')); });
  });
}

function fmt(n) { return (Number(n || 0) / 1e9).toFixed(6); }

async function check(label, addr) {
  console.log(`\n=== ${label} ===`);
  console.log(`Addr: ${addr}`);
  try {
    const i = await api('/getAddressInformation?address=' + encodeURIComponent(addr));
    const r = i.result || {};
    console.log(`  Balance: ${fmt(r.balance)} TON`);
    console.log(`  State: ${r.state}`);

    const tx = await api('/getTransactions?address=' + encodeURIComponent(addr) + '&limit=5');
    const list = tx.result || [];
    console.log(`  TX count: ${list.length}`);
    for (const t of list) {
      const hash = t.hash || t.transaction_id?.hash || '?';
      const lt = t.lt || t.transaction_id?.lt || '?';
      const utime = t.utime || t.transaction_id?.now || 0;
      const time = utime ? new Date(utime * 1000).toISOString() : '?';
      // Check if it has in_msg
      const inMsg = t.in_msg;
      const outMsgs = t.out_msgs || [];
      const inValue = inMsg?.value || '0';
      console.log(`  ── ${hash.substring(0,16)}... lt=${lt} time=${time}`);
      console.log(`     in_value: ${fmt(inValue)} TON, out_count: ${outMsgs.length}`);
      if (outMsgs.length > 0) {
        for (let j = 0; j < Math.min(outMsgs.length, 4); j++) {
          const om = outMsgs[j];
          console.log(`     out[${j}]: to=${(om.destination||'?').substring(0,30)}... value=${fmt(om.value||'0')}`);
        }
      }
    }
  } catch(e) {
    console.log(`  ERROR: ${e.message}`);
  }
}

async function main() {
  console.log('=== PoC #1 State Check v2 ===');

  await check('Auditor', 'kQBcQeVDhlytSlreZCE0lQBDDuwqzJU0XSZT4Ylq2Yoai2su');
  // Small delay to avoid rate limit
  await new Promise(r => setTimeout(r, 500));
  await check('Attacker', 'kQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuFwc');
  await new Promise(r => setTimeout(r, 500));
  await check('Sale Contract', 'kQBa5r-JfunfwejA5CM7mNXVnSM63qqx9ULhz5CdGCgIBUWw');

  console.log('\n=== DONE ===');
  process.exit(0);
}

main().catch(e => { console.error('FATAL:', e); process.exit(1); });