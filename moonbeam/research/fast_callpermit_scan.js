// High-throughput failed CallPermit scanner
// Strategy: concurrent batch eth_getBlockReceipts (5 concurrent × 100 blocks = 500 bl/s)
"use strict";

const fs = require("fs");

const CALLPERMIT   = "0x000000000000000000000000000000000000080a";
const DISPATCH_SEL = "0xb5ea0966";
const DPS          = "0xd1a9ba3e61ac676f58b29ea0a09cf5d7f4f35138";
const TMAP         = "0x0e67601818237834fF8A280312a6F4F4934e6283";
const MOONBEANS    = "0x683724817a7d526d6256aec0d6f8ddf541b924de";

const FINANCIAL = new Set([
  "0xdb76d5b3", // buyVoyages
  "0xa9059cbb", // transfer
  "0x23b872dd", // transferFrom
  "0x095ea7b3", // approve
  "0x4b29e822", // acceptOffer
  "0x2e1a7d4d", // withdraw
  "0x4e71d92d", // claim
  "0x42842e0e", // safeTransferFrom ERC721
  "0xf242432a", // safeTransferFrom ERC1155
]);

const RPCS = [
  "https://rpc.api.moonbeam.network",
  "https://moonbeam-rpc.publicnode.com",
  "https://moonbeam.api.onfinality.io/public",
  "https://moonbeam.unitedbloc.com",
];

const sleep = ms => new Promise(r => setTimeout(r, ms));

// Round-robin RPC with per-endpoint index
let rpcIdx = 0;
function nextRpc() { return RPCS[rpcIdx++ % RPCS.length]; }

async function batchReceipts(blockNums, attempt = 0) {
  const url = nextRpc();
  try {
    const payload = blockNums.map((n, i) => ({
      jsonrpc: "2.0", id: i,
      method: "eth_getBlockReceipts",
      params: ["0x" + n.toString(16)],
    }));
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(20000),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const body = await res.json();
    if (!Array.isArray(body)) {
      if (body.error?.code === -32011) throw Object.assign(new Error("BATCH_TOO_LARGE"), { batchTooLarge: true });
      throw new Error(JSON.stringify(body).slice(0, 200));
    }
    body.sort((a, b) => a.id - b.id);
    return body.map(x => x.result ?? []);
  } catch (e) {
    if (e.batchTooLarge && attempt === 0) {
      // Split into two halves
      const mid = Math.floor(blockNums.length / 2);
      const [left, right] = await Promise.all([
        batchReceipts(blockNums.slice(0, mid), 0),
        batchReceipts(blockNums.slice(mid), 0),
      ]);
      return [...left, ...right];
    }
    if (attempt >= 3) return blockNums.map(() => []);
    await sleep(600 * (attempt + 1));
    return batchReceipts(blockNums, attempt + 1);
  }
}

function decodeDispatch(input) {
  if (!input || !input.startsWith(DISPATCH_SEL)) return null;
  try {
    const d = input.slice(10);
    const from      = "0x" + d.slice(24, 64);
    const to        = "0x" + d.slice(88, 128);
    const dataOff   = parseInt(d.slice(192, 256), 16) * 2;
    const dataLen   = parseInt(d.slice(dataOff, dataOff + 64), 16) * 2;
    const innerData = "0x" + d.slice(dataOff + 64, dataOff + 64 + dataLen);
    const deadline  = BigInt("0x" + d.slice(320, 384));
    const v         = Number("0x" + d.slice(384, 448));
    const r         = "0x" + d.slice(448, 512);
    const s         = "0x" + d.slice(512, 576);
    return { from: from.toLowerCase(), to: to.toLowerCase(), innerData, deadline, v, r, s };
  } catch { return null; }
}

function filterReceipts(receipts, blockNum) {
  const hits = [];
  for (const rec of (receipts || [])) {
    if (!rec.to || rec.to.toLowerCase() !== CALLPERMIT) continue;
    if (rec.status !== "0x0") continue;
    if (!rec.input?.startsWith(DISPATCH_SEL)) continue;

    const d = decodeDispatch(rec.input);
    if (!d) continue;

    const innerSel = d.innerData.slice(0, 10).toLowerCase();
    const isDPS      = d.to === DPS;
    const isMB       = d.to === MOONBEANS;
    const isFinancial = FINANCIAL.has(innerSel);

    if (!isDPS && !isMB && !isFinancial) continue;

    hits.push({
      txHash: rec.transactionHash,
      blockNum,
      signer:    d.from,
      target:    d.to,
      innerSel,
      innerData: d.innerData,
      deadline:  Number(d.deadline),
      input:     rec.input,
      isDPS, isMB, isFinancial,
    });
  }
  return hits;
}

