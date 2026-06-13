const https = require('https');
const net = require('net');
const tls = require('tls');
const { URL } = require('url');
const { Blockchain, createShardAccount } = require('@ton/sandbox');
const { Address, Cell, Dictionary, TupleBuilder, beginCell, toNano } = require('@ton/core');
const cfg = require('./config');

const SCALE = 1e9;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function get(url, headers) {
  return new Promise((resolve) => {
    https.get(url, { headers: Object.assign({ 'User-Agent': 'evaa-monitor/2', accept: 'application/json' }, headers || {}) }, (r) => {
      let d = ''; r.on('data', (c) => d += c); r.on('end', () => resolve({ s: r.statusCode, d }));
    }).on('error', (e) => resolve({ s: 0, d: e.message }));
  });
}
async function getJson(url, headers) { const r = await get(url, headers); try { return JSON.parse(r.d); } catch { return {}; } }

const tcKey = () => ({ 'X-API-Key': cfg.TONCENTER_KEY });

// ---- account state (toncenter v2 getAddressInformation: base64 code/data) ----
async function fetchState(addr, retries = 4) {
  const a = Address.parse(addr).toString({ urlSafe: true, bounceable: true });
  for (let i = 0; i < retries; i++) {
    const r = await get(`https://toncenter.com/api/v2/getAddressInformation?address=${a}`, tcKey());
    if (r.s === 200) { try { const j = JSON.parse(r.d); if (j.result && j.result.data) return { code: j.result.code, data: j.result.data, balance: j.result.balance }; } catch {} return null; }
    if ([429, 502, 503].includes(r.s)) { await sleep(800 * (i + 1)); continue; }
    return null;
  }
  return null;
}
function toCell(b64) { if (!b64) return null; try { return Cell.fromBase64(b64); } catch { return null; } }

async function forkAccount(bc, addr) {
  const st = await fetchState(addr);
  if (!st || !st.code || !st.data) return null;
  const a = Address.parse(addr);
  const bal = BigInt(st.balance || 0);
  await bc.setShardAccount(a, createShardAccount({ address: a, code: toCell(st.code), data: toCell(st.data), balance: bal > toNano('5') ? bal : toNano('5'), workchain: 0 }));
  return a;
}

// ---- master oracle feed map + config decimals ----
// pythToEvaa: Map<pythId_bigint, {evaaId: bigint, multiplierPythId: bigint}>
// multiplierPythId != 0n => compound feed: EVAA_price = ref_USD_price × orig_rate
async function masterMaps() {
  const st = await fetchState(cfg.MAIN_POOL);
  const data = toCell(st.data);
  const root = data.beginParse();
  root.loadRef(); root.loadRef();
  const mc = root.loadRef().beginParse();
  const assetCfgDict = mc.loadMaybeRef(); mc.loadInt(8); mc.loadAddress();
  const oc = mc.loadRef().beginParse(); oc.loadAddress();
  const fd = oc.loadRef().beginParse();
  // dict value = evaaId(256) + optional multiplierPythId(256)
  const pythToEvaa = fd.loadDict(Dictionary.Keys.BigUint(256), {
    serialize: () => {},
    parse: (s) => {
      const evaaId = s.loadUintBig(256);
      const multiplierPythId = s.remainingBits >= 256 ? s.loadUintBig(256) : 0n;
      return { evaaId, multiplierPythId };
    },
  });
  // decimals: per asset config value -> jw_hash(256) + decimals(8)
  const decimals = new Map();
  if (assetCfgDict) {
    const d = Dictionary.loadDirect(Dictionary.Keys.BigUint(256), { serialize: () => {}, parse: (s) => { s.loadUintBig(256); return s.loadUint(8); } }, assetCfgDict);
    for (const k of d.keys()) decimals.set(k, d.get(k));
  }
  return { pythToEvaa, decimals };
}

