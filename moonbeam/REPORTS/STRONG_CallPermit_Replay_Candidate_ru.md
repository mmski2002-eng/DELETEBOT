# Strong CallPermit Replay Candidate: Diode DriveMember AddJoinCode

Дата проверки: 2026-05-12

## A. Strong Candidate

Network: Moonbeam

Failed/public signature tx:

- Tx: `0xd5e49fc3e721a70059348b1186f3d7cfa14f52e7ac6af1fefb12eece4e6f862f`
- Block: `15410765`
- Block timestamp: `1777381944`
- Status: failed, `execution reverted`
- Receipt gas used: `39,516`
- Dispatcher: `0x937C492A77aE90DE971986d003fFbc5f8bb2232C`
- CallPermit: `0x000000000000000000000000000000000000080a`
- Signed `from`: `0x6A210A61dC8112C1344858d82B1dbDE850b957a1`
- Target `to`: `0x597B2084f1a74df59f3431AbE38dBeEc42dFd1c2`
- Deadline: `1777385542`, active at tx time and still active after the next block
- Signed nonce recovered from EIP-712: `8`
- `v/r/s`: public in calldata

Decoded inner action:

```text
dispatch(
  from     = 0x6A210A61dC8112C1344858d82B1dbDE850b957a1,
  to       = 0x597B2084f1a74df59f3431AbE38dBeEc42dFd1c2,
  value    = 0,
  data     = SubmitTransaction(address,bytes),
  gaslimit = 4000000,
  deadline = 1777385542,
  v/r/s    = public calldata
)
```

Outer call:

```text
0x130dbfbb = SubmitTransaction(address dst, bytes data)
dst        = 0xa1A3Cc69c5E2fA553b521aCC3c5876cd375195e3
```

Nested call:

```text
0xa05f1f2c = AddJoinCode(address,uint256,uint256,uint256)
args:
  0x88e0B12bC374D9322f1F7E137a90888b10D5dF7a
  2092741941
  500
  200
```

Selector sources:

- OpenChain signature DB resolves `0x130dbfbb` as `SubmitTransaction(address,bytes)`.
- OpenChain signature DB resolves `0xa05f1f2c` as `AddJoinCode(address,uint256,uint256,uint256)`.

Target/source facts:

- `0x597B2084f1a74df59f3431AbE38dBeEc42dFd1c2` is an EIP-1967 proxy-like contract.
- Implementation slot at block `15410765`: `0x2ee98b1dcb555e38b33b9d73d258a2ffe5a4e577`.
- Admin slot: `0xAf7De307Eb221c916BaA33218b6780cAE6ab8792`.
- Implementation `0x2ee98...` is verified on Moonscan as `DriveMember`.
- `DriveMember.SubmitTransaction(address dst, bytes data)` is `onlyMember` and executes arbitrary external call:

```solidity
function SubmitTransaction(address dst, bytes memory data) public onlyMember
{
    require(external_call(dst, data.length, data), "General Transaction failed");
}
```

Permission/state chain:

- At block `15410764`, `0x6A210A61...957a1` is owner/member of `0x597B...d1c2`.
- `0xa1A3...195e3` is another EIP-1967 proxy-like contract.
- `0xa1A3...195e3` implementation slot: `0xf5c0106e10adbc8f1404407be6076546a41a67ba`.
- `0xa1A3...195e3` owner is `0x597B...d1c2`.
- Direct historical `SubmitTransaction` simulation with the exact `0xd5e49f...` inner calldata estimates successfully at `~320,260` gas on blocks `15410764`, `15410765`, `15410766`, and `15410767`.

Why the failed tx was not consumed:

- It was signed for nonce `8`.
- In the same block, immediately before it, tx `0x5eb1dd70d421c855441a183b0d60e7e7b0301dbaf6123ec9c049beec58bbd05a` used the same signed `from` but nonce `7` and failed.
- Because nonce `7` was not consumed, the nonce-`8` permit in `0xd5e49f...` was a future-nonce permit at publication time and failed early.
- This still publicly disclosed a valid nonce-`8` signature.

Replay window opens:

- Next block tx `0x277b88471c24df7cfdf04d0104c537353cb1aff12f928141ff1d9e64bde9c5e6` succeeded.
- It used the same signed `from` and EIP-712 recovered nonce `7`.
- Block: `15410766`
- Block timestamp: `1777381950`
- Deadline of public nonce-`8` tx: `1777385542`
- Remaining replay window after nonce-`7` success: about `3592` seconds.
- After nonce `7` was consumed, the already-public nonce-`8` calldata from `0xd5e49f...` could be replayed by any dispatcher before deadline.

Sensitivity:

- This is not a token-transfer funds-loss candidate.
- It is a permission/action candidate: a Diode `DriveMember` owner/member authorization executing `AddJoinCode(...)` through a proxy-owned target.
- The action mutates application permission/join-code state, so it is not a harmless view/config read.

Verdict:

- Strong user-action replay candidate.
- Not yet proven as direct user-funds loss.
- The concrete exploit window is after block `15410766` and before timestamp `1777385542`: replay the exact calldata from `0xd5e49f...` from any account.

## B. Rejected But Notable

- `0xf69757c165643ddfd3058f63fd81c977c172c5e3036d1f8b89f3ea0769e75f4a`: valid-looking failed `0x38b5bc9c` to `0xAf7D...8792`, but fork trace showed deterministic CREATE2 collision. Not transient.
- `0x5eb1dd70d421c855441a183b0d60e7e7b0301dbaf6123ec9c049beec58bbd05a`: nonce `7`, same signer as strong candidate, but target is the already-rejected `0xAf7D...8792` path and failed with high gas. Useful only because its failure left nonce `7` unconsumed.
- `0x2facc77b5d7692f4c029d011e4022e2e9a6d087d7d6f6a653f24d564afc4930a` and `0x6cf591da981bc6b955c1a3bb9563d7755fa4c3ea69ed07560fb7ede50f035b31`: same signer/target family, signed for future nonces `9` and `10`; after only one success, nonce reached `8`, so these did not become replayable in the checked window.

## C. Best Next Fork Test

Ganache cannot faithfully execute Moonbeam CallPermit precompile at `0x080a`; it sees local stub bytecode and reverts.

Best fork/test route:

1. Use a Moonbeam-native fork/runtime test, Chopsticks, or a patched local precompile harness.
2. Start from block `15410766` state.
3. Set block timestamp below `1777385542`.
4. Submit exact tx input from `0xd5e49f...` to `0x080a` from any unrelated funded account.
5. Expected: nonce `8` is consumed and `SubmitTransaction -> AddJoinCode(...)` executes.

## D. Further Scan Strategy

Do not rely only on historical `nonces(from)` via public RPC for this precompile. The same-block sequence shows the safer method:

1. Decode failed `dispatch(...)`.
2. Brute-force recover the signed nonce over a bounded range.
3. Group txs by signed `from`.
4. Track same-signer nonce chains in block/order.
5. Flag failed future-nonce permits where an earlier nonce is later consumed before the failed permit deadline.
6. Prioritize nested `SubmitTransaction`, token approvals/transfers, swaps, mint/buy, claim/withdraw, bridge/staking/rewards calls.
