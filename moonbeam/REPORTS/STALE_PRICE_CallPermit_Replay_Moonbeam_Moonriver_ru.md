# Отчет: CallPermit replay как отложенное исполнение stale favorable order

**Дата:** 2026-05-12  
**Компонент:** CallPermit precompile `0x000000000000000000000000000000000000080a`  
**Сети:** Moonbeam, Moonriver  
**Фокус:** не griefing и не "user overpays later", а сценарии, где старая публичная подпись позволяет позже исполнить выгодные для подписанта условия: stale price, stale offer, stale order.

---

## 1. Краткий вывод

Найден реальный и проверяемый класс кандидатов: MoonBeans marketplace на Moonbeam и Moonriver.

Самый сильный путь эксплуатации - `acceptOffer(...)`:

1. Владелец NFT подписывает через CallPermit принятие оффера по фиксированной цене.
2. Первая CallPermit-транзакция намеренно падает: future nonce, paused trading, disabled collection, снятый NFT approval или другое временное условие.
3. `v/r/s` и calldata становятся публичными.
4. Nonce позже становится current или временное условие исчезает.
5. Рынок NFT падает, старый оффер становится stale-high/favorable для продавца.
6. Тот же `dispatch(...)` replay'ится.
7. NFT продается по старой выгодной цене, если оффер еще активен и покупатель не отменил его.

Это не theft-by-relayer в чистом виде: выручка идет продавцу/подписанту по логике marketplace. Но это подходит под целевой паттерн "attacker/user intentionally keeps old favorable authorization alive and executes later when market moved favorably".

---

## 2. Корневая механика CallPermit

Документация Moonbeam по CallPermit:

- `dispatch(...)` может быть вызван не только подписантом, а любым аккаунтом/relayer'ом.
- Вызов исполняется от имени recovered signer.
- Nonce используется для replay protection.

Критичная предпосылка для этого отчета: при failed/reverted CallPermit dispatch nonce не становится окончательно consumed. Поэтому публичная подпись из failed tx остается reusable, пока:

- deadline не истек;
- nonce стал актуальным;
- целевой calldata больше не ревертит;
- целевой контракт все еще принимает старые параметры.

Источник:  
https://docs.moonbeam.network/builders/ethereum/precompiles/ux/call-permit/

---

## 3. Candidate A: MoonBeans Marketplace V9 на Moonbeam

**Contract:** `0x683724817a7d526d6256Aec0D6f8ddF541b924de`  
**Network:** Moonbeam  
**Source:** https://moonbeam.moonscan.io/address/0x683724817a7d526d6256Aec0D6f8ddF541b924de#code  
**Contract name:** `MarketPlace`

### Уязвимая функция

```solidity
function acceptOffer(
    address ca,
    uint256 tokenId,
    uint256 price,
    address from,
    bool escrowedBid
) external nonReentrant
```

### Что фиксируется в signed calldata

- `ca` - NFT collection.
- `tokenId` - конкретный NFT.
- `price` - фиксированная цена оффера.
- `from` - buyer, чей оффер принимается.
- `escrowedBid` - escrowed/non-escrowed режим оффера.

### Что может измениться позже

- floor price / market value NFT;
- текущая привлекательность старого оффера;
- approval владельца NFT на marketplace;
- `tradingPaused`;
- `collectionTradingEnabled[ca]`;
- CallPermit nonce, если изначально подпись была на future nonce;
- баланс/allowance buyer'а для non-escrowed offer;
- наличие escrowed funds для escrowed offer.

### Почему replay может стать прибыльным

Marketplace ищет matching offer по фиксированным полям:

- `_offers[i].price == price`;
- `_offers[i].buyer == from`;
- `_offers[i].accepted == false`;
- `_offers[i].escrowed == escrowedBid`.

В функции нет expiry для оффера и нет проверки "цена должна соответствовать текущему рынку". Если покупатель оставил старый высокий оффер активным, продавец может исполнить ранее подписанный `acceptOffer` позже, когда цена NFT уже упала.

