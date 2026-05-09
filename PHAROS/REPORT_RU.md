Заголовок

Отсутствие проверки владения ключом валидатора / proof-of-possession в `Staking.registerValidator()` позволяет захватить validator identity и активировать валидатора с непроверенными ключами

Серьёзность

High

Потенциально Critical, если node / consensus layer Pharos не выполняет независимую off-chain проверку владения validator key или PoP перед принятием validator set.

Затронутый компонент

- Системный контракт: `Staking` по адресу `0x4100000000000000000000000000000000000000`
- Напрямую затронутая функция: `registerValidator(...)`
- Связанные жизненные циклы: `advanceEpoch()`, активация валидатора, `updateValidator(...)`, `exitValidator(...)`

Подтверждённые связанные системные адреса

- `0x4100000000000000000000000000000000000000` - `Staking` proxy / system contract
- `0x4100000000000000000000000000000000000001` - `Staking` implementation
- `0x3100000000000000000000000000000000000000` - `ChainConfig` proxy
- `0x3100000000000000000000000000000000000001` - `ChainConfig` implementation

Краткое резюме

`Staking.registerValidator()` принимает:

- `_publicKey`
- `_publicKeyPop`
- `_blsPublicKey`
- `_blsPublicKeyPop`
- `_endpoint`

но не проверяет, что вызывающий реально владеет приватными ключами, соответствующими `_publicKey` или `_blsPublicKey`.

Контракт вычисляет `poolId` из `_publicKey` как:

`poolId = sha256(publicKeyBytes)`

и первый вызвавший, зарегистрировавший этот public key, становится владельцем соответствующей validator-записи.

Из-за этого, если атакующий узнаёт public key другого валидатора до его on-chain регистрации, он может заранее зарегистрировать этот ключ, занять производный `poolId` и заблокировать легитимному владельцу регистрацию этой validator identity.

Локальные тесты также подтверждают, что валидатор, зарегистрированный с произвольными PoP placeholder-значениями, может пройти путь от `pendingAdd` до `active` через обычный epoch activation flow.

Что подтверждено

- On-chain регистрация валидатора не проверяет PoP и не проверяет владение ключом.
- Первый регистратор данного `publicKey` становится владельцем соответствующего `poolId`.
- Валидатор с произвольными PoP-значениями может стать active внутри staking-контракта.

Что пока не подтверждено

- Выполняет ли Pharos node / consensus layer компенсирующую off-chain проверку перед тем, как доверять validator set.
- Используются ли BLS-ключи таким образом, что отсутствие PoP эскалирует проблему в rogue-key / aggregate-signature vulnerability.

Корневая причина

Контракт хранит PoP-related поля, но не валидирует их перед принятием регистрации валидатора.

В видимом registration path:

- `_publicKeyPop` просто сохраняется
- `_blsPublicKeyPop` просто сохраняется
- криптографическая проверка владения ключом не выполняется
- уникальность `poolId` обеспечивается только хешем public key, а не доказательством контроля над этим ключом

Влияние

Подтверждённое влияние:

- validator key squatting
- denial of service регистрации валидатора
- несанкционированная привязка validator identity к staking owner address атакующего
- активация validator entry с произвольными PoP placeholder-значениями

Условное влияние, зависящее от непубличного node / consensus behavior:

- включение неработоспособного валидатора в active validator set
- деградация целостности validator set
- ухудшение liveness, если сеть доверяет валидаторам, которые на самом деле не могут подписывать consensus messages
- потенциально более серьёзный consensus-level риск, если BLS keys используются без независимой проверки владения

Почему это сильнее, чем предыдущий `advanceEpoch` finding

Предыдущая проблема с duplicate `poolId` в reward path была admin-only input validation bug.

Эта проблема принципиально отличается:

- `registerValidator()` — внешняя `payable` функция
- attack surface публичный
- атакующему не нужны admin-привилегии
- уязвимый state transition начинается на boundary принятия валидатора

