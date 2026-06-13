import {
    Address, beginCell, Cell, Contract, ContractProvider,
    contractAddress, Sender, toNano
} from '@ton/core';

export class MockPool implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

    static createFromAddress(address: Address) {
        return new MockPool(address);
    }

    static createFromInit(code: Cell, reject = false) {
        const data = beginCell().storeUint(reject ? 1 : 0, 1).endCell();
        const init = { code, data };
        return new MockPool(contractAddress(0, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender) {
        await provider.internal(via, {
            value: toNano('0.5'),
            sendMode: 1,
            body: beginCell().endCell(),
        });
    }

    async sendSetRejectMode(provider: ContractProvider, via: Sender, reject: boolean) {
        await provider.internal(via, {
            value: toNano('0.05'),
            sendMode: 1,
            body: beginCell()
                .storeUint(0xAAAAAAAA, 32)
                .storeUint(0n, 64)
                .storeUint(reject ? 1 : 0, 1)
            .endCell(),
        });
    }

    async getShouldReject(provider: ContractProvider): Promise<boolean> {
        const res = await provider.get('get_should_reject', []);
        return res.stack.readNumber() !== 0;
    }
}
