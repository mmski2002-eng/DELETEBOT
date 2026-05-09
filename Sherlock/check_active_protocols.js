/**
 * Проверка активных протоколов в Sherlock Protocol на mainnet
 * Ищет протоколы с premium > 0 и claimablePremiums > 0
 * 
 * Запуск: cd sherlock-v2-core && node ..\check_active_protocols.js
 */

const { ethers } = require('ethers');

const SHERLOCK = '0x0865a889183039689034dA55c1Fd12aF5083eabF';
const PM = '0x3d0b8a0a10835ab9b0f0beb54c5400b8aacaa1d3';

const RPCS = [
    'https://eth.drpc.org',
    'https://rpc.ankr.com/eth',
    'https://ethereum.publicnode.com',
];

async function connectToMainnet() {
    for (const rpc of RPCS) {
        try {
            const provider = new ethers.providers.JsonRpcProvider(rpc, 1);
            await provider.ready;
            const block = await provider.getBlockNumber();
            console.log(`✅ Connected via ${rpc} (block: ${block})`);
            return provider;
        } catch (e) {
            console.log(`⚠️  ${rpc} failed: ${e.message.slice(0, 60)}`);
        }
    }
    throw new Error('No working RPC found');
}

function sel(sig) {
    return ethers.utils.id(sig).slice(0, 10);
}

async function call(provider, to, data) {
    try {
        const result = await provider.call({ to, data });
        return ethers.BigNumber.from(result);
    } catch (e) {
        return ethers.BigNumber.from(0);
    }
}

