// Targeted scanner: failed CallPermit dispatches to DPS / ERC-20 transfers
// Uses parallel single requests (not batched) for speed
"use strict";

const fs = require("fs");

const CALLPERMIT   = "0x000000000000000000000000000000000000080a";
const DISPATCH_SEL = "0xb5ea0966";
const DPS          = "0xd1a9ba3e61ac676f58b29ea0a09cf5d7f4f35138";
const TMAP         = "0x0e67601818237834fF8A280312a6F4F4934e6283";
const MOONBEANS    = "0x683724817a7d526d6256aec0d6f8ddf541b924de";

const BUYVOYAGES_SEL   = "0xdb76d5b3";
const TRANSFER_SEL     = "0xa9059cbb";
const TRANSFERFROM_SEL = "0x23b872dd";
const APPROVE_SEL      = "0x095ea7b3";
const ACCEPT_OFFER_SEL = "0x4b29e822";
const WITHDRAW_SEL     = "0x2e1a7d4d";
const CLAIM_SEL        = "0x4e71d92d";

const FINANCIAL = new Set([
  BUYVOYAGES_SEL, TRANSFER_SEL, TRANSFERFROM_SEL, APPROVE_SEL,
  ACCEPT_OFFER_SEL, WITHDRAW_SEL, CLAIM_SEL,
]);

const RPCS = [
  "https://rpc.api.moonbeam.network",
  "https://moonbeam-rpc.publicnode.com",
  "https://moonbeam.api.onfinality.io/public",
  "https://moonbeam.unitedbloc.com",
];

let ri = 0;
const rpc = () => RPCS[ri++ % RPCS.length];
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function ethRpc(method, params, attempt = 0) {
  const url = rpc();
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
      signal: AbortSignal.timeout(12000),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const body = await res.json();
    if (body.error) throw new Error(JSON.stringify(body.error).slice(0, 200));
    return body.result;
  } catch (e) {
    if (attempt >= 3) return null;
    await sleep(500 * (attempt + 1));
    return ethRpc(method, params, attempt + 1);
  }
}

function hx(n) { return "0x" + BigInt(n).toString(16); }
function pad(addr) { return addr.replace("0x", "").padStart(64, "0"); }

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

async function getBlockReceipts(blockNum) {
  return ethRpc("eth_getBlockReceipts", [hx(blockNum)]);
}

