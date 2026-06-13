TORCH FINANCE — SECURITY RESEARCH REPORT
ШАГ 1: ARCHITECTURE RECONNAISSANCE
Контракты в scope
torch-dex-contract (FunC, ~1800 строк кода)

Контракт	Роль
factory/main.fc	Деплой пулов, vault'ов, LP account'ов
pools/base_pool/main.fc	Stable swap pool: deposit/swap/withdraw
pools/meta_pool/main.fc	Meta pool (base LP + другой актив)
pools/algorithms/curve_algorithm.fc	StableSwap математика (Newton's method)
pools/handler.fc	Общие обработчики deposit/swap/withdraw
pools/parser.fc	Парсинг + валидация sender
vaults/jetton_vault/main.fc	Entry point для jetton активов
vaults/ton_vault/main.fc	Entry point для TON
lp_account/main.fc	Накапливает активы перед deposit_all
torch-tgusd-contract (Tolk, ~1500 строк кода)

Контракт	Роль
tgusd-engine/main.tolk	Минт/погашение tgUSD, оракул-order система
redeem-account/main.tolk	Child contract для cooldown redemption
tgusd-staking/main.tolk	Стейкинг tgUSD → stgUSD, reward vesting
unstake-account/main.tolk	Child contract для cooldown unstake
Граф взаимодействий DEX

User
 ├─[deposit]→ Vault →[deposit_internal]→ Factory →[install]→ LPAccount
 │                                                               └─[deposit_all]→ Pool →[payout]→ Vault → User
 ├─[swap]→ Vault →[swap_internal]→ Pool →[payout]→ Vault → User  
 └─[withdraw]→ Vault(LP) →[withdraw_internal]→ Pool →[payout]→ Vault → User
Privileged roles
DEX: pool::admin, factory::admin — stop/unstop pool, ramp A, update fees, upgrade code
tgUSD: admin (multisig), custodialWallet, stakedManager, signerKey (off-chain signer)
ШАГ 2-5: АНАЛИЗ УЯЗВИМОСТЕЙ
🔴 CRITICAL-1: tgUSD Staking — Permanent freeze of user funds after pool drains
Файл: tgusd-staking/shares.tolk + tgusd-staking/main.tolk

Описание
convertToShares имеет race condition при totalShares == 0 но totalStaked > 0:


// shares.tolk:13
fun convertToShares(totalShares, totalStaked, unvestedAmount, stakeAmount): coins {
    if (totalStaked == 0) {
        return stakeAmount;  // только этот путь safe
    }
    // ОПАСНОСТЬ: если totalShares == 0 но totalStaked > 0:
    return mulDivFloor(stakeAmount, totalShares, (totalStaked - unvestedAmount));
    //                              ↑ = 0         ↑ может быть = 0 → DIV BY ZERO
}
Когда totalShares == 0 и totalStaked > 0, функция возвращает 0 (или бросает division-by-zero). Затем:


// handler.tolk:43
val mintedShares: coins = convertToShares(...);  // возвращает 0 или бросает
requirePositiveShare(mintedShares);               // бросает ERROR_INVALID_SHARE
Критически важно: в этом пути нет commit() перед throw. Паттерн commit() + throw() используется в других местах для отправки refund-сообщения перед откатом транзакции. Здесь он ОТСУТСТВУЕТ.

PoC последовательность
User A стейкает 1000 tgUSD → totalShares=1000, totalStaked=1000
Протокол отправляет reward 100 tgUSD (через OP_SUPPLY_REWARD_FP) → totalStaked=1100, vestingReward=100
User A анстейкает все 1000 stgUSD (burns):
shares == totalShares → unstakedAmount = totalStaked - unvestedAmount = 1100 - 100 = 1000
После: totalShares=0, totalStaked=100 (unvested rewards остаются)
User B отправляет 500 tgUSD в стейкинг с OP_STAKE_FP:
convertToShares(totalShares=0, totalStaked=100, unvestedAmount≈100, stakeAmount=500)
totalStaked != 0 → не входит в первую ветку
mulDivFloor(500, 0, 100-100) = mulDivFloor(500, 0, ~0) → exception ИЛИ возвращает 0
requirePositiveShare(0) → throw без commit()
Refund сообщение НЕ отправляется
Транзакция User B откатывается. Но 500 tgUSD уже находятся в tgUSDJettonWallet стейкинга — навсегда заблокированы.
Почему state = totalShares=0, totalStaked>0 достижим без admin
Это нормальный жизненный цикл протокола:

Все пользователи вышли из стейкинга
Остались невестированные rewards в totalStaked
Не требует никаких привилегированных операций
После анстейка последнего пользователя: totalStaked = vestingReward_остаток. Любой новый стейкер попадает в ловушку.

Severity: Critical
Impact: Permanent freeze of funds — tgUSD навсегда в staking wallet
Exploitability: Без admin, через естественный lifecycle протокола
In scope: ✅ "Permanent freezing of funds due to contract errors" явно в scope
Fix

fun convertToShares(totalShares, totalStaked, unvestedAmount, stakeAmount): coins {
    if (totalStaked == 0 || totalShares == 0) {  // ← добавить totalShares == 0
        return stakeAmount;
    }
    val vestedStaked = totalStaked - unvestedAmount;
    if (vestedStaked == 0) { return stakeAmount; }  // ← guard against div/0
    return mulDivFloor(stakeAmount, totalShares, vestedStaked);
}
И добавить refund pattern в staking handler для OP_STAKE_FP:


val mintedShares = handleStake(...);
// если handleStake throws → нужен refundByTransfer() + commitContractDataAndActions() перед throw
🟡 MEDIUM-1: tgUSD Staking — OP_DEALLOCATE_STAKED_FP без проверки jettonSender
Файл: tgusd-staking/main.tolk:94-103


if (forwardPayloadOp == OP_DEALLOCATE_STAKED_FP) {
    remainingStaked += jettonAmount;  // ← нет проверки jettonSender!
    logStakedDeallocated(jettonSender, jettonAmount, remainingStaked);
    saveData();
    return;
}
Любой может отправить tgUSD в стейкинг с этим opcode и искусственно увеличить remainingStaked. При этом totalStaked не меняется.

Impact: remainingStaked > totalStaked → admin/stakedManager могут аллоцировать больше чем реально застейкано пользователями, нарушая инварианты протокола. Severity: Medium (требует admin для эксплуатации).

🟡 MEDIUM-2: DEX — Jetton vault пропускает проверку asset_out в op::payout
Файл: jetton_vault/main.fc:222-244

TON vault явно проверяет:


// ton_vault/main.fc:172
throw_unless(error::wrong_assets, asset_out.cell_hash() == pack_ton_asset().cell_hash());
Jetton vault эту проверку не делает. asset_out принимается из сообщения, но не сравнивается с vault::jetton_master.

В текущей архитектуре это не ведёт к прямой краже (т.к. vault всегда шлёт из своего vault::jetton_wallet), но нарушает defense-in-depth. Если когда-либо изменится логика routing — уязвимость откроется. Severity: Medium.

🔵 LOW-1: DEX — simulate::swap_exact_out помечен impure в getter
Файл: getters.fc:100-110

simulate::swap_exact_out объявлен как impure inline но используется только в getter методе get_simulate_swap_exact_out. Не влияет на безопасность (getters не меняют состояние), но семантически некорректно.

ШАГ 6: ИТОГОВАЯ КЛАССИФИКАЦИЯ
ID	Severity	Файл	Описание	In Scope
C-1	Critical	tgusd-staking/shares.tolk	Permanent freeze стейкеров при totalShares=0, totalStaked>0	✅
M-1	Medium	tgusd-staking/main.tolk:94	OP_DEALLOCATE_STAKED_FP без jettonSender validation	✅
M-2	Medium	jetton_vault/main.fc:222	Missing asset_out check vs TON vault	✅
L-1	Low	pools/getters.fc:100	swap_exact_out impure в getter	❌ (best practice)
ВЕЩИ, КОТОРЫЕ ВЫГЛЯДЯТ ПОДОЗРИТЕЛЬНО, НО КОРРЕКТНЫ
Bounced messages игнорируются — в DEX корректно, т.к. commit()+throw() pattern отправляет refund ДО отката
Signed rates без nonce — намеренно, replay в пределах expiration window это design decision (oracle price feed)
ASSET_NOT_FOUND = TRUE = -1 — используется корректно, все проверки != ASSET_NOT_FOUND присутствуют
get_d division by zero при xp[i]=0 — защищён инвариантом StableSwap (резервы не могут достичь 0)
claim_admin_fee обнуляет fees перед deposit — корректно, все изменения в одной транзакции
lp_account save_data после self-destruct — нормально, TON уничтожает контракт в конце транзакции