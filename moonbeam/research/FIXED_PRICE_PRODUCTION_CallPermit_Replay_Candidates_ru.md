# Fixed-price production candidates для stale CallPermit replay

Дата: 2026-05-12

Цель: найти real production-used контракты на Moonbeam / Moonriver / EVM ecosystems, где failed CallPermit replay сохраняет **исторически выгодную фиксированную цену**, а не просто исполняет swap по текущим AMM reserves.

CallPermit:

```text
0x000000000000000000000000000000000000080a
```

Базовый primitive уже доказан локальными fork PoC:

```text
failed / future-nonce CallPermit dispatch
-> public v/r/s + exact calldata
-> nonce unchanged
-> exact same calldata reusable later
-> nonce consumed only after successful replay
```

## Executive verdict

По строгому фильтру "production-used + fixed historical price + CallPermit-compatible" сильный прямой кандидат остается один:

```text
MoonBeans Marketplace V9
Moonbeam
0x683724817a7d526d6256Aec0D6f8ddF541b924de
acceptOffer(address,uint256,uint256,address,bool)
```

Это не ERC20 RFQ, а NFT marketplace settlement, но именно он лучше всего совпадает с требуемой моделью:

- цена фиксирована в calldata (`price`);
- execution later не пересчитывает fair/current market price;
- failed dispatch оставляет reusable authorization;
- buyer/seller могут контролировать временный revert;
- exact same calldata позже продает/покупает по stale fixed price;
- контракт реально использовался: Moonbeam DApp Directory показывает Moonbeans как NFT marketplace с `currentTx.moonbeam = 8409`, `currentUsers.moonbeam = 1134`, а Moonscan для Marketplace V9 показывает `8,493` tx.

Для ERC20 RFQ/limit-order settlement на Moonbeam/Moonriver найден технически подходящий, но **не production-used** кандидат:

```text
DODO LimitOrder / RFQ
Moonriver
0xbF50d94E286609c866De1308f8f5f1e4c50a2Fe6
fillLimitOrder / fillRFQByUser / matchingRFQByPlatform
```

Он имеет правильную fixed-price механику (`makerAmount / takerAmount`), но на Moonscan у адреса всего `3` transactions. Поэтому он rejected для основной цели.

Для крупных EVM fixed-order систем типа 1inch Limit Order, 0x RFQ/Limit, CoW Protocol, Seaport: это production-used fixed-price / signed-order infrastructure, но нет прямой CallPermit precompile среды. Без Moonbeam/Moonriver CallPermit это не является exploitable path именно в заявленной модели.

## Candidate 1: MoonBeans Marketplace V9

```text
PROJECT: MoonBeans
CHAIN: Moonbeam
CONTRACT: 0x683724817a7d526d6256Aec0D6f8ddF541b924de
FUNCTION: acceptOffer(address ca,uint256 tokenId,uint256 price,address from,bool escrowedBid)
TYPE: NFT marketplace fixed offer settlement
LIKELIHOOD: High
```

### REAL USAGE EVIDENCE

- Moonbeam DApp Directory: Moonbeans listed as an NFT marketplace.
- DApp Directory metrics:

```text
currentTx.moonbeam = 8409
currentUsers.moonbeam = 1134
```

- DApp Directory `web3goContracts` lists:

```text
Moonbeans: Marketplace V9
0x683724817a7d526d6256aec0d6f8ddf541b924de
```

- Moonscan tx count for Marketplace V9:

```text
8,493 transactions
```

- Latest sampled Marketplace V9 transactions:

```text
0xb8e2a556c8366ef22f049979480d66f767128ae0c19667f41b4996d0bf847606
block 11586684 / 2025-07-04T20:37:48Z

0xb21b89fcf1610cf976341a3dfc2041426d94e584e7fe9487d3aee442f139ffc4
block 11023267 / 2025-05-25T14:25:36Z
```

This is production-used historically and still has an active public site, but current marketplace activity is not high.

### HOW PRICE IS FIXED

The seller-signed CallPermit calldata fixes:

```text
ca
tokenId
price
from / buyer
escrowedBid
```

