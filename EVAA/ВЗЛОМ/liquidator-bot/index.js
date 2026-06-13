// ===============================================================
//  EVAA stale-price liquidation MONITOR (read-only, no transactions)
//  Two-tier:
//   - tier1 (slow, SCAN_INTERVAL_MS): for every known position, compute its
//     "flip factor" f* — the collateral-price multiplier at which the REAL
//     contract's getIsLiquidable flips to true. f*=1 => already liquidatable
//     now. f*<1 => still healthy, becomes liquidatable if collateral price
//     drops to f* * ref_price.
//   - live watch (FAST_INTERVAL_MS): prices come from a real-time Hermes SSE
//     stream. If the live/ref ratio for a position's collateral nears its
//     cached f*, run the on-chain confirm (fork + getIsLiquidable with fresh
//     vs 180s-stale prices), throttled per position by CONFIRM_COOLDOWN_MS.
//     Alert ONLY if confirmed on real bytecode.
// ===============================================================
const fs = require('fs');
const path = require('path');
const cfg = require('./config');
const L = require('./lib');

const fmt = (ms) => new Date(ms).toISOString().replace('T', ' ').slice(0, 19);
const short = (a) => a.slice(0, 8) + '…' + a.slice(-6);

function loadJson(file, def) {
  try { return JSON.parse(fs.readFileSync(path.resolve(__dirname, file), 'utf8')); } catch { return def; }
}
function saveJson(file, obj) {
  const dir = path.resolve(__dirname, cfg.DATA_DIR); if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.resolve(__dirname, file), JSON.stringify(obj));
}

let pythToEvaaCache = null;    // pyth feed id (BigInt) -> evaa asset id (BigInt), set by tier1
let decimalsCache = new Map(); // evaa asset id (BigInt) -> decimals, set by tier1
let symbolCache = new Map();   // evaa asset id (BigInt) -> { symbol, quote }, fetched once at startup
const liveMap = new Map();     // evaa asset id (BigInt) -> live price, updated by Hermes stream
let lastPriceUpdate = 0;
let lastTier1Time = 0;
const lastConfirm = new Map(); // addr -> ms of last on-chain confirm (throttle)
let lastHeartbeat = 0;

// human-readable amount + symbol for a balance (evaaId: BigInt, bal: BigInt, always positive)
function fmtAsset(evaaId, bal) {
  const meta = symbolCache.get(evaaId);
  const dec = decimalsCache.get(evaaId) ?? 9;
  return { symbol: meta ? meta.symbol : evaaId.toString(16).slice(0, 6) + '…', amt: Number(bal) / Math.pow(10, dec) };
}

// price formatted with its native unit ($ for USD-quoted feeds, otherwise "<value> <QUOTE>")
function fmtPrice(evaaId, price) {
  if (price == null) return '—';
  const meta = symbolCache.get(evaaId);
  if (!meta || meta.quote === 'USD') return `$${price.toFixed(price < 1 ? 5 : 4)}`;
  return `${price.toFixed(5)} ${meta.quote}`;
}

// ---------------- Tier 1: slow full re-scan, computes flip factors ----------------
async function tier1() {
  const t0 = Date.now();
  console.log(`\n[${fmt(t0)}] tier1 (full re-scan) start`);

  lastTier1Time = t0;
  const { pythToEvaa, decimals } = await L.masterMaps();
  pythToEvaaCache = pythToEvaa;
  decimalsCache = decimals;
  const fresh = await L.livePrices(pythToEvaa);
  console.log(`  prices: ${fresh.size} assets`);

  const persisted = new Set(loadJson(cfg.USERS_FILE, []));
  const harvested = await L.harvestUsers(cfg.CANDIDATE_PAGES);
  const users = [...new Set([...persisted, ...harvested])].slice(0, cfg.MAX_USERS_PER_SCAN);
  console.log(`  candidates: ${users.length} (persisted ${persisted.size} + harvested ${harvested.length})`);

  const bc = await L.Blockchain.create();
  const masterAddr = await L.forkAccount(bc, cfg.MAIN_POOL);
  const { cfgCell, dynCell } = await L.masterCells(bc, masterAddr);

  const known = new Set();
  const cache = [];
  let scanned = 0, alreadyLiq = 0;
  for (const addr of users) {
    let userA;
    try { userA = await L.forkAccount(bc, addr); } catch { continue; }
    if (!userA) continue;
    let bal;
    try { bal = await L.userBalances(bc, userA, dynCell); } catch { continue; }
    if (!bal) continue;
    for (const [k] of bal.assets) if (!fresh.has(k)) { bal = null; break; }
    if (!bal) continue;
    known.add(addr);

    let ff;
    try { ff = await L.flipFactor(bc, userA, cfgCell, dynCell, fresh, bal.collIds); } catch { continue; }
    if (ff === null) continue;
    scanned++;
    if (ff >= 1) alreadyLiq++;

    let collUsd = 0, debtUsd = 0;
    const assets = [];
    for (const [k, v] of bal.assets) {
      const dec = decimals.get(k) ?? 9;
      const px = fresh.get(k) ?? 0;
      const usd = Number(v) / Math.pow(10, dec) * px;
      if (v > 0n) collUsd += usd; else debtUsd += Math.abs(usd);
      assets.push({ id: k.toString(16), bal: v.toString() });
    }

    const refPrices = {};
    for (const k of bal.collIds) refPrices[k.toString(16)] = fresh.get(k);

    cache.push({ addr, collIds: [...bal.collIds].map((x) => x.toString(16)), flipFactor: ff, refPrices, collUsd, debtUsd, assets, t: t0 });
    process.stdout.write(`  [${scanned}] ${short(addr)} flip=${ff.toFixed(4)}      \r`);
  }
  saveJson(cfg.USERS_FILE, [...known]);
  saveJson(cfg.FLIP_CACHE_FILE, cache);

  console.log(`\n  cached ${cache.length} positions | already-liquidatable@fresh: ${alreadyLiq}`);
  await alertHonestNow(cache);
  return cache;
}

