const fs = require('fs');
const path = require('path');
const { beginCell, Address, toNano } = require('@ton/core');

const targetPath = path.join(__dirname, '..', 'TARGET_TEMPLATE.json');

function loadTarget() {
  const raw = fs.readFileSync(targetPath, 'utf8');
  return JSON.parse(raw);
}

function requireField(name, value) {
  if (value === undefined || value === null || value === '') {
    throw new Error(`Missing required field in TARGET_TEMPLATE.json: ${name}`);
  }
}

function buildMinimalExecuteBody(cfg) {
  const opHex = cfg.execute_opcode_hex || cfg.withdraw_opcode_hex;
  requireField('execute_opcode_hex or withdraw_opcode_hex', opHex);

  const opcode = Number.parseInt(opHex, 16);
  if (!Number.isFinite(opcode)) {
    throw new Error('opcode hex is not a valid hex number');
  }

  // This is only a generic skeleton.
  // Replace fields once the real body schema is known.
  const body = beginCell()
    .storeUint(opcode, 32)
    .storeUint(0, 64) // query_id placeholder
    .endCell();

  return body;
}

function printSummary(cfg, body) {
  console.log('=== R1 Treasury Auth Probe ===');
  console.log(`Target name: ${cfg.target_name || 'unknown'}`);
  console.log(`Network: ${cfg.network || 'unknown'}`);
  console.log(`Treasury: ${cfg.treasury_address || '<missing>'}`);
  console.log(`Governance: ${cfg.governance_address || '<missing>'}`);
  console.log(`Timelock: ${cfg.timelock_address || '<missing>'}`);
  console.log(`Withdraw opcode: ${cfg.withdraw_opcode_hex || '<missing>'}`);
  console.log(`Execute opcode: ${cfg.execute_opcode_hex || '<missing>'}`);
  console.log(`Body BOC(base64): ${body.toBoc().toString('base64')}`);
  console.log('');
  console.log('Next step: replace the placeholder body layout with the real withdraw/execute schema and send only in a controlled environment.');
}

function main() {
  const cfg = loadTarget();
  const body = buildMinimalExecuteBody(cfg);
  printSummary(cfg, body);
}

main();
