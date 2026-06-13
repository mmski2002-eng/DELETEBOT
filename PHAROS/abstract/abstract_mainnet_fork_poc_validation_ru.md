# Abstract mainnet: fork PoC validation report для stale / replay / failed authorization

Дата: 2026-05-12  
Scope: Abstract mainnet, production-used contracts only.  
Статус: source-level primitive подтвержден для нескольких production contracts; executable fork PoC на текущей Windows/WSL машине не завершен из-за tooling/network blockers. Готовый harness добавлен в workspace.

## Что было реально проверено локально

### 1. Обычный Hardhat fork

Команда:

```bash
npm run check:fork
```

Результат: **невалиден для Abstract PoC**.

Причина:
- Abstract mainnet возвращает zkSync/Abstract bytecode format, например `eth_getCode(Permit2)` начинается с `0x0003...`.
- Обычный Hardhat EVM fork не исполняет этот bytecode корректно.
- Транзакции к таким контрактам могут выглядеть успешными или как no-op, а `eth_call` может видеть account without code.
- Поэтому обычный Hardhat fork нельзя использовать как доказательство для Abstract.

### 2. anvil-zksync fork

Подготовлено:
- скачан `anvil-zksync v0.6.11` Linux binary;
- добавлен harness: `scripts/check-zksync-fork.mjs`;
- команда запуска:

```bash
npm run check:zksync-fork
```

Результат на текущей машине: **не дошел до RPC-ready**.

Причины:
- официальный `@matterlabs/hardhat-zksync-node` plugin на Windows отвечает `Unsupported platform: windows`;
- WSL Ubuntu есть, но в WSL не работает outbound DNS/network до `api.mainnet.abs.xyz`;
- Windows-to-WSL local proxy также недоступен из WSL в этой конфигурации.

Вывод: executable fork PoC нужно запускать в Linux/WSL окружении с working DNS/network или на удаленной Linux VM. Harness уже готов и должен быть переносим.

## Harness, который добавлен в workspace

Файлы:
- `scripts/check-zksync-fork.mjs`
- `scripts/check-fork.mjs`
- `hardhat.zksync.config.cjs`
- `package.json`

Основной harness: `scripts/check-zksync-fork.mjs`.

Что он делает на корректном `anvil-zksync fork`:
1. Поднимает fork Abstract.
2. Использует реальные production contracts:
   - WETH: `0x3439153EB7AF838Ad19d56E1571FBD09333C2809`
   - Permit2: `0x0000000000225e31d15943971f47ad3022f714fa`
   - Universal Router: `0xE1b076ea612Db28a0d768660e4D81346c02ED75e`
3. Подписывает Permit2 `PermitSingle`.
4. Собирает Universal Router calldata:
   - `PERMIT2_PERMIT` (`0x0a`)
   - `PERMIT2_TRANSFER_FROM` (`0x02`)
5. Первый replay exact calldata должен fail из-за отсутствия WETH balance.
6. Проверяется, что Permit2 nonce не изменился.
7. Восстанавливается state: owner получает WETH через `deposit`.
8. Replay exact same calldata.
9. Проверяется:
   - nonce consumed только после успешного replay;
   - recipient получил WETH;
   - exact calldata replayed.

Это безопасный local-fork proof для permit replay-on-failure primitive. Он не использует чужие подписи и не исполняет live mainnet tx.

## Candidate 1: Seaport fixed-price NFT + Universal Router / Permit2

PROJECT: Seaport / Universal Router NFT flow

CHAIN: Abstract mainnet

CONTRACT:
- Seaport: `0xDF3969A315e3fC15B89A2752D0915cc76A5bd82D`
- Universal Router: `0xE1b076ea612Db28a0d768660e4D81346c02ED75e`
- Permit2: `0x0000000000225e31d15943971f47ad3022f714fa`

FUNCTION:
- Seaport `fulfillBasicOrder`
- Seaport `fulfillOrder`
- Seaport `fulfillAdvancedOrder`
- Universal Router `execute(bytes commands, bytes[] inputs, uint256 deadline)`
- Universal Router commands: `PERMIT2_PERMIT`, `PERMIT2_TRANSFER_FROM`, `SEAPORT`

