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

function codeHashFromBoc(boc) {
  const cell = Cell.fromBoc(Buffer.from(boc, 'hex'))[0];
  return cell.hash().toString('hex');
}

function decodeWithdrawBody(rawBodyHex) {
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
  const vault = await getJson(`https://tonapi.io/v2/blockchain/accounts/${encodeURIComponent(VAULT)}`);
  const txs = await getJson(`https://tonapi.io/v2/blockchain/accounts/${encodeURIComponent(VAULT)}/transactions?limit=${LIMIT}`);

  const withdraws = (txs.transactions || []).filter((tx) => tx.in_msg && tx.in_msg.op_code === '0x7bdd97de');
  const uniqueSenders = [...new Set(withdraws.map((tx) => tx.in_msg.source?.address).filter(Boolean))];

  const senderAccounts = await Promise.all(
    uniqueSenders.map(async (address) => ({
      address,
      account: await getJson(`https://tonapi.io/v2/blockchain/accounts/${encodeURIComponent(address)}`)
    }))
  );

  const summary = {
    vault: {
      address: vault.address,
      balance: String(vault.balance),
      code_hash: codeHashFromBoc(vault.code),
      data_hash: codeHashFromBoc(vault.data)
    },
    withdraw_count: withdraws.length,
    unique_withdraw_senders: uniqueSenders.length,
    sender_accounts: senderAccounts.map(({ address, account }) => ({
      address,
      balance: String(account.balance),
      status: account.status,
      code_hash: codeHashFromBoc(account.code),
      data_hash: codeHashFromBoc(account.data),
      same_code_as_vault: codeHashFromBoc(account.code) === codeHashFromBoc(vault.code)
    })),
    withdraws: withdraws.map((tx) => ({
      tx_hash: tx.hash,
      utime: tx.utime,
      source: tx.in_msg.source?.address || null,
      source_is_wallet: tx.in_msg.source?.is_wallet ?? null,
      inbound_value: String(tx.in_msg.value),
      decoded: decodeWithdrawBody(tx.in_msg.raw_body),
      out_msgs: (tx.out_msgs || []).map((m) => ({
        destination: m.destination?.address || null,
        value: String(m.value),
        op_code: m.op_code || null,
        decoded_op_name: m.decoded_op_name || null
      }))
    }))
  };

  console.log(JSON.stringify(summary, null, 2));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
