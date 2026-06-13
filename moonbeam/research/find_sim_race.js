"use strict";
// Find a failed CallPermit dispatch where eth_call at block N-1 returns SUCCESS
// but real tx at block N failed. That proves simulation is insufficient.
const axios = require("axios");
const { ethers } = require("ethers");
const fs = require("fs");

const provider = new ethers.JsonRpcProvider("https://rpc.api.moonbeam.network");
const API_KEY  = "EA7VUYECW52XBENHBJ4TWHJVT7GVFEAA7D";
const BASE     = "https://api.etherscan.io/v2/api";
const CALLPERMIT = "0x000000000000000000000000000000000000080a";
const DISPATCH_SEL = "0xb5ea0966";

const DISPATCH_ABI = ["function dispatch(address from, address to, uint256 value, bytes data, uint64 gaslimit, uint256 deadline, uint8 v, bytes32 r, bytes32 s)"];
const iface = new ethers.Interface(DISPATCH_ABI);

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function api(params) {
  const r = await axios.get(BASE, { params: { apikey: API_KEY, chainid: "1284", ...params }, timeout: 15000 });
  return r.data;
}

async function main() {
  // Fetch last 1000 failed txs to CallPermit
  console.log("Fetching failed txs to CallPermit...");
  const pages = [1, 2]; // up to 2000 txs
  const allTxs = [];
  for (const page of pages) {
    const data = await api({ module: "account", action: "txlist", address: CALLPERMIT, sort: "desc", page, offset: 1000 });
    if (data.status !== "1") break;
    allTxs.push(...data.result);
    await sleep(300);
  }

  const failedTxs = allTxs.filter(tx => tx.txreceipt_status === "0" || tx.isError === "1");
  const dispatchFailed = failedTxs.filter(tx => tx.input?.startsWith(DISPATCH_SEL));
  console.log("Total fetched:", allTxs.length, "| Failed:", failedTxs.length, "| Failed dispatches:", dispatchFailed.length);

  const results = [];

  for (const tx of dispatchFailed) {
    const block = parseInt(tx.blockNumber);
    let dec;
    try {
      dec = iface.decodeFunctionData("dispatch", tx.input);
    } catch { continue; }

    const deadlineTs = Number(dec.deadline);
    const blockData = await provider.getBlock(block);
    await sleep(100);

    const deadlineExpiredAtBlock = deadlineTs < blockData.timestamp;
    const item = {
      hash: tx.hash,
      block,
      from: tx.from,
      signer: dec.from.toLowerCase(),
      target: dec.to.toLowerCase(),
      innerSel: dec.data.slice(0, 10),
      deadline: new Date(deadlineTs * 1000).toISOString(),
      blockTs: blockData.timestamp,
      deadlineExpiredAtBlock,
    };

    if (deadlineExpiredAtBlock) {
      // deadline expired → can't be simulation insufficiency
      console.log("SKIP", tx.hash.slice(0, 18), "deadline expired at block");
      results.push({ ...item, simAtNm1: "N/A (deadline expired at block)", verdict: "SKIP" });
      continue;
    }

    // Deadline was valid at block N — simulate at N-1
    console.log("Testing", tx.hash.slice(0, 18), "block", block, "target", dec.to.slice(0, 10), "sel", dec.data.slice(0, 10));
    try {
      const ret = await provider.call({ to: CALLPERMIT, data: tx.input, from: tx.from }, block - 1);
      // Sim at N-1 succeeded!
      const verdict = "PROOF: sim SUCCESS at N-1, real FAIL at N";
      console.log("  *** FOUND PROOF:", verdict, "***");
      console.log("  returnData:", ret);
      results.push({ ...item, simAtNm1: "SUCCESS", returnData: ret, verdict });
    } catch (e) {
      const err = e.message?.slice(0, 150) || "unknown";
      results.push({ ...item, simAtNm1: "FAIL", simError: err, verdict: "NO PROOF (sim also fails)" });
      console.log("  sim also fails:", err.slice(0, 80));
    }
    await sleep(300);
  }

  fs.writeFileSync("research/sim_race_results.json", JSON.stringify(results, null, 2));
  console.log("\nSaved: research/sim_race_results.json");

  const proofs = results.filter(r => r.simAtNm1 === "SUCCESS");
  if (proofs.length > 0) {
    console.log("\n=== PROOF CANDIDATES ===");
    proofs.forEach(p => console.log(p.hash, p.target, p.innerSel));
  } else {
    console.log("\nNo simulation-insufficiency proof found in this batch.");
    console.log("All failed dispatches either had expired deadline or sim also fails.");
  }
}

main().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
