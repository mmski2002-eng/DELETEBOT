const { ethers } = require("hardhat");

/**
 * ════════════════════════════════════════════════════════
 *  Try to call mint() directly — is it public?
 * ════════════════════════════════════════════════════════
 *
 * Usage: npx hardhat run scripts/try_mint.js --network campNetwork
 */

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("  🚀 TRY TO MINT — is mint() public?");
  console.log("═══════════════════════════════════════════════\n");

  const deployerAddr = "0xd6DfAE7E62DD93Cc2CB525B7785983682b6802dc"; // target wallet
  const targetAddress = deployerAddr;

  console.log(`  Deployer (target): ${deployerAddr}`);
  console.log(`  Target:           ${targetAddress}\n`);

  const tokens = [
    { name: "CP#1 (0-dec)", proxy: "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537" },
    { name: "CP#2 (18-dec)", proxy: "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF" },
  ];

  for (const token of tokens) {
    console.log(`📀 ${token.name}`);

    const cp = await ethers.getContractAt(
      [
        "function mint(address to, uint256 amount) external",
        "function mint(address to, address from, uint256 amount) external",
        "function totalSupply() view returns (uint256)",
        "function balanceOf(address) view returns (uint256)",
        "function decimals() view returns (uint8)",
      ],
      token.proxy
    );

    const totalSupplyBefore = await cp.totalSupply();
    const dec = await cp.decimals().catch(() => 18);
    console.log(`  Total supply before: ${ethers.formatUnits(totalSupplyBefore, dec)}`);

    // Check mint access via static call (no tx sending)
    console.log(`\n  📞 Static-checking mint(address,uint256) access...`);
    try {
      // Encode a mint call via raw ABI (avoid ambiguity)
      const mintSelector = "0x40c10f19"; // mint(address,uint256)
      const mintData = mintSelector + targetAddress.substring(2).toLowerCase().padStart(64, "0") + 100n.toString(16).padStart(64, "0");
      const result = await ethers.provider.call({
        to: token.proxy,
        from: targetAddress,
        data: mintData,
        gasLimit: 500000,
      });
      console.log(`  ✅ MINT DID NOT REVERT! Anyone can call mint()`);
      console.log(`  🚨 PUBLIC MINT DETECTED!`);
    } catch (e) {
      const msg = e.message;
      if (msg.includes("revert") || msg.includes("execution reverted")) {
        console.log(`  ❌ Mint reverted — protected (requires role)`);
        // Try to extract revert reason
        const dataMatch = msg.match(/data="([^"]+)"/);
        if (dataMatch) {
          try {
            const reason = ethers.toUtf8String("0x" + dataMatch[1].substring(138));
            console.log(`  Revert reason: ${reason.replace(/\u0000/g, "")}`);
          } catch (e2) { /* ignore */ }
        }
      } else {
        console.log(`  ⚠️  ${msg.substring(0, 100)}`);
      }
    }

    // Check mint(address,address,uint256)
    console.log(`\n  📞 Static-checking mint(address,address,uint256)...`);
    try {
      // Encode mint(address,address,uint256) raw
    const mintSelector2 = "0x9dc29fac";
    const mintData2 = mintSelector2 + targetAddress.substring(2).toLowerCase().padStart(64, "0") + targetAddress.substring(2).toLowerCase().padStart(64, "0") + 200n.toString(16).padStart(64, "0");
      const result2 = await ethers.provider.call({
        to: token.proxy,
        from: targetAddress,
        data: mintData2,
        gasLimit: 500000,
      });
      console.log(`  ✅ MINT(3args) DID NOT REVERT! Anyone can call!`);
    } catch (e) {
      if (e.message.includes("revert")) {
        console.log(`  ❌ Mint(3args) reverted — protected`);
      } else {
        console.log(`  ⚠️  ${e.message.substring(0, 60)}`);
      }
    }

    console.log();
  }

  // ─── Let's also try to figure out the actual role system ──
  console.log(`${"═".repeat(55)}`);
  console.log("  🔍 TRY DIFFERENT ROLE NAMES");
  console.log(`${"═".repeat(55)}\n`);

  const targetWallet = "0xd6DfAE7E62DD93Cc2CB525B7785983682b6802dc";

  // Generate keccak256 for various role names
  const roleNames = [
    "ADMIN_ROLE", "admin", "Admin", "ADMIN",
    "MINTER_ROLE", "MinterRole", "minter_role",
    "mint", "Mint", "MINT",
    "CONTROLLER", "controller", "Controller",
    "GOVERNOR", "governor", "Governor",
    "MANAGER", "manager", "Manager",
    "CREATOR", "creator", "Creator",
    "OWNER", "owner", "Owner",
    "OPERATOR", "operator", "Operator",
  ];

  for (const token of tokens) {
    console.log(`  📀 ${token.name}`);
    const cp = await ethers.getContractAt(
      ["function hasRole(bytes32, address) view returns (bool)"],
      token.proxy
    );

    let anyRole = false;
    for (const name of roleNames) {
      const roleHash = ethers.id(name);
      try {
        const hasIt = await cp.hasRole(roleHash, targetWallet);
        if (hasIt) {
          console.log(`    ✅ ${name} (${roleHash.substring(0, 10)}...) = HAS ROLE!`);
          anyRole = true;
        }
      } catch (e) { /* skip */ }
    }
    if (!anyRole) {
      console.log(`    ❌ No matching role found for target wallet`);
    }
  }

  console.log("\n═══════════════════════════════════════════════\n");
}

main().catch(e => { console.error(e); process.exit(1); });
