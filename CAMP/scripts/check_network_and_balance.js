const { ethers } = require("hardhat");

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("  🔍 NETWORK & BALANCE CHECK");
  console.log("═══════════════════════════════════════════════\n");

  const network = await ethers.provider.getNetwork();
  console.log(`  Сеть: Camp Network`);
  console.log(`  Chain ID: ${network.chainId}`);
  console.log(`  Нативный токен: CAMP (а НЕ ETH!)`);
  console.log();

  const targetWallet = "0xd6DfAE7E62DD93Cc2CB525B7785983682b6802dc";
  const balance = await ethers.provider.getBalance(targetWallet);
  
  console.log(`  👤 Кошелёк: ${targetWallet}`);
  console.log(`  Баланс: ${ethers.formatEther(balance)} CAMP`);
  console.log(`  (в предыдущем ответе я ошибочно назвал это ETH)`);
  console.log();
  console.log(`  ⚠️  Это сеть Camp Network (L2), её нативный токен — CAMP,`);
  console.log(`      а не Ethereum ETH. Ошибка в терминологии с моей стороны.`);
  
  // Also check the bridge balance properly
  const bridgeAddr = "0x12C3E3B84B75ca4a9388de696621ac5F2Ae36953";
  const bridgeBal = await ethers.provider.getBalance(bridgeAddr);
  console.log();
  console.log(`  🌉 Bridge (CrustySwap) баланс: ${ethers.formatEther(bridgeBal)} CAMP`);
  console.log(`  (это CAMP на Camp Network, который пришёл с Ethereum через мост)`);

  console.log("\n═══════════════════════════════════════════════\n");
}

main().catch(e => { console.error(e); process.exit(1); });
