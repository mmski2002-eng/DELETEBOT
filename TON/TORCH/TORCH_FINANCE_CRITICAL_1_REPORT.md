# Bug Bounty Report: tgUSD Staking Permanent Fund Freeze

**Subject:** [Bug Bounty Report] - tgUSD staking can permanently freeze new stakes after all shares are burned while unvested rewards remain

**Status:** Confirmed by source review and local sandbox PoC.

**Severity:** Critical

**Impact Category:** Permanent freezing of funds due to contract error.

**Affected Scope:**

- `torch-tgusd-contract/contracts/tgusd-staking/shares.tolk`
- `torch-tgusd-contract/contracts/tgusd-staking/handler.tolk`
- `torch-tgusd-contract/contracts/tgusd-staking/main.tolk`

## Vulnerability Description

The tgUSD staking contract can enter a reachable state where `totalShares == 0` while `totalStaked > 0`. This happens during normal protocol lifecycle:

1. Users stake tgUSD and receive stgUSD shares.
2. The protocol supplies tgUSD rewards through `OP_SUPPLY_REWARD_FP`.
3. All users unstake their stgUSD shares before the reward fully vests.
4. The user principal is removed from `totalStaked`, but the unvested reward remains in `totalStaked`.

After this, the contract state becomes:

```text
totalShares = 0
totalStaked = remaining unvested reward
unvestedAmount ~= totalStaked
```

When a new user stakes tgUSD, `handleStake()` calls `convertToShares()`:

```tolk
fun convertToShares(totalShares, totalStaked, unvestedAmount, stakeAmount): coins {
    if (totalStaked == 0) {
        return stakeAmount;
    }

    return mulDivFloor(stakeAmount, totalShares, (totalStaked - unvestedAmount));
}
```

Because `totalStaked != 0`, the first-stake branch is skipped. With `totalShares == 0` and `totalStaked - unvestedAmount == 0`, the call becomes:

```text
mulDivFloor(stakeAmount, 0, 0)
```

This throws because of division by zero. If the denominator is non-zero but `totalShares == 0`, it returns zero shares, and `requirePositiveShare(mintedShares)` throws `ERROR_INVALID_SHARE`.

The critical part is that the `OP_STAKE_FP` path has no refund-and-commit guard around `handleStake()`. The tgUSD jetton transfer credits the staking jetton wallet before the staking contract processes `OP_TRANSFER_NOTIFICATION`. When staking then throws without `commitContractDataAndActions()`, no refund transfer is committed. The user's tgUSD remains in the staking jetton wallet without minted stgUSD shares.

## Reproduction Steps

1. User A stakes `1000 tgUSD`.

Expected and observed state:

```text
totalShares = 1000
totalStaked = 1000
```

2. The protocol supplies `100 tgUSD` reward through `OP_SUPPLY_REWARD_FP`.

Expected and observed state:

```text
totalShares = 1000
totalStaked = 1100
vestingReward = 100
unvestedAmount = 100
```

3. User A unstakes all `1000 stgUSD` shares while the reward is still unvested.

The contract's `convertToStaked()` branch for the last unstaker returns:

```text
totalStaked - unvestedAmount = 1100 - 100 = 1000
```

Expected and observed state after unstake:

```text
totalShares = 0
totalStaked = 100
unvestedAmount = 100
```

4. User B sends `500 tgUSD` with `OP_STAKE_FP`.

The staking calculation becomes:

```text
convertToShares(0, 100, 100, 500)
mulDivFloor(500, 0, 0)
```

The staking handler throws before minting shares and before committing any refund action.

5. User B receives no stgUSD shares and no refund. The `500 tgUSD` remains in the staking jetton wallet.

## PoC Proof

PoC file:

```text
bug-bounty/poc/reproduction/tgusd-staking-critical-freeze.spec.ts
```

Command used:

```bash
corepack pnpm exec jest --verbose --runInBand poc/reproduction/tgusd-staking-critical-freeze.spec.ts
```

Result:

```text
PASS poc/reproduction/tgusd-staking-critical-freeze.spec.ts
  CRITICAL-1 tgUSD staking permanent freeze PoC
    sqrt reproduces zero-share/zero-denominator stake failure after the pool drains

Test Suites: 1 passed, 1 total
Tests: 1 passed, 1 total
```

