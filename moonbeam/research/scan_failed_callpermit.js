const { ethers } = require("ethers");

const CALL_PERMIT = "0x000000000000000000000000000000000000080a";
const DISPATCH_SELECTOR = "0xb5ea0966";

const NETWORKS = {
  moonbeam: {
    rpc: process.env.MOONBEAM_RPC || "https://rpc.api.moonbeam.network",
    explorer: "https://moonbeam.moonscan.io/tx/",
  },
  moonriver: {
    rpc: process.env.MOONRIVER_RPC || "https://rpc.api.moonriver.moonbeam.network",
    explorer: "https://moonriver.moonscan.io/tx/",
  },
};

const dispatchIface = new ethers.Interface([
  "function dispatch(address from,address to,uint256 value,bytes data,uint64 gaslimit,uint256 deadline,uint8 v,bytes32 r,bytes32 s)",
]);

const commonSelectors = {
  "0x095ea7b3": "approve(address,uint256)",
  "0xa9059cbb": "transfer(address,uint256)",
  "0x23b872dd": "transferFrom(address,address,uint256)",
  "0x38ed1739": "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
  "0x7ff36ab5": "swapExactETHForTokens(uint256,address[],address,uint256)",
  "0x18cbafe5": "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
  "0x4e71d92d": "claim()",
  "0x2e1a7d4d": "withdraw(uint256)",
  "0xdb006a75": "redeem(uint256)",
  "0x1249c58b": "mint()",
  "0xa0712d68": "mint(uint256)",
  "0xa6f2ae3a": "buy(uint256)",
  "0xdb76d5b3": "buyVoyages(uint16,uint256,address)",
};

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function rpc(url, payload) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) throw new Error(`${url} HTTP ${res.status}`);
  return res.json();
}

async function batch(url, calls) {
  const out = await rpc(url, calls.map((call, i) => ({ jsonrpc: "2.0", id: i, ...call })));
  if (!Array.isArray(out)) throw new Error(JSON.stringify(out));
  out.sort((a, b) => a.id - b.id);
  return out.map((item) => item.result);
}

function hexBlock(n) {
  return "0x" + n.toString(16);
}

function summarizeInner(data) {
  if (!data || data === "0x" || data.length < 10) return { selector: data || "0x", name: "empty/unknown" };
  const selector = data.slice(0, 10).toLowerCase();
  return { selector, name: commonSelectors[selector] || "unknown" };
}

async function scanNetwork(name, cfg, blocksBack, batchSize) {
  const latestHex = (await rpc(cfg.rpc, { jsonrpc: "2.0", id: 1, method: "eth_blockNumber", params: [] })).result;
  const latest = Number.parseInt(latestHex, 16);
  const start = Math.max(0, latest - blocksBack + 1);
  const found = [];

  console.error(`[${name}] scanning blocks ${start}..${latest} (${blocksBack})`);

  async function scanBatch(from) {
    const to = Math.max(start, from - batchSize + 1);
    const calls = [];
    for (let n = from; n >= to; n--) {
      calls.push({ method: "eth_getBlockReceipts", params: [hexBlock(n)] });
    }
    let receiptGroups;
    try {
      receiptGroups = await batch(cfg.rpc, calls);
    } catch (error) {
      console.error(`[${name}] batch failed at ${to}-${from}: ${error.message}`);
      return [];
    }

    const batchFound = [];
    for (const receipts of receiptGroups) {
      for (const receipt of receipts || []) {
        if ((receipt.to || "").toLowerCase() !== CALL_PERMIT) continue;
        if (receipt.status !== "0x0") continue;

        const tx = (await rpc(cfg.rpc, {
          jsonrpc: "2.0",
          id: 1,
          method: "eth_getTransactionByHash",
          params: [receipt.transactionHash],
        })).result;
        if (!tx || !tx.input?.toLowerCase().startsWith(DISPATCH_SELECTOR)) continue;

        let decoded = null;
        try {
          decoded = dispatchIface.decodeFunctionData("dispatch", tx.input);
        } catch {}
        const inner = decoded ? summarizeInner(decoded.data) : { selector: "decode-failed", name: "decode-failed" };

        batchFound.push({
          network: name,
          txHash: receipt.transactionHash,
          explorer: cfg.explorer + receipt.transactionHash,
          block: Number.parseInt(receipt.blockNumber, 16),
          status: receipt.status,
          dispatcher: tx.from,
          signedFrom: decoded?.from,
          targetTo: decoded?.to,
          value: decoded?.value?.toString(),
          gaslimit: decoded?.gaslimit?.toString(),
          deadline: decoded?.deadline?.toString(),
          v: decoded?.v?.toString(),
          r: decoded?.r,
          s: decoded?.s,
          innerSelector: inner.selector,
          innerName: inner.name,
          innerData: decoded?.data,
        });
      }
    }
    return batchFound;
  }

  const ranges = [];
  for (let from = latest; from >= start; from -= batchSize) ranges.push(from);
  const concurrency = Number(process.env.SCAN_CONCURRENCY || 6);

  for (let i = 0; i < ranges.length; i += concurrency) {
    const slice = ranges.slice(i, i + concurrency);
    const settled = await Promise.all(slice.map((from) => scanBatch(from)));
    for (const items of settled) found.push(...items);

    if (found.length && process.env.STOP_ON_FOUND === "1") break;
    if (i % (concurrency * 10) === 0) {
      console.error(`[${name}] at block ${Math.max(start, slice[slice.length - 1] - batchSize + 1)}, found=${found.length}`);
    }
  }

  return found;
}

async function main() {
  const networkArg = process.argv[2] || "both";
  const blocksBack = Number(process.argv[3] || 100000);
  const batchSize = Number(process.argv[4] || 50);
  const names = networkArg === "both" ? Object.keys(NETWORKS) : [networkArg];
  const all = [];
  for (const name of names) {
    all.push(...await scanNetwork(name, NETWORKS[name], blocksBack, batchSize));
  }
  console.log(JSON.stringify(all, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
