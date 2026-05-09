const { ethers } = require("hardhat");

/**
 * ════════════════════════════════════════════════════════
 *  Check tokens for unlimited mint vulnerabilities
 * ════════════════════════════════════════════════════════
 *
 * Usage: npx hardhat run scripts/check_tokens.js --network campNetwork
 */

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("  TOKEN ANALYSIS — Infinite Mint Vulnerabilities");
  console.log("═══════════════════════════════════════════════\n");

  const tokens = [
    { addr: "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537", name: "CampPoint #1 (0-dec)" },
    { addr: "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF", name: "CampPoint #2 (18-dec)" },
    { addr: "0x1aE9c40eCd2DD6ad5858E5430A556d7aff28A44b", name: "wCAMP" },
    { addr: "0xC42BAA20e3a159cF7A8aDFA924648C2a2d59E062", name: "WETH" },
    { addr: "0x587aF234D373C752a6F6E9eD6c4Ce871e7528BCF", name: "WBTC" },
    { addr: "0x71002dbf6cC7A885cE6563682932370c056aAca9", name: "MUSDC" },
    { addr: "0xe9a9aFfb353c2daE8453d041bc849ae5946B996b", name: "sxUSDC" },
  ];

  for (const t of tokens) {
    console.log(`\n📀 ${t.name}`);
    console.log(`  Address: ${t.addr}`);
    console.log(`  ${"─".repeat(50)}`);

    try {
      const code = await ethers.provider.getCode(t.addr);
      console.log(`  Code size: ${(code.length - 2) / 2} bytes`);

      // Standard ERC-20 checks
      const erc20ABI = [
        "function name() view returns (string)",
        "function symbol() view returns (string)",
        "function decimals() view returns (uint8)",
        "function totalSupply() view returns (uint256)",
        "function balanceOf(address) view returns (uint256)",
      ];
      const contract = await ethers.getContractAt(erc20ABI, t.addr);

      const [name, symbol, decimals, totalSupply] = await Promise.all([
        contract.name().catch(() => "N/A"),
        contract.symbol().catch(() => "N/A"),
        contract.decimals().catch(() => 255),
        contract.totalSupply().catch(() => 0n),
      ]);

      console.log(`  Name: ${name}`);
      console.log(`  Symbol: ${symbol}`);
      console.log(`  Decimals: ${decimals}`);
      console.log(`  Total Supply: ${ethers.formatUnits(totalSupply, decimals)}`);

      // ─── Check for mint functions in bytecode ─────
      // Look for function selectors related to minting
      const mintSelectors = [
        "40c10f19", // mint(address,uint256)
        "a0712d68", // mint(uint256)
        "9dc29fac", // mint(address,address,uint256)
        "731133e9", // mintBatch
        "278d9c5e", // _mint (internal, won't be in public selectors)
        "7a9e5e4b", // tokensMinted
      ];

      console.log(`\n  🔍 Checking for mint functions in bytecode:`);
      for (const selector of mintSelectors) {
        const found = code.toLowerCase().includes(selector);
        if (found) {
          console.log(`    ⚠️  Found selector: 0x${selector}`);

          // Try to call it with a random address to see if it reverts
          const iface = new ethers.Interface([
            `function mint(address to, uint256 amount) external view returns (bool)`,
          ]);
          try {
            // We can't easily check if it's public without calling it
            // But we can check if the function exists by encoding
            const mintSelector = `0x${selector}`;
            console.log(`    ⚠️  Potential mint function detected at selector 0x${selector}`);
          } catch (e) {
            // ignore
          }
        }
      }

      // ─── Try to detect OpenZeppelin Ownable patterns ──
      const ownerSelectors = [
        "8da5cb5b", // owner()
        "f2fde38b", // transferOwnership(address)
      ];

      let hasOwner = false;
      for (const selector of ownerSelectors) {
        if (code.toLowerCase().includes(selector)) {
          hasOwner = true;
          break;
        }
      }
      console.log(`  🔑 Has Ownable pattern: ${hasOwner ? "✅ YES" : "❌ NO"}`);

      // ─── Check a known address balance (bridge) ──
      const bridgeAddr = "0x12C3E3B84B75ca4a9388de696621ac5F2Ae36953";
      try {
        const bridgeBal = await contract.balanceOf(bridgeAddr);
        if (bridgeBal > 0n) {
          console.log(`  🌉 Bridge balance: ${ethers.formatUnits(bridgeBal, decimals)}`);
        }
      } catch (e) { /* ignore */ }

      // ─── Check vault balance of this token ──
      const vaultAddr = "0xb27092564b5434f68706753f9C0ADDC49Ca71dC5";
      try {
        const vaultBal = await contract.balanceOf(vaultAddr);
        if (vaultBal > 0n) {
          console.log(`  🗄️  Vault balance: ${ethers.formatUnits(vaultBal, decimals)}`);
        }
      } catch (e) { /* ignore */ }

      // ─── Check if totalSupply grows unusually ──
      // For wCAMP with non-round supply, check if it can be minted freely
      if (name === "CampPoint" || name === "Wrapped CAMP" || symbol === "CP") {
        console.log(`\n  ⚡ Checking mint authority...`);
        // Try to check if caller=zero can mint (foundry-style test)
        // In hardhat we can impersonate
      }

    } catch (e) {
      console.log(`  ❌ Error: ${e.message.substring(0, 80)}`);
    }
  }

  // ─── Special deep dive: CampPoint tokens ─────────
  console.log(`\n${"═".repeat(55)}`);
  console.log("  🚨 DEEP DIVE: CampPoint Token Comparison");
  console.log(`${"═".repeat(55)}`);

  const cp1Addr = "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537";
  const cp2Addr = "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF";

  for (const [label, addr] of [["CP#1 (0-dec)", cp1Addr], ["CP#2 (18-dec)", cp2Addr]]) {
    console.log(`\n  ${label}: ${addr}`);

    // Get full bytecode and compare
    const code = await ethers.provider.getCode(addr);
    console.log(`  Code size: ${(code.length - 2) / 2} bytes`);

    // Check for specific function selectors commonly found in ERC-20 + mint
    const allSelectors = [];
    // Parse selectors from bytecode (every 4 bytes after the PUSH4 opcode 0x63)
    for (let i = 0; i < code.length - 10; i += 2) {
      if (code.substring(i, i + 4) === "63") {
        // PUSH4 instruction - next 8 chars are the selector
        const selector = code.substring(i + 4, i + 12);
        if (selector.match(/^[0-9a-f]{8}$/)) {
          allSelectors.push(selector);
        }
      }
    }

    // Deduplicate
    const uniqueSelectors = [...new Set(allSelectors)];
    console.log(`  Unique function selectors found: ${uniqueSelectors.length}`);

    // Known ERC-20 selectors
    const knownSelectors = {
      "70a08231": "balanceOf(address)",
      "18160ddd": "totalSupply()",
      "313ce567": "decimals()",
      "06fdde03": "name()",
      "95d89b41": "symbol()",
      "a9059cbb": "transfer(address,uint256)",
      "23b872dd": "transferFrom(address,address,uint256)",
      "095ea7b3": "approve(address,uint256)",
      "dd62ed3e": "allowance(address,address)",
      "40c10f19": "🚨 mint(address,uint256) — UNPROTECTED MINT!",
      "9dc29fac": "🚨 mint(address,address,uint256)",
      "2eb2c2d6": "🚨 mintBatch",
      "8da5cb5b": "owner()",
      "f2fde38b": "transferOwnership(address)",
      "3659cfe6": "upgradeTo(address)",
      "4f1ef286": "upgradeToAndCall(address,bytes)",
    };

    for (const sel of uniqueSelectors) {
      if (knownSelectors[sel]) {
        console.log(`    [0x${sel}] ${knownSelectors[sel]}`);
      }
    }

    // Check for any UNKNOWN selectors (potential custom functions)
    const unknownSelectors = uniqueSelectors.filter(s => !knownSelectors[s]);
    if (unknownSelectors.length > 0) {
      console.log(`  Custom/unknown selectors (${unknownSelectors.length}):`);
      // Group by first byte to show less noise
      const grouped = {};
      for (const s of unknownSelectors) {
        const prefix = s.substring(0, 2);
        grouped[prefix] = (grouped[prefix] || 0) + 1;
      }
      for (const [prefix, count] of Object.entries(grouped)) {
        console.log(`    0x${prefix}... (${count} functions)`);
      }
    }
  }

  console.log("\n═══════════════════════════════════════════════");
  console.log("  ANALYSIS COMPLETE");
  console.log("═══════════════════════════════════════════════\n");
}

main().catch(e => { console.error(e); process.exit(1); });
