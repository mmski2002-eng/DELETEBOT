# Failed Moonbeam/Moonriver CallPermit dispatch candidates

Дата: 2026-05-12  
Scope: failed/reverted tx to `0x000000000000000000000000000000000000080a` with selector `0xb5ea0966` (`dispatch(address,address,uint256,bytes,uint64,uint256,uint8,bytes32,bytes32)`).

## Search Method

Used public RPC `eth_getBlockReceipts` over recent blocks, then fetched full tx only for receipts where:

- `receipt.to == 0x000000000000000000000000000000000000080a`
- `receipt.status == 0x0`
- tx input starts with `0xb5ea0966`

Then decoded `dispatch(...)` calldata and checked whether the signature recovers `signedFrom` using CallPermit EIP-712 domain, decoded message fields, and `nonces(signedFrom)` at `block - 1`.

Script:

- [scan_failed_callpermit.js](</c:/DELETEBOT/moonbeam/research/scan_failed_callpermit.js>)

Run examples:

```powershell
$env:SCAN_CONCURRENCY='12'
node research\scan_failed_callpermit.js moonbeam 50000 100 > research\failed_callpermit_moonbeam_50k.json
node research\scan_failed_callpermit.js moonriver 50000 100 > research\failed_callpermit_moonriver_50k.json
```

## Summary

Moonbeam recent 50k blocks:

- Raw failed `dispatch` tx found: 98
- Signature-valid at `block - 1` using historical CallPermit nonce: 1
- Clear funds-moving inner selector (`approve`, `transfer`, `transferFrom`, `swap`, `claim`, `withdraw`, `redeem`, `mint`, `buy`): 0 signature-valid candidates found
- One invalid-signature/mismatched-nonce raw failed tx contains nested `approve(max)` calldata, but it is **not replay-valid** under historical nonce verification and should not be used as proof.

Moonriver recent scan:

- No failed `dispatch` candidates found in the completed portion of the recent 50k-block scan.
- Public RPC returned many `429` responses in the older part of the window, so re-run with lower concurrency or alternate RPC for complete coverage.

## Candidate 1: Valid Permit, Target Revert, Unknown Action

| Field | Value |
|---|---|
| Network | Moonbeam |
| Tx hash | `0xf69757c165643ddfd3058f63fd81c977c172c5e3036d1f8b89f3ea0769e75f4a` |
| Explorer | https://moonbeam.moonscan.io/tx/0xf69757c165643ddfd3058f63fd81c977c172c5e3036d1f8b89f3ea0769e75f4a |
| Block | `15556162` |
| Status / revert | Fail / explorer shows `execution reverted` without a specific decoded reason |
| Tx sender / dispatcher | `0x68e0bafdda9ef323f692fc080d612718c941d120` |
| Signed `from` | `0xb73B78353Fb704FC6fd0c9a3350Be4942F3846F8` |
| CallPermit nonce at `block - 1` | `9` |
| Signature check | Recovers `0xb73B...46F8` with nonce `9` |
| Target `to` | `0xAf7De307Eb221c916BaA33218b6780cAE6ab8792` |
| `value` | `0` |
| `gaslimit` | `4000000` |
| `deadline` | `1778350664` (`2026-05-09T18:17:44Z`) |
| `v/r/s` visible in calldata | Yes |
| Inner selector | `0x38b5bc9c` |
| Decoded inner `data` | unknown function selector with three address arguments |
| Inner args by ABI shape | `0xE664535Edfe130C9E7250DA50fddfbe2413f12Fc`, `0x8f541f73b5996abda01271a7d1cf7772aa5aef2a`, `0xf5c0106e10adbc8f1404407be6076546a41a67ba` |

Raw inner data:

```text
0x38b5bc9c
  000000000000000000000000e664535edfe130c9e7250da50fddfbe2413f12fc
  0000000000000000000000008f541f73b5996abda01271a7d1cf7772aa5aef2a
  000000000000000000000000f5c0106e10adbc8f1404407be6076546a41a67ba
```

Assessment:

- **Does it prove public signature disclosure?** Yes.
- **Does it prove nonce-not-consumed replay precondition?** Strongly likely: the permit signature is valid for the historical nonce, deadline was still valid at the block, and the tx failed, so failure likely happened in target subcall after permit verification.
- **Is action sensitive?** Unknown. The target contract is unverified in the checks above; selector `0x38b5bc9c` is not identified by 4byte. It takes three addresses and calls a contract with bytecode at `0xf5c010...`, but I cannot classify it as funds/action-sensitive without ABI/source.
- **Can revert be temporary?** Unknown. Since the target function is unidentified, transient-condition analysis is not safe.
- **Can same calldata be replayed later?** Historically, yes, before `deadline`, if nonce remained unchanged and target condition changed. As of 2026-05-12, no: the deadline has expired.

Verdict for this tx: **valid replay-mechanism candidate, but not a bounty-grade user-funds/action impact candidate yet.**

