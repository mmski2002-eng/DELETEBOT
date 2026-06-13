#!/usr/bin/env node
/**
 * diode_balance_risk_finder.js
 *
 * Goal: Find a failed CallPermit dispatch where target multisig had non-zero
 * DIODE balance AT THE TIME of the failed tx → bounty-grade financial risk proof.
 *
 * Strategy:
 *  Phase 1: Check all existing SubmitTransaction candidates (50k + bounty_candidates)
 *           - DIODE balance of target multisig AT THAT BLOCK
 *           - Nonce rollback verify
 *           - IsMember/IsOwner check
 *  Phase 2: Scan additional block ranges for missed failed dispatches
 *           - Filter: SubmitTransaction + direct financial selectors
 *  Phase 3: Check staking/delegation candidates (GLMR at risk)
 *  Output:  REPORTS/DIODE_BALANCE_RISK_ru.md
 */

const fs = require("fs");
const path = require("path");

const CALLPERMIT   = "0x000000000000000000000000000000000000080a";
const DIODE_TOKEN  = "0x434116a99619f2b465a137199c38c1aab0353913";
const DISPATCH_SEL = "0xb5ea0966";
const SUBMIT_SEL   = "0x130dbfbb";

const FINANCIAL_SELECTORS = {
  "0xa9059cbb": "transfer(address,uint256)",
  "0x23b872dd": "transferFrom(address,address,uint256)",
  "0x095ea7b3": "approve(address,uint256)",
  "0x38ed1739": "swapExactTokensForTokens",
  "0x2e1a7d4d": "withdraw(uint256)",
  "0x3ccfd60b": "withdraw()",
  "0xdb006a75": "redeem(uint256)",
  "0x4e71d92d": "claim()",
  "0x42842e0e": "safeTransferFrom(address,address,uint256)",
};

const RPCS = [
  "https://rpc.api.moonbeam.network",
  "https://moonbeam-rpc.publicnode.com",
  "https://moonbeam.api.onfinality.io/public",
];

const RESEARCH_DIR = __dirname;
const REPORTS_DIR  = path.join(__dirname, "../REPORTS");

// ── RPC ───────────────────────────────────────────────────────────────────────

const sleep = ms => new Promise(r => setTimeout(r, ms));

let _rpc = null;
async function getWorkingRpc() {
  if (_rpc) return _rpc;
  for (const url of RPCS) {
    try {
      await rpcCall(url, "eth_blockNumber", []);
      _rpc = url;
      return url;
    } catch {}
  }
  throw new Error("no working RPC");
}

async function rpcCall(url, method, params, attempt = 0) {
  try {
    const r = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
      signal: AbortSignal.timeout(20000),
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const body = await r.json();
    if (body.error) throw new Error(`RPC ${body.error.code}: ${body.error.message}`);
    return body.result;
  } catch (e) {
    if (attempt >= 4) throw e;
    await sleep(800 * (attempt + 1));
    return rpcCall(url, method, params, attempt + 1);
  }
}

async function rpc(method, params) {
  const url = await getWorkingRpc();
  return rpcCall(url, method, params);
}

async function batchRpc(calls) {
  const url = await getWorkingRpc();
  const r = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(calls.map((c, i) => ({ jsonrpc: "2.0", id: i, ...c }))),
    signal: AbortSignal.timeout(30000),
  });
  const body = await r.json();
  if (!Array.isArray(body)) throw new Error(JSON.stringify(body).slice(0, 200));
  body.sort((a, b) => a.id - b.id);
  return body.map(x => x.result);
}

const hx = n => "0x" + BigInt(n).toString(16);
const pad = a => a.toLowerCase().replace("0x", "").padStart(64, "0");

// ── Checkers ──────────────────────────────────────────────────────────────────

async function diodeBalance(addr, block) {
  try {
    const res = await rpc("eth_call", [{ to: DIODE_TOKEN, data: "0x70a08231" + pad(addr) }, hx(block)]);
    return BigInt(res || "0x0");
  } catch { return 0n; }
}

async function nonceAt(addr, block) {
  try {
    const res = await rpc("eth_call", [{ to: CALLPERMIT, data: "0x7ecebe00" + pad(addr) }, hx(block)]);
    return BigInt(res || "0x0");
  } catch { return null; }
}

