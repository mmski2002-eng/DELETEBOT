/**
 * CRIT-02 on-chain verifier — Step 1: Read LiquidityDeposit state
 *
 * Usage:
 *   npx ts-node scripts/crit02_read_state.ts <LiquidityDeposit_address>
 *
 * Find the address in tonviewer: start adding liquidity on DeDust UI (don't complete),
 * check the tx trace — a new LIQUIDITY_DEPOSIT contract appears.
 * Or use crit02_build_tx.ts to create a fresh one.
 */

import { Address, TonClient } from '@ton/ton';

const MAINNET_RPC = 'https://toncenter.com/api/v2/jsonRPC';

// Getter names from DeDust LiquidityDeposit (FunC snake_case)
const GETTERS = {
    owner:    'get_owner_address',
    pool:     'get_pool_address',
    balances: 'get_balances',
    targets:  'get_target_balances',
    minLp:    'get_minimal_lp_amount',
    isProc:   'get_is_processing',
} as const;

async function main() {
    const rawAddr = process.argv[2];
    if (!rawAddr) {
        console.error('Usage: npx ts-node scripts/crit02_read_state.ts <LiquidityDeposit_address>');
        process.exit(1);
    }

    const ldAddr = Address.parse(rawAddr);
    const client = new TonClient({ endpoint: MAINNET_RPC });

    console.log(`\n=== LiquidityDeposit: ${ldAddr.toString()} ===\n`);

    // Check contract exists
    const state = await client.getContractState(ldAddr);
    if (state.state !== 'active') {
        console.error(`Contract state: ${state.state} — not active, nothing to verify.`);
        process.exit(1);
    }
    console.log(`Contract state: ${state.state}  (balance: ${Number(state.balance) / 1e9} TON)\n`);

    // Read all getters
    try {
        const [ownerR, poolR, balR, tgtR, minLpR, isProcR] = await Promise.all([
            client.runMethod(ldAddr, GETTERS.owner),
            client.runMethod(ldAddr, GETTERS.pool),
            client.runMethod(ldAddr, GETTERS.balances),
            client.runMethod(ldAddr, GETTERS.targets),
            client.runMethod(ldAddr, GETTERS.minLp),
            client.runMethod(ldAddr, GETTERS.isProc),
        ]);

        const owner       = ownerR.stack.readAddress();
        const pool        = poolR.stack.readAddress();
        const balA        = balR.stack.readBigNumber();
        const balB        = balR.stack.readBigNumber();
        const tgtA        = tgtR.stack.readBigNumber();
        const tgtB        = tgtR.stack.readBigNumber();
        const minLp       = minLpR.stack.readBigNumber();
        const isProcessing = isProcR.stack.readBoolean();

        console.log('owner:          ', owner.toString());
        console.log('pool:           ', pool.toString());
        console.log(`balance_a:       ${balA} (${Number(balA) / 1e9} TON-like units)`);
        console.log(`balance_b:       ${balB} (${Number(balB) / 1e9} TON-like units)`);
        console.log(`target_a:        ${tgtA}`);
        console.log(`target_b:        ${tgtB}`);
        console.log(`min_lp_amount:   ${minLp}`);
        console.log(`isProcessing:    ${isProcessing}`);

        // Diagnosis
        console.log('\n=== DIAGNOSIS ===');
        if (!isProcessing && balA > 0n && balB === 0n) {
            console.log('[PARTIAL_A] First deposit received, second pending. CANCEL_DEPOSIT should work.');
        } else if (!isProcessing && balB > 0n && balA === 0n) {
            console.log('[PARTIAL_B] Second deposit received, first pending. CANCEL_DEPOSIT should work.');
        } else if (isProcessing) {
            console.log('[PROCESSING] Assets sent to pool, awaiting LP. CANCEL_DEPOSIT behavior unknown — THIS IS THE CRITICAL CHECK.');
        } else if (balA === 0n && balB === 0n) {
            console.log('[IDLE] No pending deposits.');
        } else {
            console.log('[BOTH_PENDING] Both assets received, not yet sent to pool.');
        }

    } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error('Getter call failed:', msg);
        console.error('Contract may not implement expected getters — check if address is correct LiquidityDeposit.');
    }
}

main().catch(console.error);
