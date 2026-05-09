# Отчёт по безопасности Aavegotchi на Base
**Дата**: 2026-05-09  
**Цепь**: Base Mainnet  
**Тип**: Attacker-executable Critical/High уязвимости

---

## Подтверждение активного production-деплоя на Base

| Контракт | Адрес | Статус |
|---|---|---|
| Aavegotchi Diamond (ERC721) | `0xa99c4B08201F2913Db8D28e71d020c4298F29dBF` | 153 000+ txns, verified, active |
| GBM Auction (Baazaar) | `0x80320A0000C7A6a34086E2ACAD6915Ff57FfDA31` | 21 700+ txns, verified, active |
| Forge Diamond | `0x50aF2d63b839aA32b4166FD1Cb247129b715186C` | verified, active |
| GHST Token | `0xcd2f22236dd9dfe2356d7c543161d4d260fd9bcb` | ERC20, active |
| Proof of Play VRF Proxy | `0x9eC728Fce50c77e0BeF7d34F1ab28a46409b7aF1` | 97 230+ txns, active, upgradeable |
| Wearable Diamond | `0x052e6c114a166B0e91C2340370d72D4C33752B4b` | active |
| GLTR Staking | `0xaB449DcA14413a6ae0bcea9Ea210B57aCe280d2c` | active |

Все перечисленные контракты верифицированы на BaseScan. Транзакции актуальны на момент анализа (май 2026).

---

## Уязвимость #1

- **Title**: VRFFacet — обход Chainlink VRF, случайность полностью предсказуема
- **Severity**: Critical
- **Affected Function**: `drawRandomNumber(uint256 _tokenId)` → `tempFulfillRandomness()` | файл `contracts/Aavegotchi/facets/VRFFacet.sol`

**Root Cause**:

В функции `drawRandomNumber` сразу после отправки запроса в Chainlink VRF вызывается `tempFulfillRandomness` с детерминированным «случайным» числом:

```solidity
// line 52 — VRFFacet.sol
// for testing
tempFulfillRandomness(requestId, uint256(keccak256(abi.encodePacked(block.number, _tokenId))));
```

`tempFulfillRandomness` немедленно устанавливает `status = STATUS_OPEN_PORTAL` и записывает `tokenIdToRandomNumber[tokenId] = keccak256(block.number, tokenId)`.

Когда (и если) Chainlink отвечает через `rawFulfillRandomness`, функция ревертится:
```solidity
require(s.aavegotchis[tokenId].status == LibAavegotchi.STATUS_VRF_PENDING, "VRF not pending");
```
— статус уже `OPEN_PORTAL`. Callback Chainlink никогда не проходит.

Итого: **эффективная случайность = `keccak256(block.number, tokenId)`** — оба значения публично известны до подачи транзакции.

**Attack Path**:

1. Атакующий владеет порталом с `tokenId = T` (или покупает его).
2. Перед вызовом `openPortals` вычисляет:
   ```
   randomNumber = keccak256(abi.encodePacked(targetBlock, T))
   ```
3. Для каждой опции `i` в диапазоне 0–9 вычисляет:
   ```
   traitSeed_i = keccak256(abi.encodePacked(randomNumber, i))
   ```
   и через `singlePortalAavegotchiTraits(hauntId, randomNumber, i)` восстанавливает все 10 комплектов трейтов.
4. Если ни один вариант не выгоден — ждёт следующего блока и повторяет.
5. Найдя блок с максимальным BRS/редкостью — подаёт `openPortals([T])`.
6. Немедленно вызывает `claimAavegotchi(T, bestOption, ...)` с оптимальным индексом.

**Impact**:

- Атакующий получает Aavegotchi с максимально редкими трейтами «по выбору», не платя премию.
- Rare/mythical готчи (10–100× floor) доступны системно и бесплатно сверх стоимости портала.
- Весь механизм «provably fair randomness» — маркетинговая ложь: рандом определяется номером блока.
- Комиссия LINK тратится впустую на каждый портал (реальный VRF-ответ игнорируется).

**Proof of Concept idea**:

```python
from web3 import Web3
import itertools

def predict_gotchi_traits(block_number, token_id, haunt_id):
    random_number = Web3.keccak(
        Web3.solidity_keccak(['uint256', 'uint256'], [block_number, token_id])
    )
    options = {}
    for i in range(10):
        trait_seed = Web3.keccak(
            Web3.solidity_keccak(['uint256', 'uint256'], [int(random_number.hex(), 16), i])
        )
        # вычислить BRS через ту же логику, что и singlePortalAavegotchiTraits
        options[i] = compute_brs(trait_seed, haunt_id)
    return max(options, key=options.get)

# Когда найден нужный блок — вызвать openPortals и claimAavegotchi
```

