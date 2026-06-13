# Abstract mainnet: кандидаты stale / replay / delayed execution

Дата проверки: 2026-05-12. Цепочка: Abstract Ethereum L2 mainnet.

Важно: ниже не “готовые эксплойты”, а реальные production-used кандидаты, где в verified source на Abstract есть подписанная авторизация / permit-like / meta-tx и потенциально option-like delayed execution. Для подтверждения уязвимости нужны транзакционные симуляции с конкретными order/call payload и сроками expiration/deadline.

## 1. Relay Approval Proxy V3 + Relay Router V3

PROJECT: Relay

CHAIN: Abstract mainnet

CONTRACT:
- Relay Approval Proxy V3: `0xccc88a9d1b4ed6b0eaba998850414b24f1c315be`
- Relay Router V3: `0xb92fe925DC43a0ECdE6c8b1a2709c170Ec4fFf4f`
- Источники: https://abscan.org/address/0xccc88a9d1b4ed6b0eaba998850414b24f1c315be и https://abscan.org/address/0xb92fe925DC43a0ECdE6c8b1a2709c170Ec4fFf4f

FUNCTIONS:
- `permitTransferAndMulticall`
- `permit2TransferAndMulticall`
- `permit3009TransferAndMulticall`
- Router `multicall`
- Router internal `_aggregate3Value`

TYPE: meta-tx / permit-like / cross-contract settlement / ERC20 + arbitrary multicall

REAL USAGE EVIDENCE:
- Approval Proxy V3: 41,262 tx на Abscan.
- Router V3: 142,091 tx на Abscan.
- Контракты verified и подписаны как Relay production contracts.

PERMIT / AUTH MECHANISM:
- ERC-2612-like permit через `trustlessPermit`.
- Permit2 `permitWitnessTransferFrom`.
- ERC-3009 `receiveWithAuthorization`.
- Permit2 witness hash включает `msg.sender` как relayer, `refundTo`, `nftRecipient`, `metadata`, hash массива `calls`.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Да, кандидат сильный.
- В proxy permit/authorization вызывается до router `multicall`.
- Если downstream call в Router V3 с `allowFailure=false` ревертит, весь transaction revert откатывает:
  - ERC20 permit nonce / allowance update,
  - Permit2 nonce consumption,
  - ERC-3009 authorization consumption,
  - ERC20 transfer to router.
- В результате та же signed authorization остается потенциально исполнимой до `deadline` / `validBefore` / Permit2 deadline.
- Если `allowFailure=true`, router не ревертит по этому inner-call, поэтому authorization обычно расходуется; это уже не replay, но может давать partial-execution риск.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Пользователь подписывает fixed set of calls / fixed token amount / fixed settlement route.
- Relayer/solver не обязан исполнять немедленно и может дождаться более выгодного состояния в пределах deadline:
  - изменилась цена/ликвидность в downstream AMM/marketplace;
  - mint/claim/order target временно revert, затем становится исполнимым;
  - balance/allowance/state пользователя временно делает исполнение невозможным, затем восстанавливается;
  - fixed input amount становится favorable для relayer/solver при изменении внешнего состояния.
- Если первая попытка ревертит, authorization не сгорает и может быть отправлена позже.

ECONOMIC IMPACT / PROFIT PATH:
- Option-like право исполнить signed route в течение окна deadline.
- Возможная прибыль возникает не из permit отдельно, а из связки `permit -> transfer tokens to router -> arbitrary multicall`, если signed calls фиксируют цену/количество/маршрут и оставляют solver возможность выбрать момент.
- Наиболее интересны payloads, где downstream call связан с NFT mint/purchase, fixed-price sale, RFQ/limit-like settlement, bridge payout, bonding curve или claim с меняющимся state.

LIKELIHOOD / FEASIBILITY:
- Высокая как кандидат на stale/delayed execution.
- Нужна выборка реальных tx input data и проверка сроков `deadline/expiration`, `allowFailure`, target contracts и экономического результата.

## 2. Relay Depository

PROJECT: Relay

CHAIN: Abstract mainnet

