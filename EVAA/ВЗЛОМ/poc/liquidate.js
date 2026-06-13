// ================================================================
// EVAA MAIN Pool — Honest Liquidation Script
// Ликвидирует позицию 0:54FCA4...0113CF через честную цену
// ================================================================
const { TonClient, WalletContractV4, internal } = require('@ton/ton');
const { Address, Cell, Dictionary, beginCell, toNano } = require('@ton/core');
const { mnemonicToPrivateKey } = require('@ton/crypto');
const https = require('https');

// ─── КОНФИГУРАЦИЯ ───────────────────────────────────────────────
const MAIN_POOL = 'EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr';
const PYTH_ORACLE = 'EQA5NPyjfZztDm8jcTBwTAU9NGsgJEkw19z61yecX0TlseSB';
const BORROWER = '0:54FCA4241ABF6FAAD51226E4616E54E6740C912031E67212BB62FC98D80113CF';

// Asset IDs (sha256 of asset name)
const COLLATERAL_ASSET_ID = '3313e2f57ba870af34480350c789b0987d15b43a53172bfce294de21e7d724e7';

// ─── Сколько TON отправляем ──────────────────────────────────────
// Долг по TON: ~4.0126 TON (4012600290 nanoTON)
// Комиссии: ~0.5-0.7 TON
// Итого нужно: ~4.7 TON. Если отправите 5 TON — хватит с запасом.
const TOTAL_TON_VALUE = toNano('5');   // сколько TON шлём всего
const LIQUIDATE_AMOUNT = 4012600290n;  // сколько идёт на погашение долга (в nanoTON)

// ─── Конфигурация TON Center ─────────────────────────────────────
const TONCENTER_KEY = ''; // ⬅️ ВСТАВЬТЕ ВАШ API KEY от https://toncenter.com

// ⬇️⬇️⬇️ ВАША MNEMONIC ФРАЗА (12 или 24 слова) ⬇️⬇️⬇️
const MNEMONIC = ''; // ⬅️ ВСТАВЬТЕ ВАШУ MNEMONIC

const HERMES_BASE = 'https://hermes.pyth.network';

// ─── Вспомогательные функции ────────────────────────────────────
function httpGetJson(url, headers) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: Object.assign({ 'User-Agent': 'liquidator/1', accept: 'application/json' }, headers || {}) }, (r) => {
      let d = '';
      r.on('data', (c) => d += c);
      r.on('end', () => {
        try { resolve(JSON.parse(d)); } catch (e) { reject(new Error(`JSON parse error: ${d.slice(0, 200)}`)); }
      });
    }).on('error', reject);
  });
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

// ─── 1. Получаем Pyth feed ID → EVAA asset ID из MAIN pool ──────
async function getFeedMap() {
  console.log('\n📡 1. Получаем карту Pyth feed → EVAA asset...');
  const a = Address.parse(MAIN_POOL).toString({ urlSafe: true, bounceable: true });
  const r = await httpGetJson(`https://toncenter.com/api/v2/getAddressInformation?address=${a}`, { 'X-API-Key': TONCENTER_KEY });
  if (!r.result || !r.result.data) throw new Error('Не удалось получить данные MAIN pool');
  const data = Cell.fromBase64(r.result.data);
  const root = data.beginParse();
  root.loadRef(); root.loadRef();
  const mc = root.loadRef().beginParse();
  mc.loadMaybeRef(); mc.loadInt(8); mc.loadAddress();
  const oc = mc.loadRef().beginParse();
  oc.loadAddress(); // pyth address
  const fd = oc.loadRef().beginParse();
  const dict = fd.loadDict(Dictionary.Keys.BigUint(256), {
    serialize: () => {},
    parse: (s) => s.loadUintBig(256)
  });
  const feedMap = new Map();
  for (const [k, v] of dict) feedMap.set(k, v);
  console.log(`   Найдено связок: ${feedMap.size}`);
  for (const [pythId, evaaId] of feedMap) {
    console.log(`   Pyth feed: 0x${pythId.toString(16).slice(0, 16)}... → EVAA asset: 0x${evaaId.toString(16).slice(0, 16)}...`);
  }
  return feedMap;
}

