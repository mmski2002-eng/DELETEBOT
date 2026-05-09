/**
 * CRIT-02 on-chain verifier — Build transactions
 *
 * TX A: DEPOSIT_LIQUIDITY (TON only, no second asset) → creates partial LiquidityDeposit
 * TX B: CANCEL_DEPOSIT → send to LiquidityDeposit address to test cancellation
 *
 * Usage: npx ts-node scripts/crit02_build_tx.ts
 */

import { Address, beginCell, toNano } from '@ton/core';
import { Asset, PoolType } from '@dedust/sdk';

const OP_DEPOSIT_LIQUIDITY = 0xd55e4686;
const OP_CANCEL_DEPOSIT    = 0x166cedee;

const NATIVE_VAULT = 'EQDa4VOnTYlLvDJ0gZjNYm5PXfSmmtL6Vs6A_CZEtXCNICq_';

const TON_ASSET  = Asset.native();
const USDT_ASSET = Asset.jetton(Address.parse('EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs'));

const DEPOSIT_NANO  = toNano('0.001');
const GAS_NANO      = toNano('0.3');   // SDK hardcodes 0.3 TON — required for chain
const CANCEL_GAS    = toNano('0.1');

function buildDepositA(): Buffer {
    return beginCell()
        .storeUint(OP_DEPOSIT_LIQUIDITY, 32)
        .storeUint(0n, 64)                    // query_id
        .storeCoins(DEPOSIT_NANO)             // amount (TON)
        .storeUint(PoolType.VOLATILE, 1)      // pool_type
        .storeSlice(TON_ASSET.toSlice())      // asset_0
        .storeSlice(USDT_ASSET.toSlice())     // asset_1
        .storeRef(
            beginCell()
                .storeCoins(0)               // min_lp = 0
                .storeCoins(DEPOSIT_NANO)    // target_balance_0
                .storeCoins(0)              // target_balance_1 = 0 → partial deposit
            .endCell()
        )
        .storeMaybeRef(null)                  // fulfill_payload (root cell, not in ref)
        .storeMaybeRef(null)                  // reject_payload  (root cell, not in ref)
        .endCell()
        .toBoc();
}

function buildCancelDeposit(): Buffer {
    return beginCell()
        .storeUint(OP_CANCEL_DEPOSIT, 32)
        .storeUint(0n, 64)
        .storeBit(0)   // no custom_payload
        .endCell()
        .toBoc();
}

function main() {
    const txA = buildDepositA();
    const txB = buildCancelDeposit();

    const totalA = DEPOSIT_NANO + GAS_NANO;

    console.log('=== TX A: DEPOSIT_LIQUIDITY ===');
    console.log('To:    ', NATIVE_VAULT);
    console.log('Value: ', `${Number(totalA) / 1e9} TON`);
    console.log('Hex:   ', txA.toString('hex'));
    console.log('B64:   ', txA.toString('base64'));

    console.log('\n=== TX B: CANCEL_DEPOSIT ===');
    console.log('To:    <LiquidityDeposit addr from tonviewer after TX A>');
    console.log('Value: ', `${Number(CANCEL_GAS) / 1e9} TON`);
    console.log('Hex:   ', txB.toString('hex'));
    console.log('B64:   ', txB.toString('base64'));

    console.log('\n=== CHECKLIST ===');
    console.log('1. Send TX A → find LD addr in tonviewer tx trace');
    console.log('2. npx ts-node scripts/crit02_read_state.ts <addr>');
    console.log('   → expect: isProcessing=false, balance_a>0, balance_b=0');
    console.log('3. Send TX B to LD addr → expect refund of 0.01 TON');
    console.log('4. isProcessing=true test: complete both deposits via DeDust UI,');
    console.log('   then send TX B during LP minting window');
    console.log('   REVERT → КРИТ-02 confirmed | REFUND → safe');
}

main();