CONTRACT:
- `0x4cD00E387622C35bDDB9b4c962C136462338BC31`
- Источник: https://abscan.org/address/0x4cD00E387622C35bDDB9b4c962C136462338BC31

FUNCTIONS:
- `execute(CallRequest request, bytes signature)`
- `_executeCalls`
- `deposit` / deposit accounting functions as surrounding value flow

TYPE: meta-tx / signed CallRequest / depository / delayed settlement

REAL USAGE EVIDENCE:
- 236,702 tx на Abscan.
- Verified production Relay contract.

PERMIT / AUTH MECHANISM:
- EIP-712-style signed `CallRequest`.
- `CallRequest` содержит `Call[] calls`, `uint256 nonce`, `uint256 expiration`.
- Signature проверяется через `allocator.isValidSignatureNow(eip712Hash, signature)`.
- Replay guard: `callRequests[structHash] = true`.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Да, кандидат сильный.
- `callRequests[structHash] = true` ставится до `_executeCalls`, но если downstream call с `allowFailure=false` ревертит, полный revert откатывает запись replay guard.
- Та же allocator signature остается reusable до `request.expiration`.
- Если конкретные calls помечены `allowFailure=true`, request может считаться использованным даже при failed inner-call, что снижает replay, но оставляет partial-execution surface.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Solver/relayer получает signed CallRequest и может выбрать момент исполнения до expiration.
- Если target state сначала делает call failing, replay guard не фиксируется.
- Позже, когда state становится favorable, тот же signed request можно исполнить.
- Особенно интересны call payloads, которые выводят средства, обменивают активы, вызывают marketplace/settlement или зависят от external price/liquidity.

ECONOMIC IMPACT / PROFIT PATH:
- Option-like исполнение signed arbitrary calls из depository flow.
- Экономический смысл зависит от того, кто получает output и какие target calls подписаны allocator: stale payout, stale swap route, stale NFT/asset settlement, или call, выгодный solver после изменения цены/ликвидности.

LIKELIHOOD / FEASIBILITY:
- Высокая как replay-on-revert primitive.
- Нужно отдельно подтвердить, что production payloads содержат price-sensitive calls, а expiration не слишком короткий.

## 3. LayerZero LZMultiCall

PROJECT: LayerZero / LZMultiCall

CHAIN: Abstract mainnet

CONTRACT:
- `0xa8752e1ceeab44cd84214ebfcefd9c8cb535fb98`
- Источник: https://abscan.org/address/0xa8752e1ceeab44cd84214ebfcefd9c8cb535fb98

FUNCTIONS:
- `execute(Call[] calls, bytes32 quoteId, uint256 expiration, address signer, bytes signature)`
- `execute(Call[] calls, bytes32 quoteId)`
- `_executeCalls`
- `_handleTransfer`
- `_handleCall`

TYPE: meta-tx / signed multicall / transfer delegate / cross-contract execution

REAL USAGE EVIDENCE:
- 2,897 tx на Abscan.
- Verified contract, active production use.

PERMIT / AUTH MECHANISM:
- EIP-712 digest over calls, `quoteId`, `expiration`, and current `nonces[signer]`.
- Signature checked with `SignatureChecker.isValidSignatureNow`.
- Nonce is incremented before signature check / calls, but Solidity revert rolls it back.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Да.
- `_handleCall` bubbles revert on failed target call.
- If any signed call reverts, full tx reverts and `nonces[signer]++` is rolled back.
- Same signature remains valid until `expiration`, provided nonce did not advance via another successful execution.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- A signed quote/call bundle can be delayed by the relayer until target state becomes favorable.
- If execution fails because of temporary liquidity/state/balance/allowance conditions, the authorization is not consumed.
- Later execution can succeed against changed marketplace/vault/bridge/transfer state.

ECONOMIC IMPACT / PROFIT PATH:
- Depends on signed calls.
- Strongest cases are fixed `quoteId` bundles that contain token transfer delegate plus a downstream settlement or mint/swap action.
- Potential gain is option value during the expiration window.

LIKELIHOOD / FEASIBILITY:
- Medium-high.
- The primitive is clearly replay-on-revert; economic severity depends on observed production call payloads and expiration windows.

## 4. ERC1155 SeaDrop Contract Offerer / signed mint path

