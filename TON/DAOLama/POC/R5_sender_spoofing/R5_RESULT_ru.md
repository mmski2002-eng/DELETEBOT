# R5 Result: sender spoofing

## Verdict

`R5` как `sender spoofing against vault withdraw path` по текущим данным **не подтверждается**.

Более точный статус:

- `Confirmed`: нет
- `Not confirmed`: да
- `Residual risk`: остаётся, потому что без исходников нельзя окончательно доказать, что trust привязан именно к address, а не только к форме вызова

## Главный вывод

Observed chain behavior сейчас скорее **против** гипотезы sender spoofing.

`vault` не получает `withdraw` напрямую от user wallet. Вместо этого observed flow выглядит так:

- user / holder инициирует action на внешнем адресе
- intermediate worker contract получает событие типа `jetton_burn`
- именно этот worker contract вызывает `daolama_vault_withdraw`

Это больше похоже на жёстко заданный internal route, чем на открытую точку входа.

## Подтверждённые факты

### 1. Все observed withdraw sender'ы — контракты, не кошельки

Для `0x7bdd97de`:

- `source_is_wallet = false` во всех observed tx

### 2. Все observed sender'ы принадлежат одному семейству кода

У всех `5` уникальных sender'ов одинаковый `code_hash`:

- `1b9c374c91cf251615da603055fe7fdee1effe45a21536cdd97eedec16675428`

Но разные `data_hash`, что похоже на pattern:

- один и тот же worker code
- разные instance state

### 3. Каждый sender стабильно связан с одним recipient

По observed tx history:

- каждый sender работает только с одним recipient address
- меняется amount
- recipient не "прыгает" между разными адресами для одного и того же sender

Это сильный индикатор position-bound / account-bound worker contract модели.

### 4. Есть chain route `jetton_burn -> worker -> vault_withdraw`

Пример для sender:

- `0:ca7d0cc5688f4ecc490428fea63b264cd9031f78ed120a91571d30b4a5b45265`

Его tx history показывает:

- inbound `jetton_burn`
- затем outbound `daolama_vault_withdraw`

Это подтверждает, что worker не случайный внешний caller, а часть бизнес-цепочки исполнения.

## Почему spoofing не подтверждается

Чтобы подтвердить `R5`, нужен минимум один из фактов:

1. vault принимает withdraw от произвольного sender
2. fake sender с тем же интерфейсом выглядит достаточным
3. sender authorization отсутствует или завязана только на body

По текущим данным этого нет.

Observed chain behavior наоборот поддерживает модель:

- `vault` общается с ограниченным набором protocol-controlled worker contracts
- user wallets напрямую в withdraw path не входят
- sender-family выглядит deterministic и role-bound

## Что пока нельзя исключить полностью

Остаётся остаточный риск:

1. `vault` может доверять не address whitelist, а лишь коду/формату вызова
2. возможен clone/state-init attack, если trusted sender derivation сделана неверно
3. возможен exploit, если можно задеплоить контракт с ожидаемым address через uninitialized path

Но это уже не подтверждается текущими observed tx и требует либо исходников, либо decompilation sender checks.

## Практический итог

`R5` сейчас **не стоит отправлять как подтверждённую уязвимость**.

Корректный статус:

- `investigated`
- `not reproduced`
- `current on-chain evidence suggests restricted worker-based sender model`

## Артефакты

- `POC/R5_sender_spoofing/POC_PLAN_ru.md`
- `POC/R5_sender_spoofing/scripts/research_r5_live.js`

## Следующий лучший шаг

Чтобы закрыть `R5` сильнее, нужны:

1. decompilation `recv_internal` у vault
2. исходники worker contracts
3. анализ address derivation / state-init для trusted worker deployment
