# Moonbeam CallPermit nonce rollback: mediation evidence

Дата: 2026-05-12  
Статус: public-info / local-fork research; реальные сервисы не атакованы.

## A. Verdict

**Verdict: gather more before mediation, but do not abandon.**

Сейчас лучший доказанный impact - не "hypothetical relayer griefing", а нарушение публично задокументированной модели CallPermit: Moonbeam сам описывает precompile как механизм gasless/meta-transactions, где `dispatch()` может вызываться любым адресом/контрактом, dispatcher платит fee, а nonce нужен для replay protection. Публичный Moonscan также показывает, что `0x000000000000000000000000000000000000080a` - это `Moonbeam: Call Permit` с большим количеством `Dispatch` транзакций.

Для сильной Immunefi mediation все еще не хватает одного из двух:

1. конкретного production relayer/sponsor, который принимает CallPermit payload от пользователей и несет gas loss;
2. конкретного failed/reverted CallPermit tx, где calldata раскрывает reusable `v/r/s`, nonce не consumed, а последующий replay может стать successful.

Без этого Moonbeam может уверенно держать линию: "impact only to external relayers / relayer should simulate".

## B. Weakest Points In Moonbeam Rejection

1. **"Third-party relayers only" неполно.** CallPermit не является сторонней интеграцией поверх Moonbeam; это официальный Moonbeam precompile на `0x080a`. Официальная документация прямо позиционирует его для gasless transactions: signer подписывает EIP-712 permit, другой адрес/контракт dispatches и платит fee.

2. **"Relayer should simulate" не закрывает time-of-check/time-of-inclusion.** Даже корректная симуляция в block N не гарантирует success при inclusion в block N+k. Любые state-dependent условия могут измениться: balance/allowance, NFT ownership, already-claimed flags, DEX reserves/slippage, deadlines/timestamps, oracle state.

3. **"Atomic EVM semantics" не отвечает на replay-protection invariant.** Проблема не в том, что EVM rollback неожиданный, а в том, что protocol-level nonce для подписи откатывается вместе с target revert. Если failed transaction раскрывает signature в public calldata, permissionless `dispatch()` превращает failed permit в публичный reusable authorization until deadline.

4. **"No Moonbeam infra at risk" не закрывает user-action replay.** Если подпись опубликована в reverted tx, а `msg.sender`/relayer не входит в signed payload, later replay может выполнить user-authorized action без fresh consent, когда revert condition исчезнет.

## C. Strongest Mediation Argument

Самый сильный angle:

> CallPermit advertises permissionless dispatch and gasless execution, but failed dispatch publishes the full authorization while preserving the nonce. This breaks the expected one-shot nature of a signed authorization. If the target revert condition is transient, any observer can replay the same public calldata later, not just the original relayer.

Это сильнее, чем griefing relayers, потому что переводит impact из "external relayer lost gas" в "publicly revealed signed user authorization can remain live after an on-chain failed attempt".

Но для bounty-relevant impact нужен concrete target, где later success приводит к user funds movement или state-changing user action: swap, claim, purchase, bridge claim, NFT transfer/mint/buy, staking withdraw, lending repay/liquidation.

## D. Real CallPermit Integrations Found

| Evidence | Status | Notes |
|---|---:|---|
| Moonbeam official Call Permit docs | Confirmed | Docs say permit can authorize any EVM call, can be dispatched by anyone/contract, dispatcher pays tx fees, and the precompile can be used for gas-less transactions. Address is `0x000000000000000000000000000000000000080a` on Moonbeam/Moonriver/Moonbase. |
| Moonbeam precompiles overview | Confirmed | Lists Call Permit at `0x000000000000000000000000000000000000080a`; page last updated 2026-01-27. |
| Moonscan address page | Confirmed public on-chain use | Address labeled `Moonbeam: Call Permit`; indexed ABI includes `dispatch(...)`, `nonces(owner)`, `DOMAIN_SEPARATOR()`. Search snapshot showed 948,827 total transactions and many `Dispatch` rows from sender `0xDfBe5e56...Af0263b01` in Jan 2026. Needs live re-check before mediation because the page snapshot is not May 2026-live. |
| Moonbeam gasless CallPermit DPS tutorial | Confirmed example with real target | Official tutorial uses Damned Pirates Society `Cartographer V1` on Moonbeam at `0xD1A9bA3e61Ac676f58B29EA0a09Cf5D7f4f35138`, calling `buyVoyages(...)`; it explicitly uses a `thirdPartyGasSigner` and says the third-party account pays GLMR gas. |
| `ismaventuras/callpermit-nft-moonbeam` | Confirmed public repo/example | Public GitHub repo and demo for lazy minting NFT via CallPermit on Moonbase Alpha; good evidence of developer adoption, weaker for mainnet economic impact. |
| Diode Client `DiodeClient.Contracts.CallPermit` | Confirmed SDK/library wrapper | HexDocs documents a CallPermit contract wrapper with `dispatch`, `nonces`, `call_permit`, `decode_dispatch`; this is real integration surface, but not yet evidence of a relayer losing funds. |
| Chainlink Block Magic hackathon Moonbeam bounty | Confirmed ecosystem promotion | Challenge explicitly asks builders to use Moonbeam Call Permit for gasless experience and suggests games, bridges, cross-chain swaps; useful to show Moonbeam promoted this exact use case. |