async function scanRange(start, end, batchSize = 80, concurrent = 5) {
  const candidates = [];
  const total = end - start + 1;
  let done = 0;
  const t0 = Date.now();

  for (let b = start; b <= end; b += batchSize * concurrent) {
    // Build concurrent groups
    const groups = [];
    for (let g = 0; g < concurrent; g++) {
      const gStart = b + g * batchSize;
      if (gStart > end) break;
      const gEnd = Math.min(gStart + batchSize - 1, end);
      const nums = [];
      for (let i = gStart; i <= gEnd; i++) nums.push(i);
      groups.push(nums);
    }

    const results = await Promise.all(groups.map(nums => batchReceipts(nums)));

    for (let g = 0; g < groups.length; g++) {
      for (let i = 0; i < groups[g].length; i++) {
        const blockNum  = groups[g][i];
        const receipts  = results[g]?.[i];
        const hits = filterReceipts(receipts, blockNum);
        candidates.push(...hits);
        done++;
      }
    }

    if (done % 5000 < batchSize * concurrent) {
      const elapsed = (Date.now() - t0) / 1000;
      const bps = done / elapsed;
      const remaining = (total - done) / bps;
      const pct = ((done / total) * 100).toFixed(1);
      const eta = remaining < 60 ? `${remaining.toFixed(0)}s` : `${(remaining/60).toFixed(1)}m`;
      console.log(`  block ${b} | ${pct}% | ${bps.toFixed(0)} bl/s | eta ${eta} | found ${candidates.length}`);
    }
  }

  return candidates;
}

async function ethCall(to, data, block, attempt = 0) {
  const url = nextRpc();
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_call", params: [{ to, data }, block] }),
      signal: AbortSignal.timeout(10000),
    });
    const body = await res.json();
    return body.result ?? null;
  } catch {
    if (attempt >= 2) return null;
    await sleep(400);
    return ethCall(to, data, block, attempt + 1);
  }
}

function pad(addr) { return addr.replace("0x", "").padStart(64, "0"); }
function hx(n) { return "0x" + BigInt(n).toString(16); }

async function analyzeCandidate(c) {
  const bHex  = hx(c.blockNum);
  const bPrev = hx(c.blockNum - 1);

  const nonceSel = "0x7ecebe00";
  const [nb, na, nn] = await Promise.all([
    ethCall(CALLPERMIT, nonceSel + pad(c.signer), bPrev),
    ethCall(CALLPERMIT, nonceSel + pad(c.signer), bHex),
    ethCall(CALLPERMIT, nonceSel + pad(c.signer), "latest"),
  ]);

  const nBefore = nb ? BigInt(nb) : null;
  const nAfter  = na ? BigInt(na) : null;
  const nNow    = nn ? BigInt(nn) : null;
  const rolled  = nBefore !== null && nAfter !== null && nBefore === nAfter;

  // Token balance
  let tokenAddr = null;
  if (c.isDPS) tokenAddr = TMAP;
  else if (["0xa9059cbb","0x23b872dd","0x095ea7b3"].includes(c.innerSel)) tokenAddr = c.target;

  let balBefore = null, balNow = null;
  if (tokenAddr) {
    const balSel = "0x70a08231";
    const [bb, bn] = await Promise.all([
      ethCall(tokenAddr, balSel + pad(c.signer), bPrev),
      ethCall(tokenAddr, balSel + pad(c.signer), "latest"),
    ]);
    balBefore = bb && bb !== "0x" ? BigInt(bb) : 0n;
    balNow    = bn && bn !== "0x" ? BigInt(bn) : 0n;
  }

  const expired  = Date.now() / 1000 > c.deadline;
  const consumed = nNow !== null && nBefore !== null && nNow > nBefore;
  const live     = rolled && !consumed && !expired;

  let simResult = null;
  if (rolled && !consumed) {
    const r = await ethCall(CALLPERMIT, c.input.replace(/^(0x)?/, "0x"), "latest");
    // Actually need to use eth_call with from
    try {
      const res = await fetch(nextRpc(), {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          jsonrpc: "2.0", id: 1,
          method: "eth_call",
          params: [{ to: CALLPERMIT, data: c.input, from: "0x000000000000000000000000000000000000dead" }, "latest"],
        }),
        signal: AbortSignal.timeout(10000),
      });
      const body = await res.json();
      if (body.result) simResult = body.result === "0x01" ? "SUCCESS" : `RESULT:${body.result.slice(0,20)}`;
      else if (body.error) simResult = `REVERT:${body.error.message?.slice(0,80)}`;
    } catch { simResult = "TIMEOUT"; }
  }

  const fmt = v => v !== null ? (v / 10n**18n).toString() : "N/A";

  return {
    ...c,
    deadline: undefined, // remove raw
    deadlineHuman: new Date(c.deadline * 1000).toISOString(),
    nonceBefore: nBefore?.toString() ?? null,
    nonceAfter:  nAfter?.toString()  ?? null,
    nonceNow:    nNow?.toString()    ?? null,
    nonceRolledBack: rolled,
    nonceConsumed: consumed,
    tokenAddr,
    balBefore: balBefore?.toString() ?? null,
    balNow:    balNow?.toString()    ?? null,
    deadlineExpired: expired,
    liveReplay: live,
    simResult,
  };
}

