/**
 * Phase 8.3 — Mainnet bytecode analysis
 * Checks presence/absence of bounce handler (flags & 1) in DeDust contracts.
 *
 * TVM instructions are bit-packed inside cells; byte-level hex search misses
 * patterns that start on non-byte boundaries.  We scan ALL bit-offsets.
 */

import { Cell, beginCell } from '@ton/core';
import * as fs from 'fs';

const FACTORY_ADDR = 'EQBfBWT7X2BHg9tXAxzhz2aKiNTU1tpt5NsiK0uSDW_YAJ67';
const NATIVE_VAULT = 'EQDa4VOnTYlLvDJ0gZjNYm5PXfSmmtL6Vs6A_CZEtXCNICq_';
const JETTON_VAULT = 'EQAQd6pQ8cd-Q_Ho0ic1uA6anFjQkHKGpfCO1najOSaaJuH4';

async function fetchCode(addr: string): Promise<string> {
    const r = await fetch(`https://toncenter.com/api/v2/getAddressInformation?address=${addr}`);
    const d: any = await r.json();
    return d?.result?.code ?? '';
}

/** Collect all bits from the entire cell tree (DFS, refs flattened) */
function collectAllBits(cell: Cell): string {
    let bits = cell.bits.toString(); // hex string representing bits
    // bits.toString() returns hex, each char = 4 bits
    // Convert to binary string
    let bin = '';
    for (const ch of bits) {
        bin += parseInt(ch, 16).toString(2).padStart(4, '0');
    }
    // Trim to actual bit count
    bin = bin.slice(0, cell.bits.length);
    // Recurse into refs
    for (const ref of cell.refs) {
        bin += collectAllBits(ref);
    }
    return bin;
}

/** Search for a bit pattern (given as binary string) at every offset */
function bitSearch(haystack: string, needle: string): number[] {
    const positions: number[] = [];
    let idx = haystack.indexOf(needle);
    while (idx !== -1) {
        positions.push(idx);
        idx = haystack.indexOf(needle, idx + 1);
    }
    return positions;
}

function toBin(hex: string): string {
    let bin = '';
    for (const ch of hex) bin += parseInt(ch, 16).toString(2).padStart(4, '0');
    return bin;
}

// TVM opcodes as binary strings
const OPC = {
    // LDU n = 0xD0 (n-1),  LDU 4 = 0xD003
    LDU4:      toBin('D003'),      // 1101000000000011
    // LDSLICE n = 0xD7 0x2C (n-1) for loading slice;  alternate form for flags
    CTOS:      toBin('D7'),        // 11010111  cell-to-slice
    PUSHINT1:  toBin('71'),        // 01110001  PUSHINT 1 (4-bit signed form: 0111 xxxx where xxxx=value-1? actually 71 = 0111 0001)
    AND:       toBin('B0'),        // 10110000
    IFJMP:     toBin('DE'),        // 11011110
    IFNOTJMP:  toBin('DC'),        // 11011100
    // LDUX = D1 (load n-bit uint, n from stack) — less common here
    LDUX:      toBin('D1'),
};

function analyzeContract(name: string, boc: string): void {
    if (!boc) { console.log(`\n=== ${name} ===\n  NO CODE`); return; }

    const cell = Cell.fromBase64(boc);
    const allBits = collectAllBits(cell);
    const b64len = boc.length;

    console.log(`\n=== ${name} ===`);
    console.log(`  BOC base64 len   : ${b64len} chars (~${Math.floor(b64len*3/4)} bytes)`);
    console.log(`  Total cell bits  : ${allBits.length}`);

    // Search for patterns at all bit offsets
    const ldu4    = bitSearch(allBits, OPC.LDU4);
    const pushAnd = bitSearch(allBits, OPC.PUSHINT1 + OPC.AND);
    const ifjmp   = bitSearch(allBits, OPC.IFJMP);
    const ifnotjmp= bitSearch(allBits, OPC.IFNOTJMP);
    const ctos    = bitSearch(allBits, OPC.CTOS);

    console.log(`  CTOS (D7)        : ${ctos.length} hits at bits [${ctos.slice(0,5).join(',')}]`);
    console.log(`  LDU 4 (D003)     : ${ldu4.length} hits at bits [${ldu4.slice(0,5).join(',')}]`);
    console.log(`  PUSHINT1+AND(71B0): ${pushAnd.length} hits at bits [${pushAnd.slice(0,5).join(',')}]`);
    console.log(`  IFJMP (DE)       : ${ifjmp.length} hits at bits [${ifjmp.slice(0,5).join(',')}]`);
    console.log(`  IFNOTJMP (DC)    : ${ifnotjmp.length} hits at bits [${ifnotjmp.slice(0,5).join(',')}]`);

    // Check for 0xffffffff constant (bounce prefix in body)
    const ffff = bitSearch(allBits, '1'.repeat(32));
    console.log(`  0xffffffff const : ${ffff.length} hits`);

    // Check for op 0x11111111 (pool_swap_internal in fixed vault)
    const op11 = bitSearch(allBits, toBin('11111111'));
    console.log(`  op 0x11111111    : ${op11.length} hits`);

    // Bounce handler heuristic:
    // Must have: LDU 4 (load flags), PUSHINT 1 + AND (flags & 1), IFJMP (branch on bounced)
    const hasLDU4    = ldu4.length > 0;
    const hasAND1    = pushAnd.length > 0;
    const hasIFJMP   = ifjmp.length > 0;
    const bounceOk   = hasLDU4 && hasAND1 && hasIFJMP;

    console.log(`  >> Bounce handler: ${bounceOk ? 'LIKELY PRESENT ✓' : 'LIKELY ABSENT — VULNERABLE ✗'}`);
    if (!hasLDU4)  console.log(`     ⚠ LDU 4 not found (flags~load_uint(4) missing?)`);
    if (!hasAND1)  console.log(`     ⚠ PUSHINT1+AND not found (flags & 1 check missing?)`);
    if (!hasIFJMP) console.log(`     ⚠ IFJMP not found (branch on bounced missing?)`);
}

async function main() {
    console.log('=== Phase 8.3: DeDust Mainnet Bytecode Analysis ===');
    console.log('Bit-level scan across full cell tree\n');

    const [factoryBoc, nativeVaultBoc, jettonVaultBoc] = await Promise.all([
        Promise.resolve(fs.readFileSync('phase83_factory_boc.txt', 'utf8').trim()),
        Promise.resolve(fs.readFileSync('phase83_native_vault_boc.txt', 'utf8').trim()),
        Promise.resolve(fs.readFileSync('phase83_jetton_vault_boc.txt', 'utf8').trim()),
    ]);

    analyzeContract('Factory', factoryBoc);
    analyzeContract('NativeVault (TON)', nativeVaultBoc);
    analyzeContract('JettonVault (USDT)', jettonVaultBoc);

    console.log('\n=== Summary ===');
    console.log('TVM bounce-handler pattern: CTOS → LDU 4 → PUSHINT 1 → AND → IFJMP');
    console.log('Vulnerability (CRIT-01): vault locks tokens on swap but lacks bounce handler →');
    console.log('  if pool rejects swap, locked amount stays > 0, user funds permanently locked.');
}

main().catch(console.error);
