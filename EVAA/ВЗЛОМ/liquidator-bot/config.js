// ===============================================================
// EVAA stale-price liquidation MONITOR (read-only) — config
// ===============================================================
// minimal .env loader (no dependency)
(() => {
  const fs = require('fs'), path = require('path');
  const p = path.resolve(__dirname, '.env');
  if (!fs.existsSync(p)) return;
  for (const line of fs.readFileSync(p, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^['"]|['"]$/g, '');
  }
})();

module.exports = {
  // EVAA MAIN pool (funded). Note: different code-hash than the in-scope
  // Pyth-v8-ToB repo; uses the same Pyth oracle + prices_ttl=180.
  MAIN_POOL: 'EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr',

  // toncenter v3 (archival, reliable pagination) — key from env or here
  TONCENTER_BASE: 'https://toncenter.com/api/v3',
  TONCENTER_KEY: process.env.TONCENTER_KEY || '',

  // Pyth Hermes (live + OHLC) — no key needed
  HERMES_BASE: 'https://hermes.pyth.network',
  PYTH_BENCH_BASE: 'https://benchmarks.pyth.network',

  // tier1: slow full re-scan — recomputes each known position's flip factor
  // (collateral-price multiplier at which getIsLiquidable flips to true)
  SCAN_INTERVAL_MS: 5 * 60 * 1000,
  CANDIDATE_PAGES: 8,          // toncenter pages of recent txs to harvest users
  MAX_USERS_PER_SCAN: 400,
  STALE_WINDOW_S: 180,         // EVAA prices_ttl (vuln window)

  // live watch: prices come from a Hermes SSE stream (real-time, no polling).
  // every FAST_INTERVAL_MS the live/ref ratio is recomputed for cached positions;
  // only triggers an on-chain confirm (fork + getIsLiquidable) when price nears
  // a cached flip factor, throttled by CONFIRM_COOLDOWN_MS per position.
  FAST_INTERVAL_MS: 5 * 1000,
  TRIGGER_MARGIN: 0.03,        // re-check on-chain if live/ref ratio <= flipFactor*(1+margin)
  CONFIRM_COOLDOWN_MS: 15 * 1000, // min time between on-chain confirms for the same position
  HEARTBEAT_INTERVAL_MS: 60 * 60 * 1000, // periodic "alive" Telegram message
  FLIP_CACHE_FILE: './data/flip_cache.json',
  HONEST_ALERTED_FILE: './data/honest_alerted.json', // dedup set for "liquidatable@fresh, profitable" alerts

  // alert thresholds
  ALERT_BUFFER_PCT: 8,         // flag position if real buffer < this (within realistic wick range)
  WICK_LOOKBACK_DAYS: 14,      // measure recent max 180s round-trip wick of the driver feed
  WICK_DRIVER_SYMBOL: 'Crypto.TON/USD', // reference exploitable-wick magnitude

  // Telegram alert (fill TELEGRAM_TOKEN + TELEGRAM_CHAT via env)
  // secrets come from .env (see .env.example)
  TELEGRAM_TOKEN: process.env.TELEGRAM_TOKEN || '',
  TELEGRAM_CHAT: process.env.TELEGRAM_CHAT || '',
  // optional: http://user:pass@host:port — tunnel Telegram via CONNECT proxy
  // (needed on hosts where api.telegram.org is blocked directly)
  TG_PROXY: process.env.TG_PROXY || '',

  DATA_DIR: './data',
  USERS_FILE: './data/known_users.json', // persisted user set (catch idle positions)
};
