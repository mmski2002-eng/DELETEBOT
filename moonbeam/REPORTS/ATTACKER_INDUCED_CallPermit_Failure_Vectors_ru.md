# Отчет: attacker-induced failure vectors для раскрытия reusable CallPermit signatures

**Дата:** 2026-05-12  
**Target:** CallPermit precompile `0x000000000000000000000000000000000000080a`  
**Сети:** Moonbeam, Moonriver  
**Цель поиска:** реальные способы намеренно создать временный revert window, чтобы failed `dispatch(...)` публично раскрыл `v/r/s`, а тот же authorization можно было replay'ить позже.

---

## 1. Главный вывод

Найдены практические векторы, но они различаются по силе:

1. **Strongest third-party vector:** MoonBeans Marketplace `acceptOffer(...)` с non-escrowed offers. Покупатель-атакующий может сам сделать offer temporarily unfulfillable через баланс/allowance, заставить seller-signed CallPermit fail, а позже восстановить состояние и replay'нуть покупку по stale price.
2. **Generic AMM vector:** StellaSwap/Beamswap/Solarbeam routers. Атакующий может front-run'ом ухудшить reserves так, чтобы signed swap упал на `INSUFFICIENT_OUTPUT_AMOUNT` или `EXCESSIVE_INPUT_AMOUNT`. Это очень практичный leak-вектор, но replay-profit зависит от того, кому идет output и как атакующий монетизирует delayed swap.
3. **Universal future-nonce vector:** если атакующий получил signed permit с будущим nonce, он может дешево опубликовать его до времени, получить failed `Invalid permit`, а позже replay'нуть, когда nonce станет current. Это не требует контроля над target contract.
4. **Admin/config vector:** DPS `buyVoyages(...)` и похожие mutable-price purchase flows. Временный fail возможен через pause/config/price, но third-party attacker обычно не может вызвать его без admin/owner роли. Сильнее как malicious relayer + future nonce + later config change.

---

## 2. Почему failed dispatch раскрывает reusable authorization

CallPermit `dispatch(...)` принимает в calldata:

```text
from, to, value, data, gaslimit, deadline, v, r, s
```

Если транзакция попадает on-chain и fails/reverts, все эти поля уже публичны. Для replay есть два разных случая:

- **Target-induced revert после успешной проверки permit:** подпись была валидна для текущего nonce, precompile дошел до target call, target reverted. Из-за rollback nonce не считается consumed, поэтому тот же `v/r/s` reusable до deadline.
- **Future nonce publication:** подпись еще не валидна, потому что nonce слишком ранний. Failed tx все равно публикует `v/r/s`; позже, когда nonce станет current, тот же calldata может стать valid.

Источник по CallPermit и permissionless dispatch:  
https://docs.moonbeam.network/builders/ethereum/precompiles/ux/call-permit/

---

## 3. Candidate A: MoonBeans Marketplace `acceptOffer` через buyer-induced balance/allowance failure

**Оценка:** Strong / practical  
**Network:** Moonbeam  
**Contract:** `0x683724817a7d526d6256Aec0D6f8ddF541b924de`  
**Source:** https://moonbeam.moonscan.io/address/0x683724817a7d526d6256Aec0D6f8ddF541b924de#code  
**Function:** `acceptOffer(address ca, uint256 tokenId, uint256 price, address from, bool escrowedBid)`

### Exact revert condition

В `acceptOffer(...)` для non-escrowed bid вызывается `tokenPurchase(...)`:

```solidity
require(_token.balanceOf(msg.sender) >= price, "Buyer does not have enough money to purchase.");
require(_token.allowance(newOwner, address(this)) >= price, "Marketplace not approved to spend buyer tokens.");
...
_token.transferFrom(newOwner, oldOwner, remainder);
```

Здесь есть важная особенность: `acceptOffer` исполняется от имени seller'а (`msg.sender` после CallPermit), но проверка allowance относится к `newOwner`, то есть buyer `from`.

