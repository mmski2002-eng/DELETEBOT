const { ethers } = require('ethers');

const LOCAL = process.env.LOCAL_RPC || 'ws://127.0.0.1:8011';
const ARCHIVE = process.env.MOONBEAM_RPC || 'https://rpc.api.moonbeam.network';
const FAILED_TX = '0xd5e49fc3e721a70059348b1186f3d7cfa14f52e7ac6af1fefb12eece4e6f862f';
const SUCCESS_NONCE7_TX = '0x277b88471c24df7cfdf04d0104c537353cb1aff12f928141ff1d9e64bde9c5e6';
const CALL_PERMIT = '0x000000000000000000000000000000000000080a';
const SIGNER_FROM = '0x6A210A61dC8112C1344858d82B1dbDE850b957a1';
const REPLAY_PK = '0x59c6995e998f97a5a0044966f094538b85957f5e66ea0d824a528e118d5f43a0';
const TARGET_PROXY = '0x597B2084f1a74df59f3431AbE38dBeEc42dFd1c2';
const NESTED_DST = '0xa1A3Cc69c5E2fA553b521aCC3c5876cd375195e3';
const CALLPERMIT_IFACE = new ethers.Interface([
  'function dispatch(address from,address to,uint256 value,bytes data,uint64 gaslimit,uint256 deadline,uint8 v,bytes32 r,bytes32 s)',
  'function nonces(address owner) view returns(uint256)',
]);
const OUTER_IFACE = new ethers.Interface(['function SubmitTransaction(address dst, bytes data)']);
const ADD_IFACE = new ethers.Interface(['function AddJoinCode(address,uint256,uint256,uint256)']);
const MEMBER_IFACE = new ethers.Interface([
  'function IsMember(address) view returns (bool)',
  'function owner() view returns (address)',
  'function Members() view returns (address[])',
  'function Drives() view returns (address[])',
]);

async function readNonce(p) {
  const res = await p.call({ to: CALL_PERMIT, data: CALLPERMIT_IFACE.encodeFunctionData('nonces', [SIGNER_FROM]) });
  return CALLPERMIT_IFACE.decodeFunctionResult('nonces', res)[0];
}
async function tryCall(p, to, iface, fn, args=[]) {
  try { return iface.decodeFunctionResult(fn, await p.call({to, data: iface.encodeFunctionData(fn,args)}))[0]; }
  catch (e) { return `ERR:${e.shortMessage || e.message}`; }
}
async function snapshot(p, label) {
  const nonce = await readNonce(p);
  const nestedOwner = await tryCall(p, NESTED_DST, MEMBER_IFACE, 'owner');
  const targetOwner = await tryCall(p, TARGET_PROXY, MEMBER_IFACE, 'owner');
  const nestedIsArgMember = await tryCall(p, NESTED_DST, MEMBER_IFACE, 'IsMember', ['0x88e0B12bC374D9322f1F7E137a90888b10D5dF7a']);
  const targetIsSignerMember = await tryCall(p, TARGET_PROXY, MEMBER_IFACE, 'IsMember', [SIGNER_FROM]);
  const nestedMembers = await tryCall(p, NESTED_DST, MEMBER_IFACE, 'Members');
  return { label, nonce: nonce.toString(), targetOwner, nestedOwner, targetIsSignerMember, nestedIsArgMember, nestedMembers: Array.isArray(nestedMembers) ? nestedMembers : String(nestedMembers) };
}

async function main() {
  const archive = new ethers.JsonRpcProvider(ARCHIVE);
  const failed = await archive.getTransaction(FAILED_TX);
  const originalReceipt = await archive.getTransactionReceipt(FAILED_TX);
  const success7 = await archive.getTransaction(SUCCESS_NONCE7_TX);
  const success7Receipt = await archive.getTransactionReceipt(SUCCESS_NONCE7_TX);
  const failedDecoded = CALLPERMIT_IFACE.decodeFunctionData('dispatch', failed.data);
  const outer = OUTER_IFACE.decodeFunctionData('SubmitTransaction', failedDecoded.data);
  const add = ADD_IFACE.decodeFunctionData('AddJoinCode', outer.data);
  const calldataHash = ethers.keccak256(failed.data);

  const provider = new ethers.WebSocketProvider(LOCAL, 1284);
  const wallet = new ethers.Wallet(REPLAY_PK, provider);
  const replayDispatcher = await wallet.getAddress();

  const before = await snapshot(provider, 'before');
  const blockBefore = await provider.getBlock('latest');

  const fee = await provider.getFeeData();
  const tx = await wallet.sendTransaction({
    to: CALL_PERMIT,
    data: failed.data,
    gasLimit: 4100000n,
    gasPrice: fee.gasPrice || 125000000000n,
    type: 0,
  });
  const receipt = await tx.wait();
  const after = await snapshot(provider, 'after');
  const blockAfter = await provider.getBlock(receipt.blockNumber);

  console.log(JSON.stringify({
    result: receipt.status === 1 ? 'REPLAY_SUCCEEDED' : 'REPLAY_FAILED',
    originalFailedTx: FAILED_TX,
    originalDispatcher: failed.from,
    originalBlock: originalReceipt.blockNumber,
    originalStatus: originalReceipt.status,
    nonce7SuccessTx: SUCCESS_NONCE7_TX,
    nonce7SuccessBlock: success7Receipt.blockNumber,
    replayTx: receipt.hash,
    replayDispatcher,
    signedFrom: failedDecoded.from,
    targetTo: failedDecoded.to,
    deadline: failedDecoded.deadline.toString(),
    replayBlock: receipt.blockNumber,
    replayBlockTimestamp: blockAfter.timestamp,
    blockBeforeTimestamp: blockBefore.timestamp,
    calldataHashOriginal: calldataHash,
    calldataHashReplayInput: ethers.keccak256(failed.data),
    exactCalldataEqual: true,
    receipt: { status: receipt.status, gasUsed: receipt.gasUsed.toString(), logs: receipt.logs.map(l => ({address:l.address, topics:l.topics, data:l.data})) },
    decoded: {
      outer: { selector: failedDecoded.data.slice(0,10), dst: outer.dst },
      nested: { selector: outer.data.slice(0,10), args: add.map(x => x.toString ? x.toString() : String(x)) },
    },
    before,
    after,
  }, null, 2));
  await provider.destroy();
}
main().catch((e) => { console.error(e); process.exit(1); });
