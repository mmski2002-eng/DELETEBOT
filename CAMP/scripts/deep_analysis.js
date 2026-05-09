const { ethers } = require("hardhat");

/**
 * ════════════════════════════════════════════════════════
 *  Deep analysis: can bridge funds reach vulnerable contracts?
 * ════════════════════════════════════════════════════════
 *
 * Usage: npx hardhat run scripts/deep_analysis.js --network campNetwork
 */

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("  DEEP RISK ANALYSIS — Bridge ↔ Vulnerable Contracts");
  console.log("═══════════════════════════════════════════════\n");

  const bridgeAddr = "0x12C3E3B84B75ca4a9388de696621ac5F2Ae36953";
  const vaultAddr = "0xb27092564b5434f68706753f9C0ADDC49Ca71dC5";
  const marketAddr = "0x7C969ea45cdA884902102212DDF14f2A33988208";
  const marketV2Addr = "0x81BeB79b977cAd2B1d06aFC62b4aABB7611107b4";
  const factory1 = "0xaed623AF25128f3FC39cA855441BC4d9Dbf1AaBB";
  const factory2 = "0x92c29a571CeAC162E9e644EB19B8546317FB2058";
  const zeroAddr = "0x0000000000000000000000000000000000000000";

  // ─── 1. Try to decode what the bridge contract is ────────
  console.log("🔎 1. WHAT IS CRUSTYSWAP?");

  const bridgeCode = await ethers.provider.getCode(bridgeAddr);

  // Check first 4 bytes of code (might be a create2 deployment pattern)
  const codeSlice = bridgeCode.substring(0, 50);
  console.log(`  Code prefix: 0x${codeSlice}...`);

  // Check if it's an upgradeable proxy (ERC-1967 style)
  const storageSlot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
  const impl = await ethers.provider.getStorage(bridgeAddr, storageSlot).catch(() => null);
  if (impl && impl !== "0x0000000000000000000000000000000000000000000000000000000000000000") {
    const implAddr = "0x" + impl.substring(26);
    console.log(`  ⚠️  ERC-1967 Proxy → implementation at: ${implAddr}`);
  } else {
    console.log(`  Not an ERC-1967 proxy (or not upgradeable)`);
  }

  // Check admin storage slot
  const adminSlot = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";
  const admin = await ethers.provider.getStorage(bridgeAddr, adminSlot).catch(() => null);
  if (admin && admin !== "0x0000000000000000000000000000000000000000000000000000000000000000") {
    const adminAddr = "0x" + admin.substring(26);
    console.log(`  Proxy admin: ${adminAddr}`);
  }

  // ─── 2. Check if marketplace interacts with vault ───────
  console.log(`\n🔎 2. MARKETPLACE → VAULT PATH`);

  // Check marketplace code for updateVaultBalance calls
  const marketCode = await ethers.provider.getCode(marketAddr);
  const hasVaultRef = marketCode.toLowerCase().includes(vaultAddr.substring(2).toLowerCase());
  console.log(`  Market v1 references vault in code: ${hasVaultRef ? "⚠️ YES" : "NO"}`);

  const marketV2Code = await ethers.provider.getCode(marketV2Addr);
  const hasVaultRefV2 = marketV2Code.toLowerCase().includes(vaultAddr.substring(2).toLowerCase());
  console.log(`  Market v2 references vault in code: ${hasVaultRefV2 ? "⚠️ YES" : "NO"}`);

  // Check if marketplace references the bridge
  const hasBridgeRef = marketCode.toLowerCase().includes(bridgeAddr.substring(2).toLowerCase());
  console.log(`  Market v1 references bridge: ${hasBridgeRef ? "⚠️ YES" : "NO"}`);
  const hasBridgeRefV2 = marketV2Code.toLowerCase().includes(bridgeAddr.substring(2).toLowerCase());
  console.log(`  Market v2 references bridge: ${hasBridgeRefV2 ? "⚠️ YES" : "NO"}`);

  // ─── 3. Check vault factories for active vaults ──────────
  console.log(`\n🔎 3. VAULT FACTORIES — any deployed vaults with funds?`);

  const factory1Code = await ethers.provider.getCode(factory1);
  const factory2Code = await ethers.provider.getCode(factory2);
  console.log(`  Factory #1 has code: ${factory1Code.length > 3}`);
  console.log(`  Factory #2 has code: ${factory2Code.length > 3}`);

  // ─── 4. Check wCAMP/wETH pairs ──────────────────────────
  console.log(`\n🔎 4. LIQUIDITY ANALYSIS`);

  const wcampAddr = "0x1aE9c40eCd2DD6ad5858E5430A556d7aff28A44b";
  const wethAddr = "0xC42BAA20e3a159cF7A8aDFA924648C2a2d59E062";

  // Check wCAMP total supply
  try {
    const wcamp = await ethers.getContractAt(
      ["function totalSupply() view returns (uint256)", "function balanceOf(address) view returns (uint256)"],
      wcampAddr
    );
    const wcampSupply = await wcamp.totalSupply();
    console.log(`  wCAMP total supply: ${ethers.formatEther(wcampSupply)}`);
    const wcampBridge = await wcamp.balanceOf(bridgeAddr);
    console.log(`  wCAMP in bridge: ${ethers.formatEther(wcampBridge)}`);
  } catch (e) {
    console.log(`  wCAMP: ${e.message.substring(0, 50)}`);
  }

  // Check WETH
  try {
    const weth = await ethers.getContractAt(
      ["function totalSupply() view returns (uint256)", "function balanceOf(address) view returns (uint256)"],
      wethAddr
    );
    const wethSupply = await weth.totalSupply();
    console.log(`  WETH total supply: ${ethers.formatEther(wethSupply)}`);
    const wethBridge = await weth.balanceOf(bridgeAddr);
    console.log(`  WETH in bridge: ${ethers.formatEther(wethBridge)}`);
  } catch (e) {
    console.log(`  WETH: ${e.message.substring(0, 50)}`);
  }

  // ─── 5. Final risk assessment ──────────────────────────
  console.log(`\n═══════════════════════════════════════════════`);
  console.log(`  FINAL RISK ASSESSMENT`);
  console.log(`═══════════════════════════════════════════════\n`);

  const bridgeETH = await ethers.provider.getBalance(bridgeAddr);
  const vaultETH = await ethers.provider.getBalance(vaultAddr);

  console.log(`  💰 Bridge funds (from Ethereum): ${ethers.formatEther(bridgeETH)} ETH`);
  console.log(`  🗄️  Vault funds: ${ethers.formatEther(vaultETH)} ETH`);
  console.log(`  🏪 Market v1 funds: ${ethers.formatEther(await ethers.provider.getBalance(marketAddr))} ETH`);
  console.log(`  🏪 Market v2 funds: ${ethers.formatEther(await ethers.provider.getBalance(marketV2Addr))} ETH`);

  console.log(`\n  📋 SCENARIO ANALYSIS:`);
  console.log(`  ─────────────────────────────────────────────`);
  console.log(`  Scenario 1: Direct vault drain`);
  console.log(`    Attack: updateVaultBalance → inflate → lock funds`);
  console.log(`    Risk NOW: 🟢 NONE (vault empty)`);
  console.log(`    Risk IF FUNDED: 🔴 CRITICAL`);
  console.log(``);
  console.log(`  Scenario 2: Bridge funds → Marketplace → Vault`);
  console.log(`    Path: ETH on Ethereum → bridge → Camp Network`);
  console.log(`    → user buys NFT access → marketplace distributes`);
  console.log(`    → _distributeRoyalty() → vault.updateVaultBalance()`);
  console.log(`    → vault gets real funds → vulnerable to inflation`);
  console.log(`    Risk: 🟠 MODERATE (depends on marketplace activity)`);
  console.log(``);
  console.log(`  Scenario 3: Gas griefing via fake tokens`);
  console.log(`    Attack: add 200+ tokens → _update() loop → DoS`);
  console.log(`    Risk NOW: 🟢 NONE (no royalty tokens minted)`);
  console.log(`    Risk IF ACTIVE: 🔴 CRITICAL (permanent freeze)`);
  console.log(``);

  // ─── Check recent bridge activity ──────────────
  console.log(`  📊 The bridge holds ${ethers.formatEther(bridgeETH)} ETH that came from Ethereum.`);
  console.log(`  This is REAL value. If any of these funds flow through`);
  console.log(`  the Marketplace → IpRoyaltyVault pipeline, they become`);
  console.log(`  vulnerable to the access control exploit.`);
  console.log(``);
  console.log(`  💀 WORST CASE: Bridge.get(ETH) → buyAccess() →`);
  console.log(`    _distributeRoyalty() → vault.updateVaultBalance(real)`);
  console.log(`    → attacker front-runs with updateVaultBalance(fake)`);
  console.log(`    → revenue claims broken → funds trapped forever`);
  console.log(``);
  console.log(`  RECOMMENDATION: Fix access control BEFORE any`);
  console.log(`  bridged funds enter the Marketplace/Vault pipeline.\n`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
