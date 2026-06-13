/**
 * Детальный анализ транзакций контракта продажи (fixed msg_data)
 */
const https = require('https');

function api(path) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      'https://testnet.toncenter.com/api/v2' + path,
      { method: 'GET', timeout: 8000, headers: { 'Connection': 'close' } },
      (res) => { let d=''; res.on('data',c=>d+=c); res.on('end',()=>{try{resolve(JSON.parse(d))}catch(e){reject(e)}}); }
    );
    req.on('error',reject); req.on('timeout',()=>{req.destroy();reject(new Error('timeout'));});
    req.end();
  });
}

function fmt(n) { return (Number(n||0)/1e9).toFixed(6); }

function runMethod(addr, method, stack) {
  const body = JSON.stringify({ address: addr, method, stack: stack || [] });
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

function safeStr(x) { return typeof x === 'string' ? x : JSON.stringify(x); }

const SALE_RAW = '0:2746b56ed003b7fec26f374c779f3abec286e8d721386f08cb36165b842a613c';

async function main() {
  console.log('=== Transaction Trace: Sale Contract ===\n');

  console.log('Last 5 transactions:');
  const tx = await api('/getTransactions?address=' + SALE_RAW + '&limit=5&archival=false');
  const list = tx.result || [];
  console.log(`Count: ${list.length}\n`);

  for (let i = 0; i < list.length; i++) {
    const t = list[i];
    const hash = t.hash || t.transaction_id?.hash || '?';
    const lt = t.lt || t.transaction_id?.lt || '?';
    const utime = t.utime || t.transaction_id?.now || 0;
    const time = utime ? new Date(utime * 1000).toISOString() : '?';
    
    console.log(`─── TX #${i} ───`);
    console.log(`  hash: ${hash}`);
    console.log(`  lt:   ${lt}`);
    console.log(`  time: ${time}`);
    
    // in_msg
    const inMsg = t.in_msg;
    if (inMsg) {
      console.log(`  IN msg:`);
      console.log(`    source: ${inMsg.source || '?'}`);
      console.log(`    destination: ${inMsg.destination || '?'}`);
      console.log(`    value: ${fmt(inMsg.value)} TON`);
      console.log(`    fwd_fee: ${fmt(inMsg.fwd_fee)} TON`);
      console.log(`    ihr_fee: ${fmt(inMsg.ihr_fee)} TON`);
      console.log(`    created_lt: ${inMsg.created_lt}`);
      if (inMsg.msg_data) {
        console.log(`    msg_data: ${safeStr(inMsg.msg_data).substring(0, 200)}`);
      }
      if (inMsg.body) {
        console.log(`    body: ${safeStr(inMsg.body).substring(0, 200)}`);
      }
    }

    // out_msgs
    const outMsgs = t.out_msgs || [];
    console.log(`  OUT msgs: ${outMsgs.length}`);
    for (let j = 0; j < Math.min(outMsgs.length, 5); j++) {
      const om = outMsgs[j];
      console.log(`    [${j}]:`);
      console.log(`      to: ${(om.destination || '?').substring(0, 64)}`);
      console.log(`      value: ${fmt(om.value)} TON`);
      console.log(`      fwd_fee: ${fmt(om.fwd_fee)} TON`);
      console.log(`      bounce: ${om.bounce}`);
      console.log(`      bounced: ${om.bounced}`);
      if (om.msg_data) {
        console.log(`      msg_data: ${safeStr(om.msg_data).substring(0, 120)}`);
      }
    }

    // compute_ph
    if (t.compute_ph) {
      console.log(`  COMPUTE:`);
      console.log(`    exit_code: ${t.compute_ph.exit_code}`);
      console.log(`    success: ${t.compute_ph.success}`);
      console.log(`    gas_used: ${t.compute_ph.gas_used}`);
      console.log(`    gas_fees: ${fmt(t.compute_ph.gas_fees)} TON`);
      console.log(`    mode: ${t.compute_ph.mode}`);
    }

    // storage_ph
    if (t.storage_ph) {
      console.log(`  STORAGE:`);
      console.log(`    fees: ${fmt(t.storage_ph.storage_fees_collected || 0)} TON`);
    }

    // action
    if (t.action) {
      console.log(`  ACTION:`);
      console.log(`    success: ${t.action.success}`);
      console.log(`    valid: ${t.action.valid}`);
      console.log(`    result_code: ${t.action.result_code}`);
      console.log(`    total_fwd_fees: ${fmt(t.action.total_fwd_fees)} TON`);
    }

    // aborted
    if (t.aborted) {
      console.log(`  ⚠️ ABORTED: ${t.aborted}`);
    }

    console.log('');
  }

  // get_sale_data через raw
  console.log('=== get_sale_data ===');
  const method = await runMethod(SALE_RAW, 'get_sale_data', []);
  console.log(JSON.stringify(method, null, 2));
  if (method.ok && method.result) {
    const stack = method.result.stack || [];
    console.log('\nParsed stack:');
    for (let i = 0; i < stack.length; i++) {
      const [type, val] = stack[i];
      console.log(`  [${i}] ${type}: ${val}`);
      if (type === 'num') {
        const n = BigInt(val);
        console.log(`       dec: ${n.toString()}, bin: ${n.toString(2)}`);
      }
    }
  }

  console.log('\n=== DONE ===');
  process.exit(0);
}

main().catch(e => { console.error('FATAL:', e.message); process.exit(1); });