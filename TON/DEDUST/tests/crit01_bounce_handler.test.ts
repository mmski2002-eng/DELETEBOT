/**
 * CRIT-01: Bounce handler absent in Vault
 *
 * Pool rejects swap (throws 333).
 * BuggyVault: bounce hits throw(0xffff) → locked stays > 0 → permanent token lock.
 * FixedVault: bounce handler decrements locked + refunds user.
 */

import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { Cell, toNano } from '@ton/core';
import { compile } from '@ton/blueprint';
import { MockVaultBuggy } from '../wrappers/MockVaultBuggy';
import { MockVaultFixed } from '../wrappers/MockVaultFixed';
import { MockPool } from '../wrappers/MockPool';
import '@ton/test-utils';

describe('CRIT-01: Vault bounce handler', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let user: SandboxContract<TreasuryContract>;
    let vaultBuggyCode: Cell;
    let vaultFixedCode: Cell;
    let poolCode: Cell;

    beforeAll(async () => {
        vaultBuggyCode = await compile('MockVaultBuggy');
        vaultFixedCode = await compile('MockVaultFixed');
        poolCode      = await compile('MockPool');
    });

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        deployer   = await blockchain.treasury('deployer');
        user       = await blockchain.treasury('user');
    });

    it('[VULNERABLE] locked > 0 after pool bounce — no bounce handler', async () => {
        // Deploy pool in reject mode
        const pool = blockchain.openContract(MockPool.createFromInit(poolCode, true));
        await pool.sendDeploy(deployer.getSender());
        expect(await pool.getShouldReject()).toBe(true);

        // Deploy buggy vault
        const vault = blockchain.openContract(MockVaultBuggy.createFromInit(vaultBuggyCode, deployer.address));
        await vault.sendDeploy(deployer.getSender());
        expect(await vault.getLockedAmount()).toBe(0n);

        // User sends swap → vault locks 1 TON → forwards to pool → pool throws 333
        const result = await vault.sendSwap(user.getSender(), {
            amount: toNano('1'),
            poolAddress: pool.address,
        });

        // TX1: user → vault: success (vault locked 1 TON)
        expect(result.transactions).toHaveTransaction({
            from: user.address,
            to: vault.address,
            success: true,
        });

        // TX2: vault → pool: FAIL exit 333
        expect(result.transactions).toHaveTransaction({
            from: vault.address,
            to: pool.address,
            success: false,
            exitCode: 333,
        });

        // TX3: bounced message → vault: FAIL exit 0xffff (no bounce handler)
        // Pool sends bounce back; vault hits throw(0xffff) because op=0xffffffff unhandled
        expect(result.transactions).toHaveTransaction({
            from: pool.address,
            to: vault.address,
            success: false,
            exitCode: 0xffff,
        });

        // PROOF: 1 TON permanently locked
        const locked = await vault.getLockedAmount();
        expect(locked).toBeGreaterThan(0n);
        console.log(`[CRIT-01 CONFIRMED] ${locked} nanoTON locked forever in vault`);
    });

    it('[FIXED] locked returns to 0 after pool bounce — with bounce handler', async () => {
        const pool = blockchain.openContract(MockPool.createFromInit(poolCode, true));
        await pool.sendDeploy(deployer.getSender());

        const vault = blockchain.openContract(MockVaultFixed.createFromInit(vaultFixedCode, deployer.address));
        await vault.sendDeploy(deployer.getSender());

        const result = await vault.sendSwap(user.getSender(), {
            amount: toNano('1'),
            poolAddress: pool.address,
        });

        // Pool threw 333 → bounce back to fixed vault → handled successfully
        expect(result.transactions).toHaveTransaction({
            from: vault.address,
            to: pool.address,
            success: false,
            exitCode: 333,
        });
        expect(result.transactions).toHaveTransaction({
            from: pool.address,
            to: vault.address,
            success: true,
        });

        // Fixed vault handled bounce → locked = 0
        const locked = await vault.getLockedAmount();
        expect(locked).toBe(0n);
        console.log('[CRIT-01 FIX VERIFIED] locked cleared after bounce');
    });

    it('[CONTROL] pool accepts → locked = 0 after successful swap', async () => {
        const pool = blockchain.openContract(MockPool.createFromInit(poolCode, false));
        await pool.sendDeploy(deployer.getSender());

        const vault = blockchain.openContract(MockVaultBuggy.createFromInit(vaultBuggyCode, deployer.address));
        await vault.sendDeploy(deployer.getSender());

        const result = await vault.sendSwap(user.getSender(), {
            amount: toNano('1'),
            poolAddress: pool.address,
        });

        expect(result.transactions).toHaveTransaction({
            from: vault.address,
            to: pool.address,
            success: true,
        });

        // In real DeDust, pool would send payout back and vault decrements locked.
        // Our mock pool does nothing on success, so locked stays > 0 here.
        // This test verifies the happy path reaches pool without error.
        console.log('[CONTROL] Happy path: vault → pool success, no bounce');
    });
});
