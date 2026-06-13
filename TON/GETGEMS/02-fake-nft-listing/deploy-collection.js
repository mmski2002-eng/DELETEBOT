/**
 * Deploy only: collection + NFT item + sale contract.
 * No polling. Exits after printing addresses.
 * Run: node 02-fake-nft-listing/deploy-collection.js
 */
const path  = require('path');
const fs    = require('fs');
const https = require('https');
const { compileFunc } = require('../nft-contracts/node_modules/@ton-community/func-js');
const { mnemonicToWalletKey } = require('../nft-contracts/node_modules/@ton/crypto');
const {
  WalletContractV4, TonClient, internal, toNano,
  Address, beginCell, contractAddress, Cell
} = require('../nft-contracts/node_modules/@ton/ton');

const ATTACKER_MNEMONIC = 'asthma black design brick oxygen cat that potato nurse umbrella quote snack bag color walnut jump stem cloth kit sand volcano secret cloth better';
const MARKETPLACE_FEE_ADDRESS = Address.parse('EQDDuxx7sa3Dt2GE85a0sIHp4GVoa7OKbAanfo3co9H-h06d');
const FULL_PRICE   = toNano('0.05');
const OP_TRANSFER  = 0x5fcc3d14;
const BASE_URL     = 'https://raw.githubusercontent.com/mmski2002-eng/DELETEBOT/main/TON/GETGEMS/nft-metadata';
const SOURCES_DIR  = path.resolve(__dirname, '../contracts/sources');
const PATCH        = 'int builder_null?(builder b) asm "ISNULL";';

const NftFixPriceSaleV4R1CodeBoc = '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';
const SALE_CODE_CELL = Cell.fromBase64(NftFixPriceSaleV4R1CodeBoc);

const client = new TonClient({ endpoint: 'https://testnet.toncenter.com/api/v2/jsonRPC', apiKey: '' });

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function fmt(n)    { return (Number(n) / 1e9).toFixed(6); }
async function withRetry(fn, max = 6) {
  for (let i = 1; i <= max; i++) {
    try { return await fn(); } catch (e) {
      if (i < max) { await sleep(e.message?.includes('429') ? 2500 * i : 1200); continue; }
      throw e;
    }
  }
}
function makeOffchainContent(url) {
  return beginCell().storeUint(0x01, 8).storeBuffer(Buffer.from(url)).endCell();
}
async function compile(targets) {
  const r = await compileFunc({
    targets,
    sources: p => p === 'patch.fc' ? PATCH : fs.readFileSync(path.join(SOURCES_DIR, p), 'utf8'),
  });
  if (r.status === 'error') throw new Error('FunC: ' + r.message);
  return Cell.fromBase64(r.codeBoc);
}
async function getSaleState(saleAddr) {
  try {
    const r = await withRetry(() => client.runMethod(saleAddr, 'get_fix_price_data_v4'));
    const isCompleteTVM = r.stack.readNumber();
    r.stack.readNumber(); r.stack.readCell(); r.stack.readCell();
    const owner = r.stack.readCell().beginParse().loadAddress();
    return { isComplete: isCompleteTVM !== 0, owner: owner?.toString({ testOnly: true, bounceable: true }) ?? 'addr_none' };
  } catch (e) { return { error: e.message }; }
}

