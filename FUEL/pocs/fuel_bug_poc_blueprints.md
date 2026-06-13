# Fuel bug POC blueprints

These are reproducible POC blueprints to convert into Rust/Fuels or TS tests.

## POC-Bridge-001: L1->L2 DepositWithData Reentrancy

Contracts:

- `fuel-bridge/packages/fungible-token/bridge-fungible-token/implementation`
- malicious receiver implementing `MessageReceiver.process_message`

Setup:

1. Deploy bridge proxy + implementation in local Fuel test provider.
2. Create one L1 deposit message with `DepositType::ContractWithData`.
3. Set `to = malicious_receiver_contract_id`.
4. Receiver `process_message(msg_idx)` calls `bridge.process_message(msg_idx)` again before returning.

Expected:

- Nested call reverts due to `reentrancy_guard`.
- `tokens_minted[asset_id]` increases exactly once.
- Receiver balance equals deposit amount once.
- No refund is registered.

Bug signal:

- `tokens_minted` increases twice.
- Receiver balance doubles.
- Refund exists despite successful mint.

## POC-Bridge-002: DepositWithData Revert/Sticky Funds

Contracts:

- Fuel L2 bridge implementation
- receiver that always reverts in `process_message`

Steps:

1. Relay deposit-to-contract-with-data to reverting receiver.
2. Record tx status, `tokens_minted`, bridge balance, receiver balance, refund amount.
3. Try `claim_refund(from, token_address, token_id)`.

Expected:

- Either full transaction reverts with no mint, or a defined refund path exists.

Bug signal:

- `tokens_minted` increased but receiver has no funds.
- No refund available.
- Funds remain inside bridge contract with no withdrawal path.

## POC-Bridge-003: L2 Withdraw Double Finalization

Contracts:

- Fuel L2 bridge `withdraw`
- L1 `FuelERC20GatewayV4.finalizeWithdrawal`

Steps:

1. Mint/bridge asset to user on Fuel.
2. User calls `withdraw(to)` on L2.
3. Generate/obtain message proof.
4. Call L1 `finalizeWithdrawal(to, token, amount, tokenId)`.
5. Call `finalizeWithdrawal` again with same proof/message.

Expected:

- Second finalize rejected by portal/proof/message consumed state.
- L1 escrow decreases once.

Bug signal:

- Same proof unlocks twice.

## POC-Mira-001: Donation Before First Mint

Contracts:

- Mira AMM
- mock SRC20/native token contract

Steps:

1. Deploy AMM and two mock assets.
2. Create pool.
3. Transfer/donate `D0/D1` directly to AMM without calling `mint`.
4. First LP calls `mint(pool_id, lp)`.
5. Burn LP and compare recovered assets vs intended deposit.

Expected:

- Donation cannot be captured unfairly by first LP, or behavior is documented and bounded.

Bug signal:

- First LP extracts donated assets or initializes distorted reserves/LP supply.

## POC-Mira-002: Flash Swap Wrong Repayment

Contracts:

- Mira AMM
- malicious `IBaseCallee`

Steps:

1. Seed pool with token0/token1.
2. Call `swap(pool, token0_out > 0, token1_out = 0, to = malicious_callee, data = Some(...))`.
3. In callee hook, repay wrong asset, too little asset, then enough asset in separate variants.
4. Check tx status, reserves, balances, LP invariant.

Expected:

- Wrong/insufficient repayment reverts atomically.
- Valid repayment succeeds with invariant preserved.

Bug signal:

- Output retained without valid input.
- Reserves diverge from balances.

## POC-Swaylend-001: Duplicate Absorb

Contracts:

- Swaylend Market
- Pyth/Stork mock

Steps:

1. Supply base and collateral.
2. Borrower creates a position.
3. Oracle price moves borrower below liquidation threshold.
4. Liquidator calls `absorb([borrower, borrower], oracle_inputs)`.
5. Read `user_collateral`, `totals_collateral`, `market_basic`, `reserves`.

Expected:

- Duplicate is rejected or second pass is a no-op without underflow.

Bug signal:

- Totals underflow, liquidation event double-counts, or reserves inconsistent.

## POC-Swaylend-002: Stale Oracle Buy Collateral

Contracts:

- Swaylend Market
- oracle mock

Steps:

1. Make borrower liquidatable at price P1.
2. Absorb collateral.
3. Move oracle to P2 but do not call `update_price_feeds`.
4. Call `buy_collateral(asset, min_amount, recipient)`.
5. Repeat with update + buy in same multicall.

Expected:

- Contract cannot sell using stale price if freshness is required.
- Multicall path uses fresh price.

Bug signal:

- Buyer obtains collateral at stale favorable price.

## POC-Fluid-001: Stale Hint Reinsert

Contracts:

- Fluid BorrowOperations
- Fluid SortedTroves
- TroveManager/Oracle

Steps:

1. Open troves A, B, C.
2. Compute hints for A adjustment.
3. Before A submits, B changes collateral/debt and reorders list.
4. A calls `adjust_trove` using stale hints.
5. Verify sorted list invariant: descending NICR, correct head/tail, size unchanged.

Expected:

- Contract finds valid insertion or reverts safely.

Bug signal:

- Linked list corruption, wrong ordering, lost node, duplicate node.

## POC-Fluid-002: StabilityPool Deposit-Before-Liquidation

Contracts:

- Fluid StabilityPool
- TroveManager
- CommunityIssuance

Steps:

1. Depositor A has long-standing deposit.
2. Depositor B deposits immediately before liquidation/offset.
3. Liquidate trove and call `offset`.
4. B withdraws immediately.
5. Compare B asset/FPT gains against stake and time assumptions.

Expected:

- B receives only mathematically proportional gains.

Bug signal:

- B captures disproportionate liquidation gains or FPT issuance.

## POC-V12-001: Cancel-Fill Race

Contracts:

- V12 orderbook when source/address is available
- off-chain matcher/indexer mock

Steps:

1. User places order.
2. Matcher reads order from indexer snapshot.
3. User cancels order.
4. Matcher submits fill using stale snapshot.

Expected:

- Fill fails after cancel.

Bug signal:

- Cancelled order can be filled or assets move partially.
