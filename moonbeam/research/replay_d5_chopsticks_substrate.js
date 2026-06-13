const { ApiPromise, WsProvider } = require('@polkadot/api');
const { ethers } = require('ethers');

const WS = process.env.CHOPSTICKS_WS || 'ws://127.0.0.1:8011';
const ARCHIVE = process.env.MOONBEAM_RPC || 'https://rpc.api.moonbeam.network';
const FAILED_TX = '0xd5e49fc3e721a70059348b1186f3d7cfa14f52e7ac6af1fefb12eece4e6f862f';
const SUCCESS_NONCE7_TX = '0x277b88471c24df7cfdf04d0104c537353cb1aff12f928141ff1d9e64bde9c5e6';
const CALL_PERMIT = '0x000000000000000000000000000000000000080a';
const SIGNED_FROM = '0x6A210A61dC8112C1344858d82B1dbDE850b957a1';
const TARGET = '0x597B2084f1a74df59f3431AbE38dBeEc42dFd1c2';
const NESTED_DST = '0xa1A3Cc69c5E2fA553b521aCC3c5876cd375195e3';
const JOIN_CODE_ACCOUNT_SEEN_IN_REPLAY = '0x567b6dDb05396C0A83853B6f40D27450534C7963';
const REPLAY_PK = '0x59c6995e998f97a5a0044966f094538b85957f5e66ea0d824a528e118d5f43a0';
const FUND = '1000000000000000000000';
const CP = new ethers.Interface(['function dispatch(address from,address to,uint256 value,bytes data,uint64 gaslimit,uint256 deadline,uint8 v,bytes32 r,bytes32 s)','function nonces(address) view returns(uint256)']);
const OUTER = new ethers.Interface(['function SubmitTransaction(address dst,bytes data)']);
const ADD = new ethers.Interface(['function AddJoinCode(address,uint256,uint256,uint256)']);
const MEM = new ethers.Interface(['function owner() view returns(address)','function IsMember(address) view returns(bool)','function Members() view returns(address[])']);

