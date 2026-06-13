// ================================================================
// sandbox_liq_cheapest.js
// Sandbox-симуляция ликвидации позиции 0:54FCA4...0113CF
// Исправлено:
//  - одиночный prefetch обоих аккаунтов (нет двойного tonapi.io → 429)
//  - compound feed pricing (stTON = TON_USD × stTON/TON_rate)
//  - показывает полный 4-tx refund flow даже если позиция здорова
// ================================================================
const { Blockchain, createShardAccount, internal } = require('@ton/sandbox');
const { Address, Cell, Dictionary, TupleBuilder, beginCell, toNano } = require('@ton/core');
const { fetchAccount } = require('./fork');
const https = require('https');

// ─── Константы ──────────────────────────────────────────────────
const MAIN_POOL   = 'EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr';
// USER_SC: адрес смарт-контракта позиции (user SC), не owner wallet
const USER_SC     = '0:54FCA4241ABF6FAAD51226E4616E54E6740C912031E67212BB62FC98D80113CF';
const COLLATERAL_ID = BigInt('0x3313e2f57ba870af34480350c789b0987d15b43a53172bfce294de21e7d724e7');
const TON_ASSET_ID  = BigInt('0x1a4219fe5e60d63af2a3cc7dce6fec69b45c6b5718497a6148e7c232ac87bd8a');
const LIQUIDATE_AMOUNT = 4012600290n;  // nanoTON (TON debt)
const HERMES_BASE = 'https://hermes.pyth.network';
const SCALE = 1_000_000_000n;

const FAKE_PYTH_ADDR = Address.parse('0:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
const MY_LIQUIDATOR  = Address.parse('0:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');

// ─── Утилиты ────────────────────────────────────────────────────
function httpGet(url) {
  return new Promise((res) => {
    https.get(url, { headers: { 'User-Agent': 'evaa-sandbox/1', accept: 'application/json' } }, (r) => {
      let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d }));
    }).on('error', e => res({ s: 0, d: e.message }));
  });
}
async function httpGetJson(url) {
  const r = await httpGet(url);
  try { return JSON.parse(r.d); } catch { return {}; }
}

// ─── Читаем owner_address из user SC data ───────────────────────
// user SC storage: coins(version) + addr(master) + addr(owner) + ...
function readOwnerFromUserSC(userAccData) {
  const ds = userAccData.beginParse();
  ds.loadCoins();    // user_version
  ds.loadAddress();  // master_address
  return ds.loadAddress(); // owner_address
}

// ─── Парсим MAIN pool data (без HTTP) ───────────────────────────
// feeds: Map<pythId_bigint, {evaaId, multiplierPythId}> (512-bit values!)
// multiplierPythId != 0n → compound feed (price = ref_price × orig_price)
function parseMasterInfo(acc) {
  const root = acc.data.beginParse();
  root.loadRef(); // meta
  root.loadRef(); // upgrade_config
  const mc = root.loadRef().beginParse();

  // market_config: dict(asset_cfg) + int(8) + addr + ref(oracles_info) + dict(tokens_keys) + addr
  const assetCfgCell   = mc.loadMaybeRef();
  const ifActive       = mc.loadInt(8);
  const admin          = mc.loadAddress();
  const oraclesInfoCell = mc.loadRef();
  const tokenKeysCell  = mc.loadMaybeRef();
  const supervisor     = mc.loadAddress();

  // oracles_info: addr + ref(feeds_data) + uint32 + uint64*3
  const oi = oraclesInfoCell.beginParse();
  const pythAddr     = oi.loadAddress();
  const feedsDataCell = oi.loadRef();
  const pricesTtl    = oi.loadUint(32);
  const computeBaseGas = oi.loadUintBig(64);
  const computePerGas  = oi.loadUintBig(64);
  const singleFee      = oi.loadUintBig(64);

  // feeds_data: pyth_to_evaa_map (256-key, 256+256? value) + evaa_refs dict
  const fd = feedsDataCell.beginParse();
  const pythToEvaaDict = fd.loadDict(
    Dictionary.Keys.BigUint(256),
    {
      serialize: () => {},
      // Value = evaaId(256) + optional multiplierPythId(256)
      parse: (s) => {
        const evaaId = s.loadUintBig(256);
        const multiplierPythId = s.remainingBits >= 256 ? s.loadUintBig(256) : 0n;
        return { evaaId, multiplierPythId };
      },
    }
  );

  const feeds = new Map();
  for (const [k, v] of pythToEvaaDict) feeds.set(k, v);

  console.log(`  prices_ttl: ${pricesTtl}s | pyth_address: ${pythAddr.toString()}`);
  console.log(`  feeds count: ${feeds.size}`);
  for (const [p, { evaaId, multiplierPythId }] of feeds) {
    const compound = multiplierPythId !== 0n ? ` [× 0x${multiplierPythId.toString(16).slice(0,8)}...]` : '';
    console.log(`    Pyth 0x${p.toString(16).slice(0,12)}... → EVAA 0x${evaaId.toString(16).slice(0,12)}...${compound}`);
  }

  return {
    acc, feeds, oraclesInfoCell, feedsDataCell, pricesTtl,
    computeBaseGas, computePerGas, singleFee,
    assetCfgCell, ifActive, admin, tokenKeysCell, supervisor,
  };
}