For `acceptOffer(...)`, `price` is an explicit calldata argument. The settlement does not recompute an NFT floor, oracle price, collection TWAP, AMM reserve price, or current fair value.

### WHAT IS SIGNED

The signed CallPermit message signs:

```text
from      = seller
to        = Marketplace V9
value     = 0
data      = abi.encodeCall(acceptOffer, (ca, tokenId, price, buyer, false))
gaslimit
nonce
deadline
```

The `data` field contains the fixed stale `price`.

### WHAT IS COMPUTED AT EXECUTION

Execution checks current marketplace/token state:

- offer exists and matches `price`, `buyer`, `escrowedBid`;
- buyer WGLMR balance/allowance is enough for `price`;
- seller owns the NFT;
- marketplace has ERC721 approval;
- collection is tradable;
- offer not already accepted.

But the economic price itself remains the signed `price`.

### CAN HISTORICAL PRICE SURVIVE

Yes.

This was already proven in the local Chopsticks fork PoCs:

- `REPORTS/MOONBEANS_V9_STALE_ACCEPT_OFFER_CallPermit_Fork_PoC_ru.md`
- `REPORTS/MOONBEANS_V9_SELLER_CONTROLLED_REVERT_CallPermit_PoC_ru.md`
- `REPORTS/MOONBEANS_V9_MASS_SELLER_CONTROLLED_CallPermit_PoC_ru.md`

The PoCs replayed exact same CallPermit calldata after failed/future-nonce publication and executed the stale fixed offer price later.

### CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION

Yes.

Observed fork behavior:

```text
dispatch validates permit
target call reverts inside acceptOffer / token transfer / ERC721 transfer path
CallPermit nonce stays unchanged
v/r/s and full dispatch calldata are public
exact same bytes replay later
nonce consumed only after successful replay
```

### POSSIBLE REVERT VECTOR

Buyer-controlled:

```text
buyer creates non-escrowed offer
buyer removes WGLMR allowance or moves WGLMR balance
seller-signed acceptOffer dispatch reverts
buyer restores allowance/balance
same calldata replays later
```

Seller-controlled:

```text
seller signs acceptOffer
seller revokes setApprovalForAll(marketplace, false)
seller calls failed dispatch and leaks v/r/s
seller restores approval
unrelated dispatcher replays same calldata
```

Future-nonce publication:

```text
nonce N+K permit is published early
dispatch fails as Invalid permit / future nonce
later nonce advances to N+K
exact same stale acceptOffer calldata becomes valid
```

### POTENTIAL STALE-PROFIT PATH

Seller-benefiting stale high sale:

```text
t0: buyer offers 100 WGLMR for NFT
t1: seller signs acceptOffer(..., price=100 WGLMR, buyer, false)
t2: dispatch intentionally fails, signature public, nonce unchanged
t3: floor falls; NFT is now worth 70 WGLMR
t4: seller restores approval/ownership
t5: any account replays exact same calldata
t6: seller receives historical 100 WGLMR, can buy back cheaper
```

Buyer-benefiting stale cheap buy:

```text
t0: buyer creates low/old offer accepted by seller authorization
t1: dispatch fails and leaks seller authorization
t2: floor rises above signed price
t3: buyer restores WGLMR allowance/balance
t4: replay buys NFT at stale cheap fixed price
```

### CAN USER SELL ABOVE CURRENT MARKET

Yes, if the signed `price` is above later market/floor and the offer remains live/fundable.

This is the closest match to the user's token example:

```text
sell asset later at old high fixed price
then buy back cheaper on current market
```

### CAN USER BUY BELOW CURRENT MARKET

Yes, in the mirror case where a seller-signed sale/acceptance remains reusable and market/floor rises after the failed dispatch.

### IS THIS BETTER THAN STELLASWAP

Yes for fixed historical price.

StellaSwap exactOutput computes the actual input from current pool state. MoonBeans `acceptOffer` executes a fixed signed price from calldata. The old price survives as an actual historical settlement term, not merely a slippage bound around current AMM execution.

### LIKELIHOOD

