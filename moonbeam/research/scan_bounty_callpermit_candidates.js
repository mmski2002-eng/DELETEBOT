const { ethers } = require("ethers");

const CALL_PERMIT = "0x000000000000000000000000000000000000080a";
const DISPATCH_SELECTOR = "0xb5ea0966";
const CP_IFACE = new ethers.Interface([
  "function dispatch(address from,address to,uint256 value,bytes data,uint64 gaslimit,uint256 deadline,uint8 v,bytes32 r,bytes32 s)",
  "function nonces(address owner) view returns(uint256)",
]);

const NETWORKS = {
  moonbeam: {
    chainId: 1284,
    explorer: "https://moonbeam.moonscan.io/tx/",
    rpcs: [
      process.env.MOONBEAM_RPC,
      "https://moonbeam-rpc.publicnode.com",
      "https://moonbeam.api.onfinality.io/public",
      "https://rpc.api.moonbeam.network",
      "https://moonbeam.unitedbloc.com",
    ].filter(Boolean),
  },
  moonriver: {
    chainId: 1285,
    explorer: "https://moonriver.moonscan.io/tx/",
    rpcs: [
      process.env.MOONRIVER_RPC,
      "https://moonriver-rpc.publicnode.com",
      "https://moonriver.api.onfinality.io/public",
      "https://rpc.api.moonriver.moonbeam.network",
      "https://moonriver.unitedbloc.com",
    ].filter(Boolean),
  },
};

const selectors = {
  "0x095ea7b3": "approve(address,uint256)",
  "0xa9059cbb": "transfer(address,uint256)",
  "0x23b872dd": "transferFrom(address,address,uint256)",
  "0x38ed1739": "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
  "0x18cbafe5": "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
  "0x7ff36ab5": "swapExactETHForTokens(uint256,address[],address,uint256)",
  "0x414bf389": "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
  "0xc04b8d59": "exactInput((bytes,address,uint256,uint256,uint256))",
  "0x4e71d92d": "claim()",
  "0x2e1a7d4d": "withdraw(uint256)",
  "0xdb006a75": "redeem(uint256)",
  "0x1249c58b": "mint()",
  "0xa0712d68": "mint(uint256)",
  "0xa6f2ae3a": "buy(uint256)",
  "0x6a627842": "mint(address)",
  "0xfaa1786f": "setAutoCompound(address,uint8,uint256,uint256)",
  "0xc90eee83": "cancelDelegationRequest(address)",
  "0x1a1c740c": "scheduleRevokeDelegation(address)",
};

const prioritySelectors = new Set([
  "0x095ea7b3", "0xa9059cbb", "0x23b872dd", "0x38ed1739", "0x18cbafe5", "0x7ff36ab5",
  "0x414bf389", "0xc04b8d59", "0x4e71d92d", "0x2e1a7d4d", "0xdb006a75", "0x1249c58b",
  "0xa0712d68", "0xa6f2ae3a", "0x6a627842", "0xfaa1786f", "0xc90eee83", "0x1a1c740c",
]);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function usage() {
  console.error("usage: node scan_bounty_callpermit_candidates.js <network> <blocksBack> <batchSize> [endBlockDecimal]");
  process.exit(1);
}

function hx(n) { return "0x" + BigInt(n).toString(16); }

async function rpc(url, method, params, attempt = 0) {
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const body = await res.json();
    if (body.error) throw new Error(`${body.error.code}: ${body.error.message}`);
    return body.result;
  } catch (e) {
    if (attempt >= Number(process.env.SCAN_RETRIES || 5)) throw e;
    await sleep(Number(process.env.SCAN_RETRY_MS || 750) * (attempt + 1));
    return rpc(url, method, params, attempt + 1);
  }
}

async function batchRpc(url, calls, attempt = 0) {
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(calls.map((c, i) => ({ jsonrpc: "2.0", id: i, ...c }))),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const body = await res.json();
    if (!Array.isArray(body)) throw new Error(JSON.stringify(body).slice(0, 200));
    body.sort((a, b) => a.id - b.id);
    return body.map((x) => {
      if (x.error) throw new Error(`${x.error.code}: ${x.error.message}`);
      return x.result;
    });
  } catch (e) {
    if (attempt >= Number(process.env.SCAN_RETRIES || 5)) throw e;
    await sleep(Number(process.env.SCAN_RETRY_MS || 750) * (attempt + 1));
    return batchRpc(url, calls, attempt + 1);
  }
}

function innerSelector(data) {
  return data && data.length >= 10 ? data.slice(0, 10).toLowerCase() : "0x";
}

function hasNestedSensitive(data) {
  const lower = (data || "").toLowerCase();
  return [...prioritySelectors].find((s) => lower.includes(s.slice(2)));
}

async function firstWorkingRpc(rpcs) {
  for (const url of rpcs) {
    try {
      const block = await rpc(url, "eth_blockNumber", []);
      await rpc(url, "eth_getBlockReceipts", [block]);
      return url;
    } catch (e) {
      console.error(`skip rpc ${url}: ${e.message}`);
    }
  }
  throw new Error("no usable RPC");
}

async function nonceAt(provider, from, blockNumber) {
  const data = CP_IFACE.encodeFunctionData("nonces", [from]);
  const res = await provider.call({ to: CALL_PERMIT, data }, blockNumber);
  return CP_IFACE.decodeFunctionResult("nonces", res)[0];
}