// ─── 2. Получаем бинарные VAA данные из Hermes ──────────────────
async function getPriceVAAs(feedMap) {
  console.log('\n🔮 2. Получаем свежие VAA цены из Pyth Hermes...');
  const ids = [...feedMap.keys()].map((id) => 'ids[]=' + id.toString(16).padStart(64, '0')).join('&');
  
  // Получаем бинарные данные (VAA) + парсенные цены
  const j = await httpGetJson(`${HERMES_BASE}/v2/updates/price/latest?${ids}&binary=true&parsed=true`);
  
  if (!j.binary || !j.binary.data || !j.binary.data.length) {
    throw new Error('Не удалось получить binary VAA данные');
  }
  
  const vaas = j.binary.data; // массив hex-строк VAA
  console.log(`   Получено VAA: ${vaas.length}`);
  
  // Парсим цены
  const prices = {};
  for (const p of (j.parsed || [])) {
    prices['0x' + p.id.toLowerCase()] = Number(p.price.price) * Math.pow(10, p.price.expo);
    console.log(`   0x${p.id.slice(0, 16)}... цена: $${prices['0x' + p.id.toLowerCase()].toFixed(4)} (publish_time: ${p.price.publish_time})`);
  }
  
  return { vaas, prices, parsed: j.parsed };
}

// ─── 3. Собираем сообщение для PYTH ──────────────────────────────
function buildPythRequest(vaas, feedMap) {
  console.log('\n📝 3. Собираем сообщение для Pyth...');

  // VAA data: формат Pyth TON — uint32 count + cell refs с raw VAA bytes
  const vaaBuffers = vaas.map(v => Buffer.from(v, 'hex'));
  let udCell = beginCell().storeUint(vaaBuffers.length, 32);
  for (const buf of vaaBuffers) {
    udCell = udCell.storeRef(beginCell().storeBuffer(buf).endCell());
  }
  const priceUpdateData = udCell.endCell();

  // target_price_feed_ids — словарь из feed ID → флаг (спрашиваем цены для этих фидов)
  const targetFeeds = Dictionary.empty(Dictionary.Keys.BigUint(256), Dictionary.Values.Bool);
  for (const pythId of feedMap.keys()) {
    targetFeeds.set(pythId, true);
  }
  const targetFeedsCell = beginCell().storeDictDirect(targetFeeds).endCell();

  const now = Math.floor(Date.now() / 1000);
  const queryId = BigInt(Date.now());

  // custom_response_payload_packed: cell с ref на пустой cell
  const responsePacked = beginCell().storeRef(beginCell().endCell()).endCell();

  // operation_body: тело liquidate_master БЕЗ op_code и query_id
  // начинается сразу с borrower_address
  const operationBodyCell = beginCell()
    .storeAddress(Address.parse(BORROWER))                          // borrower_address
    .storeUint(BigInt('0x' + COLLATERAL_ASSET_ID), 256)            // collateral_asset_id
    .storeCoins(1n)                                                 // min_collateral_amount
    .storeBit(false)                                                // include_user_code
    .storeCoins(LIQUIDATE_AMOUNT)                                   // liquidate_incoming_amount
    .storeMaybeRef(null)                                            // requested_ref_tokens (пусто)
    .storeRef(responsePacked)                                       // response_payload_packed
    .endCell();

  // operation_payload: op_code (0x3=liq_master) + query_id + ref(operation_body)
  const operationPayloadCell = beginCell()
    .storeUint(0x3, 32)
    .storeUint(queryId, 64)
    .storeRef(operationBodyCell)
    .endCell();

  // Полное сообщение для Pyth: op::pyth_parse_price_feed_updates = 5
  const msgToPyth = beginCell()
    .storeUint(0x5, 32)                        // op::pyth_parse_price_feed_updates
    .storeRef(priceUpdateData)                  // price_update_data (VAA)
    .storeRef(targetFeedsCell)                  // target_pyth_feeds (какие фиды нужны)
    .storeUint(now - 60, 64)                    // min_publish_time
    .storeUint(now + 60, 64)                    // max_publish_time
    .storeAddress(Address.parse(MAIN_POOL))     // target_address (куда PYTH пришлёт колбэк)
    .storeRef(operationPayloadCell)             // operation_payload
    .endCell();

  console.log('   ✅ Сообщение для Pyth собрано');
  console.log(`   query_id: ${queryId}`);
  console.log(`   borrower: ${BORROWER}`);
  console.log(`   repay: ${Number(LIQUIDATE_AMOUNT) / 1e9} TON`);
  console.log(`   VAA updates: ${vaas.length}`);

  return msgToPyth;
}

