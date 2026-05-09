const { ethers } = require("hardhat");

/**
 * ════════════════════════════════════════════════════════
 *  Deep bytecode analysis — find infinite mint vulnerabilties
 * ════════════════════════════════════════════════════════
 *
 * Usage: npx hardhat run scripts/deep_token_analysis.js --network campNetwork
 */

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("  🔬 DEEP BYTECODE ANALYSIS — Infinite Mint");
  console.log("═══════════════════════════════════════════════\n");

  // ─── 1. CampPoint tokens — 225 bytes each?! ──────────
  console.log("🔎 PHASE 1: CampPoint Mystery (225 bytes)"); 

  for (const [label, addr] of [
    ["CP#1 (0-dec)", "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537"],
    ["CP#2 (18-dec)", "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF"]
  ]) {
    console.log(`\n  📀 ${label}: ${addr}`);
    const code = await ethers.provider.getCode(addr);
    console.log(`  Full bytecode (${code.length / 2 - 1} bytes):`);

    // Disassemble first part
    const ops = disassemble(code);
    console.log(`  Instructions: ${ops.length}`);
    for (let i = 0; i < Math.min(ops.length, 30); i++) {
      console.log(`    ${ops[i]}`);
    }
    if (ops.length > 30) {
      console.log(`    ... (${ops.length - 30} more instructions)`);
    }
  }

  // ─── 2. WETH — found mint selector ──────────────────
  console.log(`\n${"═".repeat(55)}`);
  console.log("🔎 PHASE 2: WETH — mint(address,uint256) found!");
  console.log(`${"═".repeat(55)}`);

  const wethAddr = "0xC42BAA20e3a159cF7A8aDFA924648C2a2d59E062";
  const wethCode = await ethers.provider.getCode(wethAddr);

  // Try to call WETH functions
  const wethABI = [
    "function mint(address to, uint256 amount) external returns (bool)",
    "function owner() view returns (address)",
    "function name() view returns (string)",
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)",
    "function totalSupply() view returns (uint256)",
    "function balanceOf(address) view returns (uint256)",
  ];

  try {
    const weth = await ethers.getContractAt(wethABI, wethAddr);
    const [name, symbol, decimals, totalSupply, wethOwner] = await Promise.all([
      weth.name(),
      weth.symbol(),
      weth.decimals(),
      weth.totalSupply(),
      weth.owner().catch(() => "N/A"),
    ]);
    console.log(`  Name: ${name}`);
    console.log(`  Symbol: ${symbol}`);
    console.log(`  Decimals: ${decimals}`);
    console.log(`  Total Supply: ${ethers.formatEther(totalSupply)}`);
    console.log(`  Owner: ${wethOwner}`);

    // Try to call mint as a random user (to see if it reverts)
    const [deployer] = await ethers.getSigners();
    const randomWallet = ethers.Wallet.createRandom().connect(ethers.provider);

    console.log(`\n  ⚠️  Attempting to call mint() as random user...`);
    try {
      const tx = await weth.connect(deployer).mint(deployer.address, ethers.parseEther("1"), {
        gasLimit: 100000
      });
      const receipt = await tx.wait();
      console.log(`  ❌ MINT SUCCEEDED! New supply: ${ethers.formatEther(await weth.totalSupply())}`);
      console.log(`  🚨 UNPROTECTED MINT — anyone can create WETH!`);
    } catch (e) {
      const msg = e.message.substring(0, 100);
      if (msg.includes("revert") || msg.includes("execution reverted")) {
        console.log(`  ✅ Mint reverted — protected (good)`);
      } else if (msg.includes("sender doesn't have")) {
        console.log(`  ⚠️  Random wallet can't send (expected), trying deployer...`);
        // Try with deployer
        try {
          const tx = await weth.mint(deployer.address, ethers.parseEther("1"), { gasLimit: 100000 });
          const receipt = await tx.wait();
          console.log(`  ❌ MINT SUCCEEDED via deployer! ${ethers.formatEther(await weth.totalSupply())}`);
        } catch(e2) {
          console.log(`  ✅ Mint reverted: ${e2.message.substring(0, 80)}`);
        }
      } else {
        console.log(`  ⚠️  ${msg}`);
      }
    }
  } catch (e) {
    console.log(`  ❌ Error: ${e.message.substring(0, 80)}`);
  }

  // ─── 3. MUSDC — found mint(uint256) selector ──────────
  console.log(`\n${"═".repeat(55)}`);
  console.log("🔎 PHASE 3: MUSDC — mint(uint256) found!");
  console.log(`${"═".repeat(55)}`);

  const musdcAddr = "0x71002dbf6cC7A885cE6563682932370c056aAca9";
  try {
    const musdc = await ethers.getContractAt(
      ["function mint(uint256 amount) external returns (bool)", "function owner() view returns (address)", "function name() view returns (string)", "function totalSupply() view returns (uint256)"],
      musdcAddr
    );
    const [name, totalSupply, owner] = await Promise.all([
      musdc.name(),
      musdc.totalSupply(),
      musdc.owner().catch(() => "N/A"),
    ]);
    console.log(`  Name: ${name}`);
    console.log(`  Total Supply: ${ethers.formatUnits(totalSupply, 6)}`);
    console.log(`  Owner: ${owner}`);

    // Try mint
    console.log(`  Attempting to call mint(1000) as deployer...`);
    try {
      const [deployer] = await ethers.getSigners();
      const tx = await musdc.mint(1000n * 10n**6n, { gasLimit: 100000 });
      const receipt = await tx.wait();
      const newSupply = await musdc.totalSupply();
      console.log(`  ❌ MINT SUCCEEDED! New supply: ${ethers.formatUnits(newSupply, 6)}`);
    } catch (e) {
      console.log(`  ✅ Mint reverted: ${e.message.substring(0, 80)}`);
    }
  } catch (e) {
    console.log(`  ❌ Error: ${e.message.substring(0, 80)}`);
  }

  // ─── 4. CampPoint check who can mint ────────────────
  console.log(`\n${"═".repeat(55)}`);
  console.log("🔎 PHASE 4: CampPoint — who controls the supply?");
  console.log(`${"═".repeat(55)}`);

  for (const [label, addr] of [
    ["CP#1 (0-dec)", "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537"],
    ["CP#2 (18-dec)", "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF"]
  ]) {
    console.log(`\n  📀 ${label}: ${addr}`);

    // With only 225 bytes and no selectors, these might be balance-only contracts
    // Let's check what the bytecode actually does
    const code = await ethers.provider.getCode(addr);

    // Try to interpret as a minimal proxy (ERC-1167)
    // ERC-1167: 0x363d3d373d3d3d363d73...address...5af43d82803e903d91602b57fd5bf3
    const eip1167Pattern = "363d3d373d3d3d363d73";
    const eip1167Pattern2 = "5af43d82803e903d91602b57fd5bf3";
    
    if (code.includes(eip1167Pattern)) {
      const implStart = code.indexOf(eip1167Pattern) + eip1167Pattern.length;
      const implAddrBytes = code.substring(implStart, implStart + 40);
      const implAddr = "0x" + implAddrBytes;
      console.log(`  ⚠️  ERC-1167 Minimal Proxy! Implementation: ${implAddr}`);

      // Check implementation
      const implCode = await ethers.provider.getCode(implAddr);
      console.log(`  Implementation code size: ${(implCode.length - 2) / 2} bytes`);

      // Check if implementation has mint
      if (implCode.toLowerCase().includes("40c10f19")) {
        console.log(`  🚨 Implementation has mint(address,uint256)!`);
      }
    } else {
      console.log(`  Not an ERC-1167 proxy`);
      console.log(`  Raw bytecode analysis:`);
      const ops = disassemble(code);
      for (let i = 0; i < ops.length; i++) {
        console.log(`    ${ops[i]}`);
      }
    }
  }

  // ─── 5. Check who has the most tokens ──────────────
  console.log(`\n${"═".repeat(55)}`);
  console.log("🔎 PHASE 5: Top holders — who can mint?");
  console.log(`${"═".repeat(55)}`);

  const allTokens = [
    { addr: "0x52DE57cc9f27b8c2f7F949Ccc784aD5c071eB537", name: "CP#1", dec: 0 },
    { addr: "0xa5C64282ecad22D692Da25d04D3849a5aa0a40BF", name: "CP#2", dec: 18 },
    { addr: "0xC42BAA20e3a159cF7A8aDFA924648C2a2d59E062", name: "WETH", dec: 18 },
  ];

  const keyAccounts = [
    "0x12C3E3B84B75ca4a9388de696621ac5F2Ae36953", // Bridge
    "0x7C969ea45cdA884902102212DDF14f2A33988208", // Marketplace v1
    "0x81BeB79b977cAd2B1d06aFC62b4aABB7611107b4", // Marketplace v2
    "0xb27092564b5434f68706753f9C0ADDC49Ca71dC5", // Vault
    "0xC4a35ce77b090cb511CEb5622D9A41f9A722e4E4", // IpNFT
  ];

  for (const token of allTokens) {
    console.log(`\n  📀 ${token.name} (${token.addr}):`);
    const contract = await ethers.getContractAt(
      ["function balanceOf(address) view returns (uint256)", "function totalSupply() view returns (uint256)"],
      token.addr
    );
    const totalSupply = await contract.totalSupply();
    console.log(`  Total supply: ${ethers.formatUnits(totalSupply, token.dec)}`);

    for (const acct of keyAccounts) {
      try {
        const bal = await contract.balanceOf(acct);
        if (bal > 0n) {
          const pct = Number(bal * 10000n / totalSupply) / 100;
          console.log(`    ${acct.substring(0, 10)}... : ${ethers.formatUnits(bal, token.dec)} (${pct}%)`);
        }
      } catch (e) { /* ignore */ }
    }
  }

  console.log("\n═══════════════════════════════════════════════");
  console.log("  ANALYSIS COMPLETE");
  console.log("═══════════════════════════════════════════════\n");
}