// ─── Живые цены из Hermes (raw int64) ───────────────────────────
async function getLivePricesRaw(feeds) {
  console.log('\n[2] Получаем живые цены из Hermes...');
  const ids = [...feeds.keys()].map(id => 'ids[]=' + id.toString(16).padStart(64, '0')).join('&');
  const j = await httpGetJson(`${HERMES_BASE}/v2/updates/price/latest?${ids}&parsed=true`);
  if (!j.parsed || !j.parsed.length) throw new Error('Hermes: нет данных');

  const raw = new Map();
  for (const p of j.parsed) {
    const id = BigInt('0x' + p.id.toLowerCase());
    const priceFloat = Number(p.price.price) * Math.pow(10, p.price.expo);
    raw.set(id, {
      price_raw: BigInt(p.price.price),
      conf_raw:  BigInt(p.price.conf),
      expo:      p.price.expo,
      timestamp: p.price.publish_time,
      price_float: priceFloat,
    });
    const feedEntry = feeds.get(id);
    const evaaTag = feedEntry ? `EVAA 0x${feedEntry.evaaId.toString(16).slice(0,8)}...` : '(unknown)';
    console.log(`  0x${p.id.slice(0,12)}... [${evaaTag}] → $${priceFloat.toFixed(4)} (raw ${p.price.price}, expo ${p.price.expo})`);
  }
  return raw;
}

// ─── EVAA prices dict для getIsLiquidable ───────────────────────
// Правильно вычисляет compound feeds: price = p_ref * SCALE / s_ref * p_orig / s_orig
function buildEvaaPricesDict(feeds, rawPrices) {
  const V = { serialize: (s, b) => b.storeCoins(s), parse: (s) => s.loadCoins() };
  const d = Dictionary.empty(Dictionary.Keys.BigUint(256), V);

  for (const [pythId, feedEntry] of feeds) {
    const r = rawPrices.get(pythId);
    if (!r) continue;

    let evaaPrice;
    if (feedEntry.multiplierPythId !== 0n) {
      // Compound: price = p_referred * scale / s_referred * p_original / s_original
      const ref = rawPrices.get(feedEntry.multiplierPythId);
      if (!ref) continue;
      const s_orig = BigInt(10 ** (-r.expo));
      const s_ref  = BigInt(10 ** (-ref.expo));
      evaaPrice = ref.price_raw * SCALE / s_ref * r.price_raw / s_orig;
    } else {
      const scale = BigInt(10 ** (-r.expo));
      evaaPrice = r.price_raw * SCALE / scale;
    }

    if (evaaPrice > 0n) d.set(feedEntry.evaaId, evaaPrice);
  }
  return beginCell().storeDictDirect(d).endCell();
}