Это именно stale favorable execution:

- старый `price` выгоден продавцу;
- calldata не пересчитывает цену;
- failed CallPermit не уничтожает authorization;
- later replay исполняет старые экономические условия.

### Как намеренно опубликовать failed tx

Реалистичные варианты:

- **Future nonce:** подписать permit с nonce `n+1`, публично отправить `dispatch` до потребления nonce `n`; tx падает, подпись опубликована.
- **Approval gating:** продавец временно снимает `setApprovalForAll`, поэтому `acceptOffer` ревертит на `Marketplace not approved`.
- **Paused/collection disabled:** если состояние marketplace/collection временно не позволяет торговать.
- **Transient balance/allowance issue:** для non-escrowed offer исполнение может зависеть от состояния средств/allowance buyer'а.

### Может ли unrelated account replay'ить позже

Да. `dispatch(...)` у CallPermit permissionless. Любой аккаунт, увидевший `v/r/s` и calldata в failed tx, может повторить тот же вызов после того, как nonce/условия стали валидными.

Практически прибыль получает продавец/подписант, потому что именно он является `msg.sender` внутри marketplace и получает оплату за NFT. У unrelated relayer'а прямая on-chain прибыль появляется только при внешней договоренности, bundle/MEV-стратегии или если он сам контролирует подписанта.

### Реалистичный profit path

1. У NFT есть оффер 100 GLMR.
2. Продавец подписывает `acceptOffer(collection, tokenId, 100 GLMR, buyer, escrowedBid)`.
3. CallPermit tx падает и публикует подпись.
4. Через время floor падает до 60 GLMR, но buyer не отменил оффер.
5. Старый `dispatch` replay'ится.
6. Продавец получает 100 GLMR вместо актуальной рыночной цены.

### Оценка severity

**Medium / Medium-High.**

Факторы вверх:

- фиксированная цена в calldata;
- нет expiry у marketplace-level offer;
- failed CallPermit оставляет подпись живой;
- permissionless replay.

Факторы вниз:

- buyer может отменить оффер;
- прибыль чаще идет подписанту, а не произвольному relayer'у;
- требуется активный старый offer и неистекший CallPermit deadline.

### Fork PoC feasibility

**High.**

PoC можно построить на fork Moonbeam:

1. Создать или найти активный offer.
2. Подписать CallPermit `dispatch` на `acceptOffer`.
3. Отправить failing dispatch через future nonce или снятый approval.
4. Восстановить approval / сделать nonce current.
5. Replay'нуть тот же calldata.
6. Проверить, что NFT перешел buyer'у, а seller получил старую цену.

---

## 4. Candidate B: MoonBeans Marketplace V3 на Moonriver

**Contract:** `0x16d7Edd3A562BB60aA0B3Af357A2c195cE2AA974`  
**Network:** Moonriver  
**Source:** https://moonriver.moonscan.io/address/0x16d7Edd3A562BB60aA0B3Af357A2c195cE2AA974#code  
**Contract name:** `MarketPlace`

### Уязвимая функция

```solidity
function acceptOffer(
    address ca,
    uint256 tokenId,
    uint256 price,
    address from,
    bool escrowedBid
) external nonReentrant
```

### Почему это тот же класс риска

Moonriver V3 использует тот же экономический паттерн:

- seller принимает оффер;
- `price` фиксирован в calldata;
- matching offer ищется в mutable storage;
- offer accepted only after successful execution;
- failed CallPermit не инвалидирует подпись;
- повторный `dispatch` может быть вызван позже любым аккаунтом.

### Profit path

1. Buyer держит старый высокий оффер на NFT.
2. Seller подписывает `acceptOffer` через CallPermit.
3. Первый dispatch намеренно падает и публикует подпись.
4. Рынок NFT падает.
5. Если offer не отменен, replay исполняет продажу по старой высокой цене.

### Оценка severity

**Medium.**

