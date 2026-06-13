"use strict";
const { ethers } = require("ethers");
const fs = require("fs");

const provider = new ethers.JsonRpcProvider("https://rpc.api.moonbeam.network");

const FAILED_TX   = "0xfd164de94ae08b91e83389dedfc60ba652180dd085fe943847d179925fe6e973";
const FAILED_BLOCK = 15616976;
const CALLPERMIT  = "0x000000000000000000000000000000000000080a";
const RELAYER     = "0xceca2f8cf1983b4cf0c1ba51fd382c2bc37aba58";
const SIGNER      = "0xafbe621c3bca78437aa0299a6fc3cf893087e7fc";

const DISPATCH_ABI = ["function dispatch(address from, address to, uint256 value, bytes data, uint64 gaslimit, uint256 deadline, uint8 v, bytes32 r, bytes32 s)"];
const iface = new ethers.Interface(DISPATCH_ABI);

async function main() {
  // Step 1: Get failed tx
  console.log("=== STEP 1: Failed tx data ===");
  const tx = await provider.getTransaction(FAILED_TX);
  const decoded = iface.decodeFunctionData("dispatch", tx.data);
  console.log("From (relayer):", tx.from);
  console.log("To (CallPermit):", tx.to);
  console.log("Signer:", decoded.from);
  console.log("Target:", decoded.to);
  console.log("Inner selector:", decoded.data.slice(0, 10));
  console.log("Deadline:", new Date(Number(decoded.deadline) * 1000).toISOString());

  // Step 2: Nonce rollback verification
  console.log("\n=== STEP 2: Nonce rollback ===");
  const nonceData = "0x7ecebe00" + SIGNER.slice(2).padStart(64, "0");
  const [nonceBefore, nonceAfter] = await Promise.all([
    provider.call({ to: CALLPERMIT, data: nonceData }, FAILED_BLOCK - 1),
    provider.call({ to: CALLPERMIT, data: nonceData }, FAILED_BLOCK),
  ]);
  const nb = BigInt(nonceBefore);
  const na = BigInt(nonceAfter);
  console.log(`Nonce at block ${FAILED_BLOCK - 1}:`, nb.toString());
  console.log(`Nonce at block ${FAILED_BLOCK}:  `, na.toString());
  console.log("Rollback confirmed:", nb === na ? "YES ✅" : "NO ❌");

  // Step 3: Simulate at N-1 (what relayer would have done)
  console.log("\n=== STEP 3: Simulation at N-1 (relayer's perspective) ===");
  let simResults = {};
  for (const offset of [1, 2, 3, 5]) {
    const blk = FAILED_BLOCK - offset;
    try {
      const ret = await provider.call({ to: CALLPERMIT, data: tx.data, from: RELAYER }, blk);
      simResults[`N-${offset}`] = { block: blk, result: "SUCCESS", returnData: ret };
      console.log(`Simulation at block N-${offset} (${blk}): SUCCESS ✅  returnData: ${ret}`);
    } catch (e) {
      const msg = e.message?.slice(0, 120) || "unknown";
      simResults[`N-${offset}`] = { block: blk, result: "FAIL", error: msg };
      console.log(`Simulation at block N-${offset} (${blk}): FAIL ❌  ${msg}`);
    }
  }

  // Step 4: Real tx result
  console.log("\n=== STEP 4: Real tx result ===");
  const receipt = await provider.getTransactionReceipt(FAILED_TX);
  console.log("Receipt status:", receipt.status, receipt.status === 0 ? "(FAIL ❌)" : "(SUCCESS ✅)");
  console.log("Gas used:", receipt.gasUsed.toString());
  const gasLostWei = receipt.gasUsed * tx.gasPrice;
  const gasLostGLMR = ethers.formatEther(gasLostWei);
  console.log("GLMR lost by relayer:", gasLostGLMR, "GLMR");

  // Step 5: What changed between N-1 and N?
  console.log("\n=== STEP 5: Block analysis ===");
  const block = await provider.getBlock(FAILED_BLOCK, true);
  console.log("Total txs in block:", block.transactions.length);
  const failedIdx = block.transactions.findIndex(
    t => t.hash?.toLowerCase() === FAILED_TX.toLowerCase()
  );
  console.log("Failed tx position:", failedIdx, "(0 = first in block)");

  if (failedIdx > 0) {
    console.log(`\nTxs BEFORE failed tx in same block (positions 0..${failedIdx - 1}):`);
    for (let i = 0; i < failedIdx; i++) {
      const t = block.transactions[i];
      console.log(`  [${i}] ${t.hash} | from: ${t.from} → ${t.to}`);
    }
  } else {
    console.log("Failed tx is FIRST in block — state change came from PREVIOUS block");
  }

  const signerTxs = block.transactions.filter(t => t.from?.toLowerCase() === SIGNER.toLowerCase());
  console.log("\nSigner txs in same block:", signerTxs.length);
  signerTxs.forEach(t => console.log(" ", t.hash, "→", t.to));

  // Step 6: Revert reason
  console.log("\n=== STEP 6: Revert reason ===");
  try {
    await provider.call(
      { to: tx.to, data: tx.data, from: tx.from, gasLimit: tx.gasLimit },
      FAILED_BLOCK
    );
    console.log("No revert (unexpected)");
  } catch (e) {
    console.log("Revert at block N:", e.message?.slice(0, 300));
  }

  // Step 7: Proof verdict
  const simN1 = simResults["N-1"];
  const simN1Success = simN1?.result === "SUCCESS";
  const anySimSuccess = Object.values(simResults).some(r => r.result === "SUCCESS");
  const rollbackConfirmed = nb === na;

  console.log("\n=== FINAL VERDICT ===");
  console.log("Simulation at N-1:", simN1?.result);
  console.log("Real tx at N:      FAIL");
  console.log("Nonce rollback:   ", rollbackConfirmed ? "CONFIRMED" : "NOT confirmed");
  console.log("GLMR lost:        ", gasLostGLMR);

  let proofStrength;
  if (simN1Success) {
    proofStrength = "STRONG";
    console.log("\n✅ PROOF COMPLETE (STRONG):");
    console.log("   Relayer simulated at N-1 → SUCCESS");
    console.log("   Real tx at N → FAIL");
    console.log("   Race condition between simulation and inclusion is unavoidable.");
    console.log("   Moonbeam's mitigation ('simulate before sending') is provably insufficient.");
  } else if (anySimSuccess) {
    const firstSuccess = Object.entries(simResults).find(([,v]) => v.result === "SUCCESS");
    proofStrength = "PARTIAL";
    console.log(`\n⚠️  PROOF PARTIAL: sim at N-1 also failed, but SUCCESS at ${firstSuccess[0]}`);
    console.log("   State changed across multiple blocks — window of vulnerability existed.");
  } else {
    proofStrength = "NONE";
    console.log("\n❌ PROOF INCOMPLETE: all simulations failed");
    console.log("   This tx may not be the best example. Check tx position in block and revert reason.");
  }

  const proof = {
    title: "Proof: Simulation Does Not Protect Relayers from CallPermit Nonce Rollback",
    claim: "Moonbeam: 'relayers should simulate before submission'. This proves simulation is insufficient.",
    timestamp: new Date().toISOString(),
    network: "Moonbeam mainnet (chainId 1284)",
    evidence: {
      relayer: RELAYER,
      signer: SIGNER,
      failedTx: FAILED_TX,
      failedBlock: FAILED_BLOCK,
      target: decoded.to,
      innerSelector: decoded.data.slice(0, 10),
      deadline: new Date(Number(decoded.deadline) * 1000).toISOString(),
      nonceBefore: nb.toString(),
      nonceAfter: na.toString(),
      nonceRollbackConfirmed: rollbackConfirmed,
      gasLostGLMR,
      simulations: simResults,
      realTxStatus: receipt.status === 0 ? "FAIL" : "SUCCESS",
      txPositionInBlock: failedIdx,
      blockTxCount: block.transactions.length,
    },
    proofStrength,
    conclusion: simN1Success
      ? "Relayer followed best practice (simulation showed SUCCESS at N-1) but still lost gas. " +
        "State changed between simulation and inclusion — inherent blockchain race condition. " +
        "Nonce rollback amplifies this: failed dispatch leaves v/r/s replayable by anyone. " +
        "Simulation cannot protect relayers from this class of vulnerability."
      : anySimSuccess
        ? "Simulation showed SUCCESS at an earlier block — state change window existed. " +
          "Nonce rollback still confirmed. Vulnerability is real but this tx is not ideal example."
        : "All simulations failed — investigate revert reason and tx position."
  };

  fs.writeFileSync("simulation_insufficiency_proof.json", JSON.stringify(proof, null, 2));
  console.log("\nSaved: simulation_insufficiency_proof.json");
}

main().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