async function evmCall(api, from, to, data, gas = 10000000) {
  const result = await api.call.ethereumRuntimeRPCApi.call(from, to, data, 0, gas, null, null, null, false, null, null);
  const json = result.toJSON();
  if (!json.ok) throw new Error(JSON.stringify(json));
  return { exitReason: json.ok.exitReason, value: json.ok.value, usedGas: BigInt(json.ok.usedGas.standard).toString(), logs: json.ok.logs };
}
async function callDecode(api, to, iface, fn, args = []) {
  const out = await evmCall(api, '0x0000000000000000000000000000000000000000', to, iface.encodeFunctionData(fn, args));
  return { raw: out.value, decoded: iface.decodeFunctionResult(fn, out.value).map((x) => x.toString ? x.toString() : String(x)) };
}
async function nonce(api) {
  return (await callDecode(api, CALL_PERMIT, CP, 'nonces', [SIGNED_FROM])).decoded[0];
}
async function accountBasic(api, addr) {
  const v = await api.call.ethereumRuntimeRPCApi.accountBasic(addr);
  const j = v.toJSON();
  return { balance: BigInt(j.balance).toString(), nonce: BigInt(j.nonce).toString() };
}
async function systemAccount(api, addr) {
  const v = await api.query.system.account(addr);
  const j = v.toJSON();
  return { nonce: j.nonce, providers: j.providers, data: { free: BigInt(j.data.free).toString(), reserved: BigInt(j.data.reserved).toString(), frozen: BigInt(j.data.frozen).toString(), flags: BigInt(j.data.flags).toString() } };
}
async function snapshot(api, label, replayAddr) {
  return {
    label,
    block: (await api.query.system.number()).toString(),
    timestampMs: (await api.query.timestamp.now()).toString(),
    callPermitNonceSignedFrom: await nonce(api),
    replayAccountBasic: await accountBasic(api, replayAddr),
    replaySystemAccount: await systemAccount(api, replayAddr),
    targetOwner: await callDecode(api, TARGET, MEM, 'owner'),
    targetSignedFromIsMember: await callDecode(api, TARGET, MEM, 'IsMember', [SIGNED_FROM]),
    nestedOwner: await callDecode(api, NESTED_DST, MEM, 'owner'),
    nestedMembers: await callDecode(api, NESTED_DST, MEM, 'Members'),
    joinCodeAccountBasic: await accountBasic(api, JOIN_CODE_ACCOUNT_SEEN_IN_REPLAY),
    joinCodeSystemAccount: await systemAccount(api, JOIN_CODE_ACCOUNT_SEEN_IN_REPLAY),
  };
}
function rawLegacyV(raw) {
  const rlp = ethers.decodeRlp(raw);
  return BigInt(rlp[6]).toString();
}
async function main() {
  const provider = new WsProvider(WS);
  const api = await ApiPromise.create({ provider, noInitWarn: true });
  const archive = new ethers.JsonRpcProvider(ARCHIVE);
  const failed = await archive.getTransaction(FAILED_TX);
  const failedReceipt = await archive.getTransactionReceipt(FAILED_TX);
  const success7Receipt = await archive.getTransactionReceipt(SUCCESS_NONCE7_TX);
  const failedBlock = await archive.getBlock(failedReceipt.blockNumber);
  const success7Block = await archive.getBlock(success7Receipt.blockNumber);
  const decoded = CP.decodeFunctionData('dispatch', failed.data);
  const outer = OUTER.decodeFunctionData('SubmitTransaction', decoded.data);
  const add = ADD.decodeFunctionData('AddJoinCode', outer.data);

  const wallet = new ethers.Wallet(REPLAY_PK);
  const replayAddr = wallet.address;
  if (replayAddr.toLowerCase() === failed.from.toLowerCase() || replayAddr.toLowerCase() === SIGNED_FROM.toLowerCase()) {
    throw new Error('replay account is not unrelated');
  }

  await provider.send('dev_setStorage', [{ System: { Account: [[[replayAddr], { nonce: 0, consumers: 0, providers: 1, sufficients: 0, data: { free: FUND, reserved: 0, frozen: 0, flags: 0 } }]] } }]);
  const before = await snapshot(api, 'before', replayAddr);

  const raw = await wallet.signTransaction({
    to: CALL_PERMIT,
    data: failed.data,
    nonce: BigInt(before.replayAccountBasic.nonce),
    gasPrice: 125000000000n,
    gasLimit: 4100000n,
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

  const ext = api.tx.ethereum.transact(ethTx);
  const events = [];
  const statusInfo = await new Promise((resolve, reject) => {
    let unsub;
    ext.send((result) => {
      if (result.dispatchError) reject(new Error(result.dispatchError.toString()));
      if (result.status.isInBlock || result.status.isFinalized) {
        for (const { event } of result.events) events.push({ section: event.section, method: event.method, data: event.data.toString(), human: event.toHuman() });
        resolve({ status: result.status.type, hash: result.status.asInBlock?.toHex?.() || result.status.toString() });
        if (unsub) unsub();
      }
    }).then((u) => { unsub = u; }).catch(reject);
  });

  const after = await snapshot(api, 'after', replayAddr);
  const currentReceipts = (await api.query.ethereum.currentReceipts()).toJSON();
  const currentStatuses = (await api.query.ethereum.currentTransactionStatuses()).toJSON();

  const ethereumExecuted = events.filter((e) => e.section === 'ethereum' && e.method === 'Executed');
  const output = {
    result: after.callPermitNonceSignedFrom === '9' ? 'REPLAY_SUCCEEDED' : 'REPLAY_UNCONFIRMED',
    originalFailedTx: FAILED_TX,
    originalDispatcher: failed.from,
    originalBlock: failedReceipt.blockNumber,
    originalBlockTimestamp: failedBlock.timestamp,
    originalStatus: failedReceipt.status,
    nonce7SuccessTx: SUCCESS_NONCE7_TX,
    nonce7SuccessBlock: success7Receipt.blockNumber,
    nonce7SuccessBlockTimestamp: success7Block.timestamp,
    replayDispatcher: replayAddr,
    replayIsUnrelated: replayAddr.toLowerCase() !== failed.from.toLowerCase() && replayAddr.toLowerCase() !== decoded.from.toLowerCase(),
    signedFrom: decoded.from,
    targetTo: decoded.to,
    deadline: decoded.deadline.toString(),
    replayTimestampSeconds: Math.floor(Number(after.timestampMs) / 1000),
    replayBeforeDeadline: Math.floor(Number(after.timestampMs) / 1000) < Number(decoded.deadline),
    exactCalldataHash: ethers.keccak256(failed.data),
    signedEthereumReplayTxHash: ethers.keccak256(raw),
    exactCalldataEqual: parsed.data === failed.data,
    outer: { selector: decoded.data.slice(0, 10), signature: 'SubmitTransaction(address,bytes)', dst: outer.dst },
    nested: { selector: outer.data.slice(0, 10), signature: 'AddJoinCode(address,uint256,uint256,uint256)', args: add.map((x) => x.toString ? x.toString() : String(x)) },
    substrateStatus: statusInfo,
    ethereumExecuted,
    before,
    after,
    stateDiff: {
      callPermitNonceSignedFrom: `${before.callPermitNonceSignedFrom} -> ${after.callPermitNonceSignedFrom}`,
      replayEthNonce: `${before.replayAccountBasic.nonce} -> ${after.replayAccountBasic.nonce}`,
      replayBalance: `${before.replayAccountBasic.balance} -> ${after.replayAccountBasic.balance}`,
      joinCodeAccountBalance: `${before.joinCodeAccountBasic.balance} -> ${after.joinCodeAccountBasic.balance}`,
      joinCodeSystemProviders: `${before.joinCodeSystemAccount.providers} -> ${after.joinCodeSystemAccount.providers}`,
    },
    events,
    currentReceipts,
    currentStatuses,
  };
  console.log(JSON.stringify(output, null, 2));
  await api.disconnect();
}
main().catch((e) => { console.error(e); process.exit(1); });