// ---------------- honest opportunities: f* >= 1 (liquidatable@live price) and profitable ----------------
async function alertHonestNow(cache) {
  const honest = cache.filter((p) => p.flipFactor >= 1 && (p.collUsd - p.debtUsd) > 0);
  const prevAlerted = new Set(loadJson(cfg.HONEST_ALERTED_FILE, []));
  const nowAddrs = new Set(honest.map((p) => p.addr));
  const newOnes = honest.filter((p) => !prevAlerted.has(p.addr));
  saveJson(cfg.HONEST_ALERTED_FILE, [...nowAddrs]);
  console.log(`  honest-now (f*>=1, profit>0): ${honest.length} total, ${newOnes.length} new`);
  if (!newOnes.length) return;

  const lines = newOnes
    .sort((a, b) => (b.collUsd - b.debtUsd) - (a.collUsd - a.debtUsd))
    .map((p) => `<code>${short(p.addr)}</code> — выгода ≈$${Math.round(p.collUsd - p.debtUsd)} (coll≈$${Math.round(p.collUsd)}, debt≈$${Math.round(p.debtUsd)})`)
    .join('\n');

  const msg =
    `💰 <b>EVAA — доступна ЧЕСТНАЯ ликвидация по текущей цене</b> (не баг устаревшей цены)\n` +
    `Время: ${fmt(Date.now())} UTC\n` +
    `Пул: MAIN | tier1-снимок\n` +
    `Новых позиций: ${newOnes.length}\n\n${lines}\n\n` +
    `getIsLiquidable=true по живой цене прямо сейчас. Любой адрес может вызвать liquidate() и забрать бонус.`;
  const ok = await L.telegram(msg);
  console.log(`    -> telegram (honest-now): ${ok ? 'sent' : 'NOT sent'}`);
}

// ---------------- live/ref ratio for every cached f*<1 position ----------------
function computeRatios(cache) {
  const out = [];
  for (const p of cache) {
    if (p.flipFactor >= 1) continue;
    let minRatio = Infinity;
    for (const idHex of p.collIds) {
      const ref = p.refPrices[idHex];
      const cur = liveMap.get(BigInt('0x' + idHex));
      if (!ref || cur == null) { minRatio = Infinity; break; }
      const r = cur / ref;
      if (r < minRatio) minRatio = r;
    }
    out.push({ p, minRatio, trig: p.flipFactor * (1 + cfg.TRIGGER_MARGIN) });
  }
  return out;
}

function logNearMiss(ratios) {
  const finite = ratios.filter((r) => r.minRatio !== Infinity);
  if (!finite.length) return;
  const top = [...finite].sort((a, b) => (a.minRatio - a.trig) - (b.minRatio - b.trig)).slice(0, 3);
  console.log(`[${fmt(Date.now())}] closest: ` + top.map((r) => `${short(r.p.addr)} dist=${((r.minRatio - r.trig) * 100).toFixed(2)}%`).join(', '));
}

