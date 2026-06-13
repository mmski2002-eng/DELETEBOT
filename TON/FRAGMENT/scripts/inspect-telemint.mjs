import fs from 'node:fs';
import path from 'node:path';
import { Address, Cell } from '@ton/core';

const OP_DEPLOY = 0x4637289a;
const OP_DEPLOY_V2 = 0x4637289b;

function usage() {
  console.error(`Usage:
  node scripts/inspect-telemint.mjs decode <payload-or-json-path>
  node scripts/inspect-telemint.mjs compare <payload-or-json-path-a> <payload-or-json-path-b>`);
  process.exit(1);
}

function fail(message) {
  console.error(`Error: ${message}`);
  process.exit(1);
}

function toUtf8(buffer) {
  return new TextDecoder().decode(buffer);
}

function formatCoins(value) {
  return `${value.toString()} nanotons`;
}

function formatAddress(address) {
  if (!address) {
    return null;
  }

  if (address instanceof Address) {
    return address.toString();
  }

  return address.toString();
}

function sha256Hex(cell) {
  return cell.hash().toString('hex');
}

function readInput(source) {
  if (!source) {
    usage();
  }

  if (!fs.existsSync(source)) {
    return {
      kind: 'payload',
      payload: source.trim(),
      raw: source.trim(),
    };
  }

  const raw = fs.readFileSync(source, 'utf8');
  const trimmed = raw.trim();

  if (source.endsWith('.json') || trimmed.startsWith('{')) {
    const parsed = JSON.parse(raw);
    const message = parsed?.messages?.[0];
    const payload = message?.payload ?? parsed?.payload;

    if (!payload) {
      fail(`No payload found in JSON file: ${source}`);
    }

    return {
      kind: 'json',
      payload: payload.trim(),
      raw,
      json: parsed,
      source: path.resolve(source),
      destination: message?.address ?? parsed?.address ?? null,
      amount: message?.amount ?? parsed?.amount ?? null,
      validUntil: parsed?.validUntil ?? null,
    };
  }

  return {
    kind: 'payload',
    payload: trimmed,
    raw,
    source: path.resolve(source),
  };
}

function loadRootCell(payload) {
  return Cell.fromBase64(payload);
}

function parseTelemintText(slice) {
  const len = slice.loadUint(8);
  const bytes = slice.loadBuffer(len);
  return {
    length: len,
    text: toUtf8(bytes),
    hex: bytes.toString('hex'),
  };
}

function parseAuctionConfig(cell) {
  const slice = cell.beginParse();
  return {
    beneficiary_address: formatAddress(slice.loadAddress()),
    initial_min_bid: formatCoins(slice.loadCoins()),
    max_bid: formatCoins(slice.loadCoins()),
    min_bid_step: slice.loadUint(8),
    min_extend_time: slice.loadUint(32),
    duration: slice.loadUint(32),
    cell_hash: sha256Hex(cell),
  };
}

function parseRoyalty(cell) {
  if (!cell) {
    return null;
  }

  return {
    cell_hash: sha256Hex(cell),
  };
}

function parseRestrictions(cell) {
  if (!cell) {
    return {
      present: false,
      force_sender_address: null,
      rewrite_sender_address: null,
      sender_bound: false,
      sender_rewritten: false,
      cell_hash: null,
    };
  }

  const slice = cell.beginParse();
  const hasForce = slice.loadBit();
  const forceSender = hasForce ? slice.loadAddress() : null;
  const hasRewrite = slice.loadBit();
  const rewriteSender = hasRewrite ? slice.loadAddress() : null;

  return {
    present: true,
    force_sender_address: formatAddress(forceSender),
    rewrite_sender_address: formatAddress(rewriteSender),
    sender_bound: hasForce,
    sender_rewritten: hasRewrite,
    cell_hash: sha256Hex(cell),
  };
}

function parseDeployPayload(payload) {
  const root = loadRootCell(payload);
  const slice = root.beginParse();
  const op = slice.loadUint(32);

  if (op !== OP_DEPLOY && op !== OP_DEPLOY_V2) {
    fail(`Unsupported opcode 0x${op.toString(16)}`);
  }

  const signature = slice.loadBuffer(64).toString('hex');
  const subwalletId = slice.loadUint(32);
  const validSince = slice.loadUint(32);
  const validTill = slice.loadUint(32);
  const tokenName = parseTelemintText(slice);
  const content = slice.loadRef();
  const auctionConfig = slice.loadRef();
  const royalty = slice.loadMaybeRef();

  let restrictions = null;
  if (op === OP_DEPLOY_V2) {
    restrictions = slice.loadMaybeRef();
  }

  const parsedRestrictions = parseRestrictions(restrictions);

  return {
    op,
    op_name: op === OP_DEPLOY ? 'telemint_msg_deploy' : 'telemint_msg_deploy_v2',
    root_hash: sha256Hex(root),
    signature,
    subwallet_id: subwalletId,
    valid_since: validSince,
    valid_till: validTill,
    token_name: tokenName.text,
    token_name_hex: tokenName.hex,
    content_cell_hash: sha256Hex(content),
    auction_config: parseAuctionConfig(auctionConfig),
    royalty: parseRoyalty(royalty),
    restrictions: parsedRestrictions,
    sender_binding_present: parsedRestrictions.sender_bound,
  };
}

function summarizeInput(input, decoded) {
  return {
    source: input.source ?? null,
    input_kind: input.kind,
    destination: input.destination ?? null,
    amount: input.amount ?? null,
    valid_until: input.validUntil ?? null,
    payload_base64: input.payload,
    payload_sha256: decoded.root_hash,
    decoded,
  };
}

function compareInputs(a, b) {
  const payloadEqual = a.payload === b.payload;
  const decodedA = parseDeployPayload(a.payload);
  const decodedB = parseDeployPayload(b.payload);

  return {
    payload_equal: payloadEqual,
    same_opcode: decodedA.op === decodedB.op,
    same_signature: decodedA.signature === decodedB.signature,
    same_token_name: decodedA.token_name === decodedB.token_name,
    same_auction_config: decodedA.auction_config.cell_hash === decodedB.auction_config.cell_hash,
    same_restrictions: decodedA.restrictions.cell_hash === decodedB.restrictions.cell_hash,
    sender_binding_a: decodedA.restrictions.force_sender_address,
    sender_binding_b: decodedB.restrictions.force_sender_address,
    decoded_a: summarizeInput(a, decodedA),
    decoded_b: summarizeInput(b, decodedB),
  };
}

const [, , command, ...args] = process.argv;

if (!command) {
  usage();
}

if (command === 'decode') {
  if (args.length !== 1) {
    usage();
  }

  const input = readInput(args[0]);
  const decoded = parseDeployPayload(input.payload);
  console.log(JSON.stringify(summarizeInput(input, decoded), null, 2));
  process.exit(0);
}

if (command === 'compare') {
  if (args.length !== 2) {
    usage();
  }

  const left = readInput(args[0]);
  const right = readInput(args[1]);
  console.log(JSON.stringify(compareInputs(left, right), null, 2));
  process.exit(0);
}

usage();
