const { ethers } = require("hardhat");

/**
 * ════════════════════════════════════════════════════════
 *  Who can call mint() on CampPoint implementations?
 * ════════════════════════════════════════════════════════
 *
 * Usage: npx hardhat run scripts/check_mint_access.js --network campNetwork
 */

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("  🔐 WHO CAN MINT? — CampPoint Access Control");
  console.log("═══════════════════════════════════════════════\n");

  const implementations = [
    { addr: "0xac14d9896b0115a078bfb58a14f0fae85983daca", name: "CP#1 Impl (0-dec proxy)", proxy: "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537" },
    { addr: "0xb478c35e230e6b808f4dc2464f44e3e6dcc3c809", name: "CP#2 Impl (18-dec proxy)", proxy: "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF" },
  ];

  for (const impl of implementations) {
    console.log(`📀 ${impl.name}`);
    console.log(`  Implementation: ${impl.addr}`);
    console.log(`  Proxy:          ${impl.proxy}`);
    console.log(`  ${"─".repeat(50)}`);

    const code = await ethers.provider.getCode(impl.addr);
    console.log(`  Code size: ${(code.length - 2) / 2} bytes`);

    // ─── Check for Access Control selectors ──
    const selectors = {
      "8da5cb5b": "owner()",
      "f2fde38b": "transferOwnership(address)",
      "715018a6": "renounceOwnership()",
      "2f2be15c": "hasRole(bytes32,address)",
      "91d14854": "getRoleAdmin(bytes32)",
      "a217fddf": "getRoleMemberCount(bytes32)",
      "ca15c873": "getRoleMember(bytes32,uint256)",
      "248a9ca3": "DEFAULT_ADMIN_ROLE()",
      "8456cb59": "pause()",
      "3f4ba83a": "unpause()",
      "5c975abb": "paused()",
      "40c10f19": "🚨 mint(address,uint256)",
      "9dc29fac": "🚨 mint(address,address,uint256)",
      "2eb2c2d6": "🚨 mintBatch",
      "3659cfe6": "🚨 upgradeTo(address)",
      "4f1ef286": "🚨 upgradeToAndCall(address,bytes)",
    };

    console.log(`\n  🔍 Function selectors in implementation:`);
    const foundSelectors = [];

    for (let i = 0; i < code.length - 10; i += 2) {
      if (code.substring(i, i + 4) === "63") {
        const selector = code.substring(i + 4, i + 12);
        if (selector.match(/^[0-9a-f]{8}$/)) {
          foundSelectors.push(selector);
        }
      }
    }

    const uniqueSelectors = [...new Set(foundSelectors)];
    for (const sel of uniqueSelectors) {
      if (selectors[sel]) {
        console.log(`    [0x${sel}] ${selectors[sel]}`);
      }
    }

    // ─── Check for anything related to ownership ──
    const hasOwner = uniqueSelectors.some(s => 
      ["8da5cb5b", "f2fde38b", "715018a6"].includes(s)
    );

    const hasRole = uniqueSelectors.some(s =>
      ["2f2be15c", "91d14854", "a217fddf", "ca15c873", "248a9ca3"].includes(s)
    );

    console.log(`\n  🔑 Access Control Analysis:`);
    console.log(`    Ownable (owner/transferOwnership): ${hasOwner ? "✅ YES" : "❌ NO"}`);
    console.log(`    AccessControl (hasRole/grantRole): ${hasRole ? "✅ YES" : "❌ NO"}`);

    if (!hasOwner && !hasRole) {
      console.log(`    🚨 NO ACCESS CONTROL DETECTED! mint() might be public!`);
    }

    // ─── Try to call owner() through proxy ──
    console.log(`\n  📞 Trying to call through proxy...`);
    const proxyABI = [
      "function owner() view returns (address)",
      "function mint(address to, uint256 amount) external returns (bool)",
      "function DEFAULT_ADMIN_ROLE() view returns (bytes32)",
    ];

    const proxy = await ethers.getContractAt(proxyABI, impl.proxy);

    // Try owner
    try {
      const owner = await proxy.owner();
      console.log(`    owner(): ${owner}`);
    } catch (e) {
      console.log(`    owner(): ❌ REVERTED — ${e.message.substring(0, 50)}`);
    }

    // Try DEFAULT_ADMIN_ROLE
    try {
      const adminRole = await proxy.DEFAULT_ADMIN_ROLE();
      console.log(`    DEFAULT_ADMIN_ROLE(): ${adminRole}`);

      // Check if deployer has admin role
      const [signer] = await ethers.getSigners();
      const hasRole = await proxy["hasRole(bytes32,address)"](adminRole, signer.address);
      console.log(`    Deployer has admin role: ${hasRole}`);
    } catch (e) {
      console.log(`    DEFAULT_ADMIN_ROLE(): ❌ REVERTED`);
    }

    console.log();
  }

  // ─── Compare the two implementations ────────────
  console.log(`${"═".repeat(55)}`);
  console.log("  🔎 IMPLEMENTATION COMPARISON");
  console.log(`${"═".repeat(55)}\n`);

  const cp1Code = await ethers.provider.getCode("0xac14d9896b0115a078bfb58a14f0fae85983daca");
  const cp2Code = await ethers.provider.getCode("0xb478c35e230e6b808f4dc2464f44e3e6dcc3c809");

  console.log(`  CP#1 Impl: ${(cp1Code.length - 2) / 2} bytes`);
  console.log(`  CP#2 Impl: ${(cp2Code.length - 2) / 2} bytes`);

  if (cp1Code === cp2Code) {
    console.log(`  ✅ Implementations are IDENTICAL`);
  } else {
    console.log(`  ❌ Implementations are DIFFERENT`);
    console.log(`  CP#1 starts: ${cp1Code.substring(0, 64)}...`);
    console.log(`  CP#2 starts: ${cp2Code.substring(0, 64)}...`);

    // Check last 64 bytes (metadata)
    console.log(`  CP#1 ends: ${cp1Code.substring(cp1Code.length - 64)}`);
    console.log(`  CP#2 ends: ${cp2Code.substring(cp2Code.length - 64)}`);
  }

  // ─── Check who has admin access ────────────────
  console.log(`\n${"═".repeat(55)}`);
  console.log("  🔎 WHO CAN UPGRADE THE PROXIES?");
  console.log(`${"═".repeat(55)}\n`);

  const upgradeSlot = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";

  for (const [label, proxyAddr] of [["CP#1", "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537"], 
                                      ["CP#2", "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF"]]) {
    const admin = await ethers.provider.getStorage(proxyAddr, upgradeSlot).catch(() => null);
    if (admin && admin !== "0x0000000000000000000000000000000000000000000000000000000000000000") {
      const adminAddr = "0x" + admin.substring(26);
      console.log(`  ${label} proxy admin: ${adminAddr}`);

      // Check admin's balance
      const bal = await ethers.provider.getBalance(adminAddr);
      console.log(`    Admin ETH balance: ${ethers.formatEther(bal)} ETH`);

      // Check admin's CampPoint holdings
      const proxy = await ethers.getContractAt(
        ["function balanceOf(address) view returns (uint256)", "function decimals() view returns (uint8)"],
        proxyAddr
      );
      const dec = await proxy.decimals().catch(() => 18);
      const adminBal = await proxy.balanceOf(adminAddr);
      console.log(`    Admin CP balance: ${ethers.formatUnits(adminBal, dec)}`);
    } else {
      console.log(`  ${label} proxy admin: ZERO (not upgradeable or renounced)`);
    }
  }

  console.log("\n═══════════════════════════════════════════════");
  console.log("  ANALYSIS COMPLETE");
  console.log("═══════════════════════════════════════════════\n");
}

main().catch(e => { console.error(e); process.exit(1); });