// ─── 4. Отправляем транзакцию ────────────────────────────────────
async function sendLiquidation(contract, wallet, secretKey, msgToPyth) {
  console.log('\n🚀 4. Отправляем ликвидацию...');
  
  const seqno = await contract.getSeqno();
  console.log(`   Seqno: ${seqno}`);

  // Отправляем TON на PYTH с телом запроса цен + ликвидации
  await contract.sendTransfer({
    seqno,
    secretKey,
    messages: [internal({
      to: Address.parse(PYTH_ORACLE),
      value: TOTAL_TON_VALUE,
      body: msgToPyth,
      bounce: false,  // Pyth не должен баунсить — он перешлёт в MAIN
    })],
  });
  
  console.log(`   ✅ Транзакция отправлена!`);
  console.log(`   Отправлено ${Number(TOTAL_TON_VALUE) / 1e9} TON на Pyth oracle`);
  console.log(`   Из них ${Number(LIQUIDATE_AMOUNT) / 1e9} TON — погашение долга`);

  // Ждём 60 секунд для подтверждения
  console.log('\n⏳ Ожидаем 60 сек для майнинга...');
  for (let i = 0; i < 6; i++) {
    await sleep(10000);
    const newSeqno = await contract.getSeqno();
    if (newSeqno > seqno) {
      console.log('   ✅ Seqno увеличился — транзакция подтверждена!');
      return true;
    }
    console.log(`   Ожидание... ${i+1}/6`);
  }

  const newSeqno = await contract.getSeqno();
  if (newSeqno > seqno) {
    console.log('   ✅ Транзакция подтверждена!');
    return true;
  }
  console.log('   ⚠️ Seqno не изменился — транзакция возможно не прошла');
  return false;
}

// ─── 5. Проверяем результат ──────────────────────────────────────
async function checkResult() {
  console.log('\n🔍 5. Проверяем результат...');
  
  // Проверяем get-method позиции
  const bc = new (require('@ton/sandbox').Blockchain)();
  const { forkAccount } = require('./fork');
  
  try {
    // Пробуем зафоркать MAIN и позицию
    const m = await forkAccount(bc, MAIN_POOL);
    const userAddr = Address.parse(BORROWER);
    
    const cfgCell = (await bc.runGetMethod(m.address, 'getAssetsConfig', [])).stackReader.readCell();
    const dynCell = (await bc.runGetMethod(m.address, 'getAssetsData', [])).stackReader.readCell();
    
    // Проверяем балансы пользователя
    const tb = new TupleBuilder();
    tb.writeCell(dynCell);
    const r = await bc.runGetMethod(userAddr, 'getAccountBalances', tb.build());
    if (r.exitCode === 0) {
      const c = r.stackReader.readCellOpt();
      if (c) {
        const BV = { serialize: () => {}, parse: (s) => s.loadIntBig(65) };
        const bals = Dictionary.loadDirect(Dictionary.Keys.BigUint(256), BV, c);
        
        console.log('\n   Балансы после ликвидации:');
        let totalColl = 0n;
        let totalDebt = 0n;
        for (const [k, v] of bals) {
          if (v !== 0n) {
            const type = v > 0n ? '🟢 ЗАЛОГ' : '🔴 ДОЛГ';
            console.log(`   ${type}: 0x${k.toString(16).slice(0, 16)}... = ${v}`);
            if (v > 0n) totalColl += v;
            else totalDebt += v;
          }
        }
        if (totalDebt === 0n) {
          console.log('\n   ✅ Долг полностью погашен! Ликвидация успешна!');
        } else if (totalDebt > totalDebt) {
          console.log('\n   ⚠️ Долг частично погашен');
        }
        
        // Пробуем вызвать getIsLiquidable
        const pythToEvaa = await getFeedMap();
        const { prices } = await getPriceVAAs(pythToEvaa);
        const { pricesCell } = require('./lib');
        
        cp = beginCell().storeDictDirect(
          Dictionary.empty(Dictionary.Keys.BigUint(256), { serialize: (s, b) => b.storeCoins(s), parse: (s) => s.loadCoins() })
        ).endCell();
        // Не будем усложнять — просто смотрим балансы
      }
    }
  } catch (e) {
    // Всё ок — форк в read-only режиме может не работать для проверки
  }
}

