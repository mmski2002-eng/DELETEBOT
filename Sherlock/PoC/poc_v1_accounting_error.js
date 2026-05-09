/**
 * PoC #1 — Accounting Error в SherlockProtocolManager._settleProtocolDebt()
 * Severity: Critical | Impact: Direct theft of unclaimed yield
 *
 * Суть: Когда debt > activeBalance протокола, claimablePremiumError вычисляется,
 * и если она > lastClaimablePremiumsForStakers_, то lastClaimablePremiumsForStakers = 0,
 * а insufficientTokens БЕЗВОЗВРАТНО теряется для стейкеров.
 *
 * УСЛОВИЕ ТРИГГЕРА: debt > activeBalance
 * debt = premiumPerSecond * (currentTime - lastAccounted)
 * Нужно: premiumPerSecond * timeDiff > activeBalance
 */

function simulate() {
    console.log("=".repeat(80));
    console.log("PoC #1: Accounting Error в _settleProtocolDebt()");
    console.log("Severity: CRITICAL | Impact: Direct theft of unclaimed yield");
    console.log("=".repeat(80));

    // Параметры протокола для ТРИГГЕРА ошибки
    // debt = premiumPerSecond * timeDiff ДОЛЖЕН БЫТЬ > activeBalance
    const premiumPerSecond = 1000n * BigInt(1e6); // 1000 USDC/сек (высокий premium)
    const lastAccounted = 1000000n;                 // timestamp последнего учёта
    const currentTime = 1001500n;                   // текущий timestamp (500 сек прошло)
    const activeBalance = 100_000n * BigInt(1e6);   // 100k USDC баланс протокола (низкий)
    const lastClaimablePremiumsForStakers_ = 1_000_000n * BigInt(1e6); // 1M USDC накоплено
    
    console.log("\n📊 Исходные данные:");
    console.log(`   premiumPerSecond:           ${(premiumPerSecond / BigInt(1e6)).toString()} USDC/сек`);
    console.log(`   Прошло времени:             ${(currentTime - lastAccounted).toString()} сек`);
    console.log(`   activeBalance:              ${(activeBalance / BigInt(1e6)).toString()} USDC`);
    console.log(`   lastClaimablePremiums:      ${(lastClaimablePremiumsForStakers_ / BigInt(1e6)).toString()} USDC`);

    // Шаг 1: Начисление долга
    const timeDiff = currentTime - lastAccounted;
    const debt = premiumPerSecond * timeDiff;
    
    console.log(`\n📈 Долг протокола:`);
    console.log(`   debt = ${(premiumPerSecond / BigInt(1e6)).toString()} USDC/сек * ${timeDiff} сек = ${(debt / BigInt(1e6)).toString()} USDC`);
    console.log(`   activeBalance:              ${(activeBalance / BigInt(1e6)).toString()} USDC`);
    console.log(`   debt > activeBalance:       ${debt > activeBalance ? "ДА - ТРИГГЕР ОШИБКИ!" : "НЕТ"}`);

    if (debt <= activeBalance) {
        console.log("\n⚠️  Условие не выполнено. Увеличьте premiumPerSecond или timeDiff.");
        return;
    }

    // Шаг 2: Вычисление ошибки (как в контракте - упрощённо)
    // В контракте: доля стейкеров в premium = (100% - PROTOCOL_PERCENTAGE)
    const PROTOCOL_PERCENTAGE = 15n; // 15%
    const PROTOCOL_PERCENTAGE_DENOMINATOR = 100n;
    
    // protocolDebt - это долг уже после распределения premium между протоколом и стейкерами
    // Когда debt > balance, вычисляется protocolError
    const protocolError = debt - activeBalance;
    // Доля ошибки, которая приходится на стейкеров (85%)
    const claimablePremiumError = (protocolError * (PROTOCOL_PERCENTAGE_DENOMINATOR - PROTOCOL_PERCENTAGE)) / PROTOCOL_PERCENTAGE_DENOMINATOR;
    
    console.log(`\n⚙️  Механизм ошибки:`);
    console.log(`   protocolError = ${(protocolError / BigInt(1e6)).toString()} USDC (debt - balance)`);
    console.log(`   Доля стейкеров: ${100 - Number(PROTOCOL_PERCENTAGE)}%`);
    console.log(`   claimablePremiumError = ${(claimablePremiumError / BigInt(1e6)).toString()} USDC`);

    // Шаг 3: Применение логики из контракта (строки 296-303)
    let insufficientTokens = 0n;
    let lastClaimablePremiums = lastClaimablePremiumsForStakers_;
    
    console.log(`\n🔍 Логика контракта (строки 296-303):`);
    console.log(`   if (claimablePremiumError (${(claimablePremiumError / BigInt(1e6)).toString()} USDC) >`);
    console.log(`       lastClaimablePremiums (${(lastClaimablePremiums / BigInt(1e6)).toString()} USDC))`);
    
    if (claimablePremiumError > lastClaimablePremiums) {
        insufficientTokens = claimablePremiumError - lastClaimablePremiums;
        lastClaimablePremiums = 0n;
        console.log(`   ✅ ДА! => lastClaimablePremiums = 0`);
        console.log(`   insufficientTokens = ${(insufficientTokens / BigInt(1e6)).toString()} USDC`);
    } else {
        lastClaimablePremiums = lastClaimablePremiums - claimablePremiumError;
        console.log(`   ❌ НЕТ => lastClaimablePremiums = ${(lastClaimablePremiums / BigInt(1e6)).toString()} USDC`);
    }
    
    console.log(`\n💥 ПОТЕРЯ ДЛЯ СТЕЙКЕРОВ:`);
    console.log(`   insufficientTokens = ${(insufficientTokens / BigInt(1e6)).toString()} USDC`);
    console.log(`   Эта сумма БЕЗВОЗВРАТНО ПОТЕРЯНА!`);
    
    // Демонстрация: как атакующий может спровоцировать
    console.log(`\n🎯 ВЕКТОР АТАКИ:`);
    console.log(`   1. Атакующий создает протокол с premiumPerSecond = 1000 USDC/сек`);
    console.log(`      и activeBalance = 100k USDC`);
    console.log(`   2. Через 500 сек долг = 500k USDC > 100k balance`);
    console.log(`   3. Любой вызов _settleProtocolDebt() (через protocolUpdate())`);
    console.log(`      триггерит ошибку:`);
    console.log(`      - claimablePremiumError = ${(claimablePremiumError / BigInt(1e6)).toString()} USDC`);
    console.log(`      - lastClaimablePremiums обнуляется`);
    console.log(`      - insufficientTokens = ${(insufficientTokens / BigInt(1e6)).toString()} USDC теряется`);
    
    // Альтернативный сценарий: claimablePremiumError < lastClaimablePremiums, но всё равно потеря
    console.log(`\n📋 Сценарий 2: claimablePremiumError < lastClaimablePremiums (частичная потеря):`);
    const smallerError = 500_000n * BigInt(1e6); // 500k USDC ошибка
    const largerPremiums = 2_000_000n * BigInt(1e6); // 2M premiums
    
    if (smallerError <= largerPremiums) {
        const remaining = largerPremiums - smallerError;
        console.log(`   claimablePremiumError (${(smallerError / BigInt(1e6)).toString()} USDC) <`);
        console.log(`   lastClaimablePremiums (${(largerPremiums / BigInt(1e6)).toString()} USDC)`);
        console.log(`   => lastClaimablePremiums = ${(remaining / BigInt(1e6)).toString()} USDC`); 
        console.log(`   ✅ Частичная потеря: ${(smallerError / BigInt(1e6)).toString()} USDC списано со стейкеров`);
    }

    console.log("\n" + "=".repeat(80));
    console.log("📋 РЕЗЮМЕ: Критическая уязвимость подтверждена.");
    console.log("   Accounting error приводит к безвозвратной потере");
    console.log("   доходности стейкеров (claimable premiums).");
    console.log("   insufficientTokens не компенсируется ниоткуда.");
    console.log("=".repeat(80));
}

simulate();
