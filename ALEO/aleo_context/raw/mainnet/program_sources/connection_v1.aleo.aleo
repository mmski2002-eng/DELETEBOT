import credits.aleo;
import gmp_checksum_v1.aleo;
import gmp_lib_v1.aleo;

program connection_v1.aleo;

struct Message:
    src_chain_id as u128;
    src_address as [u8; 32u32];
    conn_sn as u128;
    dst_chain_id as u128;
    dst_address as [u8; 32u32];
    payload as [u8; 32u32];

struct Receipts:
    src_chain_id as u128;
    conn_sn as u128;

struct Signatures:
    signature_1 as [u8; 65u32];
    signature_2 as [u8; 65u32];
    signature_3 as [u8; 65u32];
    signature_4 as [u8; 65u32];
    signature_5 as [u8; 65u32];

mapping already_processed:
    key as Receipts.public;
    value as boolean.public;

mapping chain_id:
    key as boolean.public;
    value as u128.public;

mapping owner_conn:
    key as boolean.public;
    value as address.public;

mapping total_validators:
    key as boolean.public;
    value as u8.public;

mapping validators:
    key as boolean.public;
    value as gmp_lib_v1.aleo/Validators.public;

mapping threshold:
    key as boolean.public;
    value as u8.public;

mapping messages:
    key as u128.public;
    value as Message.public;

function initialize:
    input r0 as u128.public;
    input r1 as address.public;
    input r2 as gmp_lib_v1.aleo/Validators.public;
    input r3 as u8.public;
    assert.eq self.caller aleo1yhqmy5wkal76ks837svjzc97hqgjeuy2rhegthtmrxmx5phehu9sr6hxgx;
    call gmp_lib_v1.aleo/get_unique_validator_count r2 into r4 r5;
    gt r3 0u8 into r6;
    lte r3 r4 into r7;
    and r6 r7 into r8;
    assert.eq r8 true;
    async initialize r0 r1 r5 r3 r4 into r9;
    output r9 as connection_v1.aleo/initialize.future;

finalize initialize:
    input r0 as u128.public;
    input r1 as address.public;
    input r2 as gmp_lib_v1.aleo/Validators.public;
    input r3 as u8.public;
    input r4 as u8.public;
    contains owner_conn[true] into r5;
    not r5 into r6;
    assert.eq r6 true;
    set r0 into chain_id[true];
    set r1 into owner_conn[true];
    set r4 into total_validators[true];
    set r2 into validators[true];
    set r3 into threshold[true];

function send_message:
    input r0 as u128.public;
    input r1 as [u8; 32u32].public;
    input r2 as u128.public;
    input r3 as [u8; 32u32].public;
    serialize.bits.raw self.caller  (address) into r4 ([boolean; 253u32]);
    call gmp_lib_v1.aleo/bit253_to_256bits r4 into r5;
    call gmp_lib_v1.aleo/bit256_to_bytes32 r5 into r6;
    async send_message r6 r0 r1 r2 r3 into r7;
    output r7 as connection_v1.aleo/send_message.future;

finalize send_message:
    input r0 as [u8; 32u32].public;
    input r1 as u128.public;
    input r2 as [u8; 32u32].public;
    input r3 as u128.public;
    input r4 as [u8; 32u32].public;
    contains messages[r3] into r5;
    not r5 into r6;
    assert.eq r6 true;
    get chain_id[true] into r7;
    cast r7 r0 r3 r1 r2 r4 into r8 as Message;
    set r8 into messages[r3];

function verify_message:
    input r0 as u128.public;
    input r1 as [u8; 32u32].public;
    input r2 as u128.public;
    input r3 as u128.public;
    input r4 as [u8; 32u32].public;
    input r5 as gmp_lib_v1.aleo/Validators.public;
    input r6 as Signatures.public;
    serialize.bits.raw self.caller  (address) into r7 ([boolean; 253u32]);
    call gmp_lib_v1.aleo/bit253_to_256bits r7 into r8;
    call gmp_lib_v1.aleo/bit256_to_bytes32 r8 into r9;
    call gmp_lib_v1.aleo/u128_to_bytes32 r0 r3 r2 into r10 r11 r12 r13;
    call gmp_lib_v1.aleo/flatten_6x32_to_192 r11 r10 r12 r1 r9 r4 into r14;
    hash.keccak256.native.raw r14 into r15 as [boolean; 256u32];
    deserialize.bits.raw r15  ([boolean; 256u32]) into r16 ([u8; 32u32]);
    call gmp_lib_v1.aleo/get_unique_validator_count r5 into r17 r18;
    async verify_message r0 r2 r3 r18 r6 r16 r17 r13 into r19;
    output r19 as connection_v1.aleo/verify_message.future;

