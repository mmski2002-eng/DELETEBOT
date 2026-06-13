Title

Missing validator key ownership / proof-of-possession validation in `Staking.registerValidator()` enables validator key squatting and invalid validator activation

Severity

High

Potentially Critical if the Pharos node / consensus layer does not independently validate validator key ownership or PoP before accepting the validator set.

Affected component

- System contract: `Staking` at `0x4100000000000000000000000000000000000000`
- Directly affected function: `registerValidator(...)`
- Related lifecycle functions: `advanceEpoch()`, validator activation flow, `updateValidator(...)`, `exitValidator(...)`

Confirmed related system addresses

- `0x4100000000000000000000000000000000000000` - `Staking` proxy / system contract
- `0x4100000000000000000000000000000000000001` - `Staking` implementation
- `0x3100000000000000000000000000000000000000` - `ChainConfig` proxy
- `0x3100000000000000000000000000000000000001` - `ChainConfig` implementation

Summary

`Staking.registerValidator()` accepts:

- `_publicKey`
- `_publicKeyPop`
- `_blsPublicKey`
- `_blsPublicKeyPop`
- `_endpoint`

but does not verify that the caller actually controls the private keys corresponding to `_publicKey` or `_blsPublicKey`.

The contract derives `poolId` from `_publicKey` as:

`poolId = sha256(publicKeyBytes)`

and the first caller who registers that public key becomes the owner of that validator record.

As a result, if an attacker learns another validator's public key before that validator registers on-chain, the attacker can pre-register it, occupy the derived `poolId`, and block the legitimate owner from registering the same validator identity.

Local testing also confirms that a validator registered with arbitrary PoP placeholder values can progress from `pendingAdd` to `active` through the normal epoch activation flow.

What is confirmed

- On-chain validator registration does not verify PoP or key ownership.
- The first registrant of a given `publicKey` becomes the owner of the corresponding `poolId`.
- A validator registered with arbitrary PoP values can become active in the staking contract.

What is not yet confirmed

- Whether the Pharos node / consensus layer performs a compensating off-chain validation before trusting the validator set.
- Whether BLS keys are used in a way that makes missing PoP escalate into a rogue-key / aggregate-signature vulnerability.

Root cause

The contract stores PoP-related fields but does not validate them before accepting validator registration.

In the visible registration path:

- `_publicKeyPop` is stored
- `_blsPublicKeyPop` is stored
- no cryptographic ownership check is performed
- `poolId` uniqueness is enforced only by the public key hash, not by proof of control

Impact

Confirmed impact:

- validator key squatting
- validator registration denial of service
- unauthorized binding of a validator identity to the attacker's staking owner address
- activation of a validator entry with arbitrary PoP placeholder values

Conditional impact, depending on non-public node / consensus behavior:

- inclusion of an unusable validator in the active validator set
- validator-set integrity degradation
- liveness degradation if the network trusts validators that cannot actually sign
- potentially stronger consensus-level risk if BLS keys are consumed without independent ownership validation

Why this is stronger than the previous `advanceEpoch` finding

The earlier duplicate-`poolId` reward issue was an admin-only input validation bug.

This issue is different:

- `registerValidator()` is an externally callable `payable` function
- the attack surface is public
- the attacker does not need admin privileges
- the vulnerable state transition begins at the validator admission boundary

Public evidence from Pharos tooling and docs

1. The official public `ops` tool targets staking contract `0x4100000000000000000000000000000000000000`.
2. In the public `ops` source, `add-validator` packs `registerValidator(...)` using:
   - `domainPubKey`
   - `stabilizingPubKey`
   - `proofOfPossession = "0x00"`
   - `blsProofOfPossession = "0x00"`
3. The public validator deployment docs describe registration using `domain-pubkey` and `stabilizing-pubkey`, but do not document a required PoP generation or validation step in the registration workflow.

This is strong public evidence that the supported public registration path does not rely on real PoP values at the contract boundary.

References:

- `PharosNetwork/ops`: https://github.com/PharosNetwork/ops
- `validator.go` raw: https://raw.githubusercontent.com/PharosNetwork/ops/main/cmd/validator.go
- Validator deployment docs: https://docs.pharosnetwork.xyz/node-and-validator-guide/validator-node-deployment/using-binary-deployment
- Node debugging docs referencing the same system contract: https://docs.pharosnetwork.xyz/node-and-validator-guide/node-debugging-and-configuration

Code path

Visible behavior in `Staking.sol`:

1. `registerValidator(...)` reads `_publicKey`
2. converts it to bytes
3. computes `poolId = sha256(publicKeyBytes)`
4. rejects only if that `poolId` is already owned by another address
5. stores `_publicKeyPop` and `_blsPublicKeyPop`
6. adds the validator to `pendingAddPoolSets`
7. later `advanceEpoch()` can activate it if the stake threshold is satisfied

This means the contract treats the public key string itself as the validator identity anchor, but does not prove that the registrant controls that identity.