### Can attacker induce revert cheaply?

Да, если attacker является buyer'ом из offer:

- выставить non-escrowed offer;
- получить seller-signed CallPermit на `acceptOffer(...)`;
- перед публикацией dispatch временно убрать allowance marketplace или вывести WMOVR/TOKEN balance;
- отправить `dispatch(...)`;
- target call ревертит на balance/allowance condition;
- `v/r/s` становится публичным, nonce не consumed.

Это дешево: revoke/approve или временный перевод средств.

### Can revert be temporary?

Да. Buyer потом возвращает баланс или allowance.

### Does failed tx publish reusable signature?

Да. Failed CallPermit tx содержит `v/r/s` и exact target calldata. Так как failure происходит внутри target после permit verification, nonce rollback делает подпись reusable до deadline.

### Can same calldata later succeed?

Да, если:

- NFT все еще у seller'а;
- seller не отменил approval marketplace;
- offer все еще matching по `price`, `buyer`, `escrowed == false`, `accepted == false`;
- buyer восстановил balance/allowance;
- deadline CallPermit не истек.

### Replay profitability

Для attacker-buyer это сильный stale-price сценарий:

1. Seller подписывает acceptance по текущей цене, например 100 GLMR/WMOVR.
2. Buyer-атакующий делает allowance/balance temporarily insufficient.
3. Failed dispatch раскрывает подпись.
4. NFT дорожает до 150 GLMR.
5. Buyer восстанавливает allowance/balance и replay'ит старый `acceptOffer`.
6. Buyer получает NFT за stale 100 вместо текущей цены.

### Replay dispatcher restrictions

CallPermit `dispatch` permissionless. Replay может отправить сам attacker-buyer или любой другой аккаунт, но экономический beneficiary в этом сценарии - buyer `from`.

### Realistic attack flow

1. Buyer делает non-escrowed offer на NFT.
2. Seller подписывает CallPermit `acceptOffer(collection, tokenId, price, buyer, false)`.
3. Buyer/relayer front-runs или сам публикует dispatch после revoke allowance.
4. Dispatch fails, signature public.
5. Buyer ждет favorable market movement.
6. Buyer restores allowance.
7. Buyer replay'ит тот же dispatch и покупает NFT по stale price.

### Fork PoC feasibility

**High.**

Нужны только:

- seller-owned NFT;
- non-escrowed offer от buyer;
- buyer allowance initially removed for failure;
- exact same dispatch replay after allowance restored.

### Severity

**High для NFT stale-price сценария, если deadline длинный и seller не может быстро отозвать риск.**  
Ограничения: seller может снять marketplace approval или перевести NFT; offer может быть отменен; требуется, чтобы attacker был buyer/offer-side.

---

## 4. Candidate B: MoonBeans Marketplace V3 на Moonriver

**Оценка:** Strong / practical  
**Network:** Moonriver  
**Contract:** `0x16d7Edd3A562BB60aA0B3Af357A2c195cE2AA974`  
**Source:** https://moonriver.moonscan.io/address/0x16d7Edd3A562BB60aA0B3Af357A2c195cE2AA974#code  
**Function:** `acceptOffer(address ca, uint256 tokenId, uint256 price, address from, bool escrowedBid)`

Moonriver V3 имеет тот же паттерн marketplace offer acceptance.

### Exact revert condition

Для non-escrowed bid:

- buyer balance insufficient;
- buyer allowance insufficient;
- NFT approval missing;
- trading paused / collection disabled;
- matching offer not found.

Самый attacker-induced путь - buyer balance/allowance.

### Can attacker induce revert cheaply?

Да, если attacker является buyer'ом в offer. Он контролирует собственный WMOVR/TOKEN allowance и balance.

### Can same calldata later succeed?

Да, после восстановления allowance/balance, если seller/NFT/offer state все еще валидны.

### Replay profitability

Аналог Moonbeam V9: покупка NFT по stale price после роста рынка.

