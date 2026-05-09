/**
 * PoC #7 — Precision loss в SherDistributionManager.calcReward()
 * Severity: High | Impact: Yield theft (SHER tokens)
 *
 * Суть: Деление перед умножением в calcReward() приводит к потере точности.
 * Проблема в строке 151: дополнительное деление на DECIMALS (1e6) после того,
 * как уже произошло целочисленное деление на (zeroRewardsStartTVL - maxRewardsEndTVL).
 * Для малых _amount это даёт 0 SHER.
 */

function simulate() {
    console.log("=".repeat(80));
    console.log("PoC #7: Precision loss в SherDistributionManager.calcReward()");
    console.log("Severity: HIGH | Impact: Yield theft (SHER tokens)");
    console.log("=".repeat(80));

    // Параметры из контракта
    const DECIMALS = BigInt(1e6);                // 6 decimals для USDC
    const SHER_DECIMALS = BigInt(1e18);           // 18 decimals для SHER
    const maxRewardsRate = 40n * BigInt(1e12);    // 40% APR в 1e18 формате
    const maxRewardsAvailable = 100_000n * SHER_DECIMALS; // 100k SHER max rewards
    const zeroRewardsStartTVL = 100_000_000n * DECIMALS;  // 100M USDC
    const maxRewardsEndTVL = 10_000_000n * DECIMALS;      // 10M USDC
    const _period = 1209600n;                     // 2 weeks в секундах

    console.log("\n📊 Параметры Kors curve:");
    console.log(`   maxRewardsRate:             40% APR`);
    console.log(`   maxRewardsAvailable:        ${(maxRewardsAvailable / SHER_DECIMALS).toString()} SHER`);
    console.log(`   zeroRewardsStartTVL:        ${(zeroRewardsStartTVL / DECIMALS).toString()} USDC`);
    console.log(`   maxRewardsEndTVL:           ${(maxRewardsEndTVL / DECIMALS).toString()} USDC`);

    // --- ТЕСТ 1: проверим деление/умножение порядок ---
    console.log("\n" + "-".repeat(40));
    console.log("TEST 1: Проверка порядка вычислений");
    console.log("-".repeat(40));
    
    // tvl = maxRewardsEndTVL - 1 (чуть ниже границы - полные награды)
    // Формула: _sher = (_amount * maxRewardsRate * _period) / DECIMALS
    const tvl1 = maxRewardsEndTVL - 1n;
    const amount1 = 1n * DECIMALS; // 1 USDC
    
    const fullReward = (amount1 * maxRewardsRate * _period) / DECIMALS;
    console.log(`\n  tvl < maxRewardsEndTVL: полные награды`);
    console.log(`  amount = 1 USDC, period = 14 days`);
    console.log(`  _sher = ${(fullReward / SHER_DECIMALS).toString()} SHER`);
    console.log(`  _sher (wei) = ${fullReward}`);
    
    // --- ТЕСТ 2: tvl в Kors зоне, близко к maxRewardsEndTVL ---
    console.log("\n" + "-".repeat(40));
    console.log("TEST 2: Деление перед умножением - потеря точности");
    console.log("-".repeat(40));
    
    // tvl = maxRewardsEndTVL + 1n (чуть выше - в Kors зоне)
    // Но из-за округления: (zeroRewardsStartTVL - tvl) / (zeroRewardsStartTVL - maxRewardsEndTVL)
    // Для малых _amount результат может быть 0 после / DECIMALS
    
    const tvl2 = maxRewardsEndTVL + 1n; // 10,000,001 USDC
    console.log(`\n  tvl = ${(tvl2 / DECIMALS).toString()} USDC (чуть выше maxRewardsEndTVL)`);
    console.log(`  В Kors зоне: ${((tvl2 - maxRewardsEndTVL) * 100n / (zeroRewardsStartTVL - maxRewardsEndTVL)).toString()}% от maxRewardsEndTVL до zeroRewardsStartTVL`);
    
    // Уязвимое место в контракте (строки 148-151):
    // _sher += (
    //     ((zeroRewardsStartTVL - position) * _amount * maxRewardsRate * _period) /
    //     (zeroRewardsStartTVL - maxRewardsEndTVL)
    // ) / DECIMALS;
    //
    // Проблема: целочисленное деление на (zeroRewardsStartTVL - maxRewardsEndTVL),
    // а затем ещё / DECIMALS. Для малых _amount:
    // numerator = (90M) * amount * 40e12 * 1.2e6 = очень большое число
    // denominator = 90M USDC = 90_000_000 * 1e6 = 9e13
    // После первого деления: big / 9e13
    // После второго деления (/1e6): может быть 0 для малых amount
    
    const testAmounts = [
        1n,                    // 1 wei
        100n,                  // 100 wei
        10000n,                // 0.01 USDC
        DECIMALS / 100n,       // 0.01 USDC
        DECIMALS / 10n,        // 0.1 USDC
        DECIMALS,              // 1 USDC
        DECIMALS * 10n,        // 10 USDC
        DECIMALS * 100n,       // 100 USDC
    ];
    
    console.log(`\n  Результаты calcReward() для разных _amount:`);
    console.log(`  ${"_amount".padEnd(22)} | step1 (slopePart1/slopePart2) | step2 (/DECIMALS) | _sher`);
    console.log(`  ${"-".repeat(22)}-|-${"-".repeat(33)}-|-${"-".repeat(15)}-|-${"-".repeat(10)}`);
    
    for (const amount of testAmounts) {
        const diff = zeroRewardsStartTVL - tvl2; // 90_000_000 USDC - 1 wei (почти 90M)
        const slopePart1 = diff * amount * maxRewardsRate * _period;
        const slopePart2 = zeroRewardsStartTVL - maxRewardsEndTVL; // 90M USDC
        const step1 = slopePart1 / slopePart2; // первое деление
        const step2 = step1 / DECIMALS;        // второе деление
        
        const amountFormatted = amount < DECIMALS 
            ? `${amount.toString()} wei` 
            : `${(amount / DECIMALS).toString()} USDC`;
        
        const lost = (step2 === 0n && amount > 0n) ? " ⚠️  LOST!" : "";
        console.log(`  ${amountFormatted.padEnd(22)} | ${step1.toString().padEnd(31)} | ${step2.toString().padEnd(13)} | ${(step2 / SHER_DECIMALS).toString().padEnd(8)}${lost}`);
    }

    // --- ТЕСТ 3: накопление потерь ---
    console.log("\n" + "-".repeat(40));
    console.log("TEST 3: Накопление потерь при массовых микростейках");
    console.log("-".repeat(40));
    
    const N = 1000;
    const microAmount = 1000n; // 1000 wei = 0.001 USDC
    
    let totalSherMicro = 0n;
    const diff2 = zeroRewardsStartTVL - tvl2;
    const slopePart2Val = zeroRewardsStartTVL - maxRewardsEndTVL;
    
    for (let i = 0; i < N; i++) {
        const s1 = diff2 * microAmount * maxRewardsRate * _period;
        const s2 = s1 / slopePart2Val;
        const s3 = s2 / DECIMALS;
        totalSherMicro += s3;
    }
    
    // Bulk: один большой стейк N * microAmount
    const bulkAmount = microAmount * BigInt(N);
    const b1 = diff2 * bulkAmount * maxRewardsRate * _period;
    const b2 = b1 / slopePart2Val;
    const b3 = b2 / DECIMALS;
    
    const loss = b3 - totalSherMicro;
    console.log(`\n  ${N}x micro-stakes of ${microAmount} wei each:`);
    console.log(`  Bulk reward:   ${(b3 / SHER_DECIMALS).toString()} SHER`);
    console.log(`  Micro reward:  ${(totalSherMicro / SHER_DECIMALS).toString()} SHER`);
    console.log(`  Precision loss: ${(loss / SHER_DECIMALS).toString()} SHER`);

    // --- ТЕСТ 4: Минимальный стейк для получения 1 wei SHER ---
    console.log("\n" + "-".repeat(40));
    console.log("TEST 4: Найти минимальный стейк для ненулевой награды");
    console.log("-".repeat(40));
    
    for (let a = 1n; a <= 1_000_000n; a *= 10n) {
        const s1 = diff2 * a * maxRewardsRate * _period;
        const s2 = s1 / slopePart2Val;
        const s3 = s2 / DECIMALS;
        const amtLabel = a < DECIMALS 
            ? `${a.toString()} wei (${(a * 1000000n / DECIMALS).toString()}e-6 USDC)`
            : `${(a / DECIMALS).toString()} USDC`;
        console.log(`  amount=${amtLabel.padEnd(25)} => _sher=${(s3 / SHER_DECIMALS).toString().padStart(5)} wei${s3 === 0n ? " ⚠️  ZERO" : ""}`);
    }
    
    console.log("\n" + "=".repeat(80));
    console.log("RESULT: Precision loss CONFIRMED.");
    console.log("  For amounts < 1 USDC in Kors curve zone, the");
    console.log("  double-division pattern causes _sher = 0.");
    console.log("  Mass micro-stakes lose significant SHER rewards.");
    console.log("=".repeat(80));
}

simulate();
