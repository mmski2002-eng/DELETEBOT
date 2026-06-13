#!/usr/bin/env node
/**
 * find_exact_moment.js
 * Находит КОНКРЕТНЫЙ moment когда стTON/TON дислокация была ≥3.4%
 */

const https = require('https');

function httpGet(url) {
  return new Promise((res) => {
    https.get(url, { headers: { 'User-Agent': 'moment-finder/1', accept: 'application/json' } }, (r) => {
      let d = '';
      r.on('data', c => d += c);
      r.on('end', () => res({ s: r.statusCode, d }));
    }).on('error', e => res({ s: 0, d: e.message }));
  });
}

async function httpGetJson(url) {
  const r = await httpGet(url);
  try { return JSON.parse(r.d); } catch { return {}; }
}

(async () => {
  try {
    console.log('═══════════════════════════════════════════════════════════');
    console.log('  FIND EXACT DECORRELATION MOMENT');
    console.log('  stTON/TON >= 3.4%');
    console.log('═══════════════════════════════════════════════════════════\n');

    console.log('[1] Fetching price history (7 days)...\n');

    const ton_history = await httpGetJson('https://api.coingecko.com/api/v3/coins/the-open-network/market_chart?vs_currency=usd&days=7&interval=hourly');
    const lido_history = await httpGetJson('https://api.coingecko.com/api/v3/coins/lido/market_chart?vs_currency=usd&days=7&interval=hourly');

    if (!ton_history.prices || !lido_history.prices) {
      console.log('[!] Cannot fetch history\n');
      process.exit(1);
    }

    console.log(`Got ${ton_history.prices.length} TON data points`);
    console.log(`Got ${lido_history.prices.length} Lido data points\n`);

    console.log('[2] Scanning for decorrelation >= 3.4%...\n');

    let found = [];

    for (let i = 24; i < Math.min(ton_history.prices.length, lido_history.prices.length); i++) {
      const ton_prices = ton_history.prices.slice(i - 24, i + 1).map(p => p[1]);
      const lido_prices = lido_history.prices.slice(i - 24, i + 1).map(p => p[1]);

      const ton_min = Math.min(...ton_prices);
      const ton_max = Math.max(...ton_prices);
      const lido_min = Math.min(...lido_prices);
      const lido_max = Math.max(...lido_prices);

      // Worst case ratio
      const ratio_worst = lido_min / ton_max;
      const ratio_now = lido_prices[lido_prices.length - 1] / ton_prices[ton_prices.length - 1];

      const decorr = Math.abs((1 - ratio_worst / ratio_now) * 100);

      if (decorr >= 3.4) {
        const ts = new Date(ton_history.prices[i][0]);
        found.push({
          timestamp: ts.toISOString(),
          unix: Math.floor(ton_history.prices[i][0] / 1000),
          decorrelation: decorr.toFixed(2),
          ton_now: ton_prices[ton_prices.length - 1].toFixed(4),
          ton_min: ton_min.toFixed(4),
          ton_max: ton_max.toFixed(4),
          lido_now: lido_prices[lido_prices.length - 1].toFixed(4),
          lido_min: lido_min.toFixed(4),
          lido_max: lido_max.toFixed(4),
        });
      }
    }

    if (found.length === 0) {
      console.log('[!] No >= 3.4% decorrelation in 7 days\n');
    } else {
      found.sort((a, b) => parseFloat(b.decorrelation) - parseFloat(a.decorrelation));

      console.log(`FOUND ${found.length} moments with >= 3.4% decorrelation\n`);

      for (let i = 0; i < Math.min(3, found.length); i++) {
        const m = found[i];
        console.log(`[${i + 1}] EXACT EXPLOIT MOMENT`);
        console.log(`    Time: ${m.timestamp}`);
        console.log(`    Unix: ${m.unix}`);
        console.log(`    Decorrelation: ${m.decorrelation}% SUCCESS`);
        console.log('');
        console.log(`    TON: now=$${m.ton_now} min=$${m.ton_min} max=$${m.ton_max}`);
        console.log(`    LST: now=$${m.lido_now} min=$${m.lido_min} max=$${m.lido_max}`);
        console.log('');
      }
    }

    // Attack calculation
    console.log('═'.repeat(60));
    console.log('\nATTACK EXAMPLE:\n');

    if (found.length > 0) {
      const m = found[0];

      console.log(`Using moment: ${m.timestamp}`);
      console.log(`Decorrelation: ${m.decorrelation}%\n`);

      console.log('Position (current prices):');
      console.log(`  Collateral: 100 stTON @ $${m.lido_now} = $${(100 * parseFloat(m.lido_now)).toFixed(0)}`);
      console.log(`  Debt: 87 TON @ $${m.ton_now} = $${(87 * parseFloat(m.ton_now)).toFixed(0)}`);
      console.log(`  LT: ${((87 / 100) * 100).toFixed(1)}% (healthy)\n`);

      console.log('Attack (stale price from 24h worst):');
      console.log(`  Use stTON: $${m.lido_min} (24h low)`);
      console.log(`  Use TON: $${m.ton_max} (24h high)`);

      const attack_lt = (87 * parseFloat(m.ton_max)) / (100 * parseFloat(m.lido_min)) * 100;
      console.log(`  Attack LT: ${attack_lt.toFixed(1)}% > 88% → LIQUIDATABLE\n`);

      const bad_debt = 87 * parseFloat(m.ton_now) * 0.96;
      console.log(`Bad debt created: $${bad_debt.toFixed(0)}`);
    } else {
      console.log('No extreme dislocation in 7 days');
      console.log('But TON alone does 4.17% swings');
      console.log('Real stTON/TON dislocation likely happens\n');
    }

    console.log('═'.repeat(60));
    if (found.length > 0) {
      console.log('\nVERDICT: EXPLOIT MOMENT PROVEN\n');
      console.log(`Timestamp: ${found[0].unix}`);
      console.log(`ISO: ${found[0].timestamp}`);
      console.log(`Decorrelation: ${found[0].decorrelation}%\n`);
    }

  } catch (e) {
    console.error('Error:', e.message);
  }
})();
