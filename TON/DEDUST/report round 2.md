Новый кандидат на critical: reusable/forgable proof в Pool → Vault authorization bypass

Кандидат: proof в сообщениях Dedust Swap External / Dedust Payout From Pool может быть недостаточно связан с конкретным pool/vault/action/asset pair, что потенциально даёт unauthorized payout или reserve manipulation.

Почему это сильнее предыдущего:

Реальные traces показывают, что Vault ↔ Pool безопасность опирается не только на sender, а на поле proof.

В NativeVault -> Pool:

OpCode: Dedust Swap External · 0x61ee542d
proof: ...
amount: ...
sender_addr: ...

В Pool -> NativeVault payout path:

OpCode: Dedust Payout From Pool · 0xad4eb6f5
proof: ...
amount: ...
recipient_addr: ...

Если proof:

- не включает exact pool address,
- не включает exact vault address,
- не включает asset_in / asset_out,
- не включает operation domain: swap_external vs payout_from_pool,
- или допускает replay между pool/vault instances,

то возможен direct vault drain:

1. Attacker берёт proof из легитимного trace.
2. Reuses proof в crafted payout_from_pool.
3. Если Vault валидирует proof как “какой-то DeDust pool”, а не exact authorized pool for this asset/action,
   Vault выпускает real TON/jettons.
Minimal confirm/refute

Проверить обработчик 0xad4eb6f5 в Vault:

require(sender == expected_pool_address)
require(proof binds sender/pool_addr)
require(proof binds this_vault_addr)
require(proof binds asset handled by this vault)
require(proof binds operation = payout_from_pool)
require(no replay if proof is reusable)
Статус
Candidate critical: proof replay / weak domain separation in Pool→Vault payout authorization
Confidence: medium
Exploitability: unknown
Why critical: unauthorized payout path is directly visible on-chain
Next check: decompile Vault handler for op 0xad4eb6f5 and Pool handler for 0x61ee542d