async function maybeHeartbeat(ratios) {
  const now = Date.now();
  if (now - lastHeartbeat < cfg.HEARTBEAT_INTERVAL_MS) return;
  lastHeartbeat = now;
  const finite = ratios.filter((r) => r.minRatio !== Infinity);
  const closest = [...finite].sort((a, b) => (a.minRatio - a.trig) - (b.minRatio - b.trig))[0];
  const ageS = Math.round((now - lastPriceUpdate) / 1000);
  const tier1AgeMin = Math.round((now - lastTier1Time) / 60000);

  let closestLine = '';
  if (closest) {
    const collId = closest.p.collIds[0];
    const meta = symbolCache.get(BigInt('0x' + collId));
    const dist = (closest.minRatio - closest.trig) * 100;
    closestLine =
      `Ближе всего к флипу: <code>${short(closest.p.addr)}</code> (${meta ? meta.symbol : 'актив'}), ` +
      `запас до триггера: ${dist.toFixed(2)}%\n`;
  }

  const msg =
    `🟢 <b>EVAA монитор активен</b>\n` +
    `Время: ${fmt(now)} UTC\n` +
    `Отслеживается позиций: ${ratios.length} (с f*&lt;1: ${finite.length})\n` +
    closestLine +
    `Цены обновлены: ${ageS}с назад | последний полный пересчёт (tier1): ${tier1AgeMin}м назад`;
  const ok = await L.telegram(msg);
  console.log(`[${fmt(now)}] heartbeat -> telegram: ${ok ? 'sent' : 'NOT sent'}`);
}

// ---------------- live trigger: confirm on-chain when ratio nears f* ----------------
async function checkTriggers(ratios) {
  const now = Date.now();
  const triggered = ratios.filter(({ p, minRatio, trig }) =>
    minRatio !== Infinity && minRatio <= trig && now - (lastConfirm.get(p.addr) || 0) >= cfg.CONFIRM_COOLDOWN_MS);
  if (!triggered.length) return;
  for (const { p } of triggered) lastConfirm.set(p.addr, now);

  console.log(`\n[${fmt(now)}] live price near flip for ${triggered.length} position(s) — confirming on-chain`);

  const { fresh, stale, staleAgeS } = await L.priceWindow(pythToEvaaCache);

  const bc = await L.Blockchain.create();
  const masterAddr = await L.forkAccount(bc, cfg.MAIN_POOL);
  const { cfgCell, dynCell } = await L.masterCells(bc, masterAddr);

  for (const { p, minRatio } of triggered) {
    let userA;
    try { userA = await L.forkAccount(bc, p.addr); } catch { continue; }
    if (!userA) continue;
    let info;
    try { info = await L.userInfo(bc, userA, cfgCell, dynCell, fresh, stale); } catch { continue; }
    if (!info) continue;

    console.log(`  ${short(p.addr)} ratio=${minRatio.toFixed(4)} flip=${p.flipFactor.toFixed(4)} liqFresh=${info.liqFresh} liqStale=${info.liqStale}`);

    if (info.attackableNow) {
      await alertAttackable(p, info, fresh, stale, staleAgeS);
    } else if (info.liqFresh) {
      await alertLiqFresh(p, info, fresh);
    }
  }
}

async function alertAttackable(p, info, fresh, stale, staleAgeS) {
  const coll = info.assets.find((a) => a[1] > 0n);
  const debt = info.assets.find((a) => a[1] < 0n);
  const cA = fmtAsset(coll[0], coll[1]);
  const dA = fmtAsset(debt[0], -debt[1]);
  const curPx = fresh.get(coll[0]);
  const stalePx = stale.get(coll[0]);
  const ageS = staleAgeS.get(coll[0]) ?? cfg.STALE_WINDOW_S;
  const dropPct = curPx ? (stalePx / curPx - 1) * 100 : 0;
  const profit = Math.round(p.collUsd - p.debtUsd);

  const msg =
    `🚨 <b>EVAA — ПОДТВЕРЖДЕНО: ликвидация возможна ПРЯМО СЕЙЧАС</b> (баг устаревшей цены)\n` +
    `Время: ${fmt(Date.now())} UTC\n` +
    `Пул: MAIN | окно устаревания цены (TTL): ${cfg.STALE_WINDOW_S}с\n` +
    `Позиция: <code>${short(p.addr)}</code>\n\n` +
    `Коллатерал: <b>${cA.symbol}</b>, баланс ${cA.amt.toFixed(4)} (≈$${Math.round(p.collUsd)})\n` +
    `  текущая цена: ${fmtPrice(coll[0], curPx)} | цена ${ageS}с назад: ${fmtPrice(coll[0], stalePx)} (${dropPct.toFixed(2)}%)\n` +
    `Долг: <b>${dA.symbol}</b>, баланс ${dA.amt.toFixed(4)} (≈$${Math.round(p.debtUsd)})\n\n` +
    `Оценка выгоды ликвидатора: ≈$${profit}\n\n` +
    `По текущей цене позиция здорова (getIsLiquidable=false), но цена Pyth от ${ageS}с назад (в пределах TTL=${cfg.STALE_WINDOW_S}с) делает getIsLiquidable=true — вызов liquidate() пройдёт успешно.\n` +
    `Подтверждено выполнением реального байткода контракта (форк mainnet).`;
  const ok = await L.telegram(msg);
  console.log(`    -> telegram (attackable-now): ${ok ? 'sent' : 'NOT sent'}`);
}

