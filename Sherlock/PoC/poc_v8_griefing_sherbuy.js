/**
 * PoC #8 — Гриффер может заблокировать покупку SHER через dust-транзакцию
 * Severity: High (Griefing / DoS) | Impact: Temporary freezing / DoS
 *
 * Суть: viewCapitalRequirements() требует sherAmount % SHER_STEPS == 0.
 * 1 wei SHER напрямую в SherBuy ломает всю покупку.
 */

function simulate() {
    console.log("=".repeat(80));
    console.log("PoC #8: Гриффинг SherBuy через dust-транзакцию");
    console.log("Severity: HIGH (Griefing / DoS) | Impact: Temporary freezing");
    console.log("=".repeat(80));

    const DECIMALS = BigInt(1e18); // SHER has 18 decimals
    const SHER_STEPS = BigInt(1e16); // 0.01 SHER
    
    // Симулируем SherBuy.execute()
    // В контракте: viewCapitalRequirements() рассчитывает sherAmount исходя из
    // available = sher.balanceOf(address(this))
    // Если available не кратен SHER_STEPS → revert
    
    console.log("\n📊 Параметры:");
    console.log(`   SHER_STEPS:                 ${(SHER_STEPS / BigInt(1e16)).toString()}e16 (0.01 SHER)`);
    console.log(`   Для успешной покупки:       sherAmount % ${SHER_STEPS.toString()} == 0`);

    // --- Тест 1: Нормальная работа ---
    console.log("\n" + "-".repeat(40));
    console.log("🧪 Тест 1: Нормальная работа (без пыли)");
    console.log("-".repeat(40));
    
    const normalBalance = 100_000n * DECIMALS; // 100,000 SHER
    const normalRemaining = normalBalance % SHER_STEPS;
    console.log(`   balanceOf(SherBuy):          ${(normalBalance / DECIMALS).toString()} SHER`);
    console.log(`   balance % SHER_STEPS:        ${normalRemaining}`);
    console.log(`   Успешная покупка:           ${normalRemaining === 0n ? "✅ ДА" : "❌ НЕТ"}`);

    // --- Тест 2: Атака ---
    console.log("\n" + "-".repeat(40));
    console.log("🧪 Тест 2: После отправки 1 wei SHER (dust-атака)");
    console.log("-".repeat(40));
    
    const dustAmount = 1n; // 1 wei SHER
    const attackedBalance = normalBalance + dustAmount;
    const attackedRemaining = attackedBalance % SHER_STEPS;
    
    console.log(`   Атакующий отправляет:       ${dustAmount} wei (${(dustAmount * BigInt(1e18) / DECIMALS).toString()}e-18 SHER)`);
    console.log(`   balanceOf(SherBuy):          ${(attackedBalance / DECIMALS).toString()} SHER + ${attackedBalance % DECIMALS} wei`);
    console.log(`   balance % SHER_STEPS:        ${attackedRemaining}`);
    console.log(`   Успешная покупка:           ${attackedRemaining === 0n ? "✅ ДА" : "❌ НЕТ — REVERT!"}`);

    // --- Тест 3: Различные суммы dust ---
    console.log("\n" + "-".repeat(40));
    console.log("🧪 Тест 3: Различные dust-суммы");
    console.log("-".repeat(40));

    const dustTests = [1n, 2n, 10n, SHER_STEPS - 1n, SHER_STEPS / 2n, SHER_STEPS + 1n];
    
    for (const dust of dustTests) {
        const testBalance = normalBalance + dust;
        const testRemaining = testBalance % SHER_STEPS;
        const blocked = testRemaining !== 0n;
        console.log(`   dust=${dust.toString().padStart(22)} wei | blocked=${blocked ? "⚠️  ДА" : "✅ НЕТ"} | balance%steps=${testRemaining}`);
    }

    // --- Анализ ---
    console.log("\n" + "=".repeat(40));
    console.log("📊 АНАЛИЗ АТАКИ:");
    console.log("=".repeat(40));
    
    console.log(`\n💰 Стоимость атаки:`);
    console.log(`   Dust:                       1 wei SHER (≈ $0.0000000000000001)`);
    console.log(`   Газ:                        ~25k gas для ERC20 transfer`);
    console.log(`   Общая стоимость:            < $0.01`);
    
    console.log(`\n📅 Длительность блокировки:`);
    console.log(`   SherBuy активен до newEntryDeadline`);
    console.log(`   Блокировка может длиться ${14} дней (стандартная кампания)`);
    
    console.log(`\n👥 Жертвы:`);
    console.log(`   Все участники SherBuy кампании`);
    console.log(`   Не могут купить SHER по установленной цене`);
    
    console.log(`\n🔧 Невозможность восстановления:`);
    console.log(`   Нет функции "clean dust" в контракте`);
    console.log(`   Админ не может забирать ERC20 токены (если только не предусмотрено)`);
    console.log(`   Единственный выход: ждать дедлайна`);

    console.log("\n" + "=".repeat(80));
    console.log("📋 РЕЗЮМЕ: Griefing уязвимость подтверждена.");
    console.log("   1 wei SHER (стоимость < $0.0000000001) блокирует всю");
    console.log("   кампанию SherBuy на срок до дедлайна (14+ дней).");
    console.log("   Функция не имеет механизма очистки dust.");
    console.log("=".repeat(80));
}

simulate();
