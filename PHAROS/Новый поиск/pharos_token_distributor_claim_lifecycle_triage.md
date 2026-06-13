# Pharos Mainnet TokenDistributor Claim Lifecycle Triage

Scope: Pharos Mainnet, chainId `1672 / 0x688`.

Known sample tx:
`0xbf9b95fedab7b325f6424235ef8d8ee3d153064aa27004c87b248ff412d2a857`

Focus: whether a `Claimed` event and USDC `Transfer` are backed by canonical consumed entitlement state.

## 1. Contract baseline

| Field | Value |
|---|---|
| tx hash | `0xbf9b95fedab7b325f6424235ef8d8ee3d153064aa27004c87b248ff412d2a857` |
| block | `7197137` (`0x6dd1d1`) |
| timestamp | `2026-05-13T12:38:30Z` |
| from / claimant | `0x39581287bb2c105d2f9f38df6e235f64de84c682` |
| to / contract | `0x7c06f7d4e0f77b5e1d6499f2a1dc291de044f100` |
| contract label | `TokenDistributor` |
| receipt status | `1` |
| method | `claim(uint256 maxAmount, bytes32[] proof)` |
| selector | `0x2f52ebb7` |
| log count | `2` |
| token transfer count | `1` ERC20 `Transfer` log |
| token distributed | USDC at `0xc879c018db60520f4355c26ed1a6d572cdac1815` |
| token decimals | `6` |
| contract verification | `TokenDistributor` verified, non-proxy |
| ABI availability | verified ABI and source available through SocialScan |

Constructor-derived values:

- `owner`: `0x498aae86660270f3ad3a8431aae0c0e41dfd1af8`
- `operator`: `0x7a39c61adbd6d4767d858da6ce2ae3253780ea2e`
- `token`: `0xc879c018db60520f4355c26ed1a6d572cdac1815`

Relevant public/read functions:

- `claimedAmounts(address)`
- `totalClaimed()`
- `merkleRoot()`
- `token()`
- `owner()`
- `operator()`
- `startTime()`
- `endTime()`

Verified source consumption model:

```solidity
uint256 claimedAmount = claimedAmounts[msg.sender];
if (maxAmount <= claimedAmount) revert InvalidAmount();
bytes32 leaf = keccak256(abi.encodePacked(msg.sender, maxAmount));
if (!MerkleProof.verify(proof, merkleRoot, leaf)) revert InvalidProof();
uint256 pendingAmount = maxAmount - claimedAmount;
claimedAmounts[msg.sender] = maxAmount;
totalClaimed += pendingAmount;
transfer(msg.sender, pendingAmount);
emit Claimed(msg.sender, pendingAmount);
```

So the canonical consumed state is not a separate boolean. It is `claimedAmounts[account] >= maxAmount` for the current entitlement root.

## 2. Claim tx decode

| Field | Value |
|---|---|
| Function | `claim(uint256 maxAmount, bytes32[] proof)` |
| Claimant / recipient | `0x39581287bb2c105d2f9f38df6e235f64de84c682` |
| maxAmount | `15630000` raw units (`15.63 USDC`) |
| token | `0xc879c018db60520f4355c26ed1a6d572cdac1815` |
| proof length | `14` `bytes32` siblings |
| leaf | `0x1113fd2670115b6962f94b8b5a37e4a4677f7d6ba11c331700ff94c7eca1ff62` |
| computed proof root | `0x161f92db47b0b32798015f761e397a0a8fbd337915adb4b35decf26090c6e7b1` |
| on-chain `merkleRoot` | `0x161f92db47b0b32798015f761e397a0a8fbd337915adb4b35decf26090c6e7b1` |
| event recipient | `0x39581287bb2c105d2f9f38df6e235f64de84c682` |
| event amount | `15630000` |
| Transfer from | `0x7c06f7d4e0f77b5e1d6499f2a1dc291de044f100` |
| Transfer to | `0x39581287bb2c105d2f9f38df6e235f64de84c682` |
| Transfer amount | `15630000` |

Decoded logs:

| Log | Emitter | Event | Parameters |
|---:|---|---|---|
| 0 | USDC `0xc879...1815` | `Transfer(address,address,uint256)` | `from = TokenDistributor`, `to = 0x3958...c682`, `value = 15630000` |
| 1 | TokenDistributor `0x7c06...f100` | `Claimed(address,uint256)` | `account = 0x3958...c682`, `amount = 15630000` |

