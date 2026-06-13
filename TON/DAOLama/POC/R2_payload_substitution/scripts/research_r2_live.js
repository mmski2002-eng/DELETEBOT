const https = require('https');

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

async function main() {
  const txs = await getJson(`https://tonapi.io/v2/blockchain/accounts/${encodeURIComponent(VAULT)}/transactions?limit=${LIMIT}`);

  const grouped = new Map();
  for (const tx of txs.transactions || []) {
    const op = tx.in_msg?.op_code || null;
    const decoded = tx.in_msg?.decoded_op_name || null;
    const key = `${op}|${decoded}`;
    const value = grouped.get(key) || {
      count: 0,
      wallet_senders: 0,
      contract_senders: 0,
      samples: []
    };
    value.count += 1;
    if (tx.in_msg?.source?.is_wallet) {
      value.wallet_senders += 1;
    } else {
      value.contract_senders += 1;
    }
    if (value.samples.length < 5) {
      value.samples.push({
        tx_hash: tx.hash,
        utime: tx.utime,
        source: tx.in_msg?.source?.address || null,
        op,
        decoded,
        out_ops: (tx.out_msgs || []).map((m) => m.decoded_op_name || m.op_code || null).filter(Boolean)
      });
    }
    grouped.set(key, value);
  }

  console.log(JSON.stringify(Object.fromEntries(grouped), null, 2));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
