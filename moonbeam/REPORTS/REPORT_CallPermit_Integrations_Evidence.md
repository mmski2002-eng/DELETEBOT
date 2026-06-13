# Доказательства использования CallPermit в реальных relayer/газ-абстракциях

**Дата составления:** 8 мая 2026  
**Цель:** Сбор подтверждений того, что функциональность CallPermit precompile (`0x000000000000000000000000000000000000080a`) реально задействована в экосистеме Moonbeam для gas-спонсорства и meta-transactions.

---

## 1. Официальная документация Moonbeam — CallPermit Precompile

### 1.1. Источник
- **URL:** https://docs.moonbeam.network/builders/pallets-precompiles/precompiles/call-permit/
- **Описание:** Официальная документация Moonbeam Network описывает CallPermit как precompile, реализующий EIP-712 подписанные мета-транзакции.  

### 1.2. Ключевые цитаты из документации (по смыслу):
> "The Call Permit precompile allows users to sign permits (EIP-712 Typed Data) for arbitrary calls, which can then be executed by any address that pays the gas fees."

> "The `dispatch()` function executes the permit: it recovers the signer from the signature, verifies the nonce, increments it, and executes the specified call."

### 1.3. Значение для отчёта
Официальная документация Moonbeam **прямо описывает** использование CallPermit для meta-transactions, где relayer платит газ, а пользователь подписывает permit. Это базовое подтверждение того, что атакуемая функциональность является частью официального API сети.

**Статус:** ✅ Подтверждено

---

## 2. Реальный проект: `callpermit-nft-moonbeam` (GitHub)

### 2.1. Репозиторий
- **URL:** https://github.com/ismaventuras/callpermit-nft-moonbeam
- **Описание:** "An example on how to use Call Permit precompile using hardhat and next.js"
- **Топики:** `ethereum`, `ethers`, `hardhat`, `moonbeam`, `nextjs`, `wagmi`
- **Дата создания:** 12 марта 2023
- **Развёрнуто:** Moonbase Alpha (testnet)
- **Demo:** https://callpermit-nft-moonbeam.vercel.app/

### 2.2. README.md — Прямые указания на использование
Репозиторий явно ссылается на официальную документацию Moonbeam:
> "Based on [Interacting with the Call Permit Precompile](https://docs.moonbeam.network/builders/pallets-precompiles/precompiles/call-permit/) by Moonbeam team."

**Сценарий использования:** Lazy Minting NFT — пользователь подписывает permit на mint NFT, а relayer (или любой другой адрес) вызывает `dispatch()` и платит газ.

### 2.3. Значение для отчёта
Это **реальный проект**, который:
- Использует `dispatch()` функцию CallPermit precompile
- Подразумевает, что executor (вызывающий dispatch) платит газ
- Развёрнут на Moonbase Alpha (реальная тестнет-сеть)
- Содержит исходный код смарт-контракта на Solidity

**Статус:** ✅ Подтверждено — существует публичный GitHub-репозиторий

---

## 3. Связь с Biconomy

### 3.1. Документация Biconomy
- **URL:** https://docs.biconomy.io/
- Biconomy предоставляет инфраструктуру для gasless-транзакций через:
  - **Supertransaction API** — мультичейн-оркестрация
  - **AbstractJS SDK** — разделы "Sponsor Gas", "Gas in Tokens", "Estimating Gas"
  - **Gasless Apps** — спонсирование транзакций для пользователей

### 3.2. Применимость к Moonbeam
Biconomy поддерживает множество EVM-совместимых сетей. Хотя Moonbeam не указан явно на главной странице документации, архитектура Biconomy позволяет интегрироваться с любой EVM-цепочкой, включая Moonbeam. Biconomy использует механизмы **подписанных meta-transactions** (EIP-712), где:
1. Пользователь подписывает транзакцию off-chain
2. Biconomy relayer отправляет её в сеть и платит газ
3. Relayer получает компенсацию от dApp (paymaster) или пользователя

### 3.3. Сценарий атаки на CallPermit через Biconomy
Если Biconomy добавит поддержку Moonbeam (или уже поддерживает через generic EVM integration), то relayer Biconomy, обрабатывающий `dispatch()` вызовы, будет уязвим для griefing-атаки:
1. Атакующий подписывает permit с вызовом функции, которая ревертнется
2. Отправляет permit в Biconomy relayer
3. Relayer вызывает `dispatch()` → платит газ → subcall ревертится → nonce откатывается
4. Атакующий повторяет ту же подпись снова → relayer снова платит газ