## 3. Event vs token balance table

USDC uses Circle `FiatTokenV2_2`. The verified implementation stores balances in `balanceAndBlacklistStates`, which maps at storage slot `9` in the proxy storage layout.

Balance slots:

- recipient balance slot: `keccak256(recipient . uint256(9))` =
  `0x7b29df9ce75f9e6cff30e4959074b435a1867ab264ef7a73e74d2b32a52122c6`
- distributor balance slot: `keccak256(distributor . uint256(9))` =
  `0xa15cdda3a31449600d61872eaa1f0ecb8b3437e70758a85a566e1d5014d45c63`

| Tx | Token | Distributor | Recipient | Event amount | Transfer amount | Distributor balance before | Distributor balance after | Recipient balance before | Recipient balance after | Distributor delta | Recipient delta | Matches event |
|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `0xbf9b...a857` | USDC `0xc879...1815` | `0x7c06...f100` | `0x3958...c682` | `15630000` | `15630000` | `59719090000` | `59703460000` | `0` | `15630000` | `-15630000` | `+15630000` | yes |

Evidence:

- Raw `Transfer` log amount: `0x000...00ee7eb0` = `15630000`.
- Direct `eth_getStorageAt` on USDC balance slots at block `7197136` and `7197137` gives exact before/after values above.
- No native value was transferred in the claim tx.

Note: historical `eth_call balanceOf(...)` was not used as primary before/after evidence because this RPC returned inconsistent historical public-read values in this investigation. Direct storage reads at explicit block tags reconciled cleanly with the transfer log.

## 4. Consumed-state proof

Distributor storage layout from verified source:

- slot `0`: ReentrancyGuard status
- slot `1`: `merkleRoot`
- slot `2`: `totalClaimed`
- slot `3`: packed `startTime` / `endTime`
- slot `4`: `claimedAmounts(address)` mapping

Claimant consumed-state slot:

`keccak256(0x39581287bb2c105d2f9f38df6e235f64de84c682 . uint256(4))` =
`0xe4a7a25d804096bd7e09cba516f1428f6cda96a38b0418c814bb71536f1aefbe`

| Evidence type | Before | After | Latest | Does it prove consumed state? | Confidence | Notes |
|---|---:|---:|---:|---|---|---|
| `claimedAmounts[claimant]` storage slot | `0` | `15630000` | `15630000` | yes | High | Direct `eth_getStorageAt` at `N-1`, `N`, latest. |
| `totalClaimed` storage slot | `440303600000` | `440319230000` | `441228840000` | supports | High | Delta at sample tx is `15630000`; later claims increased latest. |
| `debug_traceTransaction prestateTracer` | mapping slot `0`; `totalClaimed` before value present | mapping slot `0xee7eb0`; `totalClaimed` after value present | N/A | yes | High | Confirms the tx wrote the consumed marker before/with transfer. |
| Repeat `eth_call` with same calldata/from at block `N` | N/A | reverts `0x2c5211c6` | reverts `0x2c5211c6` | yes | High | `0x2c5211c6` = `InvalidAmount()`, matching `maxAmount <= claimedAmounts[msg.sender]`. |
| Public `claimedAmounts(address)` historical `eth_call` | returned `15630000` even at `N-1` | `15630000` | `15630000` | not used for before/after | Low for historical | Historical public calls appear unreliable on this RPC for this contract; direct storage is preferred. |

Conclusion: the claim is canonically consumed for this account and maxAmount because `claimedAmounts[account]` was set to `15630000`, equal to the Merkle entitlement amount, and the same calldata no longer passes the amount check.

## 5. Claim scope analysis