### Fork PoC feasibility

**High.** Логика PoC идентична Moonbeam V9.

### Severity

**Medium-High.** Ниже, если marketplace activity/liquidity на Moonriver ниже, но технический паттерн тот же.

---

## 5. Candidate C: AMM V2 routers - reserve manipulation causes slippage revert

**Оценка:** Practical leak vector / conditional profit  
**Networks:** Moonbeam, Moonriver  
**Contracts:**

- Beamswap Router V1, Moonbeam: `0x96b244391D98B62D19aE89b1A4dCcf0fc56970C7`  
  Source: https://moonbeam.moonscan.io/address/0x96b244391D98B62D19aE89b1A4dCcf0fc56970C7#code
- StellaSwap Router V1, Moonbeam: `0xd0A01ec574D1fC6652eDF79cb2F880fd47D34Ab1`  
  Source: https://moonbeam.moonscan.io/address/0xd0A01ec574D1fC6652eDF79cb2F880fd47D34Ab1#code
- Solarbeam Solar Router, Moonriver: `0xAA30eF758139ae4a7f798112902Bf6d65612045f`  
  Source: https://moonriver.moonscan.io/address/0xAA30eF758139ae4a7f798112902Bf6d65612045f#code

### Exact functions

V2-style:

```solidity
swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] path, address to, uint deadline)
swapTokensForExactTokens(uint amountOut, uint amountInMax, address[] path, address to, uint deadline)
swapExactETHForTokens(uint amountOutMin, address[] path, address to, uint deadline)
swapTokensForExactETH(uint amountOut, uint amountInMax, address[] path, address to, uint deadline)
```

### Exact revert condition

Beamswap/StellaSwap V2 pattern:

```solidity
amounts = getAmountsOut(factory, amountIn, path);
require(amounts[amounts.length - 1] >= amountOutMin, "... INSUFFICIENT_OUTPUT_AMOUNT");

amounts = getAmountsIn(factory, amountOut, path);
require(amounts[0] <= amountInMax, "... EXCESSIVE_INPUT_AMOUNT");
```

Solarbeam Moonriver has the same class. A real Moonriver failed tx exists with:

```text
SolarRouter: INSUFFICIENT_OUTPUT_AMOUNT
```

Example:  
https://moonriver.moonscan.io/tx/0x22e8d369dc13b07fc39e3ac5e61d2218ccba51d4f5f0e36dbcb4207c05c5962a

This example is not CallPermit, but it proves the exact router failure mode is live on Moonriver.

### Can attacker induce revert cheaply?

Да, если victim/relayer transaction is visible in mempool:

- для `swapExact...`: attacker front-runs a swap in the same pool/path to reduce expected output below `amountOutMin`;
- для `swap...ForExact`: attacker moves reserves so required input becomes greater than `amountInMax`;
- attacker can often back-run to restore position, paying only price impact, fees and gas.

Cheaper on thin-liquidity pairs; expensive on deep pools.

### Can revert be temporary?

Да. AMM reserves are mutable every block. Attacker can manipulate reserves for one block or one bundle, then unwind.

### Does failed tx publish reusable signature?

Да, если victim action is wrapped in CallPermit and the router revert happens after permit verification. The failed `dispatch` exposes:

- `from`;
- router `to`;
- swap calldata;
- `deadline`;
- `v/r/s`.

Nonce remains reusable because the target call reverted.

### Can same calldata later succeed?

Да, if before the signed router deadline:

- reserves move back so `amountOutMin`/`amountInMax` passes;
- victim still has token balance and allowance for the router/precompile flow;
- CallPermit deadline still valid.

### Replay profitability

Profit is conditional and less direct than MoonBeans:

- If output recipient `to` is attacker or attacker-controlled contract, direct profit can be high.
- If `to` is victim, attacker profits only through MEV around the delayed forced swap: pre-positioning, back-running, arbitrage, or causing victim to sell/buy at a stale time.
- Standard slippage bounds prevent "execute at worse than signed minOut/maxIn"; the profit comes from timing optionality and leaked authorization, not from bypassing slippage.