async function main() {
  const atkKey    = await mnemonicToWalletKey(ATTACKER_MNEMONIC.split(/\s+/));
  const atkWallet = WalletContractV4.create({ publicKey: atkKey.publicKey, workchain: 0 });
  const atkAddr   = atkWallet.address;
  const atk       = client.open(atkWallet);
  console.log('Атакующий:', atkAddr.toString({ testOnly: true, bounceable: true }));

  // 1. Compile
  console.log('\n[1] Компиляция...');
  const [COL_CODE, NFT_CODE] = await Promise.all([
    compile(['imports/stdlib.fc', 'op-codes.fc', 'params.fc', 'patch.fc', 'nft-collection.fc']),
    compile(['imports/stdlib.fc', 'op-codes.fc', 'params.fc', 'patch.fc', 'nft-item.fc']),
  ]);
  console.log('  OK');

  // 2. Deploy collection
  console.log('\n[2] Deploy collection...');
  const nonce = Math.floor(Date.now() / 1000);
  const collData = beginCell()
    .storeRef(makeOffchainContent(`${BASE_URL}/collection.json#${nonce}`))
    .storeUint(0, 64)
    .storeAddress(atkAddr)
    .storeRef(NFT_CODE)
    .endCell();
  const collAddr = contractAddress(0, { code: COL_CODE, data: collData });
  console.log('  addr:', collAddr.toString({ bounceable: true, testOnly: true }));

  if ((await withRetry(() => client.getContractState(collAddr))).state !== 'active') {
    const seq = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq, secretKey: atkKey.secretKey,
      messages: [internal({ to: collAddr, value: toNano('0.05'), bounce: false, init: { code: COL_CODE, data: collData } })],
    }));
    console.log('  TX sent, 15s...');
    await sleep(15000);
    console.log('  state:', (await withRetry(() => client.getContractState(collAddr))).state);
  } else { console.log('  already deployed'); }

  // 3. Mint NFT #0
  console.log('\n[3] Mint NFT #0...');
  const nftItemData = beginCell().storeUint(0, 64).storeAddress(collAddr).endCell();
  const nftAddr = contractAddress(0, { code: NFT_CODE, data: nftItemData });
  console.log('  addr:', nftAddr.toString({ bounceable: true, testOnly: true }));

  if ((await withRetry(() => client.getContractState(nftAddr))).state !== 'active') {
    const mintBody = beginCell()
      .storeUint(1, 32).storeUint(0, 64).storeUint(0, 64)
      .storeRef(makeOffchainContent(`${BASE_URL}/0.json`))
      .storeAddress(atkAddr)
      .storeCoins(toNano('0.05'))
      .endCell();
    await sleep(500);
    const seq2 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq2, secretKey: atkKey.secretKey,
      messages: [internal({ to: collAddr, value: toNano('0.15'), bounce: true, body: mintBody })],
    }));
    console.log('  TX sent, 20s...');
    await sleep(20000);
    console.log('  state:', (await withRetry(() => client.getContractState(nftAddr))).state);
  } else { console.log('  already deployed'); }

  // 4. Deploy sale
  console.log('\n[4] Deploy sale...');
  const saleData = beginCell()
    .storeBit(0).storeAddress(atkAddr).storeAddress(null)
    .storeCoins(FULL_PRICE).storeUint(0, 32).storeUint(0, 64)
    .storeRef(beginCell()
      .storeAddress(MARKETPLACE_FEE_ADDRESS).storeAddress(atkAddr)
      .storeUint(2500, 17).storeUint(0, 17)
      .storeAddress(nftAddr)
      .storeUint(Math.floor(Date.now() / 1000), 32)
      .endCell())
    .storeDict(null).storeBit(0).endCell();
  const saleAddr = contractAddress(0, { code: SALE_CODE_CELL, data: saleData });
  console.log('  addr:', saleAddr.toString({ bounceable: true, testOnly: true }));

  if ((await withRetry(() => client.getContractState(saleAddr))).state !== 'active') {
    await sleep(500);
    const seq3 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq3, secretKey: atkKey.secretKey,
      messages: [internal({ to: saleAddr, value: toNano('0.05'), bounce: false, init: { code: SALE_CODE_CELL, data: saleData } })],
    }));
    console.log('  TX sent, 15s...');
    await sleep(15000);
    console.log('  state:', (await withRetry(() => client.getContractState(saleAddr))).state);
  } else { console.log('  already deployed'); }

  // 5. Transfer NFT → sale (triggers ownership_assigned)
  console.log('\n[5] Transfer NFT → sale...');
  const check = await getSaleState(saleAddr);
  if (!check.error && check.owner !== 'addr_none') {
    console.log('  already initialized, nft_owner:', check.owner);
  } else {
    const transferBody = beginCell()
      .storeUint(OP_TRANSFER, 32).storeUint(0, 64)
      .storeAddress(saleAddr).storeAddress(atkAddr)
      .storeBit(0).storeCoins(toNano('0.1')).storeBit(0)
      .endCell();
    await sleep(500);
    const seq4 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq4, secretKey: atkKey.secretKey,
      messages: [internal({ to: nftAddr, value: toNano('0.3'), bounce: true, body: transferBody })],
    }));
    console.log('  TX sent, 25s...');
    await sleep(25000);
    const s2 = await getSaleState(saleAddr);
    console.log('  is_initialized:', (!s2.error && s2.owner !== 'addr_none') ? '✅' : '❌');
    if (!s2.error) console.log('  nft_owner:', s2.owner);
  }

  // Done
  const raw = { coll: collAddr.toRawString(), nft: nftAddr.toRawString(), sale: saleAddr.toRawString() };
  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║  ✅ ЗАДЕПЛОЕНО                                               ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║  Collection:', collAddr.toString({ bounceable: true, testOnly: true }));
  console.log('║  NFT item:  ', nftAddr.toString({ bounceable: true, testOnly: true }));
  console.log('║  Sale:      ', saleAddr.toString({ bounceable: true, testOnly: true }));
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║  Покупатель → Tonkeeper Testnet → 0.08 TON →               ║');
  console.log('║  ' + saleAddr.toString({ bounceable: true, testOnly: true }).padEnd(56) + '║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('\nExplorers:');
  console.log('  https://testnet.tonscan.org/address/' + raw.coll);
  console.log('  https://testnet.tonscan.org/address/' + raw.nft);
  console.log('  https://testnet.tonscan.org/address/' + raw.sale);
}

main().then(() => process.exit(0)).catch(e => { console.error('FATAL:', e.message); process.exit(1); });