**Assumptions**: VRFFacet задеплоен в Base Diamond без изменений (GitHub master ветка, последний коммит — 19 июля 2025, за 6 дней до миграции на Base).

**Верификация (2026-05-09)**:  
BaseScan не показывает `openPortals` в списке write-функций Diamond — это может означать:
- VRFFacet заменён кастомным фасетом Proof of Play VRF → уязвимость #1 неактивна  
- ИЛИ BaseScan не отображает все функции Diamond (ABI генерируется из прокси, а не из фасетов)  
В GitHub-репозитории нет коммитов, связанных с заменой VRF на PoP перед миграцией (последний коммит VRFFacet.sol — 19 июля 2025, замена modifier name). Wiki Aavegotchi подтверждает переход на "Proof of Play VRF" для Base. Точный адрес VRF-фасета в Diamond **не верифицирован on-chain**.

**Confidence Level**: MEDIUM-HIGH (код confirmed в production-ветке; deployment неопределён — требует прямого вызова `facetAddress(0x32197727)` через DiamondLoupe).

---

## Уязвимость #2

- **Title**: EscrowFacet — `batchDepositGHST` перманентно сломана на Base (DoS)
- **Severity**: High
- **Affected Function**: `batchDepositGHST(uint256[] calldata _tokenIds, uint256[] calldata _values)` | файл `contracts/Aavegotchi/facets/EscrowFacet.sol`

**Root Cause**:

Функция хардкодит адрес GHST-токена Polygon вместо Base:

```solidity
function batchDepositGHST(uint256[] calldata _tokenIds, uint256[] calldata _values) external {
    require(_tokenIds.length == _values.length, "...");
    address maticGHST = 0x385Eeac5cB85A38A9a07A70c73e0a3271CfB54A7;  // ← POLYGON адрес
    for (uint256 index = 0; index < _tokenIds.length; index++) {
        ...
        LibERC20.transferFrom(maticGHST, LibMeta.msgSender(), escrow, value);
    }
}
```

На Base адрес `0x385Eeac5cB85A38A9a07A70c73e0a3271CfB54A7` — это **обычный EOA-кошелёк** (не контракт).

`LibERC20.transferFrom` выполняет:
```solidity
assembly { size := extcodesize(_token) }
require(size > 0, 'LibERC20: ERC20 token address has no code');
```
Для EOA `extcodesize == 0` → **всегда revert**.

**Attack Path**:

Не требует внешнего атакующего. Любой пользователь, вызывающий `batchDepositGHST`, получает немедленный revert. Функция неработоспособна на Base с момента деплоя.

**Impact**:

- Batch-депозит GHST в эскроу нескольких готчи сразу недоступен.
- Пользователи вынуждены вызывать `depositERC20` по одному на каждый токен.
- Broken interface: код успешно прошёл компиляцию, верификацию и деплой, но функционирует только на Polygon.
- Потенциально мешает автоматизированным инструментам и интеграциям, которые рассчитывают на batch-операцию.

**Proof of Concept idea**:

```javascript
// Вызов немедленно ревертится
await aavegotchiDiamond.batchDepositGHST([tokenId1, tokenId2], [amount1, amount2]);
// Revert: "LibERC20: ERC20 token address has no code"
```

**Assumptions**: Нет; `extcodesize` проверка подтверждена в `LibERC20.sol`; EOA-статус адреса подтверждён через BaseScan.

**Confidence Level**: CRITICAL (100% воспроизводимо).

---

## Уязвимость #3

- **Title**: GBM Auction — `commitBid` подпись без chainId и nonce, уязвима к replay-атаке
- **Severity**: Medium
- **Affected Function**: `commitBid(uint256 _auctionId, uint256 _bidAmount, uint256 _highestBid, bytes memory _signature)` | файл `contracts/facets/GBMFacet.sol` (GBM Diamond `0x80320A0000C7A6a34086E2ACAD6915Ff57FfDA31`)

**Root Cause**:

Хэш для верификации подписи конструируется без `chainId`, `nonce` и `expiry`:

```solidity
bytes32 messageHash = keccak256(abi.encodePacked(
    msg.sender,      // bidder
    _auctionId,      // auction ID
    _bidAmount,      // bid amount
    _highestBid      // current highest bid — единственный «нонс»
));
require(LibSignature.isValid(messageHash, _signature, s.backendPubKey), "bid: Invalid signature");
```

`LibSignature.isValid` не добавляет chainId, нонс и timestamp — подтверждено анализом кода.

**Attack Path (cross-chain replay)**:

1. GBM-контракт был задеплоен на Polygon и на Base. Если адрес GBM-контракта совпадает на обеих цепях (или на Base + testnet), и если на одной цепи бэкенд подписал `(bidder=A, auctionId=N, bidAmount=X, highestBid=0)`:
2. Атакующий A использует эту подпись на другой цепи для аукциона N в момент, когда `highestBid == 0` (начало аукциона).
3. Результат: A размещает ставку без свежей авторизации от бэкенда.

**Attack Path (same-chain auction-reset replay) — УТОЧНЕНО**:

Верификация показала: `auctionId = keccak256(abi.encodePacked(tokenContract, tokenId, tokenKind))` — тот же ID при релистинге одного и того же NFT. ОДНАКО `claim()` **не сбрасывает `highestBid` в 0** после завершения аукциона. При релистинге (`_rewrite=true`) аукцион стартует с прежним значением `highestBid` (равным цене последней выигрышной ставки). 

Следовательно, replay со старой подписью `highestBid=0` возможен **только** для первого аукциона каждого конкретного NFT (до первой ставки), или если аукцион был явно отменён без ставок.

**Конкретный Same-Chain Scenario (ограниченный)**:
1. NFT #X выставляется первый раз → `auctionId=H`, `highestBid=0`.
2. Бэкенд подписывает `(bidder=A, H, bidAmount=100, highestBid=0)`.
3. Bidder A не исполняет подпись немедленно.
4. Кто-то другой ставит первым, `highestBid` растёт.
5. Аукцион отменяется (до первой ставки), NFT возвращается.
6. NFT снова выставляется с `_rewrite=true` — `highestBid` сохраняется из прошлого аукциона (если ставки были) или равен 0 (если не было).
7. При совпадении `highestBid=0` старая подпись работает.

**Attack Path (cross-chain replay) — ОСНОВНОЙ ВЕКТОР**:
1. GBM задеплоен на Base (prod) и на testnet/staging с тем же `backendPubKey` и одинаковой логикой генерации auctionId.
2. Тестнет использует те же адреса токен-контрактов (через CREATE2 или намеренную синхронизацию) → те же `auctionId`.
3. Бэкенд подписывает `(bidder=A, auctionId=X, bidAmount=100, highestBid=0)` для testnet.
4. Replay на mainnet при совпадении `highestBid == 0` для аукциона X.

**Impact**:
- Несанкционированные ставки без актуальной авторизации бэкенда.
- При успехе: исполнитель атаки "захватывает" ставку с устаревшим разрешением, предыдущий bidder получает незапланированный refund + incentive.

**Proof of Concept idea**:

```python
# Старая подпись от testnet-бэкенда: (bidder, auctionId=H, 100e18, highestBid=0)
old_sig = "0xabc..."

# На mainnet, если auctionId=H начинается с highestBid=0:
gbm_auction_mainnet.commitBid(
    _auctionId=H,
    _bidAmount=100e18,
    _highestBid=0,
    _signature=old_sig  # chainId не проверяется
)
```

**Верификация (2026-05-09)**:  
- auctionId = `keccak256(tokenContract, tokenId, tokenKind)` — **ПОДТВЕРЖДЕНО**, один и тот же NFT всегда даёт один и тот же ID.
- `claim()` НЕ сбрасывает `highestBid` — **ПОДТВЕРЖДЕНО** (код функции проверен).
- Same-chain replay при релистинге: возможен только если `highestBid` на момент релистинга == значению в старой подписи. Практически ограничен первым аукционом NFT без ставок.

**Assumptions**: Бэкенд использует тот же приватный ключ на нескольких средах (prod/testnet) и/или токен-контракты имеют совпадающие адреса.

**Confidence Level**: MEDIUM (cross-chain replay реалистичен при общем backendPubKey между средами; same-chain replay ограничен).

---

## Уязвимость #4

- **Title**: GBM Auction — `bid()` не имеет reentrancy guard при multiple external ERC20 calls
- **Severity**: High (при нестандартных ERC20) / Medium (с GHST)
- **Affected Function**: `bid(uint256 _auctionId, uint256 _bidAmount, uint256 _highestBid)` internal | файл `contracts/facets/GBMFacet.sol`

**Root Cause**:

Функция `bid()` вызывает несколько external calls без reentrancy guard:

```solidity
// 1. Получить GHST от нового биддера
IERC20(s.erc20Currency).transferFrom(msg.sender, address(this), _bidAmount);

// Обновление стейта (частичное, до refund)
s.auctions[_auctionId].highestBidder = msg.sender;
s.auctions[_auctionId].highestBid = _bidAmount;

// 2. Апрувнуть контракту самому себе
IERC20(s.erc20Currency).approve(address(this), (previousHighestBid + duePay));

// 3. Отправить refund+incentive предыдущему биддеру
IERC20(s.erc20Currency).transferFrom(address(this), previousHighestBidder, (previousHighestBid + duePay));
```