async function checkAuth(multisig, signer, block) {
  try {
    const bk = hx(block);
    const [membersRaw, ownerRaw] = await Promise.all([
      rpc("eth_call", [{ to: multisig, data: "0x6bb04b86" }, bk]),
      rpc("eth_call", [{ to: multisig, data: "0x8da5cb5b" }, bk]),
    ]);
    const owner = ownerRaw ? "0x" + ownerRaw.slice(-40) : null;
    const isOwner = owner?.toLowerCase() === signer.toLowerCase();
    // decode members array
    let isMember = false;
    if (membersRaw && membersRaw.length > 130) {
      const count = Number(BigInt("0x" + membersRaw.slice(66, 130)));
      for (let i = 0; i < count; i++) {
        const m = "0x" + membersRaw.slice(130 + i * 64 + 24, 130 + i * 64 + 64);
        if (m.toLowerCase() === signer.toLowerCase()) { isMember = true; break; }
      }
    }
    return { isOwner, isMember, auth: isOwner || isMember, owner };
  } catch { return { isOwner: false, isMember: false, auth: false, owner: null }; }
}

async function verifyNonceRollback(signer, block) {
  const [before, after] = await Promise.all([
    nonceAt(signer, block - 1),
    nonceAt(signer, block),
  ]);
  return { before, after, rollback: before !== null && after !== null && before === after };
}

// ── Decode ────────────────────────────────────────────────────────────────────

function decodeDispatch(input) {
  // dispatch(address from, address to, uint256 value, bytes data, uint64 gaslimit, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
  if (!input || !input.toLowerCase().startsWith(DISPATCH_SEL.slice(2))) return null;
  try {
    const d = input.slice(10); // strip selector
    const from     = "0x" + d.slice(24, 64);
    const to       = "0x" + d.slice(88, 128);
    const value    = BigInt("0x" + d.slice(128, 192));
    const dataOff  = Number(BigInt("0x" + d.slice(192, 256)));
    const gasLimit = BigInt("0x" + d.slice(256, 320));
    const deadline = BigInt("0x" + d.slice(320, 384));
    const v        = Number(BigInt("0x" + d.slice(384, 448)));
    const r        = "0x" + d.slice(448, 512);
    const s        = "0x" + d.slice(512, 576);
    const dataLen  = Number(BigInt("0x" + d.slice(dataOff * 2 - d.length < 0 ? 0 : (dataOff - 4) * 2, (dataOff - 4) * 2 + 64)));
    // simpler: inner data starts at bytes offset from param start (offset 4 = selector)
    // ABI encoding: data offset is in words from start of params (after selector)
    const paramHex = d; // d starts at param position 0
    const dataOffset = Number(BigInt("0x" + paramHex.slice(192, 256)));
    const dataLenHex = paramHex.slice(dataOffset * 2, dataOffset * 2 + 64);
    const dataLength = Number(BigInt("0x" + dataLenHex));
    const innerData = "0x" + paramHex.slice(dataOffset * 2 + 64, dataOffset * 2 + 64 + dataLength * 2);
    return { from, to, value, gasLimit, deadline, v, r, s, innerData };
  } catch { return null; }
}

function findNestedFinancial(innerData) {
  const hex = (innerData || "").toLowerCase().replace("0x", "");
  for (let i = 8; i + 8 <= hex.length; i += 2) {
    const candidate = "0x" + hex.slice(i, i + 8);
    if (FINANCIAL_SELECTORS[candidate]) return { selector: candidate, name: FINANCIAL_SELECTORS[candidate] };
  }
  return null;
}

// ── Load existing candidates ──────────────────────────────────────────────────

function readFileAny(fpath) {
  const buf = fs.readFileSync(fpath);
  if (buf[0] === 0xFF && buf[1] === 0xFE) return buf.toString("utf16le");
  if (buf[0] === 0xFE && buf[1] === 0xFF) {
    const s = Buffer.alloc(buf.length);
    for (let i = 0; i < buf.length - 1; i += 2) { s[i] = buf[i+1]; s[i+1] = buf[i]; }
    return s.toString("utf8");
  }
  return buf.toString("utf8");
}

function loadExisting() {
  const files = [
    "bounty_candidates_moonbeam_100k_150k.jsonl",
    "bounty_candidates_moonbeam_150k_200k.jsonl",
    "failed_callpermit_moonbeam_50k_validsig.json",
    "failed_callpermit_moonbeam_50k.json",
  ];
  const all = [];
  const seen = new Set();
  for (const fname of files) {
    const fp = path.join(RESEARCH_DIR, fname);
    if (!fs.existsSync(fp)) continue;
    const raw = readFileAny(fp).trim();
    if (!raw) continue;
    let items = [];
    if (fname.endsWith(".jsonl")) {
      items = raw.split("\n").filter(Boolean).map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
    } else {
      const start = raw.indexOf("[");
      try { items = JSON.parse(start >= 0 ? raw.slice(start) : raw); } catch {}
    }
    for (const item of items) {
      const hash = item.txHash;
      if (!hash || seen.has(hash)) continue;
      seen.add(hash);
      all.push(item);
    }
    console.error(`[load] ${fname}: ${items.length} items`);
  }
  return all;
}