## Rejected Raw Candidate: Nested DIODE `approve(max)` But Signature Mismatch

| Field | Value |
|---|---|
| Network | Moonbeam |
| Tx hash | `0x93153619331c6ae3154e1792254d3d9c73a1baaeeb11dbeea8cff37603aba985` |
| Explorer | https://moonbeam.moonscan.io/tx/0x93153619331c6ae3154e1792254d3d9c73a1baaeeb11dbeea8cff37603aba985 |
| Block | `15556164` |
| Status / revert | Fail / `execution reverted` |
| Dispatcher | `0x68e0bafdda9ef323f692fc080d612718c941d120` |
| Claimed signed `from` | `0xb73B78353Fb704FC6fd0c9a3350Be4942F3846F8` |
| Target `to` | `0xE664535Edfe130C9E7250DA50fddfbe2413f12Fc` |
| Inner selector | `0x130dbfbb` unknown wrapper |
| Nested sensitive calldata | contains ERC-20 `approve(address,uint256)` selector `0x095ea7b3` for DIODE token `0x434116a99619f2b465a137199c38c1aab0353913`, spender `0xc933776dA2F9FdC1E4531aD592A3fe5d0d964737`, amount `uint256.max` |
| Signature check | Recovered `0x2c5256578314dE69c10Fd7D6Fd7CE0E15743D225`, not claimed `from` |

Assessment:

- **Action sensitive?** Yes, nested approval max would be sensitive if the permit were valid.
- **Replay candidate?** No. Historical nonce/signature check does not recover the claimed `from`, so this failed tx is more consistent with invalid permit / nonce mismatch than target-condition revert.
- **Use in mediation?** Do not use as proof of exploitable replay. It is useful only to show that sensitive action payloads appear in public `dispatch` calldata.

## Staking Precompile Raw Failures

The scan also found many failed dispatches to target:

`0x0000000000000000000000000000000000000800`

Likely Moonbeam staking precompile actions by selector:

- `0xfaa1786f` -> 4byte identifies `setAutoCompound(address,uint8,uint256,uint256)`
- `0xc90eee83` -> 4byte identifies `cancelDelegationRequest(address)`
- `0x1a1c740c` -> 4byte identifies `scheduleRevokeDelegation(address)`

Representative examples:

| Selector | Example tx | Block | Dispatcher | Signed `from` | Target |
|---|---|---:|---|---|---|
| `0xfaa1786f` | `0x14baa07481c4cf2338e064f4ffc1cc083c3e541bbe8a182694ce182e14f0fd95` | `15568114` | `0xbd0825351deb39fafa487971529c758c0737849e` | `0xDCC84F30Fac85f5E8f7Dcf80B154A05AD25d2824` | `0x0800` |
| `0xc90eee83` | `0x73879b66dc56db36fbb1513a447ea5292762a719e16db387ace86963057ee5a7` | `15568088` | `0xbd0825351deb39fafa487971529c758c0737849e` | `0xDCC84F30Fac85f5E8f7Dcf80B154A05AD25d2824` | `0x0800` |
| `0x1a1c740c` | `0x709cef6a5f18585d5645e4c638a110832e8a6e893e95a51ff207271880aded72` | `15543932` | `0xbe8d7c117a848ea4920d1d28886b6af9675ae560` | `0xDCC84F30Fac85f5E8f7Dcf80B154A05AD25d2824` | `0x0800` |

Assessment:

- **Action sensitive?** Potentially yes: staking delegation/autocompound settings affect staking state and rewards behavior.
- **Replay candidate?** In this scan, these did not pass the historical nonce/signature recovery check using `nonces(from)` at `block - 1`, so they should not be treated as target-revert replay proof without deeper per-tx nonce-order analysis.
- **Can same calldata replay now?** No, deadlines are expired.

## Final Verdict

I found real failed/reverted Moonbeam `dispatch(...)` txs with public `v/r/s`, but **did not find a strong user-funds/action replay candidate** in the scanned recent window.

Best candidate:

- `0xf69757c165643ddfd3058f63fd81c977c172c5e3036d1f8b89f3ea0769e75f4a`
- Valid permit under historical nonce
- Failed with deadline still valid
- Target action unidentified, so impact cannot be claimed as funds/action-sensitive yet

Strong-looking but rejected:

- `0x93153619331c6ae3154e1792254d3d9c73a1baaeeb11dbeea8cff37603aba985`
- Contains nested DIODE `approve(max)`, but signature does not recover claimed `from` for historical nonce, so it is not replay-valid evidence.

Next step for bounty-grade proof:

1. Run the script over larger historical windows and/or with an Etherscan v2 API key.
2. Filter to failed tx where signature recovers with historical nonce.
3. Then prioritize inner selectors `approve`, `transferFrom`, `swap`, `claim`, `withdraw`, `redeem`, `mint`, `buy`.
4. For candidates with unknown wrapper selectors, fetch/decompile target ABI/source before claiming sensitivity.