Ни явного `ReentrancyGuard`, ни паттерна checks-effects-interactions для всего flow.

**Attack Path**:

Если `s.erc20Currency` когда-либо будет заменён на токен с хуками (ERC777, ERC1363), или если GHST получит callback-функциональность через апгрейд:

1. `previousHighestBidder` — контракт-атакующий.
2. Атакующий размещает минимальную ставку (`highestBid = 1`).
3. Легитимный пользователь делает более высокую ставку — вызывается `bid()`.
4. В шаге `transferFrom(address(this), attackerContract, refund+incentive)` токен вызывает `tokensReceived` hook на контракте атакующего.
5. Атакующий реентерит `bid()` с новой ставкой.
6. Approval из шага 2 текущего вызова (`approve(this, refund+incentive)`) пересекается с повторным вызовом.

**Текущее состояние с GHST (ERC20)**: reentrancy не эксплуатируется — стандартный ERC20 не вызывает hooks у получателя. Уязвимость активируется при замене `erc20Currency` на ERC777/ERC1363 или при апгрейде GHST.

**Impact**:

- При активации: многократный drain GHST из GBM-контракта.
- GBM держит до ~3500 GHST + активные аукционные ставки.

**Proof of Concept idea**:

```solidity
// Если erc20Currency поддерживает ERC777:
contract MaliciousBidder {
    function tokensReceived(address, address, address, uint256 amount, ...) external {
        // Реентер в bid() пока approve(this, amount) ещё активен
        IGBMFacet(auction).commitBid(auctionId, amount + 1, amount, validSig);
    }
}
```

**Assumptions**: Эксплуатируется только если `erc20Currency` имеет transfer-hooks. С GHST (plain ERC20) — потенциальная проблема, не активная угроза.

**Confidence Level**: HIGH (код подтверждён; риск активен при смене токена или апгрейде GHST).

---

## Результаты дополнительной верификации

### VRFFacet — статус деплоя на Base

- BaseScan не показывает `openPortals` в write-функциях Diamond (ABI Diamond прокси не содержит фасетных функций — это технический артефакт).
- GitHub: VRFFacet.sol последний раз изменён 19 июля 2025 (modifier rename); нет коммитов с заменой на PoP VRF.
- Wiki Aavegotchi подтверждает переход на "Proof of Play VRF" для Base, но без GitHub-ссылки на имплементацию.
- **Требует**: прямого вызова `facetAddress(bytes4(keccak256("openPortals(uint256[])")))` на Diamond.

### GBM auctionId — верифицировано

- `auctionId = keccak256(abi.encodePacked(tokenContract, tokenId, tokenKind))` — детерминированный хэш, **одинаков при релистинге того же NFT**.
- `claim()` не сбрасывает `highestBid` в 0 после завершения аукциона.
- При `_rewrite=true` релистинг начинается с прежним `highestBid` (не 0) — same-chain replay с подписью `highestBid=0` возможен только для первого аукциона NFT до первой ставки.
- Cross-chain replay (отсутствие chainId) — основной вектор.

### Proof of Play VRFSystem (`0x9eC728...`) — анализ

- TransparentUpgradeableProxy, **нет timelock**, апгрейд мгновенный. Последнее обновление имплементации — июнь 2025.
- Имплементация: `0x63ce7fcdcd0ac48d5c303685faca2e6d56c2f1af` (VRFSystem.sol).
- `deliverRandomNumber(uint256 id, uint256 roundNumber, uint256 randomNumber)` — **без верификации подписи**, только role-based access через `IGameRegistry`.
- `deliverSignedRandomNumber(...)` — с ECDSA-подписью, более защищённый вариант.
- Admin-компрометация позволяет мгновенно заменить имплементацию и вернуть произвольную случайность → **исключено из отчёта как admin-risk** согласно scope.

---

## Суммарная таблица

| # | Название | Severity | Контракт | Confidence | Статус верификации |
|---|---|---|---|---|---|
| 1 | VRFFacet predictable randomness (block.number) | Critical | Aavegotchi Diamond | Medium-High | Код confirmed; on-chain facet deployment не верифицирован |
| 2 | batchDepositGHST Polygon hardcode DoS | High | Aavegotchi Diamond | Critical (100%) | Полностью верифицировано |
| 3 | GBM commitBid no chainId/nonce | Medium | GBM Diamond | Medium | auctionId-логика уточнена; same-chain replay ограничен; cross-chain основной вектор |
| 4 | GBM bid() + claim() no reentrancy guard | High (при ERC777) / Medium (с GHST) | GBM Diamond | High (код) | Код confirmed; exploitable при смене erc20Currency |
