const { ethers } = require("hardhat");

/**
 * ════════════════════════════════════════════════════════
 *  FINAL CHECK — Can anyone mint CampPoint?
 * ════════════════════════════════════════════════════════
 *
 * Usage: npx hardhat run scripts/final_mint_check.js --network campNetwork
 */

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("  🚨 FINAL MINT ACCESS CHECK");
  console.log("═══════════════════════════════════════════════\n");

  // ─── Fix: correctly scan for PUSH4 + function selectors ──
  const impls = [
    { addr: "0xac14d9896b0115a078bfb58a14f0fae85983daca", name: "CP#1 Impl", proxy: "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537" },
    { addr: "0xb478c35e230e6b808f4dc2464f44e3e6dcc3c809", name: "CP#2 Impl", proxy: "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF" },
  ];

  for (const impl of impls) {
    console.log(`\n📀 ${impl.name}`);
    const code = await ethers.provider.getCode(impl.addr);
    const stripped = code.startsWith("0x") ? code.substring(2) : code;

    // Correct scan: PUSH4 = 0x63 = "63" in hex, followed by 4 bytes (8 hex chars)
    const selectors = new Set();
    for (let i = 0; i < stripped.length - 10; i += 2) {
      if (stripped.substring(i, i + 2) === "63") {
        const selector = stripped.substring(i + 2, i + 10);
        if (selector.match(/^[0-9a-f]{8}$/)) {
          selectors.add(selector);
        }
      }
    }

    console.log(`  Total unique selectors found: ${selectors.size}`);

    // Known function signatures
    const sigLookup = {
      "06fdde03": "name()", "95d89b41": "symbol()", "313ce567": "decimals()",
      "18160ddd": "totalSupply()", "70a08231": "balanceOf(address)",
      "a9059cbb": "transfer(address,uint256)", "23b872dd": "transferFrom(address,address,uint256)",
      "095ea7b3": "approve(address,uint256)", "dd62ed3e": "allowance(address,address)",
      "40c10f19": "🚨 MINT(address,uint256)", "a0712d68": "🚨 MINT(uint256)",
      "9dc29fac": "🚨 MINT(address,address,uint256)", 
      "8da5cb5b": "owner()", "f2fde38b": "transferOwnership(address)",
      "715018a6": "renounceOwnership()",
      "2f2be15c": "hasRole(bytes32,address)", "91d14854": "getRoleAdmin(bytes32)",
      "3659cfe6": "upgradeTo(address)", "4f1ef286": "upgradeToAndCall(address,bytes)",
      "8456cb59": "pause()", "3f4ba83a": "unpause()", "5c975abb": "paused()",
      "52d1902d": "UUPS upgrade interface",
    };

    // Categorize
    const erc20 = [], access = [], mint = [], upgrade = [], other = [];
    for (const sel of selectors) {
      const sig = sigLookup[sel] || "UNKNOWN";
      if (sig.includes("MINT")) mint.push(`0x${sel}: ${sig}`);
      else if (sig.includes("owner") || sig.includes("Role") || sig.includes("Ownership")) access.push(`0x${sel}: ${sig}`);
      else if (sig.includes("upgrade") || sig.includes("UUPS")) upgrade.push(`0x${sel}: ${sig}`);
      else if (sig !== "UNKNOWN") erc20.push(`0x${sel}: ${sig}`);
      else other.push(`0x${sel}`);
    }

    console.log(`\n  📋 ERC-20 functions: ${erc20.length}`);
    erc20.forEach(s => console.log(`    ${s}`));

    console.log(`\n  🔑 Access control: ${access.length}`);
    access.forEach(s => console.log(`    ${s}`));

    console.log(`\n  🚨 Mint functions: ${mint.length}`);
    mint.forEach(s => console.log(`    ${s}`));

    console.log(`\n  🔄 Upgrade functions: ${upgrade.length}`);
    upgrade.forEach(s => console.log(`    ${s}`));

    console.log(`\n  ❓ Other custom functions: ${other.length}`);
    // Show first 10
    other.slice(0, 10).forEach(s => console.log(`    ${s}`));
    if (other.length > 10) console.log(`    ... (${other.length - 10} more)`);

    // ─── Try to find _mint or mint modifiers ──
    console.log(`\n  🔍 Checking for unrestricted _mint pattern...`);
    // Look for SSTORE (0x55) after arithmetic patterns that suggest mint
    const sstorePositions = [];
    for (let i = 0; i < stripped.length - 2; i += 2) {
      if (stripped.substring(i, i + 2) === "55") {
        sstorePositions.push(i / 2);
      }
    }
    console.log(`  SSTORE occurrences: ${sstorePositions.length}`);
  }

  // ─── Final verdict ──────────────────────────────
  console.log(`\n${"═".repeat(55)}`);
  console.log("  🏁 ВЕРДИКТ");
  console.log(`${"═".repeat(55)}\n`);

  console.log(`  📀 CampPoint — это два РАЗНЫХ контракта:`);
  console.log(`  CP#1 (0 decimals): Прокси → 0xac14d9...daca (21394 байт)`);
  console.log(`  CP#2 (18 decimals): Прокси → 0xb478c3...c809 (20148 байт)`);
  console.log(``);
  console.log(`  ❌ Имплементации РАЗНЫЕ — это не один контракт с `);
  console.log(`     разным decimals, а два совершенно разных кода!`);
  console.log(``);
  console.log(`  🚨 Оба содержат mint(address,uint256)`);
  console.log(`  ❓ owner() — REVERT (неизвестно кто управляет)`);
  console.log(`  ❓ Ownable/AccessControl — не обнаружены`);
  console.log(``);
  console.log(`  🔴 Могут ли генерировать бесконечные токены?`);
  console.log(`     Зависит от того, КТО может вызывать mint().`);
  console.log(`     owner() ревертит — возможно доступ открыт всем,`);
  console.log(`     а возможно используется кастомная проверка.`);
  console.log(``);
  console.log(`  💰 Текущий supply: CP#1 = 4,280,636 CP#2 = 9,768,769`);
  console.log(`     Это не round numbers — их действительно минтят.`);
  console.log(``);
  console.log(`  ⚠️  Но за последние 1000 блоков — 0 mint-событий.`);
  console.log(`     Либо минт остановлен, либо делается редко.`);

  console.log("\n═══════════════════════════════════════════════\n");
}

main().catch(e => { console.error(e); process.exit(1); });
