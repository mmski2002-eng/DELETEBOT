/**
 * CRIT-01 empirical verification using REAL NativeVault mainnet bytecode
 * Deploys production contract code into @ton/sandbox + MockPool reject mode
 * Tests whether production vault correctly handles bounced pool_swap_internal
 */

import { Blockchain, SandboxContract, TreasuryContract, createShardAccount, internal } from '@ton/sandbox';
import { Cell, beginCell, toNano, Address, contractAddress } from '@ton/core';
import { compile } from '@ton/blueprint';
import * as fs from 'fs';
import * as path from 'path';
import '@ton/test-utils';

describe('CRIT-01: Real NativeVault mainnet bytecode — bounce handler', () => {
    let blockchain: Blockchain;
    let user: SandboxContract<TreasuryContract>;
    let vaultAddr: Address;
    let poolAddr: Address;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        user = await blockchain.treasury('user');

        // --- Deploy REAL NativeVault (mainnet bytecode + mainnet data) ---
        const codeBoc = fs.readFileSync(
            path.resolve(__dirname, '../phase83_native_vault_boc.txt'), 'utf8').trim();
        const dataBoc = fs.readFileSync(
            path.resolve(__dirname, '../phase83_native_vault_data.txt'), 'utf8').trim();
        const code = Cell.fromBase64(codeBoc);
        const data = Cell.fromBase64(dataBoc);

        vaultAddr = contractAddress(0, { code, data });
        await blockchain.setShardAccount(vaultAddr, createShardAccount({
            code,
            data,
            balance: toNano('100'),
            workchain: 0,
        }));

        // --- Deploy MockPool in REJECT mode ---
        const poolCode = await compile('MockPool');
        const poolData = beginCell().storeUint(1, 1).endCell(); // reject=1
        poolAddr = contractAddress(0, { code: poolCode, data: poolData });
        await blockchain.setShardAccount(poolAddr, createShardAccount({
            code: poolCode,
            data: poolData,
            balance: toNano('5'),
            workchain: 0,
        }));
    });

    function buildSwapBody(amount: bigint, pool: Address): Cell {
        // SwapParams format confirmed from mainnet tx decode:
        // [32: deadline] [2: addr_none recipient] [2: addr_none referral] [1: no fulfill] [1: no reject]
        // = 38 bits, 0 refs
        const swapParams = beginCell()
            .storeUint(Math.floor(Date.now() / 1000) + 300, 32)
            .storeUint(0, 2)    // recipient = addr_none (use sender)
            .storeUint(0, 2)    // referral  = addr_none (none)
            .storeBit(false)    // no fulfill_payload
            .storeBit(false)    // no reject_payload
            .endCell();

        return beginCell()
            .storeUint(0xea06185d, 32)  // SWAP op
            .storeUint(0n, 64)           // query_id
            .storeCoins(amount)          // amount
            .storeAddress(pool)          // pool_addr (SwapStep)
            .storeUint(0, 1)             // step_has_next = false
            .storeCoins(0n)              // limit = 0 (no slippage limit)
            .storeBit(false)             // extra flag (always 0 in real txs)
            .storeRef(swapParams)
            .endCell();
    }

    it('pool rejects → bounced msg returns to vault → vault exit code 0', async () => {
        const swapAmount = toNano('1');

        const result = await blockchain.sendMessage(internal({
            from: user.address,
            to:   vaultAddr,
            value: swapAmount + toNano('0.5'),
            bounce: false,
            body: buildSwapBody(swapAmount, poolAddr),
        }));

        console.log('\n=== Transaction chain ===');
        for (const tx of result.transactions) {
            const src  = tx.inMessage?.info?.src?.toString()?.substring(0, 10) ?? '?';
            const dest = (tx.inMessage?.info as any)?.dest?.toString()?.substring(0, 10) ?? '?';
            const bodySlice = tx.inMessage?.body?.beginParse();
            const op = bodySlice && bodySlice.remainingBits >= 32
                ? '0x' + bodySlice.loadUint(32).toString(16) : '?';
            const exit = (tx.description as any)?.computePhase?.exitCode ?? 'N/A';
            const bounced = (tx.inMessage?.info as any)?.bounced ?? false;
            console.log(`  ${src}→${dest} op=${op} exit=${exit} bounced=${bounced}`);
        }

        // Find all txs destined to vault
        const vaultTxs = result.transactions.filter(tx =>
            (tx.inMessage?.info as any)?.dest?.equals(vaultAddr)
        );

        // First vault tx = the SWAP (should succeed)
        const swapTx = vaultTxs[0];
        expect((swapTx.description as any)?.computePhase?.exitCode).toBe(0);

        // Find the bounced tx (MockPool throws 333 → bounce goes back to vault)
        const bouncedTx = vaultTxs.find(tx => (tx.inMessage?.info as any)?.bounced === true);

        if (!bouncedTx) {
            console.log('\n⚠ No bounced tx reached vault (pool may not have sent bounce)');
            console.log('  Check MockPool throw_if(333, ...) fired correctly');
            // Pool should have thrown — check pool tx
            const poolTx = result.transactions.find(tx =>
                (tx.inMessage?.info as any)?.dest?.equals(poolAddr)
            );
            const poolExit = (poolTx?.description as any)?.computePhase?.exitCode;
            console.log('  Pool exit code:', poolExit, '(333 = throw_if in reject mode)');
            expect(poolExit).toBe(333); // confirms pool threw → bounce sent
            return;
        }

        const bounceExit = (bouncedTx.description as any)?.computePhase?.exitCode;
        console.log('\n✓ Bounced tx reached vault, exit code:', bounceExit);

        if (bounceExit === 0) {
            console.log('✓ BOUNCE HANDLER WORKING — vault handled bounce gracefully');
            // Also check vault sent refund out (out_msgs from bounce tx)
            const outMsgs = bouncedTx.outMessages.size;
            console.log('  Out messages from bounce handler:', outMsgs, '(>0 = refund sent)');
        } else if (bounceExit === 0xffff) {
            console.log('✗ CRIT-01 CONFIRMED — vault hit throw(0xffff) on bounced msg → funds locked');
        } else {
            console.log('? Unexpected exit code:', bounceExit);
        }

        expect(bounceExit).toBe(0); // bounce handler must succeed
    });

    it('pool accepts → vault processes normally (control test)', async () => {
        // Reset pool to accept mode
        const poolCode = await compile('MockPool');
        const poolData = beginCell().storeUint(0, 1).endCell(); // reject=0
        await blockchain.setShardAccount(poolAddr, createShardAccount({
            code: poolCode,
            data: poolData,
            balance: toNano('5'),
            workchain: 0,
        }));

        const result = await blockchain.sendMessage(internal({
            from: user.address,
            to:   vaultAddr,
            value: toNano('1.5'),
            bounce: false,
            body: buildSwapBody(toNano('1'), poolAddr),
        }));

        const vaultTx = result.transactions.find(tx =>
            (tx.inMessage?.info as any)?.dest?.equals(vaultAddr)
        );
        const exit = (vaultTx?.description as any)?.computePhase?.exitCode;
        console.log('\nControl test — vault exit:', exit);
        expect(exit).toBe(0);
    });
});