**Статус:** ⚠️ Косвенное подтверждение — Biconomy поддерживает meta-transactions, которые могут быть адаптированы для Moonbeam

---

## 4. Связь с OpenGSN

### 4.1. Архитектура OpenGSN
- **URL:** https://docs.opengsn.org/
- OpenGSN — децентрализованная сеть relayer'ов для gasless-транзакций
- Ключевые компоненты: **Forwarder** (проверяет подпись и nonce), **RelayHub**, **Paymasters**
- Forwarder использует **nonce-based replay protection** — точно такой же механизм, как в CallPermit

### 4.2. Параллель с уязвимостью CallPermit
В OpenGSN Forwarder:
1. Проверяет nonce подписанного сообщения
2. Инкрементит nonce
3. Выполняет call
4. Если call ревертится — **nonce не откатывается** (так как OpenGSN использует смарт-контракт, а не прекомпил)

А в CallPermit precompile:
1. Nonce инкрементится в storage
2. Выполняется subcall
3. Subcall ревертится → nonce **откатывается** из-за EVM frame rollback

### 4.3. Применимость к Moonbeam
- OpenGSN **не указывает Moonbeam** в списке поддерживаемых сетей (поддерживаются Ethereum, Polygon, Optimism, Arbitrum, Avalanche, BSC, Gnosis Chain)
- Однако OpenGSN может быть развёрнут на любой EVM-совместимой цепочке
- Атака на CallPermit отличается от OpenGSN тем, что не требует специального Forwarder — уязвимость в самом прекомпиле

**Статус:** ⚠️ OpenGSN не поддерживает Moonbeam напрямую, но служит концептуальным подтверждением релевантности nonce-based relayer систем

---

## 5. Связь с Gelato Network

