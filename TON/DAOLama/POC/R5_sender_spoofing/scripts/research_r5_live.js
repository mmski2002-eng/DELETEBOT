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

function cellHash(hexBoc) {
  return Cell.fromBoc(Buffer.from(hexBoc, 'hex'))[0].hash().toString('hex');
}

async function main() {
  const txs = await getJson(`https://tonapi.io/v2/blockchain/accounts/${encodeURIComponent(VAULT)}/transactions?limit=${LIMIT}`);
  const withdraws = (txs.transactions || []).filter((tx) => tx.in_msg?.op_code === '0x7bdd97de');
  const senders = [...new Set(withdraws.map((tx) => tx.in_msg.source?.address).filter(Boolean))];

  const senderAccounts = [];
  for (const address of senders) {
    const account = await getJson(`https://tonapi.io/v2/blockchain/accounts/${encodeURIComponent(address)}`);
    senderAccounts.push({
      address,
      balance: String(account.balance),
      code_hash: cellHash(account.code),
      data_hash: cellHash(account.data)
    });
  }

  const perSender = {};
  for (const tx of withdraws) {
    const src = tx.in_msg.source.address;
    const cell = Cell.fromBoc(Buffer.from(tx.in_msg.raw_body, 'hex'))[0];
    const s = cell.beginParse();
    s.loadUint(32);
    s.loadUintBig(64);
    const amount = s.loadCoins().toString();
    const recipient = s.loadAddress().toRawString();

    perSender[src] ||= {
      count: 0,
      recipients: new Set(),
      amounts: []
    };
    perSender[src].count += 1;
    perSender[src].recipients.add(recipient);
    perSender[src].amounts.push(amount);
  }

  const normalizedPerSender = Object.fromEntries(
    Object.entries(perSender).map(([address, value]) => [
      address,
      {
        count: value.count,
        recipient_count: value.recipients.size,
        recipients: [...value.recipients],
        amounts: value.amounts
      }
    ])
  );

  console.log(JSON.stringify({
    vault: VAULT,
    sender_count: senders.length,
    sender_accounts: senderAccounts,
    per_sender: normalizedPerSender
  }, null, 2));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