// ─── price_feeds_cell для Pyth-callback (linked list) ───────────
function buildPriceFeedsCell(feeds, rawPrices) {
  const entries = [];
  for (const [pythId, r] of rawPrices) {
    if (!feeds.has(pythId)) continue;
    entries.push({ pythId, r });
  }
  if (!entries.length) throw new Error('Нет данных для price_feeds_cell');

  let tail = null;
  for (let i = entries.length - 1; i >= 0; i--) {
    const { pythId, r } = entries[i];
    const currentPriceCell = beginCell()
      .storeInt(r.price_raw, 64)
      .storeUint(r.conf_raw, 64)
      .storeInt(r.expo, 32)
      .storeUint(r.timestamp, 64)
      .endCell();

    const priceDataCell = beginCell().storeRef(currentPriceCell).endCell();

    let item = beginCell()
      .storeUint(pythId, 256)
      .storeRef(priceDataCell);
    if (tail !== null) item = item.storeRef(tail);
    tail = item.endCell();
  }
  return tail;
}

// ─── Патчим MAIN data: pyth_address → FAKE_PYTH ─────────────────
function patchMainData(mainData, fakePythAddr, feedsDataCell, pricesTtl,
    computeBaseGas, computePerGas, singleFee,
    assetCfgCell, ifActive, admin, tokenKeysCell, supervisor) {

  const newOraclesInfo = beginCell()
    .storeAddress(fakePythAddr)
    .storeRef(feedsDataCell)
    .storeUint(pricesTtl, 32)
    .storeUint(computeBaseGas, 64)
    .storeUint(computePerGas, 64)
    .storeUint(singleFee, 64)
    .endCell();

  const newMC = beginCell()
    .storeMaybeRef(assetCfgCell)
    .storeInt(ifActive, 8)
    .storeAddress(admin)
    .storeRef(newOraclesInfo)
    .storeMaybeRef(tokenKeysCell)
    .storeAddress(supervisor);

  // root: meta + upgrade_config + market_config + store_dict(asset_dyn)
  const rootSlice = mainData.beginParse();
  const meta          = rootSlice.loadRef();
  const upgradeConfig = rootSlice.loadRef();
  rootSlice.loadRef(); // отбрасываем старый market_config
  const assetDynBit = rootSlice.loadBit();
  const assetDynRef = assetDynBit ? rootSlice.loadRef() : null;

  const newRoot = beginCell()
    .storeRef(meta)
    .storeRef(upgradeConfig)
    .storeRef(newMC.endCell())
    .storeBit(assetDynBit);
  if (assetDynRef) newRoot.storeRef(assetDynRef);
  return newRoot.endCell();
}

// ─── Pyth→MAIN callback message ─────────────────────────────────
function buildPythCallbackMessage(priceFeedsCell, rawPrices, queryId, ownerAddr) {
  const customResponsePayload = beginCell().endCell();
  const responsePacked = beginCell().storeRef(customResponsePayload).endCell();

  // parse_liquidate_master_message: amounts = uint64 (не coins!), include_user_code = int(2)
  const opBody = beginCell()
    .storeAddress(ownerAddr)          // borrower_address = owner EOA wallet
    .storeUint(COLLATERAL_ID, 256)    // collateral_asset_id
    .storeUint(1n, 64)                // min_collateral_amount (uint64)
    .storeInt(0n, 2)                  // include_user_code (int2)
    .storeUint(LIQUIDATE_AMOUNT, 64)  // liquidate_incoming_amount (uint64)
    .storeMaybeRef(null)              // requested_ref_tokens
    .storeRef(responsePacked)
    .endCell();

  const opPayload = beginCell()
    .storeUint(3, 32)   // op::liquidate_master
    .storeUint(queryId, 64)
    .storeRef(opBody)
    .endCell();

  // Pyth callback: op(5) + uint8(numFeeds) + ref(feeds) + addr(sender) + ref(op)
  return beginCell()
    .storeUint(5, 32)
    .storeUint(rawPrices.size, 8)
    .storeRef(priceFeedsCell)
    .storeAddress(MY_LIQUIDATOR)
    .storeRef(opPayload)
    .endCell();
}