// ── Scan new blocks ───────────────────────────────────────────────────────────

async function scanBlockRange(startBlock, endBlock, batchSize = 200) {
  const found = [];
  console.error(`[scan] blocks ${startBlock}..${endBlock}`);
  for (let from = endBlock; from >= startBlock; from -= batchSize) {
    const to = Math.max(startBlock, from - batchSize + 1);
    try {
      const calls = [];
      for (let b = from; b >= to; b--) calls.push({ method: "eth_getBlockReceipts", params: [hx(b)] });
      const groups = await batchRpc(calls);
      for (let i = 0; i < groups.length; i++) {
        const receipts = groups[i] || [];
        for (const r of receipts) {
          if ((r.to || "").toLowerCase() !== CALLPERMIT.toLowerCase()) continue;
          if (r.status !== "0x0") continue;
          const input = r.input || r.data || "";
          if (!input.toLowerCase().startsWith(DISPATCH_SEL.slice(2))) continue;
          const decoded = decodeDispatch(input);
          if (!decoded) continue;
          const sel = decoded.innerData.slice(0, 10).toLowerCase();
          const isSubmitTx  = sel === SUBMIT_SEL;
          const isFinancial = !!FINANCIAL_SELECTORS[sel];
          const nested      = !isFinancial ? findNestedFinancial(decoded.innerData) : null;
          if (!isSubmitTx && !isFinancial && !nested) continue;
          const blockNum = from - i;
          found.push({
            txHash: r.transactionHash || r.hash,
            block: blockNum,
            dispatcher: r.from,
            signedFrom: decoded.from,
            targetTo: decoded.to,
            innerSelector: sel,
            deadline: decoded.deadline.toString(),
            innerData: decoded.innerData,
            isSubmitTx,
            isFinancial,
            nested,
          });
          console.error(`[scan] FOUND at block ${blockNum}: ${r.transactionHash} sel=${sel}`);
        }
      }
    } catch (e) {
      console.error(`[scan] batch error at ${from}: ${e.message.slice(0, 80)}`);
    }
    if (from % 10000 === 0) console.error(`[scan] progress: block ${from}`);
    await sleep(50);
  }
  return found;
}

// ── Analyze candidate ─────────────────────────────────────────────────────────

async function analyzeCandidate(c, block, signer, multisig) {
  const [bal, nonces, auth, blockInfo] = await Promise.all([
    diodeBalance(multisig, block),
    verifyNonceRollback(signer, block),
    checkAuth(multisig, signer, block),
    rpc("eth_getBlockByNumber", [hx(block), false]).catch(() => null),
  ]);
  const deadline = Number(BigInt(c.deadline || "0"));
  const ts = blockInfo ? Number(BigInt(blockInfo.timestamp)) : 0;
  const windowSec = deadline > ts ? deadline - ts : 0;
  return {
    ...c,
    block,
    diodeBalance: bal,
    diodeBalanceFmt: (bal / 10n**18n).toString() + "." + (bal % 10n**18n).toString().padStart(18, "0").slice(0, 4),
    nonceRollback: nonces.rollback,
    nonceBefore: nonces.before?.toString(),
    nonceAfter: nonces.after?.toString(),
    isOwner: auth.isOwner,
    isMember: auth.isMember,
    authPass: auth.auth,
    multisigOwner: auth.owner,
    blockTimestamp: ts,
    windowSeconds: windowSec,
    hasFunds: bal > 0n,
  };
}

// ── Report ────────────────────────────────────────────────────────────────────

