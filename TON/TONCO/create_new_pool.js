const { beginCell, Address, toNano, Cell } = require('@ton/core');

// Адреса из .env.local TONCO SDK
const POOL_FACTORY = 'EQCXrVg3we6FKI4NKjBe9vlJKM5aGcDQB61LdfI_KmN_2Kj2';
const PTON_MINTER = 'EQCUnExmdgwAKADi-j2KPKThyQqTc7U650cgM0g78UzZXn9J';
const USDT_MINTER = 'EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs';
const ROUTER = 'EQC_-t0nCnOFMdp7E7qPxAOCbCWGFz-e3pwxb6tTvFmshjt5';

// OP коды
const POOL_FACTORY_CREATE_POOL = 0x9e9a8f7f;
const POOL_FACTORY_ORDER_INIT = 0x8b85de63;

// Настройки
const TICK_SPACING = 1; // для TON-USDT как на существующем пуле
const FEE = 30; // 0.3% (30/10000)
const POOL_ACTIVE = 1;

// Ваш кошелек
const YOUR_WALLET = 'UQCvPAknwpT9a9dSCCtF_RdRh2bssBmuOBNG0hamNL5EuLpT'; // ваш адрес

// TON/USDT цена ~ 5.5 USD за TON (май 2025)
// sqrtPriceX96 = sqrt(price) * 2^96
// price = 5.5 (USDT за TON)
// sqrt = sqrt(5.5) ≈ 2.345
// sqrtPriceX96 = 2.345 * 2^96
function calculateSqrtPriceX96(price) {
    const sqrtPrice = Math.sqrt(price);
    const result = BigInt(Math.floor(sqrtPrice * 2**64)) * BigInt(2**32);
    return result;
}

// Примерная цена TON ≈ 5.5 USDT
const INITIAL_PRICE_X96 = calculateSqrtPriceX96(5.5);

console.log('=== Создание нового пула TON-USDT на mainnet ===');
console.log('');

// Вариант 1: Создание через фабрику напрямую
// Нам нужно узнать jetton wallet адреса для TON и USDT
// Они вычисляются через минтеры + адрес назначения

// Получаем jetton wallet адрес для pTON
// Адрес jetton wallet = hash(минтер, owner) по правилам TON жетонов
// Для пула jetton wallet - это кошелек, который принадлежит пулу
// Но при создании пула фабрика сама создаст эти кошельки/привяжет их

// Из существующего пула мы можем получить jetton wallet адреса
// Но для создания нового пула через фабрику нам нужно их передать

// На самом деле, существующий пул TON-USDT уже имеет jetton wallet адреса.
// Давайте найдем их в данных пула.

// Вместо этого, давайте попробуем создать пул через ROUTERV3_CREATE_POOL
// Роутер сам разберется с jetton wallet'ами

const ROUTERV3_CREATE_POOL = 0x2e3034ef;

function generateRouterCreatePoolMessage(jetton0Minter, jetton1Minter, sqrtPriceX96, fee, tickSpacing) {
    // settings: 16 бит = fee (первые 4 бита под тип, остальные 12 под комиссию)
    const settings = fee; // просто fee = 30 для 0.3%
    
    const body = beginCell()
        .storeUint(ROUTERV3_CREATE_POOL, 32)  // OP code
        .storeUint(0, 64)                       // query_id
        .storeAddress(Address.parse(jetton0Minter))
        .storeAddress(Address.parse(jetton1Minter))
        .storeUint(sqrtPriceX96, 160)           // initial sqrt price
        .storeUint(settings, 16)                // settings (fee)
        .storeUint(tickSpacing, 24)             // tick spacing
        .endCell();
    
    return body;
}

// Вариант 2: Создание через ROUTERV3_CREATE_POOL
console.log('--- Вариант 1: Через роутер (ROUTERV3_CREATE_POOL) ---');
// pTON минтер как jetton0 (TON)
// USDT минтер как jetton1 (USDT)
const bodyRouter = generateRouterCreatePoolMessage(
    PTON_MINTER,
    USDT_MINTER,
    INITIAL_PRICE_X96,
    FEE,
    TICK_SPACING
);

const bodyRouterBoc = bodyRouter.toBoc().toString('base64');
const routerCreateLink = `https://app.tonkeeper.com/transfer/${ROUTER}?amount=${toNano('0.3').toString()}&bin=${encodeURIComponent(bodyRouterBoc)}`;
console.log('Body BoC:', bodyRouterBoc);
console.log('Ссылка для создания пула через РОУТЕР:');
console.log(routerCreateLink);
console.log('');

