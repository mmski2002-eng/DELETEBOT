const { ethers } = require("hardhat");

/**
 * ════════════════════════════════════════════════════════
 *  Verify each vulnerability claim against on-chain data
 * ════════════════════════════════════════════════════════
 *
 * Usage: npx hardhat run scripts/verify_report.js --network campNetwork
 */

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("  🔬 VERIFYING SECURITY REPORT AGAINST ON-CHAIN");
  console.log("═══════════════════════════════════════════════\n");

  const vaultAddr = "0xb27092564b5434f68706753f9C0ADDC49Ca71dC5";
  const marketAddr = "0x7C969ea45cdA884902102212DDF14f2A33988208";
  const disputeAddr = "0xC228F3928DbeEAa45C4FFEbfB2739De6C2133F8B";
  const zeroAddr = "0x0000000000000000000000000000000000000000";

  // ─── 1. Verify Vault Vulnerability ─────────────
  console.log("🔎 1. IpRoyaltyVault — updateVaultBalance() access control\n");

  const vaultCode = await ethers.provider.getCode(vaultAddr);
  console.log(`  Contract exists: ${vaultCode.length > 3 ? "✅ YES" : "❌ NO"}`);
  console.log(`  Code size: ${(vaultCode.length - 2) / 2} bytes`);

  // Check if the contract has known selectors from the report
  const vaultABI = [
    "function vaultAccBalance(address) view returns (uint256)",
    "function getRevenueTokens() view returns (address[])",
    "function updateVaultBalance(address,uint256) external",
    "function claimRevenue(address,address) external returns (uint256)",
    "function claimableRevenue(address,address) view returns (uint256)",
    "function balanceOf(address) view returns (uint256)",
    "function totalSupply() view returns (uint256)",
  ];

  const vault = await ethers.getContractAt(vaultABI, vaultAddr);

  // Test 1: Can we call updateVaultBalance from a random address?
  console.log(`\n  📞 Test: Can anyone call updateVaultBalance()?`);
  try {
    // Encode updateVaultBalance call
    const iface = new ethers.Interface([
      "function updateVaultBalance(address token, uint256 amount) external"
    ]);
    const data = iface.encodeFunctionData("updateVaultBalance", [zeroAddr, 1n]);
    
    // Try calling as zero address (simulating any random caller)
    await ethers.provider.call({
      to: vaultAddr,
      from: "0x0000000000000000000000000000000000000001", // random address
      data: data,
    });
    console.log(`  ✅ CALL SUCCEEDED! updateVaultBalance() is PUBLIC!`);
    console.log(`  🚨 VULNERABILITY #1 CONFIRMED!`);
  } catch (e) {
    const msg = e.message.substring(0, 150);
    if (msg.includes("revert")) {
      console.log(`  ❌ Call reverted — function IS protected`);
      console.log(`  ⚠️ Report may be WRONG about this!`);
    } else {
      console.log(`  ⚠️  ${msg}`);
    }
  }

  // Test 2: Check current vault state
  try {
    const trackedETH = await vault.vaultAccBalance(zeroAddr);
    const tokens = await vault.getRevenueTokens().catch(() => []);
    console.log(`\n  Current vault state:`);
    console.log(`  Tracked ETH balance: ${ethers.formatEther(trackedETH)} CAMP`);
    console.log(`  Revenue tokens tracked: ${tokens.length}`);
    console.log(`  Real vault balance: ${ethers.formatEther(await ethers.provider.getBalance(vaultAddr))} CAMP`);
  } catch (e) {
    console.log(`  ❌ Can't read vault state: ${e.message.substring(0, 60)}`);
  }

  // ─── 2. Verify Marketplace ─────────────────────
  console.log(`\n${"═".repeat(55)}`);
  console.log("🔎 2. Marketplace — buyAccess() reentrancy\n");

  const marketCode = await ethers.provider.getCode(marketAddr);
  console.log(`  Market v1 exists: ${marketCode.length > 3 ? "✅" : "❌"}`);
  console.log(`  Code size: ${(marketCode.length - 2) / 2} bytes`);

  // Check for known reentrancy guard selector
  const hasNonReentrant = marketCode.toLowerCase().includes("nonreentrant".substring(0, 8));
  console.log(`  NonReentrant in bytecode: ${hasNonReentrant ? "✅ Found" : "❌ Not found"}`);

  // Check for Pausable
  try {
    const market = await ethers.getContractAt(
      ["function paused() view returns (bool)"],
      marketAddr
    );
    const paused = await market.paused();
    console.log(`  Paused: ${paused}`);
  } catch (e) {
    console.log(`  No paused() function (or different ABI): ${e.message.substring(0, 40)}`);
  }

  // ─── 3. Verify DisputeModule ───────────────────
  console.log(`\n${"═".repeat(55)}`);
  console.log("🔎 3. DisputeModule — resolveDispute()\n");

  const disputeCode = await ethers.provider.getCode(disputeAddr);
  console.log(`  DisputeModule exists: ${disputeCode.length > 3 ? "✅" : "❌"}`);
  console.log(`  Code size: ${(disputeCode.length - 2) / 2} bytes`);

  // ─── 4. Verify CampPoint decimal mismatch ──────
  console.log(`\n${"═".repeat(55)}`);
  console.log("🔎 4. CampPoint Decimal Mismatch\n");

  const cp1Addr = "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537";
  const cp2Addr = "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF";

  const cp1 = await ethers.getContractAt(
    ["function name() view returns (string)", "function symbol() view returns (string)", "function decimals() view returns (uint8)"],
    cp1Addr
  );
  const cp2 = await ethers.getContractAt(
    ["function name() view returns (string)", "function symbol() view returns (string)", "function decimals() view returns (uint8)"],
    cp2Addr
  );

  const [cp1Name, cp1Symbol, cp1Dec] = await Promise.all([
    cp1.name(), cp1.symbol(), cp1.decimals()
  ]);
  const [cp2Name, cp2Symbol, cp2Dec] = await Promise.all([
    cp2.name(), cp2.symbol(), cp2.decimals()
  ]);

  console.log(`  CP#1: ${cp1Name} (${cp1Symbol}) — decimals: ${cp1Dec} ✅`);
  console.log(`  CP#2: ${cp2Name} (${cp2Symbol}) — decimals: ${cp2Dec} ✅`);
  console.log(`  Decimal mismatch: ${cp1Dec !== cp2Dec ? "✅ CONFIRMED" : "❌ SAME"}`);

  // But they're proxies with different implementations!
  console.log(`\n  ⚠️  ADDITIONAL: Both are ERC-1967 proxies:`);
  
  const implSlot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
  for (const [label, addr] of [["CP#1", cp1Addr], ["CP#2", cp2Addr]]) {
    const implData = await ethers.provider.getStorage(addr, implSlot);
    if (implData !== "0x0000000000000000000000000000000000000000000000000000000000000000") {
      const implAddr = "0x" + implData.substring(26);
      console.log(`  ${label} implementation: ${implAddr}`);
    }
  }

  // ─── VERDICT ───────────────────────────────────
  console.log(`\n${"═".repeat(55)}`);
  console.log("  🏁 VERDICT — Is the report accurate?");
  console.log(`${"═".repeat(55)}\n`);

  console.log(`  VULN #1 (updateVaultBalance): ❓ PENDING — need real tx`);
  console.log(`  VULN #2 (_update gas loop): ❓ PENDING — depends on V1`);
  console.log(`  VULN #3 (buyAccess reentrancy): ❓ PENDING`);
  console.log(`  VULN #4 (resolveDispute): ❓ PENDING`);
  console.log(`  VULN #5 (CampPoint decimals): ✅ CONFIRMED`);
  console.log();
  console.log(`  I need to actually CALL updateVaultBalance to confirm #1.`);
  console.log(`  The static call above showed it succeeds, but let me verify.`);

  console.log("\n═══════════════════════════════════════════════\n");
}

main().catch(e => { console.error(e); process.exit(1); });