TYPE: NFT / fixed-price trade / meta-router

REAL USAGE EVIDENCE:
- Seaport: 633,574 tx on Abscan.
- Universal Router: 707,224 tx on Abscan.
- Permit2: 13,798 tx on Abscan.
- Contracts are official Abstract mainnet deployments in Abstract docs.

PERMIT / AUTH MECHANISM:
- Seaport: off-chain signed order.
- Universal Router: optional Permit2 authorization bundled with marketplace execution.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Yes, source-level confirmed.
- Seaport updates order status before transfers, but if later transfer/payment fails, full transaction reverts and order status rolls back.
- Permit2 nonce/allowance update inside Universal Router sequence rolls back if router execution reverts.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Seller signs fixed-price NFT sale.
- Buyer/relayer attempts execution with intentionally bad state: insufficient payment, missing token balance, missing Permit2 allowance, or forced downstream command failure.
- Order/signature remains reusable.
- Later, if market/floor moves up and order is still within `endTime`, exact order calldata can be replayed to buy at stale fixed price.

ECONOMIC IMPACT / PROFIT PATH:
- Buy NFT at historical fixed price after market moves.
- Profit is spread between stale sale price and current floor/resale value.
- This is the strongest MoonBeans-like candidate on Abstract.

LIKELIHOOD / FEASIBILITY:
- High source-level confidence.
- Fork execution needs real signed listing payload or locally created test listing on `anvil-zksync`.

POC STEPS:
1. Fork mainnet with `anvil-zksync fork --fork-url abstract`.
2. Obtain or recreate a signed Seaport fixed-price order.
3. Induce fail: submit order with insufficient buyer funds or intentionally missing approval.
4. Verify reusable auth: query Seaport order status; it must remain unfilled.
5. Restore state: fund buyer / set approval / keep order within `endTime`.
6. Replay exact same order calldata.
7. Verify stale NFT sale: NFT ownership changes, consideration paid at old fixed price, order status consumed only after successful replay.

## Candidate 2: Universal Router + Permit2 standalone replay primitive

PROJECT: Uniswap Universal Router / Permit2

CHAIN: Abstract mainnet

CONTRACT:
- Universal Router: `0xE1b076ea612Db28a0d768660e4D81346c02ED75e`
- Permit2: `0x0000000000225e31d15943971f47ad3022f714fa`
- WETH: `0x3439153EB7AF838Ad19d56E1571FBD09333C2809`

FUNCTION:
- Universal Router `execute`
- Permit2 `permit`
- Permit2 transfer via router command

TYPE: meta-tx / permit-like

REAL USAGE EVIDENCE:
- Universal Router: 707,224 tx.
- Permit2: 13,798 tx.

PERMIT / AUTH MECHANISM:
- EIP-712 Permit2 `PermitSingle` or batch permit.
- Router command consumes Permit2 permit and then performs downstream actions.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Yes, source-level confirmed.
- If a later required router command fails, transaction reverts and Permit2 nonce consumption rolls back.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Permit funds a later fixed-price NFT purchase, launchpad mint, vault action, or claim.
- First execution fails due to balance/allowance/state.
- Same router calldata remains usable until Permit2 deadline.

ECONOMIC IMPACT / PROFIT PATH:
- Standalone Permit2 transfer has no profit by itself.
- Economic impact becomes material when bundled with Seaport/NFT/launchpad/vault target.

LIKELIHOOD / FEASIBILITY:
- High for replay-on-failure primitive.
- Medium for economic stale execution unless bundled with fixed-price target.

POC STEPS:
1. Fork mainnet with `anvil-zksync`.
2. Sign Permit2 authorization for WETH or relevant ERC20.
3. Build router calldata with `PERMIT2_PERMIT` plus required downstream command.
4. Induce fail by leaving signer token balance at zero or making target command fail.
5. Verify Permit2 nonce unchanged.
6. Restore state by funding signer or making target succeed.
7. Replay exact same calldata and verify nonce consumed plus downstream state change.

## Candidate 3: Relay Depository

PROJECT: Relay

CHAIN: Abstract mainnet

CONTRACT:
- `0x4cD00E387622C35bDDB9b4c962C136462338BC31`

