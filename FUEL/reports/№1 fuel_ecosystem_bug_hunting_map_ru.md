# Карта Fuel для bug hunting

Дата сбора: 2026-05-13  
Сеть: Fuel Ignition mainnet, chain id `9889`  
RPC: `https://mainnet.fuel.network/v1/graphql`

## 1. Execution model Fuel

FuelVM построена вокруг UTXO-модели, но не ограничивается простыми переводами как Bitcoin. Транзакции могут тратить coin/message inputs, вызывать контракты, создавать контракты, загружать blobs и проходить через скрипт транзакции. Важная особенность для анализа багов: пользователь заранее указывает inputs/outputs и `inputContracts`, то есть транзакция несет строгий список ресурсов, с которыми будет работать.

Параллельное исполнение достигается не магией VM, а тем, что непересекающиеся UTXO/contract access lists можно безопасно исполнять одновременно. Если две транзакции не конкурируют за один и тот же UTXO или contract state, узел может обрабатывать их параллельно. Это меняет threat model: особенно важны ошибки в перечислении ресурсов, неверные assumptions о последовательности вызовов и multi-contract композиции.

FuelVM отличается от EVM:

- FuelVM register-based, инструкции фиксированной ширины 32 бита; EVM stack-based.
- У Fuel есть `predicates`, `scripts`, `contracts`; predicates задают условия траты UTXO без постоянного состояния.
- Native assets встроены в VM: контракт может mint/burn собственные asset IDs, а не держать ERC-20 balances как обычное contract storage.
- Нет EVM-style global account nonce/state tree как основной модели исполнения; доступы выражаются через UTXO/input contracts.
- Контрактный код на Fuel по смыслу immutable после деплоя; upgrade обычно делается через proxy-pattern/новый contract id/миграцию, а не изменением байткода.
- Cross-contract calls используют call frames и изоляцию памяти. В спецификации FuelVM отдельно описаны ownership checks и W^X-граница исполняемой памяти.

## 2. Собранные артефакты

Сырые данные и скрипт:

- `scripts/collect_recent_fuel_activity.ps1` - воспроизводимый сбор последних транзакций через GraphQL.
- `data/recent_transactions_sample.json` - 1000 последних транзакций из свежего блока.
- `data/contract_activity_sample.csv` - агрегат contract IDs из sample.
- `data/known_contract_metadata.csv` - RPC metadata по известным контрактам.
- `data/contract_map.csv` - основная таблица контрактов.
- `sources/README.md` - список источников.

Ограничение: публичный Fuel GraphQL не является полноценным аналитическим индексером за 3-6 месяцев. Поэтому точный rolling volume за месяцы нужно досчитать через собственный индексер/Envio/Sentio/Dune-like pipeline. В этом пакете есть воспроизводимый свежий on-chain sample и карта подтвержденных контрактов.

## 3. Последний on-chain sample

Собрано: 1000 транзакций.  
Высота sample: `53410530`.  
Статусы: `866` success, `134` failure.

Топ горячих contract IDs в этом блоке:

| Contract | Tx count | Notes |
|---|---:|---|
| `0x02c7b1edf72ac8135d21da3eb27205432ca09c88968a65eb6eb165b48e842368` | 999 | unlabeled; bytecode ~20k hex chars |
| `0x132ab8709aff3d228bbb07af7d2338d1e4f1fcb060135922495147849dd6b8fc` | 383 | unlabeled; has balances; same salt template as several peers |
| `0xe749999a6a5190a2e8a53582f508a2ab1c9ba378d37b69dd9d5a3fc95ff15f3a` | 249 | unlabeled; large bytecode ~64k hex chars |
| `0x5a908a89f5caac1a76b199e71e44e42ffed125b2c4e64d0982e60a536a394f76` | 244 | unlabeled; balances present |
| `0x66fa6d1e596a43d5c6533986c54a853f870276133836a71463c2d76ba92182da` | 244 | unlabeled; balances present |

Вывод: главный практический bug-hunting target из свежего ончейна - не только публично известные протоколы, а unlabeled группа контрактов с экстремальной частотой в одном блоке. Их нужно деанонимизировать через explorer labels, байткод matching с open-source repos и события/ABI inference.

## 4. Контракты и dApps