Риск экономически реалистичен, особенно для escrowed bids, потому что средства уже лежат в marketplace. Для non-escrowed bids нужна актуальная платежеспособность/allowance buyer'а.

### Fork PoC feasibility

**High.**

Fork PoC аналогичен Moonbeam V9, но на Moonriver RPC/fork.

---

## 5. Borderline: swap/router/order flows

Был найден класс контрактов с `executeOrder(...)`/router-like behavior, например Beefy Zap Router на Moonbeam:

**Contract:** `0xEC6eEDbe6B006E1cFA2e22Cb46a132888bFc62D8`  
**Source:** https://moonbeam.moonscan.io/address/0xEC6eEDbe6B006E1cFA2e22Cb46a132888bFc62D8#code

Этот кандидат слабее для целевой идеи.

Причина: calldata чаще фиксирует minOut/slippage/order constraints, но не гарантирует старую исполняемую цену. При replay результат все равно зависит от текущей ликвидности и текущего route execution. Это может быть важно для generic replay, но не является чистым "buy at stale cheap price" без дополнительного downstream контракта, который сам хранит stale fixed terms.

Итог: держать как secondary surface, но не считать основным stale-price finding без отдельного PoC.

---

## 6. Что было отсеяно

Следующие варианты не считаются сильными кандидатами под этот отчет:

- обычный `fulfillListing(address ca, uint256 tokenId)`, где цена берется из текущего listing storage, а не фиксируется в signed calldata;
- AMM swap с `minOut`, если later replay просто исполняется по текущему pool price и не дает старую гарантированную цену;
- сценарии, где пользователь просто платит больше позже;
- calldata, которое навсегда остается failing;
- контракты, где order nonce/order hash инвалидируется независимо от успешности внешнего CallPermit;
- flows, где deadline всегда короткий и не оставляет реалистичного окна replay.

---

## 7. Минимальные условия для подтверждения бага

Для полноценного подтверждения нужны одновременно:

1. Подпись CallPermit с достаточно длинным deadline.
2. Первый `dispatch` должен revert'нуть до успешного marketplace state transition.
3. Nonce CallPermit должен остаться reusable или future nonce должен позже стать current.
4. Matching offer должен остаться активным.
5. Buyer должен не отменить offer и иметь средства/escrow/allowance.
6. Market price должен измениться так, чтобы старый `price` стал выгодным для подписанта.
7. Replay того же calldata должен успешно исполнить `acceptOffer`.

---

## 8. Рекомендуемый следующий PoC

Лучший PoC target:

**MoonBeans Marketplace V9 на Moonbeam**  
`0x683724817a7d526d6256Aec0D6f8ddF541b924de`  
Function: `acceptOffer(address,uint256,uint256,address,bool)`

План:

1. Fork Moonbeam на блоке с активным/создаваемым offer.
2. Подготовить seller-owned NFT и buyer offer.
3. Seller подписывает CallPermit на `acceptOffer`.
4. Опубликовать failing dispatch:
   - либо future nonce;
   - либо temporarily removed marketplace approval.
5. Сделать условия валидными.
6. Replay'нуть тот же `dispatch` byte-for-byte.
7. Assert:
   - NFT перешел buyer'у;
   - seller получил fixed stale `price`;
   - та же подпись была использована после failed tx.

---

## 9. Итоговая оценка

MoonBeans `acceptOffer(...)` - лучший найденный реальный кандидат под требуемую exploit-идею:

- signed calldata фиксирует выгодную цену;
- экономическое состояние может измениться позже;
- failed CallPermit публикует reusable подпись;
- replay permissionless;
- контракт не имеет expiry/market freshness check на уровне `acceptOffer`;
- profit path реалистичен для stale-high NFT offers.

Основное ограничение: это скорее delayed self-benefiting authorization, чем прямое присвоение средств сторонним relayer'ом. Тем не менее для цели "reusable profitable delayed order after failed/future-nonce CallPermit" кандидат подходит.
