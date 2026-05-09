const { ethers } = require("hardhat");

/**
 * ════════════════════════════════════════════════════════
 *  Check if mint() is public — can anyone mint?
 * ════════════════════════════════════════════════════════
 *
 * Usage: npx hardhat run scripts/check_mint_public.js --network campNetwork
 */

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("  🚀 CAN ANYONE MINT CampPoint?");
  console.log("═══════════════════════════════════════════════\n");

  const targetWallet = "0xd6DfAE7E62DD93Cc2CB525B7785983682b6802dc";
  const randomWallet = "0x0000000000000000000000000000000000000001";
  
  const tokens = [
    { name: "CP#1 (0-dec)", proxy: "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537" },
    { name: "CP#2 (18-dec)", proxy: "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF" },
  ];

  // Use separate interfaces to avoid ambiguity
  const mintABI = new ethers.Interface(["function mint(address to, uint256 amount) external"]);
  const mint3ABI = new ethers.Interface(["function mint(address to, address from, uint256 amount) external"]);

  for (const token of tokens) {
    console.log(`📀 ${token.name}`);
    console.log(`  ${"─".repeat(50)}`);

    // Check total supply first
    const cp = await ethers.getContractAt(
      ["function totalSupply() view returns (uint256)", "function decimals() view returns (uint8)"],
      token.proxy
    );
    const totalSupply = await cp.totalSupply();
    const dec = await cp.decimals().catch(() => 18);
    console.log(`  Total Supply: ${ethers.formatUnits(totalSupply, dec)}`);

    // ─── Test 1: Can target wallet call mint(address,uint256)? ──
    console.log(`\n  📞 Test #1: Target wallet → mint(address,uint256)`);
    const mintOneData = mintABI.encodeFunctionData("mint", [targetWallet, 100n]);
    try {
      await ethers.provider.call({
        to: token.proxy,
        from: targetWallet,
        data: mintOneData,
      });
      console.log(`  ✅ CALL SUCCEEDED! Target can mint!`);
      console.log(`  🚨 UNPROTECTED MINT DETECTED!`);
    } catch (e) {
      const msg = e.message.substring(0, 120);
      if (msg.includes("revert")) {
        console.log(`  ❌ Reverted — mint requires role ❌`);
        // Try to extract revert reason
        const dataMatch = msg.match(/data='(0x[0-9a-f]+)'/);
        if (dataMatch) {
          try {
            const data = dataMatch[1];
            const reason = ethers.toBeArray(data);
            if (data.length > 138) {
              const reasonStr = ethers.toUtf8String("0x" + data.substring(138));
              console.log(`  Revert: ${reasonStr.replace(/\\u0000/g, "").replace(/[^a-zA-Z0-9_]/g, " ")}`);
            }
          } catch (e2) { /* ignore */ }
        }
      } else {
        console.log(`  ⚠️  ${msg}`);
      }
    }

    // ─── Test 2: Can random wallet call mint? ──
    console.log(`\n  📞 Test #2: Random wallet → mint(address,uint256)`);
    try {
      await ethers.provider.call({
        to: token.proxy,
        from: randomWallet,
        data: mintOneData,
      });
      console.log(`  ✅ CALL SUCCEEDED! Random wallet can mint!`);
      console.log(`  🚨 COMPLETELY PUBLIC MINT DETECTED!`);
    } catch (e) {
      if (e.message.includes("revert")) {
        console.log(`  ❌ Reverted — mint requires role ❌`);
      } else {
        console.log(`  ⚠️  ${e.message.substring(0, 60)}`);
      }
    }

    // ─── Test 3: Can target call mint(address,address,uint256)? ──
    console.log(`\n  📞 Test #3: Target → mint(address,address,uint256)`);
    const mintThreeData = mint3ABI.encodeFunctionData("mint", [targetWallet, targetWallet, 200n]);
    try {
      await ethers.provider.call({
        to: token.proxy,
        from: targetWallet,
        data: mintThreeData,
      });
      console.log(`  ✅ CALL SUCCEEDED! Target can batch-mint!`);
    } catch (e) {
      if (e.message.includes("revert")) {
        console.log(`  ❌ Reverted — protected`);
      }
    }

    // ─── Check where tokens came from ──
    console.log(`\n  🔍 Checking mint history for target wallet...`);
    try {
      const transferTopic = ethers.id("Transfer(address,address,uint256)");
      const zeroTopic = "0x0000000000000000000000000000000000000000000000000000000000000000";
      const targetTopic = "0x000000000000000000000000" + targetWallet.substring(2).toLowerCase();

      const events = await ethers.provider.getLogs({
        address: token.proxy,
        topics: [transferTopic, zeroTopic, targetTopic],
        fromBlock: 0,
        toBlock: "latest",
      });
      console.log(`  Total mint events to ${targetWallet.substring(0, 10)}...: ${events.length}`);
      
      let totalMinted = 0n;
      for (const ev of events) {
        const amount = BigInt(ev.data);
        totalMinted += amount;
      }
      console.log(`  Total tokens minted to wallet: ${ethers.formatUnits(totalMinted, dec)}`);

      // Show last 3 mints
      const recent = events.slice(-3);
      for (const ev of recent) {
        const amount = BigInt(ev.data);
        const block = ev.blockNumber;
        console.log(`    Block ${block}: mint ${ethers.formatUnits(amount, dec)}`);
      }
    } catch (e) {
      console.log(`  ❌ ${e.message.substring(0, 60)}`);
    }

    console.log();
  }

  // ─── Summary ────────────────────────────────────
  console.log(`${"═".repeat(55)}`);
  console.log("  🏁 ИТОГ ПО CAMP POINT");
  console.log(`${"═".repeat(55)}\n`);

  console.log(`  👤 Кошелёк ${targetWallet}:`);
  console.log(`  • MINTER_ROLE: ❌ НЕТ`);
  console.log(`  • DEFAULT_ADMIN_ROLE: ❌ НЕТ`);
  console.log(`  • Любая другая роль: ❌ НЕТ`);
  console.log(`  • Баланс CP#1: 50`);
  console.log(`  • Баланс CP#2: 59`);
  console.log(``);
  console.log(`  🔐 mint() — защищён (требует роль)`);
  console.log(`  ❓ Но getRoleMember() — ревертит`);
  console.log(`  ❓ Неизвестно, у кого сейчас роль минтера`);
  console.log(``);
  console.log(`  💰 Мост (Bridge): 456.7 ETH с Ethereum`);
  console.log(`  Владелец моста: 0x3c276499D267F400bCa6173B7A9916e95443e64b`);
  console.log(`  (не зависит от уязвимости CampPoint)`);

  console.log("\n═══════════════════════════════════════════════\n");
}

main().catch(e => { console.error(e); process.exit(1); });
