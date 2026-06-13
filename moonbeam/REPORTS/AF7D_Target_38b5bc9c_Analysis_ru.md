# Analysis: `0xAf7De307Eb221c916BaA33218b6780cAE6ab8792` / selector `0x38b5bc9c`

Дата: 2026-05-12  
Tx under analysis: `0xf69757c165643ddfd3058f63fd81c977c172c5e3036d1f8b89f3ea0769e75f4a`  
Network: Moonbeam

## Verdict

**Not a usable public-signature replay impact candidate.**

The failed CallPermit dispatch is a valid permit and does publish `v/r/s`, but the target failure is not a transient user-funds/action condition. Fork trace shows the target reverts at `CREATE2` because the deterministic deployment address already had code before the failed tx. The same calldata could not become successful later unless the already-deployed contract at that deterministic address disappeared, which is not a realistic transient condition.

## 1. Target Verification / ABI / Proxy

Target:

`0xAf7De307Eb221c916BaA33218b6780cAE6ab8792`

Findings:

- Moonscan status: **Contract: Unverified**.
- Sourcify full match: not found.
- Sourcify partial match: not found.
- ABI: not available from verified source.
- EIP-1967 proxy slots:
  - implementation: `0x0`
  - admin: `0x0`
  - beacon: `0x0`
- Conclusion: target itself is **not an EIP-1967 proxy**.

Runtime bytecode:

- length: `2091` bytes
- code hash: `0xab0f5270310d1fa0edef3c81065934c8c4a9dbad71fe3c4560e8ccde4dd4d46a`
- no Solidity metadata / swarm hash found by `evm` package.

Detected selectors in target bytecode:

```text
0x38b5bc9c
0x97d0ec42
0xb4e23cc0
0x09dfc965
0x277f2594
0x189acdbd
0xc4d66de8
0x8da5cb5b
```

4byte:

- `0x38b5bc9c`: no match
- `0x97d0ec42`: no match
- `0xb4e23cc0`: no match
- `0x09dfc965`: no match
- `0x277f2594`: no match
- `0x189acdbd`: no match
- `0xc4d66de8`: `initialize(address)`
- `0x8da5cb5b`: `owner()`

GitHub/web search:

- No useful public result found for `0x38b5bc9c`.
- No useful public result found for target address.
- No useful public source for exact bytecode hash.

## 2. Addresses Passed To `0x38b5bc9c`

Failed tx inner calldata:

```text
0x38b5bc9c
  000000000000000000000000e664535edfe130c9e7250da50fddfbe2413f12fc
  0000000000000000000000008f541f73b5996abda01271a7d1cf7772aa5aef2a
  000000000000000000000000f5c0106e10adbc8f1404407be6076546a41a67ba
```

Arguments:

1. `0xE664535Edfe130C9E7250DA50fddfbe2413f12Fc`
2. `0x8f541f73b5996abda01271a7d1cf7772aa5aef2a`
3. `0xf5c0106e10adbc8f1404407be6076546a41a67ba`

Address checks at block `15556162`:

| Address | Code | Notes |
|---|---:|---|
| `0xE664...12Fc` | yes, 495 bytes | EIP-1967 proxy-like contract; implementation slot = `0x2ee98b1dcb555e38b33b9d73d258a2ffe5a4e577`; admin slot = `0xAf7De307...8792`; `owner()` returns signedFrom `0xb73B...46F8`. |
| `0x8f541...ef2a` | no code | EOA-like; used by target as CREATE2 salt. |
| `0xf5c010...67ba` | yes, 18699 bytes | implementation/logic address embedded into CREATE2 init code. |

## 3. What `0x38b5bc9c` Does

No source/ABI was found, but bytecode and fork trace are clear enough for this tx:

1. Function accepts three address-like arguments.
2. It builds init code in memory.
3. It executes `CREATE2`.
4. For this tx:
   - `salt = 0x0000000000000000000000008f541f73b5996abda01271a7d1cf7772aa5aef2a`
   - init code size = `705` bytes
   - init code hash = `0x1e3d2a55cd2f86a91e6f92a2bace7fb7b1e69cb1ec1424ab08d51794c767e62b`
   - predicted CREATE2 address = `0xDB158a944989493686cCa6c3D8764DD7328823Ba`