async function pricesAt(pythToEvaa, ts) {
  const ids = [...pythToEvaa.keys()];
  const hexes = ids.map((id) => id.toString(16).padStart(64, '0'));
  const ep = ts ? `/v2/updates/price/${ts}` : '/v2/updates/price/latest';
  const j = await getJson(`${cfg.HERMES_BASE}${ep}?${hexes.map((h) => 'ids[]=' + h).join('&')}&parsed=true`);
  // raw Hermes float prices by pythId hex
  const raw = {};
  for (const p of (j.parsed || [])) raw['0x' + p.id.toLowerCase()] = Number(p.price.price) * Math.pow(10, p.price.expo);
  const m = new Map();
  for (const [id, feedEntry] of pythToEvaa) {
    const hex = '0x' + id.toString(16).padStart(64, '0');
    const origPrice = raw[hex];
    if (origPrice == null) continue;
    if (feedEntry.multiplierPythId !== 0n) {
      // compound: EVAA_price = ref_USD × orig_rate  (e.g. TON_USD × stTON/TON)
      const refHex = '0x' + feedEntry.multiplierPythId.toString(16).padStart(64, '0');
      const refPrice = raw[refHex];
      if (refPrice == null) continue;
      m.set(feedEntry.evaaId, refPrice * origPrice);
    } else {
      m.set(feedEntry.evaaId, origPrice);
    }
  }
  return m;
}

async function livePrices(pythToEvaa) { return pricesAt(pythToEvaa, null); }

// real-time price feed: opens a Hermes SSE stream and calls onUpdate(evaaAssetId, price)
// for every price tick. Handles compound feeds (stTON = TON_USD × stTON/TON_rate).
function streamPrices(pythToEvaa, onUpdate) {
  const ids = [...pythToEvaa.keys()].map((id) => id.toString(16).padStart(64, '0'));
  const qs = ids.map((h) => 'ids[]=' + h).join('&');
  const url = `${cfg.HERMES_BASE}/v2/updates/price/stream?${qs}&parsed=true`;
  // cache raw prices per pythId hex so compound feeds can be recomputed on any tick
  const rawCache = new Map();

  const recompute = (updatedHex) => {
    for (const [pythId, feedEntry] of pythToEvaa) {
      const hex = '0x' + pythId.toString(16).padStart(64, '0');
      const isDirectFeed = hex === updatedHex;
      const isMultiplierFeed = feedEntry.multiplierPythId !== 0n &&
        '0x' + feedEntry.multiplierPythId.toString(16).padStart(64, '0') === updatedHex;
      if (!isDirectFeed && !isMultiplierFeed) continue;
      const origPrice = rawCache.get(hex);
      if (origPrice == null) continue;
      if (feedEntry.multiplierPythId !== 0n) {
        const refHex = '0x' + feedEntry.multiplierPythId.toString(16).padStart(64, '0');
        const refPrice = rawCache.get(refHex);
        if (refPrice == null) continue; // wait until both components received
        onUpdate(feedEntry.evaaId, refPrice * origPrice);
      } else {
        onUpdate(feedEntry.evaaId, origPrice);
      }
    }
  };

  const connect = () => {
    let buf = '';
    https.get(url, { headers: { 'User-Agent': 'evaa-monitor/2', accept: 'text/event-stream' } }, (r) => {
      r.setEncoding('utf8');
      r.on('data', (chunk) => {
        buf += chunk;
        let idx;
        while ((idx = buf.indexOf('\n\n')) >= 0) {
          const block = buf.slice(0, idx); buf = buf.slice(idx + 2);
          if (!block.startsWith('data:')) continue;
          try {
            const j = JSON.parse(block.slice(5));
            for (const p of (j.parsed || [])) {
              const hex = '0x' + p.id.toLowerCase();
              rawCache.set(hex, Number(p.price.price) * Math.pow(10, p.price.expo));
              recompute(hex);
            }
          } catch {}
        }
      });
      r.on('end', () => setTimeout(connect, 2000));
      r.on('error', () => setTimeout(connect, 2000));
    }).on('error', () => setTimeout(connect, 2000));
  };
  connect();
}

