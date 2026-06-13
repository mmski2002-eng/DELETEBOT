const fs = require('fs');
const path = require('path');
const https = require('https');
const crypto = require('crypto');
const nacl = require('tweetnacl');
const { compileFunc } = require('@ton-community/func-js');
const {
    Address,
    Cell,
    beginCell,
    contractAddress,
} = require('@ton/core');
const {
    Blockchain,
    createShardAccount,
} = require('@ton/sandbox');

const ROOT = path.resolve(__dirname, '..');
const TELEMINT_FUNC = path.join(ROOT, 'telemint', 'func');
const OP_TELEMINT_DEPLOY_V2 = 0x4637289b;
const WORKCHAIN = 0;

const PRODUCTION_COLLECTIONS = [
    { name: 'Anonymous Telegram Numbers', address: 'EQAOQdwdw8kGftJCSFgOErM1mBjYPe4DBPq8-AhF6vr9si5N' },
    { name: 'Telegram Usernames', address: 'EQCA14o1-VWhS2efqoh_9M1b_A9DtKTuoqfmkn83AbJzwnPi' },
    { name: 'Snoop Doggs', address: 'EQAoJw7BpOcBD3y9voMuEQ-qhS3K4gtM-6EePLxkzk8iSifX' },
    { name: 'Heart Lockets', address: 'EQC4XEulxb05Le5gF6esMtDWT5XZ6tlzlMBQGNsqffxpdC5U' },
    { name: 'Precious Peaches', address: 'EQA4i58iuS9DUYRtUZ97sZo5mnkbiYUBpWXQOe3dEUCcP1W8' },
    { name: 'Snow Globes', address: 'EQAPNu648fe_uqUoeH6V_-fIDJYea_5Xu2rXn6iZFil49bMY' },
    { name: 'Xmas Stockings', address: 'EQDz_VecErEBTLOTiR1tq0VS3lZuHHqhYmhZbthcrbFk7ztK' },
    { name: 'Jacks-in-the-Box', address: 'EQA401QqpXtBnwIaDbFjwd5yXfP2mYiCusbJ3Zcw9eXR9CqL' },
    { name: 'Genie Lamps', address: 'EQCt2C3yCRNX267B3l6h1QsU6agm4ZgTAb7NpVGiFKlBXOAA' },
];

function rawAddress(hexByte) {
    return Address.parseRaw(`0:${hexByte.repeat(64)}`);
}

function sha256BigInt(text) {
    return BigInt(`0x${crypto.createHash('sha256').update(Buffer.from(text, 'utf8')).digest('hex')}`);
}

async function compileFromDir(baseDir, targets) {
    const result = await compileFunc({
        targets,
        sources: (filename) => fs.readFileSync(path.join(baseDir, filename), 'utf8'),
    });

    if (result.status === 'error') {
        throw new Error(result.message);
    }

    return Cell.fromBoc(Buffer.from(result.codeBoc, 'base64'))[0];
}

function loadFuncText(refCell) {
    const s = refCell.beginParse();
    const len = Number(s.loadUint(8));
    return s.loadBuffer(len).toString('utf8');
}

function storeFuncText(builder, text) {
    const data = Buffer.from(text, 'utf8');
    return builder.storeUint(data.length, 8).storeBuffer(data);
}

function packTextRef(text) {
    return storeFuncText(beginCell(), text).endCell();
}

function packRoyaltyParams(numerator, denominator, destination) {
    return beginCell()
        .storeUint(numerator, 16)
        .storeUint(denominator, 16)
        .storeAddress(destination)
        .endCell();
}

function packAuctionConfig(beneficiary, initialMinBid, maxBid, minBidStep, minExtendTime, duration) {
    return beginCell()
        .storeAddress(beneficiary)
        .storeCoins(initialMinBid)
        .storeCoins(maxBid)
        .storeUint(minBidStep, 8)
        .storeUint(minExtendTime, 32)
        .storeUint(duration, 32)
        .endCell();
}

function packCollectionContent(url) {
    return beginCell()
        .storeRef(beginCell().storeStringTail(url).endCell())
        .endCell();
}

