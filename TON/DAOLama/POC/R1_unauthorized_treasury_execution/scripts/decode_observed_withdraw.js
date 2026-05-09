const fs = require('fs');
const { Cell } = require('@ton/core');

function loadJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
}

function main() {
  const data = loadJson('vault_txs.json');
  const tx = data.transactions.find((t) => t.in_msg && t.in_msg.op_code === '0x7bdd97de');

  if (!tx) {
    throw new Error('Observed withdraw tx not found');
  }

  const cell = Cell.fromBoc(Buffer.from(tx.in_msg.raw_body, 'hex'))[0];
  const s = cell.beginParse();

  const opcode = '0x' + s.loadUint(32).toString(16);
  const queryId = s.loadUintBig(64).toString();
  const amount = s.loadCoins().toString();
  const recipient = s.loadAddress().toRawString();

  console.log(JSON.stringify({
    tx_hash: tx.hash,
    source: tx.in_msg.source.address,
    vault: tx.in_msg.destination.address,
    opcode,
    query_id: queryId,
    amount,
    recipient,
    out_msgs: (tx.out_msgs || []).map((m) => ({
      destination: m.destination?.address || null,
      value: String(m.value),
      op_code: m.op_code || null,
      decoded_op_name: m.decoded_op_name || null
    })),
    remaining_bits_after_recipient: s.remainingBits
  }, null, 2));
}

main();