function disassemble(code) {
  const opcodes = {
    "00": "STOP", "01": "ADD", "02": "MUL", "03": "SUB", "04": "DIV",
    "10": "LT", "11": "GT", "12": "SLT", "13": "SGT", "14": "EQ",
    "15": "ISZERO", "16": "AND", "17": "OR", "18": "XOR", "19": "NOT",
    "1a": "BYTE", "20": "SHA3",
    "30": "ADDRESS", "31": "BALANCE", "32": "ORIGIN", "33": "CALLER",
    "34": "CALLVALUE", "35": "CALLDATALOAD", "36": "CALLDATASIZE",
    "37": "CALLDATACOPY", "38": "CODESIZE", "39": "CODECOPY",
    "3a": "GASPRICE", "3b": "EXTCODESIZE", "3c": "EXTCODECOPY",
    "3d": "RETURNDATASIZE", "3e": "RETURNDATACOPY", "3f": "EXTCODEHASH",
    "40": "BLOCKHASH", "41": "COINBASE", "42": "TIMESTAMP", "43": "NUMBER",
    "44": "DIFFICULTY", "45": "GASLIMIT", "46": "CHAINID",
    "47": "SELFBALANCE", "48": "BASEFEE",
    "50": "POP", "51": "MLOAD", "52": "MSTORE", "53": "MSTORE8",
    "54": "SLOAD", "55": "SSTORE", "56": "JUMP", "57": "JUMPI",
    "58": "PC", "59": "MSIZE", "5a": "GAS", "5b": "JUMPDEST",
    "60": "PUSH1", "61": "PUSH2", "62": "PUSH3", "63": "PUSH4",
    "64": "PUSH5", "65": "PUSH6", "66": "PUSH7", "67": "PUSH8",
    "68": "PUSH9", "69": "PUSH10", "6a": "PUSH11", "6b": "PUSH12",
    "6c": "PUSH13", "6d": "PUSH14", "6e": "PUSH15", "6f": "PUSH16",
    "70": "PUSH17", "71": "PUSH18", "72": "PUSH19", "73": "PUSH20",
    "74": "PUSH21", "75": "PUSH22", "76": "PUSH23", "77": "PUSH24",
    "78": "PUSH25", "79": "PUSH26", "7a": "PUSH27", "7b": "PUSH28",
    "7c": "PUSH29", "7d": "PUSH30", "7e": "PUSH31", "7f": "PUSH32",
    "80": "DUP1", "81": "DUP2", "82": "DUP3", "83": "DUP4",
    "90": "SWAP1", "91": "SWAP2", "92": "SWAP3",
    "a0": "LOG0", "a1": "LOG1", "a2": "LOG2", "a3": "LOG3", "a4": "LOG4",
    "f0": "CREATE", "f1": "CALL", "f2": "CALLCODE", "f3": "RETURN",
    "f4": "DELEGATECALL", "f5": "CREATE2", "fa": "STATICCALL",
    "fd": "REVERT", "fe": "INVALID", "ff": "SELFDESTRUCT",
  };

  const stripped = code.startsWith("0x") ? code.substring(2) : code;
  const result = [];
  let i = 0;

  while (i < stripped.length - 1) {
    const byte = stripped.substring(i, i + 2);
    const op = opcodes[byte] || `UNKNOWN(0x${byte})`;
    const pos = i / 2;

    if (byte >= "60" && byte <= "7f") {
      // PUSH instruction
      const pushLen = parseInt(byte, 16) - 0x5f;
      const data = stripped.substring(i + 2, i + 2 + pushLen * 2);
      const dataInt = data.length > 0 ? BigInt("0x" + data).toString() : "0";
      result.push(`[${pos}] ${op} 0x${data} (${dataInt})`);
      i += 2 + pushLen * 2;
    } else {
      result.push(`[${pos}] ${op}`);
      i += 2;
    }

    if (result.length > 50) break;
  }

  return result;
}

main().catch(e => { console.error(e); process.exit(1); });