```text
High technically.
Medium-High economically for NFT collections with real floor movement and long CallPermit deadlines.
```

This is the strongest direct Moonbeam production-used stale fixed-price replay candidate found.

## Candidate 2: DODO LimitOrder / RFQ on Moonriver

```text
PROJECT: DODO
CHAIN: Moonriver
CONTRACT: 0xbF50d94E286609c866De1308f8f5f1e4c50a2Fe6
FUNCTIONS:
  fillLimitOrder(Order,bytes,uint256,uint256,bytes)
  fillRFQByUser(Order,bytes,uint256,uint256)
  matchingRFQByPlatform(Order,bytes,bytes,uint256,uint256,uint256,address)
TYPE: ERC20 signed order / RFQ settlement
LIKELIHOOD: Low because usage is too low
STATUS: Technically matches, rejected as production target
```

### REAL USAGE EVIDENCE

Positive:

- Official DODO docs list Moonriver deployment family and approve/proxy contracts.
- Moonscan has verified ABI for `DODOLimitOrder`.
- The contract exposes `LimitOrderFilled`, `RFQByUserFilled`, and `RFQByPlatformFilled` events.

Negative:

```text
Moonscan tx count for 0xbF50...2Fe6 = 3 transactions
```

Latest sampled tx hashes:

```text
0xf9d89af0dd752868392c9d34e4ea9ee8ce3bb7f3e7f3c62c6d3f4d6ccb89a295
0xf3c35412f353105be69932ece62b5866b3d88667496262848aed102c7c1e51fe
0xe5cdcb4354efc415c739f04ad9d40d2854c50b6242c7f47df7d30aebc527a795
```

This fails the user's "not dead / not empty / production-used" filter.

### HOW PRICE IS FIXED

The order struct fixes:

```text
makerToken
takerToken
makerAmount
takerAmount
makerTokenFeeAmount
maker
taker
expiration
saltOrSlot
```

The fixed quote is:

```text
makerAmount / takerAmount
```

Settlement computes proportional fill amounts from these signed order fields, not from an AMM reserve lookup.

### WHAT IS SIGNED

Two signature layers can exist:

1. Maker signs the DODO order.
2. Taker/user signs CallPermit to call `fillLimitOrder(...)` or `fillRFQByUser(...)`.

The CallPermit-signed calldata can contain:

```text
full Order tuple
maker signature
takerFillAmount
threshold amount
takerInteraction
```

### WHAT IS COMPUTED AT EXECUTION

Execution computes:

```text
curMakerFillAmount = curTakerFillAmount * order.makerAmount / order.takerAmount
```

It also checks:

- maker signature;
- expiration;
- filled amount;
- maker/taker balances and allowances;
- private taker constraint if `order.taker` is set;
- optional taker interaction.

It does not fetch current market price.

### CAN HISTORICAL PRICE SURVIVE

Yes technically.

If a CallPermit authorization to fill a still-valid DODO order is leaked by a failed dispatch, the exact same calldata preserves the original maker/taker ratio.

### CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION

Yes, by the CallPermit primitive, if the target call reverts after permit validation. Plausible revert vectors:

- taker temporarily has insufficient balance/allowance;
- maker temporarily has insufficient balance/allowance via DODOApproveProxy path;
- order is future nonce / future CallPermit nonce publication;
- optional `takerInteraction` reverts.

### POTENTIAL STALE-PROFIT PATH

Sell above current market:

```text
t0: maker order offers 100 USDC for 100 TOKEN
t1: taker signs CallPermit to fill the order
t2: dispatch fails due taker allowance/balance
t3: TOKEN market falls; 100 TOKEN now worth 70 USDC
t4: taker restores balance/allowance
t5: any account replays exact same calldata
t6: taker sells 100 TOKEN for historical 100 USDC
t7: taker buys back TOKEN cheaper
```

Buy below current market:

```text
t0: maker order sells 100 TOKEN for 70 USDC
t1: taker CallPermit fill leaks through failed dispatch
t2: TOKEN rallies
t3: replay buys 100 TOKEN for old 70 USDC
```

### CAN USER SELL ABOVE CURRENT MARKET