// fresh = latest; stale = per-asset MIN over the last STALE_WINDOW_S (sampled),
// i.e. the most adverse real price an attacker could still submit within the TTL.
// staleAgeS = how many seconds ago that minimum was observed (per asset).
async function priceWindow(pythToEvaa) {
  const now = Math.floor(Date.now() / 1000);
  const dts = [0, 60, 120, cfg.STALE_WINDOW_S - 1];
  const samples = [];
  for (const dt of dts) { samples.push(await pricesAt(pythToEvaa, dt === 0 ? null : now - dt)); await sleep(60); }
  const fresh = samples[0];
  const stale = new Map();
  const staleAgeS = new Map();
  for (const [k, v] of fresh) {
    let min = v, minDt = 0;
    for (let i = 0; i < samples.length; i++) { const x = samples[i].get(k); if (x != null && x < min) { min = x; minDt = dts[i]; } }
    stale.set(k, min);
    staleAgeS.set(k, minDt);
  }
  return { fresh, stale, staleAgeS };
}

// one-time lookup: evaa asset id -> { symbol, quote }
// compound feeds get quote:'USD' since stored price is already USD (ref × orig)
async function feedSymbols(pythToEvaa) {
  const list = await getJson(`${cfg.HERMES_BASE}/v2/price_feeds`);
  const byId = new Map();
  for (const f of (Array.isArray(list) ? list : [])) {
    if (f.attributes) byId.set(f.id, { symbol: f.attributes.base, quote: f.attributes.quote_currency });
  }
  const out = new Map();
  for (const [pythId, feedEntry] of pythToEvaa) {
    const meta = byId.get(pythId.toString(16).padStart(64, '0'));
    if (meta) {
      const quote = feedEntry.multiplierPythId !== 0n ? 'USD' : meta.quote;
      out.set(feedEntry.evaaId, { symbol: meta.symbol, quote });
    }
  }
  return out;
}

function pricesCell(evaaPrice, collateralIds, factor) {
  const V = { serialize: (s, b) => b.storeCoins(s), parse: (s) => s.loadCoins() };
  const d = Dictionary.empty(Dictionary.Keys.BigUint(256), V);
  for (const [k, v] of evaaPrice) { let p = v * SCALE; if (factor !== 1 && collateralIds.has(k)) p *= factor; d.set(k, BigInt(Math.round(p))); }
  return beginCell().storeDictDirect(d).endCell();
}

// ---- per-user: balances + real buffer via getIsLiquidable ----
const BVAL = { serialize: () => {}, parse: (s) => s.loadIntBig(65) };

async function userBalances(bc, userAddr, dynCell) {
  let r;
  try { r = await bc.runGetMethod(userAddr, 'isUserSc', []); if (r.exitCode !== 0 || r.stackReader.readBigNumber() === 0n) return null; } catch { return null; }
  try { const tb = new TupleBuilder(); tb.writeCell(dynCell); r = await bc.runGetMethod(userAddr, 'getAccountBalances', tb.build()); if (r.exitCode !== 0) return null; const c = r.stackReader.readCellOpt(); if (!c) return null;
    const bals = Dictionary.loadDirect(Dictionary.Keys.BigUint(256), BVAL, c);
    const assets = []; const collIds = new Set(); let hasD = false, hasC = false;
    for (const [k, v] of bals) { if (v === 0n) continue; assets.push([k, v]); if (v < 0n) hasD = true; if (v > 0n) { hasC = true; collIds.add(k); } }
    if (!hasD || !hasC) return null;
    return { assets, collIds };
  } catch { return null; }
}

async function isLiqAt(bc, userAddr, cfgCell, dynCell, priceMap, collIds, factor) {
  const tb = new TupleBuilder(); tb.writeCell(cfgCell); tb.writeCell(dynCell); tb.writeCell(pricesCell(priceMap, collIds, factor));
  const r = await bc.runGetMethod(userAddr, 'getIsLiquidable', tb.build());
  if (r.exitCode !== 0) return null;
  return r.stackReader.readBigNumber() === -1n;
}