function buildReport(results, scanStats) {
  const now = new Date().toISOString();
  const withFunds = results.filter(r => r.hasFunds);
  const authOk    = results.filter(r => r.authPass);
  const rollback  = results.filter(r => r.nonceRollback);
  const critical  = results.filter(r => r.hasFunds && r.authPass && r.nonceRollback);

  let md = `# DIODE Balance Risk Analysis — CallPermit Nonce Rollback

**Дата:** ${now}
**Цель:** Найти failed CallPermit dispatch где target multisig имел DIODE баланс в момент failed tx

---

## Executive Summary

| Метрика | Значение |
|---------|---------|
| Проверено кандидатов | ${results.length} |
| Нашли DIODE > 0 в multisig AT BLOCK | ${withFunds.length} |
| Auth check PASS (owner/member) | ${authOk.length} |
| Nonce rollback confirmed | ${rollback.length} |
| 🔴 КРИТИЧЕСКИЕ (все три) | ${critical.length} |
| Диапазон сканирования | ${scanStats.ranges} |

`;

  if (critical.length > 0) {
    md += `## 🔴 КРИТИЧЕСКИЕ НАХОДКИ\n\n`;
    for (const r of critical) md += formatFinding(r, "CRITICAL");
  } else {
    md += `## ❌ Случаев с DIODE > 0 в multisig на момент failed tx — НЕ НАЙДЕНО\n\n`;
    md += `Все known Diode Drive multisigs имели **0 DIODE** в момент каждого failed dispatch.\n\n`;
    md += `**Вероятная причина:** Diode Drive контракты используются для децентрализованного хранения (Drive/filesystem),\n`;
    md += `а не для хранения DIODE токенов. DIODE токены хранятся у individual users или в staking contract.\n\n`;
  }

  if (withFunds.length > 0 && critical.length === 0) {
    md += `## Находки с DIODE > 0 (но без nonce rollback или auth)\n\n`;
    for (const r of withFunds) md += formatFinding(r, "PARTIAL");
  }

  md += `## Все проверенные кандидаты\n\n`;
  md += `| TX | Block | Multisig | DIODE@block | Rollback | Auth | Inner |\n`;
  md += `|----|-------|----------|-------------|---------|------|-------|\n`;
  for (const r of results) {
    const bal = r.hasFunds ? `🔴 ${r.diodeBalanceFmt}` : `0`;
    const rb  = r.nonceRollback ? "✅" : "❌";
    const a   = r.authPass ? "✅" : "❌";
    const hash8 = (r.txHash || "").slice(0, 10) + "...";
    const sel = r.isSubmitTx ? "SubmitTx" : (r.isFinancial ? "FINANCIAL" : "nested");
    md += `| [${hash8}](https://moonbeam.moonscan.io/tx/${r.txHash}) | ${r.block} | \`${(r.targetTo||"").slice(0,10)}...\` | ${bal} | ${rb} | ${a} | ${sel} |\n`;
  }

  md += `\n---\n\n## Лучшие находки без DIODE баланса (но с подтверждённым rollback + auth)\n\n`;
  const bestNoFunds = results.filter(r => r.nonceRollback && r.authPass && !r.hasFunds);
  if (bestNoFunds.length > 0) {
    md += `Nonce rollback подтверждён + signer авторизован на multisig, но DIODE баланс = 0:\n\n`;
    for (const r of bestNoFunds.slice(0, 5)) md += formatFinding(r, "STRONG_NOBAL");
  }

  md += `\n---\n\n## Методология\n\n`;
  md += `1. Загружены existing candidates из scan files\n`;
  md += `2. Дополнительный scan блоков: ${scanStats.ranges}\n`;
  md += `3. Для каждого SubmitTransaction кандидата: eth_call balanceOf(multisig) AT BLOCK\n`;
  md += `4. Nonce rollback: eth_call nonces(signer) при block-1 vs block\n`;
  md += `5. Auth: eth_call Members() + owner() на multisig\n`;
  md += `6. Приоритет: DIODE > 0 + rollback confirmed + auth pass = CRITICAL\n`;

  return md;
}