function packCollectionData({ touched, subwalletId, publicKey, content, itemCode, fullDomain, royaltyParams }) {
    return beginCell()
        .storeInt(touched ? -1 : 0, 1)
        .storeUint(subwalletId, 32)
        .storeBuffer(publicKey)
        .storeRef(content)
        .storeRef(itemCode)
        .storeRef(packTextRef(fullDomain))
        .storeRef(royaltyParams)
        .endCell();
}

function packRestrictions(forceSenderAddress, rewriteSenderAddress) {
    return beginCell()
        .storeBit(!!forceSenderAddress)
        .storeAddress(forceSenderAddress ?? null)
        .storeBit(!!rewriteSenderAddress)
        .storeAddress(rewriteSenderAddress ?? null)
        .endCell();
}

function packUnsignedDeployV2({ subwalletId, validSince, validTill, tokenName, content, auctionConfig, royaltyParams, restrictions }) {
    return storeFuncText(
        beginCell()
            .storeUint(subwalletId, 32)
            .storeUint(validSince, 32)
            .storeUint(validTill, 32),
        tokenName,
    )
        .storeRef(content)
        .storeRef(auctionConfig)
        .storeMaybeRef(royaltyParams)
        .storeMaybeRef(restrictions)
        .endCell();
}

function signDeployV2(unsignedDeploy, secretKey) {
    const signature = nacl.sign.detached(unsignedDeploy.hash(), secretKey);
    return beginCell()
        .storeUint(OP_TELEMINT_DEPLOY_V2, 32)
        .storeBuffer(Buffer.from(signature))
        .storeSlice(unsignedDeploy.beginParse())
        .endCell();
}

function packItemConfig(index, collectionAddress) {
    return beginCell()
        .storeUint(index, 256)
        .storeAddress(collectionAddress)
        .endCell();
}

function packItemData(index, collectionAddress) {
    return beginCell()
        .storeRef(packItemConfig(index, collectionAddress))
        .storeBit(false)
        .endCell();
}

function calculateItemAddress(index, collectionAddress, itemCode) {
    return contractAddress(WORKCHAIN, {
        code: itemCode,
        data: packItemData(index, collectionAddress),
    });
}

function parseTokenInfo(contentCell) {
    if (!contentCell) {
        return null;
    }
    const contentSlice = contentCell.beginParse();
    contentSlice.loadRef();
    contentSlice.loadMaybeRef();
    const tokenInfo = contentSlice.loadRef();
    const tokenSlice = tokenInfo.beginParse();
    const nameLen = Number(tokenSlice.loadUint(8));
    const name = tokenSlice.loadBuffer(nameLen).toString('utf8');
    const domainLen = Number(tokenSlice.loadUint(8));
    const domain = tokenSlice.loadBuffer(domainLen).toString('utf8');
    return { name, domain };
}

