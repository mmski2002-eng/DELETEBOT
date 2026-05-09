const { ethers } = require("hardhat");

/**
 * ════════════════════════════════════════════════════════
 *  Check CrustySwap Bridge — connection to vulnerable contracts
 * ════════════════════════════════════════════════════════
 *
 * Usage: npx hardhat run scripts/check_bridge.js --network campNetwork
 */

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("  BRIDGE ANALYSIS — CrustySwap (funded from ETH)");
  console.log("═══════════════════════════════════════════════\n");

  const bridgeAddr = "0x12C3E3B84B75ca4a9388de696621ac5F2Ae36953";
  const vaultAddr = "0xb27092564b5434f68706753f9C0ADDC49Ca71dC5";
  const marketAddr = "0x7C969ea45cdA884902102212DDF14f2A33988208";
  const zeroAddr = "0x0000000000000000000000000000000000000000";

  // ─── Bridge state ──────────────────────────────
  console.log("🌉 CRUSTYSWAP BRIDGE");
  console.log(`  Address: ${bridgeAddr}`);
  const bridgeETH = await ethers.provider.getBalance(bridgeAddr);
  console.log(`  Native balance: ${ethers.formatEther(bridgeETH)} CAMP/ETH\n`);

  // ─── Try to get bridge ABI — check if it's a known contract ──
  const bridgeCode = await ethers.provider.getCode(bridgeAddr);
  console.log(`  Code size: ${bridgeCode.length / 2 - 1} bytes`);

  // Try common bridge interfaces
  // Check if it's a simple pool or actual bridge
  const bridgeABI = [
    "function token0() view returns (address)",
    "function token1() view returns (address)",
    "function getReserves() view returns (uint112, uint112, uint32)",
    "function factory() view returns (address)",
    "function balanceOf(address) view returns (uint256)",
  ];

  try {
    const bridge = await ethers.getContractAt(bridgeABI, bridgeAddr);
    const t0 = await bridge.token0();
    const t1 = await bridge.token1();
    console.log(`  Looks like a DEX pair (Uniswap v2 style):`);
    console.log(`    token0: ${t0}`);
    console.log(`    token1: ${t1}`);
    const reserves = await bridge.getReserves().catch(() => null);
    if (reserves) {
      console.log(`    Reserves: ${reserves[0]}, ${reserves[1]}`);
    }
  } catch (e) {
    console.log(`  Not a standard DEX pair: ${e.message.substring(0, 60)}`);
  }

  // ─── Check if bridge interacts with vault ──────
  // Look at recent transactions from/to bridge
  console.log(`\n📡 Checking bridge interaction with vulnerable contracts...`);

  // Check bridge's token holdings
  const tokensToCheck = [
    { addr: "0xC42BAA20e3a159cF7A8aDFA924648C2a2d59E062", name: "WETH", decimals: 18 },
    { addr: "0x1aE9c40eCd2DD6ad5858E5430A556d7aff28A44b", name: "wCAMP", decimals: 18 },
    { addr: "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537", name: "CP (0-dec)", decimals: 0 },
    { addr: "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF", name: "CP (18-dec)", decimals: 18 },
  ];

  for (const t of tokensToCheck) {
    try {
      const token = await ethers.getContractAt(
        ["function balanceOf(address) view returns (uint256)"],
        t.addr
      );
      const bridgeBal = await token.balanceOf(bridgeAddr);
      const vaultBal = await token.balanceOf(vaultAddr);
      console.log(`  ${t.name}:`);
      console.log(`    Bridge: ${ethers.formatUnits(bridgeBal, t.decimals)}`);
      console.log(`    Vault:  ${ethers.formatUnits(vaultBal, t.decimals)}`);
    } catch (e) {
      console.log(`  ${t.name}: ❌ (${e.message.substring(0, 40)})`);
    }
  }

  // ─── Check if vault can receive bridge funds ───
  console.log(`\n🔍 CRITICAL PATH ANALYSIS`);
  console.log(`  Bridge (${ethers.formatEther(bridgeETH)} ETH) → ??? → Vault`);

  // Check if there's a path where bridge funds end up in vault
  // The marketplace _distributeRoyalty() calls vault.updateVaultBalance()
  // If marketplace processes payments that come from bridge...

  // Check marketplace v2
  const marketV2Addr = "0x81BeB79b977cAd2B1d06aFC62b4aABB7611107b4";
  const m2Bal = await ethers.provider.getBalance(marketV2Addr);
  console.log(`  Marketplace v2 balance: ${ethers.formatEther(m2Bal)} ETH`);
  const m2Code = await ethers.provider.getCode(marketV2Addr);
  console.log(`  Marketplace v2 has code: ${m2Code.length > 3}`);

  // Check vault factory addresses
  const factory1 = "0xaed623AF25128f3FC39cA855441BC4d9Dbf1AaBB";
  const factory2 = "0x92c29a571CeAC162E9e644EB19B8546317FB2058";
  const f1Bal = await ethers.provider.getBalance(factory1);
  const f2Bal = await ethers.provider.getBalance(factory2);
  console.log(`  VaultFactory #1 balance: ${ethers.formatEther(f1Bal)} ETH`);
  console.log(`  VaultFactory #2 balance: ${ethers.formatEther(f2Bal)} ETH`);

  // Check if wCAMP (wrapped native token) can be swapped
  const wcampAddr = "0x1aE9c40eCd2DD6ad5858E5430A556d7aff28A44b";
  const wcampBridgeBal = await ethers.getContractAt(
    ["function balanceOf(address) view returns (uint256)"],
    wcampAddr
  ).then(c => c.balanceOf(bridgeAddr)).catch(() => null);
  const wcampVaultBal = await ethers.getContractAt(
    ["function balanceOf(address) view returns (uint256)"],
    wcampAddr
  ).then(c => c.balanceOf(vaultAddr)).catch(() => null);
  console.log(`\n  wCAMP Bridge balance: ${wcampBridgeBal ? ethers.formatEther(wcampBridgeBal) : 'unknown'}`);
  console.log(`  wCAMP Vault balance: ${wcampVaultBal ? ethers.formatEther(wcampVaultBal) : 'unknown'}`);

  console.log("\n═══════════════════════════════════════════════");
  console.log("  ANALYSIS COMPLETE");
  console.log("═══════════════════════════════════════════════\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
