"use strict";
const { ethers } = require("ethers");
const fs = require("fs");

const provider = new ethers.JsonRpcProvider("https://rpc.api.moonbeam.network");
const CALLPERMIT = "0x000000000000000000000000000000000000080a";
const DISPATCH_SELECTOR = "0xb5ea0966";

const DISPATCH_ABI = ["function dispatch(address from, address to, uint256 value, bytes data, uint64 gaslimit, uint256 deadline, uint8 v, bytes32 r, bytes32 s)"];
const iface = new ethers.Interface(DISPATCH_ABI);

const FINANCIAL_SELECTORS = {
  "0xa9059cbb": "transfer(address,uint256)",
  "0x23b872dd": "transferFrom(address,address,uint256)",
  "0x095ea7b3": "approve(address,uint256)",
  "0x4e71d92d": "claim()",
  "0x372500ab": "claimRewards()",
  "0x3d18b912": "getReward()",
  "0x853828b6": "withdrawAll()",
  "0xe9fad8ee": "exit()",
  "0x7050ccd9": "claimReward(bool)",
  "0xb88a802f": "collectReward()",
  "0x1c4b774b": "harvest(uint256)",
  "0x2f940c70": "withdrawAndHarvest(uint256,address)",
  "0xddc63262": "harvestAll()",
  "0xa0712d68": "mint(uint256)",
  "0xdb006a75": "redeemUnderlying(uint256)",
  "0x852a12e3": "redeem(uint256)",
  "0xc5ebeaec": "borrow(uint256)",
  "0xf5e3c462": "repayBorrow(uint256)",
  "0x4e4d9fea": "repayBorrowBehalf(address,uint256)",
  "0x2e1a7d4d": "withdraw(uint256)",
  "0xd0e30db0": "deposit()",
  "0xe8e33700": "addLiquidity(...)",
  "0xbaa2abde": "removeLiquidity(...)",
  "0x02751cec": "removeLiquidityETH(...)",
  "0xaf2979eb": "removeLiquidityETHWithPermit(...)",
  "0x38ed1739": "swapExactTokensForTokens",
  "0x8803dbee": "swapTokensForExactTokens",
  "0x7ff36ab5": "swapExactETHForTokens",
  "0x18cbafe5": "swapExactTokensForETH",
  "0xfb3bdb41": "swapETHForExactTokens",
  "0x5c11d795": "swapExactTokensForTokensSupportingFeeOnTransferTokens",
  "0x1249c58b": "mint()",
  "0x40d097c3": "safeMint(address)",
  "0x6a627842": "mint(address)",
  "0xd85d3d27": "publicMint(uint256)",
  "0xdb76d5b3": "buyVoyages(uint16,uint256,address)",
  "0xb1dc65a4": "claim(bytes32,bytes)",
  "0x1e83409a": "claim(address)",
  "0xc87b56dd": "claimTokens(address,uint256)",
  "0x56781388": "castVote(uint256,bool)",
  "0x15373e3d": "castVoteWithReason(uint256,uint8,string)",
};

const PRIORITY_TARGETS = new Set([
  "0x091608f4e4a15335440f0bc2ddee6f5b526d7063",
  "0xd0670aee3698f66e2d4daf071eb9c690d978bfa8",
  "0xa649325aa7c5093d12d6f98eb4378deae68ce23f",
  "0xf03b75831397d4695a6b9dddeea0e578faa30907",
  "0x68218b7fb651dfc7b5606a6b5b3c4a2b66c1e0e3",
  "0xd1a9ba3e61ac676f58b29ea0a09cf5d7f4f35138",
]);

const sleep = ms => new Promise(r => setTimeout(r, ms));

// Batch eth_getBlockReceipts — up to 100 blocks per HTTP request
async function batchReceipts(blockNums, attempt = 0) {
  const RPCS = [
    "https://rpc.api.moonbeam.network",
    "https://moonbeam-rpc.publicnode.com",
    "https://moonbeam.api.onfinality.io/public",
    "https://moonbeam.unitedbloc.com",
  ];
  const url = RPCS[attempt % RPCS.length];
  try {
    const payload = blockNums.map((n, i) => ({
      jsonrpc: "2.0", id: i,
      method: "eth_getBlockReceipts",
      params: [ethers.toQuantity(n)],
    }));
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(25000),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const body = await res.json();
    if (!Array.isArray(body)) {
      const msg = JSON.stringify(body).slice(0, 200);
      if (msg.includes("-32011") && blockNums.length > 1) {
        const mid = Math.floor(blockNums.length / 2);
        const [L, R] = await Promise.all([
          batchReceipts(blockNums.slice(0, mid)),
          batchReceipts(blockNums.slice(mid)),
        ]);
        return [...L, ...R];
      }
      throw new Error(msg);
    }
    body.sort((a, b) => a.id - b.id);
    return body.map(x => x.result ?? []);
  } catch (e) {
    if (attempt >= 4) return blockNums.map(() => []);
    await sleep(700 * (attempt + 1));
    return batchReceipts(blockNums, attempt + 1);
  }
}