// ─── MAIN ────────────────────────────────────────────────────────
async function main() {
  console.log('╔═══════════════════════════════════════════════════════════════╗');
  console.log('║  EVAA Sandbox: позиция 0:54FCA4...0113CF                     ║');
  console.log('║  coll≈$57  debt≈$47  (алерт бота — ложное срабатывание)      ║');
  console.log('╚═══════════════════════════════════════════════════════════════╝');

  // ── 1. Prefetch обоих аккаунтов ОДИН РАЗ (избегаем двойного fetch MAIN) ──
  console.log('\n[1] Prefetch MAIN + user SC из mainnet (parallel)...');
  const [mainRaw, userRaw] = await Promise.all([
    fetchAccount(MAIN_POOL),
    fetchAccount(USER_SC),
  ]);
  console.log(`  MAIN:    ${mainRaw.address.toString()}`);
  console.log(`  User SC: ${userRaw.address.toString()}`);

  console.log('\n[1b] Парсим конфигурацию MAIN...');
  const info = parseMasterInfo(mainRaw);

  // ── 2. Живые цены ────────────────────────────────────────────────
  const rawPrices = await getLivePricesRaw(info.feeds);
  if (!rawPrices.size) throw new Error('Не получили цены из Hermes');

  // ── 3. Создаём sandbox, ставим аккаунты (используем уже скачанные данные) ─
  console.log('\n[3] Форкаем аккаунты в sandbox...');
  const bc = await Blockchain.create();
  // bc.now после fetch цен — гарантируем TTL check пройдёт
  bc.now = Math.floor(Date.now() / 1000);

  await bc.setShardAccount(mainRaw.address, createShardAccount({
    address:   mainRaw.address,
    code:      mainRaw.code,
    data:      mainRaw.data,
    balance:   mainRaw.balance > toNano('100') ? mainRaw.balance : toNano('100'),
    workchain: 0,
  }));
  console.log(`  MAIN forked (balance=${Number(mainRaw.balance) / 1e9} TON)`);

  await bc.setShardAccount(userRaw.address, createShardAccount({
    address:   userRaw.address,
    code:      userRaw.code,
    data:      userRaw.data,
    balance:   userRaw.balance > toNano('1') ? userRaw.balance : toNano('1'),
    workchain: 0,
  }));
  console.log(`  User SC forked (balance=${Number(userRaw.balance) / 1e9} TON)`);

  const ownerAddress = readOwnerFromUserSC(userRaw.data);
  console.log(`  Owner wallet: ${ownerAddress.toString()}`);

  // ── 4. getIsLiquidable с правильными compound-ценами ─────────────
  console.log('\n[4] Проверяем getIsLiquidable (compound EVAA prices)...');
  const cfgCell = (await bc.runGetMethod(mainRaw.address, 'getAssetsConfig', [])).stackReader.readCell();
  const dynCell = (await bc.runGetMethod(mainRaw.address, 'getAssetsData',   [])).stackReader.readCell();

  const evaaPricesCell = buildEvaaPricesDict(info.feeds, rawPrices);

  // Показываем вычисленные EVAA цены
  const evaaD = Dictionary.loadDirect(
    Dictionary.Keys.BigUint(256),
    { serialize: () => {}, parse: (s) => s.loadCoins() },
    evaaPricesCell
  );
  for (const [k, v] of evaaD) {
    let name = `0x${k.toString(16).slice(0,12)}...`;
    if (k === COLLATERAL_ID) name = 'COLLATERAL (stTON compound)';
    if (k === TON_ASSET_ID)  name = 'TON';
    console.log(`  EVAA price ${name}: ${(Number(v) / 1e9).toFixed(4)} USD`);
  }

  const tb = new TupleBuilder();
  tb.writeCell(cfgCell);
  tb.writeCell(dynCell);
  tb.writeCell(evaaPricesCell);
  const liqResult = await bc.runGetMethod(userRaw.address, 'getIsLiquidable', tb.build());
  const isLiq = liqResult.exitCode === 0 && liqResult.stackReader.readBigNumber() === -1n;
  console.log(`  getIsLiquidable = ${isLiq ? '✅ TRUE' : '❌ FALSE (позиция здорова)'} (exit=${liqResult.exitCode})`);

  // ── 5. Балансы позиции ────────────────────────────────────────────
  console.log('\n[5] Балансы позиции...');
  const BVAL = { serialize: () => {}, parse: (s) => s.loadIntBig(65) };
  const tb2 = new TupleBuilder(); tb2.writeCell(dynCell);
  const balResult = await bc.runGetMethod(userRaw.address, 'getAccountBalances', tb2.build());
  if (balResult.exitCode === 0) {
    const balCell = balResult.stackReader.readCellOpt();
    if (balCell) {
      const bals = Dictionary.loadDirect(Dictionary.Keys.BigUint(256), BVAL, balCell);
      for (const [k, v] of bals) {
        if (v === 0n) continue;
        const type = v > 0n ? 'ЗАЛОГ' : 'ДОЛГ ';
        const dec9 = Number(v < 0n ? -v : v) / 1e9;
        let name = `0x${k.toString(16).slice(0,12)}...`;
        if (k === COLLATERAL_ID) name = 'stTON (COLLATERAL)';
        if (k === TON_ASSET_ID)  name = 'TON';
        console.log(`  ${type}: ${name}: ${dec9.toFixed(6)}`);
      }
    }
  }

  if (!isLiq) {
    console.log('\n  ⚠️  FALSE POSITIVE: бот использует простые цены stTON/TON ($1.12)');
    console.log('     Правильная цена stTON = TON_USD × stTON_rate (compound) → позиция здорова.');
    console.log('  → Продолжаем симуляцию: показываем полный 4-tx flow (refund)...');
  }

  // ── 6. Патчим MAIN: pyth_address → FAKE_PYTH ─────────────────────
  console.log('\n[6] Патчим MAIN storage (pyth_address → FAKE_PYTH)...');
  const patchedData = patchMainData(
    mainRaw.data,
    FAKE_PYTH_ADDR,
    info.feedsDataCell, info.pricesTtl,
    info.computeBaseGas, info.computePerGas, info.singleFee,
    info.assetCfgCell, info.ifActive, info.admin,
    info.tokenKeysCell, info.supervisor
  );

  await bc.setShardAccount(mainRaw.address, createShardAccount({
    address:   mainRaw.address,
    code:      mainRaw.code,
    data:      patchedData,
    balance:   mainRaw.balance > toNano('100') ? mainRaw.balance : toNano('100'),
    workchain: 0,
  }));
  console.log(`  FAKE_PYTH: ${FAKE_PYTH_ADDR.toString()}`);

  // Создаём FAKE_PYTH account в sandbox
  await bc.setShardAccount(FAKE_PYTH_ADDR, createShardAccount({
    address:   FAKE_PYTH_ADDR,
    code:      beginCell().endCell(),
    data:      beginCell().endCell(),
    balance:   toNano('100'),
    workchain: 0,
  }));

  // Создаём MY_LIQUIDATOR account
  await bc.setShardAccount(MY_LIQUIDATOR, createShardAccount({
    address:   MY_LIQUIDATOR,
    code:      beginCell().endCell(),
    data:      beginCell().endCell(),
    balance:   toNano('10'),
    workchain: 0,
  }));

  // Верификация патча
  const mc2 = await bc.runGetMethod(mainRaw.address, 'getAssetsConfig', []);
  console.log(`  getAssetsConfig после патча: exit=${mc2.exitCode} (0=ОК)`);

  // ── 7. Строим price_feeds_cell ────────────────────────────────────
  console.log('\n[7] Строим price_feeds_cell...');
  const priceFeedsCell = buildPriceFeedsCell(info.feeds, rawPrices);
  console.log(`  Feeds в linked list: ${rawPrices.size}`);

  // ── 8. Строим и отправляем Pyth callback ─────────────────────────
  const queryId = BigInt(Date.now());
  const callbackBody = buildPythCallbackMessage(priceFeedsCell, rawPrices, queryId, ownerAddress);
  console.log(`\n[8] Отправляем FAKE_PYTH → MAIN (query_id=${queryId})...`);
  console.log(`    borrower_address (owner wallet): ${ownerAddress.toString()}`);

  const sendResult = await bc.sendMessage(
    internal({
      from:   FAKE_PYTH_ADDR,
      to:     mainRaw.address,
      value:  toNano('6'),
      body:   callbackBody,
      bounce: false,
    })
  );

  // ── 9. Анализируем транзакции ─────────────────────────────────────
  console.log('\n[9] Транзакции:');
  const txs = sendResult.transactions;
  console.log(`  Всего транзакций: ${txs.length}`);
  // tx.address в sandbox — BigInt (raw 256-bit hash). Конвертируем через hex.
  const addrToHex = (a) => {
    if (!a) return null;
    if (typeof a === 'bigint') return a.toString(16).padStart(64, '0');
    // Address object
    try { return Buffer.from(a.hash).toString('hex'); } catch { return a.toString(); }
  };
  const knownAddrs = {
    [addrToHex(mainRaw.address)]:  'MAIN',
    [addrToHex(userRaw.address)]:  'USER_SC',
    [addrToHex(FAKE_PYTH_ADDR)]:   'FAKE_PYTH',
    [addrToHex(MY_LIQUIDATOR)]:    'MY_LIQUIDATOR',
  };
  const addrLabel = (a) => {
    if (!a) return 'external';
    const h = addrToHex(a);
    return knownAddrs[h] ?? h?.slice(0, 12) + '...';
  };
  for (let i = 0; i < txs.length; i++) {
    const tx  = txs[i];
    const exitCode = tx.description?.computePhase?.exitCode;
    const outCount = tx.outMessagesCount;
    const icon = exitCode === 0 ? '✅' : (exitCode == null ? '⚪' : '❌');
    const toLabel   = addrLabel(tx.address);
    const fromLabel = addrLabel(tx.inMessage?.info?.src);
    console.log(`  [tx${i}] ${icon} exit=${exitCode ?? 'none'} out=${outCount} | ${fromLabel} → ${toLabel}`);
    if (exitCode !== 0 && exitCode != null) {
      console.log(`        ❌ ошибка exitCode=${exitCode}`);
    }
  }

  // ── 10. Балансы после симуляции ───────────────────────────────────
  console.log('\n[10] Балансы user SC после симуляции...');
  try {
    const dynCell2 = (await bc.runGetMethod(mainRaw.address, 'getAssetsData', [])).stackReader.readCell();
    const tb3 = new TupleBuilder(); tb3.writeCell(dynCell2);
    const balResult2 = await bc.runGetMethod(userRaw.address, 'getAccountBalances', tb3.build());
    if (balResult2.exitCode === 0) {
      const balCell2 = balResult2.stackReader.readCellOpt();
      if (balCell2) {
        const bals2 = Dictionary.loadDirect(Dictionary.Keys.BigUint(256), BVAL, balCell2);
        let hasDebt = false;
        for (const [k, v] of bals2) {
          if (v === 0n) continue;
          hasDebt = hasDebt || v < 0n;
          const type = v > 0n ? 'ЗАЛОГ' : 'ДОЛГ ';
          const dec9 = Number(v < 0n ? -v : v) / 1e9;
          let name = `0x${k.toString(16).slice(0,12)}...`;
          if (k === COLLATERAL_ID) name = 'stTON (COLLATERAL)';
          if (k === TON_ASSET_ID)  name = 'TON';
          console.log(`  ${type}: ${name}: ${dec9.toFixed(6)}`);
        }
        if (!hasDebt) console.log('  ℹ️  Нет долгов');
      } else {
        console.log('  ℹ️  Нет активных позиций');
      }
    }
  } catch (e) {
    console.log(`  ⚠️ ошибка: ${e.message}`);
  }

  // ── 11. Итог ──────────────────────────────────────────────────────
  const okCount   = txs.filter(t => t.description?.computePhase?.exitCode === 0).length;
  const failCount = txs.filter(t => {
    const c = t.description?.computePhase?.exitCode;
    return c != null && c !== 0;
  }).length;
  console.log('\n' + '═'.repeat(62));
  console.log(`  Транзакций: ${txs.length} | OK: ${okCount} | Ошибок: ${failCount}`);
  if (!isLiq) {
    console.log('  ВЫВОД: FALSE POSITIVE от бота.');
    console.log('  Причина: lib.js использует simple stTON/TON цену (~$1.12)');
    console.log('           вместо compound TON_USD × stTON/TON (~$1.94).');
    console.log('  На цепочке: MAIN→USER_SC (not liquidatable)→MAIN→refund к ликвидатору.');
  } else {
    console.log('  ВЫВОД: позиция ликвидируема. Проверь exitCode транзакций выше.');
  }
  console.log('═'.repeat(62));
}

main().catch(e => {
  console.error('\n❌ Ошибка:', e.message);
  console.error(e.stack);
  process.exit(1);
});