Yes, if the stale maker order remains live, unfilled, unexpired, and funded.

### CAN USER BUY BELOW CURRENT MARKET

Yes, same condition.

### IS THIS BETTER THAN STELLASWAP

Mechanically yes: DODO order price is fixed in signed order fields, unlike StellaSwap current-reserve execution.

Practically no for bounty/impact: the Moonriver deployment has only 3 transactions and should not be presented as a production-used exploitable target.

### LIKELIHOOD

```text
Technical: Medium-High
Production impact on Moonriver: Low / rejected
```

## Candidate 3: DPS Cartographer `buyVoyages`

```text
PROJECT: Damned Pirates Society
CHAIN: Moonbeam
CONTRACT: 0xD1A9bA3e61Ac676f58B29EA0a09Cf5D7f4f35138
FUNCTION: buyVoyages(uint16,uint256,address)
TYPE: game purchase / mutable config pricing
LIKELIHOOD FOR THIS REQUEST: Rejected as not fixed historical price
```

### REAL USAGE EVIDENCE

- Moonbeam official CallPermit gasless tutorial uses DPS Cartographer V1 and `buyVoyages(...)` as the concrete example target.
- Moonscan tx count for the Cartographer address:

```text
13,701 transactions
```

- Sample latest transaction:

```text
0x1215b87d13f28a6cc1aca1b48cf30fd5e610453f5e3c20537c46dc3ba0e5a161
block 11944924 / 2025-07-30T04:04:42Z
selector 0xdb76d5b3 = buyVoyages(uint16,uint256,address)
```

### WHY IT IS NOT THE REQUESTED CLASS

`buyVoyages(...)` does not preserve a historical fixed price in calldata.

The signed calldata fixes:

```text
voyageType
amount
voyage contract
```

But it does not fix:

```text
expected TMAP cost
maxPrice
historical tmapPerVoyage
```

The contract reads current `gameSettings.tmapPerVoyage(_voyageType)` at execution.

### CAN HISTORICAL PRICE SURVIVE

No.

The local fork PoC proved an economic replay, but in the opposite class:

```text
user signed when TMAP cost was 1
replay happened when current config cost was 10
execution burned 10
```

That is mutable current-price replay, not historical fixed-price replay.

### IS THIS BETTER THAN STELLASWAP

For changed-price replay, it is interesting because pricing is a mutable config variable rather than AMM reserves.

For this specific request, no: it does not preserve old favorable fixed price.

### LIKELIHOOD

```text
Rejected for fixed historical price.
Keep only as contrast / separate bug class.
```

## EVM production systems: fixed-price, but no direct CallPermit surface

These systems are relevant as design analogues, not as direct Moonbeam CallPermit targets.

### 1inch Limit Order Protocol

```text
PROJECT: 1inch Limit Order Protocol
CHAIN: Ethereum / BNB Chain / Polygon / Optimism / Arbitrum / Gnosis / Avalanche / Sonic / Unichain
TYPE: offchain signed limit orders
```

1inch docs state that limit orders execute at the specified price and list supported chains. Moonbeam/Moonriver are not in the supported-chain list in the checked docs.

Fixed-price relevance:

- signed order terms fix the price;
- maker funds are not escrowed;
- fill can fail if funds are moved;
- if an equivalent CallPermit existed on the same chain, a leaked taker-side fill authorization could act like a free delayed option.

Direct CallPermit relevance:

```text
No direct Moonbeam/Moonriver deployment found in this pass.
Not exploitable via Moonbeam CallPermit as-is.
```

### 0x Limit / RFQ

```text
PROJECT: 0x Protocol
TYPE: signed limit/RFQ order settlement
```

0x has the exact shape the user is looking for at the protocol-design level:

- fixed maker/taker amounts;
- maker/taker signed order data;
- fill functions;
- sender/taker constraints;
- failure on balance/allowance.

But no production Moonbeam/Moonriver Exchange Proxy / RFQ deployment with material usage was identified.

Direct CallPermit relevance:

```text
No direct target found.
```

### CoW Protocol