async function checkNonce(addr, block) {
  const data = "0x7ecebe00" + addr.slice(2).padStart(64, "0");
  try {
    const v = await provider.call({ to: CALLPERMIT, data }, block);
    return BigInt(v);
  } catch { return null; }
}

const findings = [];
let STOP_SCANNING = false;

async function handleCandidate(rec, block, decoded) {
  const innerSelector = decoded.data.slice(0, 10).toLowerCase();
  const fnName = FINANCIAL_SELECTORS[innerSelector];
  if (!fnName) return;

  const deadline = Number(decoded.deadline);
  const nowTimestamp = Math.floor(Date.now() / 1000);
  const deadlineValid = deadline > nowTimestamp;
  const isPriority = PRIORITY_TARGETS.has(decoded.to.toLowerCase());

  const [nonceBefore, nonceAfter, nonceNow] = await Promise.all([
    checkNonce(decoded.from, block - 1),
    checkNonce(decoded.from, block),
    checkNonce(decoded.from, "latest"),
  ]);

  const rolled    = nonceBefore !== null && nonceAfter !== null && nonceBefore === nonceAfter;
  const stillOpen = nonceNow !== null && nonceBefore !== null && nonceNow === nonceBefore;

  let priority;
  if (rolled && stillOpen && deadlineValid) priority = "LIVE";
  else if (rolled && stillOpen)             priority = "OPEN_EXPIRED_DEADLINE";
  else if (rolled)                          priority = "CLOSED";
  else                                      priority = "NO_ROLLBACK";

  console.log(`\n[${priority}] ${fnName} ${isPriority ? "⭐ PRIORITY" : ""}`);
  console.log("TX:", rec.transactionHash);
  console.log("Block:", block);
  console.log("Signer:", decoded.from);
  console.log("Target:", decoded.to);
  console.log("Deadline:", new Date(deadline * 1000).toISOString());
  console.log("Nonce rolled back:", rolled ? "✅" : "❌");
  console.log("Nonce unconsumed today:", stillOpen ? "✅" : "❌");
  console.log("Deadline still valid:", deadlineValid ? "🔴 LIVE!" : "❌ expired");

  if (priority === "LIVE") {
    STOP_SCANNING = true;
    console.log("\n🚨🚨🚨 LIVE REPLAY WINDOW FOUND 🚨🚨🚨");
    console.log("STOPPING SCAN NOW");
    console.log("SIMULATE ONLY — NEVER sendTransaction");

    let simSuccess = false;
    let simResult = null;
    let simError = null;
    try {
      simResult = await provider.call({
        to: CALLPERMIT,
        data: rec.input,
        from: "0x000000000000000000000000000000000000dEaD",
      });
      simSuccess = true;
      console.log("✅ SIMULATION SUCCESS — replay would work!");
      console.log("Return data:", simResult);
    } catch (e) {
      simError = e.message;
      console.log("❌ Simulation failed:", e.message);
    }

    let signerBalance = null;
    try {
      const balData = "0x70a08231" + decoded.from.slice(2).padStart(64, "0");
      const balHex = await provider.call({ to: decoded.to, data: balData });
      signerBalance = ethers.formatEther(BigInt(balHex));
    } catch {}

    const blockData = await provider.getBlock(block);
    const liveReport = {
      STATUS: "🚨 LIVE REPLAY WINDOW — ACTION REQUIRED",
      INSTRUCTIONS: [
        "DO NOT send any mainnet transaction",
        "Report this to researcher immediately",
        "Wait for instructions before anything else",
      ],
      tx: rec.transactionHash,
      moonscan: `https://moonbeam.moonscan.io/tx/${rec.transactionHash}`,
      block,
      blockTime: new Date(blockData.timestamp * 1000).toISOString(),
      signer: decoded.from,
      target: decoded.to,
      isPriorityTarget: isPriority,
      innerFunction: fnName,
      innerSelector,
      deadline: new Date(deadline * 1000).toISOString(),
      secondsRemaining: deadline - nowTimestamp,
      minutesRemaining: Math.floor((deadline - nowTimestamp) / 60),
      nonceRolledBack: true,
      nonceBefore: nonceBefore.toString(),
      nonceNow: nonceNow.toString(),
      simulation: { success: simSuccess, result: simResult, error: simError },
      signerTokenBalanceNow: signerBalance,
      rawInput: rec.input,
    };

    fs.writeFileSync("LIVE_FINDING.json", JSON.stringify(liveReport, null, 2));
    console.log("\n========================================");
    console.log("LIVE FINDING SAVED TO: LIVE_FINDING.json");
    console.log("========================================");
    console.log(JSON.stringify(liveReport, null, 2));
    console.log("\n⚠️  STOP. Report this to researcher right now.");
    console.log("⚠️  Time remaining:", Math.floor((deadline - nowTimestamp) / 60), "minutes");

    findings.push(liveReport);
    return;
  }

  findings.push({
    priority,
    tx: rec.transactionHash,
    moonscan: `https://moonbeam.moonscan.io/tx/${rec.transactionHash}`,
    block,
    signer: decoded.from,
    target: decoded.to,
    isPriority,
    function: fnName,
    innerSelector,
    deadline: new Date(deadline * 1000).toISOString(),
    nonceRolledBack: rolled,
    nonceStillOpen: stillOpen,
    deadlineValid,
    nonceBefore: nonceBefore?.toString() ?? null,
    nonceNow: nonceNow?.toString() ?? null,
  });

  findings.sort((a, b) => {
    const order = { LIVE: 0, OPEN_EXPIRED_DEADLINE: 1, CLOSED: 2, NO_ROLLBACK: 3 };
    return (order[a.priority] ?? 4) - (order[b.priority] ?? 4);
  });
  fs.writeFileSync("financial_findings.json", JSON.stringify(findings, null, 2));
}