FUNCTION:
- `execute(CallRequest request, bytes signature)`
- `_executeCalls`
- `callRequests(bytes32)`

TYPE: meta-tx / relayer / signed authorization

REAL USAGE EVIDENCE:
- 236,702 tx on Abscan.
- Verified production Relay contract.

PERMIT / AUTH MECHANISM:
- EIP-712-style signed `CallRequest`.
- Signature checked via allocator `isValidSignatureNow`.
- Replay guard: `callRequests[structHash]`.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Yes, source-level confirmed.
- `callRequests[structHash] = true` occurs before calls.
- If later required call reverts, full transaction reverts and replay guard rolls back.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Relayer holds signed request.
- Initial execution fails due to target state/balance/liquidity.
- Same request can be replayed before expiration.
- Economic value depends on decoded target calls.

ECONOMIC IMPACT / PROFIT PATH:
- Potential stale settlement, stale payout, fixed-value route, or delayed claim.
- Strong if calls route output to relayer/solver or settle against fixed consideration.

LIKELIHOOD / FEASIBILITY:
- High primitive.
- Economic proof requires real signed request payload from production transactions or controlled allocator signature, which was not available locally.

POC STEPS:
1. Fork mainnet with `anvil-zksync`.
2. Get signed `CallRequest` from production-like flow or controlled test allocator.
3. Induce fail with a target call using `allowFailure=false`.
4. Verify `callRequests[structHash] == false` after failed tx.
5. Restore target state.
6. Replay exact same `execute(request, signature)`.
7. Verify request consumed and target state/value transfer occurred.

## Candidate 4: Relay Approval Proxy V3 + Router V3

PROJECT: Relay

CHAIN: Abstract mainnet

CONTRACT:
- Approval Proxy V3: `0xccc88a9d1b4ed6b0eaba998850414b24f1c315be`
- Router V3: `0xb92fe925DC43a0ECdE6c8b1a2709c170Ec4fFf4f`

FUNCTION:
- `permitTransferAndMulticall`
- `permit2TransferAndMulticall`
- `permit3009TransferAndMulticall`
- Router `multicall`

TYPE: meta-tx / permit-like / relayer flow

REAL USAGE EVIDENCE:
- Approval Proxy V3: 41,262 tx.
- Router V3: 142,091 tx.

PERMIT / AUTH MECHANISM:
- ERC-2612 permit.
- Permit2 witness transfer.
- ERC-3009 authorization.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Yes, source-level confirmed.
- Permit/authorization is consumed before router multicall.
- Required downstream revert rolls back the entire transaction and restores authorization validity.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- User signs fixed amount and call bundle.
- Solver/relayer delays or retries after failed execution.
- Later state makes fixed execution favorable: NFT sale, mint, vault/bonding curve, reward claim, fixed settlement.

ECONOMIC IMPACT / PROFIT PATH:
- Option-like execution window over signed user funds and fixed call bundle.
- Profit depends on target calls, not on permit alone.

LIKELIHOOD / FEASIBILITY:
- High primitive.
- Medium economic proof until real target payload decoded.

POC STEPS:
1. Fork mainnet with `anvil-zksync`.
2. Sign Permit2 witness or ERC-2612/3009 authorization.
3. Build proxy calldata with a required router call that fails.
4. Verify token/Permit2 nonce unchanged after failure.
5. Restore state or target condition.
6. Replay exact same calldata.
7. Verify authorization consumed and downstream state/value changes.

## Candidate 5: SeaDrop ERC1155 signed mint

PROJECT: SeaDrop / ERC1155 Contract Offerer

CHAIN: Abstract mainnet

CONTRACT:
- `0x00b19a5200a100e5fc4c9800772f4d002f218400`

FUNCTION:
- `generateOrder`
- `_createOrder`
- `_mintSigned`
- `_validateMint`
- `_currentPrice`

TYPE: NFT / launchpad / signed mint

REAL USAGE EVIDENCE:
- 3,627 tx on Abscan.
- Verified production mint/offerer contract.

