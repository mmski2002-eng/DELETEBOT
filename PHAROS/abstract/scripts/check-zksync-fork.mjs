import http from "node:http";
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";
import { ethers } from "ethers";
import { Provider, Wallet, Contract } from "zksync-ethers";

const RPC_URL = "http://127.0.0.1:8011";
const ABSTRACT_RPC = "https://api.mainnet.abs.xyz";
const PROXY_PORT = 9545;
const WETH = "0x3439153EB7AF838Ad19d56E1571FBD09333C2809";
const PERMIT2 = "0x0000000000225e31d15943971f47ad3022f714fa";
const UNIVERSAL_ROUTER = "0xE1b076ea612Db28a0d768660e4D81346c02ED75e";
const RICH_PK = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const RECIPIENT = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";

const WETH_ABI = [
  "function deposit() payable",
  "function approve(address spender,uint256 amount) returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
];
const PERMIT2_ABI = [
  "function allowance(address owner,address token,address spender) view returns (uint160 amount,uint48 expiration,uint48 nonce)",
];
const ROUTER_ABI = ["function execute(bytes commands, bytes[] inputs, uint256 deadline) payable"];

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
  for (let i = 0; i < 120; i++) {
    try {
      return BigInt(await rpc("eth_chainId"));
    } catch {}
    await sleep(1000);
  }
  throw new Error("anvil-zksync fork RPC did not become ready");
}

function getWslHost() {
  const out = spawnSync("wsl", ["bash", "-lc", "awk '/nameserver/{print $2; exit}' /etc/resolv.conf"], {
    encoding: "utf8",
  });
  const host = out.stdout.trim().split(/\s+/).pop();
  if (!host) throw new Error("Cannot detect WSL host IP from /etc/resolv.conf");
  return host;
}

async function startRpcProxy() {
  const server = http.createServer(async (req, res) => {
    if (req.method !== "POST") {
      res.writeHead(405);
      res.end();
      return;
    }
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", async () => {
      try {
        const upstream = await fetch(ABSTRACT_RPC, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: Buffer.concat(chunks),
        });
        res.writeHead(upstream.status, { "content-type": "application/json" });
        res.end(Buffer.from(await upstream.arrayBuffer()));
      } catch (err) {
        res.writeHead(502, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
  });
  await new Promise((resolve) => server.listen(PROXY_PORT, "0.0.0.0", resolve));
  return server;
}

function startFork(forkUrl) {
  return spawn(
    "wsl",
    [
      "bash",
      "-lc",
      [
        "$HOME/anvil-zksync-bin/anvil-zksync",
        "--host",
        "0.0.0.0",
        "--port",
        "8011",
        "--show-node-config=false",
        "fork",
        "--fork-url",
        `'${forkUrl}'`,
      ].join(" "),
    ],
    { stdio: ["ignore", "pipe", "pipe"] },
  );
}

async function main() {
  const proxy = await startRpcProxy();
  const forkUrl = `http://${getWslHost()}:${PROXY_PORT}`;
  const fork = startFork(forkUrl);
  let bootLog = "";
  fork.stdout.on("data", (chunk) => (bootLog += chunk.toString()));
  fork.stderr.on("data", (chunk) => (bootLog += chunk.toString()));

  try {
    const chainId = await waitForRpc();
    const provider = new Provider(RPC_URL);
    const wallet = new Wallet(RICH_PK, provider);
    const owner = await wallet.getAddress();

    const code = {
      weth: await provider.getCode(WETH),
      permit2: await provider.getCode(PERMIT2),
      router: await provider.getCode(UNIVERSAL_ROUTER),
    };

    const weth = new Contract(WETH, WETH_ABI, wallet);
    const permit2 = new Contract(PERMIT2, PERMIT2_ABI, provider);
    const router = new Contract(UNIVERSAL_ROUTER, ROUTER_ABI, wallet);
    const amount = ethers.parseEther("0.01");
    const now = Math.floor(Date.now() / 1000);
    const expiration = now + 3600;
    const sigDeadline = now + 1800;
    const routerDeadline = now + 1800;

    await (await weth.approve(PERMIT2, amount)).wait();
    const before = await permit2.allowance(owner, WETH, UNIVERSAL_ROUTER);

    const permitSingle = {
      details: { token: WETH, amount, expiration, nonce: before.nonce },
      spender: UNIVERSAL_ROUTER,
      sigDeadline,
    };
    const domain = { name: "Permit2", chainId: Number(chainId), verifyingContract: PERMIT2 };
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
    const signature = await wallet.signTypedData(domain, types, permitSingle);
    const abi = ethers.AbiCoder.defaultAbiCoder();
    const permitInput = abi.encode(
      [
        "tuple(tuple(address token,uint160 amount,uint48 expiration,uint48 nonce) details,address spender,uint256 sigDeadline)",
        "bytes",
      ],
      [permitSingle, signature],
    );
    const transferInput = abi.encode(["address", "address", "uint160"], [WETH, RECIPIENT, amount]);
    const commands = "0x0a02";
    const calldata = router.interface.encodeFunctionData("execute(bytes,bytes[],uint256)", [
      commands,
      [permitInput, transferInput],
      routerDeadline,
    ]);

    let failStatus = "unexpected-success";
    try {
      await (await wallet.sendTransaction({ to: UNIVERSAL_ROUTER, data: calldata })).wait();
    } catch (err) {
      failStatus = err.shortMessage || err.message.split("\n")[0];
    }
    const afterFail = await permit2.allowance(owner, WETH, UNIVERSAL_ROUTER);
    const recipientAfterFail = await weth.balanceOf(RECIPIENT);

    await (await weth.deposit({ value: amount })).wait();
    const replayReceipt = await (await wallet.sendTransaction({ to: UNIVERSAL_ROUTER, data: calldata })).wait();
    const afterReplay = await permit2.allowance(owner, WETH, UNIVERSAL_ROUTER);
    const ownerAfterReplay = await weth.balanceOf(owner);
    const recipientAfterReplay = await weth.balanceOf(RECIPIENT);

    console.log(
      JSON.stringify(
        {
          chainId: Number(chainId),
          contracts: { WETH, PERMIT2, UNIVERSAL_ROUTER },
          codeLengths: Object.fromEntries(Object.entries(code).map(([k, v]) => [k, (v.length - 2) / 2])),
          owner,
          recipient: RECIPIENT,
          amount: amount.toString(),
          nonceBefore: before.nonce.toString(),
          failStatus,
          nonceAfterFail: afterFail.nonce.toString(),
          recipientWethAfterFail: recipientAfterFail.toString(),
          replayTxHash: replayReceipt.hash,
          replayStatus: replayReceipt.status,
          nonceAfterReplay: afterReplay.nonce.toString(),
          ownerWethAfterReplay: ownerAfterReplay.toString(),
          recipientWethAfterReplay: recipientAfterReplay.toString(),
          exactCalldataReplayed: true,
          calldataBytes: (calldata.length - 2) / 2,
        },
        null,
        2,
      ),
    );
  } catch (err) {
    console.error("ZKSYNC_FORK_CHECK_FAILED");
    console.error(err.stack || err.message);
    console.error("BOOT_LOG");
    console.error(bootLog.slice(-5000));
    process.exitCode = 1;
  } finally {
    fork.kill();
    proxy.close();
  }
}

await main();