async function main() {
  const currentBlock = await provider.getBlockNumber();
  const nowTimestamp = Math.floor(Date.now() / 1000);
  console.log(`Current block: ${currentBlock}, timestamp: ${new Date(nowTimestamp * 1000).toISOString()}`);

  const RANGES = [
    [currentBlock - 50000,   currentBlock],
    [currentBlock - 200000,  currentBlock - 50000],
    [currentBlock - 500000,  currentBlock - 200000],
    [currentBlock - 1000000, currentBlock - 500000],
    [currentBlock - 2000000, currentBlock - 1000000],
  ];

  const BATCH = 100; // blocks per HTTP request
  const CONCURRENT = 5; // concurrent batch requests

  outer:
  for (const [rangeStart, rangeEnd] of RANGES) {
    if (STOP_SCANNING) break;
    const rangeBlocks = rangeEnd - rangeStart;
    console.log(`\nScanning ${rangeStart} → ${rangeEnd} (${rangeBlocks.toLocaleString()} blocks)`);
    let found = 0;
    const t0 = Date.now();

    for (let base = rangeStart; base <= rangeEnd; base += BATCH * CONCURRENT) {
      if (STOP_SCANNING) break outer;

      // Build CONCURRENT groups of BATCH blocks
      const groups = [];
      for (let g = 0; g < CONCURRENT; g++) {
        const gStart = base + g * BATCH;
        if (gStart > rangeEnd) break;
        const nums = [];
        for (let i = gStart; i < gStart + BATCH && i <= rangeEnd; i++) nums.push(i);
        groups.push(nums);
      }

      const results = await Promise.all(groups.map(nums => batchReceipts(nums)));

      for (let g = 0; g < groups.length; g++) {
        for (let i = 0; i < groups[g].length; i++) {
          if (STOP_SCANNING) break outer;
          const blockNum = groups[g][i];
          const receipts = results[g]?.[i] ?? [];

          for (const rec of receipts) {
            if (!rec.to || rec.to.toLowerCase() !== CALLPERMIT) continue;
            if (rec.status !== "0x0") continue;
            if (!rec.input?.startsWith(DISPATCH_SELECTOR)) continue;

            try {
              const decoded = iface.decodeFunctionData("dispatch", rec.input);
              await handleCandidate(rec, blockNum, decoded);
              if (STOP_SCANNING) break outer;
              found++;
            } catch { continue; }
          }
        }
      }

      const done = Math.min(base + BATCH * CONCURRENT - rangeStart, rangeBlocks);
      const pct  = ((done / rangeBlocks) * 100).toFixed(1);
      const bps  = done / ((Date.now() - t0) / 1000);
      const eta  = (rangeBlocks - done) / bps;
      const etaStr = eta < 60 ? `${eta.toFixed(0)}s` : `${(eta / 60).toFixed(1)}m`;

      if (base % 5000 < BATCH * CONCURRENT) {
        console.log(`  block ${base} | ${pct}% | ${bps.toFixed(0)} bl/s | eta ${etaStr} | financial hits: ${found}`);
        fs.writeFileSync("financial_findings.json", JSON.stringify(findings, null, 2));
      }
    }
  }

  console.log("\n=== SCAN COMPLETE ===");
  const live   = findings.filter(f => f.priority === "LIVE" || f.STATUS?.includes("LIVE"));
  const open   = findings.filter(f => f.priority === "OPEN_EXPIRED_DEADLINE");
  const closed = findings.filter(f => f.priority === "CLOSED");

  console.log("LIVE windows:", live.length);
  console.log("Open (expired deadline):", open.length);
  console.log("Closed:", closed.length);
  console.log("Total:", findings.length);

  if (live.length === 0 && open.length === 0) {
    console.log("\nNo exploitable windows found.");
    console.log("All CLOSED findings saved to financial_findings.json");
  } else {
    console.log("\nFindings saved to financial_findings.json");
  }
}

main().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