### Replay dispatcher restrictions

CallPermit replay is permissionless. Router itself generally has no relayer binding.

### Realistic attack flow

1. Victim signs CallPermit for router swap with long enough CallPermit deadline.
2. Relayer broadcasts `dispatch(...)`.
3. Attacker sees signed calldata in mempool.
4. Attacker front-runs reserve movement so router fails slippage check.
5. Victim dispatch fails and publishes `v/r/s`.
6. Attacker waits until market/reserves make the same swap strategically useful.
7. Attacker replay'ит exact same dispatch and monetizes with back-run/arbitrage.

### Fork PoC feasibility

**High for leak/replay mechanics. Medium for profit proof.**

На fork легко показать:

- front-run reserve manipulation;
- CallPermit dispatch revert;
- same calldata replay succeeds after reserves restored.

Profit proof requires pair-specific liquidity and an MEV strategy.

### Severity

**Medium.**  
Can be **High** only if signed swap sends assets to attacker-controlled recipient, uses unsafe bounds, or the delayed swap itself has clear extractable value.

---

## 6. Candidate D: StellaSwap Router V3 / Algebra-style exactInput/exactOutput

**Оценка:** Practical leak vector / conditional profit  
**Network:** Moonbeam  
**Contract:** `0xe6d0ED3759709b743707DcfeCAe39BC180C981fe`  
**Source:** https://moonbeam.moonscan.io/address/0xe6d0ED3759709b743707DcfeCAe39BC180C981fe#code

### Exact functions

```solidity
exactInput(ExactInputParams params)
exactInputSingle(ExactInputSingleParams params)
exactOutput(ExactOutputParams params)
exactOutputSingle(ExactOutputSingleParams params)
```

Relevant fixed calldata fields:

- `amountIn`;
- `amountOutMinimum`;
- `amountOut`;
- `amountInMaximum`;
- `path`;
- `recipient`;
- `deadline`.

### Exact revert condition

The router enforces exact-input minimum output and exact-output maximum input semantics. The verified ABI/source exposes:

- `amountOutMinimum` in `exactInput` / `exactInputSingle`;
- `amountInMaximum` in `exactOutput` / `exactOutputSingle`.

An attacker can move pool price/ticks so:

- exact-input output falls below `amountOutMinimum`;
- exact-output required input exceeds `amountInMaximum`;
- price limit is hit.

### Can attacker induce revert cheaply?

Да, on low-liquidity pools or narrow liquidity ranges. On deep concentrated pools it may be expensive.

### Can revert be temporary?

Да. Pool price can be moved for a single block and restored.

### Replay profitability

Same as V2 routers: strongest as leak + timing option, not guaranteed direct theft.

### Fork PoC feasibility

**Medium-High.** Need choose a live pool with manipulable liquidity and signed CallPermit swap.

### Severity

**Medium**, pair-dependent.

---

## 7. Candidate E: Universal future-nonce publication

**Оценка:** Strong generic leak vector if attacker receives signature  
**Target:** any CallPermit action  
**Requirement:** attacker has the signed permit before it is valid/current.

### Exact revert condition

CallPermit rejects the permit because signed nonce is not current yet. In prior fork testing this appears as an invalid permit failure.

### Can attacker induce revert cheaply?

Да, if attacker is:

- malicious relayer;
- compromised frontend/backend;
- RFQ/orderflow receiver;
- counterparty who receives a signed future-nonce authorization.

They simply submit `dispatch(...)` too early.

### Can revert be temporary?

Да. The same signature becomes valid when earlier nonces are consumed.

### Does failed tx publish reusable signature?

Да. The failed tx publishes the full future-nonce authorization.

### Can same calldata later succeed?

Да, once nonce advances to the signed nonce and deadline remains valid.

### Replay profitability

Depends entirely on target action. This vector is especially dangerous when combined with:

- MoonBeans `acceptOffer` stale-price purchases;
- DPS `buyVoyages` mutable price/config;
- approvals;
- swaps with attacker-controlled recipient;
- mints/purchases where price/inventory changes later.

### Replay dispatcher restrictions

None at CallPermit level. Any account can send the later replay.

### Fork PoC feasibility

**Already high / proven locally for DPS-style flow.**  
Existing project evidence: `research/DPS_buyVoyages_CallPermit_Economic_Replay_PoC_ru.md`.

### Severity

**High as a generic primitive**, because it avoids the need to manipulate target state. Impact depends on target calldata.

---

## 8. Candidate F: DPS `Cartographer V1.buyVoyages` via mutable pause/config/price

**Оценка:** Strong economic replay, but attacker-induced failure usually requires admin or future-nonce vector  
**Network:** Moonbeam  
**Contract:** `0xD1A9bA3e61Ac676f58B29EA0a09Cf5D7f4f35138`  
**Source:** https://moonbeam.moonscan.io/address/0xD1A9bA3e61Ac676f58B29EA0a09Cf5D7f4f35138#code  
**Function:** `buyVoyages(uint16 _voyageType, uint256 _amount, DPSVoyageIV2 _voyage)`

### Exact revert conditions

Source-visible checks:

```solidity
if (nonReentrant == 2 || !voyages[_voyage]) revert Unauthorized();
if (gameSettings.isPaused(2) == 1) revert Paused();
uint256 amountOfTmap = gameSettings.tmapPerVoyage(_voyageType);
if (amountOfTmap == 0) revert WrongParams(1);
if (tmap.balanceOf(msg.sender) < amountOfTmap * _amount) revert NotEnoughTokens();
```

### Can attacker induce revert cheaply?

For a normal third-party attacker: usually **no**.

They cannot cheaply:

- pause the game;
- change `tmapPerVoyage`;
- delist voyage contract;
- reduce victim's TMAP balance.

But it is practical if attacker is:

- admin/owner;
- malicious relayer using future nonce;
- an external party who can submit the permit during a known pause/config window.

### Can revert be temporary?

Да:

- pause can be toggled;
- voyage allowlist can change;
- `tmapPerVoyage` can change;
- user balance can later become sufficient.

### Does failed tx publish reusable signature?

Да, for target-induced revert after permit verification or future-nonce publication.

### Can same calldata later succeed?

Да. Existing fork PoC already showed exact same CallPermit calldata replaying successfully after nonce became current and `tmapPerVoyage` changed.

### Replay profitability

Two forms:

- If cost rises after signing, replay can burn more TMAP than victim expected.
- If voyage config/reward assumptions change, replay can force stale purchase/mint under changed economics.

### Fork PoC feasibility

**High.** Existing local report and result:

- `research/DPS_buyVoyages_CallPermit_Economic_Replay_PoC_ru.md`
- `research/replay_dps_buyvoyages_economic_result.json`

### Severity

**Medium-High / High if admin or relayer can combine future-nonce leak with later price/config change.**  
Lower for pure third-party attacker because direct induction of the temporary revert is not generally available.

---

## 9. Approvals vector

**Оценка:** Weak as attacker-induced failure, strong as impact if leaked by other vector.

### Functions

```solidity
approve(address spender, uint256 amount)
setApprovalForAll(address operator, bool approved)
```

### Can attacker induce revert cheaply?

Usually **no**.

ERC-20 `approve` and ERC-721 `setApprovalForAll` typically do not depend on attacker-controlled pool/config state. They may fail because:

- token is paused;
- token has non-standard allowance rules;
- caller is blocked/blacklisted;
- operator restrictions exist.

But those are token-admin or token-policy conditions, not cheap third-party manipulation.

### Replay profitability

If a failed/future-nonce CallPermit leaks `approve(max)` or `setApprovalForAll`, replay impact can be severe. But the attacker-induced failure source is usually not the approval itself; it is more likely:

- future nonce;
- wrapper target revert;
- admin-controlled temporary block.

### Severity

**High impact, low standalone attacker-induced feasibility.**

---

## 10. Rejected / weak vectors

### Pure accidental swap failure

Rejected unless attacker can predictably move reserves or price before the dispatch.

### User overpays later

Rejected for this report. The target is attacker-created fail window plus stale profitable replay, not merely worse execution for the user.

### `fulfillListing(address,uint256)` on MoonBeans

Weak. The signed calldata does not include price; current listing price is read from storage, and native `msg.value` is fixed in CallPermit. Seller cannot force arbitrary higher payment beyond signed `value`.

### Escrowed MoonBeans offers

Weaker for attacker-induced fail. If funds are escrowed, buyer has less ability to cheaply make the accept fail without canceling/removing the offer itself.

---

## 11. Ranking

| Rank | Candidate | Attacker-induced fail | Later success | Profit clarity | Severity |
|---:|---|---|---|---|---|
| 1 | MoonBeans non-escrowed `acceptOffer` | Strong: buyer balance/allowance | Strong | Strong: stale cheap NFT buy | High |
| 2 | Future-nonce publication | Strong if attacker has signature | Strong after nonce advances | Target-dependent | High primitive |
| 3 | AMM V2 routers | Strong via reserve manipulation | Strong if reserves recover | Conditional MEV | Medium |
| 4 | StellaSwap V3 router | Strong on manipulable pools | Strong if price recovers | Conditional MEV | Medium |
| 5 | DPS `buyVoyages` | Weak for third-party, strong for admin/future-nonce | Strong | Strong economic replay | Medium-High |
| 6 | Approvals | Weak standalone | Strong if leaked | Potentially high | Medium |

---

## 12. Best next fork PoCs

### PoC 1: MoonBeans buyer-induced stale purchase

1. Fork Moonbeam.
2. Buyer creates non-escrowed offer and initially has allowance.
3. Seller signs CallPermit `acceptOffer(..., buyer, false)`.
4. Buyer removes allowance or token balance.
5. Attacker submits dispatch; target reverts on allowance/balance.
6. Confirm CallPermit nonce remains reusable.
7. Buyer restores allowance/balance.
8. Replay exact same dispatch.
9. Assert NFT transferred to buyer at stale fixed price.

### PoC 2: Beamswap/StellaSwap reserve manipulation leak

1. Fork Moonbeam.
2. Victim signs CallPermit for `swapExactTokensForTokens` with realistic `amountOutMin`.
3. Attacker front-runs swap on same pair to move reserves.
4. Victim dispatch fails on `INSUFFICIENT_OUTPUT_AMOUNT`.
5. Attacker unwinds reserves.
6. Replay exact same dispatch succeeds.
7. Optional: add back-run to demonstrate MEV profit.

### PoC 3: Future nonce generic leak

1. Victim signs any profitable future-nonce CallPermit action.
2. Attacker submits before nonce is current.
3. Failed tx publishes `v/r/s`.
4. Advance nonce with earlier authorization.
5. Replay exact same calldata from unrelated account.

---

## 13. Final verdict

Да: на Moonbeam/Moonriver есть реальные practical ways создать temporary revert window, который раскрывает reusable CallPermit authorization.

Самый сильный найденный third-party сценарий - **MoonBeans non-escrowed `acceptOffer`**, потому что атакующий-buyer контролирует именно то состояние, которое заставляет seller-signed acceptance revert: свой token balance/allowance. После восстановления состояния тот же calldata может купить NFT по stale price.

AMM reserve manipulation - самый универсальный DeFi leak-вектор. Он хорошо отвечает на вопрос "can attacker intentionally make victim swap fail?", но profit после replay нужно доказывать pair-specific MEV моделью.

Future nonce publication - самый сильный общий primitive, если attacker получает подпись до валидности nonce: он вообще не зависит от target revert и может быть совмещен с любым profitable/stale authorization.
