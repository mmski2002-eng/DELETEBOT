import gmp_checksum_v1.aleo;
import gmp_lib_v1.aleo;

program asset_manager_helper_v1.aleo;

struct TransferMsg:
    token as field;
    from as [u8; 32u32];
    to as [u8; 32u32];
    amount as u128;
    data as [u8; 32u32];

mapping owner_amh:
    key as boolean.public;
    value as address.public;

mapping hub_chain_id:
    key as boolean.public;
    value as u128.public;

mapping hub_am_address:
    key as boolean.public;
    value as [u8; 32u32].public;

function initialize:
    input r0 as address.public;
    input r1 as u128.public;
    input r2 as [u8; 32u32].public;
    assert.eq self.caller aleo1yhqmy5wkal76ks837svjzc97hqgjeuy2rhegthtmrxmx5phehu9sr6hxgx;
    async initialize r0 r1 r2 into r3;
    output r3 as asset_manager_helper_v1.aleo/initialize.future;

finalize initialize:
    input r0 as address.public;
    input r1 as u128.public;
    input r2 as [u8; 32u32].public;
    contains owner_amh[true] into r3;
    not r3 into r4;
    assert.eq r4 true;
    set r0 into owner_amh[true];
    set r1 into hub_chain_id[true];
    set r2 into hub_am_address[true];

function transfer_message_external:
    input r0 as field.public;
    input r1 as address.public;
    input r2 as [u8; 32u32].public;
    input r3 as u64.public;
    input r4 as [u8; 32u32].public;
    input r5 as u128.public;
    input r6 as [u8; 32u32].public;
    is.eq r0 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r7;
    ternary r7 r3 0u64 into r8;
    is.neq r0 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r9;
    cast r3 into r10 as u128;
    ternary r9 r10 0u128 into r11;
    serialize.bits.raw r1  (address) into r12 ([boolean; 253u32]);
    call gmp_lib_v1.aleo/bit253_to_256bits r12 into r13;
    call gmp_lib_v1.aleo/bit256_to_bytes32 r13 into r14;
    cast r3 into r15 as u128;
    cast r0 r14 r2 r15 r4 into r16 as TransferMsg;
    hash.keccak256 r16 into r17 as field;
    serialize.bits.raw r17  (field) into r18 ([boolean; 253u32]);
    call gmp_lib_v1.aleo/bit253_to_256bits r18 into r19;
    call gmp_lib_v1.aleo/bit256_to_bytes32 r19 into r20;
    async transfer_message_external r5 r6 into r21;
    output r8 as u64.private;
    output r11 as u128.private;
    output r16 as TransferMsg.private;
    output r20 as [u8; 32u32].private;
    output r21 as asset_manager_helper_v1.aleo/transfer_message_external.future;

finalize transfer_message_external:
    input r0 as u128.public;
    input r1 as [u8; 32u32].public;
    get hub_chain_id[true] into r2;
    get hub_am_address[true] into r3;
    assert.eq r2 r0;
    assert.eq r3 r1;

function recv_message_external:
    input r0 as u128.public;
    input r1 as [u8; 32u32].public;
    input r2 as TransferMsg.public;
    hash.keccak256 r2 into r3 as field;
    serialize.bits.raw r3  (field) into r4 ([boolean; 253u32]);
    call gmp_lib_v1.aleo/bit253_to_256bits r4 into r5;
    call gmp_lib_v1.aleo/bit256_to_bytes32 r5 into r6;
    is.eq r2.token 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r7;
    cast r2.amount into r8 as u64;
    ternary r7 r8 0u64 into r9;
    is.neq r2.token 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r10;
    ternary r10 r2.amount 0u128 into r11;
    is.eq r2.token 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r12;
    ternary r12 2015904348649554929264432577274646412635297364field r2.token into r13;
    call gmp_lib_v1.aleo/bytes32_to_bits256 r2.to into r14;
    call gmp_lib_v1.aleo/bit256_to_253bits r14 into r15;
    deserialize.bits.raw r15  ([boolean; 253u32]) into r16 (address);
    async recv_message_external r0 r1 into r17;
    output r16 as address.private;
    output r9 as u64.private;
    output r11 as u128.private;
    output r13 as field.private;
    output r6 as [u8; 32u32].private;
    output r17 as asset_manager_helper_v1.aleo/recv_message_external.future;

finalize recv_message_external:
    input r0 as u128.public;
    input r1 as [u8; 32u32].public;
    get hub_chain_id[true] into r2;
    get hub_am_address[true] into r3;
    assert.eq r2 r0;
    assert.eq r3 r1;

constructor:
    branch.eq edition 0u16 to end;
    get gmp_checksum_v1.aleo/approved_checksums[aleo1ld60rt3j9nx0lhqfnkvpj2lc3a2mq60jtg07a90kfrnlq7nllq8qlwz4zg] into r0;
    assert.eq checksum r0;
    position end;