// flip factor f*: collateral-price multiplier at which the position becomes
// liquidatable. >=1.0 means already liquidatable at the fresh price.
async function flipFactor(bc, userAddr, cfgCell, dynCell, freshPrice, collIds) {
  for (const k of collIds) if (!freshPrice.has(k)) return null;
  if (await isLiqAt(bc, userAddr, cfgCell, dynCell, freshPrice, collIds, 1.0)) return 1.0;
  let lo = 0, hi = 1;
  for (let i = 0; i < 16; i++) { const mid = (lo + hi) / 2; const l = await isLiqAt(bc, userAddr, cfgCell, dynCell, freshPrice, collIds, mid); if (l === null) return null; if (l) lo = mid; else hi = mid; }
  return hi; // liquidatable once collateral value drops to <= hi * census value
}

async function userInfo(bc, userAddr, cfgCell, dynCell, freshPrice, stalePrice) {
  // isUserSc + getAccountBalances
  let r;
  try { r = await bc.runGetMethod(userAddr, 'isUserSc', []); if (r.exitCode !== 0 || r.stackReader.readBigNumber() === 0n) return null; } catch { return null; }
  let bals;
  try { const tb = new TupleBuilder(); tb.writeCell(dynCell); r = await bc.runGetMethod(userAddr, 'getAccountBalances', tb.build()); if (r.exitCode !== 0) return null; const c = r.stackReader.readCellOpt(); if (!c) return null; bals = Dictionary.loadDirect(Dictionary.Keys.BigUint(256), BVAL, c); } catch { return null; }
  const assets = []; const collIds = new Set(); let hasD = false, hasC = false;
  for (const [k, v] of bals) { if (v === 0n) continue; assets.push([k, v]); if (v < 0n) hasD = true; if (v > 0n) { hasC = true; collIds.add(k); } }
  if (!hasD || !hasC) return null;
  for (const [k] of assets) if (!freshPrice.has(k)) return null; // need every asset priced

  const liq = async (priceMap) => {
    const tb = new TupleBuilder(); tb.writeCell(cfgCell); tb.writeCell(dynCell); tb.writeCell(pricesCell(priceMap, collIds, 1));
    const rr = await bc.runGetMethod(userAddr, 'getIsLiquidable', tb.build());
    if (rr.exitCode !== 0) return null;
    return rr.stackReader.readBigNumber() === -1n;
  };
  const liqFresh = await liq(freshPrice);
  if (liqFresh === null) return null;
  const liqStale = await liq(stalePrice);
  // attackableNow: healthy at current price, but liquidatable using a real price
  // within the last STALE_WINDOW_S that is still inside the TTL.
  return { assets, collIds, liqFresh, liqStale, attackableNow: (liqFresh === false && liqStale === true) };
}

// ---- wick magnitude: max <=180s round-trip drop over N days (Pyth 1-min OHLC) ----
async function maxWickPct(symbol, days) {
  const now = Math.floor(Date.now() / 1000);
  let candles = [];
  for (let d = 0; d < days; d += 2) {
    const to = now - d * 86400, from = to - 2 * 86400;
    const j = await getJson(`${cfg.PYTH_BENCH_BASE}/v1/shims/tradingview/history?symbol=${encodeURIComponent(symbol)}&resolution=1&from=${from}&to=${to}`);
    if (!j.t) continue;
    for (let i = 0; i < j.t.length; i++) candles.push({ t: j.t[i], l: j.l[i], c: j.c[i] });
  }
  candles.sort((a, b) => a.t - b.t);
  let best = 0;
  for (let i = 1; i < candles.length - 2; i++) {
    if (candles[i + 1].t - candles[i].t > 180) continue;
    const pre = candles[i - 1].c, lo = Math.min(candles[i].l, candles[i + 1].l), rec = Math.max(candles[i + 1].c, candles[i + 2].c);
    const drop = (pre - lo) / pre * 100;
    if (rec >= pre * 0.99 && drop > best) best = drop;
  }
  return best;
}