async function main() {
  const curHex = await (async () => {
    const r = await fetch(RPCS[0], {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_blockNumber", params: [] }),
    }).then(r => r.json());
    return parseInt(r.result, 16);
  })();

  console.log(`Current block: ${curHex}`);

  const RANGES = [
    // DPS launch + early period (~1.15M blocks total)
    { start: 2847509, end: 3200000,  label: "DPS launch 2.8M-3.2M" },
    { start: 3200000, end: 4000000,  label: "DPS early 3.2M-4.0M" },
    // Mid Moonbeam
    { start: 5000000, end: 6000000,  label: "mid 5M-6M" },
    { start: 8000000, end: 9000000,  label: "mid 8M-9M" },
    // Recent
    { start: curHex - 200000, end: curHex, label: "recent 200k" },
  ];

  const allCandidates = [];

  for (const { start, end, label } of RANGES) {
    const blocks = end - start;
    console.log(`\n[scan] ${label} (${blocks.toLocaleString()} blocks)`);
    const hits = await scanRange(start, end, 80, 5);
    console.log(`[scan] ${label}: ${hits.length} candidates`);
    allCandidates.push(...hits);
  }

  console.log(`\nTotal raw candidates: ${allCandidates.length}`);

  if (allCandidates.length === 0) {
    console.log("None found. DPS/financial selectors not used via failed CallPermit in scanned ranges.");
    const out = { ranges: RANGES.map(r => ({ ...r, blocks: r.end - r.start })), candidates: [] };
    fs.writeFileSync("research/insufficient_balance_replay_report.json", JSON.stringify(out, null, 2));
    return;
  }

  console.log(`\n[analyze] ${allCandidates.length} candidates...`);
  const analyzed = [];
  for (const c of allCandidates) {
    try {
      const r = await analyzeCandidate(c);
      analyzed.push(r);
      const tag = r.liveReplay ? "🔴 LIVE" :
                  r.nonceRolledBack && !r.nonceConsumed ? "🟡 OPEN" :
                  r.nonceRolledBack ? "🟢 HIST" : "⚪";
      const bal = r.balBefore !== null
        ? `bal=${BigInt(r.balBefore)/10n**18n}→${BigInt(r.balNow??0)/10n**18n}`
        : "";
      console.log(`${tag} blk=${r.blockNum} sel=${r.innerSel} ${bal} ${r.txHash}`);
      if (r.simResult) console.log(`     sim: ${r.simResult}`);
    } catch (e) {
      console.error(`analyze error ${c.txHash}: ${e.message}`);
    }
    await sleep(30);
  }

  const str = (_, v) => typeof v === "bigint" ? v.toString() : v;
  fs.writeFileSync("research/insufficient_balance_replay_report.json",
    JSON.stringify({ ranges: RANGES, candidates: analyzed }, str, 2));

  const live = analyzed.filter(x => x.liveReplay);
  const hist = analyzed.filter(x => x.nonceRolledBack);
  console.log(`\n=== RESULTS ===`);
  console.log(`Live: ${live.length} | Historical rollback: ${hist.length} | Total: ${analyzed.length}`);

  if (live.length) {
    for (const c of live) {
      console.log(`🔴 ${c.txHash} signer=${c.signer} deadline=${c.deadlineHuman} sim=${c.simResult}`);
    }
  }
}

main().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
