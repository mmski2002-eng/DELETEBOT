# Moonbeam/Moonriver CallPermit: economic-loss replay candidates

Date: 2026-05-12

Scope:

- CallPermit precompile: `0x000000000000000000000000000000000000080a`
- Focus: failed/reverted `dispatch(...)` publishes `v/r/s`; nonce not consumed or future nonce later becomes current; same calldata can be replayed by unrelated account before deadline.
- Economic-loss criterion: signed calldata fixes the action, but not the safe economic condition (`maxPrice`, `minOut`, `expectedAmount`, current fee/rate/config).

## A. Strongest Candidates

### 1. DPS `Cartographer V1.buyVoyages(...)` - strongest changed-price/state contract candidate

Contract:

- Moonbeam: `0xD1A9bA3e61Ac676f58B29EA0a09Cf5D7f4f35138`
- Moonscan label/source: `Damned Pirates Society: Cartographer V1`
- Official Moonbeam CallPermit tutorial uses this exact contract/action as the gasless example.

Function:

```solidity
function buyVoyages(
    uint16 _voyageType,
    uint256 _amount,
    DPSVoyageIV2 _voyage
) external
```

Source behavior:

```solidity
uint256 amountOfTmap = gameSettings.tmapPerVoyage(_voyageType);
if (amountOfTmap == 0) revert WrongParams(1);
if (tmap.balanceOf(msg.sender) < amountOfTmap * _amount) revert NotEnoughTokens();
...
tmap.burn(msg.sender, amountOfTmap);
_voyage.mint(msg.sender, voyageId, voyageConfig);
```

Current linked contracts:

- `tmap()`: `0x0e67601818237834fF8A280312a6F4F4934e6283`
- `gameSettings()`: `0xC7c536d85D40360E1b93fE06Ab06e5427AE4cED4`
- Current `tmapPerVoyage`: type `0 = 1e18`, `1 = 2e18`, `2 = 3e18`, `3 = 4e18`

Mutable economic state:

```solidity
function setTmapPerVoyage(uint256 _type, uint256 _amount) external onlyOwner {
    tmapPerVoyage[_type] = _amount;
}

function setVoyageConfigPerType(uint256 _type, CartographerConfig calldata _config) external onlyOwner { ... }
```

Why replay-dangerous:

- CallPermit signs `_voyageType`, `_amount`, `_voyage`, but not `maxTmapCost`, `expectedPrice`, `expectedConfig`, or a relayer.
- `buyVoyages` reads `gameSettings.tmapPerVoyage(_voyageType)` at execution time.
- If a user signed when type price was low, a failed/future-nonce CallPermit could expose the signature; after owner/admin changes `tmapPerVoyage`, anyone can replay the same calldata and burn more TMAP than the user expected.
- Transient conditions are realistic: `NotEnoughTokens`, pause flag, invalid/current voyage allowlist, future nonce becoming current.

Current evidence gap:

- I did **not** find a real failed CallPermit tx to `buyVoyages` in the local failed Moonbeam latest-window data.
- This is the best **contract-level** economic-loss candidate, not yet a tx-level proof.

Severity if paired with real failed/future-nonce tx:

- Potential **High** if TMAP has value/liquidity and replay can burn materially more TMAP or mint unwanted voyages after config/price changes.

### 2. DIODE `approve(max)` via `SubmitTransaction` - strongest real replayable failed tx

Failed tx:

- Moonbeam tx: `0xcd422a3a9a3525b965f541d6b0537e846e37b38f520099077fe9b1ad792fbebd`
- Block: `15441926`
- Timestamp: `1777583238`
- Status: failed
- Dispatcher: `0x937C492A77aE90DE971986d003fFbc5f8bb2232C`
- Signed `from`: `0xb5A36021e107037F8b844766C6a7dB70e39d3F46`
- Target: `0x553FD260607B6D82474Aa06685eF6c2366647D7A`
- Deadline: `1777586833`
- Exact calldata hash: `0xb7d3fbb34c4b87477befd55e1f5585f6f0eb16c2fd1090e2da7e025b9329544d`

Decoded action:

```text
CallPermit.dispatch(...)
  -> SubmitTransaction(address dst, bytes data)
     dst = 0x434116a99619f2B465A137199C38c1Aab0353913  // DIODE token
     data = approve(0xc933776dA2F9FdC1E4531aD592A3fe5d0d964737, uint256.max)
```

Replayability evidence:

```text
valid signed nonce: 4
nonce at block 15441925: 2
nonce at failed block 15441926: 2
nonce at block 15441927: 3
nonce at block 15441928: 4
eth_call exact same calldata from unrelated account at block 15441928: OK
```

Economic state:

```text
DIODE balance of target before failed tx: 0
allowance target -> spender before failed tx: 0
```

Why replay-dangerous:

- The signature grants `uint256.max` allowance to a spender, with no relayer binding.
- The replay can be sent by any unrelated account once nonce 4 becomes current.
- This can convert future DIODE balance of the signer-controlled target into withdrawable funds for the spender.

Limits:

- At the historical block, the target had `0` DIODE, so immediate balance-loss is not shown.
- Need identify/trust model for spender `0xc933...4737` before claiming direct theft.

Severity:

- **Medium now**, potentially **High** if fork proof shows allowance `0 -> max` and spender can later `transferFrom` valuable DIODE from the target after funding.

### 3. Moonbeans Marketplace `fulfillListing(address,uint256)` - structurally close but native-value capped

Contract:

- Moonbeam: `0x683724817a7d526d6256Aec0D6f8ddF541b924de`
- Source verified as `MarketPlace`.

Function:

```solidity
function fulfillListing(address ca, uint256 tokenId) external payable nonReentrant
```

Source behavior:

```solidity
uint256 price = getCurrentListingPrice(ca, tokenId);
require(msg.value >= price, "The amount sent is less than the asking price.");
...
IERC721(ca).safeTransferFrom(oldOwner, newOwner, tokenId);
```

Mutable economic state:

```solidity
listings[ca][tokenId].push(Listing(price, block.timestamp, tokenId, false));
```

Replay analysis:

- Calldata does not include `maxPrice`.
- Price is read from latest listing storage at execution.
- Seller can effectively update listing by pushing a new listing.

Why not strong:

- Payment is native `msg.value`, and CallPermit signs `value`.
- If seller raises price above signed `value`, replay reverts.
- Higher-price replay only works if the user already signed an over-large native `value`.

Severity:

- **Low / rejected** for the specific "cheap buy -> higher price charge" class.

## B. Medium / Watchlist Classes

### DEX routers: Beamswap / StellaSwap / UniswapV2-style routers

Examples:

- Beamswap Router V1: `0x96b244391D98B62D19aE89b1A4dCcf0fc56970C7`
- StellaSwap Router V1: `0xd0A01ec574D1fC6652eDF79cb2F880fd47D34Ab1`

Relevant functions:

```solidity
swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] path, address to, uint deadline)
swapExactETHForTokens(uint amountOutMin, address[] path, address to, uint deadline)
swapTokensForExactTokens(uint amountOut, uint amountInMax, address[] path, address to, uint deadline)
```

Replay analysis:

- Standard router calldata includes `amountOutMin` or `amountInMax`.
- If the signed values are sane, worse reserves/slippage cause revert rather than economic loss.
- If the user signs `amountOutMin = 0` or a very low value, then replay can execute under worse price, but that unsafe bound is itself in the signed calldata.

Severity:

- **Medium only for signatures with unsafe minOut/maxIn**, otherwise rejected.

### Bridge/XCM / lending / staking

No concrete replayable failed tx found yet in the local candidate files.

Potentially dangerous if a target function:

- signs only `positionId` / `poolId` / `assetId`;
- reads current fee, rate, penalty, epoch, bridge fee, or route from storage;
- lacks `minAmount`, `maxFee`, `expectedRate`, or `recipient` binding.

Status:

- Search target class remains open; no strong Moonbeam/Moonriver tx-level candidate in current local data.

## C. Rejected Candidates

### `0xAf7De307...8792` / selector `0x38b5bc9c`

Rejected based on fork/decompile analysis in `AF7D_Target_38b5bc9c_Analysis_ru.md`.

Reason:

- Failure is `CREATE2` collision / deterministic address already had code.
- Same calldata stays failing; not a transient economic condition.
- Not token approve/transfer/swap/mint/buy/claim.

### DIODE approve raw candidate `0x93153619...aba985`

Decoded action:

```text
SubmitTransaction -> DIODE.approve(0xc933...4737, uint256.max)
```

Reason not strong:

- Valid signed nonce is `10`, but nonce stayed `9` throughout checked blocks before deadline.
- No observed replayable window before deadline.
- Allowance was already `uint256.max` before the failed tx.

## D. Best Chopsticks Fork PoC

Best tx-level PoC:

```text
0xcd422a3a9a3525b965f541d6b0537e846e37b38f520099077fe9b1ad792fbebd
```

Fork target:

- Start from block `15441928` or `15441929`.
- Set timestamp `< 1777586833`.
- Fund unrelated replay account.
- Submit exact same calldata to CallPermit `0x080a`.

Expected proof points:

- replay dispatcher is unrelated to original dispatcher and signed `from`;
- exact calldata hash matches `0xb7d3fbb34c4b87477befd55e1f5585f6f0eb16c2fd1090e2da7e025b9329544d`;
- CallPermit nonce signer goes `4 -> 5`;
- DIODE allowance `target 0x553F...D7A -> spender 0xc933...4737` goes `0 -> uint256.max`;
- action succeeds even though original failed and disclosed `v/r/s`.

Best contract-level economic-loss PoC:

- DPS `buyVoyages`.
- On fork, simulate a user signing at low `gameSettings.tmapPerVoyage`.
- Force failed dispatch or use future nonce.
- Admin changes `setTmapPerVoyage(type, higherAmount)`.
- Replay same calldata before deadline.
- Show extra TMAP burned and voyage minted without a fresh signature.

