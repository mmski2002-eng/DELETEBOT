import { spawn } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";
import { ethers } from "ethers";

const RPC_URL = "http://127.0.0.1:8545";
const ABSTRACT_RPC = "https://api.mainnet.abs.xyz";
const ABSTRACT_CHAIN_ID = 2741n;

const WETH = "0x3439153EB7AF838Ad19d56E1571FBD09333C2809";
const PERMIT2 = "0x0000000000225e31d15943971f47ad3022f714fa";
const UNIVERSAL_ROUTER = "0xE1b076ea612Db28a0d768660e4D81346c02ED75e";

const WETH_ABI = [
  "function deposit() payable",
  "function approve(address spender,uint256 amount) returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
  "function allowance(address owner,address spender) view returns (uint256)",
];

const PERMIT2_ABI = [
  "function allowance(address owner,address token,address spender) view returns (uint160 amount,uint48 expiration,uint48 nonce)",
];

const ROUTER_ABI = [
  "function execute(bytes commands, bytes[] inputs, uint256 deadline) payable",
];

async function rpc(method, params = []) {
  const res = await fetch(RPC_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const json = await res.json();
  if (json.error) throw new Error(`${method}: ${json.error.message}`);
  return json.result;
}

async function waitForRpc() {
  for (let i = 0; i < 90; i++) {
    try {
      const chainId = await rpc("eth_chainId");
      return BigInt(chainId);
    } catch {}
    await sleep(1000);
  }
  throw new Error("Hardhat fork RPC did not become ready");
}

function startFork() {
  return spawn(
    process.execPath,
    [
      "node_modules/hardhat/dist/src/cli.js",
      "node",
      "--fork",
      ABSTRACT_RPC,
      "--hostname",
      "127.0.0.1",
      "--port",
      "8545",
    ],
    { stdio: ["ignore", "pipe", "pipe"] },
  );
}

async function main() {
  const fork = startFork();
  let bootLog = "";
  fork.stdout.on("data", (chunk) => {
    bootLog += chunk.toString();
  });
  fork.stderr.on("data", (chunk) => {
    bootLog += chunk.toString();
  });

  try {
    const forkChainId = await waitForRpc();

    const provider = new ethers.JsonRpcProvider(RPC_URL, Number(forkChainId));
    const [ownerSigner, recipientSigner] = await provider.listAccounts();
    const owner = await ownerSigner.getAddress();
    const recipient = await recipientSigner.getAddress();

    const weth = new ethers.Contract(WETH, WETH_ABI, ownerSigner);
    const permit2 = new ethers.Contract(PERMIT2, PERMIT2_ABI, provider);
    const router = new ethers.Contract(UNIVERSAL_ROUTER, ROUTER_ABI, ownerSigner);

    const amount = ethers.parseEther("0.01");
    const now = Math.floor(Date.now() / 1000);
    const expiration = now + 3600;
    const sigDeadline = now + 1800;
    const routerDeadline = now + 1800;

    await (await weth.approve(PERMIT2, amount)).wait();

    const beforeAllowance = await permit2.allowance(owner, WETH, UNIVERSAL_ROUTER);
    const nonce = beforeAllowance.nonce;

    const permitSingle = {
      details: {
        token: WETH,
        amount,
        expiration,
        nonce,
      },
      spender: UNIVERSAL_ROUTER,
      sigDeadline,
    };

    const domain = {
      name: "Permit2",
      chainId: Number(forkChainId),
      verifyingContract: PERMIT2,
    };
    const types = {
      PermitSingle: [
        { name: "details", type: "PermitDetails" },
        { name: "spender", type: "address" },
        { name: "sigDeadline", type: "uint256" },
      ],
      PermitDetails: [
        { name: "token", type: "address" },
        { name: "amount", type: "uint160" },
        { name: "expiration", type: "uint48" },
        { name: "nonce", type: "uint48" },
      ],
    };
    const signature = await ownerSigner.signTypedData(domain, types, permitSingle);

    const abi = ethers.AbiCoder.defaultAbiCoder();
    const permitInput = abi.encode(
      [
        "tuple(tuple(address token,uint160 amount,uint48 expiration,uint48 nonce) details,address spender,uint256 sigDeadline)",
        "bytes",
      ],
      [permitSingle, signature],
    );
    const transferInput = abi.encode(["address", "address", "uint160"], [WETH, recipient, amount]);
    const commands = "0x0a02";
    const calldata = router.interface.encodeFunctionData("execute(bytes,bytes[],uint256)", [
      commands,
      [permitInput, transferInput],
      routerDeadline,
    ]);

    let failStatus = "unexpected-success";
    try {
      await ownerSigner.sendTransaction({ to: UNIVERSAL_ROUTER, data: calldata });
    } catch (err) {
      failStatus = err.shortMessage || err.message.split("\n")[0];
    }

    const afterFailAllowance = await permit2.allowance(owner, WETH, UNIVERSAL_ROUTER);
    const ownerWethAfterFail = await weth.balanceOf(owner);
    const recipientWethAfterFail = await weth.balanceOf(recipient);

    await (await weth.deposit({ value: amount })).wait();

    const replayTx = await ownerSigner.sendTransaction({ to: UNIVERSAL_ROUTER, data: calldata });
    const replayReceipt = await replayTx.wait();

    const afterReplayAllowance = await permit2.allowance(owner, WETH, UNIVERSAL_ROUTER);
    const ownerWethAfterReplay = await weth.balanceOf(owner);
    const recipientWethAfterReplay = await weth.balanceOf(recipient);

    const result = {
      sourceChainId: Number(ABSTRACT_CHAIN_ID),
      forkChainId: Number(forkChainId),
      contracts: {
        WETH,
        PERMIT2,
        UNIVERSAL_ROUTER,
      },
      owner,
      recipient,
      amount: amount.toString(),
      nonceBefore: nonce.toString(),
      failStatus,
      nonceAfterFail: afterFailAllowance.nonce.toString(),
      ownerWethAfterFail: ownerWethAfterFail.toString(),
      recipientWethAfterFail: recipientWethAfterFail.toString(),
      replayTxHash: replayReceipt.hash,
      replayStatus: replayReceipt.status,
      nonceAfterReplay: afterReplayAllowance.nonce.toString(),
      ownerWethAfterReplay: ownerWethAfterReplay.toString(),
      recipientWethAfterReplay: recipientWethAfterReplay.toString(),
      exactCalldataReplayed: true,
      calldataBytes: (calldata.length - 2) / 2,
    };

    console.log(JSON.stringify(result, null, 2));
  } catch (err) {
    console.error("FORK_CHECK_FAILED");
    console.error(err.stack || err.message);
    console.error("BOOT_LOG");
    console.error(bootLog.slice(-4000));
    process.exitCode = 1;
  } finally {
    fork.kill();
  }
}

await main();
