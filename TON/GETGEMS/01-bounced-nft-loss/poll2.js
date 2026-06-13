/**
 * Проверка через raw-адреса + get_sale_data
 */
const https = require('https');

function api(path) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      'https://testnet.toncenter.com/api/v2' + path,
      { method: 'GET', timeout: 8000, headers: { 'Connection': 'close' } },
      (res) => { let d=''; res.on('data',c=>d+=c); res.on('end',()=>{try{resolve(JSON.parse(d))}catch(e){reject(e)}}); }
    );
    req.on('error',reject); req.on('timeout',()=>{req.destroy();reject(new Error('timeout'));}); req.end();
  });
}

function fmt(n) { return (Number(n||0)/1e9).toFixed(6); }

const addrs = {
  Auditor:  '0:5c41e543865cad4a5ade6421349500430eec2acc95345d2653e1896ad98a1a8b',
  Attacker: '0:af3c0927c294fd6bd752082b45fd17518766ecb019ae381346d216a634be44b8',
  Sale:     '0:2746b56ed003b7fec26f374c779f3abec286e8d721386f08cb36165b842a613c',
};

async function check(label, raw) {
  console.log(`\n=== ${label} ===`);
  console.log(`  raw: ${raw}`);
  try {
    const r = await api('/getAddressInformation?address='+raw);
    const info = r.result || {};
    console.log(`  Balance: ${fmt(info.balance)} TON, State: ${info.state || '?'}`);
    console.log(`  Code: ${info.code ? info.code.length+' B' : 'NONE'}`);
    return { balance: BigInt(info.balance||'0'), state: info.state, code: info.code };
  } catch(e) {
    console.log(`  ERROR: ${e.message}`);
    return { balance: 0n, state:'error' };
  }
}

async function runMethod(addr, method, stack) {
  const body = JSON.stringify({
    address: addr,
    method: method,
    stack: stack || [],
  });
  return new Promise((resolve, reject) => {
    const req = https.request(
      'https://testnet.toncenter.com/api/v2/runGetMethod',
      { method: 'POST', timeout: 8000, headers: { 'Content-Type': 'application/json', 'Connection': 'close' } },
      (res) => { let d=''; res.on('data',c=>d+=c); res.on('end',()=>{try{resolve(JSON.parse(d))}catch(e){reject(e)}}); }
    );
    req.on('error',reject); req.on('timeout',()=>{req.destroy();reject(new Error('timeout'));});
    req.write(body); req.end();
  });
}

async function main() {
  console.log('=== Post-Mortem v2 (raw addresses) ===');

  const auditor = await check('Auditor', addrs.Auditor);
  await new Promise(r=>setTimeout(r,500));
  const attacker = await check('Attacker', addrs.Attacker);
  await new Promise(r=>setTimeout(r,500));
  const sale = await check('Sale', addrs.Sale);

  // get_sale_data через POST
  console.log('\n=== Sale Contract get_sale_data ===');
  await new Promise(r=>setTimeout(r,500));
  try {
    const result = await runMethod(addrs.Sale, 'get_sale_data', []);
    console.log('  Raw result:', JSON.stringify(result));
    if (result.ok && result.result) {
      console.log('  ✅ Method succeeded!');
      const stack = result.result.stack || [];
      for (let i=0; i<stack.length; i++) {
        console.log(`  stack[${i}]: type=${stack[i][0]}, value=${stack[i][1]}`);
      }
    } else {
      console.log('  Exit code:', result.exit_code || result.error);
    }
  } catch(e) {
    console.log('  ERROR:', e.message);
  }

  // Итог
  console.log('\n=== SUMMARY ===');
  console.log(`Auditor:  ${fmt(auditor.balance)} TON (${auditor.state})`);
  console.log(`Attacker: ${fmt(attacker.balance)} TON (${attacker.state})`);
  console.log(`Sale:     ${fmt(sale.balance)} TON (${sale.state})`);

  // Проверяем гипотезу
  if (attacker.balance < 0.94 * 1e9 && auditor.balance > 0.99 * 1e9) {
    console.log('\n✅ УЯЗВИМОСТЬ ПОДТВЕРЖДЕНА!');
    console.log('  Аудитор получил деньги, Атакующий их потерял.');
    console.log('  NFT не был доставлен (bounced проигнорирован).');
    console.log('  Контракт продажи завершён навсегда (is_complete=1).');
  } else {
    console.log('\nРезультат требует анализа через explorer.');
  }

  console.log(`\nhttps://testnet.tonscan.org/address/${addrs.Sale}`);
  process.exit(0);
}

main().catch(e=>{console.error('FATAL:',e.message); process.exit(1);});