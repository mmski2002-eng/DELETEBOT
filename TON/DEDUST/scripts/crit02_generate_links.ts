import { Address, beginCell, toNano } from '@ton/core';
import { Asset, PoolType } from '@dedust/sdk';
import * as fs from 'fs';
import * as path from 'path';

const OP_DEPOSIT_LIQUIDITY = 0xd55e4686;
const OP_CANCEL_DEPOSIT    = 0x166cedee;

const NATIVE_VAULT = 'EQDa4VOnTYlLvDJ0gZjNYm5PXfSmmtL6Vs6A_CZEtXCNICq_';

const TON_ASSET  = Asset.native();
const USDT_ASSET = Asset.jetton(Address.parse('EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs'));

const DEPOSIT_NANO = toNano('0.001');
const GAS_NANO     = toNano('0.3');
const CANCEL_GAS   = toNano('0.1');

function buildDepositA(): Buffer {
    return beginCell()
        .storeUint(OP_DEPOSIT_LIQUIDITY, 32)
        .storeUint(0n, 64)
        .storeCoins(DEPOSIT_NANO)
        .storeUint(PoolType.VOLATILE, 1)
        .storeSlice(TON_ASSET.toSlice())
        .storeSlice(USDT_ASSET.toSlice())
        .storeRef(
            beginCell()
                .storeCoins(0)
                .storeCoins(DEPOSIT_NANO)
                .storeCoins(0)
            .endCell()
        )
        .storeMaybeRef(null)
        .storeMaybeRef(null)
        .endCell()
        .toBoc();
}

function buildCancelDeposit(): Buffer {
    return beginCell()
        .storeUint(OP_CANCEL_DEPOSIT, 32)
        .storeUint(0n, 64)
        .storeBit(0)
        .endCell()
        .toBoc();
}

function link(to: string, amountNano: bigint, boc: Buffer): string {
    return `https://app.tonkeeper.com/transfer/${to}?amount=${amountNano}&bin=${encodeURIComponent(boc.toString('base64'))}`;
}

function main() {
    const txABoc = buildDepositA();
    const txBBoc = buildCancelDeposit();

    const out = {
        purpose: 'КРИТ-02 on-chain verification: async add_liquidity race condition',
        network: 'mainnet',
        nativeVault: NATIVE_VAULT,
        pair: 'TON / USDt (EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs)',
        amounts: {
            depositTON: '0.001',
            gasTON: '0.3',
            cancelGasTON: '0.1',
        },
        expectedFlow: [
            '1. Open txALink → sends 0.01 TON deposit_a to NativeVault (value: 0.31 TON total)',
            '2. Find LiquidityDeposit addr in tonviewer tx trace',
            '3. npx ts-node scripts/crit02_read_state.ts <addr>',
            '   → expect: isProcessing=false, balance_a>0, balance_b=0',
            '4. Replace LIQUIDITY_DEPOSIT_ADDR_HERE in txBLink with real LD address',
            '5. Open txBLink → CANCEL_DEPOSIT (0x166cedee), value 0.1 TON',
            '   → expect: refund of 0.01 TON back to wallet (basic cancel)',
            '6. isProcessing=true test: redo step 1 + complete deposit_b via DeDust UI',
            '   Send TX B during LP minting window',
            '   REVERT → КРИТ-02 confirmed | REFUND → safe',
        ],
        txALink: link(NATIVE_VAULT, DEPOSIT_NANO + GAS_NANO, txABoc),
        txBLink_REPLACE_ADDR: link('LIQUIDITY_DEPOSIT_ADDR_HERE', CANCEL_GAS, txBBoc),
    };

    const outPath = path.join(__dirname, '..', 'crit02_mainnet_links.json');
    fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
    console.log('Written:', outPath);
    console.log('\ntxALink:', out.txALink);
}

main();
