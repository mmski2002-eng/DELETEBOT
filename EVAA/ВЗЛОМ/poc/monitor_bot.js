// ===============================================================
// MONITOR BOT: EVAA MAIN pool stale-price vulnerability scanner
// Periodically scans user positions and reports those at risk.
// Real mainnet data, no sandbox forking needed for basic scan.
// ===============================================================
const { Address, Cell, Dictionary, beginCell } = require('@ton/core');
const https = require('https');
const fs = require('fs');

// ─── Configuration ─────────────────────────────────────────────
const CONFIG = {
  MAIN_POOL: 'EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr',
  TON_ASSET_ID: '1a4219fe5e60d63af2a3cc7dce6fec69b45c6b5718497a6148e7c232ac87bd8a',
  SCAN_INTERVAL_MS: 5 * 60 * 1000,          // every 5 minutes
  STALE_WINDOW_S: 180,                        // EVAA prices_ttl
  ALERT_THRESHOLD_PCT: 20,                    // alert if buffer < 20%
  ESTIMATED_TON_PRICE: 3.00,
  ESTIMATED_STABLE_PRICE: 1.00,
  DATA_DIR: './monitor_data',
};

// ─── Helpers ───────────────────────────────────────────────────
function httpGet(u) {
  return new Promise((res) => {
    https.get(u, { headers: { 'User-Agent': 'x', accept: 'application/json' } }, (r) => {
      let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d }));
    }).on('error', e => res({ s: 0, d: e.message }));
  });
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function toCell(hex) {
  if (!hex) return null;
  try { return Cell.fromBoc(Buffer.from(hex, 'hex'))[0]; } catch (e) { return null; }
}

function assetName(idHex) {
  const map = {
    [CONFIG.TON_ASSET_ID]: 'TON',
    'ca9006bd3fb03d355daeeff93b24be90afaa6e3ca0073ff5720f8a852c933278': 'USDT',
  };
  return map[idHex] || `0x${idHex.slice(0, 10)}...`;
}

function estimatePrice(assetIdHex) {
  if (assetIdHex === CONFIG.TON_ASSET_ID) return CONFIG.ESTIMATED_TON_PRICE;
  return CONFIG.ESTIMATED_STABLE_PRICE;
}

function formatTime(ts) {
  return new Date(ts).toISOString().replace('T', ' ').slice(0, 19);
}

// ─── Mainnet Data Fetcher with retry ──────────────────────────
async function fetchAccountData(addr, retries = 3) {
  for (let attempt = 0; attempt < retries; attempt++) {
    try {
      const a = Address.parse(addr).toString({ urlSafe: true, bounceable: true });
      const r = await httpGet(`https://tonapi.io/v2/blockchain/accounts/${a}`);
      
      if (r.s === 200) {
        const j = JSON.parse(r.d);
        if (!j.data) return null;
        const dataCell = toCell(j.data);
        return { dataCell, codeHex: j.code, balance: j.balance, status: j.status };
      }
      
      if (r.s === 429 || r.s === 502 || r.s === 503) {
        // Rate limited or temporary error — wait and retry
        await sleep(1000 * (attempt + 1));
        continue;
      }
      
      // Other error — address doesn't exist or invalid
      return null;
    } catch (e) {
      if (attempt < retries - 1) await sleep(500);
      else return null;
    }
  }
  return null;
}

// Parse user SC storage to extract principals dict
function parseUserStorage(dataCell) {
  if (!dataCell) return null;
  try {
    const cs = dataCell.beginParse();
    const codeVersion = cs.loadCoins();
    const masterAddress = cs.loadAddress();
    const ownerAddress = cs.loadAddress();
    
    const userPrincipals = cs.loadDict(
      Dictionary.Keys.BigUint(256),
      { serialize: () => {}, parse: (s) => {
        const principal = s.loadIntBig(64);
        let origFee = null, amountBorrowed = null, lastBorrowSeqno = null;
        if (s.remainingBits > 0) {
          origFee = s.loadUintBig(64);
          if (s.remainingBits > 0) { amountBorrowed = s.loadUintBig(64);
            if (s.remainingBits > 0) lastBorrowSeqno = s.loadUintBig(64);
          }
        }
        return { principal, origFee, amountBorrowed, lastBorrowSeqno };
      }}
    );
    
    return {
      codeVersion: Number(codeVersion),
      masterAddress: masterAddress.toString(),
      ownerAddress: ownerAddress.toString(),
      userPrincipals,
    };
  } catch (e) {
    return null;
  }
}