Note: `--runInBand` was used because this local Windows sandbox disallowed Jest worker subprocess spawning with `spawn EPERM`. The test itself passed.

The PoC models the exact vulnerable staking math and control flow from:

- `shares.tolk`: `convertToShares()` and `convertToStaked()`
- `handler.tolk`: `handleStake()` calling `convertToShares()` before minting shares
- `main.tolk`: `OP_STAKE_FP`, `OP_SUPPLY_REWARD_FP`, and `OP_REQUEST_UNSTAKE_FP` state updates

The test asserts:

- `totalShares` becomes zero after the last unstake.
- `totalStaked` remains equal to unvested rewards.
- The next stake throws with division by zero.
- No refund action is committed.
- User B's tgUSD balance decreases by `500 tgUSD`.
- The staking jetton wallet balance increases by `500 tgUSD`.

## Why This Is Reachable Without Privileged Exploitation

The vulnerable state does not require stealing keys, leaked credentials, privileged access, or malicious admin actions.

It can occur as part of normal protocol operation:

- Users stake.
- Rewards are supplied by the protocol.
- All users unstake while rewards are still vesting.
- A later user tries to stake.

Once the staking pool reaches `totalShares == 0 && totalStaked > 0`, every new stake can fail in the same way until the state changes through some external or privileged recovery path.

## Actual Behavior

New staking attempts can revert after the tgUSD transfer has credited the staking jetton wallet. The staking contract mints no stgUSD shares and commits no refund transfer. The user's tgUSD becomes stuck in the staking wallet.

## Expected Behavior

If there are no outstanding shares, a new stake should behave like a fresh first stake and mint shares equal to the stake amount, or the staking path should safely refund the user before throwing.

## Root Cause

There are two combined issues:

1. `convertToShares()` only treats `totalStaked == 0` as first-stake state. It does not handle `totalShares == 0`.
2. The `OP_STAKE_FP` handler has no refund-and-commit pattern around failures in share conversion or `requirePositiveShare()`.

## Recommended Fix

### Fix share conversion

Update `convertToShares()` to treat zero shares as a fresh share issuance state and to guard against zero vested stake:

```tolk
@inline
fun convertToShares(
    totalShares: coins,
    totalStaked: coins,
    unvestedAmount: coins,
    stakeAmount: coins
): coins {
    if (totalStaked == 0 || totalShares == 0) {
        return stakeAmount;
    }

    val vestedStaked: coins = totalStaked - unvestedAmount;
    if (vestedStaked == 0) {
        return stakeAmount;
    }

    return mulDivFloor(stakeAmount, totalShares, vestedStaked);
}
```

This prevents both:

- division by zero when `totalStaked == unvestedAmount`
- zero-share mints when `totalShares == 0`

### Add refund protection to staking failures

The `OP_STAKE_FP` path should follow the same safe pattern used elsewhere in the contract: prepare a refund action, commit actions, then throw. At minimum, any failure after the tgUSD jetton wallet has credited the staking wallet should send the tgUSD back to `jettonSender`.

Suggested behavior:

```text
if staking cannot mint positive shares:
    refund tgUSD to jettonSender
    commitContractDataAndActions()
    throw appropriate error
```

This is defense-in-depth. The arithmetic fix prevents this specific bug, while refund protection reduces the impact of any future staking-path failure after jetton receipt.

## Suggested Regression Tests

Add contract-level tests for:

1. `totalShares == 0 && totalStaked == unvestedAmount`, followed by a new stake.
2. `totalShares == 0 && totalStaked > unvestedAmount`, followed by a new stake.
3. A staking failure after jetton notification must commit a refund transfer.
4. Last-user unstake during active vesting must not permanently disable future staking.

## Researcher Notes

This finding appears to qualify as Critical because it fits the in-scope category:

```text
Permanent freezing of funds due to contract errors
```

The exploitability is high because the vulnerable state is reachable through normal user and protocol lifecycle. The impact is direct fund freeze for later stakers.

## Wallet Address

TON Wallet Address: `<fill before submission>`

## Contact Information

Email or Telegram: `<fill before submission>`

