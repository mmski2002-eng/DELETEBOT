const fs = require('fs');
const path = require('path');
const { compileFunc } = require('@ton-community/func-js');
const {
    Address,
    Cell,
    Dictionary,
    beginCell,
} = require('@ton/core');
const {
    Blockchain,
    createShardAccount,
} = require('@ton/sandbox');

const ROOT = path.resolve(__dirname, '..');
const TELEMINT_FUNC = path.join(ROOT, 'telemint', 'func');
const DNS_FUNC = path.join(ROOT, 'dns-contract', 'func');

function rawAddress(hexByte) {
    return Address.parseRaw(`0:${hexByte.repeat(64)}`);
}

async function compileFromDir(baseDir, targets, extraSources = {}) {
    const result = await compileFunc({
        targets,
        sources: (filename) => {
            if (filename in extraSources) {
                return extraSources[filename];
            }
            return fs.readFileSync(path.join(baseDir, filename), 'utf8');
        },
    });

    if (result.status === 'error') {
        throw new Error(result.message);
    }

    return Cell.fromBoc(Buffer.from(result.codeBoc, 'base64'))[0];
}

function packTelemintItemConfig(index, collectionAddress) {
    return beginCell()
        .storeUint(index, 256)
        .storeAddress(collectionAddress)
        .endCell();
}

function packTelemintRoyaltyParams(numerator, denominator, destination) {
    return beginCell()
        .storeUint(numerator, 16)
        .storeUint(denominator, 16)
        .storeAddress(destination)
        .endCell();
}

function packTelemintAuctionConfig(beneficiary, initialMinBid, maxBid, minBidStep, minExtendTime, duration) {
    return beginCell()
        .storeAddress(beneficiary)
        .storeCoins(initialMinBid)
        .storeCoins(maxBid)
        .storeUint(minBidStep, 8)
        .storeUint(minExtendTime, 32)
        .storeUint(duration, 32)
        .endCell();
}

function packTelemintLastBid(bidder, bid, bidTs) {
    return beginCell()
        .storeAddress(bidder)
        .storeCoins(bid)
        .storeUint(bidTs, 32)
        .endCell();
}

function packTelemintAuctionState(lastBid, minBid, endTime) {
    return beginCell()
        .storeMaybeRef(lastBid)
        .storeCoins(minBid)
        .storeUint(endTime, 32)
        .endCell();
}

function packTelemintAuction(state, config) {
    return beginCell()
        .storeRef(state)
        .storeRef(config)
        .endCell();
}

function packTelemintContent() {
    return beginCell()
        .storeRef(beginCell().storeStringTail('nft').endCell())
        .storeBit(false)
        .storeRef(beginCell().storeStringTail('token').endCell())
        .endCell();
}

function packTelemintState(owner, content, auction, royalty) {
    return beginCell()
        .storeAddress(owner)
        .storeRef(content)
        .storeMaybeRef(auction)
        .storeRef(royalty)
        .endCell();
}

function packTelemintData(config, state) {
    return beginCell()
        .storeRef(config)
        .storeMaybeRef(state)
        .endCell();
}

function packDnsContent(records = null) {
    const builder = beginCell().storeUint(0, 8);
    if (records) {
        builder.storeDict(records);
    } else {
        builder.storeBit(false);
    }
    return builder.endCell();
}

function packDnsAuction(maxBidAddress, maxBidAmount, auctionEndTime) {
    return beginCell()
        .storeAddress(maxBidAddress)
        .storeCoins(maxBidAmount)
        .storeUint(auctionEndTime, 64)
        .endCell();
}

function packDnsData(index, collectionAddress, ownerAddress, content, domainCell, auction, lastFillUpTime) {
    const builder = beginCell()
        .storeUint(index, 256)
        .storeAddress(collectionAddress)
        .storeAddress(ownerAddress)
        .storeRef(content)
        .storeRef(domainCell)
        .storeBit(!!auction);
    if (auction) {
        builder.storeRef(auction);
    }
    return builder
        .storeUint(lastFillUpTime, 64)
        .endCell();
}

function txSummary(tx) {
    const generic = tx.description.type === 'generic' ? tx.description : null;
    const src = tx.inMessage?.info?.src?.address ?? tx.inMessage?.info?.src ?? null;
    const dest = tx.inMessage?.info?.dest?.address ?? tx.inMessage?.info?.dest ?? null;
    return {
        from: src?.toString?.() ?? null,
        to: dest?.toString?.() ?? null,
        aborted: tx.description.aborted ?? null,
        exitCode: generic?.computePhase.type === 'vm' ? generic.computePhase.exitCode : null,
        actionResultCode: generic?.actionPhase?.resultCode ?? null,
        success: !tx.description.aborted && (generic?.computePhase.type !== 'vm' || generic.computePhase.exitCode === 0) && ((generic?.actionPhase?.resultCode ?? 0) === 0),
    };
}