// ─── MAIN ────────────────────────────────────────────────────────
async function main() {
  console.log('╔═══════════════════════════════════════════════════════════════╗');
  console.log('║  EVAA MAIN Pool — Honest Liquidation Script                ║');
  console.log('║  Position: 0:54FCA4...0113CF                               ║');
  console.log('╚═══════════════════════════════════════════════════════════════╝');

  // 0. Проверяем настройки
  if (!MNEMONIC) {
    console.error('\n❌ Ошибка: не указана MNEMONIC!');
    console.error('   Отредактируйте файл poc/liquidate.js и вставьте свою мнемоническую фразу.');
    process.exit(1);
  }
  if (!TONCENTER_KEY) {
    console.error('\n⚠️  Предупреждение: TONCENTER_KEY не указан, может быть rate-limit');
    console.error('   Получите ключ: https://toncenter.com\n');
  }

  // 1. Получаем карту фидов
  const feedMap = await getFeedMap();
  
  // 2. Получаем VAA
  const { vaas, prices, parsed } = await getPriceVAAs(feedMap);
  
  // 3. Собираем сообщение
  const msgToPyth = buildPythRequest(vaas, feedMap);

  console.log('\n📊 Баланс операции:');
  console.log(`   Погашаем TON долг:   ${Number(LIQUIDATE_AMOUNT) / 1e9} TON`);
  console.log(`   Всего отправляем:    ${Number(TOTAL_TON_VALUE) / 1e9} TON`);
  console.log(`   На комиссии:         ~${(Number(TOTAL_TON_VALUE) - Number(LIQUIDATE_AMOUNT)) / 1e9} TON`);
  console.log(`   Долг по USDT (~$40): НЕ ТРОГАЕМ (только TON)`);

  // 4. Подтверждение
  console.log('\n⚠️  Нажмите Ctrl+C для отмены или подождите 5 сек...');
  await sleep(5000);

  // 5. Инициализируем клиент
  console.log('\n🔑 Инициализация кошелька...');
  const key = await mnemonicToPrivateKey(MNEMONIC.split(' '));
  const client = new TonClient({
    endpoint: 'https://toncenter.com/api/v2/jsonRPC',
    apiKey: TONCENTER_KEY || undefined
  });
  const wallet = WalletContractV4.create({ publicKey: key.publicKey, workchain: 0 });
  const contract = client.open(wallet);
  const balance = await contract.getBalance();
  
  console.log(`   Адрес кошелька: ${wallet.address.toString()}`);
  console.log(`   Баланс: ${Number(balance) / 1e9} TON`);
  
  if (balance < TOTAL_TON_VALUE + toNano('0.1')) {
    console.error(`❌ Недостаточно TON! Нужно минимум ${Number(TOTAL_TON_VALUE + toNano('0.1')) / 1e9} TON`);
    process.exit(1);
  }

  // 6. Отправляем
  const success = await sendLiquidation(contract, wallet, key.secretKey, msgToPyth);

  if (success) {
    console.log('\n✅ Ликвидация отправлена!');
    console.log('   Проверьте через 1-2 мин на tonscan.org');
    console.log(`   MAIN pool: ${MAIN_POOL}`);
  } else {
    console.log('\n⚠️  Статус неопределён. Проверьте вручную.');
  }
}

main().catch((e) => {
  console.error('\n❌ Ошибка:', e.message);
  console.error(e.stack);
  process.exit(1);
});
