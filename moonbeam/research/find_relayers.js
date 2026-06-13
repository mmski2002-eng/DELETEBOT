"use strict";
const axios = require("axios");
const { ethers } = require("ethers");
const fs = require("fs");

const API_KEY = "EA7VUYECW52XBENHBJ4TWHJVT7GVFEAA7D";
const BASE = "https://api.etherscan.io/v2/api";
const CALLPERMIT = "0x000000000000000000000000000000000000080a";
const DISPATCH_SEL = "0xb5ea0966";

const DISPATCH_ABI = ["function dispatch(address from, address to, uint256 value, bytes data, uint64 gaslimit, uint256 deadline, uint8 v, bytes32 r, bytes32 s)"];
const iface = new ethers.Interface(DISPATCH_ABI);

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function api(params) {
  const r = await axios.get(BASE, { params: { apikey: API_KEY, chainid: "1284", ...params }, timeout: 15000 });
  return r.data;
}

function decodeTarget(input) {
  if (!input?.startsWith(DISPATCH_SEL)) return null;
  try {
    const dec = iface.decodeFunctionData("dispatch", input);
    return { target: dec.to.toLowerCase(), innerSel: dec.data.slice(0, 10).toLowerCase() };
  } catch { return null; }
}

async function resolveSelector(sel) {
  try {
    const r = await axios.get(`https://api.openchain.xyz/signature-database/v1/lookup?function=${sel}&filter=true`, { timeout: 8000 });
    return r.data?.results?.function?.[sel]?.[0]?.name ?? sel;
  } catch { return sel; }
}

async function main() {
  console.log("Fetching 500 txs to CallPermit...");
  const data = await api({ module: "account", action: "txlist", address: CALLPERMIT, sort: "desc", page: 1, offset: 500 });

  if (data.status !== "1") { console.error("API error:", data.message, data.result); process.exit(1); }

  const txs = data.result;
  console.log(`Got ${txs.length} txs | ${new Date(txs.at(-1).timeStamp*1000).toISOString().slice(0,10)} → ${new Date(txs[0].timeStamp*1000).toISOString().slice(0,10)}`);

  const counts = {}, success = {}, gas = {}, last = {}, tgts = {};

  for (const tx of txs) {
    const from = tx.from.toLowerCase();
    counts[from] = (counts[from] || 0) + 1;
    success[from] = (success[from] || 0) + (tx.txreceipt_status === "1" ? 1 : 0);
    gas[from] = (gas[from] || 0) + parseInt(tx.gasUsed) * parseInt(tx.gasPrice) / 1e18;
    if (!last[from] || tx.timeStamp > last[from]) last[from] = tx.timeStamp;

    const dec = decodeTarget(tx.input);
    if (dec) {
      if (!tgts[from]) tgts[from] = {};
      const k = dec.target + "|" + dec.innerSel;
      tgts[from][k] = (tgts[from][k] || 0) + 1;
    }
  }

  const ranked = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 10);

  console.log("\n=== TOP DISPATCHERS ===");
  for (const [addr, cnt] of ranked) {
    const s = success[addr];
    console.log(`${addr} | ${cnt} txs | ${s}/${cnt} ok (${(s/cnt*100).toFixed(0)}%) | ${gas[addr].toFixed(4)} GLMR | last ${new Date(last[addr]*1000).toISOString().slice(0,10)}`);
  }

  // Resolve selectors
  const allSels = new Set();
  for (const [addr] of ranked.slice(0, 5)) for (const k of Object.keys(tgts[addr] || {})) allSels.add(k.split("|")[1]);
  const selNames = {};
  for (const sel of allSels) { selNames[sel] = await resolveSelector(sel); await sleep(80); }

  // Profile top 5
  console.log("\n=== FULL PROFILES ===\n");
  const profiles = [];

  for (let i = 0; i < Math.min(5, ranked.length); i++) {
    const [addr, cnt] = ranked[i];
    const s = success[addr];
    const lastDate = new Date(last[addr]*1000).toISOString().slice(0,10);
    const daysAgo = Math.floor((Date.now()/1000 - last[addr]) / 86400);

    // Balance
    const balData = await api({ module: "account", action: "balance", address: addr });
    await sleep(300);
    const balGlmr = balData.status === "1" ? (parseInt(balData.result) / 1e18).toFixed(2) : "?";

    // Code
    const codeData = await api({ module: "contract", action: "getabi", address: addr });
    await sleep(300);
    const type = codeData.status === "1" ? "CONTRACT" : "EOA";

    // Top targets
    const topT = Object.entries(tgts[addr] || {}).sort((a,b) => b[1]-a[1]).slice(0, 4)
      .map(([k, n]) => { const [t, sel] = k.split("|"); return `  ${t} | ${selNames[sel] || sel} (×${n})`; });

    // dApp guess
    let dapp = "Unknown";
    for (const k of Object.keys(tgts[addr] || {})) {
      const t = k.split("|")[0];
      if (t.includes("d1a9ba")) dapp = "DPS Cartographer";
      else if (["553fd2","e66453","45573","20b04b","597b2"].some(x => t.includes(x))) dapp = "Diode Network";
    }

    const risk = daysAgo <= 7 && parseFloat(balGlmr) > 1 ? "HIGH" :
                 daysAgo <= 30 && parseFloat(balGlmr) > 0.1 ? "MEDIUM" : "LOW";

    console.log(`--- #${i+1}: ${addr}`);
    console.log(`Type: ${type} | dApp: ${dapp} | Risk: ${risk}`);
    console.log(`Balance: ${balGlmr} GLMR`);
    console.log(`Txs: ${cnt} | Success: ${s}/${cnt} (${(s/cnt*100).toFixed(0)}%) | Gas: ${gas[addr].toFixed(4)} GLMR`);
    console.log(`Last: ${lastDate} (${daysAgo}d ago)`);
    console.log("Targets:"); topT.forEach(t => console.log(t));

    // Decode last 3 txs
    console.log("Recent dispatches:");
    const recent = txs.filter(t => t.from.toLowerCase() === addr).slice(0, 3);
    for (const tx of recent) {
      const dec = decodeTarget(tx.input);
      const sel = dec?.innerSel;
      const fn = sel ? (selNames[sel] || await resolveSelector(sel)) : "?";
      const status = tx.txreceipt_status === "1" ? "✅" : "❌";
      const date = new Date(tx.timeStamp*1000).toISOString().slice(0,10);
      console.log(`  ${status} ${date} → ${dec?.target || "?"} | ${fn} | ${tx.hash.slice(0,18)}...`);
    }
    console.log();

    profiles.push({ rank: i+1, addr, type, dapp, risk, balGlmr, total: cnt, success: s, gasGlmr: gas[addr].toFixed(4), lastDate, daysAgo });
  }

  fs.writeFileSync("research/relayer_profiles.json", JSON.stringify(profiles, null, 2));
  console.log("Saved: research/relayer_profiles.json");

  // Best pick
  const best = profiles.filter(p => p.risk === "HIGH")[0] || profiles[0];
  console.log(`\nBEST FOR PoC: ${best?.addr} (${best?.dapp}, ${best?.risk} risk, ${best?.balGlmr} GLMR, last ${best?.daysAgo}d ago)`);
}

main().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