| Scope component | Observed in calldata | Observed in event | Observed in storage/consumed marker | Enforced or assumed | Evidence | Risk if missing |
|---|---|---|---|---|---|---|
| claimant address | implicit via `msg.sender` | yes, `account` | yes, mapping key | enforced | source uses `msg.sender`; storage key is claimant address | low here |
| recipient address | same as claimant via transfer to `msg.sender` | same account | same as claimant key | enforced | transfer and event both use `msg.sender` | low here |
| token address | no | no | immutable / code constant | enforced by contract deployment | `token()` returns USDC; transfer calls USDC | low for this contract |
| amount / maxAmount | yes | event shows pending amount | yes, value stored as `claimedAmounts[account]` | enforced | Merkle leaf uses `msg.sender,maxAmount`; storage set to maxAmount | low |
| Merkle root | not calldata | no | slot `1` | enforced | proof computes current `merkleRoot` | low for current root |
| proof | yes | no | not stored | enforced during claim | proof root equals on-chain root | low after storage consumption |
| index | no | no | no | not used | source uses address+amount, not index | no mismatch observed |
| nonce | no | no | no | not used | claim is scoped by cumulative amount | no mismatch observed |
| deadline / time window | no | no | slots `startTime/endTime` | enforced | block time within `1777816800` to `1779026400` | low for sample |
| chain id | no | no | no | not encoded in leaf by source | assumed by contract/address context | not a mismatch for this on-chain consumed-state check |
| contract address | no | no | yes by storage owner | enforced by call target | consumed marker lives in this TokenDistributor | low here |

## 6. Additional sample checks

No additional claim txs were sampled. The known sample met the prompt's immediate STOP criteria:

- event amount and transfer amount match;
- token balance slots move by exactly the claim amount;
- `claimedAmounts[account]` changes from `0` to `maxAmount`;
- `totalClaimed` increases by the claim amount;
- repeat read-only call with the same calldata reverts with `InvalidAmount()`.

## 7. Observer comparison

| Observer | What it proves | What it cannot prove alone | Status/label | Stronger than evidence? |
|---|---|---|---|---|
| RPC receipt | tx succeeded, logs emitted | entitlement consumption without storage inspection | `status = 1` | no |
| Raw logs | exact `Transfer` and `Claimed` topics/data | consumed marker | `Transfer`, `Claimed` | logs alone would be weaker |
| SocialScan decoded events | decodes account/amount and token transfer | storage consumption unless paired with reads | `Claim`, `Claimed` | no, after storage proof |
| ERC20 token state | distributor decreased and recipient increased by `15630000` | claim entitlement is consumed | transferred | no |
| TokenDistributor consumed state | `claimedAmounts[claimant] = 15630000` after tx | broader off-chain campaign semantics | consumed for this maxAmount/account | no |
| Repeat `eth_call` | same claim no longer passes amount check | impossible under all future roots/config changes | `InvalidAmount()` | no |
| Human/UI interpretation | can reasonably show claim complete | cannot infer anything beyond this entitlement | claimed / transferred | no for this sample |

## 8. Suspicious states

None found.

Checked and disproved:

- `Claimed` emitted but no consumed state change: disproved by `claimedAmounts` storage slot.
- Transfer recipient differs from claim recipient: disproved; both are `0x3958...c682`.
- Event amount differs from token transfer amount: disproved; both `15630000`.
- Token balance delta differs from transfer amount: disproved by direct USDC balance storage.
- Same calldata remains accepted after tx: disproved; repeat `eth_call` reverts `InvalidAmount()`.
- Explorer/API label stronger than canonical state: not observed after storage proof.

## 9. Disproved/cosmetic differences

- Historical public `eth_call` inconsistency is cosmetic for this finding because direct storage reads and trace provide canonical before/after state.
- Lack of a boolean `claimed(address)` is not suspicious; this distributor uses cumulative `claimedAmounts(address)` as the consumed marker.
- There is no separate claim id/index. The entitlement is scoped by `msg.sender`, `maxAmount`, current `merkleRoot`, and this contract's storage.

## 10. Triage decision

STOP.

The sample claim lifecycle is internally consistent:

- `Claimed` amount = USDC `Transfer` amount = recipient balance delta = distributor balance delta.
- The Merkle proof computes the on-chain root.
- `claimedAmounts[claimant]` moves from `0` to `15630000`.
- `totalClaimed` increases by `15630000`.
- Repeat read-only call with identical calldata/from fails with `InvalidAmount()`.

## 11. Recommended next target

1. Explorer/indexer temporary lag around newest transactions
2. Search for verified bridge/OFT contracts with pending/refund lifecycle
3. Asset identity / token mapping checks across Pharos and Base

Final judgment:

STOP: No strong lead in sampled TokenDistributor claim lifecycle.