Публичные подтверждения из tooling и docs Pharos

1. Официальный публичный `ops` tool работает со staking-контрактом `0x4100000000000000000000000000000000000000`.
2. В публичном исходнике `ops` команда `add-validator` пакует вызов `registerValidator(...)`, используя:
   - `domainPubKey`
   - `stabilizingPubKey`
   - `proofOfPossession = "0x00"`
   - `blsProofOfPossession = "0x00"`
3. Публичная документация по validator deployment описывает регистрацию через `domain-pubkey` и `stabilizing-pubkey`, но не описывает обязательный шаг генерации или проверки PoP в registration workflow.

Это сильное публичное свидетельство того, что поддерживаемый публичный registration path не опирается на реальные PoP-значения на границе контракта.

Источники:

- `PharosNetwork/ops`: https://github.com/PharosNetwork/ops
- `validator.go` raw: https://raw.githubusercontent.com/PharosNetwork/ops/main/cmd/validator.go
- docs по деплою валидатора: https://docs.pharosnetwork.xyz/node-and-validator-guide/validator-node-deployment/using-binary-deployment
- docs по node debugging, где указан тот же system contract: https://docs.pharosnetwork.xyz/node-and-validator-guide/node-debugging-and-configuration

Code path

Видимое поведение в `Staking.sol`:

1. `registerValidator(...)` читает `_publicKey`
2. конвертирует его в bytes
3. вычисляет `poolId = sha256(publicKeyBytes)`
4. отклоняет вызов только если этот `poolId` уже принадлежит другому адресу
5. сохраняет `_publicKeyPop` и `_blsPublicKeyPop`
6. добавляет валидатора в `pendingAddPoolSets`
7. позже `advanceEpoch()` может активировать его, если достигнут stake threshold

Это означает, что контракт использует строку public key как identity anchor валидатора, но не доказывает, что регистратор действительно контролирует эту identity.

Сценарий атаки A - validator key squatting

1. Легитимный валидатор генерирует domain public key и stabilizing/BLS public key.
2. Атакующий узнаёт public key жертвы до on-chain регистрации.
3. Атакующий вызывает `registerValidator()` с чужим `_publicKey`.
4. Контракт вычисляет `poolId` жертвы из этого public key.
5. Атакующий становится `validators[poolId].owner`.
6. Когда легитимный валидатор позже пытается зарегистрировать тот же public key, транзакция ревертится, потому что pool уже зарегистрирован на другой адрес.

Результат:

- легитимный валидатор не может привязать свою validator identity к intended staking owner
- атакующий захватывает validator identity на staking layer

Сценарий атаки B - активация валидатора с невалидным PoP

1. Атакующий регистрирует валидатора с произвольными PoP placeholder-значениями.
2. Контракт принимает регистрацию и ставит валидатора в `pendingAdd`.
3. После epoch advancement контракт активирует валидатора, если stake threshold выполнен.

Результат:

- staking layer может продвинуть validator entry, для которого владение consensus key никогда не проверялось on-chain

Статус локального воспроизведения

Я выполнил локальное воспроизведение на локальной копии `PharosNetwork/contracts` через Foundry.

Добавленный тестовый файл:

- `pharos-contracts/test/StakingPoPValidationTest.t.sol`

Запущенные тесты:

- `testRegisterValidatorAcceptsArbitraryPoPValues()`
- `testFirstRegistrantCanSquatPoolId()`
- `testValidatorWithArbitraryPoPCanBecomeActive()`

Наблюдаемый результат:

- все 3 теста прошли
- `registerValidator()` принимает произвольные PoP values
- первый регистратор занимает `poolId`
- валидатор становится active после `advanceEpoch()`

Локальный вердикт:

Уязвимость на staking layer подтверждена.

Затронутые компоненты

Подтверждённо напрямую затронуты:

