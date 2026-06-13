const fs = require('fs');
const path = require('path');
const https = require('https');
const { Cell } = require('@ton/core');

const OUT_PATH = path.join(__dirname, 'fragment-collection-scan.json');
const CHECKPOINT_PATH = path.join(__dirname, 'fragment-collection-scan.checkpoint.json');
const PAGE_SIZE = 1000;
const MAX_OFFSET = 30000;
const CONCURRENCY = 2;
const TONAPI_KEY = process.env.TONAPI_KEY || '';

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function getJson(url, attempt = 0) {
    return await new Promise((resolve, reject) => {
        const headers = { accept: 'application/json' };
        if (TONAPI_KEY) {
            headers.authorization = `Bearer ${TONAPI_KEY}`;
        }
        https.get(url, { headers }, (res) => {
            let data = '';
            res.on('data', (chunk) => {
                data += chunk;
            });
            res.on('end', async () => {
                if (res.statusCode === 200) {
                    resolve(JSON.parse(data));
                    return;
                }
                if (res.statusCode === 429 && attempt < 8) {
                    await sleep(1500 * (attempt + 1));
                    try {
                        resolve(await getJson(url, attempt + 1));
                    } catch (err) {
                        reject(err);
                    }
                    return;
                }
                reject(new Error(`${res.statusCode} ${url} ${data.slice(0, 200)}`));
            });
        }).on('error', reject);
    });
}

function decodeRawCollectionContent(hex) {
    try {
        const cell = Cell.fromBoc(Buffer.from(hex, 'hex'))[0];
        return cell.beginParse().loadStringTail();
    } catch {
        return null;
    }
}

function hexContainsAscii(hex, ascii) {
    if (!hex) return false;
    return String(hex).toLowerCase().includes(Buffer.from(ascii, 'utf8').toString('hex'));
}

function isFragmentLike(collection) {
    const rawUrl = decodeRawCollectionContent(collection.raw_collection_content ?? '');
    const haystack = [
        collection.metadata?.name,
        collection.metadata?.description,
        collection.metadata?.external_url,
        collection.metadata?.external_link,
        collection.metadata?.image,
        collection.metadata?.cover_image,
        rawUrl,
    ]
        .filter(Boolean)
        .join('\n')
        .toLowerCase();

    if (haystack.includes('nft.fragment.com')) return true;
    if (haystack.includes('fragment.com')) return true;
    if (haystack.includes('telegram usernames')) return true;
    if (haystack.includes('telegram anonymous')) return true;
    if (haystack.includes('exclusive nft collection by telegram')) return true;
    if (haystack.includes('telegram’s ecosystem')) return true;
    if (haystack.includes('gifts section of their telegram account')) return true;
    return false;
}

function isOfficialFragmentCollection(collection) {
    const rawUrl = decodeRawCollectionContent(collection.raw_collection_content ?? '');
    const rawHex = String(collection.raw_collection_content ?? '');
    if (rawUrl && (rawUrl.startsWith('https://nft.fragment.com/collection/') || rawUrl === 'https://nft.fragment.com/usernames.json')) {
        return true;
    }
    return hexContainsAscii(rawHex, 'https://nft.fragment.com/collection/')
        || hexContainsAscii(rawHex, 'https://nft.fragment.com/usernames.json');
}

function loadFuncText(refCell) {
    const s = refCell.beginParse();
    const len = Number(s.loadUint(8));
    return s.loadBuffer(len).toString('utf8');
}

async function fetchAccountDetails(address) {
    const account = await getJson(`https://tonapi.io/v2/blockchain/accounts/${address}`);
    const data = Cell.fromBoc(Buffer.from(account.data, 'hex'))[0];
    const code = Cell.fromBoc(Buffer.from(account.code, 'hex'))[0];
    const result = {
        codeHash: code.hash().toString('hex'),
        touched: null,
        subwalletId: null,
        publicKey: null,
        fullDomainUtf8: null,
        itemCodeHash: null,
        contentHash: null,
        parseError: null,
    };
    try {
        const cs = data.beginParse();
        const touched = Number(cs.loadInt(1));
        const subwalletId = Number(cs.loadUint(32));
        const publicKey = cs.loadBuffer(32).toString('hex');
        const content = cs.loadRef();
        const itemCode = cs.loadRef();
        const fullDomain = loadFuncText(cs.loadRef());
        return {
            ...result,
            touched,
            subwalletId,
            publicKey,
            fullDomainUtf8: JSON.stringify(fullDomain),
            itemCodeHash: itemCode.hash().toString('hex'),
            contentHash: content.hash().toString('hex'),
        };
    } catch (err) {
        return {
            ...result,
            parseError: err.message,
        };
    }
}

async function fetchRecentDeploy(address) {
    try {
        const events = await getJson(`https://tonapi.io/v2/accounts/${address}/events?limit=10`);
        const exec = events.events
            .flatMap((event) => event.actions)
            .find((action) => action.type === 'SmartContractExec' && action.SmartContractExec?.operation?.startsWith('TelemintDeploy'));
        if (!exec) {
            return null;
        }
        const payload = exec.SmartContractExec.payload || '';
        const subwalletMatch = payload.match(/SubwalletId: (\d+)/);
        const forceMatch = payload.match(/ForceSenderAddress: ([^\n]+)/);
        const rewriteMatch = payload.match(/RewriteSenderAddress: ([^\n]+)/);
        return {
            operation: exec.SmartContractExec.operation,
            contract: exec.SmartContractExec.contract?.name ?? exec.SmartContractExec.contract?.address ?? null,
            timestamp: exec.SmartContractExec.contract ? undefined : undefined,
            subwalletId: subwalletMatch ? Number(subwalletMatch[1]) : null,
            forceSenderAddress: forceMatch ? forceMatch[1].trim() : null,
            rewriteSenderAddress: rewriteMatch ? rewriteMatch[1].trim() : null,
        };
    } catch {
        return null;
    }
}