// Вариант 3: Через фабрику
console.log('--- Вариант 2: Через фабрику (POOL_FACTORY_CREATE_POOL) ---');
// Для фабрики нужно больше параметров

// Вычисляем jetton wallet адреса для пула
// Адрес зависит от минтера и owner (пула). Но пул еще не создан...
// Фабрика сама рассчитывает адреса

const bodyFactory = beginCell()
    .storeUint(POOL_FACTORY_CREATE_POOL, 32)   // OP code
    .storeUint(0, 64)                            // query_id
    .storeAddress(Address.parse(PTON_MINTER))     // jetton0 minter
    .storeAddress(Address.parse(USDT_MINTER))     // jetton1 minter
    .storeUint(INITIAL_PRICE_X96, 160)            // initial sqrt price
    .storeUint(FEE, 16)                           // settings (fee)
    .storeRef(
        beginCell()
            .storeAddress(Address.parse('EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c')) // jetton0 wallet (плейсхолдер)
            .storeAddress(Address.parse('EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c')) // jetton1 wallet (плейсхолдер)
            .endCell()
    )
    .storeMaybeRef(null)  // без whitelisted параметров
    .endCell();

const bodyFactoryBoc = bodyFactory.toBoc().toString('base64');
const factoryCreateLink = `https://app.tonkeeper.com/transfer/${POOL_FACTORY}?amount=${toNano('0.3').toString()}&bin=${encodeURIComponent(bodyFactoryBoc)}`;
console.log('Body BoC:', bodyFactoryBoc);
console.log('Ссылка для создания пула через ФАБРИКУ:');
console.log(factoryCreateLink);
console.log('');

// Вариант 3: Прямой POOLV3_INIT на новый адрес
console.log('--- Вариант 3: POOLV3_INIT на существующий пул с is_from_admin=1 ---');
console.log('(как и раньше)');

const POOLV3_INIT = 0x441c39ed;
const IMPOSSIBLE_FEE = 10001;

const bodyPoolV3Init = beginCell()
    .storeUint(POOLV3_INIT, 32)
    .storeUint(0, 64)
    .storeUint(1, 1)  // is_from_admin = 1
    .storeUint(1, 1)  // has_admin
    .storeAddress(Address.parse(YOUR_WALLET))  // admin = наш кошелек
    .storeUint(0, 1)  // has_controller = false
    .storeUint(0, 1)  // has_tickSpacing = false
    .storeUint(0, 24)
    .storeUint(0, 1)  // has_sqrtPriceX96 = false
    .storeUint(0, 160)
    .storeUint(0, 1)  // has_activate_pool = false
    .storeUint(0, 1)
    .storeUint(IMPOSSIBLE_FEE, 16)  // protocolFee
    .storeUint(IMPOSSIBLE_FEE, 16)  // lpFee
    .storeUint(IMPOSSIBLE_FEE, 16)  // currentFee
    .storeRef(beginCell().endCell())  // nftContentPacked
    .storeRef(beginCell().endCell())  // nftItemContentPacked
    .endCell();

const poolAddress = 'EQD25vStEwc-h1QT1qlsYPQwqU5IiOhox5II0C_xsDNpMVo7';
const bodyPoolBoc = bodyPoolV3Init.toBoc().toString('base64');
const poolInitLink = `https://app.tonkeeper.com/transfer/${poolAddress}?amount=${toNano('0.15').toString()}&bin=${encodeURIComponent(bodyPoolBoc)}`;
console.log('Ссылка POOLV3_INIT на существующий пул:');
console.log(poolInitLink);
console.log('');

// Распечатываем информацию
console.log('=== Информация ===');
console.log('POOL_FACTORY:', POOL_FACTORY);
console.log('ROUTER:', ROUTER);
console.log('pTON минтер:', PTON_MINTER);
console.log('USDT минтер:', USDT_MINTER);
console.log('Начальная цена TON/USDT: 5.5');
console.log('sqrtPriceX96:', INITIAL_PRICE_X96.toString());
console.log('Комиссия:', FEE + '/10000 =', FEE/100 + '%');
console.log('');

// Декодируем body для проверки
console.log('=== Проверка сообщения для роутера (шестнадцатеричный дамп) ===');
console.log('Hex:', bodyRouter.toBoc().toString('hex'));
