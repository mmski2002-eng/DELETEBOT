# Moonbeam CallPermit: public-signature replay angle

Дата проверки: 2026-05-12  
Фокус: только сценарий `failed dispatch -> public v/r/s -> nonce not consumed -> unrelated replay -> later success`.

## Verdict

**Сценарий технически подтвержден локальным PoC и согласуется с Moonbeam docs/source.**

Что доказано:

1. `v/r/s` публикуются в calldata `dispatch(...)`.
2. Signed payload не включает dispatcher / `msg.sender` / relayer.
3. `dispatch` permissionless: docs говорят, что его может вызвать anyone / any smart contract.
4. В текущем Rust source nonce increment происходит перед subcall, но `ExitReason::Revert` возвращает `PrecompileFailure::Revert`; значит EVM-frame rollback откатывает nonce increment.
5. Локальный PoC показывает: same calldata, подписанная одним user, после failed dispatch успешно replayed вторым unrelated address после изменения state target.

Что не доказано:

1. Не найден публичный реальный failed Moonbeam `dispatch` tx, который уже можно было бы later replay до success.
2. Не доказана потеря user funds на mainnet без дополнительного конкретного failed tx / target-state analysis.

**Impact verdict:** user-action impact подтвержден как реальный класс риска для state-dependent targets. User-funds impact возможен для `approve`, `transferFrom`, DEX swap, NFT buy/mint, rewards/claim targets, но для bounty-grade доказательства нужен конкретный failed tx или live fork replay без отправки mainnet replay.

## 1. Signed Payload Fields

Moonbeam docs define the signed `CallPermit` typed data as:

```text
from: address
to: address
value: uint256
data: bytes
gaslimit: uint64
nonce: uint256
deadline: uint256
```

Docs evidence:

- Moonbeam docs say the user signs the dispatch arguments except `v/r/s`, plus signer nonce.
- The docs example `CallPermit` type lists exactly `from`, `to`, `value`, `data`, `gaslimit`, `nonce`, `deadline`.
- Domain is `name = "Call Permit Precompile"`, `version = "1"`, `chainId`, `verifyingContract = 0x000000000000000000000000000000000000080a`.

Source evidence:

- `PERMIT_TYPEHASH` in `precompiles/call-permit/src/lib.rs`:

```rust
"CallPermit(address from,address to,uint256 value,bytes data,uint64 gaslimit,uint256 nonce,uint256 deadline)"
```

- `generate_permit(...)` hashes:

```rust
PERMIT_TYPEHASH,
Address(from),
Address(to),
value,
H256::from(keccak_256(&data)),
gaslimit,
nonce,
deadline
```

## 2. Dispatcher / msg.sender / relayer Binding

**Dispatcher is not signed.**

Neither docs nor Rust source include `msg.sender`, dispatcher, relayer, executor, fee payer, or caller in the signed typed data. In source, signature verification recovers `signer == from`; it does not compare `handle.context().caller` / transaction sender to any signed field.

Important source detail:

- target subcall context uses `caller: from`, not dispatcher:

```rust
let sub_context = Context {
    caller: from,
    address: to.clone(),
    apparent_value: value,
};
```

So the target sees action as signer/from, while the actual transaction sender can be anyone who has the public calldata.

## 3. Permissionless Dispatch

Confirmed.

Moonbeam docs:

- Introduction: a permit for any EVM call "can be dispatched by anyone or any smart contract".
- Interface section: `dispatch(...)` "can be called by anyone or any smart contract".
- Docs also say the dispatcher pays transaction fees, and give Alice/Bob gasless example.

This directly supports "unrelated observer can replay same calldata" unless nonce or deadline blocks it.

## 4. Local PoC

Files added:

- [contracts/MockCallPermit.sol](</c:/DELETEBOT/moonbeam/contracts/MockCallPermit.sol>)
- [contracts/TransientTarget.sol](</c:/DELETEBOT/moonbeam/contracts/TransientTarget.sol>)
- [test/public_signature_replay_poc.js](</c:/DELETEBOT/moonbeam/test/public_signature_replay_poc.js>)
- [package.json](</c:/DELETEBOT/moonbeam/package.json>)

Run:

```powershell
npm install
npm run poc:public-replay
```

Result from local run:

```json
{
  "user": "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
  "firstDispatcher": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
  "replayDispatcher": "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
  "nonceAfterFailedDispatch": "0",
  "nonceAfterReplaySuccess": "1",
  "spentAfterReplay": "7"
}
```

What the PoC proves:

1. User signs EIP-712 `CallPermit` with fields matching Moonbeam.
2. First dispatcher calls `dispatch` while `TransientTarget.enabled == false`; target reverts.
3. Nonce remains `0` after failed dispatch.
4. Target state changes: `enabled = true`.
5. Second unrelated dispatcher sends exact same encoded `dispatch(...)` calldata, including same `v/r/s`.
6. Same signed action succeeds and consumes user credits; nonce becomes `1` only after success.

The PoC is a local model, not Moonbeam runtime. It models the relevant rollback property with Solidity's normal same-frame revert semantics. The Moonbeam-specific bridge is the Rust source: `NoncesStorage::insert(...)` occurs before `handle.call(...)`, and `ExitReason::Revert` returns `PrecompileFailure::Revert`.

## 5. Real Moonbeam Targets / Evidence

### A. CallPermit mainnet usage at `0x080a`

Moonscan labels `0x000000000000000000000000000000000000080a` as `Moonbeam : Call Permit`.