function listTransactionDestinations(transactions) {
    return transactions.map((tx) => {
        const dest = tx.inMessage?.info?.dest?.address ?? tx.inMessage?.info?.dest ?? null;
        return dest?.toString?.() ?? null;
    });
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

function getJson(url) {
    return new Promise((resolve, reject) => {
        https.get(url, { headers: { accept: 'application/json' } }, (res) => {
            let data = '';
            res.on('data', (chunk) => {
                data += chunk;
            });
            res.on('end', () => {
                if (res.statusCode !== 200) {
                    reject(new Error(`${res.statusCode} ${data.slice(0, 200)}`));
                    return;
                }
                resolve(JSON.parse(data));
            });
        }).on('error', reject);
    });
}

class CollectionContract {
    constructor(address) {
        this.address = address;
    }

    async sendInternal(provider, via, value, body) {
        await provider.internal(via, {
            value,
            body,
        });
    }
}

async function fetchProductionCollection(collection) {
    const account = await getJson(`https://tonapi.io/v2/blockchain/accounts/${collection.address}`);
    const data = Cell.fromBoc(Buffer.from(account.data, 'hex'))[0];
    const code = Cell.fromBoc(Buffer.from(account.code, 'hex'))[0];
    const cs = data.beginParse();
    const touched = Number(cs.loadInt(1));
    const subwalletId = Number(cs.loadUint(32));
    const publicKey = cs.loadBuffer(32).toString('hex');
    const content = cs.loadRef();
    const itemCode = cs.loadRef();
    const fullDomain = loadFuncText(cs.loadRef());
    return {
        name: collection.name,
        address: collection.address,
        touched,
        subwalletId,
        publicKey,
        fullDomainUtf8: JSON.stringify(fullDomain),
        codeHash: code.hash().toString('hex'),
        itemCodeHash: itemCode.hash().toString('hex'),
        contentHash: content.hash().toString('hex'),
    };
}

function parseTeleitemDeployBody(bodyCell) {
    const body = bodyCell.beginParse();
    const op = body.loadUint(32);
    const sender = body.loadAddress();
    const bid = body.loadCoins();
    const tokenInfo = body.loadRef().beginParse();
    const nameLen = Number(tokenInfo.loadUint(8));
    const name = tokenInfo.loadBuffer(nameLen).toString('utf8');
    const domainLen = Number(tokenInfo.loadUint(8));
    const domain = tokenInfo.loadBuffer(domainLen).toString('utf8');
    return {
        op,
        sender: sender?.toString?.() ?? null,
        bid: bid.toString(),
        tokenInfo: { name, domain },
    };
}

async function fetchProductionEventSample(address) {
    const data = await getJson(`https://tonapi.io/v2/accounts/${address}/events?limit=3`);
    const exec = data.events
        .flatMap((event) => event.actions)
        .find((action) => action.type === 'SmartContractExec' && action.SmartContractExec?.operation === 'TelemintDeployV2');
    if (!exec) {
        return null;
    }
    const payload = exec.SmartContractExec.payload;
    const subwalletMatch = payload.match(/SubwalletId: (\d+)/);
    const forceMatch = payload.match(/ForceSenderAddress: ([^\n]+)/);
    const rewriteMatch = payload.match(/RewriteSenderAddress: ([^\n]+)/);
    return {
        executor: exec.SmartContractExec.executor?.name ?? exec.SmartContractExec.executor?.address ?? null,
        contract: exec.SmartContractExec.contract?.name ?? exec.SmartContractExec.contract?.address ?? null,
        subwalletId: subwalletMatch ? Number(subwalletMatch[1]) : null,
        forceSenderAddress: forceMatch ? forceMatch[1].trim() : null,
        rewriteSenderAddress: rewriteMatch ? rewriteMatch[1].trim() : null,
    };
}

async function runSandboxReplay() {
    const blockchain = await Blockchain.create();
    blockchain.verbosity = { print: false, blockchainLogs: false, vmLogs: 'none', debugLogs: false };
    blockchain.now = 1_800_000_000;

    const collectionCode = await compileFromDir(TELEMINT_FUNC, ['stdlib.fc', 'common.fc', 'nft-collection-no-dns.fc']);
    const itemCode = await compileFromDir(TELEMINT_FUNC, ['stdlib.fc', 'common.fc', 'nft-item-no-dns.fc']);

    const signingKeys = nacl.sign.keyPair.fromSeed(new Uint8Array(32).fill(7));
    const publicKey = Buffer.from(signingKeys.publicKey);
    const subwalletId = 777;
    const tokenName = 'round2-proof';
    const itemIndex = sha256BigInt(tokenName);

    const collectionAAddress = rawAddress('1');
    const collectionBAddress = rawAddress('2');
    const collectionCAddress = rawAddress('3');
    const beneficiaryAddress = rawAddress('4');
    const royaltyDestination = rawAddress('5');
    const user = await blockchain.treasury('round2-user');
    const senderAddress = user.address;

    const royalty = packRoyaltyParams(5, 100, royaltyDestination);
    const auctionConfig = packAuctionConfig(beneficiaryAddress, 100_000_000n, 100_000_000n, 5, 300, 3600);
    const content = beginCell().storeStringTail('https://example.com/round2-proof.json').endCell();
    const restrictions = packRestrictions(senderAddress, beneficiaryAddress);
    const unsignedDeploy = packUnsignedDeployV2({
        subwalletId,
        validSince: blockchain.now - 60,
        validTill: blockchain.now + 3600,
        tokenName,
        content,
        auctionConfig,
        royaltyParams: null,
        restrictions,
    });
    const body = signDeployV2(unsignedDeploy, signingKeys.secretKey);

    const collectionBase = {
        touched: true,
        publicKey,
        content: packCollectionContent('https://example.com/collection.json'),
        itemCode,
        royaltyParams: royalty,
    };

    await blockchain.setShardAccount(collectionAAddress, createShardAccount({
        address: collectionAAddress,
        code: collectionCode,
        data: packCollectionData({
            ...collectionBase,
            subwalletId,
            fullDomain: 'numbers',
        }),
        balance: 10_000_000_000n,
    }));

    await blockchain.setShardAccount(collectionBAddress, createShardAccount({
        address: collectionBAddress,
        code: collectionCode,
        data: packCollectionData({
            ...collectionBase,
            subwalletId,
            fullDomain: 'other',
        }),
        balance: 10_000_000_000n,
    }));

    await blockchain.setShardAccount(collectionCAddress, createShardAccount({
        address: collectionCAddress,
        code: collectionCode,
        data: packCollectionData({
            ...collectionBase,
            subwalletId: subwalletId + 1,
            fullDomain: 'control',
        }),
        balance: 10_000_000_000n,
    }));

    const collectionA = blockchain.openContract(new CollectionContract(collectionAAddress));
    const collectionB = blockchain.openContract(new CollectionContract(collectionBAddress));
    const collectionC = blockchain.openContract(new CollectionContract(collectionCAddress));

    const itemAAddress = calculateItemAddress(itemIndex, collectionAAddress, itemCode);
    const itemBAddress = calculateItemAddress(itemIndex, collectionBAddress, itemCode);
    const itemCAddress = calculateItemAddress(itemIndex, collectionCAddress, itemCode);

    const resA = await collectionA.sendInternal(user.getSender(), 1_000_000_000n, body);
    const resB = await collectionB.sendInternal(user.getSender(), 1_000_000_000n, body);
    const resC = await collectionC.sendInternal(user.getSender(), 1_000_000_000n, body);

    const collectionATx = findTxOnAddress(resA.transactions, collectionAAddress);
    const collectionBTx = findTxOnAddress(resB.transactions, collectionBAddress);
    const collectionCTx = findTxOnAddress(resC.transactions, collectionCAddress);
    const itemATx = findTxOnAddress(resA.transactions, itemAAddress);
    const itemBTx = findTxOnAddress(resB.transactions, itemBAddress);

    return {
        samePayloadHash: unsignedDeploy.hash().toString('hex'),
        replayToA: {
            collectionTx: collectionATx ? txSummary(collectionATx) : null,
            itemTx: itemATx ? txSummary(itemATx) : null,
            itemAddress: itemAAddress.toString(),
            teleitemDeploy: itemATx?.inMessage?.body ? parseTeleitemDeployBody(itemATx.inMessage.body) : null,
            transactions: listTransactionDestinations(resA.transactions),
        },
        replayToB: {
            collectionTx: collectionBTx ? txSummary(collectionBTx) : null,
            itemTx: itemBTx ? txSummary(itemBTx) : null,
            itemAddress: itemBAddress.toString(),
            teleitemDeploy: itemBTx?.inMessage?.body ? parseTeleitemDeployBody(itemBTx.inMessage.body) : null,
            transactions: listTransactionDestinations(resB.transactions),
        },
        controlToC: {
            collectionTx: collectionCTx ? txSummary(collectionCTx) : null,
            expectedItemAddress: itemCAddress.toString(),
            transactions: listTransactionDestinations(resC.transactions),
        },
    };
}

async function main() {
    const production = [];
    for (const collection of PRODUCTION_COLLECTIONS) {
        production.push(await fetchProductionCollection(collection));
    }

    const xmasEvent = await fetchProductionEventSample('EQDz_VecErEBTLOTiR1tq0VS3lZuHHqhYmhZbthcrbFk7ztK');
    const sandbox = await runSandboxReplay();

    console.log(JSON.stringify({
        production,
        xmasEvent,
        sandbox,
    }, null, 2));
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