async function analyzeCandidate(cfg, provider, receipt, tx, block) {
  let d;
  try { d = CP_IFACE.decodeFunctionData("dispatch", tx.input); } catch { return null; }
  if (BigInt(d.deadline) < BigInt(block.timestamp)) return null;

  let nonceBefore;
  try { nonceBefore = await nonceAt(provider, d.from, receipt.blockNumber - 1); } catch { return null; }

  const domain = {
    name: "Call Permit Precompile",
    version: "1",
    chainId: cfg.chainId,
    verifyingContract: CALL_PERMIT,
  };
  const types = {
    CallPermit: [
      { name: "from", type: "address" },
      { name: "to", type: "address" },
      { name: "value", type: "uint256" },
      { name: "data", type: "bytes" },
      { name: "gaslimit", type: "uint64" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  };
  const msg = {
    from: d.from,
    to: d.to,
    value: d.value,
    data: d.data,
    gaslimit: d.gaslimit,
    nonce: nonceBefore,
    deadline: d.deadline,
  };
  let recovered;
  try {
    const sig = ethers.Signature.from({ v: Number(d.v), r: d.r, s: d.s });
    recovered = ethers.verifyTypedData(domain, types, msg, sig.serialized);
  } catch {
    return null;
  }
  if (recovered.toLowerCase() !== d.from.toLowerCase()) return null;

  let nonceAfter = null;
  try { nonceAfter = await nonceAt(provider, d.from, receipt.blockNumber); } catch {}
  if (nonceAfter !== null && nonceAfter !== nonceBefore) return null;

  const sel = innerSelector(d.data);
  const nested = hasNestedSensitive(d.data);
  const targetCode = await provider.getCode(d.to, receipt.blockNumber);
  const targetCodeHash = targetCode === "0x" ? null : ethers.keccak256(targetCode);

  const txHash = receipt.transactionHash || receipt.hash;
  const blockNumber = Number(receipt.blockNumber);

  return {
    network: cfg.name,
    txHash,
    explorer: cfg.explorer + txHash,
    block: blockNumber,
    blockTimestamp: block.timestamp,
    dispatcher: tx.from,
    signedFrom: d.from,
    targetTo: d.to,
    value: d.value.toString(),
    gaslimit: d.gaslimit.toString(),
    deadline: d.deadline.toString(),
    nonceBefore: nonceBefore.toString(),
    nonceAfter: nonceAfter?.toString(),
    v: d.v.toString(),
    r: d.r,
    s: d.s,
    innerSelector: sel,
    innerName: selectors[sel] || "unknown",
    priority: prioritySelectors.has(sel) || !!nested,
    nestedSensitiveSelector: nested || null,
    nestedSensitiveName: nested ? selectors[nested] : null,
    targetCodeLen: (targetCode.length - 2) / 2,
    targetCodeHash,
    innerData: d.data,
  };
}

async function main() {
  const net = process.argv[2];
  if (!NETWORKS[net]) usage();
  const blocksBack = Number(process.argv[3] || 50000);
  const batchSize = Number(process.argv[4] || 100);
  const cfg = { ...NETWORKS[net], name: net };
  const rpcUrl = await firstWorkingRpc(cfg.rpcs);
  console.error(`[${net}] using ${rpcUrl}`);
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const latest = process.argv[5] ? Number(process.argv[5]) : Number(await provider.getBlockNumber());
  const start = Math.max(0, latest - blocksBack + 1);
  const concurrency = Number(process.env.SCAN_CONCURRENCY || 2);
  const progressEvery = Number(process.env.SCAN_PROGRESS_EVERY || 10);
  const fs = process.env.OUT_JSONL ? require("fs") : null;
  if (fs) fs.writeFileSync(process.env.OUT_JSONL, "");
  const out = [];
  const ranges = [];
  for (let from = latest; from >= start; from -= batchSize) ranges.push(from);
  console.error(`[${net}] scanning ${start}..${latest}`);

  async function scanBatch(from) {
    const to = Math.max(start, from - batchSize + 1);
    const calls = [];
    for (let n = from; n >= to; n--) calls.push({ method: "eth_getBlockReceipts", params: [hx(n)] });
    const groups = await batchRpc(rpcUrl, calls);
    const local = [];
    for (let i = 0; i < groups.length; i++) {
      const blockNum = from - i;
      const receipts = groups[i] || [];
      const failed = receipts.filter((r) => (r.to || "").toLowerCase() === CALL_PERMIT && r.status === "0x0");
      if (!failed.length) continue;
      const block = await provider.getBlock(blockNum);
      for (const rec of failed) {
        const tx = await provider.getTransaction(rec.transactionHash || rec.hash);
        if (!tx?.data?.toLowerCase().startsWith(DISPATCH_SELECTOR)) continue;
        const item = await analyzeCandidate(cfg, provider, rec, { ...tx, input: tx.data }, block);
        if (item) local.push(item);
      }
    }
    return local;
  }

  for (let i = 0; i < ranges.length; i += concurrency) {
    const chunk = ranges.slice(i, i + concurrency);
    const settled = await Promise.allSettled(chunk.map(scanBatch));
    for (const s of settled) {
      if (s.status === "fulfilled") {
        out.push(...s.value);
        if (fs && s.value.length) {
          fs.appendFileSync(process.env.OUT_JSONL, s.value.map((x) => JSON.stringify(x)).join("\n") + "\n");
        }
      }
      else console.error(`[${net}] batch error: ${s.reason.message}`);
    }
    if (i % (concurrency * progressEvery) === 0) console.error(`[${net}] progress block ${Math.max(start, chunk.at(-1) - batchSize + 1)} candidates=${out.length}`);
    if (out.some((x) => x.priority) && process.env.STOP_ON_PRIORITY === "1") break;
  }
  console.log(JSON.stringify(out, null, 2));
}

main().catch((e) => { console.error(e); process.exit(1); });
