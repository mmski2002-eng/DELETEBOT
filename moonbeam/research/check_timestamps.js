"use strict";
const { ethers } = require("ethers");
const provider = new ethers.JsonRpcProvider("https://rpc.api.moonbeam.network");

const FAILED_BLOCK = 15616976;
const CALLPERMIT  = "0x000000000000000000000000000000000000080a";
const FAILED_TX   = "0xfd164de94ae08b91e83389dedfc60ba652180dd085fe943847d179925fe6e973";
const RELAYER     = "0xceca2f8cf1983b4cf0c1ba51fd382c2bc37aba58";
const DEADLINE_TS = Math.floor(new Date("2026-05-14T14:18:12.000Z").getTime() / 1000);

async function main() {
  console.log("Deadline:", DEADLINE_TS, "=", new Date(DEADLINE_TS * 1000).toISOString());
  console.log("");

  // Check block timestamps around N
  const offsets = [-5, -3, -2, -1, 0, 1, 2];
  const blocks = await Promise.all(offsets.map(o => provider.getBlock(FAILED_BLOCK + o)));

  for (const b of blocks) {
    const offset = b.number - FAILED_BLOCK;
    const label  = offset === 0 ? "N(failed)" : (offset < 0 ? "N" + offset : "N+" + offset);
    const rel    = b.timestamp - DEADLINE_TS;
    const status = rel < 0 ? "BEFORE deadline => sim SUCCESS" : "AFTER  deadline => tx FAIL";
    console.log("Block", b.number, "[" + label + "]", b.timestamp, new Date(b.timestamp * 1000).toISOString(), "| delta=" + rel + "s |", status);
  }

  // KEY: if N-1 is BEFORE deadline and N is AFTER => proof complete
  const blockNm1 = blocks.find(b => b.number === FAILED_BLOCK - 1);
  const blockN   = blocks.find(b => b.number === FAILED_BLOCK);

  console.log("\n=== SIMULATION INSUFFICIENCY CHECK ===");
  const simWouldSucceed = blockNm1 && blockNm1.timestamp < DEADLINE_TS;
  const realTxFails     = blockN    && blockN.timestamp   >= DEADLINE_TS;

  if (simWouldSucceed && realTxFails) {
    console.log("PROOF COMPLETE (STRONG):");
    console.log("  Block N-1 timestamp:", blockNm1.timestamp, "< deadline", DEADLINE_TS, "=> simulate SUCCESS");
    console.log("  Block N   timestamp:", blockN.timestamp,   ">= deadline", DEADLINE_TS, "=> real tx FAIL");
    console.log("  Delta: block N crossed deadline by", blockN.timestamp - DEADLINE_TS, "seconds");
    console.log("");
    console.log("  Relayer simulated at N-1: would see valid deadline => DISPATCH OK");
    console.log("  Block N mined after deadline expired => Permit expired => FAIL");
    console.log("  This is a race condition. Relayer had no way to know block N timestamp in advance.");
    console.log("  'Simulate before sending' does NOT protect against block-time deadline expiry.");
  } else if (simWouldSucceed) {
    console.log("PARTIAL: sim at N-1 would succeed but block N is also before deadline?");
    console.log("  Something else caused the failure. Investigate inner call.");
  } else {
    console.log("Deadline already expired at N-1. Simulation ALSO fails.");
    console.log("  Relayer should have caught this. Not the best example.");
    console.log("  Block N-1 ts:", blockNm1?.timestamp, "Deadline:", DEADLINE_TS);
  }

  // Also: verify simulation at N-1 returns success if timestamp is before deadline
  if (simWouldSucceed) {
    console.log("\n=== CONFIRMING: Simulate at block N-1 ===");
    const tx = await provider.getTransaction(FAILED_TX);
    try {
      const ret = await provider.call({ to: CALLPERMIT, data: tx.data, from: RELAYER }, FAILED_BLOCK - 1);
      console.log("Simulation at N-1: SUCCESS, returnData:", ret);
    } catch (e) {
      console.log("Simulation at N-1: FAIL =>", e.message.slice(0, 200));
    }
  }
}

main().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
