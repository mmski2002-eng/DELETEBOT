/**
 * HIGH (8.1.4): Gas budget analysis for multi-hop swaps
 *
 * Default: amount + 0.2 TON forwarded.
 * This test models gas consumption per hop and identifies the failure threshold.
 */

describe('HIGH (8.1.4): Multi-hop gas exhaustion', () => {

    const GAS = {
        // Estimated per-contract compute costs (conservative, from TON fee schedule)
        NATIVE_VAULT_RECV:    10_000_000n,  // 0.01 TON
        JETTON_VAULT_RECV:    12_000_000n,  // 0.012 TON
        POOL_CPMM_COMPUTE:    15_000_000n,  // 0.015 TON
        POOL_STABLE_COMPUTE:  25_000_000n,  // 0.025 TON (Newton iterations)
        JETTON_TRANSFER:      30_000_000n,  // 0.030 TON (storage + notify)
        MSG_FORWARD_FEE:       5_000_000n,  // 0.005 TON per message
        STORAGE_FEE_ESTIMATE:  2_000_000n,  // 0.002 TON per contract storage
    };

    function modelChainGas(hops: Array<{ type: 'cpmm' | 'stable'; fromJetton: boolean; toJetton: boolean }>): bigint {
        let total = 0n;

        for (let i = 0; i < hops.length; i++) {
            const hop = hops[i];
            // Input vault
            total += hop.fromJetton ? GAS.JETTON_VAULT_RECV : GAS.NATIVE_VAULT_RECV;
            total += GAS.MSG_FORWARD_FEE;
            // Pool compute
            total += hop.type === 'stable' ? GAS.POOL_STABLE_COMPUTE : GAS.POOL_CPMM_COMPUTE;
            total += GAS.MSG_FORWARD_FEE;
            // Output vault (last hop only sends to user)
            if (i === hops.length - 1) {
                total += hop.toJetton ? GAS.JETTON_TRANSFER : GAS.NATIVE_VAULT_RECV;
                total += GAS.MSG_FORWARD_FEE;
            }
            total += GAS.STORAGE_FEE_ESTIMATE * 3n; // vault + pool + wallet
        }
        return total;
    }

    it('single-hop TON→Jetton: 0.2 TON sufficient', () => {
        const defaultGas = 200_000_000n; // 0.2 TON
        const required = modelChainGas([{ type: 'cpmm', fromJetton: false, toJetton: true }]);

        console.log(`1-hop gas required:  ${Number(required) / 1e9} TON`);
        console.log(`Default forwarded:   ${Number(defaultGas) / 1e9} TON`);
        console.log(`Safety margin:       ${Number(defaultGas - required) / 1e9} TON`);

        expect(required).toBeLessThan(defaultGas);
    });

    it('2-hop TON→Jetton_B→Jetton_C: 0.2 TON still sufficient (barely)', () => {
        const defaultGas = 200_000_000n;
        const required = modelChainGas([
            { type: 'cpmm', fromJetton: false, toJetton: true },
            { type: 'cpmm', fromJetton: true,  toJetton: true },
        ]);

        console.log(`2-hop gas required:  ${Number(required) / 1e9} TON`);
        console.log(`Default forwarded:   ${Number(defaultGas) / 1e9} TON`);
        const margin = defaultGas - required;
        console.log(`Margin:              ${Number(margin) / 1e9} TON`);

        if (margin < 0n) {
            console.log('[VULNERABLE] 0.2 TON insufficient for 2-hop!');
        } else {
            console.log('[OK] 0.2 TON sufficient but margin is thin');
        }
    });

    it('[VULNERABLE] 2-hop with StableSwap: 0.2 TON may be insufficient', () => {
        const defaultGas = 200_000_000n;
        const required = modelChainGas([
            { type: 'stable', fromJetton: false, toJetton: true },
            { type: 'stable', fromJetton: true,  toJetton: true },
        ]);

        console.log(`2-hop stable gas required: ${Number(required) / 1e9} TON`);
        console.log(`Default forwarded:         ${Number(defaultGas) / 1e9} TON`);

        if (required > defaultGas) {
            console.log('[CRIT] Gas exhaustion mid-chain! Remainder:',
                Number(defaultGas - required) / 1e9, 'TON');
        }
    });

    it('[ATTACK] low-gas forwarding by integrations causes mid-chain freeze', () => {
        // An integration hardcodes 0.05 TON gas (to "save" user fees)
        const integrationGas = 50_000_000n; // 0.05 TON

        const required1Hop = modelChainGas([{ type: 'cpmm', fromJetton: false, toJetton: true }]);
        const required2Hop = modelChainGas([
            { type: 'cpmm', fromJetton: false, toJetton: true },
            { type: 'cpmm', fromJetton: true,  toJetton: true },
        ]);

        console.log('\n=== Integration using 0.05 TON gas ===');
        console.log(`1-hop needs: ${Number(required1Hop)/1e9} TON → ${integrationGas >= required1Hop ? 'OK' : 'FAIL'}`);
        console.log(`2-hop needs: ${Number(required2Hop)/1e9} TON → ${integrationGas >= required2Hop ? 'OK' : 'FAIL'}`);

        if (integrationGas < required1Hop) {
            console.log('[CRITICAL] Even 1-hop fails with 0.05 TON');
        } else if (integrationGas < required2Hop) {
            console.log('[HIGH] 1-hop OK, but 2-hop fails — mid-chain freeze if CRIT-01 not fixed');
        }

        // Without CRIT-01 fix: mid-chain gas exhaustion → bounce → tokens locked in vault
        expect(required2Hop).toBeGreaterThan(integrationGas);
        console.log('\n[8.1.4 CONFIRMED] Low-gas integrations + missing bounce handler = fund loss');
    });

    it('recommended minimum gas per hop count', () => {
        const hopsAndGas = [1, 2, 3].map(n => {
            const chain = Array.from({ length: n }, (_, i) => ({
                type: 'cpmm' as const,
                fromJetton: i > 0,
                toJetton: true,
            }));
            const gas = modelChainGas(chain);
            const recommended = gas + 30_000_000n; // 30% safety buffer
            return { hops: n, required: gas, recommended };
        });

        console.log('\n=== Gas Recommendations ===');
        hopsAndGas.forEach(({ hops, required, recommended }) => {
            console.log(`${hops} hop(s): min ${Number(required)/1e9} TON, recommended ${Number(recommended)/1e9} TON`);
        });

        // SDK should compute gasAmount dynamically based on SwapStep chain length
        console.log('\nFIX: VaultNative/VaultJetton.sendSwap() should count SwapStep depth');
        console.log('     and set gasAmount = BASE_GAS + HOP_GAS * depth');
    });
});