// Get user addresses from MAIN pool tx history
async function findUserCandidates(masterAddr, maxPages = 8) {
  const cps = new Set();
  let before = '';
  for (let page = 0; page < maxPages; page++) {
    const a = Address.parse(masterAddr).toString({ urlSafe: true, bounceable: true });
    const r = await httpGet(`https://tonapi.io/v2/blockchain/accounts/${a}/transactions?limit=100${before}`);
    const j = JSON.parse(r.d);
    const txs = j.transactions || [];
    if (!txs.length) break;
    for (const tx of txs) {
      if (tx.in_msg && tx.in_msg.source && tx.in_msg.source.address) cps.add(tx.in_msg.source.address);
      for (const om of (tx.out_msgs || []))
        if (om.destination && om.destination.address) cps.add(om.destination.address);
    }
    before = `&before_lt=${txs[txs.length - 1].lt}`;
    await sleep(500); // rate limit
  }
  return [...cps];
}

// ─── Liquidation Analysis ──────────────────────────────────────
function calculateBuffer(assets, estPrices) {
  // assets: [{idHex, principal, ...}]
  // Returns { ltv, bufferPct, collUsd, debtUsd }
  
  let totalCollUsd = 0;
  let totalDebtUsd = 0;
  
  for (const a of assets) {
    const price = estPrices[a.idHex] || estimatePrice(a.idHex);
    const value = Number(a.principal) / 1e9 * price;
    if (a.principal > 0n) totalCollUsd += value;
    if (a.principal < 0n) totalDebtUsd += Math.abs(value);
  }
  
  if (totalCollUsd <= 0 || totalDebtUsd <= 0) return null;
  
  // Simplified LTV check
  // In EVAA, liquidation threshold varies by asset (typically 75-85%)
  // We estimate: liquidatable when debt > coll * 0.8
  const ltv = totalDebtUsd / totalCollUsd;
  const liqThreshold = 0.8; // estimated average liquidation threshold
  const maxDebt = totalCollUsd * liqThreshold;
  const bufferUsd = maxDebt - totalDebtUsd;
  const bufferPct = (bufferUsd / maxDebt) * 100;
  
  return {
    ltv: ltv * 100,
    bufferPct: Math.max(0, bufferPct),
    collUsd: totalCollUsd,
    debtUsd: totalDebtUsd,
    maxDebtUsd: maxDebt,
    liqThreshold
  };
}

// ─── Main Scanner ──────────────────────────────────────────────
class EvaaMonitor {
  constructor() {
    this.knownUsers = new Map();  // address -> last scan data
    this.state = {
      lastScan: 0,
      candidatesFound: 0,
      vulnerablePositions: [],
      alertsSent: 0,
    };
    
    if (!fs.existsSync(CONFIG.DATA_DIR)) {
      fs.mkdirSync(CONFIG.DATA_DIR, { recursive: true });
    }
  }
  