finalize verify_message:
    input r0 as u128.public;
    input r1 as u128.public;
    input r2 as u128.public;
    input r3 as gmp_lib_v1.aleo/Validators.public;
    input r4 as Signatures.public;
    input r5 as [u8; 32u32].public;
    input r6 as u8.public;
    input r7 as gmp_lib_v1.aleo/u128_to_bytes32.future;
    await r7;
    cast r0 r2 into r8 as Receipts;
    get.or_use already_processed[r8] false into r9;
    not r9 into r10;
    assert.eq r10 true;
    get threshold[true] into r11;
    gte r6 r11 into r12;
    assert.eq r12 true;
    get chain_id[true] into r13;
    assert.eq r13 r1;
    get validators[true] into r14;
    cast 3u8 131u8 24u8 83u8 91u8 84u8 16u8 93u8 74u8 122u8 174u8 96u8 192u8 143u8 196u8 95u8 150u8 135u8 24u8 27u8 79u8 223u8 198u8 37u8 189u8 26u8 117u8 63u8 167u8 57u8 127u8 237u8 117u8 into r15 as [u8; 33u32];
    is.neq r3.validator_1 r15 into r16;
    cast 54u8 92u8 100u8 231u8 30u8 26u8 164u8 104u8 205u8 217u8 37u8 20u8 116u8 213u8 183u8 212u8 89u8 121u8 71u8 35u8 200u8 168u8 15u8 6u8 223u8 151u8 173u8 68u8 49u8 44u8 200u8 152u8 20u8 131u8 157u8 191u8 189u8 57u8 131u8 159u8 200u8 14u8 188u8 122u8 176u8 239u8 170u8 102u8 228u8 75u8 71u8 4u8 52u8 138u8 190u8 140u8 66u8 91u8 99u8 198u8 201u8 236u8 221u8 179u8 0u8 into r17 as [u8; 65u32];
    is.neq r4.signature_1 r17 into r18;
    and r16 r18 into r19;
    is.eq r3.validator_1 r14.validator_1 into r20;
    is.eq r3.validator_1 r14.validator_2 into r21;
    or r20 r21 into r22;
    is.eq r3.validator_1 r14.validator_3 into r23;
    or r22 r23 into r24;
    is.eq r3.validator_1 r14.validator_4 into r25;
    or r24 r25 into r26;
    is.eq r3.validator_1 r14.validator_5 into r27;
    or r26 r27 into r28;
    and r19 r28 into r29;
    is.neq r3.validator_2 r15 into r30;
    is.neq r4.signature_2 r17 into r31;
    and r30 r31 into r32;
    is.eq r3.validator_2 r14.validator_1 into r33;
    is.eq r3.validator_2 r14.validator_2 into r34;
    or r33 r34 into r35;
    is.eq r3.validator_2 r14.validator_3 into r36;
    or r35 r36 into r37;
    is.eq r3.validator_2 r14.validator_4 into r38;
    or r37 r38 into r39;
    is.eq r3.validator_2 r14.validator_5 into r40;
    or r39 r40 into r41;
    and r32 r41 into r42;
    is.neq r3.validator_3 r15 into r43;
    is.neq r4.signature_3 r17 into r44;
    and r43 r44 into r45;
    is.eq r3.validator_3 r14.validator_1 into r46;
    is.eq r3.validator_3 r14.validator_2 into r47;
    or r46 r47 into r48;
    is.eq r3.validator_3 r14.validator_3 into r49;
    or r48 r49 into r50;
    is.eq r3.validator_3 r14.validator_4 into r51;
    or r50 r51 into r52;
    is.eq r3.validator_3 r14.validator_5 into r53;
    or r52 r53 into r54;
    and r45 r54 into r55;
    is.neq r3.validator_4 r15 into r56;
    is.neq r4.signature_4 r17 into r57;
    and r56 r57 into r58;
    is.eq r3.validator_4 r14.validator_1 into r59;
    is.eq r3.validator_4 r14.validator_2 into r60;
    or r59 r60 into r61;
    is.eq r3.validator_4 r14.validator_3 into r62;
    or r61 r62 into r63;
    is.eq r3.validator_4 r14.validator_4 into r64;
    or r63 r64 into r65;
    is.eq r3.validator_4 r14.validator_5 into r66;
    or r65 r66 into r67;
    and r58 r67 into r68;
    is.neq r3.validator_5 r15 into r69;
    is.neq r4.signature_5 r17 into r70;
    and r69 r70 into r71;
    is.eq r3.validator_5 r14.validator_1 into r72;
    is.eq r3.validator_5 r14.validator_2 into r73;
    or r72 r73 into r74;
    is.eq r3.validator_5 r14.validator_3 into r75;
    or r74 r75 into r76;
    is.eq r3.validator_5 r14.validator_4 into r77;
    or r76 r77 into r78;
    is.eq r3.validator_5 r14.validator_5 into r79;
    or r78 r79 into r80;
    and r71 r80 into r81;
    ecdsa.verify.digest r4.signature_1 r3.validator_1 r5 into r82;
    cast r82 into r83 as u8;
    ternary r29 r83 0u8 into r84;
    add 0u8 r84 into r85;
    ecdsa.verify.digest r4.signature_2 r3.validator_2 r5 into r86;
    cast r86 into r87 as u8;
    ternary r42 r87 0u8 into r88;
    add r85 r88 into r89;
    ecdsa.verify.digest r4.signature_3 r3.validator_3 r5 into r90;
    cast r90 into r91 as u8;
    ternary r55 r91 0u8 into r92;
    add r89 r92 into r93;
    ecdsa.verify.digest r4.signature_4 r3.validator_4 r5 into r94;
    cast r94 into r95 as u8;
    ternary r68 r95 0u8 into r96;
    add r93 r96 into r97;
    ecdsa.verify.digest r4.signature_5 r3.validator_5 r5 into r98;
    cast r98 into r99 as u8;
    ternary r81 r99 0u8 into r100;
    add r97 r100 into r101;
    gte r101 r11 into r102;
    assert.eq r102 true;
    set true into already_processed[r8];

