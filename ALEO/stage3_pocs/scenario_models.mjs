import fs from "node:fs/promises";
import path from "node:path";

const OUT_DIR = path.join(process.cwd(), "stage3_pocs");

function ok(name, data) {
  return { scenario: name, status: data.actual === data.expected ? "matches_expected" : "edge_case_reproduced", ...data };
}

function vlinkDuplicateAttestor() {
  const attestorA = "aleo_attestor_A";
  const attestors = [attestorA, attestorA, attestorA, attestorA, attestorA];
  const signatureValidByPosition = [true, true, true, true, true];
  const registered = new Set([attestorA]);
  const threshold = 3;

  const acceptedPositions = attestors.filter((addr, i) => registered.has(addr) && signatureValidByPosition[i]).length;
  const uniqueAccepted = new Set(attestors.filter((addr, i) => registered.has(addr) && signatureValidByPosition[i])).size;

  return ok("S1_vlink_duplicate_attestor_threshold", {
    contracts: ["vlink_token_bridge_v3.aleo"],
    inputs: { threshold, attestors, signatureValidByPosition },
    expected: false,
    actual: acceptedPositions >= threshold,
    invariant: "Bridge threshold should count unique attestors, not array positions.",
    observed_delta: { acceptedPositions, uniqueAccepted },
  });
}

function creditsThresholdFullUnbond() {
  const minDelegatorStake = 10_000_000_000n;
  const bonded = 10_000_000_500n;
  const requested = 1_000n;
  const residual = bonded - requested;
  const fallsBelowMinimum = residual < minDelegatorStake;
  const actualUnbonded = fallsBelowMinimum ? bonded : requested;

  return ok("S2_credits_partial_request_full_unbond", {
    contracts: ["credits.aleo", "whalepool_easystaking_v3.aleo"],
    inputs: {
      bonded: bonded.toString(),
      requested: requested.toString(),
      minDelegatorStake: minDelegatorStake.toString(),
    },
    expected: requested.toString(),
    actual: actualUnbonded.toString(),
    invariant: "A partial unbond request should not silently become full unbond unless callers account for that branch.",
    observed_delta: {
      residual: residual.toString(),
      fallsBelowMinimum,
      extraUnbonded: (actualUnbonded - requested).toString(),
    },
  });
}

function tokenRegistryAuthExpiryReordering() {
  const proofHeight = 999;
  const authorizedUntil = 1000;
  const finalizeHeightIfOrdered = 1000;
  const finalizeHeightIfDelayed = 1001;
  const proofLocallyValid = proofHeight <= authorizedUntil;
  const orderedPasses = finalizeHeightIfOrdered <= authorizedUntil;
  const delayedPasses = finalizeHeightIfDelayed <= authorizedUntil;

  return ok("S3_token_registry_authorization_expiry_reordering", {
    contracts: ["token_registry.aleo", "arcn_pool_v2_2_2.aleo", "hyp_warp_token_*.aleo"],
    inputs: { proofHeight, authorizedUntil, finalizeHeightIfOrdered, finalizeHeightIfDelayed },
    expected: true,
    actual: delayedPasses,
    invariant: "A router/pool should not assume a valid private proof remains executable after block reordering delay.",
    observed_delta: { proofLocallyValid, orderedPasses, delayedPasses },
  });
}

function pondoTvlTolerance() {
  const reportedTvl = 1_020_000_000_000n;
  const actualRecomputedTvl = 1_000_000_000_000n;
  const lower = (reportedTvl * 98n) / 100n;
  const upper = (reportedTvl * 102n) / 100n;
  const acceptedByTolerance = actualRecomputedTvl >= lower && actualRecomputedTvl <= upper;

  return ok("S4_pondo_tvl_tolerance_stale_oracle", {
    contracts: ["pondo_protocol.aleo", "validator_oracle.aleo", "credits.aleo", "delegator1-5.aleo"],
    inputs: {
      reportedTvl: reportedTvl.toString(),
      actualRecomputedTvl: actualRecomputedTvl.toString(),
      tolerance: "98%-102% of reported value",
    },
    expected: false,
    actual: acceptedByTolerance,
    invariant: "Oracle TVL should not be economically exploitable through tolerated drift near rebalance/accounting boundaries.",
    observed_delta: {
      lower: lower.toString(),
      upper: upper.toString(),
      acceptedDrift: (reportedTvl - actualRecomputedTvl).toString(),
    },
  });
}

function usdcxFreezeRootGraceWindow() {
  const rootUpdatedHeight = 50_000;
  const blockHeightWindow = 360;
  const mintHeight = 50_100;
  const usingPreviousRoot = true;
  const previousRootStillAccepted = usingPreviousRoot && rootUpdatedHeight + blockHeightWindow > mintHeight;
  const nullifierPreviouslyUsed = false;
  const actualMintPasses = previousRootStillAccepted && !nullifierPreviouslyUsed;

  return ok("S5_usdcx_bridge_previous_freeze_root_window", {
    contracts: ["usdcx_bridge.aleo", "usdcx_freezelist.aleo", "usdcx_stablecoin.aleo"],
    inputs: { rootUpdatedHeight, blockHeightWindow, mintHeight, usingPreviousRoot, nullifierPreviouslyUsed },
    expected: false,
    actual: actualMintPasses,
    invariant: "A newly frozen address should not be mintable through an old root unless the grace window is explicitly accepted risk.",
    observed_delta: { previousRootValidUntil: rootUpdatedHeight + blockHeightWindow },
  });
}

function daraStaleOracleConsumer() {
  const currentHeight = 100_000;
  const priceUpdateBlock = 90_000;
  const assumedMaxAge = 3_600;
  const oracleRoundIncreased = true;
  const deltaWithinLimit = true;
  const consumerChecksFreshness = false;
  const stale = currentHeight - priceUpdateBlock > assumedMaxAge;
  const actualOrderAccepted = oracleRoundIncreased && deltaWithinLimit && (!consumerChecksFreshness || !stale);

  return ok("S6_dara_stale_oracle_order_acceptance", {
    contracts: ["dara_dp_credit_v5.aleo", "dara_lend_v8.aleo", "dara_flash_v1.aleo"],
    inputs: { currentHeight, priceUpdateBlock, assumedMaxAge, oracleRoundIncreased, deltaWithinLimit },
    expected: false,
    actual: actualOrderAccepted,
    invariant: "Price consumers should reject stale oracle data, not only monotonic rounds or bounded deltas.",
    observed_delta: { stale, age: currentHeight - priceUpdateBlock, consumerChecksFreshness },
  });
}

async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });
  const results = [
    vlinkDuplicateAttestor(),
    creditsThresholdFullUnbond(),
    tokenRegistryAuthExpiryReordering(),
    pondoTvlTolerance(),
    usdcxFreezeRootGraceWindow(),
    daraStaleOracleConsumer(),
  ];
  const outPath = path.join(OUT_DIR, "scenario_results.json");
  await fs.writeFile(outPath, `${JSON.stringify({ generatedAt: new Date().toISOString(), results }, null, 2)}\n`);
  console.log(JSON.stringify(results, null, 2));
  console.log(`\nWrote ${outPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