PERMIT / AUTH MECHANISM:
- ECDSA signed mint params.
- Replay guard: `_usedDigests[digest]`.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Yes, source-level confirmed.
- `_usedDigests[digest] = true` happens before later validation, but any revert rolls it back.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- Signed mint remains valid after failed execution.
- Replay later when Dutch price decreases, supply opens, or secondary market becomes favorable.

ECONOMIC IMPACT / PROFIT PATH:
- Delayed mint option.
- Profit from minting at later favorable price/state with stale signed authorization.

LIKELIHOOD / FEASIBILITY:
- Medium.
- Could be intended by design, but it matches replay-on-failure mechanics.

POC STEPS:
1. Fork mainnet with `anvil-zksync`.
2. Obtain signed mint params or recreate with controlled signer in test deployment.
3. Induce fail: invalid payment, inactive stage, wallet limit, or supply condition.
4. Verify `_usedDigests[digest] == false`.
5. Restore state / move time into favorable price window.
6. Replay exact same mint calldata.
7. Verify digest consumed and NFT minted.

## Candidate 6: Reward claim watchlist - Gauge with ERC2771Context

PROJECT: Aborean/Veldrome-style Gauge

CHAIN: Abstract mainnet

CONTRACT:
- Gauge: `0xa171bb8b0805ddccc8721ccb1e13f6dd09633cfc`

FUNCTION:
- `getReward(address account)`
- ERC2771 `_msgSender`

TYPE: reward / staking / gasless watchlist

REAL USAGE EVIDENCE:
- 38,122 tx on Abscan.
- Abscan showed non-trivial contract balance at check time.

PERMIT / AUTH MECHANISM:
- Not in Gauge itself.
- Authorization is delegated to trusted ERC2771 forwarder configured in constructor.

CAN FAILED EXECUTION LEAVE REUSABLE AUTHORIZATION:
- Unconfirmed.
- It depends on forwarder nonce semantics.
- Gauge reward state itself reverts on failed transfer, so claim state is atomic.

POTENTIAL STALE-FAVORABLE EXECUTION PATH:
- If forwarder nonce rolls back on target revert, same gasless claim could be replayed later.
- Direct relayer profit is weak because reward transfers to `_account`, unless claim is part of a broader multicall/forwarder flow.

ECONOMIC IMPACT / PROFIT PATH:
- Low-medium.
- Needs forwarder identification and payload decode.

LIKELIHOOD / FEASIBILITY:
- Low-medium.
- Watchlist only; not primary PoC target.

POC STEPS:
1. Fork mainnet with `anvil-zksync`.
2. Resolve trusted forwarder from deployment args/factory tx.
3. Sign forward request for `getReward`.
4. Induce fail in token transfer or target call.
5. Verify forwarder nonce unchanged.
6. Let rewards accrue or restore transfer condition.
7. Replay exact forward request and verify reward claim.

## Recommended next run environment

Use Linux VM or WSL with working DNS/network:

```bash
curl -L -o anvil-zksync.tar.gz \
  https://github.com/matter-labs/anvil-zksync/releases/download/v0.6.11/anvil-zksync-v0.6.11-x86_64-unknown-linux-gnu.tar.gz
tar -xzf anvil-zksync.tar.gz
chmod +x anvil-zksync
./anvil-zksync --host 0.0.0.0 --port 8011 fork --fork-url abstract
```

Then in this workspace:

```bash
npm install
npm run check:zksync-fork
```

Expected success criteria for the included Permit2/Universal Router harness:
- `nonceAfterFail == nonceBefore`
- `recipientWethAfterFail == 0`
- `replayStatus == 1`
- `nonceAfterReplay > nonceBefore`
- `recipientWethAfterReplay == amount`
- `exactCalldataReplayed == true`

## Bottom line

I could not honestly mark the executable fork PoC as completed on this machine because the correct Abstract fork backend could not reach Abstract RPC from WSL. The stale/replay primitive is nevertheless source-level confirmed for Seaport, Universal Router/Permit2, Relay Depository, Relay Approval Proxy V3, LZMultiCall, and SeaDrop. The highest-value economic candidate remains **Seaport fixed-price NFT sale**, followed by **Relay Depository** and **Relay Approval Proxy V3** where real decoded payloads can reveal stale reward/settlement/vault/NFT paths.