  async scanOnce() {
    const scanId = Date.now();
    console.log(`\n${'='.repeat(70)}`);
    console.log(`[${formatTime(scanId)}] 🔍 Scan #${Math.round(scanId/1000)} started`);
    console.log(`${'='.repeat(70)}\n`);
    
    // Step 1: Find candidates
    console.log('  📡 Fetching MAIN pool transaction participants...');
    const candidates = await findUserCandidates(CONFIG.MAIN_POOL);
    console.log(`     Found ${candidates.length} unique addresses`);
    
    // Step 2: Scan each candidate
    console.log('\n  📊 Scanning user positions...');
    const positions = [];
    
    for (let i = 0; i < candidates.length; i++) {
      const addr = candidates[i];
      
      // Skip known non-user SCs
      if (this.knownUsers.has(addr) && this.knownUsers.get(addr) === null) continue;
      
      try {
        const acc = await fetchAccountData(addr);
        if (!acc || !acc.dataCell) continue;
        
        const parsed = parseUserStorage(acc.dataCell);
        if (!parsed) continue;
        
        // Check if this is an EVAA user SC (matched master address)
        // Normalize both addresses for comparison
        const masterExpected = Address.parse(CONFIG.MAIN_POOL).toString();
        const masterActual = Address.parse(parsed.masterAddress).toString();
        if (masterActual !== masterExpected) continue;
        
        // Collect principals
        const assets = [];
        for (const [k, v] of parsed.userPrincipals) {
          if (v.principal === 0n) continue;
          const idHex = k.toString(16).padStart(64, '0');
          assets.push({ idHex, principal: v.principal, name: assetName(idHex) });
        }
        
        // Check for debt + collateral
        let hasDebt = false, hasColl = false;
        for (const a of assets) {
          if (a.principal < 0n) hasDebt = true;
          if (a.principal > 0n) hasColl = true;
        }
        
        if (!(hasDebt && hasColl)) {
          this.knownUsers.set(addr, null);
          continue;
        }
        
        // Save as known user SC
        this.knownUsers.set(addr, parsed);
        
        // Calculate buffer
        const analysis = calculateBuffer(assets);
        if (!analysis) continue;
        
        positions.push({
          address: addr,
          owner: parsed.ownerAddress,
          assets,
          analysis,
          scannedAt: scanId,
        });
        
        process.stdout.write(`  [${i+1}/${candidates.length}] ✅ ${addr.slice(0, 16)}... buffer=${analysis.bufferPct.toFixed(1)}%\r`);
        
        if (i % 5 === 4) await sleep(500); // rate limit
        else await sleep(150); // minimal delay between requests
      } catch (e) {
        // Not an EVAA user SC
        this.knownUsers.set(addr, null);
      }
    }
    
    console.log(`\n\n  ✅ Scan complete. Found ${positions.length} positions with debt+collateral`);
    
    // Step 3: Analyze vulnerability
    console.log('\n  🎯 Vulnerability analysis:');
    
    const vulnerable = positions
      .map(p => ({
        ...p,
        // For stale price: how much would price need to drop to trigger liquidation
        // At stale price, collateral value drops proportionally
        staleDropNeeded: p.analysis.bufferPct / p.analysis.liqThreshold * 100, // approx
      }))
      .sort((a, b) => a.staleDropNeeded - b.staleDropNeeded);
    
    this.state.vulnerablePositions = vulnerable;
    
    // Report
    if (vulnerable.length > 0) {
      console.log(`\n  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐`);
      console.log(`  │ #  │ Address                  │ Coll→Debt      │ Buffer  │ Stale drop│ Coll $    │ Debt $    │`);
      console.log(`  ├────────────────────────────────────────────────────────────────────────────────────────────────────┤`);
      
      for (let i = 0; i < Math.min(vulnerable.length, 10); i++) {
        const p = vulnerable[i];
        const label = p.address.slice(0, 16) + '...';
        const mainColl = p.assets.find(a => a.principal > 0n)?.name || '?';
        const mainDebt = p.assets.find(a => a.principal < 0n)?.name || '?';
        
        console.log(`  │ ${String(i+1).padStart(2)} │ ${label.padEnd(20)} │ ${mainColl.padEnd(10)}→${mainDebt.padEnd(8)} │ ${p.analysis.bufferPct.toFixed(1).padStart(5)}% │ ${(p.staleDropNeeded/100*CONFIG.STALE_WINDOW_S).toFixed(0).padStart(3)}s ago │ $${p.analysis.collUsd.toFixed(0).padStart(8)} │ $${p.analysis.debtUsd.toFixed(0).padStart(8)} │`);
      }
      console.log(`  └────────────────────────────────────────────────────────────────────────────────────────────────────┘`);
      
      // Alert if any position is critically close
      if (vulnerable.length > 0) {
        const critical = vulnerable.filter(p => p.analysis.bufferPct < CONFIG.ALERT_THRESHOLD_PCT);
        if (critical.length > 0) {
          console.log(`\n  🚨 ALERT: ${critical.length} position(s) with buffer < ${CONFIG.ALERT_THRESHOLD_PCT}%:`);
          for (const p of critical) {
            console.log(`     ⚠️  ${p.address.slice(0, 24)}...  buffer=${p.analysis.bufferPct.toFixed(1)}%  stale=${(p.staleDropNeeded/100*CONFIG.STALE_WINDOW_S).toFixed(0)}s ago`);
          }
          this.state.alertsSent++;
        }
      }
    }
    
    // Save to history
    const history = {
      scanId,
      timestamp: formatTime(scanId),
      candidates,
      totalPositions: positions.length,
      vulnerableCount: vulnerable.length,
      criticalCount: vulnerable.length > 0 ? vulnerable.filter(p => p.analysis.bufferPct < CONFIG.ALERT_THRESHOLD_PCT).length : 0,
      topVulnerable: vulnerable.slice(0, 20).map(p => ({
        address: p.address,
        owner: p.owner,
        bufferPct: p.analysis.bufferPct,
        collUsd: Math.round(p.analysis.collUsd),
        debtUsd: Math.round(p.analysis.debtUsd),
        staleWindowSec: Math.round(p.staleDropNeeded / 100 * CONFIG.STALE_WINDOW_S),
        assets: p.assets.map(a => ({
          name: a.name,
          principal: a.principal.toString(),
          usdValue: Math.round(Number(a.principal) / 1e9 * estimatePrice(a.idHex))
        }))
      })),
    };
    
    fs.writeFileSync(
      `${CONFIG.DATA_DIR}/scan_${scanId}.json`,
      JSON.stringify(history, null, 2)
    );
    
    this.state.lastScan = scanId;
    this.state.candidatesFound = candidates.length;
    
    console.log(`\n  💾 Scan saved to ${CONFIG.DATA_DIR}/scan_${scanId}.json`);
    
    // Summary
    const critCount = vulnerable.length > 0 ? vulnerable.filter(p => p.analysis.bufferPct < CONFIG.ALERT_THRESHOLD_PCT).length : 0;
    console.log(`\n  ─── SCAN SUMMARY ───`);
    console.log(`  Addresses scanned:    ${candidates.length}`);
    console.log(`  User SCs found:       ${positions.length}`);
    console.log(`  Vulnerable (stale):   ${vulnerable.length}`);
    console.log(`  Critical (<${CONFIG.ALERT_THRESHOLD_PCT}%):   ${critCount}`);
    console.log(`  Next scan in:         ${CONFIG.SCAN_INTERVAL_MS/60000} min`);
    console.log(`  ${'─'.repeat(50)}`);
    
    return history;
  }
  