function loadCheckpoint() {
    try {
        return JSON.parse(fs.readFileSync(CHECKPOINT_PATH, 'utf8'));
    } catch {
        return {
            scannedAt: null,
            collections: [],
        };
    }
}

function saveCheckpoint(rows) {
    fs.writeFileSync(CHECKPOINT_PATH, JSON.stringify({
        scannedAt: new Date().toISOString(),
        collections: rows,
    }, null, 2));
}

async function mapLimit(items, limit, fn) {
    const out = new Array(items.length);
    let index = 0;
    async function worker() {
        while (true) {
            const current = index++;
            if (current >= items.length) {
                return;
            }
            out[current] = await fn(items[current], current);
        }
    }
    await Promise.all(Array.from({ length: Math.min(limit, items.length) }, () => worker()));
    return out;
}

async function loadAllCollections() {
    const collections = [];
    for (let offset = 0; offset <= MAX_OFFSET; offset += PAGE_SIZE) {
        const page = await getJson(`https://tonapi.io/v2/nfts/collections?limit=${PAGE_SIZE}&offset=${offset}`);
        const list = page.nft_collections ?? [];
        if (list.length === 0) {
            break;
        }
        collections.push(...list);
        if (list.length < PAGE_SIZE) {
            break;
        }
    }
    return collections;
}

function groupByKey(rows, keyFn) {
    const map = new Map();
    for (const row of rows) {
        const key = keyFn(row);
        if (!map.has(key)) {
            map.set(key, []);
        }
        map.get(key).push(row);
    }
    return [...map.entries()]
        .map(([key, items]) => ({ key, items }))
        .sort((a, b) => b.items.length - a.items.length);
}

async function main() {
    const allCollections = await loadAllCollections();
    const fragmentCandidates = allCollections.filter(isFragmentLike);
    const officialCandidates = fragmentCandidates.filter(isOfficialFragmentCollection);
    const checkpoint = loadCheckpoint();
    const cached = new Map((checkpoint.collections ?? []).map((row) => [row.address, row]));
    const enriched = [];

    for (const collection of officialCandidates) {
        if (cached.has(collection.address)) {
            enriched.push(cached.get(collection.address));
        }
    }

    const pending = officialCandidates.filter((collection) => !cached.has(collection.address));
    const completedRows = [];
    const scannedRows = await mapLimit(pending, CONCURRENCY, async (collection, index) => {
        const rawUrl = decodeRawCollectionContent(collection.raw_collection_content ?? '');
        const account = await fetchAccountDetails(collection.address);
        const recentDeploy = await fetchRecentDeploy(collection.address);
        const row = {
            name: collection.metadata?.name ?? null,
            address: collection.address,
            owner: collection.owner?.address ?? null,
            externalUrl: collection.metadata?.external_url ?? collection.metadata?.external_link ?? null,
            rawCollectionUrl: rawUrl,
            ...account,
            recentDeploy,
        };
        completedRows.push(row);
        saveCheckpoint([...enriched, ...completedRows]);
        console.log(`scanned ${index + 1}/${pending.length}: ${collection.address}`);
        return row;
    });

    enriched.push(...scannedRows.filter(Boolean));
    enriched.sort((a, b) => a.address.localeCompare(b.address));

    const byPublicKey = groupByKey(enriched, (row) => row.publicKey);
    const byPublicKeyAndSubwallet = groupByKey(enriched, (row) => `${row.publicKey}:${row.subwalletId}`);
    const collisions = byPublicKeyAndSubwallet.filter((group) => group.items.length > 1);

    const summary = {
        scannedAt: new Date().toISOString(),
        coverage: {
            totalCollectionsLoaded: allCollections.length,
            fragmentLikeCollections: fragmentCandidates.length,
            officialFragmentCollections: enriched.length,
            maxOffset: MAX_OFFSET,
            pageSize: PAGE_SIZE,
        },
        counts: {
            uniquePublicKeys: byPublicKey.length,
            uniquePublicKeySubwalletPairs: byPublicKeyAndSubwallet.length,
            repeatedPublicKeys: byPublicKey.filter((group) => group.items.length > 1).length,
            repeatedPublicKeySubwalletPairs: collisions.length,
        },
        collisions,
        byPublicKey,
        collections: enriched.sort((a, b) => (a.name || '').localeCompare(b.name || '')),
    };

    fs.writeFileSync(OUT_PATH, JSON.stringify(summary, null, 2));
    console.log(JSON.stringify({
        out: OUT_PATH,
        coverage: summary.coverage,
        counts: summary.counts,
        collisionPreview: collisions.slice(0, 5).map((group) => ({
            key: group.key,
            names: group.items.map((item) => item.name),
        })),
    }, null, 2));
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
