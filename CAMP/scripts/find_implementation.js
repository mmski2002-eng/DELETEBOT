const { ethers } = require("hardhat");

/**
 * ════════════════════════════════════════════════════════
 *  Find CampPoint implementation — who can mint?
 * ════════════════════════════════════════════════════════
 *
 * Usage: npx hardhat run scripts/find_implementation.js --network campNetwork
 */

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("  🔬 CAMP POINT PROXY — FIND IMPLEMENTATION");
  console.log("═══════════════════════════════════════════════\n");

  const cp1Addr = "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537";
  const cp2Addr = "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF";

  // ─── Read full bytecode ──────────────────────────
  for (const [label, addr] of [["CP#1", cp1Addr], ["CP#2", cp2Addr]]) {
    console.log(`📀 ${label}: ${addr}`);
    const code = await ethers.provider.getCode(addr);

    // Print full bytecode
    const stripped = code.startsWith("0x") ? code.substring(2) : code;
    console.log(`  Full bytecode (${stripped.length / 2} bytes):`);
    
    // Format in 32-byte lines for analysis
    for (let i = 0; i < stripped.length; i += 64) {
      const line = stripped.substring(i, i + 64);
      const addr_offset = i / 2;
      console.log(`    [${addr_offset.toString().padStart(3, " ")}] ${line}`);
    }

    // ─── Check storage slots for implementation ──
    console.log(`\n  🔍 Checking storage for implementation address...`);
    
    // Standard ERC-1967 storage slot for implementation
    const implSlot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
    const implData = await ethers.provider.getStorage(addr, implSlot).catch(() => null);
    if (implData && implData !== "0x0000000000000000000000000000000000000000000000000000000000000000") {
      const implAddr = "0x" + implData.substring(26);
      console.log(`  ⚠️  ERC-1967 Implementation: ${implAddr}`);
      
      // Check implementation code
      const implCode = await ethers.provider.getCode(implAddr);
      console.log(`  Implementation code: ${(implCode.length - 2) / 2} bytes`);
      
      // Check if implementation has mint
      if (implCode.toLowerCase().includes("40c10f19")) {
        console.log(`  🚨 Has mint(address,uint256)!`);
      }
    } else {
      console.log(`  ❌ Not ERC-1967`);
    }

    // Check slot 0 (common for Vyper/EIP-1167)
    const slot0 = await ethers.provider.getStorage(addr, "0x0").catch(() => null);
    console.log(`  Storage[0]: ${slot0 || "N/A"}`);
    
    // Check slot 0x01 for openzeppelin proxy
    const slot1 = await ethers.provider.getStorage(addr, "0x1").catch(() => null);
    console.log(`  Storage[1]: ${slot1 || "N/A"}`);

    // Try to extract address embedded in bytecode
    // Look for 20-byte addresses pushed via PUSH20 (0x73)
    console.log(`\n  🔍 Extracting embedded addresses from bytecode...`);
    for (let i = 0; i < stripped.length - 40; i += 2) {
      if (stripped.substring(i, i + 4) === "73") {
        const addr = "0x" + stripped.substring(i + 4, i + 44);
        if (addr !== "0x0000000000000000000000000000000000000000" &&
            addr !== "0x0000000000000000000000000000000000000001") {
          console.log(`  Found PUSH20 at byte ${i/2}: ${addr}`);
        }
      }
    }
    console.log();
  }

  // ─── Try to call CampPoint with a known interface ──
  console.log(`${"═".repeat(55)}`);
  console.log("  🔎 ATTEMPTING TO CALL CampPoint FUNCTIONS");
  console.log(`${"═".repeat(55)}\n`);

  const cpABI = [
    "function name() view returns (string)",
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)",
    "function totalSupply() view returns (uint256)",
    "function balanceOf(address) view returns (uint256)",
    "function mint(address to, uint256 amount) external returns (bool)",
    "function owner() view returns (address)",
    "function renounceOwnership() external",
    "function transferOwnership(address newOwner) external",
  ];

  for (const [label, addr] of [["CP#1 (0-dec)", cp1Addr], ["CP#2 (18-dec)", cp2Addr]]) {
    console.log(`\n📀 ${label}`);
    const cp = await ethers.getContractAt(cpABI, addr);

    // Read basic info
    for (const fn of ["name", "symbol", "decimals", "totalSupply"]) {
      try {
        const val = await cp[fn]();
        console.log(`  ${fn}(): ${val.toString()}`);
      } catch (e) {
        console.log(`  ${fn}(): ❌ ${e.message.substring(0, 50)}`);
      }
    }

    // Try to read owner
    try {
      const owner = await cp.owner();
      console.log(`  owner(): ${owner}`);

      // Check if this is a known address
      const ownersToCheck = {
        "0x12C3E3B84B75ca4a9388de696621ac5F2Ae36953": "🚨 BRIDGE",
        "0x7C969ea45cdA884902102212DDF14f2A33988208": "Marketplace v1",
        "0x81BeB79b977cAd2B1d06aFC62b4aABB7611107b4": "Marketplace v2",
        "0xb27092564b5434f68706753f9C0ADDC49Ca71dC5": "Vault",
        "0xC4a35ce77b090cb511CEb5622D9A41f9A722e4E4": "IpNFT",
        "0x0000000000000000000000000000000000000000": "ZERO (renounced?)",
      };
      const known = ownersToCheck[owner.toLowerCase()] || "Unknown";
      console.log(`  Owner type: ${known}`);

    } catch (e) {
      console.log(`  owner(): ❌ ${e.message.substring(0, 50)}`);
    }

    // Check if current supply matches what's in storage
    const totalSupply = await cp.totalSupply();
    const vaultAddr = "0xb27092564b5434f68706753f9C0ADDC49Ca71dC5";
    const bridgeAddr = "0x12C3E3B84B75ca4a9388de696621ac5F2Ae36953";

    for (const [who, label] of [["0x0000000000000000000000000000000000000000", "Zero"], [vaultAddr, "Vault"], [bridgeAddr, "Bridge"]]) {
      try {
        const bal = await cp.balanceOf(who);
        if (bal > 0n) {
          console.log(`  balanceOf(${label}): ${bal.toString()}`);
        }
      } catch (e) { /* ignore */ }
    }
  }

  // ─── Check any recent CampPoint mint events ───────
  console.log(`\n${"═".repeat(55)}`);
  console.log("  🔎 RECENT MINT EVENTS (last 1000 blocks)");
  console.log(`${"═".repeat(55)}`);

  const currentBlock = await ethers.provider.getBlockNumber();
  const fromBlock = currentBlock - 1000;

  const transferTopic = ethers.id("Transfer(address,address,uint256)");
  const zeroAddr = "0x0000000000000000000000000000000000000000";

  for (const [label, addr] of [["CP#1", cp1Addr], ["CP#2", cp2Addr]]) {
    console.log(`\n  📀 ${label} Transfer events (mints = from: zero):`);
    try {
      const events = await ethers.provider.getLogs({
        address: addr,
        topic0: transferTopic,
        topic1: "0x0000000000000000000000000000000000000000000000000000000000000000",
        fromBlock,
        toBlock: "latest",
      });
      console.log(`    Found ${events.length} mint events in last 1000 blocks`);
      
      // Show last 5 mints
      const recent = events.slice(-5);
      for (const ev of recent) {
        const toAddr = "0x" + ev.topics[2].substring(26);
        const amount = BigInt(ev.data);
        console.log(`    Mint ${amount.toString()} → ${toAddr}`);
      }
    } catch (e) {
      console.log(`    ❌ ${e.message.substring(0, 60)}`);
    }
  }

  console.log("\n═══════════════════════════════════════════════");
  console.log("  ANALYSIS COMPLETE");
  console.log("═══════════════════════════════════════════════\n");
}

main().catch(e => { console.error(e); process.exit(1); });
