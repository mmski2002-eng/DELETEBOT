import { Blockchain } from '@ton-community/sandbox';
import { beginCell, Cell, contractAddress, toNano } from 'ton-core';
import { compileFunc } from '@ton-community/func-js';
import * as fs from 'fs';
import * as path from 'path';

const DEFAULT_CONTRACTS_DIR = '/tmp/rhinofi_contracts_public/ton-deposit/contracts';
const BRIDGE_BALANCE = toNano('50');

function collectSources(dir: string): Record<string, string> {
    const out: Record<string, string> = {};

    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            Object.assign(out, collectSources(fullPath));
        } else if (entry.isFile() && fullPath.endsWith('.fc')) {
            out[fullPath] = fs.readFileSync(fullPath, 'utf8');
        }
    }

    return out;
}

async function compileOriginalBridge(contractsDir: string) {
    const target = path.join(contractsDir, 'bridge_contract.fc');
    const result = await compileFunc({
        targets: [target],
        sources: collectSources(contractsDir)
    });

    if (result.status !== 'ok') {
        throw new Error(`Compilation failed: ${result.message}`);
    }

    return Cell.fromBase64(result.codeBoc);
}

async function main() {
    const contractsDir = process.env.RHINOFI_CONTRACTS_PUBLIC_DIR ?? DEFAULT_CONTRACTS_DIR;
    if (!fs.existsSync(contractsDir)) {
        throw new Error(`Contracts dir not found: ${contractsDir}`);
    }

    console.log('=== Original RHINOfi TON Bridge Check ===');
    console.log(`Contracts dir: ${contractsDir}\n`);

    const code = await compileOriginalBridge(contractsDir);
    const data = beginCell()
        .storeAddress(null)
        .storeAddress(null)
        .storeDict(null)
        .storeDict(null)
        .storeInt(0n, 1)
        .endCell();

    const init = { code, data };
    const bridgeAddress = contractAddress(0, init);

    const blockchain = await Blockchain.create();
    const attacker = await blockchain.treasury('attacker');

    await blockchain.setShardAccount(bridgeAddress, {
        account: {
            addr: bridgeAddress,
            storage: {
                lastTransLt: 0n,
                balance: { coins: BRIDGE_BALANCE },
                state: {
                    type: 'active',
                    state: { code, data }
                }
            },
            storageStats: {
                used: { cells: 0n, bits: 0n, publicCells: 0n },
                lastPaid: 0,
                duePayment: null
            }
        },
        lastTransactionLt: 0n,
        lastTransactionHash: 0n
    });

    const attackerBefore = (await blockchain.getContract(attacker.address)).balance;
    const bridgeBefore = (await blockchain.getContract(bridgeAddress)).balance;

    const transferNotification = beginCell()
        .storeUint(0x7362d09c, 32)
        .storeUint(1, 64)
        .storeCoins(toNano('10'))
        .storeAddress(attacker.address)
        .storeBit(1)
        .storeRef(beginCell().storeUint(0, 8).endCell())
        .endCell();

    const result = await blockchain.sendMessage({
        info: {
            type: 'internal',
            ihrDisabled: true,
            bounce: true,
            bounced: false,
            src: attacker.address,
            dest: bridgeAddress,
            value: { coins: toNano('1') },
            ihrFee: 0n,
            forwardFee: 0n,
            createdLt: 0n,
            createdAt: 0
        },
        body: transferNotification
    });

    const attackerAfter = (await blockchain.getContract(attacker.address)).balance;
    const bridgeAfter = (await blockchain.getContract(bridgeAddress)).balance;
    const bridgeDelta = bridgeAfter - bridgeBefore;
    const attackerDelta = attackerAfter - attackerBefore;

    console.log(`Bridge before:   ${bridgeBefore.toString()}`);
    console.log(`Bridge after:    ${bridgeAfter.toString()}`);
    console.log(`Bridge delta:    ${bridgeDelta.toString()}`);
    console.log(`Attacker delta:  ${attackerDelta.toString()}`);
    console.log(`Transactions:    ${result.transactions.length}\n`);

    result.transactions.forEach((tx, index) => {
        const aborted = 'aborted' in tx.description ? tx.description.aborted : false;
        console.log(`tx[${index}] aborted=${String(aborted)} out=${tx.outMessagesCount}`);
        for (const msg of tx.outMessages.values()) {
            const value = msg.info.type === 'internal' ? msg.info.value.coins.toString() : 'n/a';
            console.log(`  -> ${msg.info.dest?.toString?.()} value=${value}`);
        }
    });

    const bridgePreserved = bridgeAfter >= bridgeBefore;
    const onlyRefundedMsgValue = attackerDelta < toNano('2');

    console.log('');
    if (bridgePreserved && onlyRefundedMsgValue) {
        console.log('[PASS] Original bridge preserved its pre-existing balance.');
        console.log('[PASS] Refund behavior returned roughly the attached message value, not the full bridge treasury.');
        process.exit(0);
    }

    console.log('[FAIL] Original bridge behavior indicates more than msg.value was released.');
    process.exit(1);
}

main().catch((err) => {
    console.error('Fatal error:', err);
    process.exit(2);
});
