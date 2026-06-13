import fs from "node:fs/promises";
import path from "node:path";

const OUT_DIR = path.join(process.cwd(), "stage4_verification");

function result(id, title, status, details) {
  return { id, title, status, ...details };
}

function verifyVlinkDuplicateAttestor() {
  const zero = "aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc";
  const A = "aleo_attestor_A";
  const attestors = [A, A, A, A, A];
  const nonZero = attestors.filter((x) => x !== zero);
  const pairwiseUnique = new Set(nonZero).size === nonZero.length;
  const transitionAccepts = pairwiseUnique;
  return result("S1", "VLink duplicate attestor threshold", "REFUTED_BY_SOURCE", {
    contracts: ["vlink_token_bridge_v3.aleo"],
    expectedForBug: "duplicate non-zero attestors accepted",
    actual: "duplicate non-zero attestors rejected by pairwise is.neq checks before signature counting",
    sourceEvidence: [
      "vlink_token_bridge_v3.aleo consume checks r9[0] != r9[1..4] unless r9[0] is zero",
      "then r9[1] != r9[2..4], r9[2] != r9[3..4], r9[3] != r9[4]",
      "zero-address placeholders do not increment signer count",
    ],
    model: { attestors, pairwiseUnique, transitionAccepts },
    bountyAction: "Do not submit as duplicate-attestor bug. Retain bridge review for PacketId/domain binding instead.",
  });
}

function verifyCreditsFullUnbond() {
  const minDelegatorStake = 10_000_000_000n;
  const bonded = 10_000_000_500n;
  const requested = 1_000n;
  const residual = bonded - requested;
  const actual = residual < minDelegatorStake ? bonded : requested;
  return result("S2", "credits.aleo partial unbond becomes full unbond near minimum", "SOURCE_CONFIRMED_BEHAVIOR", {
    contracts: ["credits.aleo", "whalepool_easystaking_v3.aleo"],
    inputData: { bonded: bonded.toString(), requested: requested.toString(), minDelegatorStake: minDelegatorStake.toString() },
    expectedForExploit: requested.toString(),
    actual: actual.toString(),
    sourceEvidence: ["credits.aleo finalize unbond_public: lt residual 10_000_000_000u64", "ternary r18 r5.microcredits r2 selects full bonded amount when residual below minimum"],
    exploitStatus: "Needs wrapper-level accounting mismatch proof. Core behavior alone may be intentional.",
  });
}

function verifyTokenExpiry() {
  const authorizedUntil = 1000;
  const proofHeight = 999;
  const ordered = 1000;
  const delayed = 1001;
  return result("S3", "token_registry authorization expiry reordering", "SOURCE_CONFIRMED_EDGE_CASE", {
    contracts: ["token_registry.aleo", "arcn_pool_v2_2_2.aleo", "hyp_warp_token_*.aleo"],
    inputData: { proofHeight, authorizedUntil, orderedFinalizeHeight: ordered, delayedFinalizeHeight: delayed },
    actual: { proofBuiltBeforeExpiry: proofHeight <= authorizedUntil, orderedPasses: ordered <= authorizedUntil, delayedPasses: delayed <= authorizedUntil },
    sourceEvidence: ["token_registry finalize paths check lte block.height authorized_until"],
    exploitStatus: "Likely DoS/griefing unless downstream state drift is demonstrated.",
  });
}

function verifyPondoTolerance() {
  const reported = 1_020_000_000_000n;
  const actualTvl = 1_000_000_000_000n;
  const lower = (reported * 98n) / 100n;
  const upper = (reported * 102n) / 100n;
  return result("S4", "Pondo TVL tolerance accepts 2% drift", "SOURCE_CONFIRMED_BEHAVIOR", {
    contracts: ["pondo_protocol.aleo", "validator_oracle.aleo", "credits.aleo", "delegator1-5.aleo"],
    inputData: { reported: reported.toString(), actualTvl: actualTvl.toString() },
    actual: { lower: lower.toString(), upper: upper.toString(), accepted: actualTvl >= lower && actualTvl <= upper },
    sourceEvidence: ["pondo_protocol finalize set_oracle_tvl computes reported*98/100 and reported*102/100 bounds"],
    exploitStatus: "Needs downstream effect on shares/rewards/rebalance to become bounty-ready.",
  });
}

function verifyUsdcxFreezeRootWindow() {
  const rootUpdatedHeight = 50_000;
  const window = 360;
  const mintHeight = 50_100;
  const accepted = rootUpdatedHeight + window > mintHeight;
  return result("S5", "USDCX bridge previous freeze root accepted inside window", "SOURCE_CONFIRMED_BEHAVIOR", {
    contracts: ["usdcx_bridge.aleo", "usdcx_freezelist.aleo", "usdcx_stablecoin.aleo"],
    inputData: { rootUpdatedHeight, blockHeightWindow: window, mintHeight },
    actual: { previousRootAccepted: accepted, validUntilExclusive: rootUpdatedHeight + window },
    sourceEvidence: ["usdcx_bridge finalize mint_private accepts freeze_list_root[2u8] when root_updated_height + block_height_window > block.height"],
    exploitStatus: "Potentially bounty-worthy if frozen address can mint using old root after freeze update.",
  });
}

function verifyDaraStaleOracle() {
  return result("S6", "DARA stale oracle consumer acceptance", "NEEDS_PATH_PROOF", {
    contracts: ["dara_dp_credit_v5.aleo", "dara_lend_v8.aleo", "dara_flash_v1.aleo"],
    sourceEvidence: ["update_oracle_price has monotonic round and delta checks", "price_update_block mappings exist in lending/flash suite"],
    exploitStatus: "Need exact consumer function without max-age check. Testnet impact lowers bounty value.",
  });
}

async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });
  const results = [
    verifyVlinkDuplicateAttestor(),
    verifyCreditsFullUnbond(),
    verifyTokenExpiry(),
    verifyPondoTolerance(),
    verifyUsdcxFreezeRootWindow(),
    verifyDaraStaleOracle(),
  ];
  await fs.writeFile(path.join(OUT_DIR, "verification_results.json"), `${JSON.stringify({ generatedAt: new Date().toISOString(), results }, null, 2)}\n`);
  console.log(JSON.stringify(results, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