function findTxOnAddress(transactions, address) {
    return transactions.find((tx) => {
        const dest = tx.inMessage?.info?.dest?.address ?? tx.inMessage?.info?.dest ?? null;
        return dest?.equals?.(address) ?? false;
    });
}

class ExternalOnlyContract {
    constructor(address) {
        this.address = address;
    }

    async sendExternal(provider, body = beginCell().endCell()) {
        await provider.external(body);
    }

    async getAuctionState(provider) {
        const res = await provider.get('get_telemint_auction_state', []);
        const stack = res.stack;
        return {
            bidder: stack.readAddressOpt(),
            bid: stack.readBigNumber(),
            bidTs: stack.readBigNumber(),
            minBid: stack.readBigNumber(),
            endTime: stack.readBigNumber(),
        };
    }

    async getNftData(provider) {
        const res = await provider.get('get_nft_data', []);
        const stack = res.stack;
        return {
            init: stack.readBigNumber(),
            index: stack.readBigNumber(),
            collection: stack.readAddressOpt(),
            owner: stack.readAddressOpt(),
            content: stack.readCellOpt(),
        };
    }
}

class DnsItemContract {
    constructor(address) {
        this.address = address;
    }

    async sendInternalBid(provider, via, value) {
        await provider.internal(via, {
            value,
            body: beginCell().endCell(),
        });
    }

    async getAuctionInfo(provider) {
        const res = await provider.get('get_auction_info', []);
        const stack = res.stack;
        return {
            bidder: stack.readAddressOpt(),
            bid: stack.readBigNumber(),
            endTime: stack.readBigNumber(),
        };
    }

    async getNftData(provider) {
        const res = await provider.get('get_nft_data', []);
        const stack = res.stack;
        return {
            init: stack.readBigNumber(),
            index: stack.readBigNumber(),
            collection: stack.readAddressOpt(),
            owner: stack.readAddressOpt(),
            content: stack.readCellOpt(),
        };
    }
}

async function runFinding2() {
    const blockchain = await Blockchain.create();
    blockchain.verbosity = { print: false, blockchainLogs: false, vmLogs: 'none', debugLogs: false };
    blockchain.now = 1_700_000_100;

    const telemintCode = await compileFromDir(TELEMINT_FUNC, ['stdlib.fc', 'common.fc', 'nft-item-no-dns.fc']);
    const badReceiverCode = await compileFromDir(TELEMINT_FUNC, ['stdlib.fc', 'bad-receiver.fc'], {
        'bad-receiver.fc': `
            () recv_internal(int msg_value, cell in_msg_full, slice in_msg_body) impure {
                throw(777);
            }
        `,
    });

    const collectionAddress = rawAddress('1');
    const sellerAddress = rawAddress('2');
    const beneficiaryAddress = rawAddress('3');
    const itemAddress = rawAddress('4');
    const badReceiverAddress = rawAddress('5');

    const royalty = packTelemintRoyaltyParams(0, 1, beneficiaryAddress);
    const auctionConfig = packTelemintAuctionConfig(beneficiaryAddress, 2_000_000_000n, 0n, 5, 3600, 86400);
    const lastBid = packTelemintLastBid(badReceiverAddress, 5_000_000_000n, 1_700_000_000);
    const auctionState = packTelemintAuctionState(lastBid, 5_100_000_000n, 1_700_000_000);
    const auction = packTelemintAuction(auctionState, auctionConfig);
    const content = packTelemintContent();
    const state = packTelemintState(sellerAddress, content, auction, royalty);
    const config = packTelemintItemConfig(777n, collectionAddress);
    const data = packTelemintData(config, state);

    await blockchain.setShardAccount(itemAddress, createShardAccount({
        address: itemAddress,
        code: telemintCode,
        data,
        balance: 8_000_000_000n,
    }));

    await blockchain.setShardAccount(badReceiverAddress, createShardAccount({
        address: badReceiverAddress,
        code: badReceiverCode,
        data: beginCell().endCell(),
        balance: 1_000_000_000n,
    }));

    const item = blockchain.openContract(new ExternalOnlyContract(itemAddress));
    const res = await item.sendExternal(beginCell().endCell());
    const nftData = await item.getNftData();

    const itemTx = findTxOnAddress(res.transactions, itemAddress);
    const badReceiverTx = findTxOnAddress(res.transactions, badReceiverAddress);

    return {
        senderTx: itemTx ? txSummary(itemTx) : null,
        receiverTx: badReceiverTx ? txSummary(badReceiverTx) : null,
        finalOwner: nftData.owner?.toString() ?? null,
        auctionCleared: await (async () => {
            try {
                await item.getAuctionState();
                return false;
            } catch {
                return true;
            }
        })(),
        transactionsCount: res.transactions.length,
        allTransactions: res.transactions.map(txSummary),
    };
}