async function ethCall(to, data, blockHex) {
  const r = await ethRpc("eth_call", [{ to, data }, blockHex]);
  return r;
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

async function scanBlock(blockNum) {
  const receipts = await getBlockReceipts(blockNum);
  if (!receipts) return [];

  const hits = [];
  for (const rec of receipts) {
    if (!rec.to || rec.to.toLowerCase() !== CALLPERMIT) continue;
    if (rec.status !== "0x0") continue;
    if (!rec.input || !rec.input.startsWith(DISPATCH_SEL)) continue;

    const d = decodeDispatch(rec.input);
    if (!d) continue;

    const innerSel = d.innerData.slice(0, 10).toLowerCase();
    const isDPS       = d.to === DPS;
    const isMoonBeans = d.to === MOONBEANS;
    const isFinancial = FINANCIAL.has(innerSel);

    if (!isDPS && !isMoonBeans && !isFinancial) continue;

    hits.push({
      txHash:   rec.transactionHash,
      blockNum,
      signer:   d.from,
      target:   d.to,
      innerSel,
      innerData: d.innerData,
      deadline:  Number(d.deadline),
      input:     rec.input,
      isDPS,
      isMoonBeans,
      isFinancial,
    });
  }
  return hits;
}

async function scanRange(start, end, concurrency = 20) {
  const candidates = [];
  let done = 0;
  const total = end - start + 1;

  for (let b = start; b <= end; b += concurrency) {
    const batch = [];
    for (let i = 0; i < concurrency && b + i <= end; i++) {
      batch.push(scanBlock(b + i));
    }
    const results = await Promise.all(batch);
    for (const hits of results) candidates.push(...hits);
    done += batch.length;

    const pct = ((done / total) * 100).toFixed(1);
    if (done % 2000 < concurrency) {
      process.stdout.write(`\r[scan] ${b + concurrency - 1} | ${pct}% | found ${candidates.length}`);
    }
  }
  process.stdout.write("\n");
  return candidates;
}

async function analyzeCandidate(c) {
  const bHex  = hx(c.blockNum);
  const bPrev = hx(c.blockNum - 1);

  const [nBefore, nAfter, nNow] = await Promise.all([
    getNonce(c.signer, bPrev),
    getNonce(c.signer, bHex),
    getNonce(c.signer, "latest"),
  ]);

  const rolled = nBefore !== null && nAfter !== null && nBefore === nAfter;

  // Determine which token to check
  let tokenAddr = null;
  if (c.isDPS) tokenAddr = TMAP;
  else if (c.innerSel === TRANSFER_SEL || c.innerSel === TRANSFERFROM_SEL) tokenAddr = c.target;
  else if (c.innerSel === APPROVE_SEL) tokenAddr = c.target;

  let balBefore = null, balNow = null;
  if (tokenAddr) {
    [balBefore, balNow] = await Promise.all([
      getBalance(tokenAddr, c.signer, bPrev),
      getBalance(tokenAddr, c.signer, "latest"),
    ]);
  }

  const expired  = Date.now() / 1000 > c.deadline;
  const consumed = nNow !== null && nBefore !== null && nNow > nBefore;
  const live     = rolled && !consumed && !expired && (balNow === null || balNow > 0n);

  let simResult = null;
  if (rolled && !consumed) {
    const r = await ethRpc("eth_call", [{
      to:   CALLPERMIT,
      data: c.input,
      from: "0x000000000000000000000000000000000000dead",
    }, "latest"]);
    simResult = r === "0x01" ? "SUCCESS" : (r ? `RESULT:${r.slice(0, 20)}` : "EMPTY");
    if (!r) {
      // Try to get revert reason
      simResult = "REVERT (no data)";
    }
  }

  return {
    ...c,
    nonceBefore:  nBefore?.toString() ?? null,
    nonceAfter:   nAfter?.toString()  ?? null,
    nonceNow:     nNow?.toString()    ?? null,
    nonceRolledBack: rolled,
    nonceConsumed:   consumed,
    tokenAddr,
    balBefore:  balBefore?.toString() ?? null,
    balNow:     balNow?.toString()    ?? null,
    deadlineExpired: expired,
    deadlineHuman:   new Date(c.deadline * 1000).toISOString(),
    liveReplay: live,
    simResult,
  };
}

function fmt18(v) {
  if (v === null || v === undefined) return "N/A";
  const n = BigInt(v);
  const whole = n / 10n**18n;
  const frac  = ((n % 10n**18n) * 100n / 10n**18n).toString().padStart(2, "0");
  return `${whole}.${frac}`;
}

async function main() {
  const cur = parseInt(await ethRpc("eth_blockNumber", []), 16);
  console.log(`Current block: ${cur}`);

  // Priority scan ranges (DPS period + recent)
  const RANGES = [
    // DPS early activity
    { start: 2847509, end: 4000000,  label: "DPS launch period" },
    // Mid period
    { start: 6000000, end: 7000000,  label: "mid period 6M-7M" },
    { start: 9000000, end: 10000000, label: "mid period 9M-10M" },
    // Recent
    { start: cur - 100000, end: cur, label: "recent 100k" },
  ];

  const allCandidates = [];

  for (const { start, end, label } of RANGES) {
    console.log(`\n[scan] ${label}: blocks ${start}–${end} (${end - start} blocks)`);
    const hits = await scanRange(start, end, 20);
    console.log(`[scan] ${label}: ${hits.length} candidates`);
    allCandidates.push(...hits);
  }

  if (allCandidates.length === 0) {
    console.log("\nNo candidates found. DPS/transfer not used via failed CallPermit in scanned ranges.");
    fs.writeFileSync("research/insufficient_balance_replay_report.json",
      JSON.stringify({ ranges: RANGES, candidates: [] }, null, 2));
    return;
  }

  console.log(`\n[analyze] ${allCandidates.length} candidates...`);
  const analyzed = [];
  for (const c of allCandidates) {
    try {
      const r = await analyzeCandidate(c);
      analyzed.push(r);

      const tag = r.liveReplay ? "🔴 LIVE" :
                  (r.nonceRolledBack && !r.nonceConsumed) ? "🟡 OPEN" :
                  r.nonceRolledBack ? "🟢 HIST" : "⚪";

      const balStr = r.balBefore !== null
        ? `bal_before=${fmt18(r.balBefore)} bal_now=${fmt18(r.balNow)}`
        : "";

      console.log(`${tag} ${r.txHash} blk=${r.blockNum} sel=${r.innerSel} ${balStr}`);
      if (r.simResult) console.log(`     sim: ${r.simResult}`);
    } catch (e) {
      console.error(`[analyze] ${c.txHash}: ${e.message}`);
    }
    await sleep(50);
  }

  const str = (_, v) => typeof v === "bigint" ? v.toString() : v;
  fs.writeFileSync("research/insufficient_balance_replay_report.json",
    JSON.stringify({ ranges: RANGES, candidates: analyzed }, null, str, 2));

  const live = analyzed.filter(x => x.liveReplay);
  const hist = analyzed.filter(x => x.nonceRolledBack);

  console.log("\n=== SUMMARY ===");
  console.log(`Live replay: ${live.length}`);
  console.log(`Historical rollback: ${hist.length}`);
  console.log(`Total: ${analyzed.length}`);

  if (live.length) {
    console.log("\n🔴 LIVE:");
    for (const c of live) {
      console.log(`  ${c.txHash} signer=${c.signer} deadline=${c.deadlineHuman}`);
      console.log(`  balNow=${fmt18(c.balNow)} sim=${c.simResult}`);
    }
  }
  if (hist.length && !live.length) {
    console.log("\n🟢 BEST HISTORICAL:");
    const best = hist.sort((a, b) => (b.balBefore ?? "0").localeCompare(a.balBefore ?? "0"))[0];
    console.log(`  ${best.txHash} blk=${best.blockNum} sel=${best.innerSel}`);
    console.log(`  bal_before=${fmt18(best.balBefore)} nonce_rolled=${best.nonceRolledBack}`);
  }

  console.log("\nSaved: research/insufficient_balance_replay_report.json");
}

main().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