Observed current page evidence:

- Latest 25 from total `1,145,733` transactions.
- Latest rows are `Dispatch`.
- Example tx: `0xeb5ed3119dfe4d56ab2b31da1f49be97b534ca5e1fe7a42b5f5d32a838973f70`.

### B. Fresh real target: DIODE token approval via CallPermit

Moonscan tx:

`0xeb5ed3119dfe4d56ab2b31da1f49be97b534ca5e1fe7a42b5f5d32a838973f70`

Facts from tx page:

- Status: Success.
- From dispatcher: `0x1350d3b501d6842eD881B59DE4B95B27372bFaE8`.
- To: `0x000000000000000000000000000000000000080a` (`Moonbeam : Call Permit`).
- Function: `dispatch(address from,address to,uint256 value,bytes data,uint64 gaslimit,uint256 deadline,uint8 v,bytes32 r,bytes32 s)`.
- Signed `from`: `0x40bbe0e5a412e21c46319f6c183628abed49436d`.
- Target `to`: `0x5c0d1d96fac3b273df6460042704777c84862ff2`.
- Event log labels target token as `Diode: DIODE Token`.
- Inner call data contains ERC-20 `approve(address,uint256)` selector `0x095ea7b3`.
- Spender in approval event: `0xc933776dA2F9FdC1E4531aD592A3fe5d0d964737`.
- Approval value: max uint256.
- `v`, `r`, `s` are visible in input data.

Relevance:

- This proves public calldata carries user authorization material for a real token approval action.
- If a comparable approval dispatch failed transiently and nonce rolled back, the public `v/r/s` could authorize later approval without fresh user signature.

Limit:

- This specific tx succeeded, so it is not itself exploitable.
- Plain ERC-20 `approve` usually does not have common transient failure conditions unless token is paused/blacklisted/nonstandard or spender/token state changes.

### C. DPS `buyVoyages`

Moonbeam official gasless tutorial target:

- `Cartographer V1`: `0xD1A9bA3e61Ac676f58B29EA0a09Cf5D7f4f35138`
- Function: `buyVoyages(uint16 _voyageType,uint256 _amount,address _voyage)`
- `DPSVoyageV2`: `0x72A33394f0652e2Bf15d7901f3Cd46863d968424`
- Tutorial explicitly uses CallPermit gasless flow with a `thirdPartyGasSigner`.

Transient revert possibilities:

- insufficient/changed game token balance;
- allowance changed before inclusion;
- voyage config changed;
- sale paused or voyage type unavailable;
- target voyage contract state changed.

Relevance:

- Strong real target for "user action" impact because successful replay buys game voyages/actions on behalf of signer.
- Need source/ABI or fork test to prove exact revert reasons.

### D. Token `transferFrom` / allowance / balance

Not found as a concrete CallPermit tx in this pass, but it is the cleanest user-funds target class:

- signed `data` can call `transferFrom(from, attackerOrDapp, amount)` on an ERC-20;
- simulation can pass while allowance/balance later changes before inclusion;
- failed public dispatch would reveal `v/r/s`;
- later balance/allowance restoration could let unrelated observer replay.

Need real Moonbeam tx/source evidence before claiming as actual impact.

### E. DEX swap / NFT buy-mint / rewards claim

These are plausible transient-revert target classes, but no concrete CallPermit mainnet tx/source was confirmed in this pass. Do not claim as real Moonbeam impact yet.

## Final Answer

**Public-signature replay angle: proven as a mechanism.**

The signed payload does not bind dispatcher. `dispatch` is permissionless. Failed `dispatch` calldata publicly exposes `v/r/s`. Moonbeam source increments nonce before subcall but returns a revert on subcall revert, so the nonce increment is rollback-prone. Local PoC confirms same calldata can be replayed by unrelated address after target state changes, and nonce is consumed only on success.

**User-action impact: yes, for state-dependent actions.**

PoC proves this class.

**User-funds impact: plausible but not fully proven on real Moonbeam mainnet yet.**

The strongest real evidence found is a live CallPermit token `approve(max)` tx to DIODE, proving public signed calldata can authorize token approvals. To make this bounty-grade for funds loss, next step is to find a failed `Dispatch` tx to `0x080a` whose inner call is token approval/transferFrom/swap/NFT buy/claim and whose failure condition is transient.

## Sources

- Moonbeam Call Permit docs: https://docs.moonbeam.network/builders/ethereum/precompiles/ux/call-permit/
- Moonbeam CallPermit Rust source: https://raw.githubusercontent.com/moonbeam-foundation/moonbeam/master/precompiles/call-permit/src/lib.rs
- Moonbeam CallPermit Solidity interface: https://raw.githubusercontent.com/moonbeam-foundation/moonbeam/master/precompiles/call-permit/CallPermit.sol
- Moonscan CallPermit address: https://moonbeam.moonscan.io/address/0x000000000000000000000000000000000000080a
- Real CallPermit DIODE approval tx: https://moonbeam.moonscan.io/tx/0xeb5ed3119dfe4d56ab2b31da1f49be97b534ca5e1fe7a42b5f5d32a838973f70
- Moonbeam DPS gasless tutorial: https://docs.moonbeam.network/cn/tutorials/eth-api/call-permit-gasless-txs/
- DPS example tx: https://moonbeam.moonscan.io/tx/0xf1063a43c7470b7ed9b93e3a647f9812c5ac5acd5826f61c8b1d05a53166af50/advanced
