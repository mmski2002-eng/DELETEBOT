import gmp_checksum_v1.aleo;
import gmp_lib_v1.aleo;
import asset_manager_helper_v1.aleo;
import credits.aleo;
import connection_v1.aleo;
import rate_limit_v1.aleo;
import token_registry.aleo;

program asset_manager_core_v1.aleo;

mapping gmp_payload:
    key as [u8; 32u32].public;
    value as asset_manager_helper_v1.aleo/TransferMsg.public;

function transfer_native_public:
    input r0 as field.public;
    input r1 as [u8; 32u32].public;
    input r2 as u64.public;
    input r3 as u128.public;
    input r4 as [u8; 32u32].public;
    input r5 as u64.public;
    input r6 as u128.public;
    input r7 as [u8; 32u32].public;
    call asset_manager_helper_v1.aleo/transfer_message_external r0 self.caller r1 r2 r4 r6 r7 into r8 r9 r10 r11 r12;
    call credits.aleo/transfer_public_as_signer connection_v1.aleo r5 into r13;
    call credits.aleo/transfer_public_as_signer asset_manager_core_v1.aleo r8 into r14;
    call connection_v1.aleo/send_message r6 r7 r3 r11 into r15;
    async transfer_native_public r10 r11 r12 r13 r14 r15 into r16;
    output r16 as asset_manager_core_v1.aleo/transfer_native_public.future;

finalize transfer_native_public:
    input r0 as asset_manager_helper_v1.aleo/TransferMsg.public;
    input r1 as [u8; 32u32].public;
    input r2 as asset_manager_helper_v1.aleo/transfer_message_external.future;
    input r3 as credits.aleo/transfer_public_as_signer.future;
    input r4 as credits.aleo/transfer_public_as_signer.future;
    input r5 as connection_v1.aleo/send_message.future;
    await r2;
    await r3;
    await r4;
    await r5;
    set r0 into gmp_payload[r1];

function transfer_token_public:
    input r0 as field.public;
    input r1 as [u8; 32u32].public;
    input r2 as u64.public;
    input r3 as u128.public;
    input r4 as [u8; 32u32].public;
    input r5 as u64.public;
    input r6 as u128.public;
    input r7 as [u8; 32u32].public;
    call asset_manager_helper_v1.aleo/transfer_message_external r0 self.caller r1 r2 r4 r6 r7 into r8 r9 r10 r11 r12;
    call credits.aleo/transfer_public_as_signer connection_v1.aleo r5 into r13;
    call token_registry.aleo/transfer_from_public r0 self.caller asset_manager_core_v1.aleo r9 into r14;
    call connection_v1.aleo/send_message r6 r7 r3 r11 into r15;
    async transfer_token_public r10 r11 r12 r13 r14 r15 into r16;
    output r16 as asset_manager_core_v1.aleo/transfer_token_public.future;

finalize transfer_token_public:
    input r0 as asset_manager_helper_v1.aleo/TransferMsg.public;
    input r1 as [u8; 32u32].public;
    input r2 as asset_manager_helper_v1.aleo/transfer_message_external.future;
    input r3 as credits.aleo/transfer_public_as_signer.future;
    input r4 as token_registry.aleo/transfer_from_public.future;
    input r5 as connection_v1.aleo/send_message.future;
    await r2;
    await r3;
    await r4;
    await r5;
    set r0 into gmp_payload[r1];

function recv_message:
    input r0 as u128.public;
    input r1 as u128.public;
    input r2 as [u8; 32u32].public;
    input r3 as u128.public;
    input r4 as gmp_lib_v1.aleo/Validators.public;
    input r5 as connection_v1.aleo/Signatures.public;
    input r6 as asset_manager_helper_v1.aleo/TransferMsg.public;
    call asset_manager_helper_v1.aleo/recv_message_external r0 r2 r6 into r7 r8 r9 r10 r11 r12;
    call connection_v1.aleo/verify_message r0 r2 r1 r3 r11 r4 r5 into r13;
    call rate_limit_v1.aleo/verify_withdraw r6.token r6.amount into r14;
    call token_registry.aleo/transfer_public r10 r7 r9 into r15;
    call credits.aleo/transfer_public r7 r8 into r16;
    async recv_message r12 r13 r14 r15 r16 into r17;
    output r17 as asset_manager_core_v1.aleo/recv_message.future;

finalize recv_message:
    input r0 as asset_manager_helper_v1.aleo/recv_message_external.future;
    input r1 as connection_v1.aleo/verify_message.future;
    input r2 as rate_limit_v1.aleo/verify_withdraw.future;
    input r3 as token_registry.aleo/transfer_public.future;
    input r4 as credits.aleo/transfer_public.future;
    await r0;
    await r1;
    await r2;
    await r3;
    await r4;

constructor:
    branch.eq edition 0u16 to end;
    get gmp_checksum_v1.aleo/approved_checksums[aleo1xdwspfxwdsv6kxmgftvqesjjmyccrnu0smcttd4x63xqy4xh2qyq0y5yq8] into r0;
    assert.eq checksum r0;
    position end;