  async start() {
    console.log('╔══════════════════════════════════════════════════════════════════╗');
    console.log('║  EVAA MAIN Pool Stale-Price Monitor Bot                        ║');
    console.log('║  Scans every ' + CONFIG.SCAN_INTERVAL_MS/60000 + ' min | Alert at <' + CONFIG.ALERT_THRESHOLD_PCT + '% buffer      ║');
    console.log('╚══════════════════════════════════════════════════════════════════╝');
    console.log(`  Pool:     ${CONFIG.MAIN_POOL}`);
    console.log(`  TTL:      ${CONFIG.STALE_WINDOW_S}s`);
    console.log(`  Data dir: ${CONFIG.DATA_DIR}/`);
    console.log(`  Press Ctrl+C to stop\n`);
    
    // Initial scan
    await this.scanOnce();
    
    // Periodic scans
    while (true) {
      console.log(`\n  ⏳ Next scan in ${CONFIG.SCAN_INTERVAL_MS/60000} min...`);
      await sleep(CONFIG.SCAN_INTERVAL_MS);
      try {
        await this.scanOnce();
      } catch (e) {
        console.error(`\n  ❌ Scan error: ${e.message}`);
        console.log('  🔄 Retrying next cycle...');
      }
    }
  }
  
  generateReport() {
    const history = this.state;
    const vulnerable = history.vulnerablePositions;
    
    let report = `# EVAA MAIN Pool Monitor Report\n\n`;
    report += `Last scan: ${formatTime(history.lastScan)}\n`;
    report += `Total positions tracked: ${vulnerable.length}\n\n`;
    
    if (vulnerable.length > 0) {
      report += `| # | Address | Buffer | Stale Window | Coll $ | Debt $ |\n`;
      report += `|---|---------|-------|-------------|--------|--------|\n`;
      for (let i = 0; i < vulnerable.length; i++) {
        const p = vulnerable[i];
        report += `| ${i+1} | ${p.address.slice(0, 20)}... | ${p.analysis.bufferPct.toFixed(1)}% | ${(p.staleDropNeeded/100*CONFIG.STALE_WINDOW_S).toFixed(0)}s | $${Math.round(p.analysis.collUsd)} | $${Math.round(p.analysis.debtUsd)} |\n`;
      }
    }
    
    return report;
  }
}

// ─── Run ────────────────────────────────────────────────────────
const monitor = new EvaaMonitor();

if (require.main === module) {
  // Run once if called with --once
  if (process.argv.includes('--once')) {
    monitor.scanOnce()
      .then(() => {
        console.log(`\n📄 Report:\n${monitor.generateReport()}`);
      })
      .catch(e => { console.error('FATAL:', e); process.exit(1); });
  } else {
    // Continuous mode
    monitor.start().catch(e => { console.error('FATAL:', e); process.exit(1); });
  }
}

module.exports = { EvaaMonitor };