## E. Real Relayers/Sponsors Found

**Confirmed:**

1. Moonbeam official tutorial models a third-party gas signer (`thirdPartyGasSigner`) that dispatches the permit and pays gas.
2. Moonbeam docs say anyone/any smart contract may dispatch; dispatcher pays transaction fees.
3. Moonscan public address page shows many `Dispatch` transactions to `0x080a`; sample repeated sender in snapshot: `0xDfBe5e56...Af0263b01`.

**Not confirmed enough for mediation:**

1. Gelato + Moonbeam exists as generic relayer infra, but no public evidence found that Gelato currently relays CallPermit payloads.
2. Biconomy gasless infra is relevant generally, but no direct Moonbeam CallPermit integration found.
3. OpenGSN is useful for industry comparison, not evidence of real Moonbeam CallPermit relaying.

Do not claim Gelato/Biconomy as impacted unless a repo, doc, tx, endpoint, or sponsor wallet proves CallPermit usage.

## F. Simulation-Bypass Candidates

Best candidates where simulation can pass before inclusion but real tx reverts, leaving signature reusable:

1. **DPS `buyVoyages` / game purchases.** Official tutorial target: `Cartographer V1` `0xD1A9bA3e61Ac676f58B29EA0a09Cf5D7f4f35138`; call consumes TMAP and creates voyages. Revert candidates: user TMAP balance/allowance changes, voyage config changes, sale paused, voyage address/state changes.
2. **DEX swaps.** Revert candidates: slippage/minOut, reserves changed, deadline expired, token balance/allowance changed.
3. **Rewards/claims.** Revert candidates: claim already consumed, reward epoch changed, Merkle root/proof state changed.
4. **NFT mint/buy.** Revert candidates: supply sold out, ownership/listing changed, price changed, deadline expired.
5. **Bridge claim/XCM action.** Revert candidates: already claimed, channel/asset state changed, fee changed.

The strongest PoC should avoid AlwaysRevert. Use a transient revert:

1. sign permit for a valid user action;
2. make it revert due to temporary condition;
3. show nonce unchanged;
4. replay same `v/r/s` after condition becomes valid;
5. show user action executes without a fresh signature.

## G. Public-Signature Replay Analysis

CallPermit signed fields are `from`, `to`, `value`, `data`, `gaslimit`, `nonce`, `deadline`. The signed payload does **not** include `msg.sender`/relayer. Official docs and ABI show `dispatch(...)` accepts `v`, `r`, `s` as calldata. Therefore:

1. any submitted `dispatch()` transaction publishes the signature parameters in tx input calldata;
2. if target call reverts and the whole frame rolls back, `nonce` remains valid;
3. because dispatcher is permissionless and not bound in the EIP-712 payload, a different observer can resubmit the same calldata before `deadline`;
4. if the transient revert condition later clears, the same signature can execute.

Limitations:

1. if `deadline` is short, replay window is narrow;
2. if the signed `data` is permanently invalid or target always reverts, impact is relayer gas griefing only;
3. if the target action is harmless, no user funds/action impact;
4. if the relayer keeps the payload private and never submits a failed tx, public observer replay does not apply.

## H. External Side Effects Analysis

EVM logs revert with the frame. Ordinary Solidity logs and subcall state changes do not persist after revert.

For Moonbeam/Substrate precompiles and XCM-related precompiles, no public evidence was found in this pass that a CallPermit subcall can create non-atomic external side effects that survive an EVM revert. Treat this as **not proven**. Do not use it in mediation unless a local runtime test demonstrates persistent side effects.

## I. Industry Comparison

| System | Behavior | Relevance |
|---|---|---|
| OpenGSN Forwarder | Official docs say `execute` returns the target `success` flag and target errors via return data; it reverts only for verification errors. This design lets nonce updates persist even when target call fails. | Supports the argument that relayer systems intentionally decouple signature consumption from target success. |
| OpenZeppelin ERC2771Forwarder 5.x | Docs/source say `execute` reverts if the requested call reverts; in that case nonce is not consumed. | This weakens any claim that "nonce must always be consumed on failed target call" is universal. However, OZ makes the behavior explicit and emits/structures execution around ERC-2771 trusted forwarders, not arbitrary-call precompile UX. |
| EIP-3009 | Reference implementation marks authorization used before `_transfer`, but if `_transfer` reverts the whole tx reverts and authorization state rolls back. EIP also warns about public authorization/front-running and provides `receiveWithAuthorization` binding to caller/payee. | Useful mostly for the front-running/caller-binding point, not as proof that nonce must persist after revert. |