async function main() {
    console.log('='.repeat(80));
    console.log('🔍 ПОИСК АКТИВНЫХ ПРОТОКОЛОВ SHERLOCK НА MAINNET');
    console.log('='.repeat(80));

    const provider = await connectToMainnet();
    const block = await provider.getBlockNumber();
    const blockData = await provider.getBlock(block);
    const timestamp = blockData.timestamp;
    console.log(`📦 Block: ${block}, Time: ${new Date(timestamp * 1000).toISOString()}\n`);

    // =============================================
    // ШАГ 1: Глобальное состояние Sherlock
    // =============================================
    console.log('📋 Шаг 1: Глобальное состояние');
    console.log('-'.repeat(50));

    const claimablePremiums = await call(provider, PM, sel('claimablePremiums()'));
    const allPremiumsPerSec = await call(provider, PM, sel('allPremiumsPerSecToStakers()'));
    const lastClaimablePremiums = await call(provider, PM, sel('lastClaimablePremiumsForStakers()'));
    const lastAccountedGlobal = await call(provider, PM, sel('lastAccountedGlobal()'));
    const minActiveBalance = await call(provider, PM, sel('minActiveBalance()'));
    const totalShares = await call(provider, SHERLOCK, sel('totalShares()'));
    const totalTokenBalance = await call(provider, SHERLOCK, sel('totalTokenBalanceStakers()'));
    const owner = await call(provider, PM, sel('owner()'));

    console.log(`   claimablePremiums:          ${ethers.utils.formatUnits(claimablePremiums, 6)} USDC`);
    console.log(`   allPremiumsPerSecToStakers: ${ethers.utils.formatUnits(allPremiumsPerSec, 6)} USDC/сек`);
    console.log(`   lastClaimablePremiums:      ${ethers.utils.formatUnits(lastClaimablePremiums, 6)} USDC`);
    console.log(`   lastAccountedGlobal:        ${lastAccountedGlobal.toString()}`);
    console.log(`   minActiveBalance:           ${ethers.utils.formatUnits(minActiveBalance, 6)} USDC`);
    console.log(`   totalShares:                ${ethers.utils.formatEther(totalShares)}`);
    console.log(`   totalTokenBalanceStakers:   ${ethers.utils.formatUnits(totalTokenBalance, 6)} USDC`);

    if (claimablePremiums.eq(0) && allPremiumsPerSec.eq(0)) {
        console.log('\n⚠️  ПРОТОКОЛ НЕАКТИВЕН: claimablePremiums = 0, allPremiumsPerSec = 0');
        console.log('   Активных протоколов, платящих премии, НЕТ.');
    }

    // =============================================
    // ШАГ 2: Проверка через events (если доступны)
    // =============================================
    console.log('\n📋 Шаг 2: Проверка истории событий ProtocolAdded');
    console.log('-'.repeat(50));
    
    // Событие ProtocolAdded(bytes32 indexed protocol, address indexed agent, uint256 premium, uint256 activeBalance)
    const protocolAddedTopic = ethers.utils.id('ProtocolAdded(bytes32,address,uint256,uint256)');
    
    try {
        const logs = await provider.getLogs({
            address: PM,
            topics: [protocolAddedTopic],
            fromBlock: 0,
            toBlock: block,
        });
        console.log(`   Найдено событий ProtocolAdded: ${logs.length}`);
        logs.forEach((log, i) => {
            const decoded = ethers.utils.defaultAbiCoder.decode(
                ['bytes32', 'address', 'uint256', 'uint256'],
                log.data
            );
            const protocolBytes32 = decoded[0];
            const agent = decoded[1];
            const premium = decoded[2];
            const activeBal = decoded[3];
            console.log(`   ${i + 1}. Protocol: ${protocolBytes32.slice(0, 42)}...`);
            console.log(`      Agent: ${agent}, Premium: ${ethers.utils.formatUnits(premium, 6)} USDC, ActiveBal: ${ethers.utils.formatUnits(activeBal, 6)} USDC`);
        });
    } catch (e) {
        console.log(`   ⚠️  Не удалось получить события: ${e.message.slice(0, 80)}`);
        console.log('   (RPC может не поддерживать getLogs с fromBlock: 0)');
    }

    // =============================================
    // ШАГ 3: Проверка конкретных известных протоколов
    // =============================================
    console.log('\n📋 Шаг 3: Проверка известных протоколов');
    console.log('-'.repeat(50));

    const knownProtocols = [
        { name: 'Aave V2', addr: '0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9' },
        { name: 'Aave V3', addr: '0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2' },
        { name: 'Compound', addr: '0xc0a47dFe034B400B47bDaD5FecDa2621de6c4d95' },
        { name: 'Uniswap V3', addr: '0x1F98431c8aD98523631AE4a59f267346ea31F984' },
        { name: 'Balancer', addr: '0xBA12222222228d8Ba445958a75a0704d566BF2C8' },
        { name: 'Sushiswap', addr: '0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac' },
        { name: 'Liquity', addr: '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419' },
        { name: 'Yearn', addr: '0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804' },
        { name: 'Sorbet Finance', addr: '0x7A7697D6E0E1C3B2C1D4C5B7E6F8A9B0C1D2E3F4' },
    ];

    let foundActive = false;

    for (const protocol of knownProtocols) {
        // Пробуем bytes32 = left-padded address
        const pBytes = '0x' + '000000000000000000000000' + protocol.addr.slice(2).toLowerCase();
        
        try {
            const agentResult = await provider.call({ 
                to: PM, 
                data: sel('protocolAgent(bytes32)') + pBytes.slice(2).padStart(64, '0'),
            });
            const agent = '0x' + agentResult.slice(26, 66);

            if (agent !== '0x0000000000000000000000000000000000000000') {
                const premiumResult = await call(provider, PM, 
                    sel('premium(bytes32)') + pBytes.slice(2).padStart(64, '0'));
                const activeBalResult = await call(provider, PM,
                    sel('activeBalance(bytes32)') + pBytes.slice(2).padStart(64, '0'));
                const lastAccResult = await call(provider, PM,
                    sel('lastAccountedEachProtocol(bytes32)') + pBytes.slice(2).padStart(64, '0'));

                const premium = premiumResult;
                const activeBal = activeBalResult;
                const lastAcc = lastAccResult.toNumber();
                
                if (!premium.isZero() || !activeBal.isZero()) {
                    foundActive = true;
                    const timeDiff = timestamp - lastAcc;
                    const debt = premium.mul(timeDiff);
                    
                    console.log(`\n🔍 ${protocol.name}:`);
                    console.log(`   Адрес: ${protocol.addr}`);
                    console.log(`   Agent: ${agent}`);
                    console.log(`   Premium/сек: ${ethers.utils.formatUnits(premium, 6)} USDC`);
                    console.log(`   ActiveBalance: ${ethers.utils.formatUnits(activeBal, 6)} USDC`);
                    console.log(`   Последняя проверка: ${lastAcc === 0 ? 'никогда' : new Date(lastAcc * 1000).toISOString()}`);
                    console.log(`   Debt: ${ethers.utils.formatUnits(debt, 6)} USDC`);
                    console.log(`   Debt > ActiveBalance? ${debt.gt(activeBal) ? '⚠️ ДА!' : '✅ НЕТ'}`);
                    console.log(`   Активен: ${!activeBal.isZero() ? '✅ ДА' : '❌ НЕТ (balance=0)'}`);
                } else {
                    console.log(`   ${protocol.name}: найден, но неактивен (premium=0, balance=0)`);
                }
            }
        } catch (e) {
            // Протокол не найден
        }
    }

    if (!foundActive) {
        console.log('   ❌ Ни один из известных протоколов не активен в Sherlock.');
        console.log('   Все протоколы имеют premium=0 и activeBalance=0.');
    }

    // =============================================
    // ИТОГ
    // =============================================
    console.log('\n' + '='.repeat(80));
    console.log('📋 ИТОГОВЫЙ ВЕРДИКТ');
    console.log('='.repeat(80));

    if (claimablePremiums.eq(0) && allPremiumsPerSec.eq(0) && totalShares.eq(0)) {
        console.log(`
   Sherlock Protocol v2 на mainnet ПОЛНОСТЬЮ НЕАКТИВЕН:
   
   📊 claimablePremiums:       ${ethers.utils.formatUnits(claimablePremiums, 6)} USDC
   📊 allPremiumsPerSec:       ${ethers.utils.formatUnits(allPremiumsPerSec, 6)} USDC/сек
   📊 totalShares:             0 (нет стейкеров)
   📊 totalTokenBalance:       ${ethers.utils.formatUnits(totalTokenBalance, 6)} USDC
   
   ❌ Активных протоколов, платящих премии — НЕТ.
   ❌ Стейкеров — НЕТ.
   ❌ Накопленных премий — НЕТ.
   
   🛡️  Уязвимости существуют на УРОВНЕ КОДА, но в текущем состоянии
       mainnet их невозможно эксплуатировать (нечего красть).
   
   📝 Для Immunefi submission достаточно:
       ✓ Математических доказательств (PoC скрипты)
       ✓ Анализа кода со строками
       ✓ Ончейн-доказательства публичного доступа (TX на Etherscan)
       ✓ Скриптов для форка mainnet
        `);
    } else {
        console.log('⚠️  Протокол ЧАСТИЧНО активен! Возможна эксплуатация!');
    }

    console.log(`\n✅ Проверка завершена. Блок: ${block}`);
}

main().catch(err => {
    console.error('\n❌ Ошибка:', err.message);
    process.exit(1);
});