function update_validators:
    input r0 as gmp_lib_v1.aleo/Validators.public;
    input r1 as u8.public;
    call gmp_lib_v1.aleo/get_unique_validator_count r0 into r2 r3;
    gt r1 0u8 into r4;
    lte r1 r2 into r5;
    and r4 r5 into r6;
    assert.eq r6 true;
    async update_validators self.caller r3 r1 r2 into r7;
    output r7 as connection_v1.aleo/update_validators.future;

finalize update_validators:
    input r0 as address.public;
    input r1 as gmp_lib_v1.aleo/Validators.public;
    input r2 as u8.public;
    input r3 as u8.public;
    get owner_conn[true] into r4;
    assert.eq r4 r0;
    set r3 into total_validators[true];
    set r2 into threshold[true];
    set r1 into validators[true];

function update_threshold:
    input r0 as u8.public;
    gt r0 0u8 into r1;
    assert.eq r1 true;
    async update_threshold self.caller r0 into r2;
    output r2 as connection_v1.aleo/update_threshold.future;

finalize update_threshold:
    input r0 as address.public;
    input r1 as u8.public;
    get owner_conn[true] into r2;
    assert.eq r2 r0;
    get total_validators[true] into r3;
    gte r3 r1 into r4;
    assert.eq r4 true;
    set r1 into threshold[true];

function transfer_ownership:
    input r0 as address.public;
    assert.neq r0 aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc;
    async transfer_ownership self.caller r0 into r1;
    output r1 as connection_v1.aleo/transfer_ownership.future;

finalize transfer_ownership:
    input r0 as address.public;
    input r1 as address.public;
    get owner_conn[true] into r2;
    assert.eq r2 r0;
    set r1 into owner_conn[true];

function withdraw:
    input r0 as u64.private;
    gt r0 0u64 into r1;
    assert.eq r1 true;
    call credits.aleo/transfer_public aleo1yhqmy5wkal76ks837svjzc97hqgjeuy2rhegthtmrxmx5phehu9sr6hxgx r0 into r2;
    async withdraw self.caller r2 into r3;
    output r3 as connection_v1.aleo/withdraw.future;

finalize withdraw:
    input r0 as address.public;
    input r1 as credits.aleo/transfer_public.future;
    get owner_conn[true] into r2;
    assert.eq r2 r0;
    await r1;

constructor:
    branch.eq edition 0u16 to end;
    get gmp_checksum_v1.aleo/approved_checksums[aleo1m5cc30zydxas7tmhx8hulv9g8vh4585czm7kl8gqmcdmyxptyu8qz034ul] into r0;
    assert.eq checksum r0;
    position end;