async function harvestUsers(pages) {
  const seen = new Set(); let endLt = '';
  for (let p = 0; p < pages; p++) {
    let u = `${cfg.TONCENTER_BASE}/transactions?account=${cfg.MAIN_POOL}&limit=100&sort=desc`;
    if (endLt) u += `&end_lt=${endLt}`;
    const j = await getJson(u, tcKey());
    const txs = j.transactions || []; if (!txs.length) break;
    for (const t of txs) { if (t.in_msg && t.in_msg.source) seen.add(t.in_msg.source); for (const o of (t.out_msgs || [])) if (o.destination) seen.add(o.destination); }
    endLt = (BigInt(txs[txs.length - 1].lt) - 1n).toString();
    await sleep(120);
  }
  return [...seen];
}

async function masterCells(bc, masterAddr) {
  const cfgCell = (await bc.runGetMethod(masterAddr, 'getAssetsConfig', [])).stackReader.readCell();
  const dynCell = (await bc.runGetMethod(masterAddr, 'getAssetsData', [])).stackReader.readCell();
  return { cfgCell, dynCell };
}

async function telegram(text) {
  if (!cfg.TELEGRAM_TOKEN || !cfg.TELEGRAM_CHAT) return false;
  const data = JSON.stringify({ chat_id: cfg.TELEGRAM_CHAT, text, parse_mode: 'HTML', disable_web_page_preview: true });

  if (!cfg.TG_PROXY) {
    return new Promise((res) => {
      const req = https.request(`https://api.telegram.org/bot${cfg.TELEGRAM_TOKEN}/sendMessage`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } }, (r) => { r.on('data', () => {}); r.on('end', () => res(r.statusCode === 200)); });
      req.on('error', () => res(false)); req.write(data); req.end();
    });
  }

  // api.telegram.org blocked directly on some RU hosts — tunnel via HTTP CONNECT proxy
  return new Promise((resolve) => {
    const p = new URL(cfg.TG_PROXY);
    const sock = net.connect(Number(p.port) || 80, p.hostname);
    sock.setTimeout(15000, () => { sock.destroy(); resolve(false); });
    sock.once('error', () => resolve(false));
    sock.once('connect', () => {
      let req = `CONNECT api.telegram.org:443 HTTP/1.1\r\nHost: api.telegram.org:443\r\n`;
      if (p.username) req += `Proxy-Authorization: Basic ${Buffer.from(`${decodeURIComponent(p.username)}:${decodeURIComponent(p.password)}`).toString('base64')}\r\n`;
      req += '\r\n';
      sock.write(req);
    });
    sock.once('data', (chunk) => {
      if (!/^HTTP\/1\.[01] 200/.test(chunk.toString('latin1'))) { sock.destroy(); resolve(false); return; }
      const tlsSock = tls.connect({ socket: sock, servername: 'api.telegram.org' }, () => {
        const httpReq = `POST /bot${cfg.TELEGRAM_TOKEN}/sendMessage HTTP/1.1\r\nHost: api.telegram.org\r\nContent-Type: application/json\r\nContent-Length: ${Buffer.byteLength(data)}\r\nConnection: close\r\n\r\n${data}`;
        tlsSock.write(httpReq);
      });
      let resp = '';
      tlsSock.on('data', (d) => resp += d);
      tlsSock.on('end', () => resolve(/^HTTP\/1\.[01] 200/.test(resp)));
      tlsSock.on('error', () => resolve(false));
    });
  });
}

module.exports = { Blockchain, forkAccount, masterMaps, livePrices, streamPrices, priceWindow, feedSymbols, pricesAt, userInfo, userBalances, isLiqAt, flipFactor, maxWickPct, harvestUsers, masterCells, telegram, SCALE, sleep };