Attack scenario A - validator key squatting

1. A legitimate validator generates its domain public key and stabilizing/BLS public key.
2. The attacker learns the victim public key before on-chain registration.
3. The attacker calls `registerValidator()` with the victim's `_publicKey`.
4. The contract derives the victim's `poolId` from that public key.
5. The attacker becomes `validators[poolId].owner`.
6. When the legitimate validator later tries to register the same public key, the transaction reverts because the pool is already registered to another address.

Result:

- the legitimate validator cannot bind its own validator identity to its intended staking owner
- the attacker squats the validator identity at the staking layer

Attack scenario B - invalid validator activation

1. The attacker registers a validator using arbitrary PoP placeholder values.
2. The contract accepts the registration and enqueues the validator in `pendingAdd`.
3. After epoch advancement, the contract activates the validator if the stake threshold is met.

Result:

- the staking layer can promote a validator entry whose key ownership was never verified on-chain

Local reproduction status

I performed local reproduction against a local clone of `PharosNetwork/contracts` using Foundry.

Added test file:

- `pharos-contracts/test/StakingPoPValidationTest.t.sol`

Executed tests:

- `testRegisterValidatorAcceptsArbitraryPoPValues()`
- `testFirstRegistrantCanSquatPoolId()`
- `testValidatorWithArbitraryPoPCanBecomeActive()`

Observed result:

- all 3 tests passed
- `registerValidator()` accepted arbitrary PoP values
- the first registrant occupied the `poolId`
- the validator became active after `advanceEpoch()`

Local verdict:

The staking-layer vulnerability is confirmed.

Affected components

Confirmed directly affected:

- `Staking` system contract at `0x4100000000000000000000000000000000000000`
- validator registration and activation flow rooted in `registerValidator(...)`

Likely operationally coupled:

- `ChainConfig` at `0x3100000000000000000000000000000000000000`, because staking references it via `cfg()`

Conditionally affected, depending on node / consensus behavior:

- validator-set admission pipeline
- consensus liveness and validator trust model
- SPN-related validator selection surfaces, if they rely on staking-accepted validator identity

Safe PoC plan for triage

PoC 1 - arbitrary PoP is accepted

Goal:

Show that the contract accepts arbitrary `_publicKeyPop` and `_blsPublicKeyPop` and stores them unchanged.

Expected result:

Registration succeeds and stored validator fields match attacker-controlled placeholder values.

PoC 2 - key squatting

Goal:

Show that the first registrant of a public key becomes the owner of the derived `poolId`, and a later legitimate registrant cannot use that same public key.

Expected result:

Second registration reverts with:

`PoolId registered by another address: cannot re-register`

PoC 3 - invalid-PoP validator can become active

Goal:

Show that a validator registered with arbitrary PoP values can move from `pendingAdd` to `active`.

Expected result:

Validator is accepted into `pendingAdd`, then becomes active after `advanceEpoch()`.

Current assessment

This is a valid confirmed staking-layer vulnerability.

The strongest fully supported severity statement today is:

High - missing validator key ownership / PoP validation allows validator key squatting, registration DoS, and staking-layer activation of unverified validator identities.

The issue becomes potentially Critical only if further review of the Pharos node / consensus layer shows that:

- no compensating off-chain validation exists, and
- registered keys are trusted for consensus participation without ownership verification

Recommended fix

At least one of the following must be enforced:

1. Verify validator key ownership at registration time.
2. Reject registrations unless the consensus key signs a domain-separated registration message.
3. If full cryptographic PoP verification is not feasible on-chain, require the node / consensus layer to reject any validator record whose ownership proof is invalid, and document that requirement explicitly.

Recommended robust design:

- require an EVM signature from the staking owner address
- require a signature or PoP from the consensus key over a domain-separated message such as:

`PharosValidatorRegistration(chainId, stakingContract, owner, publicKey, blsPublicKey, nonce)`

- reject activation into the validator set unless that ownership proof is valid

Additional hardening

- Add an invariant test that a caller cannot register another operator's public key unless it proves key ownership.
- Add an invariant test that arbitrary PoP placeholder values cannot enter the active validator set.
- Document whether PoP validation is on-chain, off-chain, or both.
- If off-chain validation is intended, treat missing validation as consensus-critical and fail closed.

Report-ready conclusion

`Staking.registerValidator()` accepts validator identity material and PoP fields but does not verify ownership of the supplied consensus keys. Because `poolId` is derived directly from `_publicKey`, the first caller to register a public key becomes the owner of that validator identity at the staking layer. Local reproduction confirms that arbitrary PoP values are accepted, that the first registrant can squat the derived `poolId`, and that such a validator can become active through the normal epoch flow.

This confirms a real public attack surface for validator key squatting and registration DoS at the staking layer. Whether the issue escalates to consensus-critical severity depends on whether Pharos performs an independent off-chain validation of validator key ownership before accepting the validator set.
