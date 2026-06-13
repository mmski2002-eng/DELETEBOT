const https = require('https');
const { Cell } = require('@ton/core');

const VAULT = '0:a4793bce49307006d3f4e97d815fb4c78ff7655faecf8606111ae29f8d6b41f4';
const LIMIT = 100;

function getJson(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { Accept: 'application/json' } }, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        body += chunk;
      });
      res.on('end', () => {
        if (res.statusCode < 200 || res.statusCode >= 300) {
          reject(new Error(`HTTP ${res.statusCode}: ${body}`));
          return;
        }
        try {
          resolve(JSON.parse(body));
        } catch (err) {
          reject(err);
        }
      });
    }).on('error', reject);
  });
}

function decodeWithdraw(rawBodyHex) {
  const cell = Cell.fromBoc(Buffer.from(rawBodyHex, 'hex'))[0];
  const s = cell.beginParse();
  return {
    opcode: '0x' + s.loadUint(32).toString(16),
    query_id: s.loadUintBig(64).toString(),
    amount: s.loadCoins().toString(),
    recipient: s.loadAddress().toRawString(),
    tail_bits: s.remainingBits,
    tail_refs: s.remainingRefs
  };
}

async function main() {
  const txs = await getJson(`https://tonapi.io/v2/blockchain/accounts/${encodeURIComponent(VAULT)}/transactions?limit=${LIMIT}`);
  const withdraws = (txs.transactions || []).filter((tx) => tx.in_msg?.op_code === '0x7bdd97de');

  const bodyCounts = new Map();
  for (const tx of withdraws) {
    bodyCounts.set(tx.in_msg.raw_body, (bodyCounts.get(tx.in_msg.raw_body) || 0) + 1);
  }

  const duplicates = [...bodyCounts.entries()]
    .filter(([, count]) => count > 1)
    .map(([raw_body, count]) => ({ raw_body, count }));

  const result = {
    vault: VAULT,
    withdraw_count: withdraws.length,
    duplicate_body_count: duplicates.length,
    duplicates,
    withdraws: withdraws.map((tx) => ({
      tx_hash: tx.hash,
      utime: tx.utime,
      source: tx.in_msg.source?.address || null,
      source_is_wallet: tx.in_msg.source?.is_wallet ?? null,
      raw_body: tx.in_msg.raw_body,
      decoded: decodeWithdraw(tx.in_msg.raw_body),
      out0: tx.out_msgs?.[0]
        ? {
            destination: tx.out_msgs[0].destination?.address || null,
            value: String(tx.out_msgs[0].value)
          }
        : null
    }))
  };

  console.log(JSON.stringify(result, null, 2));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
