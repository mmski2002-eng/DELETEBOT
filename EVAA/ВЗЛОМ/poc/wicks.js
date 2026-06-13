const https = require('https');
function get(u){return new Promise(r=>{https.get(u,{headers:{'User-Agent':'x'}},x=>{let d='';x.on('data',c=>d+=c);x.on('end',()=>r({s:x.statusCode,d}));}).on('error',e=>r({s:0,d:e.message}));});}

const SYMBOLS = process.argv.slice(2).length ? process.argv.slice(2) : ['Crypto.TON/USD'];

(async () => {
  for (const sym of SYMBOLS) {
    const now = Math.floor(Date.now() / 1000);
    let candles = [];
    // 14 days in 2-day chunks at 1-min resolution
    for (let d = 0; d < 14; d += 2) {
      const to = now - d * 86400;
      const from = to - 2 * 86400;
      const u = 'https://benchmarks.pyth.network/v1/shims/tradingview/history?symbol=' + encodeURIComponent(sym) + '&resolution=1&from=' + from + '&to=' + to;
      const r = await get(u);
      let j; try { j = JSON.parse(r.d); } catch { continue; }
      if (!j.t) continue;
      for (let i = 0; i < j.t.length; i++) candles.push({ t: j.t[i], o: j.o[i], h: j.h[i], l: j.l[i], c: j.c[i] });
    }
    candles.sort((a, b) => a.t - b.t);
    if (!candles.length) { console.log(sym, 'no data'); continue; }
    const n = candles.length;
    console.log(`\n${sym}: ${n} 1-min candles over ~14d`);

    // intra-minute drops
    const intraDrops = candles.map(c => (c.o - c.l) / c.o * 100).sort((a, b) => b - a);
    console.log('  top intra-minute open->low drops %:', intraDrops.slice(0, 8).map(x => x.toFixed(2)).join(', '));

    // ~3-min round-trip dip: pre-dip close, trough over [i,i+1], recovery over [i+1,i+2] back to >=99% pre
    let best = 0, bestT = 0;
    for (let i = 1; i < n - 2; i++) {
      if (candles[i+1].t - candles[i].t > 180 || candles[i+2].t - candles[i].t > 240) continue;
      const pre = candles[i - 1].c;
      const lo = Math.min(candles[i].l, candles[i + 1].l);
      const rec = Math.max(candles[i + 1].c, candles[i + 2].c);
      const drop = (pre - lo) / pre * 100;
      if (rec >= pre * 0.99 && drop > best) { best = drop; bestT = candles[i].t; }
    }
    console.log('  max <=3min round-trip dip (recovers >=99%):', best.toFixed(2) + '%', best ? 'at ' + new Date(bestT * 1000).toISOString() : '');

    // count round-trip wicks by magnitude bucket
    let w3 = 0, w5 = 0, w8 = 0;
    for (let i = 1; i < n - 2; i++) {
      if (candles[i+1].t - candles[i].t > 180) continue;
      const pre = candles[i - 1].c; const lo = Math.min(candles[i].l, candles[i + 1].l); const rec = Math.max(candles[i + 1].c, candles[i + 2].c);
      const drop = (pre - lo) / pre * 100;
      if (rec >= pre * 0.99) { if (drop >= 3) w3++; if (drop >= 5) w5++; if (drop >= 8) w8++; }
    }
    console.log(`  round-trip wicks in 14d: >=3% : ${w3}, >=5% : ${w5}, >=8% : ${w8}`);
  }
})();