```text
PROJECT: CoW Protocol
TYPE: batch auction / signed intent settlement
```

CoW settlement can preserve limit prices and signed intent constraints, but execution is not a Moonbeam/Moonriver CallPermit target in this research pass.

Direct CallPermit relevance:

```text
No direct Moonbeam/Moonriver target found.
```

### Seaport / OpenSea-style fixed NFT orders

```text
PROJECT: Seaport-style NFT settlement
TYPE: signed fixed-price NFT orders
```

This class is conceptually close to MoonBeans:

- fixed consideration;
- signed order;
- optional private taker/zone constraints;
- failure on ownership/approval/balance;
- stale fixed price can survive until cancellation/expiry.

But without a Moonbeam/Moonriver deployment using CallPermit, it remains an analogy, not a direct exploit target.

## Rejected / non-findings

### Generic AMM exactInput/exactOutput

Rejected for this report.

Reason:

```text
execution price is recomputed from current reserves / current concentrated liquidity state
```

This may be a CallPermit replay issue, but it is not historical fixed-price settlement.

### DODO Moonriver as production target

Rejected for production impact.

Reason:

```text
only 3 Moonscan transactions on the LimitOrder/RFQ contract
```

Technically good, operationally too unused.

### DPS `buyVoyages`

Rejected for fixed historical price.

Reason:

```text
price is read from current mutable config, not fixed in signed calldata
```

### Large EVM RFQ/order systems

Rejected as direct CallPermit targets.

Reason:

```text
production-used, but not on Moonbeam/Moonriver CallPermit precompile environment
```

## Best target for a fork PoC

If the goal is a real fixed historical price exploit on Moonbeam today:

```text
MoonBeans Marketplace V9
acceptOffer(address,uint256,uint256,address,bool)
```

PoC status:

```text
already done
```

Relevant files:

```text
research/replay_moonbeans_acceptoffer_stale_chopsticks.js
research/replay_moonbeans_acceptoffer_stale_result.json
REPORTS/MOONBEANS_V9_STALE_ACCEPT_OFFER_CallPermit_Fork_PoC_ru.md

research/replay_moonbeans_seller_controlled_revert_chopsticks.js
research/replay_moonbeans_seller_controlled_revert_result.json
REPORTS/MOONBEANS_V9_SELLER_CONTROLLED_REVERT_CallPermit_PoC_ru.md

research/replay_moonbeans_mass_seller_controlled_chopsticks.js
research/replay_moonbeans_mass_seller_controlled_result.json
REPORTS/MOONBEANS_V9_MASS_SELLER_CONTROLLED_CallPermit_PoC_ru.md
```

If the goal is ERC20/RFQ specifically:

```text
No production-used Moonbeam/Moonriver ERC20 RFQ / limit-order settlement target found.
```

The closest technical candidate is DODO Moonriver, but its usage is too low for the requested scope.

## Sources

- Moonbeam CallPermit docs: https://docs.moonbeam.network/builders/ethereum/precompiles/ux/call-permit/
- Moonbeam gasless CallPermit tutorial using DPS `buyVoyages`: https://docs.moonbeam.network/cn/tutorials/eth-api/call-permit-gasless-txs/
- Moonbeam DApp Directory API docs: https://docs.moonbeam.network/learn/dapp-directory/
- Moonbeans DApp Directory API: https://apps.moonbeam.network/api/ds/v1/app-dir/projects/moonbeans
- Moonbeans website: https://moonbeans.io/
- MoonBeans Marketplace V9: https://moonbeam.moonscan.io/address/0x683724817a7d526d6256Aec0D6f8ddF541b924de
- DODO Moonriver docs: https://docs.dodoex.io/en/developer/contracts/dodo-v1-v2/contracts-address/moonriver
- DODO LimitOrder Moonriver: https://moonriver.moonscan.io/address/0xbF50d94E286609c866De1308f8f5f1e4c50a2Fe6
- 1inch Limit Order help center: https://help.1inch.io/en/articles/4656415-1inch-v4-limit-orders
- CoW settlement docs: https://cowswap.mintlify.app/cow-contracts/contracts/settlement