async function alertLiqFresh(p, info, fresh) {
  const coll = info.assets.find((a) => a[1] > 0n);
  const debt = info.assets.find((a) => a[1] < 0n);
  const cA = fmtAsset(coll[0], coll[1]);
  const dA = fmtAsset(debt[0], -debt[1]);

  const msg =
    `⚠️ <b>EVAA — ликвидация возможна по ТЕКУЩЕЙ цене</b> (честная, не баг)\n` +
    `Время: ${fmt(Date.now())} UTC\n` +
    `Пул: MAIN\n` +
    `Позиция: <code>${short(p.addr)}</code>\n\n` +
    `Коллатерал: <b>${cA.symbol}</b>, баланс ${cA.amt.toFixed(4)} (≈$${Math.round(p.collUsd)}, тек. цена ${fmtPrice(coll[0], fresh.get(coll[0]))})\n` +
    `Долг: <b>${dA.symbol}</b>, баланс ${dA.amt.toFixed(4)} (≈$${Math.round(p.debtUsd)})\n\n` +
    `getIsLiquidable=true при живой цене — обычная возможность ликвидации, не связано с багом устаревшей цены.`;
  const ok = await L.telegram(msg);
  console.log(`    -> telegram (liq-fresh): ${ok ? 'sent' : 'NOT sent'}`);
}

async function loop() {
  console.log('EVAA stale-price MONITOR (read-only, real-time price stream)');
  console.log(`pool ${cfg.MAIN_POOL} | tier1 every ${cfg.SCAN_INTERVAL_MS / 60000}m | check every ${cfg.FAST_INTERVAL_MS / 1000}s | confirm cooldown ${cfg.CONFIRM_COOLDOWN_MS / 1000}s | trigger margin ${(cfg.TRIGGER_MARGIN * 100).toFixed(0)}%`);

  await tier1();

  // feed set is fixed by the MAIN pool's oracle config; fetched once, tier1 re-scans reuse it
  symbolCache = await L.feedSymbols(pythToEvaaCache);
  for (const [k, v] of await L.livePrices(pythToEvaaCache)) liveMap.set(k, v);
  lastPriceUpdate = Date.now();
  L.streamPrices(pythToEvaaCache, (evaaId, price) => { liveMap.set(evaaId, price); lastPriceUpdate = Date.now(); });

  while (true) {
    await L.sleep(cfg.FAST_INTERVAL_MS);
    const cache = loadJson(cfg.FLIP_CACHE_FILE, []);
    const ratios = computeRatios(cache);
    try { await checkTriggers(ratios); } catch (e) { console.error('  checkTriggers error:', e.message); }
    logNearMiss(ratios);
    try { await maybeHeartbeat(ratios); } catch (e) { console.error('  heartbeat error:', e.message); }
    if (Date.now() - lastTier1Time >= cfg.SCAN_INTERVAL_MS) {
      try { await tier1(); } catch (e) { console.error('  tier1 error:', e.message); }
    }
  }
}

if (process.argv.includes('--once')) {
  (async () => {
    const cache = await tier1();
    symbolCache = await L.feedSymbols(pythToEvaaCache);
    for (const [k, v] of await L.livePrices(pythToEvaaCache)) liveMap.set(k, v);
    lastPriceUpdate = Date.now();
    const ratios = computeRatios(cache);
    logNearMiss(ratios);
    await checkTriggers(ratios);
  })().then(() => process.exit(0)).catch((e) => { console.error('FATAL', e); process.exit(1); });
} else if (process.argv.includes('--tg-test')) {
  L.telegram('✅ EVAA monitor test message').then((ok) => { console.log('telegram:', ok ? 'OK' : 'FAILED'); process.exit(0); });
} else {
  loop().catch((e) => { console.error('FATAL', e); process.exit(1); });
}