- системный `Staking` контракт по адресу `0x4100000000000000000000000000000000000000`
- registration и activation flow, корнем которых является `registerValidator(...)`

Вероятно операционно связаны:

- `ChainConfig` по адресу `0x3100000000000000000000000000000000000000`, потому что staking ссылается на него через `cfg()`

Условно затронуты, в зависимости от поведения node / consensus layer:

- validator-set admission pipeline
- consensus liveness и trust model валидаторов
- SPN-related validator selection surfaces, если они опираются на staking-accepted validator identity

Безопасный PoC plan для triage

PoC 1 - контракт принимает произвольный PoP

Цель:

Показать, что контракт принимает произвольные `_publicKeyPop` и `_blsPublicKeyPop` и сохраняет их как есть.

Ожидаемый результат:

Регистрация проходит успешно, а сохранённые validator fields совпадают с attacker-controlled placeholder values.

PoC 2 - key squatting

Цель:

Показать, что первый регистратор public key становится владельцем производного `poolId`, а более поздний легитимный регистратор уже не может использовать тот же public key.

Ожидаемый результат:

Вторая регистрация ревертится с:

`PoolId registered by another address: cannot re-register`

PoC 3 - валидатор с невалидным PoP может стать active

Цель:

Показать, что валидатор с произвольными PoP values может пройти путь из `pendingAdd` в `active`.

Ожидаемый результат:

Валидатор принимается в `pendingAdd`, а затем становится active после `advanceEpoch()`.

Текущая оценка

Это валидная подтверждённая staking-layer vulnerability.

Наиболее сильная полностью подтверждённая severity-формулировка на текущий момент:

High - отсутствие проверки владения validator key / PoP позволяет захватывать validator identity, вызывать registration DoS и активировать unverified validator identities на staking layer.

Проблема становится потенциально Critical только если дальнейшая проверка Pharos node / consensus layer покажет, что:

- компенсирующей off-chain валидации нет, и
- зарегистрированные ключи используются для consensus participation без проверки владения

Рекомендуемое исправление

Нужно обеспечить хотя бы одно из следующего:

1. Проверять владение validator key в момент регистрации.
2. Отклонять регистрацию, если consensus key не подписал domain-separated registration message.
3. Если полная on-chain PoP verification невозможна, node / consensus layer должен отвергать любую validator entry с невалидным ownership proof, и это должно быть явно задокументировано.

Более надёжный дизайн:

- требовать EVM-подпись от staking owner address
- требовать подпись или PoP от consensus key по domain-separated message вида:

`PharosValidatorRegistration(chainId, stakingContract, owner, publicKey, blsPublicKey, nonce)`

- не допускать активацию валидатора в validator set, пока ownership proof не валиден

Дополнительное усиление

- Добавить invariant test, что вызывающий не может зарегистрировать чужой public key без доказательства владения.
- Добавить invariant test, что arbitrary PoP placeholder values не могут попасть в active validator set.
- Явно задокументировать, где именно проверяется PoP: on-chain, off-chain или в обоих местах.
- Если задуман только off-chain validation, fail closed и рассматривать её отсутствие как consensus-critical condition.

Готовое заключение для отчёта

`Staking.registerValidator()` принимает validator identity material и PoP-поля, но не проверяет владение переданными consensus keys. Поскольку `poolId` выводится напрямую из `_publicKey`, первый вызвавший, зарегистрировавший этот public key, становится владельцем соответствующей validator identity на staking layer. Локальное воспроизведение подтверждает, что произвольные PoP values принимаются, что первый регистратор может занять производный `poolId`, и что такой валидатор может стать active через обычный epoch flow.

Это подтверждает реальную публичную атаку на staking layer: validator key squatting и registration DoS. Эскалация до consensus-critical severity зависит от того, выполняет ли Pharos независимую off-chain проверку владения validator key перед тем, как доверять validator set.