| Contract name | Type | Active tx volume | Functions | Upgradeable | Notes |
|---|---|---:|---|---|---|
| FuelL2BridgeId `0x4ea6...d0e8` | Bridge | 0/1000 sample | bridged asset/native bridge handling | код immutable; L1 bridge имеет отдельный upgrade/admin surface | официальный Fuel contract; все verified bridged assets указывают на него |
| FuelMessagePortal `0xAEB0...5DDf` | L1 Bridge | n/a | message portal, withdrawals/deposits | проверить Etherscan proxy/admin | ключ к асинхронным L1/L2 сообщениям |
| FuelERC20GatewayV4 `0xa4cA...3F67` | L1 ERC20 bridge | n/a | ERC20 deposit/withdraw | проверить Etherscan proxy/admin | основной ERC20 gateway |
| Mira AMM `0x2e40...90e7` | DEX/AMM | 0/1000 sample | `create_pool`, `mint`, `burn`, `swap`, `set_hook`, `set_protocol_fees` | README заявляет immutable core; owner functions есть | singleton AMM, native assets/SRC20 LP tokens |
| Swaylend USDC Market Proxy `0x657a...ebae` | Lending | 0/1000 sample | supply/withdraw/borrow-like accounting, `absorb`, `buy_collateral`, pause/oracle/admin | да, proxy + implementation | Compound V3-like логика, Pyth dependency |
| Fluid Protocol | Stablecoin/CDP | 0/1000 sample | troves, mint/burn USDF, liquidation, redemption, stability pool | repo содержит proxy-contract; проверять ownership | Liquity-style; сложные sorted troves и redistribution |
| Pyth `0x1c86...23da` | Oracle | 0/1000 sample | price update/read | не установлено | критическая зависимость DeFi |
| Stork `0x9c11...1149` | Oracle | 0/1000 sample | price feed API | не установлено | проверять signature/publisher path |
| The Rig `0x2181...f49b` | Liquid staking/Vault | 0/1000 sample | stFUEL staking/mint/redeem | Fuel code immutable; governance/migration отдельно | официальный verified contract |
| L2 Staking `0x095f...dc4c` | Staking/Governance-adjacent | 0/1000 sample | staking/reward accounting | Fuel code immutable | официальный verified contract |
| V12 | DEX/CLOB | not measured | on-chain order book, off-chain matcher execution | unknown | асинхронный matcher + indexer: высокий bug surface |

## 5. Hot spots для аудита

1. Unlabeled high-frequency contracts из `data/contract_activity_sample.csv`.
   Они доминируют в свежем блоке. Приоритет: ABI inference, bytecode matching, посмотреть balances/assets и failed tx reasons.

2. Bridges.
   Fuel bridge имеет L1/L2 асинхронность, message proofs, ERC20 gateway и L2 asset mapping. Риски: replay/nonce, finalization assumptions, asset metadata/subId mismatch, decimal mismatch, withdrawal proof validation.

3. Swaylend.
   Основной риск в proxy/storage layout, oracle freshness, liquidation path `absorb`, pause config, collateral factor math, negative/positive principal accounting.

4. Mira.
   AMM singleton с двумя инвариантами: volatile `x*y` и stable `x^3*y + y^3*x`. Риски: rounding, asset ordering, LP supply accounting, hook/admin fee changes, periphery script assumptions.

5. Fluid.
   Сложная state machine: troves, redemptions, stability pool, sorted linked list. Риски: list corruption, stale hints, redistribution accounting, liquidation edge cases, proxy ownership.

6. Oracles: Pyth/Stork/RedStone.
   Риски: stale update acceptance, fee update path, publisher verification, price exponent/decimal conversion.

7. V12.
   Нестандартная асинхронная модель: on-chain order book + off-chain matcher/indexer. Риски: order race, stale indexer state, matcher fee extraction, cancel/fill ordering.

## 6. Следующий индексерный шаг

Для настоящего 3-6 month volume нужен индексер:

1. Идти по blocks от `latest - ~15.5M` для 6 месяцев при ~1 sec block time, либо точнее по block timestamp.
2. Для каждой tx сохранять `inputContracts`, receipts, status, gasUsed, asset movements.
3. Нормализовать contract labels из `data/contract_map.csv`, verified contracts/assets и GitHub ABIs.
4. Строить метрики: tx/day, failed ratio, unique users, touched assets, gasUsed, transfer amount events, cross-contract fanout.

Минимальная команда для обновления свежего sample:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/collect_recent_fuel_activity.ps1
```

## 7. Источники

Основные источники перечислены в `sources/README.md`. Ключевые: Fuel docs/specs, Fuel verified contracts/assets, Fuel bridge deployments, Mira repos/ABI, Swaylend docs/deployments/ABI, Fluid repo/docs, V12 architecture docs, Pyth/Stork contract address docs.