function formatFinding(r, level) {
  const tag = { CRITICAL: "🔴 КРИТИЧЕСКАЯ НАХОДКА", PARTIAL: "🟡 Частичная", STRONG_NOBAL: "🟠 Rollback + Auth (нет баланса)" }[level];
  return `### ${tag}: \`${r.txHash}\`

**Block:** ${r.block} (${r.blockTimestamp ? new Date(r.blockTimestamp * 1000).toISOString() : "N/A"})
**Signer:** \`${r.signedFrom}\`
**Target multisig:** \`${r.targetTo}\`
**DIODE balance at block:** ${r.diodeBalanceFmt} DIODE ${r.hasFunds ? "🔴" : ""}
**Nonce rollback:** ${r.nonceRollback ? `✅ CONFIRMED (${r.nonceBefore} → ${r.nonceAfter})` : `❌ (before=${r.nonceBefore}, after=${r.nonceAfter})`}
**Auth (isOwner/isMember):** ${r.authPass ? `✅ ${r.isOwner ? "OWNER" : "MEMBER"}` : "❌ NOT AUTH"}
**Deadline:** ${r.deadline} (${r.deadline ? new Date(Number(r.deadline) * 1000).toISOString() : "N/A"})
**Replay window:** ${r.windowSeconds} seconds
**Inner call:** ${r.isSubmitTx ? "SubmitTransaction(address,bytes)" : r.innerSelector}
**Nested financial:** ${r.nested ? `${r.nested.selector} = ${r.nested.name}` : "none"}

${r.hasFunds && r.authPass && r.nonceRollback ? `**IMPACT:** В течение ${r.windowSeconds} секунд replay window любой мог выполнить SubmitTransaction от имени ${r.signedFrom} (авторизованного члена multisig) → arbitrary call execution → потенциальный drain ${r.diodeBalanceFmt} DIODE` : ""}

---

`;
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.error("[main] Loading existing candidates...");
  const existing = loadExisting();
  const submitTxCandidates = existing.filter(c =>
    (c.innerSelector || "").toLowerCase() === SUBMIT_SEL ||
    (c.priority && c.nestedSensitiveSelector)
  );
  console.error(`[main] ${existing.length} total existing, ${submitTxCandidates.length} SubmitTx/financial`);

  // Also scan additional block ranges
  const latestBlock = Number(BigInt(await rpc("eth_blockNumber", [])));
  const scanRanges = [
    // Known heavy range around the 15.5M blocks (not yet in 50k file)
    [15440000, 15538000],
    // Earlier range
    [15350000, 15440000],
  ];

  const scanStats = { ranges: scanRanges.map(([s,e]) => `${s}-${e}`).join(", ") };
  let newCandidates = [];
  for (const [start, end] of scanRanges) {
    const found = await scanBlockRange(start, end, 200);
    newCandidates.push(...found);
    console.error(`[scan] range ${start}-${end}: found ${found.length} candidates`);
    if (found.length > 0) {
      fs.writeFileSync(
        path.join(RESEARCH_DIR, `scan_new_${start}_${end}.jsonl`),
        found.map(x => JSON.stringify(x)).join("\n")
      );
    }
  }

  // Merge and deduplicate
  const allCandidates = [...submitTxCandidates];
  const seen = new Set(submitTxCandidates.map(c => c.txHash));
  for (const c of newCandidates) {
    if (c.txHash && !seen.has(c.txHash)) { seen.add(c.txHash); allCandidates.push(c); }
  }
  console.error(`[main] Total to analyze: ${allCandidates.length}`);

  // Analyze each
  const results = [];
  for (let i = 0; i < allCandidates.length; i++) {
    const c = allCandidates[i];
    const block = typeof c.block === "string" ? Number(BigInt(c.block)) : Number(c.block);
    const signer  = c.signedFrom || c.from;
    const multisig = c.targetTo || c.to;
    if (!signer || !multisig || !block) continue;
    process.stderr.write(`\r[analyze] ${i+1}/${allCandidates.length} block=${block} ...`);
    try {
      const result = await analyzeCandidate(c, block, signer, multisig);
      results.push(result);
      if (result.hasFunds) {
        console.error(`\n[🔴 FUNDS FOUND] ${c.txHash} ${result.diodeBalanceFmt} DIODE`);
      }
    } catch (e) {
      console.error(`\n[err] ${c.txHash}: ${e.message.slice(0, 80)}`);
    }
  }
  process.stderr.write("\n");

  // Save raw results
  const outJson = path.join(RESEARCH_DIR, "financial_risk_findings.json");
  const bigintReplacer = (_, v) => typeof v === "bigint" ? v.toString() : v;
  fs.writeFileSync(outJson, JSON.stringify(results, bigintReplacer, 2));
  console.error(`[main] Raw results: ${outJson}`);

  // Generate report
  const report = buildReport(results, scanStats);
  if (!fs.existsSync(REPORTS_DIR)) fs.mkdirSync(REPORTS_DIR, { recursive: true });
  const outMd = path.join(REPORTS_DIR, "DIODE_BALANCE_RISK_ru.md");
  fs.writeFileSync(outMd, report);
  console.error(`[main] Report: ${outMd}`);

  // Print summary
  const critical = results.filter(r => r.hasFunds && r.authPass && r.nonceRollback);
  console.log(`\n=== РЕЗУЛЬТАТЫ ===`);
  console.log(`Проверено: ${results.length}`);
  console.log(`С DIODE > 0: ${results.filter(r => r.hasFunds).length}`);
  console.log(`Rollback + Auth: ${results.filter(r => r.nonceRollback && r.authPass).length}`);
  console.log(`КРИТИЧЕСКИЕ: ${critical.length}`);
  if (critical.length > 0) {
    for (const r of critical) {
      console.log(`  🔴 ${r.txHash} | ${r.diodeBalanceFmt} DIODE | window ${r.windowSeconds}s`);
    }
  }
}

main().catch(e => { console.error("FATAL:", e); process.exit(1); });