5. `CREATE2` returns `0x0`.
6. The target immediately checks `EXTCODESIZE` and reverts empty (`0x`) at pc `279`.

Trace did **not** reach any external `CALL` after `CREATE2`; therefore, in this failed tx, the target did not call:

- `0xE664535Edfe130C9E7250DA50fddfbe2413f12Fc`
- `0x8f541f73b5996abda01271a7d1cf7772aa5aef2a`
- `0xf5c0106e10adbc8f1404407be6076546a41a67ba`

The init code embeds/uses the third address (`0xf5c010...`) as implementation-like input, and the second address is the CREATE2 salt. The first address appears intended for later registration/admin interaction, but this tx reverts before that path.

## 4. Revert Reason

Public Moonbeam RPC:

- `debug_traceTransaction`: method not found.
- `trace_replayTransaction`: method not found.
- `eth_call` at `block - 1`, `block`, later blocks, and latest: reverts with empty data `0x`.

Fork replay:

- Used Ganache fork at block `15556161`.
- Sent direct tx from signed `from` to target with same inner calldata.
- Tx reverted.
- `debug_traceTransaction` on fork shows:

```text
CREATE2 at pc 267
salt: 0x0000000000000000000000008f541f73b5996abda01271a7d1cf7772aa5aef2a
initHash: 0x1e3d2a55cd2f86a91e6f92a2bace7fb7b1e69cb1ec1424ab08d51794c767e62b
predicted: 0xDB158a944989493686cCa6c3D8764DD7328823Ba
then REVERT at pc 279 with empty returndata
```

Why `CREATE2` failed:

The predicted address already had code **before** the failed tx:

| Block | Code at `0xDB158a...23Ba` |
|---:|---:|
| `15556160` | 495 bytes |
| `15556161` | 495 bytes |
| `15556162` | 495 bytes |
| latest | 495 bytes |

That makes this a deterministic deployment collision / already-deployed condition.

## 5. Sensitivity

This is **not** token approve/transfer/transferFrom, DEX swap, claim, withdraw, redeem, mint/buy in the direct inner selector.

Likely action class:

- deterministic deployment / account or proxy creation;
- possible registration/admin setup after deployment;
- ownership/admin-sensitive in a broad sense because:
  - `0xE664...12Fc` has target `0xAf7D...8792` as EIP-1967 admin;
  - `0xE664...12Fc.owner()` returns the signed `from`;
  - the target bytecode includes owner-check-style paths.

But for this tx, no post-deployment registration/admin call happens because `CREATE2` fails first.

## 6. Replay Feasibility

CallPermit nonce:

| Block | `nonces(0xb73B...46F8)` |
|---:|---:|
| `15556161` | `9` |
| `15556162` | `9` |
| `15556163` | `9` |
| `15556200` | `9` |
| latest | `9` |

So the nonce was not consumed. This confirms the rollback behavior for this failed tx.

Replay window:

- Deadline: `1778350664` (`2026-05-09T18:17:44Z`)
- Block timestamp: `1778347074` (`2026-05-09T17:17:54Z`)
- It had about 1 hour of deadline window at failure time.

Could same calldata become successful later?

**No practical evidence.** The target failure was caused by a CREATE2 address already existing before the failed tx. The same CREATE2 salt/init-code/deployer combination always maps to the same occupied address. The direct target call still reverts at latest.

Therefore:

- replay before deadline would likely keep failing;
- no user-funds impact;
- no demonstrated later-success user-action impact;
- this tx should not be used as a strong mediation candidate beyond proving public `v/r/s` plus nonce rollback.

## Commands / Scripts Used

Fork trace sketch:

```js
const g = ganache.provider({
  fork: { url: 'https://rpc.api.moonbeam.network', blockNumber: 15556161 },
  wallet: { unlockedAccounts: ['0xb73B78353Fb704FC6fd0c9a3350Be4942F3846F8'] }
});
// fund signedFrom, send direct target tx, debug_traceTransaction
```

Direct target call:

```js
eth_call({
  from: '0xb73B78353Fb704FC6fd0c9a3350Be4942F3846F8',
  to: '0xAf7De307Eb221c916BaA33218b6780cAE6ab8792',
  data: '0x38b5bc9c...'
}, blockTag)
```