PROJECT: SeaDrop / ERC1155 contract offerer on Abstract

CHAIN: Abstract mainnet

CONTRACT:
- `0x00b19a5200a100e5fc4c9800772f4d002f218400`
- Источник: https://abscan.org/address/0x00b19a5200a100e5fc4c9800772f4d002f218400

FUNCTIONS:
- Seaport contract-offerer flow via `generateOrder`
- `_createOrder`
- `_mintSigned`
- `_currentPrice`
- `_validateMint`

TYPE: NFT marketplace / signed mint / launchpad-style drop

REAL USAGE EVIDENCE:
- 3,627 tx на Abscan.
- Verified production NFT mint/offerer contract.

PERMIT / AUTH MECHANISM:
- Signed mint params with ECDSA.
- `_mintSigned` computes digest from minter, fee recipient, mint params and salt.
- `_usedDigests[digest]` prevents replay after successful execution.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Да.
- `_usedDigests[digest] = true` is set before validation/mint effects, but any revert in later checks rolls back the used marker.
- Revert causes can include inactive stage, wallet limits, token supply, payment validation, fee recipient restrictions, or other mint validation.
- The same signed mint authorization can remain reusable until the signed mint params expire.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Signed mint params may encode fixed price or a price curve via `startPrice/endPrice/startTime/endTime`.
- If a signed mint fails before successful digest consumption, it can be retried later.
- For descending price / Dutch-style params, delayed execution may be favorable to the minter/relayer if the signature remains valid and supply is still available.
- For fixed-price params, stale execution remains possible until end time if market conditions change off-chain.

ECONOMIC IMPACT / PROFIT PATH:
- NFT mint option: hold or retry a valid signed mint until price/supply/market conditions are favorable.
- Potential value if secondary market price moves, drop state changes, or dynamic price decreases while the authorization remains usable.

LIKELIHOOD / FEASIBILITY:
- Medium.
- This looks partly intentional for signed mint drops, but the replay-on-revert property is real. Economic severity requires checking actual mint params, signer policy, price schedule and per-wallet limits.

## 5. Relay Approval Proxy V2.1, historical/same-pattern candidate

PROJECT: Relay

CHAIN: Abstract mainnet

CONTRACT:
- `0x58cc3e0aa6cd7bf795832a225179ec2d848ce3e7`
- Источник: https://abscan.org/address/0x58cc3e0aa6cd7bf795832a225179ec2d848ce3e7

FUNCTIONS:
- `permitTransferAndMulticall`
- `permit2TransferAndMulticall`
- `permit3009TransferAndMulticall`

TYPE: meta-tx / permit-like / cross-contract settlement

REAL USAGE EVIDENCE:
- 11,588 tx на Abscan.
- Verified Relay contract.

PERMIT / AUTH MECHANISM:
- Same family as V3: ERC-2612, Permit2 witness transfer, ERC-3009.
- Witness hash includes relayer, refund recipient, NFT recipient and calls.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Да, по той же причине: permit/authorization happens before router multicall, full revert rolls back nonce/authorization consumption.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Same as V3, but contract appears older than V3 and likely less relevant for current production flow.

ECONOMIC IMPACT / PROFIT PATH:
- Same class as V3 if still used for price-sensitive settlement.

LIKELIHOOD / FEASIBILITY:
- Medium. Worth keeping as historical/same-pattern surface, but V3 and Depository are higher priority.

## Что проверять следующим шагом

1. Вытащить последние successful и reverted tx input data для Relay Approval Proxy V3, Relay Depository и LZMultiCall.
2. Декодировать actual `calls` targets и отделить harmless cleanup/bridge calls от price-sensitive marketplace/swap/mint/vault calls.
3. Для каждого payload измерить:
   - deadline / validBefore / expiration window;
   - `allowFailure`;
   - есть ли fixed price / fixed ratio / fixed output recipient;
   - кто контролирует timing: user, relayer, solver, backend allocator;
   - сохраняется ли authorization после revert в локальной simulation.
4. Приоритет: Relay Depository и Relay Approval Proxy V3, потому что там самая большая production usage и наиболее прямой replay-on-revert primitive.
