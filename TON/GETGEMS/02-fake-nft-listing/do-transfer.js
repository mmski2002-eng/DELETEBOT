/**
 * Transfer NFT → sale contract (single step, low value)
 * Existing contracts:
 *   NFT:  kQDuwy8u0VPgyaEdBPrZnqxXgN2QmOTKgojJ5pnbTbkLcilZ
 *   Sale: kQBKWJyBKhVIc8VCg_qliuMK49Vmh7yQW8OQxeTKW5ZeYW-l
 */

const https = require('https');
const { mnemonicToWalletKey } = require('../nft-contracts/node_modules/@ton/crypto');
const {
  WalletContractV4, TonClient, internal, toNano,
  Address, beginCell
} = require('../nft-contracts/node_modules/@ton/ton');

const ATTACKER_MNEMONIC = 'asthma black design brick oxygen cat that potato nurse umbrella quote snack bag color walnut jump stem cloth kit sand volcano secret cloth better';
const NFT_ADDR  = Address.parse('kQDuwy8u0VPgyaEdBPrZnqxXgN2QmOTKgojJ5pnbTbkLcilZ');
const SALE_ADDR = Address.parse('kQBKWJyBKhVIc8VCg_qliuMK49Vmh7yQW8OQxeTKW5ZeYW-l');
const OP_TRANSFER = 0x5fcc3d14;

const client = new TonClient({ endpoint: 'https://testnet.toncenter.com/api/v2/jsonRPC' });

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function fmt(n) { return (Number(n) / 1e9).toFixed(6); }

async function withRetry(fn, max = 5) {
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
      r.on('end', () => { try { res(JSON.parse(d)); } catch { res({ raw: d.slice(0,200) }); } });
    }).on('error', rej);
  });
}

async function getSaleState() {
  const r = await withRetry(() => client.runMethod(SALE_ADDR, 'get_fix_price_data_v4'));
  const isComplete = r.stack.readNumber();
  r.stack.readNumber(); // created_at
  const mpCell  = r.stack.readCell();
  const nftCell = r.stack.readCell();
  const ownerCell = r.stack.readCell();
  const mp    = mpCell.beginParse().loadAddress();
  const nft2  = nftCell.beginParse().loadAddress();
  try {
    const nftOwner = ownerCell.beginParse().loadAddress();
    return { isComplete, marketplace: mp.toString({ testOnly: true }), nftOwner: nftOwner.toString({ testOnly: true }) };
  } catch {
    return { isComplete, marketplace: mp.toString({ testOnly: true }), nftOwner: 'addr_none' };
  }
}

async function main() {
  const key = await mnemonicToWalletKey(ATTACKER_MNEMONIC.split(/\s+/));
  const wallet = WalletContractV4.create({ publicKey: key.publicKey, workchain: 0 });
  const atk = client.open(wallet);
  const atkAddr = wallet.address;

  const bal = await withRetry(() => client.getContractState(atkAddr));
  console.log('Attacker balance:', fmt(BigInt(bal.balance || '0')), 'TON');

  // Check current NFT owner
  const nftR = await withRetry(() => client.runMethod(NFT_ADDR, 'get_nft_data'));
  nftR.stack.readNumber(); // init
  nftR.stack.readNumber(); // index
  nftR.stack.readCell();   // collection
  const ownerCell = nftR.stack.readCell();
  const nftOwner = ownerCell.beginParse().loadAddress();
  console.log('NFT current owner:', nftOwner.toString({ testOnly: true }));

  // Check sale state before
  console.log('\nSale state before:');
  const before = await getSaleState().catch(e => ({ error: e.message }));
  console.log(JSON.stringify(before, null, 2));

  if (before.nftOwner && before.nftOwner !== 'addr_none') {
    console.log('\n✅ Sale already initialized!');
    return;
  }

  // Send transfer: NFT → sale
  const transferBody = beginCell()
    .storeUint(OP_TRANSFER, 32)
    .storeUint(0, 64)
    .storeAddress(SALE_ADDR)   // new_owner
    .storeAddress(atkAddr)     // response_dest
    .storeBit(0)               // no custom_payload
    .storeCoins(toNano('0.05')) // forward_amount (ownership_assigned)
    .storeBit(0)               // empty forward_payload
    .endCell();

  const seq = await withRetry(() => atk.getSeqno());
  console.log('\nSending transfer TX (seqno:', seq, ')...');
  await withRetry(() => atk.sendTransfer({
    seqno: seq,
    secretKey: key.secretKey,
    messages: [internal({ to: NFT_ADDR, value: toNano('0.09'), bounce: true, body: transferBody })],
  }));

  console.log('TX sent, waiting 25s...');
  await sleep(25000);

  // Check sale state after
  console.log('\nSale state after:');
  const after = await getSaleState().catch(e => ({ error: e.message }));
  console.log(JSON.stringify(after, null, 2));

  const isInit = after.nftOwner && after.nftOwner !== 'addr_none';
  console.log('\nSale initialized:', isInit ? '✅ YES' : '❌ NO');

  if (isInit) {
    // Check tonapi
    await sleep(5000);
    const nftTonapi = await httpsGet(`https://testnet.tonapi.io/v2/nfts/${NFT_ADDR.toRawString()}`);
    console.log('\ntonapi NFT sale:', JSON.stringify(nftTonapi.sale));
    console.log('tonapi NFT interfaces:', nftTonapi.interfaces);

    const saleAcc = await httpsGet(`https://testnet.tonapi.io/v2/accounts/${SALE_ADDR.toRawString()}`);
    console.log('Sale contract interfaces:', saleAcc.interfaces);
    console.log('Sale contract methods:', saleAcc.get_methods);
  }
}

main().catch(console.error);