### 5.1. Gelato на Moonbeam
Gelato Network (https://www.gelato.network/) — один из крупнейших relayer-сервисов, поддерживающий Moonbeam. Gelato предоставляет:
- **Automated relayer** — отправка транзакций по расписанию или по условию
- **Gasless transactions** — спонсирование газа для пользователей
- **1Balance** — единый баланс для оплаты газа в разных сетях

### 5.2. Сценарий атаки
Если приложение на Moonbeam использует Gelato relayer в связке с CallPermit:
1. Пользователь подписывает permit (формирует EIP-712 typed data)
2. Приложение отправляет permit в Gelato relayer
3. Gelato relayer вызывает `dispatch()` и платит газ
4. При реверте subcall'а — nonce откатывается
5. Та же подпись может быть использована повторно → Gelato снова платит

### 5.3. Подтверждение
Поиск по GitHub показывает проекты, интегрирующие Gelato + Moonbeam (например, `hyd628/moonbeam-intro-course-resources`). Gelato — популярный выбор для gas-спонсорства на Moonbeam.

**Статус:** ⚠️ Косвенное подтверждение — Gelato доступен на Moonbeam и может использоваться с CallPermit

---

## 6. On-chain анализ — Методология проверки

### 6.1. Адрес precompile
```
CallPermit: 0x000000000000000000000000000000000000080a
```

### 6.2. Метод поиска транзакций
Для верификации реального использования CallPermit на Moonbeam/Moonbase Alpha необходимо:

1. **Через Moonscan API** (https://moonbeam.moonscan.io/):
   - Фильтр по адресу `0x000000000000000000000000000000000000080a`
   - Поиск входящих транзакций с вызовом `dispatch()`
   - Анализ 4-byte selector вызываемой функции

2. **Через RPC-запросы:**
   - `eth_getLogs` с фильтром по адресу precompile
   - `eth_call` для проверки nonce после успешных/reverted вызовов

3. **Пример команды curl для Moonscan:**
   ```bash
   curl "https://api-moonbase.moonscan.io/api?module=account&action=txlist&address=0x000000000000000000000000000000000000080a&startblock=0&endblock=99999999&sort=desc&apikey=YOUR_API_KEY"
   ```

### 6.3. Ограничения
- Moonscan может не индексировать вызовы к precompile адресам так же, как обычные контракты
- Для полного анализа требуется доступ к архиву блоков Moonbeam
- На тестнете Moonbase Alpha могут быть учебные/тестовые транзакции

**Статус:** 🔄 Методология описана, требуется практическая проверка

---

## 7. Резюме: Доказательная база для Immunefi

| № | Тип доказательства | Источник | Статус |
|---|-------------------|----------|--------|
| 1 | Официальная документация Moonbeam | https://docs.moonbeam.network/builders/pallets-precompiles/precompiles/call-permit/ | ✅ |
| 2 | Публичный GitHub-репозиторий с использованием CallPermit | https://github.com/ismaventuras/callpermit-nft-moonbeam | ✅ |
| 3 | Lazy minting NFT через CallPermit на Moonbase Alpha | Демо: https://callpermit-nft-moonbeam.vercel.app/ | ✅ |
| 4 | Biconomy — gasless инфраструктура (потенциально на Moonbeam) | https://docs.biconomy.io/ | ⚠️ Косвенно |
| 5 | Gelato Network — relayer на Moonbeam | https://www.gelato.network/ | ⚠️ Косвенно |
| 6 | OpenGSN — концептуальный аналог (nonce-based) | https://docs.opengsn.org/ | ⚠️ Косвенно |
| 7 | On-chain транзакции к precompile 0x080a | Требуется Moonscan API | 📋 Методология |
| 8 | Существующий PoC (nonce rollback) | test/CallPermitNonceRollbackPoC.t.sol | ✅ |

---

## 8. Аргументы для Immunefi

### 8.1. Сильные аргументы
1. **CallPermit — официальный precompile Moonbeam:** Это не экспериментальная функция, а часть основного протокола, доступная на Mainnet, Moonriver и Moonbase Alpha.
2. **dispatch() предназначен для relayer'ов:** Сама архитектура CallPermit спроектирована так, что executor (relayer) платит газ, а пользователь подписывает permit. Это прямое use-case для gas-абстракции.
3. **Существует публичный проект, использующий CallPermit:** `callpermit-nft-moonbeam` доказывает, что разработчики реально интегрируют этот precompile.
4. **Gelato доступен на Moonbeam:** Gelato — один из крупнейших relayer-сервисов, работающий на Moonbeam. Если любое dApp использует Gelato + CallPermit, атака становится экономически эффективной.
5. **Nonce-rollback не требует дополнительных условий:** Для атаки нужен только permit с неуспешным subcall'ом. Не нужно никаких специальных разрешений или привилегий.

### 8.2. Рекомендации для усиления репорта
1. ✅ **Найден публичный GitHub-репозиторий** с использованием CallPermit — можно сослаться как на proof-of-integration
2. **Проверить Moonbeam ecosystem page** на наличие dApp, использующих meta-transactions
3. **Проверить Gelato документацию** по Moonbeam интеграции
4. **Проверить Biconomy документацию** на предмет упоминания Moonbeam

---

## 9. Приложение: Полезные ссылки

| Ресурс | URL |
|--------|-----|
| Moonbeam CallPermit Docs | https://docs.moonbeam.network/builders/pallets-precompiles/precompiles/call-permit/ |
| GitHub: callpermit-nft-moonbeam | https://github.com/ismaventuras/callpermit-nft-moonbeam |
| Демо: CallPermit NFT Moonbeam | https://callpermit-nft-moonbeam.vercel.app/ |
| Biconomy Docs | https://docs.biconomy.io/ |
| OpenGSN Docs | https://docs.opengsn.org/ |
| Gelato Network | https://www.gelato.network/ |
| Moonbeam Moonscan | https://moonbeam.moonscan.io/ |
| Moonbase Alpha Faucet | https://apps.moonbeam.network/moonbase-alpha/faucet/ |
| Moonbeam GitHub (основной репозиторий) | https://github.com/moonbeam-foundation/moonbeam |
| CallPermit исходный код (Rust) | `precompiles/call-permit/src/lib.rs` |
| Наш PoC | `test/CallPermitNonceRollbackPoC.t.sol` |

---

**Подготовлено для:** DELETEBOT Security Research  
**Дата:** 8 мая 2026  
**Язык:** Русский  
**Назначение:** Сопутствующие доказательства для репорта на Immunefi
