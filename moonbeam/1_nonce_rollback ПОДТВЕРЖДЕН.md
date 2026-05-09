# Nonce Rollback в CallPermit Precompile — ПОДТВЕРЖДЕН

## Статус: 🔴 Уязвимость подтверждена

### Описание

В Moonbeam CallPermit precompile найден баг: при неуспешном subcall'е (revert) **nonce откатывается**, что позволяет повторно использовать ту же самую подпись EIP-712 неограниченное количество раз.

### Механизм

1. Пользователь подписывает permit (EIP-712 typed data) с указанием `nonce`
2. Relayer (или любой адрес) вызывает `dispatch()` и платит газ
3. Precompile проверяет nonce → **инкрементит nonce в storage** (строка ~168)
4. Precompile делает subcall (например, `transfer()` или любой контракт)
5. **Если subcall reverts** → precompile возвращает `Err(PrecompileFailure::Revert)`
6. EVM executor откатывает **все изменения состояния** текущего call frame
7. **Nonce возвращается к исходному значению**

### Результат

- Та же подпись может быть использована снова
- Relayer платит газ при каждом использовании
- Атака может повторяться бесконечно (griefing)

### Затронутые сети

- Moonbeam (mainnet) — chainId 1284
- Moonriver (canary) — chainId 1285
- Moonbase Alpha (testnet) — chainId 1287

### Адрес precompile

`0x000000000000000000000000000000000000080a`

### Код

Файл: `precompiles/call-permit/src/lib.rs`

```rust
// Nonce инкрементится ДО subcall'а
NoncesStorage::insert(from, nonce + U256::one());

// ... subcall ...

// Если revert — откатывается ВСЁ, включая nonce
match reason {
    ExitReason::Revert(_) => Err(PrecompileFailure::Revert { ... }),
    ...
}
```

### Существующий тест (не проверяет nonce)

Файл: `precompiles/call-permit/src/tests.rs`

Тест `valid_permit_reverts()` проверяет только что `dispatch()` ревертнулся, но **не проверяет изменился ли nonce**.

### PoC

См. `test/CallPermitNonceRollbackPoC.t.sol`

Два теста:
1. `testRevertingSubcallRollsBackNonce()` — nonce остаётся 0 после revert
2. `testSameFailingPermitCanBeReplayed()` — один permit можно использовать 3 раза

### Фикс

Возвращать `Ok(PrecompileOutput)` вместо `Err(PrecompileFailure::Revert)` при неуспешном subcall'е, чтобы EVM не откатывал nonce.
