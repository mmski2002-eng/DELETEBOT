const { ethers } = require("hardhat");

/**
 * ════════════════════════════════════════════════════════
 *  Check if 0xd6DfAE7E62DD93Cc2CB525B7785983682b6802dc has MINTER role
 * ════════════════════════════════════════════════════════
 *
 * Usage: npx hardhat run scripts/check_minter_role.js --network campNetwork
 */

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("  🔐 MINTER ROLE CHECK");
  console.log("═══════════════════════════════════════════════\n");

  const targetAddress = "0xd6DfAE7E62DD93Cc2CB525B7785983682b6802dc";
  console.log(`  Target wallet: ${targetAddress}`);
  const targetBal = await ethers.provider.getBalance(targetAddress);
  console.log(`  ETH balance: ${ethers.formatEther(targetBal)} ETH\n`);

  const tokens = [
    { name: "CP#1 (0-dec)", proxy: "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537", impl: "0xac14d9896b0115a078bfb58a14f0fae85983daca" },
    { name: "CP#2 (18-dec)", proxy: "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF", impl: "0xb478c35e230e6b808f4dc2464f44e3e6dcc3c809" },
  ];

  // Standard OpenZeppelin roles
  const DEFAULT_ADMIN_ROLE = ethers.ZeroHash; // 0x00...00
  
  // Try multiple common role hashes
  const rolesToCheck = [
    { label: "DEFAULT_ADMIN_ROLE", role: DEFAULT_ADMIN_ROLE },
    { label: "MINTER_ROLE", role: ethers.id("MINTER_ROLE") },
    { label: "MINTER", role: ethers.id("MINTER") },
    { label: "minter", role: ethers.id("minter") },
  ];

  for (const token of tokens) {
    console.log(`📀 ${token.name}`);
    console.log(`  Proxy: ${token.proxy}`);
    console.log(`  Impl:  ${token.impl}`);

    // Try AccessControl interface
    const abi = [
      "function hasRole(bytes32 role, address account) view returns (bool)",
      "function getRoleAdmin(bytes32 role) view returns (bytes32)",
      "function getRoleMemberCount(bytes32 role) view returns (uint256)",
      "function getRoleMember(bytes32 role, uint256 index) view returns (address)",
      "function balanceOf(address) view returns (uint256)",
      "function decimals() view returns (uint8)",
    ];

    const cp = await ethers.getContractAt(abi, token.proxy);

    const dec = await cp.decimals().catch(() => 18);
    const targetBal = await cp.balanceOf(targetAddress).catch(() => 0n);
    console.log(`  Target CP balance: ${ethers.formatUnits(targetBal, dec)}`);

    // Check roles
    for (const role of rolesToCheck) {
      try {
        const hasIt = await cp.hasRole(role.role, targetAddress);
        console.log(`  ${role.label}: ${hasIt ? "✅ YES" : "❌ NO"}`);

        if (hasIt) {
          console.log(`    ⚠️  Wallet ${targetAddress.substring(0, 10)}... has ${role.label}!`);
        }
      } catch (e) {
        console.log(`  ${role.label}: ❌ ERROR — ${e.message.substring(0, 50)}`);
      }
    }

    // Check who has admin role
    console.log(`\n  🔍 Who has DEFAULT_ADMIN_ROLE?`);
    try {
      const adminCount = await cp.getRoleMemberCount(DEFAULT_ADMIN_ROLE);
      console.log(`  Admin count: ${adminCount}`);

      for (let i = 0; i < adminCount; i++) {
        const admin = await cp.getRoleMember(DEFAULT_ADMIN_ROLE, i);
        console.log(`  Admin #${i}: ${admin}`);
        if (admin.toLowerCase() === targetAddress.toLowerCase()) {
          console.log(`    ⚠️  TARGET IS ADMIN!`);
        }
      }
    } catch (e) {
      console.log(`  ❌ getRoleMember: ${e.message.substring(0, 50)}`);
    }

    // Check MINTER_ROLE holders
    const MINTER_ROLE = rolesToCheck[1].role;
    console.log(`\n  🔍 Who has MINTER_ROLE?`);
    try {
      const minterCount = await cp.getRoleMemberCount(MINTER_ROLE);
      console.log(`  Minter count: ${minterCount}`);

      for (let i = 0; i < minterCount; i++) {
        const minter = await cp.getRoleMember(MINTER_ROLE, i);
        console.log(`  Minter #${i}: ${minter}`);
        if (minter.toLowerCase() === targetAddress.toLowerCase()) {
          console.log(`    ⚠️  TARGET IS MINTER! ✅✅✅`);
        }
      }
    } catch (e) {
      console.log(`  ❌ getRoleMember: ${e.message.substring(0, 60)}`);
    }

    // Try to list ALL roles if possible (try different role hashes)
    console.log(`\n  🔍 Trying to enumerate all roles...`);
    // Try common OpenZeppelin role identifiers
    const extraRoles = [
      "BURNER_ROLE", "PAUSER_ROLE", "UPGRADER_ROLE", "OPERATOR_ROLE",
      "TOKEN_CREATOR_ROLE", "WHITELISTED_ROLE", "BLACKLISTED_ROLE",
      "ADMIN_ROLE", "CONTROLLER_ROLE", "GOVERNANCE_ROLE",
    ];

    for (const roleName of extraRoles) {
      const roleHash = ethers.id(roleName);
      try {
        const count = await cp.getRoleMemberCount(roleHash);
        if (count > 0n) {
          console.log(`  ${roleName}: ${count} members`);
          for (let i = 0; i < count; i++) {
            const member = await cp.getRoleMember(roleHash, i);
            const isTarget = member.toLowerCase() === targetAddress.toLowerCase();
            console.log(`    #${i}: ${member}${isTarget ? " ⚠️ TARGET" : ""}`);
          }
        }
      } catch (e) {
        // skip
      }
    }

    console.log();
  }

  // ─── Extra: check if target is the owner/admin of other contracts ──
  console.log(`${"═".repeat(55)}`);
  console.log("  🔎 ADDITIONAL: Target's role in other contracts");
  console.log(`${"═".repeat(55)}\n`);

  const otherContracts = [
    { name: "Vault", addr: "0xb27092564b5434f68706753f9C0ADDC49Ca71dC5" },
    { name: "Marketplace v1", addr: "0x7C969ea45cdA884902102212DDF14f2A33988208" },
    { name: "Marketplace v2", addr: "0x81BeB79b977cAd2B1d06aFC62b4aABB7611107b4" },
    { name: "Bridge", addr: "0x12C3E3B84B75ca4a9388de696621ac5F2Ae36953" },
  ];

  const ownerABI = ["function owner() view returns (address)"];

  for (const c of otherContracts) {
    try {
      const contract = await ethers.getContractAt(ownerABI, c.addr);
      const owner = await contract.owner();
      const isTarget = owner.toLowerCase() === targetAddress.toLowerCase();
      console.log(`  ${c.name}: owner = ${owner}${isTarget ? " ⚠️ TARGET IS OWNER!" : ""}`);
    } catch (e) {
      console.log(`  ${c.name}: ❌ no owner() ${e.message.substring(0, 30)}`);
    }
  }

  console.log("\n═══════════════════════════════════════════════\n");
}

main().catch(e => { console.error(e); process.exit(1); });