async function runFinding3() {
    const blockchain = await Blockchain.create();
    blockchain.verbosity = { print: false, blockchainLogs: false, vmLogs: 'none', debugLogs: false };
    blockchain.now = 1_700_001_000;

    const dnsCode = await compileFromDir(DNS_FUNC, ['stdlib.fc', 'params.fc', 'op-codes.fc', 'dns-utils.fc', 'nft-item.fc']);
    const badReceiverCode = await compileFromDir(DNS_FUNC, ['stdlib.fc', 'bad-receiver.fc'], {
        'bad-receiver.fc': `
            () recv_internal(int msg_value, cell in_msg_full, slice in_msg_body) impure {
                accept_message();
                throw(777);
            }
        `,
    });

    const collectionAddress = rawAddress('6');
    const ownerAddress = rawAddress('7');
    const itemAddress = rawAddress('8');
    const badReceiverAddress = rawAddress('9');
    const honestBidder = await blockchain.treasury('honest-bidder');

    const content = packDnsContent();
    const domainCell = beginCell().storeStringTail('alice').endCell();
    const auction = packDnsAuction(badReceiverAddress, 1_000_000_000n, BigInt(blockchain.now + 3600));
    const data = packDnsData(123n, collectionAddress, ownerAddress, content, domainCell, auction, BigInt(blockchain.now));

    await blockchain.setShardAccount(itemAddress, createShardAccount({
        address: itemAddress,
        code: dnsCode,
        data,
        balance: 3_000_000_000n,
    }));

    await blockchain.setShardAccount(badReceiverAddress, createShardAccount({
        address: badReceiverAddress,
        code: badReceiverCode,
        data: beginCell().endCell(),
        balance: 1_000_000_000n,
    }));

    const item = blockchain.openContract(new DnsItemContract(itemAddress));
    const res = await item.sendInternalBid(honestBidder.getSender(), 1_100_000_000n);
    const auctionInfo = await item.getAuctionInfo();

    const itemTx = findTxOnAddress(res.transactions, itemAddress);
    const badReceiverTx = findTxOnAddress(res.transactions, badReceiverAddress);

    return {
        senderTx: itemTx ? txSummary(itemTx) : null,
        receiverTx: badReceiverTx ? txSummary(badReceiverTx) : null,
        newBidder: auctionInfo.bidder?.toString() ?? null,
        newBid: auctionInfo.bid.toString(),
        transactionsCount: res.transactions.length,
        allTransactions: res.transactions.map(txSummary),
    };
}

async function runFinding4() {
    const dnsCode = await compileFromDir(DNS_FUNC, ['stdlib.fc', 'params.fc', 'op-codes.fc', 'dns-utils.fc', 'nft-item.fc']);
    const blockchain = await Blockchain.create();
    blockchain.verbosity = { print: false, blockchainLogs: false, vmLogs: 'none', debugLogs: false };

    const collectionAddress = rawAddress('a');
    const ownerAddress = rawAddress('b');
    const itemAddress = rawAddress('c');

    const malformedRecord = beginCell()
        .storeUint(0xffff, 16)
        .storeRef(beginCell().storeStringTail('not-a-standard-dns-record').endCell())
        .storeRef(beginCell().storeUint(123456, 32).endCell())
        .endCell();

    const records = Dictionary.empty(Dictionary.Keys.BigUint(256), Dictionary.Values.Cell());
    records.set(0xdeadn, malformedRecord);
    const content = packDnsContent(records);

    const domainCell = beginCell().storeStringTail('alice').endCell();
    const data = packDnsData(456n, collectionAddress, ownerAddress, content, domainCell, null, 0n);

    await blockchain.setShardAccount(itemAddress, createShardAccount({
        address: itemAddress,
        code: dnsCode,
        data,
        balance: 2_000_000_000n,
    }));

    const item = blockchain.openContract(new DnsItemContract(itemAddress));
    const nftData = await item.getNftData();

    return {
        owner: nftData.owner?.toString() ?? null,
        contentHash: nftData.content?.hash().toString('hex') ?? null,
        malformedRecordHash: malformedRecord.hash().toString('hex'),
        acceptedMalformedContent: !!nftData.content,
        note: 'Contract storage accepted arbitrary record cell shape; parser-differential testing still required for wallet/explorer impact.',
    };
}

async function main() {
    const finding2 = await runFinding2();
    const finding3 = await runFinding3();
    const finding4 = await runFinding4();

    console.log(JSON.stringify({ finding2, finding3, finding4 }, null, 2));
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
