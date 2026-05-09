import {
    Address, beginCell, Cell, Contract, ContractProvider,
    contractAddress, Sender, toNano
} from '@ton/core';

export class MockVaultBuggy implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

    static createFromAddress(address: Address) {
        return new MockVaultBuggy(address);
    }

    static createFromInit(code: Cell, deployer: Address) {
        const data = beginCell().storeCoins(0).storeAddress(deployer).endCell();
        const init = { code, data };
        return new MockVaultBuggy(contractAddress(0, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender) {
        await provider.internal(via, {
            value: toNano('0.5'),
            sendMode: 1,
            body: beginCell().endCell(),
        });
    }

    async sendSwap(provider: ContractProvider, via: Sender, opts: {
        amount: bigint;
        poolAddress: Address;
        queryId?: bigint;
    }) {
        await provider.internal(via, {
            value: opts.amount + toNano('0.2'),
            sendMode: 1,
            body: beginCell()
                .storeUint(0xea06185d, 32)
                .storeUint(opts.queryId ?? 0n, 64)
                .storeCoins(opts.amount)
                .storeAddress(opts.poolAddress)
                .storeAddress(via.address!)
            .endCell(),
        });
    }

    async getLockedAmount(provider: ContractProvider): Promise<bigint> {
        const res = await provider.get('get_locked', []);
        return res.stack.readBigNumber();
    }
}
