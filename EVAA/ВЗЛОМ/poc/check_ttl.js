// Fetches EVAA master data BoC from a public API and parses prices_ttl
// per master-storage.fc layout:
//   data -> ref[2]=market_config; market_config: dict asset_config, int8 if_active,
//           msgaddr admin, ref oracles_config; oracles_config: msgaddr pyth, ref feeds_data, uint32 prices_ttl
const { Cell, Address } = require('@ton/core');

const CANDIDATES = process.argv.slice(2);
if (CANDIDATES.length === 0) {
  CANDIDATES.push('EQBKMfjX_a_dsOLm-juxyVZytFP7_KKnzGv6J01kGc72gVBp');
  CANDIDATES.push('EQDElsF7VdNEapM3P_cv1Tb5XQvkg2YwCZWDg_yFZUCKbxQl');
}

async function getDataBoc(addr) {
  const a = Address.parse(addr).toString({ urlSafe: true, bounceable: true });
  const tries = [
    { url: `https://tonapi.io/v2/blockchain/accounts/${a}`, pick: (j) => j.data },
    { url: `https://toncenter.com/api/v2/getAddressInformation?address=${a}`, pick: (j) => j.result && j.result.data },
  ];
  for (const t of tries) {
    try {
      const res = await fetch(t.url, { headers: { accept: 'application/json' } });
      if (!res.ok) { console.error(`  ${t.url} -> HTTP ${res.status}`); continue; }
      const j = await res.json();
      const data = t.pick(j);
      if (data) { console.error(`  data via ${t.url.split('/')[2]} (len ${data.length})`); return data; }
    } catch (e) { console.error(`  ${t.url} -> ${e.message}`); }
  }
  return null;
}

function toCell(data) {
  // tonapi returns hex; toncenter returns base64. Try both.
  const cleaned = data.startsWith('0x') ? data.slice(2) : data;
  if (/^[0-9a-fA-F]+$/.test(cleaned) && cleaned.length % 2 === 0) {
    try { return Cell.fromBoc(Buffer.from(cleaned, 'hex'))[0]; } catch (e) {}
  }
  return Cell.fromBase64(data);
}

function parseTtl(data) {
  const root = toCell(data).beginParse();
  root.loadRef(); // meta
  root.loadRef(); // upgrade_config
  const mc = root.loadRef().beginParse(); // market_config
  mc.loadMaybeRef(); // asset_config_collection
  const ifActive = mc.loadInt(8);
  mc.loadAddress(); // admin
  const oc = mc.loadRef().beginParse(); // oracles_config
  oc.loadAddress(); // pyth_address
  oc.loadRef();     // feeds_data
  const pricesTtl = oc.loadUint(32);
  return { ifActive, pricesTtl };
}

(async () => {
  for (const addr of CANDIDATES) {
    console.error(`\n=== ${addr} ===`);
    const data = await getDataBoc(addr);
    if (!data) { console.error('  no data'); continue; }
    try {
      const { ifActive, pricesTtl } = parseTtl(data);
      const sane = ifActive >= 0 && ifActive <= 1 && pricesTtl > 0 && pricesTtl < 100000;
      console.log(`  if_active=${ifActive}  prices_ttl=${pricesTtl}s  ${sane ? '<-- LOOKS LIKE EVAA MASTER' : '(layout parsed but values odd)'}`);
    } catch (e) {
      console.error('  parse failed (not the lending master / different layout): ' + e.message);
    }
  }
})();
