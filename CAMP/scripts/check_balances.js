const { ethers } = require("hardhat");

/**
 * ════════════════════════════════════════════════════════
 *  Check on-chain balances of vulnerable contracts
 * ════════════════════════════════════════════════════════
 *
 * Usage: npx hardhat run scripts/check_balances.js --network campNetwork
 */

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("  ON-CHAIN BALANCE CHECK — Camp Network");
  console.log("═══════════════════════════════════════════════\n");

  const vaultAddr = "0xb27092564b5434f68706753f9C0ADDC49Ca71dC5";
  const marketAddr = "0x7C969ea45cdA884902102212DDF14f2A33988208";
  const disputeAddr = "0xC228F3928DbeEAa45C4FFEbfB2739De6C2133F8B";
  const zeroAddr = "0x0000000000000000000000000000000000000000";

  // ─── IP Royalty Vault ─────────────────────────
  console.log("🔴 [VAULT] IpRoyaltyVault");
  console.log(`  Address: ${vaultAddr}`);
  const vaultETH = await ethers.provider.getBalance(vaultAddr);
  console.log(`  Native ETH balance: ${ethers.formatEther(vaultETH)} ETH`);

  // Check if vault has code
  const vaultCode = await ethers.provider.getCode(vaultAddr);
  console.log(`  Has code on-chain: ${vaultCode.length > 3 ? "✅ YES" : "❌ NO"}`);

  // ─── Try reading vault state ────────────────────
  const abi = [
    "function vaultAccBalance(address) view returns (uint256)",
    "function getRevenueTokens() view returns (address[])",
    "function claimerRevenueDebt(address,address) view returns (int256)",
    "function balanceOf(address) view returns (uint256)",
    "function totalSupply() view returns (uint256)",
  ];

  try {
    const vault = await ethers.getContractAt(abi, vaultAddr);
    const tracked = await vault.vaultAccBalance(zeroAddr);
    console.log(`  Tracked ETH balance (vaultAccBalance): ${ethers.formatEther(tracked)} ETH`);

    // Check discrepancy
    if (tracked > vaultETH) {
      const diff = tracked - vaultETH;
      console.log(`  ⚠️  DISCREPANCY: tracked > real by ${ethers.formatEther(diff)} ETH`);
    } else if (tracked < vaultETH) {
      const diff = vaultETH - tracked;
      console.log(`  ⚠️  DISCREPANCY: tracked < real by ${ethers.formatEther(diff)} ETH`);
    } else {
      console.log(`  ✅ Tracked balance matches real balance`);
    }

    // Check revenue tokens
    const tokens = await vault.getRevenueTokens();
    console.log(`  Revenue tokens tracked: ${tokens.length}`);
    if (tokens.length > 0) {
      for (let i = 0; i < Math.min(tokens.length, 5); i++) {
        console.log(`    [${i}] ${tokens[i]}`);
        const bal = await vault.vaultAccBalance(tokens[i]);
        console.log(`        tracked balance: ${ethers.formatEther(bal)}`);
        // Get real token balance
        try {
          const token = await ethers.getContractAt(
            ["function balanceOf(address) view returns (uint256)", "function symbol() view returns (string)"],
            tokens[i]
          );
          const realBal = await token.balanceOf(vaultAddr);
          const symbol = await token.symbol();
          console.log(`        real balance (${symbol}): ${ethers.formatEther(realBal)}`);
          if (bal > realBal) {
            console.log(`        ❌ INFLATED by ${ethers.formatEther(bal - realBal)}`);
          }
        } catch(e) {
          console.log(`        Could not check real balance`);
        }
      }
      if (tokens.length > 5) {
        console.log(`    ... and ${tokens.length - 5} more`);
      }
    }
  } catch (e) {
    console.log(`  ❌ Could not read vault state: ${e.message}`);
  }

  // ─── Check marketplace ──────────────────────────
  console.log(`\n🟠 [MARKETPLACE] v1`);
  console.log(`  Address: ${marketAddr}`);
  const marketETH = await ethers.provider.getBalance(marketAddr);
  console.log(`  ETH balance: ${ethers.formatEther(marketETH)} ETH`);
  const marketCode = await ethers.provider.getCode(marketAddr);
  console.log(`  Has code: ${marketCode.length > 3 ? "✅ YES" : "❌ NO"}`);

  // ─── Check DisputeModule ────────────────────────
  console.log(`\n🟡 [DISPUTE] DisputeModule`);
  console.log(`  Address: ${disputeAddr}`);
  const disputeETH = await ethers.provider.getBalance(disputeAddr);
  console.log(`  ETH balance: ${ethers.formatEther(disputeETH)} ETH`);

  // ─── Check CampPoint tokens ─────────────────────
  const cp1Addr = "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537";
  const cp2Addr = "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF";
  const tokenABI = [
    "function decimals() view returns (uint8)",
    "function totalSupply() view returns (uint256)",
    "function symbol() view returns (string)",
    "function balanceOf(address) view returns (uint256)",
  ];

  console.log(`\n🟡 [TOKENS] CampPoint Decimal Mismatch`);

  const cp1 = await ethers.getContractAt(tokenABI, cp1Addr);
  const cp2 = await ethers.getContractAt(tokenABI, cp2Addr);

  const cp1Sym = await cp1.symbol();
  const cp2Sym = await cp2.symbol();
  const cp1Dec = await cp1.decimals();
  const cp2Dec = await cp2.decimals();
  const cp1Supply = await cp1.totalSupply();
  const cp2Supply = await cp2.totalSupply();

  console.log(`  ${cp1Sym} #1: ${cp1Addr}`);
  console.log(`    Decimals: ${cp1Dec}`);
  console.log(`    Total Supply: ${cp1Supply.toString()}`);
  console.log(`  ${cp2Sym} #2: ${cp2Addr}`);
  console.log(`    Decimals: ${cp2Dec}`);
  console.log(`    Total Supply: ${ethers.formatEther(cp2Supply)}`);

  // Check if vault has these tokens
  const vaultCP1 = await cp1.balanceOf(vaultAddr);
  const vaultCP2 = await cp2.balanceOf(vaultAddr);
  console.log(`  Vault CP1 (0-dec) balance: ${vaultCP1.toString()}`);
  console.log(`  Vault CP2 (18-dec) balance: ${ethers.formatEther(vaultCP2)}`);

  // ─── Check other tokens in vault ────────────────
  console.log(`\n📊 [VAULT] Token holdings`);
  const tokensToCheck = [
    { addr: "0xC42BAA20e3a159cF7A8aDFA924648C2a2d59E062", name: "WETH", decimals: 18 },
    { addr: "0x587aF234D373C752a6F6E9eD6c4Ce871e7528BCF", name: "WBTC", decimals: 8 },
    { addr: "0x71002dbf6cC7A885cE6563682932370c056aAca9", name: "MUSDC", decimals: 6 },
    { addr: "0x1aE9c40eCd2DD6ad5858E5430A556d7aff28A44b", name: "wCAMP", decimals: 18 },
    { addr: "0xe9a9aFfb353c2daE8453d041bc849ae5946B996b", name: "sxUSDC", decimals: 6 },
  ];

  for (const t of tokensToCheck) {
    try {
      const token = await ethers.getContractAt(
        ["function balanceOf(address) view returns (uint256)"],
        t.addr
      );
      const bal = await token.balanceOf(vaultAddr);
      console.log(`  ${t.name}: ${ethers.formatUnits(bal, t.decimals)}`);
    } catch (e) {
      console.log(`  ${t.name}: ❌ could not read (${e.message.split('(')[0]})`);
    }
  }

  // ─── Check Game Rooms ───────────────────────────
  console.log(`\n🎮 [GAMES] Game Rooms`);
  const gameRooms = [
    { addr: "0x41bC74bA2AD289EC615743C1Eea82977427A798B", name: "GameRoom #1" },
    { addr: "0x88a029A09f3037dA191fbE90E917257B8C5fE29b", name: "GameRoom #2" },
    { addr: "0x065355AC879A3f4F85C5dd89aA255F8Dd07822B6", name: "GameRoom #3" },
    { addr: "0x5eddEa35aeDDbc3fccF390B3D4F8D4775bF22FD5", name: "GameRoom #4" },
    { addr: "0x22E5A26E21Eaac16F4D452392d7D7c1fAa8E0F67", name: "GameRoom #5" },
  ];

  let totalGames = 0n;
  for (const gr of gameRooms) {
    const bal = await ethers.provider.getBalance(gr.addr);
    totalGames += bal;
    console.log(`  ${gr.name}: ${ethers.formatEther(bal)} CAMP`);
  }
  console.log(`  ──────────────────────────`);
  console.log(`  TOTAL in Game Rooms: ${ethers.formatEther(totalGames)} CAMP`);

  // ─── Bridge ──────────────────────────────────────
  const bridgeAddr = "0x12C3E3B84B75ca4a9388de696621ac5F2Ae36953";
  console.log(`\n🌉 [BRIDGE] CrustySwap`);
  const bridgeBal = await ethers.provider.getBalance(bridgeAddr);
  console.log(`  ETH balance: ${ethers.formatEther(bridgeBal)} ETH`);

  console.log("\n═══════════════════════════════════════════════");
  console.log("  CHECK COMPLETE");
  console.log("═══════════════════════════════════════════════\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