Conclusion: industry comparison should be framed carefully. The invariant is not universal "consume nonce on any target failure". The stronger point is: for a permissionless arbitrary-call gasless precompile, Moonbeam exposes public signatures and has no relayer binding, so nonce rollback creates replay/griefing risk unless this behavior is explicitly documented and safely handled by integrators.

## J. Concrete PoC Plan

1. **Local fork / dev node target.** Implement `TransientTarget` with:
   - `execute(uint amount)` succeeds only when `enabled == true`;
   - before enabled, it reverts;
   - on success, transfers ERC20/NFT or records irreversible user action.
2. **Generate real CallPermit typed data.** Use `from`, `to`, `value`, `data`, `gaslimit`, `nonce`, `deadline`; sign with user key.
3. **Submit failed `dispatch()`.** Relayer account sends tx to `0x080a`; target reverts; assert `CallPermit.nonces(from)` unchanged.
4. **Show public replay.** A second unrelated account copies exact calldata including `v/r/s`; after toggling `enabled`, resubmits.
5. **Assert impact.** Same signature executes user action/fund movement without fresh consent; nonce finally increments only after success.
6. **Optional mainnet evidence.** Use Moonscan to find reverted `Dispatch` txs to `0x080a`; decode target `to/data`; check if target condition could become valid later. Do not execute replay on mainnet.

## K. Draft Bullets For Immunefi Mediation

- Moonbeam's rejection understates that CallPermit is a first-party precompile and a documented gasless/meta-transaction primitive, not a third-party relayer feature.
- Official docs state `dispatch` can be called by anyone/any smart contract and the dispatcher pays transaction fees; this is exactly the relayer/sponsor model.
- The EIP-712 payload does not bind the dispatcher. Once a failed `dispatch` is mined, the full signature is public calldata.
- Because a target revert rolls back the nonce increment, a failed public permit remains valid until its deadline.
- Simulation is insufficient: state can change between simulation and inclusion, causing transient reverts despite correct relayer behavior.
- The impact is not only relayer gas loss. In transient-revert cases, any observer can replay the publicly revealed signature later and execute the user's authorized action without fresh consent.
- Moonscan labels `0x080a` as `Moonbeam: Call Permit` and indexes large-scale `Dispatch` usage; this demonstrates real on-chain use of the precompile, not a theoretical API.
- Moonbeam's own DPS gasless tutorial gives a concrete mainnet-style target/action (`Cartographer V1.buyVoyages`) and a third-party gas signer model.
- We are not relying on AlwaysRevert-only impact. The requested remediation is based on transient target failures where replay can later succeed.
- Requested outcome: recognize at least gas-griefing/replay-protection impact, or reopen for additional evidence with a transient-revert PoC and public-calldata replay analysis.

## Sources

- Moonbeam Call Permit docs: https://docs.moonbeam.network/builders/ethereum/precompiles/ux/call-permit/
- Moonbeam precompiles overview: https://docs.moonbeam.network/builders/ethereum/precompiles/overview/
- Moonscan Call Permit address: https://moonbeam.moonscan.io/address/0x000000000000000000000000000000000000080a
- Moonbeam gasless CallPermit tutorial: https://docs.moonbeam.network/cn/tutorials/eth-api/call-permit-gasless-txs/
- DPS tutorial transaction example: https://moonbeam.moonscan.io/tx/0xf1063a43c7470b7ed9b93e3a647f9812c5ac5acd5826f61c8b1d05a53166af50/advanced
- `ismaventuras/callpermit-nft-moonbeam`: https://github.com/ismaventuras/callpermit-nft-moonbeam
- Diode Client CallPermit wrapper: https://hexdocs.pm/diode_client/DiodeClient.Contracts.CallPermit.html
- Chainlink Block Magic Moonbeam challenge: https://chainlinkblockmagic.devpost.com/
- OpenGSN Forwarder docs: https://docs.opengsn.org/soldoc/contracts/forwarder/forwarder
- OpenZeppelin ERC2771Forwarder docs: https://docs.openzeppelin.com/contracts/5.x/api/metatx
- OpenZeppelin ERC2771Forwarder source: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/metatx/ERC2771Forwarder.sol
- ERC-3009: https://eips.ethereum.org/EIPS/eip-3009
